-- Idempotency guard for manual admin TON adjustments
CREATE UNIQUE INDEX IF NOT EXISTS ton_reward_ledger_admin_adjust_key
  ON public.ton_reward_ledger (source_id)
  WHERE source_type = 'admin_ton_adjust' AND source_id IS NOT NULL;

-- Lookup a player + official internal TON balance by Telegram ID
CREATE OR REPLACE FUNCTION public.admin_ton_lookup(p_admin_id bigint, p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v record;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT id, telegram_id, COALESCE(NULLIF(btrim(COALESCE(first_name,'') || ' ' || COALESCE(last_name,'')), ''), username, 'Jogador') AS name,
         COALESCE(ton_balance, 0) AS ton_balance
    INTO v
    FROM game_players WHERE telegram_id = p_telegram_id;
  IF v.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'PLAYER_NOT_FOUND'); END IF;
  RETURN jsonb_build_object('ok', true, 'userId', v.id, 'telegramId', v.telegram_id,
    'name', v.name, 'balanceTon', to_char(round(v.ton_balance, 9), 'FM999999999990.999999999'));
END $$;

-- Official atomic TON adjustment (internal withdrawable balance = game_players.ton_balance)
CREATE OR REPLACE FUNCTION public.admin_adjust_ton_balance(
  p_admin_id bigint,
  p_target_telegram_id bigint,
  p_amount numeric,
  p_operation text,
  p_reason text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_op text := lower(btrim(COALESCE(p_operation, '')));
  v_amount numeric;
  v_user uuid;
  v_name text;
  v_before numeric;
  v_after numeric;
  v_key text := btrim(COALESCE(p_idempotency_key, ''));
  v_existing record;
  v_ledger uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF v_op NOT IN ('add', 'remove') THEN RAISE EXCEPTION 'INVALID_OPERATION'; END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF v_key = '' THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED'; END IF;
  IF p_amount IS NULL OR NOT (p_amount > 0) OR p_amount <> p_amount OR p_amount = 'Infinity'::numeric THEN
    RAISE EXCEPTION 'INVALID_AMOUNT';
  END IF;
  v_amount := round(p_amount, 9);
  IF v_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  -- Double-click protection: same request key returns the original result.
  SELECT l.id, l.balance_after, l.amount_ton, l.direction INTO v_existing
    FROM ton_reward_ledger l
   WHERE l.source_type = 'admin_ton_adjust' AND l.source_id = v_key;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'ledgerId', v_existing.id,
      'operation', v_op, 'amountTon', to_char(v_existing.amount_ton, 'FM999999999990.999999999'),
      'balanceAfter', to_char(round(v_existing.balance_after, 9), 'FM999999999990.999999999'));
  END IF;

  SELECT id, COALESCE(ton_balance, 0),
         COALESCE(NULLIF(btrim(COALESCE(first_name,'') || ' ' || COALESCE(last_name,'')), ''), username, 'Jogador')
    INTO v_user, v_before, v_name
    FROM game_players WHERE telegram_id = p_target_telegram_id FOR UPDATE;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  IF v_op = 'add' THEN
    v_after := round(v_before + v_amount, 9);
  ELSE
    IF v_before < v_amount THEN RAISE EXCEPTION 'INSUFFICIENT_TON_BALANCE'; END IF;
    v_after := round(v_before - v_amount, 9);
  END IF;

  UPDATE game_players SET ton_balance = v_after, updated_at = now() WHERE id = v_user;

  INSERT INTO ton_reward_ledger (user_id, amount_ton, direction, source_type, source_id, note, balance_after)
  VALUES (v_user, v_amount, CASE WHEN v_op = 'add' THEN 'credit' ELSE 'debit' END,
          'admin_ton_adjust', v_key, btrim(p_reason), v_after)
  RETURNING id INTO v_ledger;

  PERFORM public.admin_log(
    p_admin_id, 'TON_BALANCE_ADJUSTED', 'player', v_user::text,
    jsonb_build_object('ton_balance', to_char(round(v_before, 9), 'FM999999999990.999999999')),
    jsonb_build_object(
      'target_telegram_id', p_target_telegram_id::text,
      'operation', CASE WHEN v_op = 'add' THEN 'ADD' ELSE 'REMOVE' END,
      'amount', to_char(v_amount, 'FM999999999990.999999999'),
      'before', to_char(round(v_before, 9), 'FM999999999990.999999999'),
      'after', to_char(v_after, 'FM999999999990.999999999'),
      'reason', btrim(p_reason),
      'ledger_id', v_ledger
    ),
    btrim(p_reason), jsonb_build_object('financial', true, 'idempotency_key', v_key));

  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'ledgerId', v_ledger,
    'userId', v_user, 'name', v_name, 'telegramId', p_target_telegram_id, 'operation', v_op,
    'amountTon', to_char(v_amount, 'FM999999999990.999999999'),
    'balanceBefore', to_char(round(v_before, 9), 'FM999999999990.999999999'),
    'balanceAfter', to_char(v_after, 'FM999999999990.999999999'));
END $$;

-- Last manual TON adjustments (from the real ledger)
CREATE OR REPLACE FUNCTION public.admin_ton_adjust_history(p_admin_id bigint, p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', x.id, 'direction', x.direction,
      'amountTon', to_char(round(x.amount_ton, 9), 'FM999999999990.999999999'),
      'balanceAfter', to_char(round(x.balance_after, 9), 'FM999999999990.999999999'),
      'reason', x.note, 'player', x.player, 'telegramId', x.telegram_id::text,
      'createdAt', x.created_at) ORDER BY x.created_at DESC), '[]'::jsonb)
    FROM (
      SELECT l.*, COALESCE(NULLIF(btrim(COALESCE(g.first_name,'') || ' ' || COALESCE(g.last_name,'')), ''), g.username, 'Jogador') AS player,
             g.telegram_id
        FROM ton_reward_ledger l JOIN game_players g ON g.id = l.user_id
       WHERE l.source_type = 'admin_ton_adjust'
       ORDER BY l.created_at DESC LIMIT GREATEST(1, LEAST(25, COALESCE(p_limit, 10)))
    ) x);
END $$;

REVOKE ALL ON FUNCTION public.admin_adjust_ton_balance(bigint, bigint, numeric, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ton_lookup(bigint, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ton_adjust_history(bigint, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_adjust_ton_balance(bigint, bigint, numeric, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_ton_lookup(bigint, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_ton_adjust_history(bigint, integer) TO service_role;