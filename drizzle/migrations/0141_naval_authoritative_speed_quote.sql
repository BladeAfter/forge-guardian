DO $patch$
DECLARE definition text := pg_get_functiondef('public.naval_state(uuid)'::regprocedure);
BEGIN
 IF position('''speed'',naval_stat(p_user,''spd'')' in definition)=0 THEN
  IF position('''max_hp'',naval_stat(p_user,''hp'')' in definition)=0 OR position('n.user_id,n.active_class AS class_id' in definition)=0 THEN RAISE EXCEPTION 'NAVAL_STATE_SPEED_PATCH_MISMATCH'; END IF;
  definition := replace(definition,'''max_hp'',naval_stat(p_user,''hp'')','''speed'',naval_stat(p_user,''spd''),''max_hp'',naval_stat(p_user,''hp'')');
  definition := replace(definition,'n.user_id,n.active_class AS class_id','n.user_id,public.naval_stat(n.user_id,''spd'') AS speed,n.active_class AS class_id');
  EXECUTE definition;
 END IF;
END $patch$;
REVOKE ALL ON FUNCTION public.naval_state(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_state(uuid) TO service_role;