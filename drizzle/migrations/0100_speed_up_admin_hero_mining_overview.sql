CREATE OR REPLACE FUNCTION public.admin_hero_mining_overview(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s hero_mining_settings%rowtype;
  v_currency text;
  h_eligible bigint := 0;
  h_paused bigint := 0;
  h_suspended bigint := 0;
  h_daily numeric := 0;
  p_susp bigint := 0;
  p_qual bigint := 0;
  g_unclaimed numeric := 0;
  g_unclaimed_susp numeric := 0;
  g_unclaimed_myth numeric := 0;
  g_returned numeric := 0;
  g_cap bigint := 0;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO s FROM hero_mining_settings WHERE id;
  v_currency := COALESCE(s.mining_currency, 'ton');

  -- Qualified players resolved ONCE (was a per-row EXISTS over 100k+ heroes).
  CREATE TEMP TABLE IF NOT EXISTS _hm_qual (user_id uuid PRIMARY KEY) ON COMMIT DROP;
  TRUNCATE _hm_qual;
  INSERT INTO _hm_qual (user_id)
  SELECT DISTINCT a.user_id FROM ton_mining_access a
   WHERE a.access_type <> 'LOCKED' AND a.revoked_at IS NULL AND a.user_id IS NOT NULL;

  SELECT COUNT(*) FILTER (WHERE a.access_type = 'LOCKED' OR a.revoked_at IS NOT NULL),
         COUNT(*) FILTER (WHERE a.access_type <> 'LOCKED' AND a.revoked_at IS NULL)
    INTO p_susp, p_qual
    FROM ton_mining_access a;

  SELECT
    COUNT(*) FILTER (WHERE q.user_id IS NOT NULL AND r.ton_per_day > 0
                       AND NOT COALESCE(h.market_locked,false) AND NOT COALESCE(h.is_nft_exclusive,false)),
    COUNT(*) FILTER (WHERE q.user_id IS NOT NULL AND r.ton_per_day > 0 AND COALESCE(h.market_locked,false)),
    COUNT(*) FILTER (WHERE q.user_id IS NULL AND r.ton_per_day > 0),
    COALESCE(SUM(COALESCE(r.ton_per_day,0)) FILTER (WHERE q.user_id IS NOT NULL
                       AND NOT COALESCE(h.market_locked,false) AND NOT COALESCE(h.is_nft_exclusive,false)), 0)
    INTO h_eligible, h_paused, h_suspended, h_daily
    FROM player_heroes h
    LEFT JOIN _hm_qual q ON q.user_id = h.user_id
    LEFT JOIN hero_mining_rates r
      ON r.rarity = lower(btrim(COALESCE(h.rarity,'')))
     AND hero_mining_rarity_eligible(h.rarity);

  SELECT COALESCE(SUM(g.hero_mining_unclaimed_ton) FILTER (WHERE q.user_id IS NOT NULL), 0),
         COALESCE(SUM(g.hero_mining_unclaimed_ton) FILTER (WHERE q.user_id IS NULL), 0),
         COALESCE(SUM(g.hero_mining_unclaimed_myth), 0),
         COALESCE(SUM(g.hero_mining_returned_ton), 0),
         COUNT(*) FILTER (WHERE COALESCE(g.hero_mining_invested_ton,0) > 0
                            AND COALESCE(g.hero_mining_returned_ton,0) >= COALESCE(g.hero_mining_invested_ton,0))
    INTO g_unclaimed, g_unclaimed_susp, g_unclaimed_myth, g_returned, g_cap
    FROM game_players g
    LEFT JOIN _hm_qual q ON q.user_id = g.id;

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
    'unclaimedMyth', g_unclaimed_myth,
    'claimedMyth', (SELECT COALESCE(SUM(amount_myth), 0) FROM hero_mining_claims),
    'rates', COALESCE((SELECT jsonb_agg(jsonb_build_object('rarity', rarity, 'tonPerDay', ton_per_day) ORDER BY ton_per_day) FROM hero_mining_rates), '[]'::jsonb),
    'suspendedPlayers', p_susp,
    'qualifiedPlayers', p_qual,
    'eligibleHeroes', h_eligible,
    'pausedHeroes', h_paused,
    'suspendedHeroes', h_suspended,
    'networkDailyTon', h_daily,
    'unclaimedTon', g_unclaimed,
    'suspendedUnclaimedTon', g_unclaimed_susp,
    'claimedTon', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_claims),
    'claimedTon24h', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_claims WHERE created_at > now() - interval '24 hours'),
    'investedTon', (SELECT COALESCE(SUM(amount_ton), 0) FROM hero_mining_investments),
    'returnedTon', g_returned,
    'investorsCount', (SELECT COUNT(DISTINCT user_id) FROM hero_mining_investments),
    'capReachedPlayers', g_cap,
    'claims', (SELECT COALESCE(jsonb_agg(jsonb_build_object('amountTon', c.amount_ton, 'amountMyth', COALESCE(c.amount_myth,0),
        'currency', COALESCE(c.currency,'ton'), 'heroCount', c.hero_count,
        'createdAt', c.created_at, 'telegramId', g.telegram_id, 'name', COALESCE(g.display_name, g.first_name)) ORDER BY c.created_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM hero_mining_claims ORDER BY created_at DESC LIMIT 10) c
      LEFT JOIN game_players g ON g.id = c.user_id)
  );
END
$$;

CREATE INDEX IF NOT EXISTS idx_hero_mining_claims_created_at ON public.hero_mining_claims (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ton_mining_access_user ON public.ton_mining_access (user_id);
