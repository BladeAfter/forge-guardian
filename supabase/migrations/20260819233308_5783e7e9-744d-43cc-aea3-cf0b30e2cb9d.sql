CREATE OR REPLACE FUNCTION public.admin_veteran_v2_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.veteran_vault_v2_config; p public.veteran_myth_pools; v_recent jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  c := public.veteran_v2_settings();
  SELECT * INTO p FROM public.veteran_myth_pools WHERE id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'player', g.username, 'telegramId', v.telegram_id, 'priceTon', v.price_ton,
      'method', v.payment_method, 'status', v.status, 'myth', v.myth_reward_snapshot,
      'createdAt', v.created_at) ORDER BY v.created_at DESC), '[]'::jsonb) INTO v_recent
    FROM (SELECT * FROM public.veteran_vault_v2_purchases ORDER BY created_at DESC LIMIT 10) v
    LEFT JOIN public.game_players g ON g.id = v.user_id;

  RETURN jsonb_build_object(
    'enabled', c.enabled, 'salesPaused', c.sales_paused, 'packageVersion', c.package_version,
    'priceTon', c.price_ton, 'popupEnabled', c.popup_enabled, 'popupFrequency', c.popup_frequency,
    'boostPercent', c.boost_percent, 'heroDailyMyth', c.hero_daily_myth, 'petDailyMyth', c.pet_daily_myth,
    'dragonDailyMyth', c.dragon_daily_myth, 'mythReward', c.myth_reward, 'legendaryChests', c.legendary_chests,
    'fragments', c.fragments, 'weapons', c.weapons_per_purchase, 'mythReferenceRate', c.myth_reference_rate,
    'rewardVersion', c.reward_configuration_version,
    'pool', jsonb_build_object(
      'rewardFunded', COALESCE(p.reward_funded,0), 'rewardDistributed', COALESCE(p.reward_distributed,0),
      'rewardAvailable', COALESCE(p.reward_funded,0) - COALESCE(p.reward_distributed,0),
      'miningFunded', COALESCE(p.mining_funded,0), 'miningDistributed', COALESCE(p.mining_distributed,0),
      'miningAvailable', COALESCE(p.mining_funded,0) - COALESCE(p.mining_distributed,0)),
    'sold', (SELECT count(*) FROM public.veteran_vault_v2_purchases WHERE status IN ('paid','delivered')),
    'pending', (SELECT count(*) FROM public.veteran_vault_v2_purchases WHERE status = 'pending' AND expires_at > now()),
    'tonRaised', (SELECT COALESCE(sum(price_ton),0) FROM public.veteran_vault_v2_purchases WHERE status IN ('paid','delivered')),
    'templates', jsonb_build_object(
      'heroes', (SELECT count(*) FROM public.hero_catalog WHERE veteran_line AND enabled),
      'pets', (SELECT count(*) FROM public.pets WHERE veteran_line AND COALESCE(veteran_role,'pet')='pet'),
      'dragons', (SELECT count(*) FROM public.pets WHERE veteran_line AND veteran_role='dragon'),
      'eggs', (SELECT count(*) FROM public.pet_eggs WHERE veteran_line),
      'weapons', (SELECT count(*) FROM public.equipment_templates WHERE veteran_line AND is_active)),
    'recent', v_recent);
END $$;

CREATE OR REPLACE FUNCTION public.admin_veteran_v2_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_num numeric; v_bool boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM public.veteran_v2_settings();
  v_num := NULLIF(btrim(COALESCE(p_value,'')), '')::numeric;
  v_bool := lower(COALESCE(p_value,'')) IN ('1','true','on','yes');

  IF p_field = 'enabled' THEN UPDATE public.veteran_vault_v2_config SET enabled = v_bool, updated_at = now() WHERE id;
  ELSIF p_field = 'paused' THEN UPDATE public.veteran_vault_v2_config SET sales_paused = v_bool, updated_at = now() WHERE id;
  ELSIF p_field = 'popup' THEN UPDATE public.veteran_vault_v2_config SET popup_enabled = v_bool, updated_at = now() WHERE id;
  ELSIF p_field = 'frequency' THEN
    IF upper(p_value) NOT IN ('ONCE_PER_SESSION','ONCE_PER_DAY','UNTIL_PURCHASED','DISABLED') THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    UPDATE public.veteran_vault_v2_config SET popup_frequency = upper(p_value), updated_at = now() WHERE id;
  ELSIF p_field = 'version' THEN
    IF btrim(COALESCE(p_value,'')) = '' THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    UPDATE public.veteran_vault_v2_config SET package_version = btrim(p_value), updated_at = now() WHERE id;
  ELSIF p_field = 'price' THEN UPDATE public.veteran_vault_v2_config SET price_ton = GREATEST(0, v_num), updated_at = now() WHERE id;
  ELSIF p_field = 'boost' THEN UPDATE public.veteran_vault_v2_config SET boost_percent = GREATEST(0, v_num), updated_at = now() WHERE id;
  ELSIF p_field = 'heromyth' THEN UPDATE public.veteran_vault_v2_config SET hero_daily_myth = GREATEST(0, v_num), updated_at = now() WHERE id;
  ELSIF p_field = 'petmyth' THEN UPDATE public.veteran_vault_v2_config SET pet_daily_myth = GREATEST(0, v_num), updated_at = now() WHERE id;
  ELSIF p_field = 'dragonmyth' THEN UPDATE public.veteran_vault_v2_config SET dragon_daily_myth = GREATEST(0, v_num), updated_at = now() WHERE id;
  ELSIF p_field = 'myth' THEN UPDATE public.veteran_vault_v2_config SET myth_reward = GREATEST(0, v_num), updated_at = now() WHERE id;
  ELSIF p_field = 'chests' THEN UPDATE public.veteran_vault_v2_config SET legendary_chests = GREATEST(0, v_num)::int, updated_at = now() WHERE id;
  ELSIF p_field = 'fragments' THEN UPDATE public.veteran_vault_v2_config SET fragments = GREATEST(0, v_num)::int, updated_at = now() WHERE id;
  ELSIF p_field = 'weapons' THEN UPDATE public.veteran_vault_v2_config SET weapons_per_purchase = GREATEST(1, v_num)::int, updated_at = now() WHERE id;
  ELSIF p_field = 'reference' THEN UPDATE public.veteran_vault_v2_config SET myth_reference_rate = GREATEST(0, v_num), updated_at = now() WHERE id;
  ELSE RAISE EXCEPTION 'INVALID_FIELD'; END IF;

  UPDATE public.veteran_vault_v2_config
     SET reward_configuration_version = reward_configuration_version + 1, updated_at = now()
   WHERE id AND p_field IN ('myth','chests','fragments','weapons','heromyth','petmyth','dragonmyth','boost');

  PERFORM public.admin_log(p_admin_id, 'veteran_v2_set', p_field, COALESCE(p_value,''));
  RETURN public.admin_veteran_v2_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_veteran_v2_fund(p_admin_id bigint, p_pool text, p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p public.veteran_myth_pools;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_amount IS NULL OR p_amount = 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
  PERFORM public.veteran_v2_settings();
  SELECT * INTO p FROM public.veteran_myth_pools WHERE id FOR UPDATE;
  IF lower(COALESCE(p_pool,'reward')) = 'mining' THEN
    IF COALESCE(p.mining_funded,0) + p_amount < COALESCE(p.mining_distributed,0) THEN RAISE EXCEPTION 'VETERAN_POOL_RESERVED_LOCKED'; END IF;
    UPDATE public.veteran_myth_pools SET mining_funded = mining_funded + p_amount, updated_at = now() WHERE id;
  ELSE
    IF COALESCE(p.reward_funded,0) + p_amount < COALESCE(p.reward_distributed,0) THEN RAISE EXCEPTION 'VETERAN_POOL_RESERVED_LOCKED'; END IF;
    UPDATE public.veteran_myth_pools SET reward_funded = reward_funded + p_amount, updated_at = now() WHERE id;
  END IF;
  INSERT INTO public.veteran_vault_v2_ledger(kind, myth_amount, note)
    VALUES ('pool_funding', p_amount, 'admin funding: ' || lower(COALESCE(p_pool,'reward')));
  PERFORM public.admin_log(p_admin_id, 'veteran_v2_fund', lower(COALESCE(p_pool,'reward')), p_amount::text);
  RETURN public.admin_veteran_v2_overview(p_admin_id);
END $$;

REVOKE ALL ON FUNCTION public.admin_veteran_v2_overview(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_veteran_v2_set(bigint, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_veteran_v2_fund(bigint, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_veteran_v2_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_veteran_v2_set(bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_veteran_v2_fund(bigint, text, numeric) TO service_role;