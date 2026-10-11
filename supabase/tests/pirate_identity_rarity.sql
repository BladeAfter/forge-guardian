BEGIN;
DO $test$
DECLARE p public.player_heroes%ROWTYPE;
BEGIN
  IF (SELECT rarity FROM public.hero_catalog WHERE hero_key='mx2_gundrek') IS DISTINCT FROM 'common' THEN
    RAISE EXCEPTION 'Gundrek must remain common';
  END IF;
  IF EXISTS(SELECT 1 FROM public.hero_catalog GROUP BY image HAVING count(*)>1) THEN
    RAISE EXCEPTION 'Different pirates share artwork';
  END IF;
  SELECT * INTO p FROM public.player_heroes WHERE hero_key='mx2_gundrek' LIMIT 1;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Missing owned Gundrek fixture'; END IF;
  BEGIN
    UPDATE public.player_heroes SET rarity='uncommon' WHERE id=p.id;
    RAISE EXCEPTION 'Mismatched Gundrek rarity was accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'hero_catalog_rarity_mismatch:%' THEN RAISE; END IF;
  END;
END $test$;
ROLLBACK;