do $mig$
declare src text; patched text;
begin
  select pg_get_functiondef(p.oid) into src from pg_proc p
   where p.proname = 'market_get_sellable' and pronamespace = 'public'::regnamespace;
  patched := replace(src,
    'from player_inventory i where i.user_id = u and i.quantity > 0',
    'from player_inventory i left join chest_reward_tables c on c.chest_code = i.item_code
     where i.user_id = u and i.quantity > 0');
  if patched = src then raise exception 'PATCH_FAILED'; end if;
  execute patched;
end $mig$;