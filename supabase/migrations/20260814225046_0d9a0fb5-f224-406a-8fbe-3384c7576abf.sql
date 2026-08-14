alter table public.nft_reward_pool add column if not exists debt_ton numeric(20,9) not null default 0;

create or replace function public.nft_pool_settle_payment(p_amount numeric)
returns numeric
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_before numeric; v_use numeric;
begin
  select balance_ton into v_before from public.nft_reward_pool where id for update;
  v_use := least(coalesce(v_before,0), p_amount);
  update public.nft_reward_pool
     set balance_ton = coalesce(balance_ton,0) - v_use,
         debt_ton = coalesce(debt_ton,0) + (p_amount - v_use),
         lifetime_paid_ton = lifetime_paid_ton + p_amount,
         reserved_ton = greatest(0, reserved_ton - p_amount),
         updated_at = now()
   where id;
  return coalesce(v_before,0);
end $function$;

revoke all on function public.nft_pool_settle_payment(numeric) from public, anon, authenticated;

create or replace function public.nft_claim_position(p_telegram_id bigint, p_position_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare u uuid; p public.nft_yield_positions; s public.nft_pool_settings;
        v_before numeric; amount numeric; claim uuid := gen_random_uuid();
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_pool_accrue();
  s := public.nft_pool_settings_row();
  select * into p from public.nft_yield_positions
   where id = p_position_id and owner_user_id = u and status = 'active' for update;
  if p.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  amount := round(p.accrued_ton, 6);
  if amount <= 0 or amount < s.min_claim_ton then raise exception 'CLAIM_TOO_SMALL'; end if;

  v_before := public.nft_pool_settle_payment(amount);
  update public.nft_yield_positions
     set accrued_ton = accrued_ton - amount, claimed_ton = claimed_ton + amount,
         roi_reached = roi_reached or (claimed_ton + amount) >= roi_target_ton,
         last_claim_at = now(), updated_at = now()
   where id = p.id;
  insert into public.nft_pool_transactions(type, amount_ton, balance_before, balance_after, nft_id, user_id, telegram_id, claim_id, note)
  values ('CLAIM_PAYMENT', -amount, v_before, greatest(0, v_before - amount), p.nft_pet_id, u, p_telegram_id, claim,
          format('NFT #%s claim', p.nft_serial));
  perform public.credit_ton_reward(u, amount, 'nft_reward', claim::text, format('NFT #%s reward claim', p.nft_serial));

  return jsonb_build_object('ok', true, 'claimId', claim, 'amountTon', amount) || public.nft_my_rewards_json(p_telegram_id);
end $function$;

revoke all on function public.nft_claim_position(bigint, uuid) from public, anon, authenticated;

create or replace function public.nft_claim_reward(p_telegram_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare u uuid; p public.nft_yield_positions; s public.nft_pool_settings;
        v_before numeric; amount numeric; claim uuid := gen_random_uuid();
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_pool_accrue();
  s := public.nft_pool_settings_row();
  select * into p from public.nft_yield_positions
   where owner_user_id = u and status = 'active' order by nft_serial limit 1 for update;
  if p.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  amount := round(p.accrued_ton, 6);
  if amount <= 0 or amount < s.min_claim_ton then raise exception 'CLAIM_TOO_SMALL'; end if;

  v_before := public.nft_pool_settle_payment(amount);
  update public.nft_yield_positions
     set accrued_ton = accrued_ton - amount, claimed_ton = claimed_ton + amount,
         roi_reached = roi_reached or (claimed_ton + amount) >= roi_target_ton,
         last_claim_at = now(), updated_at = now()
   where id = p.id;
  insert into public.nft_pool_transactions(type, amount_ton, balance_before, balance_after, nft_id, user_id, telegram_id, claim_id, note)
  values ('CLAIM_PAYMENT', -amount, v_before, greatest(0, v_before - amount), p.nft_pet_id, u, p_telegram_id, claim,
          format('NFT #%s claim', p.nft_serial));
  perform public.credit_ton_reward(u, amount, 'nft_reward', claim::text, format('NFT #%s reward claim', p.nft_serial));

  return jsonb_build_object('ok', true, 'claimId', claim, 'amountTon', amount) || public.nft_my_reward(p_telegram_id);
end $function$;

revoke all on function public.nft_claim_reward(bigint) from public, anon, authenticated;