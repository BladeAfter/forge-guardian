CREATE OR REPLACE FUNCTION public.market_finalize_purchase(p_listing_id uuid, p_buyer uuid, p_external boolean DEFAULT false, p_tx_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  l market_listings%rowtype; g game_players%rowtype; settings jsonb; cur text;
  fee_amount numeric; received numeric; hold_hours integer; tx_id uuid;
  risk jsonb; score integer; flags text[]; new_status text; value_fc numeric;
  buyer_before numeric; buyer_after numeric; pair_trades integer; pair_fc numeric;
  buy_today numeric; v5 integer; v24 integer; vel jsonb; pl jsonb; nal jsonb;
  ton_before numeric; is_admin boolean; settled_now boolean := false; fee_pct numeric;
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
      insert into market_security_audit(event, listing_id, buyer_user_id, seller_user_id, currency, price_fc, price_ton, risk_flags, details)
      values ('risk_flag', l.id, p_buyer, l.seller_user_id, cur, l.price_fc, l.price_ton, array['HIGH_VELOCITY'], jsonb_build_object('per5m', v5, 'per24h', v24));
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
    -- Fee ALWAYS comes from the backend config, never from the listing row or
    -- the API request, so a tampered fee (0%, 1%, ...) can never be honoured.
    fee_pct := coalesce((settings->>'feePercentTon')::numeric, 5);
    fee_amount := round(l.price_ton * fee_pct / 100, 9);
    received := round(l.price_ton - fee_amount, 9);
    hold_hours := 0;
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
    fee_pct := coalesce((settings->>'feePercent')::numeric, 5);
    fee_amount := round(l.price_fc * fee_pct / 100);
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
    perform market_item_give(p_buyer, l.item_code, l.snapshot, coalesce(l.quantity,1));
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
    fee_pct,
    case when cur = 'FC' then fee_amount else null end,
    case when cur = 'TON' then fee_amount else null end,
    case when cur = 'FC' then received else null end,
    case when cur = 'TON' then received else null end,
    l.snapshot, new_status, now() + make_interval(hours => hold_hours), score, flags, p_tx_hash)
  returning id into tx_id;

  insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, currency, price_fc, price_ton)
  values (l.item_type, l.item_instance_id, l.item_code, l.seller_user_id, p_buyer, l.id, tx_id, cur,
          case when cur = 'FC' then l.price_fc else null end,
          case when cur = 'TON' then l.price_ton else null end);

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

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, currency, price_ton, fee_ton, price_fc, fee_fc, risk_score, risk_flags, details)
  values ('sale_created', l.id, tx_id, p_buyer, l.seller_user_id, cur,
          case when cur = 'TON' then l.price_ton else null end,
          case when cur = 'TON' then fee_amount else null end,
          case when cur = 'FC' then l.price_fc else null end,
          case when cur = 'FC' then fee_amount else null end, score, flags,
          jsonb_build_object('status', new_status, 'currency', cur, 'price', coalesce(l.price_fc, l.price_ton),
                             'external', p_external, 'txHash', p_tx_hash,
                             'settleAt', now() + make_interval(hours => hold_hours)));

  -- TON sales have no hold: settle in the SAME transaction, so the seller's
  -- withdrawable TON balance is credited the moment the payment is confirmed.
  if cur = 'TON' and new_status = 'pending' then
    perform market_settle_transaction(tx_id, null);
    settled_now := true;
  end if;

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (l.seller_user_id, 'market_sale', 'MARKET',
    coalesce(l.snapshot->>'name','Item') || ' → ' ||
      case when cur = 'TON' then l.price_ton::text || ' TON' else l.price_fc::bigint::text || ' FC' end,
    case when cur = 'FC' then received else null end,
    jsonb_build_object('listingId', l.id, 'currency', cur, 'fee', fee_amount, 'holdHours', hold_hours,
                       'status', case when settled_now then 'settled' else 'pending' end),
    'market_sale:' || l.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'currency', cur,
    'pricePaid', coalesce(l.price_fc, l.price_ton), 'priceFc', l.price_fc, 'priceTon', l.price_ton,
    'feeFc', case when cur = 'FC' then fee_amount else null end,
    'feeTon', case when cur = 'TON' then fee_amount else null end,
    'sellerReceived', received, 'balanceFc', case when cur = 'FC' then buyer_after else g.forge_coins end,
    'balanceTon', case when cur = 'TON' then buyer_after else coalesce(g.ton_balance,0) end,
    'itemType', l.item_type, 'name', l.snapshot->>'name', 'settlementHours', hold_hours,
    'settledInstantly', settled_now,
    'transactionId', tx_id, 'underReview', new_status = 'review');
end $function$;