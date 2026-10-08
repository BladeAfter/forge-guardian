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
      'ranking', '[]'::jsonb, 'participantCount', 0, 'totalValidReferrals', 0,
      'player', jsonb_build_object('validReferrals',0,'position',NULL,'estimatedRewardTon',0,'lifetimeReferrals',v_lifetime),
      'serverTime', now()
    );
  END IF;

  SELECT COALESCE(sum(r.valid_referrals),0), count(*)::int
    INTO v_total_valid, v_participants
  FROM public.event_referral_ranking(e.id, 1000000) r;

  SELECT jsonb_agg(jsonb_build_object(
      'position', r.rank_no,
      'userId', r.user_id,
      'name', r.name,
      'username', r.username,
      'avatarUrl', r.avatar_url,
      'validReferrals', r.valid_referrals,
      'estimatedRewardTon', public.event_reward_for_rank(e.rules_json, e.prize_pool_ton, r.rank_no::int, r.valid_referrals, v_total_valid),
      'isYou', (v_user IS NOT NULL AND r.user_id = v_user)
    ) ORDER BY r.rank_no)
  INTO v_ranking
  FROM public.event_referral_ranking(e.id, GREATEST(1, COALESCE((e.rules_json->>'topLimit')::int, 100))) r;

  IF v_user IS NOT NULL THEN
    SELECT r.rank_no, r.valid_referrals INTO v_rank, v_valid
    FROM public.event_referral_ranking(e.id, 1000000) r WHERE r.user_id = v_user;
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

CREATE OR REPLACE FUNCTION public.event_finalize(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.special_events%rowtype; v_total bigint := 0; v_rows integer := 0; v_sum numeric := 0;
BEGIN
  SELECT * INTO e FROM public.special_events WHERE id = p_event_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(e.id::text, 42));

  SELECT COALESCE(sum(r.valid_referrals),0) INTO v_total FROM public.event_referral_ranking(e.id, 1000000) r;

  INSERT INTO public.event_results (event_id, user_id, final_rank, valid_referrals, reward_ton, status)
  SELECT e.id, r.user_id, r.rank_no::int, r.valid_referrals::int,
         public.event_reward_for_rank(e.rules_json, e.prize_pool_ton, r.rank_no::int, r.valid_referrals, v_total),
         'pending'
  FROM public.event_referral_ranking(e.id, GREATEST(1, COALESCE((e.rules_json->>'topLimit')::int, 100))) r
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

CREATE OR REPLACE FUNCTION public.admin_events(p_admin_id bigint, p_action text, p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.special_events%rowtype; v_res jsonb; v_key text; v_days numeric; v_start timestamptz; v_rules jsonb; v_total bigint;
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
      status = CASE WHEN status = 'cancelled' THEN status
                    WHEN v_start > now() THEN 'scheduled'
                    WHEN COALESCE((p_payload->>'endsAt')::timestamptz,
                         v_start + make_interval(mins => (GREATEST(1, COALESCE((p_payload->>'days')::numeric, 30)) * 1440)::int)) > now() THEN 'active'
                    ELSE 'finished' END
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
    IF e.status <> 'finished' THEN PERFORM public.event_finalize(e.id); END IF;
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

  SELECT COALESCE(sum(r.valid_referrals),0) INTO v_total FROM public.event_referral_ranking(e.id, 1000000) r;

  RETURN jsonb_build_object(
    'event', jsonb_build_object('id',e.id,'eventKey',e.event_key,'name',e.name,'type',e.type,'status',e.status,
      'startsAt',e.starts_at,'endsAt',e.ends_at,'prizePoolTon',e.prize_pool_ton,'rules',e.rules_json),
    'totalValidReferrals', v_total,
    'participantCount', (SELECT count(*) FROM public.event_referral_ranking(e.id, 1000000)),
    'ranking', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'position', r.rank_no, 'name', r.name, 'username', r.username, 'validReferrals', r.valid_referrals,
        'rewardTon', public.event_reward_for_rank(e.rules_json, e.prize_pool_ton, r.rank_no::int, r.valid_referrals, v_total)
      ) ORDER BY r.rank_no) FROM public.event_referral_ranking(e.id, GREATEST(1, COALESCE((p_payload->>'limit')::int, 20))) r), '[]'::jsonb),
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