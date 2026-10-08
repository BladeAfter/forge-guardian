create or replace function public.admin_myth_utility_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.myth_utility_settings; v_sale jsonb; v_burn numeric; v_users bigint; v_last jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select * into s from public.myth_utility_settings where id;
  v_sale := public.myth_sale_stats();
  select coalesce(sum(amount_myth), 0), count(distinct user_id) into v_burn, v_users from public.myth_utility_burns;
  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_last from (
    select jsonb_build_object('feature', b.feature_code, 'amount', b.amount_myth, 'at', b.created_at) as x
    from public.myth_utility_burns b order by b.created_at desc limit 8
  ) q;
  return jsonb_build_object(
    'enabled', s.enabled,
    'mythPerTon', s.myth_per_ton,
    'fcPerTon', s.fc_per_ton,
    'mythPerFc', round(s.myth_per_ton / nullif(s.fc_per_ton, 0), 6),
    'discountPercent', s.discount_percent,
    'onchainBurnEnabled', s.onchain_burn_enabled,
    'jettonMaster', s.jetton_master,
    'features', coalesce((select jsonb_agg(jsonb_build_object(
        'code', f.feature_code, 'label', f.label, 'enabled', f.enabled,
        'pricingMode', f.pricing_mode, 'customMyth', f.custom_myth,
        'burned', coalesce((select sum(b.amount_myth) from public.myth_utility_burns b where b.feature_code = f.feature_code), 0))
      order by f.feature_code) from public.myth_utility_features f), '[]'::jsonb),
    'utilityBurned', round(v_burn, 4),
    'payers', v_users,
    'lastBurns', v_last,
    'sale', v_sale
  );
end $$;

create or replace function public.admin_myth_utility_set(p_admin_id bigint, p_field text, p_value text, p_feature text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_num numeric; v_bool boolean;
begin
  perform public.admin_assert(p_admin_id);
  if p_field = 'enabled' then
    v_bool := p_value in ('1', 'true', 'on');
    update public.myth_utility_settings set enabled = v_bool, updated_at = now() where id;
  elsif p_field = 'onchain' then
    v_bool := p_value in ('1', 'true', 'on');
    update public.myth_utility_settings set onchain_burn_enabled = v_bool, updated_at = now() where id;
  elsif p_field = 'mythperton' then
    v_num := p_value::numeric;
    if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
    update public.myth_utility_settings set myth_per_ton = v_num, updated_at = now() where id;
  elsif p_field = 'fcperton' then
    v_num := p_value::numeric;
    if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
    update public.myth_utility_settings set fc_per_ton = v_num, updated_at = now() where id;
  elsif p_field = 'discount' then
    v_num := p_value::numeric;
    if v_num < 0 or v_num > 90 then raise exception 'INVALID_DISCOUNT'; end if;
    update public.myth_utility_settings set discount_percent = v_num, updated_at = now() where id;
  elsif p_field = 'feature' then
    v_bool := p_value in ('1', 'true', 'on');
    update public.myth_utility_features set enabled = v_bool, updated_at = now() where feature_code = p_feature;
    if not found then raise exception 'FEATURE_NOT_FOUND'; end if;
  elsif p_field = 'mode' then
    if upper(p_value) not in ('AUTO_FC', 'AUTO_TON', 'CUSTOM') then raise exception 'INVALID_MODE'; end if;
    update public.myth_utility_features set pricing_mode = upper(p_value), updated_at = now() where feature_code = p_feature;
    if not found then raise exception 'FEATURE_NOT_FOUND'; end if;
  elsif p_field = 'custom' then
    v_num := nullif(p_value, '')::numeric;
    update public.myth_utility_features set custom_myth = v_num, updated_at = now() where feature_code = p_feature;
    if not found then raise exception 'FEATURE_NOT_FOUND'; end if;
  else
    raise exception 'INVALID_FIELD';
  end if;
  perform public.admin_log(p_admin_id, 'myth_utility_set', 'myth_utility',
    coalesce(p_feature, 'settings'), jsonb_build_object('field', p_field, 'value', p_value));
  return public.admin_myth_utility_overview(p_admin_id);
end $$;

revoke execute on function public.admin_myth_utility_overview(bigint) from public, anon, authenticated;
revoke execute on function public.admin_myth_utility_set(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_myth_utility_overview(bigint) to service_role;
grant execute on function public.admin_myth_utility_set(bigint, text, text, text) to service_role;