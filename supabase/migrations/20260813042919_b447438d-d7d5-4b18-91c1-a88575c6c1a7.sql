CREATE OR REPLACE FUNCTION public.player_pets_nft_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
declare nft boolean;
begin
  if tg_op = 'INSERT' then
    select is_nft_exclusive into nft from public.pets where id = new.pet_id;
    if coalesce(nft,false) then
      if new.nft_pet_id is null then raise exception 'NFT_PET_ADMIN_ONLY'; end if;
      new.tradable := false;
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.nft_pet_id is not null then
      if new.nft_pet_id is distinct from old.nft_pet_id then raise exception 'NFT_PET_IMMUTABLE'; end if;
      if new.user_id is distinct from old.user_id then raise exception 'NFT_PET_NOT_TRANSFERABLE'; end if;
      new.tradable := false;
    end if;
    return new;
  end if;
  if old.nft_pet_id is not null and coalesce(current_setting('mythreon.nft_revoke', true), '') <> '1' then
    raise exception 'NFT_PET_CANNOT_BE_DESTROYED';
  end if;
  return old;
end $function$;

CREATE OR REPLACE FUNCTION public.market_block_pet_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'DELETE' then
    if old.market_locked and old.nft_pet_id is null then raise exception 'PET_LISTED_IN_MARKET'; end if;
    return old;
  end if;
  if new.nft_pet_id is not null then return new; end if;
  if old.market_locked and new.market_locked then
    if new.is_active then raise exception 'PET_LISTED_IN_MARKET'; end if;
    if new.level is distinct from old.level or new.xp is distinct from old.xp
       or new.evolution_stage is distinct from old.evolution_stage
       or new.user_id is distinct from old.user_id then
      raise exception 'PET_LISTED_IN_MARKET';
    end if;
  end if;
  return new;
end $function$;

UPDATE public.player_pets p
   SET market_locked = false, tradable = false, updated_at = now()
 WHERE p.nft_pet_id IS NOT NULL
   AND p.market_locked
   AND NOT EXISTS (
     SELECT 1 FROM public.market_listings l
      WHERE l.item_type = 'pet' AND l.item_instance_id = p.id AND l.status = 'active');