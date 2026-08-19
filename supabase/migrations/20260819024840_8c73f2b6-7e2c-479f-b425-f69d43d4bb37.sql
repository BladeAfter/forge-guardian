DO $$
DECLARE v_pts numeric; v_ev uuid;
BEGIN
  SELECT id INTO v_ev FROM public.spending_events WHERE status='active' ORDER BY starts_at DESC LIMIT 1;
  PERFORM public.record_spending_points('4631f7a2-4b32-4f23-acc9-7e55d32d2300'::uuid,'fc_spend','verify:live:1','FC',1000);
  SELECT total_points INTO v_pts FROM public.spending_event_scores WHERE event_id=v_ev AND user_id='4631f7a2-4b32-4f23-acc9-7e55d32d2300';
  RAISE NOTICE 'points=%', v_pts;
  IF COALESCE(v_pts,0) <> 1000 THEN RAISE EXCEPTION 'scoring engine not live (points=%)', v_pts; END IF;
  DELETE FROM public.spending_event_entries WHERE event_id=v_ev AND source_transaction_id='verify:live:1';
  PERFORM public.spending_event_recount_user(v_ev,'4631f7a2-4b32-4f23-acc9-7e55d32d2300');
  PERFORM public.spending_event_refresh_ticker(v_ev);
END $$;