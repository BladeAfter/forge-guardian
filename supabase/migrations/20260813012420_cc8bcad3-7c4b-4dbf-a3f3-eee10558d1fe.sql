-- 1) No client (anon/authenticated) may execute any database function directly.
--    Every gameplay/admin operation goes through Edge Functions using the service role,
--    which validate Telegram initData / super-admin identity before touching the DB.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- 2) Explicit default-deny on the tables flagged as realtime-published.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['clan_boss_damage','clan_boss_instances','global_boss_participants',
      'market_listings','pet_egg_orders','player_season_pass','season_pass_orders','wallet_deposits'] LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- 3) Sensitive financial tables are not consumed by any client subscription: unpublish them.
ALTER PUBLICATION supabase_realtime DROP TABLE public.wallet_deposits;
ALTER PUBLICATION supabase_realtime DROP TABLE public.pet_egg_orders;
ALTER PUBLICATION supabase_realtime DROP TABLE public.season_pass_orders;
ALTER PUBLICATION supabase_realtime DROP TABLE public.player_season_pass;