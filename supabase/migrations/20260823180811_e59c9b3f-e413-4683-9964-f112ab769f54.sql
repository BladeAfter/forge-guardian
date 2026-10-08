-- 0039 CLAN BOSS DYNAMIC SCALING (per-clan, 24h target cycle)
CREATE TABLE IF NOT EXISTS public.clan_boss_scaling_config (
  id smallint PRIMARY KEY DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  cycle_lock_enabled boolean NOT NULL DEFAULT true,
  cycle_hours integer NOT NULL DEFAULT 24,
  target_duration_seconds integer NOT NULL DEFAULT 84600,
  survival_factor numeric NOT NULL DEFAULT 1.05,
  hp_share numeric NOT NULL DEFAULT 0.80,
  def_share numeric NOT NULL DEFAULT 0.20,
  def_mitigation_cap numeric NOT NULL DEFAULT 0.35,
  min_effective_damage_pct numeric NOT NULL DEFAULT 25,
  atk_ratio numeric NOT NULL DEFAULT 0.35,
  hp_scaling numeric NOT NULL DEFAULT 1.0,
  def_scaling numeric NOT NULL DEFAULT 1.0,
  atk_scaling numeric NOT NULL DEFAULT 1.0,
  w_24h numeric NOT NULL DEFAULT 0.50,
  w_3d numeric NOT NULL DEFAULT 0.30,
  w_7d numeric NOT NULL DEFAULT 0.20,
  engagement_factor numeric NOT NULL DEFAULT 0.45,
  outlier_median_factor numeric NOT NULL DEFAULT 20,
  max_scale_up_per_cycle numeric NOT NULL DEFAULT 1.60,
  max_scale_down_per_cycle numeric NOT NULL DEFAULT 0.75,
  rebase_kills_threshold integer NOT NULL DEFAULT 2,
  rebase_max_scale numeric NOT NULL DEFAULT 25,
  too_easy_seconds integer NOT NULL DEFAULT 64800,
  too_hard_seconds integer NOT NULL DEFAULT 97200,
  scaling_version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.clan_boss_scaling_config(id) VALUES (1) ON CONFLICT (id) DO NOTHING;
GRANT ALL ON public.clan_boss_scaling_config TO service_role;
ALTER TABLE public.clan_boss_scaling_config ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_boss_scaling_profiles (
  clan_id uuid PRIMARY KEY REFERENCES public.clans(id) ON DELETE CASCADE,
  clan_power_snapshot numeric NOT NULL DEFAULT 0,
  active_members_snapshot integer NOT NULL DEFAULT 0,
  boss_participants_snapshot integer NOT NULL DEFAULT 0,
  historical_damage_rate numeric NOT NULL DEFAULT 0,
  effective_dps numeric NOT NULL DEFAULT 0,
  hp_multiplier numeric NOT NULL DEFAULT 1,
  def_multiplier numeric NOT NULL DEFAULT 1,
  atk_multiplier numeric NOT NULL DEFAULT 1,
  scaling_tier text NOT NULL DEFAULT 'LOW',
  last_actual_duration_seconds integer,
  last_quality text,
  last_mode text,
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  scaling_version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_boss_scaling_profiles TO service_role;
ALTER TABLE public.clan_boss_scaling_profiles ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_boss_performance_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  instance_id uuid NOT NULL UNIQUE,
  cycle integer,
  clan_power_snapshot numeric,
  active_members_snapshot integer,
  historical_damage_rate numeric,
  base_hp numeric,
  hp_multiplier numeric,
  effective_hp numeric,
  base_def numeric,
  def_multiplier numeric,
  effective_def numeric,
  base_atk numeric,
  atk_multiplier numeric,
  effective_atk numeric,
  boss_power numeric,
  target_duration_seconds integer,
  actual_duration_seconds integer,
  quality text,
  final_status text,
  total_damage numeric,
  participants integer,
  scaling_version integer,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cb_perf_clan_idx ON public.clan_boss_performance_history(clan_id, created_at DESC);
GRANT ALL ON public.clan_boss_performance_history TO service_role;
ALTER TABLE public.clan_boss_performance_history ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.clan_boss_instances
  ADD COLUMN IF NOT EXISTS boss_def numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS boss_atk numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS boss_power numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS base_hp numeric,
  ADD COLUMN IF NOT EXISTS hp_multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS def_multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS atk_multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS clan_power_snapshot numeric,
  ADD COLUMN IF NOT EXISTS active_members_snapshot integer,
  ADD COLUMN IF NOT EXISTS historical_dps_snapshot numeric,
  ADD COLUMN IF NOT EXISTS scaling_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS scaling_version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS target_duration_seconds integer,
  ADD COLUMN IF NOT EXISTS cycle_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS cycle_ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS actual_duration_seconds integer,
  ADD COLUMN IF NOT EXISTS duration_quality text;

CREATE INDEX IF NOT EXISTS cb_inst_cycle_lock_idx ON public.clan_boss_instances(clan_id, cycle_ends_at DESC);

CREATE OR REPLACE FUNCTION public.clan_boss_scaling_cfg()
RETURNS public.clan_boss_scaling_config
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT * FROM public.clan_boss_scaling_config WHERE id = 1
$fn$;
REVOKE ALL ON FUNCTION public.clan_boss_scaling_cfg() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_metrics(p_clan_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE sc public.clan_boss_scaling_config; cfg public.clan_boss_config;
        v_med numeric; v_cap numeric; v_out integer := 0;
        v_d24 numeric := 0; v_d3 numeric := 0; v_d7 numeric := 0;
        v_atk24 integer := 0; v_avg numeric := 0; v_avg_power numeric := 0;
        v_parts24 integer := 0; v_parts7 integer := 0; v_kills24 integer := 0;
        v_members integer := 0; v_act24 integer := 0; v_act7 integer := 0;
        v_power numeric := 0; v_roster numeric := 0; v_apd numeric;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  cfg := public.clan_boss_cfg();
  v_apd := GREATEST(1, 86400.0 / GREATEST(60, cfg.cooldown_seconds));

  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY damage) INTO v_med
    FROM public.clan_boss_attack_log
   WHERE clan_id = p_clan_id AND created_at > now() - interval '7 days' AND damage > 0;
  v_cap := GREATEST(COALESCE(v_med, 0) * GREATEST(2, sc.outlier_median_factor), 100000);

  SELECT
    COALESCE(sum(damage) FILTER (WHERE created_at > now() - interval '24 hours' AND damage <= v_cap), 0),
    COALESCE(sum(damage) FILTER (WHERE created_at > now() - interval '3 days'  AND damage <= v_cap), 0) / 3.0,
    COALESCE(sum(damage) FILTER (WHERE created_at > now() - interval '7 days'  AND damage <= v_cap), 0) / 7.0,
    count(*) FILTER (WHERE created_at > now() - interval '24 hours' AND damage <= v_cap),
    count(DISTINCT user_id) FILTER (WHERE created_at > now() - interval '24 hours' AND damage <= v_cap),
    count(DISTINCT user_id) FILTER (WHERE damage <= v_cap),
    count(*) FILTER (WHERE damage > v_cap),
    COALESCE(avg(team_power) FILTER (WHERE damage <= v_cap AND team_power > 0), 0)
  INTO v_d24, v_d3, v_d7, v_atk24, v_parts24, v_parts7, v_out, v_avg_power
  FROM public.clan_boss_attack_log
  WHERE clan_id = p_clan_id AND created_at > now() - interval '7 days' AND damage > 0;

  SELECT COALESCE(avg(damage), 0) INTO v_avg
    FROM public.clan_boss_attack_log
   WHERE clan_id = p_clan_id AND created_at > now() - interval '7 days'
     AND damage > 0 AND damage <= v_cap;

  SELECT count(*) INTO v_kills24 FROM public.clan_boss_instances
   WHERE clan_id = p_clan_id AND status = 'defeated' AND finished_at > now() - interval '24 hours';

  SELECT count(*) INTO v_members FROM public.clan_members WHERE clan_id = p_clan_id;
  SELECT COALESCE(total_power, 0) INTO v_power FROM public.clans WHERE id = p_clan_id;

  SELECT count(*) FILTER (WHERE g.updated_at > now() - interval '24 hours'),
         count(*) FILTER (WHERE g.updated_at > now() - interval '7 days')
    INTO v_act24, v_act7
    FROM public.clan_members m JOIN public.game_players g ON g.id = m.user_id
   WHERE m.clan_id = p_clan_id;

  SELECT COALESCE(sum(public.clan_player_power(u)), 0) INTO v_roster FROM (
    SELECT user_id AS u FROM public.clan_members WHERE clan_id = p_clan_id
    UNION
    SELECT user_id FROM public.clan_membership_history
     WHERE clan_id = p_clan_id AND created_at > now() - interval '7 days'
    LIMIT 250
  ) s;

  RETURN jsonb_build_object(
    'clanPower', v_power,
    'rosterPowerHistorical', v_roster,
    'members', v_members,
    'active24h', v_act24,
    'active7d', v_act7,
    'bossParticipants24h', v_parts24,
    'bossParticipants7d', v_parts7,
    'attacks24h', v_atk24,
    'attacksPerDayPerPlayer', v_apd,
    'avgDamagePerAttack', round(v_avg),
    'avgAttackerPower', round(v_avg_power),
    'damage24h', round(v_d24),
    'damage3dAvg', round(v_d3),
    'damage7dAvg', round(v_d7),
    'bossesKilled24h', v_kills24,
    'outlierAttacks', v_out,
    'outlierCap', round(v_cap));
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_metrics(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_effective_dps(p_clan_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE sc public.clan_boss_scaling_config; m jsonb;
        v_weighted numeric; v_potential numeric; v_expected numeric; v_src text;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  m := public.clan_boss_metrics(p_clan_id);

  v_weighted := (m->>'damage24h')::numeric * sc.w_24h
              + (m->>'damage3dAvg')::numeric * sc.w_3d
              + (m->>'damage7dAvg')::numeric * sc.w_7d;

  v_potential := (m->>'bossParticipants7d')::numeric
               * (m->>'attacksPerDayPerPlayer')::numeric
               * GREATEST((m->>'avgDamagePerAttack')::numeric, 0)
               * sc.engagement_factor;

  v_expected := GREATEST(COALESCE(v_weighted, 0), COALESCE(v_potential, 0));
  v_src := CASE WHEN COALESCE(v_potential,0) > COALESCE(v_weighted,0) THEN 'CAPACITY_MODEL' ELSE 'WEIGHTED_HISTORY' END;

  IF v_expected <= 0 THEN
    v_expected := (m->>'rosterPowerHistorical')::numeric
                * (m->>'attacksPerDayPerPlayer')::numeric * 0.15;
    v_src := 'ROSTER_FALLBACK';
  END IF;

  RETURN jsonb_build_object(
    'expected24hDamage', round(GREATEST(v_expected, 0)),
    'dps', round(GREATEST(v_expected, 0) / 86400.0, 2),
    'weightedHistory', round(COALESCE(v_weighted, 0)),
    'capacityModel', round(COALESCE(v_potential, 0)),
    'source', v_src,
    'metrics', m);
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_effective_dps(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_compute_scaling(p_clan_id uuid, p_cycle integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE sc public.clan_boss_scaling_config; cfg public.clan_boss_config;
        tpl public.clan_boss_templates; prof public.clan_boss_scaling_profiles;
        d jsonb; m jsonb; v_cycle integer;
        v_base_hp numeric; v_target_total numeric; v_target_hp numeric;
        v_mult numeric; v_prev numeric; v_calib numeric := 1; v_mode text := 'GRADUAL';
        v_hp numeric; v_def numeric; v_base_def numeric; v_atk numeric; v_base_atk numeric;
        v_avg_power numeric; v_tier text; v_last integer; v_kills integer;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  cfg := public.clan_boss_cfg();
  v_cycle := GREATEST(1, COALESCE(p_cycle,
    (SELECT COALESCE(MAX(cycle), 0) + 1 FROM public.clan_boss_instances WHERE clan_id = p_clan_id)));
  tpl := public.clan_boss_template_for_cycle(v_cycle);
  v_base_hp := GREATEST(1, COALESCE(tpl.max_hp, public.clan_boss_scaled_hp(p_clan_id, v_cycle)));

  d := public.clan_boss_effective_dps(p_clan_id);
  m := d->'metrics';
  v_avg_power := GREATEST(COALESCE((m->>'avgAttackerPower')::numeric, 0),
                          COALESCE((m->>'rosterPowerHistorical')::numeric, 0)
                            / GREATEST(1, COALESCE((m->>'members')::numeric, 1)));
  v_kills := COALESCE((m->>'bossesKilled24h')::int, 0);

  SELECT * INTO prof FROM public.clan_boss_scaling_profiles WHERE clan_id = p_clan_id;
  v_prev := GREATEST(0.01, COALESCE(prof.hp_multiplier, 1));
  v_last := prof.last_actual_duration_seconds;

  IF v_last IS NOT NULL AND v_last > 0 THEN
    v_calib := LEAST(GREATEST(sc.target_duration_seconds::numeric / v_last, 0.25), 8);
  END IF;

  v_target_total := GREATEST(1, (d->>'expected24hDamage')::numeric)
                  * sc.survival_factor
                  * (sc.target_duration_seconds::numeric / 86400.0)
                  * GREATEST(0.1, sc.hp_scaling)
                  * v_calib;

  v_target_hp := v_target_total * LEAST(0.95, GREATEST(0.5, sc.hp_share));
  v_mult := v_target_hp / v_base_hp;

  IF NOT sc.enabled THEN
    v_mult := 1; v_mode := 'DISABLED';
  ELSIF v_kills >= GREATEST(1, sc.rebase_kills_threshold)
     OR (v_last IS NOT NULL AND v_last < sc.target_duration_seconds / 2)
     OR prof.clan_id IS NULL THEN
    v_mode := CASE WHEN prof.clan_id IS NULL THEN 'INITIAL_REBASE' ELSE 'FULL_RECALIBRATION' END;
    v_mult := LEAST(v_mult, v_prev * GREATEST(2, sc.rebase_max_scale));
  ELSE
    v_mult := LEAST(GREATEST(v_mult, v_prev * sc.max_scale_down_per_cycle),
                    v_prev * sc.max_scale_up_per_cycle);
  END IF;
  v_mult := GREATEST(v_mult, 0.05);

  v_hp := round(v_base_hp * v_mult);

  v_base_def := GREATEST(1, round(GREATEST(v_avg_power, 100)
                 * LEAST(sc.def_mitigation_cap, GREATEST(0, sc.def_share))
                 / GREATEST(0.05, 1 - LEAST(sc.def_mitigation_cap, GREATEST(0, sc.def_share)))));
  v_def := round(v_base_def * GREATEST(0.1, sc.def_scaling));

  v_base_atk := GREATEST(1, round(GREATEST(v_avg_power, 100) * GREATEST(0.01, sc.atk_ratio)));
  v_atk := round(v_base_atk * GREATEST(0.1, sc.atk_scaling));

  v_tier := CASE
    WHEN (d->>'expected24hDamage')::numeric >= 300000000 THEN 'EXTREME'
    WHEN (d->>'expected24hDamage')::numeric >= 80000000 THEN 'HIGH'
    WHEN (d->>'expected24hDamage')::numeric >= 15000000 THEN 'MEDIUM'
    ELSE 'LOW' END;

  RETURN jsonb_build_object(
    'clanId', p_clan_id, 'cycle', v_cycle,
    'baseHp', v_base_hp, 'hpMultiplier', round(v_mult, 4), 'effectiveHp', v_hp,
    'baseDef', v_base_def, 'defMultiplier', GREATEST(0.1, sc.def_scaling), 'effectiveDef', v_def,
    'baseAtk', v_base_atk, 'atkMultiplier', GREATEST(0.1, sc.atk_scaling), 'effectiveAtk', v_atk,
    'bossPower', round(v_hp / 1000.0 + v_atk * 5 + v_def * 3 + v_cycle * 1000),
    'targetDurationSeconds', sc.target_duration_seconds,
    'expectedDurationSeconds', LEAST(259200, round(
        v_hp / GREATEST(1, (d->>'expected24hDamage')::numeric
              * LEAST(0.95, GREATEST(0.5, sc.hp_share)) / 86400.0))),
    'mode', v_mode, 'calibration', round(v_calib, 3), 'tier', v_tier,
    'scalingVersion', sc.scaling_version,
    'dps', d);
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_compute_scaling(uuid, integer) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_scaling_persist(p_clan_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE s jsonb; m jsonb;
BEGIN
  s := public.clan_boss_compute_scaling(p_clan_id, NULL);
  m := s->'dps'->'metrics';
  INSERT INTO public.clan_boss_scaling_profiles(
    clan_id, clan_power_snapshot, active_members_snapshot, boss_participants_snapshot,
    historical_damage_rate, effective_dps, hp_multiplier, def_multiplier, atk_multiplier,
    scaling_tier, metrics, scaling_version, last_mode, updated_at)
  VALUES (p_clan_id, (m->>'clanPower')::numeric, (m->>'active24h')::int,
          (m->>'bossParticipants7d')::int, (s->'dps'->>'weightedHistory')::numeric,
          (s->'dps'->>'dps')::numeric, (s->>'hpMultiplier')::numeric,
          (s->>'defMultiplier')::numeric, (s->>'atkMultiplier')::numeric,
          s->>'tier', m, (s->>'scalingVersion')::int, s->>'mode', now())
  ON CONFLICT (clan_id) DO UPDATE SET
    clan_power_snapshot = EXCLUDED.clan_power_snapshot,
    active_members_snapshot = EXCLUDED.active_members_snapshot,
    boss_participants_snapshot = EXCLUDED.boss_participants_snapshot,
    historical_damage_rate = EXCLUDED.historical_damage_rate,
    effective_dps = EXCLUDED.effective_dps,
    hp_multiplier = EXCLUDED.hp_multiplier,
    def_multiplier = EXCLUDED.def_multiplier,
    atk_multiplier = EXCLUDED.atk_multiplier,
    scaling_tier = EXCLUDED.scaling_tier,
    metrics = EXCLUDED.metrics,
    scaling_version = EXCLUDED.scaling_version,
    last_mode = EXCLUDED.last_mode,
    updated_at = now();
  RETURN s;
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_scaling_persist(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_apply_def(p_raw numeric, p_def numeric, p_power numeric)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE sc public.clan_boss_scaling_config; v_mit numeric; v_out numeric;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  IF COALESCE(p_def, 0) <= 0 THEN RETURN GREATEST(1, round(p_raw)); END IF;
  v_mit := LEAST(GREATEST(sc.def_mitigation_cap, 0),
                 p_def / (p_def + GREATEST(1, COALESCE(p_power, 1))));
  v_out := p_raw * (1 - v_mit);
  RETURN GREATEST(round(p_raw * GREATEST(1, sc.min_effective_damage_pct) / 100.0), round(v_out), 1);
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_apply_def(numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_cycle_lock(p_clan_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE sc public.clan_boss_scaling_config; v_next timestamptz;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  IF NOT sc.cycle_lock_enabled THEN RETURN jsonb_build_object('locked', false); END IF;
  SELECT MAX(COALESCE(cycle_ends_at, starts_at + make_interval(hours => sc.cycle_hours)))
    INTO v_next
    FROM public.clan_boss_instances WHERE clan_id = p_clan_id;
  IF v_next IS NULL OR v_next <= now() THEN RETURN jsonb_build_object('locked', false); END IF;
  RETURN jsonb_build_object('locked', true, 'nextBossAt', v_next,
    'secondsRemaining', GREATEST(0, ceil(EXTRACT(epoch FROM (v_next - now())))::int));
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_cycle_lock(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_record_performance(p_instance_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE sc public.clan_boss_scaling_config; b public.clan_boss_instances;
        v_dur integer; v_q text;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  SELECT * INTO b FROM public.clan_boss_instances WHERE id = p_instance_id;
  IF b.id IS NULL THEN RETURN; END IF;
  v_dur := GREATEST(1, ceil(EXTRACT(epoch FROM (COALESCE(b.finished_at, now()) - b.starts_at)))::int);
  v_q := CASE WHEN p_status <> 'defeated' THEN 'TARGET_MISSED_OVERTIME'
              WHEN v_dur < sc.too_easy_seconds THEN 'TOO_EASY'
              WHEN v_dur > sc.too_hard_seconds THEN 'TOO_HARD'
              ELSE 'BALANCED' END;

  UPDATE public.clan_boss_instances
     SET actual_duration_seconds = v_dur, duration_quality = v_q WHERE id = b.id;

  INSERT INTO public.clan_boss_performance_history(
    clan_id, instance_id, cycle, clan_power_snapshot, active_members_snapshot,
    historical_damage_rate, base_hp, hp_multiplier, effective_hp,
    base_def, def_multiplier, effective_def, base_atk, atk_multiplier, effective_atk,
    boss_power, target_duration_seconds, actual_duration_seconds, quality, final_status,
    total_damage, participants, scaling_version)
  VALUES (b.clan_id, b.id, b.cycle, b.clan_power_snapshot, b.active_members_snapshot,
    b.historical_dps_snapshot, COALESCE(b.base_hp, b.max_hp), b.hp_multiplier, b.max_hp,
    (b.scaling_snapshot->>'baseDef')::numeric, b.def_multiplier, b.boss_def,
    (b.scaling_snapshot->>'baseAtk')::numeric, b.atk_multiplier, b.boss_atk,
    b.boss_power, COALESCE(b.target_duration_seconds, sc.target_duration_seconds),
    v_dur, v_q, p_status,
    b.total_damage, b.participants, b.scaling_version)
  ON CONFLICT (instance_id) DO NOTHING;

  UPDATE public.clan_boss_scaling_profiles
     SET last_actual_duration_seconds = v_dur, last_quality = v_q, updated_at = now()
   WHERE clan_id = b.clan_id;
END $fn$;
REVOKE ALL ON FUNCTION public.clan_boss_record_performance(uuid, text) FROM PUBLIC, anon, authenticated;