CREATE OR REPLACE FUNCTION public.clan_war_dashboard(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        'clanId', c.id, 'name', c.name, 'tag', c.tag, 'emblem', c.emblem_config,
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
    'yourClan', (SELECT jsonb_build_object('id',c.id,'name',c.name,'tag',c.tag,'emblem',c.emblem_config,'rating',c.war_rating,
                        'league', public.clan_war_league(c.war_rating)) FROM public.clans c WHERE c.id=v_clan),
    'enemyClan', (SELECT jsonb_build_object('id',c.id,'name',c.name,'tag',c.tag,'emblem',c.emblem_config,'rating',c.war_rating,
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
END; $function$;