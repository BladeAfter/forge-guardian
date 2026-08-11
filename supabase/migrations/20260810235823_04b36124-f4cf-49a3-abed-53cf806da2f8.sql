CREATE OR REPLACE FUNCTION public.admin_player_detail(p_admin_id bigint, p_ref text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(x) INTO v FROM (
    SELECT (public.admin_player_detail_base(p_admin_id, p_ref)) AS d
  ) x;
  RETURN NULL;
END;
$fn$;

DROP FUNCTION IF EXISTS public.admin_player_detail(bigint, text);
