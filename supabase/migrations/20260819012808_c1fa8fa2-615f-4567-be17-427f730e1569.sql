revoke execute on function public.founder_pack_settings() from public;
revoke execute on function public.founder_pack_snapshot() from public;
revoke execute on function public.founder_pack_state(bigint) from public;
revoke execute on function public.founder_pack_deliver(uuid) from public;
revoke execute on function public.founder_pack_start_purchase(bigint, text, text) from public;
revoke execute on function public.founder_pack_confirm_order(uuid, text, text) from public;
revoke execute on function public.founder_pack_pending_orders(bigint) from public;
revoke execute on function public.founder_frame_set(bigint, boolean) from public;
revoke execute on function public.get_player_entitlements(bigint) from public;
revoke execute on function public.open_resource_chest(bigint, uuid) from public;
revoke execute on function public.admin_founder_pack_overview(bigint) from public;
revoke execute on function public.admin_founder_pack_set(bigint, text, text) from public;
grant execute on function public.founder_pack_state(bigint) to service_role;
grant execute on function public.founder_pack_start_purchase(bigint, text, text) to service_role;
grant execute on function public.founder_pack_confirm_order(uuid, text, text) to service_role;
grant execute on function public.founder_pack_pending_orders(bigint) to service_role;
grant execute on function public.founder_frame_set(bigint, boolean) to service_role;
grant execute on function public.get_player_entitlements(bigint) to service_role;
grant execute on function public.open_resource_chest(bigint, uuid) to service_role;
grant execute on function public.admin_founder_pack_overview(bigint) to service_role;
grant execute on function public.admin_founder_pack_set(bigint, text, text) to service_role;

CREATE OR REPLACE FUNCTION public.get_player_inventory(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; v_chests jsonb; v_eggs jsonb; v_items jsonb;
  v_summon jsonb := public.fragment_summon_config(); v_frag_cost int := public.universal_fusion_fragment_cost();
  v_per_hero int := greatest(1, coalesce((public.fragment_summon_config()->>'fragments_per_hero')::int, 5));
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  v_chests := coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'itemCode',i.item_code,'name',coalesce(c.name,i.item_code),'subtitle',coalesce(c.subtitle,''),'quantity',i.quantity,'rarityRates',coalesce(c.rarity_rates,'{}'::jsonb)) order by i.item_code)
      from player_inventory i left join chest_reward_tables c on c.chest_code=i.item_code
      where i.user_id=u and i.item_type='hero_chest' and i.quantity>0),'[]'::jsonb);

  v_eggs := coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'slug',e.slug,'name',e.name,'image',e.image_url,'quantity',pi.quantity,'rarityRates',e.rarity_rates) order by e.name)
      from player_pet_inventory pi join pet_eggs e on e.id=pi.item_id
      where pi.user_id=u and pi.item_type='egg' and pi.quantity>0),'[]'::jsonb);

  v_items := (
    select coalesce(jsonb_agg(x order by x->>'category', x->>'name'),'[]'::jsonb) from (
      select jsonb_build_object('key','chest:'||i.id,'itemId',i.item_code,'instanceId',i.id,'itemType','chest','category','chests',
        'name',coalesce(c.name,i.item_code),'description',coalesce(c.subtitle,''),'image',null,'rarity',null,
        'quantity',i.quantity,'usable',true,'action','open-chest') as x
      from player_inventory i left join chest_reward_tables c on c.chest_code=i.item_code
      where i.user_id=u and i.item_type='hero_chest' and i.quantity>0
      union all
      select jsonb_build_object('key','exclusive:'||i.id,'itemId',i.item_code,'instanceId',i.id,
        'itemType','exclusive_chest','category','chests',
        'name', case when i.item_code ilike '%pet%' then 'BAÚ MÍTICO EXCLUSIVO DE PET' else 'BAÚ MÍTICO EXCLUSIVO DE HERÓI' end,
        'description', case when i.item_code ilike '%pet%' then 'Pet mítico exclusivo do Passe' else 'Herói mítico exclusivo do Passe' end,
        'image', case when i.item_code ilike '%pet%' then '/assets/game/inventory/exclusive-pet-chest.png' else '/assets/game/inventory/exclusive-hero-chest.png' end,
        'rarity','mythic','exclusive',true,
        'quantity',i.quantity,'usable',true,'action','open-exclusive-chest')
      from player_inventory i
      where i.user_id=u and i.item_type='exclusive_chest' and i.quantity>0
      union all
      -- FOUNDER PACK: premium resource chest (configurable content, opened server-side)
      select jsonb_build_object('key','resource:'||i.id,'itemId',i.item_code,'instanceId',i.id,
        'itemType','resource_chest','category','chests',
        'name','BAÚ PREMIUM DE RECURSOS','description','Founder Pack · recursos premium',
        'image',null,'rarity','legendary','quantity',i.quantity,'usable',true,'action','open-resource-chest')
      from player_inventory i
      where i.user_id=u and i.item_type='resource_chest' and i.quantity>0
      union all
      -- Tower keys: pure collectibles for now (no action, never consumed)
      select jsonb_build_object('key','tower_key:'||i.item_code,'itemId',i.item_code,'instanceId',i.id,
        'itemType','tower_key','category','keys',
        'name',coalesce(k.name, initcap(replace(i.item_code,'_',' '))),
        'description',coalesce(k.description,''),'image',k.image_url,'rarity',coalesce(k.rarity,'rare'),
        'quantity',i.quantity,'usable',false,'action',null)
      from player_inventory i left join tower_key_catalog k on k.code=i.item_code
      where i.user_id=u and i.item_type='tower_key' and i.quantity>0
      union all
      select jsonb_build_object('key',i.item_type||':'||i.item_code,'itemId',i.item_code,'instanceId',i.id,'itemType',i.item_type,
        'category',case when i.item_type ilike '%fragment%' then 'fragments' else 'other' end,
        'name',initcap(replace(i.item_code,'_',' ')),
        'description',case when i.item_type='fragments' and i.item_code='fragments'
            then v_per_hero || ' = RANDOM HERO' else initcap(replace(i.item_type,'_',' ')) end,
        'image',null,'rarity',null,
        'quantity',i.quantity,
        'usable', i.item_type='fragments' and i.item_code='fragments' and i.quantity >= v_per_hero,
        'action', case when i.item_type='fragments' and i.item_code='fragments' then 'summon-hero' end,
        'costPerUse', case when i.item_type='fragments' and i.item_code='fragments' then v_per_hero end,
        'summonRates', case when i.item_type='fragments' and i.item_code='fragments' then v_summon->'rates' end)
      from player_inventory i
      where i.user_id=u and i.item_type not in ('hero_chest','exclusive_chest','tower_key','resource_chest') and i.quantity>0
      union all
      select jsonb_build_object('key','egg:'||e.id,'itemId',e.id::text,'instanceId',null,'itemType','egg','category','eggs',
        'name',e.name,'description','Pet Egg','image',e.image_url,
        'rarity',(select k from jsonb_each_text(coalesce(e.rarity_rates,'{}'::jsonb)) as t(k,v) order by (v)::numeric desc limit 1),
        'quantity',pi.quantity,'usable',true,'action','hatch')
      from player_pet_inventory pi join pet_eggs e on e.id=pi.item_id
      where pi.user_id=u and pi.item_type='egg' and pi.quantity>0
      union all
      select jsonb_build_object('key','food:'||f.code,'itemId',f.code,'instanceId',null,'itemType','food','category','food',
        'name',f.name,'description','Pet Food','image',f.icon,'rarity',f.rarity,
        'quantity',pf.quantity,'usable',true,'action','feed')
      from player_pet_food pf join pet_food_items f on f.code=pf.food_code
      where pf.user_id=u and pf.quantity>0
      union all
      select jsonb_build_object('key','universal_fragment','itemId','universal_fragment','instanceId',null,'itemType','universal_fragment',
        'category','fragments','name','Universal Fragment',
        'description', v_frag_cost || ' = HERO FUSION','image',null,'rarity',null,
        'quantity',pi.quantity,'usable',false,'action','view-fusion','costPerUse', v_frag_cost)
      from player_pet_inventory pi
      where pi.user_id=u and pi.item_type='universal_fragment' and pi.item_id is null and pi.quantity>0
      union all
      select jsonb_build_object('key','pet_fragment:'||pp.id,'itemId',pp.pet_id::text,'instanceId',pp.id,'itemType','pet_fragment',
        'category','fragments','name',p.name||' Fragment','description','Pet Fragment','image',p.image_baby_url,'rarity',pp.rarity,
        'quantity',pp.fragments,'usable',false,'action',null)
      from player_pets pp join pets p on p.id=pp.pet_id
      where pp.user_id=u and pp.fragments>0 and not coalesce(pp.market_locked,false)
      union all
      select jsonb_build_object('key','equipment:'||pe.id,'itemId',t.code,'instanceId',pe.id,'itemType','equipment',
        'category','equipment','name',t.name,'description',t.description,'image',t.image_url,'rarity',t.rarity,
        'quantity',1,'usable',false,'action',null,
        'slot',t.slot,'kind',t.kind,'heroClass',t.hero_class,
        'bonusAttack',t.bonus_attack,'bonusDefense',t.bonus_defense,'bonusHp',t.bonus_hp,'power',t.power,
        'equipped',pe.hero_id is not null,'equippedHeroId',pe.hero_id,'equippedHeroName',hero.name,
        'listed',false)
      from player_equipment pe
      join equipment_templates t on t.id=pe.template_id
      left join player_heroes hero on hero.id=pe.hero_id
      where pe.user_id=u and not coalesce(pe.market_locked,false)
    ) s
  );

  return jsonb_build_object('chests',v_chests,'eggs',v_eggs,'items',v_items);
end $function$;