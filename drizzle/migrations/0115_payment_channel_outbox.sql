-- lovable-cron-fallback-reviewed: Event-driven enqueue wakes delivery immediately; minute retries only exist while pending/sending rows exist, and unschedule after drain. At most 1440 retries/day while blocked, zero idle polling.
CREATE TABLE public.payment_channel_outbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), kind text NOT NULL CHECK(kind IN ('deposit','withdrawal')),
 source_id uuid NOT NULL, amount_ton numeric NOT NULL, amount_fc numeric NOT NULL DEFAULT 0,
 wallet text, tx_hash text NOT NULL, occurred_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sending','sent','uncertain')),
 attempts integer NOT NULL DEFAULT 0, next_attempt_at timestamptz NOT NULL DEFAULT now(),
 claimed_at timestamptz, sent_at timestamptz, message_id bigint, last_error text,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(kind,source_id), UNIQUE(kind,tx_hash)
);
GRANT ALL ON public.payment_channel_outbox TO service_role;
ALTER TABLE public.payment_channel_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY payment_channel_server ON public.payment_channel_outbox FOR ALL TO service_role USING(true) WITH CHECK(true);
CREATE INDEX payment_channel_pending ON public.payment_channel_outbox(status,next_attempt_at);
CREATE TABLE public.payment_channel_health (id boolean PRIMARY KEY DEFAULT true CHECK(id), ready boolean NOT NULL DEFAULT false, bot_username text, detail text, checked_at timestamptz);
GRANT ALL ON public.payment_channel_health TO service_role;
ALTER TABLE public.payment_channel_health ENABLE ROW LEVEL SECURITY;
CREATE POLICY payment_channel_health_server ON public.payment_channel_health FOR ALL TO service_role USING(true) WITH CHECK(true);
CREATE OR REPLACE FUNCTION public.payment_channel_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE k text;
BEGIN
 SELECT worker_key INTO k FROM public.ton_auto_withdraw_settings WHERE id;
 IF coalesce(k,'')='' THEN RETURN; END IF;
 PERFORM net.http_post(url:='https://oaivxwzrggfqhapohlht.supabase.co/functions/v1/payment-channel', headers:=jsonb_build_object('Content-Type','application/json','x-payment-channel-secret',k),body:='{}'::jsonb,timeout_milliseconds:=120000);
END $$;
CREATE OR REPLACE FUNCTION public.payment_channel_retry() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 UPDATE payment_channel_outbox SET status='uncertain', last_error='Envio interrompido; conferir o canal antes de reenviar.' WHERE status='sending' AND claimed_at<now()-interval '10 minutes';
 IF NOT EXISTS(SELECT 1 FROM payment_channel_outbox WHERE status IN ('pending','sending')) THEN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname='mythic-seas-payment-notices';
  RETURN;
 END IF;
 IF EXISTS(SELECT 1 FROM payment_channel_outbox WHERE status='pending' AND next_attempt_at<=now()) THEN PERFORM public.payment_channel_tick(); END IF;
END $$;
CREATE OR REPLACE FUNCTION public.payment_channel_wake() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('payment-channel-schedule',0));
 IF NEW.status='pending' THEN
  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='mythic-seas-payment-notices') THEN
   PERFORM cron.schedule('mythic-seas-payment-notices','* * * * *','SELECT public.payment_channel_retry();');
  END IF;
  IF TG_OP='INSERT' THEN PERFORM public.payment_channel_tick(); END IF;
 ELSIF NOT EXISTS(SELECT 1 FROM payment_channel_outbox WHERE status IN ('pending','sending')) THEN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname='mythic-seas-payment-notices';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER payment_channel_wake AFTER INSERT OR UPDATE OF status ON public.payment_channel_outbox FOR EACH ROW EXECUTE FUNCTION public.payment_channel_wake();
CREATE OR REPLACE FUNCTION public.payment_channel_claim() RETURNS SETOF public.payment_channel_outbox LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 RETURN QUERY WITH picked AS (SELECT id FROM payment_channel_outbox WHERE status='pending' AND next_attempt_at<=now() ORDER BY created_at LIMIT 8 FOR UPDATE SKIP LOCKED)
 UPDATE payment_channel_outbox q SET status='sending',attempts=q.attempts+1,claimed_at=now() FROM picked WHERE q.id=picked.id RETURNING q.*;
END $$;
CREATE OR REPLACE FUNCTION public.payment_channel_enqueue() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE kind text; amt numeric; moment timestamptz; addr text; fc numeric; epoch timestamptz;
BEGIN
 IF EXISTS(SELECT 1 FROM game_settings WHERE key='game_reset_in_progress' AND value='true'::jsonb) THEN RETURN NEW; END IF;
 SELECT (value#>>'{}')::timestamptz INTO epoch FROM game_settings WHERE key='game_reset_epoch';
 IF TG_TABLE_NAME='wallet_deposits' THEN
  IF NEW.status<>'credited' THEN RETURN NEW; END IF;
  kind:='deposit'; amt:=NEW.amount_ton; fc:=coalesce(NEW.amount_fc,0); moment:=coalesce(NEW.credited_at,NEW.confirmed_at,now()); addr:=NEW.from_wallet;
 ELSE
  IF NEW.status NOT IN ('paid','completed') THEN RETURN NEW; END IF;
  kind:='withdrawal'; amt:=coalesce(NEW.net_ton,NEW.amount_ton); fc:=0; moment:=coalesce(NEW.paid_at,NEW.processed_at,now()); addr:=NEW.wallet_address;
 END IF;
 IF NULLIF(trim(NEW.tx_hash),'') IS NULL OR coalesce(amt,0)<=0 OR (epoch IS NOT NULL AND NEW.created_at<epoch) THEN RETURN NEW; END IF;
 INSERT INTO payment_channel_outbox(kind,source_id,amount_ton,amount_fc,wallet,tx_hash,occurred_at) VALUES(kind,NEW.id,amt,fc,addr,NEW.tx_hash,moment) ON CONFLICT DO NOTHING;
 RETURN NEW;
END $$;
CREATE TRIGGER payment_channel_deposit AFTER INSERT OR UPDATE ON public.wallet_deposits FOR EACH ROW EXECUTE FUNCTION public.payment_channel_enqueue();
CREATE TRIGGER payment_channel_withdrawal AFTER INSERT OR UPDATE ON public.wallet_withdrawals FOR EACH ROW EXECUTE FUNCTION public.payment_channel_enqueue();
REVOKE ALL ON FUNCTION public.payment_channel_tick(),public.payment_channel_retry(),public.payment_channel_wake(),public.payment_channel_claim(),public.payment_channel_enqueue() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.payment_channel_tick(),public.payment_channel_retry(),public.payment_channel_wake(),public.payment_channel_claim(),public.payment_channel_enqueue() TO service_role;