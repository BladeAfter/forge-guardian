-- Single source of truth for "when can this player attack the global boss again".
CREATE OR REPLACE FUNCTION public.boss_heroes_revive_at(p_user uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT min(s.revive_at)
    FROM public.hero_combat_state s
    JOIN public.boss_combats bc ON bc.id = s.combat_id
   WHERE bc.user_id = p_user
     AND bc.status = 'active'
     AND s.slot IS NOT NULL
     AND NOT s.is_alive
     AND s.revive_at IS NOT NULL
     AND s.revive_at > now()
$$;

REVOKE ALL ON FUNCTION public.boss_heroes_revive_at(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.boss_heroes_revive_at(uuid) TO service_role;

-- NEXT ATTACK = MAX(cooldown_end, heroes_revive_at). Never a fresh cooldown after revive.
CREATE OR REPLACE FUNCTION public.boss_auto_next_attack_at(p_user uuid, p_cooldown_end timestamptz)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT GREATEST(coalesce(p_cooldown_end, now()), coalesce(public.boss_heroes_revive_at(p_user), coalesce(p_cooldown_end, now())))
$$;

REVOKE ALL ON FUNCTION public.boss_auto_next_attack_at(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.boss_auto_next_attack_at(uuid, timestamptz) TO service_role;

-- ============================ GLOBAL BOSS ============================
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
      -- Retry as soon as the real blocker clears (revive), never a new full cooldown.
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
    INSERT INTO public.global_boss_attack_log(user_id, telegram_id, boss_id, cycle_id, attack_type, damage, team_power, pass_type)
      VALUES (r.user_id, r.telegram_id, cyc.boss_template_id, cyc.id, 'season_pass_auto', v_dmg, coalesce(v_power,0), v_tier);
    -- MAX(cooldown_end, revive_at): dead heroes only wait the official revive timer.
    v_next := public.boss_auto_next_attack_at(r.user_id, now() + interval '300 seconds');
    UPDATE public.global_boss_auto_attack SET last_auto_attack_at = now(),
      next_auto_attack_at = v_next, attacks_total = attacks_total + 1,
      paused_reason = NULL, updated_at = now() WHERE user_id = r.user_id;
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('processed', v_count, 'cycleId', cyc.id);
END $function$;

CREATE OR REPLACE FUNCTION public.attack_boss(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b public.boss_templates; v_result jsonb; u uuid; cyc uuid; v_before numeric; v_after numeric; v_power numeric;
BEGIN
  b := public.active_boss_template();
  IF b.code IS NULL THEN RAISE EXCEPTION 'BOSS_NOT_ACTIVE'; END IF;
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF NOT EXISTS (SELECT 1 FROM public.boss_team_slots ts WHERE ts.user_id = u) THEN
    RAISE EXCEPTION 'BOSS_TEAM_EMPTY';
  END IF;
  SELECT id INTO cyc FROM public.global_boss_cycles WHERE status = 'active' ORDER BY created_at DESC LIMIT 1;
  SELECT coalesce(damage_total,0) INTO v_before FROM public.global_boss_participants
    WHERE boss_cycle_id = cyc AND user_id = u;
  v_result := public.process_boss_combat(p_telegram_id);
  SELECT coalesce(damage_total,0) INTO v_after FROM public.global_boss_participants
    WHERE boss_cycle_id = cyc AND user_id = u;
  SELECT coalesce(sum(s.final_atk),0) INTO v_power FROM public.hero_combat_state s
    JOIN public.boss_combats bc ON bc.id = s.combat_id
    WHERE bc.user_id = u AND s.slot IS NOT NULL;
  INSERT INTO public.global_boss_attack_log(user_id, telegram_id, boss_id, cycle_id, attack_type, damage, team_power, pass_type)
    VALUES (u, p_telegram_id, b.id, cyc, 'manual', greatest(0, coalesce(v_after,0) - coalesce(v_before,0)),
            coalesce(v_power,0), public.global_boss_auto_pass_tier(u));
  -- shared cooldown: MAX(cooldown_end, revive_at) so a revive never stacks a new cooldown
  UPDATE public.global_boss_auto_attack SET last_auto_attack_at = now(),
    next_auto_attack_at = public.boss_auto_next_attack_at(u, now() + interval '300 seconds'),
    updated_at = now() WHERE user_id = u;
  PERFORM public.record_quest_event_for_telegram(p_telegram_id, 'boss_attack', 1);
  RETURN v_result;
END $function$;

CREATE OR REPLACE FUNCTION public.global_boss_auto_attack_state_json(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE a public.global_boss_auto_attack%rowtype; v_tier text; v_team boolean; v_reason text;
        v_revive timestamptz; v_next timestamptz;
BEGIN
  IF p_user IS NULL THEN RETURN jsonb_build_object('eligible',false,'enabled',false,'active',false,'reason','no_pass'); END IF;
  INSERT INTO public.global_boss_auto_attack(user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO a FROM public.global_boss_auto_attack WHERE user_id = p_user;
  v_tier := public.global_boss_auto_pass_tier(p_user);
  v_team := EXISTS (SELECT 1 FROM public.boss_team_slots WHERE user_id = p_user);
  v_revive := public.boss_heroes_revive_at(p_user);
  v_next := GREATEST(a.next_auto_attack_at, coalesce(v_revive, a.next_auto_attack_at));
  v_reason := CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN NOT a.enabled THEN 'disabled'
                   WHEN NOT v_team THEN 'no_team' ELSE NULL END;
  RETURN jsonb_build_object(
    'eligible', v_tier IS NOT NULL, 'passTier', v_tier, 'enabled', a.enabled,
    'hasTeam', v_team, 'active', v_tier IS NOT NULL AND a.enabled AND v_team,
    'intervalSeconds', 300, 'lastAttackAt', a.last_auto_attack_at,
    'nextAttackAt', v_next, 'nextAutoAttackAt', v_next,
    'revivesAt', v_revive, 'waitingRevive', v_revive IS NOT NULL AND v_revive >= a.next_auto_attack_at,
    'blockedBy', CASE WHEN v_revive IS NOT NULL AND v_revive >= a.next_auto_attack_at THEN 'revive'
                      WHEN a.next_auto_attack_at > now() THEN 'cooldown' ELSE NULL END,
    'attacksTotal', a.attacks_total, 'reason', v_reason);
END $function$;

-- ============================ CLAN BOSS ============================
CREATE OR REPLACE FUNCTION public.process_clan_boss_auto_attacks(p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; r record; v_tier text; v_count int := 0; v_paused int := 0;
        v_retry timestamptz; v_last timestamptz;
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

CREATE OR REPLACE FUNCTION public.clan_boss_auto_attack_state_json(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE a public.clan_boss_auto_attack%rowtype; cfg public.clan_boss_config;
        v_tier text; v_team boolean; v_clan uuid; v_boss boolean; v_reason text;
        v_revive timestamptz; v_next timestamptz;
BEGIN
  IF p_user IS NULL THEN RETURN jsonb_build_object('eligible',false,'enabled',false,'active',false,'reason','no_pass'); END IF;
  cfg := public.clan_boss_cfg();
  INSERT INTO public.clan_boss_auto_attack(user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO a FROM public.clan_boss_auto_attack WHERE user_id = p_user;
  v_tier := public.global_boss_auto_pass_tier(p_user);
  v_team := public.clan_player_power(p_user) > 0;
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = p_user;
  v_boss := v_clan IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.clan_boss_instances
     WHERE clan_id = v_clan AND status = 'active' AND current_hp > 0 AND ends_at > now());
  v_revive := public.boss_heroes_revive_at(p_user);
  v_next := GREATEST(a.next_auto_attack_at, coalesce(v_revive, a.next_auto_attack_at));
  v_reason := CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN NOT a.enabled THEN 'disabled'
                   WHEN v_clan IS NULL THEN 'no_clan' WHEN NOT v_team THEN 'no_team'
                   WHEN NOT v_boss THEN 'no_boss' ELSE NULL END;
  RETURN jsonb_build_object(
    'eligible', v_tier IS NOT NULL, 'passTier', v_tier, 'enabled', a.enabled,
    'hasTeam', v_team, 'inClan', v_clan IS NOT NULL, 'bossActive', v_boss,
    'active', v_tier IS NOT NULL AND a.enabled AND v_team AND v_clan IS NOT NULL AND v_boss,
    'intervalSeconds', GREATEST(1, cfg.cooldown_seconds),
    'lastAttackAt', a.last_auto_attack_at,
    'nextAttackAt', v_next, 'nextAutoAttackAt', v_next,
    'revivesAt', v_revive, 'waitingRevive', v_revive IS NOT NULL AND v_revive >= a.next_auto_attack_at,
    'blockedBy', CASE WHEN v_revive IS NOT NULL AND v_revive >= a.next_auto_attack_at THEN 'revive'
                      WHEN a.next_auto_attack_at > now() THEN 'cooldown' ELSE NULL END,
    'attacksTotal', a.attacks_total, 'reason', v_reason);
END $function$;