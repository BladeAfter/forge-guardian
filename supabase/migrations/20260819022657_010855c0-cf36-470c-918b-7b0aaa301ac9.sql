CREATE OR REPLACE FUNCTION public.get_spending_event_dashboard(p_telegram_id bigint, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  ev public.spending_events; v_uid uuid; v_ranking jsonb; v_rewards jsonb;
  v_me public.spending_event_scores; v_pos integer; v_next_points numeric;
  v_ticker public.spending_event_ticker; v_next jsonb; v_breakdown jsonb;
BEGIN
  SELECT * INTO ev FROM public.active_spending_event();
  IF ev.id IS NULL THEN
    SELECT * INTO ev FROM spending_events WHERE status IN ('scheduled','finished')
      ORDER BY (status = 'scheduled') DESC, starts_at DESC LIMIT 1;
  END IF;
  SELECT id INTO v_uid FROM game_players WHERE telegram_id = p_telegram_id;

  IF ev.id IS NULL THEN
    RETURN jsonb_build_object('event', NULL, 'ranking', '[]'::jsonb, 'rewards', '[]'::jsonb,
      'breakdown', '[]'::jsonb,
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

  SELECT COALESCE(jsonb_agg(jsonb_build_object('group', g, 'points', pts, 'entries', cnt)
           ORDER BY pts DESC), '[]'::jsonb) INTO v_breakdown
    FROM (
      SELECT public.spending_source_group(e.source_type) AS g,
             SUM(e.spending_points) AS pts, COUNT(*) AS cnt
        FROM spending_event_entries e
       WHERE e.event_id = ev.id AND e.user_id = v_uid
       GROUP BY 1 HAVING SUM(e.spending_points) > 0
    ) q;

  IF v_pos IS NOT NULL AND v_pos > 1 AND v_next_points IS NOT NULL THEN
    v_next := jsonb_build_object('rank', v_pos - 1, 'needed', GREATEST(0, v_next_points - COALESCE(v_me.total_points,0) + 1));
  END IF;

  RETURN jsonb_build_object(
    'event', jsonb_build_object('id', ev.id, 'name', ev.name, 'startsAt', ev.starts_at, 'endsAt', ev.ends_at,
      'status', ev.status, 'tonRateFc', public.spending_currency_rate('TON'), 'topLimit', ev.top_limit,
      'fcRate', public.spending_currency_rate('FC')),
    'totals', jsonb_build_object('points', COALESCE(v_ticker.total_points,0), 'fcSpent', COALESCE(v_ticker.total_fc,0),
      'tonSpent', COALESCE(v_ticker.total_ton,0), 'participants', COALESCE(v_ticker.participants,0)),
    'player', jsonb_build_object('points', COALESCE(v_me.total_points,0), 'fcSpent', COALESCE(v_me.fc_spent,0),
      'tonSpent', COALESCE(v_me.ton_spent,0), 'position', v_pos,
      'estimatedReward', CASE WHEN v_pos IS NULL THEN NULL ELSE public.spending_event_reward_label(ev.id, v_pos) END,
      'nextRank', v_next -> 'rank', 'neededToNext', v_next -> 'needed'),
    'ranking', v_ranking,
    'rewards', v_rewards,
    'breakdown', v_breakdown,
    'serverTime', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF'));
END $$;

REVOKE EXECUTE ON FUNCTION public.get_spending_event_dashboard(bigint, integer) FROM anon, authenticated;