create table if not exists public.auctions (
  id uuid primary key default gen_random_uuid(),
  seller_user_id uuid not null references public.game_players(id) on delete cascade,
  item_type text not null check (item_type in ('hero','pet','equipment')),
  item_instance_id uuid not null,
  snapshot jsonb not null default '{}'::jsonb,
  starting_bid_ton numeric(20,9) not null check (starting_bid_ton > 0),
  current_bid_ton numeric(20,9),
  min_increment_ton numeric(20,9) not null default 0.1,
  bid_count integer not null default 0,
  highest_bidder_id uuid references public.game_players(id) on delete set null,
  fee_percent numeric(6,3) not null default 5,
  status text not null default 'active' check (status in ('active','sold','expired','cancelled')),
  ends_at timestamptz not null,
  final_price_ton numeric(20,9),
  fee_ton numeric(20,9),
  seller_net_ton numeric(20,9),
  winner_user_id uuid references public.game_players(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz
);
create unique index if not exists auctions_active_instance_idx
  on public.auctions(item_type, item_instance_id) where status = 'active';
create index if not exists auctions_status_ends_idx on public.auctions(status, ends_at);
create index if not exists auctions_seller_idx on public.auctions(seller_user_id, status);

create table if not exists public.auction_bids (
  id uuid primary key default gen_random_uuid(),
  auction_id uuid not null references public.auctions(id) on delete cascade,
  bidder_user_id uuid not null references public.game_players(id) on delete cascade,
  amount_ton numeric(20,9) not null check (amount_ton > 0),
  status text not null default 'highest' check (status in ('highest','outbid','won','refunded')),
  idempotency_key text unique,
  created_at timestamptz not null default now()
);
create index if not exists auction_bids_auction_idx on public.auction_bids(auction_id, created_at desc);
create index if not exists auction_bids_bidder_idx on public.auction_bids(bidder_user_id, created_at desc);

create table if not exists public.auction_ledger (
  id uuid primary key default gen_random_uuid(),
  event text not null,
  auction_id uuid references public.auctions(id) on delete set null,
  bid_id uuid references public.auction_bids(id) on delete set null,
  user_id uuid references public.game_players(id) on delete set null,
  counterparty_user_id uuid references public.game_players(id) on delete set null,
  gross_ton numeric(20,9),
  fee_ton numeric(20,9),
  net_ton numeric(20,9),
  balance_before numeric(20,9),
  balance_after numeric(20,9),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists auction_ledger_auction_idx on public.auction_ledger(auction_id, created_at desc);

grant all on public.auctions to service_role;
grant all on public.auction_bids to service_role;
grant all on public.auction_ledger to service_role;
alter table public.auctions enable row level security;
alter table public.auction_bids enable row level security;
alter table public.auction_ledger enable row level security;

create or replace function public.auction_settings_json()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'enabled', coalesce((v->>'enabled')::boolean, true),
    'feePercent', least(10, greatest(5, coalesce((v->>'feePercent')::numeric, 5))),
    'minStartingBidTon', greatest(0.01, coalesce((v->>'minStartingBidTon')::numeric, 0.1)),
    'minIncrementTon', greatest(0.001, coalesce((v->>'minIncrementTon')::numeric, 0.1)),
    'antiSnipeEnabled', coalesce((v->>'antiSnipeEnabled')::boolean, true),
    'antiSnipeWindowMinutes', greatest(0, coalesce((v->>'antiSnipeWindowMinutes')::numeric, 2)),
    'antiSnipeExtensionMinutes', greatest(0, coalesce((v->>'antiSnipeExtensionMinutes')::numeric, 2)),
    'durations', coalesce(v->'durations', '[6,12,24,48,72]'::jsonb),
    'currency', 'TON'
  ) from (select coalesce((select value from game_settings where key = 'auction'), '{}'::jsonb) as v) s;
$$;

create or replace function public.auction_can_access(p_telegram_id bigint)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((auction_settings_json()->>'enabled')::boolean, true)
      or market_is_bypass_admin(p_telegram_id);
$$;

create or replace function public.auction_only_item(p_item_type text, p_rarity text)
returns boolean language sql immutable set search_path to 'public' as $$
  select lower(coalesce(p_rarity,'')) in ('nft_exclusive','divine','celestial')
      or (lower(coalesce(p_item_type,'')) = 'hero'
          and lower(coalesce(p_rarity,'')) in ('legendary','mythic','ancestral'));
$$;

create or replace function public.auction_ton_move(p_user uuid, p_amount numeric, p_event text,
  p_auction uuid, p_bid uuid, p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path to 'public' as $$
declare before_bal numeric; after_bal numeric;
begin
  select coalesce(ton_balance,0) into before_bal from game_players where id = p_user for update;
  if before_bal is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if p_amount > 0 and before_bal < p_amount then raise exception 'INSUFFICIENT_TON_BALANCE'; end if;
  update game_players
     set ton_balance = coalesce(ton_balance,0) - p_amount,
         ton_reserved = greatest(0, coalesce(ton_reserved,0) + p_amount)
   where id = p_user
   returning coalesce(ton_balance,0) into after_bal;
  insert into auction_ledger(event, auction_id, bid_id, user_id, gross_ton, balance_before, balance_after, details)
  values (p_event, p_auction, p_bid, p_user, abs(p_amount), before_bal, after_bal, coalesce(p_details,'{}'::jsonb));
end $$;

create or replace function public.auction_item_snapshot(p_user uuid, p_item_type text, p_instance uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare h player_heroes%rowtype; pp player_pets%rowtype; pet_row pets%rowtype;
        pe player_equipment%rowtype; tpl equipment_templates%rowtype; nft nft_equipment%rowtype;
        kind text := lower(coalesce(p_item_type,''));
begin
  if kind = 'hero' then
    select * into h from player_heroes where id = p_instance and user_id = p_user for update;
    if h.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(h.market_locked,false) then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(h.locked,false) then raise exception 'HERO_LOCKED'; end if;
    if coalesce(h.tradable,true) = false then raise exception 'HERO_NOT_TRADABLE'; end if;
    if exists (select 1 from pvp_team_slots s where s.hero_id = h.id) then raise exception 'HERO_IN_PVP_TEAM'; end if;
    if exists (select 1 from boss_team_slots b where b.player_hero_id = h.id) then raise exception 'HERO_IN_BOSS_TEAM'; end if;
    if not auction_only_item('hero', h.rarity) then raise exception 'NOT_AUCTION_ITEM'; end if;
    return jsonb_build_object('name', h.name, 'rarity', lower(coalesce(h.rarity,'')), 'level', coalesce(h.level,1),
      'image', h.image, 'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)),
      'hp', round(coalesce(h.final_hp,0)), 'serial', h.nft_serial,
      'dailyYield', coalesce(hero_mining_rate(h.rarity),0), 'heroKey', h.hero_key);
  elsif kind = 'pet' then
    select * into pp from player_pets where id = p_instance and user_id = p_user for update;
    if pp.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(pp.market_locked,false) then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(pp.is_active,false) then raise exception 'PET_IS_ACTIVE'; end if;
    if coalesce(pp.tradable,true) = false then raise exception 'PET_NOT_TRADABLE'; end if;
    if not auction_only_item('pet', pp.rarity) then raise exception 'NOT_AUCTION_ITEM'; end if;
    select * into pet_row from pets where id = pp.pet_id;
    return jsonb_build_object('name', coalesce(pet_row.name,'Pet'), 'rarity', lower(coalesce(pp.rarity,'')),
      'level', coalesce(pp.level,1),
      'image', coalesce(pet_row.image_final_url, pet_row.image_adult_url, pet_row.image_base_url, pet_row.image_young_url),
      'evolution', pp.evolution_stage, 'tier', coalesce(pp.evolution_tier,0), 'dailyYield', 0);
  elsif kind = 'equipment' then
    select * into pe from player_equipment where id = p_instance and user_id = p_user for update;
    if pe.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(pe.market_locked,false) then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(pe.locked,false) then raise exception 'ITEM_LOCKED'; end if;
    if pe.hero_id is not null then raise exception 'ITEM_EQUIPPED'; end if;
    select * into tpl from equipment_templates where id = pe.template_id;
    if not auction_only_item('equipment', tpl.rarity) then raise exception 'NOT_AUCTION_ITEM'; end if;
    select * into nft from nft_equipment where player_equipment_id = pe.id limit 1;
    return jsonb_build_object('name', coalesce(tpl.name,'Equipment'), 'rarity', lower(coalesce(tpl.rarity,'')),
      'level', coalesce(pe.level,1), 'image', tpl.image_url, 'slot', tpl.slot,
      'serial', nft.nft_serial, 'dailyYield', 0);
  end if;
  raise exception 'INVALID_ITEM_TYPE';
end $$;

create or replace function public.auction_item_lock(p_item_type text, p_instance uuid, p_locked boolean)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if p_item_type = 'hero' then
    update player_heroes set market_locked = p_locked, updated_at = now() where id = p_instance;
  elsif p_item_type = 'pet' then
    update player_pets set market_locked = p_locked, updated_at = now() where id = p_instance;
  else
    update player_equipment set market_locked = p_locked, updated_at = now() where id = p_instance;
  end if;
end $$;

create or replace function public.auction_item_transfer(p_item_type text, p_instance uuid, p_buyer uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if p_item_type = 'hero' then
    update player_heroes set user_id = p_buyer, market_locked = false, updated_at = now() where id = p_instance;
  elsif p_item_type = 'pet' then
    update player_pets set user_id = p_buyer, market_locked = false, is_active = false, updated_at = now() where id = p_instance;
  else
    update player_equipment set user_id = p_buyer, market_locked = false, hero_id = null, updated_at = now() where id = p_instance;
    update nft_equipment set owner_user_id = p_buyer, updated_at = now() where player_equipment_id = p_instance;
  end if;
end $$;

create or replace function public.auction_create(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid,
  p_starting_bid_ton numeric, p_duration_hours integer)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare cfg jsonb; u uuid; snap jsonb; kind text := lower(coalesce(p_item_type,'')); start_bid numeric;
        auction_id uuid; dur_hours integer := coalesce(p_duration_hours,24); ends timestamptz;
begin
  cfg := auction_settings_json();
  if not coalesce((cfg->>'enabled')::boolean, true) and not market_is_bypass_admin(p_telegram_id) then
    raise exception 'AUCTION_DISABLED';
  end if;
  if kind not in ('hero','pet','equipment') then raise exception 'INVALID_ITEM_TYPE'; end if;
  if not exists (select 1 from jsonb_array_elements_text(cfg->'durations') d where d::integer = dur_hours) then
    raise exception 'INVALID_DURATION';
  end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  start_bid := round(coalesce(p_starting_bid_ton,0), 9);
  if start_bid <= 0 then raise exception 'INVALID_PRICE'; end if;
  if start_bid < (cfg->>'minStartingBidTon')::numeric then raise exception 'PRICE_BELOW_MINIMUM'; end if;
  if start_bid > 100000 then raise exception 'PRICE_ABOVE_MAXIMUM'; end if;

  snap := auction_item_snapshot(u, kind, p_item_instance_id);
  perform auction_item_lock(kind, p_item_instance_id, true);
  ends := now() + make_interval(hours => dur_hours);

  insert into auctions(seller_user_id, item_type, item_instance_id, snapshot, starting_bid_ton,
    min_increment_ton, fee_percent, ends_at)
  values (u, kind, p_item_instance_id, snap || jsonb_build_object('seller', market_seller_label(u)),
    start_bid, (cfg->>'minIncrementTon')::numeric, (cfg->>'feePercent')::numeric, ends)
  returning id into auction_id;

  return jsonb_build_object('ok', true, 'auctionId', auction_id, 'startingBidTon', start_bid,
    'currency', 'TON', 'feePercent', (cfg->>'feePercent')::numeric, 'endsAt', ends);
end $$;

create or replace function public.auction_place_bid(p_telegram_id bigint, p_auction_id uuid,
  p_amount_ton numeric, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare cfg jsonb; a auctions%rowtype; bidder uuid; amount numeric; min_next numeric;
        prev_bidder uuid; prev_amount numeric; already_reserved numeric := 0; diff numeric;
        bid_id uuid; new_ends timestamptz;
begin
  if p_idempotency_key is not null and exists (select 1 from auction_bids where idempotency_key = p_idempotency_key) then
    select * into a from auctions where id = p_auction_id;
    return jsonb_build_object('ok', true, 'duplicate', true, 'currentBidTon', a.current_bid_ton);
  end if;
  cfg := auction_settings_json();
  select id into bidder from game_players where telegram_id = p_telegram_id;
  if bidder is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select * into a from auctions where id = p_auction_id for update;
  if a.id is null then raise exception 'AUCTION_NOT_FOUND'; end if;
  if a.status <> 'active' then raise exception 'AUCTION_NOT_ACTIVE'; end if;
  if a.ends_at <= now() then raise exception 'AUCTION_ENDED'; end if;
  if a.seller_user_id = bidder then raise exception 'CANNOT_BID_OWN_AUCTION'; end if;

  amount := round(coalesce(p_amount_ton,0), 9);
  if amount <= 0 then raise exception 'INVALID_BID'; end if;
  min_next := case when a.current_bid_ton is null then a.starting_bid_ton
                   else round(a.current_bid_ton + a.min_increment_ton, 9) end;
  if amount < min_next then raise exception 'BID_TOO_LOW'; end if;

  prev_bidder := a.highest_bidder_id; prev_amount := coalesce(a.current_bid_ton,0);
  if prev_bidder = bidder then already_reserved := prev_amount; end if;
  diff := round(amount - already_reserved, 9);
  if diff > 0 then
    perform auction_ton_move(bidder, diff, 'AUCTION_TON_RESERVED', a.id, null,
      jsonb_build_object('bidTon', amount, 'previousReserved', already_reserved));
  end if;

  insert into auction_bids(auction_id, bidder_user_id, amount_ton, status, idempotency_key)
  values (a.id, bidder, amount, 'highest', p_idempotency_key)
  returning id into bid_id;
  update auction_bids set status = 'outbid' where auction_id = a.id and id <> bid_id and status = 'highest';

  if prev_bidder is not null and prev_bidder <> bidder then
    perform auction_ton_move(prev_bidder, -prev_amount, 'AUCTION_TON_RELEASED', a.id, bid_id,
      jsonb_build_object('outbidBy', amount));
    insert into player_notifications(user_id, type, title, message, metadata)
    values (prev_bidder, 'auction_outbid', 'YOU HAVE BEEN OUTBID',
      'Bid ' || prev_amount || ' TON -> ' || amount || ' TON. Reserved TON released.',
      jsonb_build_object('auctionId', a.id, 'previousBidTon', prev_amount, 'currentBidTon', amount));
  end if;

  new_ends := a.ends_at;
  if coalesce((cfg->>'antiSnipeEnabled')::boolean, true)
     and a.ends_at - now() <= make_interval(mins => ((cfg->>'antiSnipeWindowMinutes')::numeric)::integer) then
    new_ends := a.ends_at + make_interval(mins => ((cfg->>'antiSnipeExtensionMinutes')::numeric)::integer);
  end if;

  update auctions set current_bid_ton = amount, highest_bidder_id = bidder,
    bid_count = bid_count + 1, ends_at = new_ends, updated_at = now() where id = a.id;

  return jsonb_build_object('ok', true, 'auctionId', a.id, 'bidTon', amount, 'reservedTon', amount,
    'currency', 'TON', 'endsAt', new_ends, 'bidCount', a.bid_count + 1,
    'availableTon', (select coalesce(ton_balance,0) from game_players where id = bidder));
end $$;

create or replace function public.auction_cancel(p_telegram_id bigint, p_auction_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare a auctions%rowtype; u uuid;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  select * into a from auctions where id = p_auction_id for update;
  if a.id is null then raise exception 'AUCTION_NOT_FOUND'; end if;
  if a.seller_user_id <> u then raise exception 'NOT_AUCTION_OWNER'; end if;
  if a.status <> 'active' then raise exception 'AUCTION_NOT_ACTIVE'; end if;
  if a.bid_count > 0 then raise exception 'AUCTION_HAS_BIDS'; end if;
  perform auction_item_lock(a.item_type, a.item_instance_id, false);
  update auctions set status = 'cancelled', finished_at = now(), updated_at = now() where id = a.id;
  return jsonb_build_object('ok', true, 'auctionId', a.id, 'status', 'cancelled');
end $$;

create or replace function public.auction_finalize_one(p_auction_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare a auctions%rowtype; gross numeric; fee numeric; net numeric;
        buyer_before numeric; buyer_after numeric; seller_before numeric; seller_after numeric;
begin
  select * into a from auctions where id = p_auction_id for update;
  if a.id is null then raise exception 'AUCTION_NOT_FOUND'; end if;
  if a.status <> 'active' then return jsonb_build_object('ok', true, 'status', a.status); end if;
  if a.ends_at > now() then return jsonb_build_object('ok', true, 'status', 'active'); end if;

  if a.highest_bidder_id is null then
    perform auction_item_lock(a.item_type, a.item_instance_id, false);
    update auctions set status = 'expired', finished_at = now(), updated_at = now() where id = a.id;
    return jsonb_build_object('ok', true, 'status', 'expired');
  end if;

  gross := round(coalesce(a.current_bid_ton,0), 9);
  fee := round(gross * a.fee_percent / 100, 9);
  net := round(gross - fee, 9);

  select coalesce(ton_reserved,0) into buyer_before from game_players where id = a.highest_bidder_id for update;
  if buyer_before < gross then raise exception 'RESERVATION_MISSING'; end if;
  update game_players set ton_reserved = greatest(0, coalesce(ton_reserved,0) - gross)
   where id = a.highest_bidder_id returning coalesce(ton_reserved,0) into buyer_after;
  insert into auction_ledger(event, auction_id, user_id, counterparty_user_id, gross_ton, fee_ton, net_ton,
    balance_before, balance_after, details)
  values ('AUCTION_TON_PURCHASE', a.id, a.highest_bidder_id, a.seller_user_id, gross, fee, net,
    buyer_before, buyer_after, jsonb_build_object('itemType', a.item_type, 'snapshot', a.snapshot));

  select coalesce(ton_balance,0) into seller_before from game_players where id = a.seller_user_id for update;
  update game_players set ton_balance = coalesce(ton_balance,0) + net
   where id = a.seller_user_id returning coalesce(ton_balance,0) into seller_after;
  insert into auction_ledger(event, auction_id, user_id, counterparty_user_id, gross_ton, fee_ton, net_ton,
    balance_before, balance_after, details)
  values ('AUCTION_TON_SALE', a.id, a.seller_user_id, a.highest_bidder_id, gross, fee, net,
    seller_before, seller_after, jsonb_build_object('itemType', a.item_type));
  insert into auction_ledger(event, auction_id, user_id, gross_ton, fee_ton, details)
  values ('AUCTION_TON_FEE', a.id, a.seller_user_id, gross, fee, jsonb_build_object('feePercent', a.fee_percent));

  insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, status, note)
  values (a.seller_user_id, net, 'credit', 'auction_sale', a.id::text, 'confirmed', 'Auction sale');

  perform auction_item_transfer(a.item_type, a.item_instance_id, a.highest_bidder_id);

  update auction_bids set status = 'won'
   where auction_id = a.id and bidder_user_id = a.highest_bidder_id and status = 'highest';
  update auctions set status = 'sold', winner_user_id = a.highest_bidder_id, final_price_ton = gross,
    fee_ton = fee, seller_net_ton = net, finished_at = now(), updated_at = now() where id = a.id;

  insert into player_notifications(user_id, type, title, message, metadata)
  values (a.highest_bidder_id, 'auction_won', 'AUCTION WON!',
    coalesce(a.snapshot->>'name','Item') || ' - ' || gross || ' TON.',
    jsonb_build_object('auctionId', a.id, 'finalPriceTon', gross));
  insert into player_notifications(user_id, type, title, message, metadata)
  values (a.seller_user_id, 'auction_sold', 'AUCTION SOLD',
    coalesce(a.snapshot->>'name','Item') || ' - +' || net || ' TON.',
    jsonb_build_object('auctionId', a.id, 'grossTon', gross, 'feeTon', fee, 'netTon', net));

  return jsonb_build_object('ok', true, 'status', 'sold', 'grossTon', gross, 'feeTon', fee, 'netTon', net);
end $$;

create or replace function public.auction_finalize_due()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record; total integer := 0;
begin
  for r in select id from auctions where status = 'active' and ends_at <= now() limit 50 loop
    begin
      perform auction_finalize_one(r.id);
      total := total + 1;
    exception when others then
      insert into auction_ledger(event, auction_id, details)
      values ('AUCTION_FINALIZE_FAILED', r.id, jsonb_build_object('error', sqlerrm));
    end;
  end loop;
  return total;
end $$;

create or replace function public.auction_browse(p_telegram_id bigint, p_item_type text default 'all',
  p_sort text default 'ending', p_limit integer default 60, p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; cfg jsonb; rows_json jsonb;
begin
  perform auction_finalize_due();
  cfg := auction_settings_json();
  select id into u from game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(x order by x_index), '[]'::jsonb) into rows_json from (
    select jsonb_build_object(
      'id', a.id, 'itemType', a.item_type, 'name', a.snapshot->>'name',
      'rarity', a.snapshot->>'rarity', 'level', coalesce((a.snapshot->>'level')::integer,1),
      'image', a.snapshot->>'image', 'serial', a.snapshot->>'serial',
      'stars', coalesce((a.snapshot->>'stars')::integer,0),
      'atk', coalesce((a.snapshot->>'atk')::numeric,0), 'hp', coalesce((a.snapshot->>'hp')::numeric,0),
      'dailyYield', coalesce((a.snapshot->>'dailyYield')::numeric,0),
      'seller', a.snapshot->>'seller',
      'startingBidTon', a.starting_bid_ton, 'currentBidTon', a.current_bid_ton,
      'minNextBidTon', case when a.current_bid_ton is null then a.starting_bid_ton
                            else round(a.current_bid_ton + a.min_increment_ton, 9) end,
      'bidCount', a.bid_count, 'endsAt', a.ends_at, 'mine', a.seller_user_id = u,
      'iAmHighest', a.highest_bidder_id is not null and a.highest_bidder_id = u,
      'myBidTon', (select max(b.amount_ton) from auction_bids b where b.auction_id = a.id and b.bidder_user_id = u)
    ) as x,
    row_number() over (order by
      case when p_sort = 'price_low' then coalesce(a.current_bid_ton, a.starting_bid_ton) end asc,
      case when p_sort = 'price_high' then coalesce(a.current_bid_ton, a.starting_bid_ton) end desc,
      case when p_sort = 'newest' then a.created_at end desc,
      a.ends_at asc) as x_index
    from auctions a
    where a.status = 'active' and (p_item_type = 'all' or a.item_type = p_item_type)
    limit greatest(1, least(100, coalesce(p_limit,60))) offset greatest(0, coalesce(p_offset,0))
  ) q;
  return jsonb_build_object(
    'auctions', rows_json,
    'availableTon', (select coalesce(ton_balance,0) from game_players where id = u),
    'reservedTon', (select coalesce(ton_reserved,0) from game_players where id = u),
    'settings', cfg,
    'canCreate', coalesce((cfg->>'enabled')::boolean, true) or market_is_bypass_admin(p_telegram_id),
    'adminBypass', market_is_bypass_admin(p_telegram_id));
end $$;

create or replace function public.auction_mine(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid;
begin
  perform auction_finalize_due();
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object(
    'selling', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', a.snapshot->>'name',
        'rarity', a.snapshot->>'rarity', 'image', a.snapshot->>'image', 'itemType', a.item_type,
        'currentBidTon', a.current_bid_ton, 'startingBidTon', a.starting_bid_ton, 'bidCount', a.bid_count,
        'endsAt', a.ends_at, 'status', a.status, 'finalPriceTon', a.final_price_ton,
        'netTon', a.seller_net_ton) order by a.created_at desc), '[]'::jsonb)
      from auctions a where a.seller_user_id = u),
    'bidding', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', a.snapshot->>'name',
        'rarity', a.snapshot->>'rarity', 'image', a.snapshot->>'image', 'itemType', a.item_type,
        'myBidTon', b.amount_ton, 'currentBidTon', a.current_bid_ton, 'endsAt', a.ends_at,
        'auctionStatus', a.status,
        'status', case when a.status = 'sold' and a.winner_user_id = u then 'won'
                       when a.status = 'active' and a.highest_bidder_id = u then 'highest'
                       when a.status = 'active' then 'outbid' else a.status end
      ) order by a.updated_at desc), '[]'::jsonb)
      from auctions a
      join (select auction_id, max(amount_ton) amount_ton from auction_bids where bidder_user_id = u group by 1) b
        on b.auction_id = a.id),
    'availableTon', (select coalesce(ton_balance,0) from game_players where id = u),
    'reservedTon', (select coalesce(ton_reserved,0) from game_players where id = u),
    'settings', auction_settings_json());
end $$;

create or replace function public.auction_sellable(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object(
    'heroes', (select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'itemType', 'hero', 'name', h.name,
        'rarity', lower(h.rarity), 'level', h.level, 'image', h.image, 'stars', coalesce(h.fusion_level,0),
        'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0)),
        'dailyYield', coalesce(hero_mining_rate(h.rarity),0),
        'available', not coalesce(h.market_locked,false) and not coalesce(h.locked,false)
          and coalesce(h.tradable,true)
          and not exists (select 1 from pvp_team_slots s where s.hero_id = h.id)
          and not exists (select 1 from boss_team_slots t where t.player_hero_id = h.id)
      ) order by h.name), '[]'::jsonb)
      from player_heroes h where h.user_id = u and auction_only_item('hero', h.rarity)),
    'pets', (select coalesce(jsonb_agg(jsonb_build_object('id', pp.id, 'itemType', 'pet',
        'name', coalesce(pt.name,'Pet'), 'rarity', lower(pp.rarity), 'level', pp.level,
        'image', coalesce(pt.image_final_url, pt.image_adult_url, pt.image_base_url),
        'available', not coalesce(pp.market_locked,false) and not coalesce(pp.is_active,false) and coalesce(pp.tradable,true)
      ) order by pp.level desc), '[]'::jsonb)
      from player_pets pp left join pets pt on pt.id = pp.pet_id
      where pp.user_id = u and auction_only_item('pet', pp.rarity)),
    'equipment', (select coalesce(jsonb_agg(jsonb_build_object('id', pe.id, 'itemType', 'equipment',
        'name', tpl.name, 'rarity', lower(tpl.rarity), 'level', pe.level, 'image', tpl.image_url,
        'slot', tpl.slot,
        'available', not coalesce(pe.market_locked,false) and not coalesce(pe.locked,false) and pe.hero_id is null
      ) order by tpl.name), '[]'::jsonb)
      from player_equipment pe join equipment_templates tpl on tpl.id = pe.template_id
      where pe.user_id = u and auction_only_item('equipment', tpl.rarity)),
    'availableTon', (select coalesce(ton_balance,0) from game_players where id = u),
    'settings', auction_settings_json());
end $$;

create or replace function public.admin_auction_overview(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform admin_assert(p_telegram_id);
  return jsonb_build_object(
    'settings', auction_settings_json(),
    'active', (select count(*) from auctions where status = 'active'),
    'sold', (select count(*) from auctions where status = 'sold'),
    'expired', (select count(*) from auctions where status = 'expired'),
    'volumeTon', (select coalesce(sum(final_price_ton),0) from auctions where status = 'sold'),
    'feeTon', (select coalesce(sum(fee_ton),0) from auctions where status = 'sold'));
end $$;

create or replace function public.admin_auction_set(p_telegram_id bigint, p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare merged jsonb;
begin
  perform admin_assert(p_telegram_id);
  if p_key not in ('enabled','feePercent','minStartingBidTon','minIncrementTon',
                   'antiSnipeEnabled','antiSnipeWindowMinutes','antiSnipeExtensionMinutes','durations') then
    raise exception 'INVALID_KEY';
  end if;
  select coalesce(value,'{}'::jsonb) into merged from game_settings where key = 'auction';
  merged := coalesce(merged,'{}'::jsonb) || jsonb_build_object(p_key, p_value);
  insert into game_settings(key, value, category, label, updated_by)
  values ('auction', merged, 'auction', 'Auction settings', p_telegram_id)
  on conflict (key) do update set value = merged, updated_by = p_telegram_id, updated_at = now();
  return auction_settings_json();
end $$;

revoke all on function public.auction_settings_json() from anon, authenticated;
revoke all on function public.auction_can_access(bigint) from anon, authenticated;
revoke all on function public.auction_only_item(text, text) from anon, authenticated;
revoke all on function public.auction_ton_move(uuid, numeric, text, uuid, uuid, jsonb) from anon, authenticated;
revoke all on function public.auction_item_snapshot(uuid, text, uuid) from anon, authenticated;
revoke all on function public.auction_item_lock(text, uuid, boolean) from anon, authenticated;
revoke all on function public.auction_item_transfer(text, uuid, uuid) from anon, authenticated;
revoke all on function public.auction_create(bigint, text, uuid, numeric, integer) from anon, authenticated;
revoke all on function public.auction_place_bid(bigint, uuid, numeric, text) from anon, authenticated;
revoke all on function public.auction_cancel(bigint, uuid) from anon, authenticated;
revoke all on function public.auction_finalize_one(uuid) from anon, authenticated;
revoke all on function public.auction_finalize_due() from anon, authenticated;
revoke all on function public.auction_browse(bigint, text, text, integer, integer) from anon, authenticated;
revoke all on function public.auction_mine(bigint) from anon, authenticated;
revoke all on function public.auction_sellable(bigint) from anon, authenticated;
revoke all on function public.admin_auction_overview(bigint) from anon, authenticated;
revoke all on function public.admin_auction_set(bigint, text, jsonb) from anon, authenticated;

select cron.schedule('auction-finalize', '* * * * *', $$select public.auction_finalize_due();$$)
where not exists (select 1 from cron.job where jobname = 'auction-finalize');