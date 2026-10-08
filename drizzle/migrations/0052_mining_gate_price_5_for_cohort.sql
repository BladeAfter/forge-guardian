CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; u game_players%rowtype; v_count integer;
        v_rate_ton numeric; v_rate_myth numeric; v_pet_rate_myth numeric; v_pet_count integer;
        v_invested numeric; v_returned numeric; v_remaining numeric;
        v_access text; v_locked boolean;
        s hero_mining_settings%rowtype;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  v_access := ton_mining_access_sync(v_user);
  v_locked := (v_access = 'LOCKED_PASS_REQUIRED');
  PERFORM hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;

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
      'priceTon', CASE WHEN ton_mining_in_v2_cohort(v_user) THEN 5 ELSE COALESCE(s.pass_gate_price_ton, 5) END),
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
