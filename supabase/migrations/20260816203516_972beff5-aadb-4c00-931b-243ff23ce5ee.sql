DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'clan_messages','game_players','player_heroes','player_pets','player_inventory',
    'clan_members','wallet_deposits','wallet_withdrawals','market_transactions','auction_bids'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated, PUBLIC', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
    EXECUTE format('DROP POLICY IF EXISTS "No direct client access" ON public.%I', t);
    EXECUTE format('CREATE POLICY "No direct client access" ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS "Pet catalog art is readable" ON storage.objects;
CREATE POLICY "Pet catalog art is readable"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'pet-images');