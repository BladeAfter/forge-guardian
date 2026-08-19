CREATE OR REPLACE FUNCTION public.deliver_myth_sale_milestone_weapon(p_user uuid, p_code text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_tpl uuid;
BEGIN
  SELECT id INTO v_tpl FROM public.equipment_templates WHERE code = p_code;
  IF v_tpl IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.player_equipment WHERE user_id = p_user AND source_ref = v_tpl) THEN RETURN; END IF;
  INSERT INTO public.player_equipment(user_id, template_id, source, source_ref)
  VALUES (p_user, v_tpl, 'myth_sale_milestone', v_tpl);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.deliver_myth_sale_milestone_weapon(uuid, text) FROM anon, authenticated, PUBLIC;
GRANT EXECUTE ON FUNCTION public.deliver_myth_sale_milestone_weapon(uuid, text) TO service_role;