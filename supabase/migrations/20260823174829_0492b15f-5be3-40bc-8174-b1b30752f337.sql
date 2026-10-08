CREATE OR REPLACE FUNCTION public.admin_clan_anti_abuse(
  p_admin_id bigint, p_action text DEFAULT 'get', p_value text DEFAULT NULL, p_target text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_anti_abuse_settings; v_uid uuid; v_num numeric; v_res jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action = 'set_leave' THEN
    v_num := GREATEST(0, COALESCE(p_value::numeric, 24));
    UPDATE public.clan_anti_abuse_settings SET leave_cooldown_hours = v_num, updated_at = now() WHERE id = 1;
    PERFORM public.admin_log(p_admin_id, 'clan_anti_abuse_set_leave', NULL, jsonb_build_object('hours', v_num));
  ELSIF p_action = 'set_kick' THEN
    v_num := GREATEST(0, COALESCE(p_value::numeric, 6));
    UPDATE public.clan_anti_abuse_settings SET kick_cooldown_hours = v_num, updated_at = now() WHERE id = 1;
    PERFORM public.admin_log(p_admin_id, 'clan_anti_abuse_set_kick', NULL, jsonb_build_object('hours', v_num));
  ELSIF p_action = 'toggle' THEN
    UPDATE public.clan_anti_abuse_settings SET enabled = NOT enabled, updated_at = now() WHERE id = 1;
    PERFORM public.admin_log(p_admin_id, 'clan_anti_abuse_toggle', NULL, '{}'::jsonb);
  ELSIF p_action = 'toggle_boss_lock' THEN
    UPDATE public.clan_anti_abuse_settings SET boss_lock_enabled = NOT boss_lock_enabled, updated_at = now() WHERE id = 1;
    PERFORM public.admin_log(p_admin_id, 'clan_anti_abuse_toggle_boss_lock', NULL, '{}'::jsonb);
  END IF;

  IF p_target IS NOT NULL AND btrim(p_target) <> '' THEN
    SELECT id INTO v_uid FROM public.game_players
     WHERE telegram_id::text = btrim(p_target)
        OR lower(COALESCE(username,'')) = lower(ltrim(btrim(p_target), '@'))
        OR id::text = btrim(p_target)
     LIMIT 1;
  END IF;

  IF p_action = 'clear_cooldown' AND v_uid IS NOT NULL THEN
    DELETE FROM public.clan_join_cooldowns WHERE user_id = v_uid;
    PERFORM public.admin_log(p_admin_id, 'clan_anti_abuse_clear_cooldown', v_uid, '{}'::jsonb);
  ELSIF p_action = 'clear_boss_lock' AND v_uid IS NOT NULL THEN
    DELETE FROM public.clan_boss_player_locks WHERE user_id = v_uid;
    PERFORM public.admin_log(p_admin_id, 'clan_anti_abuse_clear_boss_lock', v_uid, '{}'::jsonb);
  END IF;

  cfg := public.clan_anti_abuse_cfg();
  v_res := jsonb_build_object(
    'enabled', cfg.enabled,
    'leaveCooldownHours', cfg.leave_cooldown_hours,
    'kickCooldownHours', cfg.kick_cooldown_hours,
    'bossLockEnabled', cfg.boss_lock_enabled,
    'bossLockMinHours', cfg.boss_lock_min_hours,
    'activeCooldowns', COALESCE((SELECT jsonb_agg(x ORDER BY x->>'until') FROM (
        SELECT jsonb_build_object('name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'telegramId', g.telegram_id, 'until', c.cooldown_until, 'reason', c.reason,
          'changes24h', c.changes_24h) x
          FROM public.clan_join_cooldowns c JOIN public.game_players g ON g.id = c.user_id
         WHERE c.cooldown_until > now() ORDER BY c.cooldown_until LIMIT 25) s), '[]'::jsonb),
    'activeCooldownCount', (SELECT count(*)::int FROM public.clan_join_cooldowns WHERE cooldown_until > now()),
    'bossLocks', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT jsonb_build_object('name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'telegramId', g.telegram_id, 'clan', cl.name, 'until', l.locked_until) x
          FROM public.clan_boss_player_locks l
          JOIN public.game_players g ON g.id = l.user_id
          LEFT JOIN public.clans cl ON cl.id = l.clan_id
         WHERE l.locked_until > now() ORDER BY l.locked_until LIMIT 25) s2), '[]'::jsonb),
    'bossLockCount', (SELECT count(*)::int FROM public.clan_boss_player_locks WHERE locked_until > now()),
    'flags', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT jsonb_build_object('name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'telegramId', g.telegram_id, 'flag', f.flag, 'details', f.details, 'at', f.created_at) x
          FROM public.clan_abuse_flags f JOIN public.game_players g ON g.id = f.user_id
         ORDER BY f.created_at DESC LIMIT 15) s3), '[]'::jsonb)
  );

  IF v_uid IS NOT NULL THEN
    v_res := v_res || jsonb_build_object('audit', jsonb_build_object(
      'userId', v_uid,
      'name', (SELECT COALESCE(display_name, first_name, username, 'Player') FROM public.game_players WHERE id = v_uid),
      'telegramId', (SELECT telegram_id FROM public.game_players WHERE id = v_uid),
      'currentClan', (SELECT cl.name FROM public.clan_members m JOIN public.clans cl ON cl.id = m.clan_id WHERE m.user_id = v_uid),
      'history', COALESCE((SELECT jsonb_agg(jsonb_build_object('clan', COALESCE(h.clan_name, cl.name), 'joinedAt', h.joined_at,
            'leftAt', h.left_at, 'reason', h.leave_reason) ORDER BY h.joined_at DESC)
          FROM public.clan_membership_history h LEFT JOIN public.clans cl ON cl.id = h.clan_id
         WHERE h.user_id = v_uid), '[]'::jsonb),
      'bossDamage', COALESCE((SELECT jsonb_agg(jsonb_build_object('clan', cl.name, 'damage', d.damage,
            'status', d.eligibility_status, 'instance', d.instance_id) ORDER BY d.last_attack_at DESC NULLS LAST)
          FROM public.clan_boss_damage d LEFT JOIN public.clans cl ON cl.id = d.clan_id
         WHERE d.user_id = v_uid LIMIT 15), '[]'::jsonb),
      'rewards', (SELECT count(*)::int FROM public.clan_boss_claims WHERE user_id = v_uid),
      'cooldown', public.clan_join_cooldown_json(v_uid),
      'bossLock', public.clan_boss_lock_json(v_uid),
      'flags', COALESCE((SELECT jsonb_agg(jsonb_build_object('flag', flag, 'at', created_at, 'details', details) ORDER BY created_at DESC)
          FROM public.clan_abuse_flags WHERE user_id = v_uid), '[]'::jsonb)
    ));
  ELSIF p_target IS NOT NULL AND btrim(p_target) <> '' THEN
    v_res := v_res || jsonb_build_object('audit', jsonb_build_object('notFound', true, 'query', p_target));
  END IF;

  RETURN v_res;
END $function$;
REVOKE ALL ON FUNCTION public.admin_clan_anti_abuse(bigint, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_clan_anti_abuse(bigint, text, text, text) TO service_role;