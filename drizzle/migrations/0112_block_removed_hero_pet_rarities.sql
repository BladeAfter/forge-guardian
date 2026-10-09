CREATE OR REPLACE FUNCTION public.reject_removed_creature_rarity() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE row_data jsonb := to_jsonb(NEW); r text := lower(trim(coalesce(row_data->>'rarity','')));
BEGIN
  IF r IN ('ancestral','nft_exclusive','celestial','nft exclusivo','nft exclusive','ancestral celestial') OR coalesce((row_data->>'is_nft_exclusive')::boolean,false) THEN
    RAISE EXCEPTION 'CREATURE_RARITY_REMOVED' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.reject_removed_creature_rarity() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reject_removed_creature_rarity() TO service_role;
CREATE TRIGGER block_removed_rarity BEFORE INSERT OR UPDATE ON public.hero_catalog FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rarity();
CREATE TRIGGER block_removed_rarity BEFORE INSERT OR UPDATE ON public.player_heroes FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rarity();
CREATE TRIGGER block_removed_rarity BEFORE INSERT OR UPDATE ON public.pets FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rarity();
CREATE TRIGGER block_removed_rarity BEFORE INSERT OR UPDATE ON public.player_pets FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rarity();
CREATE OR REPLACE FUNCTION public.reject_removed_creature_rates() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF coalesce(NEW.rarity_rates,'{}'::jsonb) ?| ARRAY['ancestral','nft_exclusive','celestial'] THEN RAISE EXCEPTION 'CREATURE_RARITY_REMOVED' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.reject_removed_creature_rates() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reject_removed_creature_rates() TO service_role;
CREATE TRIGGER block_removed_rates BEFORE INSERT OR UPDATE OF rarity_rates ON public.pet_eggs FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rates();
CREATE TRIGGER block_removed_rates BEFORE INSERT OR UPDATE OF rarity_rates ON public.chest_reward_tables FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rates();
CREATE TRIGGER block_removed_rates BEFORE INSERT OR UPDATE OF rarity_rates ON public.calendar_reward_config FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rates();