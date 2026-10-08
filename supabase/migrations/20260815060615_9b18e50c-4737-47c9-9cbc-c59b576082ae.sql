CREATE OR REPLACE FUNCTION public.admin_nft_pricing_overview(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
      'yieldMin', min(mining_daily_ton), 'yieldMax', max(mining_daily_ton)
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
      'priceMin', min(price_ton), 'priceMax', max(price_ton)
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

REVOKE ALL ON FUNCTION public.admin_nft_pricing_overview(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_nft_pricing_overview(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_nft_pricing_set(p_admin_id bigint, p_target text, p_key text, p_value numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
     where status <> 'BURNED'
       and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier);
    n := coalesce((select count(*) from public.nft_heroes where status <> 'BURNED' and (v_key = 'all' or coalesce(tier_ton, price_ton) = v_tier)), 0);
    insert into public.game_settings(key, value) values ('nft_yield_hero_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;

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
    update public.nft_yield_positions set daily_yield_ton = p_value, updated_at = now()
     where tier_ton = v_tier and status = 'ACTIVE';
    n := coalesce((select count(*) from public.nft_yield_positions where tier_ton = v_tier and status = 'ACTIVE'), 0);
    insert into public.game_settings(key, value) values ('nft_yield_pet_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;

  elsif v_target = 'equip_price' then
    update public.nft_equipment n set price_ton = p_value, updated_at = now()
     where n.status = 'AVAILABLE' and n.owner_user_id is null
       and (v_key = 'all' or exists (select 1 from public.equipment_templates t where t.id = n.template_id and lower(t.slot) = v_key));
    n := coalesce((select count(*) from public.nft_equipment e where e.status = 'AVAILABLE' and e.owner_user_id is null and (v_key = 'all' or exists (select 1 from public.equipment_templates t where t.id = e.template_id and lower(t.slot) = v_key))), 0);
    insert into public.game_settings(key, value) values ('nft_price_equip_' || v_key, to_jsonb(p_value))
      on conflict (key) do update set value = excluded.value;
  else
    raise exception 'INVALID_TARGET';
  end if;

  perform public.admin_bump_settings_version();
  perform public.admin_log(p_admin_id, 'nft_pricing_set', null, null, jsonb_build_object('target', v_target, 'key', v_key, 'value', p_value, 'affected', n));
  return public.admin_nft_pricing_overview(p_admin_id) || jsonb_build_object('affected', n);
end $function$;

REVOKE ALL ON FUNCTION public.admin_nft_pricing_set(bigint, text, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_nft_pricing_set(bigint, text, text, numeric) TO service_role;