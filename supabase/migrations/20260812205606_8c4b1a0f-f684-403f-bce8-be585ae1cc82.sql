CREATE OR REPLACE FUNCTION public.global_boss_overlay(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE cyc public.global_boss_cycles; v_dmg numeric := 0; v_rank int; v_share numeric := 0;
        v_min numeric; v_est numeric := 0; v_last jsonb; v_total_bosses int;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NULL THEN
    SELECT * INTO cyc FROM public.global_boss_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF cyc.id IS NULL THEN RETURN '{}'::jsonb; END IF;
  SELECT COALESCE(max(boss_number), 0) INTO v_total_bosses FROM public.global_boss_templates WHERE enabled;

  SELECT jsonb_build_object('cycleNumber', c.cycle_number, 'name', c.boss_name, 'damage', l.damage_total,
                            'rank', l.rank, 'rewardFc', l.reward_fc, 'distributedAt', l.distributed_at)
    INTO v_last
    FROM public.global_boss_reward_ledger l JOIN public.global_boss_cycles c ON c.id = l.boss_cycle_id
   WHERE l.user_id = p_user ORDER BY l.distributed_at DESC LIMIT 1;

  SELECT damage_total INTO v_dmg FROM public.global_boss_participants WHERE boss_cycle_id = cyc.id AND user_id = p_user;
  v_dmg := COALESCE(v_dmg, 0);
  IF v_dmg > 0 THEN
    SELECT count(*) + 1 INTO v_rank FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND damage_total > v_dmg;
  END IF;
  v_min := GREATEST(COALESCE(cyc.minimum_damage_fixed, 0), cyc.max_hp * COALESCE(cyc.minimum_damage_percent, 0) / 100.0);
  IF cyc.total_damage > 0 THEN
    v_share := v_dmg / cyc.total_damage;
    v_est := CASE WHEN v_dmg >= v_min THEN round(cyc.reward_pool_fc * v_share) ELSE COALESCE(cyc.minimum_reward_fc, 0) END;
  END IF;

  RETURN jsonb_build_object(
    'bossName', cyc.boss_name, 'bossLevel', cyc.boss_level,
    'bossMaxHp', cyc.max_hp, 'bossCurrentHp', cyc.current_hp,
    'rewardAmount', cyc.reward_pool_fc, 'totalDamageDealt', v_dmg,
    'bossActive', cyc.status = 'active',
    'globalBoss', jsonb_build_object(
      'cycleId', cyc.id, 'cycleNumber', cyc.cycle_number, 'name', cyc.boss_name, 'image', cyc.boss_image,
      'bossKey', cyc.boss_key, 'bossNumber', COALESCE(cyc.boss_number, 1), 'subtitle', cyc.boss_subtitle,
      'theme', cyc.boss_theme, 'background', cyc.boss_background, 'totalBosses', v_total_bosses,
      'endedReason', cyc.ended_reason, 'bossLevel', cyc.boss_level,
      'status', cyc.status, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp,
      'rewardPoolFc', cyc.reward_pool_fc, 'totalDamage', cyc.total_damage, 'participants', cyc.participants,
      'startsAt', cyc.starts_at, 'endsAt', cyc.ends_at, 'defeatedAt', cyc.defeated_at,
      'minimumDamage', v_min, 'minimumRewardFc', cyc.minimum_reward_fc,
      'rankBonusEnabled', cyc.rank_bonus_enabled,
      'yourDamage', v_dmg, 'yourRank', v_rank, 'yourSharePercent', round(v_share * 100, 4),
      'estimatedReward', v_est,
      'lastReward', v_last));
END; $function$;

REVOKE ALL ON FUNCTION public.global_boss_overlay(uuid) FROM anon, authenticated;
