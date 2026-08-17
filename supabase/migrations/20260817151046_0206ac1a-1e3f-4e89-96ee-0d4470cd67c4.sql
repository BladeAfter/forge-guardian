CREATE OR REPLACE FUNCTION public.process_global_boss_auto_attacks(p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cyc public.global_boss_cycles; r record; v_before numeric; v_after numeric;
        v_power numeric; v_tier text; v_count int := 0; v_dmg numeric := 0; v_next timestamptz;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('global_boss_auto_attacks')) THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 'locked');
  END IF;
  cyc := public.ensure_global_boss_cycle();
  IF cyc.id IS NULL OR cyc.status <> 'active' OR cyc.current_hp <= 0 THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 'boss_inactive');
  END IF;
  FOR r IN
    SELECT a.user_id, g.telegram_id
    FROM public.global_boss_auto_attack a
    JOIN public.game_players g ON g.id = a.user_id
    WHERE a.enabled
      AND a.next_auto_attack_at <= now()
      AND public.global_boss_auto_pass_tier(a.user_id) IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.boss_team_slots ts WHERE ts.user_id = a.user_id)
    ORDER BY a.next_auto_attack_at
    LIMIT GREATEST(1, LEAST(coalesce(p_limit, 500), 2000))
    FOR UPDATE OF a SKIP LOCKED
  LOOP
    SELECT * INTO cyc FROM public.global_boss_cycles WHERE id = cyc.id;
    EXIT WHEN cyc.status <> 'active' OR cyc.current_hp <= 0;
    v_tier := public.global_boss_auto_pass_tier(r.user_id);
    CONTINUE WHEN v_tier IS NULL;
    SELECT coalesce(damage_total,0) INTO v_before FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND user_id = r.user_id;
    BEGIN
      PERFORM public.process_boss_combat(r.telegram_id);
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.global_boss_auto_attack
         SET next_auto_attack_at = public.boss_auto_next_attack_at(r.user_id, now() + interval '15 seconds'),
             paused_reason = left(SQLERRM, 200), updated_at = now()
       WHERE user_id = r.user_id;
      CONTINUE;
    END;
    SELECT coalesce(damage_total,0) INTO v_after FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND user_id = r.user_id;
    SELECT coalesce(sum(s.final_atk),0) INTO v_power FROM public.hero_combat_state s
      JOIN public.boss_combats bc ON bc.id = s.combat_id
      WHERE bc.user_id = r.user_id AND s.slot IS NOT NULL;
    v_dmg := greatest(0, coalesce(v_after,0) - coalesce(v_before,0));
    BEGIN
      INSERT INTO public.global_boss_attack_log(user_id, telegram_id, boss_id, cycle_id, attack_type, damage, team_power, pass_type)
        VALUES (r.user_id, r.telegram_id, cyc.template_id, cyc.id, 'season_pass_auto', v_dmg, coalesce(v_power,0), v_tier);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    v_next := public.boss_auto_next_attack_at(r.user_id, now() + interval '300 seconds');
    UPDATE public.global_boss_auto_attack SET last_auto_attack_at = now(),
      next_auto_attack_at = v_next, attacks_total = attacks_total + 1,
      paused_reason = NULL, updated_at = now() WHERE user_id = r.user_id;
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('processed', v_count, 'cycleId', cyc.id);
END $function$;