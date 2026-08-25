-- ============================================================
-- 0041 — NFT MINING PASS ACCESS GATE
-- ============================================================

ALTER TABLE public.hero_mining_settings
  ADD COLUMN IF NOT EXISTS pass_gate_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pass_gate_cutoff_at timestamptz NOT NULL DEFAULT '2026-08-25T00:00:00Z',
  ADD COLUMN IF NOT EXISTS pass_gate_price_ton numeric NOT NULL DEFAULT 5;

CREATE TABLE IF NOT EXISTS public.ton_mining_access (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  access_type text NOT NULL DEFAULT 'LOCKED',
  source text,
  granted_at timestamptz,
  mining_access_granted_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ton_mining_access_type_check CHECK (access_type IN ('LEGACY_GRANTED','PASS_GRANTED','MANUAL_GRANTED','LOCKED'))
);

GRANT ALL ON public.ton_mining_access TO service_role;
ALTER TABLE public.ton_mining_access ENABLE ROW LEVEL SECURITY;
-- No anon/authenticated grants: this table is read only through SECURITY DEFINER RPCs.

CREATE INDEX IF NOT EXISTS idx_ton_mining_access_type ON public.ton_mining_access(access_type);

CREATE OR REPLACE FUNCTION public.ton_mining_access_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_ton_mining_access_touch ON public.ton_mining_access;
CREATE TRIGGER trg_ton_mining_access_touch BEFORE UPDATE ON public.ton_mining_access
  FOR EACH ROW EXECUTE FUNCTION public.ton_mining_access_touch();

-- ------------------------------------------------------------
-- Gate helpers
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ton_mining_gate_enabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT pass_gate_enabled FROM hero_mining_settings WHERE id), false);
$$;

CREATE OR REPLACE FUNCTION public.ton_mining_gate_cutoff()
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT pass_gate_cutoff_at FROM hero_mining_settings WHERE id), '2026-08-25T00:00:00Z'::timestamptz);
$$;

-- Official 5 TON pass (adventurer) or above, active season, respecting expiry.
CREATE OR REPLACE FUNCTION public.ton_mining_pass_confirmed_at(p_user_id uuid)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(ps.purchased_at, ps.updated_at)
    FROM public.player_season_pass ps
    JOIN public.season_pass_seasons s ON s.id = ps.season_id
   WHERE ps.user_id = p_user_id
     AND ps.tier IN ('adventurer','legendary')
     AND s.active
     AND (ps.expires_at IS NULL OR ps.expires_at > now())
   ORDER BY COALESCE(ps.purchased_at, ps.updated_at) ASC
   LIMIT 1;
$$;

-- Read-only authorization decision. Never mutates.
CREATE OR REPLACE FUNCTION public.can_access_ton_mining(p_user_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row ton_mining_access%rowtype; v_created timestamptz; v_cutoff timestamptz;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  IF NOT ton_mining_gate_enabled() THEN RETURN 'LEGACY_GRANTED'; END IF;

  SELECT * INTO v_row FROM ton_mining_access WHERE user_id = p_user_id;
  IF v_row.user_id IS NOT NULL AND v_row.access_type = 'LEGACY_GRANTED' THEN RETURN 'LEGACY_GRANTED'; END IF;
  IF v_row.user_id IS NOT NULL AND v_row.access_type = 'MANUAL_GRANTED'
     AND v_row.revoked_at IS NULL
     AND (v_row.expires_at IS NULL OR v_row.expires_at > now()) THEN RETURN 'MANUAL_GRANTED'; END IF;

  v_cutoff := ton_mining_gate_cutoff();
  SELECT created_at INTO v_created FROM game_players WHERE id = p_user_id;
  IF v_created IS NOT NULL AND v_created < v_cutoff THEN RETURN 'LEGACY_GRANTED'; END IF;

  IF ton_mining_pass_confirmed_at(p_user_id) IS NOT NULL THEN RETURN 'PASS_GRANTED'; END IF;
  RETURN 'LOCKED_PASS_REQUIRED';
END $$;

CREATE OR REPLACE FUNCTION public.ton_mining_access_allowed(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.can_access_ton_mining(p_user_id) <> 'LOCKED_PASS_REQUIRED';
$$;

-- Persists the decision and, on a NEW unlock, stamps every mining cursor to now()
-- so a player can never receive retroactive accrual for the locked period.
CREATE OR REPLACE FUNCTION public.ton_mining_access_sync(p_user_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_state text; v_row ton_mining_access%rowtype; v_pass_at timestamptz; v_now timestamptz := now();
BEGIN
  IF p_user_id IS NULL THEN RETURN 'LOCKED_PASS_REQUIRED'; END IF;
  v_state := can_access_ton_mining(p_user_id);
  SELECT * INTO v_row FROM ton_mining_access WHERE user_id = p_user_id;

  -- Legacy snapshot rows and manual grants are authoritative and never rewritten here.
  IF v_row.user_id IS NOT NULL AND v_row.access_type IN ('LEGACY_GRANTED','MANUAL_GRANTED')
     AND v_state IN ('LEGACY_GRANTED','MANUAL_GRANTED') THEN
    RETURN v_state;
  END IF;

  IF v_state = 'PASS_GRANTED' THEN
    v_pass_at := COALESCE(ton_mining_pass_confirmed_at(p_user_id), v_now);
    IF v_row.user_id IS NULL OR v_row.access_type <> 'PASS_GRANTED' THEN
      -- New unlock: flush cursors so accrual starts at the confirmed pass moment.
      UPDATE player_heroes SET mining_last_at = GREATEST(v_pass_at, v_now) WHERE user_id = p_user_id;
      UPDATE player_pets SET mining_last_at = GREATEST(v_pass_at, v_now) WHERE user_id = p_user_id;
      UPDATE nft_equipment SET mining_last_at = GREATEST(v_pass_at, v_now) WHERE owner_user_id = p_user_id;
      UPDATE player_equipment SET mining_last_at = GREATEST(v_pass_at, v_now) WHERE user_id = p_user_id;
      INSERT INTO ton_mining_access(user_id, access_type, source, granted_at, mining_access_granted_at)
      VALUES (p_user_id, 'PASS_GRANTED', 'season_pass_5_ton', v_pass_at, GREATEST(v_pass_at, v_now))
      ON CONFLICT (user_id) DO UPDATE
        SET access_type = 'PASS_GRANTED', source = 'season_pass_5_ton',
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

  -- LOCKED: pass expired or never bought. Keep earned rewards, stop future accrual.
  INSERT INTO ton_mining_access(user_id, access_type, source)
  VALUES (p_user_id, 'LOCKED', 'pass_required')
  ON CONFLICT (user_id) DO UPDATE SET access_type = 'LOCKED', source = 'pass_required';
  RETURN 'LOCKED_PASS_REQUIRED';
END $$;

-- ------------------------------------------------------------
-- Accrual gate: locked players only move cursors forward (no hidden accrual)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_myth_flat numeric := 0; v_pet_myth numeric := 0; v_pet_flat numeric := 0;
        v_eq_myth numeric := 0; v_peq_myth numeric := 0;
        v_out numeric; v_room numeric; v_boost numeric := 0;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() OR NOT public.ton_mining_access_allowed(p_user_id) THEN
    -- Settle cursors to now(): earned rewards stay, no retroactive accrual later.
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE player_pets SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE nft_equipment SET mining_last_at = v_now WHERE owner_user_id = p_user_id;
    UPDATE player_equipment SET mining_last_at = v_now WHERE user_id = p_user_id AND COALESCE(mining_daily_myth,0) > 0;
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
           hero_mining_hero_dual(h.nft_hero_id) AS dual,
           COALESCE(h.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.dual AS dual, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT
    COALESCE(SUM(CASE WHEN rate > 0 THEN rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_ton_gain, v_myth_gain, v_myth_flat
    FROM moved;

  WITH pelig AS (
    SELECT p.id, GREATEST(COALESCE(p.mining_daily_myth, 0), 0) AS myth_rate,
           COALESCE(p.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(p.mining_last_at, p.created_at, v_now)))) AS secs
      FROM player_pets p
     WHERE p.user_id = p_user_id
       AND COALESCE(p.mining_daily_myth, 0) > 0
       AND NOT COALESCE(p.market_locked, false)
  ), pmoved AS (
    UPDATE player_pets pp SET mining_last_at = v_now
      FROM pelig e WHERE pp.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT COALESCE(SUM(CASE WHEN NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_pet_myth, v_pet_flat FROM pmoved;

  WITH eelig AS (
    SELECT n.id, GREATEST(COALESCE(n.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(n.mining_last_at, n.assigned_at, n.created_at, v_now)))) AS secs
      FROM nft_equipment n
     WHERE n.owner_user_id = p_user_id
       AND n.status <> 'BURNED'
       AND COALESCE(n.mining_daily_myth, 0) > 0
  ), emoved AS (
    UPDATE nft_equipment ne SET mining_last_at = v_now
      FROM eelig e WHERE ne.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_eq_myth FROM emoved;

  WITH qelig AS (
    SELECT q.id, GREATEST(COALESCE(q.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(q.mining_last_at, q.created_at, v_now)))) AS secs
      FROM player_equipment q
     WHERE q.user_id = p_user_id
       AND COALESCE(q.mining_daily_myth, 0) > 0
       AND NOT COALESCE(q.market_locked, false)
       AND NOT EXISTS (SELECT 1 FROM nft_equipment n WHERE n.player_equipment_id = q.id)
  ), qmoved AS (
    UPDATE player_equipment pq SET mining_last_at = v_now
      FROM qelig e WHERE pq.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_peq_myth FROM qmoved;

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0) + GREATEST(v_eq_myth, 0) + GREATEST(v_peq_myth, 0);

  v_boost := GREATEST(COALESCE(public.veteran_v2_boost_percent(p_user_id), 0), 0);
  v_myth_gain := round(v_myth_gain * (1 + v_boost / 100.0) + GREATEST(v_myth_flat, 0) + GREATEST(v_pet_flat, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
   RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END
$function$;

-- ------------------------------------------------------------
-- Player state: expose the access decision
-- ------------------------------------------------------------
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
         COALESCE(SUM(hero_mining_hero_rate(h.rarity, h.nft_hero_id)), 0),
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
    'miningAccess', v_access,
    'accessLocked', v_locked,
    'passGate', jsonb_build_object(
      'enabled', COALESCE(s.pass_gate_enabled, false),
      'cutoffAt', COALESCE(s.pass_gate_cutoff_at, '2026-08-25T00:00:00Z'::timestamptz),
      'priceTon', COALESCE(s.pass_gate_price_ton, 5)),
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

-- ------------------------------------------------------------
-- Claim gate (server side authority)
-- ------------------------------------------------------------
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
        v_pending_ton numeric; v_pending_myth numeric; v_access text;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF NOT hero_mining_enabled() THEN RAISE EXCEPTION 'MINING_DISABLED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('hero_mining_claim:' || v_user::text));
  v_access := ton_mining_access_sync(v_user);
  PERFORM hero_mining_accrue(v_user);

  SELECT round(COALESCE(hero_mining_unclaimed_ton,0),9), round(COALESCE(hero_mining_unclaimed_myth,0),9),
         round(COALESCE(hero_mining_invested_ton, 0), 9), round(COALESCE(hero_mining_returned_ton, 0), 9)
    INTO v_pending_ton, v_pending_myth, v_invested, v_returned
    FROM game_players WHERE id = v_user;

  -- Locked players may only settle rewards legitimately earned BEFORE the lock.
  IF v_access = 'LOCKED_PASS_REQUIRED' AND v_pending_ton <= 0 AND v_pending_myth <= 0 THEN
    RAISE EXCEPTION 'MINING_PASS_REQUIRED';
  END IF;

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

  v_room := GREATEST(0, round(v_invested - v_returned, 9));
  IF v_invested > 0 AND v_room > 0 THEN
    v_ton := round(LEAST(v_pending_ton, v_room), 9);
    IF v_ton < GREATEST(v_min_ton, 0.000001) THEN v_ton := 0; END IF;
  END IF;

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

-- ------------------------------------------------------------
-- LEGACY SNAPSHOT + safety check (only enables the gate if counts match)
-- ------------------------------------------------------------
DO $$
DECLARE v_cutoff timestamptz := '2026-08-25T00:00:00Z'; v_expected bigint; v_marked bigint;
BEGIN
  SELECT COUNT(*) INTO v_expected FROM game_players WHERE created_at < v_cutoff;

  INSERT INTO public.ton_mining_access(user_id, access_type, source, granted_at)
  SELECT g.id, 'LEGACY_GRANTED', 'cutoff_snapshot_2026_08_25', now()
    FROM game_players g WHERE g.created_at < v_cutoff
  ON CONFLICT (user_id) DO UPDATE SET access_type = 'LEGACY_GRANTED', revoked_at = NULL;

  SELECT COUNT(*) INTO v_marked FROM public.ton_mining_access WHERE access_type = 'LEGACY_GRANTED';

  IF v_marked < v_expected THEN
    RAISE EXCEPTION 'LEGACY_SNAPSHOT_MISMATCH expected % marked %', v_expected, v_marked;
  END IF;

  UPDATE hero_mining_settings
     SET pass_gate_enabled = true, pass_gate_cutoff_at = v_cutoff, pass_gate_price_ton = 5, updated_at = now()
   WHERE id;

  RAISE NOTICE 'TON MINING GATE ON — legacy % of %', v_marked, v_expected;
END $$;

-- ------------------------------------------------------------
-- ADMIN BOT RPCs
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_ton_mining_gate(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE s hero_mining_settings%rowtype;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  RETURN jsonb_build_object(
    'enabled', COALESCE(s.pass_gate_enabled, false),
    'cutoffAt', s.pass_gate_cutoff_at,
    'priceTon', COALESCE(s.pass_gate_price_ton, 5),
    'legacyUsers', (SELECT COUNT(*) FROM ton_mining_access WHERE access_type = 'LEGACY_GRANTED'),
    'passUsers', (SELECT COUNT(*) FROM ton_mining_access WHERE access_type = 'PASS_GRANTED'),
    'manualUsers', (SELECT COUNT(*) FROM ton_mining_access WHERE access_type = 'MANUAL_GRANTED'),
    'lockedUsers', (SELECT COUNT(*) FROM ton_mining_access WHERE access_type = 'LOCKED'),
    'usersAfterCutoff', (SELECT COUNT(*) FROM game_players WHERE created_at >= COALESCE(s.pass_gate_cutoff_at, now())),
    'totalUsers', (SELECT COUNT(*) FROM game_players)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mining_gate_set(p_admin_id bigint, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  UPDATE hero_mining_settings SET pass_gate_enabled = COALESCE(p_enabled, false), updated_at = now() WHERE id;
  PERFORM admin_log(p_admin_id, 'ton_mining_gate_toggle', 'hero_mining', 'pass_gate', NULL,
    jsonb_build_object('enabled', p_enabled), 'pass gate do NFT mining alternado', '{}'::jsonb);
  RETURN admin_ton_mining_gate(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mining_gate_cutoff(p_admin_id bigint, p_cutoff timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old timestamptz;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_cutoff IS NULL THEN RAISE EXCEPTION 'INVALID_CUTOFF'; END IF;
  SELECT pass_gate_cutoff_at INTO v_old FROM hero_mining_settings WHERE id;
  UPDATE hero_mining_settings SET pass_gate_cutoff_at = p_cutoff, updated_at = now() WHERE id;

  -- Re-snapshot legacy players for the new cutoff (never blocks anyone already legacy).
  INSERT INTO public.ton_mining_access(user_id, access_type, source, granted_at)
  SELECT g.id, 'LEGACY_GRANTED', 'cutoff_resnapshot', now()
    FROM game_players g WHERE g.created_at < p_cutoff
  ON CONFLICT (user_id) DO UPDATE SET access_type = 'LEGACY_GRANTED', revoked_at = NULL;

  PERFORM admin_log(p_admin_id, 'ton_mining_gate_cutoff', 'hero_mining', 'pass_gate',
    jsonb_build_object('cutoffAt', v_old), jsonb_build_object('cutoffAt', p_cutoff), 'cutoff do pass gate alterado', '{}'::jsonb);
  RETURN admin_ton_mining_gate(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mining_gate_users(p_admin_id bigint, p_type text, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_type text := UPPER(COALESCE(p_type, 'LOCKED'));
BEGIN
  PERFORM admin_assert(p_admin_id);
  RETURN jsonb_build_object('type', v_type, 'users', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'telegramId', g.telegram_id, 'name', COALESCE(g.display_name, g.first_name),
      'createdAt', g.created_at, 'accessType', a.access_type, 'grantedAt', a.granted_at,
      'miningStartedAt', a.mining_access_granted_at, 'source', a.source) ORDER BY a.updated_at DESC)
    FROM (SELECT * FROM ton_mining_access WHERE access_type = v_type ORDER BY updated_at DESC LIMIT GREATEST(COALESCE(p_limit,20),1)) a
    JOIN game_players g ON g.id = a.user_id), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mining_gate_grant(p_admin_id bigint, p_telegram_id bigint, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_now timestamptz := now();
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = v_user;
  UPDATE player_pets SET mining_last_at = v_now WHERE user_id = v_user;
  UPDATE nft_equipment SET mining_last_at = v_now WHERE owner_user_id = v_user;
  UPDATE player_equipment SET mining_last_at = v_now WHERE user_id = v_user;

  INSERT INTO ton_mining_access(user_id, access_type, source, granted_at, mining_access_granted_at, note)
  VALUES (v_user, 'MANUAL_GRANTED', 'admin', v_now, v_now, p_note)
  ON CONFLICT (user_id) DO UPDATE
    SET access_type = 'MANUAL_GRANTED', source = 'admin', granted_at = v_now,
        mining_access_granted_at = v_now, revoked_at = NULL, expires_at = NULL, note = p_note;

  PERFORM admin_log(p_admin_id, 'ton_mining_access_grant', 'player', p_telegram_id::text, NULL,
    jsonb_build_object('accessType', 'MANUAL_GRANTED', 'note', p_note), 'acesso manual ao NFT mining concedido', '{}'::jsonb);
  RETURN jsonb_build_object('ok', true, 'telegramId', p_telegram_id, 'accessType', 'MANUAL_GRANTED');
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mining_gate_revoke(p_admin_id bigint, p_telegram_id bigint, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_type text;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT access_type INTO v_type FROM ton_mining_access WHERE user_id = v_user;
  IF v_type IS DISTINCT FROM 'MANUAL_GRANTED' THEN RAISE EXCEPTION 'NOT_A_MANUAL_GRANT'; END IF;

  UPDATE ton_mining_access
     SET access_type = 'LOCKED', revoked_at = now(), source = 'admin_revoke', note = p_note
   WHERE user_id = v_user;

  PERFORM admin_log(p_admin_id, 'ton_mining_access_revoke', 'player', p_telegram_id::text,
    jsonb_build_object('accessType', v_type), jsonb_build_object('accessType', 'LOCKED'),
    'acesso manual ao NFT mining revogado', '{}'::jsonb);
  RETURN jsonb_build_object('ok', true, 'telegramId', p_telegram_id, 'accessType', 'LOCKED');
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mining_gate_audit(p_admin_id bigint, p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; a ton_mining_access%rowtype; g game_players%rowtype;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO g FROM game_players WHERE telegram_id = p_telegram_id;
  IF g.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_user := g.id;
  SELECT * INTO a FROM ton_mining_access WHERE user_id = v_user;
  RETURN jsonb_build_object(
    'telegramId', p_telegram_id,
    'name', COALESCE(g.display_name, g.first_name),
    'createdAt', g.created_at,
    'cutoffAt', ton_mining_gate_cutoff(),
    'access', can_access_ton_mining(v_user),
    'stored', COALESCE(a.access_type, 'NONE'),
    'source', a.source,
    'grantedAt', a.granted_at,
    'miningStartedAt', a.mining_access_granted_at,
    'passTier', COALESCE(has_active_season_pass(v_user), 'none'),
    'passConfirmedAt', ton_mining_pass_confirmed_at(v_user),
    'unclaimedTon', round(COALESCE(g.hero_mining_unclaimed_ton,0),9),
    'unclaimedMyth', round(COALESCE(g.hero_mining_unclaimed_myth,0),9),
    'lifetimeTon', round(COALESCE(g.hero_mining_lifetime_ton,0),9),
    'lifetimeMyth', round(COALESCE(g.hero_mining_lifetime_myth,0),9),
    'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('action', l.action, 'newValue', l.new_value, 'createdAt', l.created_at) ORDER BY l.created_at DESC)
      FROM (SELECT * FROM admin_audit_logs WHERE target_type = 'player' AND target_id = p_telegram_id::text
              AND action LIKE 'ton_mining_access%' ORDER BY created_at DESC LIMIT 10) l), '[]'::jsonb)
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_ton_mining_gate(bigint) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_ton_mining_gate_set(bigint, boolean) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_ton_mining_gate_cutoff(bigint, timestamptz) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_ton_mining_gate_users(bigint, text, integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_ton_mining_gate_grant(bigint, bigint, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_ton_mining_gate_revoke(bigint, bigint, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_ton_mining_gate_audit(bigint, bigint) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.can_access_ton_mining(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ton_mining_access_sync(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ton_mining_access_allowed(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ton_mining_pass_confirmed_at(uuid) FROM anon, authenticated;