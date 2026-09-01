-- Índice único perdido quando item_id passou a aceitar NULL (fragmentos universais).
create unique index if not exists player_pet_inventory_user_type_item_uidx
  on public.player_pet_inventory(user_id, item_type, item_id)
  where item_id is not null;

-- Move um ovo do inventário genérico para o estoque de pets sem depender de ON CONFLICT.
create or replace function public.pet_egg_move_from_inventory(p_user_id uuid, p_egg_id uuid)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare v_slug text; v_row public.player_inventory; v_stock uuid;
begin
  select slug into v_slug from pet_eggs where id = p_egg_id;
  if v_slug is null then return false; end if;
  select * into v_row from player_inventory
   where user_id = p_user_id and item_type = 'pet_egg'
     and lower(replace(item_code,'_','-')) = lower(replace(v_slug,'_','-'))
     and quantity > 0
   order by quantity desc limit 1 for update;
  if v_row.id is null then return false; end if;
  update player_inventory set quantity = quantity - 1, updated_at = now() where id = v_row.id;
  delete from player_inventory where id = v_row.id and quantity <= 0;

  select id into v_stock from player_pet_inventory
   where user_id = p_user_id and item_type = 'egg' and item_id = p_egg_id
   limit 1 for update;
  if v_stock is null then
    insert into player_pet_inventory(user_id,item_type,item_id,quantity)
      values(p_user_id,'egg',p_egg_id,1);
  else
    update player_pet_inventory set quantity = quantity + 1, updated_at = now() where id = v_stock;
  end if;
  return true;
end $function$;
revoke all on function public.pet_egg_move_from_inventory(uuid,uuid) from public, anon, authenticated;
grant execute on function public.pet_egg_move_from_inventory(uuid,uuid) to service_role;