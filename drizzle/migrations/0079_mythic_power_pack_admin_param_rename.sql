DROP FUNCTION IF EXISTS public.admin_mythic_power_pack_set(bigint, text, text);
DROP FUNCTION IF EXISTS public.admin_mythic_power_pack_overview(bigint);

CREATE OR REPLACE FUNCTION public.admin_mythic_power_pack_overview(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c public.mythic_power_pack_config; v_count integer; v_ton numeric; v_bonus integer; v_purchases jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  c := public.mythic_power_pack_settings();
  SELECT count(*)::int, COALESCE(sum(price_ton),0) INTO v_count, v_ton
    FROM public.mythic_power_pack_purchases WHERE status IN ('paid','delivered');
  SELECT count(*)::int INTO v_bonus FROM public.mythic_power_pack_purchases WHERE first_purchase_bonus;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'purchaseId', p.id, 'player', g.name, 'telegramId', g.telegram_id,
      'priceTon', p.price_ton, 'status', p.status, 'method', p.payment_method,
      'firstPurchaseBonus', p.first_purchase_bonus,
      'deliveredAt', p.delivered_at, 'error', p.fulfillment_error) ORDER BY p.created_at DESC), '[]'::jsonb)
    INTO v_purchases
    FROM public.mythic_power_pack_purchases p
    JOIN public.game_players g ON g.id = p.user_id
   WHERE p.status IN ('paid','delivered');
  RETURN jsonb_build_object(
    'offerId','MYTHIC_POWER_PACK',
    'config', to_jsonb(c),
    'totalPurchases', COALESCE(v_count,0), 'totalTon', COALESCE(v_ton,0),
    'firstPurchaseBonusClaims', COALESCE(v_bonus,0),
    'purchases', v_purchases);
END $$;

CREATE OR REPLACE FUNCTION public.admin_mythic_power_pack_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_num numeric; v_bool boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
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
  RETURN public.admin_mythic_power_pack_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_mythic_power_pack_retry(p_admin_id bigint, p_purchase_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN public.mythic_power_pack_deliver(p_purchase_id);
END $$;