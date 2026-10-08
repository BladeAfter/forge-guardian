-- Central finalization hook for confirmed NFT pet purchases:
-- feeds Spending Event + one-time referral TON commission, idempotently.
create or replace function public.nft_purchase_finalize()
returns trigger language plpgsql security definer set search_path to 'public'
as $fn$
declare v_ref text; v_amount numeric; v_new text; v_old text; v_ref_res jsonb;
begin
  v_ref := 'nft_order:' || NEW.id::text;
  v_amount := round(coalesce(NEW.price_ton, 0), 9);
  v_new := lower(coalesce(NEW.status, ''));
  v_old := case when TG_OP = 'UPDATE' then lower(coalesce(OLD.status, '')) else null end;

  if v_new in ('confirmed','completed','delivered','paid_confirmed')
     and (TG_OP = 'INSERT' or v_old is distinct from v_new)
     and v_amount > 0 then
    -- 1. Spending Event (1 TON = ton_rate_fc points, computed server-side)
    perform public.record_spending_points(NEW.user_id, 'nft_pet_purchase', v_ref, 'TON', v_amount);
    -- 2. One-time referral commission (skipped automatically if already processed)
    v_ref_res := public.referral_pay_ton_commission(NEW.user_id, 'nft_pet_purchase', v_ref, v_amount);
    raise log 'NFT_PET_PURCHASE order=% buyer=% amount_ton=% spending_ref=% referral_eligible=% referral_commission_ton=%',
      NEW.id, NEW.user_id, v_amount, v_ref,
      not coalesce((v_ref_res->>'duplicate')::boolean, false), coalesce(v_ref_res->>'totalTon','0');
  elsif TG_OP = 'UPDATE' and v_new in ('refunded','reversed','cancelled','canceled','failed','expired')
     and v_old is distinct from v_new then
    perform public.record_spending_reversal(v_ref);
  end if;
  return NEW;
end $fn$;

revoke all on function public.nft_purchase_finalize() from public, anon, authenticated;

drop trigger if exists trg_nft_purchase_finalize_ins on public.nft_pet_orders;
create trigger trg_nft_purchase_finalize_ins after insert on public.nft_pet_orders
for each row execute function public.nft_purchase_finalize();

drop trigger if exists trg_nft_purchase_finalize_upd on public.nft_pet_orders;
create trigger trg_nft_purchase_finalize_upd after update of status on public.nft_pet_orders
for each row execute function public.nft_purchase_finalize();