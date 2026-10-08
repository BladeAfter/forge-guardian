-- 1) Apply the account-wide TON mining bonus (Celestial packs) to NFT pet pool yield too.
create or replace function public.nft_pool_accrue()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare s public.nft_pool_settings; r public.nft_yield_positions; secs numeric;
        gain_ton numeric; gain_myth numeric; bonus numeric;
        touched integer := 0; total numeric := 0; total_myth numeric := 0;
begin
  s := public.nft_pool_settings_row();
  perform public.nft_pool_sync_positions();
  if not s.accrual_enabled then return jsonb_build_object('enabled', false, 'positions', 0); end if;
  for r in select * from public.nft_yield_positions where status = 'active' for update loop
    secs := greatest(0, extract(epoch from (now() - r.last_accrual_at)));
    if secs < 60 then continue; end if;
    bonus := greatest(coalesce((select account_ton_mining_bonus from public.game_players where id = r.owner_user_id), 0), 0);
    gain_ton := round(public.nft_effective_daily(r) * (secs / 86400.0) * (1 + bonus / 100.0), 9);
    gain_myth := round(public.nft_effective_daily_myth(r) * (secs / 86400.0), 9);
    update public.nft_yield_positions
       set accrued_ton = accrued_ton + greatest(gain_ton, 0),
           accrued_myth = accrued_myth + greatest(gain_myth, 0),
           roi_reached = roi_reached or (greatest(gain_ton,0) > 0 and (claimed_ton + accrued_ton + gain_ton) >= roi_target_ton),
           last_accrual_at = now(), updated_at = now()
     where id = r.id;
    touched := touched + 1;
    total := total + greatest(gain_ton, 0);
    total_myth := total_myth + greatest(gain_myth, 0);
  end loop;
  update public.nft_reward_pool
     set reserved_ton = coalesce((select sum(accrued_ton) from public.nft_yield_positions where status = 'active'), 0),
         updated_at = now()
   where id;
  return jsonb_build_object('enabled', true, 'currency', 'dual', 'positions', touched,
                            'accrued', total, 'accruedMyth', total_myth);
end $$;

-- 2) Swap the Sovereign Pack NFT pet (Sylvaris) of player 8389114826 for a Celestial pet,
--    keeping the same yield position and activating 0.80 TON/day.
update public.player_pets
   set pet_id = '40fd4e48-338f-4cb7-b074-bcc472a004b7', -- Solvanthys (celestial)
       rarity = 'celestial',
       mining_last_at = now(),
       updated_at = now()
 where id = 'a3301748-cb55-4494-a17d-56c1bab5ccd9';

update public.nft_pets
   set daily_yield_ton = 0.80,
       daily_yield_myth = 0,
       mining_pending_reveal = false,
       mining_revealed_at = now(),
       updated_at = now()
 where id = '36c4d3b6-7fe5-429e-a8d2-1a452ab9edff';

update public.nft_yield_positions
   set daily_yield_ton = 0.80,
       roi_target_ton = 150,
       roi_reached = false,
       status = 'active',
       last_accrual_at = now(),
       updated_at = now()
 where nft_pet_id = '36c4d3b6-7fe5-429e-a8d2-1a452ab9edff';

update public.sovereign_pack_items
   set mining_pending_reveal = false,
       revealed_ton = 0.80,
       revealed_myth = 0,
       revealed_at = now()
 where id = '20e6498e-f99e-4d0b-ba31-80651f590591';

select public.ton_mining_bonus_recalc('61727fe2-2cae-4dea-8e47-cd3cfe09a505');
