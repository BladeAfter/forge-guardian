REVOKE ALL ON FUNCTION public.trg_myth_sale_milestones() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_myth_sale_milestones() FROM anon;
REVOKE ALL ON FUNCTION public.trg_myth_sale_milestones() FROM authenticated;
REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM authenticated;