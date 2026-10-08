-- Purchase: 100% internal TON or 100% TonConnect (never mixed), with pool reservation.
create or replace function public.veteran_vault_start_purchase(p_telegram_id bigint, p_wallet_address text, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.game_players; c public.veteran_vault_config; st jsonb; o public.veteran_vault_purchases;
        v_price numeric; v_nano text; s jsonb; v_ton_budget numeric; v_myth_budget numeric;
        p public.veteran_vault_pool; v_av_ton numeric; v_av_myth numeric;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'INVALID_REQUEST'; end if;
  select * into u from public.game_players where telegram_id = p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if coalesce(u.banned,false) then raise exception 'PLAYER_BANNED'; end if;

  c := public.veteran_vault_settings();
  if not c.enabled then raise exception 'VETERAN_VAULT_DISABLED'; end if;
  if c.sales_paused then raise exception 'VETERAN_VAULT_SALES_PAUSED'; end if;
  if exists (select 1 from public.veteran_vault_purchases
              where user_id = u.id and vault_version = c.vault_version and status in ('paid','settled')) then
    raise exception 'VETERAN_VAULT_ALREADY_PURCHASED';
  end if;
  st := public.veteran_vault_state(p_telegram_id);
  if not coalesce((st->>'veteran')::boolean, false) then raise exception 'VETERAN_VAULT_NOT_ELIGIBLE'; end if;

  v_ton_budget := public.veteran_vault_ton_budget();
  v_myth_budget := public.veteran_vault_myth_budget();
  select * into p from public.veteran_vault_pool where id for update;
  v_av_ton := coalesce(p.ton_funded,0) - coalesce(p.ton_reserved,0) - coalesce(p.ton_distributed,0);
  v_av_myth := coalesce(p.myth_funded,0) - coalesce(p.myth_reserved,0) - coalesce(p.myth_distributed,0);
  if v_av_ton < v_ton_budget or v_av_myth < v_myth_budget then raise exception 'VETERAN_VAULT_SOLD_OUT'; end if;

  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;
  s := public.veteran_vault_snapshot();

  select * into o from public.veteran_vault_purchases where idempotency_key = p_idempotency_key;
  if o.id is null then
    select * into o from public.veteran_vault_purchases
     where user_id = u.id and status = 'pending' and expires_at > now() order by created_at desc limit 1;
  end if;
  if o.id is not null and o.status in ('paid','settled') then
    return jsonb_build_object('status','completed','method',o.payment_method,'purchaseId',o.id,
      'priceTon',o.price_ton,'delivery',o.delivery,'duplicate',true,'state',public.veteran_vault_state(p_telegram_id));
  end if;

  -- INTERNAL TON: only when it covers 100% of the price
  if round(coalesce(u.ton_balance,0), 9) >= round(v_price, 9) then
    update public.game_players set ton_balance = round(coalesce(ton_balance,0) - v_price, 9), updated_at = now()
     where id = u.id;
    if o.id is not null and o.status = 'pending' then
      update public.veteran_vault_purchases
         set status='paid', payment_method='internal_ton', confirmed_at=now(), reward_snapshot=s,
             price_ton=v_price, amount_nano=v_nano, vault_version=c.vault_version,
             ton_reserved=v_ton_budget, myth_reserved=v_myth_budget
       where id = o.id returning * into o;
    else
      insert into public.veteran_vault_purchases(user_id, telegram_id, vault_version, price_ton, amount_nano,
        reward_snapshot, payment_method, status, idempotency_key, confirmed_at, ton_reserved, myth_reserved)
      values (u.id, p_telegram_id, c.vault_version, v_price, v_nano, s, 'internal_ton', 'paid',
        p_idempotency_key, now(), v_ton_budget, v_myth_budget)
      returning * into o;
    end if;
    update public.veteran_vault_pool
       set ton_reserved = ton_reserved + v_ton_budget, myth_reserved = myth_reserved + v_myth_budget,
           updated_at = now() where id;
    insert into public.veteran_vault_ledger(purchase_id, user_id, kind, ton_amount, note)
      values (o.id, u.id, 'purchase_internal', v_price, 'veteran vault paid with internal TON');
    perform public.veteran_vault_deliver(o.id);
    select * into o from public.veteran_vault_purchases where id = o.id;
    return jsonb_build_object('status','completed','method','internal_ton','purchaseId',o.id,
      'priceTon',v_price,'delivery',o.delivery,'state',public.veteran_vault_state(p_telegram_id));
  end if;

  if o.id is not null and o.status = 'pending' then
    return jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
      'paymentAddress',o.payment_address,'amountNano',o.amount_nano,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(coalesce(u.ton_balance,0), 9));
  end if;

  insert into public.veteran_vault_purchases(user_id, telegram_id, vault_version, price_ton, amount_nano,
    reward_snapshot, payment_method, status, payment_address, payment_comment, idempotency_key)
  values (u.id, p_telegram_id, c.vault_version, v_price, v_nano, s, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'forge_veteran:' || gen_random_uuid(), p_idempotency_key)
  returning * into o;

  return jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
    'paymentAddress',o.payment_address,'amountNano',o.amount_nano,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(coalesce(u.ton_balance,0), 9));
end $$;

-- On-chain settlement (idempotent, unique tx hash, never charges twice)
create or replace function public.veteran_vault_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare o public.veteran_vault_purchases; v_min numeric; v_ton numeric; v_myth numeric;
begin
  if p_tx_hash is null or btrim(p_tx_hash) = '' then raise exception 'TX_HASH_REQUIRED'; end if;
  select * into o from public.veteran_vault_purchases where id = p_order_id for update;
  if o.id is null then raise exception 'VETERAN_VAULT_ORDER_NOT_FOUND'; end if;
  if o.status = 'settled' then
    return jsonb_build_object('status','already_processed','purchaseId',o.id,'delivery',o.delivery);
  end if;
  if exists (select 1 from public.veteran_vault_purchases where tx_hash = btrim(p_tx_hash) and id <> o.id) then
    raise exception 'TX_ALREADY_USED';
  end if;
  v_min := (o.amount_nano::numeric * 97) / 100;
  if coalesce(p_amount_nano::numeric, 0) < v_min then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  insert into public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  values (btrim(p_tx_hash), o.user_id, 'veteran_vault', p_amount_nano::numeric, o.id::text)
  on conflict (tx_hash) do nothing;

  if o.status = 'pending' then
    v_ton := public.veteran_vault_ton_budget();
    v_myth := public.veteran_vault_myth_budget();
    update public.veteran_vault_purchases
       set status='paid', tx_hash=btrim(p_tx_hash), confirmed_at=coalesce(confirmed_at, now()),
           ton_reserved = v_ton, myth_reserved = v_myth
     where id = o.id;
    update public.veteran_vault_pool
       set ton_reserved = ton_reserved + v_ton, myth_reserved = myth_reserved + v_myth, updated_at = now() where id;
    insert into public.veteran_vault_ledger(purchase_id, user_id, kind, ton_amount, note)
      values (o.id, o.user_id, 'purchase_onchain', o.price_ton, 'veteran vault paid via TonConnect');
  end if;
  return public.veteran_vault_deliver(o.id) || jsonb_build_object('status','completed','purchaseId',o.id);
end $$;

-- CLAIM ALL AVAILABLE: matured daily + milestone + final rewards, idempotent per (purchase, day, type).
create or replace function public.veteran_vault_claim(p_telegram_id bigint, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.game_players; o public.veteran_vault_purchases; s jsonb; c public.veteran_vault_config;
        p public.veteran_vault_pool; v_days int; v_elapsed int; v_day int; v_amount numeric;
        v_ton numeric := 0; v_myth numeric := 0; v_final jsonb := null; v_av_ton numeric; v_av_myth numeric;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id for update;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  c := public.veteran_vault_settings();
  select * into o from public.veteran_vault_purchases
   where user_id = u.id and status = 'settled' order by created_at desc limit 1;
  if o.id is null then raise exception 'VETERAN_VAULT_NOT_ACTIVE'; end if;
  perform 1 from public.veteran_vault_purchases where id = o.id for update;

  s := o.reward_snapshot;
  v_days := greatest(1, coalesce((s->>'cycleDays')::int, 45));
  v_elapsed := least(v_days, greatest(1, floor(extract(epoch from (now() - o.cycle_start_at)) / 86400.0)::int + 1));

  select * into p from public.veteran_vault_pool where id for update;
  v_av_ton := coalesce(o.ton_reserved,0);
  v_av_myth := coalesce(o.myth_reserved,0);

  for v_day in 1..v_elapsed loop
    -- daily MYTH
    v_amount := coalesce((s->>'dailyMyth')::numeric, 0);
    if v_amount > 0 and v_av_myth >= v_myth + v_amount then
      insert into public.veteran_vault_claims(purchase_id, user_id, reward_day, reward_type, myth_amount)
      values (o.id, u.id, v_day, 'daily_myth', v_amount) on conflict do nothing;
      if found then v_myth := v_myth + v_amount; end if;
    end if;
    -- milestone TON
    v_amount := coalesce((s->'rewardSchedule'->'ton'->>v_day::text)::numeric, 0);
    if v_amount > 0 and v_av_ton >= v_ton + v_amount then
      insert into public.veteran_vault_claims(purchase_id, user_id, reward_day, reward_type, ton_amount)
      values (o.id, u.id, v_day, 'milestone_ton', v_amount) on conflict do nothing;
      if found then v_ton := v_ton + v_amount; end if;
    end if;
    -- milestone MYTH
    v_amount := coalesce((s->'rewardSchedule'->'mythBonus'->>v_day::text)::numeric, 0);
    if v_amount > 0 and v_av_myth >= v_myth + v_amount then
      insert into public.veteran_vault_claims(purchase_id, user_id, reward_day, reward_type, myth_amount)
      values (o.id, u.id, v_day, 'milestone_myth', v_amount) on conflict do nothing;
      if found then v_myth := v_myth + v_amount; end if;
    end if;
  end loop;

  -- FINAL REWARD (day = cycle_days), only once
  if v_elapsed >= v_days then
    insert into public.veteran_vault_claims(purchase_id, user_id, reward_day, reward_type, myth_amount, payload)
    values (o.id, u.id, v_days, 'final', coalesce((s->'finalReward'->>'myth')::numeric, 0), s->'finalReward')
    on conflict do nothing;
    if found then
      v_final := s->'finalReward';
      v_amount := coalesce((s->'finalReward'->>'myth')::numeric, 0);
      if v_amount > 0 and v_av_myth >= v_myth + v_amount then v_myth := v_myth + v_amount; end if;
      if coalesce((s->'finalReward'->>'fragments')::int, 0) > 0 then
        perform public.add_universal_fragments(u.id, (s->'finalReward'->>'fragments')::int);
      end if;
      if coalesce(s->'finalReward'->>'chest','') <> '' then
        insert into public.player_inventory(user_id, item_type, item_code, quantity)
        values (u.id, 'resource_chest', s->'finalReward'->>'chest', greatest(1, coalesce((s->'finalReward'->>'chestQty')::int,1)))
        on conflict (user_id, item_type, item_code)
          do update set quantity = public.player_inventory.quantity + greatest(1, coalesce((s->'finalReward'->>'chestQty')::int,1)), updated_at = now();
      end if;
      if coalesce(s->'finalReward'->>'badge','') <> '' then
        insert into public.player_entitlements(user_id, code, source)
        values (u.id, s->'finalReward'->>'badge', 'veteran_vault') on conflict (user_id, code) do nothing;
      end if;
      update public.veteran_vault_purchases set completed_at = coalesce(completed_at, now()) where id = o.id;
    end if;
  end if;

  if v_ton <= 0 and v_myth <= 0 and v_final is null then
    return jsonb_build_object('ok', true, 'nothingToClaim', true, 'state', public.veteran_vault_state(p_telegram_id));
  end if;

  -- credit TON to the internal withdrawable balance (pool-backed, never minted)
  if v_ton > 0 then
    update public.game_players set ton_balance = round(coalesce(ton_balance,0) + v_ton, 9), updated_at = now() where id = u.id;
    update public.veteran_vault_pool set ton_reserved = greatest(0, ton_reserved - v_ton),
           ton_distributed = ton_distributed + v_ton, updated_at = now() where id;
    update public.veteran_vault_purchases set ton_reserved = greatest(0, ton_reserved - v_ton),
           ton_distributed = ton_distributed + v_ton where id = o.id;
  end if;
  if v_myth > 0 then
    insert into public.myth_balances(user_id, amount) values (u.id, 0) on conflict (user_id) do nothing;
    update public.myth_balances set amount = amount + v_myth, updated_at = now() where user_id = u.id;
    insert into public.myth_ledger(user_id, direction, amount, reason) values (u.id, 'credit', v_myth, 'veteran_vault_cycle');
    update public.veteran_vault_pool set myth_reserved = greatest(0, myth_reserved - v_myth),
           myth_distributed = myth_distributed + v_myth, updated_at = now() where id;
    update public.veteran_vault_purchases set myth_reserved = greatest(0, myth_reserved - v_myth),
           myth_distributed = myth_distributed + v_myth where id = o.id;
  end if;
  insert into public.veteran_vault_ledger(purchase_id, user_id, kind, ton_amount, myth_amount, note)
    values (o.id, u.id, 'cycle_claim', v_ton, v_myth, coalesce(p_idempotency_key,'claim'));

  return jsonb_build_object('ok', true, 'tonClaimed', round(v_ton,9), 'mythClaimed', round(v_myth,2),
    'finalReward', v_final, 'day', v_elapsed, 'state', public.veteran_vault_state(p_telegram_id));
end $$;

revoke all on function public.veteran_vault_start_purchase(bigint, text, text) from public, anon, authenticated;
revoke all on function public.veteran_vault_confirm_order(uuid, text, text) from public, anon, authenticated;
revoke all on function public.veteran_vault_claim(bigint, text) from public, anon, authenticated;