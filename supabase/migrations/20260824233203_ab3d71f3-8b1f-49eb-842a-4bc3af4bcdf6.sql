-- 1) Purge the useless "not_found" polling noise (1.5M rows / 546 MB) written every minute.
DELETE FROM public.ton_payment_logs
 WHERE blockchain_status = 'not_found' AND fulfillment_status = 'pending';

-- 2) Hero collection: the query filters by user and orders by created_at DESC.
CREATE INDEX IF NOT EXISTS player_heroes_user_created_idx
  ON public.player_heroes (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ton_payment_logs_created_idx
  ON public.ton_payment_logs (created_at DESC);

-- 3) Housekeeping so the technical payment log can never grow unbounded again.
CREATE OR REPLACE FUNCTION public.prune_ton_payment_logs()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare n integer;
begin
  delete from public.ton_payment_logs
   where created_at < now() - interval '30 days'
      or (blockchain_status = 'not_found' and created_at < now() - interval '2 hours');
  get diagnostics n = row_count;
  return n;
end $$;

REVOKE ALL ON FUNCTION public.prune_ton_payment_logs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_ton_payment_logs() TO service_role;

SELECT cron.schedule('ton-payment-logs-prune', '17 * * * *', $$select public.prune_ton_payment_logs()$$);