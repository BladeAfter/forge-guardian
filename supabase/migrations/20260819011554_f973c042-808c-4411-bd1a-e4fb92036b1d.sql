UPDATE public.player_heroes h
SET mining_daily_myth = 1500, updated_at = now()
FROM (SELECT h2.id FROM public.player_heroes h2
      LEFT JOIN public.nft_heroes n ON n.id = h2.nft_hero_id
      WHERE (h2.is_nft_exclusive OR lower(h2.rarity) = 'nft_exclusive')
        AND COALESCE(h2.mining_daily_myth,0) = 0
        AND COALESCE(n.mining_daily_ton,0) = 0) t
WHERE h.id = t.id;

UPDATE public.player_pets p
SET mining_daily_myth = 1500, updated_at = now()
FROM (SELECT p2.id FROM public.player_pets p2
      LEFT JOIN public.nft_pets n ON n.id = p2.nft_pet_id
      WHERE (lower(p2.rarity) = 'nft_exclusive' OR p2.pass_exclusive)
        AND COALESCE(p2.mining_daily_myth,0) = 0
        AND COALESCE(n.daily_yield_ton,0) = 0) t
WHERE p.id = t.id;