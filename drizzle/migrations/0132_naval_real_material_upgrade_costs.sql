ALTER TABLE public.naval_upgrade_config ADD COLUMN nails_base integer NOT NULL DEFAULT 12 CHECK (nails_base>0), ADD COLUMN rope_base integer NOT NULL DEFAULT 8 CHECK (rope_base>0);
COMMENT ON COLUMN public.naval_upgrade_config.iron_base IS 'DEPRECATED for fleet upgrades: replaced by nails_base and rope_base; retained for legacy schema compatibility.';
CREATE OR REPLACE FUNCTION public.naval_upgrade_material_costs(p_category text, p_level integer) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT jsonb_build_object('magic_wood',ceil(wood_base*power(growth,p_level-1)), 'nails',ceil(nails_base*power(growth,p_level-1)), 'rope',ceil(rope_base*power(growth,p_level-1))) FROM public.naval_upgrade_config WHERE category=p_category AND p_level BETWEEN 1 AND max_level
$$;
REVOKE ALL ON FUNCTION public.naval_upgrade_material_costs(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_upgrade_material_costs(text,integer) TO service_role;
DO $patch$
DECLARE definition text; old_block text; new_block text;
BEGIN
 definition:=pg_get_functiondef('public.naval_fleet(uuid,text,jsonb)'::regprocedure);
 old_block:=$old$    UPDATE realm_material_balances SET amount=amount-CASE WHEN material_id='magic_wood' THEN wood ELSE iron END,updated_at=now()
      WHERE user_id=p_user AND ((material_id='magic_wood' AND amount>=wood) OR (material_id='iron_ore' AND amount>=iron));
    GET DIAGNOSTICS n=ROW_COUNT; IF n<2 THEN RAISE EXCEPTION 'NAVAL_MATERIALS_REQUIRED'; END IF;$old$;
 new_block:=$new$    PERFORM 1 FROM public.realm_material_balances WHERE user_id=p_user AND material_id IN ('magic_wood','nails','rope') ORDER BY material_id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM jsonb_each_text(public.naval_upgrade_material_costs(u.category,lvl+1)) c LEFT JOIN public.realm_material_balances b ON b.user_id=p_user AND b.material_id=c.key WHERE coalesce(b.amount,0)<c.value::numeric) THEN RAISE EXCEPTION 'NAVAL_MATERIALS_REQUIRED'; END IF;
    PERFORM public.realm_material_add(p_user,c.key,-c.value::numeric,'naval_upgrade',cls||':'||u.category||':'||(lvl+1)::text) FROM jsonb_each_text(public.naval_upgrade_material_costs(u.category,lvl+1)) c ORDER BY c.key;$new$;
 IF position(old_block in definition)=0 THEN RAISE EXCEPTION 'FLEET_UPGRADE_PATCH_MISMATCH'; END IF;
 EXECUTE replace(definition,old_block,new_block);
 definition:=pg_get_functiondef('public.naval_fleet_view(uuid)'::regprocedure);
 old_block:=$old$'growth',growth)$old$;
 new_block:=$new$'growth',growth,'materialCosts',(SELECT jsonb_object_agg(l::text,public.naval_upgrade_material_costs(category,l)) FROM generate_series(1,max_level) l))$new$;
 IF position(old_block in definition)=0 THEN RAISE EXCEPTION 'FLEET_VIEW_PATCH_MISMATCH'; END IF;
 EXECUTE replace(definition,old_block,new_block);
END $patch$;
REVOKE ALL ON FUNCTION public.naval_fleet(uuid,text,jsonb),public.naval_fleet_view(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_fleet(uuid,text,jsonb),public.naval_fleet_view(uuid) TO service_role;