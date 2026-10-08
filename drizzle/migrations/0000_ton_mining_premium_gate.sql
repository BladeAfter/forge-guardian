-- ============================================================
-- TON MINING — PREMIUM ACCESS RULE
-- Unlocked when: legacy 5 TON pass (owned before the rule start),
-- 20 TON pass (any time), NFT hero, NFT pet, or deposits > 30 TON.
-- ============================================================

ALTER TABLE public.hero_mining_settings
  ADD COLUMN IF NOT EXISTS premium_gate_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS premium_rule_start_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS legacy_pass5_access boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS legacy_pass20_access boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS unlock_by_nft_hero boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS unlock_by_nft_pet boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS unlock_by_deposit_ton boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS required_deposit_ton numeric NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS required_pass_ton numeric NOT NULL DEFAULT 20;

ALTER TABLE public.ton_mining_access DROP CONSTRAINT IF EXISTS ton_mining_access_type_check;
ALTER TABLE public.ton_mining_access ADD CONSTRAINT ton_mining_access_type_check
  CHECK (access_type IN ('LEGACY_GRANTED','PASS_GRANTED','MANUAL_GRANTED','NFT_GRANTED','DEPOSIT_GRANTED','LOCKED'));

-- Earliest confirmed pass of a given tier (active season, respecting expiry).
CREATE OR REPLACE FUNCTION public.ton_mining_pass_tier_at(p_user_id uuid, p_tier text)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT MIN(COALESCE(ps.purchased_at, ps.updated_at))
    FROM public.player_season_pass ps
    JOIN public.season_pass_seasons s ON s.id = ps.season_id
   WHERE ps.user_id = p_user_id
     AND s.active
     AND (ps.expires_at IS NULL OR ps.expires_at > now())
     AND (
       (p_tier = 'legendary' AND (ps.tier = 'legendary' OR COALESCE(ps.legendary_owned, false)))
       OR (p_tier = 'adventurer' AND (ps.tier IN ('adventurer','legendary') OR COALESCE(ps.adventurer_owned, false) OR COALESCE(ps.legendary_owned, false)))
     );
$$;

CREATE OR REPLACE FUNCTION public.ton_mining_owns_nft_hero(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.nft_heroes WHERE owner_user_id = p_user_id)
      OR EXISTS (SELECT 1 FROM public.player_heroes WHERE user_id = p_user_id AND nft_hero_id IS NOT NULL);
$$;

CREATE OR REPLACE FUNCTION public.ton_mining_owns_nft_pet(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.nft_pets WHERE owner_user_id = p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.ton_mining_deposited_ton(p_user_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(SUM(amount_ton), 0)
    FROM public.wallet_deposits
   WHERE user_id = p_user_id
     AND (status IN ('confirmed','paid','credited') OR confirmed_at IS NOT NULL OR credited_at IS NOT NULL);
$$;

-- Read-only authorization decision (never mutates).
CREATE OR REPLACE FUNCTION public.can_access_ton_mining(p_user_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row ton_mining_access%rowtype; v_created timestamptz; s hero_mining_settings%rowtype;
        v_pass5 timestamptz; v_pass20 timestamptz;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  IF NOT ton_mining_gate_enabled() THEN RETURN 'LEGACY_GRANTED'; END IF;

  SELECT * INTO s FROM hero_mining_settings WHERE id;

  SELECT * INTO v_row FROM ton_mining_access WHERE user_id = p_user_id;
  IF v_row.user_id IS NOT NULL AND v_row.access_type = 'LEGACY_GRANTED' THEN RETURN 'LEGACY_GRANTED'; END IF;
  IF v_row.user_id IS NOT NULL AND v_row.access_type = 'MANUAL_GRANTED'
     AND v_row.revoked_at IS NULL
     AND (v_row.expires_at IS NULL OR v_row.expires_at > now()) THEN RETURN 'MANUAL_GRANTED'; END IF;

  -- Players created before the pass-gate cutoff are legacy players.
  SELECT created_at INTO v_created FROM game_players WHERE id = p_user_id;
  IF v_created IS NOT NULL AND v_created < ton_mining_gate_cutoff() THEN RETURN 'LEGACY_GRANTED'; END IF;

  v_pass20 := ton_mining_pass_tier_at(p_user_id, 'legendary');
  v_pass5 := ton_mining_pass_tier_at(p_user_id, 'adventurer');

  -- 20 TON pass always unlocks.
  IF COALESCE(s.legacy_pass20_access, true) AND v_pass20 IS NOT NULL THEN RETURN 'PASS_GRANTED'; END IF;

  -- 5 TON pass only unlocks when it was already owned before this premium rule started.
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

-- Persist the decision; a NEW unlock flushes cursors so no retroactive accrual happens.
CREATE OR REPLACE FUNCTION public.ton_mining_access_sync(p_user_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_state text; v_row ton_mining_access%rowtype; v_at timestamptz; v_now timestamptz := now(); v_src text;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  v_state := can_access_ton_mining(p_user_id);
  SELECT * INTO v_row FROM ton_mining_access WHERE user_id = p_user_id;

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
  ON CONFLICT (user_id) DO UPDATE SET access_type = 'LOCKED', source = 'premium_pass_required';
  RETURN 'LOCKED_PASS_REQUIRED';
END $$;

CREATE OR REPLACE FUNCTION public.ton_mining_access_allowed(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.can_access_ton_mining(p_user_id) <> 'LOCKED_PASS_REQUIRED';
$$;