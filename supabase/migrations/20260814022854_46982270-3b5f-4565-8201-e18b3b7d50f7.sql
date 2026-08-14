-- Central entry point for any eligible purchase (FC or TON).
CREATE OR REPLACE FUNCTION public.register_spending_event_purchase(
  p_user_id uuid, p_source_type text, p_source_transaction_id text,
  p_currency text, p_amount numeric)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.record_spending_points(p_user_id, p_source_type, p_source_transaction_id, p_currency, p_amount)
$$;

-- Retroactive, idempotent backfill of confirmed NFT pet/hero purchases.
CREATE OR REPLACE FUNCTION public.spending_event_backfill_nft_purchases()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r record; v_rate numeric; v_points numeric; v_added integer := 0; v_touched uuid[] := '{}';
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('spending_backfill_nft', 91));

  FOR r IN
    WITH orders AS (
      SELECT 'nft_order:' || id::text AS ref, 'nft_pet_purchase' AS source_type,
             user_id, round(COALESCE(price_ton, 0), 9) AS amount, created_at
        FROM nft_pet_orders
       WHERE lower(COALESCE(status, '')) IN ('confirmed','completed','delivered','paid_confirmed','paid')
      UNION ALL
      SELECT 'nft_hero_order:' || id::text, 'nft_hero_purchase',
             user_id, round(COALESCE(price_ton, 0), 9), created_at
        FROM nft_hero_orders
       WHERE lower(COALESCE(status, '')) IN ('confirmed','completed','delivered','paid_confirmed','paid')
    )
    SELECT o.*, ev.id AS event_id, ev.ton_rate_fc
      FROM orders o
      JOIN spending_events ev
        ON o.created_at >= ev.starts_at AND o.created_at < ev.ends_at
     WHERE o.user_id IS NOT NULL AND o.amount > 0
       AND NOT EXISTS (
         SELECT 1 FROM spending_event_entries e
          WHERE e.event_id = ev.id AND e.source_transaction_id = o.ref)
  LOOP
    v_rate := GREATEST(1, COALESCE(r.ton_rate_fc, public.spending_ton_rate_fc()));
    v_points := round(r.amount * v_rate);
    IF v_points <= 0 THEN CONTINUE; END IF;

    INSERT INTO spending_event_entries(event_id, user_id, source_transaction_id, source_type,
      currency, original_amount, conversion_rate_fc, spending_points, created_at)
    VALUES (r.event_id, r.user_id, r.ref, r.source_type, 'TON', r.amount, v_rate, v_points, r.created_at)
    ON CONFLICT (event_id, source_transaction_id) DO NOTHING;

    IF FOUND THEN
      v_added := v_added + 1;
      IF NOT (r.event_id = ANY(v_touched)) THEN v_touched := v_touched || r.event_id; END IF;
    END IF;
  END LOOP;

  FOREACH r IN ARRAY '{}'::record[] LOOP END LOOP; -- no-op guard
  IF array_length(v_touched, 1) IS NOT NULL THEN
    PERFORM public.spending_event_refresh_ticker(t) FROM unnest(v_touched) AS t;
  END IF;

  RETURN jsonb_build_object('ok', true, 'entriesAdded', v_added, 'events', to_jsonb(v_touched));
END $function$;

REVOKE ALL ON FUNCTION public.register_spending_event_purchase(uuid, text, text, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.spending_event_backfill_nft_purchases() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_spending_event_purchase(uuid, text, text, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.spending_event_backfill_nft_purchases() TO service_role;

SELECT public.spending_event_backfill_nft_purchases();