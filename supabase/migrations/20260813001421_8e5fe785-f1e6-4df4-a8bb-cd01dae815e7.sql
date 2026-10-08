CREATE OR REPLACE FUNCTION public.admin_nft_hero_revoke(p_admin_id bigint, p_nft_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n public.nft_heroes; c public.hero_catalog; prev uuid;
begin
  perform public.admin_assert(p_admin_id);
  select * into n from nft_heroes where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_HERO_NOT_FOUND'; end if;
  select * into c from hero_catalog where hero_key = n.hero_template_id;
  prev := n.owner_user_id;
  if n.player_hero_id is not null then
    delete from pvp_team_slots where hero_id = n.player_hero_id;
    delete from boss_team_slots where player_hero_id = n.player_hero_id;
    delete from hero_combat_state where hero_id = n.player_hero_id;
    update market_listings set status = 'CANCELLED', cancelled_at = now(), updated_at = now()
      where item_type = 'HERO' and item_instance_id = n.player_hero_id and status = 'ACTIVE';
    update player_heroes set market_locked = false, locked = false where id = n.player_hero_id;
    perform set_config('mythreon.nft_hero_revoke','1', true);
    delete from player_heroes where id = n.player_hero_id;
    perform set_config('mythreon.nft_hero_revoke','0', true);
  end if;
  update nft_heroes set owner_user_id = null, player_hero_id = null, status = 'AVAILABLE',
      revoked_at = now(), assigned_at = null, updated_at = now()
   where id = n.id;
  insert into nft_hero_history (nft_hero_id, action, admin_telegram_id, from_user_id, reason)
    values (n.id, 'REVOKED', p_admin_id, prev, p_reason);
  perform public.admin_log(p_admin_id,'nft_hero.revoke','hero',n.unique_instance_id,null,
    jsonb_build_object('from', prev), p_reason);
  return jsonb_build_object('instance', n.unique_instance_id, 'hero', c.name, 'serial', n.nft_serial);
end $function$;