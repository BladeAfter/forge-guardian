ALTER TABLE public.player_pets DROP CONSTRAINT IF EXISTS player_pets_rarity_check;
ALTER TABLE public.player_pets ADD CONSTRAINT player_pets_rarity_check
  CHECK (rarity = ANY (ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral','exclusive','nft_exclusive','celestial']));

ALTER TABLE public.pet_hatch_history DROP CONSTRAINT IF EXISTS pet_hatch_history_result_rarity_check;
ALTER TABLE public.pet_hatch_history ADD CONSTRAINT pet_hatch_history_result_rarity_check
  CHECK (result_rarity = ANY (ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral','exclusive','nft_exclusive','celestial']));