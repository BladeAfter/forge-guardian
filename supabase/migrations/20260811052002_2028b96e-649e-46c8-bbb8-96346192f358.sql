-- Read-only public access so Realtime can deliver global boss changes to players.
GRANT SELECT ON public.global_boss_cycles TO anon, authenticated;
GRANT SELECT ON public.global_boss_participants TO anon, authenticated;

DROP POLICY IF EXISTS "global boss cycles are public read" ON public.global_boss_cycles;
CREATE POLICY "global boss cycles are public read"
ON public.global_boss_cycles FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "global boss ranking is public read" ON public.global_boss_participants;
CREATE POLICY "global boss ranking is public read"
ON public.global_boss_participants FOR SELECT TO anon, authenticated USING (true);

-- Full row images so Realtime filters and diffs work on UPDATE/DELETE.
ALTER TABLE public.global_boss_cycles REPLICA IDENTITY FULL;
ALTER TABLE public.global_boss_participants REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='global_boss_cycles') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.global_boss_cycles;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='global_boss_participants') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.global_boss_participants;
  END IF;
END $$;