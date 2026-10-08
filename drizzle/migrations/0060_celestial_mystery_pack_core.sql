-- ============================================================
-- 💫 CELESTIAL MYSTERY PACK — 100 TON premium pack
-- Hero Celestial + NFT Pet delivered with MINING TO BE REVEALED
-- (no invented rate, no retroactive mining), 1M FC, 10 legendary
-- chests, 2 NFT weapons, 2 armors, 4 random premium items and a
-- permanent account-wide +3% TON mining bonus.
-- ============================================================

ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS account_ton_mining_bonus numeric NOT NULL DEFAULT 0;

ALTER TABLE public.player_heroes
  ADD COLUMN IF NOT EXISTS mining_pending_reveal boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS mining_revealed_at timestamptz;

ALTER TABLE public.nft_pets
  ADD COLUMN IF NOT EXISTS mining_pending_reveal boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS mining_revealed_at timestamptz;

CREATE TABLE IF NOT EXISTS public.celestial_pack_config (
  id boolean PRIMARY KEY DEFAULT true,
  enabled boolean NOT NULL DEFAULT true,
  sales_paused boolean NOT NULL DEFAULT false,
  package_version text NOT NULL DEFAULT 'CELESTIAL_MYSTERY_V1',
  price_ton numeric NOT NULL DEFAULT 100,
  popup_enabled boolean NOT NULL DEFAULT false,
  popup_frequency text NOT NULL DEFAULT 'UNTIL_PURCHASED',
  fc_reward numeric NOT NULL DEFAULT 1000000,
  legendary_chests integer NOT NULL DEFAULT 10,
  nft_weapons integer NOT NULL DEFAULT 2,
  armors integer NOT NULL DEFAULT 2,
  random_items integer NOT NULL DEFAULT 4,
  account_ton_bonus_percent numeric NOT NULL DEFAULT 3,
  random_items_pool jsonb NOT NULL DEFAULT '[
    {"type":"key_chest","code":"celestial_chest","qty":1},
    {"type":"key_chest","code":"eternity_chest","qty":1},
    {"type":"key_chest","code":"void_chest","qty":1},
    {"type":"hero_chest","code":"legendary_chest","qty":1},
    {"type":"resource_chest","code":"premium_resource_chest","qty":1},
    {"type":"exclusive_chest","code":"exclusive-pet-chest","qty":1},
    {"type":"exclusive_chest","code":"exclusive-hero-chest","qty":1},
    {"type":"pet_egg","code":"mythic-egg","qty":1}
  ]'::jsonb,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT celestial_pack_config_singleton CHECK (id)
);
GRANT ALL ON public.celestial_pack_config TO service_role;
ALTER TABLE public.celestial_pack_config ENABLE ROW LEVEL SECURITY;
INSERT INTO public.celestial_pack_config(id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.celestial_pack_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
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
  bonus_percent_snapshot numeric NOT NULL DEFAULT 3,
  fc_snapshot numeric NOT NULL DEFAULT 0,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  delivery jsonb,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '1 hour',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.celestial_pack_purchases TO service_role;
ALTER TABLE public.celestial_pack_purchases ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS celestial_pack_purchases_user_idx ON public.celestial_pack_purchases(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS celestial_pack_purchases_tx_idx ON public.celestial_pack_purchases(tx_hash) WHERE tx_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.celestial_pack_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  purchase_id uuid NOT NULL REFERENCES public.celestial_pack_purchases(id) ON DELETE CASCADE,
  item_type text NOT NULL,
  template_id text,
  instance_id uuid,
  mining_pending_reveal boolean NOT NULL DEFAULT false,
  revealed_ton numeric,
  revealed_myth numeric,
  revealed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.celestial_pack_items TO service_role;
ALTER TABLE public.celestial_pack_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS celestial_pack_items_user_idx ON public.celestial_pack_items(user_id);

CREATE TABLE IF NOT EXISTS public.celestial_pack_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid REFERENCES public.celestial_pack_purchases(id) ON DELETE SET NULL,
  user_id uuid,
  kind text NOT NULL,
  ton_amount numeric,
  fc_amount numeric,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.celestial_pack_ledger TO service_role;
ALTER TABLE public.celestial_pack_ledger ENABLE ROW LEVEL SECURITY;

-- ---------------- settings ----------------
CREATE OR REPLACE FUNCTION public.celestial_pack_settings()
RETURNS public.celestial_pack_config
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.celestial_pack_config;
BEGIN
  SELECT * INTO c FROM public.celestial_pack_config WHERE id = true;
  RETURN c;
END $$;

-- ---------------- state ----------------
CREATE OR REPLACE FUNCTION public.celestial_pack_state(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.celestial_pack_config;
        v_owned public.celestial_pack_purchases; v_pending public.celestial_pack_purchases;
        v_heroes integer;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  c := public.celestial_pack_settings();

  SELECT count(*) INTO v_heroes FROM public.hero_catalog hc
   WHERE lower(hc.rarity) = 'celestial' AND hc.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = hc.hero_key);

  SELECT * INTO v_owned FROM public.celestial_pack_purchases
   WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered')
   ORDER BY created_at DESC LIMIT 1;
  SELECT * INTO v_pending FROM public.celestial_pack_purchases
   WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'enabled', COALESCE(c.enabled,false),
    'salesPaused', COALESCE(c.sales_paused,false),
    'packageVersion', c.package_version,
    'show', COALESCE(c.enabled,false) AND (v_owned.id IS NOT NULL OR NOT COALESCE(c.sales_paused,false)),
    'popupEnabled', COALESCE(c.popup_enabled,false) AND v_owned.id IS NULL,
    'popupFrequency', c.popup_frequency,
    'purchased', v_owned.id IS NOT NULL,
    'eligible', COALESCE(c.enabled,false) AND NOT COALESCE(c.sales_paused,false) AND v_owned.id IS NULL AND v_heroes > 0,
    'soldOut', COALESCE(c.enabled,false) AND v_heroes <= 0,
    'celestialAvailable', v_heroes,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'availableTon', round(COALESCE(u.ton_balance,0), 9),
    'fcReward', c.fc_reward,
    'legendaryChests', c.legendary_chests,
    'nftWeapons', c.nft_weapons,
    'armors', c.armors,
    'randomItems', c.random_items,
    'accountBonusPercent', c.account_ton_bonus_percent,
    'ownerBonusPercent', round(COALESCE(u.account_ton_mining_bonus,0), 4),
    'miningRevealPending', COALESCE((SELECT bool_or(i.mining_pending_reveal) FROM public.celestial_pack_items i WHERE i.user_id = u.id), false),
    'delivery', v_owned.delivery,
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type', i.item_type, 'template', i.template_id, 'instanceId', i.instance_id,
        'pendingReveal', i.mining_pending_reveal, 'revealedTon', i.revealed_ton,
        'revealedMyth', i.revealed_myth, 'revealedAt', i.revealed_at) ORDER BY i.created_at)
      FROM public.celestial_pack_items i WHERE i.user_id = u.id), '[]'::jsonb),
    'pendingOrder', CASE WHEN v_pending.id IS NULL THEN NULL ELSE jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.expected_nanoton, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) END
  );
END $$;

-- ---------------- delivery ----------------
CREATE OR REPLACE FUNCTION public.celestial_pack_deliver(p_purchase_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.celestial_pack_purchases; c public.celestial_pack_config;
        hc public.hero_catalog; np public.nft_pets;
        v_hero uuid; v_delivery jsonb := '{}'::jsonb; v_weapons jsonb := '[]'::jsonb;
        v_armors jsonb := '[]'::jsonb; v_random jsonb := '[]'::jsonb;
        r record; v_peq uuid; v_assign jsonb; v_pick jsonb; v_pool jsonb; i integer;
BEGIN
  SELECT * INTO o FROM public.celestial_pack_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'CELESTIAL_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'alreadyDelivered', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'CELESTIAL_PACK_NOT_PAID'; END IF;
  c := public.celestial_pack_settings();

  -- 1) Celestial hero: one of the unowned Celestial templates, mining TO BE REVEALED.
  SELECT * INTO hc FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key)
   ORDER BY random() LIMIT 1;
  IF hc.hero_key IS NULL THEN RAISE EXCEPTION 'CELESTIAL_HERO_SOLD_OUT'; END IF;
  INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image,
      mining_daily_myth, mining_ton_override, mining_pending_reveal, mining_last_at, premium_source)
  VALUES (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image,
      0, 0, true, now(), 'CELESTIAL_PACK')
  RETURNING id INTO v_hero;
  INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id, mining_pending_reveal)
  VALUES (o.user_id, o.id, 'hero', hc.hero_key, v_hero, true);
  v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object(
    'id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name, 'miningStatus', 'MINING_TO_BE_REVEALED'));

  -- 2) NFT pet: free unit, mining TO BE REVEALED (zero rates until the admin reveals).
  SELECT * INTO np FROM public.nft_pets
   WHERE owner_user_id IS NULL AND status <> 'BURNED'
   ORDER BY for_sale ASC, created_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF np.id IS NULL THEN RAISE EXCEPTION 'CELESTIAL_PACK_NFT_PET_UNAVAILABLE'; END IF;
  UPDATE public.nft_pets
     SET daily_yield_ton = 0, daily_yield_myth = 0, mining_pending_reveal = true,
         mining_revealed_at = NULL, updated_at = now()
   WHERE id = np.id;
  v_assign := public.nft_assign_unit(np.id, o.user_id, 'celestial_pack');
  INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id, mining_pending_reveal)
  VALUES (o.user_id, o.id, 'nft_pet', np.unique_instance_id, np.id, true);
  v_delivery := v_delivery || jsonb_build_object('nftPet', v_assign || jsonb_build_object(
    'nftPetId', np.id, 'miningStatus', 'MINING_TO_BE_REVEALED'));

  -- 3) Forge Coins
  IF COALESCE(o.fc_snapshot, 0) > 0 THEN
    UPDATE public.game_players SET forge_coins = COALESCE(forge_coins,0) + o.fc_snapshot, updated_at = now()
     WHERE id = o.user_id;
    v_delivery := v_delivery || jsonb_build_object('forgeCoins', o.fc_snapshot);
  END IF;

  -- 4) Legendary chests
  IF COALESCE(c.legendary_chests,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', 'legendary_chest', c.legendary_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
    v_delivery := v_delivery || jsonb_build_object('legendaryChests', c.legendary_chests);
  END IF;

  -- 5) NFT weapons (1/1 units)
  FOR r IN SELECT n.id FROM public.nft_equipment n
            JOIN public.equipment_templates t ON t.id = n.template_id
           WHERE n.owner_user_id IS NULL AND n.status <> 'BURNED' AND lower(COALESCE(t.slot,'')) = 'weapon'
           ORDER BY n.for_sale ASC, n.created_at ASC
           LIMIT GREATEST(0, COALESCE(c.nft_weapons,2)) LOOP
    v_assign := public.nft_equipment_assign_unit(r.id, o.user_id, 'celestial_pack');
    INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'nft_weapon', v_assign->>'name', (v_assign->>'instanceId')::uuid);
    v_weapons := v_weapons || jsonb_build_array(v_assign);
  END LOOP;

  -- 6) Legendary armors
  FOR r IN SELECT * FROM public.equipment_templates
           WHERE is_active AND NOT COALESCE(is_nft,false)
             AND lower(COALESCE(slot,'')) IN ('armor','chest','armour')
             AND lower(COALESCE(rarity,'')) IN ('legendary','mythic')
           ORDER BY random() LIMIT GREATEST(0, COALESCE(c.armors,2)) LOOP
    INSERT INTO public.player_equipment(user_id, template_id, level, source, source_ref)
    VALUES (o.user_id, r.id, 1, 'celestial_pack', gen_random_uuid())
    RETURNING id INTO v_peq;
    INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'armor', r.code, v_peq);
    v_armors := v_armors || jsonb_build_array(jsonb_build_object('id', v_peq, 'code', r.code, 'name', r.name));
  END LOOP;

  -- 7) Random premium items
  v_pool := COALESCE(c.random_items_pool, '[]'::jsonb);
  IF jsonb_array_length(v_pool) > 0 THEN
    FOR i IN 1..GREATEST(0, COALESCE(c.random_items,0)) LOOP
      v_pick := v_pool -> floor(random() * jsonb_array_length(v_pool))::int;
      INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
      VALUES (o.user_id, v_pick->>'type', v_pick->>'code', GREATEST(1, COALESCE((v_pick->>'qty')::int, 1)))
      ON CONFLICT (user_id, item_type, item_code)
        DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
      INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id)
      VALUES (o.user_id, o.id, 'random_item', v_pick->>'code');
      v_random := v_random || jsonb_build_array(v_pick);
    END LOOP;
  END IF;

  -- 8) Account-wide TON mining bonus (permanent, applied on every TON accrual)
  IF COALESCE(o.bonus_percent_snapshot,0) > 0 THEN
    UPDATE public.game_players
       SET account_ton_mining_bonus = round(COALESCE(account_ton_mining_bonus,0) + o.bonus_percent_snapshot, 4),
           updated_at = now()
     WHERE id = o.user_id;
  END IF;

  INSERT INTO public.player_entitlements(user_id, code, source) VALUES (o.user_id, 'CELESTIAL_PACK_OWNER', 'celestial_pack')
    ON CONFLICT (user_id, code) DO NOTHING;

  v_delivery := v_delivery || jsonb_build_object(
    'nftWeapons', v_weapons, 'armors', v_armors, 'randomItems', v_random,
    'accountBonusPercent', o.bonus_percent_snapshot);

  UPDATE public.celestial_pack_purchases
     SET status = 'delivered', delivered_at = now(), delivery = v_delivery WHERE id = o.id;

  INSERT INTO public.celestial_pack_ledger(purchase_id, user_id, kind, fc_amount, note)
    VALUES (o.id, o.user_id, 'delivery', o.fc_snapshot, 'celestial mystery pack delivered (mining to be revealed)');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (o.user_id, 'celestial_pack', 'CELESTIAL MYSTERY PACK ATIVO',
          'Recompensas entregues. As taxas de mineracao do Heroi Celestial e do Pet NFT serao reveladas em breve.',
          v_delivery, 'celestial_pack:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END $$;

-- ---------------- purchase ----------------
CREATE OR REPLACE FUNCTION public.celestial_pack_start_purchase(p_telegram_id bigint, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.celestial_pack_config; o public.celestial_pack_purchases;
        v_price numeric; v_nano text; v_heroes integer;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  c := public.celestial_pack_settings();
  IF NOT c.enabled THEN RAISE EXCEPTION 'CELESTIAL_PACK_DISABLED'; END IF;
  IF c.sales_paused THEN RAISE EXCEPTION 'CELESTIAL_PACK_SALES_PAUSED'; END IF;
  IF EXISTS (SELECT 1 FROM public.celestial_pack_purchases
              WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered')) THEN
    RAISE EXCEPTION 'CELESTIAL_PACK_ALREADY_PURCHASED';
  END IF;

  SELECT count(*) INTO v_heroes FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key);
  IF v_heroes <= 0 THEN RAISE EXCEPTION 'CELESTIAL_PACK_SOLD_OUT'; END IF;

  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;

  SELECT * INTO o FROM public.celestial_pack_purchases WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NULL THEN
    SELECT * INTO o FROM public.celestial_pack_purchases
     WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF o.id IS NOT NULL AND o.status IN ('paid','delivered') THEN
    RETURN jsonb_build_object('status','completed','method',o.payment_method,'purchaseId',o.id,
      'priceTon',o.price_ton,'delivery',o.delivery,'duplicate',true,'state',public.celestial_pack_state(p_telegram_id));
  END IF;

  IF round(COALESCE(u.ton_balance,0), 9) >= round(v_price, 9) THEN
    UPDATE public.game_players SET ton_balance = round(COALESCE(ton_balance,0) - v_price, 9), updated_at = now() WHERE id = u.id;
    IF o.id IS NOT NULL AND o.status = 'pending' THEN
      UPDATE public.celestial_pack_purchases
         SET status='paid', payment_method='internal_ton', confirmed_at=now(), price_ton=v_price,
             expected_nanoton=v_nano, package_version=c.package_version,
             bonus_percent_snapshot=c.account_ton_bonus_percent, fc_snapshot=c.fc_reward,
             reward_configuration_version=c.reward_configuration_version
       WHERE id = o.id RETURNING * INTO o;
    ELSE
      INSERT INTO public.celestial_pack_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
        payment_method, status, idempotency_key, confirmed_at, bonus_percent_snapshot, fc_snapshot, reward_configuration_version)
      VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'internal_ton', 'paid', p_idempotency_key, now(),
        c.account_ton_bonus_percent, c.fc_reward, c.reward_configuration_version)
      RETURNING * INTO o;
    END IF;
    INSERT INTO public.celestial_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, u.id, 'purchase_internal', v_price, 'celestial mystery pack paid with internal TON');
    PERFORM public.celestial_pack_deliver(o.id);
    SELECT * INTO o FROM public.celestial_pack_purchases WHERE id = o.id;
    RETURN jsonb_build_object('status','completed','method','internal_ton','purchaseId',o.id,
      'priceTon',v_price,'delivery',o.delivery,'state',public.celestial_pack_state(p_telegram_id));
  END IF;

  IF o.id IS NOT NULL AND o.status = 'pending' THEN
    RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
      'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(COALESCE(u.ton_balance,0), 9));
  END IF;

  INSERT INTO public.celestial_pack_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
    payment_method, status, payment_address, payment_comment, idempotency_key,
    bonus_percent_snapshot, fc_snapshot, reward_configuration_version)
  VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'mythreon_celpack:' || gen_random_uuid(), p_idempotency_key,
    c.account_ton_bonus_percent, c.fc_reward, c.reward_configuration_version)
  RETURNING * INTO o;

  RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
    'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(COALESCE(u.ton_balance,0), 9));
END $$;

CREATE OR REPLACE FUNCTION public.celestial_pack_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.celestial_pack_purchases; v_min numeric;
BEGIN
  IF p_tx_hash IS NULL OR btrim(p_tx_hash) = '' THEN RAISE EXCEPTION 'TX_HASH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.celestial_pack_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'CELESTIAL_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('status','already_processed','purchaseId',o.id,'delivery',o.delivery);
  END IF;
  IF EXISTS (SELECT 1 FROM public.celestial_pack_purchases WHERE tx_hash = btrim(p_tx_hash) AND id <> o.id) THEN
    RAISE EXCEPTION 'TX_ALREADY_USED';
  END IF;
  v_min := (o.expected_nanoton::numeric * 97) / 100;
  IF COALESCE(p_amount_nano::numeric, 0) < v_min THEN RAISE EXCEPTION 'INVALID_PAYMENT_AMOUNT'; END IF;

  INSERT INTO public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  VALUES (btrim(p_tx_hash), o.user_id, 'celestial_pack', p_amount_nano::numeric, o.id::text)
  ON CONFLICT (tx_hash) DO NOTHING;

  IF o.status = 'pending' THEN
    UPDATE public.celestial_pack_purchases
       SET status='paid', tx_hash=btrim(p_tx_hash), confirmed_at=COALESCE(confirmed_at, now())
     WHERE id = o.id;
    INSERT INTO public.celestial_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, o.user_id, 'purchase_onchain', o.price_ton, 'celestial mystery pack paid via TonConnect');
  END IF;
  RETURN public.celestial_pack_deliver(o.id) || jsonb_build_object('status','completed','purchaseId',o.id);
END $$;

-- ---------------- admin: overview / config / reveal ----------------
CREATE OR REPLACE FUNCTION public.admin_celestial_pack_overview(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.celestial_pack_config; v_sold integer; v_ton numeric; v_heroes integer;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  c := public.celestial_pack_settings();
  SELECT count(*), COALESCE(SUM(price_ton),0) INTO v_sold, v_ton
    FROM public.celestial_pack_purchases WHERE status IN ('paid','delivered');
  SELECT count(*) INTO v_heroes FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key);
  RETURN jsonb_build_object(
    'config', to_jsonb(c), 'sold', v_sold, 'tonCollected', round(v_ton,9), 'celestialAvailable', v_heroes,
    'pendingReveals', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'itemId', i.id, 'userId', i.user_id, 'telegramId', g.telegram_id, 'player', COALESCE(g.username, g.name),
        'type', i.item_type, 'template', i.template_id, 'instanceId', i.instance_id, 'createdAt', i.created_at)
        ORDER BY i.created_at)
      FROM public.celestial_pack_items i JOIN public.game_players g ON g.id = i.user_id
      WHERE i.mining_pending_reveal), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_celestial_pack_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_num numeric; v_bool boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_field = 'enabled' OR p_field = 'sales_paused' OR p_field = 'popup_enabled' THEN
    v_bool := lower(COALESCE(p_value,'')) IN ('1','true','on','yes');
    IF p_field = 'enabled' THEN UPDATE public.celestial_pack_config SET enabled = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'sales_paused' THEN UPDATE public.celestial_pack_config SET sales_paused = v_bool, updated_at = now() WHERE id;
    ELSE UPDATE public.celestial_pack_config SET popup_enabled = v_bool, updated_at = now() WHERE id; END IF;
  ELSIF p_field IN ('price_ton','fc_reward','legendary_chests','nft_weapons','armors','random_items','account_ton_bonus_percent') THEN
    v_num := COALESCE(p_value,'')::numeric;
    IF v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    IF p_field = 'price_ton' THEN UPDATE public.celestial_pack_config SET price_ton = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'fc_reward' THEN UPDATE public.celestial_pack_config SET fc_reward = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'legendary_chests' THEN UPDATE public.celestial_pack_config SET legendary_chests = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'nft_weapons' THEN UPDATE public.celestial_pack_config SET nft_weapons = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'armors' THEN UPDATE public.celestial_pack_config SET armors = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'random_items' THEN UPDATE public.celestial_pack_config SET random_items = v_num::int, updated_at = now() WHERE id;
    ELSE UPDATE public.celestial_pack_config SET account_ton_bonus_percent = v_num, updated_at = now() WHERE id; END IF;
  ELSIF p_field = 'popup_frequency' THEN
    UPDATE public.celestial_pack_config SET popup_frequency = upper(btrim(COALESCE(p_value,'UNTIL_PURCHASED'))), updated_at = now() WHERE id;
  ELSE
    RAISE EXCEPTION 'UNKNOWN_FIELD';
  END IF;
  PERFORM public.admin_log(p_admin_id,'celestial_pack.set','config',p_field,null,jsonb_build_object('value',p_value),null);
  RETURN public.admin_celestial_pack_overview(p_admin_id);
END $$;

/**
 * Reveals the real mining rate of a Celestial Pack item. Never retroactive:
 * mining_last_at is reset to now(), so accrual starts at the reveal moment.
 */
CREATE OR REPLACE FUNCTION public.admin_celestial_pack_reveal(p_admin_id bigint, p_item_id uuid, p_daily_ton numeric, p_daily_myth numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE it public.celestial_pack_items; v_ton numeric; v_myth numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO it FROM public.celestial_pack_items WHERE id = p_item_id FOR UPDATE;
  IF it.id IS NULL THEN RAISE EXCEPTION 'CELESTIAL_PACK_ITEM_NOT_FOUND'; END IF;
  IF NOT it.mining_pending_reveal THEN RAISE EXCEPTION 'CELESTIAL_PACK_ALREADY_REVEALED'; END IF;
  v_ton := GREATEST(COALESCE(p_daily_ton,0), 0);
  v_myth := GREATEST(COALESCE(p_daily_myth,0), 0);

  IF it.item_type = 'hero' THEN
    UPDATE public.player_heroes
       SET mining_ton_override = v_ton, mining_daily_myth = v_myth,
           mining_pending_reveal = false, mining_revealed_at = now(), mining_last_at = now(), updated_at = now()
     WHERE id = it.instance_id;
  ELSIF it.item_type = 'nft_pet' THEN
    UPDATE public.nft_pets
       SET daily_yield_ton = v_ton, daily_yield_myth = v_myth,
           mining_pending_reveal = false, mining_revealed_at = now(), updated_at = now()
     WHERE id = it.instance_id;
    UPDATE public.player_pets SET mining_daily_myth = v_myth, mining_last_at = now(), updated_at = now()
     WHERE nft_pet_id = it.instance_id;
    PERFORM public.nft_pool_sync_positions();
  ELSE
    RAISE EXCEPTION 'CELESTIAL_PACK_ITEM_NOT_REVEALABLE';
  END IF;

  UPDATE public.celestial_pack_items
     SET mining_pending_reveal = false, revealed_ton = v_ton, revealed_myth = v_myth, revealed_at = now()
   WHERE id = it.id;

  INSERT INTO public.celestial_pack_ledger(purchase_id, user_id, kind, note)
    VALUES (it.purchase_id, it.user_id, 'mining_revealed',
      it.item_type || ' revealed: ' || v_ton::text || ' TON/dia + ' || v_myth::text || ' MYTH/dia');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (it.user_id, 'celestial_pack', 'MINERACAO REVELADA',
    'A taxa de mineracao do seu ' || it.item_type || ' do Celestial Mystery Pack foi revelada.',
    jsonb_build_object('ton', v_ton, 'myth', v_myth, 'itemId', it.id), 'celestial_reveal:' || it.id::text)
  ON CONFLICT DO NOTHING;

  PERFORM public.admin_log(p_admin_id,'celestial_pack.reveal','item',it.id::text,null,
    jsonb_build_object('ton',v_ton,'myth',v_myth,'type',it.item_type),null);

  RETURN jsonb_build_object('ok', true, 'itemId', it.id, 'ton', v_ton, 'myth', v_myth);
END $$;

-- ---------------- accrual: skip pending reveal + apply account TON bonus ----------------
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_myth_flat numeric := 0; v_pet_myth numeric := 0; v_pet_flat numeric := 0;
        v_eq_myth numeric := 0; v_peq_myth numeric := 0;
        v_out numeric; v_room numeric; v_boost numeric := 0; v_ton_bonus numeric := 0;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() OR NOT public.ton_mining_access_allowed(p_user_id) THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE player_pets SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE nft_equipment SET mining_last_at = v_now WHERE owner_user_id = p_user_id;
    UPDATE player_equipment SET mining_last_at = v_now WHERE user_id = p_user_id AND COALESCE(mining_daily_myth,0) > 0;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  v_room := GREATEST(COALESCE(hero_mining_remaining(p_user_id), 0), 0);

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_row_rate(h.mining_ton_override, h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(
             COALESCE(h.mining_daily_myth, 0),
             CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                  ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END
           ) AS myth_rate,
           hero_mining_hero_dual(h.nft_hero_id) AS dual,
           COALESCE(h.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND NOT COALESCE(h.mining_pending_reveal, false)
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.dual AS dual, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT
    COALESCE(SUM(CASE WHEN rate > 0 THEN rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 AND is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_ton_gain, v_myth_gain, v_myth_flat
    FROM moved;

  WITH pelig AS (
    SELECT p.id, GREATEST(COALESCE(p.mining_daily_myth, 0), 0) AS myth_rate,
           COALESCE(p.premium_source, '') = 'FOUNDER' AS is_founder,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(p.mining_last_at, p.created_at, v_now)))) AS secs
      FROM player_pets p
     WHERE p.user_id = p_user_id
       AND COALESCE(p.mining_daily_myth, 0) > 0
       AND NOT COALESCE(p.market_locked, false)
  ), pmoved AS (
    UPDATE player_pets pp SET mining_last_at = v_now
      FROM pelig e WHERE pp.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs, e.is_founder AS is_founder
  )
  SELECT COALESCE(SUM(CASE WHEN NOT is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN is_founder THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_pet_myth, v_pet_flat FROM pmoved;

  WITH eelig AS (
    SELECT n.id, GREATEST(COALESCE(n.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(n.mining_last_at, n.assigned_at, n.created_at, v_now)))) AS secs
      FROM nft_equipment n
     WHERE n.owner_user_id = p_user_id
       AND n.status <> 'BURNED'
       AND COALESCE(n.mining_daily_myth, 0) > 0
  ), emoved AS (
    UPDATE nft_equipment ne SET mining_last_at = v_now
      FROM eelig e WHERE ne.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_eq_myth FROM emoved;

  WITH qelig AS (
    SELECT q.id, GREATEST(COALESCE(q.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(q.mining_last_at, q.created_at, v_now)))) AS secs
      FROM player_equipment q
     WHERE q.user_id = p_user_id
       AND COALESCE(q.mining_daily_myth, 0) > 0
       AND NOT COALESCE(q.market_locked, false)
       AND NOT EXISTS (SELECT 1 FROM nft_equipment n WHERE n.player_equipment_id = q.id)
  ), qmoved AS (
    UPDATE player_equipment pq SET mining_last_at = v_now
      FROM qelig e WHERE pq.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_peq_myth FROM qmoved;

  -- Account-wide TON mining bonus (Celestial Mystery Pack): applied to TON accrual only.
  v_ton_bonus := GREATEST(COALESCE((SELECT account_ton_mining_bonus FROM game_players WHERE id = p_user_id), 0), 0);
  v_ton_gain := GREATEST(v_ton_gain, 0) * (1 + v_ton_bonus / 100.0);
  v_ton_gain := round(LEAST(v_ton_gain, v_room), 9);
  v_myth_gain := GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0) + GREATEST(v_eq_myth, 0) + GREATEST(v_peq_myth, 0);

  v_boost := GREATEST(COALESCE(public.veteran_v2_boost_percent(p_user_id), 0), 0)
           + GREATEST(COALESCE(public.season_pass_perk_percent(p_user_id, 'myth_mining_bonus_percent'), 0), 0);
  v_myth_gain := round(v_myth_gain * (1 + v_boost / 100.0) + GREATEST(v_myth_flat, 0) + GREATEST(v_pet_flat, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
   RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END $$;
