-- =====================================================================
-- PERSONAL CLAN BOSS — per-member adaptive boss + daily defeated limit
-- Global Boss is NOT touched by this migration.
-- =====================================================================

-- 1) instance shape -----------------------------------------------------
ALTER TABLE public.clan_boss_instances
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS is_personal boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS boss_number_today integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS difficulty text,
  ADD COLUMN IF NOT EXISTS player_power_snapshot numeric,
  ADD COLUMN IF NOT EXISTS performance_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS reset_day date;

DROP INDEX IF EXISTS public.clan_boss_instances_active_uidx;
DROP INDEX IF EXISTS public.clan_boss_instances_cycle_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS clan_boss_instances_personal_active_uidx
  ON public.clan_boss_instances(user_id) WHERE status = 'active' AND user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS clan_boss_instances_shared_active_uidx
  ON public.clan_boss_instances(clan_id) WHERE status = 'active' AND user_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS clan_boss_instances_personal_cycle_uidx
  ON public.clan_boss_instances(user_id, cycle) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS clan_boss_instances_user_idx
  ON public.clan_boss_instances(user_id, created_at DESC);

-- legacy shared bosses stop here (no rewards are granted for an expiry)
UPDATE public.clan_boss_instances
   SET status = 'expired', finished_at = now()
 WHERE status = 'active' AND user_id IS NULL;

-- personal performance history columns
ALTER TABLE public.clan_boss_performance_history
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS player_power numeric,
  ADD COLUMN IF NOT EXISTS attack_count integer,
  ADD COLUMN IF NOT EXISTS avg_damage_per_attack numeric,
  ADD COLUMN IF NOT EXISTS max_hit numeric,
  ADD COLUMN IF NOT EXISTS boss_number_today integer,
  ADD COLUMN IF NOT EXISTS difficulty text;
CREATE INDEX IF NOT EXISTS cb_perf_user_idx
  ON public.clan_boss_performance_history(user_id, created_at DESC);

-- 2) personal config singleton -----------------------------------------
CREATE TABLE IF NOT EXISTS public.clan_boss_personal_config (
  id smallint PRIMARY KEY DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  daily_limit integer NOT NULL DEFAULT 4,
  reset_hour_utc integer NOT NULL DEFAULT 0,
  boss_duration_hours integer NOT NULL DEFAULT 24,
  target_attacks_per_boss integer NOT NULL DEFAULT 12,
  very_easy_pct numeric NOT NULL DEFAULT 25,
  easy_pct numeric NOT NULL DEFAULT 15,
  balanced_pct numeric NOT NULL DEFAULT 5,
  hard_pct numeric NOT NULL DEFAULT 0,
  very_hard_pct numeric NOT NULL DEFAULT -10,
  max_scale_up numeric NOT NULL DEFAULT 1.50,
  max_scale_down numeric NOT NULL DEFAULT 0.70,
  capacity_floor numeric NOT NULL DEFAULT 0.40,
  capacity_ceiling numeric NOT NULL DEFAULT 2.50,
  min_hp numeric NOT NULL DEFAULT 1000000,
  max_hp numeric NOT NULL DEFAULT 2000000000,
  def_mitigation_target numeric NOT NULL DEFAULT 0.15,
  atk_ratio numeric NOT NULL DEFAULT 0.25,
  outlier_median_factor numeric NOT NULL DEFAULT 8,
  history_samples integer NOT NULL DEFAULT 5,
  fc_pool_pct numeric NOT NULL DEFAULT 100,
  difficulty_bonus_enabled boolean NOT NULL DEFAULT false,
  scaling_version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clan_boss_personal_config_single CHECK (id = 1)
);
GRANT ALL ON public.clan_boss_personal_config TO service_role;
ALTER TABLE public.clan_boss_personal_config ENABLE ROW LEVEL SECURITY;
INSERT INTO public.clan_boss_personal_config(id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- 3) per-player profile --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.clan_boss_player_profile (
  user_id uuid PRIMARY KEY,
  effective_power numeric NOT NULL DEFAULT 0,
  official_power numeric NOT NULL DEFAULT 0,
  recent_avg_damage numeric NOT NULL DEFAULT 0,
  recent_avg_clear_time integer,
  recent_avg_attacks numeric,
  recent_max_hit numeric NOT NULL DEFAULT 0,
  recommended_hp numeric NOT NULL DEFAULT 0,
  recommended_def numeric NOT NULL DEFAULT 0,
  recommended_atk numeric NOT NULL DEFAULT 0,
  difficulty_rating text,
  last_quality text,
  samples integer NOT NULL DEFAULT 0,
  daily_limit_override integer,
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  scaling_version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_boss_player_profile TO service_role;
ALTER TABLE public.clan_boss_player_profile ENABLE ROW LEVEL SECURITY;

-- 4) per-player daily defeated counter (survives clan hopping) ----------
CREATE TABLE IF NOT EXISTS public.clan_boss_daily_counters (
  user_id uuid NOT NULL,
  reset_day date NOT NULL,
  defeated_count integer NOT NULL DEFAULT 0,
  last_defeat_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, reset_day)
);
GRANT ALL ON public.clan_boss_daily_counters TO service_role;
ALTER TABLE public.clan_boss_daily_counters ENABLE ROW LEVEL SECURITY;

-- 5) helpers -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.clan_boss_personal_cfg()
RETURNS public.clan_boss_personal_config
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT * FROM public.clan_boss_personal_config WHERE id = 1 $$;

CREATE OR REPLACE FUNCTION public.clan_boss_reset_day(p_at timestamptz DEFAULT now())
RETURNS date
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT ((p_at AT TIME ZONE 'UTC')
          - make_interval(hours => GREATEST(0, LEAST(23, (SELECT reset_hour_utc FROM public.clan_boss_personal_config WHERE id = 1)))))::date
$$;

CREATE OR REPLACE FUNCTION public.clan_boss_next_reset_at(p_at timestamptz DEFAULT now())
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT ((public.clan_boss_reset_day(p_at) + 1)::timestamp
          + make_interval(hours => GREATEST(0, LEAST(23, (SELECT reset_hour_utc FROM public.clan_boss_personal_config WHERE id = 1)))))
         AT TIME ZONE 'UTC'
$$;

-- effective daily limit = personal override ?? global default
CREATE OR REPLACE FUNCTION public.clan_boss_personal_daily(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE pc public.clan_boss_personal_config; v_day date; v_count integer; v_over integer; v_limit integer; v_next timestamptz;
BEGIN
  pc := public.clan_boss_personal_cfg();
  v_day := public.clan_boss_reset_day(now());
  SELECT defeated_count INTO v_count FROM public.clan_boss_daily_counters WHERE user_id = p_user AND reset_day = v_day;
  SELECT daily_limit_override INTO v_over FROM public.clan_boss_player_profile WHERE user_id = p_user;
  v_limit := GREATEST(0, COALESCE(v_over, pc.daily_limit));
  v_next := public.clan_boss_next_reset_at(now());
  RETURN jsonb_build_object(
    'day', v_day, 'defeated', COALESCE(v_count, 0), 'limit', v_limit,
    'globalLimit', pc.daily_limit, 'override', v_over,
    'limitReached', COALESCE(v_count, 0) >= v_limit,
    'resetAt', v_next,
    'secondsToReset', GREATEST(0, ceil(EXTRACT(epoch FROM (v_next - now())))::int));
END $$;

-- outlier-safe personal combat metrics
CREATE OR REPLACE FUNCTION public.clan_boss_player_metrics(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE pc public.clan_boss_personal_config;
        v_med numeric; v_cap numeric; v_avg numeric := 0; v_max numeric := 0;
        v_atks integer := 0; v_out integer := 0; v_power numeric; v_team numeric;
        v_clear numeric; v_used numeric; v_hp numeric; v_quality text; v_samples integer := 0;
        v_pet numeric := 0; v_buffs jsonb;
BEGIN
  pc := public.clan_boss_personal_cfg();
  v_power := GREATEST(0, COALESCE(public.clan_player_power(p_user), 0));
  v_buffs := COALESCE(public.get_pet_bonuses(p_user), '{}'::jsonb);
  v_pet := COALESCE((v_buffs->>'boss_damage_percent')::numeric, 0)
         + COALESCE((v_buffs->>'team_attack_percent')::numeric, 0);

  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY damage) INTO v_med
    FROM public.clan_boss_attack_log WHERE user_id = p_user AND damage > 0 AND created_at > now() - interval '14 days';
  v_cap := GREATEST(COALESCE(v_med, 0) * GREATEST(2, pc.outlier_median_factor), 1000);

  SELECT COALESCE(avg(damage), 0), COALESCE(max(damage), 0), count(*)
    INTO v_avg, v_max, v_atks
    FROM public.clan_boss_attack_log
   WHERE user_id = p_user AND damage > 0 AND damage <= v_cap AND created_at > now() - interval '14 days';

  SELECT count(*) INTO v_out FROM public.clan_boss_attack_log
   WHERE user_id = p_user AND created_at > now() - interval '14 days' AND damage > v_cap;

  SELECT avg(h.actual_duration_seconds), avg(h.attack_count), avg(h.effective_hp), count(*)
    INTO v_clear, v_used, v_hp, v_samples
    FROM (SELECT * FROM public.clan_boss_performance_history
           WHERE user_id = p_user AND final_status = 'defeated'
           ORDER BY created_at DESC LIMIT GREATEST(1, pc.history_samples)) h;

  SELECT quality INTO v_quality FROM public.clan_boss_performance_history
   WHERE user_id = p_user ORDER BY created_at DESC LIMIT 1;

  SELECT COALESCE(effective_hp, 0) INTO v_team FROM (SELECT NULL::numeric AS effective_hp) z;

  RETURN jsonb_build_object(
    'officialPower', round(v_power),
    'petBonusPercent', round(v_pet, 2),
    'avgDamagePerAttack', round(COALESCE(v_avg, 0)),
    'maxHit', round(COALESCE(v_max, 0)),
    'attacks14d', v_atks,
    'outlierAttacks', v_out,
    'outlierCap', round(v_cap),
    'avgClearSeconds', CASE WHEN v_clear IS NULL THEN NULL ELSE round(v_clear)::int END,
    'avgAttacksPerBoss', CASE WHEN v_used IS NULL THEN NULL ELSE round(v_used, 2) END,
    'avgClearedHp', round(COALESCE(v_hp, 0)),
    'samples', COALESCE(v_samples, 0),
    'lastQuality', v_quality);
END $$;

-- personal scaling: base stats x personal scale (never compounding blindly)
CREATE OR REPLACE FUNCTION public.clan_boss_personal_scaling(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE pc public.clan_boss_personal_config; m jsonb;
        v_power numeric; v_dpa numeric; v_capacity numeric;
        v_prev numeric; v_prev_status text; v_prev_attacks numeric; v_prev_dur integer;
        v_rating text := 'INITIAL'; v_pct numeric := 0; v_hp numeric; v_def numeric; v_atk numeric;
        v_target integer; v_diff text; v_mode text := 'CAPACITY';
BEGIN
  pc := public.clan_boss_personal_cfg();
  m := public.clan_boss_player_metrics(p_user);
  v_target := GREATEST(3, pc.target_attacks_per_boss);
  v_power := GREATEST(1, (m->>'officialPower')::numeric);

  -- expected damage per attack: official power is the floor, real history wins when higher
  v_dpa := GREATEST(v_power * (1 + GREATEST(0, (m->>'petBonusPercent')::numeric) / 100.0),
                    COALESCE((m->>'avgDamagePerAttack')::numeric, 0));
  v_capacity := GREATEST(pc.min_hp, v_dpa * v_target);

  SELECT h.effective_hp, h.final_status, h.attack_count, h.actual_duration_seconds
    INTO v_prev, v_prev_status, v_prev_attacks, v_prev_dur
    FROM public.clan_boss_performance_history h
   WHERE h.user_id = p_user ORDER BY h.created_at DESC LIMIT 1;

  IF v_prev IS NOT NULL AND COALESCE(v_prev, 0) > 0 THEN
    v_mode := 'ADAPTIVE';
    IF v_prev_status <> 'defeated' THEN
      v_rating := 'VERY_HARD'; v_pct := pc.very_hard_pct;
    ELSE
      v_prev_attacks := GREATEST(1, COALESCE(v_prev_attacks, v_target));
      v_rating := CASE
        WHEN v_prev_attacks <= v_target * 0.40 THEN 'TOO_EASY'
        WHEN v_prev_attacks <= v_target * 0.70 THEN 'EASY'
        WHEN v_prev_attacks <= v_target * 1.15 THEN 'BALANCED'
        WHEN v_prev_attacks <= v_target * 1.60 THEN 'HARD'
        ELSE 'VERY_HARD' END;
      v_pct := CASE v_rating
        WHEN 'TOO_EASY' THEN pc.very_easy_pct WHEN 'EASY' THEN pc.easy_pct
        WHEN 'BALANCED' THEN pc.balanced_pct WHEN 'HARD' THEN pc.hard_pct
        ELSE pc.very_hard_pct END;
    END IF;
    v_hp := v_prev * (1 + v_pct / 100.0);
    -- controlled growth: never compound past the caps, always anchored on real capacity
    v_hp := LEAST(v_hp, v_prev * GREATEST(1, pc.max_scale_up));
    v_hp := GREATEST(v_hp, v_prev * LEAST(1, pc.max_scale_down));
    v_hp := LEAST(GREATEST(v_hp, v_capacity * GREATEST(0.05, pc.capacity_floor)),
                  v_capacity * GREATEST(1, pc.capacity_ceiling));
  ELSE
    -- initial calibration: recent real damage history if any, else power + team power
    v_hp := v_capacity;
    v_mode := CASE WHEN COALESCE((m->>'attacks14d')::int, 0) > 0 THEN 'INITIAL_HISTORY' ELSE 'INITIAL_POWER' END;
  END IF;

  v_hp := round(LEAST(GREATEST(v_hp, pc.min_hp), pc.max_hp));
  v_def := round(v_power * LEAST(0.6, GREATEST(0, pc.def_mitigation_target))
                 / GREATEST(0.05, 1 - LEAST(0.6, GREATEST(0, pc.def_mitigation_target))));
  v_atk := round(GREATEST(1, v_power * GREATEST(0.01, pc.atk_ratio)));

  v_diff := CASE
    WHEN v_hp < 10000000 THEN 'ROOKIE'
    WHEN v_hp < 30000000 THEN 'VETERAN'
    WHEN v_hp < 75000000 THEN 'ELITE'
    WHEN v_hp < 150000000 THEN 'MASTER'
    WHEN v_hp < 400000000 THEN 'LEGEND'
    ELSE 'MYTHIC' END;

  RETURN jsonb_build_object(
    'userId', p_user, 'mode', v_mode, 'rating', v_rating, 'growthPct', v_pct,
    'officialPower', round(v_power), 'estimatedDamagePerAttack', round(v_dpa),
    'capacityHp', round(v_capacity), 'previousHp', round(COALESCE(v_prev, 0)),
    'recommendedHp', v_hp, 'recommendedDef', v_def, 'recommendedAtk', v_atk,
    'bossPower', round(v_hp * 1.2 + v_atk * 10 + v_def * 10),
    'difficulty', v_diff, 'targetAttacks', v_target,
    'scalingVersion', pc.scaling_version, 'metrics', m);
END $$;

CREATE OR REPLACE FUNCTION public.clan_boss_profile_persist(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE s jsonb; m jsonb;
BEGIN
  s := public.clan_boss_personal_scaling(p_user);
  m := s->'metrics';
  INSERT INTO public.clan_boss_player_profile(
    user_id, effective_power, official_power, recent_avg_damage, recent_avg_clear_time,
    recent_avg_attacks, recent_max_hit, recommended_hp, recommended_def, recommended_atk,
    difficulty_rating, last_quality, samples, metrics, scaling_version, updated_at)
  VALUES (p_user, (s->>'estimatedDamagePerAttack')::numeric, (s->>'officialPower')::numeric,
    (m->>'avgDamagePerAttack')::numeric, (m->>'avgClearSeconds')::int,
    (m->>'avgAttacksPerBoss')::numeric, (m->>'maxHit')::numeric,
    (s->>'recommendedHp')::numeric, (s->>'recommendedDef')::numeric, (s->>'recommendedAtk')::numeric,
    s->>'difficulty', m->>'lastQuality', COALESCE((m->>'samples')::int, 0), m,
    (s->>'scalingVersion')::int, now())
  ON CONFLICT (user_id) DO UPDATE SET
    effective_power = EXCLUDED.effective_power,
    official_power = EXCLUDED.official_power,
    recent_avg_damage = EXCLUDED.recent_avg_damage,
    recent_avg_clear_time = EXCLUDED.recent_avg_clear_time,
    recent_avg_attacks = EXCLUDED.recent_avg_attacks,
    recent_max_hit = EXCLUDED.recent_max_hit,
    recommended_hp = EXCLUDED.recommended_hp,
    recommended_def = EXCLUDED.recommended_def,
    recommended_atk = EXCLUDED.recommended_atk,
    difficulty_rating = EXCLUDED.difficulty_rating,
    last_quality = EXCLUDED.last_quality,
    samples = EXCLUDED.samples,
    metrics = EXCLUDED.metrics,
    scaling_version = EXCLUDED.scaling_version,
    updated_at = now();
  RETURN s;
END $$;

-- fixed-HP trigger must never override a personal boss
CREATE OR REPLACE FUNCTION public.clan_boss_apply_fixed_hp()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_fixed numeric;
BEGIN
  IF NEW.user_id IS NOT NULL THEN RETURN NEW; END IF;
  v_fixed := (public.clan_boss_clan_cfg(NEW.clan_id)->>'fixedHp')::numeric;
  IF COALESCE(v_fixed, 0) > 0 THEN
    NEW.max_hp := round(v_fixed);
    NEW.current_hp := LEAST(COALESCE(NEW.current_hp, round(v_fixed)), round(v_fixed));
    NEW.min_damage_required := LEAST(COALESCE(NEW.min_damage_required, 0), round(v_fixed));
  END IF;
  RETURN NEW;
END $$;

-- 6) personal spawn ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.clan_boss_personal_ensure(p_user uuid, p_clan uuid)
RETURNS public.clan_boss_instances
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_boss_config; pc public.clan_boss_personal_config;
        b public.clan_boss_instances; tpl public.clan_boss_templates; cc jsonb;
        s jsonb; dl jsonb; v_cycle integer; v_level integer; v_rewards jsonb;
        v_hp numeric; v_dur integer; v_day date; v_today integer;
BEGIN
  cfg := public.clan_boss_cfg();
  pc := public.clan_boss_personal_cfg();
  cc := public.clan_boss_clan_cfg(p_clan);
  v_day := public.clan_boss_reset_day(now());

  SELECT * INTO b FROM public.clan_boss_instances
   WHERE user_id = p_user AND status = 'active' LIMIT 1;

  IF b.id IS NOT NULL AND b.ends_at <= now() THEN
    PERFORM public.clan_boss_settle(b.id, 'expired');
    b := NULL;
  END IF;
  -- HP is preserved between sessions: an existing boss is never regenerated
  IF b.id IS NOT NULL THEN
    IF b.clan_id <> p_clan THEN
      UPDATE public.clan_boss_instances SET clan_id = p_clan WHERE id = b.id RETURNING * INTO b;
    END IF;
    RETURN b;
  END IF;

  dl := public.clan_boss_personal_daily(p_user);
  IF (dl->>'limitReached')::boolean THEN RETURN NULL; END IF;

  SELECT COALESCE(MAX(cycle), 0) + 1 INTO v_cycle FROM public.clan_boss_instances WHERE user_id = p_user;
  SELECT GREATEST(1, level) INTO v_level FROM public.clans WHERE id = p_clan;
  tpl := public.clan_boss_template_for_cycle(v_cycle);
  s := public.clan_boss_profile_persist(p_user);
  v_hp := GREATEST(1, (s->>'recommendedHp')::numeric);
  v_today := COALESCE((dl->>'defeated')::int, 0) + 1;
  v_dur := GREATEST(1, COALESCE(pc.boss_duration_hours, 24));

  v_rewards := COALESCE(cfg.rewards, '{}'::jsonb);
  IF tpl.id IS NOT NULL THEN
    v_rewards := v_rewards || jsonb_build_object('fcPool', tpl.reward_fc, 'clanXp', tpl.reward_clan_xp,
      'bossKey', tpl.boss_key, 'theme', tpl.theme, 'baseDamage', tpl.base_damage);
  END IF;
  v_rewards := v_rewards || COALESCE(cc->'rewards', '{}'::jsonb);
  IF COALESCE((cc->>'rewardFcPool')::numeric, 0) > 0 THEN
    v_rewards := v_rewards || jsonb_build_object('fcPool', (cc->>'rewardFcPool')::numeric);
  END IF;
  -- rewards are NOT scaled by personal HP; admins tune the share explicitly
  v_rewards := v_rewards || jsonb_build_object(
    'fcPool', round(COALESCE((v_rewards->>'fcPool')::numeric, 0) * GREATEST(0, pc.fc_pool_pct) / 100.0));

  INSERT INTO public.clan_boss_instances(
    user_id, is_personal, clan_id, boss_key, boss_name, cycle, level, max_hp, current_hp,
    min_damage_required, rewards_snapshot, starts_at, ends_at,
    base_hp, hp_multiplier, def_multiplier, atk_multiplier,
    boss_def, boss_atk, boss_power, difficulty, boss_number_today, reset_day,
    player_power_snapshot, performance_snapshot, scaling_snapshot, scaling_version,
    target_duration_seconds, cycle_started_at, cycle_ends_at)
  VALUES (p_user, true, p_clan, COALESCE(tpl.boss_key, cfg.boss_key), COALESCE(tpl.name, cfg.boss_name),
    v_cycle, COALESCE(v_level, 1), round(v_hp), round(v_hp),
    round(v_hp * cfg.min_damage_pct / 100.0), v_rewards, now(), now() + make_interval(hours => v_dur),
    (s->>'capacityHp')::numeric, 1, 1, 1,
    (s->>'recommendedDef')::numeric, (s->>'recommendedAtk')::numeric, (s->>'bossPower')::numeric,
    s->>'difficulty', v_today, v_day,
    (s->>'officialPower')::numeric, s->'metrics', s, (s->>'scalingVersion')::int,
    NULL, now(), now() + make_interval(hours => v_dur))
  RETURNING * INTO b;

  RETURN b;
END $$;

-- 7) performance recording (personal aware) ------------------------------
CREATE OR REPLACE FUNCTION public.clan_boss_record_performance(p_instance_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE sc public.clan_boss_scaling_config; pc public.clan_boss_personal_config;
        b public.clan_boss_instances; v_dur integer; v_q text;
        v_attacks integer; v_max numeric; v_avg numeric; v_target integer;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  pc := public.clan_boss_personal_cfg();
  SELECT * INTO b FROM public.clan_boss_instances WHERE id = p_instance_id;
  IF b.id IS NULL THEN RETURN; END IF;
  v_dur := GREATEST(1, ceil(EXTRACT(epoch FROM (COALESCE(b.finished_at, now()) - b.starts_at)))::int);

  IF b.user_id IS NOT NULL THEN
    v_target := GREATEST(3, pc.target_attacks_per_boss);
    SELECT COALESCE(sum(attacks), 0) INTO v_attacks FROM public.clan_boss_damage WHERE instance_id = b.id;
    SELECT COALESCE(max(damage), 0), COALESCE(avg(damage), 0) INTO v_max, v_avg
      FROM public.clan_boss_attack_log WHERE clan_boss_id = b.id;
    v_q := CASE
      WHEN p_status <> 'defeated' THEN 'TARGET_MISSED_OVERTIME'
      WHEN v_attacks <= v_target * 0.40 THEN 'TOO_EASY'
      WHEN v_attacks <= v_target * 0.70 THEN 'EASY'
      WHEN v_attacks <= v_target * 1.15 THEN 'BALANCED'
      WHEN v_attacks <= v_target * 1.60 THEN 'HARD'
      ELSE 'VERY_HARD' END;
  ELSE
    v_q := CASE WHEN p_status <> 'defeated' THEN 'TARGET_MISSED_OVERTIME'
                WHEN v_dur < sc.too_easy_seconds THEN 'TOO_EASY'
                WHEN v_dur > sc.too_hard_seconds THEN 'TOO_HARD'
                ELSE 'BALANCED' END;
  END IF;

  UPDATE public.clan_boss_instances
     SET actual_duration_seconds = v_dur, duration_quality = v_q WHERE id = b.id;

  INSERT INTO public.clan_boss_performance_history(
    clan_id, instance_id, user_id, cycle, clan_power_snapshot, active_members_snapshot,
    historical_damage_rate, base_hp, hp_multiplier, effective_hp,
    base_def, def_multiplier, effective_def, base_atk, atk_multiplier, effective_atk,
    boss_power, target_duration_seconds, actual_duration_seconds, quality, final_status,
    total_damage, participants, scaling_version,
    player_power, attack_count, avg_damage_per_attack, max_hit, boss_number_today, difficulty)
  VALUES (b.clan_id, b.id, b.user_id, b.cycle, b.clan_power_snapshot, b.active_members_snapshot,
    b.historical_dps_snapshot, COALESCE(b.base_hp, b.max_hp), b.hp_multiplier, b.max_hp,
    COALESCE((b.scaling_snapshot->>'baseDef')::numeric, b.boss_def), b.def_multiplier, b.boss_def,
    COALESCE((b.scaling_snapshot->>'baseAtk')::numeric, b.boss_atk), b.atk_multiplier, b.boss_atk,
    b.boss_power, COALESCE(b.target_duration_seconds, sc.target_duration_seconds),
    v_dur, v_q, p_status, b.total_damage, b.participants, b.scaling_version,
    b.player_power_snapshot, v_attacks, round(COALESCE(v_avg, 0)), round(COALESCE(v_max, 0)),
    b.boss_number_today, b.difficulty)
  ON CONFLICT (instance_id) DO NOTHING;

  IF b.user_id IS NULL THEN
    UPDATE public.clan_boss_scaling_profiles
       SET last_actual_duration_seconds = v_dur, last_quality = v_q, updated_at = now()
     WHERE clan_id = b.clan_id;
  ELSE
    PERFORM public.clan_boss_profile_persist(b.user_id);
  END IF;
END $$;

-- 8) settle: personal bosses count only when actually DEFEATED -----------
CREATE OR REPLACE FUNCTION public.clan_boss_settle(p_instance_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
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
      v_share := CASE WHEN b.max_hp > 0 THEN LEAST(1, r.damage / b.max_hp) ELSE 0 END;
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

    -- daily counter: only a REAL defeat consumes one of the player's daily bosses
    IF b.user_id IS NOT NULL THEN
      INSERT INTO public.clan_boss_daily_counters(user_id, reset_day, defeated_count, last_defeat_at)
      VALUES (b.user_id, public.clan_boss_reset_day(now()), 1, now())
      ON CONFLICT (user_id, reset_day) DO UPDATE
        SET defeated_count = public.clan_boss_daily_counters.defeated_count + 1,
            last_defeat_at = now(), updated_at = now();
    END IF;
  END IF;

  PERFORM public.clan_boss_record_performance(b.id, p_status);
END $$;

-- 9) strike: personal instance only --------------------------------------
CREATE OR REPLACE FUNCTION public.clan_boss_strike(p_telegram_id bigint, p_instance_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_boss_config; pc public.clan_boss_personal_config;
        v_uid uuid; v_clan uuid; b public.clan_boss_instances; dl jsonb;
        v_last timestamptz; v_damage numeric; v_raw numeric; v_base numeric; v_power numeric;
        v_bonus numeric; v_buffs jsonb;
        v_crit boolean := false; v_defeated boolean := false; v_type text;
BEGIN
  cfg := public.clan_boss_cfg();
  pc := public.clan_boss_personal_cfg();
  v_type := CASE WHEN coalesce(current_setting('mythreon.clan_attack_type', true), 'manual') = 'season_pass_auto'
                 THEN 'season_pass_auto' ELSE 'manual' END;
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  -- personal lock: one player, one boss, one transaction
  PERFORM pg_advisory_xact_lock(hashtextextended('clanbosspersonal:'||v_uid::text, 0));

  -- a player may only ever touch his OWN personal instance
  IF p_instance_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.clan_boss_instances
                WHERE id = p_instance_id AND (user_id IS NULL OR user_id <> v_uid))
      THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
  END IF;

  b := public.clan_boss_personal_ensure(v_uid, v_clan);
  IF b.id IS NULL THEN
    dl := public.clan_boss_personal_daily(v_uid);
    RAISE EXCEPTION 'CLAN_BOSS_DAILY_LIMIT'
      USING DETAIL = COALESCE(dl->>'secondsToReset', '0'),
            HINT = 'next_reset_in_seconds=' || COALESCE(dl->>'secondsToReset', '0');
  END IF;
  IF p_instance_id IS NOT NULL AND p_instance_id <> b.id THEN RAISE EXCEPTION 'CLAN_BOSS_STALE'; END IF;

  SELECT * INTO b FROM public.clan_boss_instances WHERE id = b.id FOR UPDATE;
  IF b.user_id <> v_uid THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
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
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_boss_damage', v_damage::bigint);
  dl := public.clan_boss_personal_daily(v_uid);

  RETURN jsonb_build_object('status','ok', 'damage', v_damage, 'critical', v_crit,
    'currentHp', GREATEST(0, b.current_hp), 'maxHp', b.max_hp, 'defeated', v_defeated,
    'rawDamage', v_raw, 'bossDef', b.boss_def, 'bossAtk', b.boss_atk,
    'difficulty', b.difficulty, 'daily', dl,
    'damageBeforePet', v_base, 'petBossDamagePercent', v_bonus, 'attackType', v_type,
    'nextAttackAt', now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)));
END $$;

-- 10) state read ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_clan_boss(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; c public.clans%rowtype;
        b public.clan_boss_instances; d public.clan_boss_damage; v_next timestamptz;
        tpl public.clan_boss_templates; v_total integer; v_last integer; dl jsonb;
        v_prev public.clan_boss_instances; prof public.clan_boss_player_profile; v_day date;
BEGIN
  cfg := public.clan_boss_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  SELECT count(*)::int, COALESCE(MAX(cycle_number),0) INTO v_total, v_last
    FROM public.clan_boss_templates WHERE enabled;
  IF v_clan IS NULL THEN
    RETURN jsonb_build_object('inClan', false, 'bossName', cfg.boss_name, 'bossKey', cfg.boss_key,
      'personal', true, 'totalBosses', v_total,
      'autoAttack', public.clan_boss_auto_attack_state_json(v_uid), 'serverTime', now());
  END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;
  b := public.clan_boss_personal_ensure(v_uid, v_clan);
  dl := public.clan_boss_personal_daily(v_uid);
  SELECT * INTO prof FROM public.clan_boss_player_profile WHERE user_id = v_uid;
  v_day := public.clan_boss_reset_day(now());

  IF b.id IS NULL THEN
    SELECT * INTO v_prev FROM public.clan_boss_instances
     WHERE user_id = v_uid ORDER BY starts_at DESC LIMIT 1;
    RETURN jsonb_build_object(
      'inClan', true, 'personal', true, 'totalBosses', v_total,
      'autoAttack', public.clan_boss_auto_attack_state_json(v_uid),
      'clan', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'level', c.level, 'emblem', c.emblem_config),
      'daily', dl, 'cycleLocked', true,
      'nextBossAt', dl->>'resetAt',
      'nextBossInSeconds', COALESCE((dl->>'secondsToReset')::int, 0),
      'profile', CASE WHEN prof.user_id IS NULL THEN NULL ELSE jsonb_build_object(
        'recommendedHp', prof.recommended_hp, 'difficulty', prof.difficulty_rating,
        'officialPower', prof.official_power, 'avgDamage', prof.recent_avg_damage) END,
      'lastBoss', CASE WHEN v_prev.id IS NULL THEN NULL ELSE jsonb_build_object(
        'name', v_prev.boss_name, 'cycle', v_prev.cycle, 'status', v_prev.status,
        'maxHp', v_prev.max_hp, 'totalDamage', v_prev.total_damage,
        'bossPower', v_prev.boss_power, 'finishedAt', v_prev.finished_at,
        'durationSeconds', v_prev.actual_duration_seconds) END,
      'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'cycle', h.cycle, 'status', h.status, 'maxHp', h.max_hp, 'totalDamage', h.total_damage,
          'bossName', h.boss_name, 'bossKey', h.boss_key, 'clanXp', h.clan_xp_awarded,
          'finishedAt', h.finished_at) ORDER BY h.cycle DESC)
        FROM public.clan_boss_instances h WHERE h.user_id = v_uid AND h.status <> 'active'), '[]'::jsonb),
      'serverTime', now());
  END IF;

  tpl := public.clan_boss_template_for_cycle(b.cycle);
  SELECT * INTO d FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid;
  v_next := COALESCE(d.last_attack_at, to_timestamp(0)) + make_interval(secs => GREATEST(1, cfg.cooldown_seconds));

  RETURN jsonb_build_object(
    'inClan', true, 'personal', true,
    'totalBosses', v_total, 'cycleLocked', false, 'daily', dl,
    'autoAttack', public.clan_boss_auto_attack_state_json(v_uid),
    'clan', jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'level', c.level, 'emblem', c.emblem_config),
    'boss', jsonb_build_object(
      'id', b.id, 'key', b.boss_key, 'name', b.boss_name, 'cycle', b.cycle, 'level', b.level,
      'maxHp', b.max_hp, 'currentHp', b.current_hp, 'status', b.status,
      'startsAt', b.starts_at, 'endsAt', b.ends_at, 'cycleEndsAt', b.cycle_ends_at,
      'def', b.boss_def, 'atk', b.boss_atk, 'power', b.boss_power,
      'difficulty', b.difficulty, 'bossNumberToday', b.boss_number_today,
      'subtitle', COALESCE(tpl.subtitle, ''), 'theme', COALESCE(tpl.theme, 'abyss'),
      'imageUrl', tpl.image_url, 'backgroundUrl', tpl.background_url,
      'baseDamage', COALESCE(tpl.base_damage, 0), 'rewardFc', COALESCE((b.rewards_snapshot->>'fcPool')::numeric, 0),
      'bossNumber', COALESCE(tpl.cycle_number, b.cycle),
      'isFinal', COALESCE(tpl.cycle_number, 0) >= v_last,
      'clanDamage', COALESCE(b.total_damage, 0),
      'attacks', COALESCE(b.attacks, 0),
      'participants', 1,
      'minDamageForRewards', GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'clanXpReward', COALESCE((b.rewards_snapshot->>'clanXp')::integer, cfg.clan_xp_reward),
      'cooldownSeconds', cfg.cooldown_seconds
    ),
    'me', jsonb_build_object(
      'damage', COALESCE(d.damage, 0), 'attacks', COALESCE(d.attacks, 0), 'rank', NULL,
      'nextAttackAt', CASE WHEN d.last_attack_at IS NULL THEN NULL ELSE v_next END,
      'canAttack', b.status = 'active' AND b.current_hp > 0 AND (d.last_attack_at IS NULL OR v_next <= now()),
      'eligibleForRewards', COALESCE(d.damage,0) >= GREATEST(0, round(b.max_hp * cfg.min_damage_pct / 100.0)),
      'power', public.clan_player_power(v_uid),
      'difficulty', b.difficulty
    ),
    -- clan-wide social ranking for the current server day (each boss stays private)
    'ranking', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'damage')::numeric DESC) FROM (
        SELECT jsonb_build_object('userId', i.user_id,
          'name', COALESCE(g.display_name, g.first_name, g.username, 'Player'),
          'username', g.username, 'avatar', g.avatar_url,
          'damage', SUM(i.total_damage), 'attacks', SUM(i.attacks),
          'isMe', i.user_id = v_uid) x
        FROM public.clan_boss_instances i JOIN public.game_players g ON g.id = i.user_id
        WHERE i.clan_id = v_clan AND i.user_id IS NOT NULL AND i.starts_at > now() - interval '24 hours'
        GROUP BY i.user_id, g.display_name, g.first_name, g.username, g.avatar_url
        ORDER BY SUM(i.total_damage) DESC LIMIT 50) s), '[]'::jsonb),
    'rewards', COALESCE(b.rewards_snapshot, cfg.rewards),
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'cycle', h.cycle, 'status', h.status, 'maxHp', h.max_hp, 'totalDamage', h.total_damage,
        'bossName', h.boss_name, 'bossKey', h.boss_key,
        'clanXp', h.clan_xp_awarded, 'finishedAt', h.finished_at,
        'topName', NULL, 'topDamage', h.total_damage) ORDER BY h.cycle DESC)
      FROM public.clan_boss_instances h
      WHERE h.user_id = v_uid AND h.status <> 'active'), '[]'::jsonb),
    'serverTime', now()
  );
END $$;

-- 11) auto attack sees the personal boss ---------------------------------
CREATE OR REPLACE FUNCTION public.clan_boss_auto_attack_state_json(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE a public.clan_boss_auto_attack%rowtype; cfg public.clan_boss_config;
        v_tier text; v_team boolean; v_clan uuid; v_boss boolean; v_reason text;
        v_revive timestamptz; v_next timestamptz; dl jsonb;
BEGIN
  IF p_user IS NULL THEN RETURN jsonb_build_object('eligible',false,'enabled',false,'active',false,'reason','no_pass'); END IF;
  cfg := public.clan_boss_cfg();
  INSERT INTO public.clan_boss_auto_attack(user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO a FROM public.clan_boss_auto_attack WHERE user_id = p_user;
  v_tier := public.global_boss_auto_pass_tier(p_user);
  v_team := public.clan_player_power(p_user) > 0;
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = p_user;
  dl := public.clan_boss_personal_daily(p_user);
  v_boss := v_clan IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.clan_boss_instances
             WHERE user_id = p_user AND status = 'active' AND current_hp > 0 AND ends_at > now())
    OR NOT (dl->>'limitReached')::boolean);
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
    'attacksTotal', a.attacks_total, 'reason', v_reason, 'daily', dl);
END $$;

CREATE OR REPLACE FUNCTION public.clan_boss_auto_attack_one(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE cfg public.clan_boss_config; r record; v_tier text; v_next timestamptz;
        v_last timestamptz; v_retry timestamptz; v_err text; v_reason text; dl jsonb;
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
  dl := public.clan_boss_personal_daily(r.uid);
  IF v_tier IS NULL OR r.clan_id IS NULL OR public.clan_player_power(r.uid) <= 0
     OR ((dl->>'limitReached')::boolean
         AND NOT EXISTS (SELECT 1 FROM public.clan_boss_instances
                          WHERE user_id = r.uid AND status = 'active' AND current_hp > 0 AND ends_at > now())) THEN
    v_reason := CASE WHEN v_tier IS NULL THEN 'no_pass' WHEN r.clan_id IS NULL THEN 'no_clan'
                     WHEN public.clan_player_power(r.uid) <= 0 THEN 'no_team' ELSE 'daily_limit' END;
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
    SELECT d.last_attack_at INTO v_last FROM public.clan_boss_damage d
      JOIN public.clan_boss_instances i ON i.id = d.instance_id
     WHERE d.user_id = r.uid AND i.user_id = r.uid AND i.status = 'active'
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
END $$;

-- 12) admin surface ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_clan_boss_personal(
  p_admin_id bigint, p_action text DEFAULT 'overview', p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE pc public.clan_boss_personal_config; v_uid uuid; v_num numeric; v_day date;
        prof public.clan_boss_player_profile; b public.clan_boss_instances; g public.game_players%rowtype;
        v_clan text; dl jsonb; s jsonb; v_ref text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  pc := public.clan_boss_personal_cfg();
  v_day := public.clan_boss_reset_day(now());
  v_ref := NULLIF(trim(COALESCE(p_ref, '')), '');

  -- player lookup: telegram id / @username / internal uuid
  IF v_ref IS NOT NULL AND p_action <> 'set' THEN
    SELECT * INTO g FROM public.game_players
     WHERE (v_ref ~ '^[0-9]+$' AND telegram_id = v_ref::bigint)
        OR lower(username) = lower(ltrim(v_ref, '@'))
        OR (v_ref ~* '^[0-9a-f-]{36}$' AND id = v_ref::uuid)
     LIMIT 1;
    v_uid := g.id;
  END IF;

  IF p_action = 'set' THEN
    v_num := COALESCE((p_payload->>'value')::numeric, 0);
    UPDATE public.clan_boss_personal_config SET
      enabled = CASE WHEN p_ref='enabled' THEN COALESCE((p_payload->>'value')::boolean, enabled) ELSE enabled END,
      daily_limit = CASE WHEN p_ref='daily_limit' THEN GREATEST(0, LEAST(50, v_num))::int ELSE daily_limit END,
      reset_hour_utc = CASE WHEN p_ref='reset_hour_utc' THEN GREATEST(0, LEAST(23, v_num))::int ELSE reset_hour_utc END,
      boss_duration_hours = CASE WHEN p_ref='boss_duration_hours' THEN GREATEST(1, LEAST(168, v_num))::int ELSE boss_duration_hours END,
      target_attacks_per_boss = CASE WHEN p_ref='target_attacks_per_boss' THEN GREATEST(3, LEAST(200, v_num))::int ELSE target_attacks_per_boss END,
      very_easy_pct = CASE WHEN p_ref='very_easy_pct' THEN v_num ELSE very_easy_pct END,
      easy_pct = CASE WHEN p_ref='easy_pct' THEN v_num ELSE easy_pct END,
      balanced_pct = CASE WHEN p_ref='balanced_pct' THEN v_num ELSE balanced_pct END,
      hard_pct = CASE WHEN p_ref='hard_pct' THEN v_num ELSE hard_pct END,
      very_hard_pct = CASE WHEN p_ref='very_hard_pct' THEN v_num ELSE very_hard_pct END,
      max_scale_up = CASE WHEN p_ref='max_scale_up' THEN GREATEST(1, LEAST(5, v_num)) ELSE max_scale_up END,
      max_scale_down = CASE WHEN p_ref='max_scale_down' THEN GREATEST(0.1, LEAST(1, v_num)) ELSE max_scale_down END,
      capacity_floor = CASE WHEN p_ref='capacity_floor' THEN GREATEST(0.05, LEAST(1, v_num)) ELSE capacity_floor END,
      capacity_ceiling = CASE WHEN p_ref='capacity_ceiling' THEN GREATEST(1, LEAST(10, v_num)) ELSE capacity_ceiling END,
      min_hp = CASE WHEN p_ref='min_hp' THEN GREATEST(1000, v_num) ELSE min_hp END,
      max_hp = CASE WHEN p_ref='max_hp' THEN GREATEST(100000, v_num) ELSE max_hp END,
      def_mitigation_target = CASE WHEN p_ref='def_mitigation_target' THEN GREATEST(0, LEAST(0.6, v_num)) ELSE def_mitigation_target END,
      atk_ratio = CASE WHEN p_ref='atk_ratio' THEN GREATEST(0.01, LEAST(5, v_num)) ELSE atk_ratio END,
      outlier_median_factor = CASE WHEN p_ref='outlier_median_factor' THEN GREATEST(2, LEAST(100, v_num)) ELSE outlier_median_factor END,
      history_samples = CASE WHEN p_ref='history_samples' THEN GREATEST(1, LEAST(50, v_num))::int ELSE history_samples END,
      fc_pool_pct = CASE WHEN p_ref='fc_pool_pct' THEN GREATEST(0, LEAST(1000, v_num)) ELSE fc_pool_pct END,
      difficulty_bonus_enabled = CASE WHEN p_ref='difficulty_bonus_enabled' THEN COALESCE((p_payload->>'value')::boolean, difficulty_bonus_enabled) ELSE difficulty_bonus_enabled END,
      scaling_version = CASE WHEN p_ref='scaling_version' THEN GREATEST(1, v_num)::int ELSE scaling_version END,
      updated_at = now()
    WHERE id = 1;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_set', 'clan_boss', p_ref, NULL::jsonb, p_payload, 'painel admin', '{}'::jsonb);
    RETURN to_jsonb(public.clan_boss_personal_cfg());
  END IF;

  IF p_action = 'report' THEN
    RETURN jsonb_build_object(
      'config', to_jsonb(pc), 'day', v_day,
      'players', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT jsonb_build_object(
          'userId', p.user_id, 'username', gp.username, 'name', COALESCE(gp.display_name, gp.first_name, gp.username),
          'telegramId', gp.telegram_id,
          'power', p.official_power, 'recommendedHp', p.recommended_hp,
          'difficulty', p.difficulty_rating, 'lastQuality', p.last_quality,
          'avgClearSeconds', p.recent_avg_clear_time, 'avgDamage', p.recent_avg_damage,
          'override', p.daily_limit_override,
          'currentBossHp', (SELECT i.current_hp FROM public.clan_boss_instances i
                             WHERE i.user_id = p.user_id AND i.status = 'active' LIMIT 1),
          'bossesToday', COALESCE((SELECT dc.defeated_count FROM public.clan_boss_daily_counters dc
                                    WHERE dc.user_id = p.user_id AND dc.reset_day = v_day), 0)) x
        FROM public.clan_boss_player_profile p
        JOIN public.game_players gp ON gp.id = p.user_id
        ORDER BY p.recommended_hp DESC LIMIT GREATEST(1, LEAST(100, COALESCE((p_payload->>'limit')::int, 20)))) s), '[]'::jsonb));
  END IF;

  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'player_not_found', 'ref', p_ref); END IF;

  IF p_action = 'set_limit' THEN
    INSERT INTO public.clan_boss_player_profile(user_id, daily_limit_override)
    VALUES (v_uid, GREATEST(0, LEAST(50, COALESCE((p_payload->>'value')::int, pc.daily_limit))))
    ON CONFLICT (user_id) DO UPDATE SET daily_limit_override = EXCLUDED.daily_limit_override, updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_limit', 'player', v_uid::text, NULL::jsonb, p_payload, 'painel admin', '{}'::jsonb);
  ELSIF p_action = 'clear_limit' THEN
    UPDATE public.clan_boss_player_profile SET daily_limit_override = NULL, updated_at = now() WHERE user_id = v_uid;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_limit_clear', 'player', v_uid::text, NULL::jsonb, '{}'::jsonb, 'painel admin', '{}'::jsonb);
  ELSIF p_action = 'reset_daily' THEN
    DELETE FROM public.clan_boss_daily_counters WHERE user_id = v_uid AND reset_day = v_day;
    PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_reset', 'player', v_uid::text, NULL::jsonb, '{}'::jsonb, 'painel admin', '{}'::jsonb);
  ELSIF p_action = 'recalculate' THEN
    SELECT * INTO b FROM public.clan_boss_instances WHERE user_id = v_uid AND status = 'active' LIMIT 1;
    IF b.id IS NOT NULL THEN
      UPDATE public.clan_boss_instances SET status = 'expired', finished_at = now() WHERE id = b.id;
    END IF;
    s := public.clan_boss_profile_persist(v_uid);
    PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_recalc', 'player', v_uid::text, NULL::jsonb, s, 'painel admin', '{}'::jsonb);
  ELSIF p_action = 'history' THEN
    RETURN jsonb_build_object('userId', v_uid, 'username', g.username,
      'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'bossNumber', h.boss_number_today, 'hp', h.effective_hp, 'def', h.effective_def, 'atk', h.effective_atk,
        'power', h.player_power, 'attacks', h.attack_count, 'avgDamage', h.avg_damage_per_attack,
        'maxHit', h.max_hit, 'clearSeconds', h.actual_duration_seconds, 'quality', h.quality,
        'status', h.final_status, 'difficulty', h.difficulty, 'at', h.created_at) ORDER BY h.created_at DESC)
        FROM (SELECT * FROM public.clan_boss_performance_history
               WHERE user_id = v_uid ORDER BY created_at DESC LIMIT 15) h), '[]'::jsonb));
  END IF;

  SELECT * INTO prof FROM public.clan_boss_player_profile WHERE user_id = v_uid;
  SELECT * INTO b FROM public.clan_boss_instances WHERE user_id = v_uid AND status = 'active' LIMIT 1;
  SELECT c.name INTO v_clan FROM public.clan_members m JOIN public.clans c ON c.id = m.clan_id WHERE m.user_id = v_uid;
  dl := public.clan_boss_personal_daily(v_uid);

  RETURN jsonb_build_object(
    'userId', v_uid, 'telegramId', g.telegram_id, 'username', g.username,
    'name', COALESCE(g.display_name, g.first_name, g.username), 'clan', v_clan,
    'officialPower', COALESCE(prof.official_power, public.clan_player_power(v_uid)),
    'bossPower', COALESCE(b.boss_power, 0),
    'currentBossHp', COALESCE(b.current_hp, 0), 'currentBossMaxHp', COALESCE(b.max_hp, 0),
    'difficulty', COALESCE(b.difficulty, prof.difficulty_rating),
    'recommendedHp', COALESCE(prof.recommended_hp, 0),
    'avgClearSeconds', prof.recent_avg_clear_time, 'avgDamage', prof.recent_avg_damage,
    'lastQuality', prof.last_quality,
    'daily', dl, 'globalLimit', pc.daily_limit, 'override', prof.daily_limit_override,
    'config', to_jsonb(pc));
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_clan_boss_personal(bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_personal_cfg() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_personal_scaling(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_player_metrics(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_profile_persist(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_personal_ensure(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_personal_daily(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_reset_day(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.clan_boss_next_reset_at(timestamptz) FROM PUBLIC, anon, authenticated;