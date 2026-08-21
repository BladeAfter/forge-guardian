REVOKE ALL ON FUNCTION public.myth_purchase_total(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_myth_pack_milestones() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM PUBLIC, anon, authenticated;