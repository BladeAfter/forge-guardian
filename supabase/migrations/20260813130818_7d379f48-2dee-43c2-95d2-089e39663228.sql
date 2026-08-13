-- Expose the yield settings inside the master-admin-only pool overview.
-- Player-facing payloads are untouched: nft_my_reward still returns only the
-- player's own NFT yield and never any pool treasury data.
create or replace function public.admin_nft_pool_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare base jsonb; s public.nft_pool_settings;
begin
  perform public.admin_assert(p_admin_id);
  base := public.admin_nft_pool_overview_core();
  select * into s from public.nft_pool_settings where id;
  return base || jsonb_build_object('settings', jsonb_build_object(
    'tier20DailyTon', s.tier20_daily_ton,
    'tier30DailyTon', s.tier30_daily_ton,
    'minClaimTon', s.min_claim_ton,
    'accrualEnabled', s.accrual_enabled
  ));
end $$;

revoke all on function public.admin_nft_pool_overview(bigint) from public, anon, authenticated;
grant execute on function public.admin_nft_pool_overview(bigint) to service_role, postgres;