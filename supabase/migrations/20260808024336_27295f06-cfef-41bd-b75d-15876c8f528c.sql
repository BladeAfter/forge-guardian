-- 1. Default settings for hero shop -------------------------------------------------
INSERT INTO public.game_settings (key, value, category, label)
VALUES
  ('hero_recruit_price_1x', '25000'::jsonb, 'heroes', 'Preço do recrutamento 1x (FC)'),
  ('hero_recruit_price_5x', '125000'::jsonb, 'heroes', 'Preço do recrutamento 5x (FC)'),
  ('hero_recruit_price_10x', '250000'::jsonb, 'heroes', 'Preço do recrutamento 10x (FC)'),
  ('hero_summon_rates', '{"common":62,"uncommon":25,"rare":10,"epic":2.7,"legendary":0.3}'::jsonb, 'heroes', 'Chances de invocação por raridade (%)')
ON CONFLICT (key) DO NOTHING;

-- 2. Read helpers --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hero_recruit_price(p_count integer)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT (value #>> '{}')::numeric FROM public.game_settings
      WHERE key = 'hero_recruit_price_' || p_count::text || 'x'),
    25000 * p_count
  );
$$;

CREATE OR REPLACE FUNCTION public.hero_summon_rates()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT value FROM public.game_settings WHERE key = 'hero_summon_rates'),
    '{"common":62,"uncommon":25,"rare":10,"epic":2.7,"legendary":0.3}'::jsonb
  );
$$;

CREATE OR REPLACE FUNCTION public.get_hero_shop_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'prices', jsonb_build_object(
      '1', public.hero_recruit_price(1),
      '5', public.hero_recruit_price(5),
      '10', public.hero_recruit_price(10)
    ),
    'odds', public.hero_summon_rates(),
    'version', COALESCE((SELECT (value #>> '{}')::numeric FROM public.game_settings WHERE key = 'settings_version'), 1)
  );
$$;

-- 3. Recruitment now reads prices and odds from settings -----------------------------
CREATE OR REPLACE FUNCTION public.recruit_heroes(p_telegram_id bigint, p_count integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  v_user uuid; v_cost numeric; i int; roll numeric; acc numeric; rarity_pick text;
  picked hero_catalog%rowtype; new_hero_id uuid; result jsonb := '[]'::jsonb;
  v_rates jsonb; v_total numeric; r record;
begin
  if p_count not in (1,5,10) then raise exception 'Invalid recruitment count'; end if;

  v_cost := public.hero_recruit_price(p_count);
  if v_cost is null or v_cost <= 0 then raise exception 'invalid_recruit_price'; end if;

  v_rates := public.hero_summon_rates();
  select sum((value #>> '{}')::numeric) into v_total from jsonb_each(v_rates);
  if v_total is null or v_total <= 0 then
    v_rates := '{"common":62,"uncommon":25,"rare":10,"epic":2.7,"legendary":0.3}'::jsonb;
    v_total := 100;
  end if;

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
    rarity_pick := 'common';
    for r in
      select key, (value #>> '{}')::numeric as chance
      from jsonb_each(v_rates)
      order by (value #>> '{}')::numeric asc, key asc
    loop
      acc := acc + r.chance;
      if roll < acc then rarity_pick := r.key; exit; end if;
    end loop;

    select * into picked from hero_catalog where rarity = rarity_pick and enabled order by random() limit 1;
    if picked.hero_key is null then
      select * into picked from hero_catalog where enabled order by random() limit 1;
    end if;
    if picked.hero_key is null then raise exception 'hero_catalog_empty'; end if;

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
end;
$$;

-- 4. Admin mutations -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_hero_recruit_price(
  p_admin_id bigint, p_count integer, p_price numeric, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_key text; v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_count NOT IN (1,5,10) THEN RAISE EXCEPTION 'invalid_count'; END IF;
  IF p_price IS NULL OR p_price < 1 OR p_price > 1000000000 THEN RAISE EXCEPTION 'invalid_price'; END IF;

  v_key := 'hero_recruit_price_' || p_count::text || 'x';
  SELECT value INTO v_old FROM public.game_settings WHERE key = v_key;

  INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
  VALUES (v_key, to_jsonb(round(p_price)), 'heroes',
          'Preço do recrutamento ' || p_count::text || 'x (FC)', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;

  PERFORM public.admin_log(p_admin_id, 'hero.recruit_price', 'setting', v_key,
                           v_old, to_jsonb(round(p_price)), p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN public.get_hero_shop_config();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_hero_summon_rates(
  p_admin_id bigint, p_rates jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[] := ARRAY['common','uncommon','rare','epic','legendary'];
  v_total numeric := 0; k text; v numeric; v_old jsonb; v_final jsonb := '{}'::jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  FOR k, v IN SELECT key, (value #>> '{}')::numeric FROM jsonb_each(p_rates) LOOP
    IF NOT (k = ANY(v_allowed)) THEN RAISE EXCEPTION 'invalid_rarity:%', k; END IF;
    IF v IS NULL OR v < 0 OR v > 100 THEN RAISE EXCEPTION 'invalid_rate:%', k; END IF;
    v_total := v_total + v;
    v_final := v_final || jsonb_build_object(k, round(v, 4));
  END LOOP;

  IF (SELECT count(*) FROM jsonb_object_keys(v_final)) <> 5 THEN
    RAISE EXCEPTION 'missing_rarities';
  END IF;
  IF abs(v_total - 100) > 0.001 THEN
    RAISE EXCEPTION 'rates_must_total_100:%', v_total;
  END IF;

  SELECT value INTO v_old FROM public.game_settings WHERE key = 'hero_summon_rates';
  INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
  VALUES ('hero_summon_rates', v_final, 'heroes', 'Chances de invocação por raridade (%)', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;

  PERFORM public.admin_log(p_admin_id, 'hero.summon_rates', 'setting', 'hero_summon_rates',
                           v_old, v_final, p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN public.get_hero_shop_config();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reset_hero_shop(p_admin_id bigint, p_scope text DEFAULT 'prices')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_scope IN ('prices','all') THEN
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 1, 25000, 'reset_default');
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 5, 125000, 'reset_default');
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 10, 250000, 'reset_default');
  END IF;
  IF p_scope IN ('odds','all') THEN
    PERFORM public.admin_set_hero_summon_rates(
      p_admin_id,
      '{"common":62,"uncommon":25,"rare":10,"epic":2.7,"legendary":0.3}'::jsonb,
      'reset_default');
  END IF;
  RETURN public.get_hero_shop_config();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_hero_shop_overview(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
    'config', public.get_hero_shop_config(),
    'heroes_total', (SELECT count(*) FROM public.hero_catalog),
    'heroes_enabled', (SELECT count(*) FROM public.hero_catalog WHERE enabled),
    'by_rarity', COALESCE((SELECT jsonb_object_agg(rarity, c) FROM (
        SELECT rarity, count(*) c FROM public.hero_catalog WHERE enabled GROUP BY rarity) s), '{}'::jsonb)
  ) INTO v;
  RETURN v;
END;
$$;

-- 5. Execution privileges: backend/admin only ---------------------------------------
REVOKE ALL ON FUNCTION public.hero_recruit_price(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_summon_rates() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_hero_shop_config() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.recruit_heroes(bigint, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_hero_recruit_price(bigint, integer, numeric, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_hero_summon_rates(bigint, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_reset_hero_shop(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_shop_overview(bigint) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.hero_recruit_price(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_summon_rates() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_hero_shop_config() TO service_role;
GRANT EXECUTE ON FUNCTION public.recruit_heroes(bigint, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_hero_recruit_price(bigint, integer, numeric, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_hero_summon_rates(bigint, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_reset_hero_shop(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_shop_overview(bigint) TO service_role;