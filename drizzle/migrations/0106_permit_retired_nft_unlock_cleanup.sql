CREATE OR REPLACE FUNCTION public.reject_retired_nft_asset() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE blocked boolean:=false;
BEGIN
IF TG_OP='UPDATE' AND TG_TABLE_NAME IN ('player_pets','player_heroes','player_equipment') AND (to_jsonb(NEW)-ARRAY['market_locked','updated_at','mining_last_at','tradable']) = (to_jsonb(OLD)-ARRAY['market_locked','updated_at','mining_last_at','tradable']) AND COALESCE((to_jsonb(NEW)->>'market_locked')::boolean,false)=false THEN RETURN NEW; END IF;
IF TG_TABLE_NAME IN ('nft_pets','nft_heroes','nft_equipment','sub_nfts') THEN blocked:=true;
ELSIF TG_TABLE_NAME='player_pets' THEN blocked:=NEW.nft_pet_id IS NOT NULL OR NEW.sub_nft_id IS NOT NULL OR EXISTS(SELECT 1 FROM pets WHERE id=NEW.pet_id AND is_nft_exclusive);
ELSIF TG_TABLE_NAME='player_heroes' THEN blocked:=COALESCE(NEW.is_nft_exclusive,false) OR NEW.nft_hero_id IS NOT NULL OR EXISTS(SELECT 1 FROM hero_catalog WHERE hero_key=NEW.hero_key AND is_nft_exclusive);
ELSIF TG_TABLE_NAME='player_equipment' THEN blocked:=EXISTS(SELECT 1 FROM equipment_templates WHERE id=NEW.template_id AND is_nft);
END IF;
IF blocked THEN RAISE EXCEPTION 'NFT_ASSETS_RETIRED'; END IF; RETURN NEW;
END $$;