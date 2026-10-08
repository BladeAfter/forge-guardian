-- ============================================================ special events (independent from the weekly community pool)
CREATE TABLE IF NOT EXISTS public.special_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  name text NOT NULL,
  type text NOT NULL DEFAULT 'referral_ranking',
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('scheduled','active','finished','cancelled')),
  prize_pool_ton numeric NOT NULL DEFAULT 0 CHECK (prize_pool_ton >= 0),
  rules_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.special_events TO anon, authenticated;
GRANT ALL ON public.special_events TO service_role;
ALTER TABLE public.special_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "special events are public" ON public.special_events;
CREATE POLICY "special events are public" ON public.special_events FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.event_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.special_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  final_rank integer NOT NULL,
  valid_referrals integer NOT NULL DEFAULT 0,
  reward_ton numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed','skipped')),
  paid_at timestamptz,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, user_id)
);
GRANT ALL ON public.event_results TO service_role;
ALTER TABLE public.event_results ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_special_events_status ON public.special_events(status, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_results_event ON public.event_results(event_id, final_rank);

CREATE OR REPLACE FUNCTION public.special_events_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS trg_special_events_touch ON public.special_events;
CREATE TRIGGER trg_special_events_touch BEFORE UPDATE ON public.special_events
FOR EACH ROW EXECUTE FUNCTION public.special_events_touch();
DROP TRIGGER IF EXISTS trg_event_results_touch ON public.event_results;
CREATE TRIGGER trg_event_results_touch BEFORE UPDATE ON public.event_results
FOR EACH ROW EXECUTE FUNCTION public.special_events_touch();

-- ============================================================ default rules
CREATE OR REPLACE FUNCTION public.event_default_rules()
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT jsonb_build_object(
    'minDailyQuests', 1,
    'requireOnboarding', true,
    'topLimit', 100,
    'distributionMode', 'fixed',
    'distribution', jsonb_build_array(
      jsonb_build_object('from',1,'to',1,'ton',25),
      jsonb_build_object('from',2,'to',2,'ton',15),
      jsonb_build_object('from',3,'to',3,'ton',10),
      jsonb_build_object('from',4,'to',10,'totalTon',20),
      jsonb_build_object('from',11,'to',50,'totalTon',20),
      jsonb_build_object('from',51,'to',100,'totalTon',10)
    )
  );
$$;

-- ============================================================ ranking built from real referrals (anti-fraud filters)
CREATE OR REPLACE FUNCTION public.event_referral_ranking(p_event_id uuid, p_limit integer DEFAULT 100)
RETURNS TABLE (user_id uuid, name text, username text, avatar_url text, valid_referrals bigint, rank_no bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.special_events%rowtype; v_min_quests integer;
BEGIN
  SELECT * INTO e FROM public.special_events WHERE id = p_event_id;
  IF e.id IS NULL THEN RETURN; END IF;
  v_min_quests := GREATEST(0, COALESCE((e.rules_json->>'minDailyQuests')::int, 1));

  RETURN QUERY
  WITH valid AS (
    SELECT r.inviter_id AS uid
    FROM public.referrals r
    JOIN public.game_players invited ON invited.id = r.user_id
    JOIN public.game_players inviter ON inviter.id = r.inviter_id
    WHERE r.level = 1
      AND r.created_at >= e.starts_at
      AND r.created_at <= LEAST(e.ends_at, now())
      AND r.inviter_id <> r.user_id
      AND invited.telegram_id IS NOT NULL
      AND inviter.telegram_id IS NOT NULL
      AND invited.telegram_id <> inviter.telegram_id
      AND COALESCE(invited.banned, false) = false
      AND COALESCE(inviter.banned, false) = false
      AND (
        v_min_quests = 0 OR (
          SELECT count(*) FROM public.player_quest_progress q
          WHERE q.user_id = invited.id AND q.completed_at IS NOT NULL
        ) >= v_min_quests
      )
  ), agg AS (
    SELECT uid, count(*)::bigint AS total FROM valid GROUP BY uid
  )
  SELECT a.uid,
         COALESCE(NULLIF(g.display_name,''), NULLIF(g.first_name,''), NULLIF(g.username,''), 'Warrior')::text,
         g.username, g.avatar_url, a.total,
         ROW_NUMBER() OVER (ORDER BY a.total DESC, g.created_at ASC, a.uid)
  FROM agg a JOIN public.game_players g ON g.id = a.uid
  ORDER BY a.total DESC, g.created_at ASC, a.uid
  LIMIT GREATEST(1, COALESCE(p_limit, 100));
END; $$;
REVOKE ALL ON FUNCTION public.event_referral_ranking(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.event_referral_ranking(uuid, integer) TO service_role;

-- ============================================================ prize per position (fixed ranking or proportional)
CREATE OR REPLACE FUNCTION public.event_reward_for_rank(p_rules jsonb, p_prize numeric, p_rank integer, p_valid bigint, p_total_valid bigint)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE mode text; d jsonb; el jsonb; f integer; t integer; per numeric;
BEGIN
  IF p_rank IS NULL OR p_rank < 1 OR COALESCE(p_prize,0) <= 0 THEN RETURN 0; END IF;
  mode := COALESCE(p_rules->>'distributionMode','fixed');
  IF mode = 'proportional' THEN
    IF COALESCE(p_total_valid,0) <= 0 THEN RETURN 0; END IF;
    RETURN round(p_prize * COALESCE(p_valid,0)::numeric / p_total_valid::numeric, 4);
  END IF;
  d := COALESCE(p_rules->'distribution', public.event_default_rules()->'distribution');
  FOR el IN SELECT value FROM jsonb_array_elements(d) LOOP
    f := COALESCE((el->>'from')::int, 0);
    t := COALESCE((el->>'to')::int, f);
    IF p_rank BETWEEN f AND t THEN
      IF el ? 'ton' THEN per := COALESCE((el->>'ton')::numeric, 0);
      ELSE per := COALESCE((el->>'totalTon')::numeric, 0) / GREATEST(1, (t - f + 1)); END IF;
      RETURN round(per, 4);
    END IF;
  END LOOP;
  RETURN 0;
END; $$;
REVOKE ALL ON FUNCTION public.event_reward_for_rank(jsonb, numeric, integer, bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.event_reward_for_rank(jsonb, numeric, integer, bigint, bigint) TO service_role;

-- ============================================================ keeps statuses in sync with the real clock
CREATE OR REPLACE FUNCTION public.event_sync_statuses()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.special_events SET status='active' WHERE status='scheduled' AND starts_at <= now() AND ends_at > now();
  UPDATE public.special_events SET status='finished' WHERE status='active' AND ends_at <= now();
END; $$;
REVOKE ALL ON FUNCTION public.event_sync_statuses() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.event_sync_statuses() TO service_role;

-- ============================================================ player-facing dashboard (called by the game edge function)
CREATE OR REPLACE FUNCTION public.get_special_events_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; e public.special_events%rowtype; nx public.special_events%rowtype;
        v_total_valid bigint := 0; v_participants integer := 0; v_ranking jsonb := '[]'::jsonb;
        v_player jsonb := NULL; v_rank bigint; v_valid bigint := 0; v_lifetime integer := 0;
BEGIN
  PERFORM public.event_sync_statuses();
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT * INTO e FROM public.special_events WHERE status='active' ORDER BY starts_at DESC LIMIT 1;
  SELECT * INTO nx FROM public.special_events WHERE status='scheduled' ORDER BY starts_at ASC LIMIT 1;

  IF v_user IS NOT NULL THEN
    SELECT count(*)::int INTO v_lifetime FROM public.referrals WHERE inviter_id = v_user AND level = 1;
  END IF;

  IF e.id IS NULL THEN
    RETURN jsonb_build_object(
      'event', NULL,
      'nextEvent', CASE WHEN nx.id IS NULL THEN NULL ELSE jsonb_build_object(
        'name', nx.name, 'startsAt', nx.starts_at, 'endsAt', nx.ends_at, 'prizePoolTon', nx.prize_pool_ton, 'type', nx.type) END,
      'ranking', '[]'::jsonb, 'participantCount', 0,
      'player', jsonb_build_object('validReferrals',0,'position',NULL,'estimatedRewardTon',0,'lifetimeReferrals',v_lifetime),
      'serverTime', now()
    );
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS tmp_event_rank (
    user_id uuid, name text, username text, avatar_url text, valid_referrals bigint, position bigint
  ) ON COMMIT DROP;
  DELETE FROM tmp_event_rank;
  INSERT INTO tmp_event_rank
  SELECT * FROM public.event_referral_ranking(e.id, 100000);

  SELECT COALESCE(sum(valid_referrals),0), count(*)::int INTO v_total_valid, v_participants FROM tmp_event_rank;

  SELECT jsonb_agg(jsonb_build_object(
      'position', r.position,
      'userId', r.user_id,
      'name', r.name,
      'username', r.username,
      'avatarUrl', r.avatar_url,
      'validReferrals', r.valid_referrals,
      'estimatedRewardTon', public.event_reward_for_rank(e.rules_json, e.prize_pool_ton, r.position::int, r.valid_referrals, v_total_valid),
      'isYou', (v_user IS NOT NULL AND r.user_id = v_user)
    ) ORDER BY r.position)
  INTO v_ranking
  FROM tmp_event_rank r
  WHERE r.position <= GREATEST(1, COALESCE((e.rules_json->>'topLimit')::int, 100));

  IF v_user IS NOT NULL THEN
    SELECT position, valid_referrals INTO v_rank, v_valid FROM tmp_event_rank WHERE user_id = v_user;
  END IF;

  v_player := jsonb_build_object(
    'validReferrals', COALESCE(v_valid,0),
    'position', v_rank,
    'estimatedRewardTon', public.event_reward_for_rank(e.rules_json, e.prize_pool_ton, v_rank::int, COALESCE(v_valid,0), v_total_valid),
    'lifetimeReferrals', v_lifetime
  );

  RETURN jsonb_build_object(
    'event', jsonb_build_object(
      'id', e.id, 'eventKey', e.event_key, 'name', e.name, 'type', e.type,
      'startsAt', e.starts_at, 'endsAt', e.ends_at, 'status', e.status,
      'prizePoolTon', e.prize_pool_ton,
      'distributionMode', COALESCE(e.rules_json->>'distributionMode','fixed'),
      'minDailyQuests', COALESCE((e.rules_json->>'minDailyQuests')::int, 1),
      'topLimit', COALESCE((e.rules_json->>'topLimit')::int, 100),
      'distribution', COALESCE(e.rules_json->'distribution', public.event_default_rules()->'distribution')
    ),
    'nextEvent', CASE WHEN nx.id IS NULL THEN NULL ELSE jsonb_build_object(
      'name', nx.name, 'startsAt', nx.starts_at, 'endsAt', nx.ends_at, 'prizePoolTon', nx.prize_pool_ton, 'type', nx.type) END,
    'ranking', COALESCE(v_ranking,'[]'::jsonb),
    'participantCount', v_participants,
    'totalValidReferrals', v_total_valid,
    'player', v_player,
    'serverTime', now()
  );
END; $$;
REVOKE ALL ON FUNCTION public.get_special_events_dashboard(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_special_events_dashboard(bigint) TO service_role;

-- ============================================================ freeze final ranking
CREATE OR REPLACE FUNCTION public.event_finalize(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.special_events%rowtype; v_total bigint := 0; v_rows integer := 0; v_sum numeric := 0;
BEGIN
  SELECT * INTO e FROM public.special_events WHERE id = p_event_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(e.id::text, 42));

  CREATE TEMP TABLE IF NOT EXISTS tmp_event_final (
    user_id uuid, name text, username text, avatar_url text, valid_referrals bigint, position bigint
  ) ON COMMIT DROP;
  DELETE FROM tmp_event_final;
  INSERT INTO tmp_event_final SELECT * FROM public.event_referral_ranking(e.id, 100000);
  SELECT COALESCE(sum(valid_referrals),0) INTO v_total FROM tmp_event_final;

  INSERT INTO public.event_results (event_id, user_id, final_rank, valid_referrals, reward_ton, status)
  SELECT e.id, r.user_id, r.position::int, r.valid_referrals::int,
         public.event_reward_for_rank(e.rules_json, e.prize_pool_ton, r.position::int, r.valid_referrals, v_total),
         'pending'
  FROM tmp_event_final r
  WHERE r.position <= GREATEST(1, COALESCE((e.rules_json->>'topLimit')::int, 100))
  ON CONFLICT (event_id, user_id) DO UPDATE
    SET final_rank = EXCLUDED.final_rank,
        valid_referrals = EXCLUDED.valid_referrals,
        reward_ton = CASE WHEN public.event_results.status = 'paid' THEN public.event_results.reward_ton ELSE EXCLUDED.reward_ton END;

  UPDATE public.special_events SET status='finished', ends_at = LEAST(ends_at, now()) WHERE id = e.id;
  SELECT count(*)::int, COALESCE(sum(reward_ton),0) INTO v_rows, v_sum FROM public.event_results WHERE event_id = e.id;
  RETURN jsonb_build_object('eventId', e.id, 'name', e.name, 'winners', v_rows, 'totalRewardTon', v_sum, 'totalValidReferrals', v_total);
END; $$;
REVOKE ALL ON FUNCTION public.event_finalize(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.event_finalize(uuid) TO service_role;

-- ============================================================ pay the frozen ranking (idempotent per row)
CREATE OR REPLACE FUNCTION public.event_distribute(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.special_events%rowtype; r record; v_before numeric; v_after numeric; v_paid integer := 0; v_sum numeric := 0;
BEGIN
  SELECT * INTO e FROM public.special_events WHERE id = p_event_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(e.id::text, 43));

  FOR r IN SELECT * FROM public.event_results WHERE event_id = e.id AND status = 'pending' AND reward_ton > 0 ORDER BY final_rank LOOP
    SELECT COALESCE(ton_balance,0) INTO v_before FROM public.game_players WHERE id = r.user_id FOR UPDATE;
    IF v_before IS NULL THEN
      UPDATE public.event_results SET status='failed', note='player_not_found' WHERE id = r.id;
      CONTINUE;
    END IF;
    v_after := v_before + r.reward_ton;
    UPDATE public.game_players SET ton_balance = v_after, updated_at = now() WHERE id = r.user_id;
    INSERT INTO public.wallet_ledger (user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
    VALUES (r.user_id, 'event_reward', 0, r.reward_ton, v_before, v_after, 'event:' || e.event_key || ':#' || r.final_rank);
    UPDATE public.event_results SET status='paid', paid_at=now() WHERE id = r.id;
    v_paid := v_paid + 1; v_sum := v_sum + r.reward_ton;
  END LOOP;

  RETURN jsonb_build_object('eventId', e.id, 'paid', v_paid, 'totalTon', v_sum,
    'pending', (SELECT count(*) FROM public.event_results WHERE event_id=e.id AND status='pending'),
    'failed', (SELECT count(*) FROM public.event_results WHERE event_id=e.id AND status='failed'));
END; $$;
REVOKE ALL ON FUNCTION public.event_distribute(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.event_distribute(uuid) TO service_role;

-- ============================================================ admin bot module
CREATE OR REPLACE FUNCTION public.admin_events(p_admin_id bigint, p_action text, p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.special_events%rowtype; v_id uuid; v_res jsonb; v_key text; v_days numeric; v_start timestamptz; v_rules jsonb; v_total bigint;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM public.event_sync_statuses();
  p_payload := COALESCE(p_payload, '{}'::jsonb);

  IF p_ref IS NOT NULL AND p_ref <> '' THEN
    SELECT * INTO e FROM public.special_events WHERE id::text = p_ref OR event_key = p_ref;
  ELSE
    SELECT * INTO e FROM public.special_events WHERE status='active' ORDER BY starts_at DESC LIMIT 1;
    IF e.id IS NULL THEN SELECT * INTO e FROM public.special_events ORDER BY created_at DESC LIMIT 1; END IF;
  END IF;

  IF p_action = 'list' THEN
    RETURN jsonb_build_object('events', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',s.id,'eventKey',s.event_key,'name',s.name,'type',s.type,'status',s.status,
      'startsAt',s.starts_at,'endsAt',s.ends_at,'prizePoolTon',s.prize_pool_ton) ORDER BY s.created_at DESC)
      FROM public.special_events s), '[]'::jsonb));
  END IF;

  IF p_action = 'create' THEN
    v_days := GREATEST(1, COALESCE((p_payload->>'days')::numeric, 30));
    v_start := COALESCE((p_payload->>'startsAt')::timestamptz, now());
    v_key := COALESCE(NULLIF(p_payload->>'eventKey',''),
      regexp_replace(lower(COALESCE(NULLIF(p_payload->>'name',''),'special_event')), '[^a-z0-9]+', '_', 'g') || '_' || to_char(v_start,'YYYY_MM_DD_HH24MI'));
    INSERT INTO public.special_events (event_key, name, type, starts_at, ends_at, status, prize_pool_ton, rules_json)
    VALUES (v_key,
      COALESCE(NULLIF(p_payload->>'name',''), 'Special Event'),
      COALESCE(NULLIF(p_payload->>'type',''), 'referral_ranking'),
      v_start,
      v_start + make_interval(mins => (v_days * 1440)::int),
      CASE WHEN v_start > now() THEN 'scheduled' ELSE 'active' END,
      GREATEST(0, COALESCE((p_payload->>'prizeTon')::numeric, 0)),
      public.event_default_rules() || COALESCE(p_payload->'rules','{}'::jsonb))
    RETURNING * INTO e;
    PERFORM public.admin_log(p_admin_id, 'event_create', 'special_event', e.id::text, NULL, to_jsonb(e), 'admin bot');
  ELSIF p_action = 'set_prize' THEN
    IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
    UPDATE public.special_events SET prize_pool_ton = GREATEST(0, COALESCE((p_payload->>'value')::numeric, prize_pool_ton))
    WHERE id = e.id RETURNING * INTO e;
    PERFORM public.admin_log(p_admin_id, 'event_set_prize', 'special_event', e.id::text, NULL, jsonb_build_object('prizePoolTon', e.prize_pool_ton), 'admin bot');
  ELSIF p_action = 'set_dates' THEN
    IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
    v_start := COALESCE((p_payload->>'startsAt')::timestamptz, e.starts_at);
    UPDATE public.special_events SET starts_at = v_start,
      ends_at = COALESCE((p_payload->>'endsAt')::timestamptz,
        v_start + make_interval(mins => (GREATEST(1, COALESCE((p_payload->>'days')::numeric, 30)) * 1440)::int)),
      status = CASE WHEN status IN ('finished','cancelled') THEN status
                    WHEN v_start > now() THEN 'scheduled' ELSE 'active' END
    WHERE id = e.id RETURNING * INTO e;
    PERFORM public.admin_log(p_admin_id, 'event_set_dates', 'special_event', e.id::text, NULL, jsonb_build_object('startsAt',e.starts_at,'endsAt',e.ends_at), 'admin bot');
  ELSIF p_action = 'set_rules' THEN
    IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
    v_rules := COALESCE(p_payload->'rules', '{}'::jsonb);
    UPDATE public.special_events SET rules_json = rules_json || v_rules WHERE id = e.id RETURNING * INTO e;
    PERFORM public.admin_log(p_admin_id, 'event_set_rules', 'special_event', e.id::text, NULL, e.rules_json, 'admin bot');
  ELSIF p_action = 'finish' THEN
    IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
    v_res := public.event_finalize(e.id);
    SELECT * INTO e FROM public.special_events WHERE id = e.id;
    PERFORM public.admin_log(p_admin_id, 'event_finish', 'special_event', e.id::text, NULL, v_res, 'admin bot');
  ELSIF p_action = 'distribute' THEN
    IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
    IF e.status <> 'finished' THEN v_res := public.event_finalize(e.id); END IF;
    v_res := public.event_distribute(e.id);
    SELECT * INTO e FROM public.special_events WHERE id = e.id;
    PERFORM public.admin_log(p_admin_id, 'event_distribute', 'special_event', e.id::text, NULL, v_res, 'admin bot');
  ELSIF p_action = 'cancel' THEN
    IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
    UPDATE public.special_events SET status='cancelled' WHERE id = e.id RETURNING * INTO e;
    PERFORM public.admin_log(p_admin_id, 'event_cancel', 'special_event', e.id::text, NULL, NULL, 'admin bot');
  END IF;

  IF e.id IS NULL THEN
    RETURN jsonb_build_object('event', NULL, 'ranking', '[]'::jsonb, 'result', v_res);
  END IF;

  SELECT COALESCE(sum(valid_referrals),0) INTO v_total FROM public.event_referral_ranking(e.id, 100000);

  RETURN jsonb_build_object(
    'event', jsonb_build_object('id',e.id,'eventKey',e.event_key,'name',e.name,'type',e.type,'status',e.status,
      'startsAt',e.starts_at,'endsAt',e.ends_at,'prizePoolTon',e.prize_pool_ton,'rules',e.rules_json),
    'totalValidReferrals', v_total,
    'participantCount', (SELECT count(*) FROM public.event_referral_ranking(e.id, 100000)),
    'ranking', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'position', r.position, 'name', r.name, 'username', r.username, 'validReferrals', r.valid_referrals,
        'rewardTon', public.event_reward_for_rank(e.rules_json, e.prize_pool_ton, r.position::int, r.valid_referrals, v_total)
      ) ORDER BY r.position) FROM public.event_referral_ranking(e.id, GREATEST(1, COALESCE((p_payload->>'limit')::int, 20))) r), '[]'::jsonb),
    'results', COALESCE((SELECT jsonb_agg(jsonb_build_object('rank',x.final_rank,'rewardTon',x.reward_ton,'status',x.status) ORDER BY x.final_rank)
      FROM (SELECT * FROM public.event_results WHERE event_id = e.id ORDER BY final_rank LIMIT 20) x), '[]'::jsonb),
    'payoutSummary', (SELECT jsonb_build_object(
        'rows', count(*), 'pending', count(*) FILTER (WHERE status='pending'), 'paid', count(*) FILTER (WHERE status='paid'),
        'failed', count(*) FILTER (WHERE status='failed'), 'paidTon', COALESCE(sum(reward_ton) FILTER (WHERE status='paid'),0))
      FROM public.event_results WHERE event_id = e.id),
    'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('action',l.action,'at',l.created_at,'value',l.new_value) ORDER BY l.created_at DESC)
      FROM (SELECT * FROM public.admin_audit_logs WHERE target_type='special_event' ORDER BY created_at DESC LIMIT 10) l), '[]'::jsonb),
    'result', v_res
  );
END; $$;
REVOKE ALL ON FUNCTION public.admin_events(bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_events(bigint, text, text, jsonb) TO service_role;

-- ============================================================ first event: Referral Championship (100 TON, 30 days)
INSERT INTO public.special_events (event_key, name, type, starts_at, ends_at, status, prize_pool_ton, rules_json)
VALUES ('referral_championship_2026_08', 'Referral Championship', 'referral_ranking',
  '2026-08-11 00:00:00+00', '2026-09-10 00:00:00+00', 'active', 100, public.event_default_rules())
ON CONFLICT (event_key) DO NOTHING;