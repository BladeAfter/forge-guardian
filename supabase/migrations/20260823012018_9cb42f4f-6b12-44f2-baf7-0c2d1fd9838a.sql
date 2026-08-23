REVOKE EXECUTE ON FUNCTION public.withdraw_min_deposit_ton() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.player_ton_deposit_total(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_min_deposit_ton() TO service_role;
GRANT EXECUTE ON FUNCTION public.player_ton_deposit_total(uuid) TO service_role;