REVOKE ALL ON FUNCTION public.hero_real_summon_rates() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hero_effective_real_summon_odds() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_hero_real_summon_rates(bigint, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_hero_real_odds(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_real_summon_rates() TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_effective_real_summon_odds() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_hero_real_summon_rates(bigint, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_hero_real_odds(bigint) TO service_role;