CREATE OR REPLACE FUNCTION public.confirm_pet_egg_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare o public.pet_egg_orders%rowtype; tg bigint; key text; res jsonb; needs_credit boolean; pool jsonb;
begin
  select * into o from public.pet_egg_orders where id=p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  select telegram_id into tg from public.game_players where id=o.user_id;
  if tg is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  key:='egg_order:'||o.id::text;

  res:=public.get_pet_egg_opening(tg,key);
  if coalesce(res->>'status','')<>'not_found' then
    if o.status<>'delivered' then update public.pet_egg_orders set status='delivered',delivered_at=coalesce(delivered_at,now()),tx_hash=coalesce(tx_hash,p_tx_hash) where id=o.id; end if;
    pool:=public.record_ton_revenue(o.user_id,o.price_ton,'egg_purchase',o.id::text,coalesce(o.tx_hash,p_tx_hash));
    return jsonb_build_object('status','already_processed','orderId',o.id,'eggId',o.egg_id,'poolContribution',pool)||res;
  end if;

  if o.status in ('pending','expired') then
    if p_amount_nano is not null and p_amount_nano<>o.amount_nano then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
    if exists(select 1 from public.pet_egg_orders where tx_hash=p_tx_hash and id<>o.id)
      or exists(select 1 from public.wallet_deposits where tx_hash=p_tx_hash) then raise exception 'TX_ALREADY_USED'; end if;
    update public.pet_egg_orders set status='paid',tx_hash=p_tx_hash,paid_at=now() where id=o.id;
    needs_credit:=true;
  elsif o.status='paid' then
    needs_credit:=true;
  elsif o.status='delivered' then
    needs_credit:=false;
  else
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  if needs_credit then
    insert into public.player_pet_inventory(user_id,item_type,item_id,quantity) values(o.user_id,'egg',o.egg_id,1)
    on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
    do update set quantity=player_pet_inventory.quantity+1,updated_at=now();
  end if;

  res:=public.hatch_pet_egg(tg,o.egg_id,key);
  update public.pet_egg_orders set status='delivered',delivered_at=now() where id=o.id;
  pool:=public.record_ton_revenue(o.user_id,o.price_ton,'egg_purchase',o.id::text,coalesce(p_tx_hash,o.tx_hash));
  return jsonb_build_object('status','completed','orderId',o.id,'eggId',o.egg_id,'poolContribution',pool)||res;
end
$$;
