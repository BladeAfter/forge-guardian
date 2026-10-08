CREATE OR REPLACE FUNCTION public.claim_starter_pack(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pl public.game_players; v_egg uuid; v_updated int;
begin
  select * into pl from public.game_players where telegram_id = p_telegram_id for update;
  if pl.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if pl.banned then raise exception 'PLAYER_BANNED'; end if;
  if pl.created_at < public.starter_pack_cutoff() then raise exception 'STARTER_PACK_NOT_ELIGIBLE'; end if;

  -- single-writer guard: only the transaction that flips the flag delivers the pack
  update public.game_players
    set starter_pack_claimed = true, starter_pack_claimed_at = now(),
        forge_coins = coalesce(forge_coins, 0) + 50000, updated_at = now()
    where id = pl.id and coalesce(starter_pack_claimed, false) = false;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    return jsonb_build_object('claimed', true, 'alreadyClaimed', true,
      'message', 'Starter Pack already claimed',
      'status', public.get_starter_pack_status(p_telegram_id));
  end if;

  select id into v_egg from public.pet_eggs where slug = 'common-egg' and is_enabled;
  if v_egg is null then raise exception 'STARTER_EGG_NOT_FOUND'; end if;
  insert into public.player_pet_inventory(user_id, item_type, item_id, quantity)
  values (pl.id, 'egg', v_egg, 1)
  on conflict (user_id, item_type, (coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
  do update set quantity = public.player_pet_inventory.quantity + 1, updated_at = now();

  -- starter chest changed to 5x existing Common Hero Chest
  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (pl.id, 'hero_chest', 'common_hero_chest', 5)
  on conflict (user_id, item_type, item_code)
  do update set quantity = public.player_inventory.quantity + 5, updated_at = now();

  return jsonb_build_object(
    'claimed', true, 'alreadyClaimed', false,
    'granted', jsonb_build_object('fc', 50000, 'eggCode', 'common-egg', 'eggQuantity', 1,
                                  'chestCode', 'common_hero_chest', 'chestQuantity', 5),
    'balance', (select forge_coins from public.game_players where id = pl.id),
    'status', public.get_starter_pack_status(p_telegram_id)
  );
end $function$;

REVOKE ALL ON FUNCTION public.claim_starter_pack(bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_starter_pack(bigint) TO service_role;