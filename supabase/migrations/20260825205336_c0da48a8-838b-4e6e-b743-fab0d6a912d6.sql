-- Stop replicating sensitive game/economy tables to Realtime.
-- The client never subscribes (realtime disabled; all reads go through the game-api edge function),
-- so replication only widens the surface for these tables.
ALTER PUBLICATION supabase_realtime DROP TABLE public.market_listings;
ALTER PUBLICATION supabase_realtime DROP TABLE public.myth_balances;
ALTER PUBLICATION supabase_realtime DROP TABLE public.myth_burn_history;
ALTER PUBLICATION supabase_realtime DROP TABLE public.myth_sale_transactions;
ALTER PUBLICATION supabase_realtime DROP TABLE public.myth_staking_positions;
ALTER PUBLICATION supabase_realtime DROP TABLE public.spending_event_scores;
ALTER PUBLICATION supabase_realtime DROP TABLE public.global_boss_participants;
ALTER PUBLICATION supabase_realtime DROP TABLE public.clan_boss_instances;
ALTER PUBLICATION supabase_realtime DROP TABLE public.clan_boss_damage;

-- MYTH sale milestone claims: players have no Supabase session (Telegram initData auth),
-- so the auth.uid() policy could never match. Replace it with an explicit service-role-only
-- rule and revoke client grants so access happens only through the backend.
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='myth_sale_milestone_claims' LOOP
    EXECUTE format('DROP POLICY %I ON public.myth_sale_milestone_claims', p.policyname);
  END LOOP;
END $$;

ALTER TABLE public.myth_sale_milestone_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.myth_sale_milestone_claims FROM anon, authenticated;
GRANT ALL ON public.myth_sale_milestone_claims TO service_role;
CREATE POLICY "Service role manages milestone claims"
  ON public.myth_sale_milestone_claims FOR ALL TO service_role USING (true) WITH CHECK (true);