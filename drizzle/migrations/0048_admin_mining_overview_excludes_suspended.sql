CREATE OR REPLACE FUNCTION public.ton_mining_qualified(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.ton_mining_access a
     WHERE a.user_id = p_user_id
       AND a.access_type <> 'LOCKED'
       AND a.revoked_at IS NULL
  );
$$;

GRANT EXECUTE ON FUNCTION public.ton_mining_qualified(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_hero_mining_overview(p_admin_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
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
    'suspendedPlayers', (SELECT COUNT(*) FROM ton_mining_access a WHERE a.access_type = 'LOCKED' OR a.revoked_at IS NOT NULL),
    'qualifiedPlayers', (SELECT COUNT(*) FROM ton_mining_access a WHERE a.access_type <> 'LOCKED' AND a.revoked_at IS NULL),
    'eligibleHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false) AND hero_mining_rate(h.rarity) > 0 AND ton_mining_qualified(h.user_id)),
    'pausedHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE COALESCE(h.market_locked, false) AND hero_mining_rate(h.rarity) > 0 AND ton_mining_qualified(h.user_id)),
    'suspendedHeroes', (SELECT COUNT(*) FROM player_heroes h WHERE hero_mining_rate(h.rarity) > 0 AND NOT ton_mining_qualified(h.user_id)),
    'networkDailyTon', (SELECT COALESCE(SUM(hero_mining_rate(h.rarity)), 0) FROM player_heroes h WHERE NOT COALESCE(h.market_locked, false) AND NOT COALESCE(h.is_nft_exclusive, false) AND ton_mining_qualified(h.user_id)),
    'unclaimedTon', (SELECT COALESCE(SUM(g.hero_mining_unclaimed_ton), 0) FROM game_players g WHERE ton_mining_qualified(g.id)),
    'suspendedUnclaimedTon', (SELECT COALESCE(SUM(g.hero_mining_unclaimed_ton), 0) FROM game_players g WHERE NOT ton_mining_qualified(g.id)),
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
END
$fn$;
