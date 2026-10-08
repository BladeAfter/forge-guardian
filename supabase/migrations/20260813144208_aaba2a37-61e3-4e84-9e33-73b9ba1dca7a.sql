alter table public.nft_pets
  add column if not exists price_ton numeric(18,9),
  add column if not exists tier_ton numeric(18,9),
  add column if not exists for_sale boolean not null default false;

create table if not exists public.nft_pet_orders(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  nft_pet_id uuid not null references public.nft_pets(id) on delete restrict,
  price_ton numeric(18,9) not null,
  amount_nano text not null,
  payment_address text not null,
  payment_comment text not null unique,
  idempotency_key text not null unique,
  status text not null default 'pending' check (status in ('pending','paid','confirmed','delivered','expired','cancelled')),
  tx_hash text unique,
  paid_at timestamptz,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz not null default now() + interval '30 minutes',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant all on public.nft_pet_orders to service_role;
alter table public.nft_pet_orders enable row level security;
create index if not exists nft_pet_orders_user_idx on public.nft_pet_orders(user_id, status);

create or replace function public.nft_pet_orders_touch() returns trigger language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists trg_nft_pet_orders_touch on public.nft_pet_orders;
create trigger trg_nft_pet_orders_touch before update on public.nft_pet_orders
for each row execute function public.nft_pet_orders_touch();

/* Shop payload for the player: sale data only, never any pool/treasury figure. */
create or replace function public.nft_shop_json(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid; s public.nft_pool_settings; items jsonb; total int; sold int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  s := public.nft_pool_settings_row();
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb), count(*),
         count(*) filter (where x->>'status' = 'SOLD_OUT')
    into items, total, sold
  from (
    select jsonb_build_object(
      'id', n.id,
      'serial', n.nft_serial,
      'instance', n.unique_instance_id,
      'name', pt.name,
      'slug', pt.slug,
      'image', coalesce(pt.image_adult_url, pt.image_young_url, pt.image_baby_url),
      'rarity', 'nft_exclusive',
      'priceTon', round(coalesce(n.price_ton, n.tier_ton, 20), 9),
      'tierTon', round(coalesce(n.tier_ton, 20), 9),
      'dailyYieldTon', round(case when coalesce(n.tier_ton, 20) >= 30 then s.tier30_daily_ton else s.tier20_daily_ton end, 9),
      'supply', 1,
      'status', case when n.status = 'AVAILABLE' and n.owner_user_id is null then 'AVAILABLE' else 'SOLD_OUT' end,
      'ownedByMe', (u is not null and n.owner_user_id = u),
      'passives', coalesce(pt.base_passives, '{}'::jsonb)
    ) as x
    from public.nft_pets n
    join public.pets pt on pt.id = n.pet_template_id
    where n.for_sale and n.status <> 'BURNED'
  ) q;
  return jsonb_build_object(
    'totalSupply', coalesce(total, 0),
    'sold', coalesce(sold, 0),
    'available', coalesce(total, 0) - coalesce(sold, 0),
    'items', items,
    'balanceTon', coalesce((select round(ton_balance, 9) from public.game_players where id = u), 0)
  );
end $$;

/* Single place that turns an available NFT into an owned pet + yield position. */
create or replace function public.nft_assign_unit(p_nft_id uuid, p_user_id uuid, p_source text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n public.nft_pets; pt public.pets; v_pp uuid;
begin
  select * into n from public.nft_pets where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_BURNED'; end if;
  if n.owner_user_id is not null then
    if n.owner_user_id = p_user_id then
      return jsonb_build_object('status', 'already_delivered', 'playerPetId', n.player_pet_id, 'serial', n.nft_serial);
    end if;
    raise exception 'NFT_ALREADY_OWNED';
  end if;
  select * into pt from public.pets where id = n.pet_template_id;

  insert into public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, tradable, market_locked, nft_pet_id)
  values (p_user_id, pt.id, pt.rarity, 1, 0, 'baby', 0, false, false, true, n.id)
  returning id into v_pp;

  update public.nft_pets
     set owner_user_id = p_user_id, player_pet_id = v_pp, status = 'OWNED',
         assigned_at = now(), revoked_at = null, for_sale = for_sale, updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('tier_ton', coalesce(tier_ton, 20))
   where id = n.id;

  insert into public.nft_pet_history (nft_pet_id, action, to_user_id, reason, metadata)
  values (n.id, 'PURCHASED', p_user_id, p_source, jsonb_build_object('serial', n.nft_serial, 'priceTon', n.price_ton));

  perform public.nft_pool_sync_positions();

  return jsonb_build_object('status', 'completed', 'playerPetId', v_pp, 'serial', n.nft_serial,
    'petName', pt.name, 'instance', n.unique_instance_id);
end $$;

/* Buy with the internal withdrawable TON balance (atomic, idempotent). */
create or replace function public.nft_buy_with_balance(p_telegram_id bigint, p_nft_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; n public.nft_pets; price numeric; done public.nft_pet_orders; res jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nft_buy:'||p_nft_id::text, 0));

  select * into done from public.nft_pet_orders where idempotency_key = p_idempotency_key;
  if done.id is not null then
    return jsonb_build_object('status', 'already_processed', 'orderId', done.id);
  end if;

  select * into n from public.nft_pets where id = p_nft_id for update;
  if n.id is null or not n.for_sale then raise exception 'NFT_NOT_FOR_SALE'; end if;
  if n.status <> 'AVAILABLE' or n.owner_user_id is not null then raise exception 'NFT_SOLD_OUT'; end if;
  price := round(coalesce(n.price_ton, n.tier_ton, 20), 9);

  insert into public.nft_pet_orders(user_id, nft_pet_id, price_ton, amount_nano, payment_address, payment_comment,
    idempotency_key, status, paid_at, confirmed_at)
  values (u, n.id, price, round(price * 1000000000)::text, 'internal_balance', 'internal:'||gen_random_uuid(),
    p_idempotency_key, 'confirmed', now(), now())
  returning * into done;

  perform public.debit_ton_balance(u, price, 'nft_purchase', done.id::text,
    format('NFT #%s purchase', n.nft_serial));

  res := public.nft_assign_unit(n.id, u, 'balance_purchase');
  update public.nft_pet_orders set status = 'delivered', delivered_at = now() where id = done.id;
  return res || jsonb_build_object('orderId', done.id, 'priceTon', price, 'paidWith', 'balance');
end $$;

/* TON Connect order: unique comment binds one payment to one NFT. */
create or replace function public.nft_create_order(p_telegram_id bigint, p_nft_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; n public.nft_pets; o public.nft_pet_orders; price numeric; address text;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into o from public.nft_pet_orders where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into n from public.nft_pets where id = p_nft_id for update;
    if n.id is null or not n.for_sale then raise exception 'NFT_NOT_FOR_SALE'; end if;
    if n.status <> 'AVAILABLE' or n.owner_user_id is not null then raise exception 'NFT_SOLD_OUT'; end if;
    price := round(coalesce(n.price_ton, n.tier_ton, 20), 9);
    address := public.wallet_hot_address();
    insert into public.nft_pet_orders(user_id, nft_pet_id, price_ton, amount_nano, payment_address, payment_comment, idempotency_key)
    values (u, n.id, price, round(price * 1000000000)::text, address, 'forge_nft:'||gen_random_uuid(), p_idempotency_key)
    returning * into o;
  end if;
  return jsonb_build_object('id', o.id, 'paymentAddress', o.payment_address, 'amountNano', o.amount_nano,
    'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
end $$;

create or replace function public.nft_deliver_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.nft_pet_orders; res jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('nft_order:'||p_order_id::text, 0));
  select * into o from public.nft_pet_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.delivered_at is not null then
    return jsonb_build_object('status', 'already_delivered', 'orderId', o.id);
  end if;
  if o.status not in ('paid','confirmed') then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
  res := public.nft_assign_unit(o.nft_pet_id, o.user_id, 'ton_purchase');
  update public.nft_pet_orders set status = 'delivered', delivered_at = now() where id = o.id;
  return res || jsonb_build_object('orderId', o.id, 'priceTon', o.price_ton, 'paidWith', 'ton');
end $$;

create or replace function public.nft_confirm_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.nft_pet_orders; v_expected numeric; v_received numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended('nft_order:'||p_order_id::text, 0));
  select * into o from public.nft_pet_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.tx_hash is null then
    if nullif(trim(coalesce(p_tx_hash, '')), '') is null then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
    v_expected := coalesce(nullif(o.amount_nano, '')::numeric, 0);
    v_received := coalesce(nullif(trim(coalesce(p_amount_nano, '')), '')::numeric, v_expected);
    if v_received < v_expected * 0.97 then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from public.nft_pet_orders where tx_hash = p_tx_hash and id <> o.id)
       or exists(select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
       or exists(select 1 from public.wallet_deposits where tx_hash = p_tx_hash)
       or exists(select 1 from public.season_pass_orders where tx_hash = p_tx_hash)
    then raise exception 'TX_ALREADY_USED'; end if;
    update public.nft_pet_orders
       set status = 'confirmed', tx_hash = p_tx_hash, paid_at = coalesce(paid_at, now()),
           confirmed_at = coalesce(confirmed_at, now())
     where id = o.id;
  end if;
  return public.nft_deliver_order(o.id);
end $$;

create or replace function public.nft_reconcile_orders(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; o record; res jsonb;
  delivered jsonb := '[]'::jsonb; already jsonb := '[]'::jsonb; results jsonb := '[]'::jsonb; pending jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  update public.nft_pet_orders set status = 'expired'
   where user_id = u and status = 'pending' and tx_hash is null and expires_at < now() - interval '2 hours';

  for o in select id from public.nft_pet_orders
            where user_id = u and tx_hash is not null and delivered_at is null
              and status in ('paid','confirmed') order by created_at loop
    begin
      res := public.nft_deliver_order(o.id);
      if res->>'status' = 'completed' then
        delivered := delivered || jsonb_build_array(o.id::text);
        results := results || jsonb_build_array(res);
      else already := already || jsonb_build_array(o.id::text);
      end if;
    exception when others then null;
    end;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('id', ord.id, 'paymentComment', ord.payment_comment,
      'amountNano', ord.amount_nano, 'priceTon', ord.price_ton, 'petName', pt.name) order by ord.created_at), '[]'::jsonb)
    into pending
  from public.nft_pet_orders ord
  join public.nft_pets n on n.id = ord.nft_pet_id
  join public.pets pt on pt.id = n.pet_template_id
  where ord.user_id = u and ord.status = 'pending' and ord.tx_hash is null and ord.expires_at > now() - interval '2 hours';

  return jsonb_build_object('delivered', delivered, 'alreadyDelivered', already, 'results', results, 'awaitingPayment', pending);
end $$;

revoke all on function public.nft_shop_json(bigint) from public, anon, authenticated;
revoke all on function public.nft_assign_unit(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.nft_buy_with_balance(bigint, uuid, text) from public, anon, authenticated;
revoke all on function public.nft_create_order(bigint, uuid, text) from public, anon, authenticated;
revoke all on function public.nft_deliver_order(uuid) from public, anon, authenticated;
revoke all on function public.nft_confirm_purchase(uuid, text, text) from public, anon, authenticated;
revoke all on function public.nft_reconcile_orders(bigint) from public, anon, authenticated;
grant execute on function public.nft_shop_json(bigint) to service_role;
grant execute on function public.nft_assign_unit(uuid, uuid, text) to service_role;
grant execute on function public.nft_buy_with_balance(bigint, uuid, text) to service_role;
grant execute on function public.nft_create_order(bigint, uuid, text) to service_role;
grant execute on function public.nft_deliver_order(uuid) to service_role;
grant execute on function public.nft_confirm_purchase(uuid, text, text) to service_role;
grant execute on function public.nft_reconcile_orders(bigint) to service_role;