-- Rarities available in the Hero Recruit shop. Ancestral is never part of it.
INSERT INTO public.game_settings(key, value)
VALUES ('hero_recruit_rarity_enabled',
  '{"common":true,"uncommon":true,"rare":true,"epic":true,"legendary":true,"mythic":true}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Canonical flag map: always the 6 shop rarities, defaulting to enabled.
CREATE OR REPLACE FUNCTION public.hero_recruit_rarity_flags()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_object_agg(r, COALESCE((stored.value -> r)::text::boolean, true))
  FROM unnest(ARRAY['common','uncommon','rare','epic','legendary','mythic']) AS r
  LEFT JOIN (SELECT value FROM public.game_settings WHERE key = 'hero_recruit_rarity_enabled') stored ON true;
$$;

CREATE OR REPLACE FUNCTION public.hero_rarity_recruitable(p_rarity text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((public.hero_recruit_rarity_flags() -> lower(trim(coalesce(p_rarity,''))))::text::boolean, false);
$$;

-- Effective odds: base weights of ENABLED rarities that own at least one recruitable
-- hero, normalized back to 100%. Base values in game_settings are never rewritten.
CREATE OR REPLACE FUNCTION public.hero_effective_summon_odds()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_total numeric := 0; v_out jsonb := '{}'::jsonb; r record;
BEGIN
  FOR r IN
    SELECT e.key AS rarity, (e.value #>> '{}')::numeric AS chance
      FROM jsonb_each(public.hero_summon_rates()) e
     WHERE e.key <> 'ancestral'
       AND (e.value #>> '{}')::numeric > 0
       AND public.hero_rarity_recruitable(e.key)
       AND EXISTS (SELECT 1 FROM public.hero_catalog c
                    WHERE c.rarity = e.key AND c.enabled AND c.recruit_enabled)
  LOOP
    v_total := v_total + r.chance;
    v_out := v_out || jsonb_build_object(r.rarity, r.chance);
  END LOOP;

  IF v_total <= 0 THEN RETURN '{}'::jsonb; END IF;

  SELECT jsonb_object_agg(key, round((value #>> '{}')::numeric * 100 / v_total, 2))
    INTO v_out FROM jsonb_each(v_out);
  RETURN v_out;
END; $$;

-- Shop config now exposes the normalized odds plus the raw flags/base weights.
CREATE OR REPLACE FUNCTION public.get_hero_shop_config()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'prices', jsonb_build_object(
      '1', public.hero_recruit_price(1),
      '5', public.hero_recruit_price(5),
      '10', public.hero_recruit_price(10)
    ),
    'odds', public.hero_effective_summon_odds(),
    'baseOdds', public.hero_summon_rates() - 'ancestral',
    'rarityEnabled', public.hero_recruit_rarity_flags(),
    'version', COALESCE((SELECT (value #>> '{}')::numeric FROM public.game_settings WHERE key = 'settings_version'), 1)
  );
$$;

-- Recruit uses the same effective odds, so a disabled rarity can never be rolled.
CREATE OR REPLACE FUNCTION public.recruit_heroes(p_telegram_id bigint, p_count integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  v_user uuid; v_cost numeric; i int; roll numeric; acc numeric; rarity_pick text;
  picked hero_catalog%rowtype; new_hero_id uuid; result jsonb := '[]'::jsonb;
  v_weights jsonb; v_total numeric := 0; r record;
begin
  if p_count not in (1,5,10) then raise exception 'Invalid recruitment count'; end if;

  v_cost := public.hero_recruit_price(p_count);
  if v_cost is null or v_cost <= 0 then raise exception 'invalid_recruit_price'; end if;

  -- server is the source of truth for which rarities may be summoned
  v_weights := public.hero_effective_summon_odds();
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

    -- double guard: never deliver a hero from a disabled rarity
    if not public.hero_rarity_recruitable(rarity_pick) then raise exception 'rarity_disabled:%', rarity_pick; end if;

    -- the hero keeps its own template rarity; we never rewrite it with the roll
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
end; $$;

-- Admin: read the rarity switchboard (flags + base weight + normalized weight + pool size).
CREATE OR REPLACE FUNCTION public.admin_hero_rarity_flags(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb; v_base jsonb; v_eff jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_base := public.hero_summon_rates();
  v_eff := public.hero_effective_summon_odds();
  SELECT jsonb_agg(jsonb_build_object(
      'rarity', r,
      'enabled', (public.hero_recruit_rarity_flags() -> r)::text::boolean,
      'base', COALESCE((v_base #>> ARRAY[r])::numeric, 0),
      'effective', COALESCE((v_eff #>> ARRAY[r])::numeric, 0),
      'heroes', (SELECT count(*) FROM public.hero_catalog c WHERE c.rarity = r AND c.enabled AND c.recruit_enabled)
    ) ORDER BY idx) INTO v
  FROM unnest(ARRAY['common','uncommon','rare','epic','legendary','mythic']) WITH ORDINALITY AS t(r, idx);
  RETURN jsonb_build_object('rarities', COALESCE(v, '[]'::jsonb), 'total_effective',
    COALESCE((SELECT sum((value #>> '{}')::numeric) FROM jsonb_each(v_eff)), 0));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_hero_rarity_enabled(p_admin_id bigint, p_rarity text, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_rarity text := lower(trim(coalesce(p_rarity, ''))); v_flags jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_rarity NOT IN ('common','uncommon','rare','epic','legendary','mythic') THEN
    RAISE EXCEPTION 'RARITY_NOT_TOGGLEABLE:%', v_rarity;
  END IF;
  v_flags := public.hero_recruit_rarity_flags() || jsonb_build_object(v_rarity, coalesce(p_enabled, true));

  -- at least one rarity with an actual hero pool must stay open
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_each(v_flags) f
     WHERE (f.value)::text::boolean
       AND COALESCE((public.hero_summon_rates() #>> ARRAY[f.key])::numeric, 0) > 0
       AND EXISTS (SELECT 1 FROM public.hero_catalog c WHERE c.rarity = f.key AND c.enabled AND c.recruit_enabled)
  ) THEN RAISE EXCEPTION 'LAST_ACTIVE_RARITY'; END IF;

  INSERT INTO public.game_settings(key, value) VALUES ('hero_recruit_rarity_enabled', v_flags)
    ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();
  PERFORM public.admin_bump_settings_version();
  PERFORM public.admin_log(p_admin_id, 'hero_rarity_toggle', 'game_settings', v_rarity,
    jsonb_build_object('enabled', coalesce(p_enabled, true)));
  RETURN public.admin_hero_rarity_flags(p_admin_id);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_hero_shop_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
    'config', public.get_hero_shop_config(),
    'rarity_flags', public.hero_recruit_rarity_flags(),
    'heroes_total', (SELECT count(*) FROM public.hero_catalog),
    'heroes_enabled', (SELECT count(*) FROM public.hero_catalog WHERE enabled),
    'by_rarity', COALESCE((SELECT jsonb_object_agg(rarity, c) FROM (
        SELECT rarity, count(*) c FROM public.hero_catalog WHERE enabled GROUP BY rarity) s), '{}'::jsonb)
  ) INTO v;
  RETURN v;
END; $$;

REVOKE ALL ON FUNCTION public.hero_recruit_rarity_flags() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_rarity_recruitable(text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_effective_summon_odds() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_rarity_flags(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_hero_rarity_enabled(bigint, text, boolean) FROM anon, authenticated;