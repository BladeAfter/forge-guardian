-- NFTs que ganharam taxa em MYTH mantiveram o TON congelado, mas o acúmulo de TON
-- só ocorre quando o NFT está marcado como mineração dupla. Restaura a regra.
UPDATE public.nft_heroes
   SET mining_dual = true, updated_at = now()
 WHERE COALESCE(mining_daily_ton, 0) > 0
   AND COALESCE(mining_daily_myth, 0) > 0
   AND COALESCE(mining_dual, false) = false;