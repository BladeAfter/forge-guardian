-- 1. Per-instance MYTH yield columns
ALTER TABLE public.nft_heroes ADD COLUMN IF NOT EXISTS mining_daily_myth numeric NOT NULL DEFAULT 0;
ALTER TABLE public.nft_pets ADD COLUMN IF NOT EXISTS daily_yield_myth numeric NOT NULL DEFAULT 0;
ALTER TABLE public.nft_yield_positions
  ADD COLUMN IF NOT EXISTS daily_yield_myth numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS accrued_myth numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS claimed_myth numeric NOT NULL DEFAULT 0;

-- 2. Freeze guards also protect the MYTH yield of sold units
CREATE OR REPLACE FUNCTION public.nft_hero_yield_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
BEGIN
  IF NEW.owner_user_id IS NOT NULL AND NEW.yield_locked_at IS NULL THEN
    NEW.yield_locked_at := now();
  END IF;
  IF OLD.yield_locked_at IS NOT NULL AND NOT public.nft_yield_override_allowed() THEN
    IF NEW.mining_daily_ton IS DISTINCT FROM OLD.mining_daily_ton THEN
      NEW.mining_daily_ton := OLD.mining_daily_ton;
    END IF;
    IF NEW.mining_daily_myth IS DISTINCT FROM OLD.mining_daily_myth THEN
      NEW.mining_daily_myth := OLD.mining_daily_myth;
    END IF;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.nft_pet_yield_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
BEGIN
  IF NEW.owner_user_id IS NOT NULL AND NEW.yield_locked_at IS NULL THEN
    NEW.yield_locked_at := now();
  END IF;
  IF OLD.yield_locked_at IS NOT NULL AND NOT public.nft_yield_override_allowed() THEN
    IF NEW.daily_yield_ton IS DISTINCT FROM OLD.daily_yield_ton THEN
      NEW.daily_yield_ton := OLD.daily_yield_ton;
    END IF;
    IF NEW.daily_yield_myth IS DISTINCT FROM OLD.daily_yield_myth THEN
      NEW.daily_yield_myth := OLD.daily_yield_myth;
    END IF;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.nft_position_yield_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
BEGIN
  IF NEW.yield_locked_at IS NULL THEN NEW.yield_locked_at := now(); END IF;
  IF NOT public.nft_yield_override_allowed() THEN
    IF NEW.daily_yield_ton IS DISTINCT FROM OLD.daily_yield_ton THEN
      NEW.daily_yield_ton := OLD.daily_yield_ton;
    END IF;
    IF NEW.daily_yield_myth IS DISTINCT FROM OLD.daily_yield_myth THEN
      NEW.daily_yield_myth := OLD.daily_yield_myth;
    END IF;
  END IF;
  RETURN NEW;
END $function$;

-- 3. MYTH rate per hero: NFT units use their own frozen value, others the global setting
CREATE OR REPLACE FUNCTION public.hero_mining_hero_myth_rate(p_rarity text, p_nft_hero_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_nft_hero_id IS NOT NULL THEN COALESCE(
      NULLIF((SELECT GREATEST(COALESCE(mining_daily_myth, 0), 0) FROM nft_heroes WHERE id = p_nft_hero_id), 0),
      hero_mining_myth_per_day())
    ELSE hero_mining_myth_per_day()
  END;
$$;
REVOKE EXECUTE ON FUNCTION public.hero_mining_hero_myth_rate(text, uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.hero_mining_effective_daily(p_rarity text, p_nft_hero_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN hero_mining_hero_rate(p_rarity, p_nft_hero_id) <= 0 THEN 0
    WHEN hero_mining_currency() = 'myth' THEN hero_mining_hero_myth_rate(p_rarity, p_nft_hero_id)
    ELSE hero_mining_hero_rate(p_rarity, p_nft_hero_id)
  END;
$$;

-- 4. Accrual honours the per-unit MYTH rate
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_now timestamptz := now(); v_gain numeric := 0; v_out numeric; v_room numeric;
        v_currency text := hero_mining_currency();
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT CASE WHEN v_currency = 'myth' THEN hero_mining_unclaimed_myth
                                 ELSE hero_mining_unclaimed_ton END
                       FROM game_players WHERE id = p_user_id), 0);
  END IF;

  IF v_currency = 'ton' THEN
    v_room := COALESCE(hero_mining_remaining(p_user_id), 0);
    IF v_room <= 0 THEN
      UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
      RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
    END IF;
  END IF;

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(
    CASE WHEN rate <= 0 THEN 0
         WHEN v_currency = 'myth' THEN myth_rate * secs / 86400.0
         ELSE rate * secs / 86400.0 END), 0)
    INTO v_gain FROM moved;

  IF v_currency = 'myth' THEN
    v_gain := round(GREATEST(v_gain, 0), 9);
    UPDATE game_players
       SET hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_gain, 9),
           updated_at = now()
     WHERE id = p_user_id
    RETURNING hero_mining_unclaimed_myth INTO v_out;
  ELSE
    v_gain := round(LEAST(GREATEST(v_gain, 0), v_room), 9);
    UPDATE game_players
       SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
           updated_at = now()
     WHERE id = p_user_id
    RETURNING hero_mining_unclaimed_ton INTO v_out;
  END IF;

  RETURN COALESCE(v_out, 0);
END $$;

CREATE OR REPLACE FUNCTION public.hero_mining_settle_all()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_now timestamptz := now(); v_currency text := hero_mining_currency();
        v_ton_total numeric := 0; v_myth_total numeric := 0;
BEGIN
  DROP TABLE IF EXISTS _mining_settle;
  CREATE TEMP TABLE _mining_settle ON COMMIT DROP AS
  WITH elig AS (
    SELECT h.id, h.user_id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id IS NOT NULL
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.user_id AS user_id, e.rate AS rate, e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT user_id,
         round(SUM(CASE WHEN rate > 0 AND v_currency = 'ton' THEN rate * secs / 86400.0 ELSE 0 END), 9) AS ton_gain,
         round(SUM(CASE WHEN rate > 0 AND v_currency = 'myth' THEN myth_rate * secs / 86400.0 ELSE 0 END), 9) AS myth_gain
    FROM moved GROUP BY user_id;

  IF v_currency = 'ton' THEN
    UPDATE game_players g
       SET hero_mining_unclaimed_ton = round(COALESCE(g.hero_mining_unclaimed_ton,0)
             + LEAST(s.ton_gain, GREATEST(0, COALESCE(g.hero_mining_invested_ton,0)
               - COALESCE(g.hero_mining_returned_ton,0) - COALESCE(g.hero_mining_unclaimed_ton,0))), 9),
           updated_at = now()
      FROM _mining_settle s
     WHERE g.id = s.user_id AND s.ton_gain > 0;
    SELECT COALESCE(SUM(ton_gain),0) INTO v_ton_total FROM _mining_settle;
  ELSE
    UPDATE game_players g
       SET hero_mining_unclaimed_myth = round(COALESCE(g.hero_mining_unclaimed_myth,0) + s.myth_gain, 9),
           updated_at = now()
      FROM _mining_settle s
     WHERE g.id = s.user_id AND s.myth_gain > 0;
    SELECT COALESCE(SUM(myth_gain),0) INTO v_myth_total FROM _mining_settle;
  END IF;

  IF v_myth_total > 0 THEN
    INSERT INTO nft_mining_ledger (entry_type, currency, amount, meta)
    VALUES ('NFT_MINING_MYTH_ACCRUAL', 'myth', v_myth_total, jsonb_build_object('scope','settle_all'));
  END IF;

  RETURN jsonb_build_object('currency', v_currency, 'tonAccrued', v_ton_total, 'mythAccrued', v_myth_total, 'settledAt', v_now);
END $$;

-- 5. NFT pet positions: snapshot + accrue + claim in MYTH when MYTH is the active currency
CREATE OR REPLACE FUNCTION public.nft_pool_sync_positions()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare s public.nft_pool_settings; created integer := 0;
begin
  s := public.nft_pool_settings_row();
  insert into public.nft_yield_positions(nft_pet_id, owner_user_id, nft_serial, tier_ton, daily_yield_ton, daily_yield_myth, roi_target_ton, yield_locked_at)
  select n.id, n.owner_user_id, n.nft_serial,
         case when coalesce(n.tier_ton, (n.metadata->>'tier_ton')::numeric, 20) >= 30 then 30 else 20 end,
         coalesce(n.daily_yield_ton,
           case when coalesce(n.tier_ton, (n.metadata->>'tier_ton')::numeric, 20) >= 30 then s.tier30_daily_ton else s.tier20_daily_ton end),
         coalesce(n.daily_yield_myth, 0),
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

CREATE OR REPLACE FUNCTION public.nft_effective_daily_myth(p_position nft_yield_positions)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE WHEN p_position.status <> 'active' THEN 0
              ELSE GREATEST(COALESCE(p_position.daily_yield_myth, 0), 0) END;
$$;

CREATE OR REPLACE FUNCTION public.nft_pool_accrue()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare s public.nft_pool_settings; r public.nft_yield_positions; secs numeric; gain numeric;
        touched integer := 0; total numeric := 0; v_currency text := public.hero_mining_currency();
begin
  s := public.nft_pool_settings_row();
  perform public.nft_pool_sync_positions();
  if not s.accrual_enabled then return jsonb_build_object('enabled', false, 'positions', 0); end if;
  for r in select * from public.nft_yield_positions where status = 'active' for update loop
    secs := greatest(0, extract(epoch from (now() - r.last_accrual_at)));
    if secs < 60 then continue; end if;
    if v_currency = 'myth' then
      gain := round(public.nft_effective_daily_myth(r) * (secs / 86400.0), 9);
      update public.nft_yield_positions
         set accrued_myth = accrued_myth + gain, last_accrual_at = now(), updated_at = now()
       where id = r.id;
    else
      gain := round(public.nft_effective_daily(r) * (secs / 86400.0), 9);
      update public.nft_yield_positions
         set accrued_ton = accrued_ton + gain,
             roi_reached = roi_reached or (claimed_ton + accrued_ton + gain) >= roi_target_ton,
             last_accrual_at = now(), updated_at = now()
       where id = r.id;
    end if;
    touched := touched + 1; total := total + gain;
  end loop;
  update public.nft_reward_pool
     set reserved_ton = coalesce((select sum(accrued_ton) from public.nft_yield_positions where status = 'active'), 0),
         updated_at = now()
   where id;
  return jsonb_build_object('enabled', true, 'currency', v_currency, 'positions', touched, 'accrued', total);
end $function$;

CREATE OR REPLACE FUNCTION public.nft_claim_position(p_telegram_id bigint, p_position_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; p public.nft_yield_positions; s public.nft_pool_settings;
        v_before numeric; amount numeric; claim uuid := gen_random_uuid();
        v_currency text := public.hero_mining_currency(); v_min numeric; v_available numeric;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_pool_accrue();
  s := public.nft_pool_settings_row();
  select * into p from public.nft_yield_positions
   where id = p_position_id and owner_user_id = u and status = 'active' for update;
  if p.id is null then raise exception 'NFT_NOT_FOUND'; end if;

  if v_currency = 'myth' then
    amount := floor(greatest(coalesce(p.accrued_myth,0),0) * 1000000) / 1000000;
    select coalesce(min_claim_myth, 0) into v_min from public.hero_mining_settings where id;
    v_available := public.myth_mining_pool_available();
    if amount <= 0 or amount < coalesce(v_min, 0) then raise exception 'CLAIM_TOO_SMALL'; end if;
    if amount > v_available then raise exception 'MYTH_POOL_EMPTY'; end if;

    update public.nft_yield_positions
       set accrued_myth = greatest(0, accrued_myth - amount), claimed_myth = claimed_myth + amount,
           last_claim_at = now(), updated_at = now()
     where id = p.id;

    update public.myth_mining_pool
       set distributed_myth = round(distributed_myth + amount, 9), updated_at = now()
     where id;

    insert into public.myth_balances (user_id, amount, updated_at)
    values (u, amount, now())
    on conflict (user_id) do update set amount = round(public.myth_balances.amount + amount, 9), updated_at = now();

    insert into public.myth_supply_ledger (entry_type, amount, user_id, reference_id, note)
    values ('MINING', amount, u, claim::text, format('NFT #%s MYTH mining claim', p.nft_serial));

    insert into public.nft_mining_ledger (entry_type, currency, amount, user_id, reference_id)
    values ('NFT_MINING_MYTH_CLAIM', 'myth', amount, u, claim::text);

    return jsonb_build_object('ok', true, 'claimId', claim, 'currency', 'myth', 'amountTon', 0, 'amountMyth', amount)
           || public.nft_my_rewards_json(p_telegram_id);
  end if;

  amount := floor(greatest(coalesce(p.accrued_ton,0),0) * 1000000) / 1000000;
  if amount <= 0 or amount < s.min_claim_ton then raise exception 'CLAIM_TOO_SMALL'; end if;

  v_before := public.nft_pool_settle_payment(amount);
  update public.nft_yield_positions
     set accrued_ton = greatest(0, accrued_ton - amount), claimed_ton = claimed_ton + amount,
         roi_reached = roi_reached or (claimed_ton + amount) >= roi_target_ton,
         last_claim_at = now(), updated_at = now()
   where id = p.id;
  insert into public.nft_pool_transactions(type, amount_ton, balance_before, balance_after, nft_id, user_id, telegram_id, claim_id, note)
  values ('CLAIM_PAYMENT', -amount, v_before, greatest(0, v_before - amount), p.nft_pet_id, u, p_telegram_id, claim,
          format('NFT #%s claim', p.nft_serial));
  perform public.credit_ton_reward(u, amount, 'nft_reward', claim::text, format('NFT #%s reward claim', p.nft_serial));

  return jsonb_build_object('ok', true, 'claimId', claim, 'currency', 'ton', 'amountTon', amount) || public.nft_my_rewards_json(p_telegram_id);
end $function$;

-- 6. Player-facing payloads expose the MYTH yield per unit
CREATE OR REPLACE FUNCTION public.nft_my_rewards_json(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; total integer; items jsonb; v_currency text := public.hero_mining_currency();
        v_min_myth numeric;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select coalesce(min_claim_myth, 0) into v_min_myth from public.hero_mining_settings where id;
  select count(*) into total from public.nft_pets;
  select coalesce(jsonb_agg(x order by x->>'serial'), '[]'::jsonb) into items from (
    select jsonb_build_object(
      'positionId', p.id,
      'serial', p.nft_serial,
      'name', coalesce(pt.name, 'NFT PET'),
      'rarity', coalesce(pp.rarity, pt.rarity, 'nft_exclusive'),
      'level', coalesce(pp.level, 1),
      'image', coalesce(pt.image_adult_url, pt.image_young_url, pt.image_baby_url),
      'tierTon', p.tier_ton,
      'currency', v_currency,
      'dailyYieldTon', public.nft_effective_daily(p),
      'dailyYieldMyth', public.nft_effective_daily_myth(p),
      'availableTon', round(p.accrued_ton, 6),
      'availableMyth', round(coalesce(p.accrued_myth, 0), 6),
      'lifetimeEarnedTon', round(p.claimed_ton, 6),
      'lifetimeEarnedMyth', round(coalesce(p.claimed_myth, 0), 6),
      'roiReached', p.roi_reached,
      'minClaimTon', (public.nft_pool_settings_row()).min_claim_ton,
      'minClaimMyth', coalesce(v_min_myth, 0),
      'canClaim', case when v_currency = 'myth'
                       then round(coalesce(p.accrued_myth,0), 6) >= coalesce(v_min_myth, 0) and coalesce(p.accrued_myth,0) > 0
                       else round(p.accrued_ton, 6) >= (public.nft_pool_settings_row()).min_claim_ton end,
      'lastClaimAt', p.last_claim_at
    ) as x
    from public.nft_yield_positions p
    left join public.nft_pets n on n.id = p.nft_pet_id
    left join public.player_pets pp on pp.id = n.player_pet_id
    left join public.pets pt on pt.id = coalesce(pp.pet_id, n.pet_template_id)
    where p.owner_user_id = u and p.status = 'active'
  ) q;
  return jsonb_build_object('totalSupply', greatest(total, 10), 'items', items, 'currency', v_currency);
end $function$;

CREATE OR REPLACE FUNCTION public.nft_hero_shop_json(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; items jsonb; total int; sold int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb), count(*),
         count(*) filter (where x->>'status' = 'SOLD_OUT')
    into items, total, sold
  from (
    select jsonb_build_object(
      'id', n.id,
      'serial', n.nft_serial,
      'instance', n.unique_instance_id,
      'name', c.name,
      'slug', c.hero_key,
      'image', c.image,
      'rarity', 'nft_exclusive',
      'priceTon', round(coalesce(n.price_ton, n.tier_ton, 20), 9),
      'tierTon', round(coalesce(n.tier_ton, n.price_ton, 20), 9),
      'dailyYieldTon', round(coalesce(n.mining_daily_ton, 0), 9),
      'dailyYieldMyth', round(coalesce(n.mining_daily_myth, 0), 9),
      'supply', 1,
      'status', case when n.status = 'AVAILABLE' and n.owner_user_id is null then 'AVAILABLE' else 'SOLD_OUT' end,
      'ownedByMe', (u is not null and n.owner_user_id = u),
      'atk', round(coalesce(c.base_atk, 0)),
      'hp', round(coalesce(c.base_hp, 0))
    ) as x
    from public.nft_heroes n
    join public.hero_catalog c on c.hero_key = n.hero_template_id
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
      'dailyYieldMyth', round(coalesce(n.daily_yield_myth, 0), 9),
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

-- 7. Admin: MYTH yield targets that only touch unsold shop stock
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

  elsif v_target = 'hero_yield_myth' then
    update public.nft_heroes set mining_daily_myth = p_value, updated_at = now()
     where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
       and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier);
    n := coalesce((select count(*) from public.nft_heroes
                    where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
                      and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier)), 0);
    insert into public.game_settings(key, value) values ('nft_yield_myth_hero_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;
    perform public.admin_log(p_admin_id, 'NFT_YIELD_TEMPLATE_CHANGED', 'hero', v_key, null,
      jsonb_build_object('target', v_target, 'value', p_value, 'currency', 'myth', 'appliedTo', 'SHOP_STOCK_ONLY', 'affected', n));

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

  elsif v_target = 'pet_yield_myth' then
    update public.nft_pets set daily_yield_myth = p_value, updated_at = now()
     where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
       and (v_key = 'all' or coalesce(tier_ton, 20) = v_tier);
    n := coalesce((select count(*) from public.nft_pets
                    where status = 'AVAILABLE' and owner_user_id is null and yield_locked_at is null
                      and (v_key = 'all' or coalesce(tier_ton, 20) = v_tier)), 0);
    insert into public.game_settings(key, value) values ('nft_yield_myth_pet_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;
    perform public.admin_log(p_admin_id, 'NFT_YIELD_TEMPLATE_CHANGED', 'pet', v_key, null,
      jsonb_build_object('target', v_target, 'value', p_value, 'currency', 'myth', 'appliedTo', 'SHOP_STOCK_ONLY', 'affected', n));

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

CREATE OR REPLACE FUNCTION public.admin_nft_pricing_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare s public.nft_pool_settings; heroes jsonb; pets jsonb; equips jsonb; defaults jsonb;
begin
  perform public.admin_assert(p_admin_id);
  s := public.nft_pool_settings_row();

  select coalesce(jsonb_agg(x order by (x->>'tier')::numeric), '[]'::jsonb) into heroes
  from (
    select jsonb_build_object(
      'tier', coalesce(tier_ton, price_ton, 0),
      'available', count(*) filter (where status = 'AVAILABLE' and owner_user_id is null),
      'sold', count(*) filter (where owner_user_id is not null),
      'priceMin', min(price_ton), 'priceMax', max(price_ton),
      'yieldMin', min(mining_daily_ton), 'yieldMax', max(mining_daily_ton),
      'mythMin', min(mining_daily_myth) filter (where status = 'AVAILABLE' and owner_user_id is null),
      'mythMax', max(mining_daily_myth) filter (where status = 'AVAILABLE' and owner_user_id is null)
    ) as x
    from public.nft_heroes
    where status <> 'BURNED'
    group by coalesce(tier_ton, price_ton, 0)
  ) q;

  select coalesce(jsonb_agg(x order by (x->>'tier')::numeric), '[]'::jsonb) into pets
  from (
    select jsonb_build_object(
      'tier', coalesce(tier_ton, price_ton, 0),
      'available', count(*) filter (where status = 'AVAILABLE' and owner_user_id is null),
      'sold', count(*) filter (where owner_user_id is not null),
      'priceMin', min(price_ton), 'priceMax', max(price_ton),
      'mythMin', min(daily_yield_myth) filter (where status = 'AVAILABLE' and owner_user_id is null),
      'mythMax', max(daily_yield_myth) filter (where status = 'AVAILABLE' and owner_user_id is null)
    ) as x
    from public.nft_pets
    where status <> 'BURNED'
    group by coalesce(tier_ton, price_ton, 0)
  ) q;

  select coalesce(jsonb_agg(x order by x->>'slot'), '[]'::jsonb) into equips
  from (
    select jsonb_build_object(
      'slot', t.slot,
      'available', count(*) filter (where n.status = 'AVAILABLE' and n.owner_user_id is null),
      'sold', count(*) filter (where n.owner_user_id is not null),
      'priceMin', min(n.price_ton), 'priceMax', max(n.price_ton)
    ) as x
    from public.nft_equipment n
    join public.equipment_templates t on t.id = n.template_id
    where n.status <> 'BURNED'
    group by t.slot
  ) q;

  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into defaults
  from public.game_settings where key like 'nft_price_%' or key like 'nft_yield_%';

  return jsonb_build_object(
    'heroes', heroes,
    'pets', pets,
    'equipment', equips,
    'miningCurrency', public.hero_mining_currency(),
    'petYield', jsonb_build_object(
      'tier20', s.tier20_daily_ton,
      'tier30', s.tier30_daily_ton,
      'roiMultiplier', s.roi_multiplier,
      'minClaimTon', s.min_claim_ton,
      'accrualEnabled', s.accrual_enabled
    ),
    'defaults', defaults
  );
end $function$;