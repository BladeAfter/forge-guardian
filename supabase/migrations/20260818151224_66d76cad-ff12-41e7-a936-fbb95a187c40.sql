CREATE OR REPLACE FUNCTION public.buy_pass_locked_reward(p_telegram_id bigint, p_reward_id uuid, p_wallet_address text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u game_players%rowtype; r season_pass_rewards%rowtype; p player_season_pass%rowtype;
        cfg jsonb; v_price numeric; v_ver int; o pass_locked_reward_orders%rowtype;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'INVALID_REQUEST'; end if;
  select * into u from game_players where telegram_id = p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if coalesce(u.banned,false) then raise exception 'PLAYER_BANNED'; end if;

  cfg := pass_locked_reward_config();
  if not coalesce((cfg->>'enabled')::boolean, true) then raise exception 'LOCKED_REWARD_PURCHASE_DISABLED'; end if;
  v_price := coalesce((cfg->>'price_ton')::numeric, 10);
  if v_price <= 0 then raise exception 'INVALID_PRICE'; end if;

  select * into r from season_pass_rewards where id = p_reward_id and enabled;
  if r.id is null then raise exception 'REWARD_NOT_FOUND'; end if;
  select * into p from player_season_pass where user_id = u.id and season_id = r.season_id;
  v_ver := case when coalesce(p.tier,'none') = 'none' then 2 else coalesce(p.pass_version, 1) end;
  if coalesce(r.min_pass_version,1) <= v_ver then raise exception 'REWARD_NOT_LOCKED'; end if;

  -- One paid unlock per locked reward per user: each chest has its own single-purchase limit.
  if exists (select 1 from pass_locked_reward_orders
              where user_id = u.id and reward_id = r.id and status in ('paid','delivered','completed')) then
    raise exception 'LOCKED_REWARD_ALREADY_OWNED';
  end if;

  select * into o from pass_locked_reward_orders where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into o from pass_locked_reward_orders
      where user_id = u.id and reward_id = r.id and status = 'pending' and expires_at > now()
      order by created_at desc limit 1;
  end if;
  if o.id is not null and o.status = 'pending' then
    return jsonb_build_object('status','payment_required','method','ton_connect','orderId', o.id,
      'paymentAddress', o.payment_address, 'amountNano', o.amount_nano, 'amountTon', o.price_ton,
      'paymentComment', o.payment_comment, 'expiresAt', o.expires_at, 'priceTon', o.price_ton);
  end if;

  if round(coalesce(u.ton_balance,0), 9) >= round(v_price, 9) then
    update game_players set ton_balance = round(coalesce(ton_balance,0) - v_price, 9), updated_at = now() where id = u.id;
    insert into pass_locked_reward_orders(user_id, telegram_id, reward_id, season_id, price_ton, amount_nano,
      status, method, idempotency_key)
    values (u.id, p_telegram_id, r.id, r.season_id, v_price, round(v_price*1000000000)::text,
      'paid', 'internal_ton', p_idempotency_key)
    returning * into o;
    perform pass_locked_reward_deliver(o.id);
    return jsonb_build_object('status','completed','method','internal_ton','orderId', o.id,
      'priceTon', v_price, 'itemCode', r.reward_code,
      'dashboard', get_season_pass_dashboard(p_telegram_id),
      'inventory', get_player_inventory(p_telegram_id));
  end if;

  insert into pass_locked_reward_orders(user_id, telegram_id, reward_id, season_id, price_ton, amount_nano,
    payment_address, payment_comment, status, method, idempotency_key)
  values (u.id, p_telegram_id, r.id, r.season_id, v_price, round(v_price*1000000000)::text,
    wallet_hot_address(), 'forge_passchest:' || gen_random_uuid(), 'pending', 'ton_connect', p_idempotency_key)
  returning * into o;

  return jsonb_build_object('status','payment_required','method','ton_connect','orderId', o.id,
    'paymentAddress', o.payment_address, 'amountNano', o.amount_nano, 'amountTon', o.price_ton,
    'paymentComment', o.payment_comment, 'expiresAt', o.expires_at, 'priceTon', v_price,
    'availableTon', round(coalesce(u.ton_balance,0), 9));
end $function$;

CREATE OR REPLACE FUNCTION public.get_season_pass_dashboard(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_level int; v_xpl int; v_max int; v_mult numeric; v_levels int; v_ver int; v_ends timestamptz;
        v_cfg jsonb; v_limit int; v_bought int; v_locked jsonb;
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
  v_locked := public.pass_locked_reward_config();
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
        'type', r.reward_type, 'code', r.reward_code, 'amount', r.amount, 'title', r.title,
        'exclusive', r.reward_type = 'exclusive_chest',
        'requiresPassVersion', COALESCE(r.min_pass_version, 1),
        'versionLocked', COALESCE(r.min_pass_version, 1) > v_ver,
        -- A locked reward already paid for is delivered: it shows the claimed check, never the buy button.
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
        ORDER BY r.level, CASE r.tier WHEN 'adventurer' THEN 1 ELSE 2 END), '[]')
      FROM public.season_pass_rewards r
      LEFT JOIN public.season_pass_claims c ON c.reward_id = r.id AND c.user_id = u
      LEFT JOIN LATERAL (
        SELECT plo.id FROM public.pass_locked_reward_orders plo
        WHERE plo.user_id = u AND plo.reward_id = r.id
          AND plo.status IN ('paid','delivered','completed') LIMIT 1) o ON true
      WHERE r.season_id = s.id AND r.enabled AND r.tier IN ('adventurer','legendary')));
END; $function$;