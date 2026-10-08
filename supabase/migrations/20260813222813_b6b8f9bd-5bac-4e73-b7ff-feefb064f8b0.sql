-- ============================================================ HERO TON MINING
-- Passive TON generation driven exclusively by hero RARITY.
-- No combat system, economy conversion or NFT rule is touched here.

CREATE TABLE IF NOT EXISTS public.hero_mining_rates (
  rarity text PRIMARY KEY,
  ton_per_day numeric NOT NULL DEFAULT 0 CHECK (ton_per_day >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.hero_mining_rates TO service_role;
ALTER TABLE public.hero_mining_rates ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.hero_mining_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  min_claim_ton numeric NOT NULL DEFAULT 0 CHECK (min_claim_ton >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.hero_mining_settings TO service_role;
ALTER TABLE public.hero_mining_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.hero_mining_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  amount_ton numeric NOT NULL CHECK (amount_ton > 0),
  hero_count integer NOT NULL DEFAULT 0,
  rate_per_day numeric NOT NULL DEFAULT 0,
  source text NOT NULL DEFAULT 'HERO_MINING_CLAIM',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.hero_mining_claims TO service_role;
ALTER TABLE public.hero_mining_claims ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS hero_mining_claims_user_idx ON public.hero_mining_claims (user_id, created_at DESC);

INSERT INTO public.hero_mining_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.hero_mining_rates (rarity, ton_per_day) VALUES
  ('common', 0.008), ('uncommon', 0.017), ('rare', 0.042), ('epic', 0.060),
  ('legendary', 0.090), ('mythic', 0.500), ('ancestral', 0.750)
ON CONFLICT (rarity) DO NOTHING;

ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS hero_mining_unclaimed_ton numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hero_mining_lifetime_ton numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hero_mining_claimed_at timestamptz;

ALTER TABLE public.player_heroes
  ADD COLUMN IF NOT EXISTS mining_last_at timestamptz;

-- Existing collections start mining from NOW: no retroactive payout.
UPDATE public.player_heroes SET mining_last_at = now() WHERE mining_last_at IS NULL;

-- ------------------------------------------------------------ config readers
CREATE OR REPLACE FUNCTION public.hero_mining_rate(p_rarity text)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT ton_per_day FROM hero_mining_rates WHERE rarity = lower(btrim(COALESCE(p_rarity, '')))), 0);
$$;

CREATE OR REPLACE FUNCTION public.hero_mining_enabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT enabled FROM hero_mining_settings WHERE id), true);
$$;

-- ------------------------------------------------------------ accrual (server clock only)
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_now timestamptz := now(); v_gain numeric := 0; v_unclaimed numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    -- Paused globally: cursors move forward so the paused window never pays.
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

  v_gain := round(GREATEST(v_gain, 0), 9);
  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_unclaimed;

  RETURN COALESCE(v_unclaimed, 0);
END $$;

-- ------------------------------------------------------------ per-hero settlement
-- Runs BEFORE the ownership/listing change, so the production accumulated until this
-- exact moment stays with the previous owner. Sold, listed or fused-away units stop mining.
CREATE OR REPLACE FUNCTION public.hero_mining_settle_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_gain numeric := 0; v_secs numeric;
BEGIN
  IF NOT COALESCE(OLD.market_locked, false)
     AND NOT COALESCE(OLD.is_nft_exclusive, false)
     AND hero_mining_enabled() THEN
    v_secs := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(OLD.mining_last_at, OLD.created_at, now()))));
    v_gain := round(hero_mining_rate(OLD.rarity) * v_secs / 86400.0, 9);
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

DROP TRIGGER IF EXISTS trg_hero_mining_settle_update ON public.player_heroes;
CREATE TRIGGER trg_hero_mining_settle_update
BEFORE UPDATE OF user_id, market_locked ON public.player_heroes
FOR EACH ROW
WHEN (OLD.user_id IS DISTINCT FROM NEW.user_id
      OR COALESCE(OLD.market_locked, false) IS DISTINCT FROM COALESCE(NEW.market_locked, false))
EXECUTE FUNCTION public.hero_mining_settle_row();

DROP TRIGGER IF EXISTS trg_hero_mining_settle_delete ON public.player_heroes;
CREATE TRIGGER trg_hero_mining_settle_delete
BEFORE DELETE ON public.player_heroes
FOR EACH ROW EXECUTE FUNCTION public.hero_mining_settle_row();

-- ------------------------------------------------------------ player state
CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; u game_players%rowtype; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  v_unclaimed := hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;
  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;

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
    'eligibleHeroes', COALESCE(v_count, 0),
    'availableTon', round(COALESCE(u.ton_balance, 0), 9),
    'minClaimTon', COALESCE(v_min, 0),
    'lastClaimAt', u.hero_mining_claimed_at,
    'updatedAt', now(),
    'rates', COALESCE((SELECT jsonb_object_agg(rarity, ton_per_day) FROM hero_mining_rates), '{}'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'amountTon', c.amount_ton, 'heroCount', c.hero_count,
        'ratePerDay', c.rate_per_day, 'createdAt', c.created_at) ORDER BY c.created_at DESC)
      FROM (SELECT * FROM hero_mining_claims WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) c), '[]'::jsonb)
  );
END $$;

-- ------------------------------------------------------------ CLAIM ALL (atomic + single-flight)
CREATE OR REPLACE FUNCTION public.claim_hero_mining(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric; v_claim uuid;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF NOT hero_mining_enabled() THEN RAISE EXCEPTION 'MINING_DISABLED'; END IF;

  -- Serialises concurrent claims from any device/tab for this player.
  PERFORM pg_advisory_xact_lock(hashtext('hero_mining_claim:' || v_user::text));

  v_unclaimed := hero_mining_accrue(v_user);
  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;
  IF COALESCE(v_unclaimed, 0) < GREATEST(COALESCE(v_min, 0), 0.000001) THEN
    RAISE EXCEPTION 'NOTHING_TO_CLAIM';
  END IF;

  SELECT COUNT(*), COALESCE(SUM(hero_mining_rate(h.rarity)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.market_locked, false)
     AND NOT COALESCE(h.is_nft_exclusive, false)
     AND hero_mining_rate(h.rarity) > 0;

  INSERT INTO hero_mining_claims (user_id, amount_ton, hero_count, rate_per_day)
  VALUES (v_user, round(v_unclaimed, 9), COALESCE(v_count, 0), round(COALESCE(v_rate, 0), 9))
  RETURNING id INTO v_claim;

  UPDATE game_players
     SET hero_mining_unclaimed_ton = 0,
         hero_mining_lifetime_ton = round(COALESCE(hero_mining_lifetime_ton, 0) + v_unclaimed, 9),
         hero_mining_claimed_at = now(),
         updated_at = now()
   WHERE id = v_user;

  -- Goes straight into the single withdrawable TON balance (no separate mining wallet).
  PERFORM credit_ton_reward(v_user, round(v_unclaimed, 9), 'hero_mining', v_claim::text, 'Hero TON mining claim');

  RETURN jsonb_build_object('ok', true, 'claimedTon', round(v_unclaimed, 9), 'claimId', v_claim)
      || get_hero_mining_state(p_telegram_id);
END $$;

-- ------------------------------------------------------------ admin panel
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
    'claims', (SELECT COALESCE(jsonb_agg(jsonb_build_object('amountTon', c.amount_ton, 'heroCount', c.hero_count,
        'createdAt', c.created_at, 'telegramId', g.telegram_id, 'name', COALESCE(g.display_name, g.first_name)) ORDER BY c.created_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM hero_mining_claims ORDER BY created_at DESC LIMIT 15) c
      JOIN game_players g ON g.id = c.user_id)
  );
END $$;

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
    'lastClaimAt', g.hero_mining_claimed_at,
    'availableTon', round(COALESCE(g.ton_balance, 0), 9),
    'dailyRateTon', (SELECT COALESCE(SUM(hero_mining_rate(h.rarity)), 0) FROM player_heroes h
       WHERE h.user_id = v_user AND NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false)),
    'eligibleHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE h.user_id = v_user
       AND NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false) AND hero_mining_rate(h.rarity) > 0),
    'pausedHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE h.user_id = v_user AND COALESCE(h.market_locked, false)),
    'byRarity', COALESCE((SELECT jsonb_agg(jsonb_build_object('rarity', r.rarity, 'count', r.qty, 'tonPerDay', round(r.qty * hero_mining_rate(r.rarity), 9)) ORDER BY r.rarity)
      FROM (SELECT lower(h.rarity) AS rarity, COUNT(*) AS qty FROM player_heroes h
             WHERE h.user_id = v_user AND NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false)
             GROUP BY 1) r), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_set_rate(p_admin_id bigint, p_rarity text, p_ton_per_day numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_rarity text := lower(btrim(COALESCE(p_rarity, ''))); v_old numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF v_rarity = '' THEN RAISE EXCEPTION 'INVALID_RARITY'; END IF;
  IF p_ton_per_day IS NULL OR p_ton_per_day < 0 OR p_ton_per_day > 100 THEN RAISE EXCEPTION 'INVALID_RATE'; END IF;
  SELECT ton_per_day INTO v_old FROM hero_mining_rates WHERE rarity = v_rarity;

  INSERT INTO hero_mining_rates (rarity, ton_per_day, updated_at)
  VALUES (v_rarity, round(p_ton_per_day, 9), now())
  ON CONFLICT (rarity) DO UPDATE SET ton_per_day = EXCLUDED.ton_per_day, updated_at = now();

  PERFORM admin_log(p_admin_id, 'hero_mining_set_rate', 'hero_mining', v_rarity,
    jsonb_build_object('tonPerDay', v_old), jsonb_build_object('tonPerDay', round(p_ton_per_day, 9)),
    'taxa de mineração alterada pelo painel admin', '{}'::jsonb);
  RETURN admin_hero_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_toggle(p_admin_id bigint, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  -- Flushing cursors before pausing means the paused window never generates TON.
  UPDATE player_heroes SET mining_last_at = now() WHERE mining_last_at IS NULL;
  UPDATE hero_mining_settings SET enabled = COALESCE(p_enabled, true), updated_at = now() WHERE id;
  IF COALESCE(p_enabled, true) THEN
    UPDATE player_heroes SET mining_last_at = now();
  END IF;
  PERFORM admin_log(p_admin_id, 'hero_mining_toggle', 'hero_mining', 'settings', NULL,
    jsonb_build_object('enabled', COALESCE(p_enabled, true)), 'mineração de TON alternada pelo painel admin', '{}'::jsonb);
  RETURN admin_hero_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_set_min_claim(p_admin_id bigint, p_min_ton numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_min_ton IS NULL OR p_min_ton < 0 OR p_min_ton > 100 THEN RAISE EXCEPTION 'INVALID_MIN'; END IF;
  UPDATE hero_mining_settings SET min_claim_ton = round(p_min_ton, 9), updated_at = now() WHERE id;
  PERFORM admin_log(p_admin_id, 'hero_mining_min_claim', 'hero_mining', 'settings', NULL,
    jsonb_build_object('minClaimTon', round(p_min_ton, 9)), 'resgate mínimo de mineração alterado', '{}'::jsonb);
  RETURN admin_hero_mining_overview(p_admin_id);
END $$;

-- ------------------------------------------------------------ execution locked to the backend
REVOKE ALL ON FUNCTION public.hero_mining_rate(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_enabled() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_accrue(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_mining_settle_row() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_hero_mining_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_hero_mining(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_mining_overview(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_mining_user(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_mining_set_rate(bigint, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_mining_toggle(bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_mining_set_min_claim(bigint, numeric) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.hero_mining_rate(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_enabled() TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_accrue(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_hero_mining_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_hero_mining(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_mining_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_mining_user(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_mining_set_rate(bigint, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_mining_toggle(bigint, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_mining_set_min_claim(bigint, numeric) TO service_role;