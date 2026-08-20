INSERT INTO public.myth_utility_features(feature_code, label, pricing_mode, enabled)
VALUES ('HERO_RECRUIT', 'Hero Recruitment', 'AUTO_FC', true)
ON CONFLICT (feature_code) DO UPDATE SET enabled = true, label = excluded.label;

CREATE OR REPLACE FUNCTION public.recruit_heroes(p_telegram_id bigint, p_count integer, p_pay_currency text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_user uuid; v_cost numeric; i int; roll numeric; acc numeric; rarity_pick text;
  picked hero_catalog%rowtype; new_hero_id uuid; result jsonb := '[]'::jsonb;
  v_weights jsonb; v_total numeric := 0; r record;
  v_currency text := upper(coalesce(p_pay_currency, 'FC'));
  v_myth numeric; v_burn jsonb;
begin
  if p_count not in (1,5,10) then raise exception 'Invalid recruitment count'; end if;

  v_cost := public.hero_recruit_price(p_count);
  if v_cost is null or v_cost <= 0 then raise exception 'invalid_recruit_price'; end if;

  v_weights := public.hero_effective_real_summon_odds();
  select coalesce(sum((value #>> '{}')::numeric), 0) into v_total from jsonb_each(v_weights);
  if v_total <= 0 then raise exception 'recruit_pool_unavailable'; end if;

  insert into game_players(telegram_id, last_seen_at) values (p_telegram_id, now())
    on conflict(telegram_id) do update set last_seen_at = now(), updated_at = now()
    returning id into v_user;

  if v_currency = 'MYTH' then
    v_myth := public.myth_utility_price('HERO_RECRUIT', v_cost, 0);
    if v_myth is null or v_myth <= 0 then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;
    v_burn := public.myth_utility_charge(v_user, 'HERO_RECRUIT', v_myth, null, null,
      jsonb_build_object('count', p_count, 'fcEquivalent', v_cost));
  else
    if (select forge_coins from game_players where id = v_user for update) < v_cost then
      raise exception 'NOT_ENOUGH_FC';
    end if;
    update game_players set forge_coins = forge_coins - v_cost, updated_at = now() where id = v_user;
  end if;

  for i in 1..p_count loop
    roll := random() * v_total;
    acc := 0;
    rarity_pick := null;
    for r in
      select key, (value #>> '{}')::numeric as chance
        from jsonb_each(v_weights)
       order by (value #>> '{}')::numeric asc, key asc
    loop
      acc := acc + r.chance;
      if roll < acc then rarity_pick := r.key; exit; end if;
    end loop;
    if rarity_pick is null then
      select key into rarity_pick from jsonb_each(v_weights)
       order by (value #>> '{}')::numeric desc, key asc limit 1;
    end if;

    if not public.hero_rarity_recruitable(rarity_pick) then raise exception 'rarity_disabled:%', rarity_pick; end if;

    select * into picked from hero_catalog
     where rarity = rarity_pick and enabled and recruit_enabled
     order by random() limit 1;
    if picked.hero_key is null then raise exception 'recruit_pool_unavailable:%', rarity_pick; end if;

    insert into player_heroes(user_id, hero_key, name, rarity, level, image)
      values (v_user, picked.hero_key, picked.name, picked.rarity, 1, picked.image)
      returning id into new_hero_id;
    result := result || jsonb_build_array(jsonb_build_object(
      'id', new_hero_id, 'heroKey', picked.hero_key, 'name', picked.name,
      'rarity', picked.rarity, 'level', 1, 'image', picked.image));
  end loop;

  return jsonb_build_object(
    'heroes', result,
    'balance', (select forge_coins from game_players where id = v_user),
    'cost', case when v_currency = 'MYTH' then 0 else v_cost end,
    'currency', v_currency,
    'mythSpent', case when v_currency = 'MYTH' then v_myth else null end,
    'mythBurn', v_burn
  );
end; $function$;

REVOKE ALL ON FUNCTION public.recruit_heroes(bigint, integer, text) FROM public;
GRANT EXECUTE ON FUNCTION public.recruit_heroes(bigint, integer, text) TO service_role;