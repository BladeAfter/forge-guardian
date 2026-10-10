REVOKE ALL ON FUNCTION public.realm_explore_auto(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.realm_explore_auto(uuid,uuid) TO service_role;