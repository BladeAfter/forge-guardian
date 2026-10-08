CREATE OR REPLACE FUNCTION public.process_clan_boss_auto_attacks(p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; r record; v_tier text; v_count int := 0; v_paused int := 0;
        v_retry timestamptz; v_last timestamptz; v_next timestamptz;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('clan_boss_auto_attacks')) THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 'locked');
  END IF;
  cfg := public.clan_boss_cfg();
  FOR r IN
    SELECT a.user_id, g.telegram_id, cm.clan_id
    FROM public.clan_boss_auto_attack a
    JOIN public.game_players g ON g.id = a.user_id
    LEFT JOIN public.clan_members cm ON cm.user_id = a.user_id
    WHERE a.enabled AND a.next_auto_attack_at <= now()
    ORDER BY a.next_auto_attack_at
    LIMIT GREATEST(1, LEAST(coalesce(p_limit, 500), 2000))
    FOR UPDATE OF a SKIP LOCKED
  LOOP
    -- Never trust the stored preference: the pass must still be valid NOW.
    v_tier := public.global_boss_auto_pass_tier(r.user_id);
    IF v_tier IS NULL OR r.clan_id IS NULL OR public.clan_player_power(r.user_id) <= 0
       OR NOT EXISTS (SELECT 1 FROM public.clan_boss_instances
                       WHERE clan_id = r.clan_id AND status = 'active' AND current_hp > 0 AND ends_at > now()) THEN
      UPDATE public.clan_boss_auto_attack
         SET next_auto_attack_at = now() + make_interval(secs => GREATEST(60, cfg.cooldown_seconds / 5)),
             paused_reason = CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN r.clan_id IS NULL THEN 'no_clan'
                                  WHEN public.clan_player_power(r.user_id) <= 0 THEN 'no_team' ELSE 'no_boss' END,
             updated_at = now()
       WHERE user_id = r.user_id;
      v_paused := v_paused + 1;
      CONTINUE;
    END IF;
    BEGIN
      PERFORM set_config('mythreon.clan_attack_type', 'season_pass_auto', true);
      PERFORM public.clan_boss_strike(r.telegram_id, NULL);
      PERFORM set_config('mythreon.clan_attack_type', 'manual', true);
      -- The strike landed: schedule the NEXT auto attack at the real eligibility
      -- moment (cooldown from this attack, or the team revive time if later).
      v_next := GREATEST(
        now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)),
        coalesce(public.boss_heroes_revive_at(r.user_id), now()));
      UPDATE public.clan_boss_auto_attack
         SET last_auto_attack_at = now(),
             next_auto_attack_at = v_next,
             attacks_total = coalesce(attacks_total, 0) + 1,
             paused_reason = NULL,
             updated_at = now()
       WHERE user_id = r.user_id;
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('mythreon.clan_attack_type', 'manual', true);
      -- Reschedule at the REAL eligibility moment (remaining cooldown / revive),
      -- never by starting a brand new cooldown from scratch.
      SELECT d.last_attack_at INTO v_last FROM public.clan_boss_damage d
        JOIN public.clan_boss_instances i ON i.id = d.instance_id
       WHERE d.user_id = r.user_id AND i.clan_id = r.clan_id AND i.status = 'active'
       ORDER BY d.last_attack_at DESC LIMIT 1;
      v_retry := GREATEST(
        now() + interval '15 seconds',
        coalesce(v_last + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)), now() + interval '15 seconds'),
        coalesce(public.boss_heroes_revive_at(r.user_id), now() + interval '15 seconds'));
      UPDATE public.clan_boss_auto_attack
         SET next_auto_attack_at = v_retry,
             paused_reason = left(SQLERRM, 200), updated_at = now()
       WHERE user_id = r.user_id;
    END;
  END LOOP;
  RETURN jsonb_build_object('processed', v_count, 'paused', v_paused);
END $function$;

REVOKE ALL ON FUNCTION public.process_clan_boss_auto_attacks(integer) FROM PUBLIC, anon, authenticated;