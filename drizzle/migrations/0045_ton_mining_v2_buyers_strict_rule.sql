-- TON MINING — V2 buyers follow the NEW rule strictly (no legacy bypass).
-- Any player owning a V2+ pass is evaluated by the V2 rule: only the 20 TON
-- (legendary) V2 pass unlocks TON mining. V2 5 TON never unlocks.
-- Players still on V1 (not completed / never purchased) keep the V1 rules.

CREATE OR REPLACE FUNCTION public.ton_mining_has_v2_pass(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.player_season_pass ps
     WHERE ps.user_id = p_user_id
       AND COALESCE(ps.pass_version, 1) >= 2
  );
$$;

GRANT EXECUTE ON FUNCTION public.ton_mining_has_v2_pass(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ton_mining_has_v2_pass(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.can_access_ton_mining(p_user_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row ton_mining_access%rowtype; v_created timestamptz; s hero_mining_settings%rowtype;
        v_pass5 timestamptz; v_pass20 timestamptz; v_v2 boolean;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  IF NOT ton_mining_gate_enabled() THEN RETURN 'LEGACY_GRANTED'; END IF;

  SELECT * INTO s FROM hero_mining_settings WHERE id;

  v_v2 := ton_mining_has_v2_pass(p_user_id);

  SELECT * INTO v_row FROM ton_mining_access WHERE user_id = p_user_id;
  IF NOT v_v2 AND v_row.user_id IS NOT NULL AND v_row.access_type = 'LEGACY_GRANTED' THEN
    RETURN 'LEGACY_GRANTED';
  END IF;
  IF v_row.user_id IS NOT NULL AND v_row.access_type = 'MANUAL_GRANTED'
     AND v_row.revoked_at IS NULL
     AND (v_row.expires_at IS NULL OR v_row.expires_at > now()) THEN RETURN 'MANUAL_GRANTED'; END IF;

  -- Legacy cutoff only applies to players who are NOT on a V2 pass.
  IF NOT v_v2 THEN
    SELECT created_at INTO v_created FROM game_players WHERE id = p_user_id;
    IF v_created IS NOT NULL AND v_created < ton_mining_gate_cutoff() THEN RETURN 'LEGACY_GRANTED'; END IF;
  END IF;

  v_pass20 := ton_mining_pass_tier_at(p_user_id, 'legendary');
  v_pass5 := ton_mining_pass_tier_at(p_user_id, 'adventurer');

  -- 20 TON pass (V1 or V2) always unlocks.
  IF COALESCE(s.legacy_pass20_access, true) AND v_pass20 IS NOT NULL THEN RETURN 'PASS_GRANTED'; END IF;

  -- 5 TON pass: V1 legacy rule only (ton_mining_pass_tier_at already excludes V2).
  IF COALESCE(s.legacy_pass5_access, true) AND v_pass5 IS NOT NULL
     AND (NOT COALESCE(s.premium_gate_enabled, true)
          OR v_pass5 < COALESCE(s.premium_rule_start_at, now())) THEN
    RETURN 'PASS_GRANTED';
  END IF;

  IF COALESCE(s.unlock_by_nft_hero, true) AND ton_mining_owns_nft_hero(p_user_id) THEN RETURN 'NFT_GRANTED'; END IF;
  IF COALESCE(s.unlock_by_nft_pet, true) AND ton_mining_owns_nft_pet(p_user_id) THEN RETURN 'NFT_GRANTED'; END IF;
  IF COALESCE(s.unlock_by_deposit_ton, true)
     AND ton_mining_deposited_ton(p_user_id) > COALESCE(s.required_deposit_ton, 30) THEN
    RETURN 'DEPOSIT_GRANTED';
  END IF;

  RETURN 'LOCKED_PASS_REQUIRED';
END $$;

CREATE OR REPLACE FUNCTION public.ton_mining_access_sync(p_user_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_state text; v_row ton_mining_access%rowtype; v_at timestamptz; v_now timestamptz := now(); v_src text;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  v_state := can_access_ton_mining(p_user_id);
  SELECT * INTO v_row FROM ton_mining_access WHERE user_id = p_user_id;

  -- Sticky legacy/manual access is preserved, EXCEPT for V2 pass owners which
  -- must always follow the strict V2 rule.
  IF v_row.user_id IS NOT NULL AND v_row.access_type IN ('LEGACY_GRANTED','MANUAL_GRANTED')
     AND v_state IN ('LEGACY_GRANTED','MANUAL_GRANTED') THEN
    RETURN v_state;
  END IF;

  IF v_state IN ('PASS_GRANTED','NFT_GRANTED','DEPOSIT_GRANTED') THEN
    v_src := CASE v_state WHEN 'PASS_GRANTED' THEN 'season_pass' WHEN 'NFT_GRANTED' THEN 'nft_ownership' ELSE 'deposits_over_threshold' END;
    v_at := COALESCE(ton_mining_pass_confirmed_at(p_user_id), v_now);
    IF v_row.user_id IS NULL OR v_row.access_type <> v_state THEN
      UPDATE player_heroes SET mining_last_at = GREATEST(v_at, v_now) WHERE user_id = p_user_id;
      UPDATE player_pets SET mining_last_at = GREATEST(v_at, v_now) WHERE user_id = p_user_id;
      UPDATE nft_equipment SET mining_last_at = GREATEST(v_at, v_now) WHERE owner_user_id = p_user_id;
      UPDATE player_equipment SET mining_last_at = GREATEST(v_at, v_now) WHERE user_id = p_user_id;
      INSERT INTO ton_mining_access(user_id, access_type, source, granted_at, mining_access_granted_at)
      VALUES (p_user_id, v_state, v_src, v_at, GREATEST(v_at, v_now))
      ON CONFLICT (user_id) DO UPDATE
        SET access_type = EXCLUDED.access_type, source = EXCLUDED.source,
            granted_at = COALESCE(ton_mining_access.granted_at, EXCLUDED.granted_at),
            mining_access_granted_at = COALESCE(ton_mining_access.mining_access_granted_at, EXCLUDED.mining_access_granted_at),
            revoked_at = NULL;
    END IF;
    RETURN v_state;
  END IF;

  IF v_state = 'LEGACY_GRANTED' THEN
    INSERT INTO ton_mining_access(user_id, access_type, source, granted_at, mining_access_granted_at)
    VALUES (p_user_id, 'LEGACY_GRANTED', 'cutoff_snapshot', v_now, NULL)
    ON CONFLICT (user_id) DO UPDATE SET access_type = 'LEGACY_GRANTED', revoked_at = NULL;
    RETURN v_state;
  END IF;

  INSERT INTO ton_mining_access(user_id, access_type, source)
  VALUES (p_user_id, 'LOCKED', 'premium_pass_required')
  ON CONFLICT (user_id) DO UPDATE SET access_type = 'LOCKED', source = 'premium_pass_required', revoked_at = now();
  RETURN 'LOCKED_PASS_REQUIRED';
END $$;