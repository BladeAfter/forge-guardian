-- 1) Pool de heróis dos packs não deve excluir heróis já possuídos por outros jogadores
CREATE OR REPLACE FUNCTION public.adventurer_hero_pool_size()
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT count(*)::int FROM public.hero_catalog h, public.adventurer_pack_config c
   WHERE c.id AND h.enabled
     AND lower(h.rarity) = lower(c.hero_rarity)
     AND lower(h.rarity) NOT LIKE '%celestial%'
     AND lower(h.rarity) NOT LIKE '%mythic%'
$function$;

CREATE OR REPLACE FUNCTION public.vanguard_hero_pool_size()
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT count(*)::int FROM public.hero_catalog h, public.vanguard_pack_config c
   WHERE c.id AND h.enabled
     AND lower(h.rarity) = lower(c.hero_rarity)
     AND lower(h.rarity) NOT LIKE '%celestial%'
$function$;

-- 2) Nos deliveries, preferir heróis ainda não possuídos, mas nunca bloquear a entrega
DO $patch$
DECLARE v_src text; v_new text; v_name text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['adventurer_pack_deliver','vanguard_pack_deliver'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_src
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = v_name
     LIMIT 1;
    IF v_src IS NULL THEN CONTINUE; END IF;
    v_new := replace(v_src,
      'AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key)' || chr(10) || '   ORDER BY random() LIMIT 1;',
      'ORDER BY (EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key)) ASC, random() LIMIT 1;');
    IF v_new = v_src THEN
      RAISE EXCEPTION 'PATCH_PATTERN_NOT_FOUND: %', v_name;
    END IF;
    EXECUTE v_new;
  END LOOP;
END $patch$;

-- 3) Estado do Legendary Adventurer Pack: esgotado deve considerar estoque vendido, não heróis já existentes
CREATE OR REPLACE FUNCTION public.adventurer_pack_state(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE u public.game_players; c public.adventurer_pack_config;
        v_owned public.adventurer_pack_purchases; v_pending public.adventurer_pack_purchases;
        v_heroes integer; v_sold integer; v_stock integer;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  c := public.adventurer_pack_settings();
  v_heroes := public.adventurer_hero_pool_size();
  SELECT count(*)::int INTO v_sold FROM public.adventurer_pack_purchases
   WHERE package_version = c.package_version AND status IN ('paid','delivered');
  v_stock := CASE WHEN COALESCE(c.stock_total,0) > 0
                  THEN GREATEST(COALESCE(c.stock_total,0) - COALESCE(v_sold,0), 0)
                  ELSE v_heroes END;

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
                AND v_owned.id IS NULL AND v_heroes > 0 AND v_stock > 0,
    'soldOut', COALESCE(c.enabled,false) AND (v_heroes <= 0 OR v_stock <= 0),
    'stockRemaining', v_stock,
    'stockTotal', COALESCE(c.stock_total,0),
    'sold', COALESCE(v_sold,0),
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
END $function$;