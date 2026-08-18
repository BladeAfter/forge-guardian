
create or replace function public.open_exclusive_chest(p_telegram_id bigint, p_inventory_item_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  u uuid; inv player_inventory%rowtype; v_kind text; hc hero_catalog%rowtype; pt pets%rowtype;
  v_id uuid; v_seed int; v_reward jsonb; v_chest_code text; v_frag int;
begin
  select id into u from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('exclusive_chest:'||u::text, 7));

  select * into inv from player_inventory
    where id = p_inventory_item_id and user_id = u and item_type = 'exclusive_chest' for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;
  v_kind := case when inv.item_code ilike '%pet%' then 'pet' else 'hero' end;
  v_seed := (random()*1000000)::int;

  update player_inventory set quantity = quantity - 1, updated_at = now() where id = inv.id;
  delete from player_inventory where id = inv.id and quantity <= 0;

  if v_kind = 'hero' then
    select * into hc from hero_catalog c
      where c.rarity = 'mythic' and coalesce(c.is_pass_exclusive, false) = false and coalesce(c.enabled, true)
        and not exists (select 1 from player_heroes h where h.user_id = u and h.hero_key = c.hero_key)
      order by random() limit 1;
    if hc.hero_key is null then
      select * into hc from hero_catalog c
        where c.rarity = 'mythic' and coalesce(c.is_pass_exclusive, false) = false and coalesce(c.enabled, true)
        order by random() limit 1;
    end if;
    if hc.hero_key is not null then
      -- pass_exclusive = true: pass chest heroes are collection/combat only and NEVER mine TON.
      insert into player_heroes(user_id, hero_key, name, rarity, level, image, attribute_seed, pass_exclusive)
      values (u, hc.hero_key, hc.name, 'mythic', 1, hc.image, v_seed, true) returning id into v_id;
      v_reward := jsonb_build_object('kind','hero','exclusive',true,'heroId',v_id,'heroKey',hc.hero_key,
        'name',hc.name,'rarity','mythic','image',hc.image,'title',hc.name,'mining',false);
    end if;
  else
    select * into pt from pets p
      where p.rarity = 'mythic' and coalesce(p.is_pass_exclusive, false) = false and coalesce(p.is_enabled, true)
        and not exists (select 1 from player_pets pp where pp.user_id = u and pp.pet_id = p.id)
      order by random() limit 1;
    if pt.id is null then
      select * into pt from pets p
        where p.rarity = 'mythic' and coalesce(p.is_pass_exclusive, false) = false and coalesce(p.is_enabled, true)
        order by random() limit 1;
    end if;
    if pt.id is not null then
      insert into player_pets(user_id, pet_id, rarity, level, xp, evolution_stage,
        is_season_exclusive, exclusive_badge, tradable, pass_exclusive)
      values (u, pt.id, 'mythic', 1, 0, 'baby', false, 'MYTHIC', true, true) returning id into v_id;
      v_reward := jsonb_build_object('kind','pet','exclusive',true,'petId',v_id,'petSlug',pt.slug,
        'name',pt.name,'rarity','mythic','image',coalesce(pt.image_base_url, pt.image_baby_url),'title',pt.name,'mining',false);
    end if;
  end if;

  if v_reward is null then
    v_frag := add_universal_fragments(u, 100);
    select chest_code into v_chest_code from chest_reward_tables
      where enabled order by coalesce((rarity_rates->>'legendary')::numeric, 0) desc nulls last limit 1;
    if v_chest_code is not null then
      insert into player_inventory(user_id, item_type, item_code, quantity)
      values (u, 'hero_chest', v_chest_code, 1)
      on conflict(user_id, item_type, item_code)
        do update set quantity = player_inventory.quantity + 1, updated_at = now();
    end if;
    update game_players set forge_coins = forge_coins + 50000, updated_at = now() where id = u;
    v_reward := jsonb_build_object('kind','fallback','exclusive',true,'title','COLEÇÃO COMPLETA',
      'fragments',100,'fragmentBalance',v_frag,'chestCode',v_chest_code,'forgeCoins',50000);
  end if;

  insert into reward_open_logs(user_id, telegram_id, source, item_key, item_type, rolled_rarity, reward_id, reward_name)
  values (u, p_telegram_id, 'season_pass', inv.item_code, 'exclusive_chest', 'mythic', v_id, v_reward->>'name');

  return jsonb_build_object('reward', v_reward, 'chestCode', inv.item_code,
    'inventory', get_player_inventory(p_telegram_id));
end $function$;

create or replace function public.get_season_pass_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $function$
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
      'priceTon', COALESCE((v_locked->>'price_ton')::numeric, 2.5),
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
          AND COALESCE((v_locked->>'enabled')::boolean, true),
        'priceTon', CASE WHEN COALESCE(r.min_pass_version, 1) > v_ver
          THEN COALESCE((v_locked->>'price_ton')::numeric, 2.5) ELSE NULL END,
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
