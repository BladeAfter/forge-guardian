-- Marketplace maintenance switch -------------------------------------------------
INSERT INTO public.game_settings(key, value, category, label) VALUES
  ('marketplace_enabled', to_jsonb(true), 'marketplace', 'Marketplace ativo'),
  ('marketplace_maintenance_message', to_jsonb('We are improving the Player Market. Please try again later.'::text), 'marketplace', 'Mensagem de manutenção'),
  ('marketplace_admin_bypass', '[8118569391]'::jsonb, 'marketplace', 'IDs com acesso durante manutenção')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.market_status_json()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'enabled', coalesce((select (value #>> '{}')::boolean from game_settings where key = 'marketplace_enabled'), true),
    'maintenanceMessage', coalesce((select (value #>> '{}') from game_settings where key = 'marketplace_maintenance_message'),
      'We are improving the Player Market. Please try again later.'),
    'updatedAt', (select updated_at from game_settings where key = 'marketplace_enabled'),
    'bypassCount', coalesce((select jsonb_array_length(value) from game_settings where key = 'marketplace_admin_bypass'), 0)
  );
$function$;

-- Central authorization: the only place that knows about the bypass whitelist.
CREATE OR REPLACE FUNCTION public.market_is_bypass_admin(p_telegram_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from game_settings s,
      lateral jsonb_array_elements_text(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) e(v)
     where s.key = 'marketplace_admin_bypass' and e.v = p_telegram_id::text
  );
$function$;

CREATE OR REPLACE FUNCTION public.market_can_access(p_telegram_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (market_status_json()->>'enabled')::boolean or market_is_bypass_admin(p_telegram_id);
$function$;

CREATE OR REPLACE FUNCTION public.market_status(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select market_status_json()
    || jsonb_build_object(
         'adminBypass', market_is_bypass_admin(p_telegram_id),
         'canAccess', market_can_access(p_telegram_id))
    - 'bypassCount';
$function$;

-- Gate every player-facing market RPC ------------------------------------------
CREATE OR REPLACE FUNCTION public.market_browse(p_telegram_id bigint, p_item_type text DEFAULT 'all'::text, p_rarity text DEFAULT 'all'::text, p_sort text DEFAULT 'newest'::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; balance numeric := 0; pending numeric := 0; rows_json jsonb; lim integer := least(greatest(coalesce(p_limit,60),1),100);
begin
  if not market_can_access(p_telegram_id) then
    return jsonb_build_object('listings', '[]'::jsonb, 'balanceFc', 0, 'pendingFc', 0,
      'settings', market_settings_json(), 'eligibility', null, 'activeCount', 0,
      'status', market_status(p_telegram_id));
  end if;

  select id, forge_coins, market_pending_fc into u, balance, pending from game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(item), '[]'::jsonb) into rows_json from (
    select jsonb_build_object(
      'id', l.id, 'itemType', l.item_type, 'priceFc', l.price_fc, 'quantity', l.quantity,
      'createdAt', l.created_at, 'mine', (l.seller_user_id = u),
      'seller', coalesce(l.snapshot->>'seller', market_seller_label(l.seller_user_id)),
      'name', coalesce(l.snapshot->>'name','Item'),
      'rarity', lower(coalesce(l.snapshot->>'rarity','common')),
      'level', coalesce((l.snapshot->>'level')::integer, 1),
      'image', l.snapshot->>'image',
      'atk', coalesce((l.snapshot->>'atk')::numeric, 0),
      'hp', coalesce((l.snapshot->>'hp')::numeric, 0),
      'stars', coalesce((l.snapshot->>'stars')::integer, 0)
    ) as item
    from market_listings l
    where l.status = 'active'
      and (l.risk_level <> 'high' or l.seller_user_id = u)
      and (coalesce(p_item_type,'all') = 'all' or l.item_type = p_item_type)
      and (coalesce(p_rarity,'all') = 'all' or lower(coalesce(l.snapshot->>'rarity','common')) = lower(p_rarity))
    order by
      case when p_sort = 'price_low' then l.price_fc end asc nulls last,
      case when p_sort = 'price_high' then l.price_fc end desc nulls last,
      l.created_at desc
    limit lim offset greatest(coalesce(p_offset,0),0)
  ) q;

  return jsonb_build_object('listings', rows_json, 'balanceFc', coalesce(balance,0),
    'pendingFc', coalesce(pending,0),
    'settings', market_settings_json(),
    'eligibility', case when u is null then null else market_sell_eligibility(u) end,
    'status', market_status(p_telegram_id),
    'activeCount', (select count(*) from market_listings where seller_user_id = u and status = 'active'));
end $function$;

CREATE OR REPLACE FUNCTION public.market_get_sellable(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; heroes jsonb; pets jsonb; items jsonb;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', h.id, 'name', h.name, 'rarity', h.rarity, 'level', h.level, 'image', h.image,
    'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0)),
    'priceRange', market_price_range('hero', h.rarity, h.level)
  ) order by h.created_at desc), '[]'::jsonb) into heroes
  from player_heroes h
  where h.user_id = u and not h.market_locked and coalesce(h.locked,false) = false
    and coalesce(h.tradable, true) = true
    and not exists (select 1 from pvp_team_slots s where s.player_hero_id = h.id)
    and not exists (select 1 from boss_team_slots b where b.hero_id = h.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', pet.name, 'rarity', p.rarity, 'level', p.level,
    'image', coalesce(pet.image_adult_url, pet.image_young_url, pet.image_baby_url),
    'evolution', p.evolution_stage, 'tier', coalesce(p.evolution_tier,0),
    'priceRange', market_price_range('pet', p.rarity, p.level)
  ) order by p.created_at desc), '[]'::jsonb) into pets
  from player_pets p join pets pet on pet.id = p.pet_id
  where p.user_id = u and not p.market_locked and not coalesce(p.is_active,false)
    and coalesce(p.tradable, true) = true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code', i.item_code, 'itemType', i.item_type, 'quantity', i.quantity,
    'priceRange', market_price_range('item', 'default', 1)
  ) order by i.item_code), '[]'::jsonb) into items
  from player_inventory i
  where i.user_id = u and i.quantity > 0 and coalesce(i.tradable, true) = true
    and i.item_type not in ('fragments');

  return jsonb_build_object('heroes', heroes, 'pets', pets, 'items', items,
    'settings', market_settings_json(), 'eligibility', market_sell_eligibility(u),
    'status', market_status(p_telegram_id));
end $function$;

CREATE OR REPLACE FUNCTION public.market_my_listings(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; pending numeric := 0;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select id, market_pending_fc into u, pending from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object(
    'listings', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'itemType', l.item_type, 'name', coalesce(l.snapshot->>'name','Item'),
        'rarity', lower(coalesce(l.snapshot->>'rarity','common')), 'level', coalesce((l.snapshot->>'level')::integer,1),
        'image', l.snapshot->>'image', 'priceFc', l.price_fc, 'status', l.status,
        'createdAt', l.created_at, 'soldAt', l.sold_at, 'cancelledAt', l.cancelled_at,
        'feePercent', l.fee_percent
      ) order by l.created_at desc), '[]'::jsonb) from market_listings l where l.seller_user_id = u),
    'purchases', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'itemType', t.item_type, 'name', coalesce(t.snapshot->>'name','Item'),
        'rarity', lower(coalesce(t.snapshot->>'rarity','common')), 'image', t.snapshot->>'image',
        'priceFc', t.price_fc, 'createdAt', t.created_at,
        'status', case when t.status = 'settled' then 'settled' else 'processing' end,
        'seller', market_seller_label(t.seller_user_id)
      ) order by t.created_at desc), '[]'::jsonb) from market_transactions t where t.buyer_user_id = u),
    'sales', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', coalesce(t.snapshot->>'name','Item'), 'priceFc', t.price_fc,
        'receivedFc', t.seller_received_fc, 'createdAt', t.created_at,
        'settleAt', t.settle_at,
        'status', case when t.status = 'settled' then 'settled'
                       when t.status = 'reversed' then 'reversed' else 'pending' end
      ) order by t.created_at desc), '[]'::jsonb) from market_transactions t where t.seller_user_id = u),
    'pendingFc', coalesce(pending, 0),
    'status', market_status(p_telegram_id),
    'settings', market_settings_json()
  );
end $function$;

CREATE OR REPLACE FUNCTION public.market_price_quote(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid DEFAULT NULL, p_item_code text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; kind text := lower(coalesce(p_item_type,'')); rar text := 'default'; lvl integer := 1;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if kind = 'hero' then
    select lower(h.rarity), h.level into rar, lvl from player_heroes h where h.id = p_item_instance_id and h.user_id = u;
  elsif kind = 'pet' then
    select lower(p.rarity), p.level into rar, lvl from player_pets p where p.id = p_item_instance_id and p.user_id = u;
  else
    kind := 'item';
  end if;
  return jsonb_build_object(
    'range', market_price_range(kind, coalesce(rar,'default'), coalesce(lvl,1)),
    'settings', market_settings_json(),
    'eligibility', market_sell_eligibility(u));
end $function$;

-- create / cancel / buy: maintenance is enforced server-side, not in the client.
CREATE OR REPLACE FUNCTION public.market_create_listing(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid, p_item_code text, p_price_fc numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid; settings jsonb; fee numeric; max_active integer; elig jsonb; range jsonb;
  active_count integer; snap jsonb; listing_id uuid; kind text := lower(coalesce(p_item_type,''));
  h player_heroes%rowtype; pp player_pets%rowtype; inv player_inventory%rowtype; pet_row pets%rowtype;
  rar text := 'default'; lvl integer := 1; price numeric; risk text := 'low'; sell_today numeric;
  g game_players%rowtype; nal jsonb;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  if kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  select * into g from game_players where telegram_id = p_telegram_id for update;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  u := g.id;

  if g.market_cooldown_until is not null and g.market_cooldown_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;

  elig := market_sell_eligibility(u);
  if not (elig->>'canSell')::boolean then raise exception 'MARKET_SELLING_LOCKED'; end if;

  settings := market_settings_json();
  fee := (settings->>'feePercent')::numeric;
  max_active := (settings->>'maxActiveListings')::integer;

  if p_price_fc is null or p_price_fc <> trunc(p_price_fc) or p_price_fc <= 0 then raise exception 'INVALID_PRICE'; end if;
  price := trunc(p_price_fc);

  select count(*) into active_count from market_listings where seller_user_id = u and status = 'active';
  if active_count >= max_active then raise exception 'TOO_MANY_ACTIVE_LISTINGS'; end if;

  if kind = 'hero' then
    select * into h from player_heroes where id = p_item_instance_id and user_id = u for update;
    if h.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if h.market_locked then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(h.locked,false) then raise exception 'HERO_LOCKED'; end if;
    if coalesce(h.tradable,true) = false then raise exception 'HERO_NOT_TRADABLE'; end if;
    if exists (select 1 from pvp_team_slots s where s.player_hero_id = h.id) then raise exception 'HERO_IN_PVP_TEAM'; end if;
    if exists (select 1 from boss_team_slots b where b.hero_id = h.id) then raise exception 'HERO_IN_BOSS_TEAM'; end if;
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
    if inv.item_type = 'fragments' then raise exception 'ITEM_NOT_TRADABLE'; end if;
    rar := 'default'; lvl := 1;
    snap := jsonb_build_object('name', initcap(replace(inv.item_code,'_',' ')), 'rarity', 'rare', 'level', 1,
      'itemType', inv.item_type, 'code', inv.item_code);
  end if;

  range := market_price_range(kind, rar, lvl);
  if price < (range->>'min')::numeric then raise exception 'PRICE_BELOW_MINIMUM'; end if;
  if price > (range->>'max')::numeric then raise exception 'PRICE_ABOVE_MAXIMUM'; end if;

  nal := settings->'newAccountLimits';
  if market_account_days(u) < coalesce((nal->>'days')::integer, 7) then
    select coalesce(sum(price_fc),0) into sell_today from market_transactions
     where seller_user_id = u and status <> 'reversed' and created_at > now() - interval '24 hours';
    if sell_today + price > coalesce((nal->>'sellFcPerDay')::numeric, 250000) then raise exception 'DAILY_SELL_LIMIT'; end if;
  end if;

  if kind = 'hero' then
    update player_heroes set market_locked = true, updated_at = now() where id = p_item_instance_id;
  elsif kind = 'pet' then
    update player_pets set market_locked = true, updated_at = now() where id = p_item_instance_id;
  else
    update player_inventory set quantity = quantity - 1, updated_at = now() where user_id = u and item_code = p_item_code;
  end if;

  if price >= (range->>'max')::numeric * 0.95 and market_account_days(u) < 14 then risk := 'high';
  elsif price >= (range->>'max')::numeric * 0.9 then risk := 'medium';
  end if;

  insert into market_listings(seller_user_id, item_type, item_instance_id, item_code, price_fc, fee_percent, snapshot, risk_level)
  values (u, kind, case when kind = 'item' then null else p_item_instance_id end,
          case when kind = 'item' then p_item_code else null end, price, fee,
          snap || jsonb_build_object('seller', market_seller_label(u)), risk)
  returning id into listing_id;

  insert into market_security_audit(event, listing_id, seller_user_id, price_fc, details)
  values ('listing_created', listing_id, u, price, jsonb_build_object('range', range, 'riskLevel', risk));

  return jsonb_build_object('ok', true, 'listingId', listing_id, 'feePercent', fee, 'range', range,
    'settlementHours', (settings->>'settlementHours')::integer,
    'sellerReceives', price - round(price * fee / 100));
end $function$;

CREATE OR REPLACE FUNCTION public.market_cancel_listing(p_telegram_id bigint, p_listing_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; l market_listings%rowtype;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  if l.seller_user_id <> u then raise exception 'NOT_LISTING_OWNER'; end if;
  if l.status <> 'active' then raise exception 'LISTING_NOT_ACTIVE'; end if;

  if l.item_type = 'hero' then
    update player_heroes set market_locked = false, updated_at = now() where id = l.item_instance_id;
  elsif l.item_type = 'pet' then
    update player_pets set market_locked = false, updated_at = now() where id = l.item_instance_id;
  else
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (u, coalesce(l.snapshot->>'itemType','item'), l.item_code, l.quantity)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  update market_listings set status = 'cancelled', cancelled_at = now() where id = l.id;
  insert into market_security_audit(event, listing_id, seller_user_id, price_fc)
  values ('listing_cancelled', l.id, u, l.price_fc);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.market_buy_listing(p_telegram_id bigint, p_listing_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  buyer uuid; buyer_before numeric; buyer_after numeric; g game_players%rowtype;
  l market_listings%rowtype; fee_fc numeric; received numeric; settings jsonb;
  risk jsonb; score integer; flags text[]; tx_id uuid; hold_hours integer;
  pair_trades integer; pair_fc numeric; buy_today numeric; v5 integer; v24 integer;
  vel jsonb; pl jsonb; nal jsonb; new_status text;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  perform set_config('mythreon.market_txn', '1', true);
  settings := market_settings_json();

  select * into g from game_players where telegram_id = p_telegram_id for update;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  buyer := g.id; buyer_before := g.forge_coins;
  if coalesce(g.banned,false) then raise exception 'ACCOUNT_BANNED'; end if;
  if g.market_cooldown_until is not null and g.market_cooldown_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;
  if g.market_restricted_until is not null and g.market_restricted_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;

  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  if l.status <> 'active' then raise exception 'ITEM_NO_LONGER_AVAILABLE'; end if;
  if l.seller_user_id = buyer then raise exception 'CANNOT_BUY_OWN_LISTING'; end if;
  if buyer_before < l.price_fc then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;

  vel := settings->'velocity';
  select count(*) into v5 from market_transactions where buyer_user_id = buyer and created_at > now() - interval '5 minutes';
  select count(*) into v24 from market_transactions where buyer_user_id = buyer and created_at > now() - interval '24 hours';
  if v5 >= coalesce((vel->>'per5m')::integer, 5) or v24 >= coalesce((vel->>'per24h')::integer, 40) then
    update game_players set market_cooldown_until = now() + make_interval(mins => coalesce((vel->>'cooldownMinutes')::integer, 360))
      where id = buyer;
    insert into market_security_audit(event, listing_id, buyer_user_id, seller_user_id, price_fc, risk_flags, details)
    values ('risk_flag', l.id, buyer, l.seller_user_id, l.price_fc, array['HIGH_VELOCITY'], jsonb_build_object('per5m', v5, 'per24h', v24));
    raise exception 'MARKET_TEMPORARILY_LIMITED';
  end if;

  pl := settings->'pairLimits';
  select count(*), coalesce(sum(price_fc),0) into pair_trades, pair_fc
    from market_transactions
   where buyer_user_id = buyer and seller_user_id = l.seller_user_id
     and status <> 'reversed' and created_at > now() - interval '24 hours';
  if pair_trades >= coalesce((pl->>'tradesPerDay')::integer, 3) then raise exception 'PAIR_TRADE_LIMIT'; end if;
  if pair_fc + l.price_fc > coalesce((pl->>'fcPerDay')::numeric, 2000000) then raise exception 'PAIR_VALUE_LIMIT'; end if;

  nal := settings->'newAccountLimits';
  if market_account_days(buyer) < coalesce((nal->>'days')::integer, 7) then
    select coalesce(sum(price_fc),0) into buy_today from market_transactions
     where buyer_user_id = buyer and status <> 'reversed' and created_at > now() - interval '24 hours';
    if buy_today + l.price_fc > coalesce((nal->>'buyFcPerDay')::numeric, 500000) then raise exception 'DAILY_BUY_LIMIT'; end if;
  end if;

  risk := market_risk_assess(buyer, l.seller_user_id, l);
  score := (risk->>'score')::integer;
  flags := array(select jsonb_array_elements_text(risk->'flags'));
  new_status := case when score >= 60 or 'SAME_WALLET' = any(flags) or 'CIRCULAR_TRADE' = any(flags)
                       or 'ITEM_RETURNED' = any(flags) then 'review' else 'pending' end;

  fee_fc := round(l.price_fc * l.fee_percent / 100);
  received := l.price_fc - fee_fc;
  hold_hours := coalesce((settings->>'settlementHours')::integer, 72);

  update game_players set forge_coins = forge_coins - l.price_fc, updated_at = now()
    where id = buyer returning forge_coins into buyer_after;

  update game_players set market_pending_fc = market_pending_fc + received, updated_at = now()
    where id = l.seller_user_id;

  if l.item_type = 'hero' then
    delete from pvp_team_slots where player_hero_id = l.item_instance_id;
    delete from boss_team_slots where hero_id = l.item_instance_id;
    update player_heroes set user_id = buyer, market_locked = false, updated_at = now() where id = l.item_instance_id;
  elsif l.item_type = 'pet' then
    update player_pets set user_id = buyer, market_locked = false, is_active = false, updated_at = now() where id = l.item_instance_id;
  else
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (buyer, coalesce(l.snapshot->>'itemType','item'), l.item_code, l.quantity)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  update market_listings set status = 'sold', buyer_user_id = buyer, sold_at = now() where id = l.id;

  insert into market_transactions(listing_id, seller_user_id, buyer_user_id, item_type, item_instance_id, item_code,
    price_fc, fee_percent, fee_fc, seller_received_fc, snapshot, status, settle_at, risk_score, risk_flags)
  values (l.id, l.seller_user_id, buyer, l.item_type, l.item_instance_id, l.item_code,
    l.price_fc, l.fee_percent, fee_fc, received, l.snapshot, new_status,
    now() + make_interval(hours => hold_hours), score, flags)
  returning id into tx_id;

  insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, price_fc)
  values (l.item_type, l.item_instance_id, l.item_code, l.seller_user_id, buyer, l.id, tx_id, l.price_fc);

  insert into market_pair_stats(buyer_user_id, seller_user_id, trades, total_fc)
  values (buyer, l.seller_user_id, 1, l.price_fc)
  on conflict (buyer_user_id, seller_user_id) do update
    set trades = market_pair_stats.trades + 1,
        total_fc = market_pair_stats.total_fc + excluded.total_fc,
        last_trade_at = now();

  insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
  values (buyer, 'market_purchase', -l.price_fc, buyer_before, buyer_after, tx_id::text);

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, price_fc, fee_fc, risk_score, risk_flags, details)
  values ('sale_created', l.id, tx_id, buyer, l.seller_user_id, l.price_fc, fee_fc, score, flags,
          jsonb_build_object('status', new_status, 'settleAt', now() + make_interval(hours => hold_hours), 'pair', jsonb_build_object('trades', pair_trades, 'fc', pair_fc)));

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (l.seller_user_id, 'market_sale', 'MARKET',
    coalesce(l.snapshot->>'name','Item') || ' vendido por ' || l.price_fc::bigint || ' FC',
    received, jsonb_build_object('listingId', l.id, 'feeFc', fee_fc, 'holdHours', hold_hours, 'status', 'pending'),
    'market_sale:' || l.id::text);

  return jsonb_build_object('ok', true, 'pricePaid', l.price_fc, 'feeFc', fee_fc,
    'sellerReceived', received, 'balanceFc', buyer_after, 'itemType', l.item_type,
    'name', l.snapshot->>'name', 'settlementHours', hold_hours,
    'underReview', new_status = 'review');
end $function$;

-- Admin toggle -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_market_set_enabled(p_admin_id bigint, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare old_value boolean;
begin
  perform admin_assert(p_admin_id);
  if p_enabled is null then raise exception 'INVALID_VALUE'; end if;
  select (value #>> '{}')::boolean into old_value from game_settings where key = 'marketplace_enabled';
  insert into game_settings(key, value, category, label, updated_by)
  values ('marketplace_enabled', to_jsonb(p_enabled), 'marketplace', 'Marketplace ativo', p_admin_id)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = p_admin_id;

  perform admin_log(p_admin_id, case when p_enabled then 'MARKET_ENABLED' else 'MARKET_DISABLED' end,
    'market', 'marketplace_enabled', to_jsonb(coalesce(old_value, true)), to_jsonb(p_enabled), null, '{}'::jsonb);
  insert into market_security_audit(event, admin_id, details)
  values (case when p_enabled then 'MARKET_ENABLED' else 'MARKET_DISABLED' end, p_admin_id,
          jsonb_build_object('oldValue', coalesce(old_value, true), 'newValue', p_enabled));

  return market_status_json();
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_overview(p_admin_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_assert(p_admin_id);
  return jsonb_build_object(
    'settings', market_settings_json(),
    'status', market_status_json(),
    'active', (select count(*) from market_listings where status = 'active'),
    'sold', (select count(*) from market_listings where status = 'sold'),
    'cancelled', (select count(*) from market_listings where status = 'cancelled'),
    'volumeFc', (select coalesce(sum(price_fc),0) from market_transactions where status <> 'reversed'),
    'burnedFc', (select coalesce(sum(fee_fc),0) from market_transactions where status = 'settled'),
    'pendingTrades', (select count(*) from market_transactions where status = 'pending'),
    'reviewTrades', (select count(*) from market_transactions where status = 'review'),
    'reversedTrades', (select count(*) from market_transactions where status = 'reversed'),
    'heldFc', (select coalesce(sum(market_pending_fc),0) from game_players)
  );
end $function$;

DO $$
DECLARE fn text;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure::text
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND (p.proname LIKE 'market\_%' OR p.proname LIKE 'admin\_market\_%')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;