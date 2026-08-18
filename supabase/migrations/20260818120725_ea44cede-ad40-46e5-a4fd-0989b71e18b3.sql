-- ============ MYTH TOKEN SALE ============
CREATE TABLE IF NOT EXISTS public.myth_sale_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  sale_status text NOT NULL DEFAULT 'paused',
  myth_per_ton numeric NOT NULL DEFAULT 20000,
  sale_allocation numeric NOT NULL DEFAULT 100000000,
  intent_minutes integer NOT NULL DEFAULT 15,
  min_purchase_myth numeric NOT NULL DEFAULT 1000,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.myth_sale_config TO service_role;
ALTER TABLE public.myth_sale_config ENABLE ROW LEVEL SECURITY;
INSERT INTO public.myth_sale_config (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.myth_burn_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  amount numeric NOT NULL CHECK (amount > 0),
  reason text,
  created_by bigint,
  supply_before numeric NOT NULL,
  supply_after numeric NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.myth_burn_history TO service_role;
ALTER TABLE public.myth_burn_history ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.myth_supply_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_type text NOT NULL CHECK (entry_type IN ('INITIAL_SUPPLY','SALE','BURN','ADMIN_ADJUSTMENT','REFUND')),
  amount numeric NOT NULL,
  user_id uuid,
  reference_id text,
  admin_telegram_id bigint,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.myth_supply_ledger TO service_role;
ALTER TABLE public.myth_supply_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.myth_payment_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  myth_amount numeric NOT NULL CHECK (myth_amount > 0),
  price_snapshot numeric NOT NULL,
  amount_ton numeric NOT NULL,
  amount_nano numeric NOT NULL,
  payment_address text NOT NULL,
  payment_comment text NOT NULL UNIQUE,
  wallet_address text,
  status text NOT NULL DEFAULT 'pending',
  tx_hash text,
  transaction_id uuid,
  idempotency_key text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
GRANT ALL ON public.myth_payment_intents TO service_role;
ALTER TABLE public.myth_payment_intents ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS myth_intents_pending_idx ON public.myth_payment_intents (status, expires_at);

CREATE TABLE IF NOT EXISTS public.myth_sale_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  myth_amount numeric NOT NULL CHECK (myth_amount > 0),
  price_snapshot numeric NOT NULL,
  amount_ton numeric NOT NULL,
  amount_nano numeric NOT NULL,
  payment_method text NOT NULL CHECK (payment_method IN ('INTERNAL','TONCONNECT')),
  status text NOT NULL DEFAULT 'CONFIRMED',
  tx_hash text,
  intent_id uuid,
  idempotency_key text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.myth_sale_transactions TO service_role;
ALTER TABLE public.myth_sale_transactions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS myth_sale_tx_user_idx ON public.myth_sale_transactions (user_id, created_at DESC);

-- Realtime
DO $$ BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.myth_sale_transactions; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.myth_burn_history; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- ============ AGGREGATES ============
CREATE OR REPLACE FUNCTION public.myth_expire_payment_intents()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n integer;
BEGIN
  UPDATE public.myth_payment_intents
     SET status = 'expired', updated_at = now()
   WHERE status = 'pending' AND expires_at <= now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION public.myth_sale_stats()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.myth_sale_config; tok public.myth_token_settings;
  v_sold numeric; v_burned numeric; v_reserved numeric; v_raised numeric; v_avail numeric; v_last timestamptz;
BEGIN
  PERFORM public.myth_expire_payment_intents();
  SELECT * INTO cfg FROM public.myth_sale_config WHERE id;
  SELECT * INTO tok FROM public.myth_token_settings WHERE id;
  SELECT COALESCE(SUM(myth_amount),0), COALESCE(SUM(amount_ton),0), MAX(created_at)
    INTO v_sold, v_raised, v_last FROM public.myth_sale_transactions WHERE status = 'CONFIRMED';
  SELECT COALESCE(SUM(amount),0) INTO v_burned FROM public.myth_burn_history;
  SELECT COALESCE(SUM(myth_amount),0) INTO v_reserved FROM public.myth_payment_intents
   WHERE status = 'pending' AND expires_at > now();
  v_avail := GREATEST(0, cfg.sale_allocation - v_sold - v_burned - v_reserved);
  RETURN jsonb_build_object(
    'symbol', tok.token_symbol, 'name', tok.token_name,
    'saleStatus', cfg.sale_status,
    'mythPerTon', cfg.myth_per_ton,
    'minPurchase', cfg.min_purchase_myth,
    'intentMinutes', cfg.intent_minutes,
    'initialSupply', tok.total_supply,
    'saleAllocation', cfg.sale_allocation,
    'effectiveSupply', GREATEST(0, tok.total_supply - v_burned),
    'sold', round(v_sold, 4),
    'burned', round(v_burned, 4),
    'reserved', round(v_reserved, 4),
    'available', round(v_avail, 4),
    'tonRaised', round(v_raised, 9),
    'burnedPercent', CASE WHEN tok.total_supply > 0 THEN round(v_burned / tok.total_supply * 100, 4) ELSE 0 END,
    'soldPercent', CASE WHEN cfg.sale_allocation > 0 THEN round(v_sold / cfg.sale_allocation * 100, 4) ELSE 0 END,
    'lastSaleAt', v_last,
    'serverTime', now()
  );
END $$;

CREATE OR REPLACE FUNCTION public.get_myth_sale_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.game_players%rowtype; v_stats jsonb;
BEGIN
  v_stats := public.myth_sale_stats();
  SELECT * INTO g FROM public.game_players WHERE telegram_id = p_telegram_id;
  RETURN jsonb_build_object(
    'stats', v_stats,
    'player', CASE WHEN g.id IS NULL THEN jsonb_build_object('mythBalance', 0, 'internalTon', 0)
      ELSE jsonb_build_object(
        'mythBalance', round(COALESCE((SELECT amount FROM public.myth_balances WHERE user_id = g.id), 0), 4),
        'internalTon', round(COALESCE(g.ton_balance, 0), 9)) END,
    'purchases', CASE WHEN g.id IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', t.id, 'mythAmount', t.myth_amount, 'amountTon', t.amount_ton,
        'method', t.payment_method, 'status', t.status, 'createdAt', t.created_at) ORDER BY t.created_at DESC)
      FROM (SELECT * FROM public.myth_sale_transactions WHERE user_id = g.id ORDER BY created_at DESC LIMIT 20) t), '[]'::jsonb) END,
    'pendingIntent', CASE WHEN g.id IS NULL THEN NULL ELSE (
      SELECT jsonb_build_object('id', i.id, 'mythAmount', i.myth_amount, 'amountTon', i.amount_ton,
        'amountNano', i.amount_nano::bigint::text, 'paymentAddress', i.payment_address,
        'paymentComment', i.payment_comment, 'expiresAt', i.expires_at)
      FROM public.myth_payment_intents i
      WHERE i.user_id = g.id AND i.status = 'pending' AND i.expires_at > now()
      ORDER BY i.created_at DESC LIMIT 1) END,
    'burns', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', b.id, 'amount', b.amount, 'reason', b.reason,
        'createdAt', b.created_at) ORDER BY b.created_at DESC)
      FROM (SELECT * FROM public.myth_burn_history ORDER BY created_at DESC LIMIT 10) b), '[]'::jsonb)
  );
END $$;

-- ============ PURCHASE (INTERNAL OR TONCONNECT INTENT) ============
CREATE OR REPLACE FUNCTION public.myth_start_purchase(
  p_telegram_id bigint, p_myth_amount numeric, p_wallet_address text DEFAULT NULL, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.game_players%rowtype; cfg public.myth_sale_config; stats jsonb;
  v_amount numeric; v_cost numeric; v_nano numeric; v_bal numeric; v_after numeric;
  v_tx public.myth_sale_transactions; v_intent public.myth_payment_intents; hot text; v_key text;
BEGIN
  v_amount := floor(COALESCE(p_myth_amount, 0));
  SELECT * INTO g FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(g.banned, false) THEN RAISE EXCEPTION 'ACCOUNT_BANNED'; END IF;

  SELECT * INTO cfg FROM public.myth_sale_config WHERE id FOR UPDATE;
  IF cfg.sale_status <> 'active' THEN RAISE EXCEPTION 'SALE_PAUSED'; END IF;
  IF v_amount < cfg.min_purchase_myth THEN RAISE EXCEPTION 'MIN_PURCHASE_NOT_MET'; END IF;
  IF cfg.myth_per_ton <= 0 THEN RAISE EXCEPTION 'SALE_PAUSED'; END IF;

  v_key := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');
  IF v_key IS NOT NULL THEN
    SELECT * INTO v_tx FROM public.myth_sale_transactions WHERE idempotency_key = v_key;
    IF v_tx.id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'method', 'INTERNAL', 'duplicate', true,
        'transactionId', v_tx.id, 'mythAmount', v_tx.myth_amount, 'amountTon', v_tx.amount_ton,
        'stats', public.myth_sale_stats());
    END IF;
    SELECT * INTO v_intent FROM public.myth_payment_intents WHERE idempotency_key = v_key AND status = 'pending' AND expires_at > now();
    IF v_intent.id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'method', 'TONCONNECT', 'duplicate', true,
        'paymentId', v_intent.id, 'mythAmount', v_intent.myth_amount, 'amountTon', v_intent.amount_ton,
        'amountNano', v_intent.amount_nano::bigint::text, 'paymentAddress', v_intent.payment_address,
        'paymentComment', v_intent.payment_comment, 'expiresAt', v_intent.expires_at, 'stats', public.myth_sale_stats());
    END IF;
  END IF;

  stats := public.myth_sale_stats();
  IF v_amount > (stats->>'available')::numeric THEN RAISE EXCEPTION 'INSUFFICIENT_SUPPLY'; END IF;

  v_cost := round(v_amount / cfg.myth_per_ton, 9);
  v_nano := ceil(v_amount / cfg.myth_per_ton * 1000000000);
  v_cost := round(v_nano / 1000000000, 9);
  IF v_nano <= 0 THEN RAISE EXCEPTION 'MIN_PURCHASE_NOT_MET'; END IF;
  v_bal := round(COALESCE(g.ton_balance, 0), 9);

  -- RULE: internal TON only when it covers 100% of the cost. Never split payments.
  IF v_bal >= v_cost THEN
    UPDATE public.game_players SET ton_balance = round(COALESCE(ton_balance,0) - v_cost, 9)
      WHERE id = g.id RETURNING ton_balance INTO v_after;
    INSERT INTO public.ton_reward_ledger(user_id, amount_ton, direction, source_type, source_id, status, note, balance_after)
      VALUES (g.id, v_cost, 'debit', 'myth_purchase', NULL, 'completed', 'MYTH token purchase', v_after);

    INSERT INTO public.myth_sale_transactions(user_id, myth_amount, price_snapshot, amount_ton, amount_nano,
      payment_method, status, idempotency_key)
      VALUES (g.id, v_amount, cfg.myth_per_ton, v_cost, v_nano, 'INTERNAL', 'CONFIRMED', v_key)
      RETURNING * INTO v_tx;

    INSERT INTO public.myth_balances(user_id, amount) VALUES (g.id, 0) ON CONFLICT (user_id) DO NOTHING;
    UPDATE public.myth_balances SET amount = amount + v_amount, updated_at = now() WHERE user_id = g.id;
    INSERT INTO public.myth_ledger(user_id, direction, amount, reason) VALUES (g.id, 'credit', v_amount, 'token_sale');
    INSERT INTO public.myth_supply_ledger(entry_type, amount, user_id, reference_id, note)
      VALUES ('SALE', v_amount, g.id, v_tx.id::text, 'internal TON purchase');
    UPDATE public.myth_sale_transactions SET id = id WHERE id = v_tx.id;

    RETURN jsonb_build_object('ok', true, 'method', 'INTERNAL', 'transactionId', v_tx.id,
      'mythAmount', v_amount, 'amountTon', v_cost, 'internalTon', round(v_after, 9),
      'stats', public.myth_sale_stats());
  END IF;

  -- FALLBACK: external wallet pays 100%; internal balance stays untouched.
  IF p_wallet_address IS NULL OR length(btrim(p_wallet_address)) < 10 THEN RAISE EXCEPTION 'WALLET_REQUIRED'; END IF;
  SELECT value_text INTO hot FROM public.wallet_settings WHERE key = 'ton_hot_wallet';
  IF hot IS NULL OR btrim(hot) = '' THEN RAISE EXCEPTION 'WALLET_NOT_CONFIGURED'; END IF;

  INSERT INTO public.myth_payment_intents(user_id, myth_amount, price_snapshot, amount_ton, amount_nano,
    payment_address, payment_comment, wallet_address, expires_at, idempotency_key)
  VALUES (g.id, v_amount, cfg.myth_per_ton, v_cost, v_nano, btrim(hot),
    'MYTH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)), btrim(p_wallet_address),
    now() + make_interval(mins => GREATEST(5, cfg.intent_minutes)), v_key)
  RETURNING * INTO v_intent;

  RETURN jsonb_build_object('ok', true, 'method', 'TONCONNECT', 'paymentId', v_intent.id,
    'mythAmount', v_amount, 'amountTon', v_cost, 'amountNano', v_intent.amount_nano::bigint::text,
    'paymentAddress', v_intent.payment_address, 'paymentComment', v_intent.payment_comment,
    'expiresAt', v_intent.expires_at, 'internalTon', v_bal, 'stats', public.myth_sale_stats());
END $$;

CREATE OR REPLACE FUNCTION public.myth_confirm_payment_intent(p_payment_id uuid, p_tx_hash text, p_amount_nano numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i public.myth_payment_intents; v_tx public.myth_sale_transactions; stats jsonb; min_nano numeric;
BEGIN
  IF p_tx_hash IS NULL OR btrim(p_tx_hash) = '' THEN RAISE EXCEPTION 'TX_HASH_REQUIRED'; END IF;
  SELECT * INTO i FROM public.myth_payment_intents WHERE id = p_payment_id FOR UPDATE;
  IF i.id IS NULL THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;
  IF i.status = 'confirmed' THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'status', 'confirmed', 'transactionId', i.transaction_id);
  END IF;
  IF i.status <> 'pending' THEN RAISE EXCEPTION 'PAYMENT_EXPIRED'; END IF;

  min_nano := i.amount_nano * 0.97;
  IF COALESCE(p_amount_nano, 0) < min_nano THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_MISMATCH'; END IF;

  PERFORM 1 FROM public.myth_sale_config WHERE id FOR UPDATE;
  stats := public.myth_sale_stats();
  IF i.myth_amount > (stats->>'available')::numeric + i.myth_amount THEN RAISE EXCEPTION 'INSUFFICIENT_SUPPLY'; END IF;

  INSERT INTO public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  VALUES (btrim(p_tx_hash), i.user_id, 'myth_purchase', p_amount_nano, i.id::text);

  INSERT INTO public.myth_sale_transactions(user_id, myth_amount, price_snapshot, amount_ton, amount_nano,
    payment_method, status, tx_hash, intent_id)
  VALUES (i.user_id, i.myth_amount, i.price_snapshot, i.amount_ton, i.amount_nano, 'TONCONNECT', 'CONFIRMED',
    btrim(p_tx_hash), i.id)
  RETURNING * INTO v_tx;

  INSERT INTO public.myth_balances(user_id, amount) VALUES (i.user_id, 0) ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.myth_balances SET amount = amount + i.myth_amount, updated_at = now() WHERE user_id = i.user_id;
  INSERT INTO public.myth_ledger(user_id, direction, amount, reason) VALUES (i.user_id, 'credit', i.myth_amount, 'token_sale');
  INSERT INTO public.myth_supply_ledger(entry_type, amount, user_id, reference_id, note)
    VALUES ('SALE', i.myth_amount, i.user_id, v_tx.id::text, 'tonconnect purchase');

  UPDATE public.myth_payment_intents
     SET status = 'confirmed', tx_hash = btrim(p_tx_hash), transaction_id = v_tx.id, updated_at = now()
   WHERE id = i.id;

  RETURN jsonb_build_object('ok', true, 'status', 'confirmed', 'transactionId', v_tx.id,
    'mythAmount', i.myth_amount, 'amountTon', i.amount_ton, 'stats', public.myth_sale_stats());
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'DUPLICATE_TRANSACTION';
END $$;

CREATE OR REPLACE FUNCTION public.myth_pending_payment_intents(p_max_age_minutes integer DEFAULT 240)
RETURNS TABLE(id uuid, user_id uuid, myth_amount numeric, amount_nano numeric, payment_comment text, created_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT i.id, i.user_id, i.myth_amount, i.amount_nano, i.payment_comment, i.created_at
    FROM public.myth_payment_intents i
   WHERE i.status IN ('pending','expired')
     AND i.tx_hash IS NULL
     AND i.created_at > now() - make_interval(mins => GREATEST(15, p_max_age_minutes))
   ORDER BY i.created_at DESC LIMIT 200;
$$;

-- ============ ADMIN ============
CREATE OR REPLACE FUNCTION public.admin_myth_sale_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  RETURN public.myth_sale_stats() || jsonb_build_object(
    'recentSales', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT t.myth_amount, t.amount_ton, t.payment_method, t.created_at,
               COALESCE(p.display_name, p.username, '-') AS player, p.telegram_id
          FROM public.myth_sale_transactions t LEFT JOIN public.game_players p ON p.id = t.user_id
         WHERE t.status = 'CONFIRMED' ORDER BY t.created_at DESC LIMIT 10) x), '[]'::jsonb),
    'topBuyers', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT SUM(t.myth_amount) AS myth_amount, SUM(t.amount_ton) AS amount_ton,
               COALESCE(p.display_name, p.username, '-') AS player, p.telegram_id
          FROM public.myth_sale_transactions t LEFT JOIN public.game_players p ON p.id = t.user_id
         WHERE t.status = 'CONFIRMED' GROUP BY p.display_name, p.username, p.telegram_id
         ORDER BY 1 DESC LIMIT 10) x), '[]'::jsonb),
    'activeIntents', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT i.myth_amount, i.amount_ton, i.expires_at, i.payment_comment, p.telegram_id
          FROM public.myth_payment_intents i LEFT JOIN public.game_players p ON p.id = i.user_id
         WHERE i.status = 'pending' AND i.expires_at > now() ORDER BY i.created_at DESC LIMIT 10) x), '[]'::jsonb),
    'failedIntents', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT i.myth_amount, i.amount_ton, i.status, i.created_at, p.telegram_id
          FROM public.myth_payment_intents i LEFT JOIN public.game_players p ON p.id = i.user_id
         WHERE i.status IN ('expired','cancelled') ORDER BY i.created_at DESC LIMIT 10) x), '[]'::jsonb),
    'burnHistory', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT b.amount, b.reason, b.created_at, b.supply_before, b.supply_after
          FROM public.myth_burn_history b ORDER BY b.created_at DESC LIMIT 10) x), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_sale_set(p_admin_id bigint, p_key text, p_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.myth_sale_config; v_old numeric; v_sold numeric; v_burned numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO cfg FROM public.myth_sale_config WHERE id FOR UPDATE;
  IF p_key = 'price' THEN
    IF COALESCE(p_value,0) <= 0 THEN RAISE EXCEPTION 'MYTH_INVALID_PRICE'; END IF;
    v_old := cfg.myth_per_ton;
    UPDATE public.myth_sale_config SET myth_per_ton = p_value, updated_at = now() WHERE id;
  ELSIF p_key = 'allocation' THEN
    SELECT COALESCE(SUM(myth_amount),0) INTO v_sold FROM public.myth_sale_transactions WHERE status = 'CONFIRMED';
    SELECT COALESCE(SUM(amount),0) INTO v_burned FROM public.myth_burn_history;
    IF COALESCE(p_value,0) < v_sold + v_burned THEN RAISE EXCEPTION 'MYTH_ALLOCATION_TOO_LOW'; END IF;
    v_old := cfg.sale_allocation;
    UPDATE public.myth_sale_config SET sale_allocation = p_value, updated_at = now() WHERE id;
  ELSIF p_key = 'minutes' THEN
    v_old := cfg.intent_minutes;
    UPDATE public.myth_sale_config SET intent_minutes = GREATEST(5, COALESCE(p_value,15))::integer, updated_at = now() WHERE id;
  ELSIF p_key = 'min_purchase' THEN
    v_old := cfg.min_purchase_myth;
    UPDATE public.myth_sale_config SET min_purchase_myth = GREATEST(1, COALESCE(p_value,1)), updated_at = now() WHERE id;
  ELSE
    RAISE EXCEPTION 'MYTH_INVALID_KEY';
  END IF;
  PERFORM admin_log(p_admin_id, 'myth_sale_' || CASE WHEN p_key = 'price' THEN 'price_changed' ELSE 'config_changed' END,
    jsonb_build_object('key', p_key, 'oldValue', v_old, 'newValue', p_value));
  RETURN public.admin_myth_sale_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_sale_status(p_admin_id bigint, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old text;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_status NOT IN ('active','paused') THEN RAISE EXCEPTION 'MYTH_INVALID_STATUS'; END IF;
  SELECT sale_status INTO v_old FROM public.myth_sale_config WHERE id FOR UPDATE;
  UPDATE public.myth_sale_config SET sale_status = p_status, updated_at = now() WHERE id;
  PERFORM admin_log(p_admin_id, CASE WHEN p_status = 'active' THEN 'myth_sale_started' ELSE 'myth_sale_paused' END,
    jsonb_build_object('oldValue', v_old, 'newValue', p_status));
  RETURN public.admin_myth_sale_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_burn(p_admin_id bigint, p_amount numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE stats jsonb; v_amount numeric; v_before numeric; v_after numeric; v_burn public.myth_burn_history;
BEGIN
  PERFORM admin_assert(p_admin_id);
  v_amount := floor(COALESCE(p_amount, 0));
  IF v_amount <= 0 THEN RAISE EXCEPTION 'MYTH_INVALID_AMOUNT'; END IF;
  PERFORM 1 FROM public.myth_sale_config WHERE id FOR UPDATE;
  stats := public.myth_sale_stats();
  IF v_amount > (stats->>'available')::numeric THEN RAISE EXCEPTION 'INSUFFICIENT_SUPPLY'; END IF;
  v_before := (stats->>'effectiveSupply')::numeric;
  v_after := v_before - v_amount;
  INSERT INTO public.myth_burn_history(amount, reason, created_by, supply_before, supply_after)
  VALUES (v_amount, NULLIF(btrim(COALESCE(p_reason,'')), ''), p_admin_id, v_before, v_after)
  RETURNING * INTO v_burn;
  INSERT INTO public.myth_supply_ledger(entry_type, amount, admin_telegram_id, reference_id, note)
  VALUES ('BURN', v_amount, p_admin_id, v_burn.id::text, 'INTERNAL_SUPPLY_BURN');
  PERFORM admin_log(p_admin_id, 'myth_burned', jsonb_build_object('amount', v_amount, 'reason', p_reason,
    'supplyBefore', v_before, 'supplyAfter', v_after, 'kind', 'INTERNAL_SUPPLY_BURN'));
  RETURN public.admin_myth_sale_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_supply_adjust(p_admin_id bigint, p_amount numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF COALESCE(p_amount,0) = 0 THEN RAISE EXCEPTION 'MYTH_INVALID_AMOUNT'; END IF;
  INSERT INTO public.myth_supply_ledger(entry_type, amount, admin_telegram_id, note)
  VALUES ('ADMIN_ADJUSTMENT', p_amount, p_admin_id, NULLIF(btrim(COALESCE(p_reason,'')), ''));
  PERFORM admin_log(p_admin_id, 'myth_supply_adjusted', jsonb_build_object('amount', p_amount, 'reason', p_reason));
  RETURN public.admin_myth_sale_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_sale_history(p_admin_id bigint, p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  RETURN COALESCE((SELECT jsonb_agg(x) FROM (
    SELECT t.myth_amount, t.amount_ton, t.payment_method, t.status, t.created_at, t.tx_hash,
           COALESCE(p.display_name, p.username, '-') AS player, p.telegram_id
      FROM public.myth_sale_transactions t LEFT JOIN public.game_players p ON p.id = t.user_id
     ORDER BY t.created_at DESC LIMIT GREATEST(1, LEAST(100, COALESCE(p_limit, 30)))) x), '[]'::jsonb);
END $$;

GRANT EXECUTE ON FUNCTION public.get_myth_sale_dashboard(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.myth_sale_stats() TO service_role;
GRANT EXECUTE ON FUNCTION public.myth_start_purchase(bigint, numeric, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.myth_confirm_payment_intent(uuid, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.myth_expire_payment_intents() TO service_role;
GRANT EXECUTE ON FUNCTION public.myth_pending_payment_intents(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_sale_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_sale_set(bigint, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_sale_status(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_burn(bigint, numeric, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_supply_adjust(bigint, numeric, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_sale_history(bigint, integer) TO service_role;