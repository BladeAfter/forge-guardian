CREATE OR REPLACE FUNCTION public.founder_pack_settings()
RETURNS public.founder_pack_config
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.founder_pack_config WHERE id = true
$$;

CREATE OR REPLACE FUNCTION public.founder_pack_deliver(p_purchase_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o public.founder_pack_purchases;
  s jsonb;
  hc public.hero_catalog;
  pt public.pets;
  v_hero uuid;
  v_pet uuid;
  v_season uuid;
  v_delivery jsonb := '{}'::jsonb;
  v_chests int;
  v_hero_myth numeric;
  v_pet_myth numeric;
  v_weapon public.equipment_templates;
  v_peq uuid;
BEGIN
  SELECT * INTO o
  FROM public.founder_pack_purchases
  WHERE id = p_purchase_id
  FOR UPDATE;

  IF o.id IS NULL THEN RAISE EXCEPTION 'FOUNDER_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'settled' THEN
    RETURN jsonb_build_object('ok', true, 'alreadySettled', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'FOUNDER_PACK_NOT_PAID'; END IF;

  s := o.reward_snapshot;
  v_chests := greatest(coalesce((s->>'legendaryChests')::int, 1), 1);
  v_hero_myth := greatest(coalesce((s->>'heroDailyMyth')::numeric, 0), 0);
  v_pet_myth := greatest(coalesce((s->>'petDailyMyth')::numeric, 0), 0);

  v_season := nullif(s->>'seasonId', '')::uuid;
  IF v_season IS NULL THEN
    SELECT id INTO v_season
    FROM public.season_pass_seasons
    WHERE active = true
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;
  IF v_season IS NOT NULL THEN
    PERFORM public.season_pass_apply_entitlement(o.user_id, v_season, coalesce(s->>'passTier', 'legendary'));
    v_delivery := v_delivery || jsonb_build_object('pass', jsonb_build_object('seasonId', v_season, 'tier', coalesce(s->>'passTier', 'legendary')));
  END IF;

  IF coalesce((s->>'mythAmount')::numeric, 0) > 0 THEN
    INSERT INTO public.myth_balances(user_id, amount)
    VALUES (o.user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;
    UPDATE public.myth_balances
    SET amount = amount + (s->>'mythAmount')::numeric, updated_at = now()
    WHERE user_id = o.user_id;
    INSERT INTO public.myth_ledger(user_id, direction, amount, reason)
    VALUES (o.user_id, 'credit', (s->>'mythAmount')::numeric, 'founder_pack');
    v_delivery := v_delivery || jsonb_build_object('myth', (s->>'mythAmount')::numeric);
  END IF;

  SELECT * INTO hc FROM public.hero_catalog WHERE hero_key = s->>'heroKey';
  IF hc.hero_key IS NULL THEN
    SELECT * INTO hc FROM public.hero_catalog WHERE rarity = 'mythic' ORDER BY random() LIMIT 1;
  END IF;
  IF hc.hero_key IS NOT NULL THEN
    INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image, mining_daily_myth, mining_last_at, premium_source)
    VALUES (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image, v_hero_myth, now(), 'FOUNDER')
    RETURNING id INTO v_hero;
    v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object('id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name, 'dailyMyth', v_hero_myth));
  END IF;

  SELECT * INTO pt
  FROM public.pets
  WHERE slug = s->>'petSlug' AND NOT coalesce(is_nft_exclusive, false);
  IF pt.id IS NULL THEN
    SELECT * INTO pt
    FROM public.pets
    WHERE rarity = 'mythic' AND NOT coalesce(is_nft_exclusive, false)
    ORDER BY random()
    LIMIT 1;
  END IF;
  IF pt.id IS NOT NULL THEN
    INSERT INTO public.player_pets(user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active, mining_daily_myth, mining_last_at, premium_source)
    VALUES (o.user_id, pt.id, public.normalize_pet_rarity(pt.rarity), 1, 0, 'baby', 0, false, v_pet_myth, now(), 'FOUNDER')
    RETURNING id INTO v_pet;
    v_delivery := v_delivery || jsonb_build_object('pet', jsonb_build_object('id', v_pet, 'slug', pt.slug, 'name', pt.name, 'dailyMyth', v_pet_myth));
  END IF;

  INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
  VALUES (o.user_id, 'hero_chest', coalesce(s->>'equipmentChestCode', 'legendary_chest'), v_chests)
  ON CONFLICT (user_id, item_type, item_code)
  DO UPDATE SET quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();

  SELECT * INTO v_weapon
  FROM public.equipment_templates
  WHERE is_active = true
    AND (code = nullif(s->>'weaponCode', '') OR (nullif(s->>'weaponCode', '') IS NULL AND founder_line = true))
  ORDER BY (code = coalesce(s->>'weaponCode', '')) DESC, random()
  LIMIT 1;
  IF v_weapon.id IS NOT NULL THEN
    INSERT INTO public.player_equipment(user_id, template_id, level, source, source_ref, premium_source)
    VALUES (o.user_id, v_weapon.id, 1, 'founder_pack', o.id, 'FOUNDER')
    RETURNING id INTO v_peq;
    v_delivery := v_delivery || jsonb_build_object('weapon', jsonb_build_object('id', v_peq, 'code', v_weapon.code, 'name', v_weapon.name));
  END IF;

  IF coalesce((s->>'fragments')::int, 0) > 0 THEN
    PERFORM public.add_universal_fragments(o.user_id, (s->>'fragments')::int);
  END IF;

  INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
  VALUES (o.user_id, 'resource_chest', coalesce(s->>'resourceChestCode', 'premium_resource_chest'), 1)
  ON CONFLICT (user_id, item_type, item_code)
  DO UPDATE SET quantity = public.player_inventory.quantity + 1, updated_at = now();

  IF coalesce((s->>'badge')::boolean, true) THEN
    INSERT INTO public.player_entitlements(user_id, code, source)
    VALUES (o.user_id, 'founder_badge', 'founder_pack')
    ON CONFLICT (user_id, code) DO NOTHING;
  END IF;
  IF coalesce((s->>'frame')::boolean, true) THEN
    INSERT INTO public.player_entitlements(user_id, code, source, equipped)
    VALUES (o.user_id, 'founder_frame', 'founder_pack', true)
    ON CONFLICT (user_id, code) DO NOTHING;
  END IF;

  v_delivery := v_delivery || jsonb_build_object(
    'equipmentChest', coalesce(s->>'equipmentChestCode', 'legendary_chest'),
    'legendaryChests', v_chests,
    'fragments', coalesce((s->>'fragments')::int, 0),
    'resourceChest', coalesce(s->>'resourceChestCode', 'premium_resource_chest'),
    'badge', coalesce((s->>'badge')::boolean, true),
    'frame', coalesce((s->>'frame')::boolean, true)
  );

  UPDATE public.founder_pack_purchases
  SET status = 'settled', settled_at = now(), delivery = v_delivery
  WHERE id = o.id;

  UPDATE public.premium_offer_popup_views
  SET purchase_id = o.id
  WHERE user_id = o.user_id AND offer_type = 'FOUNDER_PACK' AND purchase_id IS NULL;

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (o.user_id, 'founder_pack', 'FOUNDER PACK PURCHASED',
          'Your Founder Pack rewards have been delivered.', v_delivery, 'founder_pack:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END;
$$;

REVOKE ALL ON FUNCTION public.founder_pack_deliver(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.founder_pack_deliver(uuid) TO service_role;