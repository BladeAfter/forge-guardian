-- 🔑 COMPRA DE CHAVES RARAS COM TON (saldo interno primeiro, TonConnect como fallback).
-- Preços, limites por passe, estoque de compras e entrega são 100% server-side.

CREATE TABLE IF NOT EXISTS public.tower_key_shop_config (
  key_code text PRIMARY KEY,
  price_ton numeric(20,9) NOT NULL CHECK (price_ton > 0),
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.tower_key_shop_config TO authenticated;
GRANT ALL ON public.tower_key_shop_config TO service_role;
ALTER TABLE public.tower_key_shop_config ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='tower_key_shop_config' AND policyname='tower_key_shop_config_read') THEN
    CREATE POLICY tower_key_shop_config_read ON public.tower_key_shop_config FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

INSERT INTO public.tower_key_shop_config(key_code, price_ton) VALUES
  ('eternity_key', 1), ('void_key', 5), ('celestial_key', 10)
ON CONFLICT (key_code) DO UPDATE SET price_ton = EXCLUDED.price_ton, enabled = true, updated_at = now();

CREATE TABLE IF NOT EXISTS public.tower_key_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  telegram_id bigint NOT NULL,
  key_code text NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  price_ton numeric(20,9) NOT NULL,
  expected_nanoton text NOT NULL,
  payment_method text NOT NULL DEFAULT 'ton_connect',
  status text NOT NULL DEFAULT 'pending',
  payment_address text,
  payment_comment text,
  tx_hash text,
  idempotency_key text UNIQUE,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tower_key_purchases_user_idx ON public.tower_key_purchases(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS tower_key_purchases_tx_idx ON public.tower_key_purchases(tx_hash) WHERE tx_hash IS NOT NULL;

GRANT SELECT ON public.tower_key_purchases TO authenticated;
GRANT ALL ON public.tower_key_purchases TO service_role;
ALTER TABLE public.tower_key_purchases ENABLE ROW LEVEL SECURITY;

-- Limite de compras: 10 com passe Legendary (20 TON), 5 com Adventurer (5 TON), 0 sem passe V2 pago.
CREATE OR REPLACE FUNCTION public.tower_key_purchase_limit(p_user_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.player_season_pass ps
                  WHERE ps.user_id = p_user_id AND COALESCE(ps.pass_version,1) >= 2
                    AND (COALESCE(ps.legendary_owned,false) OR ps.tier = 'legendary')) THEN 10
    WHEN EXISTS (SELECT 1 FROM public.player_season_pass ps
                  WHERE ps.user_id = p_user_id AND COALESCE(ps.pass_version,1) >= 2
                    AND (COALESCE(ps.adventurer_owned,false) OR ps.tier IN ('adventurer','legendary'))) THEN 5
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.tower_key_purchases_used(p_user_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(count(*),0)::integer FROM public.tower_key_purchases
   WHERE user_id = p_user_id AND status IN ('paid','delivered');
$$;

CREATE OR REPLACE FUNCTION public.tower_key_shop_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; v_limit integer; v_used integer;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_limit := public.tower_key_purchase_limit(u.id);
  v_used := public.tower_key_purchases_used(u.id);
  RETURN jsonb_build_object(
    'availableTon', round(COALESCE(u.ton_balance,0), 9),
    'purchaseLimit', v_limit,
    'purchasesUsed', v_used,
    'purchasesRemaining', GREATEST(0, v_limit - v_used),
    'limitReached', (v_limit > 0 AND v_used >= v_limit),
    'passRequired', (v_limit = 0),
    'keys', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'keyCode', c.key_code,
        'priceTon', c.price_ton,
        'enabled', c.enabled,
        'owned', COALESCE((SELECT quantity FROM public.player_inventory i
                            WHERE i.user_id = u.id AND i.item_type = 'tower_key' AND i.item_code = c.key_code), 0)
      ) ORDER BY c.price_ton), '[]'::jsonb) FROM public.tower_key_shop_config c),
    'pendingOrder', (SELECT jsonb_build_object('orderId', p.id, 'keyCode', p.key_code, 'amountNano', p.expected_nanoton,
        'paymentAddress', p.payment_address, 'paymentComment', p.payment_comment, 'expiresAt', p.expires_at)
      FROM public.tower_key_purchases p
      WHERE p.user_id = u.id AND p.status = 'pending' AND p.expires_at > now()
      ORDER BY p.created_at DESC LIMIT 1)
  );
END $$;

CREATE OR REPLACE FUNCTION public.tower_key_deliver(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.tower_key_purchases;
BEGIN
  SELECT * INTO o FROM public.tower_key_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'KEY_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('delivered', true, 'keyCode', o.key_code, 'quantity', o.quantity, 'duplicate', true);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'KEY_ORDER_NOT_PAID'; END IF;

  INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
  VALUES (o.user_id, 'tower_key', o.key_code, GREATEST(o.quantity, 1))
  ON CONFLICT (user_id, item_type, item_code)
    DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();

  UPDATE public.tower_key_purchases SET status = 'delivered', delivered_at = now() WHERE id = o.id;
  RETURN jsonb_build_object('delivered', true, 'keyCode', o.key_code, 'quantity', GREATEST(o.quantity,1));
END $$;

CREATE OR REPLACE FUNCTION public.tower_key_start_purchase(
  p_telegram_id bigint, p_key_code text, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.tower_key_shop_config; o public.tower_key_purchases;
        v_price numeric; v_nano text; v_limit integer; v_used integer; v_delivery jsonb;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  SELECT * INTO c FROM public.tower_key_shop_config WHERE key_code = btrim(COALESCE(p_key_code,''));
  IF c.key_code IS NULL OR NOT c.enabled THEN RAISE EXCEPTION 'KEY_NOT_PURCHASABLE'; END IF;

  SELECT * INTO o FROM public.tower_key_purchases WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NOT NULL AND o.status IN ('paid','delivered') THEN
    RETURN jsonb_build_object('status','completed','method',o.payment_method,'orderId',o.id,'keyCode',o.key_code,
      'priceTon',o.price_ton,'duplicate',true,'state',public.tower_key_shop_state(p_telegram_id));
  END IF;

  v_limit := public.tower_key_purchase_limit(u.id);
  IF v_limit <= 0 THEN RAISE EXCEPTION 'KEY_PURCHASE_REQUIRES_PASS'; END IF;
  v_used := public.tower_key_purchases_used(u.id);
  IF v_used >= v_limit THEN RAISE EXCEPTION 'KEY_PURCHASE_LIMIT_REACHED'; END IF;

  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;

  IF o.id IS NULL THEN
    SELECT * INTO o FROM public.tower_key_purchases
     WHERE user_id = u.id AND status = 'pending' AND key_code = c.key_code AND expires_at > now()
     ORDER BY created_at DESC LIMIT 1;
  END IF;

  -- 1) Saldo interno de TON cobre o preço: débito + entrega imediata.
  IF round(COALESCE(u.ton_balance,0), 9) >= round(v_price, 9) THEN
    UPDATE public.game_players SET ton_balance = round(COALESCE(ton_balance,0) - v_price, 9), updated_at = now()
     WHERE id = u.id;
    IF o.id IS NOT NULL AND o.status = 'pending' THEN
      UPDATE public.tower_key_purchases
         SET status='paid', payment_method='internal_ton', confirmed_at=now(), price_ton=v_price, expected_nanoton=v_nano
       WHERE id = o.id RETURNING * INTO o;
    ELSE
      INSERT INTO public.tower_key_purchases(user_id, telegram_id, key_code, price_ton, expected_nanoton,
        payment_method, status, idempotency_key, confirmed_at)
      VALUES (u.id, p_telegram_id, c.key_code, v_price, v_nano, 'internal_ton', 'paid', p_idempotency_key, now())
      RETURNING * INTO o;
    END IF;
    v_delivery := public.tower_key_deliver(o.id);
    RETURN jsonb_build_object('status','completed','method','internal_ton','orderId',o.id,'keyCode',o.key_code,
      'priceTon',v_price,'delivery',v_delivery,'state',public.tower_key_shop_state(p_telegram_id));
  END IF;

  -- 2) Sem saldo interno: TonConnect. A chave só é entregue após confirmação on-chain.
  IF o.id IS NOT NULL AND o.status = 'pending' THEN
    RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,'keyCode',o.key_code,
      'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(COALESCE(u.ton_balance,0), 9));
  END IF;

  INSERT INTO public.tower_key_purchases(user_id, telegram_id, key_code, price_ton, expected_nanoton,
    payment_method, status, payment_address, payment_comment, idempotency_key)
  VALUES (u.id, p_telegram_id, c.key_code, v_price, v_nano, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'mythreon_key:' || gen_random_uuid(), p_idempotency_key)
  RETURNING * INTO o;

  RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,'keyCode',o.key_code,
    'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(COALESCE(u.ton_balance,0), 9));
END $$;

CREATE OR REPLACE FUNCTION public.tower_key_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.tower_key_purchases; v_min numeric;
BEGIN
  IF p_tx_hash IS NULL OR btrim(p_tx_hash) = '' THEN RAISE EXCEPTION 'TX_HASH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.tower_key_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'KEY_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('status','already_processed','orderId',o.id,'keyCode',o.key_code);
  END IF;
  IF EXISTS (SELECT 1 FROM public.tower_key_purchases WHERE tx_hash = btrim(p_tx_hash) AND id <> o.id) THEN
    RAISE EXCEPTION 'TX_ALREADY_USED';
  END IF;
  v_min := (o.expected_nanoton::numeric * 97) / 100;
  IF COALESCE(p_amount_nano::numeric, 0) < v_min THEN RAISE EXCEPTION 'INVALID_PAYMENT_AMOUNT'; END IF;

  INSERT INTO public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  VALUES (btrim(p_tx_hash), o.user_id, 'tower_key', p_amount_nano::numeric, o.id::text)
  ON CONFLICT (tx_hash) DO NOTHING;

  IF o.status = 'pending' THEN
    UPDATE public.tower_key_purchases
       SET status='paid', tx_hash=btrim(p_tx_hash), confirmed_at=COALESCE(confirmed_at, now())
     WHERE id = o.id;
  END IF;
  RETURN public.tower_key_deliver(o.id) || jsonb_build_object('status','completed','orderId',o.id);
END $$;

GRANT EXECUTE ON FUNCTION public.tower_key_purchase_limit(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tower_key_purchases_used(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tower_key_shop_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.tower_key_start_purchase(bigint, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.tower_key_confirm_order(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.tower_key_deliver(uuid) TO service_role;
