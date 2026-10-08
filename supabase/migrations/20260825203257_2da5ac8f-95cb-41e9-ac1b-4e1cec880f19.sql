ALTER TABLE public.clan_boss_personal_config
  ADD COLUMN IF NOT EXISTS fixed_fc_pool numeric NOT NULL DEFAULT 400000;

UPDATE public.clan_boss_personal_config SET fixed_fc_pool = 400000, updated_at = now() WHERE id = 1;

-- personal boss ensure: force the fixed FC pool when configured
CREATE OR REPLACE FUNCTION public.clan_boss_personal_ensure(p_user uuid, p_clan uuid)
RETURNS public.clan_boss_instances
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
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
    IF COALESCE(pc.fixed_fc_pool, 0) > 0
       AND COALESCE((b.rewards_snapshot->>'fcPool')::numeric, 0) <> pc.fixed_fc_pool THEN
      UPDATE public.clan_boss_instances
         SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb)
             || jsonb_build_object('fcPool', pc.fixed_fc_pool)
       WHERE id = b.id RETURNING * INTO b;
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
  -- fixed personal FC pool wins over clan/template values (admin adjustable, no deploy)
  IF COALESCE(pc.fixed_fc_pool, 0) > 0 THEN
    v_rewards := v_rewards || jsonb_build_object('fcPool', round(pc.fixed_fc_pool));
  END IF;

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
END
$fn$;

-- admin setter: accept fixed_fc_pool
CREATE OR REPLACE FUNCTION public.admin_clan_boss_personal_set_fc(p_admin_id bigint, p_value numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v := GREATEST(0, LEAST(1000000000, COALESCE(p_value, 0)));
  UPDATE public.clan_boss_personal_config SET fixed_fc_pool = v, updated_at = now() WHERE id = 1;
  IF v > 0 THEN
    UPDATE public.clan_boss_instances
       SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb) || jsonb_build_object('fcPool', round(v))
     WHERE is_personal = true AND status = 'active';
  END IF;
  PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_fixed_fc', 'clan_boss', 'fixed_fc_pool',
    NULL::jsonb, jsonb_build_object('value', v), 'painel admin', '{}'::jsonb);
  RETURN to_jsonb(public.clan_boss_personal_cfg());
END
$fn$;

REVOKE ALL ON FUNCTION public.admin_clan_boss_personal_set_fc(bigint, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_clan_boss_personal_set_fc(bigint, numeric) TO service_role;

-- apply 400k to all currently active personal bosses
UPDATE public.clan_boss_instances
   SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb) || jsonb_build_object('fcPool', 400000)
 WHERE is_personal = true AND status = 'active';