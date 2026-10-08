-- =====================================================================
-- CLAN RAID V2 — collective boss, clan-adaptive HP, 5-day target,
-- 7-day deadline, 5 health gates, catch-up and auto calibration.
-- Personal Clan Boss / Global Boss / PvP / Tower / Familiar Hunt untouched.
-- =====================================================================

-- 1) SETTINGS ---------------------------------------------------------
ALTER TABLE public.clan_collective_settings
  ADD COLUMN IF NOT EXISTS raid_target_kill_days integer NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS raid_deadline_days integer NOT NULL DEFAULT 7,
  ADD COLUMN IF NOT EXISTS raid_health_gates_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS raid_safety_factor numeric NOT NULL DEFAULT 0.95,
  ADD COLUMN IF NOT EXISTS raid_dps_weight_24h numeric NOT NULL DEFAULT 0.50,
  ADD COLUMN IF NOT EXISTS raid_dps_weight_3d numeric NOT NULL DEFAULT 0.30,
  ADD COLUMN IF NOT EXISTS raid_dps_weight_7d numeric NOT NULL DEFAULT 0.20,
  ADD COLUMN IF NOT EXISTS raid_max_hp_increase_pct numeric NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS raid_max_hp_decrease_pct numeric NOT NULL DEFAULT 25,
  ADD COLUMN IF NOT EXISTS raid_catchup_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS raid_catchup_max_pct numeric NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS raid_full_kill_required boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS raid_boss_name text NOT NULL DEFAULT 'Abyssal Devourer';

UPDATE public.clan_collective_settings SET raid_duration_days = 7 WHERE raid_duration_days IS DISTINCT FROM 7;

-- 2) CYCLE SNAPSHOT + PACING -----------------------------------------
ALTER TABLE public.clan_raid_cycles
  ADD COLUMN IF NOT EXISTS clan_power_snapshot numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS active_members_snapshot integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS effective_dps_snapshot numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS target_days integer NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS deadline_days integer NOT NULL DEFAULT 7,
  ADD COLUMN IF NOT EXISTS gates_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS boss_tier text NOT NULL DEFAULT 'ABYSSAL',
  ADD COLUMN IF NOT EXISTS performance_class text,
  ADD COLUMN IF NOT EXISTS cleared_in_hours numeric,
  ADD COLUMN IF NOT EXISTS catchup_pct numeric NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.clan_raid_performance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL,
  raid_id uuid NOT NULL,
  max_hp numeric NOT NULL,
  damage_done numeric NOT NULL,
  target_days integer NOT NULL,
  cleared_in_hours numeric,
  status text NOT NULL,
  performance_class text NOT NULL,
  effective_dps numeric NOT NULL,
  suggested_next_hp numeric NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_raid_performance TO service_role;
ALTER TABLE public.clan_raid_performance ENABLE ROW LEVEL SECURITY;
CREATE POLICY "raid performance service only" ON public.clan_raid_performance
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- idempotency for attacks
ALTER TABLE public.clan_raid_attacks
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS phase integer NOT NULL DEFAULT 1;
CREATE UNIQUE INDEX IF NOT EXISTS clan_raid_attacks_idem
  ON public.clan_raid_attacks(raid_id, user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- 3) HELPERS ----------------------------------------------------------

-- Raid day 1..N since spawn, server clock only.
CREATE OR REPLACE FUNCTION public.clan_raid_day(p_started timestamptz)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT GREATEST(1, floor(EXTRACT(epoch FROM (now() - p_started)) / 86400)::int + 1);
$$;

-- Effective daily raid damage for a clan (weighted history, exploit-free rows only).
CREATE OR REPLACE FUNCTION public.clan_raid_effective_dps(p_clan uuid)
RETURNS numeric LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings;
        d24 numeric; d3 numeric; d7 numeric; v_dps numeric;
        v_power numeric; v_active integer; v_members integer;
BEGIN
  cfg := public.clan_collective_cfg();

  SELECT COALESCE(sum(damage),0) INTO d24 FROM public.clan_raid_attacks
   WHERE clan_id = p_clan AND created_at > now() - interval '24 hours' AND damage > 0;
  SELECT COALESCE(sum(damage),0)/3.0 INTO d3 FROM public.clan_raid_attacks
   WHERE clan_id = p_clan AND created_at > now() - interval '3 days' AND damage > 0;
  SELECT COALESCE(sum(damage),0)/7.0 INTO d7 FROM public.clan_raid_attacks
   WHERE clan_id = p_clan AND created_at > now() - interval '7 days' AND damage > 0;

  v_dps := d24 * cfg.raid_dps_weight_24h + d3 * cfg.raid_dps_weight_3d + d7 * cfg.raid_dps_weight_7d;

  -- No usable history: estimate from clan power / active roster.
  IF v_dps <= 0 THEN
    SELECT COALESCE(sum(public.clan_player_power(m.user_id)),0), count(*)
      INTO v_power, v_members FROM public.clan_members m WHERE m.clan_id = p_clan;
    v_active := GREATEST(1, public.clan_active_members(p_clan));
    -- avg member power * active members * attacks/day * 35 (avg attack multiplier)
    v_dps := (v_power / GREATEST(1, v_members)) * v_active * GREATEST(1, cfg.raid_attacks_per_day) * 35;
  END IF;

  RETURN GREATEST(1, v_dps);
END $$;

-- Damage already dealt on the current raid day.
CREATE OR REPLACE FUNCTION public.clan_raid_damage_today(p_raid uuid)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE(sum(damage),0) FROM public.clan_raid_attacks
   WHERE raid_id = p_raid AND attack_day = public.game_day_key();
$$;

-- HP floor available on the current day: max_hp * (1 - day*0.2), clamped at 0 on day >= target.
CREATE OR REPLACE FUNCTION public.clan_raid_phase_floor(r public.clan_raid_cycles)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN NOT r.gates_enabled THEN 0
    WHEN public.clan_raid_day(r.started_at) >= r.target_days THEN 0
    ELSE GREATEST(0, r.max_hp * (1 - (public.clan_raid_day(r.started_at) * (1.0 / r.target_days))))
  END;
$$;

-- Catch-up damage bonus, only from target day onwards.
CREATE OR REPLACE FUNCTION public.clan_raid_catchup_pct(r public.clan_raid_cycles)
RETURNS numeric LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_day integer; v_remaining numeric; v_expected numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  IF NOT cfg.raid_catchup_enabled THEN RETURN 0; END IF;
  v_day := public.clan_raid_day(r.started_at);
  IF v_day < r.target_days THEN RETURN 0; END IF;
  v_remaining := CASE WHEN r.max_hp > 0 THEN r.current_hp / r.max_hp ELSE 0 END;
  v_expected := 0.20; -- at target day the boss should be near death
  IF v_remaining <= v_expected THEN RETURN 0; END IF;
  RETURN LEAST(cfg.raid_catchup_max_pct, round(((v_remaining - v_expected) * 100) / 2.5) * 5);
END $$;

-- 4) SPAWN WITH LOCKED SNAPSHOT + CALIBRATION -------------------------
CREATE OR REPLACE FUNCTION public.clan_raid_ensure(p_clan uuid)
RETURNS public.clan_raid_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; r public.clan_raid_cycles;
        v_key date; v_power numeric; v_hp numeric; v_dps numeric;
        v_active integer; prev public.clan_raid_performance;
BEGIN
  cfg := public.clan_collective_cfg();
  v_key := public.clan_week_key();

  -- close expired raids (deadline reached with HP left)
  UPDATE public.clan_raid_cycles SET status = 'EXPIRED', updated_at = now()
   WHERE clan_id = p_clan AND status = 'ACTIVE' AND ends_at < now();

  SELECT * INTO r FROM public.clan_raid_cycles WHERE clan_id = p_clan AND raid_key = v_key;
  IF r.id IS NOT NULL OR NOT cfg.raid_enabled THEN RETURN r; END IF;

  SELECT COALESCE(sum(public.clan_player_power(m.user_id)), 0) INTO v_power
    FROM public.clan_members m WHERE m.clan_id = p_clan;
  v_active := public.clan_active_members(p_clan);
  v_dps := public.clan_raid_effective_dps(p_clan);

  -- target_hp = effective daily damage * target days * safety factor
  v_hp := round(v_dps * cfg.raid_target_kill_days * cfg.raid_safety_factor);

  -- controlled recalibration against the last raid (base stats, never compounding current HP)
  SELECT * INTO prev FROM public.clan_raid_performance
   WHERE clan_id = p_clan ORDER BY created_at DESC LIMIT 1;
  IF prev.id IS NOT NULL AND prev.max_hp > 0 THEN
    v_hp := LEAST(v_hp, prev.max_hp * (1 + cfg.raid_max_hp_increase_pct / 100.0));
    v_hp := GREATEST(v_hp, prev.max_hp * (1 - cfg.raid_max_hp_decrease_pct / 100.0));
  END IF;

  v_hp := LEAST(cfg.raid_hp_max, GREATEST(cfg.raid_hp_min, v_hp));

  INSERT INTO public.clan_raid_cycles(clan_id, raid_key, boss_name, max_hp, current_hp,
      boss_atk, boss_def, rewards_snapshot, ends_at,
      clan_power_snapshot, active_members_snapshot, effective_dps_snapshot,
      target_days, deadline_days, gates_enabled)
  VALUES (p_clan, v_key, cfg.raid_boss_name, v_hp, v_hp,
          round(v_power * 0.02), round(v_power * 0.005), cfg.raid_rewards,
          now() + make_interval(days => cfg.raid_deadline_days),
          v_power, v_active, v_dps,
          cfg.raid_target_kill_days, cfg.raid_deadline_days, cfg.raid_health_gates_enabled)
  ON CONFLICT (clan_id, raid_key) DO UPDATE SET updated_at = now()
  RETURNING * INTO r;
  RETURN r;
END $$;

-- 5) ATTACK WITH PHASE LOCK + IDEMPOTENCY -----------------------------
CREATE OR REPLACE FUNCTION public.clan_raid_attack(p_telegram_id bigint, p_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_used integer; v_power numeric; v_dmg numeric; v_buff numeric; c public.clan_weekly_cycles;
        v_floor numeric; v_day integer; v_catch numeric; v_existing numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF NOT cfg.raid_enabled THEN RAISE EXCEPTION 'RAID_DISABLED'; END IF;

  -- idempotency: same request never applies damage twice
  IF p_key IS NOT NULL THEN
    SELECT damage INTO v_existing FROM public.clan_raid_attacks
     WHERE user_id = v_uid AND idempotency_key = p_key LIMIT 1;
    IF v_existing IS NOT NULL THEN
      RETURN jsonb_build_object('status','duplicate','damage', v_existing);
    END IF;
  END IF;

  PERFORM public.clan_raid_ensure(v_clan);
  SELECT * INTO r FROM public.clan_raid_cycles
   WHERE clan_id = v_clan AND raid_key = public.clan_week_key() FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'ACTIVE' THEN RAISE EXCEPTION 'RAID_NOT_ACTIVE'; END IF;

  IF r.ends_at < now() THEN
    UPDATE public.clan_raid_cycles SET status = 'EXPIRED' WHERE id = r.id;
    PERFORM public.clan_raid_settle(r.id);
    RAISE EXCEPTION 'RAID_EXPIRED';
  END IF;

  v_day := public.clan_raid_day(r.started_at);
  v_floor := public.clan_raid_phase_floor(r);

  -- phase lock: no attack consumed while the daily HP gate is already reached
  IF r.current_hp <= v_floor THEN RAISE EXCEPTION 'RAID_PHASE_LOCKED'; END IF;

  SELECT count(*) INTO v_used FROM public.clan_raid_attacks
   WHERE raid_id = r.id AND user_id = v_uid AND attack_day = public.game_day_key();
  IF v_used >= cfg.raid_attacks_per_day THEN RAISE EXCEPTION 'RAID_DAILY_LIMIT'; END IF;

  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_buff := public.clan_buff_pct(v_clan, 'CLAN_RAID_DMG')
          + public.clan_upgrade_level(v_clan, 'WAR_HALL') * 0.5;
  v_catch := public.clan_raid_catchup_pct(r);
  v_dmg := round(v_power * (28 + random() * 14) * (1 + (v_buff + v_catch) / 100.0));
  -- damage is capped at the current phase floor, never wasted beyond it
  v_dmg := LEAST(v_dmg, r.current_hp - v_floor);

  INSERT INTO public.clan_raid_attacks(raid_id, clan_id, user_id, damage, idempotency_key, phase, payload)
  VALUES (r.id, v_clan, v_uid, v_dmg, p_key, LEAST(r.target_days, v_day),
          jsonb_build_object('power', v_power, 'buffPct', v_buff, 'catchupPct', v_catch));

  UPDATE public.clan_raid_cycles
     SET current_hp = GREATEST(0, current_hp - v_dmg),
         total_damage = total_damage + v_dmg,
         catchup_pct = v_catch,
         participants = (SELECT count(DISTINCT user_id) FROM public.clan_raid_attacks WHERE raid_id = r.id),
         status = CASE WHEN current_hp - v_dmg <= 0 THEN 'DEFEATED' ELSE status END,
         cleared_in_hours = CASE WHEN current_hp - v_dmg <= 0
                                 THEN EXTRACT(epoch FROM (now() - started_at)) / 3600 ELSE cleared_in_hours END,
         updated_at = now()
   WHERE id = r.id
  RETURNING * INTO r;

  c := public.clan_weekly_cycle_ensure(v_clan);
  UPDATE public.clan_weekly_member_progress SET raid_damage = raid_damage + v_dmg, updated_at = now()
   WHERE cycle_id = c.id AND user_id = v_uid;
  IF NOT FOUND THEN
    INSERT INTO public.clan_weekly_member_progress(cycle_id, user_id, clan_id, raid_damage)
    VALUES (c.id, v_uid, v_clan, v_dmg) ON CONFLICT DO NOTHING;
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_raid_damage', v_dmg::bigint);
  IF r.status = 'DEFEATED' THEN PERFORM public.clan_raid_settle(r.id); END IF;

  RETURN jsonb_build_object('status','ok','damage', v_dmg, 'bossHp', r.current_hp,
    'maxHp', r.max_hp, 'defeated', r.status <> 'ACTIVE',
    'phaseFloor', public.clan_raid_phase_floor(r), 'catchupPct', v_catch,
    'attacksLeft', GREATEST(0, cfg.raid_attacks_per_day - v_used - 1));
END $$;

-- 6) SETTLE + AUTO CALIBRATION RECORD ---------------------------------
CREATE OR REPLACE FUNCTION public.clan_raid_record_performance(p_raid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.clan_raid_cycles; cfg public.clan_collective_settings;
        v_hours numeric; v_class text; v_next numeric; v_target_hours numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid;
  IF r.id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.clan_raid_performance WHERE raid_id = p_raid) THEN RETURN; END IF;

  v_target_hours := r.target_days * 24.0;
  v_hours := COALESCE(r.cleared_in_hours, EXTRACT(epoch FROM (now() - r.started_at)) / 3600);

  v_class := CASE
    WHEN r.status <> 'DEFEATED' AND r.total_damage < r.max_hp * 0.7 THEN 'TOO_HARD'
    WHEN r.status <> 'DEFEATED' THEN 'HARD'
    WHEN v_hours <= v_target_hours * 0.85 THEN 'TOO_EASY'
    WHEN v_hours <= v_target_hours * 0.97 THEN 'EASY'
    WHEN v_hours <= v_target_hours * 1.20 THEN 'BALANCED'
    ELSE 'HARD' END;

  v_next := CASE v_class
    WHEN 'TOO_EASY' THEN r.max_hp * (1 + cfg.raid_max_hp_increase_pct / 100.0)
    WHEN 'EASY' THEN r.max_hp * 1.10
    WHEN 'BALANCED' THEN r.max_hp
    WHEN 'HARD' THEN r.max_hp * 0.90
    ELSE r.max_hp * (1 - cfg.raid_max_hp_decrease_pct / 100.0) END;

  INSERT INTO public.clan_raid_performance(clan_id, raid_id, max_hp, damage_done, target_days,
    cleared_in_hours, status, performance_class, effective_dps, suggested_next_hp)
  VALUES (r.clan_id, r.id, r.max_hp, r.total_damage, r.target_days,
          r.cleared_in_hours, r.status, v_class, r.effective_dps_snapshot, round(v_next));

  UPDATE public.clan_raid_cycles SET performance_class = v_class WHERE id = r.id;
END $$;

CREATE OR REPLACE FUNCTION public.clan_raid_settle(p_raid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.clan_raid_cycles; cfg public.clan_collective_settings; snap jsonb; v_min numeric; rec record;
        v_share numeric; v_reward jsonb; v_paid integer := 0; v_coins integer;
BEGIN
  cfg := public.clan_collective_cfg();
  SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid FOR UPDATE;
  IF r.id IS NULL OR r.settled_at IS NOT NULL THEN RETURN jsonb_build_object('status','already'); END IF;
  IF r.status NOT IN ('DEFEATED','EXPIRED') THEN RETURN jsonb_build_object('status','active'); END IF;

  snap := COALESCE(r.rewards_snapshot, '{}'::jsonb);
  v_min := r.max_hp * COALESCE((snap->>'minDamagePct')::numeric, 0.5) / 100.0;

  -- rewards do NOT scale with HP; a stronger boss only means a stronger clan.
  IF r.status = 'DEFEATED' OR NOT cfg.raid_full_kill_required THEN
    FOR rec IN
      SELECT user_id, sum(damage) AS dmg FROM public.clan_raid_attacks
       WHERE raid_id = r.id GROUP BY user_id HAVING sum(damage) >= v_min
    LOOP
      v_share := CASE WHEN r.total_damage > 0 THEN LEAST(1, rec.dmg / r.total_damage) ELSE 0 END;
      v_coins := floor(COALESCE((snap->>'coinsPool')::numeric, 0) * v_share)::int;
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((snap->>'fcPool')::numeric, 0) * v_share),
        'coins', v_coins);
      INSERT INTO public.clan_raid_rewards(raid_id, clan_id, user_id, damage, payload)
      VALUES (r.id, r.clan_id, rec.user_id, rec.dmg, v_reward)
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.clan_boss_deliver(rec.user_id, v_reward);
        IF v_coins > 0 THEN
          UPDATE public.clan_members SET clan_points = clan_points + v_coins, updated_at = now()
           WHERE user_id = rec.user_id;
        END IF;
        IF COALESCE((snap->>'clanXp')::int, 0) > 0 THEN
          PERFORM public.grant_clan_xp(rec.user_id, 'clan_raid', (snap->>'clanXp')::int);
        END IF;
        v_paid := v_paid + 1;
      END IF;
    END LOOP;
  END IF;

  PERFORM public.clan_raid_record_performance(r.id);
  UPDATE public.clan_raid_cycles SET status = 'SETTLED', settled_at = now() WHERE id = r.id;
  RETURN jsonb_build_object('status','settled','rewarded', v_paid);
END $$;

-- 7) DEDICATED RAID SCREEN STATE --------------------------------------
CREATE OR REPLACE FUNCTION public.clan_raid_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_day integer; v_floor numeric; v_used integer;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;

  PERFORM public.clan_raid_ensure(v_clan);
  SELECT * INTO r FROM public.clan_raid_cycles WHERE clan_id = v_clan AND raid_key = public.clan_week_key();
  IF r.id IS NULL THEN RETURN jsonb_build_object('inClan', true, 'raid', NULL); END IF;

  v_day := public.clan_raid_day(r.started_at);
  v_floor := public.clan_raid_phase_floor(r);
  SELECT count(*) INTO v_used FROM public.clan_raid_attacks
   WHERE raid_id = r.id AND user_id = v_uid AND attack_day = public.game_day_key();

  RETURN jsonb_build_object(
    'inClan', true,
    'raid', jsonb_build_object(
      'id', r.id, 'name', r.boss_name, 'tier', r.boss_tier, 'theme', r.boss_theme,
      'maxHp', r.max_hp, 'currentHp', r.current_hp, 'status', r.status,
      'atk', r.boss_atk, 'def', r.boss_def,
      'startedAt', r.started_at, 'endsAt', r.ends_at,
      'day', LEAST(v_day, r.deadline_days), 'deadlineDays', r.deadline_days, 'targetDays', r.target_days,
      'phase', LEAST(r.target_days, v_day), 'phases', r.target_days,
      'phaseFloor', v_floor, 'phaseLocked', r.current_hp <= v_floor AND r.status = 'ACTIVE',
      'nextPhaseAt', date_trunc('day', now()) + interval '1 day',
      'catchupPct', public.clan_raid_catchup_pct(r),
      'totalDamage', r.total_damage, 'participants', r.participants,
      'memberCount', (SELECT count(*) FROM public.clan_members WHERE clan_id = v_clan),
      'attacksPerDay', cfg.raid_attacks_per_day, 'attacksUsed', v_used,
      'myDamage', COALESCE((SELECT sum(damage) FROM public.clan_raid_attacks
                             WHERE raid_id = r.id AND user_id = v_uid), 0),
      'clearedInHours', r.cleared_in_hours,
      'ranking', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM (
          SELECT g.username, g.avatar_url AS avatar, sum(a.damage) AS damage,
                 count(*) AS attacks
            FROM public.clan_raid_attacks a JOIN public.game_players g ON g.id = a.user_id
           WHERE a.raid_id = r.id GROUP BY g.username, g.avatar_url
           ORDER BY sum(a.damage) DESC LIMIT 50) x)
    ));
END $$;

-- 8) ADMIN --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_clan_raid_settings()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT to_jsonb(c) FROM public.clan_collective_settings c LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.admin_clan_raid_set(p_field text, p_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_field NOT IN ('raid_target_kill_days','raid_deadline_days','raid_attacks_per_day',
                     'raid_safety_factor','raid_dps_weight_24h','raid_dps_weight_3d','raid_dps_weight_7d',
                     'raid_max_hp_increase_pct','raid_max_hp_decrease_pct','raid_catchup_max_pct',
                     'raid_hp_min','raid_hp_max','raid_health_gates_enabled','raid_catchup_enabled',
                     'raid_enabled','raid_full_kill_required')
  THEN RAISE EXCEPTION 'INVALID_FIELD'; END IF;

  IF p_field IN ('raid_health_gates_enabled','raid_catchup_enabled','raid_enabled','raid_full_kill_required') THEN
    EXECUTE format('UPDATE public.clan_collective_settings SET %I = $1, updated_at = now()', p_field)
      USING (p_value <> 0);
  ELSE
    EXECUTE format('UPDATE public.clan_collective_settings SET %I = $1, updated_at = now()', p_field)
      USING p_value;
  END IF;
  RETURN public.admin_clan_raid_settings();
END $$;

CREATE OR REPLACE FUNCTION public.admin_clan_raid_audit(p_clan uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.clan_raid_cycles; v_day integer; v_expected numeric; v_actual numeric;
BEGIN
  SELECT * INTO r FROM public.clan_raid_cycles
   WHERE clan_id = p_clan ORDER BY created_at DESC LIMIT 1;
  v_day := CASE WHEN r.id IS NULL THEN 0 ELSE public.clan_raid_day(r.started_at) END;
  v_expected := CASE WHEN r.id IS NULL THEN 0 ELSE LEAST(100, v_day * (100.0 / r.target_days)) END;
  v_actual := CASE WHEN COALESCE(r.max_hp,0) > 0 THEN (r.max_hp - r.current_hp) * 100.0 / r.max_hp ELSE 0 END;
  RETURN jsonb_build_object(
    'clanPower', (SELECT COALESCE(sum(public.clan_player_power(m.user_id)),0)
                    FROM public.clan_members m WHERE m.clan_id = p_clan),
    'activeMembers', public.clan_active_members(p_clan),
    'effectiveDps', public.clan_raid_effective_dps(p_clan),
    'currentHp', r.current_hp, 'maxHp', r.max_hp,
    'targetDays', r.target_days, 'deadlineDays', r.deadline_days,
    'day', v_day, 'expectedProgress', round(v_expected, 1), 'actualProgress', round(v_actual, 1),
    'status', COALESCE(r.performance_class, CASE
        WHEN r.id IS NULL THEN 'NO_RAID'
        WHEN v_actual >= v_expected * 1.15 THEN 'TOO_EASY'
        WHEN v_actual >= v_expected * 0.85 THEN 'BALANCED'
        ELSE 'HARD' END),
    'lastPerformance', (SELECT to_jsonb(p) FROM public.clan_raid_performance p
                         WHERE p.clan_id = p_clan ORDER BY p.created_at DESC LIMIT 1));
END $$;

-- 9) LOCK DOWN EXECUTION ------------------------------------------------
REVOKE ALL ON FUNCTION public.clan_raid_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_attack(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_ensure(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_settle(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_record_performance(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_effective_dps(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_phase_floor(public.clan_raid_cycles) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_catchup_pct(public.clan_raid_cycles) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_damage_today(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_day(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_clan_raid_settings() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_clan_raid_set(text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_clan_raid_audit(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.clan_raid_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_raid_attack(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_clan_raid_settings() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_clan_raid_set(text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_clan_raid_audit(uuid) TO service_role;
