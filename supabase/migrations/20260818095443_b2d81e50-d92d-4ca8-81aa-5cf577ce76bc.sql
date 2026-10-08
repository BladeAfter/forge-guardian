do $$
declare src text; old_txt text; new_txt text;
begin
  src := pg_get_functiondef('public.market_finalize_purchase(uuid,uuid,boolean,text)'::regprocedure);
  old_txt := 'elsif l.item_type = ''pet'' then
    update player_pets set user_id = p_buyer, market_locked = false, is_active = false, updated_at = now() where id = l.item_instance_id;';
  new_txt := 'elsif l.item_type = ''pet'' then
    if exists (
      select 1 from player_pets mine
       where mine.user_id = p_buyer
         and mine.id <> l.item_instance_id
         and mine.pet_id = (select pp.pet_id from player_pets pp where pp.id = l.item_instance_id)
    ) then raise exception ''PET_ALREADY_OWNED''; end if;
    update player_pets set user_id = p_buyer, market_locked = false, is_active = false, updated_at = now() where id = l.item_instance_id;';
  if position(old_txt in src) = 0 then raise exception 'PET_BRANCH_NOT_FOUND'; end if;
  execute replace(src, old_txt, new_txt);
end $$;