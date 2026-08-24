CREATE OR REPLACE PROCEDURE public.run_clan_boss_auto_attacks(p_limit integer DEFAULT 500)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $procedure$
DECLARE cfg public.clan_boss_config; r record; v_tier text; v_next timestamptz;
        v_last timestamptz; v_retry timestamptz; v_clan uuid; v_users uuid[];
        v_uid uuid; v_err text;
BEGIN
  IF NOT pg_try_advisory_lock(hashtext('clan_boss_auto_attacks')) THEN
    RETURN;
  END IF;

  cfg := public.clan_boss_cfg();

  SELECT array_agg(a.user_id ORDER BY a.next_auto_attack_at)
    INTO v_users
    FROM public.clan_boss_auto_attack a
    JOIN public.game_players g ON g.id = a.user_id
   WHERE a.enabled AND a.next_auto_attack_at <= now();

  IF v_users IS NULL THEN
    PERFORM pg_advisory_unlock(hashtext('clan_boss_auto_attacks'));
    RETURN;
  END IF;

  FOREACH v_uid IN ARRAY v_users[1:GREATEST(1, LEAST(coalesce(p_limit,500), 2000))] LOOP
    v_err := NULL;

    BEGIN
      r := NULL;
      SELECT a.user_id, g.telegram_id, cm.clan_id
        INTO r
        FROM public.clan_boss_auto_attack a
        JOIN public.game_players g ON g.id = a.user_id
        LEFT JOIN public.clan_members cm ON cm.user_id = a.user_id
       WHERE a.user_id = v_uid AND a.enabled AND a.next_auto_attack_at <= now();

      IF r.user_id IS NOT NULL THEN
        v_tier := public.global_boss_auto_pass_tier(r.user_id);
        IF v_tier IS NULL OR r.clan_id IS NULL OR public.clan_player_power(r.user_id) <= 0
           OR NOT EXISTS (SELECT 1 FROM public.clan_boss_instances
                           WHERE clan_id = r.clan_id AND status = 'active' AND current_hp > 0 AND ends_at > now()) THEN
          UPDATE public.clan_boss_auto_attack
             SET next_auto_attack_at = now() + make_interval(secs => GREATEST(30, cfg.cooldown_seconds)),
                 paused_reason = CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN r.clan_id IS NULL THEN 'no_clan'
                                      WHEN public.clan_player_power(r.user_id) <= 0 THEN 'no_team' ELSE 'no_boss' END,
                 updated_at = now()
           WHERE user_id = r.user_id;
        ELSE
          PERFORM set_config('mythreon.clan_attack_type', 'season_pass_auto', true);
          PERFORM public.clan_boss_strike(r.telegram_id, NULL);

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
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_err := left(SQLERRM, 200);
    END;

    IF v_err IS NOT NULL THEN
      SELECT cm.clan_id INTO v_clan FROM public.clan_members cm WHERE cm.user_id = v_uid;
      SELECT d.last_attack_at INTO v_last FROM public.clan_boss_damage d
        JOIN public.clan_boss_instances i ON i.id = d.instance_id
       WHERE d.user_id = v_uid AND i.clan_id = v_clan AND i.status = 'active'
       ORDER BY d.last_attack_at DESC LIMIT 1;
      v_retry := GREATEST(
        now() + interval '5 seconds',
        coalesce(v_last + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)), now() + interval '5 seconds'),
        coalesce(public.boss_heroes_revive_at(v_uid), now() + interval '5 seconds'));
      UPDATE public.clan_boss_auto_attack
         SET next_auto_attack_at = v_retry,
             paused_reason = v_err, updated_at = now()
       WHERE user_id = v_uid;
    END IF;

    COMMIT;
  END LOOP;

  PERFORM pg_advisory_unlock(hashtext('clan_boss_auto_attacks'));
END $procedure$;

REVOKE ALL ON PROCEDURE public.run_clan_boss_auto_attacks(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.run_clan_boss_auto_attacks(integer) TO service_role, postgres;