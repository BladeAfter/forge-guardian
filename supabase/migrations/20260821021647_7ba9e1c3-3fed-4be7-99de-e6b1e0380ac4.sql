ALTER TABLE public.nft_heroes ALTER COLUMN mining_daily_myth SET DEFAULT 5000;

DO $$
BEGIN
  PERFORM set_config('mythreon.allow_yield_override', 'on', true);
  UPDATE public.nft_heroes SET mining_daily_myth = 5000, updated_at = now()
   WHERE COALESCE(mining_daily_myth, 0) <> 5000;
  UPDATE public.player_heroes SET mining_daily_myth = 5000, updated_at = now()
   WHERE COALESCE(is_nft_exclusive, false) AND COALESCE(mining_daily_myth, 0) <> 5000;
  INSERT INTO public.game_settings(key, value) VALUES ('nft_yield_hero_myth_all', to_jsonb(5000))
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END $$;