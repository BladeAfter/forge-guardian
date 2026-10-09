CREATE OR REPLACE FUNCTION public.guard_removed_creature_settings() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE tiers jsonb; r record;
BEGIN
  IF NEW.key IN ('hero_rarity_rates','hero_summon_rates','hero_summon_rates_real','hero_recruit_rarity_enabled') AND NEW.value ?| ARRAY['ancestral','nft_exclusive','celestial'] THEN RAISE EXCEPTION 'CREATURE_RARITY_REMOVED' USING ERRCODE='23514'; END IF;
  IF NEW.key='hero_rarity_fusion_config' THEN
    tiers := coalesce(NEW.value->'tiers','{}'::jsonb);
    FOR r IN SELECT key,value FROM jsonb_each(tiers) LOOP
      IF r.key IN ('ancestral','nft_exclusive','celestial') OR r.value->>'target' IN ('ancestral','nft_exclusive','celestial') THEN RAISE EXCEPTION 'CREATURE_RARITY_REMOVED' USING ERRCODE='23514'; END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.guard_removed_creature_settings() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.guard_removed_creature_settings() TO service_role;
CREATE TRIGGER guard_removed_creature_settings BEFORE INSERT OR UPDATE ON public.game_settings FOR EACH ROW EXECUTE FUNCTION public.guard_removed_creature_settings();
CREATE TRIGGER block_removed_rarity BEFORE INSERT OR UPDATE ON public.reward_pet_pool FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rarity();
CREATE TRIGGER block_removed_rarity BEFORE INSERT OR UPDATE ON public.pet_rarity_config FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rarity();
CREATE TRIGGER block_removed_rarity BEFORE INSERT OR UPDATE ON public.hero_mining_rates FOR EACH ROW EXECUTE FUNCTION public.reject_removed_creature_rarity();