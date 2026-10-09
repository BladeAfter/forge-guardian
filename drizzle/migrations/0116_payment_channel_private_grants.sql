REVOKE ALL ON public.payment_channel_outbox, public.payment_channel_health FROM anon,authenticated;
GRANT ALL ON public.payment_channel_outbox, public.payment_channel_health TO service_role;