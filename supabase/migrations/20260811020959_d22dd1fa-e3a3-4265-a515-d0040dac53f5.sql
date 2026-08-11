-- 1. Estados oficiais do pedido
alter table public.pet_egg_orders drop constraint if exists pet_egg_orders_status_check;
alter table public.pet_egg_orders add constraint pet_egg_orders_status_check
  check (status = any (array['pending','paid','confirmed','delivered','expired','cancelled']));

alter table public.pet_egg_orders add column if not exists confirmed_at timestamptz;
update public.pet_egg_orders set confirmed_at = coalesce(confirmed_at, paid_at) where paid_at is not null;

-- 2. Encerra pedidos antigos que nunca receberam pagamento
create or replace function public.expire_stale_pet_egg_orders(p_user_id uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  with x as (
    update public.pet_egg_orders
      set status='expired'
      where status='pending' and tx_hash is null and expires_at < now()
        and (p_user_id is null or user_id=p_user_id)
      returning 1)
  select count(*) into n from x;
  return coalesce(n,0);
end $$;

-- 3. Entrega idempotente (uma criatura por pedido pago)
create or replace function public.deliver_pet_egg_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.pet_egg_orders%rowtype; tg bigint; key text; res jsonb; pool jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('pet_egg_order:'||p_order_id::text, 0));
  select * into o from public.pet_egg_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  select telegram_id into tg from public.game_players where id=o.user_id;
  if tg is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if o.tx_hash is null then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
  key := 'egg_order:'||o.id::text;

  -- Pool: 15% da receita TON, registrado uma única vez por pedido/tx.
  pool := public.record_ton_revenue(o.user_id, o.price_ton, 'egg_purchase', o.id::text, o.tx_hash);

  res := public.get_pet_egg_opening(tg, key);
  if coalesce(res->>'status','') <> 'not_found' then
    if o.status <> 'delivered' then
      update public.pet_egg_orders set status='delivered', delivered_at=coalesce(delivered_at, now()) where id=o.id;
    end if;
    return jsonb_build_object('status','already_delivered','orderId',o.id,'eggId',o.egg_id,'poolContribution',pool)||res;
  end if;

  res := public.hatch_pet_egg(tg, o.egg_id, key);
  update public.pet_egg_orders set status='delivered', delivered_at=now() where id=o.id;
  return jsonb_build_object('status','completed','orderId',o.id,'eggId',o.egg_id,'poolContribution',pool)||res;
end $$;

-- 4. Confirmação de pagamento: vincula a tx ao pedido e entrega em seguida
create or replace function public.confirm_pet_egg_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.pet_egg_orders%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('pet_egg_order:'||p_order_id::text, 0));
  select * into o from public.pet_egg_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;

  if o.tx_hash is null then
    if nullif(trim(coalesce(p_tx_hash,'')),'') is null then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
    if p_amount_nano is not null and p_amount_nano <> o.amount_nano then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from public.pet_egg_orders where tx_hash=p_tx_hash and id<>o.id)
       or exists(select 1 from public.wallet_deposits where tx_hash=p_tx_hash) then raise exception 'TX_ALREADY_USED'; end if;
    update public.pet_egg_orders
      set status='confirmed', tx_hash=p_tx_hash, paid_at=coalesce(paid_at, now()), confirmed_at=coalesce(confirmed_at, now())
      where id=o.id;
  end if;

  return public.deliver_pet_egg_order(o.id);
end $$;

-- 5. Fila de verificação: apenas pedidos realmente aguardando pagamento
create or replace function public.pending_pet_egg_orders(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  select id into u from public.game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.expire_stale_pet_egg_orders(u);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id',o.id,'eggId',o.egg_id,'eggName',e.name,'priceTon',o.price_ton,'amountNano',o.amount_nano,
      'paymentComment',o.payment_comment,'status',o.status,'createdAt',o.created_at) order by o.created_at desc),'[]')
    from public.pet_egg_orders o join public.pet_eggs e on e.id=o.egg_id
    where o.user_id=u and o.status='pending' and o.tx_hash is null and o.expires_at>=now());
end $$;

-- 6. Reconciliação: entrega o que já foi pago e lista o que falta pagar
create or replace function public.reconcile_pet_egg_orders(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; o record; res jsonb;
  delivered jsonb := '[]'::jsonb; already jsonb := '[]'::jsonb; results jsonb := '[]'::jsonb;
begin
  select id into u from public.game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.expire_stale_pet_egg_orders(u);

  for o in select ord.id, e.name as egg_name, ord.price_ton
             from public.pet_egg_orders ord join public.pet_eggs e on e.id=ord.egg_id
            where ord.user_id=u and ord.tx_hash is not null
              and (ord.status in ('paid','confirmed') or ord.delivered_at is null)
            order by ord.created_at loop
    res := public.deliver_pet_egg_order(o.id) || jsonb_build_object('eggName',o.egg_name,'priceTon',o.price_ton);
    if res->>'status' = 'completed' then delivered := delivered || jsonb_build_array(o.id::text);
      results := results || jsonb_build_array(res);
    else already := already || jsonb_build_array(o.id::text);
    end if;
  end loop;

  return jsonb_build_object(
    'delivered', delivered,
    'alreadyDelivered', already,
    'results', results,
    'awaitingPayment', public.pending_pet_egg_orders(p_telegram_id));
end $$;

-- 7. Recuperação dos pedidos já pagos que nunca entregaram a criatura
do $$
declare r record;
begin
  for r in select o.id from public.pet_egg_orders o
            where o.tx_hash is not null
              and not exists (select 1 from public.pet_hatch_history h where h.idempotency_key='egg_order:'||o.id::text) loop
    begin
      perform public.deliver_pet_egg_order(r.id);
    exception when others then
      raise notice 'egg order recovery failed: % %', r.id, sqlerrm;
    end;
  end loop;
end $$;

select public.expire_stale_pet_egg_orders(null);

grant execute on function public.deliver_pet_egg_order(uuid) to service_role;
grant execute on function public.reconcile_pet_egg_orders(bigint) to service_role;
grant execute on function public.expire_stale_pet_egg_orders(uuid) to service_role;
