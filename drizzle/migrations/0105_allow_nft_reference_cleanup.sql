DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['nft_pets','nft_heroes','nft_equipment','sub_nfts'] LOOP
 EXECUTE format('DROP TRIGGER reject_retired_nft_asset ON public.%I',t);
 EXECUTE format('CREATE TRIGGER reject_retired_nft_asset BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.reject_retired_nft_asset()',t);
 END LOOP;
END $$;