-- Restore the full overview body (the previous version referenced a helper that
-- does not exist) and append the yield settings. Admin-only: player payloads
-- never include pool treasury data.
create or replace function public.admin_nft_pool_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pool public.nft_reward_pool; s public.nft_pool_settings;
        obligation numeric; active integer; claimable numeric; total integer;
begin
  perform public.admin_assert(p_admin_id);
  perform public.nft_pool_accrue();
  select * into pool from public.nft_reward_pool where id;
  select * into s from public.nft_pool_settings where id;
  select coalesce(sum(daily_yield_ton),0), count(*) into obligation, active
    from public.nft_yield_positions where status = 'active';
  select coalesce(sum(accrued_ton),0) into claimable from public.nft_yield_positions where status = 'active';
  select count(*) into total from public.nft_pets;
  return jsonb_build_object(
    'balanceTon', pool.balance_ton, 'reservedTon', pool.reserved_ton,
    'availableTon', greatest(0, pool.balance_ton - pool.reserved_ton),
    'dailyObligationTon', obligation, 'activeNfts', active, 'totalNfts', greatest(total, 10),
    'claimableTon', round(claimable, 6), 'lifetimePaidTon', pool.lifetime_paid_ton,
    'lifetimeFundedTon', pool.lifetime_funded_ton, 'health', public.nft_pool_health(),
    'updatedAt', pool.updated_at,
    'settings', jsonb_build_object(
      'tier20DailyTon', s.tier20_daily_ton,
      'tier30DailyTon', s.tier30_daily_ton,
      'minClaimTon', s.min_claim_ton,
      'accrualEnabled', s.accrual_enabled));
end $$;

revoke all on function public.admin_nft_pool_overview(bigint) from public, anon, authenticated;
grant execute on function public.admin_nft_pool_overview(bigint) to service_role, postgres;