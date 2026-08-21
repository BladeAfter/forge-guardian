UPDATE public.nft_breeding_settings SET sub_rate_per_ton = 0.025, updated_at = now();
UPDATE public.sub_nfts SET mining_rate_ton_day = round(mining_cap_ton / 40.0, 9) WHERE mining_cap_ton > 0;