CREATE OR REPLACE FUNCTION public.request_wallet_withdrawal(
  p_telegram_id bigint, p_amount_fc numeric, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u game_players%rowtype; rate numeric; w wallet_withdrawals%rowtype; addr text := NULLIF(TRIM(COALESCE(p_wallet_address,'')),'');
BEGIN
  IF p_amount_fc < 100000 THEN RAISE EXCEPTION 'WITHDRAWAL_MINIMUM_100000'; END IF;
  IF mod(p_amount_fc, 100000) <> 0 THEN RAISE EXCEPTION 'WITHDRAWAL_MULTIPLE_100000'; END IF;
  IF addr IS NULL THEN RAISE EXCEPTION 'WALLET_REQUIRED'; END IF;
  IF NOT public.is_valid_ton_address(addr) THEN RAISE EXCEPTION 'WALLET_INVALID'; END IF;

  SELECT * INTO w FROM wallet_withdrawals WHERE idempotency_key = p_idempotency_key;
  IF w.id IS NOT NULL THEN
    RETURN jsonb_build_object('id', w.id, 'status', w.status, 'amountFc', w.amount_fc, 'amountTon', w.amount_ton, 'walletAddress', w.wallet_address);
  END IF;

  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF u.forge_coins < p_amount_fc THEN RAISE EXCEPTION 'INSUFFICIENT_FC_BALANCE'; END IF;
  SELECT value_numeric INTO rate FROM economy_settings WHERE key = 'fc_per_ton';
  rate := COALESCE(NULLIF(rate, 0), 100000);

  UPDATE game_players SET forge_coins = forge_coins - p_amount_fc, updated_at = now() WHERE id = u.id;
  INSERT INTO wallet_withdrawals(user_id, telegram_id, username, amount_fc, amount_ton, wallet_address, idempotency_key)
  VALUES (u.id, u.telegram_id, COALESCE(u.username, u.display_name), p_amount_fc, p_amount_fc / rate, addr, p_idempotency_key)
  RETURNING * INTO w;

  INSERT INTO pool_wallets(user_id, wallet_address, updated_at) VALUES (u.id, addr, now())
  ON CONFLICT (user_id) DO UPDATE SET wallet_address = EXCLUDED.wallet_address, updated_at = now();

  -- audit as a system entry (admin_id 0 = player-triggered event)
  PERFORM public.admin_log(0::bigint, 'WITHDRAWAL_REQUESTED', 'withdrawal', w.id::text, NULL,
    jsonb_build_object('user_id', u.id, 'telegram_id', u.telegram_id, 'wallet_address', addr,
                       'amount_fc', w.amount_fc, 'amount_ton', w.amount_ton), 'solicitado pelo jogador',
    jsonb_build_object('financial', true));

  RETURN jsonb_build_object('id', w.id, 'status', w.status, 'amountFc', w.amount_fc, 'amountTon', w.amount_ton, 'walletAddress', w.wallet_address);
END $$;
