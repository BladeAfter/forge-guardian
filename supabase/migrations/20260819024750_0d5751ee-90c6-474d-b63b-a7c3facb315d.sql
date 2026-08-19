INSERT INTO public.spending_events (name, starts_at, ends_at, status, ton_rate_fc, top_limit)
SELECT 'SPENDING EVENT', now(), now() + interval '14 days', 'active', 100000, 20
WHERE NOT EXISTS (SELECT 1 FROM public.active_spending_event());