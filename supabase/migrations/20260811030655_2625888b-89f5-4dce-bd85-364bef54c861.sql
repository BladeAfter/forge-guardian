DROP TABLE IF EXISTS public._boss_smoke;

CREATE OR REPLACE FUNCTION public.admin_global_boss(
  p_admin_id bigint, p_action text DEFAULT 'status', p_code text DEFAULT NULL,
  p_reason text DEFAULT NULL, p_value numeric DEFAULT NULL, p_text text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_action text := lower(coalesce(p_action, 'status')); cyc public.global_boss_cycles;
        b public.boss_templates; v_code text; v_extra jsonb := '{}'::jsonb; v_pool numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;

  IF v_action IN ('activate','spawn','switch','change_boss') THEN
    v_code := COALESCE(p_code, (SELECT code FROM public.boss_templates ORDER BY active DESC, level LIMIT 1));
    SELECT * INTO b FROM public.boss_templates WHERE code = v_code;
    IF b.code IS NULL THEN RAISE EXCEPTION 'boss_not_found'; END IF;
    -- Close the running cycle (paying whatever damage was already registered).
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET status='defeated', defeated_at=now(), updated_at=now() WHERE id=cyc.id;
      v_extra := public.distribute_global_boss_rewards(cyc.id);
    END IF;
    UPDATE public.boss_templates SET active=false, updated_at=now() WHERE active AND code <> v_code;
    UPDATE public.boss_templates SET active=true, starts_at=now(),
      ends_at=now()+make_interval(secs=>GREATEST(300, COALESCE(duration_seconds,86400))), updated_at=now()
    WHERE code=v_code RETURNING * INTO b;
    cyc := public.ensure_global_boss_cycle();

  ELSIF v_action IN ('deactivate','stop') THEN
    UPDATE public.boss_templates SET active=false, ends_at=now(), updated_at=now() WHERE active;
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET status='defeated', defeated_at=now(), updated_at=now() WHERE id=cyc.id;
      v_extra := public.distribute_global_boss_rewards(cyc.id);
      cyc := NULL;
    END IF;

  ELSIF v_action IN ('end','end_boss','kill') THEN
    IF cyc.id IS NULL THEN RAISE EXCEPTION 'no_active_cycle'; END IF;
    UPDATE public.global_boss_cycles SET current_hp=0, status='defeated', defeated_at=now(), updated_at=now() WHERE id=cyc.id;
    v_extra := public.distribute_global_boss_rewards(cyc.id);
    cyc := NULL;

  ELSIF v_action = 'distribute' THEN
    SELECT * INTO cyc FROM public.global_boss_cycles WHERE status IN ('defeated','distributing')
      ORDER BY defeated_at DESC NULLS LAST LIMIT 1;
    IF cyc.id IS NULL THEN RAISE EXCEPTION 'nothing_to_distribute'; END IF;
    v_extra := public.distribute_global_boss_rewards(cyc.id);
    cyc := NULL;

  ELSIF v_action IN ('reset','reset_cycle') THEN
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET status='defeated', defeated_at=now(), updated_at=now() WHERE id=cyc.id;
      v_extra := public.distribute_global_boss_rewards(cyc.id);
    END IF;
    b := public.active_boss_template();
    IF b.code IS NOT NULL THEN
      UPDATE public.boss_templates SET starts_at=now(),
        ends_at=now()+make_interval(secs=>GREATEST(300, COALESCE(duration_seconds,86400))), updated_at=now()
      WHERE code=b.code;
    END IF;
    cyc := public.ensure_global_boss_cycle();

  ELSIF v_action IN ('set_hp','hp') THEN
    IF COALESCE(p_value,0) < 1 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    v_code := COALESCE(p_code, (SELECT code FROM public.boss_templates WHERE active LIMIT 1), cyc.boss_key);
    UPDATE public.boss_templates SET max_hp=p_value, updated_at=now() WHERE code=v_code;
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET max_hp=p_value, current_hp=LEAST(current_hp, p_value), updated_at=now()
        WHERE id=cyc.id RETURNING * INTO cyc;
    END IF;

  ELSIF v_action IN ('set_reward','set_reward_pool','reward') THEN
    IF COALESCE(p_value,0) < 0 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    v_code := COALESCE(p_code, (SELECT code FROM public.boss_templates WHERE active LIMIT 1), cyc.boss_key);
    UPDATE public.boss_templates SET reward_amount=p_value, updated_at=now() WHERE code=v_code;
    INSERT INTO public.game_settings(key, value) VALUES ('global_boss_reward_pool_fc', to_jsonb(p_value))
      ON CONFLICT (key) DO UPDATE SET value=to_jsonb(p_value), updated_at=now();
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET reward_pool_fc=p_value, updated_at=now() WHERE id=cyc.id RETURNING * INTO cyc;
    END IF;

  ELSIF v_action IN ('set_duration','duration') THEN
    IF COALESCE(p_value,0) < 300 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    v_code := COALESCE(p_code, (SELECT code FROM public.boss_templates WHERE active LIMIT 1), cyc.boss_key);
    UPDATE public.boss_templates SET duration_seconds=p_value::int,
      ends_at=CASE WHEN active THEN COALESCE(starts_at, now())+make_interval(secs=>p_value::int) ELSE ends_at END,
      updated_at=now() WHERE code=v_code;
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET ends_at=cyc.starts_at+make_interval(secs=>p_value::int), updated_at=now()
        WHERE id=cyc.id RETURNING * INTO cyc;
    END IF;

  ELSIF v_action IN ('set_name','name') THEN
    IF COALESCE(NULLIF(trim(p_text), ''), '') = '' THEN RAISE EXCEPTION 'invalid_value'; END IF;
    v_code := COALESCE(p_code, (SELECT code FROM public.boss_templates WHERE active LIMIT 1), cyc.boss_key);
    UPDATE public.boss_templates SET name=trim(p_text), updated_at=now() WHERE code=v_code;
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET boss_name=trim(p_text), updated_at=now() WHERE id=cyc.id RETURNING * INTO cyc;
      UPDATE public.boss_combats SET boss_name=trim(p_text), updated_at=now() WHERE cycle_id=cyc.id;
    END IF;

  ELSIF v_action IN ('set_image','image') THEN
    v_code := COALESCE(p_code, (SELECT code FROM public.boss_templates WHERE active LIMIT 1), cyc.boss_key);
    UPDATE public.boss_templates SET image_url=NULLIF(trim(COALESCE(p_text,'')), ''), updated_at=now() WHERE code=v_code;
    IF cyc.id IS NOT NULL THEN
      UPDATE public.global_boss_cycles SET boss_image=NULLIF(trim(COALESCE(p_text,'')), ''), updated_at=now()
        WHERE id=cyc.id RETURNING * INTO cyc;
    END IF;

  ELSIF v_action IN ('set_min_damage','min_damage') THEN
    IF COALESCE(p_value,0) < 0 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    IF cyc.id IS NULL THEN RAISE EXCEPTION 'no_active_cycle'; END IF;
    UPDATE public.global_boss_cycles SET minimum_damage_percent=p_value, updated_at=now() WHERE id=cyc.id RETURNING * INTO cyc;

  ELSIF v_action IN ('set_min_reward','min_reward') THEN
    IF COALESCE(p_value,0) < 0 THEN RAISE EXCEPTION 'invalid_value'; END IF;
    IF cyc.id IS NULL THEN RAISE EXCEPTION 'no_active_cycle'; END IF;
    UPDATE public.global_boss_cycles SET minimum_reward_fc=p_value, updated_at=now() WHERE id=cyc.id RETURNING * INTO cyc;

  ELSIF v_action IN ('toggle_rank_bonus','rank_bonus') THEN
    IF cyc.id IS NULL THEN RAISE EXCEPTION 'no_active_cycle'; END IF;
    UPDATE public.global_boss_cycles SET rank_bonus_enabled = NOT rank_bonus_enabled, updated_at=now()
      WHERE id=cyc.id RETURNING * INTO cyc;

  ELSIF v_action IN ('status','ranking','view') THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;

  IF v_action NOT IN ('status','ranking','view') THEN
    PERFORM public.admin_log(p_admin_id, 'globalboss.'||v_action, 'global_boss', COALESCE(v_code, p_code, cyc.id::text),
      null, jsonb_build_object('value', p_value, 'text', p_text, 'result', v_extra), p_reason,
      jsonb_build_object('dangerous', true));
  END IF;

  IF cyc.id IS NULL THEN SELECT * INTO cyc FROM public.global_boss_cycles ORDER BY cycle_number DESC LIMIT 1; END IF;
  b := public.active_boss_template();
  RETURN jsonb_build_object(
    'action', v_action, 'result', v_extra,
    'templateActive', b.code IS NOT NULL,
    'template', CASE WHEN b.code IS NULL THEN null ELSE jsonb_build_object('code', b.code, 'name', b.name,
      'maxHp', b.max_hp, 'reward', b.reward_amount, 'durationSeconds', b.duration_seconds, 'endsAt', b.ends_at) END,
    'templates', (SELECT COALESCE(jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name, 'level', t.level,
        'maxHp', t.max_hp, 'active', t.active) ORDER BY t.level), '[]'::jsonb) FROM public.boss_templates t),
    'cycle', CASE WHEN cyc.id IS NULL THEN null ELSE jsonb_build_object(
      'cycleId', cyc.id, 'cycleNumber', cyc.cycle_number, 'name', cyc.boss_name, 'image', cyc.boss_image,
      'status', cyc.status, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp, 'rewardPoolFc', cyc.reward_pool_fc,
      'totalDamage', cyc.total_damage, 'participants', cyc.participants, 'startsAt', cyc.starts_at,
      'endsAt', cyc.ends_at, 'defeatedAt', cyc.defeated_at, 'distributedAt', cyc.distributed_at,
      'minimumDamagePercent', cyc.minimum_damage_percent, 'minimumRewardFc', cyc.minimum_reward_fc,
      'rankBonusEnabled', cyc.rank_bonus_enabled,
      'secondsRemaining', CASE WHEN cyc.ends_at IS NULL THEN null ELSE GREATEST(0, floor(extract(epoch FROM cyc.ends_at - now())))::int END) END,
    'top', COALESCE((SELECT jsonb_agg(jsonb_build_object('rank', r.rnk, 'name',
        COALESCE(NULLIF(g.display_name,''), NULLIF(g.first_name,''), NULLIF(g.username,''), 'Player'),
        'telegramId', g.telegram_id, 'damage', r.damage_total,
        'sharePercent', CASE WHEN cyc.total_damage > 0 THEN round(100*r.damage_total/cyc.total_damage, 3) ELSE 0 END) ORDER BY r.rnk)
      FROM (SELECT p.*, row_number() OVER (ORDER BY p.damage_total DESC, p.created_at) AS rnk
              FROM public.global_boss_participants p WHERE p.boss_cycle_id = cyc.id AND p.damage_total > 0
             ORDER BY p.damage_total DESC LIMIT 15) r
      JOIN public.game_players g ON g.id = r.user_id), '[]'::jsonb));
END; $$;

-- Keep the legacy overview aligned with the global cycle.
CREATE OR REPLACE FUNCTION public.admin_boss_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN public.admin_global_boss(p_admin_id, 'status');
END; $$;