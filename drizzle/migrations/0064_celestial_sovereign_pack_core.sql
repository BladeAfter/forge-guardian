-- 👑 CELESTIAL SOVEREIGN PACK — 200 TON (pack ultra premium, topo absoluto da loja).
CREATE TABLE IF NOT EXISTS public.ton_mining_bonus_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  policy text NOT NULL DEFAULT 'STACK',
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.ton_mining_bonus_settings(id) VALUES (true) ON CONFLICT (id) DO NOTHING;
GRANT ALL ON public.ton_mining_bonus_settings TO service_role;
ALTER TABLE public.ton_mining_bonus_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.ton_mining_bonus_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  source text NOT NULL,
  percent numeric NOT NULL DEFAULT 0,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, source)
);
CREATE INDEX IF NOT EXISTS ton_mining_bonus_entitlements_user_idx
  ON public.ton_mining_bonus_entitlements(user_id);
GRANT ALL ON public.ton_mining_bonus_entitlements TO service_role;
ALTER TABLE public.ton_mining_bonus_entitlements ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.ton_mining_bonus_policy()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT upper(COALESCE((SELECT policy FROM public.ton_mining_bonus_settings WHERE id), 'STACK'))
$$;

CREATE OR REPLACE FUNCTION public.ton_mining_bonus_recalc(p_user_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_policy text := public.ton_mining_bonus_policy(); v_value numeric;
BEGIN
  SELECT CASE WHEN v_policy = 'HIGHEST_ONLY' THEN COALESCE(max(percent),0) ELSE COALESCE(sum(percent),0) END
    INTO v_value FROM public.ton_mining_bonus_entitlements WHERE user_id = p_user_id;
  v_value := round(GREATEST(COALESCE(v_value,0), 0), 4);
  UPDATE public.game_players SET account_ton_mining_bonus = v_value, updated_at = now() WHERE id = p_user_id;
  RETURN v_value;
END $$;

CREATE OR REPLACE FUNCTION public.ton_mining_bonus_grant(p_user_id uuid, p_source text, p_percent numeric, p_note text DEFAULT NULL)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF COALESCE(p_percent,0) <= 0 THEN RETURN public.ton_mining_bonus_recalc(p_user_id); END IF;
  INSERT INTO public.ton_mining_bonus_entitlements(user_id, source, percent, note)
  VALUES (p_user_id, upper(btrim(p_source)), round(p_percent,4), p_note)
  ON CONFLICT (user_id, source) DO UPDATE
    SET percent = GREATEST(public.ton_mining_bonus_entitlements.percent, EXCLUDED.percent),
        note = COALESCE(EXCLUDED.note, public.ton_mining_bonus_entitlements.note),
        updated_at = now();
  RETURN public.ton_mining_bonus_recalc(p_user_id);
END $$;

INSERT INTO public.ton_mining_bonus_entitlements(user_id, source, percent, note)
SELECT p.user_id, 'CELESTIAL_MYSTERY_PACK', round(max(p.bonus_percent_snapshot),4), 'backfill'
  FROM public.celestial_pack_purchases p
 WHERE p.status = 'delivered' AND COALESCE(p.bonus_percent_snapshot,0) > 0
 GROUP BY p.user_id
ON CONFLICT (user_id, source) DO NOTHING;

INSERT INTO public.ton_mining_bonus_entitlements(user_id, source, percent, note)
SELECT g.id, 'LEGACY', round(COALESCE(g.account_ton_mining_bonus,0) - COALESCE(e.total,0), 4), 'backfill de bonus legado'
  FROM public.game_players g
  LEFT JOIN (SELECT user_id, sum(percent) AS total FROM public.ton_mining_bonus_entitlements GROUP BY user_id) e
         ON e.user_id = g.id
 WHERE COALESCE(g.account_ton_mining_bonus,0) - COALESCE(e.total,0) > 0.0001
ON CONFLICT (user_id, source) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.sovereign_pack_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  sales_paused boolean NOT NULL DEFAULT false,
  package_version text NOT NULL DEFAULT 'CELESTIAL_SOVEREIGN_V1',
  price_ton numeric NOT NULL DEFAULT 200,
  popup_enabled boolean NOT NULL DEFAULT false,
  popup_frequency text NOT NULL DEFAULT 'UNTIL_PURCHASED',
  popup_priority integer NOT NULL DEFAULT 110,
  fc_reward numeric NOT NULL DEFAULT 5000000,
  legendary_chests integer NOT NULL DEFAULT 20,
  mythic_chests integer NOT NULL DEFAULT 5,
  nft_weapons integer NOT NULL DEFAULT 4,
  mythic_armors integer NOT NULL DEFAULT 2,
  celestial_armors integer NOT NULL DEFAULT 2,
  random_items integer NOT NULL DEFAULT 8,
  account_ton_bonus_percent numeric NOT NULL DEFAULT 10,
  random_items_pool jsonb NOT NULL DEFAULT '[
    {"type":"key_chest","code":"celestial_chest","qty":1},
    {"type":"key_chest","code":"eternity_chest","qty":1},
    {"type":"key_chest","code":"void_chest","qty":1},
    {"type":"hero_chest","code":"legendary_chest","qty":1},
    {"type":"hero_chest","code":"mythic_chest","qty":1},
    {"type":"resource_chest","code":"premium_resource_chest","qty":1},
    {"type":"exclusive_chest","code":"exclusive-pet-chest","qty":1},
    {"type":"exclusive_chest","code":"exclusive-hero-chest","qty":1},
    {"type":"pet_egg","code":"mythic-egg","qty":1}
  ]'::jsonb,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  purchase_limit integer NOT NULL DEFAULT 1,
  stock_total integer,
  sold_out_visible boolean NOT NULL DEFAULT true,
  start_at timestamptz,
  ends_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.sovereign_pack_config(id) VALUES (true) ON CONFLICT (id) DO NOTHING;
GRANT ALL ON public.sovereign_pack_config TO service_role;
ALTER TABLE public.sovereign_pack_config ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sovereign_pack_purchases (
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
  bonus_percent_snapshot numeric NOT NULL DEFAULT 10,
  fc_snapshot numeric NOT NULL DEFAULT 0,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  delivery jsonb,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '1 hour',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sovereign_pack_purchases_user_idx ON public.sovereign_pack_purchases(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS sovereign_pack_purchases_tx_idx ON public.sovereign_pack_purchases(tx_hash) WHERE tx_hash IS NOT NULL;
GRANT ALL ON public.sovereign_pack_purchases TO service_role;
ALTER TABLE public.sovereign_pack_purchases ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sovereign_pack_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid,
  user_id uuid,
  kind text NOT NULL,
  ton_amount numeric,
  fc_amount numeric,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.sovereign_pack_ledger TO service_role;
ALTER TABLE public.sovereign_pack_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sovereign_pack_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  purchase_id uuid NOT NULL,
  item_type text NOT NULL,
  template_id text,
  instance_id uuid,
  mining_pending_reveal boolean NOT NULL DEFAULT false,
  revealed_ton numeric,
  revealed_myth numeric,
  revealed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sovereign_pack_items_user_idx ON public.sovereign_pack_items(user_id);
CREATE INDEX IF NOT EXISTS sovereign_pack_items_pending_idx ON public.sovereign_pack_items(mining_pending_reveal) WHERE mining_pending_reveal;
GRANT ALL ON public.sovereign_pack_items TO service_role;
ALTER TABLE public.sovereign_pack_items ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.sovereign_pack_settings()
RETURNS public.sovereign_pack_config LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.sovereign_pack_config;
BEGIN
  SELECT * INTO c FROM public.sovereign_pack_config WHERE id = true;
  RETURN c;
END $$;

CREATE OR REPLACE FUNCTION public.sovereign_pack_offer_meta(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.sovereign_pack_config; v_heroes integer; v_sold integer; v_mine integer;
        v_pending uuid; v_paid_pending boolean; v_stock integer;
BEGIN
  c := public.sovereign_pack_settings();
  SELECT count(*) INTO v_heroes FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key);
  SELECT count(*) INTO v_sold FROM public.sovereign_pack_purchases
   WHERE package_version = c.package_version AND status IN ('paid','delivered');
  SELECT count(*) INTO v_mine FROM public.sovereign_pack_purchases
   WHERE user_id = p_user_id AND package_version = c.package_version AND status IN ('paid','delivered');
  SELECT id INTO v_pending FROM public.sovereign_pack_purchases
   WHERE user_id = p_user_id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  SELECT EXISTS (SELECT 1 FROM public.sovereign_pack_purchases
                  WHERE user_id = p_user_id AND status = 'paid' AND delivered_at IS NULL) INTO v_paid_pending;
  v_stock := LEAST(v_heroes, COALESCE(NULLIF(c.stock_total,0) - v_sold, v_heroes));

  RETURN jsonb_build_object(
    'offerId','CELESTIAL_SOVEREIGN_PACK',
    'priceTon', c.price_ton,
    'popupEnabled', c.popup_enabled,
    'popupFrequency', c.popup_frequency,
    'popupPriority', c.popup_priority,
    'purchaseLimit', c.purchase_limit,
    'startAt', c.start_at,
    'endsAt', c.ends_at,
    'stockTotal', c.stock_total,
    'stockRemaining', GREATEST(v_stock,0),
    'soldOut', COALESCE(v_stock,0) <= 0,
    'soldOutVisible', c.sold_out_visible,
    'windowOpen', c.enabled AND NOT c.sales_paused
                  AND now() >= COALESCE(c.start_at, now())
                  AND (c.ends_at IS NULL OR now() < c.ends_at),
    'purchasedCount', v_mine,
    'purchased', v_mine >= GREATEST(c.purchase_limit,1),
    'paymentPending', v_pending IS NOT NULL,
    'pendingOrderId', v_pending,
    'processing', v_paid_pending,
    'sold', v_sold);
END $$;

CREATE OR REPLACE FUNCTION public.sovereign_pack_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.sovereign_pack_config;
        v_owned public.sovereign_pack_purchases; v_pending public.sovereign_pack_purchases;
        v_heroes integer; v_pets integer;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  c := public.sovereign_pack_settings();

  SELECT count(*) INTO v_heroes FROM public.hero_catalog hc
   WHERE lower(hc.rarity) = 'celestial' AND hc.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = hc.hero_key);
  SELECT count(*) INTO v_pets FROM public.nft_pets WHERE owner_user_id IS NULL AND status <> 'BURNED';

  SELECT * INTO v_owned FROM public.sovereign_pack_purchases
   WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered')
   ORDER BY created_at DESC LIMIT 1;
  SELECT * INTO v_pending FROM public.sovereign_pack_purchases
   WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'enabled', COALESCE(c.enabled,false),
    'salesPaused', COALESCE(c.sales_paused,false),
    'packageVersion', c.package_version,
    'show', COALESCE(c.enabled,false) AND (v_owned.id IS NOT NULL OR NOT COALESCE(c.sales_paused,false)),
    'popupEnabled', COALESCE(c.popup_enabled,false) AND v_owned.id IS NULL,
    'popupFrequency', c.popup_frequency,
    'purchased', v_owned.id IS NOT NULL,
    'eligible', COALESCE(c.enabled,false) AND NOT COALESCE(c.sales_paused,false)
                AND v_owned.id IS NULL AND v_heroes > 0 AND v_pets > 0,
    'soldOut', COALESCE(c.enabled,false) AND (v_heroes <= 0 OR v_pets <= 0),
    'celestialAvailable', v_heroes,
    'nftPetsAvailable', v_pets,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'availableTon', round(COALESCE(u.ton_balance,0), 9),
    'fcReward', c.fc_reward,
    'legendaryChests', c.legendary_chests,
    'mythicChests', c.mythic_chests,
    'nftWeapons', c.nft_weapons,
    'mythicArmors', c.mythic_armors,
    'celestialArmors', c.celestial_armors,
    'randomItems', c.random_items,
    'accountBonusPercent', c.account_ton_bonus_percent,
    'ownerBonusPercent', round(COALESCE(u.account_ton_mining_bonus,0), 4),
    'bonusPolicy', public.ton_mining_bonus_policy(),
    'bonusSources', COALESCE((SELECT jsonb_agg(jsonb_build_object('source', e.source, 'percent', e.percent) ORDER BY e.percent DESC)
        FROM public.ton_mining_bonus_entitlements e WHERE e.user_id = u.id), '[]'::jsonb),
    'miningRevealPending', COALESCE((SELECT bool_or(i.mining_pending_reveal) FROM public.sovereign_pack_items i WHERE i.user_id = u.id), false),
    'delivery', v_owned.delivery,
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type', i.item_type, 'template', i.template_id, 'instanceId', i.instance_id,
        'pendingReveal', i.mining_pending_reveal, 'revealedTon', i.revealed_ton,
        'revealedMyth', i.revealed_myth, 'revealedAt', i.revealed_at) ORDER BY i.created_at)
      FROM public.sovereign_pack_items i WHERE i.user_id = u.id), '[]'::jsonb),
    'pendingOrder', CASE WHEN v_pending.id IS NULL THEN NULL ELSE jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.expected_nanoton, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) END
  );
END $$;

CREATE OR REPLACE FUNCTION public.sovereign_pack_offer_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN public.sovereign_pack_state(p_telegram_id) || public.sovereign_pack_offer_meta(v_user);
END $$;

CREATE OR REPLACE FUNCTION public.sovereign_pack_deliver(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.sovereign_pack_purchases; c public.sovereign_pack_config;
        hc public.hero_catalog; np public.nft_pets;
        v_hero uuid; v_delivery jsonb := '{}'::jsonb; v_weapons jsonb := '[]'::jsonb;
        v_armors jsonb := '[]'::jsonb; v_random jsonb := '[]'::jsonb;
        r record; v_peq uuid; v_assign jsonb; v_pick jsonb; v_pool jsonb; i integer; v_bonus numeric;
BEGIN
  SELECT * INTO o FROM public.sovereign_pack_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'SOVEREIGN_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'alreadyDelivered', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'SOVEREIGN_PACK_NOT_PAID'; END IF;
  c := public.sovereign_pack_settings();

  SELECT * INTO hc FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key)
   ORDER BY random() LIMIT 1;
  IF hc.hero_key IS NULL THEN RAISE EXCEPTION 'CELESTIAL_HERO_SOLD_OUT'; END IF;
  INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image,
      mining_daily_myth, mining_ton_override, mining_pending_reveal, mining_last_at, premium_source)
  VALUES (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image,
      0, 0, true, now(), 'SOVEREIGN_PACK')
  RETURNING id INTO v_hero;
  INSERT INTO public.sovereign_pack_items(user_id, purchase_id, item_type, template_id, instance_id, mining_pending_reveal)
  VALUES (o.user_id, o.id, 'hero', hc.hero_key, v_hero, true);
  v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object(
    'id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name, 'miningStatus', 'MINING_TO_BE_REVEALED'));

  SELECT * INTO np FROM public.nft_pets
   WHERE owner_user_id IS NULL AND status <> 'BURNED'
   ORDER BY for_sale ASC, COALESCE(tier_ton, 0) DESC, created_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF np.id IS NULL THEN RAISE EXCEPTION 'SOVEREIGN_PACK_NFT_PET_UNAVAILABLE'; END IF;
  UPDATE public.nft_pets
     SET daily_yield_ton = 0, daily_yield_myth = 0, mining_pending_reveal = true,
         mining_revealed_at = NULL, updated_at = now()
   WHERE id = np.id;
  v_assign := public.nft_assign_unit(np.id, o.user_id, 'sovereign_pack');
  INSERT INTO public.sovereign_pack_items(user_id, purchase_id, item_type, template_id, instance_id, mining_pending_reveal)
  VALUES (o.user_id, o.id, 'nft_pet', np.unique_instance_id, np.id, true);
  v_delivery := v_delivery || jsonb_build_object('nftPet', v_assign || jsonb_build_object(
    'nftPetId', np.id, 'miningStatus', 'MINING_TO_BE_REVEALED'));

  IF COALESCE(o.fc_snapshot, 0) > 0 THEN
    UPDATE public.game_players SET forge_coins = COALESCE(forge_coins,0) + o.fc_snapshot, updated_at = now()
     WHERE id = o.user_id;
    v_delivery := v_delivery || jsonb_build_object('forgeCoins', o.fc_snapshot);
  END IF;

  IF COALESCE(c.legendary_chests,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', 'legendary_chest', c.legendary_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;
  IF COALESCE(c.mythic_chests,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', 'mythic_chest', c.mythic_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;
  v_delivery := v_delivery || jsonb_build_object(
    'legendaryChests', c.legendary_chests, 'mythicChests', c.mythic_chests);

  FOR r IN SELECT n.id FROM public.nft_equipment n
            JOIN public.equipment_templates t ON t.id = n.template_id
           WHERE n.owner_user_id IS NULL AND n.status <> 'BURNED' AND lower(COALESCE(t.slot,'')) = 'weapon'
           ORDER BY n.for_sale ASC, n.created_at ASC
           LIMIT GREATEST(0, COALESCE(c.nft_weapons,4)) LOOP
    v_assign := public.nft_equipment_assign_unit(r.id, o.user_id, 'sovereign_pack');
    INSERT INTO public.sovereign_pack_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'nft_weapon', v_assign->>'name', (v_assign->>'instanceId')::uuid);
    v_weapons := v_weapons || jsonb_build_array(v_assign);
  END LOOP;

  FOR r IN (
    SELECT m.id, m.code, m.name, m.rarity, m.image_url, 1 AS grp FROM (
      SELECT t.* FROM public.equipment_templates t
       WHERE t.is_active AND NOT COALESCE(t.is_nft,false)
         AND lower(COALESCE(t.slot,'')) IN ('armor','chest','armour')
         AND lower(COALESCE(t.rarity,'')) = 'mythic'
       ORDER BY random() LIMIT GREATEST(0, COALESCE(c.mythic_armors,2))
    ) m
    UNION ALL
    SELECT ce.id, ce.code, ce.name, ce.rarity, ce.image_url, 2 AS grp FROM (
      SELECT t.* FROM public.equipment_templates t
       WHERE t.is_active AND NOT COALESCE(t.is_nft,false)
         AND lower(COALESCE(t.slot,'')) IN ('armor','chest','armour')
         AND lower(COALESCE(t.rarity,'')) = 'celestial'
       ORDER BY random() LIMIT GREATEST(0, COALESCE(c.celestial_armors,2))
    ) ce
  ) LOOP
    INSERT INTO public.player_equipment(user_id, template_id, level, source, source_ref)
    VALUES (o.user_id, r.id, 1, 'sovereign_pack', gen_random_uuid())
    RETURNING id INTO v_peq;
    INSERT INTO public.sovereign_pack_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, CASE WHEN r.grp = 1 THEN 'mythic_armor' ELSE 'celestial_armor' END, r.code, v_peq);
    v_armors := v_armors || jsonb_build_array(jsonb_build_object(
      'id', v_peq, 'code', r.code, 'name', r.name, 'rarity', r.rarity, 'image', r.image_url));
  END LOOP;

  v_pool := COALESCE(c.random_items_pool, '[]'::jsonb);
  IF jsonb_array_length(v_pool) > 0 THEN
    FOR i IN 1..GREATEST(0, COALESCE(c.random_items,0)) LOOP
      v_pick := v_pool -> floor(random() * jsonb_array_length(v_pool))::int;
      INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
      VALUES (o.user_id, v_pick->>'type', v_pick->>'code', GREATEST(1, COALESCE((v_pick->>'qty')::int, 1)))
      ON CONFLICT (user_id, item_type, item_code)
        DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
      INSERT INTO public.sovereign_pack_items(user_id, purchase_id, item_type, template_id)
      VALUES (o.user_id, o.id, 'random_item', v_pick->>'code');
      v_random := v_random || jsonb_build_array(v_pick);
    END LOOP;
  END IF;

  v_bonus := public.ton_mining_bonus_grant(o.user_id, 'CELESTIAL_SOVEREIGN_PACK',
    COALESCE(o.bonus_percent_snapshot,0), 'Celestial Sovereign Pack');

  INSERT INTO public.player_entitlements(user_id, code, source)
  VALUES (o.user_id, 'SOVEREIGN_PACK_OWNER', 'sovereign_pack')
  ON CONFLICT (user_id, code) DO NOTHING;

  v_delivery := v_delivery || jsonb_build_object(
    'nftWeapons', v_weapons, 'armors', v_armors, 'randomItems', v_random,
    'accountBonusPercent', o.bonus_percent_snapshot, 'accountBonusEffective', v_bonus,
    'bonusPolicy', public.ton_mining_bonus_policy());

  UPDATE public.sovereign_pack_purchases
     SET status = 'delivered', delivered_at = now(), delivery = v_delivery WHERE id = o.id;

  INSERT INTO public.sovereign_pack_ledger(purchase_id, user_id, kind, fc_amount, note)
    VALUES (o.id, o.user_id, 'delivery', o.fc_snapshot, 'celestial sovereign pack delivered (mining to be revealed)');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (o.user_id, 'sovereign_pack', 'CELESTIAL SOVEREIGN PACK ATIVO',
          'Recompensas entregues. As taxas de mineracao do Heroi Celestial e do Pet NFT serao reveladas em breve.',
          v_delivery, 'sovereign_pack:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END $$;

CREATE OR REPLACE FUNCTION public.sovereign_pack_start_purchase(p_telegram_id bigint, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.sovereign_pack_config; o public.sovereign_pack_purchases;
        v_price numeric; v_nano text; v_heroes integer; v_pets integer;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  c := public.sovereign_pack_settings();
  IF NOT c.enabled THEN RAISE EXCEPTION 'SOVEREIGN_PACK_DISABLED'; END IF;
  IF c.sales_paused THEN RAISE EXCEPTION 'SOVEREIGN_PACK_SALES_PAUSED'; END IF;
  IF now() < COALESCE(c.start_at, now()) OR (c.ends_at IS NOT NULL AND now() >= c.ends_at) THEN
    RAISE EXCEPTION 'SOVEREIGN_PACK_OUTSIDE_WINDOW';
  END IF;
  IF (SELECT count(*) FROM public.sovereign_pack_purchases
       WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered'))
     >= GREATEST(c.purchase_limit,1) THEN
    RAISE EXCEPTION 'SOVEREIGN_PACK_ALREADY_PURCHASED';
  END IF;

  SELECT count(*) INTO v_heroes FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key);
  SELECT count(*) INTO v_pets FROM public.nft_pets WHERE owner_user_id IS NULL AND status <> 'BURNED';
  IF v_heroes <= 0 OR v_pets <= 0 THEN RAISE EXCEPTION 'SOVEREIGN_PACK_SOLD_OUT'; END IF;

  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;

  SELECT * INTO o FROM public.sovereign_pack_purchases WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NULL THEN
    SELECT * INTO o FROM public.sovereign_pack_purchases
     WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF o.id IS NOT NULL AND o.status IN ('paid','delivered') THEN
    RETURN jsonb_build_object('status','completed','method',o.payment_method,'purchaseId',o.id,
      'priceTon',o.price_ton,'delivery',o.delivery,'duplicate',true,'state',public.sovereign_pack_state(p_telegram_id));
  END IF;

  IF round(COALESCE(u.ton_balance,0), 9) >= round(v_price, 9) THEN
    UPDATE public.game_players SET ton_balance = round(COALESCE(ton_balance,0) - v_price, 9), updated_at = now() WHERE id = u.id;
    IF o.id IS NOT NULL AND o.status = 'pending' THEN
      UPDATE public.sovereign_pack_purchases
         SET status='paid', payment_method='internal_ton', confirmed_at=now(), price_ton=v_price,
             expected_nanoton=v_nano, package_version=c.package_version,
             bonus_percent_snapshot=c.account_ton_bonus_percent, fc_snapshot=c.fc_reward,
             reward_configuration_version=c.reward_configuration_version
       WHERE id = o.id RETURNING * INTO o;
    ELSE
      INSERT INTO public.sovereign_pack_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
        payment_method, status, idempotency_key, confirmed_at, bonus_percent_snapshot, fc_snapshot, reward_configuration_version)
      VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'internal_ton', 'paid', p_idempotency_key, now(),
        c.account_ton_bonus_percent, c.fc_reward, c.reward_configuration_version)
      RETURNING * INTO o;
    END IF;
    INSERT INTO public.sovereign_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, u.id, 'purchase_internal', v_price, 'celestial sovereign pack paid with internal TON');
    PERFORM public.sovereign_pack_deliver(o.id);
    SELECT * INTO o FROM public.sovereign_pack_purchases WHERE id = o.id;
    RETURN jsonb_build_object('status','completed','method','internal_ton','purchaseId',o.id,
      'priceTon',v_price,'delivery',o.delivery,'state',public.sovereign_pack_state(p_telegram_id));
  END IF;

  IF o.id IS NOT NULL AND o.status = 'pending' THEN
    RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
      'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(COALESCE(u.ton_balance,0), 9));
  END IF;

  INSERT INTO public.sovereign_pack_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
    payment_method, status, payment_address, payment_comment, idempotency_key,
    bonus_percent_snapshot, fc_snapshot, reward_configuration_version)
  VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'mythreon_sovpack:' || gen_random_uuid(), p_idempotency_key,
    c.account_ton_bonus_percent, c.fc_reward, c.reward_configuration_version)
  RETURNING * INTO o;

  RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
    'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(COALESCE(u.ton_balance,0), 9));
END $$;

CREATE OR REPLACE FUNCTION public.sovereign_pack_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.sovereign_pack_purchases; v_min numeric;
BEGIN
  IF p_tx_hash IS NULL OR btrim(p_tx_hash) = '' THEN RAISE EXCEPTION 'TX_HASH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.sovereign_pack_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'SOVEREIGN_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('status','already_processed','purchaseId',o.id,'delivery',o.delivery);
  END IF;
  IF EXISTS (SELECT 1 FROM public.sovereign_pack_purchases WHERE tx_hash = btrim(p_tx_hash) AND id <> o.id) THEN
    RAISE EXCEPTION 'TX_ALREADY_USED';
  END IF;
  v_min := (o.expected_nanoton::numeric * 97) / 100;
  IF COALESCE(p_amount_nano::numeric, 0) < v_min THEN RAISE EXCEPTION 'INVALID_PAYMENT_AMOUNT'; END IF;

  INSERT INTO public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  VALUES (btrim(p_tx_hash), o.user_id, 'sovereign_pack', p_amount_nano::numeric, o.id::text)
  ON CONFLICT (tx_hash) DO NOTHING;

  IF o.status = 'pending' THEN
    UPDATE public.sovereign_pack_purchases
       SET status='paid', tx_hash=btrim(p_tx_hash), confirmed_at=COALESCE(confirmed_at, now())
     WHERE id = o.id;
    INSERT INTO public.sovereign_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, o.user_id, 'purchase_onchain', o.price_ton, 'celestial sovereign pack paid via TonConnect');
  END IF;
  RETURN public.sovereign_pack_deliver(o.id) || jsonb_build_object('status','completed','purchaseId',o.id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_sovereign_pack_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.sovereign_pack_config; v_sold integer; v_ton numeric; v_heroes integer; v_pets integer;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  c := public.sovereign_pack_settings();
  SELECT count(*), COALESCE(SUM(price_ton),0) INTO v_sold, v_ton
    FROM public.sovereign_pack_purchases WHERE status IN ('paid','delivered');
  SELECT count(*) INTO v_heroes FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key);
  SELECT count(*) INTO v_pets FROM public.nft_pets WHERE owner_user_id IS NULL AND status <> 'BURNED';
  RETURN jsonb_build_object(
    'config', to_jsonb(c), 'sold', v_sold, 'tonCollected', round(v_ton,9),
    'celestialAvailable', v_heroes, 'nftPetsAvailable', v_pets,
    'bonusPolicy', public.ton_mining_bonus_policy(),
    'metrics', public.admin_premium_offer_metrics(p_admin_id,'CELESTIAL_SOVEREIGN_PACK'),
    'purchases', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'player', COALESCE(g.username, g.name), 'telegramId', g.telegram_id, 'status', p.status,
        'priceTon', p.price_ton, 'createdAt', p.created_at, 'deliveredAt', p.delivered_at)
        ORDER BY p.created_at DESC)
      FROM public.sovereign_pack_purchases p JOIN public.game_players g ON g.id = p.user_id
      WHERE p.status IN ('paid','delivered')), '[]'::jsonb),
    'pendingReveals', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'itemId', i.id, 'userId', i.user_id, 'telegramId', g.telegram_id, 'player', COALESCE(g.username, g.name),
        'type', i.item_type, 'template', i.template_id, 'instanceId', i.instance_id, 'createdAt', i.created_at)
        ORDER BY i.created_at)
      FROM public.sovereign_pack_items i JOIN public.game_players g ON g.id = i.user_id
      WHERE i.mining_pending_reveal), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_sovereign_pack_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_num numeric; v_bool boolean; v_ts timestamptz; r record;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_field IN ('enabled','sales_paused','popup_enabled','sold_out_visible') THEN
    v_bool := lower(COALESCE(p_value,'')) IN ('1','true','on','yes');
    IF p_field = 'enabled' THEN UPDATE public.sovereign_pack_config SET enabled = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'sales_paused' THEN UPDATE public.sovereign_pack_config SET sales_paused = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'sold_out_visible' THEN UPDATE public.sovereign_pack_config SET sold_out_visible = v_bool, updated_at = now() WHERE id;
    ELSE UPDATE public.sovereign_pack_config SET popup_enabled = v_bool, updated_at = now() WHERE id; END IF;
  ELSIF p_field IN ('price_ton','fc_reward','legendary_chests','mythic_chests','nft_weapons','mythic_armors',
                    'celestial_armors','random_items','account_ton_bonus_percent','popup_priority',
                    'purchase_limit','stock_total') THEN
    v_num := COALESCE(p_value,'')::numeric;
    IF v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    IF p_field = 'price_ton' THEN UPDATE public.sovereign_pack_config SET price_ton = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'fc_reward' THEN UPDATE public.sovereign_pack_config SET fc_reward = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'legendary_chests' THEN UPDATE public.sovereign_pack_config SET legendary_chests = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'mythic_chests' THEN UPDATE public.sovereign_pack_config SET mythic_chests = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'nft_weapons' THEN UPDATE public.sovereign_pack_config SET nft_weapons = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'mythic_armors' THEN UPDATE public.sovereign_pack_config SET mythic_armors = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'celestial_armors' THEN UPDATE public.sovereign_pack_config SET celestial_armors = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'random_items' THEN UPDATE public.sovereign_pack_config SET random_items = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'popup_priority' THEN UPDATE public.sovereign_pack_config SET popup_priority = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'purchase_limit' THEN UPDATE public.sovereign_pack_config SET purchase_limit = GREATEST(v_num::int,1), updated_at = now() WHERE id;
    ELSIF p_field = 'stock_total' THEN UPDATE public.sovereign_pack_config SET stock_total = NULLIF(v_num::int,0), updated_at = now() WHERE id;
    ELSE UPDATE public.sovereign_pack_config SET account_ton_bonus_percent = v_num, updated_at = now() WHERE id; END IF;
  ELSIF p_field = 'popup_frequency' THEN
    IF upper(btrim(COALESCE(p_value,''))) NOT IN ('DISABLED','DAILY','EVERY_2_DAYS','EVERY_3_DAYS','ONCE_ONLY','UNTIL_PURCHASED') THEN
      RAISE EXCEPTION 'INVALID_VALUE';
    END IF;
    UPDATE public.sovereign_pack_config SET popup_frequency = upper(btrim(p_value)), updated_at = now() WHERE id;
  ELSIF p_field IN ('start_at','ends_at') THEN
    v_ts := CASE WHEN COALESCE(btrim(p_value),'') IN ('','-','null','NULL') THEN NULL ELSE p_value::timestamptz END;
    IF p_field = 'start_at' THEN UPDATE public.sovereign_pack_config SET start_at = v_ts, updated_at = now() WHERE id;
    ELSE UPDATE public.sovereign_pack_config SET ends_at = v_ts, updated_at = now() WHERE id; END IF;
  ELSIF p_field = 'bonus_policy' THEN
    IF upper(btrim(COALESCE(p_value,''))) NOT IN ('STACK','HIGHEST_ONLY') THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    UPDATE public.ton_mining_bonus_settings SET policy = upper(btrim(p_value)), updated_at = now() WHERE id;
    FOR r IN SELECT DISTINCT user_id FROM public.ton_mining_bonus_entitlements LOOP
      PERFORM public.ton_mining_bonus_recalc(r.user_id);
    END LOOP;
  ELSE
    RAISE EXCEPTION 'UNKNOWN_FIELD';
  END IF;
  PERFORM public.admin_log(p_admin_id,'sovereign_pack.set','config',p_field,null,jsonb_build_object('value',p_value),null);
  RETURN public.admin_sovereign_pack_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_sovereign_pack_reveal(p_admin_id bigint, p_item_id uuid, p_daily_ton numeric, p_daily_myth numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE it public.sovereign_pack_items; v_ton numeric; v_myth numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO it FROM public.sovereign_pack_items WHERE id = p_item_id FOR UPDATE;
  IF it.id IS NULL THEN RAISE EXCEPTION 'SOVEREIGN_PACK_ITEM_NOT_FOUND'; END IF;
  IF NOT it.mining_pending_reveal THEN RAISE EXCEPTION 'SOVEREIGN_PACK_ALREADY_REVEALED'; END IF;
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
    RAISE EXCEPTION 'SOVEREIGN_PACK_ITEM_NOT_REVEALABLE';
  END IF;

  UPDATE public.sovereign_pack_items
     SET mining_pending_reveal = false, revealed_ton = v_ton, revealed_myth = v_myth, revealed_at = now()
   WHERE id = it.id;

  INSERT INTO public.sovereign_pack_ledger(purchase_id, user_id, kind, note)
    VALUES (it.purchase_id, it.user_id, 'mining_revealed',
      it.item_type || ' revealed: ' || v_ton::text || ' TON/dia + ' || v_myth::text || ' MYTH/dia');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (it.user_id, 'sovereign_pack', 'MINERACAO REVELADA',
    'A taxa de mineracao do seu ' || it.item_type || ' do Celestial Sovereign Pack foi revelada.',
    jsonb_build_object('ton', v_ton, 'myth', v_myth, 'itemId', it.id), 'sovereign_reveal:' || it.id::text)
  ON CONFLICT DO NOTHING;

  PERFORM public.admin_log(p_admin_id,'sovereign_pack.reveal','item',it.id::text,null,
    jsonb_build_object('ton',v_ton,'myth',v_myth,'type',it.item_type),null);

  RETURN jsonb_build_object('ok', true, 'itemId', it.id, 'ton', v_ton, 'myth', v_myth);
END $$;

CREATE OR REPLACE FUNCTION public.should_show_premium_offer_popup(p_user_id uuid, p_offer_id text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; m jsonb; c public.celestial_pack_config; s public.sovereign_pack_config;
        v_last date; v_today date := public.premium_offer_day_key(); v_offer text; v_freq text;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE id = p_user_id;
  IF u.id IS NULL THEN RETURN 'NOT_ELIGIBLE'; END IF;
  IF COALESCE(u.banned,false) THEN RETURN 'NOT_ELIGIBLE'; END IF;

  v_offer := upper(COALESCE(p_offer_id,''));
  IF v_offer = 'CELESTIAL_MYSTERY_PACK' THEN
    c := public.celestial_pack_settings();
    IF NOT c.enabled OR NOT c.popup_enabled OR upper(c.popup_frequency) = 'DISABLED' THEN RETURN 'INACTIVE'; END IF;
    m := public.celestial_pack_offer_meta(p_user_id);
    v_freq := c.popup_frequency;
  ELSIF v_offer = 'CELESTIAL_SOVEREIGN_PACK' THEN
    s := public.sovereign_pack_settings();
    IF NOT s.enabled OR NOT s.popup_enabled OR upper(s.popup_frequency) = 'DISABLED' THEN RETURN 'INACTIVE'; END IF;
    m := public.sovereign_pack_offer_meta(p_user_id);
    v_freq := s.popup_frequency;
  ELSE
    RETURN 'NOT_ELIGIBLE';
  END IF;

  IF (m->>'purchased')::boolean OR (m->>'processing')::boolean THEN RETURN 'PURCHASED'; END IF;
  IF NOT (m->>'windowOpen')::boolean THEN RETURN 'INACTIVE'; END IF;
  IF (m->>'soldOut')::boolean THEN RETURN 'INACTIVE'; END IF;

  SELECT max(impression_date) INTO v_last FROM public.premium_offer_impressions
   WHERE user_id = p_user_id AND offer_id = v_offer;
  IF v_last IS NOT NULL AND v_today < v_last + public.premium_offer_frequency_days(v_freq) THEN
    RETURN 'ALREADY_SHOWN';
  END IF;
  RETURN 'SHOW';
END $$;

CREATE OR REPLACE FUNCTION public.premium_offers_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; fc public.founder_pack_config; vc public.veteran_vault_v2_config;
        cc public.celestial_pack_config; sc public.sovereign_pack_config;
        f jsonb; v jsonb; cp jsonb; sp jsonb; meta jsonb; smeta jsonb; v_day date := public.premium_offer_day_key();
        v_queue text[] := array[]::text[]; v_f_seen boolean; v_v_seen boolean; v_v_window boolean;
        v_c_status text; v_c_seen boolean; v_s_status text; v_s_seen boolean;
        v_ranked record;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  fc := public.founder_pack_settings();
  SELECT * INTO vc FROM public.veteran_vault_v2_config WHERE id;
  cc := public.celestial_pack_settings();
  sc := public.sovereign_pack_settings();

  f := public.founder_pack_state(p_telegram_id);
  v := public.veteran_v2_state(p_telegram_id);
  cp := public.celestial_pack_state(p_telegram_id);
  meta := public.celestial_pack_offer_meta(u.id);
  sp := public.sovereign_pack_state(p_telegram_id);
  smeta := public.sovereign_pack_offer_meta(u.id);

  v_v_window := COALESCE(vc.enabled,false)
                AND now() >= COALESCE(vc.start_at, now())
                AND (vc.ends_at IS NULL OR now() < vc.ends_at);

  SELECT EXISTS (SELECT 1 FROM public.premium_offer_popup_views
                  WHERE user_id = u.id AND offer_type = 'FOUNDER_PACK' AND day_key = v_day) INTO v_f_seen;
  SELECT EXISTS (SELECT 1 FROM public.premium_offer_popup_views
                  WHERE user_id = u.id AND offer_type = 'VETERAN_VAULT' AND day_key = v_day) INTO v_v_seen;

  v_c_status := public.should_show_premium_offer_popup(u.id, 'CELESTIAL_MYSTERY_PACK');
  v_c_seen := v_c_status <> 'SHOW';
  v_s_status := public.should_show_premium_offer_popup(u.id, 'CELESTIAL_SOVEREIGN_PACK');
  v_s_seen := v_s_status <> 'SHOW';

  FOR v_ranked IN
    SELECT * FROM (
      VALUES
        ('CELESTIAL_SOVEREIGN_PACK', sc.popup_priority, v_s_status = 'SHOW'),
        ('CELESTIAL_MYSTERY_PACK', cc.popup_priority, v_c_status = 'SHOW'),
        ('FOUNDER_PACK', fc.popup_priority,
          COALESCE(fc.popup_enabled,false) AND fc.popup_frequency <> 'DISABLED'
          AND COALESCE((f->>'eligible')::boolean,false) AND NOT v_f_seen),
        ('VETERAN_VAULT', vc.popup_priority,
          COALESCE(vc.popup_enabled,false) AND vc.popup_frequency <> 'DISABLED' AND v_v_window
          AND COALESCE((v->>'eligible')::boolean,false) AND NOT v_v_seen)
    ) AS t(offer, priority, ok)
    WHERE t.ok ORDER BY t.priority DESC, t.offer
  LOOP
    v_queue := array_append(v_queue, v_ranked.offer);
  END LOOP;

  RETURN jsonb_build_object(
    'dayKey', v_day,
    'timezone', public.premium_offer_timezone(),
    'queue', to_jsonb(v_queue),
    'founder', f || jsonb_build_object('popupSeenToday', v_f_seen, 'popupFrequency', fc.popup_frequency,
                                       'popupPriority', fc.popup_priority),
    'veteran', v || jsonb_build_object('popupSeenToday', v_v_seen, 'popupFrequency', vc.popup_frequency,
                                       'startAt', vc.start_at, 'endsAt', vc.ends_at,
                                       'popupPriority', vc.popup_priority,
                                       'windowOpen', v_v_window),
    'celestial', cp || meta || jsonb_build_object('popupSeenToday', v_c_seen, 'popupStatus', v_c_status),
    'sovereign', sp || smeta || jsonb_build_object('popupSeenToday', v_s_seen, 'popupStatus', v_s_status));
END $$;