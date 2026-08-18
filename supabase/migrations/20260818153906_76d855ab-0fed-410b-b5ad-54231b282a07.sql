revoke execute on function public.myth_staking_accrue(uuid) from anon, authenticated, public;
revoke execute on function public.myth_staking_accrue_user(uuid) from anon, authenticated, public;
revoke execute on function public.get_myth_staking_dashboard(bigint) from anon, authenticated, public;
revoke execute on function public.myth_stake(bigint, numeric, text, text) from anon, authenticated, public;
revoke execute on function public.myth_staking_claim(bigint, uuid, text) from anon, authenticated, public;
revoke execute on function public.myth_unstake(bigint, uuid, text) from anon, authenticated, public;
revoke execute on function public.admin_myth_staking_overview(bigint) from anon, authenticated, public;
revoke execute on function public.admin_myth_staking_set(bigint, text, numeric) from anon, authenticated, public;
revoke execute on function public.admin_myth_staking_plan_set(bigint, text, numeric, boolean) from anon, authenticated, public;