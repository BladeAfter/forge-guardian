-- Cohort of currently-qualified miners: they must own a PAID V2 pass (5 or 20 TON)
-- to keep TON mining. Everyone outside the cohort keeps the existing rules.
CREATE TABLE IF NOT EXISTS public.ton_mining_v2_cohort (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  note text
);

GRANT SELECT ON public.ton_mining_v2_cohort TO authenticated;
GRANT ALL ON public.ton_mining_v2_cohort TO service_role;
ALTER TABLE public.ton_mining_v2_cohort ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cohort_no_client_access" ON public.ton_mining_v2_cohort FOR SELECT TO authenticated USING (false);

-- Snapshot the qualified miners (non-locked access) into the cohort.
INSERT INTO public.ton_mining_v2_cohort(user_id, note)
SELECT a.user_id, 'qualified_snapshot_2026_09_01'
  FROM public.ton_mining_access a
 WHERE a.access_type <> 'LOCKED' AND a.revoked_at IS NULL
ON CONFLICT (user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.ton_mining_has_paid_v2_pass(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.player_season_pass ps
     WHERE ps.user_id = p_user_id
       AND COALESCE(ps.pass_version, 1) >= 2
       AND (COALESCE(ps.adventurer_owned,false) OR COALESCE(ps.legendary_owned,false))
  );
$$;

GRANT EXECUTE ON FUNCTION public.ton_mining_has_paid_v2_pass(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ton_mining_in_v2_cohort(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.ton_mining_v2_cohort c WHERE c.user_id = p_user_id);
$$;

GRANT EXECUTE ON FUNCTION public.ton_mining_in_v2_cohort(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_access_ton_mining(p_user_id uuid)
 RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row ton_mining_access%rowtype; v_created timestamptz; s hero_mining_settings%rowtype;
        v_pass5 timestamptz; v_pass20 timestamptz; v_v2 boolean;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  IF NOT ton_mining_gate_enabled() THEN RETURN 'LEGACY_GRANTED'; END IF;

  -- COHORT RULE: the snapshot of qualified miners keeps mining ONLY with a paid
  -- V2 pass (5 or 20 TON). No legacy/NFT/deposit bypass for them.
  IF ton_mining_in_v2_cohort(p_user_id) THEN
    IF ton_mining_has_paid_v2_pass(p_user_id) THEN RETURN 'PASS_GRANTED'; END IF;
    RETURN 'LOCKED_PASS_REQUIRED';
  END IF;

  SELECT * INTO s FROM hero_mining_settings WHERE id;

  v_v2 := ton_mining_has_v2_pass(p_user_id);

  SELECT * INTO v_row FROM ton_mining_access WHERE user_id = p_user_id;
  IF NOT v_v2 AND v_row.user_id IS NOT NULL AND v_row.access_type = 'LEGACY_GRANTED' THEN
    RETURN 'LEGACY_GRANTED';
  END IF;
  IF v_row.user_id IS NOT NULL AND v_row.access_type = 'MANUAL_GRANTED'
     AND v_row.revoked_at IS NULL
     AND (v_row.expires_at IS NULL OR v_row.expires_at > now()) THEN RETURN 'MANUAL_GRANTED'; END IF;

  IF NOT v_v2 THEN
    SELECT created_at INTO v_created FROM game_players WHERE id = p_user_id;
    IF v_created IS NOT NULL AND v_created < ton_mining_gate_cutoff() THEN RETURN 'LEGACY_GRANTED'; END IF;
  END IF;

  v_pass20 := ton_mining_pass_tier_at(p_user_id, 'legendary');
  v_pass5 := ton_mining_pass_tier_at(p_user_id, 'adventurer');

  IF COALESCE(s.legacy_pass20_access, true) AND v_pass20 IS NOT NULL THEN RETURN 'PASS_GRANTED'; END IF;

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
END $function$;
