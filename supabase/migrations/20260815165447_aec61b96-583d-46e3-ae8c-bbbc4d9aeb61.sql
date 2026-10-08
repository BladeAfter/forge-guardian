-- ============ 1. Per-instance yield snapshot columns ============
ALTER TABLE public.nft_heroes ADD COLUMN IF NOT EXISTS yield_locked_at timestamptz;
ALTER TABLE public.nft_pets ADD COLUMN IF NOT EXISTS daily_yield_ton numeric;
ALTER TABLE public.nft_pets ADD COLUMN IF NOT EXISTS yield_locked_at timestamptz;
ALTER TABLE public.nft_yield_positions ADD COLUMN IF NOT EXISTS yield_locked_at timestamptz;

-- backfill pet instance yield from its live position, else current tier config
UPDATE public.nft_pets n
   SET daily_yield_ton = p.daily_yield_ton
  FROM public.nft_yield_positions p
 WHERE p.nft_pet_id = n.id AND n.daily_yield_ton IS NULL;

UPDATE public.nft_pets n
   SET daily_yield_ton = CASE WHEN COALESCE(n.tier_ton, 20) >= 30 THEN s.tier30_daily_ton ELSE s.tier20_daily_ton END
  FROM public.nft_pool_settings s
 WHERE n.daily_yield_ton IS NULL AND n.status <> 'BURNED';

UPDATE public.nft_pets SET yield_locked_at = COALESCE(yield_locked_at, assigned_at, created_at)
 WHERE owner_user_id IS NOT NULL;
UPDATE public.nft_heroes SET yield_locked_at = COALESCE(yield_locked_at, assigned_at, created_at)
 WHERE owner_user_id IS NOT NULL;
UPDATE public.nft_yield_positions SET yield_locked_at = COALESCE(yield_locked_at, created_at);

-- ============ 2. Immutability guards ============
CREATE OR REPLACE FUNCTION public.nft_yield_override_allowed()
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT COALESCE(current_setting('mythreon.allow_yield_override', true), '') = 'on';
$$;

CREATE OR REPLACE FUNCTION public.nft_hero_yield_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.owner_user_id IS NOT NULL AND NEW.yield_locked_at IS NULL THEN
    NEW.yield_locked_at := now();
  END IF;
  IF OLD.yield_locked_at IS NOT NULL
     AND NEW.mining_daily_ton IS DISTINCT FROM OLD.mining_daily_ton
     AND NOT public.nft_yield_override_allowed() THEN
    NEW.mining_daily_ton := OLD.mining_daily_ton;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nft_hero_yield_guard ON public.nft_heroes;
CREATE TRIGGER trg_nft_hero_yield_guard BEFORE UPDATE ON public.nft_heroes
FOR EACH ROW EXECUTE FUNCTION public.nft_hero_yield_guard();

CREATE OR REPLACE FUNCTION public.nft_pet_yield_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.owner_user_id IS NOT NULL AND NEW.yield_locked_at IS NULL THEN
    NEW.yield_locked_at := now();
  END IF;
  IF OLD.yield_locked_at IS NOT NULL
     AND NEW.daily_yield_ton IS DISTINCT FROM OLD.daily_yield_ton
     AND NOT public.nft_yield_override_allowed() THEN
    NEW.daily_yield_ton := OLD.daily_yield_ton;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nft_pet_yield_guard ON public.nft_pets;
CREATE TRIGGER trg_nft_pet_yield_guard BEFORE UPDATE ON public.nft_pets
FOR EACH ROW EXECUTE FUNCTION public.nft_pet_yield_guard();

CREATE OR REPLACE FUNCTION public.nft_position_yield_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.yield_locked_at IS NULL THEN NEW.yield_locked_at := now(); END IF;
  IF NEW.daily_yield_ton IS DISTINCT FROM OLD.daily_yield_ton
     AND NOT public.nft_yield_override_allowed() THEN
    NEW.daily_yield_ton := OLD.daily_yield_ton;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nft_position_yield_guard ON public.nft_yield_positions;
CREATE TRIGGER trg_nft_position_yield_guard BEFORE UPDATE ON public.nft_yield_positions
FOR EACH ROW EXECUTE FUNCTION public.nft_position_yield_guard();

-- ============ 3. Admin review list ============
CREATE TABLE IF NOT EXISTS public.nft_yield_review (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL,
  nft_id uuid,
  nft_serial integer,
  owner_user_id uuid,
  instance_yield numeric,
  template_yield numeric,
  suggested_yield numeric,
  status text NOT NULL DEFAULT 'PENDING',
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.nft_yield_review TO service_role;
ALTER TABLE public.nft_yield_review ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service role manages nft yield review" ON public.nft_yield_review
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============ 4. Snapshot on mint for pets, template only for shop ============
CREATE OR REPLACE FUNCTION public.nft_pool_sync_positions()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare s public.nft_pool_settings; created integer := 0;
begin
  s := public.nft_pool_settings_row();
  insert into public.nft_yield_positions(nft_pet_id, owner_user_id, nft_serial, tier_ton, daily_yield_ton, roi_target_ton, yield_locked_at)
  select n.id, n.owner_user_id, n.nft_serial,
         case when coalesce(n.tier_ton, (n.metadata->>'tier_ton')::numeric, 20) >= 30 then 30 else 20 end,
         coalesce(n.daily_yield_ton,
           case when coalesce(n.tier_ton, (n.metadata->>'tier_ton')::numeric, 20) >= 30 then s.tier30_daily_ton else s.tier20_daily_ton end),
         case when coalesce(n.tier_ton, (n.metadata->>'tier_ton')::numeric, 20) >= 30 then 30 else 20 end * s.roi_multiplier,
         now()
  from public.nft_pets n
  where n.owner_user_id is not null and n.revoked_at is null
    and not exists (select 1 from public.nft_yield_positions p where p.nft_pet_id = n.id);
  created := row_count_of_last();
  update public.nft_yield_positions p
     set owner_user_id = n.owner_user_id,
         status = case when n.revoked_at is not null or n.owner_user_id is null then 'revoked' else
                       case when p.status = 'paused' then 'paused' else 'active' end end,
         updated_at = now()
  from public.nft_pets n
  where n.id = p.nft_pet_id
    and (p.owner_user_id is distinct from n.owner_user_id
         or (n.revoked_at is not null and p.status <> 'revoked'));
  return created;
end $function$;

CREATE OR REPLACE FUNCTION public.nft_shop_json(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; s public.nft_pool_settings; items jsonb; total int; sold int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  s := public.nft_pool_settings_row();
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb), count(*),
         count(*) filter (where x->>'status' = 'SOLD_OUT')
    into items, total, sold
  from (
    select jsonb_build_object(
      'id', n.id,
      'serial', n.nft_serial,
      'instance', n.unique_instance_id,
      'name', pt.name,
      'slug', pt.slug,
      'image', coalesce(pt.image_adult_url, pt.image_young_url, pt.image_baby_url),
      'rarity', 'nft_exclusive',
      'priceTon', round(coalesce(n.price_ton, n.tier_ton, 20), 9),
      'tierTon', round(coalesce(n.tier_ton, 20), 9),
      'dailyYieldTon', round(coalesce(n.daily_yield_ton,
          case when coalesce(n.tier_ton, 20) >= 30 then s.tier30_daily_ton else s.tier20_daily_ton end), 9),
      'supply', 1,
      'status', case when n.status = 'AVAILABLE' and n.owner_user_id is null then 'AVAILABLE' else 'SOLD_OUT' end,
      'ownedByMe', (u is not null and n.owner_user_id = u),
      'passives', coalesce(pt.base_passives, '{}'::jsonb)
    ) as x
    from public.nft_pets n
    join public.pets pt on pt.id = n.pet_template_id
    where n.for_sale and n.status <> 'BURNED'
  ) q;
  return jsonb_build_object(
    'totalSupply', coalesce(total, 0),
    'sold', coalesce(sold, 0),
    'available', coalesce(total, 0) - coalesce(sold, 0),
    'items', items,
    'balanceTon', coalesce((select round(ton_balance, 9) from public.game_players where id = u), 0)
  );
end $function$;

-- tier fix must never rewrite a locked position's yield
CREATE OR REPLACE FUNCTION public.admin_nft_pool_set_tier(p_admin_id bigint, p_serial integer, p_tier_ton numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare s public.nft_pool_settings;
begin
  perform public.admin_assert(p_admin_id);
  if p_tier_ton not in (20, 30) then raise exception 'INVALID_TIER'; end if;
  s := public.nft_pool_settings_row();
  update public.nft_yield_positions
     set tier_ton = p_tier_ton,
         roi_target_ton = p_tier_ton * s.roi_multiplier,
         updated_at = now()
   where nft_serial = p_serial;
  perform public.admin_log(p_admin_id, 'nft_pool_set_tier', null, null,
    jsonb_build_object('serial', p_serial, 'tier', p_tier_ton, 'yieldPreserved', true));
  return public.admin_nft_pool_units(p_admin_id);
end $function$;

-- ============ 5. Pricing changes apply to NEW units only ============
CREATE OR REPLACE FUNCTION public.admin_nft_pricing_set(p_admin_id bigint, p_target text, p_key text, p_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare v_target text := lower(coalesce(p_target, '')); v_key text := lower(coalesce(nullif(p_key, ''), 'all'));
        v_tier numeric; n int := 0;
begin
  perform public.admin_assert(p_admin_id);
  if p_value is null or p_value < 0 then raise exception 'INVALID_VALUE'; end if;
  if v_key <> 'all' then
    begin v_tier := v_key::numeric; exception when others then v_tier := null; end;
  end if;

  if v_target = 'hero_price' then
    update public.nft_heroes set price_ton = p_value, updated_at = now()
     where status = 'AVAILABLE' and owner_user_id is null
       and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier);
    n := coalesce((select count(*) from public.nft_heroes where status = 'AVAILABLE' and owner_user_id is null and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier)), 0);
    insert into public.game_settings(key, value) values ('nft_price_hero_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;

  elsif v_target = 'hero_yield' then
    -- NEW UNITS ONLY: never touch a unit already owned / yield-locked
    update public.nft_heroes set mining_daily_ton = p_value, updated_at = now()
     where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
       and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier);
    n := coalesce((select count(*) from public.nft_heroes
                    where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
                      and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier)), 0);
    insert into public.game_settings(key, value) values ('nft_yield_hero_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;
    perform public.admin_log(p_admin_id, 'NFT_YIELD_TEMPLATE_CHANGED', 'hero', v_key, null,
      jsonb_build_object('target', v_target, 'value', p_value, 'appliedTo', 'NEW_NFTS_ONLY', 'affected', n));

  elsif v_target = 'pet_price' then
    update public.nft_pets set price_ton = p_value, updated_at = now()
     where status = 'AVAILABLE' and owner_user_id is null
       and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier);
    n := coalesce((select count(*) from public.nft_pets where status = 'AVAILABLE' and owner_user_id is null and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier)), 0);
    insert into public.game_settings(key, value) values ('nft_price_pet_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;

  elsif v_target = 'pet_yield' then
    if v_tier is null or v_tier not in (20, 30) then raise exception 'INVALID_TIER'; end if;
    if v_tier = 20 then
      update public.nft_pool_settings set tier20_daily_ton = p_value, updated_at = now() where id;
    else
      update public.nft_pool_settings set tier30_daily_ton = p_value, updated_at = now() where id;
    end if;
    -- NEW UNITS ONLY: unsold stock snapshot, active positions untouched
    update public.nft_pets set daily_yield_ton = p_value, updated_at = now()
     where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
       and coalesce(tier_ton, 20) = v_tier;
    n := coalesce((select count(*) from public.nft_pets
                    where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
                      and coalesce(tier_ton, 20) = v_tier), 0);
    insert into public.game_settings(key, value) values ('nft_yield_pet_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;
    perform public.admin_log(p_admin_id, 'NFT_YIELD_TEMPLATE_CHANGED', 'pet', v_key, null,
      jsonb_build_object('target', v_target, 'value', p_value, 'appliedTo', 'NEW_NFTS_ONLY', 'affected', n));

  elsif v_target = 'equip_price' then
    update public.nft_equipment n2 set price_ton = p_value, updated_at = now()
     where n2.status = 'AVAILABLE' and n2.owner_user_id is null
       and (v_key = 'all' or exists (select 1 from public.equipment_templates t where t.id = n2.template_id and lower(t.slot) = v_key));
    n := coalesce((select count(*) from public.nft_equipment n2
                    where n2.status = 'AVAILABLE' and n2.owner_user_id is null
                      and (v_key = 'all' or exists (select 1 from public.equipment_templates t where t.id = n2.template_id and lower(t.slot) = v_key))), 0);
    insert into public.game_settings(key, value) values ('nft_price_equip_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;
  else
    raise exception 'INVALID_TARGET';
  end if;

  perform public.admin_log(p_admin_id, 'nft_pricing_set', 'system', null, null,
    jsonb_build_object('target', v_target, 'key', v_key, 'value', p_value, 'affected', n, 'scope', 'NEW_NFTS_ONLY'));
  return public.admin_nft_pricing_overview(p_admin_id);
end $function$;

-- ============ 6. Dangerous explicit retroactive action ============
CREATE OR REPLACE FUNCTION public.admin_nft_yield_apply_existing(
  p_admin_id bigint, p_target text, p_key text, p_value numeric, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare v_target text := lower(coalesce(p_target, '')); v_tier numeric; n int := 0; r record;
begin
  perform public.admin_assert(p_admin_id);
  if p_value is null or p_value < 0 then raise exception 'INVALID_VALUE'; end if;
  if p_reason is null or length(btrim(p_reason)) < 5 then raise exception 'REASON_REQUIRED'; end if;
  begin v_tier := nullif(lower(coalesce(p_key,'')), 'all')::numeric; exception when others then v_tier := null; end;
  perform set_config('mythreon.allow_yield_override', 'on', true);

  if v_target = 'hero_yield' then
    for r in select id, nft_serial, owner_user_id, mining_daily_ton from public.nft_heroes
              where status <> 'BURNED' and yield_locked_at is not null
                and (v_tier is null or coalesce(tier_ton, price_ton) = v_tier) loop
      update public.nft_heroes set mining_daily_ton = p_value, updated_at = now() where id = r.id;
      perform public.admin_log(p_admin_id, 'NFT_INSTANCE_YIELD_FORCED', 'nft_hero', r.id::text,
        jsonb_build_object('dailyYieldTon', r.mining_daily_ton),
        jsonb_build_object('dailyYieldTon', p_value, 'serial', r.nft_serial, 'owner', r.owner_user_id),
        p_reason, '{}'::jsonb);
      n := n + 1;
    end loop;
  elsif v_target = 'pet_yield' then
    for r in select p.id, p.nft_serial, p.owner_user_id, p.daily_yield_ton, p.nft_pet_id
              from public.nft_yield_positions p
             where p.status = 'active' and (v_tier is null or p.tier_ton = v_tier) loop
      update public.nft_yield_positions set daily_yield_ton = p_value, updated_at = now() where id = r.id;
      update public.nft_pets set daily_yield_ton = p_value, updated_at = now() where id = r.nft_pet_id;
      perform public.admin_log(p_admin_id, 'NFT_INSTANCE_YIELD_FORCED', 'nft_pet', r.nft_pet_id::text,
        jsonb_build_object('dailyYieldTon', r.daily_yield_ton),
        jsonb_build_object('dailyYieldTon', p_value, 'serial', r.nft_serial, 'owner', r.owner_user_id),
        p_reason, '{}'::jsonb);
      n := n + 1;
    end loop;
  else
    raise exception 'INVALID_TARGET';
  end if;

  perform set_config('mythreon.allow_yield_override', 'off', true);
  return jsonb_build_object('ok', true, 'affected', n, 'target', v_target, 'value', p_value, 'reason', p_reason);
end $function$;

-- ============ 7. Review report for admin ============
CREATE OR REPLACE FUNCTION public.admin_nft_yield_review(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare s public.nft_pool_settings; heroes jsonb; pets jsonb;
begin
  perform public.admin_assert(p_admin_id);
  s := public.nft_pool_settings_row();

  select coalesce(jsonb_agg(jsonb_build_object(
      'serial', n.nft_serial, 'instance', n.unique_instance_id, 'tierTon', n.tier_ton,
      'instanceYield', round(coalesce(n.mining_daily_ton,0),9),
      'templateYield', round(coalesce((select (value#>>'{}')::numeric from public.game_settings
          where key = 'nft_yield_hero_' || coalesce(n.tier_ton, n.price_ton)::text), coalesce(n.mining_daily_ton,0)),9),
      'lockedAt', n.yield_locked_at, 'ownerId', n.owner_user_id) order by n.nft_serial), '[]'::jsonb)
    into heroes
    from public.nft_heroes n
   where n.status <> 'BURNED' and n.yield_locked_at is not null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'serial', p.nft_serial, 'tierTon', p.tier_ton,
      'instanceYield', round(coalesce(p.daily_yield_ton,0),9),
      'templateYield', round(case when p.tier_ton >= 30 then s.tier30_daily_ton else s.tier20_daily_ton end,9),
      'lockedAt', p.yield_locked_at, 'ownerId', p.owner_user_id) order by p.nft_serial), '[]'::jsonb)
    into pets
    from public.nft_yield_positions p
   where p.status = 'active';

  return jsonb_build_object('heroes', heroes, 'pets', pets,
    'petTemplate', jsonb_build_object('tier20', s.tier20_daily_ton, 'tier30', s.tier30_daily_ton),
    'pending', coalesce((select jsonb_agg(to_jsonb(r)) from public.nft_yield_review r where r.status = 'PENDING'), '[]'::jsonb));
end $function$;

REVOKE ALL ON FUNCTION public.admin_nft_yield_apply_existing(bigint, text, text, numeric, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_nft_yield_review(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nft_yield_override_allowed() FROM PUBLIC, anon, authenticated;