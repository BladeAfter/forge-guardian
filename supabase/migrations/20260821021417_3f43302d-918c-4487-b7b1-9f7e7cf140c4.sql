REVOKE ALL ON FUNCTION public.myth_purchase_total(uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_myth_pack_milestones() FROM anon, authenticated;
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT user_id FROM public.myth_ledger
            WHERE direction = 'credit' AND reason IN ('founder_pack','veteran_vault','veteran_vault_v2')
  LOOP
    PERFORM public.deliver_myth_sale_milestones(r.user_id);
  END LOOP;
END $$;