CREATE OR REPLACE FUNCTION public.admin_log(p_admin_id bigint, p_action text, p_context jsonb)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.admin_log(p_admin_id, p_action, 'system', NULL::text, NULL::jsonb, p_context, NULL::text, '{}'::jsonb);
$function$;
GRANT EXECUTE ON FUNCTION public.admin_log(bigint, text, jsonb) TO service_role;