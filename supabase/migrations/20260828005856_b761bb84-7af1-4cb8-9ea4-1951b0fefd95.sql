CREATE OR REPLACE FUNCTION public.clan_resolve_user(p_telegram_id text)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.clan_resolve_user(NULLIF(btrim(p_telegram_id), '')::bigint)
$function$;

REVOKE ALL ON FUNCTION public.clan_resolve_user(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_resolve_user(text) TO service_role;