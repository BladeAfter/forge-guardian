REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_settings() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.veteran_v2_deliver(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.veteran_v2_settings() TO service_role;