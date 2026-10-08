
-- ============================================================= TON MINES
CREATE TABLE public.ton_mine_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  paused boolean NOT NULL DEFAULT false,
  admin_only boolean NOT NULL DEFAULT true,
  allowed_telegram_ids bigint[] NOT NULL DEFAULT ARRAY[8118569391]::bigint[],
  loyalty_enabled boolean NOT NULL DEFAULT true,
  bonus_30_pct numeric NOT NULL DEFAULT 5,
  bonus_60_pct numeric NOT NULL DEFAULT 10,
  max_total_per_player integer NOT NULL DEFAULT 4,
  payment_ttl_minutes integer NOT NULL DEFAULT 30,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.ton_mine_settings TO service_role;
ALTER TABLE public.ton_mine_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.ton_mine_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mine_key text NOT NULL UNIQUE,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  image_url text,
  price_ton numeric NOT NULL CHECK (price_ton > 0),
  daily_ton numeric NOT NULL CHECK (daily_ton > 0),
  storage_days integer NOT NULL DEFAULT 7 CHECK (storage_days BETWEEN 1 AND 60),
  max_per_player integer NOT NULL DEFAULT 1 CHECK (max_per_player >= 0),
  sort_order integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  paused boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.ton_mine_templates TO service_role;
ALTER TABLE public.ton_mine_templates ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.ton_mine_holdings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.ton_mine_templates(id) ON DELETE RESTRICT,
  purchased_at timestamptz NOT NULL DEFAULT now(),
  last_accrual_at timestamptz NOT NULL DEFAULT now(),
  stored_ton numeric NOT NULL DEFAULT 0,
  total_claimed_ton numeric NOT NULL DEFAULT 0,
  paid_ton numeric NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ton_mine_holdings_user_idx ON public.ton_mine_holdings(user_id);
GRANT ALL ON public.ton_mine_holdings TO service_role;
ALTER TABLE public.ton_mine_holdings ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.ton_mine_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.ton_mine_templates(id) ON DELETE RESTRICT,
  price_ton numeric NOT NULL,
  amount_nano text NOT NULL,
  payment_address text NOT NULL,
  payment_comment text NOT NULL,
  idempotency_key text UNIQUE,
  status text NOT NULL DEFAULT 'pending',
  tx_hash text,
  paid_at timestamptz,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  holding_id uuid,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ton_mine_orders_user_idx ON public.ton_mine_orders(user_id, status);
GRANT ALL ON public.ton_mine_orders TO service_role;
ALTER TABLE public.ton_mine_orders ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.ton_mine_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  holding_id uuid REFERENCES public.ton_mine_holdings(id) ON DELETE SET NULL,
  template_id uuid REFERENCES public.ton_mine_templates(id) ON DELETE SET NULL,
  amount_ton numeric NOT NULL,
  claim_type text NOT NULL DEFAULT 'single',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ton_mine_claims_user_idx ON public.ton_mine_claims(user_id, created_at DESC);
GRANT ALL ON public.ton_mine_claims TO service_role;
ALTER TABLE public.ton_mine_claims ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER ton_mine_settings_updated BEFORE UPDATE ON public.ton_mine_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER ton_mine_templates_updated BEFORE UPDATE ON public.ton_mine_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER ton_mine_holdings_updated BEFORE UPDATE ON public.ton_mine_holdings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER ton_mine_orders_updated BEFORE UPDATE ON public.ton_mine_orders
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.ton_mine_settings(id) VALUES (true) ON CONFLICT DO NOTHING;

INSERT INTO public.ton_mine_templates(mine_key, name, description, image_url, price_ton, daily_ton, storage_days, max_per_player, sort_order) VALUES
  ('iron', 'Mina de Ferro Arcano', 'A entrada mais acessível ao subsolo de Mythreon. Veios de ferro encantado rendem TON de forma constante, dia após dia.', '/__l5e/assets-v1/2a62fe24-96d2-4fa6-a496-2b2de32c8d3f/mine-iron.jpg', 5, 0.11, 7, 1, 1),
  ('crystal', 'Mina de Cristal Azul', 'Cavernas de safira viva. Os cristais azuis condensam energia arcana e a convertem em TON enquanto você está offline.', '/__l5e/assets-v1/db0cb5e1-45ed-498f-928b-ed0aafcb113a/mine-crystal.jpg', 15, 0.32, 10, 1, 2),
  ('obsidian', 'Mina Obsidiana', 'Vidro vulcânico atravessado por veios de magma violeta. Alto rendimento para investidores de longo prazo.', '/__l5e/assets-v1/47e39a0f-693b-4fcf-8eb0-1ffee055847e/mine-obsidian.jpg', 35, 0.78, 14, 1, 3),
  ('celestial', 'Mina Celestial', 'O portal dourado dos antigos. A mina mais poderosa do reino, com o melhor ROI e a maior capacidade de armazenamento.', '/__l5e/assets-v1/5deadfca-e5ff-4f4a-bb55-672d8fab2329/mine-celestial.jpg', 75, 1.75, 15, 1, 4)
ON CONFLICT (mine_key) DO NOTHING;

-- ---------------------------------------------------------- helpers
CREATE OR REPLACE FUNCTION public.ton_mine_visible(p_telegram_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.enabled AND (NOT s.admin_only OR p_telegram_id = ANY (s.allowed_telegram_ids))
  FROM public.ton_mine_settings s WHERE s.id;
$$;

/** Loyalty multiplier (>=30d / >=60d), always resolved from the settings row. */
CREATE OR REPLACE FUNCTION public.ton_mine_multiplier(p_purchased_at timestamptz)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.ton_mine_settings; d numeric;
BEGIN
  SELECT * INTO s FROM public.ton_mine_settings WHERE id;
  IF s.id IS NULL OR NOT s.loyalty_enabled THEN RETURN 1; END IF;
  d := extract(epoch FROM (now() - p_purchased_at)) / 86400.0;
  IF d >= 60 THEN RETURN 1 + coalesce(s.bonus_60_pct,0)/100.0; END IF;
  IF d >= 30 THEN RETURN 1 + coalesce(s.bonus_30_pct,0)/100.0; END IF;
  RETURN 1;
END $$;

/** Offline accrual for one holding: elapsed time x daily rate, capped by storage. */
CREATE OR REPLACE FUNCTION public.ton_mine_accrue(p_holding_id uuid)
RETURNS public.ton_mine_holdings LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE h public.ton_mine_holdings; t public.ton_mine_templates; s public.ton_mine_settings;
        v_rate numeric; v_cap numeric; v_gain numeric; v_secs numeric;
BEGIN
  SELECT * INTO h FROM public.ton_mine_holdings WHERE id = p_holding_id FOR UPDATE;
  IF h.id IS NULL THEN RAISE EXCEPTION 'MINE_NOT_FOUND'; END IF;
  SELECT * INTO t FROM public.ton_mine_templates WHERE id = h.template_id;
  SELECT * INTO s FROM public.ton_mine_settings WHERE id;

  v_secs := greatest(0, extract(epoch FROM (now() - h.last_accrual_at)));
  IF NOT h.active OR NOT coalesce(s.enabled,false) OR coalesce(s.paused,false) OR coalesce(t.paused,false) THEN
    UPDATE public.ton_mine_holdings SET last_accrual_at = now() WHERE id = h.id RETURNING * INTO h;
    RETURN h;
  END IF;

  v_rate := round(t.daily_ton * public.ton_mine_multiplier(h.purchased_at), 9);
  v_cap := round(v_rate * t.storage_days, 9);
  v_gain := round(v_rate * (v_secs / 86400.0), 9);
  UPDATE public.ton_mine_holdings
     SET stored_ton = least(v_cap, round(coalesce(stored_ton,0) + v_gain, 9)),
         last_accrual_at = now()
   WHERE id = h.id
  RETURNING * INTO h;
  RETURN h;
END $$;

/** Full player-facing state: settings, catalogue, owned mines, summary and history. */
CREATE OR REPLACE FUNCTION public.ton_mines_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; s public.ton_mine_settings; h record; v_mines jsonb := '[]'::jsonb;
        v_claims jsonb; v_balance numeric; v_visible boolean;
        v_invested numeric := 0; v_daily numeric := 0; v_unclaimed numeric := 0;
        v_active int := 0; v_total_claimed numeric := 0; v_owned_total int := 0;
BEGIN
  SELECT * INTO s FROM public.ton_mine_settings WHERE id;
  SELECT id, coalesce(ton_balance,0) INTO u, v_balance FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_visible := coalesce(s.enabled,false) AND (NOT coalesce(s.admin_only,true) OR p_telegram_id = ANY (coalesce(s.allowed_telegram_ids, '{}'::bigint[])));

  FOR h IN SELECT id FROM public.ton_mine_holdings WHERE user_id = u AND active LOOP
    PERFORM public.ton_mine_accrue(h.id);
  END LOOP;

  SELECT count(*) INTO v_owned_total FROM public.ton_mine_holdings WHERE user_id = u AND active;

  SELECT coalesce(jsonb_agg(m ORDER BY (m->>'sortOrder')::int), '[]'::jsonb) INTO v_mines FROM (
    SELECT jsonb_build_object(
      'id', t.id, 'key', t.mine_key, 'name', t.name, 'description', t.description,
      'imageUrl', t.image_url, 'priceTon', t.price_ton, 'dailyTon', t.daily_ton,
      'storageDays', t.storage_days, 'maxPerPlayer', t.max_per_player, 'sortOrder', t.sort_order,
      'paused', t.paused,
      'roiDays', round(t.price_ton / nullif(t.daily_ton,0), 1),
      'ownedCount', coalesce(o.cnt, 0),
      'status', CASE WHEN coalesce(o.cnt,0) > 0 THEN 'OWNED'
                     WHEN t.paused THEN 'LOCKED'
                     WHEN coalesce(o.cnt,0) >= t.max_per_player THEN 'LOCKED'
                     ELSE 'AVAILABLE' END,
      'holdings', coalesce(o.items, '[]'::jsonb)
    ) AS m
    FROM public.ton_mine_templates t
    LEFT JOIN LATERAL (
      SELECT count(*)::int AS cnt, jsonb_agg(jsonb_build_object(
          'id', hh.id,
          'purchasedAt', hh.purchased_at,
          'storedTon', round(hh.stored_ton, 9),
          'totalClaimedTon', round(hh.total_claimed_ton, 9),
          'paidTon', hh.paid_ton,
          'multiplier', public.ton_mine_multiplier(hh.purchased_at),
          'dailyTon', round(t.daily_ton * public.ton_mine_multiplier(hh.purchased_at), 9),
          'capacityTon', round(t.daily_ton * public.ton_mine_multiplier(hh.purchased_at) * t.storage_days, 9),
          'daysHeld', floor(extract(epoch FROM (now() - hh.purchased_at)) / 86400.0),
          'fullAt', hh.last_accrual_at + make_interval(secs => greatest(0,
              (t.daily_ton * public.ton_mine_multiplier(hh.purchased_at) * t.storage_days - hh.stored_ton)
              / nullif(t.daily_ton * public.ton_mine_multiplier(hh.purchased_at), 0) * 86400.0))
        ) ORDER BY hh.purchased_at) AS items
      FROM public.ton_mine_holdings hh
      WHERE hh.user_id = u AND hh.template_id = t.id AND hh.active
    ) o ON true
    WHERE t.enabled
  ) q;

  SELECT coalesce(sum(hh.paid_ton),0), coalesce(sum(hh.stored_ton),0), coalesce(sum(hh.total_claimed_ton),0),
         count(*)::int, coalesce(sum(t.daily_ton * public.ton_mine_multiplier(hh.purchased_at)),0)
    INTO v_invested, v_unclaimed, v_total_claimed, v_active, v_daily
  FROM public.ton_mine_holdings hh JOIN public.ton_mine_templates t ON t.id = hh.template_id
  WHERE hh.user_id = u AND hh.active;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'mineName', t.name, 'mineKey', t.mine_key, 'amountTon', round(c.amount_ton,9),
      'claimType', c.claim_type, 'createdAt', c.created_at) ORDER BY c.created_at DESC), '[]'::jsonb)
    INTO v_claims
  FROM (SELECT * FROM public.ton_mine_claims WHERE user_id = u ORDER BY created_at DESC LIMIT 12) c
  LEFT JOIN public.ton_mine_templates t ON t.id = c.template_id;

  RETURN jsonb_build_object(
    'visible', v_visible,
    'enabled', coalesce(s.enabled,false),
    'paused', coalesce(s.paused,false),
    'loyalty', jsonb_build_object('enabled', s.loyalty_enabled, 'bonus30', s.bonus_30_pct, 'bonus60', s.bonus_60_pct),
    'maxTotalPerPlayer', s.max_total_per_player,
    'ownedTotal', v_owned_total,
    'balanceTon', round(v_balance, 9),
    'summary', jsonb_build_object(
      'investedTon', round(v_invested,9), 'activeMines', v_active,
      'dailyTon', round(v_daily,9), 'unclaimedTon', round(v_unclaimed,9),
      'lifetimeClaimedTon', round(v_total_claimed,9)),
    'mines', v_mines,
    'claims', coalesce(v_claims,'[]'::jsonb));
END $$;

/** Shared guard: every purchase path checks visibility, availability and per-player limits. */
CREATE OR REPLACE FUNCTION public.ton_mine_assert_can_buy(p_user_id uuid, p_telegram_id bigint, p_template_id uuid)
RETURNS public.ton_mine_templates LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.ton_mine_settings; t public.ton_mine_templates; v_owned int; v_total int;
BEGIN
  SELECT * INTO s FROM public.ton_mine_settings WHERE id;
  IF s.id IS NULL OR NOT s.enabled THEN RAISE EXCEPTION 'TON_MINES_DISABLED'; END IF;
  IF s.paused THEN RAISE EXCEPTION 'TON_MINES_PAUSED'; END IF;
  IF s.admin_only AND NOT (p_telegram_id = ANY (coalesce(s.allowed_telegram_ids,'{}'::bigint[]))) THEN
    RAISE EXCEPTION 'TON_MINES_DISABLED';
  END IF;
  SELECT * INTO t FROM public.ton_mine_templates WHERE id = p_template_id;
  IF t.id IS NULL OR NOT t.enabled THEN RAISE EXCEPTION 'MINE_NOT_FOUND'; END IF;
  IF t.paused THEN RAISE EXCEPTION 'MINE_PAUSED'; END IF;
  SELECT count(*) INTO v_owned FROM public.ton_mine_holdings WHERE user_id = p_user_id AND template_id = t.id AND active;
  IF v_owned >= t.max_per_player THEN RAISE EXCEPTION 'MINE_LIMIT_REACHED'; END IF;
  SELECT count(*) INTO v_total FROM public.ton_mine_holdings WHERE user_id = p_user_id AND active;
  IF v_total >= coalesce(s.max_total_per_player, 4) THEN RAISE EXCEPTION 'MINE_TOTAL_LIMIT_REACHED'; END IF;
  RETURN t;
END $$;

CREATE OR REPLACE FUNCTION public.ton_mine_buy_with_balance(p_telegram_id bigint, p_template_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; t public.ton_mine_templates; o public.ton_mine_orders; hid uuid;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ton_mine_buy:'||u::text, 0));

  SELECT * INTO o FROM public.ton_mine_orders WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NOT NULL THEN RETURN jsonb_build_object('status','already_processed','orderId',o.id); END IF;

  t := public.ton_mine_assert_can_buy(u, p_telegram_id, p_template_id);

  INSERT INTO public.ton_mine_orders(user_id, template_id, price_ton, amount_nano, payment_address,
      payment_comment, idempotency_key, status, paid_at, confirmed_at)
  VALUES (u, t.id, t.price_ton, round(t.price_ton * 1000000000)::text, 'internal_balance',
      'internal:'||gen_random_uuid(), p_idempotency_key, 'confirmed', now(), now())
  RETURNING * INTO o;

  PERFORM public.debit_ton_balance(u, t.price_ton, 'ton_mine_purchase', o.id::text, format('MINA DE TON: %s', t.name));

  INSERT INTO public.ton_mine_holdings(user_id, template_id, paid_ton) VALUES (u, t.id, t.price_ton) RETURNING id INTO hid;
  UPDATE public.ton_mine_orders SET status = 'delivered', delivered_at = now(), holding_id = hid WHERE id = o.id;

  RETURN jsonb_build_object('status','delivered','orderId',o.id,'holdingId',hid,'mineName',t.name,
    'priceTon',t.price_ton,'paidWith','balance');
END $$;

CREATE OR REPLACE FUNCTION public.ton_mine_create_order(p_telegram_id bigint, p_template_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; t public.ton_mine_templates; o public.ton_mine_orders; s public.ton_mine_settings; addr text;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM public.ton_mine_settings WHERE id;
  SELECT * INTO o FROM public.ton_mine_orders WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NULL THEN
    t := public.ton_mine_assert_can_buy(u, p_telegram_id, p_template_id);
    addr := public.wallet_hot_address();
    IF coalesce(addr,'') = '' THEN RAISE EXCEPTION 'TON_HOT_WALLET_MISSING'; END IF;
    INSERT INTO public.ton_mine_orders(user_id, template_id, price_ton, amount_nano, payment_address,
        payment_comment, idempotency_key, expires_at)
    VALUES (u, t.id, t.price_ton, round(t.price_ton * 1000000000)::text, addr,
        'forge_mine:'||gen_random_uuid(), p_idempotency_key,
        now() + make_interval(mins => greatest(5, coalesce(s.payment_ttl_minutes, 30))))
    RETURNING * INTO o;
  END IF;
  RETURN jsonb_build_object('id', o.id, 'paymentAddress', o.payment_address, 'amountNano', o.amount_nano,
    'amountTon', o.price_ton, 'paymentComment', o.payment_comment, 'expiresAt', o.expires_at);
END $$;

CREATE OR REPLACE FUNCTION public.ton_mine_deliver_order(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.ton_mine_orders; t public.ton_mine_templates; hid uuid;
BEGIN
  SELECT * INTO o FROM public.ton_mine_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF o.delivered_at IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_delivered','orderId',o.id,'holdingId',o.holding_id);
  END IF;
  IF o.status NOT IN ('paid','confirmed') THEN RAISE EXCEPTION 'PAYMENT_NOT_CONFIRMED'; END IF;
  SELECT * INTO t FROM public.ton_mine_templates WHERE id = o.template_id;
  INSERT INTO public.ton_mine_holdings(user_id, template_id, paid_ton) VALUES (o.user_id, o.template_id, o.price_ton)
  RETURNING id INTO hid;
  UPDATE public.ton_mine_orders SET status='delivered', delivered_at=now(), holding_id=hid WHERE id=o.id;
  RETURN jsonb_build_object('status','delivered','orderId',o.id,'holdingId',hid,'mineName',t.name,'priceTon',o.price_ton);
END $$;

CREATE OR REPLACE FUNCTION public.ton_mine_confirm_purchase(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.ton_mine_orders; v_expected numeric; v_received numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ton_mine_order:'||p_order_id::text, 0));
  SELECT * INTO o FROM public.ton_mine_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF o.tx_hash IS NULL THEN
    IF nullif(btrim(coalesce(p_tx_hash,'')),'') IS NULL THEN RAISE EXCEPTION 'PAYMENT_NOT_CONFIRMED'; END IF;
    v_expected := coalesce(nullif(o.amount_nano,'')::numeric, 0);
    v_received := coalesce(nullif(btrim(coalesce(p_amount_nano,'')),'')::numeric, v_expected);
    IF v_received < v_expected * 0.97 THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_MISMATCH'; END IF;
    IF EXISTS(SELECT 1 FROM public.ton_mine_orders WHERE tx_hash = p_tx_hash AND id <> o.id)
       OR EXISTS(SELECT 1 FROM public.nft_hero_orders WHERE tx_hash = p_tx_hash)
       OR EXISTS(SELECT 1 FROM public.nft_pet_orders WHERE tx_hash = p_tx_hash)
       OR EXISTS(SELECT 1 FROM public.pet_egg_orders WHERE tx_hash = p_tx_hash)
       OR EXISTS(SELECT 1 FROM public.wallet_deposits WHERE tx_hash = p_tx_hash)
       OR EXISTS(SELECT 1 FROM public.season_pass_orders WHERE tx_hash = p_tx_hash)
    THEN RAISE EXCEPTION 'TX_ALREADY_USED'; END IF;
    UPDATE public.ton_mine_orders
       SET status='confirmed', tx_hash=p_tx_hash, paid_at=coalesce(paid_at, now()), confirmed_at=coalesce(confirmed_at, now())
     WHERE id = o.id;
  END IF;
  RETURN public.ton_mine_deliver_order(o.id);
END $$;

CREATE OR REPLACE FUNCTION public.ton_mine_reconcile_orders(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; o record; delivered jsonb := '[]'::jsonb; already jsonb := '[]'::jsonb;
        results jsonb := '[]'::jsonb; pending jsonb; res jsonb;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  FOR o IN SELECT * FROM public.ton_mine_orders WHERE user_id = u AND status IN ('paid','confirmed') AND delivered_at IS NULL LOOP
    BEGIN
      res := public.ton_mine_deliver_order(o.id);
      IF res->>'status' = 'already_delivered' THEN already := already || to_jsonb(o.id::text);
      ELSE delivered := delivered || to_jsonb(o.id::text); END IF;
      results := results || jsonb_build_array(res);
    EXCEPTION WHEN OTHERS THEN RAISE LOG 'TON_MINE_RECONCILE order=% error=%', o.id, sqlerrm;
    END;
  END LOOP;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id', ord.id, 'paymentComment', ord.payment_comment,
      'amountNano', ord.amount_nano, 'priceTon', ord.price_ton, 'mineName', t.name) ORDER BY ord.created_at), '[]'::jsonb)
    INTO pending
  FROM public.ton_mine_orders ord JOIN public.ton_mine_templates t ON t.id = ord.template_id
  WHERE ord.user_id = u AND ord.status = 'pending' AND ord.tx_hash IS NULL
    AND ord.expires_at > now() - interval '2 hours';

  RETURN jsonb_build_object('delivered', delivered, 'alreadyDelivered', already, 'results', results, 'awaitingPayment', pending);
END $$;

CREATE OR REPLACE FUNCTION public.ton_mine_claim(p_telegram_id bigint, p_holding_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid; h record; v_total numeric := 0; v_amount numeric; cid uuid;
        v_type text := CASE WHEN p_holding_id IS NULL THEN 'all' ELSE 'single' END;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ton_mine_claim:'||u::text, 0));

  FOR h IN SELECT id, template_id FROM public.ton_mine_holdings
            WHERE user_id = u AND active AND (p_holding_id IS NULL OR id = p_holding_id) LOOP
    PERFORM public.ton_mine_accrue(h.id);
    SELECT round(stored_ton, 9) INTO v_amount FROM public.ton_mine_holdings WHERE id = h.id FOR UPDATE;
    IF coalesce(v_amount,0) <= 0 THEN CONTINUE; END IF;
    UPDATE public.ton_mine_holdings
       SET stored_ton = 0, total_claimed_ton = round(coalesce(total_claimed_ton,0) + v_amount, 9)
     WHERE id = h.id;
    INSERT INTO public.ton_mine_claims(user_id, holding_id, template_id, amount_ton, claim_type)
    VALUES (u, h.id, h.template_id, v_amount, v_type) RETURNING id INTO cid;
    PERFORM public.credit_ton_reward(u, v_amount, 'ton_mine_claim', cid::text, 'MINAS DE TON');
    v_total := round(v_total + v_amount, 9);
  END LOOP;

  IF v_total <= 0 THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;
  RETURN public.ton_mines_state(p_telegram_id) || jsonb_build_object('ok', true, 'claimedTon', v_total, 'claimType', v_type);
END $$;

-- ---------------------------------------------------------- admin bot
CREATE OR REPLACE FUNCTION public.admin_ton_mines_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.ton_mine_settings; v_mines jsonb; v_top jsonb; v_generated numeric; v_claimed numeric;
        v_unclaimed numeric; v_active int; v_sales numeric; v_daily numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO s FROM public.ton_mine_settings WHERE id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'key', t.mine_key, 'name', t.name, 'priceTon', t.price_ton, 'dailyTon', t.daily_ton,
      'storageDays', t.storage_days, 'maxPerPlayer', t.max_per_player, 'enabled', t.enabled,
      'paused', t.paused, 'imageUrl', t.image_url,
      'roiDays', round(t.price_ton / nullif(t.daily_ton,0), 1),
      'sold', (SELECT count(*) FROM public.ton_mine_holdings hh WHERE hh.template_id = t.id AND hh.active)
    ) ORDER BY t.sort_order), '[]'::jsonb) INTO v_mines FROM public.ton_mine_templates t;

  SELECT count(*)::int, coalesce(sum(hh.paid_ton),0), coalesce(sum(hh.stored_ton),0),
         coalesce(sum(hh.total_claimed_ton),0), coalesce(sum(t.daily_ton),0)
    INTO v_active, v_sales, v_unclaimed, v_claimed, v_daily
  FROM public.ton_mine_holdings hh JOIN public.ton_mine_templates t ON t.id = hh.template_id WHERE hh.active;
  v_generated := round(coalesce(v_claimed,0) + coalesce(v_unclaimed,0), 9);

  SELECT coalesce(jsonb_agg(x), '[]'::jsonb) INTO v_top FROM (
    SELECT jsonb_build_object('name', p.name, 'telegramId', p.telegram_id,
      'mines', count(*), 'investedTon', round(sum(hh.paid_ton),9),
      'dailyTon', round(sum(t.daily_ton),9), 'claimedTon', round(sum(hh.total_claimed_ton),9)) AS x
    FROM public.ton_mine_holdings hh
    JOIN public.ton_mine_templates t ON t.id = hh.template_id
    JOIN public.game_players p ON p.id = hh.user_id
    WHERE hh.active GROUP BY p.id, p.name, p.telegram_id
    ORDER BY sum(hh.paid_ton) DESC LIMIT 10) q;

  RETURN jsonb_build_object('enabled', s.enabled, 'paused', s.paused, 'adminOnly', s.admin_only,
    'allowedIds', to_jsonb(s.allowed_telegram_ids), 'loyaltyEnabled', s.loyalty_enabled,
    'bonus30', s.bonus_30_pct, 'bonus60', s.bonus_60_pct, 'maxTotalPerPlayer', s.max_total_per_player,
    'mines', v_mines, 'activeMines', v_active, 'salesTon', round(coalesce(v_sales,0),9),
    'dailyTon', round(coalesce(v_daily,0),9), 'generatedTon', v_generated,
    'claimedTon', round(coalesce(v_claimed,0),9), 'unclaimedTon', round(coalesce(v_unclaimed,0),9),
    'projection30Ton', round(coalesce(v_daily,0) * 30, 9), 'topOwners', v_top);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mines_set(p_admin_id bigint, p_field text, p_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.ton_mine_settings SET
    bonus_30_pct = CASE WHEN p_field = 'bonus30' THEN greatest(0, p_value) ELSE bonus_30_pct END,
    bonus_60_pct = CASE WHEN p_field = 'bonus60' THEN greatest(0, p_value) ELSE bonus_60_pct END,
    max_total_per_player = CASE WHEN p_field = 'maxtotal' THEN greatest(0, p_value)::int ELSE max_total_per_player END,
    payment_ttl_minutes = CASE WHEN p_field = 'ttl' THEN greatest(5, p_value)::int ELSE payment_ttl_minutes END,
    updated_at = now()
  WHERE id;
  RETURN public.admin_ton_mines_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mines_flag(p_admin_id bigint, p_field text, p_value boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.ton_mine_settings SET
    enabled = CASE WHEN p_field = 'enabled' THEN p_value ELSE enabled END,
    paused = CASE WHEN p_field = 'paused' THEN p_value ELSE paused END,
    admin_only = CASE WHEN p_field = 'adminonly' THEN p_value ELSE admin_only END,
    loyalty_enabled = CASE WHEN p_field = 'loyalty' THEN p_value ELSE loyalty_enabled END,
    updated_at = now()
  WHERE id;
  RETURN public.admin_ton_mines_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mines_allow(p_admin_id bigint, p_telegram_id bigint, p_add boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_add THEN
    UPDATE public.ton_mine_settings
       SET allowed_telegram_ids = (SELECT array_agg(DISTINCT x) FROM unnest(allowed_telegram_ids || p_telegram_id) x),
           updated_at = now() WHERE id;
  ELSE
    UPDATE public.ton_mine_settings
       SET allowed_telegram_ids = coalesce((SELECT array_agg(x) FROM unnest(allowed_telegram_ids) x WHERE x <> p_telegram_id), '{}'::bigint[]),
           updated_at = now() WHERE id;
  END IF;
  RETURN public.admin_ton_mines_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_mine_set(p_admin_id bigint, p_key text, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t public.ton_mine_templates; v_num numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO t FROM public.ton_mine_templates WHERE mine_key = lower(btrim(p_key));
  IF t.id IS NULL AND p_field <> 'create' THEN RAISE EXCEPTION 'MINE_NOT_FOUND'; END IF;

  IF p_field = 'create' THEN
    IF t.id IS NOT NULL THEN RAISE EXCEPTION 'MINE_ALREADY_EXISTS'; END IF;
    INSERT INTO public.ton_mine_templates(mine_key, name, price_ton, daily_ton, storage_days,
        sort_order)
    VALUES (lower(btrim(p_key)), btrim(p_value), 10, 0.2, 7,
        coalesce((SELECT max(sort_order) FROM public.ton_mine_templates), 0) + 1);
    RETURN public.admin_ton_mines_overview(p_admin_id);
  END IF;

  IF p_field IN ('price','daily','storage','maxper','sort') THEN
    v_num := nullif(btrim(replace(p_value, ',', '.')), '')::numeric;
    IF v_num IS NULL OR v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
  END IF;

  UPDATE public.ton_mine_templates SET
    name = CASE WHEN p_field = 'name' THEN btrim(p_value) ELSE name END,
    description = CASE WHEN p_field = 'desc' THEN btrim(p_value) ELSE description END,
    image_url = CASE WHEN p_field = 'image' THEN nullif(btrim(p_value), '') ELSE image_url END,
    price_ton = CASE WHEN p_field = 'price' THEN v_num ELSE price_ton END,
    daily_ton = CASE WHEN p_field = 'daily' THEN v_num ELSE daily_ton END,
    storage_days = CASE WHEN p_field = 'storage' THEN greatest(1, least(60, v_num))::int ELSE storage_days END,
    max_per_player = CASE WHEN p_field = 'maxper' THEN v_num::int ELSE max_per_player END,
    sort_order = CASE WHEN p_field = 'sort' THEN v_num::int ELSE sort_order END,
    enabled = CASE WHEN p_field = 'enabled' THEN lower(btrim(p_value)) IN ('1','on','true','sim') ELSE enabled END,
    paused = CASE WHEN p_field = 'paused' THEN lower(btrim(p_value)) IN ('1','on','true','sim') ELSE paused END,
    updated_at = now()
  WHERE id = t.id;
  RETURN public.admin_ton_mines_overview(p_admin_id);
END $$;

REVOKE ALL ON FUNCTION public.ton_mine_visible(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_multiplier(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_accrue(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mines_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_assert_can_buy(uuid, bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_buy_with_balance(bigint, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_create_order(bigint, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_deliver_order(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_confirm_purchase(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_reconcile_orders(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ton_mine_claim(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ton_mines_overview(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ton_mines_set(bigint, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ton_mines_flag(bigint, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ton_mines_allow(bigint, bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ton_mine_set(bigint, text, text, text) FROM PUBLIC, anon, authenticated;
