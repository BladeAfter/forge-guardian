CREATE OR REPLACE FUNCTION public.enforce_pirate_catalog_rarity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE canonical public.hero_catalog%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.hero_key IS NOT DISTINCT FROM OLD.hero_key
    AND NEW.hero_template_id IS NOT DISTINCT FROM OLD.hero_template_id
    AND NEW.rarity IS NOT DISTINCT FROM OLD.rarity THEN RETURN NEW; END IF;
  SELECT * INTO canonical FROM public.hero_catalog
    WHERE hero_key = COALESCE(NULLIF(NEW.hero_template_id, ''), NEW.hero_key);
  IF FOUND AND lower(NEW.rarity) IS DISTINCT FROM lower(canonical.rarity) THEN
    RAISE EXCEPTION 'hero_catalog_rarity_mismatch:%', canonical.hero_key USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.enforce_pirate_catalog_rarity() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_pirate_catalog_rarity() TO service_role;
CREATE TRIGGER a_pirate_catalog_rarity BEFORE INSERT OR UPDATE OF hero_key, hero_template_id, rarity
ON public.player_heroes FOR EACH ROW EXECUTE FUNCTION public.enforce_pirate_catalog_rarity();