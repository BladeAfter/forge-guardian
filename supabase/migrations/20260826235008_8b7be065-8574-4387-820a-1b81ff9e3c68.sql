CREATE OR REPLACE FUNCTION public.spending_track_pack_purchase()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_ref text; v_type text; v_amount numeric; v_new text; v_old text;
BEGIN
  IF TG_TABLE_NAME = 'founder_pack_purchases' THEN v_type := 'founder_pack';
  ELSIF TG_TABLE_NAME = 'veteran_vault_v2_purchases' THEN v_type := 'veteran_vault_v2';
  ELSE v_type := 'veteran_vault'; END IF;
  v_ref := v_type || ':' || NEW.id::text;
  v_amount := COALESCE(NEW.price_ton, 0);
  v_new := lower(COALESCE(NEW.status, ''));
  v_old := CASE WHEN TG_OP = 'UPDATE' THEN lower(COALESCE(OLD.status, '')) ELSE NULL END;
  IF v_new IN ('confirmed','completed','credited','delivered','activated','paid_confirmed')
     AND (TG_OP = 'INSERT' OR v_old IS DISTINCT FROM v_new) THEN
    PERFORM public.record_spending_points(NEW.user_id, v_type, v_ref, 'TON', v_amount);
  ELSIF v_new IN ('refunded','reversed','cancelled','failed')
     AND (TG_OP = 'UPDATE' AND v_old IS DISTINCT FROM v_new) THEN
    PERFORM public.record_spending_reversal(v_ref);
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS spending_track_founder_pack_trg ON public.founder_pack_purchases;
CREATE TRIGGER spending_track_founder_pack_trg
AFTER INSERT OR UPDATE ON public.founder_pack_purchases
FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();

DROP TRIGGER IF EXISTS spending_track_veteran_vault_trg ON public.veteran_vault_purchases;
CREATE TRIGGER spending_track_veteran_vault_trg
AFTER INSERT OR UPDATE ON public.veteran_vault_purchases
FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();

DROP TRIGGER IF EXISTS spending_track_veteran_vault_v2_trg ON public.veteran_vault_v2_purchases;
CREATE TRIGGER spending_track_veteran_vault_v2_trg
AFTER INSERT OR UPDATE ON public.veteran_vault_v2_purchases
FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();