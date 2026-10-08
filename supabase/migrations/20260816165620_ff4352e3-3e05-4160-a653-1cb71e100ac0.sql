-- GLOBAL BOSS DIFFICULTY V2 — HP 12x, DEF 6x, ATK 1.50x, always computed from BASE template stats
-- (global_boss_templates.max_hp / base_defense / base_attack), so multipliers never compound.
CREATE OR REPLACE FUNCTION public.global_boss_difficulty()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'hpMultiplier', greatest(0.1, public.global_boss_setting_num('global_boss_hp_multiplier', 12.0)),
    'defenseMultiplier', greatest(0, public.global_boss_setting_num('global_boss_defense_multiplier', 6.0)),
    'atkMultiplier', greatest(0.1, public.global_boss_setting_num('global_boss_atk_multiplier', 1.50)),
    'defenseSoftness', greatest(100, public.global_boss_setting_num('global_boss_defense_softness', 6000)),
    'defenseCapPercent', least(80, greatest(0, public.global_boss_setting_num('global_boss_defense_cap_percent', 60)))
  );
$$;

-- Re-applies the current difficulty to the RUNNING cycle from BASE stats while PRESERVING every point
-- of damage already dealt (ranking/participants untouched): new_current = new_max - damage_dealt.
CREATE OR REPLACE FUNCTION public.global_boss_reapply_difficulty()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; v_stats jsonb; v_dealt numeric; v_new_max numeric; v_old_max numeric;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1 FOR UPDATE;
  IF cyc.id IS NULL THEN RETURN jsonb_build_object('cycle', NULL, 'difficulty', public.global_boss_difficulty()); END IF;

  v_stats := public.global_boss_effective_stats(cyc.boss_number);
  v_new_max := (v_stats->>'maxHp')::numeric;
  v_old_max := cyc.max_hp;
  -- Damage already dealt to THIS cycle, derived from the HP bar it was fought with.
  v_dealt := greatest(0, cyc.max_hp - greatest(0, cyc.current_hp));

  UPDATE public.global_boss_cycles
     SET max_hp = v_new_max,
         current_hp = greatest(0, v_new_max - v_dealt),
         boss_defense = (v_stats->>'defense')::numeric,
         boss_attack = (v_stats->>'attack')::numeric,
         hp_multiplier = (v_stats->>'hpMultiplier')::numeric,
         defense_multiplier = (v_stats->>'defenseMultiplier')::numeric,
         atk_multiplier = (v_stats->>'atkMultiplier')::numeric,
         updated_at = now()
   WHERE id = cyc.id RETURNING * INTO cyc;

  RETURN jsonb_build_object(
    'cycleId', cyc.id, 'bossNumber', cyc.boss_number, 'name', cyc.boss_name,
    'baseHp', (v_stats->>'baseHp')::numeric, 'previousMaxHp', v_old_max,
    'maxHp', cyc.max_hp, 'damagePreserved', v_dealt, 'currentHp', cyc.current_hp,
    'defense', cyc.boss_defense, 'attack', cyc.boss_attack,
    'damageFactor', public.global_boss_damage_factor(cyc.boss_defense),
    'difficulty', public.global_boss_difficulty());
END; $$;

-- Admin multiplier change now PRESERVES damage dealt instead of keeping the old remaining HP.
CREATE OR REPLACE FUNCTION public.admin_global_boss_multiplier(p_admin_id bigint, p_kind text, p_value numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_kind text := lower(coalesce(p_kind, '')); v_key text; v_old numeric; v_applied jsonb;
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

  v_applied := public.global_boss_reapply_difficulty();

  PERFORM public.admin_log(p_admin_id, 'GLOBAL_BOSS_MULTIPLIER_UPDATED', 'global_boss', v_key,
    jsonb_build_object('value', v_old), jsonb_build_object('value', p_value), p_reason,
    jsonb_build_object('kind', v_kind, 'applied', v_applied, 'dangerous', true));

  RETURN jsonb_build_object('kind', v_kind, 'key', v_key, 'oldValue', v_old, 'value', p_value,
    'difficulty', public.global_boss_difficulty(), 'cycle', v_applied);
END; $$;