CREATE OR REPLACE FUNCTION public.deliver_pet_egg_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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

  -- The paid product IS the egg: grant it to the player, then open it in the same transaction.
  -- Guarded by the opening idempotency key above, so a payment can never grant two eggs.
  insert into public.player_pet_inventory(user_id, item_type, item_id, quantity, updated_at)
  values (o.user_id, 'egg', o.egg_id, 1, now())
  on conflict (user_id, item_type, coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set quantity = public.player_pet_inventory.quantity + 1, updated_at = now();

  res := public.hatch_pet_egg(tg, o.egg_id, key);
  update public.pet_egg_orders set status='delivered', delivered_at=now() where id=o.id;
  return jsonb_build_object('status','completed','orderId',o.id,'eggId',o.egg_id,'poolContribution',pool)||res;
end $$;

REVOKE ALL ON FUNCTION public.deliver_pet_egg_order(uuid) FROM PUBLIC, anon, authenticated;