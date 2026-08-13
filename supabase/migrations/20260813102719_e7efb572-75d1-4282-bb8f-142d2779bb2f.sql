alter table public.market_security_audit alter column price_fc drop not null;
alter table public.market_security_audit alter column fee_fc drop not null;
alter table public.market_security_audit alter column price_fc drop default;
alter table public.market_security_audit alter column fee_fc drop default;
alter table public.market_security_audit add column if not exists price_ton numeric null;
alter table public.market_security_audit add column if not exists fee_ton numeric null;
alter table public.market_security_audit add column if not exists currency text null;

update public.market_security_audit set currency = 'FC' where currency is null and price_fc is not null;

alter table public.market_security_audit drop constraint if exists market_security_audit_currency_price_check;
alter table public.market_security_audit add constraint market_security_audit_currency_price_check check (
  currency is null
  or (currency = 'FC' and price_ton is null and fee_ton is null)
  or (currency = 'TON' and price_fc is null and fee_fc is null)
);

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

  insert into market_security_audit(event, listing_id, seller_user_id, currency, price_fc, fee_fc, price_ton, fee_ton, details)
  values ('listing_created', listing_id, u, cur,
          case when cur = 'FC' then price else null end,
          case when cur = 'FC' then round(price * fee / 100) else null end,
          case when cur = 'TON' then price else null end,
          case when cur = 'TON' then round(price * fee / 100, 3) else null end,
          jsonb_build_object('range', range, 'riskLevel', risk, 'currency', cur, 'price', price));

  return jsonb_build_object('ok', true, 'listingId', listing_id, 'feePercent', fee, 'range', range,
    'currency', cur, 'price', price,
    'settlementHours', case when cur = 'TON' then (settings->>'settlementHoursTon')::integer else (settings->>'settlementHours')::integer end,
    'sellerReceives', case when cur = 'TON' then round(price - price * fee / 100, 3) else price - round(price * fee / 100) end);
end $function$;