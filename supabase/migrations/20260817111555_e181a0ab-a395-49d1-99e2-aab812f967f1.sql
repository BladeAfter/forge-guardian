-- Admin surface for CLAN WAR. Everything is driven by game_settings keys already
-- consumed by clan_war_cfg(), so changes are live with no deploy.
CREATE OR REPLACE FUNCTION public.admin_clan_war_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v := jsonb_build_object(
    'config', public.clan_war_cfg(),
    'season', (SELECT to_jsonb(s) FROM public.clan_war_seasons s WHERE s.status='active' ORDER BY s.starts_at DESC LIMIT 1),
    'counts', jsonb_build_object(
      'searching', (SELECT count(*) FROM public.clan_wars WHERE status='searching'),
      'preparation', (SELECT count(*) FROM public.clan_wars WHERE status='preparation'),
      'battle', (SELECT count(*) FROM public.clan_wars WHERE status='battle'),
      'finished', (SELECT count(*) FROM public.clan_wars WHERE status='finished')),
    'wars', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'warId', w.id, 'status', w.status,
        'clanA', COALESCE(ca.tag, '—'), 'clanB', COALESCE(cb.tag, '—'),
        'nameA', COALESCE(ca.name,'—'), 'nameB', COALESCE(cb.name,'—'),
        'scoreA', w.score_a, 'scoreB', w.score_b,
        'battleStartsAt', w.battle_starts_at, 'battleEndsAt', w.battle_ends_at,
        'settled', w.settled_at IS NOT NULL,
        'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM public.clan_wars ORDER BY created_at DESC LIMIT 12) w
      LEFT JOIN public.clans ca ON ca.id = w.clan_a
      LEFT JOIN public.clans cb ON cb.id = w.clan_b),
    'ranking', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'tag', c.tag, 'name', c.name, 'rating', c.war_rating,
        'league', public.clan_war_league(c.war_rating),
        'wins', c.war_wins, 'losses', c.war_losses) ORDER BY c.war_rating DESC), '[]'::jsonb)
      FROM (SELECT * FROM public.clans ORDER BY war_rating DESC LIMIT 10) c)
  );
  RETURN v;
END; $fn$;

CREATE OR REPLACE FUNCTION public.admin_clan_war_set(p_admin_id bigint, p_key text, p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_key text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_key := CASE p_key
    WHEN 'enabled' THEN 'clan_war_enabled'
    WHEN 'matchmaking' THEN 'clan_war_matchmaking'
    WHEN 'tonSeasonPrize' THEN 'clan_war_ton_season_prize'
    WHEN 'rosterSize' THEN 'clan_war_roster_size'
    WHEN 'attacksPerPlayer' THEN 'clan_war_attacks_per_player'
    WHEN 'preparationHours' THEN 'clan_war_preparation_hours'
    WHEN 'battleHours' THEN 'clan_war_battle_hours'
    WHEN 'seasonWeeks' THEN 'clan_war_season_weeks'
    WHEN 'baseRating' THEN 'clan_war_base_rating'
    WHEN 'pointsWin' THEN 'clan_war_points_win'
    WHEN 'pointsPerfect' THEN 'clan_war_points_perfect'
    WHEN 'pointsUpsetMax' THEN 'clan_war_points_upset_max'
    WHEN 'pointsLoss' THEN 'clan_war_points_loss'
    WHEN 'defenderMaxDefeats' THEN 'clan_war_defender_max_defeats'
    WHEN 'conqueredPercent' THEN 'clan_war_conquered_points_percent'
    WHEN 'sectorBonusPercent' THEN 'clan_war_sector_bonus_percent'
    ELSE NULL END;
  IF v_key IS NULL THEN RAISE EXCEPTION 'INVALID_KEY'; END IF;

  INSERT INTO public.game_settings(key, value, category, label, updated_at, updated_by)
  VALUES (v_key, p_value, 'clan_war', p_key, now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now(), updated_by = p_admin_id;

  PERFORM public.admin_log(p_admin_id, 'clan_war_set', 'clan_war', v_key, NULL, jsonb_build_object('value', p_value), NULL, '{}'::jsonb);
  RETURN public.admin_clan_war_overview(p_admin_id);
END; $fn$;

CREATE OR REPLACE FUNCTION public.admin_clan_war_action(p_admin_id bigint, p_action text, p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_res jsonb := '{}'::jsonb; v_war uuid; v_season uuid; v_weeks int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action = 'tick' THEN
    v_res := public.clan_war_tick();

  ELSIF p_action = 'settle' THEN
    v_war := NULLIF(p_ref,'')::uuid;
    IF v_war IS NULL THEN RAISE EXCEPTION 'WAR_NOT_FOUND'; END IF;
    UPDATE public.clan_wars
       SET status = 'finished', battle_ends_at = LEAST(COALESCE(battle_ends_at, now()), now()), finished_at = COALESCE(finished_at, now())
     WHERE id = v_war AND status IN ('preparation','battle');
    PERFORM public.clan_war_settle(v_war);
    v_res := jsonb_build_object('warId', v_war, 'settled', true);

  ELSIF p_action = 'cancel' THEN
    v_war := NULLIF(p_ref,'')::uuid;
    IF v_war IS NULL THEN RAISE EXCEPTION 'WAR_NOT_FOUND'; END IF;
    UPDATE public.clan_wars SET status='cancelled', finished_at = now(), settled_at = now()
      WHERE id = v_war AND status IN ('searching','preparation','battle');
    v_res := jsonb_build_object('warId', v_war, 'cancelled', true);

  ELSIF p_action = 'season_start' THEN
    v_weeks := GREATEST(1, public.setting_num('clan_war_season_weeks', 4)::int);
    UPDATE public.clan_war_seasons SET status='finished' WHERE status='active';
    INSERT INTO public.clan_war_seasons(code, name, starts_at, ends_at, status, ton_prize_enabled, ton_prize_ton)
    VALUES ('CW-'||to_char(now(),'IYYY"W"IW'), COALESCE(NULLIF(p_payload->>'name',''), 'Clan War Season'),
            now(), now() + make_interval(weeks => v_weeks), 'active',
            COALESCE((SELECT value::text='true' FROM public.game_settings WHERE key='clan_war_ton_season_prize'), false),
            COALESCE((p_payload->>'prizeTon')::numeric, 0))
    RETURNING id INTO v_season;
    v_res := jsonb_build_object('seasonId', v_season, 'weeks', v_weeks);

  ELSIF p_action = 'season_finish' THEN
    UPDATE public.clan_war_seasons SET status='finished', ends_at = now() WHERE status='active' RETURNING id INTO v_season;
    v_res := jsonb_build_object('seasonId', v_season, 'finished', true);

  ELSIF p_action = 'reset_ratings' THEN
    UPDATE public.clans
       SET war_rating = public.setting_num('clan_war_base_rating', 1000)::int,
           war_wins = 0, war_losses = 0, war_points_total = 0;
    v_res := jsonb_build_object('reset', true);

  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  PERFORM public.admin_log(p_admin_id, 'clan_war_'||p_action, 'clan_war', p_ref, NULL, v_res, NULL, COALESCE(p_payload,'{}'::jsonb));
  RETURN v_res;
END; $fn$;

DO $do$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'admin_clan_war_overview(bigint)','admin_clan_war_set(bigint,text,jsonb)','admin_clan_war_action(bigint,text,text,jsonb)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role', fn);
  END LOOP;
END $do$;