DROP FUNCTION IF EXISTS public.market_browse(bigint, text, text, text, integer, integer);

REVOKE ALL ON FUNCTION public.market_browse(bigint, text, text, text, integer, integer, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.market_browse(bigint, text, text, text, integer, integer, text) TO service_role;