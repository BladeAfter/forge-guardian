-- =========================================================
-- MYTHREON :: SPENDING EVENT (tracking layer only)
-- =========================================================

CREATE TABLE public.spending_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL DEFAULT 'SPENDING EVENT',
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL DEFAULT now() + interval '7 days',
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','active','finished','cancelled')),
  ton_rate_fc numeric NOT NULL DEFAULT 100000,
  top_limit integer NOT NULL DEFAULT 20,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.spending_events TO anon, authenticated;
GRANT ALL ON public.spending_events TO service_role;
ALTER TABLE public.spending_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "spending_events_public_read" ON public.spending_events FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE public.spending_event_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.spending_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  source_transaction_id text NOT NULL,
  source_type text NOT NULL,
  currency text NOT NULL CHECK (currency IN ('FC','TON')),
  original_amount numeric NOT NULL DEFAULT 0,
  conversion_rate_fc numeric NOT NULL DEFAULT 1,
  spending_points numeric NOT NULL DEFAULT 0,
  is_reversal boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, source_transaction_id)
);
GRANT ALL ON public.spending_event_entries TO service_role;
ALTER TABLE public.spending_event_entries ENABLE ROW LEVEL SECURITY;
CREATE INDEX spending_event_entries_event_user_idx ON public.spending_event_entries(event_id, user_id);

-- Public aggregate ticker (no personal data) used for realtime updates.
CREATE TABLE public.spending_event_ticker (
  event_id uuid PRIMARY KEY REFERENCES public.spending_events(id) ON DELETE CASCADE,
  total_points numeric NOT NULL DEFAULT 0,
  total_fc numeric NOT NULL DEFAULT 0,
  total_ton numeric NOT NULL DEFAULT 0,
  participants integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.spending_event_ticker TO anon, authenticated;
GRANT ALL ON public.spending_event_ticker TO service_role;
ALTER TABLE public.spending_event_ticker ENABLE ROW LEVEL SECURITY;
CREATE POLICY "spending_event_ticker_public_read" ON public.spending_event_ticker FOR SELECT TO anon, authenticated USING (true);

-- Rewards per position. event_id NULL = global default table.
CREATE TABLE public.spending_event_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid REFERENCES public.spending_events(id) ON DELETE CASCADE,
  position_from integer NOT NULL CHECK (position_from >= 1),
  position_to integer NOT NULL CHECK (position_to >= 1),
  label text NOT NULL,
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX spending_event_rewards_slot_idx ON public.spending_event_rewards(COALESCE(event_id, '00000000-0000-0000-0000-000000000000'::uuid), position_from);
GRANT SELECT ON public.spending_event_rewards TO anon, authenticated;
GRANT ALL ON public.spending_event_rewards TO service_role;
ALTER TABLE public.spending_event_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "spending_event_rewards_public_read" ON public.spending_event_rewards FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE public.spending_event_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.spending_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  final_rank integer NOT NULL,
  final_points numeric NOT NULL DEFAULT 0,
  reward_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  reward_status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, user_id)
);
GRANT ALL ON public.spending_event_results TO service_role;
ALTER TABLE public.spending_event_results ENABLE ROW LEVEL SECURITY;

-- Default reward table (spec)
INSERT INTO public.spending_event_rewards(event_id, position_from, position_to, label) VALUES
 (NULL,1,1,'Ancestral Egg + Exclusive Hero + 100 Universal Fragments + Legendary Chest'),
 (NULL,2,2,'Dragon Egg + Legendary Chest + 80 Universal Fragments'),
 (NULL,3,3,'Dragon Egg + Epic Chest + 70 Universal Fragments'),
 (NULL,4,4,'Epic Egg + Epic Chest + 60 Universal Fragments'),
 (NULL,5,5,'Epic Egg + Epic Chest + 50 Universal Fragments'),
 (NULL,6,6,'Epic Egg + Rare Chest + 45 Universal Fragments'),
 (NULL,7,7,'Epic Chest + 40 Universal Fragments + 5 PvP Tickets'),
 (NULL,8,8,'Epic Chest + 35 Universal Fragments + 5 PvP Tickets'),
 (NULL,9,9,'Rare Chest + 30 Universal Fragments + Pet Food'),
 (NULL,10,10,'Rare Chest + 25 Universal Fragments + Pet Food'),
 (NULL,11,12,'Rare Chest + 20 Universal Fragments'),
 (NULL,13,14,'Rare Chest + 15 Universal Fragments'),
 (NULL,15,16,'Common Chest + 15 Universal Fragments'),
 (NULL,17,18,'Common Chest + 10 Universal Fragments'),
 (NULL,19,20,'Common Chest + 5 Universal Fragments');

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spending_ton_rate_fc()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(1, COALESCE(
    (SELECT value_numeric FROM economy_settings WHERE key = 'fc_per_ton'),
    (SELECT value_numeric FROM economy_settings WHERE key = 'ton_to_fc_rate'),
    (SELECT value_numeric FROM economy_settings WHERE key = 'ton_fc_rate'),
    100000))
$$;

CREATE OR REPLACE FUNCTION public.active_spending_event()
RETURNS public.spending_events LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM spending_events
   WHERE status = 'active' AND now() >= starts_at AND now() < ends_at
   ORDER BY starts_at DESC LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.spending_event_reward_label(p_event_id uuid, p_position integer)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT label FROM spending_event_rewards
   WHERE (event_id = p_event_id OR event_id IS NULL)
     AND p_position BETWEEN position_from AND position_to
   ORDER BY (event_id IS NULL) ASC LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.spending_event_refresh_ticker(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_points numeric; v_fc numeric; v_ton numeric; v_participants integer;
BEGIN
  SELECT COALESCE(SUM(spending_points),0),
         COALESCE(SUM(CASE WHEN currency='FC' THEN original_amount ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN currency='TON' THEN original_amount ELSE 0 END),0)
    INTO v_points, v_fc, v_ton
    FROM spending_event_entries WHERE event_id = p_event_id;
  SELECT COUNT(*) INTO v_participants FROM (
    SELECT user_id FROM spending_event_entries WHERE event_id = p_event_id
     GROUP BY user_id HAVING SUM(spending_points) > 0) s;
  INSERT INTO spending_event_ticker(event_id, total_points, total_fc, total_ton, participants, updated_at)
  VALUES (p_event_id, v_points, v_fc, v_ton, v_participants, now())
  ON CONFLICT (event_id) DO UPDATE SET total_points = EXCLUDED.total_points, total_fc = EXCLUDED.total_fc,
    total_ton = EXCLUDED.total_ton, participants = EXCLUDED.participants, updated_at = now();
END $$;

/** Records one confirmed spend. Idempotent per (event, source transaction). */
CREATE OR REPLACE FUNCTION public.record_spending_points(
  p_user_id uuid, p_source_type text, p_source_transaction_id text, p_currency text, p_amount numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE ev public.spending_events; v_rate numeric; v_points numeric; v_inserted integer;
BEGIN
  IF p_user_id IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN RETURN; END IF;
  SELECT * INTO ev FROM public.active_spending_event();
  IF ev.id IS NULL THEN RETURN; END IF;
  v_rate := CASE WHEN upper(p_currency) = 'TON' THEN COALESCE(ev.ton_rate_fc, public.spending_ton_rate_fc()) ELSE 1 END;
  v_points := round(p_amount * v_rate);
  IF v_points <= 0 THEN RETURN; END IF;
  INSERT INTO spending_event_entries(event_id, user_id, source_transaction_id, source_type, currency,
    original_amount, conversion_rate_fc, spending_points)
  VALUES (ev.id, p_user_id, p_source_transaction_id, p_source_type, upper(p_currency), p_amount, v_rate, v_points)
  ON CONFLICT (event_id, source_transaction_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted > 0 THEN PERFORM public.spending_event_refresh_ticker(ev.id); END IF;
END $$;

/** Reverses a previously counted spend without deleting history. */
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
  IF v_inserted > 0 THEN PERFORM public.spending_event_refresh_ticker(e.event_id); END IF;
END $$;

-- ---------------------------------------------------------
-- Automatic tracking
-- ---------------------------------------------------------
/**
 * Any real FC decrease is a spend. Withdrawals and admin adjustments are NOT spends,
 * so a matching row created inside the same transaction opts the update out.
 */
CREATE OR REPLACE FUNCTION public.spending_track_fc_spend()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_delta numeric;
BEGIN
  v_delta := COALESCE(OLD.forge_coins, 0) - COALESCE(NEW.forge_coins, 0);
  IF v_delta <= 0 THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM wallet_withdrawals w
              WHERE w.user_id = NEW.id AND w.created_at >= transaction_timestamp()) THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM wallet_ledger l
              WHERE l.user_id = NEW.id AND l.created_at >= transaction_timestamp()
                AND l.type IN ('admin_balance_adjustment','withdrawal','withdrawal_request','withdrawal_hold','refund','transfer')) THEN
    RETURN NEW;
  END IF;
  PERFORM public.record_spending_points(NEW.id, 'fc_spend',
    'fc:' || txid_current()::text || ':' || replace(gen_random_uuid()::text, '-', ''), 'FC', v_delta);
  RETURN NEW;
END $$;

CREATE TRIGGER spending_track_fc_spend_trg
AFTER UPDATE OF forge_coins ON public.game_players
FOR EACH ROW EXECUTE FUNCTION public.spending_track_fc_spend();

/** Confirmed TON purchases only (pending/failed/cancelled never count). */
CREATE OR REPLACE FUNCTION public.spending_track_ton_order()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ref text; v_type text; v_amount numeric;
BEGIN
  IF TG_TABLE_NAME = 'pet_egg_orders' THEN v_ref := 'egg_order:' || NEW.id::text; v_type := 'premium_egg';
  ELSE v_ref := 'pass_order:' || NEW.id::text; v_type := 'battle_pass'; END IF;
  v_amount := COALESCE(NEW.price_ton, 0);
  IF lower(COALESCE(NEW.status,'')) IN ('confirmed','completed','credited','delivered','activated','paid_confirmed')
     AND lower(COALESCE(OLD.status,'')) IS DISTINCT FROM lower(COALESCE(NEW.status,'')) THEN
    PERFORM public.record_spending_points(NEW.user_id, v_type, v_ref, 'TON', v_amount);
  ELSIF lower(COALESCE(NEW.status,'')) IN ('refunded','reversed','cancelled','failed')
     AND lower(COALESCE(OLD.status,'')) IS DISTINCT FROM lower(COALESCE(NEW.status,'')) THEN
    PERFORM public.record_spending_reversal(v_ref);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER spending_track_egg_order_trg
AFTER UPDATE OF status ON public.pet_egg_orders
FOR EACH ROW EXECUTE FUNCTION public.spending_track_ton_order();

CREATE TRIGGER spending_track_pass_order_trg
AFTER UPDATE OF status ON public.season_pass_orders
FOR EACH ROW EXECUTE FUNCTION public.spending_track_ton_order();

-- ---------------------------------------------------------
-- Read API
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_spending_event_ranking(p_event_id uuid, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH totals AS (
    SELECT e.user_id, SUM(e.spending_points) AS points,
           SUM(CASE WHEN e.currency='FC' THEN e.original_amount ELSE 0 END) AS fc_spent,
           SUM(CASE WHEN e.currency='TON' THEN e.original_amount ELSE 0 END) AS ton_spent
      FROM spending_event_entries e WHERE e.event_id = p_event_id
     GROUP BY e.user_id HAVING SUM(e.spending_points) > 0
  ), ranked AS (
    SELECT ROW_NUMBER() OVER (ORDER BY t.points DESC, t.user_id) AS position, t.*,
           COALESCE(NULLIF(TRIM(COALESCE(g.display_name, '')), ''), NULLIF(g.username,''), 'Player') AS name,
           g.username, g.avatar_url
      FROM totals t LEFT JOIN game_players g ON g.id = t.user_id
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
  v_points numeric := 0; v_fc numeric := 0; v_ton numeric := 0; v_pos integer;
  v_next_points numeric; v_ticker public.spending_event_ticker; v_next jsonb;
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

  SELECT COALESCE(SUM(spending_points),0),
         COALESCE(SUM(CASE WHEN currency='FC' THEN original_amount ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN currency='TON' THEN original_amount ELSE 0 END),0)
    INTO v_points, v_fc, v_ton
    FROM spending_event_entries WHERE event_id = ev.id AND user_id = v_uid;

  IF v_points > 0 THEN
    SELECT COUNT(*) + 1 INTO v_pos FROM (
      SELECT user_id, SUM(spending_points) AS pts FROM spending_event_entries
       WHERE event_id = ev.id GROUP BY user_id HAVING SUM(spending_points) > v_points) s;
    SELECT MIN(pts) INTO v_next_points FROM (
      SELECT user_id, SUM(spending_points) AS pts FROM spending_event_entries
       WHERE event_id = ev.id GROUP BY user_id HAVING SUM(spending_points) > v_points) s2;
  END IF;

  v_ranking := public.get_spending_event_ranking(ev.id, COALESCE(p_limit, ev.top_limit), 0);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('from', position_from, 'to', position_to, 'label', label)
    ORDER BY position_from), '[]'::jsonb) INTO v_rewards
    FROM spending_event_rewards r
   WHERE r.event_id = ev.id OR (r.event_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM spending_event_rewards x WHERE x.event_id = ev.id));
  SELECT * INTO v_ticker FROM spending_event_ticker WHERE event_id = ev.id;

  IF v_pos IS NOT NULL AND v_pos > 1 AND v_next_points IS NOT NULL THEN
    v_next := jsonb_build_object('rank', v_pos - 1, 'needed', GREATEST(0, v_next_points - v_points + 1));
  END IF;

  RETURN jsonb_build_object(
    'event', jsonb_build_object('id', ev.id, 'name', ev.name, 'startsAt', ev.starts_at, 'endsAt', ev.ends_at,
      'status', ev.status, 'tonRateFc', ev.ton_rate_fc, 'topLimit', ev.top_limit),
    'totals', jsonb_build_object('points', COALESCE(v_ticker.total_points,0), 'fcSpent', COALESCE(v_ticker.total_fc,0),
      'tonSpent', COALESCE(v_ticker.total_ton,0), 'participants', COALESCE(v_ticker.participants,0)),
    'player', jsonb_build_object('points', v_points, 'fcSpent', v_fc, 'tonSpent', v_ton, 'position', v_pos,
      'estimatedReward', CASE WHEN v_pos IS NULL THEN NULL ELSE public.spending_event_reward_label(ev.id, v_pos) END,
      'nextRank', v_next -> 'rank', 'neededToNext', v_next -> 'needed'),
    'ranking', v_ranking,
    'rewards', v_rewards,
    'serverTime', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF'));
END $$;

-- ---------------------------------------------------------
-- Admin API
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_spending_event_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE ev public.spending_events; v_ticker public.spending_event_ticker; v_events jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO ev FROM public.active_spending_event();
  IF ev.id IS NULL THEN
    SELECT * INTO ev FROM spending_events ORDER BY created_at DESC LIMIT 1;
  END IF;
  SELECT * INTO v_ticker FROM spending_event_ticker WHERE event_id = ev.id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status,
    'startsAt', starts_at, 'endsAt', ends_at) ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_events FROM (SELECT * FROM spending_events ORDER BY created_at DESC LIMIT 10) s;
  RETURN jsonb_build_object('event', CASE WHEN ev.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', ev.id, 'name', ev.name, 'status', ev.status, 'startsAt', ev.starts_at, 'endsAt', ev.ends_at,
      'tonRateFc', ev.ton_rate_fc, 'topLimit', ev.top_limit) END,
    'totals', jsonb_build_object('points', COALESCE(v_ticker.total_points,0), 'fcSpent', COALESCE(v_ticker.total_fc,0),
      'tonSpent', COALESCE(v_ticker.total_ton,0), 'participants', COALESCE(v_ticker.participants,0)),
    'events', v_events);
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_create(p_admin_id bigint, p_name text DEFAULT 'SPENDING EVENT', p_days integer DEFAULT 7)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid; v_days integer := GREATEST(1, LEAST(COALESCE(p_days,7), 90));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE spending_events SET status = 'finished', updated_at = now() WHERE status = 'active';
  INSERT INTO spending_events(name, starts_at, ends_at, status, ton_rate_fc)
  VALUES (COALESCE(NULLIF(TRIM(p_name), ''), 'SPENDING EVENT'), now(), now() + (v_days || ' days')::interval,
          'active', public.spending_ton_rate_fc())
  RETURNING id INTO v_id;
  PERFORM public.spending_event_refresh_ticker(v_id);
  PERFORM public.admin_log(p_admin_id, 'SPENDING_EVENT_CREATED', 'spending_event', v_id::text, NULL,
    jsonb_build_object('days', v_days, 'name', p_name), 'novo evento de gastos');
  RETURN public.admin_spending_event_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_set_status(p_admin_id bigint, p_event_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF lower(p_status) NOT IN ('scheduled','active','finished','cancelled') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
  IF lower(p_status) = 'active' THEN
    UPDATE spending_events SET status = 'finished', updated_at = now() WHERE status = 'active' AND id <> p_event_id;
    UPDATE spending_events SET status = 'active', starts_at = now(),
      ends_at = GREATEST(ends_at, now() + interval '1 day'), updated_at = now() WHERE id = p_event_id;
  ELSE
    UPDATE spending_events SET status = lower(p_status), updated_at = now() WHERE id = p_event_id;
  END IF;
  PERFORM public.admin_log(p_admin_id, 'SPENDING_EVENT_STATUS', 'spending_event', p_event_id::text, NULL,
    jsonb_build_object('status', lower(p_status)), 'status do evento de gastos');
  RETURN public.admin_spending_event_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_set_duration(p_admin_id bigint, p_event_id uuid, p_days integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_days integer := GREATEST(1, LEAST(COALESCE(p_days,7), 90));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE spending_events SET ends_at = starts_at + (v_days || ' days')::interval, updated_at = now()
   WHERE id = p_event_id;
  PERFORM public.admin_log(p_admin_id, 'SPENDING_EVENT_DURATION', 'spending_event', p_event_id::text, NULL,
    jsonb_build_object('days', v_days), 'duração do evento de gastos');
  RETURN public.admin_spending_event_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_set_reward(
  p_admin_id bigint, p_event_id uuid, p_from integer, p_to integer, p_label text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_from integer := GREATEST(1, COALESCE(p_from,1)); v_to integer := GREATEST(1, COALESCE(p_to, p_from, 1));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_to < v_from THEN v_to := v_from; END IF;
  IF NOT EXISTS (SELECT 1 FROM spending_event_rewards WHERE event_id = p_event_id) THEN
    INSERT INTO spending_event_rewards(event_id, position_from, position_to, label, items)
    SELECT p_event_id, position_from, position_to, label, items FROM spending_event_rewards WHERE event_id IS NULL;
  END IF;
  DELETE FROM spending_event_rewards WHERE event_id = p_event_id AND position_from = v_from;
  INSERT INTO spending_event_rewards(event_id, position_from, position_to, label)
  VALUES (p_event_id, v_from, v_to, COALESCE(NULLIF(TRIM(p_label),''), 'Reward'));
  PERFORM public.admin_log(p_admin_id, 'SPENDING_EVENT_REWARD', 'spending_event', p_event_id::text, NULL,
    jsonb_build_object('from', v_from, 'to', v_to, 'label', p_label), 'recompensa do evento de gastos');
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_ranking(p_admin_id bigint, p_event_id uuid, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object('ranking', public.get_spending_event_ranking(p_event_id, p_limit, 0));
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_audit(p_admin_id bigint, p_event_id uuid, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('sourceType', s.source_type, 'currency', s.currency,
    'originalAmount', s.original_amount, 'points', s.spending_points, 'createdAt', s.created_at,
    'player', COALESCE(g.username, g.display_name, g.telegram_id::text)) ORDER BY s.created_at DESC), '[]'::jsonb)
    INTO v FROM (SELECT * FROM spending_event_entries WHERE event_id = p_event_id
                  ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit,15), 50))) s
    LEFT JOIN game_players g ON g.id = s.user_id;
  RETURN jsonb_build_object('entries', v);
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_finalize(p_admin_id bigint, p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count integer;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('spending_finalize:' || p_event_id::text, 77));
  INSERT INTO spending_event_results(event_id, user_id, final_rank, final_points, reward_json, reward_status)
  SELECT p_event_id, (r->>'userId')::uuid, (r->>'position')::int, (r->>'points')::numeric,
         jsonb_build_object('label', r->>'estimatedReward'), 'pending'
    FROM jsonb_array_elements(public.get_spending_event_ranking(p_event_id, 200, 0)) r
  ON CONFLICT (event_id, user_id) DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  UPDATE spending_events SET status = 'finished', updated_at = now() WHERE id = p_event_id;
  PERFORM public.admin_log(p_admin_id, 'SPENDING_EVENT_FINALIZED', 'spending_event', p_event_id::text, NULL,
    jsonb_build_object('winners', v_count), 'ranking congelado');
  RETURN jsonb_build_object('ok', true, 'winners', v_count);
END $$;

-- Lock down execution
REVOKE ALL ON FUNCTION public.spending_ton_rate_fc() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.active_spending_event() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.spending_event_reward_label(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.spending_event_refresh_ticker(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_spending_points(uuid, text, text, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_spending_reversal(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_spending_event_ranking(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_spending_event_dashboard(bigint, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_overview(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_create(bigint, text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_set_status(bigint, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_set_duration(bigint, uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_set_reward(bigint, uuid, integer, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_ranking(bigint, uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_audit(bigint, uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_finalize(bigint, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.spending_ton_rate_fc() TO service_role;
GRANT EXECUTE ON FUNCTION public.active_spending_event() TO service_role;
GRANT EXECUTE ON FUNCTION public.spending_event_reward_label(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.spending_event_refresh_ticker(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_spending_points(uuid, text, text, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_spending_reversal(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_spending_event_ranking(uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_spending_event_dashboard(bigint, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_create(bigint, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_set_status(bigint, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_set_duration(bigint, uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_set_reward(bigint, uuid, integer, integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_ranking(bigint, uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_audit(bigint, uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_finalize(bigint, uuid) TO service_role;

-- Realtime for the public aggregate ticker only
ALTER PUBLICATION supabase_realtime ADD TABLE public.spending_event_ticker;

-- First event: 7 days, everybody starts at zero.
INSERT INTO public.spending_events(name, starts_at, ends_at, status, ton_rate_fc)
VALUES ('SPENDING EVENT', now(), now() + interval '7 days', 'active', public.spending_ton_rate_fc());
INSERT INTO public.spending_event_ticker(event_id)
SELECT id FROM public.spending_events WHERE status = 'active';
