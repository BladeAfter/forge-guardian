-- 0039c: admin control surface for Clan Boss balance
CREATE OR REPLACE FUNCTION public.admin_clan_boss_balance(
  p_admin_id bigint, p_action text DEFAULT 'OVERVIEW',
  p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE sc public.clan_boss_scaling_config; v_clan uuid; r record; v_out jsonb; v_n integer := 0;
        v_val numeric; s jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  sc := public.clan_boss_scaling_cfg();

  IF p_action = 'OVERVIEW' THEN
    RETURN jsonb_build_object(
      'config', to_jsonb(sc),
      'clans', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'dps')::numeric DESC NULLS LAST) FROM (
          SELECT jsonb_build_object('clanId', c.id, 'name', c.name, 'tag', c.tag,
                   'power', c.total_power, 'members', (SELECT count(*) FROM public.clan_members m WHERE m.clan_id = c.id),
                   'dps', p.effective_dps, 'tier', p.scaling_tier,
                   'hpMultiplier', p.hp_multiplier, 'lastDuration', p.last_actual_duration_seconds,
                   'lastQuality', p.last_quality, 'mode', p.last_mode,
                   'kills24h', (SELECT count(*) FROM public.clan_boss_instances i
                                 WHERE i.clan_id = c.id AND i.status = 'defeated'
                                   AND i.finished_at > now() - interval '24 hours')) x
            FROM public.clans c LEFT JOIN public.clan_boss_scaling_profiles p ON p.clan_id = c.id
           WHERE NOT COALESCE(c.suspended, false)) q), '[]'::jsonb));

  ELSIF p_action = 'SET' THEN
    v_val := (p_payload->>'value')::numeric;
    IF p_ref = 'target_duration_seconds' THEN
      UPDATE public.clan_boss_scaling_config SET target_duration_seconds = GREATEST(3600, v_val::int), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'cycle_hours' THEN
      UPDATE public.clan_boss_scaling_config SET cycle_hours = GREATEST(1, v_val::int), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'hp_scaling' THEN
      UPDATE public.clan_boss_scaling_config SET hp_scaling = GREATEST(0.1, v_val), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'def_scaling' THEN
      UPDATE public.clan_boss_scaling_config SET def_scaling = GREATEST(0.1, v_val), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'atk_scaling' THEN
      UPDATE public.clan_boss_scaling_config SET atk_scaling = GREATEST(0.1, v_val), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'enabled' THEN
      UPDATE public.clan_boss_scaling_config SET enabled = (v_val <> 0), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'cycle_lock_enabled' THEN
      UPDATE public.clan_boss_scaling_config SET cycle_lock_enabled = (v_val <> 0), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'too_easy_seconds' THEN
      UPDATE public.clan_boss_scaling_config SET too_easy_seconds = GREATEST(600, v_val::int), updated_at = now() WHERE id = 1;
    ELSIF p_ref = 'too_hard_seconds' THEN
      UPDATE public.clan_boss_scaling_config SET too_hard_seconds = GREATEST(1200, v_val::int), updated_at = now() WHERE id = 1;
    ELSE
      RAISE EXCEPTION 'UNKNOWN_SETTING';
    END IF;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_balance_set', p_ref, p_payload);
    RETURN jsonb_build_object('ok', true, 'config', to_jsonb(public.clan_boss_scaling_cfg()));

  ELSIF p_action = 'VIEW_CLAN' THEN
    v_clan := p_ref::uuid;
    s := public.clan_boss_compute_scaling(v_clan, NULL);
    RETURN jsonb_build_object(
      'clan', (SELECT jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag,
                 'power', c.total_power, 'level', c.level,
                 'members', (SELECT count(*) FROM public.clan_members m WHERE m.clan_id = c.id))
                 FROM public.clans c WHERE c.id = v_clan),
      'scaling', s,
      'profile', (SELECT to_jsonb(p) FROM public.clan_boss_scaling_profiles p WHERE p.clan_id = v_clan),
      'currentBoss', (SELECT jsonb_build_object('cycle', i.cycle, 'maxHp', i.max_hp, 'currentHp', i.current_hp,
                        'def', i.boss_def, 'atk', i.boss_atk, 'power', i.boss_power,
                        'startsAt', i.starts_at, 'cycleEndsAt', i.cycle_ends_at,
                        'targetDuration', i.target_duration_seconds)
                       FROM public.clan_boss_instances i
                      WHERE i.clan_id = v_clan AND i.status = 'active' LIMIT 1),
      'lastBosses', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                       'cycle', h.cycle, 'effectiveHp', h.effective_hp, 'actual', h.actual_duration_seconds,
                       'target', h.target_duration_seconds, 'quality', h.quality, 'status', h.final_status)
                       ORDER BY h.created_at DESC)
                     FROM (SELECT * FROM public.clan_boss_performance_history
                            WHERE clan_id = v_clan ORDER BY created_at DESC LIMIT 10) h), '[]'::jsonb),
      'cycleLock', public.clan_boss_cycle_lock(v_clan));

  ELSIF p_action = 'RECALC_CLAN' THEN
    v_clan := p_ref::uuid;
    s := public.clan_boss_scaling_persist(v_clan);
    PERFORM public.admin_log(p_admin_id, 'clan_boss_recalc', p_ref, s);
    RETURN s;

  ELSIF p_action = 'RECALC_ALL' THEN
    FOR r IN SELECT id FROM public.clans WHERE NOT COALESCE(suspended, false) LOOP
      PERFORM public.clan_boss_scaling_persist(r.id);
      v_n := v_n + 1;
    END LOOP;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_recalc_all', NULL, jsonb_build_object('clans', v_n));
    RETURN jsonb_build_object('ok', true, 'clansRecalculated', v_n,
      'rebase', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', c.name, 'tier', p.scaling_tier,
                   'mode', p.last_mode, 'hpMultiplier', p.hp_multiplier))
                 FROM public.clan_boss_scaling_profiles p JOIN public.clans c ON c.id = p.clan_id
                WHERE p.last_mode IN ('FULL_RECALIBRATION','INITIAL_REBASE')), '[]'::jsonb));

  ELSIF p_action = 'OUTLIERS' THEN
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('clan', c.name,
              'outlierAttacks', (p.metrics->>'outlierAttacks')::int,
              'cap', (p.metrics->>'outlierCap')::numeric))
            FROM public.clan_boss_scaling_profiles p JOIN public.clans c ON c.id = p.clan_id
           WHERE COALESCE((p.metrics->>'outlierAttacks')::int, 0) > 0), '[]'::jsonb);

  ELSIF p_action = 'DURATION_REPORT' THEN
    RETURN COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'actual')::numeric ASC NULLS LAST) FROM (
        SELECT jsonb_build_object('clan', c.name, 'power', c.total_power,
                 'bossHp', h.effective_hp, 'actual', h.actual_duration_seconds,
                 'target', h.target_duration_seconds, 'quality', h.quality,
                 'cycle', h.cycle, 'finishedAt', h.created_at) x
          FROM public.clan_boss_performance_history h JOIN public.clans c ON c.id = h.clan_id
         WHERE h.created_at > now() - interval '14 days') q), '[]'::jsonb);

  ELSIF p_action = 'TOO_EASY' THEN
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('clan', c.name, 'clanId', c.id,
              'kills24h', k.kills, 'dps', p.effective_dps, 'tier', p.scaling_tier,
              'recommendedHp', round(p.effective_dps * 86400 * 1.05 * 0.8)))
            FROM public.clans c
            JOIN LATERAL (SELECT count(*) kills FROM public.clan_boss_instances i
                           WHERE i.clan_id = c.id AND i.status = 'defeated'
                             AND i.finished_at > now() - interval '24 hours') k ON true
            LEFT JOIN public.clan_boss_scaling_profiles p ON p.clan_id = c.id
           WHERE k.kills >= GREATEST(1, sc.rebase_kills_threshold)), '[]'::jsonb);
  END IF;

  RAISE EXCEPTION 'UNKNOWN_ACTION';
END $fn$;
REVOKE ALL ON FUNCTION public.admin_clan_boss_balance(bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;