CREATE TABLE IF NOT EXISTS public.mythic_power_pack_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  sales_paused boolean NOT NULL DEFAULT false,
  package_version text NOT NULL DEFAULT 'MYTHIC_POWER_PACK_V1',
  price_ton numeric NOT NULL DEFAULT 20,
  myth_reward numeric NOT NULL DEFAULT 40000,
  first_bonus_myth numeric NOT NULL DEFAULT 10000,
  first_bonus_key_code text NOT NULL DEFAULT 'celestial_key',
  mythic_egg_slug text NOT NULL DEFAULT 'mythic-egg',
  mythic_eggs integer NOT NULL DEFAULT 1,
  void_chests integer NOT NULL DEFAULT 1,
  equipment_chest_code text NOT NULL DEFAULT 'legend-chest',
  equipment_chests integer NOT NULL DEFAULT 1,
  universal_fragments integer NOT NULL DEFAULT 50,
  pvp_tickets integer NOT NULL DEFAULT 20,
  eternity_keys integer NOT NULL DEFAULT 2,
  void_keys integer NOT NULL DEFAULT 1,
  pet_food_code text NOT NULL DEFAULT 'pet_rare_food',
  pet_food_quantity integer NOT NULL DEFAULT 25,
  hero_xp integer NOT NULL DEFAULT 10000,
  popup_enabled boolean NOT NULL DEFAULT false,
  popup_frequency text NOT NULL DEFAULT 'daily',
  popup_priority integer NOT NULL DEFAULT 70,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  start_at timestamptz,
  ends_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.mythic_power_pack_config TO service_role;
ALTER TABLE public.mythic_power_pack_config ENABLE ROW LEVEL SECURITY;

INSERT INTO public.mythic_power_pack_config(id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.mythic_power_pack_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  telegram_id bigint,
  package_version text NOT NULL,
  price_ton numeric NOT NULL,
  expected_nanoton text NOT NULL,
  payment_method text NOT NULL DEFAULT 'ton_connect',
  status text NOT NULL DEFAULT 'pending',
  payment_address text,
  payment_comment text,
  idempotency_key text UNIQUE,
  tx_hash text,
  first_purchase_bonus boolean NOT NULL DEFAULT false,
  myth_snapshot numeric NOT NULL DEFAULT 0,
  bonus_myth_snapshot numeric NOT NULL DEFAULT 0,
  rewards_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  delivery jsonb,
  fulfillment_error text,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.mythic_power_pack_purchases TO service_role;
ALTER TABLE public.mythic_power_pack_purchases ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS mythic_power_pack_purchases_user_idx ON public.mythic_power_pack_purchases(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS mythic_power_pack_purchases_tx_idx ON public.mythic_power_pack_purchases(tx_hash) WHERE tx_hash IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS mythic_power_pack_first_bonus_once ON public.mythic_power_pack_purchases(user_id) WHERE first_purchase_bonus;

CREATE TABLE IF NOT EXISTS public.mythic_power_pack_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid REFERENCES public.mythic_power_pack_purchases(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  kind text NOT NULL,
  ton_amount numeric DEFAULT 0,
  myth_amount numeric DEFAULT 0,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.mythic_power_pack_ledger TO service_role;
ALTER TABLE public.mythic_power_pack_ledger ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.mythic_power_pack_settings()
RETURNS public.mythic_power_pack_config
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c public.mythic_power_pack_config;
BEGIN
  SELECT * INTO c FROM public.mythic_power_pack_config WHERE id = true;
  RETURN c;
END $$;

CREATE OR REPLACE FUNCTION public.mythic_power_pack_state(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE u public.game_players; c public.mythic_power_pack_config;
        v_pending public.mythic_power_pack_purchases; v_last public.mythic_power_pack_purchases;
        v_count integer; v_bonus_used boolean; v_paid_pending boolean;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  c := public.mythic_power_pack_settings();

  SELECT count(*)::int INTO v_count FROM public.mythic_power_pack_purchases
   WHERE user_id = u.id AND status IN ('paid','delivered');
  SELECT EXISTS (SELECT 1 FROM public.mythic_power_pack_purchases
                  WHERE user_id = u.id AND first_purchase_bonus) INTO v_bonus_used;
  SELECT EXISTS (SELECT 1 FROM public.mythic_power_pack_purchases
                  WHERE user_id = u.id AND status = 'paid' AND delivered_at IS NULL) INTO v_paid_pending;
  SELECT * INTO v_pending FROM public.mythic_power_pack_purchases
   WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  SELECT * INTO v_last FROM public.mythic_power_pack_purchases
   WHERE user_id = u.id AND status = 'delivered' ORDER BY delivered_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'offerId','MYTHIC_POWER_PACK',
    'enabled', c.enabled,
    'salesPaused', c.sales_paused,
    'packageVersion', c.package_version,
    'show', c.enabled,
    'popupEnabled', c.popup_enabled,
    'popupFrequency', c.popup_frequency,
    'popupPriority', c.popup_priority,
    'windowOpen', c.enabled AND NOT c.sales_paused
                  AND now() >= COALESCE(c.start_at, now())
                  AND (c.ends_at IS NULL OR now() < c.ends_at),
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'availableTon', round(COALESCE(u.ton_balance,0), 9),
    'mythReward', c.myth_reward,
    'firstBonusMyth', c.first_bonus_myth,
    'firstBonusKey', c.first_bonus_key_code,
    'firstPurchaseAvailable', NOT v_bonus_used,
    'purchasedCount', COALESCE(v_count,0),
    'mythicEggs', c.mythic_eggs,
    'voidChests', c.void_chests,
    'equipmentChests', c.equipment_chests,
    'universalFragments', c.universal_fragments,
    'pvpTickets', c.pvp_tickets,
    'eternityKeys', c.eternity_keys,
    'voidKeys', c.void_keys,
    'petFood', c.pet_food_quantity,
    'heroXp', c.hero_xp,
    'paymentPending', v_pending.id IS NOT NULL,
    'pendingOrderId', v_pending.id,
    'processing', COALESCE(v_paid_pending,false),
    'delivery', v_last.delivery,
    'pendingOrder', CASE WHEN v_pending.id IS NULL THEN NULL ELSE jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.expected_nanoton, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) END,
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'purchaseId', p.id, 'createdAt', p.created_at, 'deliveredAt', p.delivered_at,
        'priceTon', p.price_ton, 'method', p.payment_method, 'status', p.status,
        'firstPurchaseBonus', p.first_purchase_bonus, 'txHash', p.tx_hash,
        'delivery', p.delivery) ORDER BY p.created_at DESC)
      FROM public.mythic_power_pack_purchases p
      WHERE p.user_id = u.id AND p.status IN ('paid','delivered')), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.mythic_power_pack_deliver(p_purchase_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o public.mythic_power_pack_purchases; c public.mythic_power_pack_config;
        eg public.pet_eggs; v_myth numeric; v_delivery jsonb := '{}'::jsonb; v_xp jsonb;
BEGIN
  SELECT * INTO o FROM public.mythic_power_pack_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'MYTHIC_POWER_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'alreadyDelivered', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'MYTHIC_POWER_PACK_NOT_PAID'; END IF;
  c := public.mythic_power_pack_settings();

  v_myth := GREATEST(0, COALESCE(o.myth_snapshot,0)) + GREATEST(0, COALESCE(o.bonus_myth_snapshot,0));
  IF v_myth > 0 THEN
    INSERT INTO public.myth_balances(user_id, amount) VALUES (o.user_id, 0) ON CONFLICT (user_id) DO NOTHING;
    UPDATE public.myth_balances SET amount = amount + v_myth, updated_at = now() WHERE user_id = o.user_id;
    INSERT INTO public.myth_ledger(user_id, direction, amount, reason)
    VALUES (o.user_id, 'credit', v_myth, 'mythic_power_pack');
    v_delivery := v_delivery || jsonb_build_object('myth', v_myth,
      'mythBase', COALESCE(o.myth_snapshot,0), 'mythFirstBonus', COALESCE(o.bonus_myth_snapshot,0));
  END IF;

  SELECT * INTO eg FROM public.pet_eggs WHERE slug = c.mythic_egg_slug LIMIT 1;
  IF eg.id IS NOT NULL AND COALESCE(c.mythic_eggs,0) > 0 THEN
    UPDATE public.player_pet_inventory SET quantity = quantity + c.mythic_eggs, updated_at = now()
     WHERE user_id = o.user_id AND item_type = 'egg' AND item_id = eg.id;
    IF NOT FOUND THEN
      INSERT INTO public.player_pet_inventory(user_id, item_type, item_id, quantity)
      VALUES (o.user_id, 'egg', eg.id, c.mythic_eggs);
    END IF;
    v_delivery := v_delivery || jsonb_build_object('mythicEgg', jsonb_build_object(
      'id', eg.id, 'slug', eg.slug, 'name', eg.name, 'quantity', c.mythic_eggs));
  END IF;

  IF COALESCE(c.void_chests,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'key_chest', 'void_chest', c.void_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
    v_delivery := v_delivery || jsonb_build_object('voidChests', c.void_chests);
  END IF;

  IF COALESCE(c.equipment_chests,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', c.equipment_chest_code, c.equipment_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
    v_delivery := v_delivery || jsonb_build_object('equipmentChests', c.equipment_chests,
      'equipmentChestCode', c.equipment_chest_code);
  END IF;

  IF COALESCE(c.eternity_keys,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'tower_key', 'eternity_key', c.eternity_keys)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;
  IF COALESCE(c.void_keys,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'tower_key', 'void_key', c.void_keys)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;
  v_delivery := v_delivery || jsonb_build_object('eternityKeys', c.eternity_keys, 'voidKeys', c.void_keys);

  IF o.first_purchase_bonus AND COALESCE(c.first_bonus_key_code,'') <> '' THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'tower_key', c.first_bonus_key_code, 1)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + 1, updated_at = now();
    v_delivery := v_delivery || jsonb_build_object('firstPurchaseBonus', true,
      'celestialKeys', 1);
  ELSE
    v_delivery := v_delivery || jsonb_build_object('firstPurchaseBonus', false);
  END IF;

  IF COALESCE(c.universal_fragments,0) > 0 THEN
    PERFORM public.add_universal_fragments(o.user_id, c.universal_fragments);
    v_delivery := v_delivery || jsonb_build_object('fragments', c.universal_fragments);
  END IF;

  IF COALESCE(c.pvp_tickets,0) > 0 THEN
    UPDATE public.game_players
       SET pvp_tickets = COALESCE(pvp_tickets,0) + c.pvp_tickets, updated_at = now()
     WHERE id = o.user_id;
    v_delivery := v_delivery || jsonb_build_object('pvpTickets', c.pvp_tickets);
  END IF;

  IF COALESCE(c.pet_food_quantity,0) > 0 THEN
    INSERT INTO public.player_pet_food(user_id, food_code, quantity)
    VALUES (o.user_id, c.pet_food_code, c.pet_food_quantity)
    ON CONFLICT (user_id, food_code)
      DO UPDATE SET quantity = public.player_pet_food.quantity + EXCLUDED.quantity, updated_at = now();
    v_delivery := v_delivery || jsonb_build_object('petFood', c.pet_food_quantity,
      'petFoodCode', c.pet_food_code);
  END IF;

  IF COALESCE(c.hero_xp,0) > 0 THEN
    v_xp := public.key_chest_grant_hero_xp(o.user_id, c.hero_xp);
    v_delivery := v_delivery || jsonb_build_object('heroXp', c.hero_xp, 'heroXpDetail', v_xp);
  END IF;

  UPDATE public.mythic_power_pack_purchases
     SET status = 'delivered', delivered_at = now(), delivery = v_delivery WHERE id = o.id;

  INSERT INTO public.mythic_power_pack_ledger(purchase_id, user_id, kind, ton_amount, myth_amount, note)
  VALUES (o.id, o.user_id, 'delivery', o.price_ton, v_myth, 'mythic power pack rewards delivered');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (o.user_id, 'mythic_power_pack', '20 TON MYTHIC PACK',
          'Suas recompensas do 20 TON MYTHIC PACK foram entregues.',
          v_delivery, 'mythic_power_pack:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END $$;

CREATE OR REPLACE FUNCTION public.mythic_power_pack_start_purchase(p_telegram_id bigint, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE u public.game_players; c public.mythic_power_pack_config; o public.mythic_power_pack_purchases;
        v_price numeric; v_nano text; v_bonus boolean; v_bonus_myth numeric; v_snapshot jsonb;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  c := public.mythic_power_pack_settings();
  IF NOT c.enabled THEN RAISE EXCEPTION 'MYTHIC_POWER_PACK_DISABLED'; END IF;
  IF c.sales_paused THEN RAISE EXCEPTION 'MYTHIC_POWER_PACK_SALES_PAUSED'; END IF;
  IF now() < COALESCE(c.start_at, now()) OR (c.ends_at IS NOT NULL AND now() >= c.ends_at) THEN
    RAISE EXCEPTION 'MYTHIC_POWER_PACK_OUTSIDE_WINDOW';
  END IF;

  v_bonus := NOT EXISTS (SELECT 1 FROM public.mythic_power_pack_purchases
                          WHERE user_id = u.id AND first_purchase_bonus);
  v_bonus_myth := CASE WHEN v_bonus THEN GREATEST(0, COALESCE(c.first_bonus_myth,0)) ELSE 0 END;
  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;
  v_snapshot := jsonb_build_object(
    'mythReward', c.myth_reward, 'firstBonusMyth', v_bonus_myth,
    'mythicEggs', c.mythic_eggs, 'voidChests', c.void_chests,
    'equipmentChests', c.equipment_chests, 'universalFragments', c.universal_fragments,
    'pvpTickets', c.pvp_tickets, 'eternityKeys', c.eternity_keys, 'voidKeys', c.void_keys,
    'petFood', c.pet_food_quantity, 'heroXp', c.hero_xp);

  SELECT * INTO o FROM public.mythic_power_pack_purchases WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NULL THEN
    SELECT * INTO o FROM public.mythic_power_pack_purchases
     WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF o.id IS NOT NULL AND o.status IN ('paid','delivered') THEN
    RETURN jsonb_build_object('status','completed','method',o.payment_method,'purchaseId',o.id,
      'priceTon',o.price_ton,'delivery',o.delivery,'duplicate',true,
      'state',public.mythic_power_pack_state(p_telegram_id));
  END IF;

  IF round(COALESCE(u.ton_balance,0), 9) >= round(v_price, 9) THEN
    UPDATE public.game_players SET ton_balance = round(COALESCE(ton_balance,0) - v_price, 9), updated_at = now() WHERE id = u.id;
    IF o.id IS NOT NULL AND o.status = 'pending' THEN
      UPDATE public.mythic_power_pack_purchases
         SET status='paid', payment_method='internal_ton', confirmed_at=now(), price_ton=v_price,
             expected_nanoton=v_nano, package_version=c.package_version,
             first_purchase_bonus=v_bonus, myth_snapshot=c.myth_reward, bonus_myth_snapshot=v_bonus_myth,
             rewards_snapshot=v_snapshot, reward_configuration_version=c.reward_configuration_version
       WHERE id = o.id RETURNING * INTO o;
    ELSE
      INSERT INTO public.mythic_power_pack_purchases(user_id, telegram_id, package_version, price_ton,
        expected_nanoton, payment_method, status, idempotency_key, confirmed_at,
        first_purchase_bonus, myth_snapshot, bonus_myth_snapshot, rewards_snapshot, reward_configuration_version)
      VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'internal_ton', 'paid',
        p_idempotency_key, now(), v_bonus, c.myth_reward, v_bonus_myth, v_snapshot, c.reward_configuration_version)
      RETURNING * INTO o;
    END IF;
    INSERT INTO public.mythic_power_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, u.id, 'purchase_internal', v_price, 'mythic power pack paid with internal TON');
    PERFORM public.mythic_power_pack_deliver(o.id);
    SELECT * INTO o FROM public.mythic_power_pack_purchases WHERE id = o.id;
    RETURN jsonb_build_object('status','completed','method','internal_ton','purchaseId',o.id,
      'priceTon',v_price,'delivery',o.delivery,'state',public.mythic_power_pack_state(p_telegram_id));
  END IF;

  IF o.id IS NOT NULL AND o.status = 'pending' THEN
    RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
      'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(COALESCE(u.ton_balance,0), 9));
  END IF;

  INSERT INTO public.mythic_power_pack_purchases(user_id, telegram_id, package_version, price_ton,
    expected_nanoton, payment_method, status, payment_address, payment_comment, idempotency_key,
    first_purchase_bonus, myth_snapshot, bonus_myth_snapshot, rewards_snapshot, reward_configuration_version)
  VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'mythreon_mythicpack:' || gen_random_uuid(), p_idempotency_key,
    false, c.myth_reward, 0, v_snapshot, c.reward_configuration_version)
  RETURNING * INTO o;

  RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
    'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(COALESCE(u.ton_balance,0), 9));
END $$;

CREATE OR REPLACE FUNCTION public.mythic_power_pack_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o public.mythic_power_pack_purchases; c public.mythic_power_pack_config;
        v_min numeric; v_bonus boolean; v_bonus_myth numeric;
BEGIN
  IF p_tx_hash IS NULL OR btrim(p_tx_hash) = '' THEN RAISE EXCEPTION 'TX_HASH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.mythic_power_pack_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'MYTHIC_POWER_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('status','already_processed','purchaseId',o.id,'delivery',o.delivery);
  END IF;
  IF EXISTS (SELECT 1 FROM public.mythic_power_pack_purchases
              WHERE tx_hash = btrim(p_tx_hash) AND id <> o.id) THEN
    RAISE EXCEPTION 'TX_ALREADY_USED';
  END IF;
  v_min := (o.expected_nanoton::numeric * 97) / 100;
  IF COALESCE(p_amount_nano::numeric, 0) < v_min THEN RAISE EXCEPTION 'INVALID_PAYMENT_AMOUNT'; END IF;

  INSERT INTO public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  VALUES (btrim(p_tx_hash), o.user_id, 'mythic_power_pack', p_amount_nano::numeric, o.id::text)
  ON CONFLICT (tx_hash) DO NOTHING;

  IF o.status = 'pending' THEN
    c := public.mythic_power_pack_settings();
    v_bonus := NOT EXISTS (SELECT 1 FROM public.mythic_power_pack_purchases
                            WHERE user_id = o.user_id AND first_purchase_bonus);
    v_bonus_myth := CASE WHEN v_bonus THEN GREATEST(0, COALESCE(c.first_bonus_myth,0)) ELSE 0 END;
    UPDATE public.mythic_power_pack_purchases
       SET status='paid', tx_hash=btrim(p_tx_hash), confirmed_at=COALESCE(confirmed_at, now()),
           first_purchase_bonus=v_bonus, bonus_myth_snapshot=v_bonus_myth
     WHERE id = o.id RETURNING * INTO o;
    INSERT INTO public.mythic_power_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, o.user_id, 'purchase_onchain', o.price_ton, 'mythic power pack paid via TonConnect');
  END IF;
  RETURN public.mythic_power_pack_deliver(o.id) || jsonb_build_object('status','completed','purchaseId',o.id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_mythic_power_pack_overview(p_admin_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c public.mythic_power_pack_config; v_count integer; v_ton numeric; v_bonus integer;
BEGIN
  PERFORM public.admin_assert(p_admin_telegram_id);
  c := public.mythic_power_pack_settings();
  SELECT count(*)::int, COALESCE(sum(price_ton),0) INTO v_count, v_ton
    FROM public.mythic_power_pack_purchases WHERE status IN ('paid','delivered');
  SELECT count(*)::int INTO v_bonus FROM public.mythic_power_pack_purchases WHERE first_purchase_bonus;
  RETURN jsonb_build_object(
    'offerId','MYTHIC_POWER_PACK',
    'enabled', c.enabled, 'salesPaused', c.sales_paused, 'priceTon', c.price_ton,
    'mythReward', c.myth_reward, 'firstBonusMyth', c.first_bonus_myth,
    'mythicEggs', c.mythic_eggs, 'voidChests', c.void_chests, 'equipmentChests', c.equipment_chests,
    'universalFragments', c.universal_fragments, 'pvpTickets', c.pvp_tickets,
    'eternityKeys', c.eternity_keys, 'voidKeys', c.void_keys,
    'petFood', c.pet_food_quantity, 'heroXp', c.hero_xp,
    'popupEnabled', c.popup_enabled, 'popupPriority', c.popup_priority,
    'totalPurchases', COALESCE(v_count,0), 'totalTon', COALESCE(v_ton,0),
    'firstPurchaseBonusClaims', COALESCE(v_bonus,0));
END $$;

CREATE OR REPLACE FUNCTION public.admin_mythic_power_pack_set(p_admin_telegram_id bigint, p_field text, p_value text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_num numeric; v_bool boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_telegram_id);
  IF p_field IN ('enabled','sales_paused','popup_enabled') THEN
    v_bool := lower(COALESCE(p_value,'')) IN ('1','true','on','yes','sim');
    EXECUTE format('UPDATE public.mythic_power_pack_config SET %I = $1, updated_at = now() WHERE id = true', p_field)
      USING v_bool;
  ELSIF p_field IN ('price_ton','myth_reward','first_bonus_myth','mythic_eggs','void_chests',
                    'equipment_chests','universal_fragments','pvp_tickets','eternity_keys','void_keys',
                    'pet_food_quantity','hero_xp','popup_priority') THEN
    v_num := p_value::numeric;
    IF v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    EXECUTE format('UPDATE public.mythic_power_pack_config SET %I = $1, reward_configuration_version = reward_configuration_version + 1, updated_at = now() WHERE id = true', p_field)
      USING v_num;
  ELSIF p_field IN ('pet_food_code','equipment_chest_code','first_bonus_key_code','mythic_egg_slug','package_version','popup_frequency') THEN
    EXECUTE format('UPDATE public.mythic_power_pack_config SET %I = $1, updated_at = now() WHERE id = true', p_field)
      USING btrim(p_value);
  ELSE
    RAISE EXCEPTION 'INVALID_FIELD';
  END IF;
  RETURN public.admin_mythic_power_pack_overview(p_admin_telegram_id);
END $$;