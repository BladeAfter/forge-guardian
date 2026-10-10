ALTER TABLE public.realm_explore_runs ADD COLUMN IF NOT EXISTS treasure_map_found_at timestamptz, ADD COLUMN IF NOT EXISTS treasure_map_used_node uuid;
COMMENT ON COLUMN public.realm_explore_runs.treasure_map_found_at IS 'One guaranteed island clue map per adventure, claimed through service-only exploration choose.';
COMMENT ON COLUMN public.realm_explore_runs.treasure_map_used_node IS 'Treasure node that atomically consumed this adventure map; never reusable or transferable.';
DO $migration$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.realm_explore_apply(uuid,uuid,uuid,text)'::regprocedure) INTO definition;
  IF position('REALM_TREASURE_MAP_REQUIRED' in definition) = 0 THEN
    IF position('  v_type := node.node_type;' in definition) = 0 THEN RAISE EXCEPTION 'Unexpected explore apply definition'; END IF;
    definition := replace(definition, '  v_type := node.node_type;', '  IF node.node_type = ''treasure'' AND p_option <> ''ignore'' THEN
    IF run.treasure_map_found_at IS NULL OR run.treasure_map_used_node IS NOT NULL THEN
      RAISE EXCEPTION ''REALM_TREASURE_MAP_REQUIRED'';
    END IF;
    UPDATE public.realm_explore_runs SET treasure_map_used_node = p_node WHERE id = p_run;
  END IF;
  v_type := node.node_type;');
    EXECUTE definition;
  END IF;
  SELECT pg_get_functiondef('public.realm_explore_enter(uuid,uuid,uuid)'::regprocedure) INTO definition;
  IF position('REALM_TREASURE_MAP_REQUIRED' in definition) = 0 THEN
    IF position('  if node.node_type in' in definition) = 0 THEN RAISE EXCEPTION 'Unexpected explore enter definition'; END IF;
    definition := replace(definition, '  if node.node_type in', '  IF run.pending IS NOT NULL THEN RAISE EXCEPTION ''REALM_OPTION_UNKNOWN''; END IF;
  IF node.node_type = ''treasure'' AND run.treasure_map_found_at IS NOT NULL AND run.treasure_map_used_node IS NULL THEN
    v_log := public.realm_explore_apply(p_user, p_run, p_node, ''safe'');
    RETURN public.realm_state(p_user) || jsonb_build_object(''lastNode'', v_log);
  END IF;
  -- REALM_TREASURE_MAP_REQUIRED: without a map, only skipping is allowed.
  if node.node_type in');
    definition := replace(definition, 'when ''treasure'' then jsonb_build_array(''safe'',''force'',''ignore'')', 'when ''treasure'' then jsonb_build_array(''ignore'')');
    EXECUTE definition;
  END IF;
END $migration$;
CREATE OR REPLACE FUNCTION public.realm_explore_choose(p_user uuid, p_run uuid, p_option text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE run record; v_node uuid; v_log jsonb;
BEGIN
  SELECT * INTO run FROM public.realm_explore_runs WHERE id=p_run AND user_id=p_user AND status='running' FOR UPDATE;
  IF run IS NULL THEN RAISE EXCEPTION 'REALM_RUN_UNKNOWN'; END IF;
  IF p_option = 'collect_map' THEN
    IF run.pending IS NOT NULL THEN RAISE EXCEPTION 'REALM_OPTION_UNKNOWN'; END IF;
    IF run.treasure_map_found_at IS NULL THEN
      UPDATE public.realm_explore_runs SET treasure_map_found_at=now() WHERE id=p_run;
    END IF;
    RETURN public.realm_state(p_user);
  END IF;
  IF run.pending IS NULL THEN RAISE EXCEPTION 'REALM_RUN_UNKNOWN'; END IF;
  v_node := (run.pending->>'nodeId')::uuid;
  IF NOT (run.pending->'options' ? p_option) THEN RAISE EXCEPTION 'REALM_OPTION_UNKNOWN'; END IF;
  v_log := public.realm_explore_apply(p_user,p_run,v_node,p_option);
  RETURN public.realm_state(p_user) || jsonb_build_object('lastNode',v_log);
END $function$;
REVOKE ALL ON FUNCTION public.realm_explore_choose(uuid,uuid,text), public.realm_explore_enter(uuid,uuid,uuid), public.realm_explore_apply(uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.realm_explore_choose(uuid,uuid,text), public.realm_explore_enter(uuid,uuid,uuid), public.realm_explore_apply(uuid,uuid,uuid,text) TO service_role;
DO $migration$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.realm_explore_auto(uuid,uuid)'::regprocedure) INTO definition;
  IF position('treasure_map_found_at' in definition) = 0 THEN
    definition := replace(definition, 'when ''treasure'' then ''safe''', 'when ''treasure'' then CASE WHEN run.treasure_map_found_at IS NOT NULL AND run.treasure_map_used_node IS NULL THEN ''safe'' ELSE ''ignore'' END');
    EXECUTE definition;
  END IF;
END $migration$;