
CREATE OR REPLACE FUNCTION public.pet_xp_transfer_preview(p_telegram_id bigint, p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; src player_pets%rowtype; total int; cost numeric; bal numeric; targets jsonb;
BEGIN
  SELECT id, balance INTO u, bal FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO src FROM player_pets WHERE id = p_player_pet_id AND user_id = u;
  IF src.id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;

  total := pet_total_xp(src.level, src.xp);
  cost := pet_xp_transfer_cost(src.level);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', c.name, 'rarity', p.rarity,
      'image', CASE p.evolution_stage
        WHEN 'ancestral' THEN coalesce(c.image_ancestral_url, c.image_adult_url, c.image_baby_url)
        WHEN 'adult' THEN coalesce(c.image_adult_url, c.image_baby_url)
        WHEN 'young' THEN coalesce(c.image_young_url, c.image_baby_url)
        ELSE c.image_baby_url END,
      'level', p.level, 'xp', p.xp, 'capacity', pet_xp_capacity(p.level, p.xp),
      'canReceive', pet_xp_capacity(p.level, p.xp) >= total AND NOT coalesce(p.market_locked, false)
    ) ORDER BY p.level DESC), '[]'::jsonb)
  INTO targets
  FROM player_pets p JOIN pets c ON c.id = p.pet_id
  WHERE p.user_id = u AND p.id <> src.id;

  RETURN jsonb_build_object(
    'sourceId', src.id, 'level', src.level, 'xp', src.xp, 'totalXp', total,
    'costFc', cost, 'balance', bal, 'targets', targets);
END $$;

CREATE OR REPLACE FUNCTION public.pet_reset_transfer_xp(
  p_telegram_id bigint, p_source_player_pet_id uuid, p_target_player_pet_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; bal numeric; src player_pets%rowtype; tgt player_pets%rowtype;
        total int; cost numeric; maxlvl int := pet_max_level();
        lvl int; v_xp int; need int; sub record; payload jsonb;
        src_name text; tgt_name text;
BEGIN
  IF p_source_player_pet_id IS NULL OR p_target_player_pet_id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;
  IF p_source_player_pet_id = p_target_player_pet_id THEN RAISE EXCEPTION 'PET_XP_SAME_PET'; END IF;
  IF length(coalesce(p_idempotency_key, '')) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST_KEY'; END IF;

  SELECT id, balance INTO u, bal FROM game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT result INTO payload FROM pet_action_idempotency WHERE idempotency_key = p_idempotency_key AND user_id = u;
  IF payload IS NOT NULL THEN RETURN payload; END IF;

  IF p_source_player_pet_id < p_target_player_pet_id THEN
    SELECT * INTO src FROM player_pets WHERE id = p_source_player_pet_id AND user_id = u FOR UPDATE;
    SELECT * INTO tgt FROM player_pets WHERE id = p_target_player_pet_id AND user_id = u FOR UPDATE;
  ELSE
    SELECT * INTO tgt FROM player_pets WHERE id = p_target_player_pet_id AND user_id = u FOR UPDATE;
    SELECT * INTO src FROM player_pets WHERE id = p_source_player_pet_id AND user_id = u FOR UPDATE;
  END IF;
  IF src.id IS NULL OR tgt.id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;
  IF coalesce(src.market_locked, false) OR coalesce(tgt.market_locked, false) THEN RAISE EXCEPTION 'PET_LISTED_IN_MARKET'; END IF;

  FOR sub IN SELECT maturity_stage FROM sub_nfts WHERE player_pet_id IN (src.id, tgt.id) LOOP
    IF lower(coalesce(sub.maturity_stage, '')) <> 'adult' THEN RAISE EXCEPTION 'SUB_NFT_NOT_ADULT'; END IF;
  END LOOP;

  total := pet_total_xp(src.level, src.xp);
  IF total <= 0 THEN RAISE EXCEPTION 'PET_NO_XP'; END IF;
  IF pet_xp_capacity(tgt.level, tgt.xp) < total THEN RAISE EXCEPTION 'TARGET_CANNOT_RECEIVE_XP'; END IF;

  cost := pet_xp_transfer_cost(src.level);
  IF bal < cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FORGE_COINS'; END IF;

  UPDATE game_players SET balance = balance - cost, updated_at = now() WHERE id = u;
  UPDATE player_pets SET level = 1, xp = 0, updated_at = now() WHERE id = src.id;

  lvl := tgt.level; v_xp := tgt.xp + total;
  LOOP
    EXIT WHEN lvl >= maxlvl;
    need := pet_level_xp_required(lvl);
    EXIT WHEN v_xp < need;
    v_xp := v_xp - need; lvl := lvl + 1;
  END LOOP;
  IF lvl >= maxlvl THEN lvl := maxlvl; v_xp := 0; END IF;
  UPDATE player_pets SET level = lvl, xp = v_xp, updated_at = now() WHERE id = tgt.id;

  SELECT name INTO src_name FROM pets WHERE id = src.pet_id;
  SELECT name INTO tgt_name FROM pets WHERE id = tgt.pet_id;

  INSERT INTO pet_xp_transfers (user_id, telegram_id, source_player_pet_id, target_player_pet_id,
    source_pet_name, target_pet_name, source_level_before, target_level_before, target_level_after,
    xp_transferred, fc_cost, balance_before, balance_after)
  VALUES (u, p_telegram_id, src.id, tgt.id, src_name, tgt_name, src.level, tgt.level, lvl,
    total, cost, bal, bal - cost);

  INSERT INTO pet_upgrade_history (user_id, player_pet_id, old_level, new_level, fc_spent, action, xp_before, xp_added, xp_after)
  VALUES (u, src.id, src.level, 1, cost, 'xp_reset', src.xp, -total, 0),
         (u, tgt.id, tgt.level, lvl, 0, 'xp_received', tgt.xp, total, v_xp);

  INSERT INTO pet_transactions (user_id, telegram_id, event, item_type, item_ref, item_name, quantity,
    fc_cost, balance_before, balance_after, metadata)
  VALUES (u, p_telegram_id, 'PET_XP_TRANSFER', 'pet', src.id::text, src_name, 1, cost, bal, bal - cost,
    jsonb_build_object('targetPetId', tgt.id, 'targetPetName', tgt_name, 'xpTransferred', total,
      'sourceLevelBefore', src.level, 'targetLevelAfter', lvl));

  payload := jsonb_build_object('dashboard', get_pet_dashboard(p_telegram_id),
    'xpTransferResult', jsonb_build_object('sourceName', src_name, 'targetName', tgt_name,
      'sourceLevelBefore', src.level, 'targetLevelBefore', tgt.level, 'targetLevelAfter', lvl,
      'xpTransferred', total, 'costFc', cost));
  INSERT INTO pet_action_idempotency VALUES (p_idempotency_key, u, src.id, 'xp_transfer', payload, now());
  RETURN payload;
END $$;

REVOKE ALL ON FUNCTION public.pet_xp_transfer_preview(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_reset_transfer_xp(bigint, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pet_xp_transfer_preview(bigint, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_reset_transfer_xp(bigint, uuid, uuid, text) TO service_role;
