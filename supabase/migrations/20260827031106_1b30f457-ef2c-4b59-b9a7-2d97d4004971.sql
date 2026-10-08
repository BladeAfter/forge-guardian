REVOKE ALL ON FUNCTION public.clan_period_start(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_period_start(text) TO service_role;