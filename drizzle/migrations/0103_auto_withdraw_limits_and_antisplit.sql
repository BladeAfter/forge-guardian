ALTER TABLE public.ton_auto_withdraw_settings
  ADD COLUMN IF NOT EXISTS per_user_daily_ton numeric NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS per_user_daily_count integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS per_user_window_hours integer NOT NULL DEFAULT 24;

UPDATE public.ton_auto_withdraw_settings
   SET max_auto_ton = 3,
       per_user_daily_ton = 3,
       per_user_daily_count = 1,
       per_user_window_hours = 24,
       updated_at = now()
 WHERE id;

CREATE OR REPLACE FUNCTION public.auto_withdraw_config()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'enabled', s.enabled,
    'hotWallet', s.hot_wallet,
    'maxAutoTon', s.max_auto_ton,
    'minAutoTon', s.min_auto_ton,
    'dailyCapTon', s.daily_cap_ton,
    'batchSize', s.batch_size,
    'perUserDailyTon', s.per_user_daily_ton,
    'perUserDailyCount', s.per_user_daily_count,
    'perUserWindowHours', s.per_user_window_hours,
    'paidTodayTon', COALESCE((SELECT SUM(l.amount_ton) FROM ton_auto_withdraw_log l
        WHERE l.status = 'paid' AND l.created_at > date_trunc('day', now())), 0),
    'pendingCount', (SELECT COUNT(*) FROM wallet_withdrawals w WHERE w.status = 'pending'),
    'lastRunAt', s.last_run_at,
    'lastError', s.last_error)
  FROM ton_auto_withdraw_settings s WHERE s.id;
$function$;

CREATE OR REPLACE FUNCTION public.auto_withdraw_claim_batch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  s ton_auto_withdraw_settings%rowtype;
  paid_today numeric;
  room numeric;
  rec record;
  out_rows jsonb := '[]'::jsonb;
  taken integer := 0;
  win interval;
  u_ton numeric;
  u_cnt integer;
  amt numeric;
BEGIN
  SELECT * INTO s FROM ton_auto_withdraw_settings WHERE id FOR UPDATE;
  IF NOT s.enabled THEN RETURN jsonb_build_object('enabled', false, 'items', out_rows); END IF;

  win := make_interval(hours => GREATEST(1, COALESCE(s.per_user_window_hours, 24)));

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
     LIMIT GREATEST(1, s.batch_size) * 5
     FOR UPDATE SKIP LOCKED
  LOOP
    EXIT WHEN taken >= GREATEST(1, s.batch_size);
    amt := COALESCE(rec.net_ton, rec.amount_ton);
    CONTINUE WHEN amt > room;

    -- anti-split: soma e contagem por jogador/carteira na janela (auto + manual pago)
    SELECT COALESCE(SUM(x.amt), 0), COUNT(*) INTO u_ton, u_cnt FROM (
      SELECT COALESCE(l.amount_ton, 0) AS amt
        FROM ton_auto_withdraw_log l
        JOIN wallet_withdrawals w2 ON w2.id = l.withdrawal_id
       WHERE l.status IN ('claimed', 'paid')
         AND l.created_at > now() - win
         AND (w2.user_id = rec.user_id OR w2.wallet_address = rec.wallet_address)
      UNION ALL
      SELECT COALESCE(w3.net_ton, w3.amount_ton, 0)
        FROM wallet_withdrawals w3
       WHERE w3.status IN ('paid', 'completed', 'processing')
         AND COALESCE(w3.paid_at, w3.created_at) > now() - win
         AND w3.id <> rec.id
         AND (w3.user_id = rec.user_id OR w3.wallet_address = rec.wallet_address)
         AND NOT EXISTS (SELECT 1 FROM ton_auto_withdraw_log l2 WHERE l2.withdrawal_id = w3.id)
    ) x;

    CONTINUE WHEN u_cnt >= GREATEST(1, COALESCE(s.per_user_daily_count, 1));
    CONTINUE WHEN u_ton + amt > COALESCE(s.per_user_daily_ton, 3);

    UPDATE wallet_withdrawals SET status = 'processing' WHERE id = rec.id;
    INSERT INTO ton_auto_withdraw_log (withdrawal_id, telegram_id, amount_ton, status)
    VALUES (rec.id, rec.telegram_id, amt, 'claimed');

    room := room - amt;
    taken := taken + 1;
    out_rows := out_rows || jsonb_build_object(
      'id', rec.id, 'walletAddress', rec.wallet_address, 'telegramId', rec.telegram_id,
      'netTon', amt, 'grossTon', COALESCE(rec.gross_ton, rec.amount_ton));
  END LOOP;

  UPDATE ton_auto_withdraw_settings SET last_run_at = now(), updated_at = now() WHERE id;
  RETURN jsonb_build_object('enabled', true, 'items', out_rows);
END $function$;

CREATE OR REPLACE FUNCTION public.admin_auto_withdraw_set(p_admin_id bigint, p_field text, p_value text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM admin_assert(p_admin_id);
  CASE p_field
    WHEN 'enabled' THEN UPDATE ton_auto_withdraw_settings SET enabled = (p_value = 'true'), updated_at = now() WHERE id;
    WHEN 'max' THEN UPDATE ton_auto_withdraw_settings SET max_auto_ton = GREATEST(0, p_value::numeric), updated_at = now() WHERE id;
    WHEN 'min' THEN UPDATE ton_auto_withdraw_settings SET min_auto_ton = GREATEST(0, p_value::numeric), updated_at = now() WHERE id;
    WHEN 'cap' THEN UPDATE ton_auto_withdraw_settings SET daily_cap_ton = GREATEST(0, p_value::numeric), updated_at = now() WHERE id;
    WHEN 'batch' THEN UPDATE ton_auto_withdraw_settings SET batch_size = GREATEST(1, LEAST(20, p_value::int)), updated_at = now() WHERE id;
    WHEN 'wallet' THEN UPDATE ton_auto_withdraw_settings SET hot_wallet = NULLIF(TRIM(p_value), ''), updated_at = now() WHERE id;
    WHEN 'userton' THEN UPDATE ton_auto_withdraw_settings SET per_user_daily_ton = GREATEST(0, p_value::numeric), updated_at = now() WHERE id;
    WHEN 'usercount' THEN UPDATE ton_auto_withdraw_settings SET per_user_daily_count = GREATEST(1, LEAST(20, p_value::int)), updated_at = now() WHERE id;
    WHEN 'userwindow' THEN UPDATE ton_auto_withdraw_settings SET per_user_window_hours = GREATEST(1, LEAST(168, p_value::int)), updated_at = now() WHERE id;
    ELSE RAISE EXCEPTION 'unknown_field';
  END CASE;
  PERFORM admin_log(p_admin_id, 'AUTO_WITHDRAW_SET', 'auto_withdraw', p_field, NULL,
    jsonb_build_object('field', p_field, 'value', p_value), 'saque automático', jsonb_build_object('financial', true));
  RETURN admin_auto_withdraw_overview(p_admin_id);
END $function$;