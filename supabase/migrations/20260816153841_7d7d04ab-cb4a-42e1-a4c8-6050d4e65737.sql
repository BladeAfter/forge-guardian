-- Base combat stats live on the template and are NEVER touched by the difficulty multipliers,
-- so a restart/rotation always recomputes from base (no cumulative 4x -> 16x -> 64x).
ALTER TABLE public.global_boss_templates
  ADD COLUMN IF NOT EXISTS base_defense numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS base_attack numeric NOT NULL DEFAULT 0;

UPDATE public.global_boss_templates
   SET base_defense = CASE WHEN base_defense > 0 THEN base_defense ELSE 1000 + (boss_number - 1) * 500 END,
       base_attack  = CASE WHEN base_attack  > 0 THEN base_attack  ELSE 300 + (boss_number - 1) * 90 END,
       updated_at = now()
 WHERE base_defense <= 0 OR base_attack <= 0;

ALTER TABLE public.global_boss_cycles
  ADD COLUMN IF NOT EXISTS boss_defense numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS boss_attack numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hp_multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS defense_multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS atk_multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS rotation_number integer NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION public.global_boss_setting_num(p_key text, p_default numeric)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT (value #>> '{}')::numeric FROM public.game_settings WHERE key = p_key), p_default);
$$;

CREATE OR REPLACE FUNCTION public.global_boss_difficulty()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'hpMultiplier', greatest(0.1, public.global_boss_setting_num('global_boss_hp_multiplier', 4.0)),
    'defenseMultiplier', greatest(0, public.global_boss_setting_num('global_boss_defense_multiplier', 3.0)),
    'atkMultiplier', greatest(0.1, public.global_boss_setting_num('global_boss_atk_multiplier', 1.25)),
    'defenseSoftness', greatest(100, public.global_boss_setting_num('global_boss_defense_softness', 6000)),
    'defenseCapPercent', least(80, greatest(0, public.global_boss_setting_num('global_boss_defense_cap_percent', 60)))
  );
$$;

-- Official mitigation: def/(def+softness), capped, and never able to zero out legit damage.
CREATE OR REPLACE FUNCTION public.global_boss_damage_factor(p_defense numeric)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT round(greatest(0.2,
    1 - least((s.d->>'defenseCapPercent')::numeric / 100,
              greatest(0, coalesce(p_defense, 0))
              / (greatest(0, coalesce(p_defense, 0)) + (s.d->>'defenseSoftness')::numeric))), 6)
  FROM (SELECT public.global_boss_difficulty() AS d) s;
$$;

CREATE OR REPLACE FUNCTION public.global_boss_effective_stats(p_number integer)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'bossNumber', t.boss_number, 'code', t.code, 'name', t.name,
    'baseHp', t.max_hp, 'baseDefense', t.base_defense, 'baseAttack', t.base_attack,
    'maxHp', round(t.max_hp * (s.d->>'hpMultiplier')::numeric),
    'defense', round(t.base_defense * (s.d->>'defenseMultiplier')::numeric),
    'attack', round(t.base_attack * (s.d->>'atkMultiplier')::numeric),
    'hpMultiplier', (s.d->>'hpMultiplier')::numeric,
    'defenseMultiplier', (s.d->>'defenseMultiplier')::numeric,
    'atkMultiplier', (s.d->>'atkMultiplier')::numeric,
    'damageFactor', public.global_boss_damage_factor(round(t.base_defense * (s.d->>'defenseMultiplier')::numeric))
  )
  FROM public.global_boss_templates t, (SELECT public.global_boss_difficulty() AS d) s
  WHERE t.boss_number = greatest(1, coalesce(p_number, 1));
$$;

-- Rotation now wraps back to boss #1 forever and always stores EFFECTIVE stats derived from base.
CREATE OR REPLACE FUNCTION public.ensure_global_boss_cycle()
RETURNS public.global_boss_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; b public.boss_templates; t public.global_boss_templates;
        v_pool numeric; v_next int; v_last public.global_boss_cycles; v_reason text; v_seconds int;
        v_max int; v_rotation int; v_stats jsonb;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NOT NULL THEN
    IF cyc.ends_at IS NOT NULL AND cyc.ends_at <= now() THEN
      v_reason := CASE WHEN cyc.current_hp > 0 THEN 'expired' ELSE 'defeated' END;
      UPDATE public.global_boss_cycles
         SET status = CASE WHEN v_reason = 'expired' THEN 'expired' ELSE 'defeated' END,
             ended_reason = v_reason,
             defeated_at = CASE WHEN v_reason = 'defeated' THEN COALESCE(defeated_at, now()) ELSE defeated_at END,
             updated_at = now()
       WHERE id = cyc.id RETURNING * INTO cyc;
      PERFORM public.distribute_global_boss_rewards(cyc.id);
      RETURN NULL;
    END IF;
    RETURN cyc;
  END IF;

  SELECT * INTO v_last FROM public.global_boss_cycles ORDER BY cycle_number DESC LIMIT 1;
  SELECT COALESCE(max(boss_number), 0) INTO v_max FROM public.global_boss_templates WHERE enabled;
  IF v_max < 1 THEN RETURN NULL; END IF;
  v_next := COALESCE(v_last.boss_number, 0) + 1;
  v_rotation := COALESCE(v_last.rotation_number, 1);
  IF v_next > v_max THEN v_next := 1; v_rotation := v_rotation + 1; END IF;

  t := public.global_boss_template_for_number(v_next);
  IF t.id IS NULL THEN RETURN NULL; END IF;
  b := public.active_boss_template();
  v_pool := t.reward_fc;
  v_seconds := GREATEST(300, COALESCE(t.duration_seconds, 86400));
  v_stats := public.global_boss_effective_stats(t.boss_number);

  INSERT INTO public.global_boss_cycles
    (cycle_number, boss_key, boss_name, boss_image, boss_level, max_hp, current_hp, reward_pool_fc,
     starts_at, ends_at, template_id, boss_number, boss_subtitle, boss_theme, boss_background,
     boss_defense, boss_attack, hp_multiplier, defense_multiplier, atk_multiplier, rotation_number)
  VALUES ((SELECT COALESCE(max(cycle_number), 0) + 1 FROM public.global_boss_cycles),
          COALESCE(t.code, b.code), t.name, t.image_url, t.boss_level,
          (v_stats->>'maxHp')::numeric, (v_stats->>'maxHp')::numeric, v_pool,
          now(), now() + make_interval(secs => v_seconds),
          t.id, t.boss_number, t.subtitle, t.theme, t.background_url,
          (v_stats->>'defense')::numeric, (v_stats->>'attack')::numeric,
          (v_stats->>'hpMultiplier')::numeric, (v_stats->>'defenseMultiplier')::numeric,
          (v_stats->>'atkMultiplier')::numeric, v_rotation)
  ON CONFLICT DO NOTHING
  RETURNING * INTO cyc;
  IF cyc.id IS NULL THEN SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1; END IF;

  IF cyc.id IS NOT NULL THEN
    UPDATE public.boss_templates
       SET active = true, starts_at = cyc.starts_at, ends_at = cyc.ends_at, updated_at = now()
     WHERE id = (SELECT id FROM public.boss_templates ORDER BY created_at DESC LIMIT 1);
  END IF;

  RETURN cyc;
END; $$;

-- Admin: adjust multipliers without deploy. Always recomputed from BASE stats.
CREATE OR REPLACE FUNCTION public.admin_global_boss_multiplier(p_admin_id bigint, p_kind text, p_value numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_kind text := lower(coalesce(p_kind, '')); v_key text; v_old numeric;
        cyc public.global_boss_cycles; v_stats jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_key := CASE
    WHEN v_kind IN ('hp', 'hp_multiplier') THEN 'global_boss_hp_multiplier'
    WHEN v_kind IN ('def', 'defense', 'defense_multiplier') THEN 'global_boss_defense_multiplier'
    WHEN v_kind IN ('atk', 'attack', 'atk_multiplier') THEN 'global_boss_atk_multiplier'
  END;
  IF v_key IS NULL THEN RAISE EXCEPTION 'invalid_kind'; END IF;
  IF coalesce(p_value, 0) < 0.1 OR p_value > 100 THEN RAISE EXCEPTION 'invalid_value'; END IF;

  v_old := public.global_boss_setting_num(v_key, NULL);
  INSERT INTO public.game_settings(category, key, label, value)
  VALUES ('boss', v_key, 'Global Boss ' || v_kind || ' multiplier', to_jsonb(p_value))
  ON CONFLICT (key) DO UPDATE SET value = to_jsonb(p_value), updated_at = now();

  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NOT NULL THEN
    v_stats := public.global_boss_effective_stats(cyc.boss_number);
    UPDATE public.global_boss_cycles
       SET max_hp = (v_stats->>'maxHp')::numeric,
           current_hp = LEAST(current_hp, (v_stats->>'maxHp')::numeric),
           boss_defense = (v_stats->>'defense')::numeric,
           boss_attack = (v_stats->>'attack')::numeric,
           hp_multiplier = (v_stats->>'hpMultiplier')::numeric,
           defense_multiplier = (v_stats->>'defenseMultiplier')::numeric,
           atk_multiplier = (v_stats->>'atkMultiplier')::numeric,
           updated_at = now()
     WHERE id = cyc.id RETURNING * INTO cyc;
  END IF;

  PERFORM public.admin_log(p_admin_id, 'GLOBAL_BOSS_MULTIPLIER_UPDATED', 'global_boss', v_key,
    jsonb_build_object('value', v_old), jsonb_build_object('value', p_value), p_reason,
    jsonb_build_object('kind', v_kind, 'cycleId', cyc.id, 'dangerous', true));

  RETURN jsonb_build_object('kind', v_kind, 'key', v_key, 'oldValue', v_old, 'value', p_value,
    'difficulty', public.global_boss_difficulty(),
    'cycle', CASE WHEN cyc.id IS NULL THEN NULL ELSE jsonb_build_object('cycleId', cyc.id,
      'bossNumber', cyc.boss_number, 'name', cyc.boss_name, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp,
      'defense', cyc.boss_defense, 'attack', cyc.boss_attack) END);
END; $$;

-- Admin: close the running cycle (history/rewards preserved) and start a brand-new rotation at boss #1.
CREATE OR REPLACE FUNCTION public.admin_global_boss_restart_rotation(p_admin_id bigint, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_prev public.global_boss_cycles; v_new public.global_boss_cycles; t public.global_boss_templates;
        v_stats jsonb; v_rotation int; v_seconds int; v_extra jsonb := '{}'::jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  SELECT * INTO v_prev FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF v_prev.id IS NOT NULL THEN
    UPDATE public.global_boss_cycles
       SET status = 'completed',
           ended_reason = COALESCE(ended_reason, 'rotation_restart'),
           defeated_at = COALESCE(defeated_at, CASE WHEN current_hp <= 0 THEN now() END),
           updated_at = now()
     WHERE id = v_prev.id;
    v_extra := public.distribute_global_boss_rewards(v_prev.id);
  END IF;

  SELECT * INTO t FROM public.global_boss_templates WHERE enabled ORDER BY boss_number LIMIT 1;
  IF t.id IS NULL THEN RAISE EXCEPTION 'no_enabled_boss'; END IF;
  v_stats := public.global_boss_effective_stats(t.boss_number);
  v_seconds := GREATEST(300, COALESCE(t.duration_seconds, 86400));
  SELECT COALESCE(max(rotation_number), 1) + 1 INTO v_rotation FROM public.global_boss_cycles;

  INSERT INTO public.global_boss_cycles
    (cycle_number, boss_key, boss_name, boss_image, boss_level, max_hp, current_hp, reward_pool_fc,
     starts_at, ends_at, template_id, boss_number, boss_subtitle, boss_theme, boss_background,
     boss_defense, boss_attack, hp_multiplier, defense_multiplier, atk_multiplier, rotation_number, status)
  VALUES ((SELECT COALESCE(max(cycle_number), 0) + 1 FROM public.global_boss_cycles),
          t.code, t.name, t.image_url, t.boss_level,
          (v_stats->>'maxHp')::numeric, (v_stats->>'maxHp')::numeric, t.reward_fc,
          now(), now() + make_interval(secs => v_seconds),
          t.id, t.boss_number, t.subtitle, t.theme, t.background_url,
          (v_stats->>'defense')::numeric, (v_stats->>'attack')::numeric,
          (v_stats->>'hpMultiplier')::numeric, (v_stats->>'defenseMultiplier')::numeric,
          (v_stats->>'atkMultiplier')::numeric, v_rotation, 'active')
  RETURNING * INTO v_new;

  UPDATE public.boss_templates
     SET active = true, starts_at = v_new.starts_at, ends_at = v_new.ends_at, updated_at = now()
   WHERE id = (SELECT id FROM public.boss_templates ORDER BY created_at DESC LIMIT 1);

  PERFORM public.admin_log(p_admin_id, 'GLOBAL_BOSS_ROTATION_RESTARTED', 'global_boss', v_new.id::text,
    CASE WHEN v_prev.id IS NULL THEN NULL ELSE jsonb_build_object('cycleId', v_prev.id,
      'bossNumber', v_prev.boss_number, 'name', v_prev.boss_name) END,
    jsonb_build_object('cycleId', v_new.id, 'bossNumber', v_new.boss_number, 'name', v_new.boss_name,
      'maxHp', v_new.max_hp, 'defense', v_new.boss_defense, 'attack', v_new.boss_attack,
      'hpMultiplier', v_new.hp_multiplier, 'defenseMultiplier', v_new.defense_multiplier,
      'atkMultiplier', v_new.atk_multiplier, 'rotationNumber', v_new.rotation_number,
      'distribution', v_extra),
    p_reason, jsonb_build_object('dangerous', true));

  RETURN jsonb_build_object('previousCycleId', v_prev.id, 'previousBossNumber', v_prev.boss_number,
    'newCycleId', v_new.id, 'cycleNumber', v_new.cycle_number, 'rotationNumber', v_new.rotation_number,
    'bossNumber', v_new.boss_number, 'name', v_new.boss_name, 'maxHp', v_new.max_hp,
    'defense', v_new.boss_defense, 'attack', v_new.boss_attack, 'rewardPoolFc', v_new.reward_pool_fc,
    'endsAt', v_new.ends_at, 'difficulty', public.global_boss_difficulty(), 'distribution', v_extra);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_global_boss_difficulty(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; v_max int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  SELECT COALESCE(max(boss_number), 1) INTO v_max FROM public.global_boss_templates WHERE enabled;
  RETURN jsonb_build_object(
    'difficulty', public.global_boss_difficulty(),
    'bossCount', v_max,
    'first', public.global_boss_effective_stats(1),
    'last', public.global_boss_effective_stats(v_max),
    'cycle', CASE WHEN cyc.id IS NULL THEN NULL ELSE jsonb_build_object('cycleId', cyc.id,
      'cycleNumber', cyc.cycle_number, 'rotationNumber', cyc.rotation_number, 'bossNumber', cyc.boss_number,
      'name', cyc.boss_name, 'status', cyc.status, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp,
      'defense', cyc.boss_defense, 'attack', cyc.boss_attack,
      'damageFactor', public.global_boss_damage_factor(cyc.boss_defense),
      'participants', cyc.participants, 'totalDamage', cyc.total_damage) END);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_global_boss_roster(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_active_number int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT boss_number INTO v_active_number FROM public.global_boss_cycles WHERE status='active' LIMIT 1;
  RETURN jsonb_build_object(
    'activeBossNumber', v_active_number,
    'difficulty', public.global_boss_difficulty(),
    'bosses', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'bossNumber', t.boss_number, 'code', t.code, 'name', t.name, 'subtitle', t.subtitle,
        'theme', t.theme, 'maxHp', t.max_hp, 'rewardFc', t.reward_fc,
        'durationSeconds', t.duration_seconds, 'enabled', t.enabled,
        'image', t.image_url, 'background', t.background_url,
        'baseDefense', t.base_defense, 'baseAttack', t.base_attack,
        'effective', public.global_boss_effective_stats(t.boss_number),
        'current', t.boss_number = v_active_number
      ) ORDER BY t.boss_number)
      FROM public.global_boss_templates t), '[]'::jsonb)
  );
END; $$;