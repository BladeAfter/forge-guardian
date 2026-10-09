CREATE OR REPLACE FUNCTION public.reject_retired_nft_asset() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE blocked boolean := false;
BEGIN
 IF TG_TABLE_NAME IN ('nft_pets','nft_heroes','nft_equipment','sub_nfts') THEN blocked := true;
 ELSIF TG_TABLE_NAME = 'player_pets' THEN
  blocked := NEW.nft_pet_id IS NOT NULL OR NEW.sub_nft_id IS NOT NULL OR EXISTS(SELECT 1 FROM public.pets WHERE id=NEW.pet_id AND is_nft_exclusive);
 ELSIF TG_TABLE_NAME = 'player_heroes' THEN
  blocked := COALESCE(NEW.is_nft_exclusive,false) OR NEW.nft_hero_id IS NOT NULL OR EXISTS(SELECT 1 FROM public.hero_catalog WHERE hero_key=NEW.hero_key AND is_nft_exclusive);
 ELSIF TG_TABLE_NAME = 'player_equipment' THEN
  blocked := EXISTS(SELECT 1 FROM public.equipment_templates WHERE id=NEW.template_id AND is_nft);
 END IF;
 IF blocked THEN RAISE EXCEPTION 'NFT_ASSETS_RETIRED'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.reject_retired_nft_asset() FROM PUBLIC, anon, authenticated;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['nft_pets','nft_heroes','nft_equipment','sub_nfts','player_pets','player_heroes','player_equipment'] LOOP
  EXECUTE format('CREATE TRIGGER reject_retired_nft_asset BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.reject_retired_nft_asset()', t);
 END LOOP;
END $$;
COMMENT ON TABLE public.nft_pets IS 'DEPRECATED: NFT assets retired by owner request; creation blocked.';
COMMENT ON TABLE public.nft_heroes IS 'DEPRECATED: NFT assets retired by owner request; creation blocked.';
COMMENT ON TABLE public.nft_equipment IS 'DEPRECATED: NFT assets retired by owner request; creation blocked.';
COMMENT ON TABLE public.sub_nfts IS 'DEPRECATED: NFT assets retired by owner request; creation blocked.';
DROP POLICY IF EXISTS "own openings readable" ON public.season_mythic_egg_openings;
DROP POLICY IF EXISTS "grrd_self_read" ON public.global_roulette_reward_deliveries;
REVOKE ALL ON public.season_mythic_egg_openings, public.global_roulette_reward_deliveries FROM anon, authenticated;
GRANT ALL ON public.season_mythic_egg_openings, public.global_roulette_reward_deliveries TO service_role;
COMMENT ON TABLE public.tower_key_shop_config IS 'Public read-only shop configuration; no personal or transaction data. USING(true) is intentional for prices visible to every player.';