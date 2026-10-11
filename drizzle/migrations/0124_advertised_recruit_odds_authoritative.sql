CREATE OR REPLACE FUNCTION public.hero_effective_real_summon_odds()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT public.hero_effective_summon_odds();
$function$;
COMMENT ON FUNCTION public.hero_effective_real_summon_odds() IS 'Recruitment uses the exact advertised effective odds; legacy hidden-rate settings are ignored. Independent rolls; no guaranteed rarity.';
REVOKE ALL ON FUNCTION public.hero_effective_real_summon_odds() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_effective_real_summon_odds() TO service_role;