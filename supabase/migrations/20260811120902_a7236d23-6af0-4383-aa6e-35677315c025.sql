create or replace function public.create_season_pass_order(p_telegram_id bigint, p_tier text, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; s season_pass_seasons%rowtype; p player_season_pass%rowtype; o season_pass_orders%rowtype;
        price numeric; address text; upgrade boolean := false;
begin
  if p_tier not in ('adventurer','legendary') then raise exception 'INVALID_PASS_TIER'; end if;
  select id into u from game_players where telegram_id = p_telegram_id;
  select * into s from season_pass_seasons where active and now() between start_at and end_at;
  if u is null or s.id is null then raise exception 'SEASON_NOT_AVAILABLE'; end if;

  insert into player_season_pass(user_id, season_id, tier) values (u, s.id, 'none')
    on conflict (user_id, season_id) do nothing;
  select * into p from player_season_pass where user_id = u and season_id = s.id for update;

  -- Entitlement rules: adventurer only when nothing is owned; legendary while it is not owned yet.
  if p.tier = 'legendary' then raise exception 'PASS_ALREADY_OWNED'; end if;
  if p_tier = 'adventurer' and p.tier = 'adventurer' then raise exception 'PASS_ALREADY_OWNED'; end if;

  select * into o from season_pass_orders where idempotency_key = p_idempotency_key;
  if o.id is not null then
    return jsonb_build_object('id', o.id, 'tier', o.tier, 'paymentAddress', o.payment_address,
      'amountNano', o.amount_nano, 'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
  end if;

  upgrade := (p_tier = 'legendary' and p.tier = 'adventurer');
  price := case
    when p_tier = 'adventurer' then s.adventurer_price_ton
    when upgrade then greatest(s.legendary_price_ton - s.adventurer_price_ton, 0)
    else s.legendary_price_ton end;
  if price <= 0 then raise exception 'INVALID_PASS_PRICE'; end if;
  address := wallet_hot_address();

  insert into season_pass_orders(user_id, season_id, tier, price_ton, amount_nano, payment_address, payment_comment, idempotency_key)
  values (u, s.id, p_tier, price, round(price * 1000000000)::text, address, 'forge_pass:' || gen_random_uuid(), p_idempotency_key)
  returning * into o;

  return jsonb_build_object('id', o.id, 'tier', o.tier, 'upgrade', upgrade, 'paymentAddress', o.payment_address,
    'amountNano', o.amount_nano, 'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
end $$;

create or replace function public.confirm_season_pass_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o season_pass_orders%rowtype; p player_season_pass%rowtype; target text;
        expected numeric; received numeric;
begin
  if coalesce(trim(p_tx_hash), '') = '' then raise exception 'INVALID_TX_HASH'; end if;
  select * into o from season_pass_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;

  -- Idempotency: an activated order never activates a pass twice.
  if o.status = 'activated' then
    return jsonb_build_object('status', 'already_processed', 'orderId', o.id, 'tier', o.tier);
  end if;

  expected := o.amount_nano::numeric;
  received := coalesce(nullif(trim(p_amount_nano), '')::numeric, 0);
  -- Network/wallet fees: accept up to 3% below the expected amount.
  if received < expected * 0.97 then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  -- One blockchain transaction can only ever pay for one operation.
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

  -- The ORDER decides what gets activated. Legendary is never downgraded.
  target := case when o.tier = 'legendary' or p.tier = 'legendary' then 'legendary' else 'adventurer' end;

  update season_pass_orders
     set status = 'paid', tx_hash = p_tx_hash, paid_at = coalesce(paid_at, now())
   where id = o.id;

  -- XP, level and claimed rewards are untouched: only ownership changes.
  update player_season_pass
     set tier = target,
         adventurer_owned = true,
         legendary_owned = (target = 'legendary') or legendary_owned,
         purchased_at = coalesce(purchased_at, now()),
         upgraded_at = case when target = 'legendary' and p.tier = 'adventurer' then now() else upgraded_at end,
         updated_at = now()
   where user_id = o.user_id and season_id = o.season_id;

  update season_pass_orders set status = 'activated', activated_at = now() where id = o.id;
  perform record_ton_revenue(o.user_id, o.price_ton, 'battle_pass', o.id::text, p_tx_hash);
  return jsonb_build_object('status', 'completed', 'orderId', o.id, 'tier', target, 'priceTon', o.price_ton);
end $$;

create or replace function public.pending_season_pass_orders(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'tier', o.tier, 'priceTon', o.price_ton, 'amountNano', o.amount_nano,
      'paymentComment', o.payment_comment, 'status', o.status, 'createdAt', o.created_at
    ) order by o.created_at desc), '[]')
    from season_pass_orders o
    where o.user_id = u
      and o.status in ('pending', 'paid', 'expired')
      and o.created_at > now() - interval '30 days');
end $$;

revoke all on function public.create_season_pass_order(bigint, text, text) from public, anon, authenticated;
revoke all on function public.confirm_season_pass_order(uuid, text, text) from public, anon, authenticated;
revoke all on function public.pending_season_pass_orders(bigint) from public, anon, authenticated;
grant execute on function public.create_season_pass_order(bigint, text, text) to service_role;
grant execute on function public.confirm_season_pass_order(uuid, text, text) to service_role;
grant execute on function public.pending_season_pass_orders(bigint) to service_role;