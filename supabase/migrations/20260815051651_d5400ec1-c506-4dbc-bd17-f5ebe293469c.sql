DO $$
DECLARE r jsonb;
BEGIN
  r := public.nft_refill_stock('hero', 8118569391);
  RAISE NOTICE 'hero refill: %', r;
  r := public.nft_refill_stock('pet', 8118569391);
  RAISE NOTICE 'pet refill: %', r;
END $$;