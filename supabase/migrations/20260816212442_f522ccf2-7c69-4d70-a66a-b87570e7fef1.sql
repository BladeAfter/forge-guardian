CREATE OR REPLACE FUNCTION public.admin_log(p_admin_id bigint, p_action text, p_target_id text, p_context jsonb)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.admin_log(p_admin_id, p_action, 'marketing_pool', p_target_id, NULL::jsonb, p_context, NULL::text, '{}'::jsonb);
$function$;

REVOKE ALL ON FUNCTION public.admin_log(bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_log(bigint, text, text, jsonb) TO service_role;