alter table public.player_equipment add column if not exists market_locked boolean not null default false;

-- ---------------------------------------------------------------------------
-- Single source of truth for the TON minimum listing price.
-- Legendary+ heroes: 4 TON. Everything else: 0.10 TON.
-- ---------------------------------------------------------------------------
create or replace function public.market_min_price_ton(p_item_type text, p_rarity text)
returns numeric language sql immutable set search_path to 'public' as $fn$
  select case
    when lower(coalesce(p_item_type,'')) = 'hero'
     and lower(coalesce(p_rarity,'')) in ('legendary','mythic','ancestral','nft_exclusive','divine','celestial')
    then 4::numeric
    else 0.10::numeric
  end;
$fn$;

-- ---------------------------------------------------------------------------
-- Stackable / instance item sources. `code` namespaces the real inventory row:
--   <inventory_code> | food:<code> | ufrag | pfrag:<player_pet_id> | equip:<player_equipment_id>
-- ---------------------------------------------------------------------------
create or replace function public.market_item_take(p_user uuid, p_code text, p_qty integer)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  code text := lower(coalesce(p_code,'')); qty integer := greatest(coalesce(p_qty,1),1); ref text;
  inv player_inventory%rowtype; pf player_pet_food%rowtype; food pet_food_items%rowtype;
  upi player_pet_inventory%rowtype; pp player_pets%rowtype; pet_row pets%rowtype;
  pe player_equipment%rowtype; tpl equipment_templates%rowtype; rar text;
begin
  if code like 'food:%' then
    ref := substr(code, 6);
    select * into pf from player_pet_food where user_id = p_user and food_code = ref for update;
    if pf.user_id is null or coalesce(pf.quantity,0) < qty then raise exception 'ITEM_NOT_OWNED'; end if;
    select * into food from pet_food_items where code = ref;
    update player_pet_food set quantity = quantity - qty, updated_at = now()
      where user_id = p_user and food_code = ref;
    return jsonb_build_object('source','food','ref',ref,'code',code,'stackable',true,
      'name', coalesce(food.name, initcap(replace(ref,'_',' '))), 'image', food.icon,
      'rarity', coalesce(food.rarity,'common'), 'itemType','food','category','food','quantity', qty);

  elsif code = 'ufrag' then
    select * into upi from player_pet_inventory
      where user_id = p_user and item_type = 'universal_fragment' and item_id is null for update;
    if upi.id is null or coalesce(upi.quantity,0) < qty then raise exception 'ITEM_NOT_OWNED'; end if;
    update player_pet_inventory set quantity = quantity - qty, updated_at = now() where id = upi.id;
    return jsonb_build_object('source','ufrag','ref','universal_fragment','code',code,'stackable',true,
      'name','Universal Fragment','image',null,'rarity','epic','itemType','universal_fragment',
      'category','fragments','quantity', qty);

  elsif code like 'pfrag:%' then
    ref := substr(code, 7);
    select * into pp from player_pets where id = ref::uuid and user_id = p_user for update;
    if pp.id is null or coalesce(pp.fragments,0) < qty then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(pp.tradable, true) = false or coalesce(pp.is_season_exclusive,false) then raise exception 'ITEM_NOT_TRADABLE'; end if;
    select * into pet_row from pets where id = pp.pet_id;
    update player_pets set fragments = fragments - qty, updated_at = now() where id = pp.id;
    return jsonb_build_object('source','pet_fragment','ref', pp.pet_id::text,'code',code,'stackable',true,
      'name', coalesce(pet_row.name,'Pet') || ' Fragment', 'image', pet_row.image_baby_url,
      'rarity', coalesce(pp.rarity,'common'), 'itemType','pet_fragment','category','fragments','quantity', qty,
      'petId', pp.pet_id::text);

  elsif code like 'equip:%' then
    ref := substr(code, 7);
    if qty <> 1 then raise exception 'INVALID_QUANTITY'; end if;
    select * into pe from player_equipment where id = ref::uuid and user_id = p_user for update;
    if pe.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(pe.market_locked,false) then raise exception 'ALREADY_LISTED'; end if;
    if pe.hero_id is not null then raise exception 'EQUIPMENT_EQUIPPED'; end if;
    if coalesce(pe.locked,false) then raise exception 'ITEM_NOT_TRADABLE'; end if;
    select * into tpl from equipment_templates where id = pe.template_id;
    update player_equipment set market_locked = true, updated_at = now() where id = pe.id;
    return jsonb_build_object('source','equipment','ref', pe.id::text,'code',code,'stackable',false,
      'name', coalesce(tpl.name,'Equipment'), 'image', tpl.image_url, 'rarity', coalesce(tpl.rarity,'rare'),
      'itemType','equipment','category','equipment','quantity',1,'slot', tpl.slot, 'kind', tpl.kind);

  else
    select * into inv from player_inventory where user_id = p_user and item_code = code for update;
    if inv.id is null or coalesce(inv.quantity,0) < qty then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(inv.tradable,true) = false or coalesce(inv.is_exclusive,false) then raise exception 'ITEM_NOT_TRADABLE'; end if;
    update player_inventory set quantity = quantity - qty, updated_at = now() where id = inv.id;
    rar := coalesce((regexp_match(code, '(uncommon|common|improved|rare|special|epic|legendary|mythic|ancestral)'))[1], 'common');
    return jsonb_build_object('source','inventory','ref', code, 'code', code, 'stackable', true,
      'name', coalesce((select c.name from chest_reward_tables c where c.chest_code = code), initcap(replace(code,'_',' '))),
      'image', null, 'rarity', rar, 'itemType', inv.item_type,
      'category', case when inv.item_type = 'hero_chest' or code like '%chest%' then 'chests'
                       when inv.item_type ilike '%fragment%' then 'fragments' else 'other' end,
      'quantity', qty, 'invType', inv.item_type);
  end if;
end $fn$;

create or replace function public.market_item_give(p_user uuid, p_code text, p_snap jsonb, p_qty integer)
returns void language plpgsql security definer set search_path to 'public' as $fn$
declare
  src text := coalesce(p_snap->>'source', 'inventory'); qty integer := greatest(coalesce(p_qty,1),1);
  ref text := coalesce(p_snap->>'ref', p_code); target uuid; rows_hit integer;
begin
  if src = 'food' then
    insert into player_pet_food(user_id, food_code, quantity)
    values (p_user, ref, qty)
    on conflict (user_id, food_code) do update set quantity = player_pet_food.quantity + excluded.quantity, updated_at = now();

  elsif src = 'ufrag' then
    update player_pet_inventory set quantity = quantity + qty, updated_at = now()
     where user_id = p_user and item_type = 'universal_fragment' and item_id is null;
    if not found then
      insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (p_user, 'universal_fragment', null, qty);
    end if;

  elsif src = 'pet_fragment' then
    select id into target from player_pets
     where user_id = p_user and pet_id = ref::uuid order by created_at limit 1;
    if target is not null then
      update player_pets set fragments = coalesce(fragments,0) + qty, updated_at = now() where id = target;
    else
      -- Buyer does not own this companion: fragments convert to universal fragments.
      update player_pet_inventory set quantity = quantity + qty, updated_at = now()
       where user_id = p_user and item_type = 'universal_fragment' and item_id is null;
      if not found then
        insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (p_user, 'universal_fragment', null, qty);
      end if;
    end if;

  elsif src = 'equipment' then
    update player_equipment set user_id = p_user, market_locked = false, hero_id = null, updated_at = now()
     where id = ref::uuid;

  else
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (p_user, coalesce(p_snap->>'invType', p_snap->>'itemType', 'item'), coalesce(p_snap->>'code', p_code), qty)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;
end $fn$;

-- ---------------------------------------------------------------------------
-- TON price band: the minimum always comes from market_min_price_ton.
-- ---------------------------------------------------------------------------
create or replace function public.market_price_range(p_item_type text, p_rarity text, p_level integer default 1, p_currency text default 'FC')
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  kind text := lower(coalesce(p_item_type,'item'));
  rar text := lower(coalesce(nullif(p_rarity,''),'default'));
  cur text := case when upper(coalesce(p_currency,'FC')) = 'TON' then 'TON' else 'FC' end;
  r market_price_ranges%rowtype; dyn jsonb; med numeric; samples integer; settings jsonb := market_settings_json();
  v_min numeric; v_max numeric; v_rec numeric; v_source text := 'config'; hard_max numeric;
begin
  hard_max := case when cur = 'TON' then coalesce((settings->>'maxPriceTon')::numeric, 500)
                   else coalesce((settings->>'maxPriceFc')::numeric, 50000000) end;

  select * into r from market_price_ranges where item_type = kind and rarity = rar;
  if r.id is null then select * into r from market_price_ranges where item_type = kind and rarity = 'default'; end if;

  if cur = 'TON' then
    v_min := market_min_price_ton(kind, rar);
    v_max := coalesce(r.max_ton, hard_max);
    v_rec := coalesce(r.recommended_ton, least(greatest(v_min * 4, v_min), hard_max));
  else
    if r.id is null then
      v_min := coalesce((settings->'minPrice'->>kind)::numeric, 5000);
      v_max := hard_max;
      v_rec := v_min * 4;
    else
      v_min := r.min_fc; v_max := r.max_fc; v_rec := coalesce(r.recommended_fc, round((r.min_fc + r.max_fc) / 4));
    end if;
  end if;

  if coalesce(p_level,1) > 1 then
    v_max := v_max * least(1 + (least(p_level, 100) - 1) * 0.01, 1.5);
  end if;

  dyn := settings->'dynamicRange';
  select count(*), percentile_cont(0.5) within group (order by case when cur = 'TON' then t.price_ton else t.price_fc end)
    into samples, med
    from market_transactions t
   where t.status = 'settled'
     and coalesce(t.currency,'FC') = cur
     and t.item_type = kind
     and lower(coalesce(t.snapshot->>'rarity','default')) = rar
     and t.created_at > now() - make_interval(days => coalesce((dyn->>'days')::integer, 30));

  if med is not null and samples >= coalesce((dyn->>'minSamples')::integer, 5) then
    v_source := 'median';
    if cur = 'FC' then v_min := greatest(v_min, med * coalesce((dyn->>'minPercent')::numeric, 50) / 100); end if;
    v_max := least(v_max, med * coalesce((dyn->>'maxPercent')::numeric, 200) / 100);
    v_rec := med;
  end if;

  v_max := least(v_max, hard_max);
  -- The TON minimum is a hard rule and can never be raised or lowered by config/median.
  if cur = 'TON' then v_min := market_min_price_ton(kind, rar); end if;
  if v_max < v_min then v_max := v_min; end if;
  v_rec := least(greatest(coalesce(v_rec, v_min), v_min), v_max);

  if cur = 'TON' then
    return jsonb_build_object('min', round(v_min, 3), 'max', round(v_max, 3), 'recommended', round(v_rec, 3),
      'median', case when med is null then null else round(med, 3) end, 'samples', coalesce(samples,0),
      'source', v_source, 'itemType', kind, 'rarity', rar, 'currency', 'TON');
  end if;
  return jsonb_build_object('min', round(v_min), 'max', round(v_max), 'recommended', round(v_rec),
    'median', case when med is null then null else round(med) end, 'samples', coalesce(samples,0),
    'source', v_source, 'itemType', kind, 'rarity', rar, 'currency', 'FC');
end $fn$;

-- ---------------------------------------------------------------------------
-- Sellable inventory: real rows from every item source, никогда copies.
-- ---------------------------------------------------------------------------
create or replace function public.market_get_sellable(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
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
      market_price_range('hero', h.rarity, h.level, 'TON') as "priceRangeTon",
      market_min_price_ton('hero', h.rarity) as "minPriceTon"
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
      market_price_range('pet', p.rarity, p.level, 'TON') as "priceRangeTon",
      market_min_price_ton('pet', p.rarity) as "minPriceTon"
    from player_pets p join pets pet on pet.id = p.pet_id
    where p.user_id = u
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.available desc, t.category, t.name), '[]'::jsonb) into items
  from (
    -- chests and other stackable inventory rows
    select i.item_code as code,
      case when i.item_type = 'hero_chest' or i.item_code like '%chest%' then 'chest' else i.item_type end as "itemType",
      case when i.item_type = 'hero_chest' or i.item_code like '%chest%' then 'chests'
           when i.item_type ilike '%fragment%' then 'fragments' else 'other' end as category,
      coalesce(c.name, initcap(replace(i.item_code,'_',' '))) as name,
      null::text as image,
      coalesce((regexp_match(i.item_code, '(uncommon|common|improved|rare|special|epic|legendary|mythic|ancestral)'))[1], 'common') as rarity,
      i.quantity, true as stackable,
      (case when coalesce(i.tradable,true) = false then jsonb_build_array('not_tradable') else '[]'::jsonb end
        || case when coalesce(i.is_exclusive,false) then jsonb_build_array('exclusive') else '[]'::jsonb end) as locks,
      (coalesce(i.tradable,true) and not coalesce(i.is_exclusive,false)) as available
    from player_inventory i where i.user_id = u and i.quantity > 0
    union all
    -- pet food
    select 'food:' || pf.food_code, 'food', 'food', coalesce(f.name, initcap(replace(pf.food_code,'_',' '))),
      f.icon, coalesce(f.rarity,'common'), pf.quantity, true, '[]'::jsonb, true
    from player_pet_food pf left join pet_food_items f on f.code = pf.food_code
    where pf.user_id = u and pf.quantity > 0
    union all
    -- universal fragments
    select 'ufrag', 'universal_fragment', 'fragments', 'Universal Fragment', null, 'epic', pi.quantity, true, '[]'::jsonb, true
    from player_pet_inventory pi
    where pi.user_id = u and pi.item_type = 'universal_fragment' and pi.item_id is null and pi.quantity > 0
    union all
    -- pet-specific fragments
    select 'pfrag:' || pp.id::text, 'pet_fragment', 'fragments', p.name || ' Fragment', p.image_baby_url,
      coalesce(pp.rarity,'common'), pp.fragments, true,
      (case when coalesce(pp.tradable,true) = false or coalesce(pp.is_season_exclusive,false)
            then jsonb_build_array('not_tradable') else '[]'::jsonb end),
      (coalesce(pp.tradable,true) and not coalesce(pp.is_season_exclusive,false))
    from player_pets pp join pets p on p.id = pp.pet_id
    where pp.user_id = u and coalesce(pp.fragments,0) > 0
    union all
    -- equipment instances
    select 'equip:' || pe.id::text, 'equipment', 'equipment', coalesce(tpl.name,'Equipment'), tpl.image_url,
      coalesce(tpl.rarity,'rare'), 1, false,
      (case when coalesce(pe.market_locked,false) then jsonb_build_array('listed') else '[]'::jsonb end
        || case when pe.hero_id is not null then jsonb_build_array('equipped') else '[]'::jsonb end
        || case when coalesce(pe.locked,false) then jsonb_build_array('not_tradable') else '[]'::jsonb end),
      (not coalesce(pe.market_locked,false) and pe.hero_id is null and not coalesce(pe.locked,false))
    from player_equipment pe join equipment_templates tpl on tpl.id = pe.template_id
    where pe.user_id = u
  ) t;

  items := (
    select coalesce(jsonb_agg(e || jsonb_build_object(
      'priceRange', market_price_range('item','default',1,'FC'),
      'priceRangeTon', market_price_range('item','default',1,'TON'),
      'minPriceTon', market_min_price_ton('item', e->>'rarity')
    )), '[]'::jsonb)
    from jsonb_array_elements(items) as e
  );

  return jsonb_build_object('heroes', heroes, 'pets', pets, 'items', items,
    'balanceFc', coalesce(g.forge_coins,0),
    'availableTon', greatest(coalesce(g.ton_balance,0) - coalesce(g.ton_reserved,0), 0),
    'settings', market_settings_json(), 'eligibility', market_sell_eligibility(u),
    'status', market_status(p_telegram_id));
end $fn$;

-- ---------------------------------------------------------------------------
-- Listing creation: quantity aware + hard TON minimum.
-- ---------------------------------------------------------------------------
create or replace function public.market_create_listing(
  p_telegram_id bigint, p_item_type text, p_item_instance_id uuid, p_item_code text,
  p_price_fc numeric default null, p_currency text default 'FC', p_price_ton numeric default null,
  p_quantity integer default 1)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  u uuid; settings jsonb; fee numeric; max_active integer; elig jsonb; range jsonb;
  active_count integer; snap jsonb; listing_id uuid; kind text := lower(coalesce(p_item_type,''));
  cur text := case when upper(coalesce(p_currency,'FC')) = 'TON' then 'TON' else 'FC' end;
  h player_heroes%rowtype; pp player_pets%rowtype; pet_row pets%rowtype;
  rar text := 'default'; lvl integer := 1; price numeric; risk text := 'low'; sell_today numeric;
  g game_players%rowtype; nal jsonb; is_admin boolean; currencies jsonb;
  qty integer := greatest(coalesce(p_quantity,1),1); min_ton numeric;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  if kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  if kind in ('hero','pet') and qty <> 1 then raise exception 'INVALID_QUANTITY'; end if;
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
    rar := 'default'; lvl := 1;
  end if;

  -- Hard minimum (backend authority): 4 TON for legendary+ heroes, 0.10 TON otherwise.
  if cur = 'TON' then
    min_ton := market_min_price_ton(kind, rar);
    if price < min_ton then
      if min_ton > 1 then raise exception 'PRICE_BELOW_MINIMUM_LEGENDARY';
      else raise exception 'PRICE_BELOW_MINIMUM'; end if;
    end if;
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
    -- Removes EXACTLY the listed quantity from the real inventory source.
    snap := market_item_take(u, p_item_code, qty);
    if not coalesce((snap->>'stackable')::boolean, true) and qty <> 1 then raise exception 'INVALID_QUANTITY'; end if;
  end if;

  if price >= (range->>'max')::numeric * 0.95 and market_account_days(u) < 14 and not is_admin then risk := 'high';
  elsif price >= (range->>'max')::numeric * 0.9 then risk := 'medium';
  end if;

  insert into market_listings(seller_user_id, item_type, item_instance_id, item_code, currency, price_fc, price_ton, fee_percent, snapshot, risk_level, quantity)
  values (u, kind, case when kind = 'item' then null else p_item_instance_id end,
          case when kind = 'item' then lower(p_item_code) else null end, cur,
          case when cur = 'FC' then price else null end,
          case when cur = 'TON' then price else null end, fee,
          snap || jsonb_build_object('seller', market_seller_label(u), 'quantity', qty), risk, qty)
  returning id into listing_id;

  insert into market_security_audit(event, listing_id, seller_user_id, currency, price_fc, fee_fc, price_ton, fee_ton, details)
  values ('listing_created', listing_id, u, cur,
          case when cur = 'FC' then price else null end,
          case when cur = 'FC' then round(price * fee / 100) else null end,
          case when cur = 'TON' then price else null end,
          case when cur = 'TON' then round(price * fee / 100, 3) else null end,
          jsonb_build_object('range', range, 'riskLevel', risk, 'currency', cur, 'price', price, 'quantity', qty));

  return jsonb_build_object('ok', true, 'listingId', listing_id, 'feePercent', fee, 'range', range,
    'currency', cur, 'price', price, 'quantity', qty,
    'settlementHours', case when cur = 'TON' then (settings->>'settlementHoursTon')::integer else (settings->>'settlementHours')::integer end,
    'sellerReceives', case when cur = 'TON' then round(price - price * fee / 100, 3) else price - round(price * fee / 100) end);
end $fn$;

-- ---------------------------------------------------------------------------
-- Cancel: gives back exactly the reserved quantity to the original source.
-- ---------------------------------------------------------------------------
create or replace function public.market_cancel_listing(p_telegram_id bigint, p_listing_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare u uuid; l market_listings%rowtype;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null or l.seller_user_id <> u then raise exception 'LISTING_NOT_FOUND'; end if;
  if l.status = 'reserved' and coalesce(l.reserved_until, now()) > now() then raise exception 'ITEM_RESERVED'; end if;
  if l.status <> 'active' and l.status <> 'reserved' then raise exception 'ITEM_NO_LONGER_AVAILABLE'; end if;

  if l.item_type = 'hero' then
    update player_heroes set market_locked = false, updated_at = now() where id = l.item_instance_id and user_id = u;
  elsif l.item_type = 'pet' then
    update player_pets set market_locked = false, updated_at = now() where id = l.item_instance_id and user_id = u;
  else
    perform market_item_give(u, l.item_code, l.snapshot, l.quantity);
  end if;

  update market_listings set status = 'cancelled', cancelled_at = now(), reserved_for = null,
    reserved_until = null, updated_at = now() where id = l.id;

  update market_payment_intents set status = 'cancelled', updated_at = now()
   where listing_id = l.id and status = 'pending';

  return jsonb_build_object('ok', true);
end $fn$;

-- ---------------------------------------------------------------------------
-- My listings: expose the listed quantity.
-- ---------------------------------------------------------------------------
create or replace function public.market_my_listings(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare u uuid; pending numeric := 0; pending_ton numeric := 0;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select id, market_pending_fc, coalesce(market_pending_ton,0) into u, pending, pending_ton
    from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object(
    'listings', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'itemType', l.item_type, 'name', coalesce(l.snapshot->>'name','Item'),
        'rarity', lower(coalesce(l.snapshot->>'rarity','common')), 'level', coalesce((l.snapshot->>'level')::integer,1),
        'image', l.snapshot->>'image', 'priceFc', l.price_fc, 'priceTon', l.price_ton,
        'currency', coalesce(l.currency,'FC'), 'status', l.status, 'quantity', coalesce(l.quantity,1),
        'itemCode', l.item_code, 'category', l.snapshot->>'category',
        'createdAt', l.created_at, 'soldAt', l.sold_at, 'cancelledAt', l.cancelled_at,
        'feePercent', l.fee_percent) order by l.created_at desc), '[]'::jsonb)
      from market_listings l where l.seller_user_id = u),
    'purchases', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'itemType', t.item_type, 'name', coalesce(t.snapshot->>'name','Item'),
        'rarity', lower(coalesce(t.snapshot->>'rarity','common')),
        'image', t.snapshot->>'image', 'priceFc', t.price_fc, 'priceTon', t.price_ton,
        'currency', coalesce(t.currency,'FC'), 'quantity', coalesce((t.snapshot->>'quantity')::integer,1),
        'seller', market_seller_label(t.seller_user_id), 'createdAt', t.created_at) order by t.created_at desc), '[]'::jsonb)
      from market_transactions t where t.buyer_user_id = u),
    'pendingFc', pending, 'pendingTon', pending_ton,
    'settings', market_settings_json());
end $fn$;
