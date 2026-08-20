-- Hidden (real) summon rates: the shop keeps showing the public rates, the roll uses these.
CREATE OR REPLACE FUNCTION public.hero_real_summon_rates()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT COALESCE(
    (SELECT value FROM public.game_settings WHERE key = 'hero_summon_rates_real'),
    public.hero_summon_rates()
  ) - 'ancestral' || jsonb_build_object('ancestral', 0);
$function$;

CREATE OR REPLACE FUNCTION public.hero_effective_real_summon_odds()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_total numeric := 0; v_out jsonb := '{}'::jsonb; r record;
BEGIN
  FOR r IN
    SELECT e.key AS rarity, (e.value #>> '{}')::numeric AS chance
      FROM jsonb_each(public.hero_real_summon_rates()) e
     WHERE e.key NOT IN ('ancestral','nft_exclusive')
       AND (e.value #>> '{}')::numeric > 0
       AND public.hero_rarity_recruitable(e.key)
       AND EXISTS (SELECT 1 FROM public.hero_catalog c
                    WHERE c.rarity = e.key AND c.enabled AND c.recruit_enabled AND NOT c.is_nft_exclusive)
  LOOP
    v_total := v_total + r.chance;
    v_out := v_out || jsonb_build_object(r.rarity, r.chance);
  END LOOP;
  IF v_total <= 0 THEN RETURN public.hero_effective_summon_odds(); END IF;
  SELECT jsonb_object_agg(key, round((value #>> '{}')::numeric * 100 / v_total, 4))
    INTO v_out FROM jsonb_each(v_out);
  RETURN v_out;
END; $function$;

CREATE OR REPLACE FUNCTION public.admin_set_hero_real_summon_rates(p_admin_id bigint, p_rates jsonb, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_allowed text[] := ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral'];
  v_total numeric := 0; k text; v numeric; v_old jsonb; v_final jsonb := '{}'::jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  FOR k, v IN SELECT key, (value #>> '{}')::numeric FROM jsonb_each(p_rates) LOOP
    IF NOT (k = ANY(v_allowed)) THEN RAISE EXCEPTION 'invalid_rarity:%', k; END IF;
    IF v IS NULL OR v < 0 OR v > 100 THEN RAISE EXCEPTION 'invalid_rate:%', k; END IF;
    IF k = 'ancestral' AND v <> 0 THEN RAISE EXCEPTION 'ancestral_not_summonable'; END IF;
    v_total := v_total + v;
    v_final := v_final || jsonb_build_object(k, round(v, 4));
  END LOOP;
  IF (SELECT count(*) FROM jsonb_object_keys(v_final)) <> array_length(v_allowed, 1) THEN
    RAISE EXCEPTION 'missing_rarities';
  END IF;
  IF abs(v_total - 100) > 0.001 THEN RAISE EXCEPTION 'rates_must_total_100:%', v_total; END IF;

  SELECT value INTO v_old FROM public.game_settings WHERE key = 'hero_summon_rates_real';
  INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
  VALUES ('hero_summon_rates_real', v_final, 'heroes', 'Chances REAIS do sorteio (ocultas no jogo)', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;

  PERFORM public.admin_log(p_admin_id, 'hero.summon_rates_real', 'setting', 'hero_summon_rates_real', v_old, v_final, p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN jsonb_build_object('rates', v_final, 'odds', public.hero_effective_real_summon_odds(),
                            'publicOdds', public.hero_effective_summon_odds());
END; $function$;

CREATE OR REPLACE FUNCTION public.admin_hero_real_odds(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'rates', public.hero_real_summon_rates(),
    'odds', public.hero_effective_real_summon_odds(),
    'publicOdds', public.hero_effective_summon_odds(),
    'custom', EXISTS (SELECT 1 FROM public.game_settings WHERE key = 'hero_summon_rates_real')
  );
END; $function$;

REVOKE ALL ON FUNCTION public.hero_real_summon_rates() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_effective_real_summon_odds() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_real_summon_rates() TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_effective_real_summon_odds() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_hero_real_summon_rates(bigint, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_real_odds(bigint) TO service_role;

-- The roll now uses the hidden rates; the shop UI keeps reading hero_effective_summon_odds().
CREATE OR REPLACE FUNCTION public.recruit_heroes(p_telegram_id bigint, p_count integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare
  v_user uuid; v_cost numeric; i int; roll numeric; acc numeric; rarity_pick text;
  picked hero_catalog%rowtype; new_hero_id uuid; result jsonb := '[]'::jsonb;
  v_weights jsonb; v_total numeric := 0; r record;
begin
  if p_count not in (1,5,10) then raise exception 'Invalid recruitment count'; end if;

  v_cost := public.hero_recruit_price(p_count);
  if v_cost is null or v_cost <= 0 then raise exception 'invalid_recruit_price'; end if;

  -- server is the source of truth: hidden real odds decide the roll
  v_weights := public.hero_effective_real_summon_odds();
  select coalesce(sum((value #>> '{}')::numeric), 0) into v_total from jsonb_each(v_weights);
  if v_total <= 0 then raise exception 'recruit_pool_unavailable'; end if;

  insert into game_players(telegram_id, last_seen_at) values (p_telegram_id, now())
    on conflict(telegram_id) do update set last_seen_at = now(), updated_at = now()
    returning id into v_user;

  if (select forge_coins from game_players where id = v_user for update) < v_cost then
    raise exception 'NOT_ENOUGH_FC';
  end if;
  update game_players set forge_coins = forge_coins - v_cost, updated_at = now() where id = v_user;

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
    'cost', v_cost
  );
end; $function$;