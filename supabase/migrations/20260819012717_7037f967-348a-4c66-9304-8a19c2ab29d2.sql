-- ============================== FOUNDER PACK ==============================
create table if not exists public.founder_pack_config (
  id boolean primary key default true check (id),
  enabled boolean not null default true,
  price_ton numeric not null default 25,
  eligibility_days int not null default 7,
  myth_amount numeric not null default 100000,
  pass_tier text not null default 'legendary',
  hero_key text not null default 'pass-solmire',
  pet_slug text not null default 'pass-crysalune',
  equipment_chest_code text not null default 'legendary_chest',
  fragments int not null default 100,
  resource_chest_code text not null default 'premium_resource_chest',
  resource_chest jsonb not null default '{"fc":250000,"fragments":50,"pvp_tickets":10,"hero_chest":"epic_chest","hero_chest_qty":3}'::jsonb,
  badge_enabled boolean not null default true,
  frame_enabled boolean not null default true,
  pack_version int not null default 1,
  updated_at timestamptz not null default now()
);
grant all on public.founder_pack_config to service_role;
alter table public.founder_pack_config enable row level security;
insert into public.founder_pack_config(id) values (true) on conflict (id) do nothing;

create table if not exists public.founder_pack_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  telegram_id bigint,
  pack_version int not null default 1,
  price_ton numeric not null,
  amount_nano text not null,
  reward_snapshot jsonb not null default '{}'::jsonb,
  payment_method text not null default 'ton_connect',
  status text not null default 'pending',
  payment_address text,
  payment_comment text unique,
  tx_hash text unique,
  idempotency_key text unique,
  delivery jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null default now() + interval '30 minutes',
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  settled_at timestamptz
);
grant all on public.founder_pack_purchases to service_role;
alter table public.founder_pack_purchases enable row level security;
create unique index if not exists founder_pack_one_per_user
  on public.founder_pack_purchases(user_id) where status in ('paid','settled');
create index if not exists founder_pack_purchases_user_idx on public.founder_pack_purchases(user_id, status);

create table if not exists public.player_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  code text not null,
  source text,
  equipped boolean not null default false,
  granted_at timestamptz not null default now(),
  unique (user_id, code)
);
grant all on public.player_entitlements to service_role;
alter table public.player_entitlements enable row level security;

-- ------------------------------ config helpers ------------------------------
create or replace function public.founder_pack_settings()
returns public.founder_pack_config language sql stable security definer set search_path to 'public' as $$
  select * from public.founder_pack_config where id
$$;

create or replace function public.founder_pack_snapshot()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare c public.founder_pack_config; v_season uuid;
begin
  c := public.founder_pack_settings();
  select id into v_season from public.season_pass_seasons where active order by created_at desc limit 1;
  return jsonb_build_object(
    'packVersion', c.pack_version, 'priceTon', c.price_ton,
    'seasonId', v_season, 'passTier', c.pass_tier,
    'mythAmount', c.myth_amount, 'heroKey', c.hero_key, 'petSlug', c.pet_slug,
    'equipmentChestCode', c.equipment_chest_code, 'fragments', c.fragments,
    'resourceChestCode', c.resource_chest_code, 'resourceChest', c.resource_chest,
    'badge', c.badge_enabled, 'frame', c.frame_enabled);
end $$;

-- ------------------------------ eligibility / state ------------------------------
create or replace function public.founder_pack_state(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u public.game_players; c public.founder_pack_config; v_owned boolean; v_expires timestamptz;
        v_eligible boolean; v_pending public.founder_pack_purchases; v_admin boolean;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  c := public.founder_pack_settings();
  select exists (select 1 from public.founder_pack_purchases
                  where user_id = u.id and status in ('paid','settled')) into v_owned;
  v_expires := u.created_at + make_interval(days => greatest(1, c.eligibility_days));
  v_eligible := c.enabled and not v_owned and now() < v_expires;
  v_admin := p_telegram_id = 8118569391;
  select * into v_pending from public.founder_pack_purchases
   where user_id = u.id and status = 'pending' and expires_at > now()
   order by created_at desc limit 1;

  return jsonb_build_object(
    'enabled', c.enabled,
    'show', v_eligible or (v_admin and c.enabled and not v_owned),
    'testMode', (v_admin and not v_eligible),
    'eligible', v_eligible,
    'purchased', v_owned,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'eligibilityDays', c.eligibility_days,
    'eligibleUntil', v_expires,
    'accountCreatedAt', u.created_at,
    'availableTon', round(coalesce(u.ton_balance, 0), 9),
    'mythAmount', c.myth_amount,
    'fragments', c.fragments,
    'passTier', c.pass_tier,
    'pendingOrder', case when v_pending.id is null then null else jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.amount_nano, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) end);
end $$;

-- ------------------------------ atomic delivery ------------------------------
create or replace function public.founder_pack_deliver(p_purchase_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o public.founder_pack_purchases; s jsonb; hc public.hero_catalog; pt public.pets;
        v_hero uuid; v_pet uuid; v_season uuid; v_delivery jsonb := '{}'::jsonb; v_res jsonb;
begin
  select * into o from public.founder_pack_purchases where id = p_purchase_id for update;
  if o.id is null then raise exception 'FOUNDER_PACK_ORDER_NOT_FOUND'; end if;
  if o.status = 'settled' then
    return jsonb_build_object('ok', true, 'alreadySettled', true, 'purchaseId', o.id, 'delivery', o.delivery);
  end if;
  if o.status <> 'paid' then raise exception 'FOUNDER_PACK_NOT_PAID'; end if;

  s := o.reward_snapshot;

  -- 1) Season Pass (current active version, official entitlement rules)
  v_season := nullif(s->>'seasonId','')::uuid;
  if v_season is null then
    select id into v_season from public.season_pass_seasons where active order by created_at desc limit 1;
  end if;
  if v_season is not null then
    perform public.season_pass_apply_entitlement(o.user_id, v_season, coalesce(s->>'passTier','legendary'));
    v_delivery := v_delivery || jsonb_build_object('pass', jsonb_build_object('seasonId', v_season, 'tier', coalesce(s->>'passTier','legendary')));
  end if;

  -- 2) MYTH balance (never grants a staking fee tier by itself)
  if coalesce((s->>'mythAmount')::numeric, 0) > 0 then
    insert into public.myth_balances(user_id, amount) values (o.user_id, 0) on conflict (user_id) do nothing;
    update public.myth_balances set amount = amount + (s->>'mythAmount')::numeric, updated_at = now() where user_id = o.user_id;
    insert into public.myth_ledger(user_id, direction, amount, reason)
      values (o.user_id, 'credit', (s->>'mythAmount')::numeric, 'founder_pack');
    v_delivery := v_delivery || jsonb_build_object('myth', (s->>'mythAmount')::numeric);
  end if;

  -- 3) Exclusive hero (no NFT mining attached)
  select * into hc from public.hero_catalog where hero_key = s->>'heroKey';
  if hc.hero_key is null then select * into hc from public.hero_catalog where rarity = 'mythic' order by random() limit 1; end if;
  if hc.hero_key is not null then
    insert into public.player_heroes(user_id, hero_key, name, rarity, level, image)
    values (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image)
    returning id into v_hero;
    v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object('id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name));
  end if;

  -- 4) Mythic pet
  select * into pt from public.pets where slug = s->>'petSlug' and not coalesce(is_nft_exclusive,false);
  if pt.id is null then
    select * into pt from public.pets where rarity = 'mythic' and not coalesce(is_nft_exclusive,false) order by random() limit 1;
  end if;
  if pt.id is not null then
    insert into public.player_pets(user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active)
    values (o.user_id, pt.id, public.normalize_pet_rarity(pt.rarity), 1, 0, 'baby', 0, false)
    returning id into v_pet;
    v_delivery := v_delivery || jsonb_build_object('pet', jsonb_build_object('id', v_pet, 'slug', pt.slug, 'name', pt.name));
  end if;

  -- 5) Legendary equipment chest (official inventory)
  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (o.user_id, 'hero_chest', coalesce(s->>'equipmentChestCode','legendary_chest'), 1)
  on conflict (user_id, item_type, item_code)
    do update set quantity = public.player_inventory.quantity + 1, updated_at = now();

  -- 6) Universal fragments (official source)
  if coalesce((s->>'fragments')::int, 0) > 0 then
    perform public.add_universal_fragments(o.user_id, (s->>'fragments')::int);
  end if;

  -- 7) Premium resource chest
  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (o.user_id, 'resource_chest', coalesce(s->>'resourceChestCode','premium_resource_chest'), 1)
  on conflict (user_id, item_type, item_code)
    do update set quantity = public.player_inventory.quantity + 1, updated_at = now();

  -- 8/9) Founder badge + frame (cosmetic entitlements)
  if coalesce((s->>'badge')::boolean, true) then
    insert into public.player_entitlements(user_id, code, source) values (o.user_id, 'founder_badge', 'founder_pack')
      on conflict (user_id, code) do nothing;
  end if;
  if coalesce((s->>'frame')::boolean, true) then
    insert into public.player_entitlements(user_id, code, source, equipped) values (o.user_id, 'founder_frame', 'founder_pack', true)
      on conflict (user_id, code) do nothing;
  end if;

  v_delivery := v_delivery || jsonb_build_object(
    'equipmentChest', coalesce(s->>'equipmentChestCode','legendary_chest'),
    'fragments', coalesce((s->>'fragments')::int, 0),
    'resourceChest', coalesce(s->>'resourceChestCode','premium_resource_chest'),
    'badge', coalesce((s->>'badge')::boolean, true),
    'frame', coalesce((s->>'frame')::boolean, true));

  update public.founder_pack_purchases
     set status = 'settled', settled_at = now(), delivery = v_delivery
   where id = o.id;

  insert into public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  values (o.user_id, 'founder_pack', 'FOUNDER PACK PURCHASED',
          'Your Founder Pack rewards have been delivered.', v_delivery, 'founder_pack:' || o.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
end $$;

-- ------------------------------ purchase entry point ------------------------------
create or replace function public.founder_pack_start_purchase(
  p_telegram_id bigint, p_wallet_address text, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.game_players; c public.founder_pack_config; st jsonb; o public.founder_pack_purchases;
        v_price numeric; v_nano text; s jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'INVALID_REQUEST'; end if;
  select * into u from public.game_players where telegram_id = p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if coalesce(u.banned,false) then raise exception 'PLAYER_BANNED'; end if;

  c := public.founder_pack_settings();
  if not c.enabled then raise exception 'FOUNDER_PACK_DISABLED'; end if;
  if exists (select 1 from public.founder_pack_purchases where user_id = u.id and status in ('paid','settled')) then
    raise exception 'FOUNDER_PACK_ALREADY_PURCHASED';
  end if;
  st := public.founder_pack_state(p_telegram_id);
  if not coalesce((st->>'eligible')::boolean, false) then raise exception 'FOUNDER_PACK_NOT_ELIGIBLE'; end if;

  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;
  s := public.founder_pack_snapshot();

  -- idempotency: same key returns the same order
  select * into o from public.founder_pack_purchases where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into o from public.founder_pack_purchases
     where user_id = u.id and status = 'pending' and expires_at > now() order by created_at desc limit 1;
  end if;
  if o.id is not null and o.status in ('paid','settled') then
    return jsonb_build_object('status','completed','method',o.payment_method,'purchaseId',o.id,
      'priceTon',o.price_ton,'delivery',o.delivery,'duplicate',true);
  end if;

  -- INTERNAL TON: only when it covers 100% of the price (never mixed with TonConnect)
  if round(coalesce(u.ton_balance,0), 9) >= round(v_price, 9) then
    update public.game_players set ton_balance = round(coalesce(ton_balance,0) - v_price, 9), updated_at = now()
     where id = u.id;
    if o.id is not null and o.status = 'pending' then
      update public.founder_pack_purchases
         set status = 'paid', payment_method = 'internal_ton', confirmed_at = now(),
             reward_snapshot = s, price_ton = v_price, amount_nano = v_nano
       where id = o.id returning * into o;
    else
      insert into public.founder_pack_purchases(user_id, telegram_id, pack_version, price_ton, amount_nano,
        reward_snapshot, payment_method, status, idempotency_key, confirmed_at)
      values (u.id, p_telegram_id, c.pack_version, v_price, v_nano, s, 'internal_ton', 'paid',
        p_idempotency_key, now())
      returning * into o;
    end if;
    perform public.founder_pack_deliver(o.id);
    select * into o from public.founder_pack_purchases where id = o.id;
    return jsonb_build_object('status','completed','method','internal_ton','purchaseId',o.id,
      'priceTon',v_price,'delivery',o.delivery,
      'state', public.founder_pack_state(p_telegram_id));
  end if;

  if o.id is not null and o.status = 'pending' then
    return jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
      'paymentAddress',o.payment_address,'amountNano',o.amount_nano,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(coalesce(u.ton_balance,0), 9));
  end if;

  insert into public.founder_pack_purchases(user_id, telegram_id, pack_version, price_ton, amount_nano,
    reward_snapshot, payment_method, status, payment_address, payment_comment, idempotency_key)
  values (u.id, p_telegram_id, c.pack_version, v_price, v_nano, s, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'forge_founder:' || gen_random_uuid(), p_idempotency_key)
  returning * into o;

  return jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
    'paymentAddress',o.payment_address,'amountNano',o.amount_nano,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(coalesce(u.ton_balance,0), 9));
end $$;

create or replace function public.founder_pack_pending_orders(p_telegram_id bigint)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'amountNano',o.amount_nano,
      'paymentComment',o.payment_comment,'paymentAddress',o.payment_address,'priceTon',o.price_ton)), '[]'::jsonb)
  from public.founder_pack_purchases o
  join public.game_players g on g.id = o.user_id
  where g.telegram_id = p_telegram_id and o.status = 'pending' and o.expires_at > now()
$$;

create or replace function public.founder_pack_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o public.founder_pack_purchases; v_min numeric;
begin
  if p_tx_hash is null or btrim(p_tx_hash) = '' then raise exception 'TX_HASH_REQUIRED'; end if;
  select * into o from public.founder_pack_purchases where id = p_order_id for update;
  if o.id is null then raise exception 'FOUNDER_PACK_ORDER_NOT_FOUND'; end if;
  if o.status = 'settled' then
    return jsonb_build_object('status','already_processed','purchaseId',o.id,'delivery',o.delivery);
  end if;
  if exists (select 1 from public.founder_pack_purchases where tx_hash = btrim(p_tx_hash) and id <> o.id) then
    raise exception 'TX_ALREADY_USED';
  end if;
  v_min := (o.amount_nano::numeric * 97) / 100;
  if coalesce(p_amount_nano::numeric, 0) < v_min then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;
  insert into public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  values (btrim(p_tx_hash), o.user_id, 'founder_pack', p_amount_nano::numeric, o.id::text)
  on conflict (tx_hash) do nothing;
  update public.founder_pack_purchases
     set status = 'paid', tx_hash = btrim(p_tx_hash), confirmed_at = coalesce(confirmed_at, now())
   where id = o.id;
  return public.founder_pack_deliver(o.id) || jsonb_build_object('status','completed','purchaseId',o.id);
end $$;

-- ------------------------------ founder frame equip toggle ------------------------------
create or replace function public.founder_frame_set(p_telegram_id bigint, p_equipped boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  update public.player_entitlements set equipped = coalesce(p_equipped,false)
   where user_id = u and code = 'founder_frame';
  if not found then raise exception 'FOUNDER_FRAME_NOT_OWNED'; end if;
  return jsonb_build_object('ok', true, 'equipped', coalesce(p_equipped,false));
end $$;

create or replace function public.get_player_entitlements(p_telegram_id bigint)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('code',e.code,'equipped',e.equipped,'grantedAt',e.granted_at)),'[]'::jsonb)
  from public.player_entitlements e join public.game_players g on g.id = e.user_id
  where g.telegram_id = p_telegram_id
$$;

-- ------------------------------ premium resource chest ------------------------------
create or replace function public.open_resource_chest(p_telegram_id bigint, p_inventory_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid; inv public.player_inventory; cfg jsonb; v_fc numeric; v_frag int; v_tickets int;
        v_chest text; v_chest_qty int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into inv from public.player_inventory where id = p_inventory_item_id and user_id = u for update;
  if inv.id is null or inv.quantity < 1 or inv.item_type <> 'resource_chest' then raise exception 'ITEM_NOT_FOUND'; end if;

  cfg := (public.founder_pack_settings()).resource_chest;
  v_fc := coalesce((cfg->>'fc')::numeric, 0);
  v_frag := coalesce((cfg->>'fragments')::int, 0);
  v_tickets := coalesce((cfg->>'pvp_tickets')::int, 0);
  v_chest := nullif(cfg->>'hero_chest','');
  v_chest_qty := coalesce((cfg->>'hero_chest_qty')::int, 0);

  update public.player_inventory set quantity = quantity - 1, updated_at = now() where id = inv.id;
  if v_fc > 0 or v_tickets > 0 then
    update public.game_players
       set forge_coins = coalesce(forge_coins,0) + v_fc,
           pvp_tickets = coalesce(pvp_tickets,0) + v_tickets,
           updated_at = now()
     where id = u;
  end if;
  if v_frag > 0 then perform public.add_universal_fragments(u, v_frag); end if;
  if v_chest is not null and v_chest_qty > 0 then
    insert into public.player_inventory(user_id, item_type, item_code, quantity)
    values (u, 'hero_chest', v_chest, v_chest_qty)
    on conflict (user_id, item_type, item_code)
      do update set quantity = public.player_inventory.quantity + v_chest_qty, updated_at = now();
  end if;

  return jsonb_build_object('rewards', jsonb_build_object('fc', v_fc, 'fragments', v_frag,
      'pvpTickets', v_tickets, 'heroChest', v_chest, 'heroChestQty', v_chest_qty),
    'inventory', public.get_player_inventory(p_telegram_id));
end $$;

-- ------------------------------ admin (Telegram bot) ------------------------------
create or replace function public.admin_founder_pack_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c public.founder_pack_config;
begin
  perform public.admin_assert(p_admin_id);
  c := public.founder_pack_settings();
  return jsonb_build_object(
    'enabled', c.enabled, 'priceTon', c.price_ton, 'eligibilityDays', c.eligibility_days,
    'mythAmount', c.myth_amount, 'passTier', c.pass_tier, 'heroKey', c.hero_key, 'petSlug', c.pet_slug,
    'equipmentChestCode', c.equipment_chest_code, 'fragments', c.fragments,
    'resourceChestCode', c.resource_chest_code, 'resourceChest', c.resource_chest,
    'badgeEnabled', c.badge_enabled, 'frameEnabled', c.frame_enabled, 'packVersion', c.pack_version,
    'purchases', (select count(*) from public.founder_pack_purchases where status = 'settled'),
    'tonRaised', (select coalesce(sum(price_ton),0) from public.founder_pack_purchases where status in ('paid','settled')),
    'activeIntents', (select count(*) from public.founder_pack_purchases where status = 'pending' and expires_at > now()),
    'failedIntents', (select count(*) from public.founder_pack_purchases where status = 'pending' and expires_at <= now()),
    'recent', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('purchaseId', o.id, 'player', g.display_name, 'telegramId', g.telegram_id,
          'method', o.payment_method, 'priceTon', o.price_ton, 'status', o.status,
          'packVersion', o.pack_version, 'createdAt', o.created_at, 'settledAt', o.settled_at) as x
        from public.founder_pack_purchases o join public.game_players g on g.id = o.user_id
        order by o.created_at desc limit 10) t));
end $$;

create or replace function public.admin_founder_pack_set(p_admin_id bigint, p_field text, p_value text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_num numeric;
begin
  perform public.admin_assert(p_admin_id);
  if p_field = 'enabled' then
    update public.founder_pack_config set enabled = (p_value in ('1','true','t')), updated_at = now() where id;
  elsif p_field = 'price' then
    v_num := p_value::numeric; if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
    update public.founder_pack_config set price_ton = v_num, pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'days' then
    v_num := p_value::numeric; if v_num < 1 then raise exception 'INVALID_VALUE'; end if;
    update public.founder_pack_config set eligibility_days = v_num::int, updated_at = now() where id;
  elsif p_field = 'myth' then
    update public.founder_pack_config set myth_amount = greatest(0, p_value::numeric), pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'fragments' then
    update public.founder_pack_config set fragments = greatest(0, p_value::int), pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'hero' then
    if not exists (select 1 from public.hero_catalog where hero_key = p_value) then raise exception 'HERO_NOT_FOUND'; end if;
    update public.founder_pack_config set hero_key = p_value, pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'pet' then
    if not exists (select 1 from public.pets where slug = p_value) then raise exception 'PET_NOT_FOUND'; end if;
    update public.founder_pack_config set pet_slug = p_value, pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'chest' then
    update public.founder_pack_config set equipment_chest_code = p_value, pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'pass' then
    if p_value not in ('adventurer','legendary') then raise exception 'INVALID_VALUE'; end if;
    update public.founder_pack_config set pass_tier = p_value, pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'resource' then
    update public.founder_pack_config set resource_chest = p_value::jsonb, pack_version = pack_version + 1, updated_at = now() where id;
  elsif p_field = 'badge' then
    update public.founder_pack_config set badge_enabled = (p_value in ('1','true','t')), updated_at = now() where id;
  elsif p_field = 'frame' then
    update public.founder_pack_config set frame_enabled = (p_value in ('1','true','t')), updated_at = now() where id;
  else raise exception 'UNKNOWN_FIELD';
  end if;
  perform public.admin_log(p_admin_id, 'founder_pack.set', 'config', p_field, null,
    jsonb_build_object('field', p_field, 'value', p_value), null);
  return public.admin_founder_pack_overview(p_admin_id);
end $$;

revoke execute on function public.founder_pack_settings() from anon, authenticated;
revoke execute on function public.founder_pack_snapshot() from anon, authenticated;
revoke execute on function public.founder_pack_state(bigint) from anon, authenticated;
revoke execute on function public.founder_pack_deliver(uuid) from anon, authenticated;
revoke execute on function public.founder_pack_start_purchase(bigint, text, text) from anon, authenticated;
revoke execute on function public.founder_pack_confirm_order(uuid, text, text) from anon, authenticated;
revoke execute on function public.founder_pack_pending_orders(bigint) from anon, authenticated;
revoke execute on function public.founder_frame_set(bigint, boolean) from anon, authenticated;
revoke execute on function public.get_player_entitlements(bigint) from anon, authenticated;
revoke execute on function public.open_resource_chest(bigint, uuid) from anon, authenticated;
revoke execute on function public.admin_founder_pack_overview(bigint) from anon, authenticated;
revoke execute on function public.admin_founder_pack_set(bigint, text, text) from anon, authenticated;