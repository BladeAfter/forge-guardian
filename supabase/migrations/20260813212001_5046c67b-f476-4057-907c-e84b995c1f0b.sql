alter table public.player_heroes
  add column if not exists equip_atk numeric not null default 0,
  add column if not exists equip_def numeric not null default 0,
  add column if not exists equip_hp numeric not null default 0;

create or replace function public.ensure_pvp_hero_stats()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare r text;seed text;min_atk numeric;max_atk numeric;min_hp numeric;max_hp numeric;min_ag numeric;max_ag numeric;min_hg numeric;max_hg numeric;
  atk_mult numeric:=1;hp_mult numeric:=1;fuse numeric:=1;kinds text[]:=array['warrior','assassin','tank','mage','archer','support'];
  nft boolean;c public.hero_catalog;m record;def_mult numeric:=1;spd_bonus numeric:=0;crit_bonus numeric:=0;skl_mult numeric:=1;
begin
  r:=normalize_hero_rarity(new.rarity);
  new.rarity:=r;
  nft:=(r='nft_exclusive') or coalesce(new.is_nft_exclusive,false);
  if nft then new.is_nft_exclusive:=true; r:='nft_exclusive'; new.rarity:='nft_exclusive'; end if;
  new.hero_template_id:=coalesce(new.hero_template_id,new.hero_key,new.name);
  seed:=coalesce(new.stats_seed,new.id::text||':'||new.hero_template_id||':'||new.user_id::text||':'||new.created_at::text);
  new.stats_seed:=seed;
  if nft then
    select * into c from hero_catalog where hero_key=new.hero_key;
    new.archetype:=coalesce(nullif(new.archetype,''),c.hero_class,'warrior');
  end if;
  new.archetype:=coalesce(new.archetype,kinds[1+(abs(hashtextextended(seed||':kind',0))%6)::int]);
  if array_position(kinds,new.archetype) is null then new.archetype:='warrior'; end if;
  select g.min_atk,g.max_atk,g.min_hp,g.max_hp,g.min_ag,g.max_ag,g.min_hg,g.max_hg
    into min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg
    from hero_stat_ranges(r) g;
  case new.archetype
    when 'warrior' then hp_mult:=1.15;
    when 'assassin' then atk_mult:=1.15;hp_mult:=.9;
    when 'tank' then atk_mult:=.85;hp_mult:=1.3;
    when 'mage' then atk_mult:=1.2;hp_mult:=.85;
    when 'archer' then atk_mult:=1.1;
    when 'support' then atk_mult:=.9;hp_mult:=1.1;
    else new.archetype:='warrior';hp_mult:=1.15;
  end case;
  if nft then
    select * into m from hero_nft_class_mult(new.archetype);
    atk_mult:=atk_mult*coalesce(m.atk_mult,1); hp_mult:=hp_mult*coalesce(m.hp_mult,1);
    def_mult:=coalesce(m.def_mult,1); spd_bonus:=coalesce(m.speed_bonus,0);
    crit_bonus:=coalesce(m.crit_bonus,0); skl_mult:=coalesce(m.skill_mult,1);
    if c.base_atk is not null then min_atk:=c.base_atk*0.97; max_atk:=c.base_atk*1.03; end if;
    if c.base_hp is not null then min_hp:=c.base_hp*0.97; max_hp:=c.base_hp*1.03; end if;
    if coalesce(c.growth_multiplier,1) <> 1 then
      min_ag:=min_ag*c.growth_multiplier; max_ag:=max_ag*c.growth_multiplier;
      min_hg:=min_hg*c.growth_multiplier; max_hg:=max_hg*c.growth_multiplier;
    end if;
  end if;
  if new.base_atk is null or new.base_atk < min_atk then
    new.base_atk:=least(max_atk*atk_mult, greatest(min_atk, round((min_atk+pvp_stat_unit(seed||':atk')*(max_atk-min_atk))*atk_mult)));
  end if;
  if new.base_hp is null or new.base_hp < min_hp then
    new.base_hp:=least(max_hp*hp_mult, greatest(min_hp, round((min_hp+pvp_stat_unit(seed||':hp')*(max_hp-min_hp))*hp_mult)));
  end if;
  if new.attack_growth is null or new.attack_growth <= 0 or (nft and new.attack_growth < min_ag) then
    new.attack_growth:=round(min_ag+pvp_stat_unit(seed||':ag')*(max_ag-min_ag),5);end if;
  if new.hp_growth is null or new.hp_growth <= 0 or (nft and new.hp_growth < min_hg) then
    new.hp_growth:=round(min_hg+pvp_stat_unit(seed||':hg')*(max_hg-min_hg),5);end if;
  new.level:=greatest(1,coalesce(new.level,1));
  new.fusion_level:=greatest(0,coalesce(new.fusion_level,0));
  fuse:=hero_fusion_multiplier(new.fusion_level);
  new.equip_atk:=greatest(0,coalesce(new.equip_atk,0));
  new.equip_def:=greatest(0,coalesce(new.equip_def,0));
  new.equip_hp:=greatest(0,coalesce(new.equip_hp,0));
  new.final_atk:=greatest(1,round((new.base_atk+coalesce(new.bonus_atk,0))*power(1+new.attack_growth,new.level-1)*fuse)+new.equip_atk);
  new.final_hp:=greatest(1,round((new.base_hp+coalesce(new.bonus_hp,0))*power(1+new.hp_growth,new.level-1)*fuse)+new.equip_hp);
  new.defense:=greatest(1,round(coalesce(c.base_def,(new.final_hp-new.equip_hp)*0.09)*def_mult)+new.equip_def);
  new.speed:=greatest(1,round(coalesce(c.base_speed,90)+new.level+spd_bonus));
  new.crit_rate:=greatest(0,round(coalesce(c.crit_rate,5)+crit_bonus,2));
  new.skill_power:=greatest(1,round(coalesce(c.skill_power,(new.final_atk-new.equip_atk)*0.5)*skl_mult));
  new.stats_generated_at:=coalesce(new.stats_generated_at,now());
  if new.is_nft_exclusive then new.tradable:=false; new.market_locked:=true; new.locked:=true; end if;
  return new;
end $function$;

-- Recomputes the aggregated equipment bonuses of one hero and refreshes its final stats.
create or replace function public.hero_recalc_equipment(p_hero uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare a numeric:=0; d numeric:=0; h numeric:=0;
begin
  select coalesce(sum(t.bonus_attack),0), coalesce(sum(t.bonus_defense),0), coalesce(sum(t.bonus_hp),0)
    into a,d,h
    from player_equipment pe join equipment_templates t on t.id=pe.template_id
    where pe.hero_id=p_hero;
  update player_heroes set equip_atk=a, equip_def=d, equip_hp=h, updated_at=now() where id=p_hero;
end $$;

-- True when the template can be used by the hero archetype.
create or replace function public.equipment_class_ok(p_hero_class text, p_archetype text)
returns boolean
language sql
immutable
set search_path to 'public'
as $$
  select p_hero_class is null or p_hero_class = ''
    or lower(p_hero_class) = lower(coalesce(p_archetype,''))
    or (lower(coalesce(p_archetype,'')) = 'assassin' and lower(p_hero_class) = 'warrior');
$$;

create or replace function public.hero_equipment_json(p_telegram_id bigint, p_hero_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $$
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
        'listed', coalesce(pe.market_locked,false),
        'classOk', equipment_class_ok(t.hero_class, hero.archetype)
      ) order by t.slot, t.rarity, t.name)
      from player_equipment pe join equipment_templates t on t.id=pe.template_id
      where pe.user_id=u and pe.hero_id is null and coalesce(t.is_active,true)), '[]'::jsonb)
  );
end $$;

create or replace function public.equip_hero_equipment(p_telegram_id bigint, p_hero_id uuid, p_instance_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare u uuid; hero player_heroes; inst player_equipment; tpl equipment_templates; prev uuid;
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into hero from player_heroes where id=p_hero_id and user_id=u for update;
  if hero.id is null then raise exception 'HERO_NOT_OWNED'; end if;
  select * into inst from player_equipment where id=p_instance_id and user_id=u for update;
  if inst.id is null then raise exception 'EQUIPMENT_NOT_OWNED'; end if;
  if coalesce(inst.market_locked,false) then raise exception 'EQUIPMENT_LISTED'; end if;
  select * into tpl from equipment_templates where id=inst.template_id;
  if tpl.id is null or coalesce(tpl.is_active,true)=false then raise exception 'EQUIPMENT_NOT_AVAILABLE'; end if;
  if tpl.slot not in ('weapon','armor','ring') then raise exception 'INVALID_EQUIPMENT_SLOT'; end if;
  if inst.hero_id is not null and inst.hero_id <> hero.id then raise exception 'EQUIPMENT_IN_USE'; end if;
  if not equipment_class_ok(tpl.hero_class, hero.archetype) then raise exception 'WRONG_CLASS'; end if;

  -- one item per slot: the current item goes back to the inventory
  select pe.id into prev from player_equipment pe join equipment_templates t on t.id=pe.template_id
    where pe.hero_id=hero.id and t.slot=tpl.slot and pe.id<>inst.id limit 1;
  if prev is not null then update player_equipment set hero_id=null, updated_at=now() where id=prev; end if;

  update player_equipment set hero_id=hero.id, updated_at=now() where id=inst.id;
  perform hero_recalc_equipment(hero.id);
  return hero_equipment_json(p_telegram_id, hero.id);
end $$;

create or replace function public.unequip_hero_equipment(p_telegram_id bigint, p_hero_id uuid, p_slot text default null, p_instance_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare u uuid; hero player_heroes; target uuid;
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into hero from player_heroes where id=p_hero_id and user_id=u for update;
  if hero.id is null then raise exception 'HERO_NOT_OWNED'; end if;

  select pe.id into target from player_equipment pe join equipment_templates t on t.id=pe.template_id
    where pe.user_id=u and pe.hero_id=hero.id
      and (p_instance_id is null or pe.id=p_instance_id)
      and (p_slot is null or t.slot=p_slot)
    limit 1;
  if target is null then raise exception 'EQUIPMENT_NOT_EQUIPPED'; end if;

  update player_equipment set hero_id=null, updated_at=now() where id=target;
  perform hero_recalc_equipment(hero.id);
  return hero_equipment_json(p_telegram_id, hero.id);
end $$;

revoke all on function public.hero_recalc_equipment(uuid) from public, anon, authenticated;
revoke all on function public.hero_equipment_json(bigint, uuid) from public, anon, authenticated;
revoke all on function public.equip_hero_equipment(bigint, uuid, uuid) from public, anon, authenticated;
revoke all on function public.unequip_hero_equipment(bigint, uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.hero_recalc_equipment(uuid) to service_role;
grant execute on function public.hero_equipment_json(bigint, uuid) to service_role;
grant execute on function public.equip_hero_equipment(bigint, uuid, uuid) to service_role;
grant execute on function public.unequip_hero_equipment(bigint, uuid, text, uuid) to service_role;

-- Sync heroes that already carry equipment rows.
update public.player_heroes h set equip_atk=x.a, equip_def=x.d, equip_hp=x.h
from (
  select pe.hero_id, coalesce(sum(t.bonus_attack),0) a, coalesce(sum(t.bonus_defense),0) d, coalesce(sum(t.bonus_hp),0) h
  from player_equipment pe join equipment_templates t on t.id=pe.template_id
  where pe.hero_id is not null group by pe.hero_id
) x where x.hero_id=h.id;