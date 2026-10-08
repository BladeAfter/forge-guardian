-- ============================================================
-- RARE HERO MYTH MINING (pool-share, diminishing returns, no mint)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rare_myth_mining_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  daily_budget_myth numeric NOT NULL DEFAULT 10000,
  player_daily_cap_myth numeric NOT NULL DEFAULT 100,
  tier1_max integer NOT NULL DEFAULT 20,
  tier1_weight numeric NOT NULL DEFAULT 1.00,
  tier2_max integer NOT NULL DEFAULT 50,
  tier2_weight numeric NOT NULL DEFAULT 0.25,
  tier3_max integer NOT NULL DEFAULT 100,
  tier3_weight numeric NOT NULL DEFAULT 0.10,
  tier4_weight numeric NOT NULL DEFAULT 0.02,
  min_claim_myth numeric NOT NULL DEFAULT 10,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.rare_myth_mining_settings TO service_role;
ALTER TABLE public.rare_myth_mining_settings ENABLE ROW LEVEL SECURITY;
INSERT INTO public.rare_myth_mining_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.rare_myth_mining_snapshots (
  day_key date PRIMARY KEY,
  global_units numeric NOT NULL DEFAULT 0,
  daily_budget_myth numeric NOT NULL DEFAULT 0,
  players integer NOT NULL DEFAULT 0,
  emitted_myth numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.rare_myth_mining_snapshots TO service_role;
ALTER TABLE public.rare_myth_mining_snapshots ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.rare_myth_mining_daily (
  user_id uuid NOT NULL,
  day_key date NOT NULL,
  rare_count integer NOT NULL DEFAULT 0,
  effective_units numeric NOT NULL DEFAULT 0,
  emitted_myth numeric NOT NULL DEFAULT 0,
  last_accrued_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day_key)
);
CREATE INDEX IF NOT EXISTS rare_myth_mining_daily_day_idx ON public.rare_myth_mining_daily (day_key, emitted_myth DESC);
GRANT ALL ON public.rare_myth_mining_daily TO service_role;
ALTER TABLE public.rare_myth_mining_daily ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.rare_myth_mining_balances (
  user_id uuid PRIMARY KEY,
  unclaimed_myth numeric NOT NULL DEFAULT 0,
  lifetime_myth numeric NOT NULL DEFAULT 0,
  last_claim_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.rare_myth_mining_balances TO service_role;
ALTER TABLE public.rare_myth_mining_balances ENABLE ROW LEVEL SECURITY;

-- ---------------- effective units (diminishing returns) ----------------
CREATE OR REPLACE FUNCTION public.rare_myth_effective_units(p_count integer)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s rare_myth_mining_settings%rowtype; c integer := GREATEST(COALESCE(p_count,0),0); u numeric := 0; n integer;
BEGIN
  SELECT * INTO s FROM rare_myth_mining_settings WHERE id;
  IF c <= 0 THEN RETURN 0; END IF;
  n := LEAST(c, s.tier1_max); u := u + n * s.tier1_weight;
  IF c > s.tier1_max THEN
    n := LEAST(c, s.tier2_max) - s.tier1_max; u := u + GREATEST(n,0) * s.tier2_weight;
  END IF;
  IF c > s.tier2_max THEN
    n := LEAST(c, s.tier3_max) - s.tier2_max; u := u + GREATEST(n,0) * s.tier3_weight;
  END IF;
  IF c > s.tier3_max THEN
    u := u + (c - s.tier3_max) * s.tier4_weight;
  END IF;
  RETURN round(u, 6);
END $$;

-- Rare heroes owned right now. Market-listed heroes never mine (no double mining
-- while escrowed), and ownership is always the current owner_user_id of the row.
CREATE OR REPLACE FUNCTION public.rare_myth_rare_count(p_user_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(COUNT(*),0)::int FROM player_heroes h
   WHERE h.user_id = p_user_id
     AND lower(COALESCE(h.rarity,'')) = 'rare'
     AND NOT COALESCE(h.market_locked, false);
$$;

-- ---------------- daily snapshot of global effective units ----------------
CREATE OR REPLACE FUNCTION public.rare_myth_snapshot_ensure()
RETURNS public.rare_myth_mining_snapshots LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s rare_myth_mining_settings%rowtype; k date := game_day_key(); r rare_myth_mining_snapshots%rowtype;
BEGIN
  SELECT * INTO s FROM rare_myth_mining_settings WHERE id;
  SELECT * INTO r FROM rare_myth_mining_snapshots WHERE day_key = k;
  IF r.day_key IS NULL THEN
    INSERT INTO rare_myth_mining_snapshots (day_key, global_units, daily_budget_myth, players)
    SELECT k,
           COALESCE(SUM(rare_myth_effective_units(t.c)), 0),
           GREATEST(COALESCE(s.daily_budget_myth,0), 0),
           COALESCE(COUNT(*), 0)
      FROM (SELECT h.user_id, COUNT(*)::int AS c FROM player_heroes h
             WHERE lower(COALESCE(h.rarity,'')) = 'rare' AND NOT COALESCE(h.market_locked,false)
             GROUP BY h.user_id) t
    ON CONFLICT (day_key) DO NOTHING;
    SELECT * INTO r FROM rare_myth_mining_snapshots WHERE day_key = k;
  ELSIF r.daily_budget_myth <> GREATEST(COALESCE(s.daily_budget_myth,0),0) THEN
    UPDATE rare_myth_mining_snapshots
       SET daily_budget_myth = GREATEST(COALESCE(s.daily_budget_myth,0),0), updated_at = now()
     WHERE day_key = k RETURNING * INTO r;
  END IF;
  RETURN r;
END $$;

-- Total MYTH already accrued but not yet claimed (reserved against the pool).
CREATE OR REPLACE FUNCTION public.rare_myth_reserved()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(COALESCE((SELECT SUM(unclaimed_myth) FROM rare_myth_mining_balances), 0), 0);
$$;

-- ---------------- accrual ----------------
CREATE OR REPLACE FUNCTION public.rare_myth_mining_accrue(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s rare_myth_mining_settings%rowtype; snap rare_myth_mining_snapshots%rowtype;
        d rare_myth_mining_daily%rowtype; k date := game_day_key();
        v_count int; v_units numeric; v_rate numeric := 0; v_secs numeric := 0;
        v_gain numeric := 0; v_pool numeric; v_room_player numeric; v_room_global numeric;
        v_now timestamptz := now();
BEGIN
  IF p_user_id IS NULL THEN RETURN '{}'::jsonb; END IF;
  SELECT * INTO s FROM rare_myth_mining_settings WHERE id;
  snap := rare_myth_snapshot_ensure();

  v_count := rare_myth_rare_count(p_user_id);
  v_units := rare_myth_effective_units(v_count);

  INSERT INTO rare_myth_mining_daily (user_id, day_key, rare_count, effective_units)
  VALUES (p_user_id, k, v_count, v_units)
  ON CONFLICT (user_id, day_key) DO UPDATE SET rare_count = v_count, effective_units = v_units, updated_at = now();
  SELECT * INTO d FROM rare_myth_mining_daily WHERE user_id = p_user_id AND day_key = k;

  IF COALESCE(s.enabled, false) AND v_units > 0 AND COALESCE(snap.global_units,0) > 0 AND COALESCE(snap.daily_budget_myth,0) > 0 THEN
    -- Proportional slice of the fixed global budget, then the per-player hard cap.
    v_rate := round(LEAST(v_units / snap.global_units * snap.daily_budget_myth,
                          GREATEST(COALESCE(s.player_daily_cap_myth,0), 0)), 9);
    v_secs := GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(d.last_accrued_at, v_now))));
    v_gain := v_rate * v_secs / 86400.0;

    v_room_player := GREATEST(GREATEST(COALESCE(s.player_daily_cap_myth,0),0) - COALESCE(d.emitted_myth,0), 0);
    v_room_global := GREATEST(COALESCE(snap.daily_budget_myth,0) - COALESCE(snap.emitted_myth,0), 0);
    v_pool := GREATEST(myth_mining_pool_available() - rare_myth_reserved(), 0);

    v_gain := round(LEAST(v_gain, v_room_player, v_room_global, v_pool), 9);
    IF v_gain < 0 THEN v_gain := 0; END IF;
  END IF;

  UPDATE rare_myth_mining_daily
     SET last_accrued_at = v_now,
         emitted_myth = round(COALESCE(emitted_myth,0) + v_gain, 9),
         updated_at = v_now
   WHERE user_id = p_user_id AND day_key = k;

  IF v_gain > 0 THEN
    UPDATE rare_myth_mining_snapshots
       SET emitted_myth = round(COALESCE(emitted_myth,0) + v_gain, 9), updated_at = v_now
     WHERE day_key = k;

    INSERT INTO rare_myth_mining_balances (user_id, unclaimed_myth)
    VALUES (p_user_id, v_gain)
    ON CONFLICT (user_id) DO UPDATE
      SET unclaimed_myth = round(rare_myth_mining_balances.unclaimed_myth + v_gain, 9), updated_at = v_now;
  END IF;

  RETURN jsonb_build_object('rareCount', v_count, 'effectiveUnits', v_units,
                            'globalUnits', round(COALESCE(snap.global_units,0),6),
                            'estimatedDailyMyth', v_rate,
                            'gain', v_gain,
                            'emittedToday', round(COALESCE(d.emitted_myth,0) + v_gain, 9));
END $$;

-- ---------------- player state ----------------
CREATE OR REPLACE FUNCTION public.rare_myth_mining_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; s rare_myth_mining_settings%rowtype; snap rare_myth_mining_snapshots%rowtype;
        acc jsonb; b rare_myth_mining_balances%rowtype;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM rare_myth_mining_settings WHERE id;
  acc := rare_myth_mining_accrue(v_user);
  SELECT * INTO snap FROM rare_myth_mining_snapshots WHERE day_key = game_day_key();
  SELECT * INTO b FROM rare_myth_mining_balances WHERE user_id = v_user;

  RETURN jsonb_build_object(
    'enabled', COALESCE(s.enabled,false),
    'rareCount', acc->'rareCount',
    'effectiveUnits', acc->'effectiveUnits',
    'globalUnits', acc->'globalUnits',
    'estimatedDailyMyth', acc->'estimatedDailyMyth',
    'emittedToday', acc->'emittedToday',
    'playerDailyCapMyth', round(COALESCE(s.player_daily_cap_myth,0),9),
    'globalDailyBudgetMyth', round(COALESCE(snap.daily_budget_myth, s.daily_budget_myth, 0),9),
    'globalEmittedToday', round(COALESCE(snap.emitted_myth,0),9),
    'unclaimedMyth', round(COALESCE(b.unclaimed_myth,0),9),
    'lifetimeMyth', round(COALESCE(b.lifetime_myth,0),9),
    'minClaimMyth', round(COALESCE(s.min_claim_myth,0),9),
    'poolAvailable', myth_mining_pool_available(),
    'lastClaimAt', b.last_claim_at,
    'nextResetAt', game_day_start(game_day_key() + 1),
    'tiers', jsonb_build_array(
      jsonb_build_object('from',1,'to',s.tier1_max,'weight',s.tier1_weight),
      jsonb_build_object('from',s.tier1_max+1,'to',s.tier2_max,'weight',s.tier2_weight),
      jsonb_build_object('from',s.tier2_max+1,'to',s.tier3_max,'weight',s.tier3_weight),
      jsonb_build_object('from',s.tier3_max+1,'to',null,'weight',s.tier4_weight))
  );
END $$;

-- ---------------- claim ----------------
CREATE OR REPLACE FUNCTION public.rare_myth_mining_claim(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; s rare_myth_mining_settings%rowtype; v_amount numeric; v_pool numeric; v_claim uuid;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('rare_myth_claim:' || v_user::text));
  SELECT * INTO s FROM rare_myth_mining_settings WHERE id;
  PERFORM rare_myth_mining_accrue(v_user);

  SELECT round(COALESCE(unclaimed_myth,0),9) INTO v_amount FROM rare_myth_mining_balances WHERE user_id = v_user;
  v_pool := myth_mining_pool_available();
  v_amount := round(LEAST(COALESCE(v_amount,0), GREATEST(v_pool,0)), 9);
  IF v_amount <= 0 OR v_amount < GREATEST(COALESCE(s.min_claim_myth,0), 0.000001) THEN
    RAISE EXCEPTION 'NOTHING_TO_CLAIM';
  END IF;

  UPDATE rare_myth_mining_balances
     SET unclaimed_myth = GREATEST(0, round(unclaimed_myth - v_amount, 9)),
         lifetime_myth = round(lifetime_myth + v_amount, 9),
         last_claim_at = now(), updated_at = now()
   WHERE user_id = v_user;

  INSERT INTO hero_mining_claims (user_id, amount_ton, amount_myth, currency, hero_count, rate_per_day)
  VALUES (v_user, 0, v_amount, 'myth', rare_myth_rare_count(v_user), 0)
  RETURNING id INTO v_claim;

  -- Rewards come only from the pre-allocated MYTH mining pool: no new supply is minted.
  UPDATE myth_mining_pool SET distributed_myth = round(distributed_myth + v_amount, 9), updated_at = now() WHERE id;

  INSERT INTO myth_balances (user_id, amount, updated_at) VALUES (v_user, v_amount, now())
  ON CONFLICT (user_id) DO UPDATE SET amount = round(myth_balances.amount + v_amount, 9), updated_at = now();

  INSERT INTO myth_supply_ledger (entry_type, amount, user_id, reference_id, note)
  VALUES ('MINING', v_amount, v_user, 'rare_myth_mining:' || v_claim::text, 'Rare hero MYTH mining');

  INSERT INTO nft_mining_ledger (entry_type, currency, amount, user_id, reference_id, meta)
  VALUES ('RARE_MYTH_MINING_CLAIM', 'myth', v_amount, v_user, v_claim::text,
          jsonb_build_object('rareCount', rare_myth_rare_count(v_user)));

  RETURN rare_myth_mining_state(p_telegram_id) || jsonb_build_object('ok', true, 'claimedMyth', v_amount, 'claimId', v_claim);
END $$;

-- ---------------- admin bot ----------------
CREATE OR REPLACE FUNCTION public.admin_rare_myth_mining_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s rare_myth_mining_settings%rowtype; snap rare_myth_mining_snapshots%rowtype;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO s FROM rare_myth_mining_settings WHERE id;
  snap := rare_myth_snapshot_ensure();
  RETURN jsonb_build_object(
    'enabled', s.enabled,
    'dailyBudgetMyth', round(s.daily_budget_myth,9),
    'playerDailyCapMyth', round(s.player_daily_cap_myth,9),
    'minClaimMyth', round(s.min_claim_myth,9),
    'tiers', jsonb_build_array(
      jsonb_build_object('label','1-'||s.tier1_max,'weight',s.tier1_weight),
      jsonb_build_object('label',(s.tier1_max+1)||'-'||s.tier2_max,'weight',s.tier2_weight),
      jsonb_build_object('label',(s.tier2_max+1)||'-'||s.tier3_max,'weight',s.tier3_weight),
      jsonb_build_object('label',(s.tier3_max+1)||'+','weight',s.tier4_weight)),
    'globalUnits', round(COALESCE(snap.global_units,0),4),
    'miners', COALESCE(snap.players,0),
    'emittedToday', round(COALESCE(snap.emitted_myth,0),4),
    'emitted7d', round(COALESCE((SELECT SUM(emitted_myth) FROM rare_myth_mining_snapshots WHERE day_key > game_day_key() - 7),0),4),
    'emitted30d', round(COALESCE((SELECT SUM(emitted_myth) FROM rare_myth_mining_snapshots WHERE day_key > game_day_key() - 30),0),4),
    'unclaimedMyth', rare_myth_reserved(),
    'pool', (SELECT jsonb_build_object('allocated', round(allocated_myth,4), 'distributed', round(distributed_myth,4),
                                       'available', myth_mining_pool_available()) FROM myth_mining_pool WHERE id),
    'topMiners', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT jsonb_build_object('telegramId', g.telegram_id, 'name', g.username,
                                  'rareCount', d.rare_count, 'units', round(d.effective_units,3),
                                  'emitted', round(d.emitted_myth,4)) AS x
          FROM rare_myth_mining_daily d JOIN game_players g ON g.id = d.user_id
         WHERE d.day_key = game_day_key() AND d.emitted_myth > 0
         ORDER BY d.emitted_myth DESC LIMIT 10) t), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_rare_myth_mining_set(p_admin_id bigint, p_field text, p_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v numeric := GREATEST(COALESCE(p_value,0), 0);
BEGIN
  PERFORM admin_assert(p_admin_id);
  CASE lower(COALESCE(p_field,''))
    WHEN 'budget' THEN UPDATE rare_myth_mining_settings SET daily_budget_myth = v, updated_at = now() WHERE id;
    WHEN 'playercap' THEN UPDATE rare_myth_mining_settings SET player_daily_cap_myth = v, updated_at = now() WHERE id;
    WHEN 'minclaim' THEN UPDATE rare_myth_mining_settings SET min_claim_myth = v, updated_at = now() WHERE id;
    WHEN 'tier1' THEN UPDATE rare_myth_mining_settings SET tier1_weight = LEAST(v/100.0, 1), updated_at = now() WHERE id;
    WHEN 'tier2' THEN UPDATE rare_myth_mining_settings SET tier2_weight = LEAST(v/100.0, 1), updated_at = now() WHERE id;
    WHEN 'tier3' THEN UPDATE rare_myth_mining_settings SET tier3_weight = LEAST(v/100.0, 1), updated_at = now() WHERE id;
    WHEN 'tier4' THEN UPDATE rare_myth_mining_settings SET tier4_weight = LEAST(v/100.0, 1), updated_at = now() WHERE id;
    ELSE RAISE EXCEPTION 'INVALID_FIELD';
  END CASE;
  -- Tier/budget changes reshape the current snapshot so the new rule applies immediately.
  DELETE FROM rare_myth_mining_snapshots WHERE day_key = game_day_key()
    AND lower(COALESCE(p_field,'')) LIKE 'tier%';
  PERFORM rare_myth_snapshot_ensure();
  RETURN admin_rare_myth_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_rare_myth_mining_toggle(p_admin_id bigint, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  UPDATE rare_myth_mining_settings SET enabled = COALESCE(p_enabled,false), updated_at = now() WHERE id;
  RETURN admin_rare_myth_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_rare_myth_pool_add(p_admin_id bigint, p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v numeric := GREATEST(COALESCE(p_amount,0),0); v_supply numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  v_supply := COALESCE((SELECT COALESCE(total_supply, 100000000) FROM myth_token_settings LIMIT 1), 100000000);
  UPDATE myth_mining_pool
     SET allocated_myth = LEAST(round(allocated_myth + v, 9), v_supply), updated_at = now()
   WHERE id;
  INSERT INTO myth_supply_ledger (entry_type, amount, admin_telegram_id, note)
  VALUES ('POOL_ALLOCATION', v, p_admin_id, 'Rare hero mining allocation');
  RETURN admin_rare_myth_mining_overview(p_admin_id);
END $$;

REVOKE ALL ON FUNCTION public.rare_myth_mining_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rare_myth_mining_claim(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rare_myth_mining_accrue(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rare_myth_snapshot_ensure() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_rare_myth_mining_overview(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_rare_myth_mining_set(bigint, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_rare_myth_mining_toggle(bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_rare_myth_pool_add(bigint, numeric) FROM PUBLIC, anon, authenticated;