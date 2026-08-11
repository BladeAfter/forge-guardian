-- ============================================================================
-- PAYMENT RECOVERY (admin fallback). The automatic blockchain verification
-- (ton-reconcile / confirm_* functions) is untouched: this only adds a manual,
-- idempotent and fully audited escape hatch for payments the scanner missed.
-- ============================================================================

ALTER TABLE public.wallet_deposits
  ADD COLUMN IF NOT EXISTS verification_method text NOT NULL DEFAULT 'blockchain',
  ADD COLUMN IF NOT EXISTS manually_approved boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS approved_by_admin bigint,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approval_reason text;

ALTER TABLE public.pet_egg_orders
  ADD COLUMN IF NOT EXISTS verification_method text NOT NULL DEFAULT 'blockchain',
  ADD COLUMN IF NOT EXISTS manually_approved boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS approved_by_admin bigint,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approval_reason text;

ALTER TABLE public.season_pass_orders
  ADD COLUMN IF NOT EXISTS verification_method text NOT NULL DEFAULT 'blockchain',
  ADD COLUMN IF NOT EXISTS manually_approved boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS approved_by_admin bigint,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approval_reason text;

-- Rejection must be representable on every purchase table.
ALTER TABLE public.pet_egg_orders DROP CONSTRAINT IF EXISTS pet_egg_orders_status_check;
ALTER TABLE public.pet_egg_orders ADD CONSTRAINT pet_egg_orders_status_check
  CHECK (status = ANY (ARRAY['pending','paid','confirmed','delivered','expired','cancelled','rejected']));

ALTER TABLE public.season_pass_orders DROP CONSTRAINT IF EXISTS season_pass_orders_status_check;
ALTER TABLE public.season_pass_orders ADD CONSTRAINT season_pass_orders_status_check
  CHECK (status = ANY (ARRAY['pending','paid','activated','expired','cancelled','rejected']));

-- ---------------------------------------------------------------- audit trail
CREATE TABLE IF NOT EXISTS public.payment_recovery_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id bigint NOT NULL,
  order_id text NOT NULL,
  user_id uuid,
  transaction_type text NOT NULL,
  action text NOT NULL,
  amount_ton numeric,
  reward_type text,
  reward_amount numeric,
  previous_status text,
  new_status text,
  tx_hash text,
  reason text,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  approved_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.payment_recovery_audit TO service_role;
ALTER TABLE public.payment_recovery_audit ENABLE ROW LEVEL SECURITY;
-- Admin-bot only surface: no anon/authenticated policy on purpose.
CREATE POLICY "payment_recovery_audit_service_only" ON public.payment_recovery_audit
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS payment_recovery_audit_order_idx ON public.payment_recovery_audit(order_id, created_at DESC);

-- ---------------------------------------------------------------- unified view
-- One normalised row per received payment (never withdrawals).
CREATE OR REPLACE VIEW public.payment_recovery_orders AS
  SELECT d.id::text AS order_id, 'deposit'::text AS kind, 'DEPOSIT'::text AS type_label,
         d.user_id, d.amount_ton, d.status, d.tx_hash, d.created_at,
         d.credited_at AS delivered_at, d.confirmed_at AS paid_at,
         d.manually_approved, d.verification_method, d.approved_by_admin, d.approved_at, d.approval_reason,
         NULL::text AS product_label,
         (d.status IN ('credited')) AS finished
    FROM public.wallet_deposits d
  UNION ALL
  SELECT o.id::text, 'premium_egg', 'PREMIUM_EGG',
         o.user_id, o.price_ton, o.status, o.tx_hash, o.created_at,
         o.delivered_at, o.paid_at,
         o.manually_approved, o.verification_method, o.approved_by_admin, o.approved_at, o.approval_reason,
         (SELECT e.name FROM public.pet_eggs e WHERE e.id = o.egg_id),
         (o.status IN ('delivered')) AS finished
    FROM public.pet_egg_orders o
  UNION ALL
  SELECT s.id::text, 'battle_pass', 'BATTLE_PASS',
         s.user_id, s.price_ton, s.status, s.tx_hash, s.created_at,
         s.activated_at, s.paid_at,
         s.manually_approved, s.verification_method, s.approved_by_admin, s.approved_at, s.approval_reason,
         upper(s.tier),
         (s.status IN ('activated')) AS finished
    FROM public.season_pass_orders s;

REVOKE ALL ON public.payment_recovery_orders FROM anon, authenticated;
GRANT SELECT ON public.payment_recovery_orders TO service_role;

-- ---------------------------------------------------------------- helpers
CREATE OR REPLACE FUNCTION public.payment_recovery_tx_conflict(p_order_id text, p_tx_hash text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN p_tx_hash IS NULL OR p_tx_hash = '' THEN NULL
    WHEN EXISTS (SELECT 1 FROM public.processed_ton_transactions t WHERE t.tx_hash = p_tx_hash AND t.reference_id <> p_order_id)
      THEN 'processed_ton_transactions'
    WHEN EXISTS (SELECT 1 FROM public.wallet_deposits w WHERE w.tx_hash = p_tx_hash AND w.id::text <> p_order_id) THEN 'deposit'
    WHEN EXISTS (SELECT 1 FROM public.pet_egg_orders e WHERE e.tx_hash = p_tx_hash AND e.id::text <> p_order_id) THEN 'premium_egg'
    WHEN EXISTS (SELECT 1 FROM public.season_pass_orders s WHERE s.tx_hash = p_tx_hash AND s.id::text <> p_order_id) THEN 'battle_pass'
    ELSE NULL END;
$$;

REVOKE ALL ON FUNCTION public.payment_recovery_tx_conflict(text, text) FROM PUBLIC, anon, authenticated;

-- Normalised order payload (player identity + product + recovery flags).
CREATE OR REPLACE FUNCTION public.payment_recovery_order_json(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  SELECT o.*, g.telegram_id, g.username, g.name, g.banned
    INTO r
    FROM public.payment_recovery_orders o
    LEFT JOIN public.game_players g ON g.id = o.user_id
   WHERE o.order_id = p_order_id;
  IF r.order_id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'orderId', r.order_id, 'shortId', left(r.order_id, 8), 'kind', r.kind, 'typeLabel', r.type_label,
    'userId', r.user_id, 'telegramId', r.telegram_id, 'username', r.username, 'name', r.name, 'banned', COALESCE(r.banned,false),
    'amountTon', r.amount_ton, 'status', r.status, 'txHash', r.tx_hash, 'createdAt', r.created_at,
    'paidAt', r.paid_at, 'deliveredAt', r.delivered_at, 'finished', r.finished,
    'productLabel', r.product_label,
    'manuallyApproved', r.manually_approved, 'verificationMethod', r.verification_method,
    'approvedByAdmin', r.approved_by_admin, 'approvedAt', r.approved_at, 'approvalReason', r.approval_reason,
    'expectedFc', CASE WHEN r.kind = 'deposit' THEN round(r.amount_ton * public.current_ton_fc_rate()) ELSE NULL END,
    'txConflict', public.payment_recovery_tx_conflict(r.order_id, r.tx_hash),
    'paymentConfirmed', (r.tx_hash IS NOT NULL AND r.tx_hash <> ''),
    'deliveryPending', (r.tx_hash IS NOT NULL AND r.tx_hash <> '' AND NOT r.finished AND r.status <> 'rejected')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.payment_recovery_order_json(text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- delivery core
-- Idempotent: reuses the exact same confirmation/delivery routines used by the
-- automatic blockchain path, so rewards, referral commissions and the community
-- pool revenue behave identically. Returns 'already_processed' on replays.
CREATE OR REPLACE FUNCTION public.payment_recovery_deliver(p_order_id text, p_admin_id bigint, p_reason text, p_force boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o jsonb; kind text; hash text; res jsonb; conflict text; nano text; prev_status text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('payment_recovery:'||p_order_id, 0));
  o := public.payment_recovery_order_json(p_order_id);
  IF o IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  kind := o->>'kind';
  prev_status := o->>'status';

  -- Duplicate protection: never deliver a finished order twice.
  IF (o->>'finished')::boolean THEN
    RETURN jsonb_build_object('status','already_processed','orderId',p_order_id,'kind',kind,'orderStatus',prev_status);
  END IF;

  conflict := o->>'txConflict';
  IF conflict IS NOT NULL AND NOT p_force THEN
    RETURN jsonb_build_object('status','payment_conflict','orderId',p_order_id,'kind',kind,'conflictWith',conflict);
  END IF;

  -- Recovery is explicitly allowed without an on-chain hash: a synthetic,
  -- unique marker keeps the "one transaction = one operation" registry intact.
  hash := COALESCE(NULLIF(o->>'txHash',''), 'manual:'||p_order_id);
  nano := (round((o->>'amountTon')::numeric * 1000000000))::text;

  IF kind = 'deposit' THEN
    res := public.confirm_wallet_deposit((o->>'orderId')::uuid, hash, nano);
    UPDATE public.wallet_deposits
       SET verification_method = 'manual_admin', manually_approved = true,
           approved_by_admin = p_admin_id, approved_at = now(), approval_reason = p_reason
     WHERE id = (o->>'orderId')::uuid;
  ELSIF kind = 'premium_egg' THEN
    UPDATE public.pet_egg_orders
       SET tx_hash = COALESCE(NULLIF(tx_hash,''), hash),
           paid_at = COALESCE(paid_at, now()),
           status = CASE WHEN status = 'pending' THEN 'paid' ELSE status END,
           verification_method = 'manual_admin', manually_approved = true,
           approved_by_admin = p_admin_id, approved_at = now(), approval_reason = p_reason
     WHERE id = (o->>'orderId')::uuid;
    res := public.deliver_pet_egg_order((o->>'orderId')::uuid);
  ELSIF kind = 'battle_pass' THEN
    res := public.confirm_season_pass_order((o->>'orderId')::uuid, hash, nano);
    UPDATE public.season_pass_orders
       SET verification_method = 'manual_admin', manually_approved = true,
           approved_by_admin = p_admin_id, approved_at = now(), approval_reason = p_reason
     WHERE id = (o->>'orderId')::uuid;
  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_ORDER_TYPE';
  END IF;

  RETURN jsonb_build_object('status','delivered','orderId',p_order_id,'kind',kind,
    'previousStatus',prev_status,'txHash',hash,'result',res,
    'order', public.payment_recovery_order_json(p_order_id));
END;
$$;

REVOKE ALL ON FUNCTION public.payment_recovery_deliver(text, bigint, text, boolean) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- admin entry point
CREATE OR REPLACE FUNCTION public.admin_payment_recovery(
  p_admin_id bigint, p_action text, p_ref text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_kind text; v_page int; v_size int := 6; v_offset int; v_total bigint;
  v_rows jsonb; v_order jsonb; v_res jsonb; v_reason text; v_force boolean;
  v_reward_type text; v_reward_amount numeric; v_new jsonb;
BEGIN
  -- Backend-side authorisation: the Telegram buttons are never trusted alone.
  PERFORM public.admin_assert(p_admin_id);
  p_payload := COALESCE(p_payload, '{}'::jsonb);
  v_kind := NULLIF(p_payload->>'kind','');
  v_page := GREATEST(1, COALESCE((p_payload->>'page')::int, 1));
  v_size := GREATEST(1, LEAST(10, COALESCE((p_payload->>'size')::int, 6)));
  v_offset := (v_page - 1) * v_size;
  v_reason := NULLIF(p_payload->>'reason','');
  v_force := COALESCE((p_payload->>'force')::boolean, false);

  -- ---- read-only actions -------------------------------------------------
  IF p_action = 'list' THEN
    -- Only broken payments: anything already finished stays out of this module.
    WITH base AS (
      SELECT o.*, g.telegram_id, g.username, g.name
        FROM public.payment_recovery_orders o
        LEFT JOIN public.game_players g ON g.id = o.user_id
       WHERE NOT o.finished
         AND o.status <> 'rejected'
         AND (v_kind IS NULL OR o.kind = v_kind)
    )
    SELECT count(*) INTO v_total FROM base;
    WITH base AS (
      SELECT o.*, g.telegram_id, g.username, g.name
        FROM public.payment_recovery_orders o
        LEFT JOIN public.game_players g ON g.id = o.user_id
       WHERE NOT o.finished
         AND o.status <> 'rejected'
         AND (v_kind IS NULL OR o.kind = v_kind)
       ORDER BY o.created_at DESC
       OFFSET v_offset LIMIT v_size
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'orderId', b.order_id, 'shortId', left(b.order_id,8), 'kind', b.kind, 'typeLabel', b.type_label,
      'telegramId', b.telegram_id, 'username', b.username, 'name', b.name,
      'amountTon', b.amount_ton, 'status', b.status, 'createdAt', b.created_at,
      'productLabel', b.product_label, 'paymentConfirmed', (b.tx_hash IS NOT NULL AND b.tx_hash <> ''))
      ORDER BY b.created_at DESC), '[]'::jsonb) INTO v_rows FROM base b;
    RETURN jsonb_build_object('rows', v_rows, 'total', v_total, 'page', v_page, 'size', v_size,
      'pages', GREATEST(1, ceil(v_total::numeric / v_size)::int), 'kind', v_kind);
  END IF;

  IF p_action = 'resolved' THEN
    -- Manually approved / rejected history (kept apart from the pending queue).
    WITH base AS (
      SELECT o.*, g.telegram_id, g.username
        FROM public.payment_recovery_orders o
        LEFT JOIN public.game_players g ON g.id = o.user_id
       WHERE (CASE WHEN COALESCE(p_payload->>'mode','approved') = 'rejected'
                   THEN o.status = 'rejected' ELSE o.manually_approved END)
       ORDER BY COALESCE(o.approved_at, o.created_at) DESC
       LIMIT 15
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'orderId', b.order_id, 'shortId', left(b.order_id,8), 'kind', b.kind, 'typeLabel', b.type_label,
      'username', b.username, 'telegramId', b.telegram_id, 'amountTon', b.amount_ton, 'status', b.status,
      'approvedAt', b.approved_at, 'approvedByAdmin', b.approved_by_admin, 'reason', b.approval_reason)), '[]'::jsonb)
      INTO v_rows FROM base b;
    RETURN jsonb_build_object('rows', v_rows, 'mode', COALESCE(p_payload->>'mode','approved'));
  END IF;

  IF p_action = 'search' THEN
    WITH base AS (
      SELECT o.*, g.telegram_id, g.username, g.name
        FROM public.payment_recovery_orders o
        LEFT JOIN public.game_players g ON g.id = o.user_id
       WHERE p_ref IS NOT NULL AND p_ref <> ''
         AND (o.order_id = p_ref
              OR left(o.order_id, 8) = lower(replace(p_ref, '#',''))
              OR o.tx_hash = p_ref
              OR g.telegram_id::text = regexp_replace(p_ref, '\D', '', 'g')
              OR lower(COALESCE(g.username,'')) = lower(ltrim(p_ref,'@'))
              OR lower(COALESCE(g.name,'')) LIKE '%'||lower(p_ref)||'%')
       ORDER BY o.created_at DESC LIMIT 12
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'orderId', b.order_id, 'shortId', left(b.order_id,8), 'kind', b.kind, 'typeLabel', b.type_label,
      'telegramId', b.telegram_id, 'username', b.username, 'name', b.name,
      'amountTon', b.amount_ton, 'status', b.status, 'createdAt', b.created_at,
      'productLabel', b.product_label, 'paymentConfirmed', (b.tx_hash IS NOT NULL AND b.tx_hash <> ''))
      ORDER BY b.created_at DESC), '[]'::jsonb) INTO v_rows FROM base b;
    RETURN jsonb_build_object('rows', v_rows, 'query', p_ref);
  END IF;

  IF p_action = 'view' THEN
    v_order := public.payment_recovery_order_json(p_ref);
    IF v_order IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
    RETURN jsonb_build_object('order', v_order,
      'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('action',a.action,'at',a.created_at,'admin',a.admin_id,
                 'reason',a.reason,'previousStatus',a.previous_status,'newStatus',a.new_status) ORDER BY a.created_at DESC)
               FROM public.payment_recovery_audit a WHERE a.order_id = p_ref), '[]'::jsonb));
  END IF;

  IF p_action = 'audit' THEN
    RETURN jsonb_build_object('rows', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'orderId', left(a.order_id,8), 'action', a.action, 'type', a.transaction_type, 'amountTon', a.amount_ton,
      'rewardType', a.reward_type, 'rewardAmount', a.reward_amount, 'previousStatus', a.previous_status,
      'newStatus', a.new_status, 'reason', a.reason, 'admin', a.admin_id, 'at', a.created_at) ORDER BY a.created_at DESC)
      FROM (SELECT * FROM public.payment_recovery_audit ORDER BY created_at DESC LIMIT 15) a), '[]'::jsonb));
  END IF;

  -- ---- write actions -----------------------------------------------------
  v_order := public.payment_recovery_order_json(p_ref);
  IF v_order IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  IF p_action IN ('approve','retry') THEN
    v_res := public.payment_recovery_deliver(p_ref, p_admin_id, v_reason, v_force);
  ELSIF p_action = 'reject' THEN
    IF (v_order->>'finished')::boolean THEN
      RETURN jsonb_build_object('status','already_processed','orderId',p_ref);
    END IF;
    IF v_order->>'kind' = 'deposit' THEN
      UPDATE public.wallet_deposits SET status='rejected', approved_by_admin=p_admin_id,
             approved_at=now(), approval_reason=v_reason, verification_method='manual_admin'
       WHERE id = (v_order->>'orderId')::uuid;
    ELSIF v_order->>'kind' = 'premium_egg' THEN
      UPDATE public.pet_egg_orders SET status='rejected', approved_by_admin=p_admin_id,
             approved_at=now(), approval_reason=v_reason, verification_method='manual_admin'
       WHERE id = (v_order->>'orderId')::uuid;
    ELSE
      UPDATE public.season_pass_orders SET status='rejected', approved_by_admin=p_admin_id,
             approved_at=now(), approval_reason=v_reason, verification_method='manual_admin'
       WHERE id = (v_order->>'orderId')::uuid;
    END IF;
    v_res := jsonb_build_object('status','rejected','orderId',p_ref);
  ELSE
    RAISE EXCEPTION 'UNKNOWN_ACTION';
  END IF;

  v_new := public.payment_recovery_order_json(p_ref);
  v_reward_type := CASE v_order->>'kind' WHEN 'deposit' THEN 'forge_coins'
                                         WHEN 'premium_egg' THEN 'premium_egg'
                                         ELSE 'battle_pass' END;
  v_reward_amount := CASE WHEN v_order->>'kind' = 'deposit' AND v_res->>'status' = 'delivered'
                          THEN COALESCE((v_res->'result'->>'amountFc')::numeric, (v_order->>'expectedFc')::numeric)
                          ELSE NULL END;

  INSERT INTO public.payment_recovery_audit(admin_id, order_id, user_id, transaction_type, action, amount_ton,
    reward_type, reward_amount, previous_status, new_status, tx_hash, reason, result)
  VALUES (p_admin_id, p_ref, (v_order->>'userId')::uuid, v_order->>'kind', p_action,
    (v_order->>'amountTon')::numeric, v_reward_type, v_reward_amount, v_order->>'status',
    COALESCE(v_new->>'status', v_order->>'status'), COALESCE(v_res->>'txHash', v_order->>'txHash'), v_reason, v_res);

  PERFORM public.admin_log(p_admin_id, 'payment_recovery.'||p_action, 'payment_order', p_ref,
    jsonb_build_object('status', v_order->>'status'), v_res, v_reason, jsonb_build_object('financial', true));

  RETURN jsonb_build_object('result', v_res, 'order', v_new);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_payment_recovery(bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- realtime
-- The mini app must flip PENDING -> CREDITED/COMPLETED without a reload.
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.wallet_deposits; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.pet_egg_orders; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.season_pass_orders; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.player_season_pass; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;