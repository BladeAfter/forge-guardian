-- 0039b: spawn snapshot + 24h cycle lock + DEF in combat + calibration hooks
CREATE OR REPLACE FUNCTION public.clan_boss_ensure(p_clan_id uuid)
RETURNS public.clan_boss_instances
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE cfg public.clan_boss_config; sc public.clan_boss_scaling_config;
        b public.clan_boss_instances; tpl public.clan_boss_templates;
        v_cycle integer; v_level integer; v_rewards jsonb; s jsonb; v_hp numeric;
        v_key text; v_name text; v_dur integer;
BEGIN
  cfg := public.clan_boss_cfg();
  sc := public.clan_boss_scaling_cfg();

  SELECT * INTO b FROM public.clan_boss_instances
   WHERE clan_id = p_clan_id AND status = 'active' LIMIT 1;
  IF b.id IS NOT NULL AND b.ends_at <= now() THEN
    PERFORM public.clan_boss_settle(b.id, 'expired');
    b := NULL;
  END IF;
  IF b.id IS NOT NULL THEN RETURN b; END IF;

  -- 24h CYCLE LOCK: at most one rewarding Clan Boss per clan per cycle.
  IF (public.clan_boss_cycle_lock(p_clan_id)->>'locked')::boolean THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(MAX(cycle), 0) + 1 INTO v_cycle FROM public.clan_boss_instances WHERE clan_id = p_clan_id;
  SELECT GREATEST(1, level) INTO v_level FROM public.clans WHERE id = p_clan_id;
  tpl := public.clan_boss_template_for_cycle(v_cycle);
  s := public.clan_boss_scaling_persist(p_clan_id);
  v_hp := GREATEST(1, (s->>'effectiveHp')::numeric);
  v_dur := GREATEST(1, COALESCE(sc.cycle_hours, 24));
  v_key := COALESCE(tpl.boss_key, cfg.boss_key);
  v_name := COALESCE(tpl.name, cfg.boss_name);
  v_rewards := COALESCE(cfg.rewards, '{}'::jsonb);
  IF tpl.id IS NOT NULL THEN
    v_rewards := v_rewards || jsonb_build_object('fcPool', tpl.reward_fc, 'clanXp', tpl.reward_clan_xp,
      'bossKey', tpl.boss_key, 'theme', tpl.theme, 'baseDamage', tpl.base_damage);
  END IF;

  INSERT INTO public.clan_boss_instances(
    clan_id, boss_key, boss_name, cycle, level, max_hp, current_hp,
    min_damage_required, rewards_snapshot, starts_at, ends_at,
    base_hp, hp_multiplier, def_multiplier, atk_multiplier,
    boss_def, boss_atk, boss_power,
    clan_power_snapshot, active_members_snapshot, historical_dps_snapshot,
    scaling_snapshot, scaling_version, target_duration_seconds,
    cycle_started_at, cycle_ends_at)
  VALUES (p_clan_id, v_key, v_name, v_cycle, COALESCE(v_level, 1), v_hp, v_hp,
    round(v_hp * cfg.min_damage_pct / 100.0), v_rewards, now(),
    now() + make_interval(hours => v_dur),
    (s->>'baseHp')::numeric, (s->>'hpMultiplier')::numeric,
    (s->>'defMultiplier')::numeric, (s->>'atkMultiplier')::numeric,
    (s->>'effectiveDef')::numeric, (s->>'effectiveAtk')::numeric, (s->>'bossPower')::numeric,
    (s->'dps'->'metrics'->>'clanPower')::numeric,
    (s->'dps'->'metrics'->>'active24h')::int,
    (s->'dps'->>'dps')::numeric,
    s, (s->>'scalingVersion')::int, (s->>'targetDurationSeconds')::int,
    now(), now() + make_interval(hours => v_dur))
  RETURNING * INTO b;

  RETURN b;
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_ensure(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_settle(p_instance_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE cfg public.clan_boss_config; b public.clan_boss_instances; r record; snap jsonb;
        v_min numeric; v_pool numeric; v_share numeric; v_reward jsonb; v_top uuid; v_xp integer;
BEGIN
  cfg := public.clan_boss_cfg();
  SELECT * INTO b FROM public.clan_boss_instances WHERE id = p_instance_id FOR UPDATE;
  IF b.id IS NULL OR b.status <> 'active' THEN RETURN; END IF;
  snap := COALESCE(b.rewards_snapshot, cfg.rewards, '{}'::jsonb);

  SELECT user_id INTO v_top FROM public.clan_boss_damage WHERE instance_id = b.id ORDER BY damage DESC LIMIT 1;
  v_min := GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0));
  v_pool := CASE WHEN p_status = 'defeated' THEN COALESCE((snap->>'fcPool')::numeric, 0) ELSE 0 END;
  v_xp := CASE WHEN p_status = 'defeated'
            THEN GREATEST(0, COALESCE((snap->>'clanXp')::integer, cfg.clan_xp_reward)) ELSE 0 END;

  UPDATE public.clan_boss_instances
     SET status = p_status, finished_at = now(), top_user_id = v_top,
         min_damage_required = v_min, clan_xp_awarded = v_xp,
         rewards_snapshot = snap,
         total_damage = COALESCE((SELECT SUM(damage) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
         participants = COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0)
   WHERE id = b.id;

  IF p_status = 'defeated' THEN
    FOR r IN
      SELECT d.user_id, d.damage FROM public.clan_boss_damage d
       WHERE d.instance_id = b.id AND d.damage >= v_min
         AND COALESCE(d.eligibility_status, 'ELIGIBLE') = 'ELIGIBLE'
         AND NOT EXISTS (SELECT 1 FROM public.clan_boss_player_locks l
                          WHERE l.user_id = d.user_id AND l.locked_until > now() AND l.clan_id <> b.clan_id)
    LOOP
      v_share := CASE WHEN b.max_hp > 0 THEN r.damage / b.max_hp ELSE 0 END;
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((snap->'participant'->>'fc')::numeric, 0) + v_pool * v_share),
        'fragments', COALESCE((snap->'participant'->>'fragments')::int, 0),
        'petFood', COALESCE((snap->'participant'->>'petFood')::int, 0),
        'chests', COALESCE((snap->'participant'->>'chests')::int, 0),
        'pvpTickets', COALESCE((snap->'participant'->>'pvpTickets')::int, 0)
      );
      IF r.user_id = v_top THEN
        v_reward := jsonb_build_object(
          'fc', COALESCE((v_reward->>'fc')::numeric,0) + COALESCE((snap->'topDamage'->>'fc')::numeric, 0),
          'fragments', COALESCE((v_reward->>'fragments')::int,0) + COALESCE((snap->'topDamage'->>'fragments')::int, 0),
          'petFood', COALESCE((v_reward->>'petFood')::int,0) + COALESCE((snap->'topDamage'->>'petFood')::int, 0),
          'chests', COALESCE((v_reward->>'chests')::int,0) + COALESCE((snap->'topDamage'->>'chests')::int, 0),
          'pvpTickets', COALESCE((v_reward->>'pvpTickets')::int,0) + COALESCE((snap->'topDamage'->>'pvpTickets')::int, 0)
        );
      END IF;
      INSERT INTO public.clan_boss_claims(instance_id, clan_id, user_id, damage, payload)
      VALUES (b.id, b.clan_id, r.user_id, r.damage, v_reward)
      ON CONFLICT (instance_id, user_id) DO NOTHING;
      IF found THEN
        PERFORM public.clan_boss_deliver(r.user_id, v_reward);
        IF v_xp > 0 THEN PERFORM public.grant_clan_xp(r.user_id, 'clan_boss_cycle', v_xp); END IF;
      END IF;
    END LOOP;
  END IF;

  -- Auto-calibration input for the NEXT boss (never changes this one).
  PERFORM public.clan_boss_record_performance(b.id, p_status);
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_settle(uuid, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_strike(p_telegram_id bigint, p_instance_id uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; b public.clan_boss_instances;
        v_last timestamptz; v_damage numeric; v_raw numeric; v_base numeric; v_power numeric;
        v_bonus numeric; v_buffs jsonb; v_lock jsonb;
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

  IF b.id IS NULL THEN
    v_lock := public.clan_boss_cycle_lock(v_clan);
    RAISE EXCEPTION 'CLAN_BOSS_CYCLE_LOCKED'
      USING DETAIL = COALESCE(v_lock->>'secondsRemaining', '0'),
            HINT = 'next_boss_in_seconds=' || COALESCE(v_lock->>'secondsRemaining', '0');
  END IF;

  IF p_instance_id IS NOT NULL AND p_instance_id <> b.id THEN
    IF EXISTS (SELECT 1 FROM public.clan_boss_instances WHERE id = p_instance_id AND clan_id <> v_clan)
      THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
    RAISE EXCEPTION 'CLAN_BOSS_STALE';
  END IF;

  SELECT * INTO b FROM public.clan_boss_instances WHERE id = b.id FOR UPDATE;
  IF b.clan_id <> v_clan THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
  IF b.status <> 'active' OR b.current_hp <= 0 THEN RAISE EXCEPTION 'CLAN_BOSS_DEFEATED'; END IF;
  IF b.ends_at <= now() THEN RAISE EXCEPTION 'CLAN_BOSS_EXPIRED'; END IF;

  PERFORM public.clan_boss_lock_acquire(v_uid, v_clan, b.id, NULL, b.ends_at);

  SELECT last_attack_at INTO v_last FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid FOR UPDATE;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => GREATEST(1, cfg.cooldown_seconds)) THEN
    RAISE EXCEPTION 'CLAN_BOSS_COOLDOWN';
  END IF;

  v_buffs := COALESCE(public.get_pet_bonuses(v_uid), '{}'::jsonb);
  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_bonus := COALESCE((v_buffs->>'boss_damage_percent')::numeric, 0)
           + COALESCE((v_buffs->>'team_attack_percent')::numeric, 0)
           + public.pet_hp_bonus_percent(v_buffs) * 0.25;
  v_base := GREATEST(100, round(v_power * (0.85 + random() * 0.3)));
  v_raw := GREATEST(100, round(v_base * (1 + v_bonus / 100.0)));
  IF random() < LEAST(0.35, COALESCE((v_buffs->>'critical_chance_percent')::numeric, 0) / 100.0) THEN
    v_crit := true;
    v_raw := round(v_raw * (1.5 + COALESCE((v_buffs->>'critical_damage_percent')::numeric, 0) / 100.0));
  END IF;
  -- Boss DEF (locked at spawn) mitigates part of the damage, with a floor so no
  -- attack ever lands for 0/1 damage.
  v_damage := public.clan_boss_apply_def(v_raw, b.boss_def, v_power);
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
        eligibility_status = 'ELIGIBLE',
        last_attack_at = now();

  UPDATE public.clan_boss_instances
     SET participants = COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0)
   WHERE id = b.id;

  INSERT INTO public.clan_boss_attack_log(user_id, telegram_id, clan_id, clan_boss_id, attack_type, damage, team_power, pass_type)
  VALUES (v_uid, p_telegram_id, v_clan, b.id, v_type, v_damage, v_power, public.global_boss_auto_pass_tier(v_uid));

  UPDATE public.clan_boss_auto_attack
     SET last_auto_attack_at = CASE WHEN v_type = 'season_pass_auto' THEN now() ELSE last_auto_attack_at END,
         next_auto_attack_at = now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)),
         attacks_total = attacks_total + CASE WHEN v_type = 'season_pass_auto' THEN 1 ELSE 0 END,
         paused_reason = NULL, updated_at = now()
   WHERE user_id = v_uid;

  IF b.current_hp <= 0 THEN
    v_defeated := true;
    PERFORM public.clan_boss_settle(b.id, 'defeated');
    -- No immediate rewarding respawn: the 24h cycle lock decides.
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_boss_damage', v_damage::bigint);

  RETURN jsonb_build_object('status','ok', 'damage', v_damage, 'critical', v_crit,
    'currentHp', GREATEST(0, b.current_hp), 'maxHp', b.max_hp, 'defeated', v_defeated,
    'rawDamage', v_raw, 'bossDef', b.boss_def,
    'damageBeforePet', v_base, 'petBossDamagePercent', v_bonus, 'attackType', v_type,
    'nextAttackAt', now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)));
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_strike(bigint, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_clan_boss(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; c public.clans%rowtype;
        b public.clan_boss_instances; d public.clan_boss_damage; v_rank integer; v_next timestamptz;
        tpl public.clan_boss_templates; v_total integer; v_last integer; v_lock jsonb;
        v_prev public.clan_boss_instances;
BEGIN
  cfg := public.clan_boss_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  SELECT count(*)::int, COALESCE(MAX(cycle_number),0) INTO v_total, v_last
    FROM public.clan_boss_templates WHERE enabled;
  IF v_clan IS NULL THEN
    RETURN jsonb_build_object('inClan', false, 'bossName', cfg.boss_name, 'bossKey', cfg.boss_key,
      'totalBosses', v_total, 'autoAttack', public.clan_boss_auto_attack_state_json(v_uid), 'serverTime', now());
  END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;
  b := public.clan_boss_ensure(v_clan);

  IF b.id IS NULL THEN
    v_lock := public.clan_boss_cycle_lock(v_clan);
    SELECT * INTO v_prev FROM public.clan_boss_instances
     WHERE clan_id = v_clan ORDER BY starts_at DESC LIMIT 1;
    RETURN jsonb_build_object(
      'inClan', true, 'totalBosses', v_total,
      'autoAttack', public.clan_boss_auto_attack_state_json(v_uid),
      'clan', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'level', c.level, 'emblem', c.emblem_config),
      'cycleLocked', true,
      'nextBossAt', v_lock->>'nextBossAt',
      'nextBossInSeconds', COALESCE((v_lock->>'secondsRemaining')::int, 0),
      'lastBoss', CASE WHEN v_prev.id IS NULL THEN NULL ELSE jsonb_build_object(
        'name', v_prev.boss_name, 'cycle', v_prev.cycle, 'status', v_prev.status,
        'maxHp', v_prev.max_hp, 'totalDamage', v_prev.total_damage,
        'bossPower', v_prev.boss_power, 'finishedAt', v_prev.finished_at,
        'durationSeconds', v_prev.actual_duration_seconds) END,
      'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'cycle', h.cycle, 'status', h.status, 'maxHp', h.max_hp, 'totalDamage', h.total_damage,
          'bossName', h.boss_name, 'bossKey', h.boss_key, 'clanXp', h.clan_xp_awarded,
          'finishedAt', h.finished_at) ORDER BY h.cycle DESC)
        FROM public.clan_boss_instances h WHERE h.clan_id = v_clan AND h.status <> 'active'), '[]'::jsonb),
      'serverTime', now());
  END IF;

  tpl := public.clan_boss_template_for_cycle(b.cycle);
  SELECT * INTO d FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid;
  SELECT count(*) + 1 INTO v_rank FROM public.clan_boss_damage
   WHERE instance_id = b.id AND damage > COALESCE(d.damage, 0);
  v_next := COALESCE(d.last_attack_at, to_timestamp(0)) + make_interval(secs => GREATEST(1, cfg.cooldown_seconds));

  RETURN jsonb_build_object(
    'inClan', true,
    'totalBosses', v_total,
    'cycleLocked', false,
    'autoAttack', public.clan_boss_auto_attack_state_json(v_uid),
    'clan', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'level', c.level, 'emblem', c.emblem_config),
    'boss', jsonb_build_object(
      'id', b.id, 'key', b.boss_key, 'name', b.boss_name, 'cycle', b.cycle, 'level', b.level,
      'maxHp', b.max_hp, 'currentHp', b.current_hp, 'status', b.status,
      'startsAt', b.starts_at, 'endsAt', b.ends_at,
      'cycleEndsAt', b.cycle_ends_at,
      'def', b.boss_def, 'atk', b.boss_atk, 'power', b.boss_power,
      'subtitle', COALESCE(tpl.subtitle, ''),
      'theme', COALESCE(tpl.theme, 'abyss'),
      'imageUrl', tpl.image_url,
      'backgroundUrl', tpl.background_url,
      'baseDamage', COALESCE(tpl.base_damage, 0),
      'rewardFc', COALESCE(tpl.reward_fc, 0),
      'bossNumber', COALESCE(tpl.cycle_number, b.cycle),
      'isFinal', COALESCE(tpl.cycle_number, 0) >= v_last,
      'clanDamage', COALESCE((SELECT SUM(damage) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'attacks', COALESCE((SELECT SUM(attacks) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'participants', COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0),
      'minDamageForRewards', GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'clanXpReward', COALESCE((b.rewards_snapshot->>'clanXp')::integer, cfg.clan_xp_reward),
      'cooldownSeconds', cfg.cooldown_seconds
    ),
    'me', jsonb_build_object(
      'damage', COALESCE(d.damage, 0), 'attacks', COALESCE(d.attacks, 0),
      'rank', CASE WHEN COALESCE(d.damage,0) > 0 THEN v_rank ELSE NULL END,
      'nextAttackAt', CASE WHEN d.last_attack_at IS NULL THEN NULL ELSE v_next END,
      'canAttack', b.status = 'active' AND b.current_hp > 0 AND (d.last_attack_at IS NULL OR v_next <= now()),
      'eligibleForRewards', COALESCE(d.damage,0) >= GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'power', public.clan_player_power(v_uid)
    ),
    'ranking', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'damage')::numeric DESC) FROM (
        SELECT jsonb_build_object('userId', dd.user_id,
          'name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'username', g.username, 'avatar', g.avatar_url,
          'damage', dd.damage, 'attacks', dd.attacks, 'isMe', dd.user_id = v_uid) x
        FROM public.clan_boss_damage dd JOIN public.game_players g ON g.id = dd.user_id
        WHERE dd.instance_id = b.id ORDER BY dd.damage DESC LIMIT 50) s), '[]'::jsonb),
    'rewards', COALESCE(b.rewards_snapshot, cfg.rewards),
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'cycle', h.cycle, 'status', h.status, 'maxHp', h.max_hp, 'totalDamage', h.total_damage,
        'bossName', h.boss_name, 'bossKey', h.boss_key,
        'clanXp', h.clan_xp_awarded, 'finishedAt', h.finished_at,
        'topName', COALESCE(tg.display_name, tg.username, NULL),
        'topDamage', (SELECT MAX(damage) FROM public.clan_boss_damage cd WHERE cd.instance_id = h.id)) ORDER BY h.cycle DESC)
      FROM public.clan_boss_instances h LEFT JOIN public.game_players tg ON tg.id = h.top_user_id
      WHERE h.clan_id = v_clan AND h.status <> 'active'), '[]'::jsonb),
    'serverTime', now()
  );
END $fn$;
REVOKE ALL ON FUNCTION public.get_clan_boss(bigint) FROM PUBLIC, anon, authenticated;