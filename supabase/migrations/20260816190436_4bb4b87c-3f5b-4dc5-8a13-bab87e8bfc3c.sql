-- 1) Season pass orders are idempotent per (user, tier): a second click/tap on BUY reuses the
--    pending order instead of minting a new payment intent with a new amount/comment.
CREATE OR REPLACE FUNCTION public.create_season_pass_order(p_telegram_id bigint, p_tier text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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

  if p.tier = 'legendary' then raise exception 'PASS_ALREADY_OWNED'; end if;
  if p_tier = 'adventurer' and p.tier = 'adventurer' then raise exception 'PASS_ALREADY_OWNED'; end if;

  select * into o from season_pass_orders where idempotency_key = p_idempotency_key;

  -- Same product, still unpaid and not expired: return the SAME intent (same amount, same comment).
  if o.id is null then
    select * into o from season_pass_orders
     where user_id = u and season_id = s.id and tier = p_tier
       and status = 'pending' and tx_hash is null and expires_at > now()
     order by created_at desc limit 1;
  end if;

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
end $function$;

-- 2) Extra / duplicated payment absorber.
--    A wallet that sends the same payment twice (same comment) must never lose the money and must
--    never deliver the product twice: the surplus is credited to the player's internal TON balance.
--    Idempotent: one blockchain tx can only ever be absorbed once.
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

  -- This transaction was already used by some operation: nothing to do.
  if exists (select 1 from processed_ton_transactions where tx_hash = p_tx_hash) then
    return jsonb_build_object('status', 'already_processed');
  end if;

  -- Resolve the comment to the order it belongs to; only ALREADY SETTLED orders are considered,
  -- because a pending order must be settled by the regular pipeline (never absorbed).
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

  insert into player_notifications(user_id, kind, title, body)
  values (v_user, 'wallet', 'TON devolvido',
    'Detectamos um pagamento duplicado de ' || trim(to_char(v_ton, 'FM999990.000000000')) ||
    ' TON. O valor foi creditado no seu saldo TON interno.');

  return jsonb_build_object('status', 'credited', 'kind', v_kind, 'orderId', v_ref,
    'amountTon', v_ton, 'balanceTon', v_after);
end $function$;

GRANT EXECUTE ON FUNCTION public.ton_absorb_duplicate_payment(text, text, text) TO service_role;