-- =====================================================================
-- SPENDING EVENT :: real scoring engine (ledger + aggregate + hooks)
-- =====================================================================

-- 1. CONFIGURABLE RULES ------------------------------------------------
INSERT INTO public.game_settings(key, value, category, label)
VALUES ('spending_event_rules', jsonb_build_object(
  'ton_points', 100000,
  'fc_points', 1,
  'sources', jsonb_build_object(
    'ton_direct_deposit', true,
    'ton_to_fc', true,
    'myth_sale', true,
    'season_pass', true,
    'packs', true,
    'nft_shop', true,
    'marketplace', true,
    'auction', true,
    'fc_spend', true,
    'other_ton', true
  )), 'events', 'Spending Event point rules')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.spending_event_rules()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'ton_points', 100000, 'fc_points', 1,
    'sources', jsonb_build_object('ton_direct_deposit', true, 'ton_to_fc', true, 'myth_sale', true,
      'season_pass', true, 'packs', true, 'nft_shop', true, 'marketplace', true, 'auction', true,
      'fc_spend', true, 'other_ton', true)
  ) || COALESCE((SELECT value FROM game_settings WHERE key = 'spending_event_rules'), '{}'::jsonb)
$$;

-- source_type -> configurable group
CREATE OR REPLACE FUNCTION public.spending_source_group(p_source_type text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'ton_direct_deposit%' THEN 'ton_direct_deposit'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'ton_to_fc%' OR lower(COALESCE(p_source_type,'')) LIKE 'deposit_credit%' THEN 'ton_to_fc'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'myth%' THEN 'myth_sale'
    WHEN lower(COALESCE(p_source_type,'')) LIKE '%pass%' THEN 'season_pass'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'founder%' OR lower(COALESCE(p_source_type,'')) LIKE 'veteran%'
      OR lower(COALESCE(p_source_type,'')) LIKE 'premium_egg%' THEN 'packs'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'nft%' THEN 'nft_shop'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'market%' THEN 'marketplace'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'auction%' THEN 'auction'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'fc%' OR lower(COALESCE(p_source_type,'')) LIKE '%_fc_spend%' THEN 'fc_spend'
    WHEN lower(COALESCE(p_source_type,'')) LIKE 'other_ton%' THEN 'other_ton'
    ELSE 'fc_spend'
  END
$$;

CREATE OR REPLACE FUNCTION public.spending_source_enabled(p_source_type text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(
    (public.spending_event_rules() -> 'sources' ->> public.spending_source_group(p_source_type))::boolean, true)
$$;

CREATE OR REPLACE FUNCTION public.spending_currency_rate(p_currency text)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(0, CASE WHEN upper(COALESCE(p_currency,'FC')) = 'TON'
    THEN COALESCE((public.spending_event_rules() ->> 'ton_points')::numeric, 100000)
    ELSE COALESCE((public.spending_event_rules() ->> 'fc_points')::numeric, 1) END)
$$;

-- 2. PLAYER AGGREGATE --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.spending_event_scores (
  event_id uuid NOT NULL REFERENCES public.spending_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  total_points numeric NOT NULL DEFAULT 0,
  ton_points numeric NOT NULL DEFAULT 0,
  fc_points numeric NOT NULL DEFAULT 0,
  ton_spent numeric NOT NULL DEFAULT 0,
  fc_spent numeric NOT NULL DEFAULT 0,
  score_reached_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);
CREATE INDEX IF NOT EXISTS spending_event_scores_rank_idx
  ON public.spending_event_scores (event_id, total_points DESC, score_reached_at ASC);

GRANT SELECT ON public.spending_event_scores TO authenticated;
GRANT SELECT ON public.spending_event_scores TO anon;
GRANT ALL ON public.spending_event_scores TO service_role;
ALTER TABLE public.spending_event_scores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Spending event ranking is public" ON public.spending_event_scores;
CREATE POLICY "Spending event ranking is public" ON public.spending_event_scores FOR SELECT USING (true);

-- 3. AGGREGATE MAINTENANCE --------------------------------------------
CREATE OR REPLACE FUNCTION public.spending_event_recount_user(p_event_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_total numeric; v_ton numeric; v_fc numeric; v_ton_amt numeric; v_fc_amt numeric; v_at timestamptz;
BEGIN
  IF p_event_id IS NULL OR p_user_id IS NULL THEN RETURN; END IF;
  SELECT COALESCE(SUM(spending_points),0),
         COALESCE(SUM(CASE WHEN currency='TON' THEN spending_points ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN currency='FC' THEN spending_points ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN currency='TON' THEN original_amount ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN currency='FC' THEN original_amount ELSE 0 END),0),
         COALESCE(MAX(created_at), now())
    INTO v_total, v_ton, v_fc, v_ton_amt, v_fc_amt, v_at
    FROM spending_event_entries WHERE event_id = p_event_id AND user_id = p_user_id;

  INSERT INTO spending_event_scores(event_id, user_id, total_points, ton_points, fc_points, ton_spent, fc_spent, score_reached_at, updated_at)
  VALUES (p_event_id, p_user_id, v_total, v_ton, v_fc, v_ton_amt, v_fc_amt, v_at, now())
  ON CONFLICT (event_id, user_id) DO UPDATE SET
    total_points = EXCLUDED.total_points, ton_points = EXCLUDED.ton_points, fc_points = EXCLUDED.fc_points,
    ton_spent = EXCLUDED.ton_spent, fc_spent = EXCLUDED.fc_spent,
    score_reached_at = CASE WHEN EXCLUDED.total_points > spending_event_scores.total_points
                            THEN now() ELSE spending_event_scores.score_reached_at END,
    updated_at = now();
END $$;

-- 4. SCORING CORE (idempotent) ----------------------------------------
CREATE OR REPLACE FUNCTION public.record_spending_points(
  p_user_id uuid, p_source_type text, p_source_transaction_id text, p_currency text, p_amount numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE ev public.spending_events; v_rate numeric; v_points numeric; v_inserted integer;
        v_src text := lower(COALESCE(p_source_type, 'other'));
BEGIN
  IF p_user_id IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN RETURN; END IF;
  SELECT * INTO ev FROM public.active_spending_event();
  IF ev.id IS NULL THEN RETURN; END IF;
  IF NOT public.spending_source_enabled(v_src) THEN RETURN; END IF;

  v_rate := public.spending_currency_rate(p_currency);
  v_points := round(p_amount * v_rate);
  IF v_points <= 0 THEN RETURN; END IF;

  INSERT INTO spending_event_entries(event_id, user_id, source_transaction_id, source_type, currency,
    original_amount, conversion_rate_fc, spending_points)
  VALUES (ev.id, p_user_id, p_source_transaction_id, v_src, upper(COALESCE(p_currency,'FC')),
    p_amount, v_rate, v_points)
  ON CONFLICT (event_id, source_transaction_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted > 0 THEN
    PERFORM public.spending_event_recount_user(ev.id, p_user_id);
    PERFORM public.spending_event_refresh_ticker(ev.id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.record_spending_reversal(p_source_transaction_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE e public.spending_event_entries; v_inserted integer;
BEGIN
  SELECT * INTO e FROM spending_event_entries
   WHERE source_transaction_id = p_source_transaction_id AND NOT is_reversal
   ORDER BY created_at DESC LIMIT 1;
  IF e.id IS NULL THEN RETURN; END IF;
  INSERT INTO spending_event_entries(event_id, user_id, source_transaction_id, source_type, currency,
    original_amount, conversion_rate_fc, spending_points, is_reversal)
  VALUES (e.event_id, e.user_id, 'reversal:' || p_source_transaction_id, e.source_type || '_reversal',
    e.currency, -e.original_amount, e.conversion_rate_fc, -e.spending_points, true)
  ON CONFLICT (event_id, source_transaction_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted > 0 THEN
    PERFORM public.spending_event_recount_user(e.event_id, e.user_id);
    PERFORM public.spending_event_refresh_ticker(e.event_id);
  END IF;
END $$;

-- ticker now built from the aggregate
CREATE OR REPLACE FUNCTION public.spending_event_refresh_ticker(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_points numeric; v_fc numeric; v_ton numeric; v_participants integer;
BEGIN
  SELECT COALESCE(SUM(total_points),0), COALESCE(SUM(fc_spent),0), COALESCE(SUM(ton_spent),0),
         COUNT(*) FILTER (WHERE total_points > 0)
    INTO v_points, v_fc, v_ton, v_participants
    FROM spending_event_scores WHERE event_id = p_event_id;
  INSERT INTO spending_event_ticker(event_id, total_points, total_fc, total_ton, participants, updated_at)
  VALUES (p_event_id, v_points, v_fc, v_ton, v_participants, now())
  ON CONFLICT (event_id) DO UPDATE SET total_points = EXCLUDED.total_points, total_fc = EXCLUDED.total_fc,
    total_ton = EXCLUDED.total_ton, participants = EXCLUDED.participants, updated_at = now();
END $$;

-- 5. RANKING FROM AGGREGATE (tie -> reached first) ---------------------
CREATE OR REPLACE FUNCTION public.get_spending_event_ranking(p_event_id uuid, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH ranked AS (
    SELECT ROW_NUMBER() OVER (ORDER BY s.total_points DESC, s.score_reached_at ASC, s.user_id) AS position,
           s.user_id, s.total_points AS points, s.fc_spent, s.ton_spent,
           COALESCE(NULLIF(TRIM(COALESCE(g.display_name, '')), ''), NULLIF(g.username,''), 'Player') AS name,
           g.username, g.avatar_url
      FROM spending_event_scores s LEFT JOIN game_players g ON g.id = s.user_id
     WHERE s.event_id = p_event_id AND s.total_points > 0
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'position', r.position, 'userId', r.user_id, 'name', r.name, 'username', r.username,
    'avatarUrl', r.avatar_url, 'points', r.points, 'fcSpent', r.fc_spent, 'tonSpent', r.ton_spent,
    'estimatedReward', public.spending_event_reward_label(p_event_id, r.position::int)
  ) ORDER BY r.position), '[]'::jsonb)
  FROM (SELECT * FROM ranked ORDER BY position
         LIMIT GREATEST(1, LEAST(COALESCE(p_limit,20), 200)) OFFSET GREATEST(0, COALESCE(p_offset,0))) r
$$;

CREATE OR REPLACE FUNCTION public.get_spending_event_dashboard(p_telegram_id bigint, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  ev public.spending_events; v_uid uuid; v_ranking jsonb; v_rewards jsonb;
  v_me public.spending_event_scores; v_pos integer; v_next_points numeric;
  v_ticker public.spending_event_ticker; v_next jsonb;
BEGIN
  SELECT * INTO ev FROM public.active_spending_event();
  IF ev.id IS NULL THEN
    SELECT * INTO ev FROM spending_events WHERE status IN ('scheduled','finished')
      ORDER BY (status = 'scheduled') DESC, starts_at DESC LIMIT 1;
  END IF;
  SELECT id INTO v_uid FROM game_players WHERE telegram_id = p_telegram_id;

  IF ev.id IS NULL THEN
    RETURN jsonb_build_object('event', NULL, 'ranking', '[]'::jsonb, 'rewards', '[]'::jsonb,
      'totals', jsonb_build_object('points',0,'fcSpent',0,'tonSpent',0,'participants',0),
      'player', jsonb_build_object('points',0,'fcSpent',0,'tonSpent',0,'position',NULL,
        'estimatedReward',NULL,'nextRank',NULL,'neededToNext',NULL),
      'serverTime', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF'));
  END IF;

  SELECT * INTO v_me FROM spending_event_scores WHERE event_id = ev.id AND user_id = v_uid;

  IF COALESCE(v_me.total_points, 0) > 0 THEN
    SELECT COUNT(*) + 1 INTO v_pos FROM spending_event_scores s
     WHERE s.event_id = ev.id AND (s.total_points > v_me.total_points
       OR (s.total_points = v_me.total_points AND s.score_reached_at < v_me.score_reached_at));
    SELECT MIN(s.total_points) INTO v_next_points FROM spending_event_scores s
     WHERE s.event_id = ev.id AND s.total_points > v_me.total_points;
  END IF;

  v_ranking := public.get_spending_event_ranking(ev.id, COALESCE(p_limit, ev.top_limit), 0);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('from', position_from, 'to', position_to, 'label', label)
    ORDER BY position_from), '[]'::jsonb) INTO v_rewards
    FROM spending_event_rewards r
   WHERE r.event_id = ev.id OR (r.event_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM spending_event_rewards x WHERE x.event_id = ev.id));
  SELECT * INTO v_ticker FROM spending_event_ticker WHERE event_id = ev.id;

  IF v_pos IS NOT NULL AND v_pos > 1 AND v_next_points IS NOT NULL THEN
    v_next := jsonb_build_object('rank', v_pos - 1, 'needed', GREATEST(0, v_next_points - COALESCE(v_me.total_points,0) + 1));
  END IF;

  RETURN jsonb_build_object(
    'event', jsonb_build_object('id', ev.id, 'name', ev.name, 'startsAt', ev.starts_at, 'endsAt', ev.ends_at,
      'status', ev.status, 'tonRateFc', public.spending_currency_rate('TON'), 'topLimit', ev.top_limit),
    'totals', jsonb_build_object('points', COALESCE(v_ticker.total_points,0), 'fcSpent', COALESCE(v_ticker.total_fc,0),
      'tonSpent', COALESCE(v_ticker.total_ton,0), 'participants', COALESCE(v_ticker.participants,0)),
    'player', jsonb_build_object('points', COALESCE(v_me.total_points,0), 'fcSpent', COALESCE(v_me.fc_spent,0),
      'tonSpent', COALESCE(v_me.ton_spent,0), 'position', v_pos,
      'estimatedReward', CASE WHEN v_pos IS NULL THEN NULL ELSE public.spending_event_reward_label(ev.id, v_pos) END,
      'nextRank', v_next -> 'rank', 'neededToNext', v_next -> 'needed'),
    'ranking', v_ranking,
    'rewards', v_rewards,
    'serverTime', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF'));
END $$;

-- 6. GENERIC CONFIRMED-PAYMENT HOOK -----------------------------------
CREATE OR REPLACE FUNCTION public.spending_track_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_src text := TG_ARGV[0]; v_amount_col text := TG_ARGV[1]; v_currency text := TG_ARGV[2];
  v_user_col text := COALESCE(TG_ARGV[3], 'user_id');
  j jsonb := to_jsonb(NEW); o jsonb := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE '{}'::jsonb END;
  st text := lower(COALESCE(j->>'status','')); ost text := lower(COALESCE(o->>'status',''));
  v_uid uuid; v_amount numeric; v_ref text;
BEGIN
  IF st = ost THEN RETURN NEW; END IF;
  v_uid := NULLIF(j->>v_user_col, '')::uuid;
  v_amount := COALESCE(NULLIF(j->>v_amount_col,'')::numeric, 0);
  v_ref := v_src || ':' || COALESCE(j->>'id','');
  IF st IN ('confirmed','completed','credited','delivered','settled','paid','paid_confirmed','activated','active','success','claimed') THEN
    PERFORM public.record_spending_points(v_uid, v_src, v_ref, v_currency, v_amount);
  ELSIF st IN ('refunded','reversed','cancelled','canceled','failed','expired','chargeback') THEN
    PERFORM public.record_spending_reversal(v_ref);
  END IF;
  RETURN NEW;
END $$;

-- MYTH sale
DROP TRIGGER IF EXISTS spending_track_myth_sale_trg ON public.myth_sale_transactions;
CREATE TRIGGER spending_track_myth_sale_trg AFTER INSERT OR UPDATE ON public.myth_sale_transactions
FOR EACH ROW EXECUTE FUNCTION public.spending_track_payment('myth_purchase', 'amount_ton', 'TON', 'user_id');

-- Founder Pack
DROP TRIGGER IF EXISTS spending_track_founder_pack_trg ON public.founder_pack_purchases;
CREATE TRIGGER spending_track_founder_pack_trg AFTER INSERT OR UPDATE ON public.founder_pack_purchases
FOR EACH ROW EXECUTE FUNCTION public.spending_track_payment('founder_pack', 'price_ton', 'TON', 'user_id');

-- Veteran Vault
DROP TRIGGER IF EXISTS spending_track_veteran_vault_trg ON public.veteran_vault_purchases;
CREATE TRIGGER spending_track_veteran_vault_trg AFTER INSERT OR UPDATE ON public.veteran_vault_purchases
FOR EACH ROW EXECUTE FUNCTION public.spending_track_payment('veteran_vault', 'price_ton', 'TON', 'user_id');

-- NFT shop
DROP TRIGGER IF EXISTS spending_track_nft_hero_trg ON public.nft_hero_orders;
CREATE TRIGGER spending_track_nft_hero_trg AFTER INSERT OR UPDATE ON public.nft_hero_orders
FOR EACH ROW EXECUTE FUNCTION public.spending_track_payment('nft_purchase_hero', 'price_ton', 'TON', 'user_id');
DROP TRIGGER IF EXISTS spending_track_nft_pet_trg ON public.nft_pet_orders;
CREATE TRIGGER spending_track_nft_pet_trg AFTER INSERT OR UPDATE ON public.nft_pet_orders
FOR EACH ROW EXECUTE FUNCTION public.spending_track_payment('nft_purchase_pet', 'price_ton', 'TON', 'user_id');
DROP TRIGGER IF EXISTS spending_track_nft_equipment_trg ON public.nft_equipment_orders;
CREATE TRIGGER spending_track_nft_equipment_trg AFTER INSERT OR UPDATE ON public.nft_equipment_orders
FOR EACH ROW EXECUTE FUNCTION public.spending_track_payment('nft_purchase_equipment', 'price_ton', 'TON', 'user_id');

-- Season Pass locked reward unlocks (paid in TON)
DROP TRIGGER IF EXISTS spending_track_pass_locked_trg ON public.pass_locked_reward_orders;
CREATE TRIGGER spending_track_pass_locked_trg AFTER INSERT OR UPDATE ON public.pass_locked_reward_orders
FOR EACH ROW EXECUTE FUNCTION public.spending_track_payment('season_pass_locked', 'price_ton', 'TON', 'user_id');

-- 7. TON WALLET LEDGER (deposits, TON->FC, other internal TON spends) --
CREATE OR REPLACE FUNCTION public.spending_track_wallet_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_type text := lower(COALESCE(NEW.type,'')); v_ton numeric := COALESCE(NEW.amount_ton, 0);
BEGIN
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;
  IF v_type = 'ton_direct_deposit' AND v_ton > 0 THEN
    PERFORM public.record_spending_points(NEW.user_id, 'ton_direct_deposit', 'wl:' || NEW.id::text, 'TON', v_ton);
  ELSIF v_type = 'deposit_credit' AND v_ton > 0 THEN
    PERFORM public.record_spending_points(NEW.user_id, 'ton_to_fc', 'wl:' || NEW.id::text, 'TON', v_ton);
  ELSIF v_ton < 0 AND v_type NOT IN ('withdrawal','withdrawal_request','withdrawal_hold','refund','transfer',
      'duplicate_payment_refund','myth_purchase','market_purchase','market_sale','auction_bid','auction_hold',
      'auction_settlement','founder_pack','veteran_vault','season_pass','nft_purchase','admin_balance_adjustment') THEN
    PERFORM public.record_spending_points(NEW.user_id, 'other_ton_spend', 'wl:' || NEW.id::text, 'TON', abs(v_ton));
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS spending_track_wallet_ledger_trg ON public.wallet_ledger;
CREATE TRIGGER spending_track_wallet_ledger_trg AFTER INSERT ON public.wallet_ledger
FOR EACH ROW EXECUTE FUNCTION public.spending_track_wallet_ledger();

-- 8. MARKETPLACE SETTLEMENT (buyer only, TON or FC) --------------------
CREATE OR REPLACE FUNCTION public.spending_track_market_transaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE st text := lower(COALESCE(NEW.status,'')); ost text := lower(COALESCE(OLD.status,''));
        v_cur text := upper(COALESCE(NEW.currency,'FC')); v_amount numeric; v_ref text := 'market_tx:' || NEW.id::text;
BEGIN
  IF TG_OP = 'UPDATE' AND st = ost THEN RETURN NEW; END IF;
  v_amount := CASE WHEN v_cur = 'TON' THEN COALESCE(NEW.price_ton,0) ELSE COALESCE(NEW.price_fc,0) END;
  IF st IN ('settled','completed','delivered','confirmed') THEN
    PERFORM public.record_spending_points(NEW.buyer_user_id, 'market_purchase', v_ref, v_cur, v_amount);
  ELSIF st IN ('reversed','refunded','cancelled','canceled','failed') THEN
    PERFORM public.record_spending_reversal(v_ref);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS spending_track_market_transaction_trg ON public.market_transactions;
CREATE TRIGGER spending_track_market_transaction_trg AFTER INSERT OR UPDATE ON public.market_transactions
FOR EACH ROW EXECUTE FUNCTION public.spending_track_market_transaction();

-- 9. AUCTION SETTLEMENT (winner only) ---------------------------------
CREATE OR REPLACE FUNCTION public.spending_track_auction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE st text := lower(COALESCE(NEW.status,'')); ost text := lower(COALESCE(OLD.status,''));
        v_ref text := 'auction:' || NEW.id::text;
BEGIN
  IF TG_OP = 'UPDATE' AND st = ost THEN RETURN NEW; END IF;
  IF st IN ('settled','completed','finished','sold') AND NEW.winner_user_id IS NOT NULL
     AND COALESCE(NEW.final_price_ton, 0) > 0 THEN
    PERFORM public.record_spending_points(NEW.winner_user_id, 'auction_settlement', v_ref, 'TON', NEW.final_price_ton);
  ELSIF st IN ('reversed','refunded','cancelled','canceled','failed') THEN
    PERFORM public.record_spending_reversal(v_ref);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS spending_track_auction_trg ON public.auctions;
CREATE TRIGGER spending_track_auction_trg AFTER UPDATE ON public.auctions
FOR EACH ROW EXECUTE FUNCTION public.spending_track_auction();

-- 10. BACKFILL AGGREGATE FROM EXISTING LEDGER -------------------------
INSERT INTO public.spending_event_scores(event_id, user_id, total_points, ton_points, fc_points, ton_spent, fc_spent, score_reached_at, updated_at)
SELECT e.event_id, e.user_id, SUM(e.spending_points),
       SUM(CASE WHEN e.currency='TON' THEN e.spending_points ELSE 0 END),
       SUM(CASE WHEN e.currency='FC' THEN e.spending_points ELSE 0 END),
       SUM(CASE WHEN e.currency='TON' THEN e.original_amount ELSE 0 END),
       SUM(CASE WHEN e.currency='FC' THEN e.original_amount ELSE 0 END),
       MAX(e.created_at), now()
  FROM public.spending_event_entries e
 WHERE e.user_id IS NOT NULL
 GROUP BY e.event_id, e.user_id
ON CONFLICT (event_id, user_id) DO UPDATE SET
  total_points = EXCLUDED.total_points, ton_points = EXCLUDED.ton_points, fc_points = EXCLUDED.fc_points,
  ton_spent = EXCLUDED.ton_spent, fc_spent = EXCLUDED.fc_spent, updated_at = now();

-- refresh tickers for every event that has scores
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT event_id FROM public.spending_event_scores LOOP
    PERFORM public.spending_event_refresh_ticker(r.event_id);
  END LOOP;
END $$;

-- 11. REALTIME --------------------------------------------------------
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.spending_event_scores;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
ALTER TABLE public.spending_event_scores REPLICA IDENTITY FULL;
