CREATE OR REPLACE FUNCTION public.pvp_league(t integer)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v text;
BEGIN
  SELECT name INTO v FROM public.pvp_leagues
   WHERE enabled AND COALESCE(t,0) >= min_trophies
   ORDER BY min_trophies DESC LIMIT 1;
  RETURN COALESCE(v, 'Bronze V');
END;
$$;