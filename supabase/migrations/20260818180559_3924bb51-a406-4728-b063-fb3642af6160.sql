CREATE OR REPLACE FUNCTION public.clan_boss_strike(p_telegram_id bigint, p_instance_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; b public.clan_boss_instances;
        v_last timestamptz; v_damage numeric; v_base numeric; v_power numeric; v_bonus numeric; v_buffs jsonb;
        v_crit boolean := false; v_defeated boolean := false; v_type text;
BEGIN
  cfg := public.clan_boss_cfg();
  v_type := CASE WHEN coalesce(current_setting('mythreon.clan_attack_type', true), 'manual') = 'season_pass_auto'
                 THEN 'season_pass_auto' ELSE 'manual' END;
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('clanbossv2:'||v_clan::text, 0));
  b := public.clan_boss_ensure(v_clan);

  IF p_instance_id IS NOT NULL AND p_instance_id <> b.id THEN
    IF EXISTS (SELECT 1 FROM public.clan_boss_instances WHERE id = p_instance_id AND clan_id <> v_clan)
      THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
    RAISE EXCEPTION 'CLAN_BOSS_STALE';
  END IF;

  SELECT * INTO b FROM public.clan_boss_instances WHERE id = b.id FOR UPDATE;
  IF b.clan_id <> v_clan THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
  IF b.status <> 'active' OR b.current_hp <= 0 THEN RAISE EXCEPTION 'CLAN_BOSS_DEFEATED'; END IF;
  IF b.ends_at <= now() THEN RAISE EXCEPTION 'CLAN_BOSS_EXPIRED'; END IF;

  -- Single cooldown shared by manual and automatic attacks of THIS boss.
  SELECT last_attack_at INTO v_last FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid FOR UPDATE;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => GREATEST(1, cfg.cooldown_seconds)) THEN
    RAISE EXCEPTION 'CLAN_BOSS_COOLDOWN';
  END IF;

  v_buffs := COALESCE(public.get_pet_bonuses(v_uid), '{}'::jsonb);
  v_power := GREATEST(1, public.clan_player_power(v_uid));
  -- O buff de vida do pet vale como resistencia da equipe no chefe de cla (peso 25%).
  v_bonus := COALESCE((v_buffs->>'boss_damage_percent')::numeric, 0)
           + COALESCE((v_buffs->>'team_attack_percent')::numeric, 0)
           + public.pet_hp_bonus_percent(v_buffs) * 0.25;
  v_base := GREATEST(100, round(v_power * (0.85 + random() * 0.3)));
  v_damage := GREATEST(100, round(v_base * (1 + v_bonus / 100.0)));
  IF random() < LEAST(0.35, COALESCE((v_buffs->>'critical_chance_percent')::numeric, 0) / 100.0) THEN
    v_crit := true;
    v_damage := round(v_damage * (1.5 + COALESCE((v_buffs->>'critical_damage_percent')::numeric, 0) / 100.0));
  END IF;
  v_damage := LEAST(v_damage, b.current_hp);

  UPDATE public.clan_boss_instances
     SET current_hp = GREATEST(0, current_hp - v_damage),
         total_damage = total_damage + v_damage,
         attacks = attacks + 1
   WHERE id = b.id RETURNING * INTO b;

  INSERT INTO public.clan_boss_damage(instance_id, clan_id, user_id, damage, attacks, last_attack_at)
  VALUES (b.id, v_clan, v_uid, v_damage, 1, now())
  ON CONFLICT (instance_id, user_id) DO UPDATE
    SET damage = public.clan_boss_damage.damage + EXCLUDED.damage,
        attacks = public.clan_boss_damage.attacks + 1,
        last_attack_at = now();

  UPDATE public.clan_boss_instances
     SET participants = COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0)
   WHERE id = b.id;

  INSERT INTO public.clan_boss_attack_log(user_id, telegram_id, clan_id, clan_boss_id, attack_type, damage, team_power, pass_type)
  VALUES (v_uid, p_telegram_id, v_clan, b.id, v_type, v_damage, v_power, public.global_boss_auto_pass_tier(v_uid));

  -- Manual attacks push the automatic tick forward (shared clan boss cooldown).
  UPDATE public.clan_boss_auto_attack
     SET last_auto_attack_at = CASE WHEN v_type = 'season_pass_auto' THEN now() ELSE last_auto_attack_at END,
         next_auto_attack_at = now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)),
         attacks_total = attacks_total + CASE WHEN v_type = 'season_pass_auto' THEN 1 ELSE 0 END,
         paused_reason = NULL, updated_at = now()
   WHERE user_id = v_uid;

  IF b.current_hp <= 0 THEN
    v_defeated := true;
    PERFORM public.clan_boss_settle(b.id, 'defeated');
    PERFORM public.clan_boss_ensure(v_clan);
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_boss_damage', v_damage::bigint);

  RETURN jsonb_build_object('status','ok', 'damage', v_damage, 'critical', v_crit,
    'currentHp', GREATEST(0, b.current_hp), 'maxHp', b.max_hp, 'defeated', v_defeated,
    'damageBeforePet', v_base, 'petBossDamagePercent', v_bonus, 'attackType', v_type,
    'nextAttackAt', now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)));
END $function$;