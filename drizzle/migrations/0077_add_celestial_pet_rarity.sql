CREATE OR REPLACE FUNCTION public.normalize_pet_rarity(v text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  SELECT CASE lower(trim(coalesce(v,'common')))
    WHEN 'uncommon' THEN 'uncommon' WHEN 'incomum' THEN 'uncommon'
    WHEN 'rare' THEN 'rare' WHEN 'raro' THEN 'rare' WHEN 'rara' THEN 'rare'
    WHEN 'epic' THEN 'epic' WHEN 'epico' THEN 'epic' WHEN 'épico' THEN 'epic' WHEN 'epica' THEN 'epic' WHEN 'épica' THEN 'epic'
    WHEN 'legendary' THEN 'legendary' WHEN 'lendario' THEN 'legendary' WHEN 'lendário' THEN 'legendary' WHEN 'lendaria' THEN 'legendary' WHEN 'lendária' THEN 'legendary'
    WHEN 'mythic' THEN 'mythic' WHEN 'mitico' THEN 'mythic' WHEN 'mítico' THEN 'mythic' WHEN 'mitica' THEN 'mythic' WHEN 'mítica' THEN 'mythic'
    WHEN 'ancestral' THEN 'ancestral'
    WHEN 'exclusive' THEN 'exclusive' WHEN 'exclusivo' THEN 'exclusive' WHEN 'exclusiva' THEN 'exclusive'
    WHEN 'nft_exclusive' THEN 'nft_exclusive' WHEN 'nft-exclusive' THEN 'nft_exclusive'
    WHEN 'nft exclusive' THEN 'nft_exclusive' WHEN 'nft' THEN 'nft_exclusive'
    WHEN 'nft_exclusivo' THEN 'nft_exclusive' WHEN 'nft exclusivo' THEN 'nft_exclusive'
    WHEN 'celestial' THEN 'celestial' WHEN 'celeste' THEN 'celestial'
    ELSE 'common' END
$$;