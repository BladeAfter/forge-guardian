-- TON MINING — V2 RULE: only the V2 20 TON (legendary) pass mines TON.
-- V2 5 TON (adventurer) pass does NOT unlock mining. V1 rules unchanged
-- (V1 20 TON always unlocks; V1 5 TON only if owned before premium rule start).
CREATE OR REPLACE FUNCTION public.ton_mining_pass_tier_at(p_user_id uuid, p_tier text)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT MIN(COALESCE(ps.purchased_at, ps.updated_at))
    FROM public.player_season_pass ps
    JOIN public.season_pass_seasons s ON s.id = ps.season_id
   WHERE ps.user_id = p_user_id
     -- V1 requires an active season; V2+ seasons count regardless of the legacy active flag
     AND (s.active OR COALESCE(ps.pass_version, 1) >= 2)
     AND (ps.expires_at IS NULL OR ps.expires_at > now())
     AND (
       -- Legendary (20 TON): unlocks on ANY pass version (V1 and V2)
       (p_tier = 'legendary' AND (ps.tier = 'legendary' OR COALESCE(ps.legendary_owned, false)))
       OR
       -- Adventurer (5 TON): unlocks ONLY for V1 passes (legacy rule).
       -- V2 adventurer passes never unlock TON mining.
       (p_tier = 'adventurer' AND COALESCE(ps.pass_version, 1) = 1
        AND (ps.tier IN ('adventurer','legendary') OR COALESCE(ps.adventurer_owned, false) OR COALESCE(ps.legendary_owned, false)))
     );
$$;

GRANT EXECUTE ON FUNCTION public.ton_mining_pass_tier_at(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ton_mining_pass_tier_at(uuid, text) TO service_role;