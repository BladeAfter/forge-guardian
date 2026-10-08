UPDATE public.economy_settings SET value_numeric = 1 WHERE key IN ('min_fc_ton_deposit','min_direct_ton_deposit');
INSERT INTO public.economy_settings(key, value_numeric) VALUES ('min_fc_ton_deposit', 1), ('min_direct_ton_deposit', 1) ON CONFLICT (key) DO UPDATE SET value_numeric = excluded.value_numeric;
INSERT INTO public.wallet_settings(key, value_numeric) VALUES ('withdraw_min_deposit_ton', 2) ON CONFLICT (key) DO UPDATE SET value_numeric = excluded.value_numeric;
CREATE OR REPLACE FUNCTION public.withdraw_min_deposit_ton()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(0, COALESCE((SELECT value_numeric FROM wallet_settings WHERE key = 'withdraw_min_deposit_ton'), 2));
$$;
REVOKE ALL ON FUNCTION public.withdraw_min_deposit_ton() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_min_deposit_ton() TO service_role;