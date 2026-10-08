ALTER TABLE public.clan_boss_player_profile
  ADD COLUMN IF NOT EXISTS fixed_fc_pool_override numeric;

-- effective FC pool for a personal boss: player override wins, else admin global value
CREATE OR REPLACE FUNCTION public.clan_boss_personal_fc_pool(p_user uuid)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(
    (SELECT fixed_fc_pool_override FROM public.clan_boss_player_profile
      WHERE user_id = p_user AND fixed_fc_pool_override IS NOT NULL),
    (SELECT fixed_fc_pool FROM public.clan_boss_personal_config WHERE id = 1),
    0)
$$;
REVOKE ALL ON FUNCTION public.clan_boss_personal_fc_pool(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_boss_personal_fc_pool(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.clan_boss_personal_ensure(p_user uuid, p_clan uuid)
RETURNS public.clan_boss_instances
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE cfg public.clan_boss_config; pc public.clan_boss_personal_config;
        b public.clan_boss_instances; tpl public.clan_boss_templates; cc jsonb;
        s jsonb; dl jsonb; v_cycle integer; v_level integer; v_rewards jsonb;
        v_hp numeric; v_dur integer; v_day date; v_today integer; v_fc numeric;
BEGIN
  cfg := public.clan_boss_cfg();
  pc := public.clan_boss_personal_cfg();
  cc := public.clan_boss_clan_cfg(p_clan);
  v_day := public.clan_boss_reset_day(now());
  -- per-player override wins over the admin global value
  v_fc := public.clan_boss_personal_fc_pool(p_user);

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
    IF COALESCE(v_fc, 0) > 0
       AND COALESCE((b.rewards_snapshot->>'fcPool')::numeric, 0) <> v_fc THEN
      UPDATE public.clan_boss_instances
         SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb)
             || jsonb_build_object('fcPool', round(v_fc))
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
  IF COALESCE(v_fc, 0) > 0 THEN
    v_rewards := v_rewards || jsonb_build_object('fcPool', round(v_fc));
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

-- global admin setter must not stomp players that carry an explicit override
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
    UPDATE public.clan_boss_instances b
       SET rewards_snapshot = COALESCE(b.rewards_snapshot, '{}'::jsonb) || jsonb_build_object('fcPool', round(v))
     WHERE b.is_personal = true AND b.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM public.clan_boss_player_profile p
                        WHERE p.user_id = b.user_id AND p.fixed_fc_pool_override IS NOT NULL);
  END IF;
  PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_fixed_fc', 'clan_boss', 'fixed_fc_pool',
    NULL::jsonb, jsonb_build_object('value', v), 'painel admin', '{}'::jsonb);
  RETURN to_jsonb(public.clan_boss_personal_cfg());
END
$fn$;

-- admin setter for the per-player exception (NULL clears it)
CREATE OR REPLACE FUNCTION public.admin_clan_boss_personal_set_player_fc(
  p_admin_id bigint, p_telegram_id bigint, p_value numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid; v numeric; v_user text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT id, COALESCE(username, first_name, telegram_id::text) INTO v_uid, v_user
    FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'PLAYER_NOT_FOUND'); END IF;

  IF p_value IS NULL THEN
    UPDATE public.clan_boss_player_profile
       SET fixed_fc_pool_override = NULL, updated_at = now() WHERE user_id = v_uid;
    v := public.clan_boss_personal_fc_pool(v_uid);
  ELSE
    v := GREATEST(0, LEAST(1000000000, p_value));
    INSERT INTO public.clan_boss_player_profile(user_id, fixed_fc_pool_override)
    VALUES (v_uid, v)
    ON CONFLICT (user_id) DO UPDATE SET fixed_fc_pool_override = EXCLUDED.fixed_fc_pool_override,
                                        updated_at = now();
  END IF;

  UPDATE public.clan_boss_instances
     SET rewards_snapshot = COALESCE(rewards_snapshot, '{}'::jsonb) || jsonb_build_object('fcPool', round(v))
   WHERE user_id = v_uid AND is_personal = true AND status = 'active';

  PERFORM public.admin_log(p_admin_id, 'clan_boss_personal_player_fc', 'game_players', v_uid::text,
    NULL::jsonb, jsonb_build_object('telegramId', p_telegram_id, 'value', p_value), 'painel admin', '{}'::jsonb);
  RETURN jsonb_build_object('ok', true, 'player', v_user, 'telegramId', p_telegram_id,
    'override', p_value, 'effectiveFcPool', v);
END
$fn$;
REVOKE ALL ON FUNCTION public.admin_clan_boss_personal_set_player_fc(bigint, bigint, numeric)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_clan_boss_personal_set_player_fc(bigint, bigint, numeric) TO service_role;

-- requested exception: 700k FC for telegram 5154918326 only
INSERT INTO public.clan_boss_player_profile(user_id, fixed_fc_pool_override)
SELECT id, 700000 FROM public.game_players WHERE telegram_id = 5154918326
ON CONFLICT (user_id) DO UPDATE SET fixed_fc_pool_override = 700000, updated_at = now();

UPDATE public.clan_boss_instances b
   SET rewards_snapshot = COALESCE(b.rewards_snapshot, '{}'::jsonb) || jsonb_build_object('fcPool', 700000)
 WHERE b.is_personal = true AND b.status = 'active'
   AND b.user_id = (SELECT id FROM public.game_players WHERE telegram_id = 5154918326);