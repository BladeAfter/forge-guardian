-- 1. hero_catalog fusion pool flag
ALTER TABLE public.hero_catalog ADD COLUMN IF NOT EXISTS fusion_pool_enabled boolean NOT NULL DEFAULT true;

-- 2. settings
INSERT INTO public.game_settings(key, value, category, label)
VALUES ('hero_rarity_fusion_config', jsonb_build_object(
  'enabled', true,
  'required_heroes', 5,
  'tiers', jsonb_build_object(
    'common',    jsonb_build_object('target','uncommon','cost_fc',10000,'chance',80,'fragments',10),
    'uncommon',  jsonb_build_object('target','rare','cost_fc',25000,'chance',60,'fragments',20),
    'rare',      jsonb_build_object('target','epic','cost_fc',60000,'chance',40,'fragments',40),
    'epic',      jsonb_build_object('target','legendary','cost_fc',150000,'chance',20,'fragments',80)
  )), 'heroes', 'Fusão por raridade (5 heróis)')
ON CONFLICT (key) DO NOTHING;

-- 3. history table
CREATE TABLE IF NOT EXISTS public.hero_rarity_fusion_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  source_rarity text NOT NULL,
  target_rarity text NOT NULL,
  selected_hero_ids uuid[] NOT NULL DEFAULT '{}',
  selected_hero_keys text[] NOT NULL DEFAULT '{}',
  fusion_cost_fc numeric NOT NULL DEFAULT 0,
  success_chance numeric NOT NULL DEFAULT 0,
  rng_roll numeric NOT NULL DEFAULT 0,
  success boolean NOT NULL DEFAULT false,
  reward_hero_id uuid,
  reward_hero_key text,
  reward_hero_name text,
  fragment_reward integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.hero_rarity_fusion_history TO service_role;
ALTER TABLE public.hero_rarity_fusion_history ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS hero_rarity_fusion_history_user_idx ON public.hero_rarity_fusion_history(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.hero_rarity_fusion_idempotency (
  key text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  result jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.hero_rarity_fusion_idempotency TO service_role;
ALTER TABLE public.hero_rarity_fusion_idempotency ENABLE ROW LEVEL SECURITY;

-- 4. config helper
CREATE OR REPLACE FUNCTION public.hero_rarity_fusion_config()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT value FROM public.game_settings WHERE key='hero_rarity_fusion_config'), '{}'::jsonb);
$$;

-- 5. dashboard
CREATE OR REPLACE FUNCTION public.get_rarity_fusion_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_bal numeric := 0; cfg jsonb := public.hero_rarity_fusion_config(); v_heroes jsonb; v_counts jsonb;
BEGIN
  SELECT id, forge_coins INTO v_user, v_bal FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb, 'counts', '{}'::jsonb);
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity,
      'level', ph.level, 'imageUrl', ph.image, 'stars', ph.fusion_level,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'locked', ph.locked,
      'equipped', (EXISTS(SELECT 1 FROM public.pvp_team_slots t WHERE t.hero_id = ph.id)
                OR EXISTS(SELECT 1 FROM public.boss_team_slots b WHERE b.player_hero_id = ph.id)),
      'exclusive', ph.is_season_exclusive
    ) ORDER BY ph.created_at DESC), '[]'::jsonb) INTO v_heroes
  FROM public.player_heroes ph WHERE ph.user_id = v_user;
  SELECT coalesce(jsonb_object_agg(rarity, n), '{}'::jsonb) INTO v_counts FROM (
    SELECT rarity, count(*) AS n FROM public.player_heroes WHERE user_id = v_user GROUP BY rarity
  ) s;
  RETURN jsonb_build_object(
    'config', cfg, 'balance', v_bal, 'heroes', v_heroes, 'counts', v_counts,
    'fragments', coalesce((SELECT quantity FROM public.player_inventory WHERE user_id = v_user AND item_type='fragments' AND item_code='fragments'), 0),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', h.id, 'sourceRarity', h.source_rarity, 'targetRarity', h.target_rarity,
        'success', h.success, 'costFc', h.fusion_cost_fc, 'chance', h.success_chance,
        'rewardHero', h.reward_hero_name, 'fragments', h.fragment_reward, 'createdAt', h.created_at
      ) ORDER BY h.created_at DESC) FROM (
        SELECT * FROM public.hero_rarity_fusion_history WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10
      ) h), '[]'::jsonb)
  );
END; $$;

-- 6. fusion execution
CREATE OR REPLACE FUNCTION public.fuse_heroes_by_rarity(p_telegram_id bigint, p_hero_ids uuid[], p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid; v_bal numeric; cfg jsonb := public.hero_rarity_fusion_config(); tier jsonb;
  ids uuid[]; v_required int; v_count int; v_src text; v_tgt text;
  v_cost numeric; v_chance numeric; v_frags int; v_roll numeric; v_success boolean;
  picked public.hero_catalog%rowtype; v_new_id uuid; v_after numeric; v_keys text[];
  v_existing jsonb; v_frag_total int := 0; v_result jsonb; v_new_row public.player_heroes%rowtype;
BEGIN
  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    SELECT result INTO v_existing FROM public.hero_rarity_fusion_idempotency WHERE key = p_idempotency_key;
    IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  END IF;

  IF coalesce((cfg->>'enabled')::boolean, true) IS NOT TRUE THEN RAISE EXCEPTION 'FUSION_DISABLED'; END IF;

  SELECT id, forge_coins INTO v_user, v_bal FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hero_rarity_fusion:' || v_user::text, 0));

  v_required := coalesce((cfg->>'required_heroes')::int, 5);
  SELECT array_agg(DISTINCT x) INTO ids FROM unnest(coalesce(p_hero_ids, '{}'::uuid[])) x;
  IF coalesce(array_length(ids,1),0) <> v_required THEN RAISE EXCEPTION 'NEED_EXACT_HEROES'; END IF;

  PERFORM 1 FROM public.player_heroes WHERE id = ANY(ids) ORDER BY id FOR UPDATE;

  SELECT count(*), array_agg(hero_key) INTO v_count, v_keys FROM public.player_heroes WHERE id = ANY(ids) AND user_id = v_user;
  IF v_count <> v_required THEN RAISE EXCEPTION 'HERO_NOT_OWNED'; END IF;

  IF EXISTS(SELECT 1 FROM public.player_heroes WHERE id = ANY(ids) AND locked) THEN RAISE EXCEPTION 'HERO_LOCKED'; END IF;
  IF EXISTS(SELECT 1 FROM public.pvp_team_slots WHERE hero_id = ANY(ids)) THEN RAISE EXCEPTION 'HERO_EQUIPPED'; END IF;
  IF EXISTS(SELECT 1 FROM public.boss_team_slots WHERE player_hero_id = ANY(ids)) THEN RAISE EXCEPTION 'HERO_EQUIPPED'; END IF;

  SELECT count(DISTINCT rarity), min(rarity) INTO v_count, v_src FROM public.player_heroes WHERE id = ANY(ids);
  IF v_count <> 1 THEN RAISE EXCEPTION 'RARITY_MISMATCH'; END IF;

  tier := cfg->'tiers'->v_src;
  IF tier IS NULL THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  v_tgt := tier->>'target';
  v_cost := coalesce((tier->>'cost_fc')::numeric, 0);
  v_chance := least(100, greatest(0, coalesce((tier->>'chance')::numeric, 0)));
  v_frags := greatest(0, coalesce((tier->>'fragments')::int, 0));
  IF v_tgt IS NULL THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  IF v_bal < v_cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FC'; END IF;

  v_roll := random() * 100;
  v_success := v_roll < v_chance;

  IF v_success THEN
    SELECT * INTO picked FROM public.hero_catalog
      WHERE enabled AND fusion_pool_enabled AND rarity = v_tgt ORDER BY random() LIMIT 1;
    IF picked.hero_key IS NULL THEN RAISE EXCEPTION 'NO_ELIGIBLE_HERO'; END IF;
  END IF;

  UPDATE public.game_players SET forge_coins = forge_coins - v_cost, updated_at = now()
    WHERE id = v_user RETURNING forge_coins INTO v_after;

  DELETE FROM public.hero_combat_state WHERE hero_id = ANY(ids);
  DELETE FROM public.player_heroes WHERE id = ANY(ids) AND user_id = v_user;

  IF v_success THEN
    INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image)
      VALUES (v_user, picked.hero_key, picked.name, public.normalize_hero_rarity(picked.rarity), 1, picked.image)
      RETURNING id INTO v_new_id;
    SELECT * INTO v_new_row FROM public.player_heroes WHERE id = v_new_id;
  ELSE
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity, updated_at)
      VALUES (v_user, 'fragments', 'fragments', v_frags, now())
      ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + v_frags, updated_at = now()
      RETURNING quantity INTO v_frag_total;
  END IF;

  INSERT INTO public.hero_rarity_fusion_history(user_id, source_rarity, target_rarity, selected_hero_ids, selected_hero_keys,
      fusion_cost_fc, success_chance, rng_roll, success, reward_hero_id, reward_hero_key, reward_hero_name, fragment_reward)
    VALUES (v_user, v_src, v_tgt, ids, coalesce(v_keys,'{}'), v_cost, v_chance, v_roll, v_success,
      v_new_id, picked.hero_key, picked.name, CASE WHEN v_success THEN 0 ELSE v_frags END);

  v_result := jsonb_build_object(
    'success', v_success, 'sourceRarity', v_src, 'targetRarity', v_tgt,
    'costFc', v_cost, 'chance', v_chance, 'balance', v_after,
    'consumed', v_required,
    'fragments', CASE WHEN v_success THEN 0 ELSE v_frags END,
    'fragmentsTotal', v_frag_total,
    'hero', CASE WHEN v_success THEN jsonb_build_object(
        'heroId', v_new_id, 'heroKey', v_new_row.hero_key, 'name', v_new_row.name, 'rarity', v_new_row.rarity,
        'level', v_new_row.level, 'imageUrl', v_new_row.image,
        'finalAtk', round(v_new_row.final_atk), 'finalHp', round(v_new_row.final_hp),
        'power', round(v_new_row.final_atk * 2 + v_new_row.final_hp)) ELSE NULL END
  );

  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    INSERT INTO public.hero_rarity_fusion_idempotency(key, user_id, result)
      VALUES (p_idempotency_key, v_user, v_result) ON CONFLICT (key) DO NOTHING;
  END IF;

  RETURN v_result || jsonb_build_object('dashboard', public.get_rarity_fusion_dashboard(p_telegram_id));
END; $$;

-- 7. admin functions
CREATE OR REPLACE FUNCTION public.admin_rarity_fusion_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  cfg := public.hero_rarity_fusion_config();
  RETURN jsonb_build_object(
    'config', cfg,
    'attempts', (SELECT count(*) FROM public.hero_rarity_fusion_history),
    'successes', (SELECT count(*) FROM public.hero_rarity_fusion_history WHERE success),
    'fcBurned', coalesce((SELECT sum(fusion_cost_fc) FROM public.hero_rarity_fusion_history), 0),
    'pool', coalesce((SELECT jsonb_agg(jsonb_build_object('heroKey', hero_key, 'name', name, 'rarity', rarity, 'enabled', fusion_pool_enabled) ORDER BY rarity, name)
                      FROM public.hero_catalog WHERE enabled), '[]'::jsonb));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_rarity_fusion_tier(p_admin_id bigint, p_source text, p_cost numeric DEFAULT NULL, p_chance numeric DEFAULT NULL, p_fragments integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg jsonb; tier jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  cfg := public.hero_rarity_fusion_config();
  tier := cfg->'tiers'->p_source;
  IF tier IS NULL THEN RAISE EXCEPTION 'INVALID_SOURCE_RARITY'; END IF;
  IF p_cost IS NOT NULL THEN tier := tier || jsonb_build_object('cost_fc', greatest(0, p_cost)); END IF;
  IF p_chance IS NOT NULL THEN tier := tier || jsonb_build_object('chance', least(100, greatest(0, p_chance))); END IF;
  IF p_fragments IS NOT NULL THEN tier := tier || jsonb_build_object('fragments', greatest(0, p_fragments)); END IF;
  cfg := jsonb_set(cfg, ARRAY['tiers', p_source], tier);
  PERFORM public.admin_set_setting(p_admin_id, 'hero_rarity_fusion_config', cfg, 'fusão por raridade (bot)');
  RETURN cfg;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_rarity_fusion_enabled(p_admin_id bigint, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  cfg := public.hero_rarity_fusion_config() || jsonb_build_object('enabled', p_enabled);
  PERFORM public.admin_set_setting(p_admin_id, 'hero_rarity_fusion_config', cfg, 'fusão por raridade on/off (bot)');
  RETURN cfg;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_hero_fusion_pool(p_admin_id bigint, p_hero_key text, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.hero_catalog;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.hero_catalog SET fusion_pool_enabled = p_enabled, updated_at = now() WHERE hero_key = p_hero_key RETURNING * INTO c;
  IF c.hero_key IS NULL THEN RAISE EXCEPTION 'hero_not_found'; END IF;
  PERFORM public.admin_log(p_admin_id, 'hero.fusion_pool', 'hero', p_hero_key, NULL, jsonb_build_object('enabled', p_enabled), 'fusion pool (bot)');
  RETURN jsonb_build_object('heroKey', c.hero_key, 'name', c.name, 'rarity', c.rarity, 'enabled', c.fusion_pool_enabled);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_rarity_fusion_audit(p_admin_id bigint, p_limit integer DEFAULT 10, p_ref text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_ref IS NOT NULL AND length(p_ref) > 0 THEN v_uid := public.admin_resolve_player(p_ref); END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id', h.id, 'player', p.username, 'telegramId', p.telegram_id, 'name', p.first_name,
      'sourceRarity', h.source_rarity, 'targetRarity', h.target_rarity, 'heroes', array_length(h.selected_hero_ids, 1),
      'costFc', h.fusion_cost_fc, 'chance', h.success_chance, 'roll', round(h.rng_roll, 2), 'success', h.success,
      'rewardHero', h.reward_hero_name, 'rewardHeroId', h.reward_hero_id, 'fragments', h.fragment_reward,
      'createdAt', h.created_at) ORDER BY h.created_at DESC)
    FROM (SELECT * FROM public.hero_rarity_fusion_history
          WHERE v_uid IS NULL OR user_id = v_uid
          ORDER BY created_at DESC LIMIT greatest(1, least(25, coalesce(p_limit, 10)))) h
    JOIN public.game_players p ON p.id = h.user_id), '[]'::jsonb);
END; $$;