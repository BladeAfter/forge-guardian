-- ============================================================
-- Withdrawals hardening: wallet snapshot, atomic payment flow, audit
-- ============================================================
ALTER TABLE public.wallet_withdrawals
  ADD COLUMN IF NOT EXISTS telegram_id bigint,
  ADD COLUMN IF NOT EXISTS username text,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_at timestamptz,
  ADD COLUMN IF NOT EXISTS admin_id bigint,
  ADD COLUMN IF NOT EXISTS wallet_resolution_required boolean NOT NULL DEFAULT false;

-- 'paid' is the canonical终 state for the admin flow; legacy 'completed' rows stay valid.
ALTER TABLE public.wallet_withdrawals DROP CONSTRAINT IF EXISTS wallet_withdrawals_status_check;
ALTER TABLE public.wallet_withdrawals ADD CONSTRAINT wallet_withdrawals_status_check
  CHECK (status = ANY (ARRAY['pending','processing','approved','paid','completed','rejected','cancelled']));

-- wallet_address must never be empty going forward.
ALTER TABLE public.wallet_withdrawals ALTER COLUMN wallet_address DROP NOT NULL;

CREATE INDEX IF NOT EXISTS wallet_withdrawals_status_idx ON public.wallet_withdrawals (status, created_at DESC);

-- ---------------- backfill: player identity snapshot
UPDATE public.wallet_withdrawals w
SET telegram_id = g.telegram_id,
    username = COALESCE(g.username, g.display_name)
FROM public.game_players g
WHERE g.id = w.user_id AND w.telegram_id IS NULL;

-- ---------------- backfill: wallet only when unambiguous (same user_id -> one connected wallet)
UPDATE public.wallet_withdrawals w
SET wallet_address = pw.wallet_address
FROM public.pool_wallets pw
WHERE pw.user_id = w.user_id
  AND NULLIF(TRIM(COALESCE(w.wallet_address,'')),'') IS NULL
  AND NULLIF(TRIM(COALESCE(pw.wallet_address,'')),'') IS NOT NULL;

UPDATE public.wallet_withdrawals
SET wallet_resolution_required = true
WHERE NULLIF(TRIM(COALESCE(wallet_address,'')),'') IS NULL
  AND status IN ('pending','processing','approved');

-- ---------------- TON address validation helper
CREATE OR REPLACE FUNCTION public.is_valid_ton_address(p_address text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT COALESCE(
    TRIM(p_address) ~ '^[A-Za-z0-9_-]{48}$'
    OR TRIM(p_address) ~ '^-?[0-9]+:[0-9a-fA-F]{64}$', false);
$$;

-- ---------------- request: snapshot wallet + identity, validate address
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

  -- keep the connected wallet registry in sync with the wallet actually used
  INSERT INTO pool_wallets(user_id, wallet_address, updated_at) VALUES (u.id, addr, now())
  ON CONFLICT (user_id) DO UPDATE SET wallet_address = EXCLUDED.wallet_address, updated_at = now();

  PERFORM public.admin_log(NULL::bigint, 'WITHDRAWAL_REQUESTED', 'withdrawal', w.id::text, NULL,
    jsonb_build_object('user_id', u.id, 'telegram_id', u.telegram_id, 'wallet_address', addr,
                       'amount_fc', w.amount_fc, 'amount_ton', w.amount_ton), 'solicitado pelo jogador',
    jsonb_build_object('financial', true));

  RETURN jsonb_build_object('id', w.id, 'status', w.status, 'amountFc', w.amount_fc, 'amountTon', w.amount_ton, 'walletAddress', w.wallet_address);
END $$;

-- ---------------- admin: detail
CREATE OR REPLACE FUNCTION public.admin_withdrawal_detail(p_admin_id bigint, p_withdrawal_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
    'id', w.id, 'shortId', left(w.id::text, 8), 'userId', w.user_id,
    'telegramId', COALESCE(w.telegram_id, g.telegram_id),
    'username', COALESCE(w.username, g.username, g.display_name),
    'walletAddress', NULLIF(TRIM(COALESCE(w.wallet_address,'')),''),
    'walletResolutionRequired', w.wallet_resolution_required,
    'currentWallet', pw.wallet_address,
    'amountFc', w.amount_fc, 'amountTon', w.amount_ton, 'status', w.status,
    'txHash', w.tx_hash, 'createdAt', w.created_at, 'paidAt', COALESCE(w.paid_at, w.processed_at),
    'refundedAt', w.refunded_at, 'adminId', w.admin_id)
  INTO v
  FROM wallet_withdrawals w
  LEFT JOIN game_players g ON g.id = w.user_id
  LEFT JOIN pool_wallets pw ON pw.user_id = w.user_id
  WHERE w.id = p_withdrawal_id;
  IF v IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  RETURN v;
END $$;

-- ---------------- admin: list
CREATE OR REPLACE FUNCTION public.admin_list_withdrawals(p_admin_id bigint, p_status text DEFAULT NULL, p_limit integer DEFAULT 12)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v FROM (
    SELECT w.id, left(w.id::text, 8) AS short_id, w.amount_fc, w.amount_ton, w.status, w.tx_hash,
           NULLIF(TRIM(COALESCE(w.wallet_address,'')),'') AS wallet_address,
           w.wallet_resolution_required, w.created_at,
           COALESCE(w.telegram_id, g.telegram_id) AS telegram_id,
           COALESCE(w.username, g.username, g.display_name, g.telegram_id::text) AS player
    FROM wallet_withdrawals w LEFT JOIN game_players g ON g.id = w.user_id
    WHERE p_status IS NULL OR w.status = p_status
    ORDER BY w.created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 50))) t;
  RETURN jsonb_build_object('items', v);
END $$;

-- ---------------- admin: lock for payment (pending -> processing)
CREATE OR REPLACE FUNCTION public.admin_withdrawal_lock(p_admin_id bigint, p_withdrawal_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w wallet_withdrawals%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(p_withdrawal_id::text, 42));
  SELECT * INTO w FROM wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status IN ('paid','completed') THEN RAISE EXCEPTION 'already_processed'; END IF;
  IF w.status IN ('rejected','cancelled') THEN RAISE EXCEPTION 'already_processed'; END IF;
  IF w.status = 'processing' THEN RAISE EXCEPTION 'withdrawal_locked'; END IF;
  IF NULLIF(TRIM(COALESCE(w.wallet_address,'')),'') IS NULL THEN RAISE EXCEPTION 'wallet_missing'; END IF;
  IF w.amount_ton <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  UPDATE wallet_withdrawals SET status = 'processing', admin_id = p_admin_id WHERE id = w.id;
  PERFORM public.admin_log(p_admin_id, 'WITHDRAWAL_PROCESSING', 'withdrawal', w.id::text,
    jsonb_build_object('status', w.status),
    jsonb_build_object('status','processing','wallet_address', w.wallet_address, 'amount_ton', w.amount_ton,
                       'amount_fc', w.amount_fc, 'telegram_id', w.telegram_id), 'bloqueado para pagamento',
    jsonb_build_object('financial', true));
  RETURN public.admin_withdrawal_detail(p_admin_id, w.id);
END $$;

-- ---------------- admin: release lock (processing -> pending)
CREATE OR REPLACE FUNCTION public.admin_withdrawal_unlock(p_admin_id bigint, p_withdrawal_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w wallet_withdrawals%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO w FROM wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status NOT IN ('processing','approved') THEN RAISE EXCEPTION 'not_processing'; END IF;
  UPDATE wallet_withdrawals SET status = 'pending' WHERE id = w.id;
  PERFORM public.admin_log(p_admin_id, 'WITHDRAWAL_PAYMENT_FAILED', 'withdrawal', w.id::text,
    jsonb_build_object('status', w.status), jsonb_build_object('status','pending'),
    COALESCE(p_reason, 'pagamento não confirmado'), jsonb_build_object('financial', true));
  RETURN public.admin_withdrawal_detail(p_admin_id, w.id);
END $$;

-- ---------------- admin: mark paid (requires tx hash, never twice)
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
  UPDATE wallet_withdrawals
     SET status = 'paid', tx_hash = hash, paid_at = now(), processed_at = now(), admin_id = p_admin_id
   WHERE id = w.id;
  PERFORM public.admin_log(p_admin_id, 'WITHDRAWAL_PAID', 'withdrawal', w.id::text,
    jsonb_build_object('status', w.status),
    jsonb_build_object('status','paid','tx_hash', hash, 'wallet_address', w.wallet_address,
                       'amount_ton', w.amount_ton, 'amount_fc', w.amount_fc, 'telegram_id', w.telegram_id),
    'pagamento confirmado', jsonb_build_object('financial', true));
  RETURN public.admin_withdrawal_detail(p_admin_id, w.id);
END $$;

-- ---------------- admin: reject (single refund)
CREATE OR REPLACE FUNCTION public.admin_withdrawal_reject(p_admin_id bigint, p_withdrawal_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w wallet_withdrawals%rowtype; refunded boolean := false;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(p_withdrawal_id::text, 42));
  SELECT * INTO w FROM wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status IN ('paid','completed','rejected','cancelled') THEN RAISE EXCEPTION 'already_processed'; END IF;
  IF w.refunded_at IS NULL THEN
    UPDATE game_players SET forge_coins = forge_coins + w.amount_fc, updated_at = now() WHERE id = w.user_id;
    refunded := true;
  END IF;
  UPDATE wallet_withdrawals
     SET status = 'rejected', processed_at = now(), admin_id = p_admin_id,
         refunded_at = COALESCE(refunded_at, now())
   WHERE id = w.id;
  PERFORM public.admin_log(p_admin_id, 'WITHDRAWAL_REJECTED', 'withdrawal', w.id::text,
    jsonb_build_object('status', w.status),
    jsonb_build_object('status','rejected','refunded', refunded, 'amount_fc', w.amount_fc,
                       'wallet_address', w.wallet_address, 'telegram_id', w.telegram_id),
    COALESCE(p_reason, 'rejeitado pelo painel'), jsonb_build_object('financial', true));
  IF refunded THEN
    PERFORM public.admin_log(p_admin_id, 'WITHDRAWAL_REFUNDED', 'withdrawal', w.id::text, NULL,
      jsonb_build_object('amount_fc', w.amount_fc, 'user_id', w.user_id, 'telegram_id', w.telegram_id),
      'FC devolvido ao jogador', jsonb_build_object('financial', true));
  END IF;
  RETURN public.admin_withdrawal_detail(p_admin_id, w.id);
END $$;

-- ---------------- admin: connected wallets (search + list)
CREATE OR REPLACE FUNCTION public.admin_connected_wallets(p_admin_id bigint, p_query text DEFAULT NULL, p_limit integer DEFAULT 12)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; q text := NULLIF(TRIM(COALESCE(p_query,'')),'');
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.connected_at DESC), '[]'::jsonb) INTO v FROM (
    SELECT pw.wallet_address, pw.connected_at, pw.updated_at, g.id AS user_id, g.telegram_id,
           COALESCE(g.username, g.display_name, g.telegram_id::text) AS player
    FROM pool_wallets pw JOIN game_players g ON g.id = pw.user_id
    WHERE q IS NULL
       OR g.telegram_id::text = replace(q, '@', '')
       OR g.id::text = q
       OR g.username ILIKE '%' || replace(q, '@', '') || '%'
       OR g.display_name ILIKE '%' || q || '%'
       OR pw.wallet_address ILIKE '%' || q || '%'
    ORDER BY pw.connected_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 50))) t;
  RETURN jsonb_build_object('items', v, 'query', q);
END $$;

-- ---------------- legacy entry point delegates to the new atomic flow
CREATE OR REPLACE FUNCTION public.admin_review_withdrawal(
  p_admin_id bigint, p_withdrawal_id uuid, p_status text, p_tx_hash text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status text := lower(COALESCE(p_status,''));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_status IN ('paid','completed') THEN RETURN public.admin_withdrawal_mark_paid(p_admin_id, p_withdrawal_id, p_tx_hash); END IF;
  IF v_status IN ('rejected','cancelled') THEN RETURN public.admin_withdrawal_reject(p_admin_id, p_withdrawal_id, p_reason); END IF;
  IF v_status IN ('approved','processing') THEN RETURN public.admin_withdrawal_lock(p_admin_id, p_withdrawal_id); END IF;
  RAISE EXCEPTION 'invalid_status';
END $$;
