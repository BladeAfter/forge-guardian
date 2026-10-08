-- Hybrid NFT mining: each NFT keeps the currency frozen on it.
-- Sold NFTs (mining_daily_myth = 0) keep mining TON; new/shop NFTs with a MYTH
-- rate mine MYTH only. The global setting is no longer a fallback for MYTH.

CREATE OR REPLACE FUNCTION public.hero_mining_hero_myth_rate(p_rarity text, p_nft_hero_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_nft_hero_id IS NULL THEN 0
    ELSE COALESCE((SELECT GREATEST(COALESCE(mining_daily_myth, 0), 0) FROM nft_heroes WHERE id = p_nft_hero_id), 0)
  END;
$function$;

CREATE OR REPLACE FUNCTION public.hero_mining_effective_daily(p_rarity text, p_nft_hero_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN hero_mining_hero_myth_rate(p_rarity, p_nft_hero_id) > 0 THEN hero_mining_hero_myth_rate(p_rarity, p_nft_hero_id)
    ELSE GREATEST(hero_mining_hero_rate(p_rarity, p_nft_hero_id), 0)
  END;
$function$;

CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_out numeric; v_room numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  v_room := GREATEST(COALESCE(hero_mining_remaining(p_user_id), 0), 0);

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT
    COALESCE(SUM(CASE WHEN myth_rate <= 0 AND rate > 0 THEN rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_ton_gain, v_myth_gain
    FROM moved;

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := round(GREATEST(v_myth_gain, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END $function$;

CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; u game_players%rowtype; v_count integer;
        v_rate_ton numeric; v_rate_myth numeric;
        v_invested numeric; v_returned numeric; v_remaining numeric;
        s hero_mining_settings%rowtype;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  PERFORM hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;

  v_invested := round(COALESCE(u.hero_mining_invested_ton, 0), 9);
  v_returned := round(COALESCE(u.hero_mining_returned_ton, 0), 9);
  v_remaining := GREATEST(0, round(v_invested - v_returned - round(COALESCE(u.hero_mining_unclaimed_ton,0),9), 9));

  SELECT COUNT(*),
         COALESCE(SUM(CASE WHEN hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) <= 0
                           THEN hero_mining_hero_rate(h.rarity, h.nft_hero_id) ELSE 0 END), 0),
         COALESCE(SUM(GREATEST(hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id), 0)), 0)
    INTO v_count, v_rate_ton, v_rate_myth
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.pass_exclusive, false)
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND (hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0
          OR hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) > 0);

  RETURN jsonb_build_object(
    'enabled', COALESCE(s.enabled, true),
    'miningCurrency', CASE WHEN COALESCE(v_rate_myth,0) > 0 AND COALESCE(v_rate_ton,0) > 0 THEN 'hybrid'
                           WHEN COALESCE(v_rate_myth,0) > 0 THEN 'myth' ELSE 'ton' END,
    'currencyChangedAt', s.currency_changed_at,
    'mythPerDay', round(COALESCE(s.myth_per_day, 0), 9),
    'dailyRate', round(COALESCE(v_rate_ton, 0), 9),
    'dailyRateTon', round(COALESCE(v_rate_ton, 0), 9),
    'dailyRateMyth', round(COALESCE(v_rate_myth, 0), 9),
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

CREATE OR REPLACE FUNCTION public.claim_hero_mining(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; v_count integer; v_rate_ton numeric; v_rate_myth numeric;
        v_min_ton numeric; v_min_myth numeric; v_claim uuid; v_claim_myth uuid;
        v_invested numeric; v_returned numeric; v_room numeric;
        v_ton numeric := 0; v_myth numeric := 0; v_available numeric;
        v_pending_ton numeric; v_pending_myth numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF NOT hero_mining_enabled() THEN RAISE EXCEPTION 'MINING_DISABLED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('hero_mining_claim:' || v_user::text));
  PERFORM hero_mining_accrue(v_user);

  SELECT round(COALESCE(hero_mining_unclaimed_ton,0),9), round(COALESCE(hero_mining_unclaimed_myth,0),9),
         round(COALESCE(hero_mining_invested_ton, 0), 9), round(COALESCE(hero_mining_returned_ton, 0), 9)
    INTO v_pending_ton, v_pending_myth, v_invested, v_returned
    FROM game_players WHERE id = v_user;

  SELECT COUNT(*),
         COALESCE(SUM(CASE WHEN hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) <= 0
                           THEN hero_mining_hero_rate(h.rarity, h.nft_hero_id) ELSE 0 END), 0),
         COALESCE(SUM(GREATEST(hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id), 0)), 0)
    INTO v_count, v_rate_ton, v_rate_myth
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.pass_exclusive, false)
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND (hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0
          OR hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) > 0);

  SELECT COALESCE(min_claim_ton, 0), COALESCE(min_claim_myth, 0)
    INTO v_min_ton, v_min_myth FROM hero_mining_settings WHERE id;

  -- TON side: still bound by the ROI cap of real TON invested.
  v_room := GREATEST(0, round(v_invested - v_returned, 9));
  IF v_invested > 0 AND v_room > 0 THEN
    v_ton := round(LEAST(v_pending_ton, v_room), 9);
    IF v_ton < GREATEST(v_min_ton, 0.000001) THEN v_ton := 0; END IF;
  END IF;

  -- MYTH side: bound by the MYTH mining pool only.
  v_available := myth_mining_pool_available();
  IF v_available > 0 THEN
    v_myth := round(LEAST(v_pending_myth, v_available), 9);
    IF v_myth < GREATEST(v_min_myth, 0.000001) THEN v_myth := 0; END IF;
  END IF;

  IF v_ton <= 0 AND v_myth <= 0 THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;

  IF v_ton > 0 THEN
    INSERT INTO hero_mining_claims (user_id, amount_ton, currency, hero_count, rate_per_day)
    VALUES (v_user, v_ton, 'ton', COALESCE(v_count, 0), round(COALESCE(v_rate_ton, 0), 9))
    RETURNING id INTO v_claim;

    UPDATE game_players
       SET hero_mining_unclaimed_ton = GREATEST(0, round(COALESCE(hero_mining_unclaimed_ton, 0) - v_ton, 9)),
           hero_mining_lifetime_ton = round(COALESCE(hero_mining_lifetime_ton, 0) + v_ton, 9),
           hero_mining_returned_ton = round(COALESCE(hero_mining_returned_ton, 0) + v_ton, 9),
           hero_mining_claimed_at = now(), updated_at = now()
     WHERE id = v_user;

    PERFORM credit_ton_reward(v_user, v_ton, 'hero_mining', 'hero_mining:' || v_claim::text, 'Hero TON Mining');
    INSERT INTO nft_mining_ledger (entry_type, currency, amount, user_id, reference_id)
    VALUES ('NFT_MINING_TON_CLAIM', 'ton', v_ton, v_user, v_claim::text);
  END IF;

  IF v_myth > 0 THEN
    INSERT INTO hero_mining_claims (user_id, amount_ton, amount_myth, currency, hero_count, rate_per_day)
    VALUES (v_user, 0, v_myth, 'myth', COALESCE(v_count,0), round(COALESCE(v_rate_myth,0),9))
    RETURNING id INTO v_claim_myth;

    UPDATE game_players
       SET hero_mining_unclaimed_myth = GREATEST(0, round(COALESCE(hero_mining_unclaimed_myth,0) - v_myth, 9)),
           hero_mining_lifetime_myth = round(COALESCE(hero_mining_lifetime_myth,0) + v_myth, 9),
           hero_mining_claimed_at = now(), updated_at = now()
     WHERE id = v_user;

    UPDATE myth_mining_pool
       SET distributed_myth = round(distributed_myth + v_myth, 9), updated_at = now()
     WHERE id;

    INSERT INTO myth_balances (user_id, amount, updated_at)
    VALUES (v_user, v_myth, now())
    ON CONFLICT (user_id) DO UPDATE SET amount = round(myth_balances.amount + v_myth, 9), updated_at = now();

    INSERT INTO myth_supply_ledger (entry_type, amount, user_id, reference_id, note)
    VALUES ('MINING', v_myth, v_user, 'hero_mining:' || v_claim_myth::text, 'NFT mining reward');

    INSERT INTO nft_mining_ledger (entry_type, currency, amount, user_id, reference_id)
    VALUES ('NFT_MINING_MYTH_CLAIM', 'myth', v_myth, v_user, v_claim_myth::text);
  END IF;

  RETURN get_hero_mining_state(p_telegram_id)
       || jsonb_build_object('ok', true,
            'currency', CASE WHEN v_ton > 0 AND v_myth > 0 THEN 'hybrid' WHEN v_myth > 0 THEN 'myth' ELSE 'ton' END,
            'claimedTon', v_ton, 'claimedMyth', v_myth,
            'claimId', COALESCE(v_claim, v_claim_myth));
END $function$;

REVOKE ALL ON FUNCTION public.hero_mining_hero_myth_rate(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_effective_daily(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_accrue(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_hero_mining_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_hero_mining(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_mining_hero_myth_rate(text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_effective_daily(text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_accrue(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_hero_mining_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_hero_mining(bigint) TO service_role;