CREATE OR REPLACE FUNCTION public.admin_hero_mining_set_currency(p_admin_id bigint, p_currency text, p_daily numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_new text := lower(btrim(COALESCE(p_currency,''))); s hero_mining_settings%rowtype;
        v_old_currency text; v_old_daily numeric; v_new_daily numeric; v_settle jsonb;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF v_new NOT IN ('ton','myth') THEN RAISE EXCEPTION 'INVALID_CURRENCY'; END IF;

  SELECT * INTO s FROM hero_mining_settings WHERE id FOR UPDATE;
  v_old_currency := COALESCE(s.mining_currency, 'ton');
  v_old_daily := CASE WHEN v_old_currency = 'myth' THEN COALESCE(s.myth_per_day,0)
                      ELSE COALESCE((SELECT ton_per_day FROM hero_mining_rates WHERE rarity = 'legendary'), 0) END;

  v_settle := hero_mining_settle_all();

  IF p_daily IS NOT NULL THEN
    IF p_daily < 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
    IF v_new = 'myth' THEN
      UPDATE hero_mining_settings SET myth_per_day = round(p_daily, 9) WHERE id;
    ELSE
      UPDATE hero_mining_rates SET ton_per_day = round(p_daily, 9), updated_at = now()
       WHERE rarity IN ('rare','epic','legendary','mythic','ancestral');
    END IF;
  END IF;

  UPDATE hero_mining_settings
     SET mining_currency = v_new, currency_changed_at = now(), updated_at = now()
   WHERE id;

  SELECT * INTO s FROM hero_mining_settings WHERE id;
  v_new_daily := CASE WHEN v_new = 'myth' THEN COALESCE(s.myth_per_day,0)
                      ELSE COALESCE((SELECT ton_per_day FROM hero_mining_rates WHERE rarity = 'legendary'), 0) END;

  INSERT INTO nft_mining_ledger (entry_type, currency, amount, admin_telegram_id, meta)
  VALUES ('NFT_MINING_CURRENCY_CHANGED', 'none', 0, p_admin_id,
    jsonb_build_object('previousCurrency', v_old_currency, 'newCurrency', v_new,
      'oldDailyValue', v_old_daily, 'newDailyValue', v_new_daily, 'changedAt', now(), 'settle', v_settle));

  PERFORM admin_log(p_admin_id, 'hero_mining_set_currency', 'hero_mining', 'settings',
    jsonb_build_object('currency', v_old_currency, 'dailyValue', v_old_daily),
    jsonb_build_object('currency', v_new, 'dailyValue', v_new_daily),
    'moeda da mineração de NFT alterada pelo painel admin', '{}'::jsonb);

  RETURN admin_hero_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_set_myth_rate(p_admin_id bigint, p_myth_per_day numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_old numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_myth_per_day IS NULL OR p_myth_per_day < 0 OR p_myth_per_day > 1000000 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT COALESCE(myth_per_day,0) INTO v_old FROM hero_mining_settings WHERE id FOR UPDATE;
  PERFORM hero_mining_settle_all();
  UPDATE hero_mining_settings SET myth_per_day = round(p_myth_per_day, 9), updated_at = now() WHERE id;
  PERFORM admin_log(p_admin_id, 'hero_mining_set_myth_rate', 'hero_mining', 'settings',
    jsonb_build_object('mythPerDay', v_old), jsonb_build_object('mythPerDay', round(p_myth_per_day,9)),
    'valor diário de mineração em MYTH alterado', '{}'::jsonb);
  RETURN admin_hero_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_set_min_claim_myth(p_admin_id bigint, p_min_myth numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_min_myth IS NULL OR p_min_myth < 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  UPDATE hero_mining_settings SET min_claim_myth = round(p_min_myth, 9), updated_at = now() WHERE id;
  PERFORM admin_log(p_admin_id, 'hero_mining_set_min_claim_myth', 'hero_mining', 'settings', NULL,
    jsonb_build_object('minClaimMyth', round(p_min_myth,9)), 'mínimo de claim em MYTH alterado', '{}'::jsonb);
  RETURN admin_hero_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_mining_pool_set(p_admin_id bigint, p_allocated numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_supply numeric; v_old numeric; v_distributed numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_allocated IS NULL OR p_allocated < 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT COALESCE(total_supply, 0) INTO v_supply FROM myth_token_settings WHERE id;
  IF p_allocated > v_supply THEN RAISE EXCEPTION 'ABOVE_TOTAL_SUPPLY'; END IF;
  SELECT allocated_myth, distributed_myth INTO v_old, v_distributed FROM myth_mining_pool WHERE id FOR UPDATE;
  IF p_allocated < COALESCE(v_distributed, 0) THEN RAISE EXCEPTION 'BELOW_DISTRIBUTED'; END IF;
  UPDATE myth_mining_pool SET allocated_myth = round(p_allocated, 9), updated_at = now() WHERE id;
  PERFORM admin_log(p_admin_id, 'myth_mining_pool_set', 'hero_mining', 'myth_pool',
    jsonb_build_object('allocated', v_old), jsonb_build_object('allocated', round(p_allocated,9)),
    'pool de mineração MYTH ajustada', '{}'::jsonb);
  RETURN admin_hero_mining_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_mining_pool(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p myth_mining_pool%rowtype;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO p FROM myth_mining_pool WHERE id;
  RETURN jsonb_build_object(
    'allocated', COALESCE(p.allocated_myth,0),
    'distributed', COALESCE(p.distributed_myth,0),
    'available', myth_mining_pool_available(),
    'pendingUnclaimed', (SELECT COALESCE(SUM(hero_mining_unclaimed_myth),0) FROM game_players),
    'lifetimeMyth', (SELECT COALESCE(SUM(hero_mining_lifetime_myth),0) FROM game_players),
    'totalSupply', (SELECT COALESCE(total_supply,0) FROM myth_token_settings WHERE id),
    'updatedAt', p.updated_at);
END $$;

CREATE OR REPLACE FUNCTION public.admin_nft_mining_history(p_admin_id bigint, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  RETURN jsonb_build_object('entries', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('entryType', l.entry_type, 'currency', l.currency, 'amount', l.amount,
        'telegramId', g.telegram_id, 'createdAt', l.created_at, 'meta', l.meta) ORDER BY l.created_at DESC)
      FROM (SELECT * FROM nft_mining_ledger ORDER BY created_at DESC LIMIT GREATEST(COALESCE(p_limit,15),1)) l
      LEFT JOIN game_players g ON g.id = l.user_id), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s hero_mining_settings%rowtype; v_currency text;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  v_currency := COALESCE(s.mining_currency, 'ton');
  RETURN jsonb_build_object(
    'enabled', COALESCE(s.enabled, true),
    'currency', v_currency,
    'mythPerDay', COALESCE(s.myth_per_day, 0),
    'minClaimMyth', COALESCE(s.min_claim_myth, 0),
    'currencyChangedAt', s.currency_changed_at,
    'minClaimTon', COALESCE(s.min_claim_ton, 0),
    'updatedAt', s.updated_at,
    'mythPool', jsonb_build_object(
      'allocated', (SELECT COALESCE(allocated_myth,0) FROM myth_mining_pool WHERE id),
      'distributed', (SELECT COALESCE(distributed_myth,0) FROM myth_mining_pool WHERE id),
      'available', myth_mining_pool_available()),
    'unclaimedMyth', (SELECT COALESCE(SUM(hero_mining_unclaimed_myth), 0) FROM game_players),
    'claimedMyth', (SELECT COALESCE(SUM(amount_myth), 0) FROM hero_mining_claims),
    'rates', COALESCE((SELECT jsonb_agg(jsonb_build_object('rarity', rarity, 'tonPerDay', ton_per_day) ORDER BY ton_per_day) FROM hero_mining_rates), '[]'::jsonb),
    'eligibleHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false) AND hero_mining_rate(h.rarity) > 0),
    'pausedHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE COALESCE(h.market_locked, false) AND hero_mining_rate(h.rarity) > 0),
    'networkDailyTon', (SELECT COALESCE(SUM(hero_mining_rate(h.rarity)), 0) FROM player_heroes h WHERE NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false)),
    'unclaimedTon', (SELECT COALESCE(SUM(hero_mining_unclaimed_ton), 0) FROM game_players),
    'claimedTon', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_claims),
    'claimedTon24h', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_claims WHERE created_at > now() - interval '24 hours'),
    'investedTon', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_investments),
    'returnedTon', (SELECT COALESCE(SUM(hero_mining_returned_ton), 0) FROM game_players),
    'investorsCount', (SELECT COUNT(DISTINCT user_id) FROM hero_mining_investments),
    'capReachedPlayers', (SELECT COUNT(*) FROM game_players WHERE COALESCE(hero_mining_invested_ton, 0) > 0
        AND COALESCE(hero_mining_returned_ton, 0) >= COALESCE(hero_mining_invested_ton, 0)),
    'claims', (SELECT COALESCE(jsonb_agg(jsonb_build_object('amountTon', c.amount_ton, 'amountMyth', COALESCE(c.amount_myth,0),
        'currency', COALESCE(c.currency,'ton'), 'heroCount', c.hero_count,
        'createdAt', c.created_at, 'telegramId', g.telegram_id, 'name', COALESCE(g.display_name, g.first_name)) ORDER BY c.created_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM hero_mining_claims ORDER BY created_at DESC LIMIT 10) c
      LEFT JOIN game_players g ON g.id = c.user_id)
  );
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'hero_mining_settings') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.hero_mining_settings;
  END IF;
END $$;
ALTER TABLE public.hero_mining_settings REPLICA IDENTITY FULL;