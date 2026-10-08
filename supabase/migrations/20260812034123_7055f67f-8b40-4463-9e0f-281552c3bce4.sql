-- ============================================================
-- FC / withdrawable TON separation
-- ============================================================

ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS ton_reserved numeric NOT NULL DEFAULT 0;
DO $$ BEGIN
  ALTER TABLE public.game_players ADD CONSTRAINT game_players_ton_reserved_check CHECK (ton_reserved >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.ton_reward_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  amount_ton numeric NOT NULL CHECK (amount_ton > 0),
  direction text NOT NULL CHECK (direction IN ('credit','debit')),
  source_type text NOT NULL,
  source_id text,
  status text NOT NULL DEFAULT 'completed',
  note text,
  balance_after numeric,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.ton_reward_ledger TO service_role;
ALTER TABLE public.ton_reward_ledger ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX IF NOT EXISTS ton_reward_ledger_source_uniq
  ON public.ton_reward_ledger (user_id, source_type, source_id)
  WHERE source_id IS NOT NULL AND direction = 'credit';
CREATE INDEX IF NOT EXISTS ton_reward_ledger_user_idx
  ON public.ton_reward_ledger (user_id, created_at DESC);

-- keep already-earned TON prizes, without converting any FC
INSERT INTO public.ton_reward_ledger (user_id, amount_ton, direction, source_type, source_id, note, balance_after)
SELECT id, ton_balance, 'credit', 'legacy_balance', id::text, 'saldo TON de premios anterior a separacao FC/TON', ton_balance
  FROM public.game_players WHERE ton_balance > 0
ON CONFLICT DO NOTHING;

-- withdrawals: allow the new TON-only rows (amount_fc = 0) while preserving history
ALTER TABLE public.wallet_withdrawals DROP CONSTRAINT IF EXISTS wallet_withdrawals_amount_fc_check;
ALTER TABLE public.wallet_withdrawals ADD CONSTRAINT wallet_withdrawals_amount_fc_check CHECK (amount_fc >= 0);
ALTER TABLE public.wallet_withdrawals ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'fc_legacy';

INSERT INTO public.wallet_settings (key, value_numeric) VALUES ('min_withdraw_ton', 1)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.spending_event_results ADD COLUMN IF NOT EXISTS reward_ton numeric NOT NULL DEFAULT 0;

-- ============================================================
-- core credit / debit API
-- ============================================================
CREATE OR REPLACE FUNCTION public.credit_ton_reward(
  p_user_id uuid, p_amount_ton numeric, p_source_type text,
  p_source_id text DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before numeric; v_after numeric; v_id uuid;
BEGIN
  IF p_amount_ton IS NULL OR p_amount_ton <= 0 THEN RAISE EXCEPTION 'INVALID_TON_AMOUNT'; END IF;
  IF p_source_type IS NULL OR btrim(p_source_type) = '' THEN RAISE EXCEPTION 'SOURCE_TYPE_REQUIRED'; END IF;

  SELECT COALESCE(ton_balance,0) INTO v_before FROM game_players WHERE id = p_user_id FOR UPDATE;
  IF v_before IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  INSERT INTO ton_reward_ledger (user_id, amount_ton, direction, source_type, source_id, note, balance_after)
  VALUES (p_user_id, round(p_amount_ton, 9), 'credit', p_source_type, p_source_id, p_note, v_before + round(p_amount_ton, 9))
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'credited', 0, 'balanceTon', v_before);
  END IF;

  v_after := v_before + round(p_amount_ton, 9);
  UPDATE game_players SET ton_balance = v_after, updated_at = now() WHERE id = p_user_id;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'ledgerId', v_id,
    'credited', round(p_amount_ton, 9), 'balanceTon', v_after);
END $$;
REVOKE ALL ON FUNCTION public.credit_ton_reward(uuid, numeric, text, text, text) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.debit_ton_balance(
  p_user_id uuid, p_amount_ton numeric, p_source_type text,
  p_source_id text DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before numeric; v_after numeric; v_id uuid;
BEGIN
  IF p_amount_ton IS NULL OR p_amount_ton <= 0 THEN RAISE EXCEPTION 'INVALID_TON_AMOUNT'; END IF;
  SELECT COALESCE(ton_balance,0) INTO v_before FROM game_players WHERE id = p_user_id FOR UPDATE;
  IF v_before IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF v_before < round(p_amount_ton, 9) THEN RAISE EXCEPTION 'INSUFFICIENT_TON_BALANCE'; END IF;
  v_after := v_before - round(p_amount_ton, 9);
  UPDATE game_players SET ton_balance = v_after, updated_at = now() WHERE id = p_user_id;
  INSERT INTO ton_reward_ledger (user_id, amount_ton, direction, source_type, source_id, note, balance_after)
  VALUES (p_user_id, round(p_amount_ton, 9), 'debit', p_source_type, p_source_id, p_note, v_after)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'ledgerId', v_id, 'debited', round(p_amount_ton, 9), 'balanceTon', v_after);
END $$;
REVOKE ALL ON FUNCTION public.debit_ton_balance(uuid, numeric, text, text, text) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.min_withdraw_ton() RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(0.1, COALESCE((SELECT value_numeric FROM wallet_settings WHERE key = 'min_withdraw_ton'), 1));
$$;
REVOKE ALL ON FUNCTION public.min_withdraw_ton() FROM anon, authenticated;

-- ============================================================
-- player facing TON wallet
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_ton_wallet(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE u game_players%rowtype;
BEGIN
  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'balanceFc', u.forge_coins,
    'availableTon', COALESCE(u.ton_balance,0),
    'reservedTon', COALESCE(u.ton_reserved,0),
    'feePercent', public.withdraw_fee_percent(),
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
END $$;
REVOKE ALL ON FUNCTION public.get_ton_wallet(bigint) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.request_ton_withdrawal(
  p_telegram_id bigint, p_amount_ton numeric, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u game_players%rowtype; w wallet_withdrawals%rowtype;
        addr text := NULLIF(TRIM(COALESCE(p_wallet_address,'')),'');
        v_fee_percent numeric; v_gross numeric; v_fee numeric; v_net numeric;
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

  v_fee_percent := public.withdraw_fee_percent();
  v_fee := round(v_gross * v_fee_percent / 100, 6);
  v_net := round(v_gross - v_fee, 6);

  -- available -> reserved (atomic, row already locked)
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
      'gross_ton', v_gross, 'fee_percent', v_fee_percent, 'fee_ton', v_fee, 'net_ton', v_net),
    'saque TON solicitado pelo jogador', jsonb_build_object('financial', true));

  RETURN jsonb_build_object('id', w.id, 'status', w.status, 'grossTon', v_gross,
    'feePercent', v_fee_percent, 'feeTon', v_fee, 'netTon', v_net, 'walletAddress', w.wallet_address,
    'availableTon', COALESCE(u.ton_balance,0) - v_gross);
END $$;
REVOKE ALL ON FUNCTION public.request_ton_withdrawal(bigint, numeric, text, text) FROM anon, authenticated;

-- FC -> TON withdrawal is disabled from this migration on. Old requests keep their own rules.
CREATE OR REPLACE FUNCTION public.request_wallet_withdrawal(
  p_telegram_id bigint, p_amount_fc numeric, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'FC_WITHDRAWAL_DISABLED';
END $$;
REVOKE ALL ON FUNCTION public.request_wallet_withdrawal(bigint, numeric, text, text) FROM anon, authenticated;

-- ============================================================
-- withdrawal review: reserved handling for the new architecture
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_withdrawal_mark_paid(p_admin_id bigint, p_withdrawal_id uuid, p_tx_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w wallet_withdrawals%rowtype; hash text := NULLIF(TRIM(COALESCE(p_tx_hash,'')),'');
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF hash IS NULL OR length(hash) < 8 THEN RAISE EXCEPTION 'tx_hash_required'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_withdrawal_id::text, 42));
  SELECT * INTO w FROM wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status IN ('paid','completed') THEN RAISE EXCEPTION 'already_processed'; END IF;
  IF w.status IN ('rejected','cancelled') THEN RAISE EXCEPTION 'already_processed'; END IF;
  IF NULLIF(TRIM(COALESCE(w.wallet_address,'')),'') IS NULL THEN RAISE EXCEPTION 'wallet_missing'; END IF;
  IF EXISTS (SELECT 1 FROM wallet_withdrawals WHERE tx_hash = hash AND id <> w.id) THEN RAISE EXCEPTION 'tx_hash_already_used'; END IF;

  IF w.source = 'ton_balance' THEN
    UPDATE game_players SET ton_reserved = GREATEST(0, COALESCE(ton_reserved,0) - COALESCE(w.gross_ton, w.amount_ton)),
                            updated_at = now()
     WHERE id = w.user_id;
    UPDATE ton_reward_ledger SET status = 'completed'
     WHERE source_id = w.id::text AND source_type IN ('withdrawal','withdrawal_fee');
  END IF;

  UPDATE wallet_withdrawals
     SET status = 'paid', tx_hash = hash, paid_at = now(), processed_at = now(), admin_id = p_admin_id
   WHERE id = w.id;
  PERFORM public.admin_log(p_admin_id, 'WITHDRAWAL_PAID', 'withdrawal', w.id::text,
    jsonb_build_object('status', w.status),
    jsonb_build_object('status','paid','tx_hash', hash, 'wallet_address', w.wallet_address,
                       'amount_ton', w.amount_ton, 'amount_fc', w.amount_fc, 'source', w.source,
                       'telegram_id', w.telegram_id),
    'pagamento confirmado', jsonb_build_object('financial', true));
  RETURN public.admin_withdrawal_detail(p_admin_id, w.id);
END $$;
REVOKE ALL ON FUNCTION public.admin_withdrawal_mark_paid(bigint, uuid, text) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_withdrawal_reject(p_admin_id bigint, p_withdrawal_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w wallet_withdrawals%rowtype; refunded boolean := false; v_gross numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(p_withdrawal_id::text, 42));
  SELECT * INTO w FROM wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status IN ('paid','completed','rejected','cancelled') THEN RAISE EXCEPTION 'already_processed'; END IF;
  v_gross := COALESCE(w.gross_ton, w.amount_ton);

  IF w.refunded_at IS NULL THEN
    IF w.source = 'ton_balance' THEN
      -- reserved TON goes back to available TON. Never turns into FC.
      UPDATE game_players
         SET ton_reserved = GREATEST(0, COALESCE(ton_reserved,0) - v_gross),
             ton_balance = COALESCE(ton_balance,0) + v_gross,
             updated_at = now()
       WHERE id = w.user_id;
      UPDATE ton_reward_ledger SET status = 'reverted'
       WHERE source_id = w.id::text AND source_type IN ('withdrawal','withdrawal_fee');
      INSERT INTO ton_reward_ledger (user_id, amount_ton, direction, source_type, source_id, note, balance_after)
      SELECT w.user_id, v_gross, 'credit', 'withdrawal_refund', w.id::text, 'saque rejeitado',
             COALESCE(ton_balance,0) FROM game_players WHERE id = w.user_id
      ON CONFLICT DO NOTHING;
    ELSE
      UPDATE game_players SET forge_coins = forge_coins + w.amount_fc, updated_at = now() WHERE id = w.user_id;
    END IF;
    refunded := true;
  END IF;

  UPDATE wallet_withdrawals
     SET status = 'rejected', processed_at = now(), admin_id = p_admin_id,
         refunded_at = COALESCE(refunded_at, now())
   WHERE id = w.id;
  PERFORM public.admin_log(p_admin_id, 'WITHDRAWAL_REJECTED', 'withdrawal', w.id::text,
    jsonb_build_object('status', w.status),
    jsonb_build_object('status','rejected','refunded', refunded, 'amount_fc', w.amount_fc,
                       'gross_ton', v_gross, 'source', w.source,
                       'wallet_address', w.wallet_address, 'telegram_id', w.telegram_id),
    COALESCE(p_reason, 'rejeitado pelo painel'), jsonb_build_object('financial', true));
  RETURN public.admin_withdrawal_detail(p_admin_id, w.id);
END $$;
REVOKE ALL ON FUNCTION public.admin_withdrawal_reject(bigint, uuid, text) FROM anon, authenticated;

-- ============================================================
-- reward sources credit into the withdrawable balance
-- ============================================================
CREATE OR REPLACE FUNCTION public.pool_credit_pending_rewards(p_history_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; v_paid int := 0; v_sum numeric := 0; res jsonb;
BEGIN
  FOR r IN SELECT * FROM pool_rewards WHERE history_id = p_history_id AND status = 'pending' ORDER BY created_at LOOP
    res := public.credit_ton_reward(r.user_id, r.amount_ton, 'community_pool', r.id::text,
      'Community Pool ' || r.reward_type);
    UPDATE pool_rewards SET status = 'paid', paid_at = now() WHERE id = r.id;
    v_paid := v_paid + 1; v_sum := v_sum + r.amount_ton;
  END LOOP;
  RETURN jsonb_build_object('credited', v_paid, 'totalTon', v_sum);
END $$;
REVOKE ALL ON FUNCTION public.pool_credit_pending_rewards(uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.event_distribute(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e public.special_events%rowtype; r record; v_paid integer := 0; v_sum numeric := 0;
        v_source text; res jsonb;
BEGIN
  SELECT * INTO e FROM public.special_events WHERE id = p_event_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(e.id::text, 43));
  v_source := CASE WHEN COALESCE(e.event_key,'') ILIKE '%referral%' THEN 'referral_event' ELSE 'special_event' END;

  FOR r IN SELECT * FROM public.event_results WHERE event_id = e.id AND status = 'pending' AND reward_ton > 0 ORDER BY final_rank LOOP
    IF NOT EXISTS (SELECT 1 FROM public.game_players WHERE id = r.user_id) THEN
      UPDATE public.event_results SET status='failed', note='player_not_found' WHERE id = r.id;
      CONTINUE;
    END IF;
    res := public.credit_ton_reward(r.user_id, r.reward_ton, v_source, r.id::text,
      e.event_key || ' #' || r.final_rank);
    UPDATE public.event_results SET status='paid', paid_at=now() WHERE id = r.id;
    v_paid := v_paid + 1; v_sum := v_sum + r.reward_ton;
  END LOOP;

  RETURN jsonb_build_object('eventId', e.id, 'paid', v_paid, 'totalTon', v_sum,
    'pending', (SELECT count(*) FROM public.event_results WHERE event_id=e.id AND status='pending'),
    'failed', (SELECT count(*) FROM public.event_results WHERE event_id=e.id AND status='failed'));
END $$;
REVOKE ALL ON FUNCTION public.event_distribute(uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.spending_event_pay_rewards(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; v_amount numeric; v_paid int := 0; v_sum numeric := 0; res jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('spending_pay:' || p_event_id::text, 78));
  FOR r IN SELECT * FROM spending_event_results WHERE event_id = p_event_id AND reward_status = 'pending' ORDER BY final_rank LOOP
    v_amount := COALESCE(NULLIF(r.reward_ton, 0),
      (regexp_match(COALESCE(r.reward_json->>'label',''), '([0-9]+(?:[.,][0-9]+)?)\s*TON', 'i'))[1]::numeric);
    IF v_amount IS NULL OR v_amount <= 0 THEN CONTINUE; END IF;
    res := public.credit_ton_reward(r.user_id, v_amount, 'spending_event', r.id::text,
      'Spending Event #' || r.final_rank);
    UPDATE spending_event_results SET reward_ton = v_amount, reward_status = 'paid' WHERE id = r.id;
    v_paid := v_paid + 1; v_sum := v_sum + v_amount;
  END LOOP;
  RETURN jsonb_build_object('paid', v_paid, 'totalTon', v_sum);
END $$;
REVOKE ALL ON FUNCTION public.spending_event_pay_rewards(uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_spending_event_pay(p_admin_id bigint, p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE res jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  res := public.spending_event_pay_rewards(p_event_id);
  PERFORM public.admin_log(p_admin_id, 'SPENDING_EVENT_TON_PAID', 'spending_event', p_event_id::text, NULL,
    res, 'premios TON creditados no saldo sacavel', jsonb_build_object('financial', true));
  RETURN res;
END $$;
REVOKE ALL ON FUNCTION public.admin_spending_event_pay(bigint, uuid) FROM anon, authenticated;

-- ============================================================
-- admin TON rewards module
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_ton_balance(p_admin_id bigint, p_query text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE u game_players%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO u FROM game_players
   WHERE telegram_id::text = btrim(p_query)
      OR lower(COALESCE(username,'')) = lower(btrim(replace(p_query,'@','')))
      OR id::text = btrim(p_query)
   LIMIT 1;
  IF u.id IS NULL THEN RAISE EXCEPTION 'player_not_found'; END IF;
  RETURN jsonb_build_object('userId', u.id, 'telegramId', u.telegram_id,
    'username', u.username, 'displayName', u.display_name,
    'balanceFc', u.forge_coins, 'availableTon', COALESCE(u.ton_balance,0),
    'reservedTon', COALESCE(u.ton_reserved,0),
    'lifetimeCredits', (SELECT COALESCE(sum(amount_ton),0) FROM ton_reward_ledger WHERE user_id=u.id AND direction='credit'),
    'lifetimeDebits', (SELECT COALESCE(sum(amount_ton),0) FROM ton_reward_ledger WHERE user_id=u.id AND direction='debit' AND status <> 'reverted'));
END $$;
REVOKE ALL ON FUNCTION public.admin_ton_balance(bigint, text) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_ton_adjust(
  p_admin_id bigint, p_user_id uuid, p_amount_ton numeric, p_direction text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE res jsonb; v_dir text := lower(COALESCE(p_direction,'credit'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_dir NOT IN ('credit','debit') THEN RAISE EXCEPTION 'invalid_direction'; END IF;
  IF COALESCE(p_amount_ton,0) <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF v_dir = 'credit' THEN
    res := public.credit_ton_reward(p_user_id, p_amount_ton, 'admin_reward',
      'admin:' || p_admin_id || ':' || gen_random_uuid()::text, COALESCE(p_reason,'credito manual'));
  ELSE
    res := public.debit_ton_balance(p_user_id, p_amount_ton, 'adjustment',
      'admin:' || p_admin_id || ':' || gen_random_uuid()::text, COALESCE(p_reason,'debito manual'));
  END IF;
  PERFORM public.admin_log(p_admin_id, 'TON_' || upper(v_dir), 'player', p_user_id::text, NULL,
    jsonb_build_object('amount_ton', p_amount_ton, 'direction', v_dir, 'result', res),
    COALESCE(p_reason,'ajuste manual de TON'), jsonb_build_object('financial', true));
  RETURN res;
END $$;
REVOKE ALL ON FUNCTION public.admin_ton_adjust(bigint, uuid, numeric, text, text) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_ton_reward_history(p_admin_id bigint, p_user_id uuid DEFAULT NULL, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', l.id, 'telegramId', g.telegram_id, 'username', g.username,
      'amountTon', l.amount_ton, 'direction', l.direction, 'sourceType', l.source_type,
      'status', l.status, 'note', l.note, 'createdAt', l.created_at) ORDER BY l.created_at DESC), '[]')
    FROM (SELECT * FROM ton_reward_ledger
           WHERE p_user_id IS NULL OR user_id = p_user_id
           ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(50, p_limit))) l
    JOIN game_players g ON g.id = l.user_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_ton_reward_history(bigint, uuid, integer) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_ton_withdrawals(p_admin_id bigint, p_status text DEFAULT NULL, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', w.id, 'telegramId', w.telegram_id, 'username', w.username,
      'grossTon', COALESCE(w.gross_ton, w.amount_ton), 'feeTon', COALESCE(w.fee_ton,0),
      'netTon', COALESCE(w.net_ton, w.amount_ton), 'feePercent', COALESCE(w.fee_percent,0),
      'status', w.status, 'source', w.source, 'walletAddress', w.wallet_address,
      'createdAt', w.created_at) ORDER BY w.created_at DESC), '[]')
    FROM (SELECT * FROM wallet_withdrawals
           WHERE (p_status IS NULL OR status = lower(p_status))
           ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(50, p_limit))) w);
END $$;
REVOKE ALL ON FUNCTION public.admin_ton_withdrawals(bigint, text, integer) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_ton_audit(p_admin_id bigint, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', a.id, 'adminId', a.admin_id, 'action', a.action, 'targetId', a.target_id,
      'reason', a.reason, 'newValue', a.new_value, 'createdAt', a.created_at) ORDER BY a.created_at DESC), '[]')
    FROM (SELECT * FROM admin_audit_logs
           WHERE action LIKE 'TON_%' OR action LIKE '%WITHDRAWAL%'
           ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(50, p_limit))) a);
END $$;
REVOKE ALL ON FUNCTION public.admin_ton_audit(bigint, integer) FROM anon, authenticated;