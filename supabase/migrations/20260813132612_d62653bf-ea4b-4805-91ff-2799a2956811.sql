-- Player-facing list of the NFT EXCLUSIVE pets owned by the caller.
-- Read-only: never exposes pool balance, health, reserved or treasury data.
create or replace function public.nft_my_rewards_json(p_telegram_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path = public
as $$
declare u uuid; total integer; items jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select count(*) into total from public.nft_pets;
  select coalesce(jsonb_agg(x order by x->>'serial'), '[]'::jsonb) into items from (
    select jsonb_build_object(
      'positionId', p.id,
      'serial', p.nft_serial,
      'name', coalesce(pt.name, 'NFT PET'),
      'rarity', coalesce(pp.rarity, pt.rarity, 'nft_exclusive'),
      'level', coalesce(pp.level, 1),
      'image', coalesce(pt.image_adult_url, pt.image_young_url, pt.image_baby_url),
      'tierTon', p.tier_ton,
      'dailyYieldTon', public.nft_effective_daily(p),
      'availableTon', round(p.accrued_ton, 6),
      'lifetimeEarnedTon', round(p.claimed_ton, 6),
      'roiReached', p.roi_reached,
      'minClaimTon', (public.nft_pool_settings_row()).min_claim_ton,
      'canClaim', round(p.accrued_ton, 6) >= (public.nft_pool_settings_row()).min_claim_ton,
      'lastClaimAt', p.last_claim_at
    ) as x
    from public.nft_yield_positions p
    left join public.nft_pets n on n.id = p.nft_pet_id
    left join public.player_pets pp on pp.id = n.player_pet_id
    left join public.pets pt on pt.id = coalesce(pp.pet_id, n.pet_template_id)
    where p.owner_user_id = u and p.status = 'active'
  ) q;
  return jsonb_build_object('totalSupply', greatest(total, 10), 'items', items);
end $$;

revoke all on function public.nft_my_rewards_json(bigint) from public, anon, authenticated;

-- Claim for ONE specific NFT position (same rules as nft_claim_reward).
create or replace function public.nft_claim_position(p_telegram_id bigint, p_position_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare u uuid; p public.nft_yield_positions; s public.nft_pool_settings;
        pool public.nft_reward_pool; amount numeric; claim uuid := gen_random_uuid();
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_pool_accrue();
  s := public.nft_pool_settings_row();
  select * into pool from public.nft_reward_pool where id for update;
  select * into p from public.nft_yield_positions
   where id = p_position_id and owner_user_id = u and status = 'active' for update;
  if p.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  amount := round(p.accrued_ton, 6);
  if amount < s.min_claim_ton then raise exception 'CLAIM_TOO_SMALL'; end if;
  if pool.balance_ton < amount then raise exception 'POOL_INSUFFICIENT'; end if;

  update public.nft_reward_pool
     set balance_ton = balance_ton - amount,
         lifetime_paid_ton = lifetime_paid_ton + amount,
         reserved_ton = greatest(0, reserved_ton - amount),
         updated_at = now()
   where id;
  update public.nft_yield_positions
     set accrued_ton = accrued_ton - amount, claimed_ton = claimed_ton + amount,
         roi_reached = roi_reached or (claimed_ton + amount) >= roi_target_ton,
         last_claim_at = now(), updated_at = now()
   where id = p.id;
  insert into public.nft_pool_transactions(type, amount_ton, balance_before, balance_after, nft_id, user_id, telegram_id, claim_id, note)
  values ('CLAIM_PAYMENT', -amount, pool.balance_ton, pool.balance_ton - amount, p.nft_pet_id, u, p_telegram_id, claim,
          format('NFT #%s claim', p.nft_serial));
  perform public.credit_ton_reward(u, amount, 'nft_reward', claim::text, format('NFT #%s reward claim', p.nft_serial));

  return jsonb_build_object('ok', true, 'claimId', claim, 'amountTon', amount) || public.nft_my_rewards_json(p_telegram_id);
end $$;

revoke all on function public.nft_claim_position(bigint, uuid) from public, anon, authenticated;