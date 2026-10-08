-- Helper: lock reasons for a hero
CREATE OR REPLACE FUNCTION public.market_hero_locks(p_hero public.player_heroes)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT coalesce(jsonb_agg(x), '[]'::jsonb) FROM (
    SELECT 'listed'::text AS x WHERE coalesce(p_hero.market_locked,false)
    UNION ALL SELECT 'locked' WHERE coalesce(p_hero.locked,false)
    UNION ALL SELECT 'not_tradable' WHERE coalesce(p_hero.tradable,true) = false
    UNION ALL SELECT 'pvp_team' WHERE EXISTS (SELECT 1 FROM public.pvp_team_slots s WHERE s.hero_id = p_hero.id)
    UNION ALL SELECT 'global_boss_team' WHERE EXISTS (SELECT 1 FROM public.boss_team_slots b WHERE b.player_hero_id = p_hero.id)
  ) q;
$$;

CREATE OR REPLACE FUNCTION public.market_get_sellable(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; heroes jsonb; pets jsonb; items jsonb; g game_players%rowtype;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select * into g from game_players where telegram_id = p_telegram_id;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  u := g.id;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.created_at desc), '[]'::jsonb) into heroes
  from (
    select h.id, h.name, h.rarity, h.level, h.image, h.created_at,
      coalesce(h.fusion_level,0) as stars,
      round(coalesce(h.final_atk,0)) as atk,
      round(coalesce(h.final_hp,0)) as hp,
      market_hero_locks(h.*) as locks,
      (jsonb_array_length(market_hero_locks(h.*)) = 0) as available,
      market_price_range('hero', h.rarity, h.level, 'FC') as "priceRange",
      market_price_range('hero', h.rarity, h.level, 'TON') as "priceRangeTon"
    from player_heroes h where h.user_id = u
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.created_at desc), '[]'::jsonb) into pets
  from (
    select p.id, pet.name, p.rarity, p.level, p.created_at,
      coalesce(pet.image_adult_url, pet.image_young_url, pet.image_baby_url) as image,
      p.evolution_stage as evolution, coalesce(p.evolution_tier,0) as tier,
      (
        case when coalesce(p.market_locked,false) then jsonb_build_array('listed') else '[]'::jsonb end
        || case when coalesce(p.is_active,false) then jsonb_build_array('active_pet') else '[]'::jsonb end
        || case when coalesce(p.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
      ) as locks,
      (not coalesce(p.market_locked,false) and not coalesce(p.is_active,false) and coalesce(p.tradable,true)) as available,
      market_price_range('pet', p.rarity, p.level, 'FC') as "priceRange",
      market_price_range('pet', p.rarity, p.level, 'TON') as "priceRangeTon"
    from player_pets p join pets pet on pet.id = p.pet_id
    where p.user_id = u
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.code), '[]'::jsonb) into items
  from (
    select i.item_code as code, i.item_type as "itemType", i.quantity,
      (
        case when coalesce(i.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
        || case when i.item_type = 'fragments' then jsonb_build_array('not_tradable') else '[]'::jsonb end
        || case when coalesce(i.is_exclusive,false) then jsonb_build_array('exclusive') else '[]'::jsonb end
      ) as locks,
      (coalesce(i.tradable,true) and i.item_type <> 'fragments' and not coalesce(i.is_exclusive,false)) as available,
      market_price_range('item', 'default', 1, 'FC') as "priceRange",
      market_price_range('item', 'default', 1, 'TON') as "priceRangeTon"
    from player_inventory i where i.user_id = u and i.quantity > 0
  ) t;

  return jsonb_build_object('heroes', heroes, 'pets', pets, 'items', items,
    'balanceFc', coalesce(g.forge_coins,0),
    'availableTon', greatest(coalesce(g.ton_balance,0) - coalesce(g.ton_reserved,0), 0),
    'settings', market_settings_json(), 'eligibility', market_sell_eligibility(u),
    'status', market_status(p_telegram_id));
end $function$;

-- Fix the swapped column names in the listing validation
CREATE OR REPLACE FUNCTION public.market_create_listing(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid, p_item_code text, p_price_fc numeric DEFAULT NULL::numeric, p_currency text DEFAULT 'FC'::text, p_price_ton numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid; settings jsonb; fee numeric; max_active integer; elig jsonb; range jsonb;
  active_count integer; snap jsonb; listing_id uuid; kind text := lower(coalesce(p_item_type,''));
  cur text := case when upper(coalesce(p_currency,'FC')) = 'TON' then 'TON' else 'FC' end;
  h player_heroes%rowtype; pp player_pets%rowtype; inv player_inventory%rowtype; pet_row pets%rowtype;
  rar text := 'default'; lvl integer := 1; price numeric; risk text := 'low'; sell_today numeric;
  g game_players%rowtype; nal jsonb; is_admin boolean; currencies jsonb;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  if kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  select * into g from game_players where telegram_id = p_telegram_id for update;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  u := g.id;
  is_admin := market_is_bypass_admin(p_telegram_id);

  settings := market_settings_json();
  currencies := settings->'currencies';
  if not is_admin then
    if cur = 'TON' and not coalesce((currencies->>'ton')::boolean, true) then raise exception 'CURRENCY_DISABLED'; end if;
    if cur = 'FC' and not coalesce((currencies->>'fc')::boolean, true) then raise exception 'CURRENCY_DISABLED'; end if;
    if g.market_cooldown_until is not null and g.market_cooldown_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;
    elig := market_sell_eligibility(u);
    if not (elig->>'canSell')::boolean then
      raise exception '%', coalesce(elig->>'reason', 'MARKET_SELLING_LOCKED');
    end if;
  end if;

  fee := case when cur = 'TON' then (settings->>'feePercentTon')::numeric else (settings->>'feePercentFc')::numeric end;
  max_active := (settings->>'maxActiveListings')::integer;

  if cur = 'TON' then
    if p_price_ton is null or p_price_ton <= 0 then raise exception 'INVALID_PRICE'; end if;
    price := round(p_price_ton, 3);
  else
    if p_price_fc is null or p_price_fc <> trunc(p_price_fc) or p_price_fc <= 0 then raise exception 'INVALID_PRICE'; end if;
    price := trunc(p_price_fc);
  end if;

  select count(*) into active_count from market_listings where seller_user_id = u and status in ('active','reserved');
  if active_count >= max_active then raise exception 'TOO_MANY_ACTIVE_LISTINGS'; end if;

  if kind = 'hero' then
    select * into h from player_heroes where id = p_item_instance_id and user_id = u for update;
    if h.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if h.market_locked then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(h.locked,false) then raise exception 'HERO_LOCKED'; end if;
    if coalesce(h.tradable,true) = false then raise exception 'HERO_NOT_TRADABLE'; end if;
    if exists (select 1 from pvp_team_slots s where s.hero_id = h.id) then raise exception 'HERO_IN_PVP_TEAM'; end if;
    if exists (select 1 from boss_team_slots b where b.player_hero_id = h.id) then raise exception 'HERO_IN_BOSS_TEAM'; end if;
    rar := lower(coalesce(h.rarity,'default')); lvl := coalesce(h.level,1);
    snap := jsonb_build_object('name', h.name, 'rarity', h.rarity, 'level', h.level, 'image', h.image,
      'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0)),
      'heroKey', h.hero_key);
  elsif kind = 'pet' then
    select * into pp from player_pets where id = p_item_instance_id and user_id = u for update;
    if pp.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if pp.market_locked then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(pp.is_active,false) then raise exception 'PET_IS_ACTIVE'; end if;
    if coalesce(pp.tradable,true) = false then raise exception 'PET_NOT_TRADABLE'; end if;
    select * into pet_row from pets where id = pp.pet_id;
    rar := lower(coalesce(pp.rarity,'default')); lvl := coalesce(pp.level,1);
    snap := jsonb_build_object('name', coalesce(pet_row.name,'Pet'), 'rarity', pp.rarity, 'level', pp.level,
      'image', coalesce(pet_row.image_adult_url, pet_row.image_young_url, pet_row.image_baby_url),
      'evolution', pp.evolution_stage, 'tier', coalesce(pp.evolution_tier,0));
  else
    if p_item_code is null or length(p_item_code) < 2 then raise exception 'INVALID_ITEM'; end if;
    select * into inv from player_inventory where user_id = u and item_code = p_item_code for update;
    if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(inv.tradable,true) = false then raise exception 'ITEM_NOT_TRADABLE'; end if;
    if coalesce(inv.is_exclusive,false) then raise exception 'ITEM_NOT_TRADABLE'; end if;
    if inv.item_type = 'fragments' then raise exception 'ITEM_NOT_TRADABLE'; end if;
    rar := 'default'; lvl := 1;
    snap := jsonb_build_object('name', initcap(replace(inv.item_code,'_',' ')), 'rarity', 'rare', 'level', 1,
      'itemType', inv.item_type, 'code', inv.item_code);
  end if;

  range := market_price_range(kind, rar, lvl, cur);
  if price < (range->>'min')::numeric then raise exception 'PRICE_BELOW_MINIMUM'; end if;
  if price > (range->>'max')::numeric then raise exception 'PRICE_ABOVE_MAXIMUM'; end if;

  if cur = 'FC' and not is_admin then
    nal := settings->'newAccountLimits';
    if market_account_days(u) < coalesce((nal->>'days')::integer, 7) then
      select coalesce(sum(price_fc),0) into sell_today from market_transactions
       where seller_user_id = u and coalesce(currency,'FC') = 'FC' and status <> 'reversed' and created_at > now() - interval '24 hours';
      if sell_today + price > coalesce((nal->>'sellFcPerDay')::numeric, 250000) then raise exception 'DAILY_SELL_LIMIT'; end if;
    end if;
  end if;

  if kind = 'hero' then
    update player_heroes set market_locked = true, updated_at = now() where id = p_item_instance_id;
  elsif kind = 'pet' then
    update player_pets set market_locked = true, updated_at = now() where id = p_item_instance_id;
  else
    update player_inventory set quantity = quantity - 1, updated_at = now() where user_id = u and item_code = p_item_code;
  end if;

  if price >= (range->>'max')::numeric * 0.95 and market_account_days(u) < 14 and not is_admin then risk := 'high';
  elsif price >= (range->>'max')::numeric * 0.9 then risk := 'medium';
  end if;

  insert into market_listings(seller_user_id, item_type, item_instance_id, item_code, currency, price_fc, price_ton, fee_percent, snapshot, risk_level)
  values (u, kind, case when kind = 'item' then null else p_item_instance_id end,
          case when kind = 'item' then p_item_code else null end, cur,
          case when cur = 'FC' then price else null end,
          case when cur = 'TON' then price else null end, fee,
          snap || jsonb_build_object('seller', market_seller_label(u)), risk)
  returning id into listing_id;

  insert into market_security_audit(event, listing_id, seller_user_id, price_fc, details)
  values ('listing_created', listing_id, u, case when cur = 'FC' then price else null end,
          jsonb_build_object('range', range, 'riskLevel', risk, 'currency', cur, 'price', price));

  return jsonb_build_object('ok', true, 'listingId', listing_id, 'feePercent', fee, 'range', range,
    'currency', cur, 'price', price,
    'settlementHours', case when cur = 'TON' then (settings->>'settlementHoursTon')::integer else (settings->>'settlementHours')::integer end,
    'sellerReceives', case when cur = 'TON' then round(price - price * fee / 100, 3) else price - round(price * fee / 100) end);
end $function$;

REVOKE ALL ON FUNCTION public.market_hero_locks(public.player_heroes) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.market_get_sellable(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.market_create_listing(bigint, text, uuid, text, numeric, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_hero_locks(public.player_heroes) TO service_role;
GRANT EXECUTE ON FUNCTION public.market_get_sellable(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.market_create_listing(bigint, text, uuid, text, numeric, text, numeric) TO service_role;