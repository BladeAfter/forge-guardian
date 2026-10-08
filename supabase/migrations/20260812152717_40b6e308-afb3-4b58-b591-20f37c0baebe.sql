-- 1) hero_catalog.recruit_enabled ------------------------------------------------
ALTER TABLE public.hero_catalog
  ADD COLUMN IF NOT EXISTS recruit_enabled boolean NOT NULL DEFAULT true;

UPDATE public.hero_catalog SET recruit_enabled = false WHERE rarity = 'ancestral';

CREATE OR REPLACE FUNCTION public.hero_catalog_enforce_recruit_flag()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.rarity := public.normalize_hero_rarity(NEW.rarity);
  IF NEW.rarity = 'ancestral' THEN NEW.recruit_enabled := false; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hero_catalog_recruit_flag ON public.hero_catalog;
CREATE TRIGGER trg_hero_catalog_recruit_flag
  BEFORE INSERT OR UPDATE ON public.hero_catalog
  FOR EACH ROW EXECUTE FUNCTION public.hero_catalog_enforce_recruit_flag();

-- 2) audit table for rarity mismatches -------------------------------------------
CREATE TABLE IF NOT EXISTS public.hero_rarity_mismatch_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_hero_id uuid NOT NULL,
  user_id uuid,
  hero_key text NOT NULL,
  template_rarity text NOT NULL,
  owned_rarity text NOT NULL,
  flag text NOT NULL DEFAULT 'RARITY_MISMATCH',
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.hero_rarity_mismatch_audit TO service_role;
ALTER TABLE public.hero_rarity_mismatch_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "no client access to rarity audit" ON public.hero_rarity_mismatch_audit;
CREATE POLICY "no client access to rarity audit" ON public.hero_rarity_mismatch_audit
  FOR SELECT TO authenticated USING (false);

-- 3) admin_upsert_hero: never silently reset rarity to common ---------------------
CREATE OR REPLACE FUNCTION public.admin_upsert_hero(p_admin_id bigint, p_hero_key text, p_patch jsonb, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_old jsonb; v_new jsonb; v_rarity text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF COALESCE(btrim(p_hero_key),'') = '' THEN RAISE EXCEPTION 'invalid_key'; END IF;

  -- rarity belongs to the hero template: only change it when explicitly provided
  v_rarity := CASE
    WHEN p_patch ? 'rarity' AND COALESCE(btrim(p_patch->>'rarity'),'') <> ''
      THEN public.normalize_hero_rarity(p_patch->>'rarity')
    ELSE NULL END;

  SELECT to_jsonb(c) INTO v_old FROM public.hero_catalog c WHERE c.hero_key = p_hero_key;

  IF v_old IS NULL THEN
    INSERT INTO public.hero_catalog (hero_key, name, rarity, image, enabled)
    VALUES (p_hero_key, COALESCE(p_patch->>'name', p_hero_key),
            COALESCE(v_rarity, 'common'),
            COALESCE(p_patch->>'image',''), COALESCE((p_patch->>'enabled')::boolean, true));
  END IF;

  UPDATE public.hero_catalog c SET
    name = COALESCE(p_patch->>'name', c.name),
    description = COALESCE(p_patch->>'description', c.description),
    image = COALESCE(p_patch->>'image', c.image),
    battle_image = COALESCE(p_patch->>'battle_image', c.battle_image),
    rarity = COALESCE(v_rarity, c.rarity),
    hero_class = COALESCE(p_patch->>'hero_class', c.hero_class),
    base_atk = COALESCE((p_patch->>'base_atk')::numeric, c.base_atk),
    base_hp = COALESCE((p_patch->>'base_hp')::numeric, c.base_hp),
    power = COALESCE((p_patch->>'power')::numeric, c.power),
    start_level = COALESCE((p_patch->>'start_level')::int, c.start_level),
    max_level = COALESCE((p_patch->>'max_level')::int, c.max_level),
    price_fc = COALESCE((p_patch->>'price_fc')::numeric, c.price_fc),
    price_ton = COALESCE((p_patch->>'price_ton')::numeric, c.price_ton),
    discount_percent = COALESCE((p_patch->>'discount_percent')::numeric, c.discount_percent),
    drop_weight = COALESCE((p_patch->>'drop_weight')::numeric, c.drop_weight),
    stock = COALESCE((p_patch->>'stock')::int, c.stock),
    per_player_limit = COALESCE((p_patch->>'per_player_limit')::int, c.per_player_limit),
    featured = COALESCE((p_patch->>'featured')::boolean, c.featured),
    in_shop = COALESCE((p_patch->>'in_shop')::boolean, c.in_shop),
    enabled = COALESCE((p_patch->>'enabled')::boolean, c.enabled),
    recruit_enabled = COALESCE((p_patch->>'recruit_enabled')::boolean, c.recruit_enabled),
    sort_order = COALESCE((p_patch->>'sort_order')::int, c.sort_order),
    available_from = COALESCE((p_patch->>'available_from')::timestamptz, c.available_from),
    available_until = COALESCE((p_patch->>'available_until')::timestamptz, c.available_until),
    buffs = COALESCE(p_patch->'buffs', c.buffs),
    skills = COALESCE(p_patch->'skills', c.skills),
    updated_at = now()
  WHERE c.hero_key = p_hero_key;

  SELECT to_jsonb(c) INTO v_new FROM public.hero_catalog c WHERE c.hero_key = p_hero_key;
  PERFORM public.admin_log(p_admin_id, CASE WHEN v_old IS NULL THEN 'hero.create' ELSE 'hero.update' END,'hero',p_hero_key,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END;
$function$;

-- 4) recruit rates: ancestral is never summonable, config validated --------------
CREATE OR REPLACE FUNCTION public.hero_summon_rates()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT COALESCE(
    (SELECT value FROM public.game_settings WHERE key = 'hero_summon_rates'),
    '{"common":61.7,"uncommon":25,"rare":10,"epic":2.7,"legendary":0.3,"mythic":0.3,"ancestral":0}'::jsonb
  ) - 'ancestral' || jsonb_build_object('ancestral', 0);
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_hero_summon_rates(p_admin_id bigint, p_rates jsonb, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_allowed text[] := ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral'];
  v_total numeric := 0; k text; v numeric; v_old jsonb; v_final jsonb := '{}'::jsonb; v_pool int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  FOR k, v IN SELECT key, (value #>> '{}')::numeric FROM jsonb_each(p_rates) LOOP
    IF NOT (k = ANY(v_allowed)) THEN RAISE EXCEPTION 'invalid_rarity:%', k; END IF;
    IF v IS NULL OR v < 0 OR v > 100 THEN RAISE EXCEPTION 'invalid_rate:%', k; END IF;
    IF k = 'ancestral' AND v <> 0 THEN RAISE EXCEPTION 'ancestral_not_summonable'; END IF;
    IF v > 0 THEN
      SELECT count(*) INTO v_pool FROM public.hero_catalog
       WHERE rarity = k AND enabled AND recruit_enabled;
      IF v_pool = 0 THEN RAISE EXCEPTION 'empty_pool_for_rarity:%', k; END IF;
    END IF;
    v_total := v_total + v;
    v_final := v_final || jsonb_build_object(k, round(v, 4));
  END LOOP;

  IF (SELECT count(*) FROM jsonb_object_keys(v_final)) <> array_length(v_allowed, 1) THEN
    RAISE EXCEPTION 'missing_rarities';
  END IF;
  IF abs(v_total - 100) > 0.001 THEN
    RAISE EXCEPTION 'rates_must_total_100:%', v_total;
  END IF;

  SELECT value INTO v_old FROM public.game_settings WHERE key = 'hero_summon_rates';
  INSERT INTO public.game_settings (key, value, category, label, updated_at, updated_by)
  VALUES ('hero_summon_rates', v_final, 'heroes', 'Chances de invocação por raridade (%)', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;

  PERFORM public.admin_log(p_admin_id, 'hero.summon_rates', 'setting', 'hero_summon_rates', v_old, v_final, p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN public.get_hero_shop_config();
END;
$function$;

-- odds exposed to the client never include ancestral
CREATE OR REPLACE FUNCTION public.get_hero_shop_config()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT jsonb_build_object(
    'prices', jsonb_build_object(
      '1', public.hero_recruit_price(1),
      '5', public.hero_recruit_price(5),
      '10', public.hero_recruit_price(10)
    ),
    'odds', public.hero_summon_rates() - 'ancestral',
    'version', COALESCE((SELECT (value #>> '{}')::numeric FROM public.game_settings WHERE key = 'settings_version'), 1)
  );
$function$;

-- 5) recruit: roll a rarity, then pick a hero of exactly that rarity -------------
CREATE OR REPLACE FUNCTION public.recruit_heroes(p_telegram_id bigint, p_count integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare
  v_user uuid; v_cost numeric; i int; roll numeric; acc numeric; rarity_pick text;
  picked hero_catalog%rowtype; new_hero_id uuid; result jsonb := '[]'::jsonb;
  v_weights jsonb := '{}'::jsonb; v_total numeric := 0; r record;
begin
  if p_count not in (1,5,10) then raise exception 'Invalid recruitment count'; end if;

  v_cost := public.hero_recruit_price(p_count);
  if v_cost is null or v_cost <= 0 then raise exception 'invalid_recruit_price'; end if;

  -- only rarities that are summonable AND actually have eligible heroes take part
  for r in
    select e.key as rarity, (e.value #>> '{}')::numeric as chance
      from jsonb_each(public.hero_summon_rates()) e
     where e.key <> 'ancestral'
       and (e.value #>> '{}')::numeric > 0
       and exists (select 1 from hero_catalog c
                    where c.rarity = e.key and c.enabled and c.recruit_enabled)
  loop
    v_weights := v_weights || jsonb_build_object(r.rarity, r.chance);
    v_total := v_total + r.chance;
  end loop;

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
end;
$function$;