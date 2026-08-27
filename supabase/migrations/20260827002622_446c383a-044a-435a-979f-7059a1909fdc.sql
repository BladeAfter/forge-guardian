CREATE OR REPLACE FUNCTION public.admin_set_rarity_fusion_tier(
  p_admin_id bigint, p_source text, p_cost numeric DEFAULT NULL,
  p_chance numeric DEFAULT NULL, p_fragments integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg jsonb; tier jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  cfg := public.hero_rarity_fusion_config();
  tier := cfg->'tiers'->p_source;
  IF tier IS NULL THEN RAISE EXCEPTION 'INVALID_SOURCE_RARITY'; END IF;
  IF p_cost IS NOT NULL THEN tier := tier || jsonb_build_object('cost_myth', greatest(0, p_cost), 'cost_fc', 0); END IF;
  IF p_chance IS NOT NULL THEN tier := tier || jsonb_build_object('chance', least(100, greatest(0, p_chance))); END IF;
  IF p_fragments IS NOT NULL THEN tier := tier || jsonb_build_object('fragments', greatest(0, p_fragments)); END IF;
  cfg := jsonb_set(cfg, ARRAY['tiers', p_source], tier);
  PERFORM public.admin_set_setting(p_admin_id, 'hero_rarity_fusion_config', cfg, 'fusão por raridade (bot)');
  RETURN cfg;
END; $$;

CREATE OR REPLACE FUNCTION public.get_rarity_fusion_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_bal numeric := 0; cfg jsonb := public.hero_rarity_fusion_config(); v_heroes jsonb; v_counts jsonb;
        v_myth numeric := 0; v_staked numeric := 0;
BEGIN
  SELECT id, forge_coins INTO v_user, v_bal FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb, 'counts', '{}'::jsonb,
      'mythBalance', 0, 'mythAvailable', 0);
  END IF;
  SELECT coalesce(amount, 0) INTO v_myth FROM public.myth_balances WHERE user_id = v_user;
  v_staked := coalesce(public.myth_staked_amount(v_user), 0);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity,
      'level', ph.level, 'imageUrl', ph.image, 'stars', ph.fusion_level,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'locked', ph.locked,
      'equipped', NOT coalesce((us.usage->>'canFuse')::boolean, false) AND NOT coalesce(ph.locked,false),
      'usage', us.usage,
      'lockReason', us.usage->>'reason',
      'exclusive', ph.is_season_exclusive
    ) ORDER BY ph.created_at DESC), '[]'::jsonb) INTO v_heroes
  FROM public.player_heroes ph
  CROSS JOIN LATERAL (SELECT public.hero_usage_status(ph.id) AS usage) us
  WHERE ph.user_id = v_user AND NOT ph.is_nft_exclusive;
  SELECT coalesce(jsonb_object_agg(rarity, n), '{}'::jsonb) INTO v_counts FROM (
    SELECT rarity, count(*) AS n FROM public.player_heroes WHERE user_id = v_user AND NOT is_nft_exclusive GROUP BY rarity
  ) s;
  RETURN jsonb_build_object(
    'config', cfg, 'balance', v_bal, 'heroes', v_heroes, 'counts', v_counts,
    'mythBalance', coalesce(v_myth, 0),
    'mythAvailable', greatest(0, coalesce(v_myth, 0) - v_staked),
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

CREATE OR REPLACE FUNCTION public.fuse_heroes_by_rarity(
  p_telegram_id bigint, p_hero_ids uuid[], p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid; v_bal numeric; cfg jsonb := public.hero_rarity_fusion_config(); tier jsonb;
  ids uuid[]; v_required int; v_count int; v_src text; v_tgt text;
  v_cost_myth numeric; v_chance numeric; v_frags int; v_roll numeric; v_success boolean;
  picked public.hero_catalog%rowtype; v_new_id uuid; v_keys text[];
  v_existing jsonb; v_frag_total int := 0; v_result jsonb; v_new_row public.player_heroes%rowtype;
  v_blocked uuid; v_charge jsonb; v_myth_after numeric;
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

  IF EXISTS(SELECT 1 FROM public.player_heroes WHERE id = ANY(ids) AND is_nft_exclusive) THEN RAISE EXCEPTION 'NFT_HERO_UNIQUE'; END IF;
  IF EXISTS(SELECT 1 FROM public.player_heroes WHERE id = ANY(ids) AND locked) THEN RAISE EXCEPTION 'HERO_LOCKED'; END IF;

  SELECT x INTO v_blocked FROM unnest(ids) x
   WHERE NOT public.hero_fusion_material_available(x) LIMIT 1;
  IF v_blocked IS NOT NULL THEN RAISE EXCEPTION 'HERO_EQUIPPED'; END IF;

  SELECT count(DISTINCT rarity), min(rarity) INTO v_count, v_src FROM public.player_heroes WHERE id = ANY(ids);
  IF v_count <> 1 THEN RAISE EXCEPTION 'RARITY_MISMATCH'; END IF;

  tier := cfg->'tiers'->v_src;
  IF tier IS NULL THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  v_tgt := tier->>'target';
  v_cost_myth := ceil(coalesce((tier->>'cost_myth')::numeric, 0));
  v_chance := least(100, greatest(0, coalesce((tier->>'chance')::numeric, 0)));
  v_frags := greatest(0, coalesce((tier->>'fragments')::int, 0));
  IF v_tgt IS NULL OR v_tgt = 'nft_exclusive' THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  IF v_cost_myth <= 0 THEN RAISE EXCEPTION 'MYTH_INVALID_AMOUNT'; END IF;

  v_charge := public.myth_utility_charge(
    v_user, 'HERO_UPGRADE', v_cost_myth, 'rarity_fusion:' || v_src,
    coalesce(p_idempotency_key, 'rarity_fusion:' || v_user::text || ':' || clock_timestamp()::text),
    jsonb_build_object('sourceRarity', v_src, 'targetRarity', v_tgt, 'heroes', to_jsonb(ids)));
  v_myth_after := coalesce((v_charge->>'balanceAfter')::numeric, 0);

  v_roll := random() * 100;
  v_success := v_roll < v_chance;

  IF v_success THEN
    SELECT * INTO picked FROM public.hero_catalog
      WHERE enabled AND fusion_pool_enabled AND NOT is_nft_exclusive AND rarity = v_tgt ORDER BY random() LIMIT 1;
    IF picked.hero_key IS NULL THEN RAISE EXCEPTION 'NO_ELIGIBLE_HERO'; END IF;
  END IF;

  DELETE FROM public.hero_combat_state WHERE hero_id = ANY(ids);
  DELETE FROM public.player_heroes WHERE id = ANY(ids) AND user_id = v_user;

  IF v_success THEN
    INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image)
      VALUES (v_user, picked.hero_key, picked.name, public.normalize_hero_rarity(picked.rarity), 1, picked.image)
      RETURNING id INTO v_new_id;
    SELECT * INTO v_new_row FROM public.player_heroes WHERE id = v_new_id;
  ELSE
    INSERT INTO public.player_inventory AS inv (user_id, item_type, item_code, quantity, updated_at)
      VALUES (v_user, 'fragments', 'fragments', v_frags, now())
      ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = inv.quantity + v_frags, updated_at = now()
      RETURNING inv.quantity INTO v_frag_total;
  END IF;

  INSERT INTO public.hero_rarity_fusion_history(user_id, source_rarity, target_rarity, selected_hero_ids, selected_hero_keys,
      success, success_chance, rng_roll, fusion_cost_fc, reward_hero_key, reward_hero_name, reward_hero_id, fragment_reward)
    VALUES (v_user, v_src, v_tgt, ids, v_keys, v_success, v_chance, v_roll, 0,
      CASE WHEN v_success THEN picked.hero_key END, CASE WHEN v_success THEN picked.name END, v_new_id,
      CASE WHEN v_success THEN 0 ELSE v_frags END);

  v_result := jsonb_build_object(
    'success', v_success, 'sourceRarity', v_src, 'targetRarity', v_tgt,
    'costFc', 0, 'costMyth', v_cost_myth, 'chance', v_chance, 'balance', v_bal, 'consumed', v_required,
    'mythBalance', v_myth_after,
    'fragments', CASE WHEN v_success THEN 0 ELSE v_frags END,
    'fragmentsTotal', coalesce(v_frag_total, (SELECT quantity FROM public.player_inventory WHERE user_id = v_user AND item_type='fragments' AND item_code='fragments'), 0),
    'hero', CASE WHEN v_success THEN jsonb_build_object(
        'heroId', v_new_row.id, 'heroKey', v_new_row.hero_key, 'name', v_new_row.name, 'rarity', v_new_row.rarity,
        'level', v_new_row.level, 'imageUrl', v_new_row.image,
        'finalAtk', round(v_new_row.final_atk), 'finalHp', round(v_new_row.final_hp),
        'power', round(v_new_row.final_atk * 2 + v_new_row.final_hp)) END,
    'dashboard', public.get_rarity_fusion_dashboard(p_telegram_id)
  );

  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    INSERT INTO public.hero_rarity_fusion_idempotency(key, user_id, result)
      VALUES (p_idempotency_key, v_user, v_result) ON CONFLICT (key) DO NOTHING;
  END IF;

  RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.fuse_heroes_by_rarity(bigint, uuid[], text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_rarity_fusion_dashboard(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_rarity_fusion_tier(bigint, text, numeric, numeric, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fuse_heroes_by_rarity(bigint, uuid[], text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_rarity_fusion_dashboard(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_rarity_fusion_tier(bigint, text, numeric, numeric, integer) TO service_role;