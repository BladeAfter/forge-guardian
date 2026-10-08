CREATE TABLE IF NOT EXISTS public.ton_mining_suspended (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  required_pass_ton numeric NOT NULL DEFAULT 20,
  created_at timestamptz NOT NULL DEFAULT now(),
  note text
);

GRANT SELECT ON public.ton_mining_suspended TO authenticated;
GRANT ALL ON public.ton_mining_suspended TO service_role;
ALTER TABLE public.ton_mining_suspended ENABLE ROW LEVEL SECURITY;
CREATE POLICY "suspended_no_client_access" ON public.ton_mining_suspended FOR SELECT TO authenticated USING (false);

CREATE OR REPLACE FUNCTION public.ton_mining_suspension_price(p_user_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT s.required_pass_ton FROM public.ton_mining_suspended s WHERE s.user_id = p_user_id;
$$;

GRANT EXECUTE ON FUNCTION public.ton_mining_suspension_price(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_access_ton_mining(p_user_id uuid)
 RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row ton_mining_access%rowtype; v_created timestamptz; s hero_mining_settings%rowtype;
        v_pass5 timestamptz; v_pass20 timestamptz; v_v2 boolean; v_susp numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  IF NOT ton_mining_gate_enabled() THEN RETURN 'LEGACY_GRANTED'; END IF;

  -- MANUAL SUSPENSION: locked until the required paid V2 pass is owned.
  v_susp := ton_mining_suspension_price(p_user_id);
  IF v_susp IS NOT NULL THEN
    IF v_susp >= 20 THEN
      IF EXISTS (SELECT 1 FROM player_season_pass ps
                  WHERE ps.user_id = p_user_id AND COALESCE(ps.pass_version,1) >= 2
                    AND COALESCE(ps.legendary_owned,false)) THEN RETURN 'PASS_GRANTED'; END IF;
    ELSIF ton_mining_has_paid_v2_pass(p_user_id) THEN
      RETURN 'PASS_GRANTED';
    END IF;
    RETURN 'LOCKED_PASS_REQUIRED';
  END IF;

  -- COHORT RULE: snapshot of qualified miners keeps mining ONLY with a paid V2 pass (5 or 20 TON).
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

CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; u game_players%rowtype; v_count integer;
        v_rate_ton numeric; v_rate_myth numeric; v_pet_rate_myth numeric; v_pet_count integer;
        v_invested numeric; v_returned numeric; v_remaining numeric;
        v_access text; v_locked boolean; v_price numeric;
        s hero_mining_settings%rowtype;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  v_access := ton_mining_access_sync(v_user);
  v_locked := (v_access = 'LOCKED_PASS_REQUIRED');
  PERFORM hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;

  v_price := COALESCE(
    ton_mining_suspension_price(v_user),
    CASE WHEN ton_mining_in_v2_cohort(v_user) THEN 5 ELSE COALESCE(s.pass_gate_price_ton, 5) END);

  v_invested := round(COALESCE(u.hero_mining_invested_ton, 0), 9);
  v_returned := round(COALESCE(u.hero_mining_returned_ton, 0), 9);
  v_remaining := GREATEST(0, round(v_invested - v_returned - round(COALESCE(u.hero_mining_unclaimed_ton,0),9), 9));

  SELECT COUNT(*),
         COALESCE(SUM(hero_mining_row_rate(h.mining_ton_override, h.rarity, h.nft_hero_id)), 0),
         COALESCE(SUM(GREATEST(COALESCE(h.mining_daily_myth,0), hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id), 0)), 0)
    INTO v_count, v_rate_ton, v_rate_myth
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND (COALESCE(h.mining_daily_myth,0) > 0
          OR (NOT COALESCE(h.pass_exclusive,false)
              AND (hero_mining_row_rate(h.mining_ton_override, h.rarity, h.nft_hero_id) > 0
                   OR hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) > 0)));

  SELECT COUNT(*), COALESCE(SUM(GREATEST(COALESCE(p.mining_daily_myth,0), 0)), 0)
    INTO v_pet_count, v_pet_rate_myth
    FROM player_pets p
   WHERE p.user_id = v_user AND COALESCE(p.mining_daily_myth,0) > 0
     AND NOT COALESCE(p.market_locked, false);

  v_rate_myth := COALESCE(v_rate_myth,0) + COALESCE(v_pet_rate_myth,0);
  v_count := COALESCE(v_count,0) + COALESCE(v_pet_count,0);

  RETURN jsonb_build_object(
    'enabled', COALESCE(s.enabled, true),
    'miningAccess', v_access,
    'accessLocked', v_locked,
    'passGate', jsonb_build_object(
      'enabled', COALESCE(s.pass_gate_enabled, false),
      'cutoffAt', COALESCE(s.pass_gate_cutoff_at, '2026-08-25T00:00:00Z'::timestamptz),
      'priceTon', v_price),
    'miningCurrency', CASE WHEN COALESCE(v_rate_myth,0) > 0 AND COALESCE(v_rate_ton,0) > 0 THEN 'hybrid'
                           WHEN COALESCE(v_rate_myth,0) > 0 THEN 'myth' ELSE 'ton' END,
    'currencyChangedAt', s.currency_changed_at,
    'mythPerDay', round(COALESCE(s.myth_per_day, 0), 9),
    'passExclusiveMythPerDay', round(COALESCE(s.pass_exclusive_myth_per_day, 0), 9),
    'dailyRate', CASE WHEN v_locked THEN 0 ELSE round(COALESCE(v_rate_ton, 0), 9) END,
    'dailyRateTon', CASE WHEN v_locked THEN 0 ELSE round(COALESCE(v_rate_ton, 0), 9) END,
    'dailyRateMyth', CASE WHEN v_locked THEN 0 ELSE round(COALESCE(v_rate_myth, 0), 9) END,
    'unclaimed', round(COALESCE(u.hero_mining_unclaimed_ton, 0), 9),
    'unclaimedTon', round(COALESCE(u.hero_mining_unclaimed_ton, 0), 9),
    'unclaimedMyth', round(COALESCE(u.hero_mining_unclaimed_myth, 0), 9),
    'lifetimeTon', round(COALESCE(u.hero_mining_lifetime_ton, 0), 9),
    'lifetimeMyth', round(COALESCE(u.hero_mining_lifetime_myth, 0), 9),
    'mythBalance', COALESCE((SELECT amount FROM myth_balances WHERE user_id = v_user), 0),
    'mythPoolAvailable', myth_mining_pool_available(),
    'investedTon', v_invested, 'returnedTon', v_returned, 'remainingTon', v_remaining,
    'roiLimitReached', (v_invested > 0 AND v_remaining <= 0),
    'hasInvestment', (v_invested > 0),
    'eligibleHeroes', COALESCE(v_count, 0),
    'availableTon', round(COALESCE(u.ton_balance, 0), 9),
    'minClaim', COALESCE(s.min_claim_ton, 0),
    'minClaimTon', COALESCE(s.min_claim_ton, 0),
    'minClaimMyth', COALESCE(s.min_claim_myth, 0),
    'lastClaimAt', u.hero_mining_claimed_at,
    'updatedAt', now(),
    'rates', COALESCE((SELECT jsonb_object_agg(rarity, ton_per_day) FROM hero_mining_rates), '{}'::jsonb),
    'investments', COALESCE((SELECT jsonb_agg(jsonb_build_object('sourceType', i.source_type, 'amountTon', i.amount_ton, 'createdAt', i.created_at) ORDER BY i.created_at DESC)
      FROM (SELECT * FROM hero_mining_investments WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) i), '[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'amountTon', c.amount_ton, 'amountMyth', COALESCE(c.amount_myth,0), 'currency', COALESCE(c.currency,'ton'),
        'heroCount', c.hero_count, 'ratePerDay', c.rate_per_day, 'createdAt', c.created_at) ORDER BY c.created_at DESC)
      FROM (SELECT * FROM hero_mining_claims WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) c), '[]'::jsonb)
  );
END $function$;
