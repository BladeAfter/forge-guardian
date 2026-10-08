-- ============ MARKETPLACE (FC ONLY) ============

alter table public.player_heroes add column if not exists market_locked boolean not null default false;
alter table public.player_pets add column if not exists market_locked boolean not null default false;

create table if not exists public.market_listings (
  id uuid primary key default gen_random_uuid(),
  seller_user_id uuid not null references public.game_players(id) on delete cascade,
  item_type text not null check (item_type in ('hero','pet','item')),
  item_instance_id uuid,
  item_code text,
  quantity integer not null default 1 check (quantity > 0),
  price_fc numeric not null check (price_fc > 0),
  fee_percent numeric not null default 5 check (fee_percent >= 0 and fee_percent <= 50),
  status text not null default 'active' check (status in ('active','sold','cancelled')),
  buyer_user_id uuid references public.game_players(id) on delete set null,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sold_at timestamptz,
  cancelled_at timestamptz
);

GRANT SELECT (id, item_type, item_code, quantity, price_fc, fee_percent, status, snapshot, created_at, sold_at, cancelled_at) ON public.market_listings TO anon, authenticated;
GRANT ALL ON public.market_listings TO service_role;
ALTER TABLE public.market_listings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read market listings" ON public.market_listings FOR SELECT TO anon, authenticated USING (true);

create unique index if not exists market_listings_active_instance_idx
  on public.market_listings(item_type, item_instance_id) where status = 'active' and item_instance_id is not null;
create index if not exists market_listings_status_idx on public.market_listings(status, created_at desc);
create index if not exists market_listings_seller_idx on public.market_listings(seller_user_id, status);

create table if not exists public.market_transactions (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.market_listings(id) on delete cascade,
  seller_user_id uuid not null references public.game_players(id) on delete cascade,
  buyer_user_id uuid not null references public.game_players(id) on delete cascade,
  item_type text not null,
  item_instance_id uuid,
  item_code text,
  price_fc numeric not null,
  fee_percent numeric not null,
  fee_fc numeric not null,
  seller_received_fc numeric not null,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
GRANT ALL ON public.market_transactions TO service_role;
ALTER TABLE public.market_transactions ENABLE ROW LEVEL SECURITY;

drop trigger if exists market_listings_touch on public.market_listings;
create trigger market_listings_touch before update on public.market_listings
  for each row execute function public.update_updated_at_column();

-- Default, admin-tunable settings
insert into public.game_settings(key, value, category, label) values
  ('market_fee_percent', '5'::jsonb, 'marketplace', 'Taxa do mercado (%)'),
  ('market_max_active_listings', '20'::jsonb, 'marketplace', 'Anúncios ativos por jogador'),
  ('market_max_price_fc', '50000000'::jsonb, 'marketplace', 'Preço máximo por anúncio (FC)'),
  ('market_min_price', '{"hero":10000,"pet":10000,"item":5000}'::jsonb, 'marketplace', 'Preços mínimos (FC)')
on conflict (key) do nothing;

-- ============ HELPERS ============

create or replace function public.market_settings_json()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'feePercent', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_fee_percent'), 5),
    'maxActiveListings', coalesce((select (value #>> '{}')::integer from game_settings where key = 'market_max_active_listings'), 20),
    'maxPriceFc', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_max_price_fc'), 50000000),
    'minPrice', coalesce((select value from game_settings where key = 'market_min_price'), '{"hero":10000,"pet":10000,"item":5000}'::jsonb)
  );
$$;

create or replace function public.market_seller_label(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    case when nullif(g.username,'') is not null then '@' || g.username end,
    nullif(g.display_name,''),
    nullif(trim(coalesce(g.first_name,'') || ' ' || coalesce(g.last_name,'')),''),
    'Player'
  ) from game_players g where g.id = p_user;
$$;

/** Locked items can never be used, equipped, activated, fused or deleted. */
create or replace function public.market_block_locked_hero()
returns trigger language plpgsql security definer set search_path = public as $$
declare locked boolean;
begin
  select market_locked into locked from player_heroes
   where id = coalesce(new.hero_id, new.player_hero_id, old.hero_id, old.player_hero_id);
  if locked then raise exception 'HERO_LISTED_IN_MARKET'; end if;
  return new;
end $$;

create or replace function public.market_block_hero_mutation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.market_locked then raise exception 'HERO_LISTED_IN_MARKET'; end if;
    return old;
  end if;
  -- Only the marketplace itself may move a locked hero (it clears the flag in the same statement).
  if old.market_locked and new.market_locked and old.user_id is distinct from new.user_id then
    raise exception 'HERO_LISTED_IN_MARKET';
  end if;
  return new;
end $$;

drop trigger if exists market_guard_pvp_slots on public.pvp_team_slots;
create trigger market_guard_pvp_slots before insert or update on public.pvp_team_slots
  for each row execute function public.market_block_locked_hero();

drop trigger if exists market_guard_boss_slots on public.boss_team_slots;
create trigger market_guard_boss_slots before insert or update on public.boss_team_slots
  for each row execute function public.market_block_locked_hero();

drop trigger if exists market_guard_hero_mutation on public.player_heroes;
create trigger market_guard_hero_mutation before update or delete on public.player_heroes
  for each row execute function public.market_block_hero_mutation();

create or replace function public.market_block_pet_mutation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.market_locked then raise exception 'PET_LISTED_IN_MARKET'; end if;
    return old;
  end if;
  if old.market_locked and new.market_locked then
    if new.is_active then raise exception 'PET_LISTED_IN_MARKET'; end if;
    if new.level is distinct from old.level or new.xp is distinct from old.xp
       or new.evolution_stage is distinct from old.evolution_stage
       or new.user_id is distinct from old.user_id then
      raise exception 'PET_LISTED_IN_MARKET';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists market_guard_pet_mutation on public.player_pets;
create trigger market_guard_pet_mutation before update or delete on public.player_pets
  for each row execute function public.market_block_pet_mutation();

-- ============ PLAYER FUNCTIONS ============

/** Everything the player is allowed to list right now (server decides eligibility). */
create or replace function public.market_get_sellable(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid; heroes jsonb; pets jsonb; items jsonb;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', h.id, 'name', h.name, 'rarity', h.rarity, 'level', h.level, 'image', h.image,
    'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0))
  ) order by h.created_at desc), '[]'::jsonb) into heroes
  from player_heroes h
  where h.user_id = u and not h.market_locked and coalesce(h.locked,false) = false
    and coalesce(h.tradable, true) = true
    and not exists (select 1 from pvp_team_slots s where s.player_hero_id = h.id)
    and not exists (select 1 from boss_team_slots b where b.hero_id = h.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', pet.name, 'rarity', p.rarity, 'level', p.level,
    'image', coalesce(pet.image_adult_url, pet.image_young_url, pet.image_baby_url),
    'evolution', p.evolution_stage, 'tier', coalesce(p.evolution_tier,0)
  ) order by p.created_at desc), '[]'::jsonb) into pets
  from player_pets p join pets pet on pet.id = p.pet_id
  where p.user_id = u and not p.market_locked and not coalesce(p.is_active,false)
    and coalesce(p.tradable, true) = true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code', i.item_code, 'itemType', i.item_type, 'quantity', i.quantity
  ) order by i.item_code), '[]'::jsonb) into items
  from player_inventory i
  where i.user_id = u and i.quantity > 0 and coalesce(i.tradable, true) = true
    and i.item_type not in ('fragments');

  return jsonb_build_object('heroes', heroes, 'pets', pets, 'items', items, 'settings', market_settings_json());
end $$;

create or replace function public.market_create_listing(
  p_telegram_id bigint, p_item_type text, p_item_instance_id uuid, p_item_code text, p_price_fc numeric
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  u uuid; settings jsonb; fee numeric; min_price numeric; max_price numeric; max_active integer;
  active_count integer; snap jsonb; listing_id uuid; kind text := lower(coalesce(p_item_type,''));
  h player_heroes%rowtype; pp player_pets%rowtype; inv player_inventory%rowtype; pet_row pets%rowtype;
begin
  if kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  select id into u from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  settings := market_settings_json();
  fee := (settings->>'feePercent')::numeric;
  max_price := (settings->>'maxPriceFc')::numeric;
  max_active := (settings->>'maxActiveListings')::integer;
  min_price := coalesce((settings->'minPrice'->>kind)::numeric, 5000);

  if p_price_fc is null or p_price_fc <> trunc(p_price_fc) or p_price_fc <= 0 then raise exception 'INVALID_PRICE'; end if;
  if p_price_fc < min_price then raise exception 'PRICE_BELOW_MINIMUM'; end if;
  if p_price_fc > max_price then raise exception 'PRICE_ABOVE_MAXIMUM'; end if;

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
    update player_heroes set market_locked = true, updated_at = now() where id = h.id;
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
    update player_pets set market_locked = true, updated_at = now() where id = pp.id;
    snap := jsonb_build_object('name', coalesce(pet_row.name,'Pet'), 'rarity', pp.rarity, 'level', pp.level,
      'image', coalesce(pet_row.image_adult_url, pet_row.image_young_url, pet_row.image_baby_url),
      'evolution', pp.evolution_stage, 'tier', coalesce(pp.evolution_tier,0));
  else
    if p_item_code is null or length(p_item_code) < 2 then raise exception 'INVALID_ITEM'; end if;
    select * into inv from player_inventory where user_id = u and item_code = p_item_code for update;
    if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(inv.tradable,true) = false then raise exception 'ITEM_NOT_TRADABLE'; end if;
    if inv.item_type = 'fragments' then raise exception 'ITEM_NOT_TRADABLE'; end if;
    -- The unit is moved into escrow so it cannot be used or sold twice while listed.
    update player_inventory set quantity = quantity - 1, updated_at = now() where id = inv.id;
    snap := jsonb_build_object('name', initcap(replace(inv.item_code,'_',' ')), 'rarity', 'rare', 'level', 1,
      'itemType', inv.item_type, 'code', inv.item_code);
  end if;

  insert into market_listings(seller_user_id, item_type, item_instance_id, item_code, price_fc, fee_percent, snapshot)
  values (u, kind, case when kind = 'item' then null else p_item_instance_id end,
          case when kind = 'item' then p_item_code else null end, trunc(p_price_fc), fee,
          snap || jsonb_build_object('seller', market_seller_label(u)))
  returning id into listing_id;

  return jsonb_build_object('ok', true, 'listingId', listing_id, 'feePercent', fee,
    'sellerReceives', trunc(p_price_fc) - round(trunc(p_price_fc) * fee / 100));
end $$;

create or replace function public.market_cancel_listing(p_telegram_id bigint, p_listing_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; l market_listings%rowtype;
begin
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
  return jsonb_build_object('ok', true);
end $$;

/** Atomic purchase. Transfers existing FC only: the fee is burned, never minted. */
create or replace function public.market_buy_listing(p_telegram_id bigint, p_listing_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  buyer uuid; buyer_before numeric; buyer_after numeric; seller_before numeric; seller_after numeric;
  l market_listings%rowtype; fee_fc numeric; received numeric;
begin
  select id, forge_coins into buyer, buyer_before from game_players where telegram_id = p_telegram_id for update;
  if buyer is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  if l.status <> 'active' then raise exception 'ITEM_NO_LONGER_AVAILABLE'; end if;
  if l.seller_user_id = buyer then raise exception 'CANNOT_BUY_OWN_LISTING'; end if;
  if buyer_before < l.price_fc then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;

  fee_fc := round(l.price_fc * l.fee_percent / 100);
  received := l.price_fc - fee_fc;

  update game_players set forge_coins = forge_coins - l.price_fc, updated_at = now()
    where id = buyer returning forge_coins into buyer_after;
  select forge_coins into seller_before from game_players where id = l.seller_user_id for update;
  update game_players set forge_coins = forge_coins + received, updated_at = now()
    where id = l.seller_user_id returning forge_coins into seller_after;

  if l.item_type = 'hero' then
    delete from pvp_team_slots where player_hero_id = l.item_instance_id;
    delete from boss_team_slots where hero_id = l.item_instance_id;
    update player_heroes set user_id = buyer, market_locked = false, updated_at = now() where id = l.item_instance_id;
  elsif l.item_type = 'pet' then
    update player_pets set market_locked = false where id = l.item_instance_id;
    update player_pets set user_id = buyer, is_active = false, updated_at = now() where id = l.item_instance_id;
  else
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (buyer, coalesce(l.snapshot->>'itemType','item'), l.item_code, l.quantity)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  update market_listings set status = 'sold', buyer_user_id = buyer, sold_at = now() where id = l.id;

  insert into market_transactions(listing_id, seller_user_id, buyer_user_id, item_type, item_instance_id, item_code,
    price_fc, fee_percent, fee_fc, seller_received_fc, snapshot)
  values (l.id, l.seller_user_id, buyer, l.item_type, l.item_instance_id, l.item_code,
    l.price_fc, l.fee_percent, fee_fc, received, l.snapshot);

  insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
  values (buyer, 'market_purchase', -l.price_fc, buyer_before, buyer_after, l.id::text),
         (l.seller_user_id, 'market_sale', received, seller_before, seller_after, l.id::text);

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (l.seller_user_id, 'market_sale', 'MARKET',
    coalesce(l.snapshot->>'name','Item') || ' vendido por ' || l.price_fc::bigint || ' FC',
    received, jsonb_build_object('listingId', l.id, 'feeFc', fee_fc), 'market_sale:' || l.id::text);

  return jsonb_build_object('ok', true, 'pricePaid', l.price_fc, 'feeFc', fee_fc,
    'sellerReceived', received, 'balanceFc', buyer_after, 'itemType', l.item_type,
    'name', l.snapshot->>'name');
end $$;

create or replace function public.market_browse(
  p_telegram_id bigint, p_item_type text default 'all', p_rarity text default 'all',
  p_sort text default 'newest', p_limit integer default 60, p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid; balance numeric := 0; rows_json jsonb; lim integer := least(greatest(coalesce(p_limit,60),1),100);
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id;
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
      and (coalesce(p_item_type,'all') = 'all' or l.item_type = p_item_type)
      and (coalesce(p_rarity,'all') = 'all' or lower(coalesce(l.snapshot->>'rarity','common')) = lower(p_rarity))
    order by
      case when p_sort = 'price_low' then l.price_fc end asc nulls last,
      case when p_sort = 'price_high' then l.price_fc end desc nulls last,
      l.created_at desc
    limit lim offset greatest(coalesce(p_offset,0),0)
  ) q;

  return jsonb_build_object('listings', rows_json, 'balanceFc', coalesce(balance,0),
    'settings', market_settings_json(),
    'activeCount', (select count(*) from market_listings where seller_user_id = u and status = 'active'));
end $$;

create or replace function public.market_my_listings(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
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
        'seller', market_seller_label(t.seller_user_id)
      ) order by t.created_at desc), '[]'::jsonb) from market_transactions t where t.buyer_user_id = u),
    'settings', market_settings_json()
  );
end $$;

-- ============ ADMIN FUNCTIONS ============

create or replace function public.admin_market_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert(p_admin_id);
  return jsonb_build_object(
    'settings', market_settings_json(),
    'active', (select count(*) from market_listings where status = 'active'),
    'sold', (select count(*) from market_listings where status = 'sold'),
    'cancelled', (select count(*) from market_listings where status = 'cancelled'),
    'volumeFc', (select coalesce(sum(price_fc),0) from market_transactions),
    'burnedFc', (select coalesce(sum(fee_fc),0) from market_transactions)
  );
end $$;

create or replace function public.admin_market_listings(p_admin_id bigint, p_status text default 'active', p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert(p_admin_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'itemType', l.item_type, 'name', coalesce(l.snapshot->>'name','Item'),
      'rarity', l.snapshot->>'rarity', 'priceFc', l.price_fc, 'status', l.status,
      'seller', market_seller_label(l.seller_user_id), 'buyer', market_seller_label(l.buyer_user_id),
      'createdAt', l.created_at
    ) order by l.created_at desc), '[]'::jsonb)
    from (select * from market_listings
          where (coalesce(p_status,'active') = 'all' or status = p_status)
          order by created_at desc limit least(greatest(coalesce(p_limit,20),1),50)) l);
end $$;

create or replace function public.admin_market_search(p_admin_id bigint, p_query text, p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert(p_admin_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'itemType', l.item_type, 'name', coalesce(l.snapshot->>'name','Item'),
      'priceFc', l.price_fc, 'status', l.status, 'seller', market_seller_label(l.seller_user_id),
      'createdAt', l.created_at) order by l.created_at desc), '[]'::jsonb)
    from (select * from market_listings
          where coalesce(snapshot->>'name','') ilike '%' || coalesce(p_query,'') || '%'
             or id::text = coalesce(p_query,'')
          order by created_at desc limit least(greatest(coalesce(p_limit,20),1),50)) l);
end $$;

create or replace function public.admin_market_user_listings(p_admin_id bigint, p_ref text, p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare target jsonb; u uuid;
begin
  perform admin_assert(p_admin_id);
  target := admin_resolve_player(p_ref);
  u := (target->>'id')::uuid;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object('player', target, 'listings', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'itemType', l.item_type, 'name', coalesce(l.snapshot->>'name','Item'),
      'priceFc', l.price_fc, 'status', l.status, 'createdAt', l.created_at) order by l.created_at desc), '[]'::jsonb)
    from (select * from market_listings where seller_user_id = u order by created_at desc
          limit least(greatest(coalesce(p_limit,20),1),50)) l));
end $$;

create or replace function public.admin_market_audit(p_admin_id bigint, p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert(p_admin_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'itemType', t.item_type, 'name', coalesce(t.snapshot->>'name','Item'),
      'priceFc', t.price_fc, 'feeFc', t.fee_fc, 'received', t.seller_received_fc,
      'seller', market_seller_label(t.seller_user_id), 'buyer', market_seller_label(t.buyer_user_id),
      'createdAt', t.created_at) order by t.created_at desc), '[]'::jsonb)
    from (select * from market_transactions order by created_at desc
          limit least(greatest(coalesce(p_limit,20),1),50)) t);
end $$;

create or replace function public.admin_market_set_fee(p_admin_id bigint, p_percent numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare old_value numeric;
begin
  perform admin_assert(p_admin_id);
  if p_percent is null or p_percent < 0 or p_percent > 50 then raise exception 'INVALID_FEE_PERCENT'; end if;
  select (value #>> '{}')::numeric into old_value from game_settings where key = 'market_fee_percent';
  insert into game_settings(key, value, category, label, updated_by)
  values ('market_fee_percent', to_jsonb(round(p_percent,2)), 'marketplace', 'Taxa do mercado (%)', p_admin_id)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = p_admin_id;
  perform admin_log(p_admin_id, 'market_set_fee', 'market', 'market_fee_percent',
    to_jsonb(old_value), to_jsonb(round(p_percent,2)), null, '{}'::jsonb);
  return market_settings_json();
end $$;

create or replace function public.admin_market_set_min_price(p_admin_id bigint, p_item_type text, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare current_value jsonb; kind text := lower(coalesce(p_item_type,''));
begin
  perform admin_assert(p_admin_id);
  if kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  if p_value is null or p_value < 0 then raise exception 'INVALID_PRICE'; end if;
  select coalesce(value, '{}'::jsonb) into current_value from game_settings where key = 'market_min_price';
  current_value := coalesce(current_value, '{}'::jsonb) || jsonb_build_object(kind, trunc(p_value));
  insert into game_settings(key, value, category, label, updated_by)
  values ('market_min_price', current_value, 'marketplace', 'Preços mínimos (FC)', p_admin_id)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = p_admin_id;
  perform admin_log(p_admin_id, 'market_set_min_price', 'market', kind, null, current_value, null, '{}'::jsonb);
  return market_settings_json();
end $$;

create or replace function public.admin_market_set_limit(p_admin_id bigint, p_max_active integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert(p_admin_id);
  if p_max_active is null or p_max_active < 1 or p_max_active > 200 then raise exception 'INVALID_LIMIT'; end if;
  insert into game_settings(key, value, category, label, updated_by)
  values ('market_max_active_listings', to_jsonb(p_max_active), 'marketplace', 'Anúncios ativos por jogador', p_admin_id)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = p_admin_id;
  perform admin_log(p_admin_id, 'market_set_limit', 'market', 'market_max_active_listings', null, to_jsonb(p_max_active), null, '{}'::jsonb);
  return market_settings_json();
end $$;

create or replace function public.admin_market_cancel_listing(p_admin_id bigint, p_listing_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l market_listings%rowtype; owner_tg bigint;
begin
  perform admin_assert(p_admin_id);
  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  if l.status <> 'active' then raise exception 'LISTING_NOT_ACTIVE'; end if;
  select telegram_id into owner_tg from game_players where id = l.seller_user_id;
  perform market_cancel_listing(owner_tg, l.id);
  perform admin_log(p_admin_id, 'market_cancel_listing', 'market_listing', l.id::text, to_jsonb(l.status), to_jsonb('cancelled'::text), p_reason, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

-- Marketplace RPCs run through the service role only.
revoke all on function public.market_settings_json() from public, anon, authenticated;
revoke all on function public.market_seller_label(uuid) from public, anon, authenticated;
revoke all on function public.market_get_sellable(bigint) from public, anon, authenticated;
revoke all on function public.market_create_listing(bigint, text, uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.market_cancel_listing(bigint, uuid) from public, anon, authenticated;
revoke all on function public.market_buy_listing(bigint, uuid) from public, anon, authenticated;
revoke all on function public.market_browse(bigint, text, text, text, integer, integer) from public, anon, authenticated;
revoke all on function public.market_my_listings(bigint) from public, anon, authenticated;
revoke all on function public.admin_market_overview(bigint) from public, anon, authenticated;
revoke all on function public.admin_market_listings(bigint, text, integer) from public, anon, authenticated;
revoke all on function public.admin_market_search(bigint, text, integer) from public, anon, authenticated;
revoke all on function public.admin_market_user_listings(bigint, text, integer) from public, anon, authenticated;
revoke all on function public.admin_market_audit(bigint, integer) from public, anon, authenticated;
revoke all on function public.admin_market_set_fee(bigint, numeric) from public, anon, authenticated;
revoke all on function public.admin_market_set_min_price(bigint, text, numeric) from public, anon, authenticated;
revoke all on function public.admin_market_set_limit(bigint, integer) from public, anon, authenticated;
revoke all on function public.admin_market_cancel_listing(bigint, uuid, text) from public, anon, authenticated;

alter publication supabase_realtime add table public.market_listings;
