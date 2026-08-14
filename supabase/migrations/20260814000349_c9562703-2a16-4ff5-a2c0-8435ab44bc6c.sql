-- ============================================================ HERO MINING ROI CAP
-- Hero TON mining can never return more TON than the player really invested.
-- Rates per rarity are untouched. NFT Exclusive mining is untouched.

CREATE TABLE IF NOT EXISTS public.hero_mining_investments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  source_type text NOT NULL,
  reference text NOT NULL UNIQUE,
  amount_ton numeric NOT NULL CHECK (amount_ton > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.hero_mining_investments TO service_role;
ALTER TABLE public.hero_mining_investments ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS hero_mining_investments_user_idx ON public.hero_mining_investments (user_id, created_at DESC);

ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS hero_mining_invested_ton numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hero_mining_returned_ton numeric NOT NULL DEFAULT 0;

-- Already claimed hero mining counts as returned (lifetime value, never reset).
UPDATE public.game_players
   SET hero_mining_returned_ton = round(COALESCE(hero_mining_lifetime_ton, 0), 9)
 WHERE COALESCE(hero_mining_returned_ton, 0) = 0
   AND COALESCE(hero_mining_lifetime_ton, 0) > 0;

-- ------------------------------------------------------------ investment ledger
CREATE OR REPLACE FUNCTION public.hero_mining_sync_invested(p_user_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_total numeric;
BEGIN
  SELECT round(COALESCE(SUM(amount_ton), 0), 9) INTO v_total
    FROM hero_mining_investments WHERE user_id = p_user_id;
  UPDATE game_players SET hero_mining_invested_ton = v_total, updated_at = now()
   WHERE id = p_user_id;
  RETURN COALESCE(v_total, 0);
END $$;

/** Registers one confirmed TON transaction as mining capacity. Idempotent per reference. */
CREATE OR REPLACE FUNCTION public.hero_mining_register_investment(
  p_user_id uuid, p_source_type text, p_reference text, p_amount_ton numeric)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ref text;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_amount_ton, 0) <= 0 THEN RETURN 0; END IF;
  v_ref := nullif(btrim(COALESCE(p_reference, '')), '');
  IF v_ref IS NULL THEN RETURN 0; END IF;

  INSERT INTO hero_mining_investments (user_id, source_type, reference, amount_ton)
  VALUES (p_user_id, lower(COALESCE(nullif(btrim(p_source_type), ''), 'purchase')), v_ref, round(p_amount_ton, 9))
  ON CONFLICT (reference) DO NOTHING;

  RETURN hero_mining_sync_invested(p_user_id);
END $$;

/** Removes capacity when a transaction is refunded/cancelled/failed. */
CREATE OR REPLACE FUNCTION public.hero_mining_revoke_investment(p_reference text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid;
BEGIN
  DELETE FROM hero_mining_investments WHERE reference = btrim(COALESCE(p_reference, ''))
  RETURNING user_id INTO v_user;
  IF v_user IS NOT NULL THEN PERFORM hero_mining_sync_invested(v_user); END IF;
END $$;

/** Remaining ROI capacity: eligible invested TON minus TON already returned by heroes. */
CREATE OR REPLACE FUNCTION public.hero_mining_remaining(p_user_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(0, round(COALESCE(g.hero_mining_invested_ton, 0)
                         - COALESCE(g.hero_mining_returned_ton, 0)
                         - COALESCE(g.hero_mining_unclaimed_ton, 0), 9))
    FROM game_players g WHERE g.id = p_user_id;
$$;

-- ------------------------------------------------------------ eligible TON payment hooks
CREATE OR REPLACE FUNCTION public.hero_mining_track_ton_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ref text; v_type text; v_amount numeric; v_status text; v_old text;
BEGIN
  IF TG_TABLE_NAME = 'wallet_deposits' THEN
    v_ref := 'deposit:' || NEW.id::text; v_type := 'ton_deposit'; v_amount := COALESCE(NEW.amount_ton, 0);
  ELSIF TG_TABLE_NAME = 'pet_egg_orders' THEN
    v_ref := 'egg_order:' || NEW.id::text; v_type := 'premium_egg'; v_amount := COALESCE(NEW.price_ton, 0);
  ELSIF TG_TABLE_NAME = 'season_pass_orders' THEN
    v_ref := 'pass_order:' || NEW.id::text; v_type := 'battle_pass'; v_amount := COALESCE(NEW.price_ton, 0);
  ELSE
    v_ref := 'nft_order:' || NEW.id::text; v_type := 'nft_pet_purchase'; v_amount := COALESCE(NEW.price_ton, 0);
  END IF;

  v_status := lower(COALESCE(NEW.status, ''));
  v_old := lower(COALESCE(OLD.status, ''));
  IF v_status = v_old THEN RETURN NEW; END IF;

  IF v_status IN ('confirmed','completed','credited','delivered','activated','paid_confirmed') THEN
    PERFORM hero_mining_register_investment(NEW.user_id, v_type, v_ref, v_amount);
  ELSIF v_status IN ('refunded','reversed','cancelled','failed') THEN
    PERFORM hero_mining_revoke_investment(v_ref);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS hero_mining_track_deposit_trg ON public.wallet_deposits;
CREATE TRIGGER hero_mining_track_deposit_trg
AFTER UPDATE OF status ON public.wallet_deposits
FOR EACH ROW EXECUTE FUNCTION public.hero_mining_track_ton_payment();

DROP TRIGGER IF EXISTS hero_mining_track_egg_trg ON public.pet_egg_orders;
CREATE TRIGGER hero_mining_track_egg_trg
AFTER UPDATE OF status ON public.pet_egg_orders
FOR EACH ROW EXECUTE FUNCTION public.hero_mining_track_ton_payment();

DROP TRIGGER IF EXISTS hero_mining_track_pass_trg ON public.season_pass_orders;
CREATE TRIGGER hero_mining_track_pass_trg
AFTER UPDATE OF status ON public.season_pass_orders
FOR EACH ROW EXECUTE FUNCTION public.hero_mining_track_ton_payment();

DROP TRIGGER IF EXISTS hero_mining_track_nft_trg ON public.nft_pet_orders;
CREATE TRIGGER hero_mining_track_nft_trg
AFTER UPDATE OF status ON public.nft_pet_orders
FOR EACH ROW EXECUTE FUNCTION public.hero_mining_track_ton_payment();

-- Backfill: confirmed history only (free rewards are never included).
INSERT INTO public.hero_mining_investments (user_id, source_type, reference, amount_ton)
SELECT user_id, 'ton_deposit', 'deposit:' || id::text, round(amount_ton, 9)
  FROM public.wallet_deposits
 WHERE user_id IS NOT NULL AND COALESCE(amount_ton, 0) > 0
   AND lower(COALESCE(status, '')) IN ('confirmed','completed','credited','delivered','activated','paid_confirmed')
ON CONFLICT (reference) DO NOTHING;

INSERT INTO public.hero_mining_investments (user_id, source_type, reference, amount_ton)
SELECT user_id, 'premium_egg', 'egg_order:' || id::text, round(price_ton, 9)
  FROM public.pet_egg_orders
 WHERE user_id IS NOT NULL AND COALESCE(price_ton, 0) > 0
   AND lower(COALESCE(status, '')) IN ('confirmed','completed','credited','delivered','activated','paid_confirmed')
ON CONFLICT (reference) DO NOTHING;

INSERT INTO public.hero_mining_investments (user_id, source_type, reference, amount_ton)
SELECT user_id, 'battle_pass', 'pass_order:' || id::text, round(price_ton, 9)
  FROM public.season_pass_orders
 WHERE user_id IS NOT NULL AND COALESCE(price_ton, 0) > 0
   AND lower(COALESCE(status, '')) IN ('confirmed','completed','credited','delivered','activated','paid_confirmed')
ON CONFLICT (reference) DO NOTHING;

INSERT INTO public.hero_mining_investments (user_id, source_type, reference, amount_ton)
SELECT user_id, 'nft_pet_purchase', 'nft_order:' || id::text, round(price_ton, 9)
  FROM public.nft_pet_orders
 WHERE user_id IS NOT NULL AND COALESCE(price_ton, 0) > 0
   AND lower(COALESCE(status, '')) IN ('confirmed','completed','credited','delivered','activated','paid_confirmed')
ON CONFLICT (reference) DO NOTHING;

UPDATE public.game_players g
   SET hero_mining_invested_ton = COALESCE(i.total, 0)
  FROM (SELECT user_id, round(SUM(amount_ton), 9) AS total FROM public.hero_mining_investments GROUP BY user_id) i
 WHERE i.user_id = g.id;

-- ------------------------------------------------------------ capped accrual
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_now timestamptz := now(); v_gain numeric := 0; v_unclaimed numeric; v_room numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  -- ROI cap: remaining capacity = eligible invested TON - already returned - pending unclaimed.
  v_room := COALESCE(hero_mining_remaining(p_user_id), 0);
  IF v_room <= 0 THEN
    -- No investment left to recover: cursors move forward so nothing is produced.
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  WITH elig AS (
    SELECT h.id,
           hero_mining_rate(h.rarity) AS rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND NOT COALESCE(h.market_locked, false)
       AND NOT COALESCE(h.is_nft_exclusive, false)
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate * e.secs / 86400.0 AS gain
  )
  SELECT COALESCE(SUM(gain), 0) INTO v_gain FROM moved;

  -- Never exceed the total eligible TON invested.
  v_gain := round(LEAST(GREATEST(v_gain, 0), v_room), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_unclaimed;

  RETURN COALESCE(v_unclaimed, 0);
END $$;

-- Per-hero settlement respects the same cap.
CREATE OR REPLACE FUNCTION public.hero_mining_settle_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_gain numeric := 0; v_secs numeric; v_room numeric := 0;
BEGIN
  IF OLD.user_id IS NOT NULL THEN v_room := COALESCE(hero_mining_remaining(OLD.user_id), 0); END IF;

  IF v_room > 0
     AND NOT COALESCE(OLD.market_locked, false)
     AND NOT COALESCE(OLD.is_nft_exclusive, false)
     AND hero_mining_enabled() THEN
    v_secs := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(OLD.mining_last_at, OLD.created_at, now()))));
    v_gain := round(LEAST(hero_mining_rate(OLD.rarity) * v_secs / 86400.0, v_room), 9);
  END IF;

  IF v_gain > 0 AND OLD.user_id IS NOT NULL THEN
    UPDATE game_players
       SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
           updated_at = now()
     WHERE id = OLD.user_id;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    NEW.mining_last_at := now();
    RETURN NEW;
  END IF;
  RETURN OLD;
END $$;

-- ------------------------------------------------------------ player state
CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; u game_players%rowtype; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric;
        v_invested numeric; v_returned numeric; v_remaining numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  v_unclaimed := hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;
  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;

  v_invested := round(COALESCE(u.hero_mining_invested_ton, 0), 9);
  v_returned := round(COALESCE(u.hero_mining_returned_ton, 0), 9);
  v_remaining := GREATEST(0, round(v_invested - v_returned - COALESCE(v_unclaimed, 0), 9));

  SELECT COUNT(*), COALESCE(SUM(hero_mining_rate(h.rarity)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.market_locked, false)
     AND NOT COALESCE(h.is_nft_exclusive, false)
     AND hero_mining_rate(h.rarity) > 0;

  RETURN jsonb_build_object(
    'enabled', hero_mining_enabled(),
    'dailyRateTon', round(COALESCE(v_rate, 0), 9),
    'unclaimedTon', round(COALESCE(v_unclaimed, 0), 9),
    'lifetimeTon', round(COALESCE(u.hero_mining_lifetime_ton, 0), 9),
    'investedTon', v_invested,
    'returnedTon', v_returned,
    'remainingTon', v_remaining,
    'roiLimitReached', (v_invested > 0 AND v_remaining <= 0),
    'hasInvestment', (v_invested > 0),
    'eligibleHeroes', COALESCE(v_count, 0),
    'availableTon', round(COALESCE(u.ton_balance, 0), 9),
    'minClaimTon', COALESCE(v_min, 0),
    'lastClaimAt', u.hero_mining_claimed_at,
    'updatedAt', now(),
    'rates', COALESCE((SELECT jsonb_object_agg(rarity, ton_per_day) FROM hero_mining_rates), '{}'::jsonb),
    'investments', COALESCE((SELECT jsonb_agg(jsonb_build_object('sourceType', i.source_type, 'amountTon', i.amount_ton, 'createdAt', i.created_at) ORDER BY i.created_at DESC)
      FROM (SELECT * FROM hero_mining_investments WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) i), '[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'amountTon', c.amount_ton, 'heroCount', c.hero_count,
        'ratePerDay', c.rate_per_day, 'createdAt', c.created_at) ORDER BY c.created_at DESC)
      FROM (SELECT * FROM hero_mining_claims WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) c), '[]'::jsonb)
  );
END $$;

-- ------------------------------------------------------------ CLAIM ALL (capped)
CREATE OR REPLACE FUNCTION public.claim_hero_mining(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric; v_claim uuid;
        v_invested numeric; v_returned numeric; v_room numeric; v_claimable numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF NOT hero_mining_enabled() THEN RAISE EXCEPTION 'MINING_DISABLED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('hero_mining_claim:' || v_user::text));

  v_unclaimed := hero_mining_accrue(v_user);

  SELECT round(COALESCE(hero_mining_invested_ton, 0), 9), round(COALESCE(hero_mining_returned_ton, 0), 9)
    INTO v_invested, v_returned FROM game_players WHERE id = v_user;

  IF v_invested <= 0 THEN RAISE EXCEPTION 'NO_TON_INVESTMENT'; END IF;

  v_room := GREATEST(0, round(v_invested - v_returned, 9));
  IF v_room <= 0 THEN RAISE EXCEPTION 'ROI_LIMIT_REACHED'; END IF;

  -- claimable = MIN(generated by heroes, remaining mining capacity)
  v_claimable := round(LEAST(COALESCE(v_unclaimed, 0), v_room), 9);

  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;
  IF v_claimable < GREATEST(COALESCE(v_min, 0), 0.000001) THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;

  SELECT COUNT(*), COALESCE(SUM(hero_mining_rate(h.rarity)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.market_locked, false)
     AND NOT COALESCE(h.is_nft_exclusive, false)
     AND hero_mining_rate(h.rarity) > 0;

  INSERT INTO hero_mining_claims (user_id, amount_ton, hero_count, rate_per_day)
  VALUES (v_user, v_claimable, COALESCE(v_count, 0), round(COALESCE(v_rate, 0), 9))
  RETURNING id INTO v_claim;

  UPDATE game_players
     SET hero_mining_unclaimed_ton = GREATEST(0, round(COALESCE(hero_mining_unclaimed_ton, 0) - v_claimable, 9)),
         hero_mining_lifetime_ton = round(COALESCE(hero_mining_lifetime_ton, 0) + v_claimable, 9),
         hero_mining_returned_ton = round(COALESCE(hero_mining_returned_ton, 0) + v_claimable, 9),
         hero_mining_claimed_at = now(),
         updated_at = now()
   WHERE id = v_user;

  -- Credited as real, withdrawable TON (never counts as a new investment).
  PERFORM credit_ton_reward(v_user, v_claimable, 'hero_mining', 'hero_mining:' || v_claim::text, 'Hero TON Mining');

  RETURN get_hero_mining_state(p_telegram_id)
       || jsonb_build_object('ok', true, 'claimedTon', v_claimable, 'claimId', v_claim);
END $$;

-- ------------------------------------------------------------ admin visibility
CREATE OR REPLACE FUNCTION public.admin_hero_mining_user(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; g game_players%rowtype;
BEGIN
  PERFORM admin_assert(p_admin_id);
  v_user := admin_resolve_player(p_ref);
  PERFORM hero_mining_accrue(v_user);
  SELECT * INTO g FROM game_players WHERE id = v_user;
  RETURN jsonb_build_object(
    'telegramId', g.telegram_id,
    'name', COALESCE(g.display_name, g.first_name),
    'unclaimedTon', round(COALESCE(g.hero_mining_unclaimed_ton, 0), 9),
    'lifetimeTon', round(COALESCE(g.hero_mining_lifetime_ton, 0), 9),
    'investedTon', round(COALESCE(g.hero_mining_invested_ton, 0), 9),
    'returnedTon', round(COALESCE(g.hero_mining_returned_ton, 0), 9),
    'remainingTon', GREATEST(0, round(COALESCE(g.hero_mining_invested_ton, 0) - COALESCE(g.hero_mining_returned_ton, 0), 9)),
    'lastClaimAt', g.hero_mining_claimed_at,
    'availableTon', round(COALESCE(g.ton_balance, 0), 9),
    'dailyRateTon', (SELECT COALESCE(SUM(hero_mining_rate(h.rarity)), 0) FROM player_heroes h
       WHERE h.user_id = v_user AND NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false)),
    'eligibleHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE h.user_id = v_user
       AND NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false) AND hero_mining_rate(h.rarity) > 0),
    'pausedHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE h.user_id = v_user AND COALESCE(h.market_locked, false)),
    'investments', COALESCE((SELECT jsonb_agg(jsonb_build_object('sourceType', i.source_type, 'amountTon', i.amount_ton, 'createdAt', i.created_at) ORDER BY i.created_at DESC)
      FROM (SELECT * FROM hero_mining_investments WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) i), '[]'::jsonb),
    'byRarity', COALESCE((SELECT jsonb_agg(jsonb_build_object('rarity', r.rarity, 'count', r.qty, 'tonPerDay', round(r.qty * hero_mining_rate(r.rarity), 9)) ORDER BY r.rarity)
      FROM (SELECT lower(h.rarity) AS rarity, COUNT(*) AS qty FROM player_heroes h
             WHERE h.user_id = v_user AND NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false)
             GROUP BY 1) r), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s hero_mining_settings%rowtype;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  RETURN jsonb_build_object(
    'enabled', COALESCE(s.enabled, true),
    'minClaimTon', COALESCE(s.min_claim_ton, 0),
    'updatedAt', s.updated_at,
    'rates', COALESCE((SELECT jsonb_agg(jsonb_build_object('rarity', rarity, 'tonPerDay', ton_per_day) ORDER BY ton_per_day) FROM hero_mining_rates), '[]'::jsonb),
    'eligibleHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false) AND hero_mining_rate(h.rarity) > 0),
    'pausedHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE COALESCE(h.market_locked, false) AND hero_mining_rate(h.rarity) > 0),
    'networkDailyTon', (SELECT COALESCE(SUM(hero_mining_rate(h.rarity)), 0) FROM player_heroes h WHERE NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false)),
    'unclaimedTon', (SELECT COALESCE(SUM(hero_mining_unclaimed_ton), 0) FROM game_players),
    'claimedTon', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_claims),
    'claimedTon24h', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_claims WHERE created_at > now() - interval '24 hours'),
    'investedTon', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_investments),
    'returnedTon', (SELECT COALESCE(SUM(hero_mining_returned_ton), 0) FROM game_players),
    'investorsCount', (SELECT COUNT(DISTINCT user_id) FROM hero_mining_investments),
    'capReachedPlayers', (SELECT COUNT(*) FROM game_players WHERE COALESCE(hero_mining_invested_ton, 0) > 0
        AND COALESCE(hero_mining_returned_ton, 0) >= COALESCE(hero_mining_invested_ton, 0)),
    'claims', (SELECT COALESCE(jsonb_agg(jsonb_build_object('amountTon', c.amount_ton, 'heroCount', c.hero_count,
        'createdAt', c.created_at, 'telegramId', g.telegram_id, 'name', COALESCE(g.display_name, g.first_name)) ORDER BY c.created_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM hero_mining_claims ORDER BY created_at DESC LIMIT 15) c
      JOIN game_players g ON g.id = c.user_id)
  );
END $$;

-- ------------------------------------------------------------ privileges (service_role only)
REVOKE ALL ON FUNCTION public.hero_mining_sync_invested(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_register_investment(uuid, text, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_revoke_investment(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_remaining(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_track_ton_payment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_accrue(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_settle_row() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_hero_mining_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_hero_mining(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_mining_user(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_mining_overview(bigint) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.hero_mining_sync_invested(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_register_investment(uuid, text, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_revoke_investment(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_remaining(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_accrue(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_hero_mining_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_hero_mining(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_mining_user(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_mining_overview(bigint) TO service_role;