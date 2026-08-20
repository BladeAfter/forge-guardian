REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_start_purchase(bigint, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_state(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.veteran_v2_settings() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.veteran_v2_deliver(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.veteran_v2_start_purchase(bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.veteran_v2_state(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.veteran_v2_settings() TO service_role;