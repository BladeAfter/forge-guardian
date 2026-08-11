DROP FUNCTION IF EXISTS public.admin_set_pool_contribution_percent(bigint, numeric);

CREATE OR REPLACE FUNCTION public.admin_set_pool_contribution_percent(p_admin_id bigint, p_percent numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old numeric;
  v_new numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_percent IS NULL OR p_percent < 0 OR p_percent > 100 THEN
    RAISE EXCEPTION 'INVALID_POOL_PERCENT';
  END IF;

  v_new := round(p_percent::numeric, 2);

  SELECT community_pool_percent INTO v_old FROM public.pool_settings WHERE id LIMIT 1;

  IF v_old IS NULL THEN
    INSERT INTO public.pool_settings (id, community_pool_percent)
    VALUES (true, v_new)
    ON CONFLICT (id) DO UPDATE SET community_pool_percent = EXCLUDED.community_pool_percent, updated_at = now();
  ELSE
    UPDATE public.pool_settings
      SET community_pool_percent = v_new, updated_at = now()
      WHERE id;
  END IF;

  PERFORM public.admin_log(
    p_admin_id,
    'pool.contribution_percent',
    'settings',
    'community_pool_percent',
    jsonb_build_object('percent', v_old),
    jsonb_build_object('percent', v_new),
    'alteração da taxa da Community Pool (bot admin)',
    jsonb_build_object('previous', v_old, 'current', v_new, 'changed_at', now())
  );

  RETURN jsonb_build_object('previous', v_old, 'current', v_new);
END
$function$;

REVOKE ALL ON FUNCTION public.admin_set_pool_contribution_percent(bigint, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_pool_contribution_percent(bigint, numeric) TO service_role;
