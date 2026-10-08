-- AUTO-WITHDRAW (TON) ------------------------------------------------------
-- Server-side automation: pays pending withdrawals up to an admin limit from the
-- hot wallet. Anything above the limit stays for manual approval in the bot.

CREATE TABLE IF NOT EXISTS public.ton_auto_withdraw_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT false,
  hot_wallet text,
  max_auto_ton numeric NOT NULL DEFAULT 5,
  min_auto_ton numeric NOT NULL DEFAULT 0,
  daily_cap_ton numeric NOT NULL DEFAULT 50,
  batch_size integer NOT NULL DEFAULT 5,
  last_run_at timestamptz,
  last_error text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.ton_auto_withdraw_settings TO service_role;
ALTER TABLE public.ton_auto_withdraw_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "No direct client access" ON public.ton_auto_withdraw_settings
  AS RESTRICTIVE TO anon, authenticated USING (false) WITH CHECK (false);

INSERT INTO public.ton_auto_withdraw_settings (id) VALUES (true) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.ton_auto_withdraw_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  withdrawal_id uuid REFERENCES public.wallet_withdrawals(id) ON DELETE SET NULL,
  telegram_id bigint,
  amount_ton numeric,
  status text NOT NULL,
  tx_hash text,
  error text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auto_withdraw_log_created ON public.ton_auto_withdraw_log (created_at DESC);
GRANT ALL ON public.ton_auto_withdraw_log TO service_role;
ALTER TABLE public.ton_auto_withdraw_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "No direct client access" ON public.ton_auto_withdraw_log
  AS RESTRICTIVE TO anon, authenticated USING (false) WITH CHECK (false);

-- Config + today's automated total (worker reads this before paying anything).
CREATE OR REPLACE FUNCTION public.auto_withdraw_config()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'enabled', s.enabled,
    'hotWallet', s.hot_wallet,
    'maxAutoTon', s.max_auto_ton,
    'minAutoTon', s.min_auto_ton,
    'dailyCapTon', s.daily_cap_ton,
    'batchSize', s.batch_size,
    'paidTodayTon', COALESCE((SELECT SUM(l.amount_ton) FROM ton_auto_withdraw_log l
        WHERE l.status = 'paid' AND l.created_at > date_trunc('day', now())), 0),
    'pendingCount', (SELECT COUNT(*) FROM wallet_withdrawals w WHERE w.status = 'pending'),
    'lastRunAt', s.last_run_at,
    'lastError', s.last_error)
  FROM ton_auto_withdraw_settings s WHERE s.id;
$$;

-- Claims a batch: only pending requests with a wallet, inside the limit and the
-- daily cap. Each claimed row becomes 'processing' so no double payment happens.
CREATE OR REPLACE FUNCTION public.auto_withdraw_claim_batch()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s ton_auto_withdraw_settings%rowtype;
  paid_today numeric;
  room numeric;
  rec record;
  out_rows jsonb := '[]'::jsonb;
  taken integer := 0;
BEGIN
  SELECT * INTO s FROM ton_auto_withdraw_settings WHERE id FOR UPDATE;
  IF NOT s.enabled THEN RETURN jsonb_build_object('enabled', false, 'items', out_rows); END IF;

  SELECT COALESCE(SUM(amount_ton), 0) INTO paid_today FROM ton_auto_withdraw_log
   WHERE status = 'paid' AND created_at > date_trunc('day', now());
  room := GREATEST(0, COALESCE(s.daily_cap_ton, 0) - paid_today);

  FOR rec IN
    SELECT w.* FROM wallet_withdrawals w
     WHERE w.status = 'pending'
       AND NULLIF(TRIM(COALESCE(w.wallet_address, '')), '') IS NOT NULL
       AND NOT COALESCE(w.wallet_resolution_required, false)
       AND COALESCE(w.net_ton, w.amount_ton) > 0
       AND COALESCE(w.net_ton, w.amount_ton) <= s.max_auto_ton
       AND COALESCE(w.net_ton, w.amount_ton) >= COALESCE(s.min_auto_ton, 0)
     ORDER BY w.created_at ASC
     LIMIT GREATEST(1, s.batch_size)
     FOR UPDATE SKIP LOCKED
  LOOP
    EXIT WHEN taken >= GREATEST(1, s.batch_size);
    CONTINUE WHEN COALESCE(rec.net_ton, rec.amount_ton) > room;

    UPDATE wallet_withdrawals SET status = 'processing' WHERE id = rec.id;
    INSERT INTO ton_auto_withdraw_log (withdrawal_id, telegram_id, amount_ton, status)
    VALUES (rec.id, rec.telegram_id, COALESCE(rec.net_ton, rec.amount_ton), 'claimed');

    room := room - COALESCE(rec.net_ton, rec.amount_ton);
    taken := taken + 1;
    out_rows := out_rows || jsonb_build_object(
      'id', rec.id, 'walletAddress', rec.wallet_address, 'telegramId', rec.telegram_id,
      'netTon', COALESCE(rec.net_ton, rec.amount_ton), 'grossTon', COALESCE(rec.gross_ton, rec.amount_ton));
  END LOOP;

  UPDATE ton_auto_withdraw_settings SET last_run_at = now(), updated_at = now() WHERE id;
  RETURN jsonb_build_object('enabled', true, 'items', out_rows);
END $$;

-- Confirms an automated payment (reuses the audited admin path).
CREATE OR REPLACE FUNCTION public.auto_withdraw_complete(p_withdrawal_id uuid, p_tx_hash text, p_amount_ton numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE res jsonb;
BEGIN
  UPDATE wallet_withdrawals SET status = 'pending' WHERE id = p_withdrawal_id AND status = 'processing';
  res := admin_withdrawal_mark_paid(8118569391, p_withdrawal_id, p_tx_hash);
  INSERT INTO ton_auto_withdraw_log (withdrawal_id, amount_ton, status, tx_hash)
  VALUES (p_withdrawal_id, p_amount_ton, 'paid', p_tx_hash);
  RETURN res;
END $$;

-- Puts a failed request back in the queue for the next run / manual review.
CREATE OR REPLACE FUNCTION public.auto_withdraw_release(p_withdrawal_id uuid, p_error text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE wallet_withdrawals SET status = 'pending' WHERE id = p_withdrawal_id AND status = 'processing';
  INSERT INTO ton_auto_withdraw_log (withdrawal_id, status, error) VALUES (p_withdrawal_id, 'failed', LEFT(COALESCE(p_error,''), 500));
  UPDATE ton_auto_withdraw_settings SET last_error = LEFT(COALESCE(p_error,''), 500), updated_at = now() WHERE id;
END $$;

-- Admin bot surface -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_auto_withdraw_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d jsonb;
BEGIN
  PERFORM admin_assert(p_admin_id);
  d := auto_withdraw_config();
  RETURN d || jsonb_build_object(
    'pendingTon', (SELECT COALESCE(SUM(COALESCE(net_ton, amount_ton)),0) FROM wallet_withdrawals WHERE status = 'pending'),
    'processingCount', (SELECT COUNT(*) FROM wallet_withdrawals WHERE status = 'processing'),
    'recent', COALESCE((SELECT jsonb_agg(jsonb_build_object('status', l.status, 'amountTon', l.amount_ton,
        'txHash', l.tx_hash, 'error', l.error, 'createdAt', l.created_at) ORDER BY l.created_at DESC)
      FROM (SELECT * FROM ton_auto_withdraw_log ORDER BY created_at DESC LIMIT 8) l), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_auto_withdraw_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  CASE p_field
    WHEN 'enabled' THEN UPDATE ton_auto_withdraw_settings SET enabled = (p_value = 'true'), updated_at = now() WHERE id;
    WHEN 'max' THEN UPDATE ton_auto_withdraw_settings SET max_auto_ton = GREATEST(0, p_value::numeric), updated_at = now() WHERE id;
    WHEN 'min' THEN UPDATE ton_auto_withdraw_settings SET min_auto_ton = GREATEST(0, p_value::numeric), updated_at = now() WHERE id;
    WHEN 'cap' THEN UPDATE ton_auto_withdraw_settings SET daily_cap_ton = GREATEST(0, p_value::numeric), updated_at = now() WHERE id;
    WHEN 'batch' THEN UPDATE ton_auto_withdraw_settings SET batch_size = GREATEST(1, LEAST(20, p_value::int)), updated_at = now() WHERE id;
    WHEN 'wallet' THEN UPDATE ton_auto_withdraw_settings SET hot_wallet = NULLIF(TRIM(p_value), ''), updated_at = now() WHERE id;
    ELSE RAISE EXCEPTION 'unknown_field';
  END CASE;
  PERFORM admin_log(p_admin_id, 'AUTO_WITHDRAW_SET', 'auto_withdraw', p_field, NULL,
    jsonb_build_object('field', p_field, 'value', p_value), 'saque automático', jsonb_build_object('financial', true));
  RETURN admin_auto_withdraw_overview(p_admin_id);
END $$;

REVOKE ALL ON FUNCTION public.auto_withdraw_config() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_withdraw_claim_batch() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_withdraw_complete(uuid, text, numeric) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_withdraw_release(uuid, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_auto_withdraw_overview(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_auto_withdraw_set(bigint, text, text) FROM anon, authenticated;
