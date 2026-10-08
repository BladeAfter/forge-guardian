REVOKE EXECUTE ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM anon, authenticated, PUBLIC;
GRANT EXECUTE ON FUNCTION public.deliver_myth_sale_milestones(uuid) TO service_role;