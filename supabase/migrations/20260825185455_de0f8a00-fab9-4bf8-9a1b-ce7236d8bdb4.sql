CREATE OR REPLACE FUNCTION public.admin_clan_boss(p_admin_id bigint, p_action text DEFAULT 'overview'::text, p_ref text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; sc public.clan_boss_scaling_config; v_clan uuid;
        b public.clan_boss_instances; v_num numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_action = 'set' THEN
    v_num := COALESCE((p_payload->>'value')::numeric, 0);
    IF p_ref = 'fixed_hp' THEN
      UPDATE public.clan_boss_scaling_config SET fixed_hp = GREATEST(0, v_num), updated_at = now() WHERE id = 1;
      IF v_num > 0 THEN
        UPDATE public.clan_boss_instances i
           SET max_hp = round(v_num),
               current_hp = LEAST(round(v_num), GREATEST(1, round(i.current_hp * v_num / GREATEST(1, i.max_hp))))
         WHERE i.status = 'active'
           AND NOT EXISTS (SELECT 1 FROM public.clan_boss_clan_settings s
                            WHERE s.clan_id = i.clan_id AND COALESCE(s.fixed_hp, 0) > 0);
      END IF;
    ELSIF p_ref = 'bosses_per_day' THEN
      UPDATE public.clan_boss_scaling_config
         SET bosses_per_day = GREATEST(1, LEAST(48, v_num))::int,
             cycle_hours = GREATEST(1, floor(24.0 / GREATEST(1, LEAST(48, v_num)))::int),
             updated_at = now()
       WHERE id = 1;
    ELSE
      UPDATE public.clan_boss_config SET
        base_hp = CASE WHEN p_ref='base_hp' THEN GREATEST(1000, v_num) ELSE base_hp END,
        hp_per_clan_level_pct = CASE WHEN p_ref='hp_per_clan_level_pct' THEN LEAST(200, GREATEST(0, v_num)) ELSE hp_per_clan_level_pct END,
        hp_per_member_pct = CASE WHEN p_ref='hp_per_member_pct' THEN LEAST(50, GREATEST(0, v_num)) ELSE hp_per_member_pct END,
        hp_per_cycle_pct = CASE WHEN p_ref='hp_per_cycle_pct' THEN LEAST(100, GREATEST(0, v_num)) ELSE hp_per_cycle_pct END,
        duration_hours = CASE WHEN p_ref='duration_hours' THEN LEAST(720, GREATEST(1, v_num))::int ELSE duration_hours END,
        cooldown_seconds = CASE WHEN p_ref='cooldown_seconds' THEN LEAST(86400, GREATEST(10, v_num))::int ELSE cooldown_seconds END,
        clan_xp_reward = CASE WHEN p_ref='clan_xp_reward' THEN LEAST(100000, GREATEST(0, v_num))::int ELSE clan_xp_reward END,
        min_damage_pct = CASE WHEN p_ref='min_damage_pct' THEN LEAST(50, GREATEST(0, v_num)) ELSE min_damage_pct END,
        boss_name = CASE WHEN p_ref='boss_name' THEN COALESCE(NULLIF(p_payload->>'text',''), boss_name) ELSE boss_name END,
        rewards = CASE WHEN p_ref='rewards' THEN COALESCE(p_payload->'rewards', rewards)
                       WHEN p_ref='fc_pool' THEN COALESCE(rewards,'{}'::jsonb) || jsonb_build_object('fcPool', GREATEST(0, v_num))
                       ELSE rewards END,
        updated_at = now()
      WHERE id = 1;
      -- Reward edits apply live to running bosses without a per-clan override.
      IF p_ref IN ('rewards', 'fc_pool') THEN
        UPDATE public.clan_boss_instances i
           SET rewards_snapshot = COALESCE(i.rewards_snapshot, '{}'::jsonb)
             || CASE WHEN p_ref = 'rewards' THEN COALESCE(p_payload->'rewards', '{}'::jsonb)
                     ELSE jsonb_build_object('fcPool', GREATEST(0, v_num)) END
         WHERE i.status = 'active'
           AND NOT EXISTS (SELECT 1 FROM public.clan_boss_clan_settings s
                            WHERE s.clan_id = i.clan_id AND (s.reward_fc_pool IS NOT NULL OR s.rewards IS NOT NULL));
      END IF;
    END IF;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_config', 'clan_boss', p_ref, NULL::jsonb, p_payload, 'painel admin', '{}'::jsonb);
  ELSIF p_action = 'force_start' THEN
    v_clan := NULLIF(p_ref,'')::uuid;
    SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = v_clan AND status='active' LIMIT 1;
    IF b.id IS NOT NULL THEN PERFORM public.clan_boss_settle(b.id, 'expired'); END IF;
    b := public.clan_boss_ensure(v_clan);
    PERFORM public.admin_log(p_admin_id, 'clan_boss_force_start', 'clan_boss', p_ref, NULL::jsonb, jsonb_build_object('cycle', b.cycle, 'maxHp', b.max_hp), 'painel admin', '{}'::jsonb);
  ELSIF p_action = 'end_cycle' THEN
    v_clan := NULLIF(p_ref,'')::uuid;
    SELECT * INTO b FROM public.clan_boss_instances WHERE clan_id = v_clan AND status='active' LIMIT 1;
    IF b.id IS NOT NULL THEN
      PERFORM public.clan_boss_settle(b.id, CASE WHEN COALESCE((p_payload->>'reward')::boolean, false) THEN 'defeated' ELSE 'expired' END);
      PERFORM public.clan_boss_ensure(v_clan);
    END IF;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_end_cycle', 'clan_boss', p_ref, NULL::jsonb, p_payload, 'painel admin', '{}'::jsonb);
  END IF;

  cfg := public.clan_boss_cfg();
  sc := public.clan_boss_scaling_cfg();
  RETURN jsonb_build_object(
    'config', jsonb_build_object('bossName', cfg.boss_name, 'bossKey', cfg.boss_key, 'baseHp', cfg.base_hp,
      'hpPerClanLevelPct', cfg.hp_per_clan_level_pct, 'hpPerMemberPct', cfg.hp_per_member_pct,
      'hpPerCyclePct', cfg.hp_per_cycle_pct, 'durationHours', cfg.duration_hours,
      'cooldownSeconds', cfg.cooldown_seconds, 'clanXpReward', cfg.clan_xp_reward,
      'minDamagePct', cfg.min_damage_pct, 'rewards', cfg.rewards,
      'fixedHp', sc.fixed_hp, 'bossesPerDay', sc.bosses_per_day, 'cycleHours', sc.cycle_hours),
    'active', COALESCE((SELECT jsonb_agg(jsonb_build_object('clanId', c.id, 'clan', c.name, 'tag', c.tag,
        'cycle', i.cycle, 'level', i.level, 'maxHp', i.max_hp, 'currentHp', i.current_hp,
        'participants', i.participants, 'endsAt', i.ends_at) ORDER BY i.current_hp ASC)
      FROM public.clan_boss_instances i JOIN public.clans c ON c.id = i.clan_id WHERE i.status='active'), '[]'::jsonb),
    'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('clan', c.name, 'cycle', i.cycle, 'status', i.status,
        'totalDamage', i.total_damage, 'clanXp', i.clan_xp_awarded, 'finishedAt', i.finished_at,
        'top', COALESCE(g.display_name, g.username)) ORDER BY i.finished_at DESC)
      FROM (SELECT * FROM public.clan_boss_instances WHERE status <> 'active' ORDER BY finished_at DESC LIMIT 15) i
      JOIN public.clans c ON c.id = i.clan_id LEFT JOIN public.game_players g ON g.id = i.top_user_id), '[]'::jsonb)
  );
END $function$;