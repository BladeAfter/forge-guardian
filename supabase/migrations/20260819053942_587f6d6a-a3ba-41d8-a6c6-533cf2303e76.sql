CREATE OR REPLACE FUNCTION public.get_global_boss_ranking(p_telegram_id bigint, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE cyc public.global_boss_cycles; v_user uuid; v_limit int := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
        v_min numeric; v_top jsonb; v_you jsonb;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NULL THEN SELECT * INTO cyc FROM public.global_boss_cycles ORDER BY created_at DESC LIMIT 1; END IF;
  IF cyc.id IS NULL THEN RETURN jsonb_build_object('cycle', null, 'top', '[]'::jsonb, 'you', null); END IF;
  v_min := GREATEST(COALESCE(cyc.minimum_damage_fixed, 0), cyc.max_hp * COALESCE(cyc.minimum_damage_percent, 0) / 100.0);

  WITH ranked AS (
    SELECT p.user_id, p.damage_total, row_number() OVER (ORDER BY p.damage_total DESC, p.created_at) AS rnk
      FROM public.global_boss_participants p
     WHERE p.boss_cycle_id = cyc.id AND p.damage_total > 0
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'rank', r.rnk, 'userId', r.user_id,
           'name', COALESCE(NULLIF(g.display_name, ''), NULLIF(g.first_name, ''), NULLIF(g.username, ''), 'Player'),
           'username', g.username, 'photoUrl', g.avatar_url,
           'avatarBorder', g.avatar_border,
           'damage', r.damage_total,
           'sharePercent', CASE WHEN cyc.total_damage > 0 THEN round(100 * r.damage_total / cyc.total_damage, 4) ELSE 0 END,
           'estimatedReward', CASE WHEN cyc.total_damage > 0 AND r.damage_total >= v_min
                                   THEN round(cyc.reward_pool_fc * r.damage_total / cyc.total_damage)
                                   ELSE COALESCE(cyc.minimum_reward_fc, 0) END,
           'isYou', r.user_id = v_user) ORDER BY r.rnk), '[]'::jsonb)
    INTO v_top
    FROM (SELECT * FROM ranked ORDER BY rnk LIMIT v_limit) r
    JOIN public.game_players g ON g.id = r.user_id;

  WITH ranked AS (
    SELECT p.user_id, p.damage_total, row_number() OVER (ORDER BY p.damage_total DESC, p.created_at) AS rnk
      FROM public.global_boss_participants p
     WHERE p.boss_cycle_id = cyc.id AND p.damage_total > 0
  )
  SELECT jsonb_build_object('rank', r.rnk, 'damage', r.damage_total,
           'sharePercent', CASE WHEN cyc.total_damage > 0 THEN round(100 * r.damage_total / cyc.total_damage, 4) ELSE 0 END,
           'estimatedReward', CASE WHEN cyc.total_damage > 0 AND r.damage_total >= v_min
                                   THEN round(cyc.reward_pool_fc * r.damage_total / cyc.total_damage)
                                   ELSE COALESCE(cyc.minimum_reward_fc, 0) END)
    INTO v_you FROM ranked r WHERE r.user_id = v_user;

  RETURN jsonb_build_object(
    'cycle', jsonb_build_object('cycleId', cyc.id, 'cycleNumber', cyc.cycle_number, 'name', cyc.boss_name,
      'status', cyc.status, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp, 'rewardPoolFc', cyc.reward_pool_fc,
      'totalDamage', cyc.total_damage, 'participants', cyc.participants, 'minimumDamage', v_min),
    'top', v_top, 'you', v_you);
END;
$function$;