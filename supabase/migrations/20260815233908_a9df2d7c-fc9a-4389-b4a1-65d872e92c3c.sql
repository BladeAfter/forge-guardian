-- 1. Official player power: same formula used everywhere else in the game (atk*2 + hp).
CREATE OR REPLACE FUNCTION public.clan_player_power(p_user_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(SUM(final_atk * 2 + final_hp), 0) FROM public.player_heroes WHERE user_id = p_user_id
$$;

-- 2. Configurable online threshold (minutes).
INSERT INTO public.game_settings(key, value)
VALUES ('clan_online_minutes', '5'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.clan_online_minutes()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(1, COALESCE((SELECT value::text::int FROM public.game_settings WHERE key = 'clan_online_minutes'), 5))
$$;

-- 3. Server-controlled activity touch (throttled to once per minute, timestamp always now()).
CREATE OR REPLACE FUNCTION public.touch_player_activity(p_telegram_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.game_players
     SET last_seen_at = now()
   WHERE telegram_id = p_telegram_id
     AND (last_seen_at IS NULL OR last_seen_at < now() - interval '60 seconds');
END; $$;

REVOKE ALL ON FUNCTION public.touch_player_activity(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.touch_player_activity(bigint) TO service_role;

CREATE INDEX IF NOT EXISTS clan_join_requests_pending_idx
  ON public.clan_join_requests(clan_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS game_players_last_seen_idx ON public.game_players(last_seen_at);

-- 4. Dashboard: aggregated member/request management data in a single query.
CREATE OR REPLACE FUNCTION public.get_clan_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; c public.clans%rowtype; v_role text; v_week date;
        v_manage boolean; v_online int; v_members jsonb; v_stats jsonb; v_season uuid;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN
    RETURN jsonb_build_object(
      'inClan', false,
      'createCostFc', COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000),
      'balance', COALESCE((SELECT forge_coins FROM public.game_players WHERE id = v_uid), 0),
      'recommended', COALESCE((SELECT jsonb_agg(public.clan_public(x) ORDER BY x.level DESC)
        FROM (SELECT * FROM public.clans WHERE NOT suspended ORDER BY level DESC, xp DESC LIMIT 20) x), '[]'::jsonb)
    );
  END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;
  v_week := public.clan_week_key();
  v_online := public.clan_online_minutes();
  -- Officers and above (rank >= 2) manage members, exactly like accept/reject already requires.
  v_manage := public.clan_role_rank(v_role) >= 2;
  SELECT id INTO v_season FROM public.season_pass_seasons WHERE active AND now() BETWEEN start_at AND end_at LIMIT 1;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'userId', m.user_id, 'role', m.role, 'contribution', m.contribution, 'clanPoints', m.clan_points,
      'name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
      'username', g.username, 'avatar', g.avatar_url,
      'trophies', g.pvp_trophies, 'league', public.pvp_league(g.pvp_trophies),
      'power', h.power::bigint, 'heroes', h.heroes, 'accountLevel', h.account_level,
      'lastActive', g.last_seen_at,
      'online', g.last_seen_at IS NOT NULL AND g.last_seen_at > now() - make_interval(mins => v_online),
      'joinedAt', m.joined_at, 'isMe', m.user_id = v_uid)
      ORDER BY public.clan_role_rank(m.role) DESC, m.contribution DESC), '[]'::jsonb)
    INTO v_members
   FROM public.clan_members m
   JOIN public.game_players g ON g.id = m.user_id
   LEFT JOIN LATERAL (
     SELECT COALESCE(SUM(ph.final_atk * 2 + ph.final_hp), 0) AS power,
            COUNT(*)::int AS heroes,
            GREATEST(1, COALESCE(MAX(ph.level), 1)) AS account_level
       FROM public.player_heroes ph WHERE ph.user_id = m.user_id) h ON true
   WHERE m.clan_id = v_clan;

  SELECT jsonb_build_object(
      'members', count(*)::int,
      'memberLimit', c.member_limit,
      'onlineNow', count(*) FILTER (WHERE g.last_seen_at > now() - make_interval(mins => v_online))::int,
      'active24h', count(*) FILTER (WHERE g.last_seen_at > now() - interval '24 hours')::int,
      'inactive3d', count(*) FILTER (WHERE g.last_seen_at IS NULL OR g.last_seen_at < now() - interval '3 days')::int,
      'inactive7d', count(*) FILTER (WHERE g.last_seen_at IS NULL OR g.last_seen_at < now() - interval '7 days')::int,
      'inactive14d', count(*) FILTER (WHERE g.last_seen_at IS NULL OR g.last_seen_at < now() - interval '14 days')::int,
      'pendingRequests', COALESCE((SELECT count(*) FROM public.clan_join_requests r
        WHERE r.clan_id = v_clan AND r.status = 'pending'), 0)::int)
    INTO v_stats
   FROM public.clan_members m JOIN public.game_players g ON g.id = m.user_id WHERE m.clan_id = v_clan;

  RETURN jsonb_build_object(
    'inClan', true,
    'role', v_role,
    'canManageMembers', v_manage,
    'onlineThresholdMinutes', v_online,
    'clan', public.clan_public(c),
    'stats', v_stats,
    'me', (SELECT jsonb_build_object('contribution', contribution, 'clanPoints', clan_points, 'role', role) FROM public.clan_members WHERE user_id = v_uid),
    'members', v_members,
    -- Join requests only reach members with manage permission; gameplay data only, no private fields.
    'requests', CASE WHEN NOT v_manage THEN '[]'::jsonb ELSE COALESCE((
        SELECT jsonb_agg(jsonb_build_object('id', r.id, 'userId', r.user_id,
          'name', COALESCE(g.display_name, g.first_name, g.username,'Player'),
          'username', g.username, 'avatar', g.avatar_url,
          'trophies', g.pvp_trophies, 'league', public.pvp_league(g.pvp_trophies),
          'power', h.power::bigint, 'heroes', h.heroes, 'accountLevel', h.account_level,
          'lastActive', g.last_seen_at,
          'online', g.last_seen_at IS NOT NULL AND g.last_seen_at > now() - make_interval(mins => v_online),
          'createdAt', r.created_at) ORDER BY r.created_at)
          FROM public.clan_join_requests r
          JOIN public.game_players g ON g.id = r.user_id
          LEFT JOIN LATERAL (
            SELECT COALESCE(SUM(ph.final_atk * 2 + ph.final_hp), 0) AS power,
                   COUNT(*)::int AS heroes,
                   GREATEST(1, COALESCE(MAX(ph.level), 1)) AS account_level
              FROM public.player_heroes ph WHERE ph.user_id = r.user_id) h ON true
         WHERE r.clan_id = v_clan AND r.status = 'pending'), '[]'::jsonb) END,
    'missions', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', m.code, 'title', m.title, 'target', m.target,
        'rewardPoints', m.reward_points,
        'progress', COALESCE((SELECT p.progress FROM public.clan_mission_progress p WHERE p.clan_id=v_clan AND p.mission_code=m.code AND p.week_key=v_week),0),
        'completed', COALESCE((SELECT p.completed FROM public.clan_mission_progress p WHERE p.clan_id=v_clan AND p.mission_code=m.code AND p.week_key=v_week),false)))
      FROM public.clan_missions m WHERE m.active), '[]'::jsonb),
    'boss', (SELECT jsonb_build_object('id', b.id, 'name', b.name, 'maxHealth', b.max_health, 'currentHealth', b.current_health,
        'status', b.status, 'endsAt', b.ends_at, 'rewardPoints', b.reward_points,
        'myDamage', COALESCE((SELECT damage FROM public.clan_boss_participants WHERE cycle_id=b.id AND user_id=v_uid),0),
        'top', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', COALESCE(g.display_name,g.first_name,'Player'),'avatar',g.avatar_url,'damage',p.damage) ORDER BY p.damage DESC)
          FROM public.clan_boss_participants p JOIN public.game_players g ON g.id=p.user_id WHERE p.cycle_id=b.id),'[]'::jsonb))
      FROM public.clan_boss_cycles b WHERE b.clan_id=v_clan AND b.status='active' ORDER BY b.started_at DESC LIMIT 1),
    'ranking', COALESCE((SELECT jsonb_agg(public.clan_public(x)) FROM (SELECT * FROM public.clans WHERE NOT suspended ORDER BY level DESC, xp DESC LIMIT 20) x), '[]'::jsonb)
  );
END; $$;

-- 5. Atomic accept: lock clan + request row, re-validate pending state, clan membership and capacity.
CREATE OR REPLACE FUNCTION public.clan_manage(p_telegram_id bigint, p_action text, p_target uuid DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_role text; v_trole text; v_count integer; c public.clans%rowtype; v_req uuid;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;

  IF p_action = 'edit' THEN
    IF public.clan_role_rank(v_role) < 3 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clans SET
      description = COALESCE(NULLIF(btrim(p_payload->>'description'),''), description),
      join_type = COALESCE(NULLIF(p_payload->>'joinType',''), join_type),
      minimum_trophies = COALESCE((p_payload->>'minimumTrophies')::int, minimum_trophies),
      emblem_config = COALESCE(p_payload->'emblem', emblem_config),
      updated_at = now()
     WHERE id = v_clan;
    RETURN jsonb_build_object('status','updated');
  END IF;

  IF p_target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  SELECT role INTO v_trole FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;

  IF p_action IN ('accept','reject') THEN
    IF public.clan_role_rank(v_role) < 2 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    -- Serialize concurrent leaders/officers on the same clan.
    PERFORM 1 FROM public.clans WHERE id = v_clan FOR UPDATE;
    SELECT id INTO v_req FROM public.clan_join_requests
      WHERE clan_id = v_clan AND user_id = p_target AND status = 'pending' FOR UPDATE;
    IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
    IF p_action = 'reject' THEN
      UPDATE public.clan_join_requests SET status='rejected' WHERE id = v_req;
      RETURN jsonb_build_object('status','rejected');
    END IF;
    SELECT count(*) INTO v_count FROM public.clan_members WHERE clan_id = v_clan;
    IF v_count >= c.member_limit THEN RAISE EXCEPTION 'CLAN_FULL'; END IF;
    IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = p_target) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
    INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (v_clan, p_target, 'member');
    UPDATE public.clan_join_requests SET status='accepted' WHERE id = v_req;
    RETURN jsonb_build_object('status','accepted');
  END IF;

  IF v_trole IS NULL THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;

  IF p_action = 'kick' THEN
    IF public.clan_role_rank(v_role) < 3 OR public.clan_role_rank(v_trole) >= public.clan_role_rank(v_role) THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    DELETE FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','kicked');
  ELSIF p_action IN ('promote','demote') THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    IF v_trole = 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role = CASE
        WHEN p_action='promote' THEN CASE v_trole WHEN 'member' THEN 'officer' WHEN 'officer' THEN 'co-leader' ELSE 'co-leader' END
        ELSE CASE v_trole WHEN 'co-leader' THEN 'officer' WHEN 'officer' THEN 'member' ELSE 'member' END END,
      updated_at = now()
     WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','role_changed');
  ELSIF p_action = 'transfer' THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role='leader' WHERE user_id = p_target AND clan_id = v_clan;
    UPDATE public.clan_members SET role='co-leader' WHERE user_id = v_uid AND clan_id = v_clan;
    UPDATE public.clans SET leader_user_id = p_target, updated_at = now() WHERE id = v_clan;
    RETURN jsonb_build_object('status','transferred');
  END IF;
  RAISE EXCEPTION 'INVALID_ACTION';
END; $$;

REVOKE ALL ON FUNCTION public.clan_player_power(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_online_minutes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_clan_dashboard(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_manage(bigint, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_player_power(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_online_minutes() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_clan_dashboard(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_manage(bigint, text, uuid, jsonb) TO service_role;