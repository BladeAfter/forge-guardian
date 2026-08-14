-- Pets/fragments listed on the market leave the normal inventory views.
CREATE OR REPLACE FUNCTION public.get_pet_dashboard(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'activePet', (SELECT player_pet_json(id) FROM player_pets WHERE user_id = u AND is_active AND NOT coalesce(market_locked,false) LIMIT 1),
    'playerPets', coalesce((SELECT jsonb_agg(player_pet_json(t.id))
        FROM (SELECT id FROM player_pets WHERE user_id = u AND NOT coalesce(market_locked,false) ORDER BY is_active DESC, level DESC, created_at) t), '[]'::jsonb),
    'catalog', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'slug', p.slug,
          'species', CASE WHEN d.found THEN p.species ELSE '???' END,
          'category', p.category,
          'description', CASE WHEN d.found THEN coalesce(p.description,'') ELSE '' END,
          'basePassives', CASE WHEN d.found THEN p.base_passives ELSE '{}'::jsonb END,
          'activeSkill', CASE WHEN d.found THEN p.active_skill ELSE NULL END,
          'rarity', p.rarity, 'availabilityType', p.availability_type,
          'hideName', p.hide_name_until_discovered,
          'images', jsonb_build_object('baby',p.image_baby_url,'young',p.image_young_url,'adult',p.image_adult_url,'ancestral',p.image_ancestral_url),
          'discovered', d.found,
          'bestRarity', (SELECT pp.rarity FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id AND NOT coalesce(pp.market_locked,false) ORDER BY pet_rarity_order(pp.rarity) DESC LIMIT 1),
          'bestLevel', (SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id AND NOT coalesce(pp.market_locked,false)),
          'sources', coalesce((SELECT jsonb_agg(DISTINCT e.name) FROM reward_pet_pool rp
                JOIN pet_eggs e ON e.id::text = rp.source_key
               WHERE rp.source_type='EGG' AND rp.pet_id = p.id AND rp.enabled AND e.is_enabled),
             coalesce((SELECT jsonb_agg(e.name ORDER BY e.name) FROM pet_eggs e
               WHERE e.is_enabled AND p.availability_type='NORMAL'
                 AND NOT EXISTS (SELECT 1 FROM reward_pet_pool rp2 WHERE rp2.source_type='EGG' AND rp2.source_key=e.id::text)
                 AND (e.allowed_pet_categories IS NULL OR e.allowed_pet_categories ? p.category)), '[]'::jsonb))
        ) ORDER BY p.name)
        FROM pets p
        CROSS JOIN LATERAL (SELECT (exists(SELECT 1 FROM pet_discoveries pd WHERE pd.user_id = u AND pd.pet_id = p.id)
              OR exists(SELECT 1 FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id)) AS found) d
        WHERE p.show_in_catalog AND (p.is_enabled OR d.found)), '[]'::jsonb),
    'foods', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'code', f.code, 'name', f.name, 'rarity', f.rarity, 'xpValue', f.xp_value, 'icon', f.icon, 'priceFc', f.price_fc,
          'quantity', coalesce((SELECT quantity FROM player_pet_food pf WHERE pf.user_id = u AND pf.food_code = f.code), 0)
        ) ORDER BY f.sort_order) FROM pet_food_items f WHERE f.enabled), '[]'::jsonb),
    'fragments', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'playerPetId', pp.id, 'petName', p.name, 'image', p.image_baby_url, 'rarity', pp.rarity, 'quantity', pp.fragments
        ) ORDER BY pp.fragments DESC) FROM player_pets pp JOIN pets p ON p.id = pp.pet_id
        WHERE pp.user_id = u AND NOT coalesce(pp.market_locked,false)), '[]'::jsonb),
    'inventory', jsonb_build_object(
        'food', coalesce((SELECT sum(quantity) FROM player_pet_food WHERE user_id = u), 0),
        'universalFragments', coalesce((SELECT quantity FROM player_pet_inventory WHERE user_id = u AND item_type = 'universal_fragment' AND item_id IS NULL), 0)),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', h.id, 'eggName', e.name, 'petName', p.name, 'rarity', h.result_rarity,
          'duplicateFragments', h.duplicate_fragments, 'createdAt', h.created_at
        ) ORDER BY h.created_at DESC) FROM pet_hatch_history h
        JOIN pet_eggs e ON e.id = h.egg_id LEFT JOIN pets p ON p.id = h.result_pet_id
        WHERE h.user_id = u), '[]'::jsonb),
    'evolutionTiers', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'tier', t.tier, 'label', t.label, 'requiredLevel', t.required_level, 'fcCost', t.fc_cost,
          'fragmentCost', t.fragment_cost, 'newBuffChance', round(t.new_buff_chance*100)
        ) ORDER BY t.tier) FROM pet_evolution_tiers t WHERE t.enabled), '[]'::jsonb),
    'rarities', coalesce((SELECT jsonb_agg(jsonb_build_object('rarity',c.rarity,'label',c.label,'order',c.sort_order,
          'primary',c.color_primary,'secondary',c.color_secondary,'glow',c.glow) ORDER BY c.sort_order)
        FROM pet_rarity_config c WHERE c.enabled), '[]'::jsonb),
    'bonuses', get_pet_bonuses(u),
    'balance', coalesce((SELECT forge_coins FROM game_players WHERE id = u), 0)
  );
END $function$;

-- Backpack: listed equipment and fragments of listed pets disappear from the inventory.
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
      select jsonb_build_object('key',i.item_type||':'||i.item_code,'itemId',i.item_code,'instanceId',i.id,'itemType',i.item_type,
        'category',case when i.item_type ilike '%fragment%' then 'fragments' else 'other' end,
        'name',initcap(replace(i.item_code,'_',' ')),'description',initcap(replace(i.item_type,'_',' ')),'image',null,'rarity',null,
        'quantity',i.quantity,'usable',false,'action',null)
      from player_inventory i
      where i.user_id=u and i.item_type<>'hero_chest' and i.quantity>0
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
        'category','fragments','name','Universal Fragment','description','Universal Fragment','image',null,'rarity',null,
        'quantity',pi.quantity,'usable',false,'action',null)
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

-- Hero equipment panel: listed equipment is not selectable/visible.
CREATE OR REPLACE FUNCTION public.hero_equipment_json(p_telegram_id bigint, p_hero_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; hero player_heroes;
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into hero from player_heroes where id=p_hero_id and user_id=u;
  if hero.id is null then raise exception 'HERO_NOT_OWNED'; end if;

  return jsonb_build_object(
    'heroId', hero.id,
    'archetype', hero.archetype,
    'stats', jsonb_build_object(
      'atk', round(hero.final_atk), 'hp', round(hero.final_hp),
      'def', round(coalesce(hero.defense,0)), 'spd', round(coalesce(hero.speed,0)),
      'crit', coalesce(hero.crit_rate,0),
      'power', round(hero.final_atk*2.2+hero.final_hp*.18+hero.level*25),
      'baseAtk', round(hero.final_atk-coalesce(hero.equip_atk,0)),
      'baseHp', round(hero.final_hp-coalesce(hero.equip_hp,0)),
      'baseDef', round(coalesce(hero.defense,0)-coalesce(hero.equip_def,0)),
      'basePower', round((hero.final_atk-coalesce(hero.equip_atk,0))*2.2+(hero.final_hp-coalesce(hero.equip_hp,0))*.18+hero.level*25),
      'equipAtk', coalesce(hero.equip_atk,0), 'equipHp', coalesce(hero.equip_hp,0), 'equipDef', coalesce(hero.equip_def,0)
    ),
    'equipped', coalesce((select jsonb_object_agg(t.slot, jsonb_build_object(
        'instanceId', pe.id, 'code', t.code, 'name', t.name, 'slot', t.slot, 'kind', t.kind,
        'rarity', t.rarity, 'image', t.image_url, 'level', coalesce(pe.level,1),
        'heroClass', t.hero_class, 'bonusAttack', t.bonus_attack, 'bonusDefense', t.bonus_defense, 'bonusHp', t.bonus_hp
      )) from player_equipment pe join equipment_templates t on t.id=pe.template_id
      where pe.hero_id=hero.id and pe.user_id=u), '{}'::jsonb),
    'available', coalesce((select jsonb_agg(jsonb_build_object(
        'instanceId', pe.id, 'code', t.code, 'name', t.name, 'slot', t.slot, 'kind', t.kind,
        'rarity', t.rarity, 'image', t.image_url, 'level', coalesce(pe.level,1),
        'heroClass', t.hero_class, 'bonusAttack', t.bonus_attack, 'bonusDefense', t.bonus_defense, 'bonusHp', t.bonus_hp,
        'listed', false,
        'classOk', equipment_class_ok(t.hero_class, hero.archetype)
      ) order by t.slot, t.rarity, t.name)
      from player_equipment pe join equipment_templates t on t.id=pe.template_id
      where pe.user_id=u and pe.hero_id is null and coalesce(t.is_active,true)
        and not coalesce(pe.market_locked,false)), '[]'::jsonb)
  );
end $function$;
