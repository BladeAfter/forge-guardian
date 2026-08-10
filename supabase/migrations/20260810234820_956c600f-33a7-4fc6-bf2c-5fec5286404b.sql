CREATE TABLE IF NOT EXISTS public.payout_announcements (
  withdrawal_id uuid PRIMARY KEY REFERENCES public.wallet_withdrawals(id) ON DELETE CASCADE,
  channel_id text,
  message_id bigint,
  tx_hash text,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payout_announcements_status_check CHECK (status IN ('pending','sending','sent','failed'))
);

GRANT ALL ON public.payout_announcements TO service_role;
ALTER TABLE public.payout_announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service role manages payout announcements" ON public.payout_announcements
  TO service_role USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS payout_announcements_status_idx ON public.payout_announcements(status, created_at DESC);

INSERT INTO public.game_settings(key, value, category, label) VALUES
  ('payments_channel_chat_id', '"-1004303374351"'::jsonb, 'wallet', 'Chat ID do canal de pagamentos'),
  ('payments_channel_enabled', 'true'::jsonb, 'wallet', 'Publicar comprovantes de saque no canal')
ON CONFLICT (key) DO NOTHING;

-- ---------------- claim: reserve the announcement slot for one withdrawal (idempotent)
CREATE OR REPLACE FUNCTION public.admin_payout_announcement_claim(p_admin_id bigint, p_withdrawal_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w wallet_withdrawals%rowtype; a payout_announcements%rowtype; g game_players%rowtype;
        v_chat text; v_news text; v_app text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('payout:' || p_withdrawal_id::text, 77));
  SELECT * INTO w FROM wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status NOT IN ('paid','completed') THEN RETURN jsonb_build_object('skip', 'not_completed', 'status', w.status); END IF;
  IF NULLIF(TRIM(COALESCE(w.tx_hash,'')),'') IS NULL THEN RETURN jsonb_build_object('skip', 'tx_hash_missing'); END IF;

  SELECT * INTO a FROM payout_announcements WHERE withdrawal_id = w.id FOR UPDATE;
  IF a.withdrawal_id IS NOT NULL AND a.status = 'sent' THEN
    RETURN jsonb_build_object('skip', 'already_sent', 'messageId', a.message_id, 'channelId', a.channel_id);
  END IF;

  INSERT INTO payout_announcements(withdrawal_id, tx_hash, status, attempts)
  VALUES (w.id, w.tx_hash, 'sending', 1)
  ON CONFLICT (withdrawal_id) DO UPDATE
     SET status = 'sending', attempts = payout_announcements.attempts + 1,
         tx_hash = EXCLUDED.tx_hash, updated_at = now();

  SELECT * INTO g FROM game_players WHERE id = w.user_id;
  SELECT value #>> '{}' INTO v_chat FROM game_settings WHERE key = 'payments_channel_chat_id';
  SELECT value #>> '{}' INTO v_app FROM game_settings WHERE key = 'telegram_app_link';
  SELECT url INTO v_news FROM channel_reward_config WHERE channel_key = 'news';

  RETURN jsonb_build_object(
    'withdrawalId', w.id,
    'amountFc', w.amount_fc,
    'amountTon', w.amount_ton,
    'txHash', w.tx_hash,
    'paidAt', COALESCE(w.paid_at, w.processed_at, now()),
    'telegramId', COALESCE(w.telegram_id, g.telegram_id),
    'username', COALESCE(NULLIF(w.username,''), g.username),
    'channelId', v_chat,
    'appLink', v_app,
    'newsUrl', v_news,
    'enabled', COALESCE((SELECT (value)::text = 'true' FROM game_settings WHERE key = 'payments_channel_enabled'), true)
  );
END $$;

-- ---------------- record the delivery result
CREATE OR REPLACE FUNCTION public.admin_payout_announcement_record(
  p_admin_id bigint, p_withdrawal_id uuid, p_status text, p_channel_id text DEFAULT NULL,
  p_message_id bigint DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE st text := lower(COALESCE(p_status,'failed')); a payout_announcements%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF st NOT IN ('sent','failed') THEN RAISE EXCEPTION 'invalid_status'; END IF;
  UPDATE payout_announcements
     SET status = st,
         channel_id = COALESCE(p_channel_id, channel_id),
         message_id = COALESCE(p_message_id, message_id),
         last_error = CASE WHEN st = 'sent' THEN NULL ELSE p_error END,
         sent_at = CASE WHEN st = 'sent' THEN now() ELSE sent_at END,
         updated_at = now()
   WHERE withdrawal_id = p_withdrawal_id
  RETURNING * INTO a;
  IF a.withdrawal_id IS NULL THEN RAISE EXCEPTION 'announcement_not_found'; END IF;
  PERFORM public.admin_log(p_admin_id,
    CASE WHEN st = 'sent' THEN 'PAYOUT_ANNOUNCED' ELSE 'PAYOUT_ANNOUNCE_FAILED' END,
    'withdrawal', p_withdrawal_id::text, NULL,
    jsonb_build_object('channel_id', a.channel_id, 'message_id', a.message_id, 'error', a.last_error),
    'comprovante no canal de pagamentos', jsonb_build_object('financial', true));
  RETURN to_jsonb(a);
END $$;

-- ---------------- overview for the admin bot
CREATE OR REPLACE FUNCTION public.admin_payout_announcements(p_admin_id bigint, p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_items jsonb; v_pending jsonb; v_chat text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT value #>> '{}' INTO v_chat FROM game_settings WHERE key = 'payments_channel_chat_id';
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.paid_at DESC), '[]'::jsonb) INTO v_items FROM (
    SELECT w.id AS withdrawal_id, w.amount_fc, w.amount_ton, w.tx_hash, w.paid_at,
           COALESCE(NULLIF(w.username,''), g.username, w.telegram_id::text) AS player,
           COALESCE(a.status, 'pending') AS status, a.message_id, a.attempts, a.last_error
    FROM wallet_withdrawals w
    JOIN game_players g ON g.id = w.user_id
    LEFT JOIN payout_announcements a ON a.withdrawal_id = w.id
    WHERE w.status IN ('paid','completed')
    ORDER BY w.paid_at DESC NULLS LAST
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 10), 30))) t;
  SELECT COALESCE(jsonb_agg(w.id ORDER BY w.paid_at), '[]'::jsonb) INTO v_pending
    FROM wallet_withdrawals w
    LEFT JOIN payout_announcements a ON a.withdrawal_id = w.id
   WHERE w.status IN ('paid','completed')
     AND NULLIF(TRIM(COALESCE(w.tx_hash,'')),'') IS NOT NULL
     AND (a.withdrawal_id IS NULL OR a.status <> 'sent');
  RETURN jsonb_build_object('channelId', v_chat, 'items', v_items, 'pending', v_pending,
    'enabled', COALESCE((SELECT (value)::text = 'true' FROM game_settings WHERE key = 'payments_channel_enabled'), true));
END $$;