ALTER TABLE public.hero_mining_settings
  ADD COLUMN IF NOT EXISTS pass_exclusive_myth_per_day numeric NOT NULL DEFAULT 1500;

-- Per-unit MYTH override: pass chest units mine MYTH even though they are not 1/1 NFTs.
ALTER TABLE public.player_heroes ADD COLUMN IF NOT EXISTS mining_daily_myth numeric NOT NULL DEFAULT 0;
ALTER TABLE public.player_pets ADD COLUMN IF NOT EXISTS mining_daily_myth numeric NOT NULL DEFAULT 0;
ALTER TABLE public.player_pets ADD COLUMN IF NOT EXISTS mining_last_at timestamptz;

CREATE OR REPLACE FUNCTION public.pass_exclusive_myth_rate()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(COALESCE((SELECT pass_exclusive_myth_per_day FROM hero_mining_settings LIMIT 1), 1500), 0)
$$;
REVOKE ALL ON FUNCTION public.pass_exclusive_myth_rate() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pass_exclusive_myth_rate() TO service_role;

-- Backfill every exclusive pass unit already delivered.
UPDATE public.player_heroes SET mining_daily_myth = public.pass_exclusive_myth_rate(), mining_last_at = COALESCE(mining_last_at, now())
 WHERE COALESCE(pass_exclusive,false) AND mining_daily_myth <= 0;
UPDATE public.player_pets SET mining_daily_myth = public.pass_exclusive_myth_rate(), mining_last_at = COALESCE(mining_last_at, now())
 WHERE COALESCE(pass_exclusive,false) AND mining_daily_myth <= 0;

-- Accrual: TON for units frozen in TON, MYTH for units carrying a MYTH rate (heroes + pets).
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_pet_myth numeric := 0; v_out numeric; v_room numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE player_pets SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  v_room := GREATEST(COALESCE(hero_mining_remaining(p_user_id), 0), 0);

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(
             COALESCE(h.mining_daily_myth, 0),
             CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                  ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END
           ) AS myth_rate,
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

  WITH pelig AS (
    SELECT p.id, GREATEST(COALESCE(p.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(p.mining_last_at, p.created_at, v_now)))) AS secs
      FROM player_pets p
     WHERE p.user_id = p_user_id
       AND COALESCE(p.mining_daily_myth, 0) > 0
       AND NOT COALESCE(p.market_locked, false)
  ), pmoved AS (
    UPDATE player_pets pp SET mining_last_at = v_now
      FROM pelig e WHERE pp.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_pet_myth FROM pmoved;

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := round(GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END $function$;

-- Dashboard totals must include the pass chest MYTH rate (heroes + pets).
CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; u game_players%rowtype; v_count integer;
        v_rate_ton numeric; v_rate_myth numeric; v_pet_rate_myth numeric; v_pet_count integer;
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
         COALESCE(SUM(CASE WHEN GREATEST(COALESCE(h.mining_daily_myth,0), hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id)) <= 0
                           THEN hero_mining_hero_rate(h.rarity, h.nft_hero_id) ELSE 0 END), 0),
         COALESCE(SUM(GREATEST(COALESCE(h.mining_daily_myth,0), hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id), 0)), 0)
    INTO v_count, v_rate_ton, v_rate_myth
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND (COALESCE(h.mining_daily_myth,0) > 0
          OR (NOT COALESCE(h.pass_exclusive,false)
              AND (hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0
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
    'miningCurrency', CASE WHEN COALESCE(v_rate_myth,0) > 0 AND COALESCE(v_rate_ton,0) > 0 THEN 'hybrid'
                           WHEN COALESCE(v_rate_myth,0) > 0 THEN 'myth' ELSE 'ton' END,
    'currencyChangedAt', s.currency_changed_at,
    'mythPerDay', round(COALESCE(s.myth_per_day, 0), 9),
    'passExclusiveMythPerDay', round(COALESCE(s.pass_exclusive_myth_per_day, 0), 9),
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