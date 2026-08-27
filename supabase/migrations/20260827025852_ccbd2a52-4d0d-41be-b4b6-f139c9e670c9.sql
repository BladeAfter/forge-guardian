CREATE OR REPLACE FUNCTION public.admin_clan_system(p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_collective_settings; v_code text; v_clan uuid;
BEGIN
  IF p_action = 'overview' THEN
    cfg := public.clan_collective_cfg();
    RETURN jsonb_build_object(
      'settings', to_jsonb(cfg),
      'upgrades', (SELECT COALESCE(jsonb_agg(to_jsonb(u) ORDER BY u.code), '[]'::jsonb) FROM public.clan_upgrade_config u),
      'buffs', (SELECT COALESCE(jsonb_agg(to_jsonb(b) ORDER BY b.code), '[]'::jsonb) FROM public.clan_buff_config b),
      'shop', (SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.sort_order), '[]'::jsonb) FROM public.clan_shop_config s),
      'stats', jsonb_build_object(
        'clansWithCycle', (SELECT count(*) FROM public.clan_weekly_cycles WHERE week_key = public.clan_week_key()),
        'weeklyContribution', (SELECT COALESCE(sum(total_contribution),0) FROM public.clan_weekly_cycles WHERE week_key = public.clan_week_key()),
        'activeRaids', (SELECT count(*) FROM public.clan_raid_cycles WHERE status = 'ACTIVE'),
        'treasuryFc', (SELECT COALESCE(sum(fc),0) FROM public.clan_treasury)));

  ELSIF p_action = 'set_setting' THEN
    v_code := p_payload->>'field';
    IF v_code = 'boss_points' THEN
      UPDATE public.clan_collective_settings
         SET boss_points = ARRAY(SELECT (jsonb_array_elements_text(p_payload->'value'))::int) WHERE id;
    ELSIF v_code = 'milestones' OR v_code = 'raid_rewards' THEN
      EXECUTE format('UPDATE public.clan_collective_settings SET %I = $1 WHERE id', v_code)
        USING (p_payload->'value');
    ELSIF v_code IN ('enabled','raid_enabled','treasury_ton_enabled','myth_milestone_rewards','raid_health_gates_enabled','raid_catchup_enabled','raid_full_kill_required') THEN
      EXECUTE format('UPDATE public.clan_collective_settings SET %I = $1 WHERE id', v_code)
        USING ((p_payload->>'value')::boolean);
    ELSIF v_code IN ('weekly_target_per_active','weekly_target_min','weekly_target_max','min_weekly_contribution',
                     'active_member_days','coins_per_contribution','clan_xp_per_contribution',
                     'raid_duration_days','raid_attacks_per_day','raid_hp_per_power','raid_hp_min','raid_hp_max',
                     'raid_target_kill_days','raid_deadline_days','raid_safety_factor',
                     'raid_dps_weight_24h','raid_dps_weight_3d','raid_dps_weight_7d',
                     'raid_max_hp_increase_pct','raid_max_hp_decrease_pct','raid_catchup_max_pct',
                     'donation_default_min_fc','donation_default_max_fc','donation_hard_max_fc',
                     'donation_default_min_myth','donation_default_max_myth','donation_hard_max_myth') THEN
      EXECUTE format('UPDATE public.clan_collective_settings SET %I = $1 WHERE id', v_code)
        USING ((p_payload->>'value')::numeric);
    ELSE RAISE EXCEPTION 'INVALID_FIELD';
    END IF;
    RETURN jsonb_build_object('status','updated','field', v_code);

  ELSIF p_action = 'set_shop_item' THEN
    UPDATE public.clan_shop_config
       SET cost_coins = COALESCE((p_payload->>'cost')::int, cost_coins),
           daily_limit = COALESCE((p_payload->>'dailyLimit')::int, daily_limit),
           weekly_limit = COALESCE((p_payload->>'weeklyLimit')::int, weekly_limit),
           enabled = COALESCE((p_payload->>'enabled')::boolean, enabled),
           updated_at = now()
     WHERE code = p_payload->>'code';
    RETURN jsonb_build_object('status','updated');

  ELSIF p_action = 'set_buff' THEN
    UPDATE public.clan_buff_config
       SET bonus_pct = COALESCE((p_payload->>'pct')::numeric, bonus_pct),
           max_pct = COALESCE((p_payload->>'maxPct')::numeric, max_pct),
           cost_fc = COALESCE((p_payload->>'costFc')::numeric, cost_fc),
           duration_hours = COALESCE((p_payload->>'hours')::int, duration_hours),
           enabled = COALESCE((p_payload->>'enabled')::boolean, enabled),
           updated_at = now()
     WHERE code = p_payload->>'code';
    RETURN jsonb_build_object('status','updated');

  ELSIF p_action = 'set_upgrade' THEN
    UPDATE public.clan_upgrade_config
       SET base_cost_fc = COALESCE((p_payload->>'baseCost')::numeric, base_cost_fc),
           max_level = COALESCE((p_payload->>'maxLevel')::int, max_level),
           bonus_per_level = COALESCE((p_payload->>'bonusPerLevel')::numeric, bonus_per_level),
           enabled = COALESCE((p_payload->>'enabled')::boolean, enabled),
           updated_at = now()
     WHERE code = p_payload->>'code';
    RETURN jsonb_build_object('status','updated');

  ELSIF p_action = 'reset_raid' THEN
    v_clan := (p_payload->>'clanId')::uuid;
    UPDATE public.clan_raid_cycles SET status = 'EXPIRED'
     WHERE status = 'ACTIVE' AND (v_clan IS NULL OR clan_id = v_clan);
    RETURN jsonb_build_object('status','raids_expired');

  ELSIF p_action = 'clan_report' THEN
    v_clan := (p_payload->>'clanId')::uuid;
    RETURN (SELECT jsonb_build_object(
        'clan', c.name, 'level', c.level,
        'weekly', (SELECT to_jsonb(w) FROM public.clan_weekly_cycles w
                    WHERE w.clan_id = c.id AND w.week_key = public.clan_week_key()),
        'treasury', (SELECT to_jsonb(t) FROM public.clan_treasury t WHERE t.clan_id = c.id),
        'raid', (SELECT to_jsonb(r) FROM public.clan_raid_cycles r
                  WHERE r.clan_id = c.id AND r.raid_key = public.clan_week_key()))
      FROM public.clans c WHERE c.id = v_clan);
  END IF;
  RAISE EXCEPTION 'INVALID_ACTION';
END $function$;

REVOKE ALL ON FUNCTION public.admin_clan_system(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_clan_system(text, jsonb) TO service_role;