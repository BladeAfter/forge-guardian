do $mig$
declare src text; patched text;
begin
  select pg_get_functiondef(p.oid) into src from pg_proc p
   where p.proname = 'market_finalize_purchase' and pronamespace = 'public'::regnamespace;
  if src is null then raise exception 'market_finalize_purchase not found'; end if;

  patched := regexp_replace(
    src,
    'insert into player_inventory\(user_id, item_type, item_code, quantity\)\s*values \(p_buyer, coalesce\(l\.snapshot->>''itemType'',''item''\), l\.item_code, l\.quantity\)\s*on conflict \(user_id, item_type, item_code\)\s*do update set quantity = player_inventory\.quantity \+ excluded\.quantity, updated_at = now\(\);',
    'perform market_item_give(p_buyer, l.item_code, l.snapshot, coalesce(l.quantity,1));',
    'g');

  if patched not like '%market_item_give%' then
    raise exception 'PATCH_FAILED: delivery block not found';
  end if;

  execute patched;
end $mig$;