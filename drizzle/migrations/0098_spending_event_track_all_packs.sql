-- Every premium pack must feed the spending event, not only Founder/Veteran.
CREATE OR REPLACE FUNCTION public.spending_track_pack_purchase()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ref text; v_type text; v_amount numeric; v_new text; v_old text;
BEGIN
  v_type := CASE TG_TABLE_NAME
    WHEN 'founder_pack_purchases' THEN 'founder_pack'
    WHEN 'veteran_vault_v2_purchases' THEN 'veteran_vault_v2'
    WHEN 'veteran_vault_purchases' THEN 'veteran_vault'
    WHEN 'celestial_pack_purchases' THEN 'celestial_pack'
    WHEN 'sovereign_pack_purchases' THEN 'sovereign_pack'
    WHEN 'vanguard_pack_purchases' THEN 'vanguard_pack'
    WHEN 'adventurer_pack_purchases' THEN 'adventurer_pack'
    WHEN 'mythic_power_pack_purchases' THEN 'mythic_power_pack'
    ELSE 'veteran_vault' END;
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

DROP TRIGGER IF EXISTS spending_track_celestial_pack_trg ON public.celestial_pack_purchases;
CREATE TRIGGER spending_track_celestial_pack_trg AFTER INSERT OR UPDATE ON public.celestial_pack_purchases
  FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();

DROP TRIGGER IF EXISTS spending_track_sovereign_pack_trg ON public.sovereign_pack_purchases;
CREATE TRIGGER spending_track_sovereign_pack_trg AFTER INSERT OR UPDATE ON public.sovereign_pack_purchases
  FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();

DROP TRIGGER IF EXISTS spending_track_vanguard_pack_trg ON public.vanguard_pack_purchases;
CREATE TRIGGER spending_track_vanguard_pack_trg AFTER INSERT OR UPDATE ON public.vanguard_pack_purchases
  FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();

DROP TRIGGER IF EXISTS spending_track_adventurer_pack_trg ON public.adventurer_pack_purchases;
CREATE TRIGGER spending_track_adventurer_pack_trg AFTER INSERT OR UPDATE ON public.adventurer_pack_purchases
  FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();

DROP TRIGGER IF EXISTS spending_track_mythic_power_pack_trg ON public.mythic_power_pack_purchases;
CREATE TRIGGER spending_track_mythic_power_pack_trg AFTER INSERT OR UPDATE ON public.mythic_power_pack_purchases
  FOR EACH ROW EXECUTE FUNCTION public.spending_track_pack_purchase();