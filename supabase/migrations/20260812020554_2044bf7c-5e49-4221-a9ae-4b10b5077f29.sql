-- 1) Remove public/anon/authenticated direct read access to sensitive gameplay tables.
--    All screens already read this data through the game-api edge function (service role).

DROP POLICY IF EXISTS "clan boss damage is readable" ON public.clan_boss_damage;
DROP POLICY IF EXISTS "clan boss instances are readable" ON public.clan_boss_instances;
DROP POLICY IF EXISTS "boss ranking readable by players" ON public.global_boss_participants;
DROP POLICY IF EXISTS "Anyone can read market listings" ON public.market_listings;

REVOKE ALL ON public.clan_boss_damage FROM anon, authenticated;
REVOKE ALL ON public.clan_boss_instances FROM anon, authenticated;
REVOKE ALL ON public.global_boss_participants FROM anon, authenticated;
REVOKE ALL ON public.market_listings FROM anon, authenticated;

GRANT ALL ON public.clan_boss_damage TO service_role;
GRANT ALL ON public.clan_boss_instances TO service_role;
GRANT ALL ON public.global_boss_participants TO service_role;
GRANT ALL ON public.market_listings TO service_role;

ALTER TABLE public.clan_boss_damage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clan_boss_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.global_boss_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_listings ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['clan_boss_damage','clan_boss_instances','global_boss_participants','market_listings'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename=t AND 'service_role' = ANY(roles)
    ) THEN
      EXECUTE format('CREATE POLICY "service role manages %1$s" ON public.%1$I FOR ALL TO service_role USING (true) WITH CHECK (true)', t);
    END IF;
  END LOOP;
END $$;

-- 2) SECURITY DEFINER functions must not be callable by anon/authenticated.
REVOKE ALL ON FUNCTION public.market_block_hero_mutation() FROM anon, authenticated, PUBLIC;
REVOKE ALL ON FUNCTION public.market_block_locked_hero() FROM anon, authenticated, PUBLIC;
REVOKE ALL ON FUNCTION public.market_block_pet_mutation() FROM anon, authenticated, PUBLIC;
REVOKE ALL ON FUNCTION public.spending_track_fc_spend() FROM anon, authenticated, PUBLIC;
REVOKE ALL ON FUNCTION public.spending_track_ton_order() FROM anon, authenticated, PUBLIC;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND p.proname = 'get_community_pool_ranking_with_estimates'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, authenticated, PUBLIC', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;