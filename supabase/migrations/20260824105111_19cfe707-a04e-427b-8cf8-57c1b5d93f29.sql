-- Per-user auto attack (one transaction per attack, driven by an edge function tick)
CREATE OR REPLACE FUNCTION public.clan_boss_auto_due_users(p_limit integer DEFAULT 500)
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT a.user_id
    FROM public.clan_boss_auto_attack a
    JOIN public.game_players g ON g.id = a.user_id
   WHERE a.enabled AND a.next_auto_attack_at <= now()
   ORDER BY a.next_auto_attack_at
   LIMIT GREATEST(1, LEAST(coalesce(p_limit, 500), 2000));
$function$;

CREATE OR REPLACE FUNCTION public.clan_boss_auto_attack_one(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; r record; v_tier text; v_next timestamptz;
        v_last timestamptz; v_retry timestamptz; v_clan uuid; v_err text; v_reason text;
BEGIN
  cfg := public.clan_boss_cfg();

  SELECT a.user_id AS uid, g.telegram_id, cm.clan_id
    INTO r
    FROM public.clan_boss_auto_attack a
    JOIN public.game_players g ON g.id = a.user_id
    LEFT JOIN public.clan_members cm ON cm.user_id = a.user_id
   WHERE a.user_id = p_user AND a.enabled AND a.next_auto_attack_at <= now()
   FOR NO KEY UPDATE OF a SKIP LOCKED;

  IF r.uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'skipped', true); END IF;

  v_tier := public.global_boss_auto_pass_tier(r.uid);
  IF v_tier IS NULL OR r.clan_id IS NULL OR public.clan_player_power(r.uid) <= 0
     OR NOT EXISTS (SELECT 1 FROM public.clan_boss_instances
                     WHERE clan_id = r.clan_id AND status = 'active' AND current_hp > 0 AND ends_at > now()) THEN
    v_reason := CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN r.clan_id IS NULL THEN 'no_clan'
                     WHEN public.clan_player_power(r.uid) <= 0 THEN 'no_team' ELSE 'no_boss' END;
    UPDATE public.clan_boss_auto_attack
       SET next_auto_attack_at = now() + make_interval(secs => GREATEST(30, cfg.cooldown_seconds)),
           paused_reason = v_reason, updated_at = now()
     WHERE user_id = r.uid;
    RETURN jsonb_build_object('ok', false, 'paused', v_reason);
  END IF;

  BEGIN
    PERFORM set_config('mythreon.clan_attack_type', 'season_pass_auto', true);
    PERFORM public.clan_boss_strike(r.telegram_id, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_err := left(SQLERRM, 200);
  END;

  IF v_err IS NOT NULL THEN
    SELECT cm.clan_id INTO v_clan FROM public.clan_members cm WHERE cm.user_id = r.uid;
    SELECT d.last_attack_at INTO v_last FROM public.clan_boss_damage d
      JOIN public.clan_boss_instances i ON i.id = d.instance_id
     WHERE d.user_id = r.uid AND i.clan_id = v_clan AND i.status = 'active'
     ORDER BY d.last_attack_at DESC LIMIT 1;
    v_retry := GREATEST(
      now() + interval '5 seconds',
      coalesce(v_last + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)), now() + interval '5 seconds'),
      coalesce(public.boss_heroes_revive_at(r.uid), now() + interval '5 seconds'));
    UPDATE public.clan_boss_auto_attack
       SET next_auto_attack_at = v_retry, paused_reason = v_err, updated_at = now()
     WHERE user_id = r.uid;
    RETURN jsonb_build_object('ok', false, 'error', v_err);
  END IF;

  v_next := GREATEST(
    now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)),
    coalesce(public.boss_heroes_revive_at(r.uid), now()));
  UPDATE public.clan_boss_auto_attack
     SET last_auto_attack_at = now(), next_auto_attack_at = v_next,
         attacks_total = coalesce(attacks_total, 0) + 1,
         paused_reason = NULL, updated_at = now()
   WHERE user_id = r.uid;

  RETURN jsonb_build_object('ok', true, 'nextAt', v_next);
END $function$;

REVOKE ALL ON FUNCTION public.clan_boss_auto_due_users(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_boss_auto_attack_one(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_boss_auto_due_users(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_boss_auto_attack_one(uuid) TO service_role;

DROP PROCEDURE IF EXISTS public.run_clan_boss_auto_attacks(integer);