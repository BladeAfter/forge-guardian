CREATE OR REPLACE FUNCTION public.admin_set_global_boss_reward(
  p_admin_id bigint,
  p_scope text,
  p_value numeric,
  p_code text DEFAULT NULL,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_scope text := lower(coalesce(p_scope,'cycle')); cyc public.global_boss_cycles;
        b public.boss_templates; v_code text; v_old numeric; v_new numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'invalid_value'; END IF;
  v_new := round(p_value);

  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;

  IF v_scope IN ('cycle','current','current_cycle') THEN
    IF cyc.id IS NULL THEN RAISE EXCEPTION 'no_active_cycle'; END IF;
    v_old := cyc.reward_pool_fc;
    -- Only the prize pool changes: HP, damage, participants, ranking and timers are preserved.
    UPDATE public.global_boss_cycles SET reward_pool_fc = v_new, updated_at = now()
      WHERE id = cyc.id RETURNING * INTO cyc;
    PERFORM public.admin_log(p_admin_id, 'global_boss_reward_change', 'global_boss_cycle', cyc.id::text,
      jsonb_build_object('reward_pool_fc', v_old),
      jsonb_build_object('reward_pool_fc', v_new),
      COALESCE(p_reason, 'current cycle reward change'),
      jsonb_build_object('scope','current_cycle','cycleNumber', cyc.cycle_number, 'bossKey', cyc.boss_key));
    RETURN jsonb_build_object('scope','current_cycle','cycleId',cyc.id,'cycleNumber',cyc.cycle_number,
      'bossName',cyc.boss_name,'oldReward',v_old,'newReward',cyc.reward_pool_fc,
      'currentHp',cyc.current_hp,'maxHp',cyc.max_hp,'participants',cyc.participants,'totalDamage',cyc.total_damage);
  ELSIF v_scope IN ('default','template','base') THEN
    v_code := COALESCE(NULLIF(trim(COALESCE(p_code,'')),''),
                       (SELECT code FROM public.boss_templates WHERE active LIMIT 1), cyc.boss_key);
    SELECT * INTO b FROM public.boss_templates WHERE code = v_code;
    IF b.code IS NULL THEN RAISE EXCEPTION 'boss_not_found'; END IF;
    v_old := b.reward_amount;
    UPDATE public.boss_templates SET reward_amount = v_new, updated_at = now()
      WHERE code = v_code RETURNING * INTO b;
    -- Default pool for the next cycles (ensure_global_boss_cycle reads this setting first).
    INSERT INTO public.game_settings(key, value) VALUES ('global_boss_reward_pool_fc', to_jsonb(v_new))
      ON CONFLICT (key) DO UPDATE SET value = to_jsonb(v_new), updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'global_boss_default_reward_change', 'boss_template', v_code,
      jsonb_build_object('reward_amount', v_old),
      jsonb_build_object('reward_amount', v_new),
      COALESCE(p_reason, 'default reward change'),
      jsonb_build_object('scope','default'));
    RETURN jsonb_build_object('scope','default','bossKey',b.code,'bossName',b.name,
      'oldReward',v_old,'newReward',b.reward_amount,
      'activeCycleReward', cyc.reward_pool_fc, 'activeCycleNumber', cyc.cycle_number);
  END IF;
  RAISE EXCEPTION 'invalid_scope';
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_global_boss_reward(bigint, text, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_global_boss_reward(bigint, text, numeric, text, text) TO service_role;