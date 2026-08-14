CREATE OR REPLACE FUNCTION public.fuse_heroes_by_rarity(p_telegram_id bigint, p_hero_ids uuid[], p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid; v_bal numeric; cfg jsonb := public.hero_rarity_fusion_config(); tier jsonb;
  ids uuid[]; v_required int; v_count int; v_src text; v_tgt text;
  v_cost numeric; v_chance numeric; v_frags int; v_roll numeric; v_success boolean;
  picked public.hero_catalog%rowtype; v_new_id uuid; v_after numeric; v_keys text[];
  v_existing jsonb; v_frag_total int := 0; v_result jsonb; v_new_row public.player_heroes%rowtype;
  v_blocked uuid;
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
  v_cost := coalesce((tier->>'cost_fc')::numeric, 0);
  v_chance := least(100, greatest(0, coalesce((tier->>'chance')::numeric, 0)));
  v_frags := greatest(0, coalesce((tier->>'fragments')::int, 0));
  IF v_tgt IS NULL OR v_tgt = 'nft_exclusive' THEN RAISE EXCEPTION 'MAX_FUSION_RARITY'; END IF;
  IF v_bal < v_cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FC'; END IF;

  v_roll := random() * 100;
  v_success := v_roll < v_chance;

  IF v_success THEN
    SELECT * INTO picked FROM public.hero_catalog
      WHERE enabled AND fusion_pool_enabled AND NOT is_nft_exclusive AND rarity = v_tgt ORDER BY random() LIMIT 1;
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
    INSERT INTO public.player_inventory AS inv (user_id, item_type, item_code, quantity, updated_at)
      VALUES (v_user, 'fragments', 'fragments', v_frags, now())
      ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = inv.quantity + v_frags, updated_at = now()
      RETURNING inv.quantity INTO v_frag_total;
  END IF;

  INSERT INTO public.hero_rarity_fusion_history(user_id, source_rarity, target_rarity, selected_hero_ids, selected_hero_keys,
      success, success_chance, rng_roll, fusion_cost_fc, reward_hero_key, reward_hero_name, reward_hero_id, fragment_reward)
    VALUES (v_user, v_src, v_tgt, ids, v_keys, v_success, v_chance, v_roll, v_cost,
      CASE WHEN v_success THEN picked.hero_key END, CASE WHEN v_success THEN picked.name END, v_new_id,
      CASE WHEN v_success THEN 0 ELSE v_frags END);

  v_result := jsonb_build_object(
    'success', v_success, 'sourceRarity', v_src, 'targetRarity', v_tgt,
    'costFc', v_cost, 'chance', v_chance, 'balance', v_after, 'consumed', v_required,
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
END; $function$;

REVOKE ALL ON FUNCTION public.fuse_heroes_by_rarity(bigint, uuid[], text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fuse_heroes_by_rarity(bigint, uuid[], text) TO service_role;

-- Marketplace: a hero busy in the Tower or already listed must not be sellable either.
CREATE OR REPLACE FUNCTION public.market_hero_locks(p_hero_id uuid)
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN (u->>'manuallyLocked')::boolean THEN 'not_tradable' END,
    CASE WHEN (u->>'pvpAttack')::boolean OR (u->>'pvpDefense')::boolean THEN 'pvp_team' END,
    CASE WHEN (u->>'globalBoss')::boolean THEN 'global_boss_team' END,
    CASE WHEN (u->>'clanBoss')::boolean THEN 'clan_boss_team' END,
    CASE WHEN (u->>'tower')::boolean THEN 'pvp_team' END,
    CASE WHEN (u->>'marketplace')::boolean THEN 'listed' END,
    CASE WHEN (u->>'isNft')::boolean THEN 'exclusive' END
  ], NULL)
  FROM public.hero_usage_status(p_hero_id) u;
$$;

REVOKE ALL ON FUNCTION public.market_hero_locks(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_hero_locks(uuid) TO service_role;