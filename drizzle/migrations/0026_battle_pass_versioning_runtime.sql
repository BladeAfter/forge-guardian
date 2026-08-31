-- Route every pass runtime function through the per-player resolved season,
-- so an upcoming version is visible only to its audience while everyone else
-- keeps using the current ACTIVE version.

-- Lazy scheduled activation: the first pass interaction at/after the scheduled
-- time flips the version, so no polling job is needed.
CREATE OR REPLACE FUNCTION public.pass_versions_apply_due()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.pass_versions
              WHERE status = 'SCHEDULED' AND activate_at IS NOT NULL AND activate_at <= now()) THEN
    PERFORM public.pass_versions_run_scheduled();
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_season_pass_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
        'type', r.reward_type, 'code', r.reward_code, 'amount', r.amount, 'title', r.title,
        'exclusive', r.reward_type = 'exclusive_chest',
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
        ORDER BY r.level, CASE r.tier WHEN 'adventurer' THEN 1 ELSE 2 END), '[]')
      FROM public.season_pass_rewards r
      LEFT JOIN public.season_pass_claims c ON c.reward_id = r.id AND c.user_id = u
      LEFT JOIN LATERAL (
        SELECT plo.id FROM public.pass_locked_reward_orders plo
        WHERE plo.user_id = u AND plo.reward_id = r.id
          AND plo.status IN ('paid','delivered','completed') LIMIT 1) o ON true
      WHERE r.season_id = s.id AND r.enabled AND r.tier IN ('adventurer','legendary')));
END; $function$;

CREATE OR REPLACE FUNCTION public.grant_season_pass_xp(p_user_id uuid, p_source text, p_reference_id text DEFAULT NULL::text, p_amount integer DEFAULT NULL::integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  s public.season_pass_seasons%rowtype; sp public.player_season_pass%rowtype;
  v_base integer; v_cap integer; v_used integer; v_final integer;
  v_mult numeric; v_day date;
  v_before integer; v_after integer; v_max integer;
  v_lvl_before integer; v_lvl_after integer; v_ins uuid;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_source,'') = '' THEN RETURN NULL; END IF;

  -- XP always goes to the season the player is currently on (never to an archived version).
  SELECT * INTO s FROM public.season_pass_seasons WHERE id = public.pass_user_season_id(p_user_id);
  IF s.id IS NULL THEN RETURN NULL; END IF;

  v_base := COALESCE(p_amount, (public.season_pass_xp_config()->>p_source)::int, 0);
  IF v_base <= 0 THEN RETURN NULL; END IF;

  v_day := public.game_day_key();

  v_cap := NULLIF(public.season_pass_xp_caps()->>p_source, '')::int;
  IF v_cap IS NOT NULL THEN
    SELECT COALESCE(SUM(COALESCE(base_xp, xp_amount)), 0) INTO v_used
      FROM public.season_pass_xp_ledger
     WHERE user_id = p_user_id AND source = p_source AND game_day = v_day;
    v_base := LEAST(v_base, GREATEST(0, v_cap - v_used));
    IF v_base <= 0 THEN
      RETURN jsonb_build_object('granted', false, 'capped', true, 'source', p_source);
    END IF;
  END IF;

  INSERT INTO public.player_season_pass(user_id, season_id, tier)
  VALUES (p_user_id, s.id, 'none') ON CONFLICT (user_id, season_id) DO NOTHING;

  SELECT * INTO sp FROM public.player_season_pass
   WHERE user_id = p_user_id AND season_id = s.id FOR UPDATE;

  v_mult := public.season_pass_tier_multiplier(sp.tier);
  v_final := GREATEST(1, floor(v_base * v_mult)::int);

  v_max := s.levels * s.xp_per_level;
  v_before := COALESCE(sp.xp, 0);
  v_after := GREATEST(0, LEAST(v_max, v_before + v_final));
  v_lvl_before := LEAST(s.levels, v_before / GREATEST(1, s.xp_per_level) + 1);
  v_lvl_after := LEAST(s.levels, v_after / GREATEST(1, s.xp_per_level) + 1);

  IF p_reference_id IS NULL THEN
    INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
        base_xp, multiplier, game_day, xp_before, xp_after, level_before, level_after)
    VALUES (p_user_id, s.id, p_source, NULL, v_after - v_before,
        v_base, v_mult, v_day, v_before, v_after, v_lvl_before, v_lvl_after)
    RETURNING id INTO v_ins;
  ELSE
    INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
        base_xp, multiplier, game_day, xp_before, xp_after, level_before, level_after)
    VALUES (p_user_id, s.id, p_source, p_reference_id, v_after - v_before,
        v_base, v_mult, v_day, v_before, v_after, v_lvl_before, v_lvl_after)
    ON CONFLICT (user_id, season_id, source, reference_id) WHERE reference_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_ins;
  END IF;

  IF v_ins IS NULL THEN
    RETURN jsonb_build_object('granted', false, 'duplicate', true,
      'xp', v_before, 'level', v_lvl_before, 'xpPerLevel', s.xp_per_level, 'levels', s.levels);
  END IF;

  UPDATE public.player_season_pass SET xp = v_after, updated_at = now()
   WHERE user_id = p_user_id AND season_id = s.id;

  RETURN jsonb_build_object('granted', true, 'amount', v_after - v_before,
    'source', p_source, 'baseXp', v_base, 'multiplier', v_mult, 'tier', COALESCE(sp.tier,'none'),
    'bonusPercent', round((v_mult - 1) * 100),
    'xp', v_after, 'level', v_lvl_after, 'levelUp', v_lvl_after > v_lvl_before,
    'xpPerLevel', s.xp_per_level, 'levels', s.levels, 'maxed', v_after >= v_max);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_season_pass_order(p_telegram_id bigint, p_tier text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u uuid; s season_pass_seasons%rowtype; p player_season_pass%rowtype; o season_pass_orders%rowtype;
        price numeric; address text; upgrade boolean := false;
begin
  if p_tier not in ('adventurer','legendary') then raise exception 'INVALID_PASS_TIER'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  select * into s from season_pass_seasons where id = public.pass_user_season_id(u);
  if u is null or s.id is null then raise exception 'SEASON_NOT_AVAILABLE'; end if;

  insert into player_season_pass(user_id, season_id, tier) values (u, s.id, 'none')
    on conflict (user_id, season_id) do nothing;
  select * into p from player_season_pass where user_id = u and season_id = s.id for update;

  if p.tier = 'legendary' then raise exception 'PASS_ALREADY_OWNED'; end if;
  if p_tier = 'adventurer' and p.tier = 'adventurer' then raise exception 'PASS_ALREADY_OWNED'; end if;

  select * into o from season_pass_orders where idempotency_key = p_idempotency_key;

  if o.id is null then
    select * into o from season_pass_orders
     where user_id = u and season_id = s.id and tier = p_tier
       and status = 'pending' and tx_hash is null and expires_at > now()
     order by created_at desc limit 1;
  end if;

  if o.id is not null then
    return jsonb_build_object('id', o.id, 'tier', o.tier, 'paymentAddress', o.payment_address,
      'amountNano', o.amount_nano, 'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
  end if;

  upgrade := (p_tier = 'legendary' and p.tier = 'adventurer');
  price := case
    when p_tier = 'adventurer' then s.adventurer_price_ton
    when upgrade then greatest(s.legendary_price_ton - s.adventurer_price_ton, 0)
    else s.legendary_price_ton end;
  if price <= 0 then raise exception 'INVALID_PASS_PRICE'; end if;
  address := wallet_hot_address();

  insert into season_pass_orders(user_id, season_id, tier, price_ton, amount_nano, payment_address, payment_comment, idempotency_key)
  values (u, s.id, p_tier, price, round(price * 1000000000)::text, address, 'forge_pass:' || gen_random_uuid(), p_idempotency_key)
  returning * into o;

  return jsonb_build_object('id', o.id, 'tier', o.tier, 'upgrade', upgrade, 'paymentAddress', o.payment_address,
    'amountNano', o.amount_nano, 'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
end $function$;

CREATE OR REPLACE FUNCTION public.season_pass_buy_with_myth(p_telegram_id bigint, p_tier text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_price_ton numeric; v_myth numeric; v_burn jsonb; v_upgrade boolean := false; v_row public.player_season_pass;
begin
  if p_tier not in ('adventurer','legendary') then raise exception 'INVALID_PASS_TIER'; end if;
  if length(coalesce(p_idempotency_key,'')) < 8 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  select * into s from public.season_pass_seasons where id = public.pass_user_season_id(u);
  if u is null or s.id is null then raise exception 'SEASON_NOT_AVAILABLE'; end if;
  perform pg_advisory_xact_lock(hashtextextended('pass_myth:'||u::text, 0));

  insert into public.player_season_pass(user_id, season_id, tier) values (u, s.id, 'none')
    on conflict (user_id, season_id) do nothing;
  select * into p from public.player_season_pass where user_id = u and season_id = s.id for update;
  if p.tier = 'legendary' then raise exception 'PASS_ALREADY_OWNED'; end if;
  if p_tier = 'adventurer' and p.tier = 'adventurer' then raise exception 'PASS_ALREADY_OWNED'; end if;

  v_upgrade := (p_tier = 'legendary' and p.tier = 'adventurer');
  v_price_ton := case
    when p_tier = 'adventurer' then s.adventurer_price_ton
    when v_upgrade then greatest(s.legendary_price_ton - s.adventurer_price_ton, 0)
    else s.legendary_price_ton end;
  if coalesce(v_price_ton,0) <= 0 then raise exception 'INVALID_PASS_PRICE'; end if;

  v_myth := public.myth_utility_price('PASS_PURCHASE', 0, v_price_ton);
  if v_myth is null then raise exception 'MYTH_PAYMENT_NOT_ENABLED'; end if;

  v_burn := public.myth_utility_charge(u, 'PASS_PURCHASE', v_myth, s.id::text || ':' || p_tier, p_idempotency_key,
    jsonb_build_object('seasonId', s.id, 'tier', p_tier, 'tonReference', v_price_ton, 'upgrade', v_upgrade));

  v_row := public.season_pass_apply_entitlement(u, s.id, p_tier);

  return public.get_season_pass_dashboard(p_telegram_id) || jsonb_build_object(
    'purchase', jsonb_build_object('tier', v_row.tier, 'paidWith', 'MYTH', 'mythSpent', v_myth,
      'tonReference', v_price_ton, 'upgrade', v_upgrade, 'mythBurn', v_burn));
end $function$;

CREATE OR REPLACE FUNCTION public.buy_season_pass_levels(p_telegram_id bigint, p_levels integer, p_idempotency_key text, p_currency text DEFAULT 'FC'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u public.game_players; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        cfg jsonb; v_price numeric; v_limit int; v_bought int; v_xpl int; v_level int;
        v_new_level int; v_xp_into int; v_new_xp numeric; v_before numeric; v_day date;
        v_cur text; v_myth numeric; v_burn jsonb;
BEGIN
  v_cur := case when upper(coalesce(p_currency,'FC')) = 'MYTH' then 'MYTH' else 'FC' end;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pass_level_buy'||u.id::text, 0));
  IF EXISTS (SELECT 1 FROM public.season_pass_level_purchases WHERE idempotency_key = p_idempotency_key) THEN
    RETURN public.get_season_pass_dashboard(p_telegram_id);
  END IF;

  cfg := public.season_pass_level_purchase_config();
  IF NOT COALESCE((cfg->>'enabled')::boolean, true) THEN RAISE EXCEPTION 'LEVEL_PURCHASE_DISABLED'; END IF;
  v_price := (cfg->'prices'->>p_levels::text)::numeric;
  IF v_price IS NULL OR p_levels <= 0 THEN RAISE EXCEPTION 'INVALID_PACK'; END IF;

  SELECT * INTO s FROM public.season_pass_seasons WHERE id = public.pass_user_season_id(u.id);
  IF s.id IS NULL THEN RAISE EXCEPTION 'SEASON_NOT_AVAILABLE'; END IF;
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (u.id, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = u.id AND season_id = s.id FOR UPDATE;

  v_xpl := GREATEST(1, s.xp_per_level);
  v_level := LEAST(s.levels, (p.xp / v_xpl)::int + 1);
  IF v_level >= s.levels THEN RAISE EXCEPTION 'MAX_LEVEL_REACHED'; END IF;
  IF v_level + p_levels > s.levels THEN RAISE EXCEPTION 'LEVELS_AVAILABLE_%', s.levels - v_level; END IF;

  v_day := public.quest_today();
  v_limit := GREATEST(0, COALESCE((cfg->>'daily_limit')::int, 5));
  SELECT COALESCE(sum(levels_bought),0) INTO v_bought FROM public.season_pass_level_purchases
    WHERE user_id = u.id AND purchase_date = v_day;
  IF v_bought + p_levels > v_limit THEN RAISE EXCEPTION 'DAILY_LIMIT_%', GREATEST(0, v_limit - v_bought); END IF;

  v_xp_into := (p.xp % v_xpl)::int;
  v_new_level := v_level + p_levels;
  v_new_xp := (v_new_level - 1)::numeric * v_xpl + v_xp_into;
  v_before := COALESCE(u.forge_coins,0);

  IF v_cur = 'MYTH' THEN
    v_myth := public.myth_utility_price('PASS_LEVELS', v_price, 0);
    IF v_myth IS NULL THEN RAISE EXCEPTION 'MYTH_PAYMENT_NOT_ENABLED'; END IF;
    v_burn := public.myth_utility_charge(u.id, 'PASS_LEVELS', v_myth, s.id::text, p_idempotency_key,
      jsonb_build_object('levels', p_levels, 'fcEquivalent', v_price));
  ELSE
    IF COALESCE(u.forge_coins,0) < v_price THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;
    UPDATE public.game_players SET forge_coins = forge_coins - v_price WHERE id = u.id;
    INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
    VALUES (u.id, 'battle_pass_level_purchase', -v_price, v_before, v_before - v_price, p_idempotency_key);
  END IF;

  UPDATE public.player_season_pass SET xp = v_new_xp, updated_at = now()
    WHERE user_id = u.id AND season_id = s.id;

  INSERT INTO public.season_pass_level_purchases
    (user_id, season_id, purchase_date, levels_bought, fc_spent, level_before, level_after, xp_before, xp_after, idempotency_key)
  VALUES (u.id, s.id, v_day, p_levels, CASE WHEN v_cur = 'MYTH' THEN 0 ELSE v_price END,
    v_level, v_new_level, p.xp, v_new_xp, p_idempotency_key);

  RETURN public.get_season_pass_dashboard(p_telegram_id)
    || jsonb_build_object('purchase', jsonb_build_object('levelsBought', p_levels,
         'fcSpent', CASE WHEN v_cur = 'MYTH' THEN 0 ELSE v_price END, 'paidWith', v_cur,
         'mythSpent', COALESCE(v_myth, 0), 'mythBurn', v_burn,
         'levelBefore', v_level, 'levelAfter', v_new_level));
END; $function$;

-- One-tap purchase with the internal TON balance: full price or nothing.
CREATE OR REPLACE FUNCTION public.season_pass_buy_with_internal_ton(p_telegram_id bigint, p_tier text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u public.game_players; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_price numeric; v_upgrade boolean := false; v_row public.player_season_pass; v_before numeric;
BEGIN
  IF p_tier NOT IN ('adventurer','legendary') THEN RAISE EXCEPTION 'INVALID_PASS_TIER'; END IF;
  IF length(coalesce(p_idempotency_key,'')) < 8 THEN RAISE EXCEPTION 'INVALID_IDEMPOTENCY_KEY'; END IF;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pass_internal:'||u.id::text, 0));
  IF EXISTS (SELECT 1 FROM public.wallet_ledger WHERE reference_id = p_idempotency_key
              AND type = 'battle_pass_internal_ton') THEN
    RETURN public.get_season_pass_dashboard(p_telegram_id) || jsonb_build_object('purchase',
      jsonb_build_object('duplicate', true, 'paidWith', 'INTERNAL_TON'));
  END IF;

  SELECT * INTO s FROM public.season_pass_seasons WHERE id = public.pass_user_season_id(u.id);
  IF s.id IS NULL THEN RAISE EXCEPTION 'SEASON_NOT_AVAILABLE'; END IF;

  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (u.id, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = u.id AND season_id = s.id FOR UPDATE;
  IF p.tier = 'legendary' THEN RAISE EXCEPTION 'PASS_ALREADY_OWNED'; END IF;
  IF p_tier = 'adventurer' AND p.tier = 'adventurer' THEN RAISE EXCEPTION 'PASS_ALREADY_OWNED'; END IF;

  v_upgrade := (p_tier = 'legendary' AND p.tier = 'adventurer');
  v_price := CASE
    WHEN p_tier = 'adventurer' THEN s.adventurer_price_ton
    WHEN v_upgrade THEN GREATEST(s.legendary_price_ton - s.adventurer_price_ton, 0)
    ELSE s.legendary_price_ton END;
  IF COALESCE(v_price,0) <= 0 THEN RAISE EXCEPTION 'INVALID_PASS_PRICE'; END IF;

  v_before := COALESCE(u.ton_balance, 0);
  -- Never split the payment: either the internal balance pays it fully, or TonConnect does.
  IF v_before < v_price THEN RAISE EXCEPTION 'INSUFFICIENT_TON_BALANCE'; END IF;

  UPDATE public.game_players SET ton_balance = round(v_before - v_price, 9), updated_at = now() WHERE id = u.id;
  INSERT INTO public.wallet_ledger(user_id, type, amount_ton, balance_before, balance_after, reference_id)
  VALUES (u.id, 'battle_pass_internal_ton', -v_price, v_before, round(v_before - v_price, 9), p_idempotency_key);

  v_row := public.season_pass_apply_entitlement(u.id, s.id, p_tier);
  PERFORM public.record_ton_revenue(u.id, v_price, 'battle_pass', s.id::text || ':' || p_tier, NULL);

  RETURN public.get_season_pass_dashboard(p_telegram_id) || jsonb_build_object('purchase',
    jsonb_build_object('tier', v_row.tier, 'paidWith', 'INTERNAL_TON', 'tonSpent', v_price,
      'upgrade', v_upgrade, 'seasonId', s.id));
END $function$;

GRANT EXECUTE ON FUNCTION public.season_pass_buy_with_internal_ton(bigint, text, text) TO service_role;
