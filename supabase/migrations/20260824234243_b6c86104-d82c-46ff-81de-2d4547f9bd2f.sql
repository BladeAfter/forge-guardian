revoke all on function public.list_premium_titles() from public, anon, authenticated;
grant execute on function public.list_premium_titles() to service_role;