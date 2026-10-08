-- LEGENDARY ADVENTURER PACK — 30 TON (tier LEGENDARY, abaixo do Mythic Vanguard 50 TON).
-- REGRAS ABSOLUTAS: nada CELESTIAL, nenhum MYTHIC garantido, passe OFICIAL de 5 TON incluído no preço.

CREATE OR REPLACE FUNCTION public.adventurer_assert_tier_safe(p_rarity text, p_what text)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE v text := lower(COALESCE(p_rarity,''));
BEGIN
  IF v LIKE '%celestial%' THEN
    RAISE EXCEPTION 'ADVENTURER_CELESTIAL_FORBIDDEN: % (%)', p_what, p_rarity;
  END IF;
  IF v LIKE '%mythic%' THEN
    RAISE EXCEPTION 'ADVENTURER_MYTHIC_FORBIDDEN: % (%)', p_what, p_rarity;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.adventurer_pack_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  sales_paused boolean NOT NULL DEFAULT false,
  package_version text NOT NULL DEFAULT 'LEGENDARY_ADVENTURER_V1',
  price_ton numeric NOT NULL DEFAULT 30,
  popup_enabled boolean NOT NULL DEFAULT true,
  popup_frequency text NOT NULL DEFAULT 'DAILY',
  popup_priority integer NOT NULL DEFAULT 80,
  hero_rarity text NOT NULL DEFAULT 'legendary',
  fc_reward numeric NOT NULL DEFAULT 250000,
  legendary_chests integer NOT NULL DEFAULT 3,
  nft_weapons integer NOT NULL DEFAULT 1,
  legendary_armors integer NOT NULL DEFAULT 1,
  universal_fragments integer NOT NULL DEFAULT 30,
  random_items integer NOT NULL DEFAULT 2,
  account_ton_bonus_percent numeric NOT NULL DEFAULT 0.5,
  grant_pass_tier text NOT NULL DEFAULT 'adventurer',
  max_reward_rarity text NOT NULL DEFAULT 'LEGENDARY',
  lock_mining_after_reveal boolean NOT NULL DEFAULT true,
  random_items_pool jsonb NOT NULL DEFAULT '[
    {"type":"fragments","code":"fragments","qty":50,"rarity":"legendary"},
    {"type":"fragments","code":"rare_fragments","qty":40,"rarity":"rare"},
    {"type":"fragments","code":"epic_fragments","qty":30,"rarity":"epic"},
    {"type":"fragments","code":"legendary_fragments","qty":20,"rarity":"legendary"},
    {"type":"hero_xp","code":"hero_xp_bundle","qty":1,"rarity":"epic"},
    {"type":"pet_food","code":"pet_food_bundle","qty":1,"rarity":"epic"},
    {"type":"pvp_ticket","code":"pvp_ticket","qty":3,"rarity":"rare"},
    {"type":"evolution","code":"evolution_materials","qty":2,"rarity":"epic"},
    {"type":"equipment_box","code":"rare_equipment_box","qty":1,"rarity":"rare"},
    {"type":"equipment_box","code":"epic_equipment_box","qty":1,"rarity":"epic"},
    {"type":"equipment_box","code":"legendary_equipment_box","qty":1,"rarity":"legendary"},
    {"type":"hero_chest","code":"rare_chest","qty":1,"rarity":"rare"},
    {"type":"hero_chest","code":"epic_chest","qty":1,"rarity":"epic"},
    {"type":"hero_chest","code":"legendary_chest","qty":1,"rarity":"legendary"},
    {"type":"upgrade_material","code":"premium_upgrade_materials","qty":2,"rarity":"epic"}
  ]'::jsonb,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  purchase_limit integer NOT NULL DEFAULT 1,
  stock_total integer,
  sold_out_visible boolean NOT NULL DEFAULT true,
  start_at timestamptz,
  ends_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.adventurer_pack_config(id) VALUES (true) ON CONFLICT (id) DO NOTHING;
GRANT ALL ON public.adventurer_pack_config TO service_role;
ALTER TABLE public.adventurer_pack_config ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.adventurer_pack_purchases (
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
  bonus_percent_snapshot numeric NOT NULL DEFAULT 0.5,
  fc_snapshot numeric NOT NULL DEFAULT 0,
  fragments_snapshot integer NOT NULL DEFAULT 0,
  pass_tier_snapshot text NOT NULL DEFAULT 'adventurer',
  reward_configuration_version integer NOT NULL DEFAULT 1,
  delivery jsonb,
  fulfillment_error text,
  confirmed_at timestamptz,
  delivered_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '1 hour',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS adventurer_pack_purchases_user_idx ON public.adventurer_pack_purchases(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS adventurer_pack_purchases_tx_idx ON public.adventurer_pack_purchases(tx_hash) WHERE tx_hash IS NOT NULL;
GRANT ALL ON public.adventurer_pack_purchases TO service_role;
ALTER TABLE public.adventurer_pack_purchases ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.adventurer_pack_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid,
  user_id uuid,
  kind text NOT NULL,
  ton_amount numeric,
  fc_amount numeric,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.adventurer_pack_ledger TO service_role;
ALTER TABLE public.adventurer_pack_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.adventurer_pack_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  purchase_id uuid NOT NULL,
  item_type text NOT NULL,
  template_id text,
  rarity text,
  instance_id uuid,
  quantity integer NOT NULL DEFAULT 1,
  mining_pending_reveal boolean NOT NULL DEFAULT false,
  mining_locked boolean NOT NULL DEFAULT false,
  revealed_ton numeric,
  revealed_myth numeric,
  revealed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (purchase_id, item_type, template_id, instance_id)
);
CREATE INDEX IF NOT EXISTS adventurer_pack_items_user_idx ON public.adventurer_pack_items(user_id);
CREATE INDEX IF NOT EXISTS adventurer_pack_items_pending_idx ON public.adventurer_pack_items(mining_pending_reveal) WHERE mining_pending_reveal;
GRANT ALL ON public.adventurer_pack_items TO service_role;
ALTER TABLE public.adventurer_pack_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.adventurer_pack_reveal_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id bigint NOT NULL,
  user_id uuid NOT NULL,
  purchase_id uuid,
  item_id uuid NOT NULL,
  item_instance_id uuid,
  item_type text NOT NULL,
  old_ton numeric,
  new_ton numeric,
  old_myth numeric,
  new_myth numeric,
  override boolean NOT NULL DEFAULT false,
  reason text,
  revealed_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.adventurer_pack_reveal_audit TO service_role;
ALTER TABLE public.adventurer_pack_reveal_audit ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.adventurer_pack_settings()
RETURNS public.adventurer_pack_config LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.adventurer_pack_config;
BEGIN
  SELECT * INTO c FROM public.adventurer_pack_config WHERE id = true;
  RETURN c;
END $$;

CREATE OR REPLACE FUNCTION public.adventurer_hero_pool_size()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT count(*)::int FROM public.hero_catalog h, public.adventurer_pack_config c
   WHERE c.id AND h.enabled
     AND lower(h.rarity) = lower(c.hero_rarity)
     AND lower(h.rarity) NOT LIKE '%celestial%'
     AND lower(h.rarity) NOT LIKE '%mythic%'
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key)
$$;

CREATE OR REPLACE FUNCTION public.adventurer_pack_offer_meta(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.adventurer_pack_config; v_heroes integer; v_sold integer; v_mine integer;
        v_pending uuid; v_paid_pending boolean; v_stock integer;
BEGIN
  c := public.adventurer_pack_settings();
  v_heroes := public.adventurer_hero_pool_size();
  SELECT count(*) INTO v_sold FROM public.adventurer_pack_purchases
   WHERE package_version = c.package_version AND status IN ('paid','delivered');
  SELECT count(*) INTO v_mine FROM public.adventurer_pack_purchases
   WHERE user_id = p_user_id AND package_version = c.package_version AND status IN ('paid','delivered');
  SELECT id INTO v_pending FROM public.adventurer_pack_purchases
   WHERE user_id = p_user_id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  SELECT EXISTS (SELECT 1 FROM public.adventurer_pack_purchases
                  WHERE user_id = p_user_id AND status = 'paid' AND delivered_at IS NULL) INTO v_paid_pending;
  v_stock := LEAST(v_heroes, COALESCE(NULLIF(c.stock_total,0) - v_sold, v_heroes));

  RETURN jsonb_build_object(
    'offerId','LEGENDARY_ADVENTURER_PACK',
    'priceTon', c.price_ton,
    'popupEnabled', c.popup_enabled,
    'popupFrequency', c.popup_frequency,
    'popupPriority', c.popup_priority,
    'purchaseLimit', c.purchase_limit,
    'startAt', c.start_at,
    'endsAt', c.ends_at,
    'stockTotal', c.stock_total,
    'stockRemaining', GREATEST(COALESCE(v_stock,0),0),
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

CREATE OR REPLACE FUNCTION public.adventurer_pack_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.adventurer_pack_config;
        v_owned public.adventurer_pack_purchases; v_pending public.adventurer_pack_purchases;
        v_heroes integer;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  c := public.adventurer_pack_settings();
  v_heroes := public.adventurer_hero_pool_size();

  SELECT * INTO v_owned FROM public.adventurer_pack_purchases
   WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered')
   ORDER BY created_at DESC LIMIT 1;
  SELECT * INTO v_pending FROM public.adventurer_pack_purchases
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
                AND v_owned.id IS NULL AND v_heroes > 0,
    'soldOut', COALESCE(c.enabled,false) AND v_heroes <= 0,
    'heroRarity', upper(c.hero_rarity),
    'legendaryAvailable', v_heroes,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'availableTon', round(COALESCE(u.ton_balance,0), 9),
    'fcReward', c.fc_reward,
    'legendaryChests', c.legendary_chests,
    'nftWeapons', c.nft_weapons,
    'legendaryArmors', c.legendary_armors,
    'universalFragments', c.universal_fragments,
    'randomItems', c.random_items,
    'passTier', c.grant_pass_tier,
    'passIncluded', true,
    'maxRewardRarity', c.max_reward_rarity,
    'accountBonusPercent', c.account_ton_bonus_percent,
    'ownerBonusPercent', round(COALESCE(u.account_ton_mining_bonus,0), 4),
    'bonusPolicy', public.ton_mining_bonus_policy(),
    'bonusSources', COALESCE((SELECT jsonb_agg(jsonb_build_object('source', e.source, 'percent', e.percent) ORDER BY e.percent DESC)
        FROM public.ton_mining_bonus_entitlements e WHERE e.user_id = u.id), '[]'::jsonb),
    'miningRevealPending', COALESCE((SELECT bool_or(i.mining_pending_reveal) FROM public.adventurer_pack_items i WHERE i.user_id = u.id), false),
    'delivery', v_owned.delivery,
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type', i.item_type, 'template', i.template_id, 'rarity', i.rarity, 'instanceId', i.instance_id,
        'pendingReveal', i.mining_pending_reveal, 'revealedTon', i.revealed_ton,
        'revealedMyth', i.revealed_myth, 'revealedAt', i.revealed_at) ORDER BY i.created_at)
      FROM public.adventurer_pack_items i WHERE i.user_id = u.id), '[]'::jsonb),
    'pendingOrder', CASE WHEN v_pending.id IS NULL THEN NULL ELSE jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.expected_nanoton, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) END
  );
END $$;

CREATE OR REPLACE FUNCTION public.adventurer_pack_offer_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN public.adventurer_pack_state(p_telegram_id) || public.adventurer_pack_offer_meta(v_user);
END $$;

CREATE OR REPLACE FUNCTION public.adventurer_pack_grant_pass(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.adventurer_pack_purchases; v_season uuid; v_tier text; v_before text; v_row record;
BEGIN
  SELECT * INTO o FROM public.adventurer_pack_purchases WHERE id = p_purchase_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ADVENTURER_PACK_ORDER_NOT_FOUND'; END IF;
  v_tier := lower(COALESCE(o.pass_tier_snapshot,'adventurer'));
  IF v_tier NOT IN ('adventurer','legendary') THEN v_tier := 'adventurer'; END IF;

  IF EXISTS (SELECT 1 FROM public.adventurer_pack_items
              WHERE purchase_id = o.id AND item_type = 'season_pass') THEN
    RETURN jsonb_build_object('granted', false, 'alreadyGranted', true, 'tier', v_tier);
  END IF;

  v_season := public.pass_user_season_id(o.user_id);
  IF v_season IS NULL THEN
    SELECT id INTO v_season FROM public.season_pass_seasons WHERE active ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_season IS NULL THEN RETURN jsonb_build_object('granted', false, 'reason', 'NO_ACTIVE_SEASON'); END IF;

  SELECT tier INTO v_before FROM public.player_season_pass WHERE user_id = o.user_id AND season_id = v_season;
  IF COALESCE(v_before,'none') IN ('adventurer','legendary') THEN
    INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity)
    VALUES (o.user_id, o.id, 'season_pass', v_season::text || ':' || v_tier, 'PASS')
    ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('granted', true, 'alreadyOwned', true, 'preserved', true,
      'seasonId', v_season, 'tier', v_tier, 'previousTier', v_before,
      'sourceType', 'PREMIUM_PACK', 'sourcePack', 'LEGENDARY_ADVENTURER_PACK', 'packPurchaseId', o.id);
  END IF;

  v_row := public.season_pass_apply_entitlement(o.user_id, v_season, v_tier);
  INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity)
  VALUES (o.user_id, o.id, 'season_pass', v_season::text || ':' || v_tier, 'PASS')
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('granted', true, 'seasonId', v_season, 'tier', v_tier,
    'previousTier', COALESCE(v_before,'none'), 'sourceType', 'PREMIUM_PACK',
    'sourcePack', 'LEGENDARY_ADVENTURER_PACK', 'packPurchaseId', o.id);
END $$;

CREATE OR REPLACE FUNCTION public.adventurer_pack_deliver(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.adventurer_pack_purchases; c public.adventurer_pack_config;
        hc public.hero_catalog; v_hero uuid; v_delivery jsonb := '{}'::jsonb;
        v_weapons jsonb := '[]'::jsonb; v_armors jsonb := '[]'::jsonb; v_random jsonb := '[]'::jsonb;
        r record; v_peq uuid; v_assign jsonb; v_pick jsonb; v_pool jsonb; v_safe jsonb := '[]'::jsonb;
        i integer; v_bonus numeric; v_pass jsonb; v_frag integer;
BEGIN
  SELECT * INTO o FROM public.adventurer_pack_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ADVENTURER_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'alreadyDelivered', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'ADVENTURER_PACK_NOT_PAID'; END IF;
  c := public.adventurer_pack_settings();

  SELECT * INTO hc FROM public.hero_catalog h
   WHERE h.enabled AND lower(h.rarity) = lower(c.hero_rarity)
     AND lower(h.rarity) NOT LIKE '%celestial%'
     AND lower(h.rarity) NOT LIKE '%mythic%'
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key)
   ORDER BY random() LIMIT 1;
  IF hc.hero_key IS NULL THEN RAISE EXCEPTION 'ADVENTURER_LEGENDARY_HERO_SOLD_OUT'; END IF;
  PERFORM public.adventurer_assert_tier_safe(hc.rarity, 'legendary_hero');
  INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image,
      mining_daily_myth, mining_ton_override, mining_pending_reveal, mining_last_at, premium_source)
  VALUES (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image,
      0, 0, true, now(), 'ADVENTURER_PACK')
  RETURNING id INTO v_hero;
  INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity, instance_id, mining_pending_reveal)
  VALUES (o.user_id, o.id, 'hero', hc.hero_key, lower(hc.rarity), v_hero, true);
  v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object(
    'id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name, 'rarity', lower(hc.rarity),
    'miningStatus', 'PENDING_REVEAL'));

  v_pass := public.adventurer_pack_grant_pass(o.id);
  v_delivery := v_delivery || jsonb_build_object('pass', v_pass);

  IF COALESCE(o.fc_snapshot,0) > 0 THEN
    UPDATE public.game_players SET forge_coins = COALESCE(forge_coins,0) + o.fc_snapshot, updated_at = now()
     WHERE id = o.user_id;
    INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity, quantity)
    VALUES (o.user_id, o.id, 'forge_coins', 'FC', NULL, o.fc_snapshot::int)
    ON CONFLICT DO NOTHING;
    v_delivery := v_delivery || jsonb_build_object('forgeCoins', o.fc_snapshot);
  END IF;

  IF COALESCE(c.legendary_chests,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', 'legendary_chest', c.legendary_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
    INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity, quantity)
    VALUES (o.user_id, o.id, 'legendary_chest', 'legendary_chest', 'legendary', c.legendary_chests)
    ON CONFLICT DO NOTHING;
  END IF;
  v_delivery := v_delivery || jsonb_build_object(
    'legendaryChests', c.legendary_chests, 'maxRewardRarity', c.max_reward_rarity);

  FOR r IN SELECT n.id, lower(COALESCE(t.rarity,'')) AS rarity FROM public.nft_equipment n
            JOIN public.equipment_templates t ON t.id = n.template_id
           WHERE n.owner_user_id IS NULL AND n.status <> 'BURNED'
             AND lower(COALESCE(t.slot,'')) = 'weapon'
             AND lower(COALESCE(t.rarity,'')) NOT LIKE '%celestial%'
           ORDER BY n.for_sale ASC, random()
           LIMIT GREATEST(0, COALESCE(c.nft_weapons,1)) LOOP
    IF lower(r.rarity) LIKE '%celestial%' THEN
      RAISE EXCEPTION 'ADVENTURER_CELESTIAL_FORBIDDEN: nft_weapon (%)', r.rarity;
    END IF;
    v_assign := public.nft_equipment_assign_unit(r.id, o.user_id, 'adventurer_pack');
    INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity, instance_id)
    VALUES (o.user_id, o.id, 'nft_weapon', v_assign->>'name', r.rarity, (v_assign->>'instanceId')::uuid)
    ON CONFLICT DO NOTHING;
    v_weapons := v_weapons || jsonb_build_array(v_assign || jsonb_build_object('rarity', r.rarity));
  END LOOP;

  FOR r IN SELECT t.id, t.code, t.name, lower(t.rarity) AS rarity, t.image_url
             FROM public.equipment_templates t
            WHERE t.is_active AND NOT COALESCE(t.is_nft,false)
              AND lower(COALESCE(t.slot,'')) IN ('armor','chest','armour')
              AND lower(COALESCE(t.rarity,'')) = 'legendary'
            ORDER BY random() LIMIT GREATEST(0, COALESCE(c.legendary_armors,1)) LOOP
    PERFORM public.adventurer_assert_tier_safe(r.rarity, 'legendary_armor');
    INSERT INTO public.player_equipment(user_id, template_id, level, source, source_ref)
    VALUES (o.user_id, r.id, 1, 'adventurer_pack', o.id::text)
    RETURNING id INTO v_peq;
    INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity, instance_id)
    VALUES (o.user_id, o.id, 'legendary_armor', r.code, r.rarity, v_peq)
    ON CONFLICT DO NOTHING;
    v_armors := v_armors || jsonb_build_array(jsonb_build_object(
      'id', v_peq, 'code', r.code, 'name', r.name, 'rarity', r.rarity, 'image', r.image_url));
  END LOOP;

  IF COALESCE(o.fragments_snapshot,0) > 0 THEN
    v_frag := public.add_universal_fragments(o.user_id, o.fragments_snapshot);
    INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity, quantity)
    VALUES (o.user_id, o.id, 'universal_fragments', 'universal_fragment', NULL, o.fragments_snapshot)
    ON CONFLICT DO NOTHING;
    v_delivery := v_delivery || jsonb_build_object('universalFragments', o.fragments_snapshot, 'fragmentsBalance', v_frag);
  END IF;

  v_pool := COALESCE(c.random_items_pool, '[]'::jsonb);
  FOR i IN 0..GREATEST(jsonb_array_length(v_pool) - 1, 0) LOOP
    v_pick := v_pool -> i;
    IF v_pick IS NOT NULL
       AND lower(COALESCE(v_pick->>'code','')) NOT LIKE '%celestial%'
       AND lower(COALESCE(v_pick->>'code','')) NOT LIKE '%mythic%'
       AND lower(COALESCE(v_pick->>'rarity','')) NOT LIKE '%celestial%'
       AND lower(COALESCE(v_pick->>'rarity','')) NOT LIKE '%mythic%'
       AND lower(COALESCE(v_pick->>'type','')) NOT IN ('fc','forge_coins','ton','ton_balance') THEN
      v_safe := v_safe || jsonb_build_array(v_pick);
    END IF;
  END LOOP;
  IF jsonb_array_length(v_safe) > 0 THEN
    FOR i IN 1..GREATEST(0, COALESCE(c.random_items,0)) LOOP
      v_pick := v_safe -> floor(random() * jsonb_array_length(v_safe))::int;
      INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
      VALUES (o.user_id, v_pick->>'type', v_pick->>'code', GREATEST(1, COALESCE((v_pick->>'qty')::int,1)))
      ON CONFLICT (user_id, item_type, item_code)
        DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
      INSERT INTO public.adventurer_pack_items(user_id, purchase_id, item_type, template_id, rarity, quantity)
      VALUES (o.user_id, o.id, 'random_item_' || i::text, v_pick->>'code', v_pick->>'rarity',
              GREATEST(1, COALESCE((v_pick->>'qty')::int,1)))
      ON CONFLICT DO NOTHING;
      v_random := v_random || jsonb_build_array(v_pick);
    END LOOP;
  END IF;

  v_bonus := public.ton_mining_bonus_grant(o.user_id, 'LEGENDARY_ADVENTURER_PACK',
    COALESCE(o.bonus_percent_snapshot,0), 'Legendary Adventurer Pack');

  INSERT INTO public.player_entitlements(user_id, code, source)
  VALUES (o.user_id, 'ADVENTURER_PACK_OWNER', 'adventurer_pack')
  ON CONFLICT (user_id, code) DO NOTHING;

  IF EXISTS (SELECT 1 FROM public.adventurer_pack_items
              WHERE purchase_id = o.id
                AND (lower(COALESCE(rarity,'')) LIKE '%celestial%'
                     OR (item_type LIKE 'random_item_%' AND lower(COALESCE(rarity,'')) LIKE '%mythic%'))) THEN
    RAISE EXCEPTION 'ADVENTURER_CELESTIAL_FORBIDDEN: fulfillment';
  END IF;

  v_delivery := v_delivery || jsonb_build_object(
    'nftWeapons', v_weapons, 'armors', v_armors, 'randomItems', v_random,
    'accountBonusPercent', o.bonus_percent_snapshot, 'accountBonusEffective', v_bonus,
    'bonusPolicy', public.ton_mining_bonus_policy(),
    'sourceType', 'PREMIUM_PACK', 'sourceId', 'LEGENDARY_ADVENTURER_PACK', 'packPurchaseId', o.id);

  UPDATE public.adventurer_pack_purchases
     SET status = 'delivered', delivered_at = now(), delivery = v_delivery, fulfillment_error = NULL
   WHERE id = o.id;

  INSERT INTO public.adventurer_pack_ledger(purchase_id, user_id, kind, fc_amount, note)
    VALUES (o.id, o.user_id, 'delivery', o.fc_snapshot, 'legendary adventurer pack delivered (mining pending reveal)');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (o.user_id, 'adventurer_pack', 'LEGENDARY ADVENTURER PACK ATIVO',
          'Recompensas entregues e passe oficial de 5 TON ativado. A taxa de mineracao do Heroi Lendario sera revelada em breve.',
          v_delivery, 'adventurer_pack:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END $$;

CREATE OR REPLACE FUNCTION public.adventurer_pack_start_purchase(p_telegram_id bigint, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.adventurer_pack_config; o public.adventurer_pack_purchases;
        v_price numeric; v_nano text; v_heroes integer;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  c := public.adventurer_pack_settings();
  IF NOT c.enabled THEN RAISE EXCEPTION 'ADVENTURER_PACK_DISABLED'; END IF;
  IF c.sales_paused THEN RAISE EXCEPTION 'ADVENTURER_PACK_SALES_PAUSED'; END IF;
  IF now() < COALESCE(c.start_at, now()) OR (c.ends_at IS NOT NULL AND now() >= c.ends_at) THEN
    RAISE EXCEPTION 'ADVENTURER_PACK_OUTSIDE_WINDOW';
  END IF;
  IF (SELECT count(*) FROM public.adventurer_pack_purchases
       WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered'))
     >= GREATEST(c.purchase_limit,1) THEN
    RAISE EXCEPTION 'ADVENTURER_PACK_ALREADY_PURCHASED';
  END IF;

  v_heroes := public.adventurer_hero_pool_size();
  IF v_heroes <= 0 THEN RAISE EXCEPTION 'ADVENTURER_PACK_SOLD_OUT'; END IF;

  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;

  SELECT * INTO o FROM public.adventurer_pack_purchases WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NULL THEN
    SELECT * INTO o FROM public.adventurer_pack_purchases
     WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF o.id IS NOT NULL AND o.status IN ('paid','delivered') THEN
    RETURN jsonb_build_object('status','completed','method',o.payment_method,'purchaseId',o.id,
      'priceTon',o.price_ton,'delivery',o.delivery,'duplicate',true,'state',public.adventurer_pack_state(p_telegram_id));
  END IF;

  IF round(COALESCE(u.ton_balance,0), 9) >= round(v_price, 9) THEN
    UPDATE public.game_players SET ton_balance = round(COALESCE(ton_balance,0) - v_price, 9), updated_at = now() WHERE id = u.id;
    IF o.id IS NOT NULL AND o.status = 'pending' THEN
      UPDATE public.adventurer_pack_purchases
         SET status='paid', payment_method='internal_ton', confirmed_at=now(), price_ton=v_price,
             expected_nanoton=v_nano, package_version=c.package_version,
             bonus_percent_snapshot=c.account_ton_bonus_percent, fc_snapshot=c.fc_reward,
             fragments_snapshot=c.universal_fragments, pass_tier_snapshot=c.grant_pass_tier,
             reward_configuration_version=c.reward_configuration_version
       WHERE id = o.id RETURNING * INTO o;
    ELSE
      INSERT INTO public.adventurer_pack_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
        payment_method, status, idempotency_key, confirmed_at, bonus_percent_snapshot, fc_snapshot,
        fragments_snapshot, pass_tier_snapshot, reward_configuration_version)
      VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'internal_ton', 'paid', p_idempotency_key, now(),
        c.account_ton_bonus_percent, c.fc_reward, c.universal_fragments, c.grant_pass_tier, c.reward_configuration_version)
      RETURNING * INTO o;
    END IF;
    INSERT INTO public.adventurer_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, u.id, 'purchase_internal', v_price, 'legendary adventurer pack paid with internal TON');
    PERFORM public.adventurer_pack_deliver(o.id);
    SELECT * INTO o FROM public.adventurer_pack_purchases WHERE id = o.id;
    RETURN jsonb_build_object('status','completed','method','internal_ton','purchaseId',o.id,
      'priceTon',v_price,'delivery',o.delivery,'state',public.adventurer_pack_state(p_telegram_id));
  END IF;

  IF o.id IS NOT NULL AND o.status = 'pending' THEN
    RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
      'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(COALESCE(u.ton_balance,0), 9));
  END IF;

  INSERT INTO public.adventurer_pack_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
    payment_method, status, payment_address, payment_comment, idempotency_key,
    bonus_percent_snapshot, fc_snapshot, fragments_snapshot, pass_tier_snapshot, reward_configuration_version)
  VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'mythreon_advpack:' || gen_random_uuid(), p_idempotency_key,
    c.account_ton_bonus_percent, c.fc_reward, c.universal_fragments, c.grant_pass_tier, c.reward_configuration_version)
  RETURNING * INTO o;

  RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
    'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(COALESCE(u.ton_balance,0), 9));
END $$;

CREATE OR REPLACE FUNCTION public.adventurer_pack_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.adventurer_pack_purchases; v_min numeric;
BEGIN
  IF p_tx_hash IS NULL OR btrim(p_tx_hash) = '' THEN RAISE EXCEPTION 'TX_HASH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.adventurer_pack_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ADVENTURER_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('status','already_processed','purchaseId',o.id,'delivery',o.delivery);
  END IF;
  IF EXISTS (SELECT 1 FROM public.adventurer_pack_purchases WHERE tx_hash = btrim(p_tx_hash) AND id <> o.id) THEN
    RAISE EXCEPTION 'TX_ALREADY_USED';
  END IF;
  v_min := (o.expected_nanoton::numeric * 97) / 100;
  IF COALESCE(p_amount_nano::numeric, 0) < v_min THEN RAISE EXCEPTION 'INVALID_PAYMENT_AMOUNT'; END IF;

  INSERT INTO public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  VALUES (btrim(p_tx_hash), o.user_id, 'adventurer_pack', p_amount_nano::numeric, o.id::text)
  ON CONFLICT (tx_hash) DO NOTHING;

  IF o.status = 'pending' THEN
    UPDATE public.adventurer_pack_purchases
       SET status='paid', tx_hash=btrim(p_tx_hash), confirmed_at=COALESCE(confirmed_at, now())
     WHERE id = o.id;
    INSERT INTO public.adventurer_pack_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, o.user_id, 'purchase_onchain', o.price_ton, 'legendary adventurer pack paid via TonConnect');
  END IF;
  RETURN public.adventurer_pack_deliver(o.id) || jsonb_build_object('status','completed','purchaseId',o.id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_adventurer_pack_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.adventurer_pack_config; v_sold integer; v_ton numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  c := public.adventurer_pack_settings();
  SELECT count(*), COALESCE(SUM(price_ton),0) INTO v_sold, v_ton
    FROM public.adventurer_pack_purchases WHERE status IN ('paid','delivered');
  RETURN jsonb_build_object(
    'config', to_jsonb(c), 'sold', v_sold, 'tonCollected', round(v_ton,9),
    'legendaryHeroesAvailable', public.adventurer_hero_pool_size(),
    'nftWeaponsAvailable', (SELECT count(*) FROM public.nft_equipment n JOIN public.equipment_templates t ON t.id = n.template_id
        WHERE n.owner_user_id IS NULL AND n.status <> 'BURNED' AND lower(COALESCE(t.slot,'')) = 'weapon'
          AND lower(COALESCE(t.rarity,'')) NOT LIKE '%celestial%'),
    'legendaryArmorTemplates', (SELECT count(*) FROM public.equipment_templates t
        WHERE t.is_active AND NOT COALESCE(t.is_nft,false)
          AND lower(COALESCE(t.slot,'')) IN ('armor','chest','armour') AND lower(COALESCE(t.rarity,'')) = 'legendary'),
    'randomPool', c.random_items_pool,
    'bonusPolicy', public.ton_mining_bonus_policy(),
    'metrics', public.admin_premium_offer_metrics(p_admin_id,'LEGENDARY_ADVENTURER_PACK'),
    'purchases', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'player', COALESCE(g.username, g.name), 'telegramId', g.telegram_id, 'status', p.status,
        'priceTon', p.price_ton, 'method', p.payment_method, 'createdAt', p.created_at,
        'deliveredAt', p.delivered_at, 'purchaseId', p.id, 'error', p.fulfillment_error)
        ORDER BY p.created_at DESC)
      FROM public.adventurer_pack_purchases p JOIN public.game_players g ON g.id = p.user_id
      WHERE p.status IN ('paid','delivered')), '[]'::jsonb),
    'intents', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'orderId', p.id, 'player', COALESCE(g.username, g.name), 'telegramId', g.telegram_id,
        'amountNano', p.expected_nanoton, 'expiresAt', p.expires_at) ORDER BY p.created_at DESC)
      FROM public.adventurer_pack_purchases p JOIN public.game_players g ON g.id = p.user_id
      WHERE p.status = 'pending' AND p.expires_at > now()), '[]'::jsonb),
    'passGrants', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'player', COALESCE(g.username, g.name), 'telegramId', g.telegram_id,
        'grant', i.template_id, 'grantedAt', i.created_at, 'purchaseId', i.purchase_id) ORDER BY i.created_at DESC)
      FROM public.adventurer_pack_items i JOIN public.game_players g ON g.id = i.user_id
      WHERE i.item_type = 'season_pass'), '[]'::jsonb),
    'pendingReveals', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'itemId', i.id, 'userId', i.user_id, 'telegramId', g.telegram_id, 'player', COALESCE(g.username, g.name),
        'type', i.item_type, 'template', i.template_id, 'instanceId', i.instance_id, 'createdAt', i.created_at)
        ORDER BY i.created_at)
      FROM public.adventurer_pack_items i JOIN public.game_players g ON g.id = i.user_id
      WHERE i.mining_pending_reveal), '[]'::jsonb),
    'reveals', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'itemType', a.item_type, 'oldTon', a.old_ton, 'newTon', a.new_ton, 'override', a.override,
        'reason', a.reason, 'revealedAt', a.revealed_at, 'telegramId', g.telegram_id,
        'player', COALESCE(g.username, g.name)) ORDER BY a.revealed_at DESC)
      FROM public.adventurer_pack_reveal_audit a JOIN public.game_players g ON g.id = a.user_id), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_adventurer_pack_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_num numeric; v_bool boolean; v_ts timestamptz;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_field IN ('enabled','sales_paused','popup_enabled','sold_out_visible','lock_mining_after_reveal') THEN
    v_bool := lower(COALESCE(p_value,'')) IN ('1','true','on','yes');
    IF p_field = 'enabled' THEN UPDATE public.adventurer_pack_config SET enabled = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'sales_paused' THEN UPDATE public.adventurer_pack_config SET sales_paused = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'sold_out_visible' THEN UPDATE public.adventurer_pack_config SET sold_out_visible = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'lock_mining_after_reveal' THEN UPDATE public.adventurer_pack_config SET lock_mining_after_reveal = v_bool, updated_at = now() WHERE id;
    ELSE UPDATE public.adventurer_pack_config SET popup_enabled = v_bool, updated_at = now() WHERE id; END IF;
  ELSIF p_field IN ('price_ton','fc_reward','legendary_chests','nft_weapons','legendary_armors','universal_fragments',
                    'random_items','account_ton_bonus_percent','popup_priority','purchase_limit','stock_total') THEN
    v_num := COALESCE(p_value,'')::numeric;
    IF v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    IF p_field = 'price_ton' THEN UPDATE public.adventurer_pack_config SET price_ton = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'fc_reward' THEN UPDATE public.adventurer_pack_config SET fc_reward = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'legendary_chests' THEN UPDATE public.adventurer_pack_config SET legendary_chests = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'nft_weapons' THEN UPDATE public.adventurer_pack_config SET nft_weapons = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'legendary_armors' THEN UPDATE public.adventurer_pack_config SET legendary_armors = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'universal_fragments' THEN UPDATE public.adventurer_pack_config SET universal_fragments = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'random_items' THEN UPDATE public.adventurer_pack_config SET random_items = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'popup_priority' THEN UPDATE public.adventurer_pack_config SET popup_priority = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'purchase_limit' THEN UPDATE public.adventurer_pack_config SET purchase_limit = GREATEST(v_num::int,1), updated_at = now() WHERE id;
    ELSIF p_field = 'stock_total' THEN UPDATE public.adventurer_pack_config SET stock_total = NULLIF(v_num::int,0), updated_at = now() WHERE id;
    ELSE UPDATE public.adventurer_pack_config SET account_ton_bonus_percent = v_num, updated_at = now() WHERE id; END IF;
  ELSIF p_field = 'popup_frequency' THEN
    IF upper(btrim(COALESCE(p_value,''))) NOT IN ('DISABLED','DAILY','EVERY_2_DAYS','EVERY_3_DAYS','ONCE_ONLY','UNTIL_PURCHASED') THEN
      RAISE EXCEPTION 'INVALID_VALUE';
    END IF;
    UPDATE public.adventurer_pack_config SET popup_frequency = upper(btrim(p_value)), updated_at = now() WHERE id;
  ELSIF p_field = 'hero_rarity' THEN
    IF lower(btrim(COALESCE(p_value,''))) <> 'legendary' THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    UPDATE public.adventurer_pack_config SET hero_rarity = 'legendary', updated_at = now() WHERE id;
  ELSIF p_field = 'grant_pass_tier' THEN
    IF lower(btrim(COALESCE(p_value,''))) NOT IN ('adventurer','legendary') THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    UPDATE public.adventurer_pack_config SET grant_pass_tier = lower(btrim(p_value)), updated_at = now() WHERE id;
  ELSIF p_field IN ('start_at','ends_at') THEN
    v_ts := CASE WHEN COALESCE(btrim(p_value),'') IN ('','-','null','NULL') THEN NULL ELSE p_value::timestamptz END;
    IF p_field = 'start_at' THEN UPDATE public.adventurer_pack_config SET start_at = v_ts, updated_at = now() WHERE id;
    ELSE UPDATE public.adventurer_pack_config SET ends_at = v_ts, updated_at = now() WHERE id; END IF;
  ELSE
    RAISE EXCEPTION 'UNKNOWN_FIELD';
  END IF;
  PERFORM public.admin_log(p_admin_id,'adventurer_pack.set',p_field,jsonb_build_object('value',p_value));
  RETURN public.admin_adventurer_pack_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_adventurer_pack_reveal(p_admin_id bigint, p_item_id uuid, p_daily_ton numeric,
  p_daily_myth numeric DEFAULT 0, p_override boolean DEFAULT false, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE it public.adventurer_pack_items; c public.adventurer_pack_config; v_ton numeric; v_myth numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  c := public.adventurer_pack_settings();
  SELECT * INTO it FROM public.adventurer_pack_items WHERE id = p_item_id FOR UPDATE;
  IF it.id IS NULL THEN RAISE EXCEPTION 'ADVENTURER_PACK_ITEM_NOT_FOUND'; END IF;
  IF it.item_type <> 'hero' THEN RAISE EXCEPTION 'ADVENTURER_PACK_ITEM_NOT_REVEALABLE'; END IF;
  IF NOT it.mining_pending_reveal THEN
    IF COALESCE(c.lock_mining_after_reveal,true) AND NOT COALESCE(p_override,false) THEN
      RAISE EXCEPTION 'ADVENTURER_MINING_LOCKED';
    END IF;
    IF COALESCE(p_override,false) AND COALESCE(btrim(p_reason),'') = '' THEN
      RAISE EXCEPTION 'ADVENTURER_OVERRIDE_REASON_REQUIRED';
    END IF;
  END IF;
  v_ton := GREATEST(COALESCE(p_daily_ton,0), 0);
  v_myth := GREATEST(COALESCE(p_daily_myth,0), 0);

  UPDATE public.player_heroes
     SET mining_ton_override = v_ton, mining_daily_myth = v_myth,
         mining_pending_reveal = false, mining_revealed_at = now(), mining_last_at = now(), updated_at = now()
   WHERE id = it.instance_id;

  INSERT INTO public.adventurer_pack_reveal_audit(admin_id, user_id, purchase_id, item_id, item_instance_id,
    item_type, old_ton, new_ton, old_myth, new_myth, override, reason)
  VALUES (p_admin_id, it.user_id, it.purchase_id, it.id, it.instance_id, it.item_type,
    it.revealed_ton, v_ton, it.revealed_myth, v_myth, COALESCE(p_override,false), p_reason);

  UPDATE public.adventurer_pack_items
     SET mining_pending_reveal = false, mining_locked = COALESCE(c.lock_mining_after_reveal,true),
         revealed_ton = v_ton, revealed_myth = v_myth, revealed_at = now()
   WHERE id = it.id;

  INSERT INTO public.adventurer_pack_ledger(purchase_id, user_id, kind, note)
    VALUES (it.purchase_id, it.user_id, 'mining_revealed',
      it.item_type || ' revealed: ' || v_ton::text || ' TON/dia + ' || v_myth::text || ' MYTH/dia');

  PERFORM public.admin_log(p_admin_id,'adventurer_pack.reveal',it.id::text,
    jsonb_build_object('ton',v_ton,'myth',v_myth,'type',it.item_type,'override',COALESCE(p_override,false),'reason',p_reason));

  RETURN jsonb_build_object('ok', true, 'itemId', it.id, 'ton', v_ton, 'myth', v_myth,
    'locked', COALESCE(c.lock_mining_after_reveal,true));
END $$;

CREATE OR REPLACE FUNCTION public.admin_adventurer_pack_retry(p_admin_id bigint, p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_result := public.adventurer_pack_deliver(p_purchase_id);
  PERFORM public.admin_log(p_admin_id,'adventurer_pack.retry_fulfillment',p_purchase_id::text,v_result);
  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.adventurer_pack_offer_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.adventurer_pack_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.adventurer_pack_start_purchase(bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.adventurer_pack_confirm_order(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_adventurer_pack_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_adventurer_pack_set(bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_adventurer_pack_reveal(bigint, uuid, numeric, numeric, boolean, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_adventurer_pack_retry(bigint, uuid) TO service_role;