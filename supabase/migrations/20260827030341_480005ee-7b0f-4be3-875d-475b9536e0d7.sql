-- 1) Remove the legacy attack function that ignored daily health gates.
DROP FUNCTION IF EXISTS public.clan_raid_attack(bigint);

-- 2) Rebase audit trail
CREATE TABLE IF NOT EXISTS public.clan_raid_rebase_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raid_id uuid NOT NULL REFERENCES public.clan_raid_cycles(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL,
  reason text NOT NULL DEFAULT 'admin_rebase',
  old_max_hp numeric NOT NULL,
  old_current_hp numeric NOT NULL,
  new_max_hp numeric NOT NULL,
  new_current_hp numeric NOT NULL,
  damage_preserved numeric NOT NULL,
  daily_capacity numeric NOT NULL,
  target_days integer NOT NULL,
  safety_factor numeric NOT NULL,
  day_index integer NOT NULL,
  unlocked_pct numeric NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_raid_rebase_audit TO service_role;
ALTER TABLE public.clan_raid_rebase_audit ENABLE ROW LEVEL SECURITY;

-- 3) Effective daily raid capacity (valid raid damage only, with bootstrap fallback)
CREATE OR REPLACE FUNCTION public.clan_raid_daily_capacity(p_clan uuid, p_raid uuid DEFAULT NULL)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE v_dps numeric; v_obs numeric := 0; v_dealt numeric; v_elapsed numeric;
        r public.clan_raid_cycles;
BEGIN
  -- weighted history: 50% last 24h, 30% 3-day avg, 20% 7-day avg (bootstrap by clan power)
  v_dps := public.clan_raid_effective_dps(p_clan);

  -- best single valid raid day over the last 7 days
  SELECT COALESCE(max(d), 0) INTO v_obs FROM (
    SELECT sum(damage) AS d FROM public.clan_raid_attacks
     WHERE clan_id = p_clan AND damage > 0 AND created_at > now() - interval '7 days'
     GROUP BY attack_day) x;

  IF p_raid IS NOT NULL THEN
    SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid;
    IF r.id IS NOT NULL THEN
      v_dealt := GREATEST(0, r.max_hp - r.current_hp);
      v_elapsed := GREATEST(1, EXTRACT(epoch FROM (now() - r.started_at)) / 86400.0);
      v_obs := GREATEST(v_obs, v_dealt, v_dealt / v_elapsed);
    END IF;
  END IF;

  RETURN GREATEST(1, v_dps, v_obs);
END $$;

-- 4) Personalised target HP: capacity * target days * safety factor (clamped by admin bounds)
CREATE OR REPLACE FUNCTION public.clan_raid_target_hp(p_clan uuid, p_raid uuid DEFAULT NULL)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_collective_settings; v_cap numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  v_cap := public.clan_raid_daily_capacity(p_clan, p_raid);
  RETURN LEAST(cfg.raid_hp_max,
           GREATEST(cfg.raid_hp_min,
             round(v_cap * GREATEST(1, cfg.raid_target_kill_days) * GREATEST(0.5, cfg.raid_safety_factor))));
END $$;

-- 5) Rebase a running raid: fix max HP, preserve every point of legitimate damage
CREATE OR REPLACE FUNCTION public.clan_raid_rebase(p_raid uuid, p_reason text DEFAULT 'admin_rebase')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_collective_settings; r public.clan_raid_cycles;
        v_dealt numeric; v_cap numeric; v_target numeric; v_min numeric; v_new numeric;
        v_day integer; v_unlocked numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'RAID_NOT_FOUND'; END IF;
  IF r.status <> 'ACTIVE' THEN
    RETURN jsonb_build_object('status', 'skipped', 'reason', 'not_active');
  END IF;

  v_dealt := GREATEST(0, r.max_hp - r.current_hp);
  v_cap := public.clan_raid_daily_capacity(r.clan_id, r.id);
  v_target := round(v_cap * GREATEST(1, r.target_days) * GREATEST(0.5, cfg.raid_safety_factor));

  v_day := LEAST(GREATEST(1, r.target_days), public.clan_raid_day(r.started_at));
  v_unlocked := CASE WHEN r.gates_enabled THEN v_day::numeric / GREATEST(1, r.target_days) ELSE 1 END;

  -- HP must be big enough for the damage already dealt to fit inside the unlocked window
  v_min := CASE WHEN v_unlocked > 0 THEN ceil(v_dealt / v_unlocked) ELSE v_dealt + 1 END;

  v_new := GREATEST(v_target, v_min, cfg.raid_hp_min, v_dealt + 1);
  v_new := LEAST(v_new, GREATEST(cfg.raid_hp_max, v_min));

  IF v_new = r.max_hp THEN
    RETURN jsonb_build_object('status', 'skipped', 'reason', 'no_change', 'maxHp', r.max_hp);
  END IF;

  INSERT INTO public.clan_raid_rebase_audit(raid_id, clan_id, reason, old_max_hp, old_current_hp,
    new_max_hp, new_current_hp, damage_preserved, daily_capacity, target_days, safety_factor,
    day_index, unlocked_pct)
  VALUES (r.id, r.clan_id, COALESCE(p_reason, 'admin_rebase'), r.max_hp, r.current_hp,
    v_new, GREATEST(1, v_new - v_dealt), v_dealt, v_cap, r.target_days, cfg.raid_safety_factor,
    v_day, round(v_unlocked * 100, 2));

  UPDATE public.clan_raid_cycles
     SET max_hp = v_new,
         current_hp = GREATEST(1, v_new - v_dealt),
         effective_dps_snapshot = v_cap,
         updated_at = now()
   WHERE id = r.id
  RETURNING * INTO r;

  RETURN jsonb_build_object('status', 'rebased', 'raidId', r.id, 'clanId', r.clan_id,
    'maxHp', r.max_hp, 'currentHp', r.current_hp, 'damagePreserved', v_dealt,
    'dailyCapacity', v_cap, 'targetDays', r.target_days,
    'unlockedPct', round(v_unlocked * 100, 2), 'day', v_day,
    'phaseLocked', r.current_hp <= public.clan_raid_phase_floor(r));
END $$;

-- 6) Rebase every active raid (used by migration + admin bot)
CREATE OR REPLACE FUNCTION public.clan_raid_rebase_all(p_reason text DEFAULT 'admin_rebase_all')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_id uuid; v_out jsonb := '[]'::jsonb; v_res jsonb;
BEGIN
  FOR v_id IN SELECT id FROM public.clan_raid_cycles WHERE status = 'ACTIVE' ORDER BY total_damage DESC LOOP
    v_res := public.clan_raid_rebase(v_id, p_reason);
    v_out := v_out || jsonb_build_array(v_res);
  END LOOP;
  RETURN jsonb_build_object('status', 'ok', 'raids', jsonb_array_length(v_out), 'results', v_out);
END $$;

-- 7) New raids use the personalised target HP helper
CREATE OR REPLACE FUNCTION public.clan_raid_ensure(p_clan uuid)
RETURNS clan_raid_cycles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_collective_settings; r public.clan_raid_cycles;
        v_key date; v_power numeric; v_hp numeric; v_dps numeric;
        v_active integer; prev public.clan_raid_performance;
BEGIN
  cfg := public.clan_collective_cfg();
  v_key := public.clan_week_key();

  UPDATE public.clan_raid_cycles SET status = 'EXPIRED', updated_at = now()
   WHERE clan_id = p_clan AND status = 'ACTIVE' AND ends_at < now();

  SELECT * INTO r FROM public.clan_raid_cycles WHERE clan_id = p_clan AND raid_key = v_key;
  IF r.id IS NOT NULL OR NOT cfg.raid_enabled THEN RETURN r; END IF;

  SELECT COALESCE(sum(public.clan_player_power(m.user_id)), 0) INTO v_power
    FROM public.clan_members m WHERE m.clan_id = p_clan;
  v_active := public.clan_active_members(p_clan);

  -- effective daily raid damage (history first, clan power as bootstrap)
  v_dps := public.clan_raid_daily_capacity(p_clan, NULL);
  v_hp := public.clan_raid_target_hp(p_clan, NULL);

  -- controlled recalibration against the previous raid performance
  SELECT * INTO prev FROM public.clan_raid_performance
   WHERE clan_id = p_clan ORDER BY created_at DESC LIMIT 1;
  IF prev.id IS NOT NULL AND prev.max_hp > 0 THEN
    v_hp := LEAST(v_hp, prev.max_hp * (1 + cfg.raid_max_hp_increase_pct / 100.0));
    v_hp := GREATEST(v_hp, prev.max_hp * (1 - cfg.raid_max_hp_decrease_pct / 100.0));
  END IF;

  v_hp := round(LEAST(cfg.raid_hp_max, GREATEST(cfg.raid_hp_min, v_hp)));

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

-- 8) Raid state: expose daily allowance, unlocked percentage and the real next-phase timestamp
CREATE OR REPLACE FUNCTION public.clan_raid_state(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_day integer; v_floor numeric; v_used integer;
        v_unlocked numeric; v_allowed numeric; v_dealt numeric; v_phase integer;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;

  PERFORM public.clan_raid_ensure(v_clan);
  SELECT * INTO r FROM public.clan_raid_cycles WHERE clan_id = v_clan AND raid_key = public.clan_week_key();
  IF r.id IS NULL THEN RETURN jsonb_build_object('inClan', true, 'raid', NULL); END IF;

  v_day := public.clan_raid_day(r.started_at);
  v_phase := LEAST(r.target_days, v_day);
  v_floor := public.clan_raid_phase_floor(r);
  v_dealt := GREATEST(0, r.max_hp - r.current_hp);
  v_unlocked := CASE WHEN r.gates_enabled THEN LEAST(1, v_phase::numeric / GREATEST(1, r.target_days)) ELSE 1 END;
  v_allowed := r.max_hp * v_unlocked;

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
      'phase', v_phase, 'phases', r.target_days,
      'phaseFloor', v_floor, 'phaseLocked', r.current_hp <= v_floor AND r.status = 'ACTIVE',
      'unlockedPct', round(v_unlocked * 100, 2),
      'allowedDamage', v_allowed,
      'damageDealt', v_dealt,
      'remainingAllowed', GREATEST(0, v_allowed - v_dealt),
      'nextPhaseAt', r.started_at + make_interval(days => v_day),
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

REVOKE ALL ON FUNCTION public.clan_raid_rebase(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_rebase_all(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_daily_capacity(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_raid_target_hp(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_raid_rebase(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_raid_rebase_all(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_raid_daily_capacity(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_raid_target_hp(uuid, uuid) TO service_role;