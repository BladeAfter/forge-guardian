-- 1) settings helper
CREATE OR REPLACE FUNCTION public.veteran_v2_settings()
RETURNS public.veteran_vault_v2_config LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.veteran_vault_v2_config;
BEGIN
  INSERT INTO public.veteran_vault_v2_config(id) VALUES (true) ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.veteran_myth_pools(id) VALUES (true) ON CONFLICT (id) DO NOTHING;
  SELECT * INTO c FROM public.veteran_vault_v2_config WHERE id;
  RETURN c;
END $$;

-- 2) owner boost (percent) — snapshotted at purchase time
CREATE OR REPLACE FUNCTION public.veteran_v2_boost_percent(p_user_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(MAX(boost_percent_snapshot), 0)
    FROM public.veteran_vault_v2_purchases
   WHERE user_id = p_user_id AND status IN ('paid','delivered');
$$;

-- 3) state
CREATE OR REPLACE FUNCTION public.veteran_v2_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.veteran_vault_v2_config; p public.veteran_myth_pools;
        v_owned public.veteran_vault_v2_purchases; v_pending public.veteran_vault_v2_purchases;
        v_available numeric; v_funded boolean;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO c FROM public.veteran_vault_v2_config WHERE id;
  SELECT * INTO p FROM public.veteran_myth_pools WHERE id;

  v_available := COALESCE(p.reward_funded,0) - COALESCE(p.reward_distributed,0);
  v_funded := v_available >= COALESCE(c.myth_reward, 0);

  SELECT * INTO v_owned FROM public.veteran_vault_v2_purchases
   WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered')
   ORDER BY created_at DESC LIMIT 1;
  SELECT * INTO v_pending FROM public.veteran_vault_v2_purchases
   WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'enabled', COALESCE(c.enabled,false),
    'salesPaused', COALESCE(c.sales_paused,false),
    'packageVersion', c.package_version,
    'show', COALESCE(c.enabled,false) AND (v_owned.id IS NOT NULL OR NOT COALESCE(c.sales_paused,false)),
    'popupEnabled', COALESCE(c.popup_enabled,false) AND v_owned.id IS NULL,
    'popupFrequency', c.popup_frequency,
    'purchased', v_owned.id IS NOT NULL,
    'eligible', COALESCE(c.enabled,false) AND NOT COALESCE(c.sales_paused,false) AND v_owned.id IS NULL AND v_funded,
    'soldOut', COALESCE(c.enabled,false) AND NOT v_funded,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'availableTon', round(COALESCE(u.ton_balance,0), 9),
    'boostPercent', c.boost_percent,
    'ownerBoostPercent', public.veteran_v2_boost_percent(u.id),
    'mythReward', c.myth_reward,
    'legendaryChests', c.legendary_chests,
    'fragments', c.fragments,
    'weaponsPerPurchase', c.weapons_per_purchase,
    'heroDailyMyth', c.hero_daily_myth,
    'petDailyMyth', c.pet_daily_myth,
    'dragonDailyMyth', c.dragon_daily_myth,
    'mythReferenceRate', c.myth_reference_rate,
    'delivery', v_owned.delivery,
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('type', i.item_type, 'template', i.template_id, 'instanceId', i.instance_id) ORDER BY i.created_at)
                         FROM public.veteran_vault_v2_items i WHERE i.user_id = u.id), '[]'::jsonb),
    'pendingOrder', CASE WHEN v_pending.id IS NULL THEN NULL ELSE jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.expected_nanoton, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) END
  );
END $$;

-- 4) deliver
CREATE OR REPLACE FUNCTION public.veteran_v2_deliver(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.veteran_vault_v2_purchases; c public.veteran_vault_v2_config;
        hc public.hero_catalog; pt public.pets; eg public.pet_eggs;
        v_hero uuid; v_pet uuid; v_season uuid; v_myth numeric; v_delivery jsonb := '{}'::jsonb;
        v_weapons jsonb := '[]'::jsonb; r record; v_peq uuid;
BEGIN
  SELECT * INTO o FROM public.veteran_vault_v2_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'VETERAN_V2_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'alreadyDelivered', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'VETERAN_V2_NOT_PAID'; END IF;
  c := public.veteran_v2_settings();

  -- premium season pass (legendary)
  SELECT id INTO v_season FROM public.season_pass_seasons WHERE active ORDER BY created_at DESC LIMIT 1;
  IF v_season IS NOT NULL THEN
    PERFORM public.season_pass_apply_entitlement(o.user_id, v_season, 'legendary');
    v_delivery := v_delivery || jsonb_build_object('pass', jsonb_build_object('seasonId', v_season, 'tier', 'legendary'));
  END IF;

  -- MYTH reward, taken from the funded Veteran reward pool (no new supply)
  v_myth := GREATEST(0, COALESCE(o.myth_reward_snapshot, c.myth_reward));
  IF v_myth > 0 THEN
    INSERT INTO public.myth_balances(user_id, amount) VALUES (o.user_id, 0) ON CONFLICT (user_id) DO NOTHING;
    UPDATE public.myth_balances SET amount = amount + v_myth, updated_at = now() WHERE user_id = o.user_id;
    INSERT INTO public.myth_ledger(user_id, direction, amount, reason) VALUES (o.user_id, 'credit', v_myth, 'veteran_vault_v2');
    UPDATE public.veteran_myth_pools SET reward_distributed = reward_distributed + v_myth, updated_at = now() WHERE id;
    v_delivery := v_delivery || jsonb_build_object('myth', v_myth);
  END IF;

  -- Veteran hero (MYTH mining only)
  SELECT * INTO hc FROM public.hero_catalog
   WHERE veteran_line AND enabled
     AND hero_key NOT IN (SELECT ph.hero_key FROM public.player_heroes ph WHERE ph.user_id = o.user_id)
   ORDER BY random() LIMIT 1;
  IF hc.hero_key IS NULL THEN
    SELECT * INTO hc FROM public.hero_catalog WHERE veteran_line AND enabled ORDER BY random() LIMIT 1;
  END IF;
  IF hc.hero_key IS NOT NULL THEN
    INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image, veteran_line, mining_daily_myth, mining_last_at)
    VALUES (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image, true, c.hero_daily_myth, now())
    RETURNING id INTO v_hero;
    INSERT INTO public.veteran_vault_v2_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'hero', hc.hero_key, v_hero);
    v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object('id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name));
  END IF;

  -- Veteran pet
  SELECT * INTO pt FROM public.pets WHERE veteran_line AND COALESCE(veteran_role,'pet') = 'pet' AND is_enabled
   ORDER BY random() LIMIT 1;
  IF pt.id IS NOT NULL THEN
    INSERT INTO public.player_pets(user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, veteran_line, mining_daily_myth, mining_last_at)
    VALUES (o.user_id, pt.id, public.normalize_pet_rarity(pt.rarity), 1, 0, 'baby', 0, false, true, c.pet_daily_myth, now())
    RETURNING id INTO v_pet;
    INSERT INTO public.veteran_vault_v2_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'pet', pt.slug, v_pet);
    v_delivery := v_delivery || jsonb_build_object('pet', jsonb_build_object('id', v_pet, 'slug', pt.slug, 'name', pt.name));
  END IF;

  -- Veteran dragon egg
  SELECT * INTO eg FROM public.pet_eggs WHERE veteran_line AND is_enabled AND veteran_dragon_pet_id IS NOT NULL
   ORDER BY random() LIMIT 1;
  IF eg.id IS NOT NULL THEN
    INSERT INTO public.player_pet_inventory(user_id, item_type, item_id, quantity)
    VALUES (o.user_id, 'egg', eg.id, 1)
    ON CONFLICT (user_id, item_type, item_id) DO UPDATE SET quantity = public.player_pet_inventory.quantity + 1, updated_at = now();
    INSERT INTO public.veteran_vault_v2_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'egg', eg.slug, eg.id);
    v_delivery := v_delivery || jsonb_build_object('egg', jsonb_build_object('id', eg.id, 'slug', eg.slug, 'name', eg.name));
  END IF;

  -- Veteran weapons
  FOR r IN SELECT * FROM public.equipment_templates WHERE veteran_line AND is_active
            ORDER BY random() LIMIT GREATEST(1, COALESCE(c.weapons_per_purchase, 2)) LOOP
    INSERT INTO public.player_equipment(user_id, template_id, level, source, source_ref, veteran_line, mining_daily_myth, mining_last_at)
    VALUES (o.user_id, r.id, 1, 'veteran_vault_v2', o.id::text, true, 1000, now())
    RETURNING id INTO v_peq;
    INSERT INTO public.veteran_vault_v2_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'weapon', r.code, v_peq);
    v_weapons := v_weapons || jsonb_build_array(jsonb_build_object('id', v_peq, 'code', r.code, 'name', r.name));
  END LOOP;

  -- Legendary chests + fragments
  IF COALESCE(c.legendary_chests, 0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', 'legendary_chest', c.legendary_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;
  IF COALESCE(c.fragments, 0) > 0 THEN
    PERFORM public.add_universal_fragments(o.user_id, c.fragments);
  END IF;

  -- Cosmetics
  INSERT INTO public.player_entitlements(user_id, code, source) VALUES (o.user_id, 'veteran_badge', 'veteran_vault_v2')
    ON CONFLICT (user_id, code) DO NOTHING;
  INSERT INTO public.player_entitlements(user_id, code, source, equipped) VALUES (o.user_id, 'veteran_frame', 'veteran_vault_v2', true)
    ON CONFLICT (user_id, code) DO NOTHING;
  INSERT INTO public.player_entitlements(user_id, code, source) VALUES (o.user_id, 'VETERAN_VAULT_V2_OWNER', 'veteran_vault_v2')
    ON CONFLICT (user_id, code) DO NOTHING;

  v_delivery := v_delivery || jsonb_build_object(
    'weapons', v_weapons, 'legendaryChests', COALESCE(c.legendary_chests,0),
    'fragments', COALESCE(c.fragments,0), 'boostPercent', o.boost_percent_snapshot,
    'badge', true, 'frame', true);

  UPDATE public.veteran_vault_v2_purchases
     SET status = 'delivered', delivered_at = now(), delivery = v_delivery WHERE id = o.id;

  INSERT INTO public.veteran_vault_v2_ledger(purchase_id, user_id, kind, myth_amount, note)
    VALUES (o.id, o.user_id, 'delivery', v_myth, 'veteran vault v2 rewards delivered');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (o.user_id, 'veteran_vault', 'VETERAN VAULT ATIVO',
          'Suas recompensas do Veteran Vault foram entregues e o bônus de +' || COALESCE(o.boost_percent_snapshot,0)::text || '% de MYTH está ativo.',
          v_delivery, 'veteran_vault_v2:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END $$;

-- 5) start purchase
CREATE OR REPLACE FUNCTION public.veteran_v2_start_purchase(p_telegram_id bigint, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; c public.veteran_vault_v2_config; p public.veteran_myth_pools;
        o public.veteran_vault_v2_purchases; v_price numeric; v_nano text; v_available numeric;
BEGIN
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  c := public.veteran_v2_settings();
  IF NOT c.enabled THEN RAISE EXCEPTION 'VETERAN_VAULT_DISABLED'; END IF;
  IF c.sales_paused THEN RAISE EXCEPTION 'VETERAN_VAULT_SALES_PAUSED'; END IF;
  IF EXISTS (SELECT 1 FROM public.veteran_vault_v2_purchases
              WHERE user_id = u.id AND package_version = c.package_version AND status IN ('paid','delivered')) THEN
    RAISE EXCEPTION 'VETERAN_VAULT_ALREADY_PURCHASED';
  END IF;

  SELECT * INTO p FROM public.veteran_myth_pools WHERE id FOR UPDATE;
  v_available := COALESCE(p.reward_funded,0) - COALESCE(p.reward_distributed,0);
  IF v_available < COALESCE(c.myth_reward,0) THEN RAISE EXCEPTION 'VETERAN_VAULT_SOLD_OUT'; END IF;

  v_price := c.price_ton;
  v_nano := round(v_price * 1000000000)::text;

  SELECT * INTO o FROM public.veteran_vault_v2_purchases WHERE idempotency_key = p_idempotency_key;
  IF o.id IS NULL THEN
    SELECT * INTO o FROM public.veteran_vault_v2_purchases
     WHERE user_id = u.id AND status = 'pending' AND expires_at > now() ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF o.id IS NOT NULL AND o.status IN ('paid','delivered') THEN
    RETURN jsonb_build_object('status','completed','method',o.payment_method,'purchaseId',o.id,
      'priceTon',o.price_ton,'delivery',o.delivery,'duplicate',true,'state',public.veteran_v2_state(p_telegram_id));
  END IF;

  -- 100% internal TON when it covers the price, otherwise 100% TonConnect
  IF round(COALESCE(u.ton_balance,0), 9) >= round(v_price, 9) THEN
    UPDATE public.game_players SET ton_balance = round(COALESCE(ton_balance,0) - v_price, 9), updated_at = now() WHERE id = u.id;
    IF o.id IS NOT NULL AND o.status = 'pending' THEN
      UPDATE public.veteran_vault_v2_purchases
         SET status='paid', payment_method='internal_ton', confirmed_at=now(), price_ton=v_price,
             expected_nanoton=v_nano, package_version=c.package_version,
             boost_percent_snapshot=c.boost_percent, myth_reward_snapshot=c.myth_reward,
             reward_configuration_version=c.reward_configuration_version
       WHERE id = o.id RETURNING * INTO o;
    ELSE
      INSERT INTO public.veteran_vault_v2_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
        payment_method, status, idempotency_key, confirmed_at, boost_percent_snapshot, myth_reward_snapshot, reward_configuration_version)
      VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'internal_ton', 'paid', p_idempotency_key, now(),
        c.boost_percent, c.myth_reward, c.reward_configuration_version)
      RETURNING * INTO o;
    END IF;
    INSERT INTO public.veteran_vault_v2_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, u.id, 'purchase_internal', v_price, 'veteran vault v2 paid with internal TON');
    PERFORM public.veteran_v2_deliver(o.id);
    SELECT * INTO o FROM public.veteran_vault_v2_purchases WHERE id = o.id;
    RETURN jsonb_build_object('status','completed','method','internal_ton','purchaseId',o.id,
      'priceTon',v_price,'delivery',o.delivery,'state',public.veteran_v2_state(p_telegram_id));
  END IF;

  IF o.id IS NOT NULL AND o.status = 'pending' THEN
    RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
      'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
      'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',o.price_ton,
      'availableTon', round(COALESCE(u.ton_balance,0), 9));
  END IF;

  INSERT INTO public.veteran_vault_v2_purchases(user_id, telegram_id, package_version, price_ton, expected_nanoton,
    payment_method, status, payment_address, payment_comment, idempotency_key,
    boost_percent_snapshot, myth_reward_snapshot, reward_configuration_version)
  VALUES (u.id, p_telegram_id, c.package_version, v_price, v_nano, 'ton_connect', 'pending',
    public.wallet_hot_address(), 'mythreon_vetv2:' || gen_random_uuid(), p_idempotency_key,
    c.boost_percent, c.myth_reward, c.reward_configuration_version)
  RETURNING * INTO o;

  RETURN jsonb_build_object('status','payment_required','method','ton_connect','orderId',o.id,
    'paymentAddress',o.payment_address,'amountNano',o.expected_nanoton,'amountTon',o.price_ton,
    'paymentComment',o.payment_comment,'expiresAt',o.expires_at,'priceTon',v_price,
    'availableTon', round(COALESCE(u.ton_balance,0), 9));
END $$;

-- 6) confirm on-chain order
CREATE OR REPLACE FUNCTION public.veteran_v2_confirm_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o public.veteran_vault_v2_purchases; v_min numeric;
BEGIN
  IF p_tx_hash IS NULL OR btrim(p_tx_hash) = '' THEN RAISE EXCEPTION 'TX_HASH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.veteran_vault_v2_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'VETERAN_V2_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('status','already_processed','purchaseId',o.id,'delivery',o.delivery);
  END IF;
  IF EXISTS (SELECT 1 FROM public.veteran_vault_v2_purchases WHERE tx_hash = btrim(p_tx_hash) AND id <> o.id) THEN
    RAISE EXCEPTION 'TX_ALREADY_USED';
  END IF;
  v_min := (o.expected_nanoton::numeric * 97) / 100;
  IF COALESCE(p_amount_nano::numeric, 0) < v_min THEN RAISE EXCEPTION 'INVALID_PAYMENT_AMOUNT'; END IF;

  INSERT INTO public.processed_ton_transactions(tx_hash, user_id, transaction_type, amount_nano, reference_id)
  VALUES (btrim(p_tx_hash), o.user_id, 'veteran_vault_v2', p_amount_nano::numeric, o.id::text)
  ON CONFLICT (tx_hash) DO NOTHING;

  IF o.status = 'pending' THEN
    UPDATE public.veteran_vault_v2_purchases
       SET status='paid', tx_hash=btrim(p_tx_hash), confirmed_at=COALESCE(confirmed_at, now())
     WHERE id = o.id;
    INSERT INTO public.veteran_vault_v2_ledger(purchase_id, user_id, kind, ton_amount, note)
      VALUES (o.id, o.user_id, 'purchase_onchain', o.price_ton, 'veteran vault v2 paid via TonConnect');
  END IF;
  RETURN public.veteran_v2_deliver(o.id) || jsonb_build_object('status','completed','purchaseId',o.id);
END $$;

-- 7) mining: +boost% MYTH for Veteran Vault owners
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
 RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_pet_myth numeric := 0; v_eq_myth numeric := 0; v_peq_myth numeric := 0;
        v_out numeric; v_room numeric; v_boost numeric := 0;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
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
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(
             COALESCE(h.mining_daily_myth, 0),
             CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                  ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END
           ) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT
    COALESCE(SUM(CASE WHEN myth_rate <= 0 AND rate > 0 THEN rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_ton_gain, v_myth_gain
    FROM moved;

  WITH pelig AS (
    SELECT p.id, GREATEST(COALESCE(p.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(p.mining_last_at, p.created_at, v_now)))) AS secs
      FROM player_pets p
     WHERE p.user_id = p_user_id
       AND COALESCE(p.mining_daily_myth, 0) > 0
       AND NOT COALESCE(p.market_locked, false)
  ), pmoved AS (
    UPDATE player_pets pp SET mining_last_at = v_now
      FROM pelig e WHERE pp.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_pet_myth FROM pmoved;

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

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0) + GREATEST(v_eq_myth, 0) + GREATEST(v_peq_myth, 0);

  -- Veteran Vault owners earn an extra boost on MYTH mining only.
  v_boost := GREATEST(COALESCE(public.veteran_v2_boost_percent(p_user_id), 0), 0);
  v_myth_gain := round(v_myth_gain * (1 + v_boost / 100.0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END;
$function$;

-- 8) Veteran eggs hatch a guaranteed Veteran dragon with MYTH mining enabled
CREATE OR REPLACE FUNCTION public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed_text text;
  rar text; picked pets%rowtype; picked_id uuid; existing player_pets%rowtype; prior pet_hatch_history%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0; new_pet_id uuid; is_new_pet boolean:=false; has_pool boolean;
  allowed text[]; v_cfg public.veteran_vault_v2_config;
begin
  if length(trim(p_idempotency_key))<8 or length(p_idempotency_key)>180 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_idempotency_key,0));
  select * into prior from pet_hatch_history
   where user_id=u and (opening_id=p_idempotency_key or idempotency_key=p_idempotency_key)
   order by created_at desc limit 1;
  if prior.id is not null then
    return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
  end if;

  select * into egg from pet_eggs where id=p_egg_id and is_enabled;
  if egg.id is null then raise exception 'EGG_NOT_FOUND'; end if;
  select * into inv from player_pet_inventory where user_id=u and item_type='egg' and item_id=p_egg_id for update;
  if inv.id is null or inv.quantity<1 then raise exception 'EGG_NOT_OWNED'; end if;

  seed_text:=forge_random_seed(p_idempotency_key);

  if coalesce(egg.veteran_line,false) and egg.veteran_dragon_pet_id is not null then
    select * into picked from pets where id = egg.veteran_dragon_pet_id;
    if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;
    rar := picked.rarity;
  else
    if abs(coalesce((select sum(value::numeric) from jsonb_each_text(egg.rarity_rates)),0)-100)>0.0001 then
      raise exception 'EGG_RATES_INVALID';
    end if;
    luck:=least(10,coalesce((get_pet_bonuses(u)->>'egg_luck_percent')::numeric,0));
    rar:=public.normalize_pet_rarity(roll_rarity_from_rates(egg.rarity_rates,luck));

    select array_agg(public.normalize_pet_rarity(k)) into allowed
      from jsonb_each_text(egg.rarity_rates) as t(k, v) where v::numeric > 0;
    if allowed is null or array_length(allowed,1) = 0 then raise exception 'EGG_RATES_INVALID'; end if;

    select exists(select 1 from reward_pet_pool rp join pets p on p.id=rp.pet_id
       where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled) into has_pool;

    if has_pool then
      picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
      if picked_id is null then
        select p.rarity into rar from reward_pet_pool rp join pets p on p.id=rp.pet_id
          where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled
            and p.rarity = any(allowed)
          order by abs(pet_rarity_order(p.rarity) - pet_rarity_order(rar)), pet_rarity_order(p.rarity) desc limit 1;
        picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
      end if;
      select * into picked from pets where id = picked_id;
    else
      select * into picked from pets p
        where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = rar
          and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
        order by hashtextextended(p.id::text||seed_text,0) limit 1;
      if picked.id is null then
        select p.rarity into rar from pets p
          where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = any(allowed)
            and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
          order by abs(pet_rarity_order(p.rarity) - pet_rarity_order(rar)), pet_rarity_order(p.rarity) desc limit 1;
        select * into picked from pets p
          where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = rar
            and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
          order by hashtextextended(p.id::text||seed_text,0) limit 1;
      end if;
    end if;
    if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;
    rar := picked.rarity;
  end if;

  update player_pet_inventory set quantity=quantity-1,updated_at=now() where id=inv.id;

  select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
  if existing.id is not null then
    select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';
    update player_pets set fragments=fragments+frags,updated_at=now() where id=existing.id;
    new_pet_id:=existing.id; is_new_pet:=false;
  else
    insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar) returning id into new_pet_id;
    frags:=0; is_new_pet:=true;
  end if;

  if coalesce(picked.veteran_line,false) then
    v_cfg := public.veteran_v2_settings();
    update player_pets
       set veteran_line = true,
           mining_daily_myth = greatest(coalesce(mining_daily_myth,0),
             case when coalesce(picked.veteran_role,'pet') = 'dragon' then v_cfg.dragon_daily_myth else v_cfg.pet_daily_myth end),
           mining_last_at = coalesce(mining_last_at, now()),
           updated_at = now()
     where id = new_pet_id;
  end if;

  insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key,opening_id,status,completed_at,is_new,result_player_pet_id)
    values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key,p_idempotency_key,'completed',now(),is_new_pet,new_pet_id) returning id into history_id;
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
    values(u,p_telegram_id,'egg',egg.slug,'pet_egg',rar,picked.id,picked.name);
  select * into prior from pet_hatch_history where id=history_id;
  return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
end $function$;

REVOKE ALL ON FUNCTION public.veteran_v2_settings() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_start_purchase(bigint, text, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_confirm_order(uuid, text, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_state(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_boost_percent(uuid) FROM anon, authenticated;