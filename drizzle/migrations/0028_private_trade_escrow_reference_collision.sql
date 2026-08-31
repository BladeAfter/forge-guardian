-- PRIVATE TRADE FIX — escrow ledger reference collision.
-- Both sides used reference_id = trade id, so the SECOND player to lock (or a
-- re-lock after unlock) violated wallet_ledger_reference_unique and the call
-- failed with a generic error, blocking the partner from accepting the offer.

create or replace function public.private_trade_ledger_ref(p_trade uuid, p_user uuid)
returns text language sql volatile set search_path to 'public' as $$
  select p_trade::text || ':' || p_user::text || ':' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)
$$;

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
    values (p_user, 'private_trade_escrow', -fc, before_fc, after_fc, private_trade_ledger_ref(p_trade, p_user));
  end if;

  if ton > 0 then
    if before_ton < ton then raise exception 'INSUFFICIENT_TON_BALANCE'; end if;
    update game_players set ton_balance = round(coalesce(ton_balance,0) - ton, 9),
           ton_reserved = round(coalesce(ton_reserved,0) + ton, 9), updated_at = now()
      where id = p_user returning coalesce(ton_balance,0) into after_ton;
    insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
    values (p_user, ton, 'debit', 'private_trade_escrow', private_trade_ledger_ref(p_trade, p_user),
            'Private trade escrow', after_ton);
  end if;

  if myth > 0 then
    select coalesce(amount,0) into before_myth from myth_balances where user_id = p_user for update;
    if coalesce(before_myth,0) < myth then raise exception 'INSUFFICIENT_MYTH_BALANCE'; end if;
    update myth_balances set amount = amount - myth, updated_at = now() where user_id = p_user;
    insert into myth_ledger(user_id, amount, direction, reason)
    values (p_user, myth, 'debit', 'PRIVATE_TRADE_ESCROW');
  end if;
end $$;

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
    values (p_user, 'private_trade_refund', fc, before_fc, after_fc, private_trade_ledger_ref(p_trade, p_user));
  end if;
  if ton > 0 then
    update game_players set ton_balance = round(coalesce(ton_balance,0) + ton, 9),
           ton_reserved = greatest(0, round(coalesce(ton_reserved,0) - ton, 9)), updated_at = now()
      where id = p_user returning coalesce(ton_balance,0) into after_ton;
    insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
    values (p_user, ton, 'credit', 'private_trade_refund', private_trade_ledger_ref(p_trade, p_user),
            'Private trade escrow released', after_ton);
  end if;
  if myth > 0 then
    insert into myth_balances(user_id, amount) values (p_user, myth)
    on conflict (user_id) do update set amount = myth_balances.amount + excluded.amount, updated_at = now();
    insert into myth_ledger(user_id, amount, direction, reason)
    values (p_user, myth, 'credit', 'PRIVATE_TRADE_REFUND');
  end if;
end $$;

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
    values (p_to, 'private_trade_received', fc, before_fc, after_fc, private_trade_ledger_ref(p_trade, p_to));
  end if;
  if ton > 0 then
    update game_players set ton_reserved = greatest(0, round(coalesce(ton_reserved,0) - ton, 9)), updated_at = now()
      where id = p_from;
    update game_players set ton_balance = round(coalesce(ton_balance,0) + ton, 9), updated_at = now()
      where id = p_to returning coalesce(ton_balance,0) into after_ton;
    insert into ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, note, balance_after)
    values (p_to, ton, 'credit', 'private_trade_received', private_trade_ledger_ref(p_trade, p_to),
            'Private trade received', after_ton);
  end if;
  if myth > 0 then
    insert into myth_balances(user_id, amount) values (p_to, myth)
    on conflict (user_id) do update set amount = myth_balances.amount + excluded.amount, updated_at = now();
    insert into myth_ledger(user_id, amount, direction, reason)
    values (p_to, myth, 'credit', 'PRIVATE_TRADE_RECEIVED');
  end if;
end $$;