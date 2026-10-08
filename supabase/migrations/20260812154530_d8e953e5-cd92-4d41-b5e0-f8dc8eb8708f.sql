CREATE OR REPLACE FUNCTION public.admin_reset_hero_shop(p_admin_id bigint, p_scope text DEFAULT 'prices'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_scope IN ('prices','all') THEN
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 1, 25000, 'reset_default');
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 5, 125000, 'reset_default');
    PERFORM public.admin_set_hero_recruit_price(p_admin_id, 10, 250000, 'reset_default');
  END IF;
  IF p_scope IN ('odds','all') THEN
    PERFORM public.admin_set_hero_summon_rates(
      p_admin_id,
      '{"common":61.7,"uncommon":25,"rare":10,"epic":2.7,"legendary":0.3,"mythic":0.3,"ancestral":0}'::jsonb,
      'reset_default');
  END IF;
  RETURN public.get_hero_shop_config();
END;
$function$;