DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT id FROM public.market_transactions
    WHERE status = 'review'
      AND coalesce(risk_score,0) < 60
      AND NOT (risk_flags && ARRAY['HIGH_PRICE','ITEM_RETURNED']::text[])
  LOOP
    PERFORM public.market_settle_transaction(r.id, 8118569391);
  END LOOP;
END $$;