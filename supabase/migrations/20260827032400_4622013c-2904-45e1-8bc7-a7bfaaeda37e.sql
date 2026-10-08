-- 1) settings: minimum days before the raid can be killed
ALTER TABLE public.clan_collective_settings
  ADD COLUMN IF NOT EXISTS raid_min_kill_days integer NOT NULL DEFAULT 5;

ALTER TABLE public.clan_raid_cycles
  ADD COLUMN IF NOT EXISTS min_kill_days integer NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS kill_unlock_at timestamp with time zone;

UPDATE public.clan_raid_cycles
   SET min_kill_days = COALESCE((SELECT raid_min_kill_days FROM public.clan_collective_settings LIMIT 1), 5)
 WHERE min_kill_days IS NULL OR min_kill_days <= 0;

UPDATE public.clan_raid_cycles
   SET kill_unlock_at = started_at + make_interval(days => GREATEST(1, min_kill_days))
 WHERE kill_unlock_at IS NULL;

-- 2) explicit participation tracking (first attack per raid + user)
CREATE TABLE IF NOT EXISTS public.clan_raid_participation (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  raid_id uuid NOT NULL REFERENCES public.clan_raid_cycles(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  first_attack_at timestamp with time zone NOT NULL DEFAULT now(),
  last_attack_at timestamp with time zone NOT NULL DEFAULT now(),
  attacks integer NOT NULL DEFAULT 0,
  effective_damage numeric NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE (raid_id, user_id)
);

GRANT ALL ON public.clan_raid_participation TO service_role;
ALTER TABLE public.clan_raid_participation ENABLE ROW LEVEL SECURITY;

-- backfill from existing attack history
INSERT INTO public.clan_raid_participation(raid_id, clan_id, user_id, first_attack_at, last_attack_at, attacks, effective_damage)
SELECT a.raid_id, a.clan_id, a.user_id, min(a.created_at), max(a.created_at), count(*), sum(a.damage)
  FROM public.clan_raid_attacks a
 GROUP BY a.raid_id, a.clan_id, a.user_id
ON CONFLICT (raid_id, user_id) DO NOTHING;

-- 3) kill unlock helper
CREATE OR REPLACE FUNCTION public.clan_raid_kill_unlock_at(r public.clan_raid_cycles)
RETURNS timestamp with time zone
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT COALESCE(r.kill_unlock_at, r.started_at + make_interval(days => GREATEST(1, COALESCE(r.min_kill_days, 5))));
$$;
REVOKE ALL ON FUNCTION public.clan_raid_kill_unlock_at(public.clan_raid_cycles) FROM PUBLIC, anon, authenticated;

-- 4) attack: never block participation, never kill before unlock
CREATE OR REPLACE FUNCTION public.clan_raid_attack(p_telegram_id bigint, p_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_used integer; v_power numeric; v_raw numeric; v_dmg numeric; v_buff numeric; c public.clan_weekly_cycles;
        v_floor numeric; v_day integer; v_catch numeric; v_existing numeric;
        v_unlock timestamptz; v_protected boolean; v_hp_floor numeric; v_first boolean := false;
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
  v_unlock := public.clan_raid_kill_unlock_at(r);
  v_protected := now() < v_unlock;
  -- HP can never go below 1 while the minimum duration is not reached
  v_hp_floor := GREATEST(v_floor, CASE WHEN v_protected THEN 1 ELSE 0 END);

  SELECT count(*) INTO v_used FROM public.clan_raid_attacks
   WHERE raid_id = r.id AND user_id = v_uid AND attack_day = public.game_day_key();
  IF v_used >= cfg.raid_attacks_per_day THEN RAISE EXCEPTION 'RAID_DAILY_LIMIT'; END IF;

  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_buff := public.clan_buff_pct(v_clan, 'CLAN_RAID_DMG')
          + public.clan_upgrade_level(v_clan, 'WAR_HALL') * 0.5;
  v_catch := public.clan_raid_catchup_pct(r);
  v_raw := round(v_power * (28 + random() * 14) * (1 + (v_buff + v_catch) / 100.0));
  -- only the damage really applied to the shared HP is recorded (no fake damage)
  v_dmg := GREATEST(0, LEAST(v_raw, r.current_hp - v_hp_floor));

  INSERT INTO public.clan_raid_attacks(raid_id, clan_id, user_id, damage, idempotency_key, phase, payload)
  VALUES (r.id, v_clan, v_uid, v_dmg, p_key, LEAST(r.target_days, v_day),
          jsonb_build_object('power', v_power, 'buffPct', v_buff, 'catchupPct', v_catch,
                             'rawDamage', v_raw, 'killProtected', v_protected, 'hpFloor', v_hp_floor));

  INSERT INTO public.clan_raid_participation(raid_id, clan_id, user_id, attacks, effective_damage)
  VALUES (r.id, v_clan, v_uid, 1, v_dmg)
  ON CONFLICT (raid_id, user_id) DO UPDATE
    SET attacks = public.clan_raid_participation.attacks + 1,
        effective_damage = public.clan_raid_participation.effective_damage + EXCLUDED.effective_damage,
        last_attack_at = now(), updated_at = now()
  RETURNING (attacks = 1) INTO v_first;

  UPDATE public.clan_raid_cycles
     SET current_hp = GREATEST(v_hp_floor, current_hp - v_dmg),
         total_damage = total_damage + v_dmg,
         catchup_pct = v_catch,
         participants = (SELECT count(*) FROM public.clan_raid_participation WHERE raid_id = r.id),
         status = CASE WHEN NOT v_protected AND current_hp - v_dmg <= 0 THEN 'DEFEATED' ELSE status END,
         cleared_in_hours = CASE WHEN NOT v_protected AND current_hp - v_dmg <= 0
                                 THEN EXTRACT(epoch FROM (now() - started_at)) / 3600 ELSE cleared_in_hours END,
         updated_at = now()
   WHERE id = r.id
  RETURNING * INTO r;

  IF v_dmg > 0 THEN
    c := public.clan_weekly_cycle_ensure(v_clan);
    UPDATE public.clan_weekly_member_progress SET raid_damage = raid_damage + v_dmg, updated_at = now()
     WHERE cycle_id = c.id AND user_id = v_uid;
    IF NOT FOUND THEN
      INSERT INTO public.clan_weekly_member_progress(cycle_id, user_id, clan_id, raid_damage)
      VALUES (c.id, v_uid, v_clan, v_dmg) ON CONFLICT DO NOTHING;
    END IF;
    PERFORM public.record_clan_mission_progress(v_uid, 'clan_raid_damage', v_dmg::bigint);
  END IF;

  IF r.status = 'DEFEATED' THEN PERFORM public.clan_raid_settle(r.id); END IF;

  RETURN jsonb_build_object('status','ok','damage', v_dmg, 'rawDamage', v_raw,
    'bossHp', r.current_hp, 'maxHp', r.max_hp, 'defeated', r.status <> 'ACTIVE',
    'killProtected', v_protected, 'killUnlockAt', v_unlock, 'minKillDays', r.min_kill_days,
    'firstAttack', v_first,
    'phaseFloor', public.clan_raid_phase_floor(r), 'catchupPct', v_catch,
    'attacksLeft', GREATEST(0, cfg.raid_attacks_per_day - v_used - 1));
END $function$;
REVOKE ALL ON FUNCTION public.clan_raid_attack(bigint, text) FROM PUBLIC, anon, authenticated;

-- 5) state: expose protection info
CREATE OR REPLACE FUNCTION public.clan_raid_state(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; r public.clan_raid_cycles;
        v_day integer; v_floor numeric; v_used integer;
        v_unlocked numeric; v_allowed numeric; v_dealt numeric; v_phase integer;
        v_unlock timestamptz; v_protected boolean;
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
  v_unlock := public.clan_raid_kill_unlock_at(r);
  v_protected := now() < v_unlock AND r.status = 'ACTIVE';

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
      'minKillDays', GREATEST(1, COALESCE(r.min_kill_days, 5)),
      'killUnlockAt', v_unlock,
      'killProtected', v_protected,
      'phase', v_phase, 'phases', r.target_days,
      'phaseFloor', v_floor, 'phaseLocked', false,
      'unlockedPct', round(v_unlocked * 100, 2),
      'allowedDamage', v_allowed,
      'damageDealt', v_dealt,
      'remainingAllowed', GREATEST(0, v_allowed - v_dealt),
      'nextPhaseAt', r.started_at + make_interval(days => v_day),
      'catchupPct', public.clan_raid_catchup_pct(r),
      'totalDamage', r.total_damage,
      'participants', (SELECT count(*) FROM public.clan_raid_participation WHERE raid_id = r.id),
      'myFirstAttackAt', (SELECT first_attack_at FROM public.clan_raid_participation
                           WHERE raid_id = r.id AND user_id = v_uid),
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
END $function$;
REVOKE ALL ON FUNCTION public.clan_raid_state(bigint) FROM PUBLIC, anon, authenticated;

-- 6) ensure new cycles carry the configured minimum + admin control
CREATE OR REPLACE FUNCTION public.clan_raid_cycles_set_kill_unlock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.min_kill_days IS NULL OR NEW.min_kill_days <= 0 THEN
    NEW.min_kill_days := GREATEST(1, COALESCE((SELECT raid_min_kill_days FROM public.clan_collective_settings LIMIT 1), 5));
  END IF;
  NEW.kill_unlock_at := NEW.started_at + make_interval(days => NEW.min_kill_days);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_clan_raid_kill_unlock ON public.clan_raid_cycles;
CREATE TRIGGER trg_clan_raid_kill_unlock BEFORE INSERT ON public.clan_raid_cycles
FOR EACH ROW EXECUTE FUNCTION public.clan_raid_cycles_set_kill_unlock();

CREATE OR REPLACE FUNCTION public.admin_clan_raid_set(p_field text, p_value numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_field NOT IN ('raid_target_kill_days','raid_deadline_days','raid_attacks_per_day',
                     'raid_safety_factor','raid_dps_weight_24h','raid_dps_weight_3d','raid_dps_weight_7d',
                     'raid_max_hp_increase_pct','raid_max_hp_decrease_pct','raid_catchup_max_pct',
                     'raid_hp_min','raid_hp_max','raid_health_gates_enabled','raid_catchup_enabled',
                     'raid_enabled','raid_full_kill_required','raid_min_kill_days')
  THEN RAISE EXCEPTION 'INVALID_FIELD'; END IF;

  IF p_field = 'raid_min_kill_days' THEN
    IF p_value < 1 OR p_value > 30 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    UPDATE public.clan_collective_settings SET raid_min_kill_days = p_value::int, updated_at = now();
    UPDATE public.clan_raid_cycles
       SET min_kill_days = p_value::int,
           kill_unlock_at = started_at + make_interval(days => p_value::int),
           updated_at = now()
     WHERE status = 'ACTIVE';
    RETURN public.admin_clan_raid_settings();
  END IF;

  IF p_field IN ('raid_health_gates_enabled','raid_catchup_enabled','raid_enabled','raid_full_kill_required') THEN
    EXECUTE format('UPDATE public.clan_collective_settings SET %I = $1, updated_at = now()', p_field)
      USING (p_value <> 0);
  ELSE
    EXECUTE format('UPDATE public.clan_collective_settings SET %I = $1, updated_at = now()', p_field)
      USING p_value;
  END IF;
  RETURN public.admin_clan_raid_settings();
END $function$;
REVOKE ALL ON FUNCTION public.admin_clan_raid_set(text, numeric) FROM PUBLIC, anon, authenticated;