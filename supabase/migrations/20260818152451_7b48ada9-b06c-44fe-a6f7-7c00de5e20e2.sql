ALTER TABLE public.hero_mining_settings
  ADD COLUMN IF NOT EXISTS mining_currency text NOT NULL DEFAULT 'ton',
  ADD COLUMN IF NOT EXISTS myth_per_day numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS min_claim_myth numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS currency_changed_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.hero_mining_settings DROP CONSTRAINT IF EXISTS hero_mining_settings_currency_check;
ALTER TABLE public.hero_mining_settings
  ADD CONSTRAINT hero_mining_settings_currency_check CHECK (mining_currency IN ('ton','myth'));

GRANT SELECT ON public.hero_mining_settings TO authenticated, anon;
DROP POLICY IF EXISTS "mining settings readable" ON public.hero_mining_settings;
CREATE POLICY "mining settings readable" ON public.hero_mining_settings FOR SELECT TO authenticated, anon USING (true);

ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS hero_mining_unclaimed_myth numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hero_mining_lifetime_myth numeric NOT NULL DEFAULT 0;

ALTER TABLE public.hero_mining_claims
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'ton',
  ADD COLUMN IF NOT EXISTS amount_myth numeric NOT NULL DEFAULT 0;
ALTER TABLE public.hero_mining_claims DROP CONSTRAINT IF EXISTS hero_mining_claims_amount_ton_check;
ALTER TABLE public.hero_mining_claims ADD CONSTRAINT hero_mining_claims_amount_ton_check CHECK (amount_ton >= 0);

CREATE TABLE IF NOT EXISTS public.myth_mining_pool (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  allocated_myth numeric NOT NULL DEFAULT 0 CHECK (allocated_myth >= 0),
  distributed_myth numeric NOT NULL DEFAULT 0 CHECK (distributed_myth >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.myth_mining_pool TO authenticated;
GRANT ALL ON public.myth_mining_pool TO service_role;
ALTER TABLE public.myth_mining_pool ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "myth mining pool readable" ON public.myth_mining_pool;
CREATE POLICY "myth mining pool readable" ON public.myth_mining_pool FOR SELECT TO authenticated USING (true);
INSERT INTO public.myth_mining_pool (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.nft_mining_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_type text NOT NULL CHECK (entry_type IN (
    'NFT_MINING_TON_ACCRUAL','NFT_MINING_TON_CLAIM',
    'NFT_MINING_MYTH_ACCRUAL','NFT_MINING_MYTH_CLAIM',
    'NFT_MINING_CURRENCY_CHANGED')),
  currency text NOT NULL CHECK (currency IN ('ton','myth','none')),
  amount numeric NOT NULL DEFAULT 0,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  admin_telegram_id bigint,
  reference_id text,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nft_mining_ledger_created_idx ON public.nft_mining_ledger (created_at DESC);
GRANT SELECT ON public.nft_mining_ledger TO authenticated;
GRANT ALL ON public.nft_mining_ledger TO service_role;
ALTER TABLE public.nft_mining_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mining ledger own rows" ON public.nft_mining_ledger;
CREATE POLICY "mining ledger own rows" ON public.nft_mining_ledger FOR SELECT TO authenticated USING (false);

ALTER TABLE public.myth_supply_ledger DROP CONSTRAINT IF EXISTS myth_supply_ledger_entry_type_check;
ALTER TABLE public.myth_supply_ledger ADD CONSTRAINT myth_supply_ledger_entry_type_check
  CHECK (entry_type IN ('INITIAL_SUPPLY','SALE','BURN','ADMIN_ADJUSTMENT','REFUND','MINING'));

CREATE OR REPLACE FUNCTION public.hero_mining_currency()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT mining_currency FROM hero_mining_settings WHERE id), 'ton');
$$;

CREATE OR REPLACE FUNCTION public.hero_mining_myth_per_day()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(COALESCE((SELECT myth_per_day FROM hero_mining_settings WHERE id), 0), 0);
$$;

CREATE OR REPLACE FUNCTION public.hero_mining_effective_daily(p_rarity text, p_nft_hero_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN hero_mining_hero_rate(p_rarity, p_nft_hero_id) <= 0 THEN 0
    WHEN hero_mining_currency() = 'myth' THEN hero_mining_myth_per_day()
    ELSE hero_mining_hero_rate(p_rarity, p_nft_hero_id)
  END;
$$;

CREATE OR REPLACE FUNCTION public.myth_mining_pool_available()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(0, COALESCE((SELECT allocated_myth - distributed_myth FROM myth_mining_pool WHERE id), 0));
$$;

CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_now timestamptz := now(); v_gain numeric := 0; v_out numeric; v_room numeric;
        v_currency text := hero_mining_currency(); v_myth numeric := hero_mining_myth_per_day();
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT CASE WHEN v_currency = 'myth' THEN hero_mining_unclaimed_myth
                                 ELSE hero_mining_unclaimed_ton END
                       FROM game_players WHERE id = p_user_id), 0);
  END IF;

  IF v_currency = 'ton' THEN
    v_room := COALESCE(hero_mining_remaining(p_user_id), 0);
    IF v_room <= 0 THEN
      UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
      RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
    END IF;
  END IF;

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(
    CASE WHEN rate <= 0 THEN 0
         WHEN v_currency = 'myth' THEN v_myth * secs / 86400.0
         ELSE rate * secs / 86400.0 END), 0)
    INTO v_gain FROM moved;

  IF v_currency = 'myth' THEN
    v_gain := round(GREATEST(v_gain, 0), 9);
    UPDATE game_players
       SET hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_gain, 9),
           updated_at = now()
     WHERE id = p_user_id
    RETURNING hero_mining_unclaimed_myth INTO v_out;
  ELSE
    v_gain := round(LEAST(GREATEST(v_gain, 0), v_room), 9);
    UPDATE game_players
       SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
           updated_at = now()
     WHERE id = p_user_id
    RETURNING hero_mining_unclaimed_ton INTO v_out;
  END IF;

  RETURN COALESCE(v_out, 0);
END $$;

CREATE OR REPLACE FUNCTION public.hero_mining_settle_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_gain numeric := 0; v_secs numeric; v_room numeric := 0; v_currency text := hero_mining_currency();
BEGIN
  IF OLD.user_id IS NOT NULL AND v_currency = 'ton' THEN
    v_room := COALESCE(hero_mining_remaining(OLD.user_id), 0);
  END IF;

  IF NOT COALESCE(OLD.market_locked, false)
     AND NOT COALESCE(OLD.is_nft_exclusive, false)
     AND hero_mining_enabled()
     AND (v_currency = 'myth' OR v_room > 0) THEN
    v_secs := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(OLD.mining_last_at, OLD.created_at, now()))));
    IF v_currency = 'myth' THEN
      v_gain := CASE WHEN hero_mining_rate(OLD.rarity) > 0
                     THEN round(hero_mining_myth_per_day() * v_secs / 86400.0, 9) ELSE 0 END;
    ELSE
      v_gain := round(LEAST(hero_mining_rate(OLD.rarity) * v_secs / 86400.0, v_room), 9);
    END IF;
  END IF;

  IF v_gain > 0 AND OLD.user_id IS NOT NULL THEN
    IF v_currency = 'myth' THEN
      UPDATE game_players
         SET hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_gain, 9),
             updated_at = now()
       WHERE id = OLD.user_id;
    ELSE
      UPDATE game_players
         SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
             updated_at = now()
       WHERE id = OLD.user_id;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN NEW.mining_last_at := now(); RETURN NEW; END IF;
  RETURN OLD;
END $$;

CREATE OR REPLACE FUNCTION public.hero_mining_settle_all()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_now timestamptz := now(); v_currency text := hero_mining_currency();
        v_myth numeric := hero_mining_myth_per_day(); v_ton_total numeric := 0; v_myth_total numeric := 0;
BEGIN
  DROP TABLE IF EXISTS _mining_settle;
  CREATE TEMP TABLE _mining_settle ON COMMIT DROP AS
  WITH elig AS (
    SELECT h.id, h.user_id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id IS NOT NULL
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.user_id AS user_id, e.rate AS rate, e.secs AS secs
  )
  SELECT user_id,
         round(SUM(CASE WHEN rate > 0 AND v_currency = 'ton' THEN rate * secs / 86400.0 ELSE 0 END), 9) AS ton_gain,
         round(SUM(CASE WHEN rate > 0 AND v_currency = 'myth' THEN v_myth * secs / 86400.0 ELSE 0 END), 9) AS myth_gain
    FROM moved GROUP BY user_id;

  IF v_currency = 'ton' THEN
    UPDATE game_players g
       SET hero_mining_unclaimed_ton = round(COALESCE(g.hero_mining_unclaimed_ton,0)
             + LEAST(s.ton_gain, GREATEST(0, COALESCE(g.hero_mining_invested_ton,0)
               - COALESCE(g.hero_mining_returned_ton,0) - COALESCE(g.hero_mining_unclaimed_ton,0))), 9),
           updated_at = now()
      FROM _mining_settle s
     WHERE g.id = s.user_id AND s.ton_gain > 0;
    SELECT COALESCE(SUM(ton_gain),0) INTO v_ton_total FROM _mining_settle;
  ELSE
    UPDATE game_players g
       SET hero_mining_unclaimed_myth = round(COALESCE(g.hero_mining_unclaimed_myth,0) + s.myth_gain, 9),
           updated_at = now()
      FROM _mining_settle s
     WHERE g.id = s.user_id AND s.myth_gain > 0;
    SELECT COALESCE(SUM(myth_gain),0) INTO v_myth_total FROM _mining_settle;
  END IF;

  IF v_ton_total > 0 THEN
    INSERT INTO nft_mining_ledger (entry_type, currency, amount, meta)
    VALUES ('NFT_MINING_TON_ACCRUAL', 'ton', v_ton_total, jsonb_build_object('scope','settle_all'));
  END IF;
  IF v_myth_total > 0 THEN
    INSERT INTO nft_mining_ledger (entry_type, currency, amount, meta)
    VALUES ('NFT_MINING_MYTH_ACCRUAL', 'myth', v_myth_total, jsonb_build_object('scope','settle_all'));
  END IF;

  RETURN jsonb_build_object('currency', v_currency, 'tonAccrued', v_ton_total, 'mythAccrued', v_myth_total, 'settledAt', v_now);
END $$;

CREATE OR REPLACE FUNCTION public.claim_hero_mining(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric; v_claim uuid;
        v_invested numeric; v_returned numeric; v_room numeric; v_claimable numeric;
        v_currency text := hero_mining_currency(); v_available numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF NOT hero_mining_enabled() THEN RAISE EXCEPTION 'MINING_DISABLED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('hero_mining_claim:' || v_user::text));
  v_unclaimed := hero_mining_accrue(v_user);

  SELECT COUNT(*), COALESCE(SUM(hero_mining_effective_daily(h.rarity, h.nft_hero_id)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.pass_exclusive, false)
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0;

  IF v_currency = 'myth' THEN
    SELECT COALESCE(min_claim_myth, 0) INTO v_min FROM hero_mining_settings WHERE id;
    v_available := myth_mining_pool_available();
    v_claimable := round(LEAST(COALESCE(v_unclaimed, 0), v_available), 9);
    IF v_available <= 0 THEN RAISE EXCEPTION 'MYTH_POOL_EMPTY'; END IF;
    IF v_claimable < GREATEST(COALESCE(v_min, 0), 0.000001) THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;

    INSERT INTO hero_mining_claims (user_id, amount_ton, amount_myth, currency, hero_count, rate_per_day)
    VALUES (v_user, 0, v_claimable, 'myth', COALESCE(v_count,0), round(COALESCE(v_rate,0),9))
    RETURNING id INTO v_claim;

    UPDATE game_players
       SET hero_mining_unclaimed_myth = GREATEST(0, round(COALESCE(hero_mining_unclaimed_myth,0) - v_claimable, 9)),
           hero_mining_lifetime_myth = round(COALESCE(hero_mining_lifetime_myth,0) + v_claimable, 9),
           hero_mining_claimed_at = now(), updated_at = now()
     WHERE id = v_user;

    UPDATE myth_mining_pool
       SET distributed_myth = round(distributed_myth + v_claimable, 9), updated_at = now()
     WHERE id;

    INSERT INTO myth_balances (user_id, amount, updated_at)
    VALUES (v_user, v_claimable, now())
    ON CONFLICT (user_id) DO UPDATE SET amount = round(myth_balances.amount + v_claimable, 9), updated_at = now();

    INSERT INTO myth_supply_ledger (entry_type, amount, user_id, reference_id, note)
    VALUES ('MINING', v_claimable, v_user, 'hero_mining:' || v_claim::text, 'NFT mining reward');

    INSERT INTO nft_mining_ledger (entry_type, currency, amount, user_id, reference_id)
    VALUES ('NFT_MINING_MYTH_CLAIM', 'myth', v_claimable, v_user, v_claim::text);

    RETURN get_hero_mining_state(p_telegram_id)
         || jsonb_build_object('ok', true, 'currency', 'myth', 'claimedMyth', v_claimable, 'claimedTon', 0, 'claimId', v_claim);
  END IF;

  SELECT round(COALESCE(hero_mining_invested_ton, 0), 9), round(COALESCE(hero_mining_returned_ton, 0), 9)
    INTO v_invested, v_returned FROM game_players WHERE id = v_user;
  IF v_invested <= 0 THEN RAISE EXCEPTION 'NO_TON_INVESTMENT'; END IF;
  v_room := GREATEST(0, round(v_invested - v_returned, 9));
  IF v_room <= 0 THEN RAISE EXCEPTION 'ROI_LIMIT_REACHED'; END IF;

  v_claimable := round(LEAST(COALESCE(v_unclaimed, 0), v_room), 9);
  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;
  IF v_claimable < GREATEST(COALESCE(v_min, 0), 0.000001) THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;

  INSERT INTO hero_mining_claims (user_id, amount_ton, currency, hero_count, rate_per_day)
  VALUES (v_user, v_claimable, 'ton', COALESCE(v_count, 0), round(COALESCE(v_rate, 0), 9))
  RETURNING id INTO v_claim;

  UPDATE game_players
     SET hero_mining_unclaimed_ton = GREATEST(0, round(COALESCE(hero_mining_unclaimed_ton, 0) - v_claimable, 9)),
         hero_mining_lifetime_ton = round(COALESCE(hero_mining_lifetime_ton, 0) + v_claimable, 9),
         hero_mining_returned_ton = round(COALESCE(hero_mining_returned_ton, 0) + v_claimable, 9),
         hero_mining_claimed_at = now(), updated_at = now()
   WHERE id = v_user;

  PERFORM credit_ton_reward(v_user, v_claimable, 'hero_mining', 'hero_mining:' || v_claim::text, 'Hero TON Mining');
  INSERT INTO nft_mining_ledger (entry_type, currency, amount, user_id, reference_id)
  VALUES ('NFT_MINING_TON_CLAIM', 'ton', v_claimable, v_user, v_claim::text);

  RETURN get_hero_mining_state(p_telegram_id)
       || jsonb_build_object('ok', true, 'currency', 'ton', 'claimedTon', v_claimable, 'claimedMyth', 0, 'claimId', v_claim);
END $$;

CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; u game_players%rowtype; v_unclaimed numeric; v_rate numeric; v_count integer;
        v_min numeric; v_invested numeric; v_returned numeric; v_remaining numeric;
        s hero_mining_settings%rowtype; v_currency text;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  v_currency := COALESCE(s.mining_currency, 'ton');
  PERFORM hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;
  v_unclaimed := CASE WHEN v_currency = 'myth' THEN round(COALESCE(u.hero_mining_unclaimed_myth,0),9)
                      ELSE round(COALESCE(u.hero_mining_unclaimed_ton,0),9) END;
  v_min := CASE WHEN v_currency = 'myth' THEN COALESCE(s.min_claim_myth, 0) ELSE COALESCE(s.min_claim_ton, 0) END;
  v_invested := round(COALESCE(u.hero_mining_invested_ton, 0), 9);
  v_returned := round(COALESCE(u.hero_mining_returned_ton, 0), 9);
  v_remaining := GREATEST(0, round(v_invested - v_returned - round(COALESCE(u.hero_mining_unclaimed_ton,0),9), 9));
  SELECT COUNT(*), COALESCE(SUM(hero_mining_effective_daily(h.rarity, h.nft_hero_id)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.pass_exclusive, false)
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0;

  RETURN jsonb_build_object(
    'enabled', COALESCE(s.enabled, true),
    'miningCurrency', v_currency,
    'currencyChangedAt', s.currency_changed_at,
    'mythPerDay', round(COALESCE(s.myth_per_day, 0), 9),
    'dailyRate', round(COALESCE(v_rate, 0), 9),
    'dailyRateTon', CASE WHEN v_currency = 'ton' THEN round(COALESCE(v_rate,0),9) ELSE 0 END,
    'dailyRateMyth', CASE WHEN v_currency = 'myth' THEN round(COALESCE(v_rate,0),9) ELSE 0 END,
    'unclaimed', v_unclaimed,
    'unclaimedTon', round(COALESCE(u.hero_mining_unclaimed_ton, 0), 9),
    'unclaimedMyth', round(COALESCE(u.hero_mining_unclaimed_myth, 0), 9),
    'lifetimeTon', round(COALESCE(u.hero_mining_lifetime_ton, 0), 9),
    'lifetimeMyth', round(COALESCE(u.hero_mining_lifetime_myth, 0), 9),
    'mythBalance', COALESCE((SELECT amount FROM myth_balances WHERE user_id = v_user), 0),
    'mythPoolAvailable', myth_mining_pool_available(),
    'investedTon', v_invested, 'returnedTon', v_returned, 'remainingTon', v_remaining,
    'roiLimitReached', (v_currency = 'ton' AND v_invested > 0 AND v_remaining <= 0),
    'hasInvestment', (v_invested > 0),
    'eligibleHeroes', COALESCE(v_count, 0),
    'availableTon', round(COALESCE(u.ton_balance, 0), 9),
    'minClaim', COALESCE(v_min, 0),
    'minClaimTon', COALESCE(s.min_claim_ton, 0),
    'minClaimMyth', COALESCE(s.min_claim_myth, 0),
    'lastClaimAt', u.hero_mining_claimed_at,
    'updatedAt', now(),
    'rates', COALESCE((SELECT jsonb_object_agg(rarity, CASE WHEN v_currency = 'myth'
              THEN CASE WHEN ton_per_day > 0 THEN round(COALESCE(s.myth_per_day,0),9) ELSE 0 END
              ELSE ton_per_day END) FROM hero_mining_rates), '{}'::jsonb),
    'investments', COALESCE((SELECT jsonb_agg(jsonb_build_object('sourceType', i.source_type, 'amountTon', i.amount_ton, 'createdAt', i.created_at) ORDER BY i.created_at DESC)
      FROM (SELECT * FROM hero_mining_investments WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) i), '[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'amountTon', c.amount_ton, 'amountMyth', COALESCE(c.amount_myth,0), 'currency', COALESCE(c.currency,'ton'),
        'heroCount', c.hero_count, 'ratePerDay', c.rate_per_day, 'createdAt', c.created_at) ORDER BY c.created_at DESC)
      FROM (SELECT * FROM hero_mining_claims WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) c), '[]'::jsonb)
  );
END $$;