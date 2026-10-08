
insert into public.game_settings(key, value, category, label)
values ('pass_locked_reward', jsonb_build_object('enabled', true, 'price_ton', 2.5), 'season_pass', 'Preço para desbloquear recompensa de passe antigo (TON)')
on conflict (key) do nothing;

create table if not exists public.pass_locked_reward_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  telegram_id bigint not null,
  reward_id uuid not null references public.season_pass_rewards(id) on delete cascade,
  season_id uuid,
  price_ton numeric not null,
  amount_nano text not null,
  payment_address text,
  payment_comment text,
  status text not null default 'pending',
  method text not null default 'ton_connect',
  tx_hash text unique,
  idempotency_key text unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 minutes',
  delivered_at timestamptz
);
create index if not exists pass_locked_reward_orders_user_idx on public.pass_locked_reward_orders(user_id, status);

grant all on public.pass_locked_reward_orders to service_role;
alter table public.pass_locked_reward_orders enable row level security;

create or replace function public.pass_locked_reward_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select value from game_settings where key = 'pass_locked_reward'),
                  jsonb_build_object('enabled', true, 'price_ton', 2.5));
$$;

-- Delivers the exclusive chest of a locked pass reward (idempotent per order).
create or replace function public.pass_locked_reward_deliver(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o pass_locked_reward_orders%rowtype; r season_pass_rewards%rowtype;
begin
  select * into o from pass_locked_reward_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.delivered_at is not null then return jsonb_build_object('ok', true, 'alreadyDelivered', true); end if;
  select * into r from season_pass_rewards where id = o.reward_id;
  if r.id is null then raise exception 'REWARD_NOT_FOUND'; end if;

  insert into player_inventory(user_id, item_type, item_code, quantity, is_exclusive, season_id, pass_tier, exclusive_reward_code, tradable)
  values (o.user_id, 'exclusive_chest', r.reward_code, greatest(1, coalesce(r.amount,1)), true, r.season_id, r.tier, r.reward_code, false)
  on conflict (user_id, item_type, item_code)
    do update set quantity = player_inventory.quantity + greatest(1, coalesce(r.amount,1)), updated_at = now();

  update pass_locked_reward_orders set status = 'completed', delivered_at = now() where id = o.id;
  return jsonb_build_object('ok', true, 'rewardId', r.id, 'itemCode', r.reward_code);
end $$;

-- Starts the unlock: internal TON balance pays instantly, otherwise a TonConnect intent is returned.
create or replace function public.buy_pass_locked_reward(
  p_telegram_id bigint, p_reward_id uuid, p_wallet_address text, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u game_players%rowtype; r season_pass_rewards%rowtype; p player_season_pass%rowtype;
        cfg jsonb; v_price numeric; v_ver int; o pass_locked_reward_orders%rowtype;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'INVALID_REQUEST'; end if;
  select * into u from game_players where telegram_id = p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if coalesce(u.banned,false) then raise exception 'PLAYER_BANNED'; end if;

  cfg := pass_locked_reward_config();
  if not coalesce((cfg->>'enabled')::boolean, true) then raise exception 'LOCKED_REWARD_PURCHASE_DISABLED'; end if;
  v_price := coalesce((cfg->>'price_ton')::numeric, 2.5);
  if v_price <= 0 then raise exception 'INVALID_PRICE'; end if;

  select * into r from season_pass_rewards where id = p_reward_id and enabled;
  if r.id is null then raise exception 'REWARD_NOT_FOUND'; end if;
  select * into p from player_season_pass where user_id = u.id and season_id = r.season_id;
  v_ver := case when coalesce(p.tier,'none') = 'none' then 2 else coalesce(p.pass_version, 1) end;
  if coalesce(r.min_pass_version,1) <= v_ver then raise exception 'REWARD_NOT_LOCKED'; end if;

  select * into o from pass_locked_reward_orders where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into o from pass_locked_reward_orders
      where user_id = u.id and reward_id = r.id and status = 'pending' and expires_at > now()
      order by created_at desc limit 1;
  end if;
  if o.id is not null and o.status = 'pending' then
    return jsonb_build_object('status','payment_required','method','ton_connect','orderId', o.id,
      'paymentAddress', o.payment_address, 'amountNano', o.amount_nano, 'amountTon', o.price_ton,
      'paymentComment', o.payment_comment, 'expiresAt', o.expires_at, 'priceTon', o.price_ton);
  end if;

  -- 1) Internal TON balance covers 100% of the price: instant unlock.
  if round(coalesce(u.ton_balance,0), 9) >= round(v_price, 9) then
    update game_players set ton_balance = round(coalesce(ton_balance,0) - v_price, 9), updated_at = now() where id = u.id;
    insert into pass_locked_reward_orders(user_id, telegram_id, reward_id, season_id, price_ton, amount_nano,
      status, method, idempotency_key)
    values (u.id, p_telegram_id, r.id, r.season_id, v_price, round(v_price*1000000000)::text,
      'paid', 'internal_ton', p_idempotency_key)
    returning * into o;
    perform pass_locked_reward_deliver(o.id);
    return jsonb_build_object('status','completed','method','internal_ton','orderId', o.id,
      'priceTon', v_price, 'itemCode', r.reward_code,
      'dashboard', get_season_pass_dashboard(p_telegram_id),
      'inventory', get_player_inventory(p_telegram_id));
  end if;

  -- 2) TonConnect: the payment is tied to THIS order by its unique comment.
  insert into pass_locked_reward_orders(user_id, telegram_id, reward_id, season_id, price_ton, amount_nano,
    payment_address, payment_comment, status, method, idempotency_key)
  values (u.id, p_telegram_id, r.id, r.season_id, v_price, round(v_price*1000000000)::text,
    wallet_hot_address(), 'forge_passchest:' || gen_random_uuid(), 'pending', 'ton_connect', p_idempotency_key)
  returning * into o;

  return jsonb_build_object('status','payment_required','method','ton_connect','orderId', o.id,
    'paymentAddress', o.payment_address, 'amountNano', o.amount_nano, 'amountTon', o.price_ton,
    'paymentComment', o.payment_comment, 'expiresAt', o.expires_at, 'priceTon', v_price,
    'availableTon', round(coalesce(u.ton_balance,0), 9));
end $$;

create or replace function public.pending_pass_locked_reward_orders(p_telegram_id bigint)
returns setof jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('id', o.id, 'amountNano', o.amount_nano, 'priceTon', o.price_ton,
    'paymentComment', o.payment_comment, 'rewardId', o.reward_id)
  from pass_locked_reward_orders o
  join game_players g on g.id = o.user_id
  where g.telegram_id = p_telegram_id and o.status = 'pending' and o.payment_comment is not null
  order by o.created_at;
$$;

create or replace function public.confirm_pass_locked_reward_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o pass_locked_reward_orders%rowtype; v_min numeric;
begin
  select * into o from pass_locked_reward_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status = 'completed' then return jsonb_build_object('status','already_processed','orderId', o.id); end if;
  if exists (select 1 from pass_locked_reward_orders where tx_hash = p_tx_hash and id <> o.id) then
    raise exception 'TX_ALREADY_USED';
  end if;
  v_min := (o.amount_nano::numeric * 97) / 100;
  if coalesce(p_amount_nano::numeric, 0) < v_min then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;
  update pass_locked_reward_orders set tx_hash = p_tx_hash, status = 'paid' where id = o.id;
  perform pass_locked_reward_deliver(o.id);
  return jsonb_build_object('status','completed','orderId', o.id, 'priceTon', o.price_ton);
end $$;

grant execute on function public.pass_locked_reward_config() to service_role;
grant execute on function public.buy_pass_locked_reward(bigint, uuid, text, text) to service_role;
grant execute on function public.pending_pass_locked_reward_orders(bigint) to service_role;
grant execute on function public.confirm_pass_locked_reward_order(uuid, text, text) to service_role;
