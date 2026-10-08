create or replace function public.nft_pool_accrue()
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.nft_pool_settings; r public.nft_yield_positions; secs numeric; gain numeric; touched integer := 0; total numeric := 0;
begin
  s := public.nft_pool_settings_row();
  perform public.nft_pool_sync_positions();
  if not s.accrual_enabled then return jsonb_build_object('enabled', false, 'positions', 0); end if;
  for r in select * from public.nft_yield_positions where status = 'active' for update loop
    secs := greatest(0, extract(epoch from (now() - r.last_accrual_at)));
    if secs < 60 then continue; end if;
    gain := round(public.nft_effective_daily(r) * (secs / 86400.0), 9);
    update public.nft_yield_positions
       set accrued_ton = accrued_ton + gain,
           roi_reached = roi_reached or (claimed_ton + accrued_ton + gain) >= roi_target_ton,
           last_accrual_at = now(), updated_at = now()
     where id = r.id;
    touched := touched + 1; total := total + gain;
  end loop;
  update public.nft_reward_pool
     set reserved_ton = coalesce((select sum(accrued_ton) from public.nft_yield_positions where status = 'active'), 0),
         updated_at = now()
   where id;
  return jsonb_build_object('enabled', true, 'positions', touched, 'accrued', total);
end $$;
revoke all on function public.nft_pool_accrue() from public, anon, authenticated;
grant execute on function public.nft_pool_accrue() to service_role, postgres;