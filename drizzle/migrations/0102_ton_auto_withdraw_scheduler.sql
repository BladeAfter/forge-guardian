-- lovable-cron-fallback-reviewed: 288 runs/day; payouts must leave within minutes of a player request and TON has no inbound webhook to trigger signing.
ALTER TABLE public.ton_auto_withdraw_settings ADD COLUMN IF NOT EXISTS worker_key text;

UPDATE public.ton_auto_withdraw_settings
   SET enabled = false, max_auto_ton = 5, min_auto_ton = 0, daily_cap_ton = 50, batch_size = 3,
       last_error = 'aguardando frase de recuperacao correta da carteira pagadora'
 WHERE id;

CREATE OR REPLACE FUNCTION public.auto_withdraw_register_worker(p_key text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE ton_auto_withdraw_settings SET worker_key = NULLIF(p_key,'') WHERE id;
$$;

CREATE OR REPLACE FUNCTION public.auto_withdraw_tick()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE s ton_auto_withdraw_settings%rowtype;
BEGIN
  SELECT * INTO s FROM ton_auto_withdraw_settings WHERE id;
  IF NOT s.enabled OR COALESCE(s.worker_key,'') = '' THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM wallet_withdrawals WHERE status = 'pending') THEN RETURN; END IF;
  PERFORM net.http_post(
    url := 'https://oaivxwzrggfqhapohlht.supabase.co/functions/v1/ton-auto-withdraw',
    headers := jsonb_build_object('Content-Type','application/json','x-auto-withdraw-secret', s.worker_key),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000);
END $$;

REVOKE ALL ON FUNCTION public.auto_withdraw_register_worker(text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_withdraw_tick() FROM anon, authenticated;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ton-auto-withdraw-tick';
SELECT cron.schedule('ton-auto-withdraw-tick', '*/5 * * * *', 'SELECT public.auto_withdraw_tick();');
