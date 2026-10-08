CREATE OR REPLACE FUNCTION public.ton_absorb_duplicate_payment(p_comment text, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_kind text; v_ref uuid; v_user uuid; v_settled_tx text;
        v_nano numeric; v_ton numeric; v_before numeric; v_after numeric; v_res jsonb;
begin
  if coalesce(trim(p_comment), '') = '' or coalesce(trim(p_tx_hash), '') = '' then
    raise exception 'INVALID_INPUT';
  end if;
  v_nano := floor(coalesce(nullif(trim(p_amount_nano), '')::numeric, 0));
  if v_nano <= 0 then raise exception 'INVALID_AMOUNT'; end if;

  if exists (select 1 from processed_ton_transactions where tx_hash = p_tx_hash) then
    return jsonb_build_object('status', 'already_processed');
  end if;

  select 'battle_pass', id, user_id, tx_hash into v_kind, v_ref, v_user, v_settled_tx
    from season_pass_orders where payment_comment = p_comment and tx_hash is not null limit 1;
  if v_ref is null then
    select 'pet_egg', id, user_id, tx_hash into v_kind, v_ref, v_user, v_settled_tx
      from pet_egg_orders where payment_comment = p_comment and tx_hash is not null limit 1;
  end if;
  if v_ref is null then
    select 'nft_pet', id, user_id, tx_hash into v_kind, v_ref, v_user, v_settled_tx
      from nft_pet_orders where payment_comment = p_comment and tx_hash is not null limit 1;
  end if;
  if v_ref is null then
    select 'nft_hero', id, user_id, tx_hash into v_kind, v_ref, v_user, v_settled_tx
      from nft_hero_orders where payment_comment = p_comment and tx_hash is not null limit 1;
  end if;
  if v_ref is null then
    select 'nft_equipment', id, user_id, tx_hash into v_kind, v_ref, v_user, v_settled_tx
      from nft_equipment_orders where payment_comment = p_comment and tx_hash is not null limit 1;
  end if;
  if v_ref is null then
    select 'deposit', id, user_id, tx_hash into v_kind, v_ref, v_user, v_settled_tx
      from wallet_deposits where payment_comment = p_comment and tx_hash is not null limit 1;
  end if;

  if v_ref is null or v_user is null then
    return jsonb_build_object('status', 'unknown_reference');
  end if;
  if v_settled_tx = p_tx_hash then
    return jsonb_build_object('status', 'already_processed');
  end if;

  v_ton := round(v_nano / 1000000000, 9);
  select coalesce(ton_balance, 0) into v_before from game_players where id = v_user for update;
  if v_before is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  insert into processed_ton_transactions(tx_hash, transaction_type, reference_id, user_id, amount_nano)
  values (p_tx_hash, 'duplicate_payment_refund', v_ref::text, v_user, v_nano);

  v_res := credit_ton_reward(v_user, v_ton, 'duplicate_payment_refund', p_tx_hash,
    'DUPLICATE_TON_PAYMENT ' || v_kind || ' ' || v_ref::text);
  v_after := coalesce((v_res->>'balanceTon')::numeric, v_before + v_ton);

  insert into wallet_ledger(user_id, type, amount_fc, amount_ton, conversion_rate, balance_before, balance_after, reference_id, tx_hash)
  values (v_user, 'duplicate_payment_refund', 0, v_ton, 0, v_before, v_after, p_tx_hash, p_tx_hash);

  insert into ton_payment_logs(order_kind, order_id, user_id, expected_amount_nano, received_amount_nano,
                               payment_reference, tx_hash, blockchain_status, fulfillment_status, error_detail)
  values (v_kind, v_ref, v_user, '0', v_nano::text, p_comment, p_tx_hash, 'found',
          'overpayment_credited', 'OVERPAYMENT_DETECTED: duplicate payment for an already settled order');

  insert into player_notifications(user_id, type, title, message, dedupe_key)
  values (v_user, 'wallet', 'TON devolvido',
    'Detectamos um pagamento duplicado de ' || trim(to_char(v_ton, 'FM999990.000000000')) ||
    ' TON. O valor foi creditado no seu saldo TON interno.',
    'dup_ton:' || p_tx_hash)
  on conflict do nothing;

  return jsonb_build_object('status', 'credited', 'kind', v_kind, 'orderId', v_ref,
    'amountTon', v_ton, 'balanceTon', v_after);
end $function$;