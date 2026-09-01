-- Saque exige passe V2 pago (Adventurer 5 TON ou Legendary 20 TON).
CREATE OR REPLACE FUNCTION public.withdraw_requires_v2_pass(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT public.ton_mining_has_paid_v2_pass(p_user_id);
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_requires_v2_pass(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.request_ton_withdrawal(
  p_telegram_id bigint, p_amount_ton numeric, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE u game_players%rowtype; w wallet_withdrawals%rowtype;
        addr text := NULLIF(TRIM(COALESCE(p_wallet_address,'')),'');
        v_fee_percent numeric; v_gross numeric; v_fee numeric; v_net numeric; v_staked numeric;
        v_dep_total numeric; v_dep_required numeric; v_locked numeric; v_withdrawable numeric;
BEGIN
  v_gross := floor(COALESCE(p_amount_ton,0) * 1000000) / 1000000;
  IF addr IS NULL THEN RAISE EXCEPTION 'WALLET_REQUIRED'; END IF;
  IF NOT public.is_valid_ton_address(addr) THEN RAISE EXCEPTION 'WALLET_INVALID'; END IF;
  IF v_gross <= 0 THEN RAISE EXCEPTION 'INVALID_TON_AMOUNT'; END IF;
  IF v_gross < public.min_withdraw_ton() THEN RAISE EXCEPTION 'WITHDRAWAL_BELOW_MINIMUM'; END IF;

  SELECT * INTO w FROM wallet_withdrawals WHERE idempotency_key = p_idempotency_key;
  IF w.id IS NOT NULL THEN
    RETURN jsonb_build_object('id', w.id, 'status', w.status, 'grossTon', w.gross_ton,
      'feePercent', w.fee_percent, 'feeTon', w.fee_ton, 'netTon', w.net_ton, 'walletAddress', w.wallet_address);
  END IF;

  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  -- Nova regra: sacar exige passe V2 pago (5 TON no mínimo).
  IF public.withdraw_requires_v2_pass(u.id) THEN
    RAISE EXCEPTION 'WITHDRAWAL_REQUIRES_V2_PASS';
  END IF;

  v_dep_required := public.withdraw_min_deposit_ton();
  v_dep_total := public.player_ton_deposit_total(u.id);
  IF v_dep_required > 0 AND v_dep_total < v_dep_required THEN
    RAISE EXCEPTION 'WITHDRAWAL_REQUIRES_DEPOSIT';
  END IF;

  IF COALESCE(u.ton_balance,0) < v_gross THEN RAISE EXCEPTION 'INSUFFICIENT_TON_BALANCE'; END IF;

  v_locked := public.player_ton_withdraw_locked(u.id);
  v_withdrawable := GREATEST(0, round(COALESCE(u.ton_balance,0) - v_locked, 6));
  IF v_gross > v_withdrawable THEN RAISE EXCEPTION 'WITHDRAWAL_DEPOSIT_LOCKED';
  END IF;

  v_staked := public.myth_staked_amount(u.id);
  v_fee_percent := public.withdraw_fee_percent_for_user(u.id);
  v_fee := round(v_gross * v_fee_percent / 100, 6);
  v_net := round(v_gross - v_fee, 6);

  UPDATE game_players
     SET ton_balance = COALESCE(ton_balance,0) - v_gross,
         ton_reserved = COALESCE(ton_reserved,0) + v_gross,
         updated_at = now()
   WHERE id = u.id;

  INSERT INTO wallet_withdrawals(user_id, telegram_id, username, amount_fc, amount_ton,
    gross_ton, fee_percent, fee_ton, net_ton, wallet_address, idempotency_key, source)
  VALUES (u.id, u.telegram_id, COALESCE(u.username, u.display_name), 0, v_gross,
    v_gross, v_fee_percent, v_fee, v_net, addr, p_idempotency_key, 'ton_balance')
  RETURNING * INTO w;

  INSERT INTO ton_reward_ledger (user_id, amount_ton, direction, source_type, source_id, status, note, balance_after)
  VALUES (u.id, v_gross, 'debit', 'withdrawal', w.id::text, 'pending', 'saque solicitado', COALESCE(u.ton_balance,0) - v_gross);
  INSERT INTO ton_reward_ledger (user_id, amount_ton, direction, source_type, source_id, status, note, balance_after)
  SELECT u.id, v_fee, 'debit', 'withdrawal_fee', w.id::text, 'pending',
         'taxa de ' || v_fee_percent || '%', COALESCE(u.ton_balance,0) - v_gross
  WHERE v_fee > 0;

  INSERT INTO pool_wallets(user_id, wallet_address, updated_at) VALUES (u.id, addr, now())
  ON CONFLICT (user_id) DO UPDATE SET wallet_address = EXCLUDED.wallet_address, updated_at = now();

  PERFORM public.admin_log(0::bigint, 'TON_WITHDRAWAL_REQUESTED', 'withdrawal', w.id::text, NULL,
    jsonb_build_object('user_id', u.id, 'telegram_id', u.telegram_id, 'wallet_address', addr,
      'gross_ton', v_gross, 'fee_percent', v_fee_percent, 'fee_ton', v_fee, 'net_ton', v_net,
      'myth_staked', v_staked, 'deposit_total_ton', v_dep_total, 'deposit_required_ton', v_dep_required,
      'locked_deposit_ton', v_locked,
      'myth_fee_threshold', public.myth_staking_fee_threshold()),
    'saque TON solicitado pelo jogador', jsonb_build_object('financial', true));

  RETURN jsonb_build_object('id', w.id, 'status', w.status, 'grossTon', v_gross,
    'feePercent', v_fee_percent, 'feeTon', v_fee, 'netTon', v_net, 'walletAddress', w.wallet_address,
    'availableTon', COALESCE(u.ton_balance,0) - v_gross,
    'lockedTon', v_locked);
END
$fn$;

CREATE OR REPLACE FUNCTION public.get_ton_wallet(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE u game_players%rowtype; v_dep numeric; v_req numeric; v_locked numeric; v_pass boolean;
BEGIN
  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_req := public.withdraw_min_deposit_ton();
  v_dep := public.player_ton_deposit_total(u.id);
  v_locked := public.player_ton_withdraw_locked(u.id);
  v_pass := public.ton_mining_has_paid_v2_pass(u.id);
  RETURN jsonb_build_object(
    'balanceFc', u.forge_coins,
    'availableTon', COALESCE(u.ton_balance,0),
    'lockedTon', v_locked,
    'withdrawableTon', GREATEST(0, round(COALESCE(u.ton_balance,0) - v_locked, 6)),
    'reservedTon', COALESCE(u.ton_reserved,0),
    'feePercent', public.withdraw_fee_percent_for_user(u.id),
    'defaultFeePercent', public.withdraw_fee_percent(),
    'mythStaked', public.myth_staked_amount(u.id),
    'mythFeeThreshold', public.myth_staking_fee_threshold(),
    'mythFeePercent', public.myth_staking_fee_percent(),
    'minWithdrawTon', public.min_withdraw_ton(),
    'depositRequirementTon', v_req,
    'depositTotalTon', v_dep,
    'depositRequirementMet', (v_req <= 0 OR v_dep >= v_req),
    'passRequirementMet', v_pass,
    'passRequirementTon', 5,
    'rewards', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'amountTon', amount_ton, 'direction', direction,
        'sourceType', source_type, 'sourceId', source_id, 'status', status,
        'note', note, 'createdAt', created_at) ORDER BY created_at DESC), '[]')
      FROM (SELECT * FROM ton_reward_ledger WHERE user_id = u.id ORDER BY created_at DESC LIMIT 40) l),
    'withdrawals', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'grossTon', COALESCE(gross_ton, amount_ton), 'feePercent', COALESCE(fee_percent,0),
        'feeTon', COALESCE(fee_ton,0), 'netTon', COALESCE(net_ton, amount_ton),
        'status', status, 'source', source, 'createdAt', created_at) ORDER BY created_at DESC), '[]')
      FROM (SELECT * FROM wallet_withdrawals WHERE user_id = u.id ORDER BY created_at DESC LIMIT 30) w)
  );
END
$fn$;
