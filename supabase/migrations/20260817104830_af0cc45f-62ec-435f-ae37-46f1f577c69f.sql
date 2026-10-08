-- =========================================================
-- CLAN WAR — lifecycle, defenses, attacks, settlement
-- =========================================================

CREATE OR REPLACE FUNCTION public.clan_war_member_role(p_user uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT role FROM public.clan_members WHERE user_id = p_user LIMIT 1;
$fn$;

-- Current war (queue / preparation / battle) for a clan.
CREATE OR REPLACE FUNCTION public.clan_war_active(p_clan uuid)
RETURNS public.clan_wars LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT * FROM public.clan_wars
   WHERE status IN ('searching','preparation','battle')
     AND (clan_a = p_clan OR clan_b = p_clan)
   ORDER BY created_at DESC LIMIT 1;
$fn$;

-- 3v3 attack team of a player (first 3 slots of the PvP attack team).
CREATE OR REPLACE FUNCTION public.clan_war_attack_team(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT COALESCE(jsonb_agg(public.pvp_hero_json(h) ORDER BY s.slot), '[]'::jsonb)
    FROM public.pvp_team_slots s
    JOIN public.player_heroes h ON h.id = s.hero_id AND h.user_id = p_user
   WHERE s.user_id = p_user AND s.team_type = 'attack' AND s.slot <= 3;
$fn$;

-- Fills the roster of a clan with its strongest members and prepares sectors.
CREATE OR REPLACE FUNCTION public.clan_war_fill_roster(p_war uuid, p_clan uuid, p_size int, p_attacks int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE r record; v_sector jsonb; v_idx int := 0; v_sec text;
BEGIN
  FOR r IN
    SELECT m.user_id, public.clan_player_power(m.user_id) AS power
      FROM public.clan_members m
     WHERE m.clan_id = p_clan
     ORDER BY power DESC
     LIMIT GREATEST(1, p_size)
  LOOP
    v_sec := 'OUTER_GATE';
    FOR v_sector IN SELECT * FROM jsonb_array_elements(public.clan_war_sector_def()) LOOP
      NULL;
    END LOOP;
    -- distribute members across sectors respecting the slot count of each one
    SELECT s->>'code' INTO v_sec FROM (
      SELECT s, sum((s->>'slots')::int) OVER (ORDER BY (s->>'order')::int, s->>'code') AS acc
        FROM jsonb_array_elements(public.clan_war_sector_def()) s
    ) q WHERE q.acc > v_idx ORDER BY q.acc LIMIT 1;
    v_sec := COALESCE(v_sec, 'OUTER_GATE');

    INSERT INTO public.clan_war_rosters(war_id, clan_id, user_id, sector, team_power_snapshot, attacks_total)
    VALUES (p_war, p_clan, r.user_id, v_sec, GREATEST(0, r.power)::bigint, GREATEST(1, p_attacks))
    ON CONFLICT (war_id, user_id) DO NOTHING;
    v_idx := v_idx + 1;
  END LOOP;

  INSERT INTO public.clan_war_sector_state(war_id, clan_id, sector)
  SELECT p_war, p_clan, s->>'code' FROM jsonb_array_elements(public.clan_war_sector_def()) s
  ON CONFLICT (war_id, clan_id, sector) DO NOTHING;
END; $fn$;

-- Leader / co-leader puts the clan in the war queue (or matches instantly).
CREATE OR REPLACE FUNCTION public.clan_war_join(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE cfg jsonb; v_uid uuid; v_clan uuid; v_role text; w public.clan_wars; o public.clan_wars;
        v_members int; v_rating int; v_season uuid;
BEGIN
  cfg := public.clan_war_cfg();
  IF NOT (cfg->>'enabled')::boolean THEN RAISE EXCEPTION 'CLAN_WAR_DISABLED'; END IF;
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF public.clan_role_rank(v_role) < public.clan_role_rank('co-leader') THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('clanwar:queue', 0));
  w := public.clan_war_active(v_clan);
  IF w.id IS NOT NULL THEN RAISE EXCEPTION 'CLAN_WAR_ALREADY_ACTIVE'; END IF;

  SELECT count(*) INTO v_members FROM public.clan_members WHERE clan_id = v_clan;
  IF v_members < 3 THEN RAISE EXCEPTION 'CLAN_WAR_NOT_ENOUGH_MEMBERS'; END IF;

  SELECT war_rating INTO v_rating FROM public.clans WHERE id = v_clan;
  v_season := (public.clan_war_current_season()).id;

  -- try to match an already queued clan with the closest rating
  SELECT * INTO o FROM public.clan_wars
   WHERE status = 'searching' AND clan_b IS NULL AND clan_a <> v_clan
   ORDER BY abs(COALESCE((SELECT war_rating FROM public.clans c WHERE c.id = clan_a), 1000) - COALESCE(v_rating,1000)) ASC,
            created_at ASC
   LIMIT 1 FOR UPDATE SKIP LOCKED;

  IF o.id IS NOT NULL THEN
    UPDATE public.clan_wars
       SET clan_b = v_clan, status = 'preparation', season_id = v_season,
           preparation_starts_at = now(),
           battle_starts_at = now() + make_interval(hours => GREATEST(1,(cfg->>'preparationHours')::int)),
           battle_ends_at = now() + make_interval(hours => GREATEST(1,(cfg->>'preparationHours')::int) + GREATEST(1,(cfg->>'battleHours')::int)),
           starts_at = now(),
           ends_at = now() + make_interval(hours => GREATEST(1,(cfg->>'preparationHours')::int) + GREATEST(1,(cfg->>'battleHours')::int)),
           roster_size = (cfg->>'rosterSize')::int,
           attacks_per_player = (cfg->>'attacksPerPlayer')::int
     WHERE id = o.id RETURNING * INTO w;
    PERFORM public.clan_war_fill_roster(w.id, w.clan_a, w.roster_size, w.attacks_per_player);
    PERFORM public.clan_war_fill_roster(w.id, w.clan_b, w.roster_size, w.attacks_per_player);
    RETURN jsonb_build_object('status','matched','warId', w.id);
  END IF;

  INSERT INTO public.clan_wars(clan_a, status, season_id, registered_by, roster_size, attacks_per_player, starts_at)
  VALUES (v_clan, 'searching', v_season, v_uid, (cfg->>'rosterSize')::int, (cfg->>'attacksPerPlayer')::int, now())
  RETURNING * INTO w;
  RETURN jsonb_build_object('status','searching','warId', w.id);
END; $fn$;

-- Leaves the queue (only while still searching).
CREATE OR REPLACE FUNCTION public.clan_war_leave_queue(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_uid uuid; v_clan uuid; v_role text; w public.clan_wars;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF public.clan_role_rank(v_role) < public.clan_role_rank('co-leader') THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
  w := public.clan_war_active(v_clan);
  IF w.id IS NULL OR w.status <> 'searching' THEN RAISE EXCEPTION 'CLAN_WAR_NOT_SEARCHING'; END IF;
  DELETE FROM public.clan_wars WHERE id = w.id;
  RETURN jsonb_build_object('status','ok');
END; $fn$;

-- Saves the 3-hero defense team during the preparation phase.
CREATE OR REPLACE FUNCTION public.clan_war_set_defense(p_telegram_id bigint, p_hero_ids uuid[], p_pet_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_uid uuid; v_clan uuid; w public.clan_wars; v_team jsonb; v_power bigint; v_count int;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  w := public.clan_war_active(v_clan);
  IF w.id IS NULL THEN RAISE EXCEPTION 'CLAN_WAR_NOT_ACTIVE'; END IF;
  IF w.status <> 'preparation' THEN RAISE EXCEPTION 'CLAN_WAR_DEFENSE_LOCKED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.clan_war_rosters WHERE war_id = w.id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'CLAN_WAR_NOT_IN_ROSTER';
  END IF;

  SELECT count(DISTINCT x) INTO v_count FROM unnest(COALESCE(p_hero_ids,'{}')) x;
  IF v_count <> 3 OR array_length(p_hero_ids,1) <> 3 THEN RAISE EXCEPTION 'CLAN_WAR_INVALID_TEAM'; END IF;
  IF (SELECT count(*) FROM public.player_heroes WHERE user_id = v_uid AND id = ANY(p_hero_ids)) <> 3 THEN
    RAISE EXCEPTION 'CLAN_WAR_INVALID_TEAM';
  END IF;
  IF p_pet_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.player_pets WHERE id = p_pet_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'CLAN_WAR_INVALID_PET';
  END IF;

  SELECT COALESCE(jsonb_agg(public.pvp_hero_json(h)), '[]'::jsonb) INTO v_team
    FROM public.player_heroes h WHERE h.user_id = v_uid AND h.id = ANY(p_hero_ids);
  SELECT COALESCE(sum((x->>'power')::numeric),0)::bigint INTO v_power FROM jsonb_array_elements(v_team) x;

  INSERT INTO public.clan_war_defenses(war_id, clan_id, user_id, hero_ids, pet_id, power, team_json, pet_buffs, updated_at)
  VALUES (w.id, v_clan, v_uid, p_hero_ids, p_pet_id, v_power, v_team, COALESCE(public.get_pet_bonuses(v_uid),'{}'::jsonb), now())
  ON CONFLICT (war_id, user_id) DO UPDATE
    SET hero_ids = EXCLUDED.hero_ids, pet_id = EXCLUDED.pet_id, power = EXCLUDED.power,
        team_json = EXCLUDED.team_json, pet_buffs = EXCLUDED.pet_buffs, updated_at = now();

  UPDATE public.clan_war_rosters SET team_power_snapshot = v_power WHERE war_id = w.id AND user_id = v_uid;
  RETURN jsonb_build_object('status','ok','power', v_power);
END; $fn$;

-- Attacks an enemy defender inside the fortress.
CREATE OR REPLACE FUNCTION public.clan_war_attack(p_telegram_id bigint, p_defender uuid, p_client_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE cfg jsonb; v_uid uuid; v_clan uuid; w public.clan_wars; me public.clan_war_rosters; foe public.clan_war_rosters;
        d public.clan_war_defenses; v_enemy uuid; v_attack jsonb; v_battle jsonb; v_win boolean; v_points int := 0;
        v_perfect boolean := false; v_upset int := 0; v_sector jsonb; v_ready boolean; v_req text; v_state public.clan_war_sector_state;
        v_atk_power bigint; v_conquered boolean := false; v_defeats int; v_alive int; v_existing jsonb;
BEGIN
  cfg := public.clan_war_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  w := public.clan_war_active(v_clan);
  IF w.id IS NULL THEN RAISE EXCEPTION 'CLAN_WAR_NOT_ACTIVE'; END IF;
  IF w.status <> 'battle' THEN RAISE EXCEPTION 'CLAN_WAR_NOT_IN_BATTLE'; END IF;
  v_enemy := CASE WHEN w.clan_a = v_clan THEN w.clan_b ELSE w.clan_a END;

  PERFORM pg_advisory_xact_lock(hashtextextended('clanwar:'||w.id::text, 0));

  IF p_client_key IS NOT NULL THEN
    SELECT battle INTO v_existing FROM public.clan_war_attacks
     WHERE war_id = w.id AND attacker_user = v_uid AND client_key = p_client_key;
    IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  END IF;

  SELECT * INTO me FROM public.clan_war_rosters WHERE war_id = w.id AND user_id = v_uid FOR UPDATE;
  IF me.id IS NULL THEN RAISE EXCEPTION 'CLAN_WAR_NOT_IN_ROSTER'; END IF;
  IF me.attacks_used >= me.attacks_total THEN RAISE EXCEPTION 'CLAN_WAR_NO_ATTACKS'; END IF;

  SELECT * INTO foe FROM public.clan_war_rosters WHERE war_id = w.id AND user_id = p_defender AND clan_id = v_enemy FOR UPDATE;
  IF foe.id IS NULL THEN RAISE EXCEPTION 'CLAN_WAR_INVALID_TARGET'; END IF;

  -- sector must be unlocked (its required sectors already conquered)
  SELECT s INTO v_sector FROM jsonb_array_elements(public.clan_war_sector_def()) s WHERE s->>'code' = foe.sector;
  v_ready := true;
  FOR v_req IN SELECT jsonb_array_elements_text(COALESCE(v_sector->'requires','[]'::jsonb)) LOOP
    IF NOT EXISTS (SELECT 1 FROM public.clan_war_sector_state
                    WHERE war_id = w.id AND clan_id = v_enemy AND sector = v_req AND conquered_at IS NOT NULL) THEN
      v_ready := false;
    END IF;
  END LOOP;
  IF NOT v_ready THEN RAISE EXCEPTION 'CLAN_WAR_SECTOR_LOCKED'; END IF;

  SELECT * INTO d FROM public.clan_war_defenses WHERE war_id = w.id AND user_id = p_defender;
  v_attack := public.clan_war_attack_team(v_uid);
  IF jsonb_array_length(v_attack) < 1 THEN RAISE EXCEPTION 'CLAN_WAR_NO_ATTACK_TEAM'; END IF;

  v_battle := public.simulate_pvp_battle(v_attack, COALESCE(d.team_json,'[]'::jsonb), w.id::text||v_uid::text||p_defender::text||me.attacks_used::text);
  v_win := COALESCE(d.team_json,'[]'::jsonb) = '[]'::jsonb OR (v_battle->>'winnerSide') = 'attacker';

  SELECT count(*) INTO v_alive FROM jsonb_array_elements(COALESCE(v_battle->'attackerState','[]'::jsonb)) x WHERE (x->>'currentHp')::numeric > 0;
  v_perfect := v_win AND v_alive >= jsonb_array_length(v_attack);

  SELECT COALESCE(sum((x->>'power')::numeric),0)::bigint INTO v_atk_power FROM jsonb_array_elements(v_attack) x;

  IF v_win THEN
    v_points := (cfg->>'pointsWin')::int;
    IF v_perfect THEN v_points := v_points + (cfg->>'pointsPerfect')::int; END IF;
    IF COALESCE(d.power,0) > v_atk_power AND v_atk_power > 0 THEN
      v_upset := LEAST((cfg->>'pointsUpsetMax')::int,
                       round(((d.power::numeric / v_atk_power) - 1) * 100)::int);
      v_points := v_points + GREATEST(0, v_upset);
    END IF;
    IF foe.defeats_taken >= (cfg->>'defenderMaxDefeats')::int THEN
      v_points := GREATEST(1, round(v_points * (cfg->>'conqueredPercent')::numeric / 100.0)::int);
    END IF;
  ELSE
    v_points := (cfg->>'pointsLoss')::int;
  END IF;

  UPDATE public.clan_war_rosters
     SET attacks_used = attacks_used + 1,
         points_earned = points_earned + v_points,
         wins = wins + CASE WHEN v_win THEN 1 ELSE 0 END,
         losses = losses + CASE WHEN v_win THEN 0 ELSE 1 END
   WHERE id = me.id;

  IF v_win THEN
    UPDATE public.clan_war_rosters SET defeats_taken = defeats_taken + 1 WHERE id = foe.id
      RETURNING defeats_taken INTO v_defeats;

    SELECT * INTO v_state FROM public.clan_war_sector_state
      WHERE war_id = w.id AND clan_id = v_enemy AND sector = foe.sector FOR UPDATE;
    IF v_state.id IS NOT NULL AND v_state.conquered_at IS NULL THEN
      UPDATE public.clan_war_sector_state SET defeats = defeats + 1 WHERE id = v_state.id;
      IF (SELECT count(*) FROM public.clan_war_rosters r
           WHERE r.war_id = w.id AND r.clan_id = v_enemy AND r.sector = foe.sector
             AND r.defeats_taken >= (cfg->>'defenderMaxDefeats')::int)
         >= COALESCE((v_sector->>'required')::int, 3) THEN
        UPDATE public.clan_war_sector_state SET conquered_at = now() WHERE id = v_state.id;
        v_conquered := true;
      END IF;
    END IF;
  END IF;

  IF v_conquered THEN
    v_points := v_points + round(v_points * (cfg->>'sectorBonusPercent')::numeric / 100.0)::int;
  END IF;

  IF w.clan_a = v_clan THEN
    UPDATE public.clan_wars SET score_a = score_a + v_points WHERE id = w.id;
  ELSE
    UPDATE public.clan_wars SET score_b = score_b + v_points WHERE id = w.id;
  END IF;

  INSERT INTO public.clan_war_attacks(war_id, attacker_user, attacker_clan, defender_user, defender_clan, sector,
                                      result, points, perfect, upset_bonus, attacker_power, defender_power, battle, client_key)
  VALUES (w.id, v_uid, v_clan, p_defender, v_enemy, foe.sector,
          CASE WHEN v_win THEN 'win' ELSE 'loss' END, v_points, v_perfect, v_upset, v_atk_power, COALESCE(d.power,0),
          jsonb_build_object('status','ok','win',v_win,'points',v_points,'perfect',v_perfect,'sectorConquered',v_conquered,
                             'battleLog', COALESCE(v_battle->'battleLog','[]'::jsonb),
                             'attackerState', COALESCE(v_battle->'attackerState','[]'::jsonb),
                             'defenderState', COALESCE(v_battle->'defenderState','[]'::jsonb)),
          p_client_key);

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_war_attack', 1);

  RETURN jsonb_build_object('status','ok','win',v_win,'points',v_points,'perfect',v_perfect,'sectorConquered',v_conquered,
                            'battleLog', COALESCE(v_battle->'battleLog','[]'::jsonb),
                            'attackerState', COALESCE(v_battle->'attackerState','[]'::jsonb),
                            'defenderState', COALESCE(v_battle->'defenderState','[]'::jsonb));
END; $fn$;

-- Settles a finished war: winner, rating, clan stats and per-player rewards.
CREATE OR REPLACE FUNCTION public.clan_war_settle(p_war uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE w public.clan_wars; v_winner uuid; v_loser uuid; ra int; rb int; ea numeric; delta int; r record;
        v_league text; v_mult numeric; v_fc bigint; v_points int;
BEGIN
  SELECT * INTO w FROM public.clan_wars WHERE id = p_war FOR UPDATE;
  IF w.id IS NULL OR w.settled_at IS NOT NULL THEN RETURN; END IF;

  IF w.score_a > w.score_b THEN v_winner := w.clan_a; v_loser := w.clan_b;
  ELSIF w.score_b > w.score_a THEN v_winner := w.clan_b; v_loser := w.clan_a; END IF;

  SELECT war_rating INTO ra FROM public.clans WHERE id = w.clan_a;
  SELECT war_rating INTO rb FROM public.clans WHERE id = w.clan_b;
  ra := COALESCE(ra,1000); rb := COALESCE(rb,1000);
  ea := 1.0 / (1.0 + power(10, (rb - ra)::numeric / 400.0));
  delta := round(40 * (CASE WHEN v_winner IS NULL THEN 0.5 WHEN v_winner = w.clan_a THEN 1 ELSE 0 END - ea))::int;

  UPDATE public.clans SET war_rating = GREATEST(0, war_rating + delta),
      war_wins = war_wins + CASE WHEN v_winner = id THEN 1 ELSE 0 END,
      war_losses = war_losses + CASE WHEN v_loser = id THEN 1 ELSE 0 END,
      war_draws = war_draws + CASE WHEN v_winner IS NULL THEN 1 ELSE 0 END,
      war_points_total = war_points_total + w.score_a
    WHERE id = w.clan_a;
  UPDATE public.clans SET war_rating = GREATEST(0, war_rating - delta),
      war_wins = war_wins + CASE WHEN v_winner = id THEN 1 ELSE 0 END,
      war_losses = war_losses + CASE WHEN v_loser = id THEN 1 ELSE 0 END,
      war_draws = war_draws + CASE WHEN v_winner IS NULL THEN 1 ELSE 0 END,
      war_points_total = war_points_total + w.score_b
    WHERE id = w.clan_b;

  INSERT INTO public.clan_war_rating_history(clan_id, war_id, season_id, rating_before, rating_after, delta, result)
  VALUES (w.clan_a, w.id, w.season_id, ra, GREATEST(0, ra + delta), delta,
          CASE WHEN v_winner IS NULL THEN 'draw' WHEN v_winner = w.clan_a THEN 'win' ELSE 'loss' END),
         (w.clan_b, w.id, w.season_id, rb, GREATEST(0, rb - delta), -delta,
          CASE WHEN v_winner IS NULL THEN 'draw' WHEN v_winner = w.clan_b THEN 'win' ELSE 'loss' END)
  ON CONFLICT (war_id, clan_id) DO NOTHING;

  FOR r IN SELECT * FROM public.clan_war_rosters WHERE war_id = w.id LOOP
    SELECT public.clan_war_league(war_rating) INTO v_league FROM public.clans WHERE id = r.clan_id;
    v_mult := public.clan_war_league_multiplier(v_league);
    v_points := r.points_earned;
    v_fc := GREATEST(0, round((v_points * 25 + CASE WHEN r.clan_id = v_winner THEN 5000 ELSE 1500 END) * v_mult))::bigint;
    IF v_fc > 0 THEN
      UPDATE public.game_players SET forge_coins = forge_coins + v_fc WHERE id = r.user_id;
    END IF;
    INSERT INTO public.clan_war_rewards(war_id, clan_id, user_id, result, payload)
    VALUES (w.id, r.clan_id, r.user_id,
            CASE WHEN v_winner IS NULL THEN 'draw' WHEN r.clan_id = v_winner THEN 'win' ELSE 'loss' END,
            jsonb_build_object('fc', v_fc, 'points', v_points, 'league', v_league))
    ON CONFLICT (war_id, user_id) DO NOTHING;
  END LOOP;

  UPDATE public.clan_wars
     SET status = 'finished', winner_clan_id = v_winner, finished_at = now(), settled_at = now(), ends_at = COALESCE(ends_at, now())
   WHERE id = w.id;
END; $fn$;

-- Scheduled tick: preparation -> battle -> finished.
CREATE OR REPLACE FUNCTION public.clan_war_tick()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE w record; v_started int := 0; v_finished int := 0;
BEGIN
  FOR w IN SELECT * FROM public.clan_wars WHERE status = 'preparation' AND battle_starts_at <= now() LOOP
    UPDATE public.clan_war_defenses SET locked_at = now() WHERE war_id = w.id AND locked_at IS NULL;
    UPDATE public.clan_wars SET status = 'battle' WHERE id = w.id;
    v_started := v_started + 1;
  END LOOP;

  FOR w IN SELECT * FROM public.clan_wars WHERE status = 'battle' AND battle_ends_at <= now() LOOP
    PERFORM public.clan_war_settle(w.id);
    v_finished := v_finished + 1;
  END LOOP;

  RETURN jsonb_build_object('started', v_started, 'finished', v_finished);
END; $fn$;

-- Everything the app needs for the Clan War tab.
CREATE OR REPLACE FUNCTION public.clan_war_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE cfg jsonb; v_uid uuid; v_clan uuid; v_role text; w public.clan_wars; v_enemy uuid; me public.clan_war_rosters;
        v_result jsonb; v_last public.clan_wars;
BEGIN
  cfg := public.clan_war_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;

  v_result := jsonb_build_object(
    'config', cfg,
    'inClan', v_clan IS NOT NULL,
    'role', v_role,
    'canManage', COALESCE(public.clan_role_rank(v_role) >= public.clan_role_rank('co-leader'), false),
    'season', (SELECT to_jsonb(s) FROM public.clan_war_seasons s WHERE s.status='active' ORDER BY s.starts_at DESC LIMIT 1),
    'war', NULL,
    'ranking', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'clanId', c.id, 'name', c.name, 'tag', c.tag, 'emblem', c.emblem,
        'rating', c.war_rating, 'league', public.clan_war_league(c.war_rating),
        'wins', c.war_wins, 'losses', c.war_losses, 'points', c.war_points_total) ORDER BY c.war_rating DESC), '[]'::jsonb)
      FROM (SELECT * FROM public.clans ORDER BY war_rating DESC LIMIT 50) c)
  );

  IF v_clan IS NULL THEN RETURN v_result; END IF;
  w := public.clan_war_active(v_clan);
  IF w.id IS NULL THEN
    SELECT * INTO v_last FROM public.clan_wars
      WHERE status='finished' AND (clan_a=v_clan OR clan_b=v_clan) ORDER BY finished_at DESC LIMIT 1;
    IF v_last.id IS NOT NULL THEN
      v_result := v_result || jsonb_build_object('lastWar', jsonb_build_object(
        'warId', v_last.id,
        'scoreYou', CASE WHEN v_last.clan_a=v_clan THEN v_last.score_a ELSE v_last.score_b END,
        'scoreEnemy', CASE WHEN v_last.clan_a=v_clan THEN v_last.score_b ELSE v_last.score_a END,
        'result', CASE WHEN v_last.winner_clan_id IS NULL THEN 'draw' WHEN v_last.winner_clan_id=v_clan THEN 'win' ELSE 'loss' END,
        'reward', (SELECT payload FROM public.clan_war_rewards WHERE war_id=v_last.id AND user_id=v_uid)));
    END IF;
    RETURN v_result;
  END IF;

  v_enemy := CASE WHEN w.clan_a = v_clan THEN w.clan_b ELSE w.clan_a END;
  SELECT * INTO me FROM public.clan_war_rosters WHERE war_id = w.id AND user_id = v_uid;

  RETURN v_result || jsonb_build_object('war', jsonb_build_object(
    'warId', w.id,
    'status', w.status,
    'preparationEndsAt', w.battle_starts_at,
    'battleEndsAt', w.battle_ends_at,
    'scoreYou', CASE WHEN w.clan_a=v_clan THEN w.score_a ELSE w.score_b END,
    'scoreEnemy', CASE WHEN w.clan_a=v_clan THEN w.score_b ELSE w.score_a END,
    'yourClan', (SELECT jsonb_build_object('id',c.id,'name',c.name,'tag',c.tag,'emblem',c.emblem,'rating',c.war_rating,
                        'league', public.clan_war_league(c.war_rating)) FROM public.clans c WHERE c.id=v_clan),
    'enemyClan', (SELECT jsonb_build_object('id',c.id,'name',c.name,'tag',c.tag,'emblem',c.emblem,'rating',c.war_rating,
                        'league', public.clan_war_league(c.war_rating)) FROM public.clans c WHERE c.id=v_enemy),
    'me', CASE WHEN me.id IS NULL THEN NULL ELSE jsonb_build_object(
            'inRoster', true, 'sector', me.sector, 'attacksLeft', GREATEST(0, me.attacks_total - me.attacks_used),
            'attacksTotal', me.attacks_total, 'points', me.points_earned, 'wins', me.wins, 'losses', me.losses,
            'defense', (SELECT jsonb_build_object('heroIds', d.hero_ids, 'petId', d.pet_id, 'power', d.power, 'team', d.team_json)
                          FROM public.clan_war_defenses d WHERE d.war_id=w.id AND d.user_id=v_uid)) END,
    'attackTeam', public.clan_war_attack_team(v_uid),
    'sectors', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'code', s->>'code', 'order', (s->>'order')::int, 'bonus', s->'bonus',
        'required', (s->>'required')::int, 'requires', s->'requires',
        'conquered', EXISTS (SELECT 1 FROM public.clan_war_sector_state st
                              WHERE st.war_id=w.id AND st.clan_id=v_enemy AND st.sector=s->>'code' AND st.conquered_at IS NOT NULL),
        'defenders', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'userId', r.user_id, 'name', COALESCE(g.display_name, g.name, g.username, 'Player'),
            'avatarUrl', g.avatar_url, 'power', COALESCE(dd.power, r.team_power_snapshot),
            'defeats', r.defeats_taken,
            'beaten', r.defeats_taken >= (cfg->>'defenderMaxDefeats')::int
          ) ORDER BY COALESCE(dd.power, r.team_power_snapshot) DESC), '[]'::jsonb)
          FROM public.clan_war_rosters r
          JOIN public.game_players g ON g.id = r.user_id
          LEFT JOIN public.clan_war_defenses dd ON dd.war_id = w.id AND dd.user_id = r.user_id
          WHERE r.war_id = w.id AND r.clan_id = v_enemy AND r.sector = s->>'code')
      ) ORDER BY (s->>'order')::int, s->>'code'), '[]'::jsonb)
      FROM jsonb_array_elements(public.clan_war_sector_def()) s),
    'roster', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'userId', r.user_id, 'name', COALESCE(g.display_name, g.name, g.username, 'Player'), 'avatarUrl', g.avatar_url,
        'sector', r.sector, 'points', r.points_earned, 'attacksLeft', GREATEST(0, r.attacks_total - r.attacks_used),
        'wins', r.wins, 'losses', r.losses, 'defeatsTaken', r.defeats_taken,
        'defenseSet', EXISTS (SELECT 1 FROM public.clan_war_defenses d WHERE d.war_id=w.id AND d.user_id=r.user_id),
        'isMe', r.user_id = v_uid) ORDER BY r.points_earned DESC), '[]'::jsonb)
      FROM public.clan_war_rosters r JOIN public.game_players g ON g.id = r.user_id
      WHERE r.war_id = w.id AND r.clan_id = v_clan),
    'feed', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', a.id, 'sector', a.sector, 'result', a.result, 'points', a.points, 'perfect', a.perfect,
        'attacker', COALESCE(ga.display_name, ga.name, ga.username, 'Player'),
        'defender', COALESCE(gd.display_name, gd.name, gd.username, 'Player'),
        'mine', a.attacker_clan = v_clan, 'createdAt', a.created_at) ORDER BY a.created_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM public.clan_war_attacks WHERE war_id = w.id ORDER BY created_at DESC LIMIT 30) a
      JOIN public.game_players ga ON ga.id = a.attacker_user
      JOIN public.game_players gd ON gd.id = a.defender_user)
  ));
END; $fn$;

DO $do$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'clan_war_member_role(uuid)','clan_war_active(uuid)','clan_war_attack_team(uuid)',
    'clan_war_fill_roster(uuid,uuid,int,int)','clan_war_join(bigint)','clan_war_leave_queue(bigint)',
    'clan_war_set_defense(bigint,uuid[],uuid)','clan_war_attack(bigint,uuid,text)','clan_war_settle(uuid)',
    'clan_war_tick()','clan_war_dashboard(bigint)','clan_war_cfg()','clan_war_sector_def()',
    'clan_war_league(integer)','clan_war_league_multiplier(text)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role', fn);
  END LOOP;
END $do$;

SELECT cron.schedule('clan-war-tick', '*/5 * * * *', $cron$SELECT public.clan_war_tick();$cron$)
WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'clan-war-tick');