-- Leader / co-leader roster selection for Clan War (20v20).
CREATE OR REPLACE FUNCTION public.clan_war_roster_candidates(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cfg jsonb; v_uid uuid; v_clan uuid; v_role text; w public.clan_wars;
BEGIN
  cfg := public.clan_war_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF NOT COALESCE(public.clan_role_rank(v_role) >= public.clan_role_rank('co-leader'), false) THEN
    RAISE EXCEPTION 'CLAN_WAR_NOT_ALLOWED';
  END IF;

  w := public.clan_war_active(v_clan);

  RETURN jsonb_build_object(
    'rosterSize', GREATEST(1, COALESCE((cfg->>'rosterSize')::int, 20)),
    'warId', w.id,
    'status', w.status,
    'editable', COALESCE(w.status IN ('searching','preparation'), false),
    'selected', COALESCE((SELECT jsonb_agg(r.user_id) FROM public.clan_war_rosters r WHERE r.war_id = w.id AND r.clan_id = v_clan), '[]'::jsonb),
    'members', COALESCE((
      SELECT jsonb_agg(x ORDER BY (x->>'power')::bigint DESC) FROM (
        SELECT jsonb_build_object(
          'userId', m.user_id,
          'name', COALESCE(g.display_name, g.name, g.username, 'Player'),
          'avatarUrl', g.avatar_url,
          'role', m.role,
          'power', GREATEST(0, COALESCE(public.clan_player_power(m.user_id), 0))::bigint,
          'inRoster', EXISTS (SELECT 1 FROM public.clan_war_rosters r WHERE r.war_id = w.id AND r.user_id = m.user_id),
          'locked', EXISTS (
            SELECT 1 FROM public.clan_war_rosters r
             WHERE r.war_id = w.id AND r.user_id = m.user_id
               AND (r.attacks_used > 0 OR r.points_earned > 0 OR r.defeats_taken > 0))
        ) AS x
          FROM public.clan_members m
          LEFT JOIN public.game_players g ON g.id = m.user_id
         WHERE m.clan_id = v_clan
      ) q
    ), '[]'::jsonb)
  );
END; $$;

CREATE OR REPLACE FUNCTION public.clan_war_set_roster(p_telegram_id bigint, p_user_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cfg jsonb; v_uid uuid; v_clan uuid; v_role text; w public.clan_wars;
        v_size int; v_attacks int; v_ids uuid[]; r record; v_idx int := 0; v_sec text;
BEGIN
  cfg := public.clan_war_cfg();
  v_size := GREATEST(1, COALESCE((cfg->>'rosterSize')::int, 20));
  v_attacks := GREATEST(1, COALESCE((cfg->>'attacksPerPlayer')::int, 3));
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF NOT COALESCE(public.clan_role_rank(v_role) >= public.clan_role_rank('co-leader'), false) THEN
    RAISE EXCEPTION 'CLAN_WAR_NOT_ALLOWED';
  END IF;

  w := public.clan_war_active(v_clan);
  IF w.id IS NULL THEN RAISE EXCEPTION 'CLAN_WAR_NOT_ACTIVE'; END IF;
  IF w.status NOT IN ('searching','preparation') THEN RAISE EXCEPTION 'CLAN_WAR_ROSTER_LOCKED'; END IF;

  -- only real clan members, deduplicated, plus every member already locked by activity
  SELECT COALESCE(array_agg(DISTINCT u), '{}'::uuid[]) INTO v_ids
    FROM unnest(COALESCE(p_user_ids, '{}'::uuid[])) u
   WHERE EXISTS (SELECT 1 FROM public.clan_members m WHERE m.clan_id = v_clan AND m.user_id = u);

  SELECT COALESCE(array_agg(DISTINCT u), '{}'::uuid[]) INTO v_ids FROM (
    SELECT unnest(v_ids) AS u
    UNION
    SELECT r.user_id FROM public.clan_war_rosters r
     WHERE r.war_id = w.id AND r.clan_id = v_clan
       AND (r.attacks_used > 0 OR r.points_earned > 0 OR r.defeats_taken > 0)
  ) q;

  IF array_length(v_ids, 1) IS NULL OR array_length(v_ids, 1) = 0 THEN RAISE EXCEPTION 'CLAN_WAR_ROSTER_EMPTY'; END IF;
  IF array_length(v_ids, 1) > v_size THEN RAISE EXCEPTION 'CLAN_WAR_ROSTER_TOO_LARGE'; END IF;

  -- drop members no longer selected (defenses go with them)
  DELETE FROM public.clan_war_defenses d
   WHERE d.war_id = w.id AND d.user_id IN (
     SELECT r.user_id FROM public.clan_war_rosters r
      WHERE r.war_id = w.id AND r.clan_id = v_clan AND NOT (r.user_id = ANY(v_ids)));

  DELETE FROM public.clan_war_rosters r
   WHERE r.war_id = w.id AND r.clan_id = v_clan AND NOT (r.user_id = ANY(v_ids));

  -- insert / refresh selected members, distributing them across fortress sectors by power
  FOR r IN
    SELECT u AS user_id, GREATEST(0, COALESCE(public.clan_player_power(u), 0)) AS power
      FROM unnest(v_ids) u
     ORDER BY 2 DESC
  LOOP
    SELECT s->>'code' INTO v_sec FROM (
      SELECT s, sum((s->>'slots')::int) OVER (ORDER BY (s->>'order')::int, s->>'code') AS acc
        FROM jsonb_array_elements(public.clan_war_sector_def()) s
    ) q WHERE q.acc > v_idx ORDER BY q.acc LIMIT 1;
    v_sec := COALESCE(v_sec, 'OUTER_GATE');

    INSERT INTO public.clan_war_rosters(war_id, clan_id, user_id, sector, team_power_snapshot, attacks_total)
    VALUES (w.id, v_clan, r.user_id, v_sec, r.power::bigint, v_attacks)
    ON CONFLICT (war_id, user_id) DO UPDATE
      SET sector = EXCLUDED.sector,
          team_power_snapshot = EXCLUDED.team_power_snapshot;
    v_idx := v_idx + 1;
  END LOOP;

  INSERT INTO public.clan_war_sector_state(war_id, clan_id, sector)
  SELECT w.id, v_clan, s->>'code' FROM jsonb_array_elements(public.clan_war_sector_def()) s
  ON CONFLICT (war_id, clan_id, sector) DO NOTHING;

  RETURN jsonb_build_object('status', 'ok', 'selected', array_length(v_ids, 1), 'rosterSize', v_size);
END; $$;

REVOKE ALL ON FUNCTION public.clan_war_roster_candidates(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_war_set_roster(bigint, uuid[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_war_roster_candidates(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_war_set_roster(bigint, uuid[]) TO service_role;