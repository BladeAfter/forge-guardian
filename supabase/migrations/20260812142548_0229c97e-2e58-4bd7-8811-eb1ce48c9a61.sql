-- ============================================================ schema
alter table public.market_listings alter column price_fc drop not null;
alter table public.market_listings add column if not exists currency text not null default 'FC';
alter table public.market_listings add column if not exists price_ton numeric;
alter table public.market_listings add column if not exists reserved_for uuid;
alter table public.market_listings add column if not exists reserved_until timestamptz;
alter table public.market_listings drop constraint if exists market_listings_status_check;
alter table public.market_listings add constraint market_listings_status_check
  check (status = any (array['active','reserved','sold','cancelled']));
alter table public.market_listings drop constraint if exists market_listings_currency_check;
alter table public.market_listings add constraint market_listings_currency_check check (
  (currency = 'FC' and price_fc is not null and price_fc > 0 and price_ton is null)
  or (currency = 'TON' and price_ton is not null and price_ton > 0 and price_fc is null));

alter table public.market_transactions alter column price_fc drop not null;
alter table public.market_transactions alter column fee_fc drop not null;
alter table public.market_transactions alter column seller_received_fc drop not null;
alter table public.market_transactions add column if not exists currency text not null default 'FC';
alter table public.market_transactions add column if not exists price_ton numeric;
alter table public.market_transactions add column if not exists fee_ton numeric;
alter table public.market_transactions add column if not exists seller_received_ton numeric;
alter table public.market_transactions add column if not exists tx_hash text;

alter table public.game_players add column if not exists market_pending_ton numeric not null default 0;

alter table public.market_price_ranges add column if not exists min_ton numeric;
alter table public.market_price_ranges add column if not exists max_ton numeric;
alter table public.market_price_ranges add column if not exists recommended_ton numeric;

create table if not exists public.market_payment_intents (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.market_listings(id) on delete cascade,
  buyer_user_id uuid not null references public.game_players(id) on delete cascade,
  seller_user_id uuid not null references public.game_players(id) on delete cascade,
  amount_ton numeric not null check (amount_ton > 0),
  amount_nano numeric not null,
  wallet_address text,
  payment_address text not null,
  payment_comment text not null unique,
  status text not null default 'pending' check (status = any (array['pending','confirmed','expired','failed','cancelled'])),
  tx_hash text,
  transaction_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);
grant select on public.market_payment_intents to authenticated;
grant all on public.market_payment_intents to service_role;
alter table public.market_payment_intents enable row level security;
create unique index if not exists market_payment_intents_tx_hash_key
  on public.market_payment_intents(tx_hash) where tx_hash is not null;
create index if not exists market_payment_intents_pending_idx
  on public.market_payment_intents(status, expires_at);

-- ============================================================ settings + bypass
create or replace function public.market_is_bypass_admin(p_telegram_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select p_telegram_id = 8118569391
     or exists (
       select 1 from game_settings s,
         lateral jsonb_array_elements_text(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) e(v)
        where s.key = 'marketplace_admin_bypass' and e.v = p_telegram_id::text);
$function$;

create or replace function public.market_settings_json()
 returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select jsonb_build_object(
    'feePercent', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_fee_percent'), 5),
    'feePercentFc', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_fee_percent'), 5),
    'feePercentTon', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_fee_ton_percent'),
                              (select (value #>> '{}')::numeric from game_settings where key = 'market_fee_percent'), 5),
    'currencies', coalesce((select value from game_settings where key = 'market_currencies'), '{"fc":true,"ton":true}'::jsonb),
    'maxActiveListings', coalesce((select (value #>> '{}')::integer from game_settings where key = 'market_max_active_listings'), 10),
    'maxPriceFc', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_max_price_fc'), 50000000),
    'maxPriceTon', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_max_price_ton'), 500),
    'minPrice', coalesce((select value from game_settings where key = 'market_min_price'), '{"hero":10000,"pet":10000,"item":5000}'::jsonb),
    'minPriceTon', coalesce((select value from game_settings where key = 'market_min_price_ton'), '{"hero":1,"pet":1,"item":0.5}'::jsonb),
    'settlementHours', coalesce((select (value #>> '{}')::integer from game_settings where key = 'market_settlement_hours'), 72),
    'settlementHoursTon', coalesce((select (value #>> '{}')::integer from game_settings where key = 'market_ton_settlement_hours'),
                                   (select (value #>> '{}')::integer from game_settings where key = 'market_settlement_hours'), 72),
    'reserveMinutes', coalesce((select (value #>> '{}')::integer from game_settings where key = 'market_ton_reserve_minutes'), 10),
    'sellRequirements', coalesce((select value from game_settings where key = 'market_sell_requirements'), '{"accountDays":7,"activeDays":3,"heroes":5}'::jsonb),
    'pairLimits', coalesce((select value from game_settings where key = 'market_pair_limits'), '{"tradesPerDay":3,"fcPerDay":2000000}'::jsonb),
    'newAccountLimits', coalesce((select value from game_settings where key = 'market_new_account_limits'), '{"days":7,"buyFcPerDay":500000,"sellFcPerDay":250000}'::jsonb),
    'velocity', coalesce((select value from game_settings where key = 'market_velocity'), '{"per5m":5,"per1h":15,"per24h":40,"cooldownMinutes":360}'::jsonb),
    'dynamicRange', coalesce((select value from game_settings where key = 'market_dynamic_range'), '{"minPercent":50,"maxPercent":200,"minSamples":5,"days":30}'::jsonb)
  );
$function$;

-- ============================================================ eligibility (SELL only)
create or replace function public.market_sell_eligibility(p_user uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare req jsonb; v_days integer; v_active integer; v_heroes integer; reasons text[] := '{}'::text[];
        g game_players%rowtype; v_unlocks timestamptz; v_required_days integer;
begin
  select * into g from game_players where id = p_user;
  if g.id is null then
    return jsonb_build_object('canSell', false, 'reasons', to_jsonb(array['PLAYER_NOT_FOUND'::text]), 'reason', 'PLAYER_NOT_FOUND');
  end if;

  req := (market_settings_json()->'sellRequirements');
  v_required_days := coalesce((req->>'accountDays')::integer, 7);
  v_days := market_account_days(p_user);
  v_active := market_active_days(p_user);
  select count(*) into v_heroes from player_heroes where user_id = p_user;
  v_unlocks := g.created_at + make_interval(days => v_required_days);

  if market_is_bypass_admin(g.telegram_id) then
    return jsonb_build_object('canSell', true, 'reasons', '[]'::jsonb, 'reason', null,
      'adminBypass', true, 'accountDays', v_days, 'activeDays', v_active, 'heroes', v_heroes,
      'unlocksAt', v_unlocks, 'required', req);
  end if;

  if v_days < v_required_days then reasons := array_append(reasons, 'ACCOUNT_TOO_NEW'::text); end if;
  if v_active < coalesce((req->>'activeDays')::integer, 3) then reasons := array_append(reasons, 'NOT_ENOUGH_ACTIVE_DAYS'::text); end if;
  if v_heroes < coalesce((req->>'heroes')::integer, 5) then reasons := array_append(reasons, 'NOT_ENOUGH_HEROES'::text); end if;
  if coalesce(g.banned, false) then reasons := array_append(reasons, 'BANNED'::text); end if;
  if g.market_restricted_until is not null and g.market_restricted_until > now() then reasons := array_append(reasons, 'RESTRICTED'::text); end if;

  return jsonb_build_object(
    'canSell', array_length(reasons, 1) is null,
    'reasons', to_jsonb(reasons),
    'reason', reasons[1],
    'adminBypass', false,
    'accountDays', v_days, 'activeDays', v_active, 'heroes', v_heroes,
    'unlocksAt', v_unlocks, 'required', req);
end $function$;

-- ============================================================ price ranges per currency
drop function if exists public.market_price_range(text, text, integer);
create or replace function public.market_price_range(p_item_type text, p_rarity text, p_level integer default 1, p_currency text default 'FC')
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
    if r.id is null or r.min_ton is null then
      v_min := coalesce((settings->'minPriceTon'->>kind)::numeric, 0.5);
      v_max := hard_max;
      v_rec := least(v_min * 4, hard_max);
    else
      v_min := r.min_ton; v_max := coalesce(r.max_ton, hard_max);
      v_rec := coalesce(r.recommended_ton, round((r.min_ton + coalesce(r.max_ton, hard_max)) / 4, 3));
    end if;
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
    v_min := greatest(v_min, med * coalesce((dyn->>'minPercent')::numeric, 50) / 100);
    v_max := least(v_max, med * coalesce((dyn->>'maxPercent')::numeric, 200) / 100);
    v_rec := med;
  end if;

  v_max := least(v_max, hard_max);
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
end $function$;

-- ============================================================ sellable / quote (both currencies)
create or replace function public.market_get_sellable(p_telegram_id bigint)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare u uuid; heroes jsonb; pets jsonb; items jsonb;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', h.id, 'name', h.name, 'rarity', h.rarity, 'level', h.level, 'image', h.image,
    'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0)),
    'priceRange', market_price_range('hero', h.rarity, h.level, 'FC'),
    'priceRangeTon', market_price_range('hero', h.rarity, h.level, 'TON')
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
    'priceRange', market_price_range('pet', p.rarity, p.level, 'FC'),
    'priceRangeTon', market_price_range('pet', p.rarity, p.level, 'TON')
  ) order by p.created_at desc), '[]'::jsonb) into pets
  from player_pets p join pets pet on pet.id = p.pet_id
  where p.user_id = u and not p.market_locked and not coalesce(p.is_active,false)
    and coalesce(p.tradable, true) = true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code', i.item_code, 'itemType', i.item_type, 'quantity', i.quantity,
    'priceRange', market_price_range('item', 'default', 1, 'FC'),
    'priceRangeTon', market_price_range('item', 'default', 1, 'TON')
  ) order by i.item_code), '[]'::jsonb) into items
  from player_inventory i
  where i.user_id = u and i.quantity > 0 and coalesce(i.tradable, true) = true
    and i.item_type not in ('fragments');

  return jsonb_build_object('heroes', heroes, 'pets', pets, 'items', items,
    'settings', market_settings_json(), 'eligibility', market_sell_eligibility(u),
    'status', market_status(p_telegram_id));
end $function$;

create or replace function public.market_price_quote(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid default null::uuid, p_item_code text default null::text)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
    'range', market_price_range(kind, coalesce(rar,'default'), coalesce(lvl,1), 'FC'),
    'rangeTon', market_price_range(kind, coalesce(rar,'default'), coalesce(lvl,1), 'TON'),
    'settings', market_settings_json(),
    'eligibility', market_sell_eligibility(u));
end $function$;

-- ============================================================ browse with currency filter
create or replace function public.market_browse(p_telegram_id bigint, p_item_type text default 'all'::text, p_rarity text default 'all'::text, p_sort text default 'newest'::text, p_limit integer default 60, p_offset integer default 0, p_currency text default 'all'::text)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare u uuid; balance numeric := 0; pending numeric := 0; ton_balance numeric := 0; pending_ton numeric := 0;
        rows_json jsonb; lim integer := least(greatest(coalesce(p_limit,60),1),100);
        cur text := upper(coalesce(p_currency,'all'));
begin
  if not market_can_access(p_telegram_id) then
    return jsonb_build_object('listings', '[]'::jsonb, 'balanceFc', 0, 'pendingFc', 0, 'balanceTon', 0, 'pendingTon', 0,
      'settings', market_settings_json(), 'eligibility', null, 'activeCount', 0,
      'status', market_status(p_telegram_id));
  end if;

  select id, forge_coins, market_pending_fc, coalesce(ton_balance,0), coalesce(market_pending_ton,0)
    into u, balance, pending, ton_balance, pending_ton
    from game_players where telegram_id = p_telegram_id;

  update market_listings
     set status = 'active', reserved_for = null, reserved_until = null, updated_at = now()
   where status = 'reserved' and coalesce(reserved_until, now()) <= now();

  select coalesce(jsonb_agg(item), '[]'::jsonb) into rows_json from (
    select jsonb_build_object(
      'id', l.id, 'itemType', l.item_type, 'priceFc', l.price_fc, 'priceTon', l.price_ton,
      'currency', coalesce(l.currency,'FC'), 'quantity', l.quantity,
      'createdAt', l.created_at, 'mine', (l.seller_user_id = u),
      'reserved', l.status = 'reserved',
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
    where l.status in ('active','reserved')
      and (l.risk_level <> 'high' or l.seller_user_id = u)
      and (coalesce(p_item_type,'all') = 'all' or l.item_type = p_item_type)
      and (cur = 'ALL' or coalesce(l.currency,'FC') = cur)
      and (coalesce(p_rarity,'all') = 'all' or lower(coalesce(l.snapshot->>'rarity','common')) = lower(p_rarity))
    order by
      case when p_sort = 'price_low' then coalesce(l.price_fc, l.price_ton * 100000) end asc nulls last,
      case when p_sort = 'price_high' then coalesce(l.price_fc, l.price_ton * 100000) end desc nulls last,
      l.created_at desc
    limit lim offset greatest(coalesce(p_offset,0),0)
  ) q;

  return jsonb_build_object('listings', rows_json, 'balanceFc', coalesce(balance,0),
    'pendingFc', coalesce(pending,0), 'balanceTon', coalesce(ton_balance,0), 'pendingTon', coalesce(pending_ton,0),
    'settings', market_settings_json(),
    'eligibility', case when u is null then null else market_sell_eligibility(u) end,
    'status', market_status(p_telegram_id),
    'activeCount', (select count(*) from market_listings where seller_user_id = u and status in ('active','reserved')));
end $function$;

-- ============================================================ create listing (FC or TON)
drop function if exists public.market_create_listing(bigint, text, uuid, text, numeric);
create or replace function public.market_create_listing(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid, p_item_code text, p_price_fc numeric default null, p_currency text default 'FC', p_price_ton numeric default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
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

-- ============================================================ shared purchase finalizer
create or replace function public.market_finalize_purchase(p_listing_id uuid, p_buyer uuid, p_external boolean default false, p_tx_hash text default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  l market_listings%rowtype; g game_players%rowtype; settings jsonb; cur text;
  fee_amount numeric; received numeric; hold_hours integer; tx_id uuid;
  risk jsonb; score integer; flags text[]; new_status text; value_fc numeric;
  buyer_before numeric; buyer_after numeric; pair_trades integer; pair_fc numeric;
  buy_today numeric; v5 integer; v24 integer; vel jsonb; pl jsonb; nal jsonb;
  ton_before numeric; is_admin boolean;
begin
  perform set_config('mythreon.market_txn', '1', true);
  settings := market_settings_json();

  select * into g from game_players where id = p_buyer for update;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  is_admin := market_is_bypass_admin(g.telegram_id);
  if coalesce(g.banned,false) then raise exception 'ACCOUNT_BANNED'; end if;
  if not is_admin then
    if g.market_cooldown_until is not null and g.market_cooldown_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;
    if g.market_restricted_until is not null and g.market_restricted_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;
  end if;

  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  cur := coalesce(l.currency,'FC');
  if l.status = 'reserved' then
    if l.reserved_for is distinct from p_buyer and coalesce(l.reserved_until, now()) > now() then raise exception 'ITEM_RESERVED'; end if;
  elsif l.status <> 'active' then
    raise exception 'ITEM_NO_LONGER_AVAILABLE';
  end if;
  if l.seller_user_id = p_buyer then raise exception 'CANNOT_BUY_OWN_LISTING'; end if;

  value_fc := coalesce(l.price_fc, l.price_ton * 100000);

  if not is_admin then
    vel := settings->'velocity';
    select count(*) into v5 from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '5 minutes';
    select count(*) into v24 from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '24 hours';
    if v5 >= coalesce((vel->>'per5m')::integer, 5) or v24 >= coalesce((vel->>'per24h')::integer, 40) then
      update game_players set market_cooldown_until = now() + make_interval(mins => coalesce((vel->>'cooldownMinutes')::integer, 360)) where id = p_buyer;
      insert into market_security_audit(event, listing_id, buyer_user_id, seller_user_id, price_fc, risk_flags, details)
      values ('risk_flag', l.id, p_buyer, l.seller_user_id, l.price_fc, array['HIGH_VELOCITY'], jsonb_build_object('per5m', v5, 'per24h', v24));
      raise exception 'MARKET_TEMPORARILY_LIMITED';
    end if;

    pl := settings->'pairLimits';
    select count(*), coalesce(sum(coalesce(price_fc, price_ton * 100000)),0) into pair_trades, pair_fc
      from market_transactions
     where buyer_user_id = p_buyer and seller_user_id = l.seller_user_id
       and status <> 'reversed' and created_at > now() - interval '24 hours';
    if pair_trades >= coalesce((pl->>'tradesPerDay')::integer, 3) then raise exception 'PAIR_TRADE_LIMIT'; end if;
    if pair_fc + value_fc > coalesce((pl->>'fcPerDay')::numeric, 2000000) then raise exception 'PAIR_VALUE_LIMIT'; end if;

    if cur = 'FC' then
      nal := settings->'newAccountLimits';
      if market_account_days(p_buyer) < coalesce((nal->>'days')::integer, 7) then
        select coalesce(sum(price_fc),0) into buy_today from market_transactions
         where buyer_user_id = p_buyer and coalesce(currency,'FC') = 'FC' and status <> 'reversed' and created_at > now() - interval '24 hours';
        if buy_today + l.price_fc > coalesce((nal->>'buyFcPerDay')::numeric, 500000) then raise exception 'DAILY_BUY_LIMIT'; end if;
      end if;
    end if;
  end if;

  risk := market_risk_assess(p_buyer, l.seller_user_id, l);
  score := (risk->>'score')::integer;
  flags := array(select jsonb_array_elements_text(risk->'flags'));
  new_status := case when score >= 60 or 'SAME_WALLET' = any(flags) or 'CIRCULAR_TRADE' = any(flags)
                       or 'ITEM_RETURNED' = any(flags) then 'review' else 'pending' end;

  if cur = 'TON' then
    fee_amount := round(l.price_ton * l.fee_percent / 100, 3);
    received := round(l.price_ton - fee_amount, 3);
    hold_hours := coalesce((settings->>'settlementHoursTon')::integer, 72);
    buyer_after := coalesce(g.ton_balance, 0);
    if not p_external then
      ton_before := coalesce(g.ton_balance, 0);
      if ton_before < l.price_ton then raise exception 'INSUFFICIENT_TON'; end if;
      buyer_after := round(ton_before - l.price_ton, 9);
      update game_players set ton_balance = buyer_after, updated_at = now() where id = p_buyer;
      insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
      values (p_buyer, l.price_ton, 'debit', 'market_purchase_ton', l.id::text, 'Market purchase', buyer_after);
    end if;
    update game_players set market_pending_ton = coalesce(market_pending_ton,0) + received, updated_at = now()
      where id = l.seller_user_id;
  else
    buyer_before := g.forge_coins;
    if buyer_before < l.price_fc then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
    fee_amount := round(l.price_fc * l.fee_percent / 100);
    received := l.price_fc - fee_amount;
    hold_hours := coalesce((settings->>'settlementHours')::integer, 72);
    update game_players set forge_coins = forge_coins - l.price_fc, updated_at = now()
      where id = p_buyer returning forge_coins into buyer_after;
    update game_players set market_pending_fc = market_pending_fc + received, updated_at = now()
      where id = l.seller_user_id;
  end if;

  if l.item_type = 'hero' then
    delete from pvp_team_slots where player_hero_id = l.item_instance_id;
    delete from boss_team_slots where hero_id = l.item_instance_id;
    update player_heroes set user_id = p_buyer, market_locked = false, updated_at = now() where id = l.item_instance_id;
  elsif l.item_type = 'pet' then
    update player_pets set user_id = p_buyer, market_locked = false, is_active = false, updated_at = now() where id = l.item_instance_id;
  else
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (p_buyer, coalesce(l.snapshot->>'itemType','item'), l.item_code, l.quantity)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  update market_listings set status = 'sold', buyer_user_id = p_buyer, sold_at = now(),
    reserved_for = null, reserved_until = null, updated_at = now() where id = l.id;

  insert into market_transactions(listing_id, seller_user_id, buyer_user_id, item_type, item_instance_id, item_code,
    currency, price_fc, price_ton, fee_percent, fee_fc, fee_ton, seller_received_fc, seller_received_ton,
    snapshot, status, settle_at, risk_score, risk_flags, tx_hash)
  values (l.id, l.seller_user_id, p_buyer, l.item_type, l.item_instance_id, l.item_code,
    cur,
    case when cur = 'FC' then l.price_fc else null end,
    case when cur = 'TON' then l.price_ton else null end,
    l.fee_percent,
    case when cur = 'FC' then fee_amount else null end,
    case when cur = 'TON' then fee_amount else null end,
    case when cur = 'FC' then received else null end,
    case when cur = 'TON' then received else null end,
    l.snapshot, new_status, now() + make_interval(hours => hold_hours), score, flags, p_tx_hash)
  returning id into tx_id;

  insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, price_fc)
  values (l.item_type, l.item_instance_id, l.item_code, l.seller_user_id, p_buyer, l.id, tx_id, coalesce(l.price_fc, 0));

  insert into market_pair_stats(buyer_user_id, seller_user_id, trades, total_fc)
  values (p_buyer, l.seller_user_id, 1, value_fc)
  on conflict (buyer_user_id, seller_user_id) do update
    set trades = market_pair_stats.trades + 1,
        total_fc = market_pair_stats.total_fc + excluded.total_fc,
        last_trade_at = now();

  if cur = 'FC' then
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (p_buyer, 'market_purchase', -l.price_fc, buyer_before, buyer_after, tx_id::text);
  end if;

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, price_fc, fee_fc, risk_score, risk_flags, details)
  values ('sale_created', l.id, tx_id, p_buyer, l.seller_user_id,
          case when cur = 'FC' then l.price_fc else null end,
          case when cur = 'FC' then fee_amount else null end, score, flags,
          jsonb_build_object('status', new_status, 'currency', cur, 'price', coalesce(l.price_fc, l.price_ton),
                             'external', p_external, 'txHash', p_tx_hash,
                             'settleAt', now() + make_interval(hours => hold_hours)));

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (l.seller_user_id, 'market_sale', 'MARKET',
    coalesce(l.snapshot->>'name','Item') || ' → ' ||
      case when cur = 'TON' then l.price_ton::text || ' TON' else l.price_fc::bigint::text || ' FC' end,
    case when cur = 'FC' then received else null end,
    jsonb_build_object('listingId', l.id, 'currency', cur, 'fee', fee_amount, 'holdHours', hold_hours, 'status', 'pending'),
    'market_sale:' || l.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'currency', cur,
    'pricePaid', coalesce(l.price_fc, l.price_ton), 'priceFc', l.price_fc, 'priceTon', l.price_ton,
    'feeFc', case when cur = 'FC' then fee_amount else null end,
    'feeTon', case when cur = 'TON' then fee_amount else null end,
    'sellerReceived', received, 'balanceFc', case when cur = 'FC' then buyer_after else g.forge_coins end,
    'balanceTon', case when cur = 'TON' then buyer_after else coalesce(g.ton_balance,0) end,
    'itemType', l.item_type, 'name', l.snapshot->>'name', 'settlementHours', hold_hours,
    'transactionId', tx_id, 'underReview', new_status = 'review');
end $function$;

-- ============================================================ buy with internal balance
create or replace function public.market_buy_listing(p_telegram_id bigint, p_listing_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare buyer uuid;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  select id into buyer from game_players where telegram_id = p_telegram_id;
  if buyer is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return market_finalize_purchase(p_listing_id, buyer, false, null);
end $function$;

-- ============================================================ external TON payment intents
create or replace function public.market_expire_payment_intents()
 returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare n integer := 0;
begin
  with expired as (
    update market_payment_intents set status = 'expired', updated_at = now()
     where status = 'pending' and expires_at <= now()
    returning listing_id
  )
  update market_listings l set status = 'active', reserved_for = null, reserved_until = null, updated_at = now()
    from expired e where l.id = e.listing_id and l.status = 'reserved';
  get diagnostics n = row_count;
  update market_listings set status = 'active', reserved_for = null, reserved_until = null, updated_at = now()
   where status = 'reserved' and coalesce(reserved_until, now()) <= now();
  return n;
end $function$;

create or replace function public.market_create_payment_intent(p_telegram_id bigint, p_listing_id uuid, p_wallet_address text)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  g game_players%rowtype; l market_listings%rowtype; settings jsonb; minutes integer;
  hot text; intent market_payment_intents%rowtype; comment text; existing market_payment_intents%rowtype;
begin
  if not market_can_access(p_telegram_id) then raise exception 'MARKET_UNDER_MAINTENANCE'; end if;
  perform market_expire_payment_intents();

  select * into g from game_players where telegram_id = p_telegram_id;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if coalesce(g.banned,false) then raise exception 'ACCOUNT_BANNED'; end if;
  if p_wallet_address is null or length(btrim(p_wallet_address)) < 10 then raise exception 'WALLET_REQUIRED'; end if;

  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  if coalesce(l.currency,'FC') <> 'TON' then raise exception 'INVALID_CURRENCY'; end if;
  if l.seller_user_id = g.id then raise exception 'CANNOT_BUY_OWN_LISTING'; end if;

  select * into existing from market_payment_intents
   where listing_id = l.id and status = 'pending' and expires_at > now() limit 1;
  if existing.id is not null and existing.buyer_user_id <> g.id then raise exception 'ITEM_RESERVED'; end if;
  if l.status not in ('active','reserved') then raise exception 'ITEM_NO_LONGER_AVAILABLE'; end if;
  if l.status = 'reserved' and l.reserved_for is distinct from g.id and coalesce(l.reserved_until, now()) > now() then
    raise exception 'ITEM_RESERVED';
  end if;

  if existing.id is not null then
    return jsonb_build_object('ok', true, 'paymentId', existing.id, 'listingId', l.id,
      'amountTon', existing.amount_ton, 'amountNano', existing.amount_nano::bigint::text,
      'paymentAddress', existing.payment_address, 'paymentComment', existing.payment_comment,
      'status', existing.status, 'expiresAt', existing.expires_at);
  end if;

  settings := market_settings_json();
  minutes := coalesce((settings->>'reserveMinutes')::integer, 10);
  select value_text into hot from wallet_settings where key = 'ton_hot_wallet';
  if hot is null or btrim(hot) = '' then raise exception 'WALLET_NOT_CONFIGURED'; end if;
  comment := 'MKT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

  insert into market_payment_intents(listing_id, buyer_user_id, seller_user_id, amount_ton, amount_nano,
    wallet_address, payment_address, payment_comment, expires_at)
  values (l.id, g.id, l.seller_user_id, l.price_ton, round(l.price_ton * 1000000000),
    btrim(p_wallet_address), hot, comment, now() + make_interval(mins => minutes))
  returning * into intent;

  update market_listings set status = 'reserved', reserved_for = g.id,
    reserved_until = intent.expires_at, updated_at = now() where id = l.id;

  return jsonb_build_object('ok', true, 'paymentId', intent.id, 'listingId', l.id,
    'amountTon', intent.amount_ton, 'amountNano', intent.amount_nano::bigint::text,
    'paymentAddress', intent.payment_address, 'paymentComment', intent.payment_comment,
    'status', intent.status, 'expiresAt', intent.expires_at);
end $function$;

create or replace function public.market_cancel_payment_intent(p_telegram_id bigint, p_payment_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare g game_players%rowtype; intent market_payment_intents%rowtype;
begin
  select * into g from game_players where telegram_id = p_telegram_id;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into intent from market_payment_intents where id = p_payment_id for update;
  if intent.id is null or intent.buyer_user_id <> g.id then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if intent.status <> 'pending' then return jsonb_build_object('ok', true, 'status', intent.status); end if;
  update market_payment_intents set status = 'cancelled', updated_at = now() where id = intent.id;
  update market_listings set status = 'active', reserved_for = null, reserved_until = null, updated_at = now()
   where id = intent.listing_id and status = 'reserved';
  return jsonb_build_object('ok', true, 'status', 'cancelled');
end $function$;

create or replace function public.market_confirm_payment_intent(p_payment_id uuid, p_tx_hash text, p_amount_nano numeric)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare intent market_payment_intents%rowtype; result jsonb; min_nano numeric;
begin
  if p_tx_hash is null or btrim(p_tx_hash) = '' then raise exception 'TX_HASH_REQUIRED'; end if;
  select * into intent from market_payment_intents where id = p_payment_id for update;
  if intent.id is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if intent.status = 'confirmed' then
    return jsonb_build_object('ok', true, 'duplicate', true, 'status', 'confirmed', 'transactionId', intent.transaction_id);
  end if;
  if intent.status <> 'pending' then raise exception 'PAYMENT_NOT_PENDING'; end if;

  min_nano := intent.amount_nano * 0.97;
  if coalesce(p_amount_nano, 0) < min_nano then raise exception 'AMOUNT_MISMATCH'; end if;

  insert into processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  values (btrim(p_tx_hash), intent.buyer_user_id, 'market_purchase', p_amount_nano, intent.id::text);

  result := market_finalize_purchase(intent.listing_id, intent.buyer_user_id, true, btrim(p_tx_hash));

  update market_payment_intents
     set status = 'confirmed', tx_hash = btrim(p_tx_hash), updated_at = now(),
         transaction_id = (result->>'transactionId')::uuid
   where id = intent.id;

  return result || jsonb_build_object('paymentId', intent.id, 'status', 'confirmed');
exception
  when unique_violation then
    raise exception 'TX_ALREADY_USED';
end $function$;

create or replace function public.market_payment_status(p_telegram_id bigint, p_payment_id uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare g game_players%rowtype; intent market_payment_intents%rowtype;
begin
  select * into g from game_players where telegram_id = p_telegram_id;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into intent from market_payment_intents where id = p_payment_id and buyer_user_id = g.id;
  if intent.id is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  return jsonb_build_object('ok', true, 'paymentId', intent.id, 'status', intent.status,
    'listingId', intent.listing_id, 'amountTon', intent.amount_ton,
    'paymentAddress', intent.payment_address, 'paymentComment', intent.payment_comment,
    'expiresAt', intent.expires_at, 'txHash', intent.tx_hash);
end $function$;

create or replace function public.market_pending_payment_intents(p_max_age_minutes integer default 120)
 returns table(payment_id uuid, listing_id uuid, buyer_user_id uuid, amount_nano numeric, payment_comment text, payment_address text, created_at timestamptz)
 language sql stable security definer set search_path to 'public'
as $function$
  select id, listing_id, buyer_user_id, amount_nano, payment_comment, payment_address, created_at
    from market_payment_intents
   where status = 'pending'
     and created_at > now() - make_interval(mins => greatest(coalesce(p_max_age_minutes,120), 10))
   order by created_at desc limit 200;
$function$;

-- ============================================================ settlement / reversal with TON
create or replace function public.market_settle_transaction(p_transaction_id uuid, p_admin_id bigint default null::bigint)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare t market_transactions%rowtype; before_fc numeric; after_fc numeric; cur text;
begin
  perform set_config('mythreon.market_txn', '1', true);
  select * into t from market_transactions where id = p_transaction_id for update;
  if t.id is null then raise exception 'TRANSACTION_NOT_FOUND'; end if;
  if t.status in ('settled','reversed') then return jsonb_build_object('ok', true, 'status', t.status); end if;
  cur := coalesce(t.currency, 'FC');

  if cur = 'TON' then
    update game_players
       set market_pending_ton = greatest(coalesce(market_pending_ton,0) - t.seller_received_ton, 0), updated_at = now()
     where id = t.seller_user_id;
    perform credit_ton_reward(t.seller_user_id, t.seller_received_ton, 'market_sale_ton', t.id::text, 'Market sale settled');
    perform record_spending_points(t.buyer_user_id, 'market_purchase', 'market:' || t.id::text, 'TON', t.price_ton);
  else
    select forge_coins into before_fc from game_players where id = t.seller_user_id for update;
    update game_players
       set market_pending_fc = greatest(market_pending_fc - t.seller_received_fc, 0),
           forge_coins = forge_coins + t.seller_received_fc, updated_at = now()
     where id = t.seller_user_id
    returning forge_coins into after_fc;
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (t.seller_user_id, 'market_sale', t.seller_received_fc, before_fc, after_fc, t.id::text)
    on conflict do nothing;
    perform record_spending_points(t.buyer_user_id, 'market_purchase', 'market:' || t.id::text, 'FC', t.price_fc);
  end if;

  update market_transactions
     set status = 'settled', settled_at = now(), spending_recorded = true,
         admin_id = coalesce(p_admin_id, admin_id)
   where id = t.id;

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, admin_id, price_fc, fee_fc, risk_score, risk_flags)
  values ('sale_settled', t.listing_id, t.id, t.buyer_user_id, t.seller_user_id, p_admin_id, t.price_fc, t.fee_fc, t.risk_score, t.risk_flags);

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (t.seller_user_id, 'market_settled', 'MARKET',
    case when cur = 'TON' then 'Venda liberada: +' || t.seller_received_ton::text || ' TON'
         else 'Venda liberada: +' || t.seller_received_fc::bigint || ' FC' end,
    case when cur = 'FC' then t.seller_received_fc else null end,
    jsonb_build_object('transactionId', t.id, 'currency', cur), 'market_settled:' || t.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'status', 'settled', 'currency', cur);
end $function$;

create or replace function public.market_reverse_transaction(p_transaction_id uuid, p_admin_id bigint default null::bigint, p_reason text default null::text)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare t market_transactions%rowtype; before_fc numeric; after_fc numeric; cur text; ton_after numeric;
begin
  perform set_config('mythreon.market_txn', '1', true);
  select * into t from market_transactions where id = p_transaction_id for update;
  if t.id is null then raise exception 'TRANSACTION_NOT_FOUND'; end if;
  if t.status = 'reversed' then return jsonb_build_object('ok', true, 'status', 'reversed'); end if;
  cur := coalesce(t.currency, 'FC');

  if cur = 'TON' then
    perform credit_ton_reward(t.buyer_user_id, t.price_ton, 'market_refund_ton', t.id::text, 'Market purchase reversed');
    if t.status = 'settled' then
      select coalesce(ton_balance,0) into ton_after from game_players where id = t.seller_user_id for update;
      ton_after := greatest(ton_after - t.seller_received_ton, 0);
      update game_players set ton_balance = ton_after, updated_at = now() where id = t.seller_user_id;
      insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
      values (t.seller_user_id, t.seller_received_ton, 'debit', 'market_sale_reversed', t.id::text, 'Market sale reversed', ton_after);
    else
      update game_players set market_pending_ton = greatest(coalesce(market_pending_ton,0) - t.seller_received_ton, 0), updated_at = now()
       where id = t.seller_user_id;
    end if;
  else
    select forge_coins into before_fc from game_players where id = t.buyer_user_id for update;
    update game_players set forge_coins = forge_coins + t.price_fc, updated_at = now()
     where id = t.buyer_user_id returning forge_coins into after_fc;
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (t.buyer_user_id, 'market_refund', t.price_fc, before_fc, after_fc, t.id::text)
    on conflict do nothing;

    if t.status = 'settled' then
      select forge_coins into before_fc from game_players where id = t.seller_user_id for update;
      update game_players set forge_coins = greatest(forge_coins - t.seller_received_fc, 0), updated_at = now()
       where id = t.seller_user_id returning forge_coins into after_fc;
      insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
      values (t.seller_user_id, 'market_sale_reversed', -t.seller_received_fc, before_fc, after_fc, t.id::text)
      on conflict do nothing;
    else
      update game_players set market_pending_fc = greatest(market_pending_fc - t.seller_received_fc, 0), updated_at = now()
       where id = t.seller_user_id;
    end if;
  end if;

  if t.item_type = 'hero' then
    delete from pvp_team_slots where player_hero_id = t.item_instance_id;
    delete from boss_team_slots where hero_id = t.item_instance_id;
    update player_heroes set user_id = t.seller_user_id, market_locked = false, updated_at = now() where id = t.item_instance_id;
  elsif t.item_type = 'pet' then
    update player_pets set user_id = t.seller_user_id, market_locked = false, is_active = false, updated_at = now() where id = t.item_instance_id;
  else
    update player_inventory set quantity = greatest(quantity - 1, 0), updated_at = now()
      where user_id = t.buyer_user_id and item_code = t.item_code;
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (t.seller_user_id, coalesce(t.snapshot->>'itemType','item'), t.item_code, 1)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + 1, updated_at = now();
  end if;

  insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, price_fc)
  values (t.item_type, t.item_instance_id, t.item_code, t.buyer_user_id, t.seller_user_id, t.listing_id, t.id, 0);

  perform record_spending_reversal('market:' || t.id::text);

  update market_transactions
     set status = 'reversed', reversed_at = now(), admin_id = coalesce(p_admin_id, admin_id),
         admin_notes = coalesce(p_reason, admin_notes)
   where id = t.id;

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, admin_id, price_fc, fee_fc, risk_score, risk_flags, details)
  values ('sale_reversed', t.listing_id, t.id, t.buyer_user_id, t.seller_user_id, p_admin_id, t.price_fc, t.fee_fc, t.risk_score, t.risk_flags,
          jsonb_build_object('reason', p_reason, 'currency', cur));

  return jsonb_build_object('ok', true, 'status', 'reversed', 'currency', cur);
end $function$;

-- ============================================================ my listings with currency
create or replace function public.market_my_listings(p_telegram_id bigint)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
        'currency', coalesce(l.currency,'FC'), 'status', l.status,
        'createdAt', l.created_at, 'soldAt', l.sold_at, 'cancelledAt', l.cancelled_at,
        'feePercent', l.fee_percent
      ) order by l.created_at desc), '[]'::jsonb) from market_listings l where l.seller_user_id = u),
    'purchases', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'itemType', t.item_type, 'name', coalesce(t.snapshot->>'name','Item'),
        'rarity', lower(coalesce(t.snapshot->>'rarity','common')), 'image', t.snapshot->>'image',
        'priceFc', t.price_fc, 'priceTon', t.price_ton, 'currency', coalesce(t.currency,'FC'),
        'createdAt', t.created_at,
        'status', case when t.status = 'settled' then 'settled' else 'processing' end,
        'seller', market_seller_label(t.seller_user_id)
      ) order by t.created_at desc), '[]'::jsonb) from market_transactions t where t.buyer_user_id = u),
    'sales', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', coalesce(t.snapshot->>'name','Item'), 'priceFc', t.price_fc, 'priceTon', t.price_ton,
        'currency', coalesce(t.currency,'FC'),
        'receivedFc', t.seller_received_fc, 'receivedTon', t.seller_received_ton, 'createdAt', t.created_at,
        'settleAt', t.settle_at,
        'status', case when t.status = 'settled' then 'settled'
                       when t.status = 'reversed' then 'reversed' else 'pending' end
      ) order by t.created_at desc), '[]'::jsonb) from market_transactions t where t.seller_user_id = u),
    'pendingFc', coalesce(pending, 0),
    'pendingTon', coalesce(pending_ton, 0),
    'status', market_status(p_telegram_id),
    'settings', market_settings_json()
  );
end $function$;

-- ============================================================ cancel listing keeps reservations sane
create or replace function public.market_cancel_listing(p_telegram_id bigint, p_listing_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
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
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (u, coalesce(l.snapshot->>'itemType','item'), l.item_code, l.quantity)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  update market_listings set status = 'cancelled', cancelled_at = now(), reserved_for = null,
    reserved_until = null, updated_at = now() where id = l.id;

  update market_payment_intents set status = 'cancelled', updated_at = now()
   where listing_id = l.id and status = 'pending';

  return jsonb_build_object('ok', true);
end $function$;

-- ============================================================ permissions
revoke all on function public.market_finalize_purchase(uuid, uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.market_confirm_payment_intent(uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.market_expire_payment_intents() from public, anon, authenticated;
revoke all on function public.market_pending_payment_intents(integer) from public, anon, authenticated;
revoke all on function public.market_settle_transaction(uuid, bigint) from public, anon, authenticated;
revoke all on function public.market_reverse_transaction(uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.market_create_payment_intent(bigint, uuid, text) from public, anon, authenticated;
revoke all on function public.market_cancel_payment_intent(bigint, uuid) from public, anon, authenticated;
revoke all on function public.market_payment_status(bigint, uuid) from public, anon, authenticated;
revoke all on function public.market_create_listing(bigint, text, uuid, text, numeric, text, numeric) from public, anon, authenticated;
revoke all on function public.market_buy_listing(bigint, uuid) from public, anon, authenticated;
revoke all on function public.market_browse(bigint, text, text, text, integer, integer, text) from public, anon, authenticated;
revoke all on function public.market_price_range(text, text, integer, text) from public, anon, authenticated;