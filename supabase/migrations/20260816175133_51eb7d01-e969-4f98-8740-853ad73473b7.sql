-- Any paid pass order (first purchase OR upgrade) grants the CURRENT entitlement (V2)
CREATE OR REPLACE FUNCTION public.confirm_season_pass_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare o season_pass_orders%rowtype; p player_season_pass%rowtype; target text;
        expected numeric; received numeric; v_ver int; v_prev int; v_expires timestamptz;
begin
  if coalesce(trim(p_tx_hash), '') = '' then raise exception 'INVALID_TX_HASH'; end if;
  select * into o from season_pass_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;

  if o.status = 'activated' then
    return jsonb_build_object('status', 'already_processed', 'orderId', o.id, 'tier', o.tier);
  end if;

  expected := o.amount_nano::numeric;
  received := coalesce(nullif(trim(p_amount_nano), '')::numeric, 0);
  if received < expected * 0.97 then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  if exists (select 1 from processed_ton_transactions where tx_hash = p_tx_hash
             and not (transaction_type = 'battle_pass' and reference_id = o.id::text)) then
    raise exception 'TX_ALREADY_USED';
  end if;
  if exists (select 1 from season_pass_orders where tx_hash = p_tx_hash and id <> o.id) then
    raise exception 'TX_ALREADY_USED';
  end if;
  insert into processed_ton_transactions(tx_hash, transaction_type, reference_id, user_id, amount_nano)
  values (p_tx_hash, 'battle_pass', o.id::text, o.user_id, received)
  on conflict (tx_hash) do nothing;

  insert into player_season_pass(user_id, season_id, tier) values (o.user_id, o.season_id, 'none')
    on conflict (user_id, season_id) do nothing;
  select * into p from player_season_pass where user_id = o.user_id and season_id = o.season_id for update;

  target := case when o.tier = 'legendary' or p.tier = 'legendary' then 'legendary' else 'adventurer' end;

  -- Every paid order upgrades the entitlement to the current pass version (V2).
  v_prev := coalesce(p.pass_version, 1);
  v_ver := greatest(v_prev, 2);
  if p.tier = 'none' or v_ver > v_prev then
    v_expires := greatest(coalesce(p.expires_at, now()), now()) + interval '30 days';
  else
    v_expires := p.expires_at;
  end if;

  update season_pass_orders
     set status = 'paid', tx_hash = p_tx_hash, paid_at = coalesce(paid_at, now())
   where id = o.id;

  update player_season_pass
     set tier = target,
         pass_version = v_ver,
         expires_at = v_expires,
         adventurer_owned = true,
         legendary_owned = (target = 'legendary') or legendary_owned,
         purchased_at = coalesce(purchased_at, now()),
         upgraded_at = case when target = 'legendary' and p.tier = 'adventurer' then now() else upgraded_at end,
         updated_at = now()
   where user_id = o.user_id and season_id = o.season_id;

  update season_pass_orders set status = 'activated', activated_at = now() where id = o.id;
  perform record_ton_revenue(o.user_id, o.price_ton, 'battle_pass', o.id::text, p_tx_hash);
  return jsonb_build_object('status', 'completed', 'orderId', o.id, 'tier', target,
    'priceTon', o.price_ton, 'passVersion', v_ver, 'previousPassVersion', v_prev, 'expiresAt', v_expires);
end $function$;