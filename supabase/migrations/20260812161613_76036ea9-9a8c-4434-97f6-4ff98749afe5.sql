CREATE OR REPLACE FUNCTION public.get_player_inventory(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare u uuid; v_chests jsonb; v_eggs jsonb; v_items jsonb;
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  -- Legacy keys kept intact: the calendar/chest screens already consume them.
  v_chests := coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'itemCode',i.item_code,'name',coalesce(c.name,i.item_code),'subtitle',coalesce(c.subtitle,''),'quantity',i.quantity,'rarityRates',coalesce(c.rarity_rates,'{}'::jsonb)) order by i.item_code)
      from player_inventory i left join chest_reward_tables c on c.chest_code=i.item_code
      where i.user_id=u and i.item_type='hero_chest' and i.quantity>0),'[]'::jsonb);

  v_eggs := coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'slug',e.slug,'name',e.name,'image',e.image_url,'quantity',pi.quantity,'rarityRates',e.rarity_rates) order by e.name)
      from player_pet_inventory pi join pet_eggs e on e.id=pi.item_id
      where pi.user_id=u and pi.item_type='egg' and pi.quantity>0),'[]'::jsonb);

  -- Consolidated read-only view over the real sources (no mirrored balances).
  v_items := (
    select coalesce(jsonb_agg(x order by x->>'category', x->>'name'),'[]'::jsonb) from (
      -- chests (player_inventory)
      select jsonb_build_object('key','chest:'||i.id,'itemId',i.item_code,'instanceId',i.id,'itemType','chest','category','chests',
        'name',coalesce(c.name,i.item_code),'description',coalesce(c.subtitle,''),'image',null,'rarity',null,
        'quantity',i.quantity,'usable',true,'action','open-chest') as x
      from player_inventory i left join chest_reward_tables c on c.chest_code=i.item_code
      where i.user_id=u and i.item_type='hero_chest' and i.quantity>0
      union all
      -- other stackable items stored in player_inventory (tickets, event items, materials, ...)
      select jsonb_build_object('key',i.item_type||':'||i.item_code,'itemId',i.item_code,'instanceId',i.id,'itemType',i.item_type,
        'category',case when i.item_type ilike '%fragment%' then 'fragments' else 'other' end,
        'name',initcap(replace(i.item_code,'_',' ')),'description',initcap(replace(i.item_type,'_',' ')),'image',null,'rarity',null,
        'quantity',i.quantity,'usable',false,'action',null)
      from player_inventory i
      where i.user_id=u and i.item_type<>'hero_chest' and i.quantity>0
      union all
      -- eggs (player_pet_inventory)
      select jsonb_build_object('key','egg:'||e.id,'itemId',e.id::text,'instanceId',null,'itemType','egg','category','eggs',
        'name',e.name,'description','Pet Egg','image',e.image_url,
        'rarity',(select k from jsonb_each_text(coalesce(e.rarity_rates,'{}'::jsonb)) as t(k,v) order by (v)::numeric desc limit 1),
        'quantity',pi.quantity,'usable',true,'action','hatch')
      from player_pet_inventory pi join pet_eggs e on e.id=pi.item_id
      where pi.user_id=u and pi.item_type='egg' and pi.quantity>0
      union all
      -- pet food (player_pet_food)
      select jsonb_build_object('key','food:'||f.code,'itemId',f.code,'instanceId',null,'itemType','food','category','food',
        'name',f.name,'description','Pet Food','image',f.icon,'rarity',f.rarity,
        'quantity',pf.quantity,'usable',true,'action','feed')
      from player_pet_food pf join pet_food_items f on f.code=pf.food_code
      where pf.user_id=u and pf.quantity>0
      union all
      -- universal fragments (player_pet_inventory)
      select jsonb_build_object('key','universal_fragment','itemId','universal_fragment','instanceId',null,'itemType','universal_fragment',
        'category','fragments','name','Universal Fragment','description','Universal Fragment','image',null,'rarity',null,
        'quantity',pi.quantity,'usable',false,'action',null)
      from player_pet_inventory pi
      where pi.user_id=u and pi.item_type='universal_fragment' and pi.item_id is null and pi.quantity>0
      union all
      -- pet fragments (player_pets.fragments)
      select jsonb_build_object('key','pet_fragment:'||pp.id,'itemId',pp.pet_id::text,'instanceId',pp.id,'itemType','pet_fragment',
        'category','fragments','name',p.name||' Fragment','description','Pet Fragment','image',p.image_baby_url,'rarity',pp.rarity,
        'quantity',pp.fragments,'usable',false,'action',null)
      from player_pets pp join pets p on p.id=pp.pet_id
      where pp.user_id=u and pp.fragments>0
    ) s
  );

  return jsonb_build_object('chests',v_chests,'eggs',v_eggs,'items',v_items);
end $function$;