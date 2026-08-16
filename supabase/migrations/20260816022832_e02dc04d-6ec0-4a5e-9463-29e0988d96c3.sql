-- 1) Non-overlapping rarity bands (higher rarity is always stronger)
CREATE OR REPLACE FUNCTION public.hero_stat_ranges(p_rarity text)
 RETURNS TABLE(min_atk numeric, max_atk numeric, min_hp numeric, max_hp numeric, min_ag numeric, max_ag numeric, min_hg numeric, max_hg numeric)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select s.min_atk,s.max_atk,s.min_hp,s.max_hp,s.min_ag,s.max_ag,s.min_hg,s.max_hg from (values
    ('common',100,170,1000,1700,.025,.030,.040,.045),
    ('uncommon',180,260,1800,2600,.028,.033,.042,.048),
    ('rare',270,380,2700,3800,.031,.036,.045,.051),
    ('epic',390,520,3900,5200,.034,.039,.048,.054),
    ('legendary',530,700,5300,7000,.037,.042,.051,.057),
    ('mythic',720,950,7200,9500,.040,.045,.054,.060),
    ('ancestral',980,1300,9800,13000,.043,.048,.057,.063),
    ('nft_exclusive',1350,1800,13500,18000,.04515,.05040,.05985,.06615)
  ) s(rarity,min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg)
  where s.rarity = public.normalize_hero_rarity(p_rarity);
$function$;

-- 2) Clamp class multipliers strictly inside the rarity band and force
--    regeneration whenever the stored value falls outside it.
CREATE OR REPLACE FUNCTION public.ensure_pvp_hero_stats()
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
    if c.base_atk is not null and c.base_atk >= min_atk then min_atk:=c.base_atk*0.97; max_atk:=c.base_atk*1.03; end if;
    if c.base_hp is not null and c.base_hp >= min_hp then min_hp:=c.base_hp*0.97; max_hp:=c.base_hp*1.03; end if;
    if coalesce(c.growth_multiplier,1) <> 1 then
      min_ag:=min_ag*c.growth_multiplier; max_ag:=max_ag*c.growth_multiplier;
      min_hg:=min_hg*c.growth_multiplier; max_hg:=max_hg*c.growth_multiplier;
    end if;
  end if;
  -- Rarity band is authoritative: stats outside it are always regenerated,
  -- and the class multiplier can never push a hero into another band.
  if new.base_atk is null or new.base_atk < min_atk or new.base_atk > max_atk then
    new.base_atk:=least(max_atk, greatest(min_atk, round((min_atk+pvp_stat_unit(seed||':atk')*(max_atk-min_atk))*atk_mult)));
  end if;
  if new.base_hp is null or new.base_hp < min_hp or new.base_hp > max_hp then
    new.base_hp:=least(max_hp, greatest(min_hp, round((min_hp+pvp_stat_unit(seed||':hp')*(max_hp-min_hp))*hp_mult)));
  end if;
  if new.attack_growth is null or new.attack_growth <= 0 or new.attack_growth < min_ag or new.attack_growth > max_ag then
    new.attack_growth:=round(min_ag+pvp_stat_unit(seed||':ag')*(max_ag-min_ag),5);end if;
  if new.hp_growth is null or new.hp_growth <= 0 or new.hp_growth < min_hg or new.hp_growth > max_hg then
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
  if new.is_nft_exclusive then new.tradable:=false; end if;
  return new;
end $function$;

-- 3) Rebuild every existing hero inside its new rarity band.
UPDATE public.player_heroes SET base_atk = NULL, base_hp = NULL;

-- 4) Keep the boss combat rows in sync with the rebuilt stats.
UPDATE public.hero_combat_state s
   SET base_atk = h.base_atk,
       final_atk = h.final_atk,
       base_hp = h.base_hp::int,
       max_hp = h.final_hp::int,
       current_hp = LEAST(GREATEST(s.current_hp,0), h.final_hp::int),
       updated_at = now()
  FROM public.player_heroes h
 WHERE h.id = s.hero_id;