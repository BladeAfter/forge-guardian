CREATE OR REPLACE FUNCTION public.get_rarity_fusion_dashboard(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; v_bal numeric := 0; cfg jsonb := public.hero_rarity_fusion_config(); v_heroes jsonb; v_counts jsonb;
        v_myth numeric := 0; v_staked numeric := 0;
BEGIN
  SELECT id, forge_coins INTO v_user, v_bal FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('config', cfg, 'balance', 0, 'heroes', '[]'::jsonb, 'counts', '{}'::jsonb,
      'mythBalance', 0, 'mythAvailable', 0);
  END IF;
  SELECT coalesce(amount, 0) INTO v_myth FROM public.myth_balances WHERE user_id = v_user;
  -- myth_balances.amount ja e o saldo liquido: o staking e debitado no momento do stake.
  -- Nao subtrair novamente, senao o disponivel vira 0 para quem tem staking ativo.
  v_staked := 0;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'heroId', ph.id, 'heroKey', ph.hero_key, 'name', ph.name, 'rarity', ph.rarity,
      'level', ph.level, 'imageUrl', ph.image, 'stars', ph.fusion_level,
      'finalAtk', round(ph.final_atk), 'finalHp', round(ph.final_hp),
      'power', round(ph.final_atk * 2 + ph.final_hp),
      'locked', ph.locked,
      'equipped', NOT coalesce((us.usage->>'canFuse')::boolean, false) AND NOT coalesce(ph.locked,false),
      'usage', us.usage,
      'lockReason', us.usage->>'reason',
      'exclusive', ph.is_season_exclusive
    ) ORDER BY ph.created_at DESC), '[]'::jsonb) INTO v_heroes
  FROM public.player_heroes ph
  CROSS JOIN LATERAL (SELECT public.hero_usage_status(ph.id) AS usage) us
  WHERE ph.user_id = v_user AND NOT ph.is_nft_exclusive;
  SELECT coalesce(jsonb_object_agg(rarity, n), '{}'::jsonb) INTO v_counts FROM (
    SELECT rarity, count(*) AS n FROM public.player_heroes WHERE user_id = v_user AND NOT is_nft_exclusive GROUP BY rarity
  ) s;
  RETURN jsonb_build_object(
    'config', cfg, 'balance', v_bal, 'heroes', v_heroes, 'counts', v_counts,
    'mythBalance', coalesce(v_myth, 0),
    'mythAvailable', greatest(0, coalesce(v_myth, 0)),
    'fragments', coalesce((SELECT quantity FROM public.player_inventory WHERE user_id = v_user AND item_type='fragments' AND item_code='fragments'), 0),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', h.id, 'sourceRarity', h.source_rarity, 'targetRarity', h.target_rarity,
        'success', h.success, 'costFc', h.fusion_cost_fc, 'chance', h.success_chance,
        'rewardHero', h.reward_hero_name, 'fragments', h.fragment_reward, 'createdAt', h.created_at
      ) ORDER BY h.created_at DESC) FROM (
        SELECT * FROM public.hero_rarity_fusion_history WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10
      ) h), '[]'::jsonb)
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.get_rarity_fusion_dashboard(bigint) TO service_role;