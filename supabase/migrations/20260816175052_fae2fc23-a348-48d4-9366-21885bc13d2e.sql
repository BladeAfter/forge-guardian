-- 1) Every player sees the full track (1..season levels = 50)
CREATE OR REPLACE FUNCTION public.season_pass_levels_for(p_pass_version integer, p_season_levels integer)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$ SELECT GREATEST(COALESCE(p_season_levels, 50), 50) $function$;

-- 2) Levels 31-50: normal rewards open to everyone; only the new exclusives need PASS V2
UPDATE public.season_pass_rewards
   SET min_pass_version = 1, updated_at = now()
 WHERE level BETWEEN 31 AND 50 AND reward_type <> 'exclusive_chest' AND min_pass_version > 1;

UPDATE public.season_pass_rewards
   SET min_pass_version = 2, updated_at = now()
 WHERE level BETWEEN 31 AND 50 AND reward_type = 'exclusive_chest' AND min_pass_version < 2;

-- 3) Legacy entitlement is explicit (never NULL)
UPDATE public.player_season_pass SET pass_version = 1 WHERE pass_version IS NULL;

-- 4) Dashboard: show all levels/rewards, flag the V2-only ones instead of hiding them
CREATE OR REPLACE FUNCTION public.get_season_pass_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_level int; v_xpl int; v_max int; v_mult numeric; v_levels int; v_ver int; v_ends timestamptz;
        v_cfg jsonb; v_limit int; v_bought int;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT * INTO s FROM public.season_pass_seasons WHERE active AND now() BETWEEN start_at AND end_at;
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
  SELECT COALESCE(sum(levels_bought),0) INTO v_bought FROM public.season_pass_level_purchases
    WHERE user_id = u AND purchase_date = public.quest_today();
  RETURN jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'endsAt', v_ends, 'levels', v_levels,
      'passVersion', v_ver, 'currentPassVersion', 2,
      'xpPerLevel', v_xpl, 'adventurerPriceTon', s.adventurer_price_ton,
      'legendaryPriceTon', s.legendary_price_ton,
      'upgradePriceTon', GREATEST(0, s.legendary_price_ton - s.adventurer_price_ton)),
    'player', jsonb_build_object('xp', p.xp, 'level', v_level, 'tier', p.tier,
      'passVersion', v_ver, 'legacyPass', p.tier <> 'none' AND COALESCE(p.pass_version,1) < 2,
      'expiresAt', p.expires_at,
      'totalXp', p.xp, 'maxXp', v_max, 'maxed', p.xp >= v_max,
      'xpIntoLevel', CASE WHEN p.xp >= v_max THEN v_xpl ELSE p.xp % v_xpl END,
      'xpForNextLevel', v_xpl,
      'xpMultiplier', v_mult, 'xpBonusPercent', round((v_mult - 1) * 100),
      'adventurerOwned', p.tier IN ('adventurer','legendary'), 'legendaryOwned', p.tier = 'legendary'),
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
        'type', r.reward_type, 'code', r.reward_code, 'amount', r.amount, 'title', r.title,
        'exclusive', r.reward_type = 'exclusive_chest',
        'requiresPassVersion', COALESCE(r.min_pass_version, 1),
        'versionLocked', COALESCE(r.min_pass_version, 1) > v_ver,
        'claimed', c.id IS NOT NULL,
        'unlocked', r.level <= v_level
          AND COALESCE(r.min_pass_version, 1) <= v_ver
          AND (
          (r.tier = 'adventurer' AND p.tier IN ('adventurer','legendary'))
          OR (r.tier = 'legendary' AND p.tier = 'legendary')))
        ORDER BY r.level, CASE r.tier WHEN 'adventurer' THEN 1 ELSE 2 END), '[]')
      FROM public.season_pass_rewards r
      LEFT JOIN public.season_pass_claims c ON c.reward_id = r.id AND c.user_id = u
      WHERE r.season_id = s.id AND r.enabled AND r.tier IN ('adventurer','legendary')));
END; $function$;

-- 5) Claim: explicit rejection for V2-only rewards
CREATE OR REPLACE FUNCTION public.season_pass_claim_version_guard() RETURNS void LANGUAGE sql IMMUTABLE AS $$ SELECT NULL::void $$;

-- 6) Any paid pass order (purchase OR upgrade) grants the current entitlement (V2)
CREATE OR REPLACE FUNCTION public.season_pass_apply_entitlement(p_user_id uuid, p_season_id uuid, p_tier text)
RETURNS public.player_season_pass LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE p public.player_season_pass%rowtype; v_ver int; v_expires timestamptz; v_prev int;
BEGIN
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (p_user_id, p_season_id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = p_user_id AND season_id = p_season_id FOR UPDATE;
  v_prev := COALESCE(p.pass_version, 1);
  v_ver := GREATEST(v_prev, 2);
  IF p.tier = 'none' OR v_ver > v_prev THEN
    v_expires := GREATEST(COALESCE(p.expires_at, now()), now()) + interval '30 days';
  ELSE
    v_expires := p.expires_at;
  END IF;
  UPDATE public.player_season_pass
     SET tier = p_tier,
         adventurer_owned = true,
         legendary_owned = (p_tier = 'legendary'),
         pass_version = v_ver,
         purchased_at = COALESCE(purchased_at, now()),
         upgraded_at = CASE WHEN p_tier = 'legendary' AND p.tier = 'adventurer' THEN now() ELSE upgraded_at END,
         expires_at = v_expires,
         updated_at = now()
   WHERE user_id = p_user_id AND season_id = p_season_id
  RETURNING * INTO p;
  RETURN p;
END; $function$;

REVOKE ALL ON FUNCTION public.season_pass_apply_entitlement(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.season_pass_apply_entitlement(uuid, uuid, text) TO service_role;