CREATE OR REPLACE FUNCTION public.veteran_v2_deliver(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE o public.veteran_vault_v2_purchases; c public.veteran_vault_v2_config;
        hc public.hero_catalog; eg public.pet_eggs;
        v_hero uuid; v_season uuid; v_myth numeric; v_delivery jsonb := '{}'::jsonb;
        v_weapons jsonb := '[]'::jsonb; r record; v_peq uuid;
BEGIN
  SELECT * INTO o FROM public.veteran_vault_v2_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'VETERAN_V2_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'alreadyDelivered', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'VETERAN_V2_NOT_PAID'; END IF;
  c := public.veteran_v2_settings();

  SELECT id INTO v_season FROM public.season_pass_seasons WHERE active ORDER BY created_at DESC LIMIT 1;
  IF v_season IS NOT NULL THEN
    PERFORM public.season_pass_apply_entitlement(o.user_id, v_season, 'legendary');
    v_delivery := v_delivery || jsonb_build_object('pass', jsonb_build_object('seasonId', v_season, 'tier', 'legendary'));
  END IF;

  v_myth := GREATEST(0, COALESCE(o.myth_reward_snapshot, c.myth_reward));
  IF v_myth > 0 THEN
    INSERT INTO public.myth_balances(user_id, amount) VALUES (o.user_id, 0) ON CONFLICT (user_id) DO NOTHING;
    UPDATE public.myth_balances SET amount = amount + v_myth, updated_at = now() WHERE user_id = o.user_id;
    INSERT INTO public.myth_ledger(user_id, direction, amount, reason) VALUES (o.user_id, 'credit', v_myth, 'veteran_vault_v2');
    UPDATE public.veteran_myth_pools SET reward_distributed = reward_distributed + v_myth, updated_at = now() WHERE id = true;
    v_delivery := v_delivery || jsonb_build_object('myth', v_myth);
  END IF;

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

  -- Unico pet do pacote: nasce ao eclodir o ovo Veteran
  SELECT * INTO eg FROM public.pet_eggs WHERE veteran_line AND is_enabled AND veteran_dragon_pet_id IS NOT NULL
   ORDER BY random() LIMIT 1;
  IF eg.id IS NOT NULL THEN
    UPDATE public.player_pet_inventory
        SET quantity = quantity + 1, updated_at = now()
      WHERE user_id = o.user_id AND item_type = 'egg' AND item_id = eg.id;
     IF NOT FOUND THEN
       INSERT INTO public.player_pet_inventory(user_id, item_type, item_id, quantity)
       VALUES (o.user_id, 'egg', eg.id, 1);
     END IF;
    INSERT INTO public.veteran_vault_v2_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'egg', eg.slug, eg.id);
    v_delivery := v_delivery || jsonb_build_object('egg', jsonb_build_object('id', eg.id, 'slug', eg.slug, 'name', eg.name));
  END IF;

  FOR r IN SELECT * FROM public.equipment_templates WHERE veteran_line AND is_active
            ORDER BY random() LIMIT GREATEST(1, COALESCE(c.weapons_per_purchase, 2)) LOOP
    INSERT INTO public.player_equipment(user_id, template_id, level, source, source_ref, veteran_line, mining_daily_myth, mining_last_at)
    VALUES (o.user_id, r.id, 1, 'veteran_vault_v2', gen_random_uuid(), true, 1000, now())
    RETURNING id INTO v_peq;
    INSERT INTO public.veteran_vault_v2_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'weapon', r.code, v_peq);
    v_weapons := v_weapons || jsonb_build_array(jsonb_build_object('id', v_peq, 'code', r.code, 'name', r.name));
  END LOOP;

  IF COALESCE(c.legendary_chests, 0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', 'legendary_chest', c.legendary_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;
  IF COALESCE(c.fragments, 0) > 0 THEN
    PERFORM public.add_universal_fragments(o.user_id, c.fragments);
  END IF;

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
          'Suas recompensas do Veteran Vault foram entregues e o bonus de +' || COALESCE(o.boost_percent_snapshot,0)::text || '% de MYTH esta ativo.',
          v_delivery, 'veteran_vault_v2:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END $function$;

REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.veteran_v2_deliver(uuid) TO service_role;