-- Public read of the active NFT mining currency/rate so every open client can react
-- instantly (Realtime) to an Admin Bot currency switch. Writes stay admin-only.
GRANT SELECT ON public.hero_mining_settings TO anon, authenticated;
GRANT ALL ON public.hero_mining_settings TO service_role;