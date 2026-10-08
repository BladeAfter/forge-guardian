-- Surface key chests in the inventory and let the Battle Pass deliver them.
DO $mig$
DECLARE src text; patched text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = 'get_player_inventory';
  patched := replace(src,
    E'      -- Tower keys: pure collectibles for now (no action, never consumed)',
    E'      -- KEY CHESTS: opened with the matching Tower key (server-side roll)\n'
    '      select jsonb_build_object(''key'',''key_chest:''||i.id,''itemId'',i.item_code,''instanceId'',i.id,\n'
    '        ''itemType'',''key_chest'',''category'',''chests'',''name'',kc.name,''description'',kc.subtitle,\n'
    '        ''image'',kc.image_url,''rarity'',kc.rarity,''quantity'',i.quantity,\n'
    '        ''usable'', coalesce(kq.quantity,0) >= 1, ''action'',''open-key-chest'',\n'
    '        ''premium'',true,''keyCode'',kc.key_code,''keyName'',coalesce(tk.name,kc.key_code),\n'
    '        ''keyImage'',tk.image_url,''keyQuantity'',coalesce(kq.quantity,0))\n'
    '      from player_inventory i\n'
    '      join key_chest_catalog kc on kc.chest_code = i.item_code\n'
    '      left join tower_key_catalog tk on tk.code = kc.key_code\n'
    '      left join player_inventory kq on kq.user_id = i.user_id and kq.item_type = ''tower_key'' and kq.item_code = kc.key_code\n'
    '      where i.user_id=u and i.item_type=''key_chest'' and i.quantity>0\n'
    '      union all\n'
    '      -- Tower keys: consumed by their matching key chest');
  IF patched = src THEN RAISE EXCEPTION 'inventory patch anchor not found'; END IF;
  src := patched;
  patched := replace(src,
    'i.item_type not in (''hero_chest'',''exclusive_chest'',''tower_key'',''resource_chest'')',
    'i.item_type not in (''hero_chest'',''exclusive_chest'',''tower_key'',''resource_chest'',''key_chest'')');
  IF patched = src THEN RAISE EXCEPTION 'inventory exclusion patch anchor not found'; END IF;
  EXECUTE patched;

  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = 'claim_season_pass_reward';
  patched := replace(src,
    'elsif r.reward_type in (''fragments'',''hero_chest'',''skin'',''chest'',''equipment_chest'',''evolution_pack'') then',
    'elsif r.reward_type in (''fragments'',''hero_chest'',''skin'',''chest'',''equipment_chest'',''evolution_pack'',''key_chest'') then');
  IF patched = src THEN RAISE EXCEPTION 'claim patch anchor not found'; END IF;
  EXECUTE patched;
END $mig$;