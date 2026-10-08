-- ============================================================================
-- PRIVATE TRADE: escrow primitives + anti-multiaccount risk engine
-- ============================================================================

-- Locks FC / internal TON / MYTH out of the spendable balances into escrow.
create or replace function public.private_trade_escrow_lock(p_user uuid, p_trade uuid, p_fc numeric, p_ton numeric, p_myth numeric)
returns void language plpgsql security definer set search_path to 'public' as $$
declare fc numeric := round(coalesce(p_fc,0)); ton numeric := round(coalesce(p_ton,0), 9);
        myth numeric := round(coalesce(p_myth,0), 4); before_fc numeric; after_fc numeric;
        before_ton numeric; after_ton numeric; before_myth numeric;
begin
  select forge_coins, coalesce(ton_balance,0) into before_fc, before_ton
    from game_players where id = p_user for update;
  if before_fc is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  if fc > 0 then
    if before_fc < fc then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;
    update game_players set forge_coins = forge_coins - fc, updated_at = now()
      where id = p_user returning forge_coins into after_fc;
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (p_user, 'private_trade_escrow', -fc, before_fc, after_fc, p_trade::text);
  end if;

  if ton > 0 then
    if before_ton < ton then raise exception 'INSUFFICIENT_TON_BALANCE'; end if;
    update game_players set ton_balance = round(coalesce(ton_balance,0) - ton, 9),
           ton_reserved = round(coalesce(ton_reserved,0) + ton, 9), updated_at = now()
      where id = p_user returning coalesce(ton_balance,0) into after_ton;
    insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
    values (p_user, ton, 'debit', 'private_trade_escrow', p_trade::text, 'Private trade escrow', after_ton);
  end if;

  if myth > 0 then
    select coalesce(amount,0) into before_myth from myth_balances where user_id = p_user for update;
    if coalesce(before_myth,0) < myth then raise exception 'INSUFFICIENT_MYTH_BALANCE'; end if;
    update myth_balances set amount = amount - myth, updated_at = now() where user_id = p_user;
    insert into myth_ledger(user_id, amount, direction, reason)
    values (p_user, myth, 'debit', 'PRIVATE_TRADE_ESCROW');
  end if;
end $$;

-- Gives escrowed currency back to its original owner (cancel / expire).
create or replace function public.private_trade_escrow_release(p_user uuid, p_trade uuid, p_fc numeric, p_ton numeric, p_myth numeric)
returns void language plpgsql security definer set search_path to 'public' as $$
declare fc numeric := round(coalesce(p_fc,0)); ton numeric := round(coalesce(p_ton,0), 9);
        myth numeric := round(coalesce(p_myth,0), 4); before_fc numeric; after_fc numeric; after_ton numeric;
begin
  if fc > 0 then
    select forge_coins into before_fc from game_players where id = p_user for update;
    update game_players set forge_coins = forge_coins + fc, updated_at = now()
      where id = p_user returning forge_coins into after_fc;
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (p_user, 'private_trade_refund', fc, before_fc, after_fc, p_trade::text);
  end if;
  if ton > 0 then
    update game_players set ton_balance = round(coalesce(ton_balance,0) + ton, 9),
           ton_reserved = greatest(0, round(coalesce(ton_reserved,0) - ton, 9)), updated_at = now()
      where id = p_user returning coalesce(ton_balance,0) into after_ton;
    insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
    values (p_user, ton, 'credit', 'private_trade_refund', p_trade::text, 'Private trade escrow released', after_ton);
  end if;
  if myth > 0 then
    insert into myth_balances(user_id, amount) values (p_user, myth)
    on conflict (user_id) do update set amount = myth_balances.amount + excluded.amount, updated_at = now();
    insert into myth_ledger(user_id, amount, direction, reason)
    values (p_user, myth, 'credit', 'PRIVATE_TRADE_REFUND');
  end if;
end $$;

-- Moves escrowed currency from the giver to the receiver (settlement).
create or replace function public.private_trade_escrow_deliver(p_from uuid, p_to uuid, p_trade uuid, p_fc numeric, p_ton numeric, p_myth numeric)
returns void language plpgsql security definer set search_path to 'public' as $$
declare fc numeric := round(coalesce(p_fc,0)); ton numeric := round(coalesce(p_ton,0), 9);
        myth numeric := round(coalesce(p_myth,0), 4); before_fc numeric; after_fc numeric; after_ton numeric;
begin
  if fc > 0 then
    select forge_coins into before_fc from game_players where id = p_to for update;
    update game_players set forge_coins = forge_coins + fc, updated_at = now()
      where id = p_to returning forge_coins into after_fc;
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (p_to, 'private_trade_received', fc, before_fc, after_fc, p_trade::text);
  end if;
  if ton > 0 then
    update game_players set ton_reserved = greatest(0, round(coalesce(ton_reserved,0) - ton, 9)), updated_at = now()
      where id = p_from;
    update game_players set ton_balance = round(coalesce(ton_balance,0) + ton, 9), updated_at = now()
      where id = p_to returning coalesce(ton_balance,0) into after_ton;
    insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
    values (p_to, ton, 'credit', 'private_trade_received', p_trade::text, 'Private trade received', after_ton);
  end if;
  if myth > 0 then
    insert into myth_balances(user_id, amount) values (p_to, myth)
    on conflict (user_id) do update set amount = myth_balances.amount + excluded.amount, updated_at = now();
    insert into myth_ledger(user_id, amount, direction, reason)
    values (p_to, myth, 'credit', 'PRIVATE_TRADE_RECEIVED');
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- RISK ENGINE. Combines several signals; a shared network alone never blocks.
-- Raw IPs never leave the security tables: only the hashed values already
-- stored by the anti-fake system are compared here, and nothing is returned to
-- the client (only the score/flags are exposed to the ADMIN).
-- ----------------------------------------------------------------------------
create or replace function public.private_trade_risk_assess(p_trade uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  t private_trades%rowtype; cfg jsonb; w jsonb; score integer := 0; flags text[] := '{}';
  a_value numeric := 0; b_value numeric := 0; a_cur numeric; b_cur numeric;
  a_days integer; b_days integer; same_device boolean; same_net boolean; same_wallet boolean;
  pair_count integer; nft_move boolean; high_rar boolean; created_gap numeric; level text;
begin
  select * into t from private_trades where id = p_trade;
  if t.id is null then raise exception 'TRADE_NOT_FOUND'; end if;
  cfg := private_trade_settings_json(); w := cfg->'weights';

  select coalesce(sum(value_fc),0) into a_value from private_trade_items where trade_id = t.id and side = 'initiator';
  select coalesce(sum(value_fc),0) into b_value from private_trade_items where trade_id = t.id and side = 'recipient';
  a_cur := t.initiator_fc + t.initiator_ton * 100000 + t.initiator_myth * 2;
  b_cur := t.recipient_fc + t.recipient_ton * 100000 + t.recipient_myth * 2;
  a_value := a_value + a_cur; b_value := b_value + b_cur;

  a_days := market_account_days(t.initiator_user_id);
  b_days := market_account_days(t.recipient_user_id);

  -- Strong signal: both accounts seen on the same installation/session/device.
  same_device := accounts_share_device(t.initiator_user_id, t.recipient_user_id);

  -- Weak signal: same hashed network only.
  select exists (
    select 1 from device_accounts da
      join device_registry dra on dra.device_hash = da.device_hash
      join device_accounts db on true
      join device_registry drb on drb.device_hash = db.device_hash
     where da.telegram_id = (select telegram_id from game_players where id = t.initiator_user_id)
       and db.telegram_id = (select telegram_id from game_players where id = t.recipient_user_id)
       and dra.last_ip_hash is not null and dra.last_ip_hash = drb.last_ip_hash
       and da.device_hash <> db.device_hash
  ) into same_net;

  -- Wallet relationship: both accounts historically funded from the same wallet.
  select exists (
    select 1 from wallet_deposits x join wallet_deposits y on lower(y.from_wallet) = lower(x.from_wallet)
     where x.user_id = t.initiator_user_id and y.user_id = t.recipient_user_id
       and nullif(x.from_wallet,'') is not null
  ) into same_wallet;

  select count(*) into pair_count from private_trades
   where status = 'completed'
     and ((initiator_user_id = t.initiator_user_id and recipient_user_id = t.recipient_user_id)
       or (initiator_user_id = t.recipient_user_id and recipient_user_id = t.initiator_user_id))
     and completed_at > now() - interval '30 days';

  select exists (select 1 from private_trade_items i where i.trade_id = t.id
    and coalesce((i.snapshot->>'nft')::boolean, false)) into nft_move;
  select exists (select 1 from private_trade_items i where i.trade_id = t.id
    and private_trade_high_rarity(i.snapshot->>'rarity')) into high_rar;

  select abs(extract(epoch from (ga.created_at - gb.created_at)) / 86400) into created_gap
    from game_players ga, game_players gb where ga.id = t.initiator_user_id and gb.id = t.recipient_user_id;

  if same_device then
    score := score + (w->>'sameDevice')::integer; flags := flags || 'SAME_DEVICE_STRONG_MATCH';
  end if;
  if same_net then score := score + (w->>'sameNetwork')::integer; flags := flags || 'SAME_NETWORK'; end if;
  if same_wallet then score := score + (w->>'sameWallet')::integer; flags := flags || 'SAME_WALLET'; end if;
  if least(a_days, b_days) < coalesce((cfg->>'minAccountDays')::integer, 7) then
    score := score + (w->>'newAccount')::integer; flags := flags || 'NEW_ACCOUNT';
  end if;
  if coalesce(created_gap, 999) <= 1 then score := score + 10; flags := flags || 'ACCOUNTS_CREATED_TOGETHER'; end if;
  if greatest(a_value, b_value) > 0
     and least(a_value, b_value) < greatest(a_value, b_value) * 0.15 then
    score := score + (w->>'oneSided')::integer; flags := flags || 'ONE_SIDED_TRADE';
  end if;
  if nft_move then score := score + (w->>'nftTransfer')::integer; flags := flags || 'NFT_TRANSFER'; end if;
  if high_rar then score := score + (w->>'highRarity')::integer; flags := flags || 'HIGH_RARITY_TRANSFER'; end if;
  if pair_count >= 3 then score := score + (w->>'repeatedPair')::integer; flags := flags || 'REPEATED_PAIR'; end if;

  -- Strong self-transfer evidence: same device AND a valuable/one-sided transfer.
  if same_device and (nft_move or high_rar) then score := score + 20; flags := flags || 'SELF_TRANSFER_SUSPECT'; end if;

  score := least(100, greatest(0, score));
  level := case when score >= (cfg->>'riskCritical')::integer then 'CRITICAL'
                when score >= (cfg->>'riskHigh')::integer then 'HIGH'
                when score >= (cfg->>'riskMedium')::integer then 'MEDIUM'
                else 'LOW' end;

  update private_trades set risk_score = score, risk_flags = flags, updated_at = now() where id = t.id;
  return jsonb_build_object('score', score, 'level', level, 'flags', to_jsonb(flags),
    'valueA', a_value, 'valueB', b_value);
end $$;