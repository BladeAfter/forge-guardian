create or replace function public.confirm_pet_egg_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o pet_egg_orders%rowtype; tg bigint; key text; res jsonb; needs_credit boolean;
begin
  select * into o from pet_egg_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  select telegram_id into tg from game_players where id=o.user_id;
  if tg is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  key:='egg_order:'||o.id::text;

  -- One payment can only ever produce one pet: an existing hatch for this order wins.
  res:=public.get_pet_egg_opening(tg,key);
  if coalesce(res->>'status','')<>'not_found' then
    if o.status<>'delivered' then update pet_egg_orders set status='delivered',delivered_at=coalesce(delivered_at,now()),tx_hash=coalesce(tx_hash,p_tx_hash) where id=o.id; end if;
    return jsonb_build_object('status','already_processed','orderId',o.id,'eggId',o.egg_id)||res;
  end if;

  if o.status in ('pending','expired') then
    if p_amount_nano is not null and p_amount_nano<>o.amount_nano then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from pet_egg_orders where tx_hash=p_tx_hash and id<>o.id)
      or exists(select 1 from wallet_deposits where tx_hash=p_tx_hash) then raise exception 'TX_ALREADY_USED'; end if;
    update pet_egg_orders set status='paid',tx_hash=p_tx_hash,paid_at=now() where id=o.id;
    needs_credit:=true;
  elsif o.status='paid' then
    needs_credit:=true;
  elsif o.status='delivered' then
    -- Legacy flow already pushed the egg into the inventory; hatch that copy instead of adding another.
    needs_credit:=false;
  else
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  if needs_credit then
    insert into player_pet_inventory(user_id,item_type,item_id,quantity) values(o.user_id,'egg',o.egg_id,1)
    on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
    do update set quantity=player_pet_inventory.quantity+1,updated_at=now();
  end if;

  res:=public.hatch_pet_egg(tg,o.egg_id,key);
  update pet_egg_orders set status='delivered',delivered_at=now() where id=o.id;
  return jsonb_build_object('status','completed','orderId',o.id,'eggId',o.egg_id)||res;
end $$;

revoke all on function public.confirm_pet_egg_purchase(uuid,text,text) from public, anon, authenticated;
grant execute on function public.confirm_pet_egg_purchase(uuid,text,text) to service_role;

-- Pending TON egg purchases of one player, for the on-chain reconciler.
create or replace function public.pending_pet_egg_orders(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u uuid;
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id',o.id,'eggId',o.egg_id,'eggName',e.name,'priceTon',o.price_ton,'amountNano',o.amount_nano,
      'paymentComment',o.payment_comment,'status',o.status,'createdAt',o.created_at)order by o.created_at desc),'[]')
    from pet_egg_orders o join pet_eggs e on e.id=o.egg_id
    where o.user_id=u and o.status in ('pending','paid','expired')
      and o.created_at > now() - interval '30 days');
end $$;

revoke all on function public.pending_pet_egg_orders(bigint) from public, anon, authenticated;
grant execute on function public.pending_pet_egg_orders(bigint) to service_role;