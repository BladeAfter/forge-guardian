
-- Config: cost of a pet XP reset/transfer (admin tunable; level tiers prepared for later use)
INSERT INTO pet_settings (key, value, updated_at)
VALUES ('xp_transfer', jsonb_build_object(
  'cost_fc', 50000,
  'use_level_tiers', false,
  'level_tiers', jsonb_build_array(
    jsonb_build_object('max_level', 10, 'cost_fc', 25000),
    jsonb_build_object('max_level', 20, 'cost_fc', 50000),
    jsonb_build_object('max_level', 30, 'cost_fc', 75000),
    jsonb_build_object('max_level', 40, 'cost_fc', 100000),
    jsonb_build_object('max_level', 50, 'cost_fc', 150000)
  )
), now())
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.pet_xp_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  telegram_id bigint,
  source_player_pet_id uuid NOT NULL,
  target_player_pet_id uuid NOT NULL,
  source_pet_name text,
  target_pet_name text,
  source_level_before integer NOT NULL,
  target_level_before integer NOT NULL,
  target_level_after integer NOT NULL,
  xp_transferred integer NOT NULL,
  fc_cost numeric NOT NULL DEFAULT 0,
  balance_before numeric,
  balance_after numeric,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.pet_xp_transfers TO service_role;
ALTER TABLE public.pet_xp_transfers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role manages pet xp transfers" ON public.pet_xp_transfers
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TRIGGER update_pet_xp_transfers_updated_at BEFORE UPDATE ON public.pet_xp_transfers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Total XP accumulated by a pet (levels already paid + current progress)
CREATE OR REPLACE FUNCTION public.pet_total_xp(p_level integer, p_xp integer)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE i int; total bigint := 0;
BEGIN
  FOR i IN 1..greatest(1, coalesce(p_level, 1)) - 1 LOOP
    total := total + pet_level_xp_required(i);
  END LOOP;
  RETURN (total + greatest(0, coalesce(p_xp, 0)))::int;
END $$;

-- How much XP a pet can still absorb before hitting the max level
CREATE OR REPLACE FUNCTION public.pet_xp_capacity(p_level integer, p_xp integer)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE i int; maxlvl int := pet_max_level(); total bigint := 0;
BEGIN
  IF coalesce(p_level, 1) >= maxlvl THEN RETURN 0; END IF;
  FOR i IN coalesce(p_level, 1)..(maxlvl - 1) LOOP
    total := total + pet_level_xp_required(i);
  END LOOP;
  RETURN greatest(0, (total - greatest(0, coalesce(p_xp, 0)))::int);
END $$;

CREATE OR REPLACE FUNCTION public.pet_xp_transfer_cost(p_level integer)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg jsonb; tier jsonb; cost numeric;
BEGIN
  SELECT value INTO cfg FROM pet_settings WHERE key = 'xp_transfer';
  cost := coalesce((cfg->>'cost_fc')::numeric, 50000);
  IF coalesce((cfg->>'use_level_tiers')::boolean, false) THEN
    FOR tier IN SELECT * FROM jsonb_array_elements(coalesce(cfg->'level_tiers', '[]'::jsonb)) LOOP
      IF greatest(1, coalesce(p_level, 1)) <= coalesce((tier->>'max_level')::int, 0) THEN
        RETURN coalesce((tier->>'cost_fc')::numeric, cost);
      END IF;
    END LOOP;
  END IF;
  RETURN cost;
END $$;

-- Preview: recoverable XP, cost and which pets can absorb 100% of it
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
      'id', p.id, 'name', c.name, 'image', coalesce(c.image_baby, ''), 'rarity', p.rarity,
      'level', p.level, 'xp', p.xp, 'capacity', pet_xp_capacity(p.level, p.xp),
      'canReceive', pet_xp_capacity(p.level, p.xp) >= total AND NOT coalesce(p.market_locked, false)
    ) ORDER BY p.level DESC), '[]'::jsonb)
  INTO targets
  FROM player_pets p JOIN pet_catalog c ON c.id = p.pet_id
  WHERE p.user_id = u AND p.id <> src.id;

  RETURN jsonb_build_object(
    'sourceId', src.id, 'level', src.level, 'xp', src.xp, 'totalXp', total,
    'costFc', cost, 'balance', bal, 'targets', targets);
END $$;

-- Atomic reset + transfer: only level/XP change, never identity, NFT, mining or breeding data
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

  -- deterministic lock order avoids deadlocks between concurrent transfers
  IF p_source_player_pet_id < p_target_player_pet_id THEN
    SELECT * INTO src FROM player_pets WHERE id = p_source_player_pet_id AND user_id = u FOR UPDATE;
    SELECT * INTO tgt FROM player_pets WHERE id = p_target_player_pet_id AND user_id = u FOR UPDATE;
  ELSE
    SELECT * INTO tgt FROM player_pets WHERE id = p_target_player_pet_id AND user_id = u FOR UPDATE;
    SELECT * INTO src FROM player_pets WHERE id = p_source_player_pet_id AND user_id = u FOR UPDATE;
  END IF;
  IF src.id IS NULL OR tgt.id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;
  IF coalesce(src.market_locked, false) OR coalesce(tgt.market_locked, false) THEN RAISE EXCEPTION 'PET_LISTED_IN_MARKET'; END IF;

  -- Sub-NFT pets can only be reset once fully matured
  FOR sub IN SELECT maturity_stage FROM sub_nfts WHERE player_pet_id IN (src.id, tgt.id) LOOP
    IF lower(coalesce(sub.maturity_stage, '')) <> 'adult' THEN RAISE EXCEPTION 'SUB_NFT_NOT_ADULT'; END IF;
  END LOOP;

  total := pet_total_xp(src.level, src.xp);
  IF total <= 0 THEN RAISE EXCEPTION 'PET_NO_XP'; END IF;
  IF pet_xp_capacity(tgt.level, tgt.xp) < total THEN RAISE EXCEPTION 'TARGET_CANNOT_RECEIVE_XP'; END IF;

  cost := pet_xp_transfer_cost(src.level);
  IF bal < cost THEN RAISE EXCEPTION 'NOT_ENOUGH_FORGE_COINS'; END IF;

  UPDATE game_players SET balance = balance - cost, updated_at = now() WHERE id = u;

  -- source pet: only level/XP reset
  UPDATE player_pets SET level = 1, xp = 0, updated_at = now() WHERE id = src.id;

  -- target pet absorbs 100% of the XP and levels up accordingly
  lvl := tgt.level; v_xp := tgt.xp + total;
  LOOP
    EXIT WHEN lvl >= maxlvl;
    need := pet_level_xp_required(lvl);
    EXIT WHEN v_xp < need;
    v_xp := v_xp - need; lvl := lvl + 1;
  END LOOP;
  IF lvl >= maxlvl THEN lvl := maxlvl; v_xp := 0; END IF;
  UPDATE player_pets SET level = lvl, xp = v_xp, updated_at = now() WHERE id = tgt.id;

  SELECT name INTO src_name FROM pet_catalog WHERE id = src.pet_id;
  SELECT name INTO tgt_name FROM pet_catalog WHERE id = tgt.pet_id;

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

REVOKE ALL ON FUNCTION public.pet_total_xp(integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_xp_capacity(integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_xp_transfer_cost(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_xp_transfer_preview(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_reset_transfer_xp(bigint, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pet_total_xp(integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_xp_capacity(integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_xp_transfer_cost(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_xp_transfer_preview(bigint, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_reset_transfer_xp(bigint, uuid, uuid, text) TO service_role;
