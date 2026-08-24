ALTER TABLE public.clan_boss_scaling_config
  ADD COLUMN IF NOT EXISTS max_hp_cap numeric NOT NULL DEFAULT 1500000000;

UPDATE public.clan_boss_scaling_config SET max_hp_cap = 1500000000, updated_at = now() WHERE id = 1;

CREATE OR REPLACE FUNCTION public.clan_boss_compute_scaling(p_clan_id uuid, p_cycle integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE sc public.clan_boss_scaling_config; cfg public.clan_boss_config;
        tpl public.clan_boss_templates; prof public.clan_boss_scaling_profiles;
        d jsonb; m jsonb; v_cycle integer;
        v_base_hp numeric; v_target_total numeric; v_target_hp numeric;
        v_mult numeric; v_prev numeric; v_calib numeric := 1; v_mode text := 'GRADUAL';
        v_hp numeric; v_def numeric; v_base_def numeric; v_atk numeric; v_base_atk numeric;
        v_avg_power numeric; v_tier text; v_last integer; v_kills integer;
        v_scaled_history boolean := false; v_cap numeric;
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

  SELECT EXISTS (
    SELECT 1 FROM public.clan_boss_performance_history h
     WHERE h.clan_id = p_clan_id
       AND COALESCE(h.scaling_version, 0) >= sc.scaling_version
       AND h.actual_duration_seconds IS NOT NULL
  ) INTO v_scaled_history;

  IF v_scaled_history AND v_last IS NOT NULL AND v_last > 0 THEN
    v_calib := LEAST(GREATEST(sc.target_duration_seconds::numeric / v_last, 0.25), 4);
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
  ELSIF NOT v_scaled_history THEN
    v_mode := CASE WHEN prof.clan_id IS NULL THEN 'INITIAL_REBASE' ELSE 'CAPACITY_REBASE' END;
  ELSIF v_kills >= GREATEST(1, sc.rebase_kills_threshold)
     OR v_last < sc.target_duration_seconds / 2 THEN
    v_mode := 'FULL_RECALIBRATION';
    v_mult := LEAST(v_mult, v_prev * GREATEST(2, sc.rebase_max_scale));
  ELSE
    v_mult := LEAST(GREATEST(v_mult, v_prev * sc.max_scale_down_per_cycle),
                    v_prev * sc.max_scale_up_per_cycle);
  END IF;
  v_mult := GREATEST(v_mult, 0.05);

  v_hp := round(v_base_hp * v_mult);

  -- Hard ceiling: no clan boss may ever be born with more HP than the configured cap.
  v_cap := GREATEST(1, COALESCE(sc.max_hp_cap, 1500000000));
  IF v_hp > v_cap THEN
    v_hp := round(v_cap);
    v_mult := v_hp / v_base_hp;
    v_mode := v_mode || '_CAPPED';
  END IF;

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
    'maxHpCap', v_cap,
    'baseDef', v_base_def, 'defMultiplier', GREATEST(0.1, sc.def_scaling), 'effectiveDef', v_def,
    'baseAtk', v_base_atk, 'atkMultiplier', GREATEST(0.1, sc.atk_scaling), 'effectiveAtk', v_atk,
    'bossPower', round(v_hp / 1000.0 + v_atk * 5 + v_def * 3 + v_cycle * 1000),
    'effectiveDps', (d->>'dps')::numeric,
    'capacity24h', (d->>'expected24hDamage')::numeric,
    'targetDurationSeconds', sc.target_duration_seconds,
    'expectedDurationSeconds', LEAST(259200, round(
        v_hp / GREATEST(1, (d->>'expected24hDamage')::numeric
              * LEAST(0.95, GREATEST(0.5, sc.hp_share)) / 86400.0))),
    'mode', v_mode, 'calibration', round(v_calib, 3), 'tier', v_tier,
    'scalingVersion', sc.scaling_version,
    'dps', d);
END $function$;

REVOKE ALL ON FUNCTION public.clan_boss_compute_scaling(uuid, integer) FROM PUBLIC, anon, authenticated;

-- Bring every live clan boss down to the cap, preserving the remaining HP percentage.
UPDATE public.clan_boss_instances
   SET current_hp = GREATEST(1, round(1500000000::numeric * (current_hp::numeric / GREATEST(1, max_hp::numeric)))),
       max_hp = 1500000000
 WHERE status = 'active' AND max_hp > 1500000000;

-- Keep per-clan multipliers from immediately re-inflating the next boss.
UPDATE public.clan_boss_scaling_profiles p
   SET hp_multiplier = LEAST(p.hp_multiplier,
        1500000000::numeric / GREATEST(1, (SELECT COALESCE(MAX(t.max_hp), 1) FROM public.clan_boss_templates t))),
       updated_at = now()
 WHERE p.hp_multiplier > 1500000000::numeric / GREATEST(1, (SELECT COALESCE(MAX(t.max_hp), 1) FROM public.clan_boss_templates t));