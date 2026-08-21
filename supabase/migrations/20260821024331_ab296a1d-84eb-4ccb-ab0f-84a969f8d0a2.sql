-- Player spending amounts must never be readable by unauthenticated clients.
-- The game reads this ranking through the game-api edge function (service role),
-- and the UI already falls back to a 25s refetch, so no client feature depends on it.
DROP POLICY IF EXISTS "Spending event ranking is public" ON public.spending_event_scores;
REVOKE ALL ON public.spending_event_scores FROM anon, authenticated;
GRANT ALL ON public.spending_event_scores TO service_role;

-- Internal economy tuning (reward tables / difficulty scaling) is server-side only.
DROP POLICY IF EXISTS "clan boss config is public read" ON public.clan_boss_config;
REVOKE ALL ON public.clan_boss_config FROM anon, authenticated;
GRANT ALL ON public.clan_boss_config TO service_role;

-- Realtime-published financial tables: keep default-deny (RLS on, no permissive
-- SELECT policy) and make sure no client role holds table privileges.
ALTER TABLE public.myth_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.myth_burn_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.myth_sale_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.myth_staking_positions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.myth_balances, public.myth_burn_history,
  public.myth_sale_transactions, public.myth_staking_positions FROM anon, authenticated;
GRANT ALL ON public.myth_balances, public.myth_burn_history,
  public.myth_sale_transactions, public.myth_staking_positions TO service_role;

-- Milestone claims stay owner-scoped only; ensure no broader privilege exists.
ALTER TABLE public.myth_sale_milestone_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.myth_sale_milestone_claims FROM anon;

-- SECURITY DEFINER helpers that bypass RLS must not be callable from the client.
-- list_premium_titles stays public: the client reads the cosmetic title catalog directly.
REVOKE EXECUTE ON FUNCTION public.pvp_bot_set_attacker_power() FROM anon, authenticated, public;
REVOKE EXECUTE ON FUNCTION public.sub_nft_passives(uuid) FROM anon, authenticated, public;
REVOKE EXECUTE ON FUNCTION public.hero_mining_hero_dual(uuid) FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.pvp_bot_set_attacker_power() TO service_role;
GRANT EXECUTE ON FUNCTION public.sub_nft_passives(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_mining_hero_dual(uuid) TO service_role;