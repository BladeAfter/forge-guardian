CREATE OR REPLACE FUNCTION public.hero_power_value(p_atk numeric, p_hp numeric, p_def numeric, p_level int)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select round(greatest(0,coalesce(p_atk,0))*2.2 + greatest(0,coalesce(p_hp,0))*0.18 + greatest(0,coalesce(p_def,0))*1.2 + greatest(1,coalesce(p_level,1))*25)
$$;
REVOKE ALL ON FUNCTION public.hero_power_value(numeric,numeric,numeric,int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_power_value(numeric,numeric,numeric,int) TO service_role;

CREATE OR REPLACE FUNCTION public.pvp_hero_json(h player_heroes)
 RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'heroId',h.id,'templateId',public.pvp_hero_template_key(h),'heroKey',h.hero_key,
    'name',h.name,'imageUrl',h.image,'rarity',normalize_hero_rarity(h.rarity),'level',h.level,
    'archetype',h.archetype,'finalAtk',h.final_atk,'finalHp',h.final_hp,
    'defense',round(coalesce(h.defense,0)),'speed',coalesce(h.speed,h.level),
    'power',public.hero_power_value(h.final_atk,h.final_hp,coalesce(h.defense,0),h.level),
    'locked',coalesce(h.locked,false),'marketLocked',coalesce(h.market_locked,false),
    'blockReason',public.pvp_hero_block_reason(h)
  )
$function$;

CREATE OR REPLACE FUNCTION public.pvp_team_power(p_user uuid, p_type text)
 RETURNS integer LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$select coalesce(sum(public.hero_power_value(h.final_atk,h.final_hp,coalesce(h.defense,0),h.level)),0)::int from pvp_team_slots s join player_heroes h on h.id=s.hero_id where s.user_id=p_user and s.team_type=p_type$function$;

CREATE OR REPLACE FUNCTION public.hero_equipment_json(p_telegram_id bigint, p_hero_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
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
      'power', public.hero_power_value(hero.final_atk, hero.final_hp, coalesce(hero.defense,0), hero.level),
      'baseAtk', round(hero.final_atk-coalesce(hero.equip_atk,0)),
      'baseHp', round(hero.final_hp-coalesce(hero.equip_hp,0)),
      'baseDef', round(coalesce(hero.defense,0)-coalesce(hero.equip_def,0)),
      'basePower', public.hero_power_value(hero.final_atk-coalesce(hero.equip_atk,0), hero.final_hp-coalesce(hero.equip_hp,0), coalesce(hero.defense,0)-coalesce(hero.equip_def,0), hero.level),
      'equipAtk', coalesce(hero.equip_atk,0), 'equipHp', coalesce(hero.equip_hp,0), 'equipDef', coalesce(hero.equip_def,0)
    ),
    'equipped', coalesce((select jsonb_object_agg(t.slot, jsonb_build_object(
        'instanceId', pe.id, 'code', t.code, 'name', t.name, 'slot', t.slot, 'kind', t.kind,
        'rarity', t.rarity, 'image', t.image_url, 'level', coalesce(pe.level,1),
        'heroClass', t.hero_class, 'bonusAttack', t.bonus_attack, 'bonusDefense', t.bonus_defense, 'bonusHp', t.bonus_hp,
        'isNft', coalesce(t.is_nft,false),
        'serial', (select ne.nft_serial from nft_equipment ne where ne.player_equipment_id=pe.id),
        'tradable', not coalesce(pe.locked,false)
      )) from player_equipment pe join equipment_templates t on t.id=pe.template_id
      where pe.hero_id=hero.id and pe.user_id=u), '{}'::jsonb),
    'available', coalesce((select jsonb_agg(jsonb_build_object(
        'instanceId', pe.id, 'code', t.code, 'name', t.name, 'slot', t.slot, 'kind', t.kind,
        'rarity', t.rarity, 'image', t.image_url, 'level', coalesce(pe.level,1),
        'heroClass', t.hero_class, 'bonusAttack', t.bonus_attack, 'bonusDefense', t.bonus_defense, 'bonusHp', t.bonus_hp,
        'listed', false,
        'isNft', coalesce(t.is_nft,false),
        'serial', (select ne.nft_serial from nft_equipment ne where ne.player_equipment_id=pe.id),
        'tradable', not coalesce(pe.locked,false),
        'classOk', equipment_class_ok(t.hero_class, hero.archetype)
      ) order by coalesce(t.is_nft,false) desc, t.slot, t.rarity, t.name)
      from player_equipment pe join equipment_templates t on t.id=pe.template_id
      where pe.user_id=u and pe.hero_id is null and coalesce(t.is_active,true)
        and not coalesce(pe.market_locked,false)), '[]'::jsonb)
  );
end $function$;