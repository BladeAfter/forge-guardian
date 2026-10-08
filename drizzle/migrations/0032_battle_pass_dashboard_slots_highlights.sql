CREATE OR REPLACE FUNCTION public.get_season_pass_dashboard(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_level int; v_xpl int; v_max int; v_mult numeric; v_levels int; v_ver int; v_ends timestamptz;
        v_cfg jsonb; v_limit int; v_bought int; v_locked jsonb; v_info jsonb;
BEGIN
  PERFORM public.pass_versions_apply_due();
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT * INTO s FROM public.season_pass_seasons WHERE id = public.pass_user_season_id(u);
  IF u IS NULL OR s.id IS NULL THEN RAISE EXCEPTION 'SEASON_NOT_AVAILABLE'; END IF;
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (u, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = u AND season_id = s.id;
  v_ver := CASE WHEN p.tier = 'none' THEN 2 ELSE COALESCE(p.pass_version, 1) END;
  v_levels := public.season_pass_levels_for(v_ver, s.levels);
  v_ends := COALESCE(p.expires_at, s.end_at);
  v_xpl := GREATEST(1, s.xp_per_level);
  v_max := v_levels * v_xpl;
  v_level := LEAST(v_levels, p.xp / v_xpl + 1);
  v_mult := public.season_pass_tier_multiplier(p.tier);
  v_cfg := public.season_pass_level_purchase_config();
  v_limit := GREATEST(0, COALESCE((v_cfg->>'daily_limit')::int, 5));
  v_locked := public.pass_locked_reward_config();
  v_info := public.pass_version_info(u, s.id);
  SELECT COALESCE(sum(levels_bought),0) INTO v_bought FROM public.season_pass_level_purchases
    WHERE user_id = u AND purchase_date = public.quest_today();
  RETURN jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'endsAt', v_ends, 'levels', v_levels,
      'passVersion', v_ver, 'currentPassVersion', 2,
      'seasonVersionNumber', COALESCE((SELECT max(v.version_number) FROM public.pass_versions v WHERE v.season_id = s.id), 1),
      'xpPerLevel', v_xpl, 'adventurerPriceTon', s.adventurer_price_ton,
      'legendaryPriceTon', s.legendary_price_ton,
      'upgradePriceTon', GREATEST(0, s.legendary_price_ton - s.adventurer_price_ton)),
    'versionInfo', v_info,
    'passHistory', COALESCE(v_info->'history', '[]'::jsonb),
    'player', jsonb_build_object('xp', p.xp, 'level', v_level, 'tier', p.tier,
      'passVersion', v_ver, 'legacyPass', p.tier <> 'none' AND COALESCE(p.pass_version,1) < 2,
      'expiresAt', p.expires_at,
      'totalXp', p.xp, 'maxXp', v_max, 'maxed', p.xp >= v_max,
      'xpIntoLevel', CASE WHEN p.xp >= v_max THEN v_xpl ELSE p.xp % v_xpl END,
      'xpForNextLevel', v_xpl,
      'xpMultiplier', v_mult, 'xpBonusPercent', round((v_mult - 1) * 100),
      'adventurerOwned', p.tier IN ('adventurer','legendary'), 'legendaryOwned', p.tier = 'legendary'),
    'lockedPurchase', jsonb_build_object(
      'enabled', COALESCE((v_locked->>'enabled')::boolean, true),
      'priceTon', COALESCE((v_locked->>'price_ton')::numeric, 10),
      'availableTon', round(COALESCE((SELECT ton_balance FROM public.game_players WHERE id = u), 0), 9)),
    'levelPurchase', jsonb_build_object(
      'enabled', COALESCE((v_cfg->>'enabled')::boolean, true),
      'prices', COALESCE(v_cfg->'prices', '{}'::jsonb),
      'dailyLimit', v_limit,
      'boughtToday', v_bought,
      'remainingToday', GREATEST(0, v_limit - v_bought),
      'maxAvailable', LEAST(GREATEST(0, v_limit - v_bought), GREATEST(0, v_levels - v_level)),
      'balanceFc', COALESCE((SELECT forge_coins FROM public.game_players WHERE id = u), 0)),
    'xpRates', public.season_pass_xp_config(),
    'xpMultipliers', public.season_pass_xp_multipliers(),
    'xpCaps', public.season_pass_xp_caps(),
    'xpToday', COALESCE((SELECT SUM(xp_amount) FROM public.season_pass_xp_ledger
      WHERE user_id = u AND game_day = public.game_day_key()), 0),
    'rewards', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('id', r.id, 'level', r.level, 'tier', r.tier,
        'slot', r.reward_slot, 'highlight', r.is_highlight, 'asset', r.reward_asset,
        'type', r.reward_type, 'code', r.reward_code, 'amount', r.amount, 'title', r.title,
        'exclusive', r.reward_type IN ('exclusive_chest','nft_equipment','nft_pet'),
        'requiresPassVersion', COALESCE(r.min_pass_version, 1),
        'versionLocked', COALESCE(r.min_pass_version, 1) > v_ver,
        'purchasable', COALESCE(r.min_pass_version, 1) > v_ver
          AND COALESCE((v_locked->>'enabled')::boolean, true)
          AND o.id IS NULL,
        'priceTon', CASE WHEN COALESCE(r.min_pass_version, 1) > v_ver
          THEN COALESCE((v_locked->>'price_ton')::numeric, 10) ELSE NULL END,
        'claimed', c.id IS NOT NULL OR o.id IS NOT NULL,
        'unlocked', (r.level <= v_level
          AND COALESCE(r.min_pass_version, 1) <= v_ver
          AND (
          (r.tier = 'adventurer' AND p.tier IN ('adventurer','legendary'))
          OR (r.tier = 'legendary' AND p.tier = 'legendary'))) OR o.id IS NOT NULL)
        ORDER BY r.level, CASE r.tier WHEN 'adventurer' THEN 1 ELSE 2 END, r.reward_slot), '[]')
      FROM public.season_pass_rewards r
      LEFT JOIN public.season_pass_claims c ON c.reward_id = r.id AND c.user_id = u
      LEFT JOIN LATERAL (
        SELECT plo.id FROM public.pass_locked_reward_orders plo
        WHERE plo.user_id = u AND plo.reward_id = r.id
          AND plo.status IN ('paid','delivered','completed') LIMIT 1) o ON true
      WHERE r.season_id = s.id AND r.enabled AND r.tier IN ('adventurer','legendary')));
END; $function$;