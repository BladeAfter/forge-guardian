-- Season Pass perks: extra rarity-fusion chance and extra MYTH mining, server-side and configurable.

INSERT INTO public.game_settings(key, value)
VALUES ('season_pass_perks', jsonb_build_object(
  'enabled', true,
  'adventurer', jsonb_build_object('fusion_bonus_percent', 5, 'myth_mining_bonus_percent', 10),
  'legendary',  jsonb_build_object('fusion_bonus_percent', 10, 'myth_mining_bonus_percent', 25)
))
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.season_pass_perk_percent(p_user_id uuid, p_perk text)
RETURNS numeric
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cfg jsonb; v_tier text; v_val numeric := 0;
BEGIN
  IF p_user_id IS NULL OR p_perk IS NULL THEN RETURN 0; END IF;
  SELECT value INTO cfg FROM public.game_settings WHERE key = 'season_pass_perks';
  cfg := COALESCE(cfg, '{}'::jsonb);
  IF COALESCE((cfg->>'enabled')::boolean, true) IS NOT TRUE THEN RETURN 0; END IF;
  v_tier := public.has_active_season_pass(p_user_id);
  IF v_tier IS NULL OR v_tier = 'none' THEN RETURN 0; END IF;
  v_val := COALESCE((cfg->v_tier->>p_perk)::numeric, 0);
  RETURN GREATEST(LEAST(v_val, 100), 0);
END $$;

GRANT EXECUTE ON FUNCTION public.season_pass_perk_percent(uuid, text) TO authenticated, service_role;

-- MYTH mining: apply the pass bonus on top of the veteran boost.
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_myth_flat numeric := 0; v_pet_myth numeric := 0; v_pet_flat numeric := 0;
        v_eq_myth numeric := 0; v_peq_myth numeric := 0;
        v_out numeric; v_room numeric; v_boost numeric := 0;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() OR NOT public.ton_mining_access_allowed(p_user_id) THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE player_pets SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE nft_equipment SET mining_last_at = v_now WHERE owner_user_id = p_user_id;
    UPDATE player_equipment SET mining_last_at = v_now WHERE user_id = p_user_id AND COALESCE(mining_daily_myth,0) > 0;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  v_room := GREATEST(COALESCE(hero_mining_remaining(p_user_id), 0), 0);

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_row_rate(h.mining_ton_override, h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(
             COALESCE(h.mining_daily_myth, 0),
             CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                  ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END
           ) AS myth_rate,
           hero_mining_hero_dual(h.nft_hero_id) AS dual,
           COALESCE(h.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.dual AS dual, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT
    COALESCE(SUM(CASE WHEN rate > 0 THEN rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_ton_gain, v_myth_gain, v_myth_flat
    FROM moved;

  WITH pelig AS (
    SELECT p.id, GREATEST(COALESCE(p.mining_daily_myth, 0), 0) AS myth_rate,
           COALESCE(p.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(p.mining_last_at, p.created_at, v_now)))) AS secs
      FROM player_pets p
     WHERE p.user_id = p_user_id
       AND COALESCE(p.mining_daily_myth, 0) > 0
       AND NOT COALESCE(p.market_locked, false)
  ), pmoved AS (
    UPDATE player_pets pp SET mining_last_at = v_now
      FROM pelig e WHERE pp.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT COALESCE(SUM(CASE WHEN NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_pet_myth, v_pet_flat FROM pmoved;

  WITH eelig AS (
    SELECT n.id, GREATEST(COALESCE(n.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(n.mining_last_at, n.assigned_at, n.created_at, v_now)))) AS secs
      FROM nft_equipment n
     WHERE n.owner_user_id = p_user_id
       AND n.status <> 'BURNED'
       AND COALESCE(n.mining_daily_myth, 0) > 0
  ), emoved AS (
    UPDATE nft_equipment ne SET mining_last_at = v_now
      FROM eelig e WHERE ne.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_eq_myth FROM emoved;

  WITH qelig AS (
    SELECT q.id, GREATEST(COALESCE(q.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(q.mining_last_at, q.created_at, v_now)))) AS secs
      FROM player_equipment q
     WHERE q.user_id = p_user_id
       AND COALESCE(q.mining_daily_myth, 0) > 0
       AND NOT COALESCE(q.market_locked, false)
       AND NOT EXISTS (SELECT 1 FROM nft_equipment n WHERE n.player_equipment_id = q.id)
  ), qmoved AS (
    UPDATE player_equipment pq SET mining_last_at = v_now
      FROM qelig e WHERE pq.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_peq_myth FROM qmoved;

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0) + GREATEST(v_eq_myth, 0) + GREATEST(v_peq_myth, 0);

  v_boost := GREATEST(COALESCE(public.veteran_v2_boost_percent(p_user_id), 0), 0)
           + GREATEST(COALESCE(public.season_pass_perk_percent(p_user_id, 'myth_mining_bonus_percent'), 0), 0);
  v_myth_gain := round(v_myth_gain * (1 + v_boost / 100.0) + GREATEST(v_myth_flat, 0) + GREATEST(v_pet_flat, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
   RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END
$function$;

-- Rarity fusion: pass tier adds flat percentage points to the success chance (capped at 100).
CREATE OR REPLACE FUNCTION public.fuse_heroes_by_rarity(p_telegram_id bigint, p_hero_ids uuid[], p_idempotency_key text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid; v_bal numeric; cfg jsonb := public.hero_rarity_fusion_config(); tier jsonb;
  ids uuid[]; v_required int; v_count int; v_src text; v_tgt text;
  v_cost_myth numeric; v_chance numeric; v_frags int; v_roll numeric; v_success boolean;
  picked public.hero_catalog%rowtype; v_new_id uuid; v_keys text[];
  v_existing jsonb; v_frag_total int := 0; v_result jsonb; v_new_row public.player_heroes%rowtype;
  v_blocked uuid; v_charge jsonb; v_myth_after numeric; v_base_chance numeric; v_pass_bonus numeric := 0;
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
  v_base_chance := least(100, greatest(0, coalesce((tier->>'chance')::numeric, 0)));
  v_pass_bonus := GREATEST(COALESCE(public.season_pass_perk_percent(v_user, 'fusion_bonus_percent'), 0), 0);
  v_chance := least(100, greatest(0, v_base_chance + v_pass_bonus));
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
    'costFc', 0, 'costMyth', v_cost_myth, 'chance', v_chance, 'baseChance', v_base_chance, 'passBonus', v_pass_bonus,
    'balance', v_bal, 'consumed', v_required,
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
END; $function$;
