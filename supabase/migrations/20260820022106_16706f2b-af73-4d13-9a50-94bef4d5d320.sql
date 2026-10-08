REVOKE ALL ON FUNCTION public.founder_pack_settings() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.founder_pack_settings() TO service_role;