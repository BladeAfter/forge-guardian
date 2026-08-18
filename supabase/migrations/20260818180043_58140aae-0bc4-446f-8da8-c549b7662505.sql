-- 1) Taxa de saque por jogador: staking >= limite => taxa fixa reduzida.
INSERT INTO public.game_settings(key, value) VALUES
  ('myth_staking_fee_threshold', to_jsonb(100000::numeric)),
  ('myth_staking_fee_percent', to_jsonb(15::numeric))
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.myth_staking_fee_threshold()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(0, COALESCE((SELECT NULLIF(value #>> '{}','')::numeric FROM game_settings WHERE key = 'myth_staking_fee_threshold'), 100000))
$$;

CREATE OR REPLACE FUNCTION public.myth_staking_fee_percent()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT GREATEST(0, LEAST(50, COALESCE((SELECT NULLIF(value #>> '{}','')::numeric FROM game_settings WHERE key = 'myth_staking_fee_percent'), 15)))
$$;

-- Staking ativo do jogador (fonte única: myth_staking_positions).
CREATE OR REPLACE FUNCTION public.myth_staked_amount(p_user uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT SUM(amount) FROM public.myth_staking_positions WHERE user_id = p_user AND status = 'active'), 0)
$$;

-- Taxa efetiva: 15% enquanto houver >= 100k MYTH em staking; padrão caso contrário.
CREATE OR REPLACE FUNCTION public.withdraw_fee_percent_for_user(p_user uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_user IS NOT NULL
     AND public.myth_staking_fee_threshold() > 0
     AND public.myth_staked_amount(p_user) >= public.myth_staking_fee_threshold()
    THEN LEAST(public.withdraw_fee_percent(), public.myth_staking_fee_percent())
    ELSE public.withdraw_fee_percent()
  END
$$;

-- 2) Carteira TON usa a taxa do jogador.
CREATE OR REPLACE FUNCTION public.get_ton_wallet(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u game_players%rowtype;
BEGIN
  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'balanceFc', u.forge_coins,
    'availableTon', COALESCE(u.ton_balance,0),
    'reservedTon', COALESCE(u.ton_reserved,0),
    'feePercent', public.withdraw_fee_percent_for_user(u.id),
    'defaultFeePercent', public.withdraw_fee_percent(),
    'mythStaked', public.myth_staked_amount(u.id),
    'mythFeeThreshold', public.myth_staking_fee_threshold(),
    'mythFeePercent', public.myth_staking_fee_percent(),
    'minWithdrawTon', public.min_withdraw_ton(),
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
END $function$;

-- 3) Saque cobra a taxa efetiva (checada no momento do pedido, com a linha travada).
CREATE OR REPLACE FUNCTION public.request_ton_withdrawal(p_telegram_id bigint, p_amount_ton numeric, p_wallet_address text, p_idempotency_key text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u game_players%rowtype; w wallet_withdrawals%rowtype;
        addr text := NULLIF(TRIM(COALESCE(p_wallet_address,'')),'');
        v_fee_percent numeric; v_gross numeric; v_fee numeric; v_net numeric; v_staked numeric;
BEGIN
  v_gross := round(COALESCE(p_amount_ton,0), 6);
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
  IF COALESCE(u.ton_balance,0) < v_gross THEN RAISE EXCEPTION 'INSUFFICIENT_TON_BALANCE'; END IF;

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
      'myth_staked', v_staked, 'myth_fee_threshold', public.myth_staking_fee_threshold()),
    'saque TON solicitado pelo jogador', jsonb_build_object('financial', true));

  RETURN jsonb_build_object('id', w.id, 'status', w.status, 'grossTon', v_gross,
    'feePercent', v_fee_percent, 'feeTon', v_fee, 'netTon', v_net, 'walletAddress', w.wallet_address,
    'availableTon', COALESCE(u.ton_balance,0) - v_gross);
END $function$;

-- 4) Carteira MYTH: circulação real, staking e taxa do jogador (tempo real no card).
CREATE OR REPLACE FUNCTION public.get_myth_wallet(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; v_cfg public.myth_token_settings; v_amount numeric := 0; v_staked numeric := 0;
        v_sold numeric := 0; v_burned numeric := 0; v_held numeric := 0;
BEGIN
  SELECT * INTO v_cfg FROM public.myth_token_settings WHERE id;
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NOT NULL THEN
    SELECT COALESCE(amount, 0) INTO v_amount FROM public.myth_balances WHERE user_id = v_user;
    v_staked := public.myth_staked_amount(v_user);
  END IF;
  SELECT COALESCE(sold, 0), COALESCE(burned, 0) INTO v_sold, v_burned FROM public.myth_sale_public_stats WHERE id;
  SELECT COALESCE(SUM(amount), 0) INTO v_held FROM public.myth_balances;
  v_held := v_held + COALESCE((SELECT SUM(amount) FROM public.myth_staking_positions WHERE status = 'active'), 0);

  RETURN jsonb_build_object(
    'name', v_cfg.token_name,
    'symbol', v_cfg.token_symbol,
    'balance', round(COALESCE(v_amount, 0), 4),
    'staked', round(COALESCE(v_staked, 0), 4),
    'totalOwned', round(COALESCE(v_amount, 0) + COALESCE(v_staked, 0), 4),
    'totalSupply', v_cfg.total_supply,
    'circulating', round(v_held, 4),
    'sold', round(COALESCE(v_sold, 0), 4),
    'burned', round(COALESCE(v_burned, 0), 4),
    'feePercent', CASE WHEN v_user IS NULL THEN NULL ELSE public.withdraw_fee_percent_for_user(v_user) END,
    'feeThreshold', public.myth_staking_fee_threshold(),
    'feePercentReduced', public.myth_staking_fee_percent(),
    'visible', v_cfg.visible_in_game,
    'status', v_cfg.status_label,
    'tradable', false,
    'withdrawable', false,
    'hasUtility', false
  );
END $function$;

-- 5) Tempo real para saldo/staking/config do token.
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.myth_balances; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.myth_staking_positions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.myth_token_settings; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
ALTER TABLE public.myth_balances REPLICA IDENTITY FULL;
ALTER TABLE public.myth_staking_positions REPLICA IDENTITY FULL;