CREATE OR REPLACE FUNCTION public.ton_mining_gate_enabled()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT pass_gate_enabled AND COALESCE(premium_gate_enabled, false)
    AND now() >= COALESCE(premium_rule_start_at, now())
    FROM hero_mining_settings WHERE id), false);
$function$;

GRANT EXECUTE ON FUNCTION public.ton_mining_gate_enabled() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ton_mining_gate_enabled() TO anon;
GRANT EXECUTE ON FUNCTION public.ton_mining_gate_enabled() TO service_role;