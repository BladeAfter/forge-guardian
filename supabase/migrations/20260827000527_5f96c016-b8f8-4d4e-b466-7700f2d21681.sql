-- CELESTIAL CLASS (nova raridade/classe exclusiva)
CREATE OR REPLACE FUNCTION public.normalize_hero_rarity(value text)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$
  select case lower(trim(coalesce(value,'common')))
    when 'common' then 'common' when 'comum' then 'common' when 'uncommon' then 'uncommon' when 'incomum' then 'uncommon'
    when 'rare' then 'rare' when 'raro' then 'rare' when 'rara' then 'rare' when 'epic' then 'epic' when 'épico' then 'epic'
    when 'epico' then 'epic' when 'épica' then 'epic' when 'epica' then 'epic' when 'legendary' then 'legendary'
    when 'lendário' then 'legendary' when 'lendario' then 'legendary' when 'lendária' then 'legendary' when 'lendaria' then 'legendary'
    when 'mythic' then 'mythic' when 'mítico' then 'mythic' when 'mitico' then 'mythic' when 'mítica' then 'mythic' when 'mitica' then 'mythic'
    when 'ancestral' then 'ancestral' when 'ancient' then 'ancestral'
    when 'celestial' then 'celestial' when 'celeste' then 'celestial'
    when 'nft_exclusive' then 'nft_exclusive' when 'nft-exclusive' then 'nft_exclusive' when 'nft exclusive' then 'nft_exclusive'
    when 'nft' then 'nft_exclusive'
    else 'common' end
$function$;

CREATE OR REPLACE FUNCTION public.hero_stat_ranges(p_rarity text)
 RETURNS TABLE(min_atk numeric, max_atk numeric, min_hp numeric, max_hp numeric, min_ag numeric, max_ag numeric, min_hg numeric, max_hg numeric)
 LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$
  select s.min_atk,s.max_atk,s.min_hp,s.max_hp,s.min_ag,s.max_ag,s.min_hg,s.max_hg from (values
    ('common',100,170,1000,1700,.025,.030,.040,.045),
    ('uncommon',180,260,1800,2600,.028,.033,.042,.048),
    ('rare',270,380,2700,3800,.031,.036,.045,.051),
    ('epic',390,520,3900,5200,.034,.039,.048,.054),
    ('legendary',530,700,5300,7000,.037,.042,.051,.057),
    ('mythic',720,950,7200,9500,.040,.045,.054,.060),
    ('ancestral',980,1300,9800,13000,.043,.048,.057,.063),
    ('nft_exclusive',1350,1800,13500,18000,.04515,.05040,.05985,.06615),
    ('celestial',15000,16500,15000,16500,.05000,.05500,.06600,.07200)
  ) s(rarity,min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg)
  where s.rarity = public.normalize_hero_rarity(p_rarity);
$function$;

-- Celestial nunca perde stats: base do catálogo é lei, apenas nível/fusão/equipamento somam
CREATE OR REPLACE FUNCTION public.ensure_pvp_hero_stats()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
declare r text;seed text;min_atk numeric;max_atk numeric;min_hp numeric;max_hp numeric;min_ag numeric;max_ag numeric;min_hg numeric;max_hg numeric;
  atk_mult numeric:=1;hp_mult numeric:=1;fuse numeric:=1;kinds text[]:=array['warrior','assassin','tank','mage','archer','support'];
  nft boolean;c public.hero_catalog;m record;def_mult numeric:=1;spd_bonus numeric:=0;crit_bonus numeric:=0;skl_mult numeric:=1;
begin
  r:=normalize_hero_rarity(new.rarity);
  new.rarity:=r;
  nft:=(r='nft_exclusive') or (coalesce(new.is_nft_exclusive,false) and r<>'celestial');
  if nft then new.is_nft_exclusive:=true; r:='nft_exclusive'; new.rarity:='nft_exclusive'; end if;
  new.hero_template_id:=coalesce(new.hero_template_id,new.hero_key,new.name);
  seed:=coalesce(new.stats_seed,new.id::text||':'||new.hero_template_id||':'||new.user_id::text||':'||new.created_at::text);
  new.stats_seed:=seed;
  select * into c from hero_catalog where hero_key=new.hero_key;
  if c.hero_class is not null and array_position(kinds,c.hero_class) is not null then
    new.archetype:=c.hero_class;
  end if;
  new.archetype:=coalesce(nullif(new.archetype,''),kinds[1+(abs(hashtextextended(seed||':kind',0))%6)::int]);
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
  -- Celestial e heróis de stats fixos ignoram completamente as faixas de raridade:
  -- os valores do catálogo são lei (sem redução de ATK/HP ao entrar no jogo).
  if (coalesce(c.fixed_base_stats,false) or r='celestial') and c.base_atk is not null and c.base_hp is not null then
    min_atk:=c.base_atk; max_atk:=c.base_atk; min_hp:=c.base_hp; max_hp:=c.base_hp;
    new.base_atk:=c.base_atk; new.base_hp:=c.base_hp;
    atk_mult:=1; hp_mult:=1;
  end if;
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

-- Bots de PvP nunca usam heróis Celestial
CREATE OR REPLACE FUNCTION public.pvp_generate_bot(p_user uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  u game_players%rowtype; v_power int; v_slots int; v_league text; band jsonb;
  v_streak int:=0; rec record; v_target numeric; v_share numeric; v_team jsonb:='[]'::jsonb;
  v_i int; v_rar text; r record; h record; v_k numeric; v_atk numeric; v_hp numeric; v_lvl int;
  v_hero_power numeric; v_total numeric:=0; v_name text; v_color text; v_strategy text; bot_id uuid;
  v_used text[]:='{}';
  first_names text[]:=array['Alex','Victor','Kai','Luna','Mika','Raven','Leo','Nova','Dmitri','Arthur','Iris','Sora','Elias','Nyx','Rex','Zara','Milo','Vera','Orion','Kira','Bruno','Talia','Enzo','Freya','Kenji','Lyra','Otto','Sasha','Tarek','Yuna','Caio','Dante','Elza','Gunnar','Hana','Ivan','Jade','Kaya','Lucca','Maya'];
  suffixes text[]:=array['','','','X','7','99','Prime','Zero','Storm','Wolf','Ash','Nyte','Vex','Rider','Blaze','Iron','Shade','Fang','Kron','Sol'];
  colors text[]:=array['#e17076','#7bc862','#65aadd','#a695e7','#ee7aae','#6ec9cb','#faa774','#d97ad9','#8f9ff0','#c9a227'];
begin
  select * into u from game_players where id=p_user;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  v_power:=pvp_team_power(u.id,'attack');
  if v_power<=0 then raise exception 'ATTACK_TEAM_EMPTY'; end if;
  v_slots:=greatest(1,least(5,(select count(*) from pvp_team_slots where user_id=u.id and team_type='attack')));
  v_league:=pvp_league(u.pvp_trophies);
  for rec in select (b.winner_id is not null and b.winner_id=b.attacker_id) w from pvp_battles b where b.attacker_id=u.id order by b.created_at desc limit 10 loop
    if rec.w then v_streak:=v_streak+1; else exit; end if;
  end loop;
  band:=pvp_bot_band(v_league,v_streak);
  v_target:=v_power*((band->>'lo')::numeric+random()*((band->>'hi')::numeric-(band->>'lo')::numeric));

  for v_i in 1..v_slots loop
    v_share:=(v_target/v_slots)*(0.9+random()*0.2);
    select s.rarity into v_rar from (
      select r2.rarity, abs(((r2.min_atk+r2.max_atk)/2*2.2+(r2.min_hp+r2.max_hp)/2*0.18+750)-v_share) gap
      from (values ('common'),('uncommon'),('rare'),('epic'),('legendary'),('mythic'),('ancestral')) rr(rarity)
      cross join lateral (select rr.rarity rarity,* from hero_stat_ranges(rr.rarity)) r2
      order by gap limit 1) s;
    v_rar:=coalesce(v_rar,'common');
    select * into r from hero_stat_ranges(v_rar);
    select hero_key,name,image,coalesce(battle_image,image) battle_image,hero_class,rarity into h
      from hero_catalog where enabled and not is_nft_exclusive and normalize_hero_rarity(rarity)=v_rar
        and normalize_hero_rarity(rarity)<>'celestial'
        and not (lower(hero_key) = any(v_used)) order by random() limit 1;
    if h.hero_key is null then
      select hero_key,name,image,coalesce(battle_image,image) battle_image,hero_class,rarity into h
        from hero_catalog where enabled and not is_nft_exclusive
          and normalize_hero_rarity(rarity)<>'celestial'
          and not (lower(hero_key) = any(v_used)) order by random() limit 1;
    end if;
    if h.hero_key is null then
      if v_i > 1 then exit; end if;
      raise exception 'NO_HERO_CATALOG';
    end if;
    v_used:=v_used||lower(h.hero_key);
    v_lvl:=greatest(1,least(60,round(10+random()*40)::int));
    v_atk:=r.min_atk+random()*(r.max_atk-r.min_atk);
    v_hp:=r.min_hp+random()*(r.max_hp-r.min_hp);
    v_k:=greatest(0.5,least(6.0,(v_share-v_lvl*25)/greatest(1,(v_atk*2.2+v_hp*0.18))));
    v_atk:=round(v_atk*v_k); v_hp:=round(v_hp*v_k);
    v_hero_power:=round(v_atk*2.2+v_hp*0.18+v_lvl*25);
    v_total:=v_total+v_hero_power;
    v_team:=v_team||jsonb_build_array(jsonb_build_object(
      'heroId','bot-'||gen_random_uuid()::text,'templateId',lower(h.hero_key),'heroKey',h.hero_key,
      'name',h.name,'imageUrl',h.image,
      'rarity',normalize_hero_rarity(h.rarity),'level',v_lvl,'archetype',h.hero_class,
      'finalAtk',v_atk::int,'finalHp',v_hp::int,'defense',0,'speed',v_lvl,
      'power',v_hero_power::int,'slot',v_i,'isBot',true));
  end loop;

  loop
    v_name:=first_names[1+floor(random()*array_length(first_names,1))::int]||suffixes[1+floor(random()*array_length(suffixes,1))::int];
    exit when not exists(select 1 from pvp_bots where target_user_id=u.id and name=v_name and created_at>now()-interval '2 hours');
  end loop;
  v_color:=colors[1+floor(random()*array_length(colors,1))::int];
  v_strategy:=(array['aggressive','defensive','balanced','finisher','tactical'])[1+floor(random()*5)::int];

  insert into pvp_bots(target_user_id,name,avatar_letter,avatar_color,power,league,trophies,team,strategy)
  values(u.id,v_name,upper(left(v_name,1)),v_color,v_total::int,v_league,
    greatest(0,u.pvp_trophies+(floor(random()*80)::int-40)),v_team,v_strategy)
  returning id into bot_id;

  return jsonb_build_object('userId',bot_id,'name',v_name,'username',null,'avatarUrl',null,
    'avatarLetter',upper(left(v_name,1)),'avatarColor',v_color,'isBot',true,'strategy',v_strategy,
    'trophies',greatest(0,u.pvp_trophies),'league',v_league,'teamPower',v_total::int,
    'wins',greatest(0,floor(random()*80)::int),'defenseTeam',v_team);
end $function$;

-- Catálogo: 10 heróis Celestial (fora da loja, fora do recrutamento, fora de drops)
INSERT INTO public.hero_catalog (hero_key,name,rarity,hero_class,image,base_atk,base_hp,power,base_def,base_speed,crit_rate,skill_power,start_level,max_level,enabled,in_shop,shop_eligible,recruit_eligible,recruit_enabled,reward_pool_eligible,random_drop_eligible,fusion_pool_enabled,is_nft_exclusive,fixed_base_stats,growth_multiplier,drop_weight,stock,sort_order,nft_class_label,description)
VALUES
  ('cel-astrael','Astrael','celestial','warrior','/assets/game/heroes-celestial/astrael.jpg',15230,15890,21000,1430,118,12,7615,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,900,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-seraphion','Seraphion','celestial','support','/assets/game/heroes-celestial/seraphion.jpg',15000,15000,20000,1350,116,12,7500,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,901,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-xypharion','Xypharion','celestial','mage','/assets/game/heroes-celestial/xypharion.jpg',15890,16240,21500,1460,120,13,7945,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,902,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-noctharius','Noctharius','celestial','mage','/assets/game/heroes-celestial/noctharius.jpg',16200,15800,22000,1420,121,13,8100,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,903,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-aetherion','Aetherion','celestial','tank','/assets/game/heroes-celestial/aetherion-celeste.jpg',15680,15320,20950,1500,115,11,7840,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,904,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-lumynarch','Lumynarch','celestial','archer','/assets/game/heroes-celestial/lumynarch.jpg',15400,16100,21200,1440,122,13,7700,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,905,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-solvyros','Solvyros','celestial','warrior','/assets/game/heroes-celestial/solvyros.jpg',15750,15600,21300,1450,118,12,7875,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,906,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-vaelistra','Vaelistra','celestial','mage','/assets/game/heroes-celestial/vaelistra.jpg',16050,15100,21700,1400,120,14,8025,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,907,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-thanarion','Thanarion','celestial','assassin','/assets/game/heroes-celestial/thanarion.jpg',16400,15450,22200,1410,124,15,8200,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,908,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.'),
  ('cel-elyssara','Elyssara','celestial','tank','/assets/game/heroes-celestial/elyssara.jpg',15550,16500,21850,1520,114,11,7775,1,20,true,false,false,false,false,false,false,false,false,true,1,0,0,909,'Celestial','Classe Celestial — atributos divinos imutáveis, apenas crescem com o nível.')
ON CONFLICT (hero_key) DO UPDATE SET
  name=excluded.name, rarity=excluded.rarity, hero_class=excluded.hero_class, image=excluded.image,
  base_atk=excluded.base_atk, base_hp=excluded.base_hp, power=excluded.power, base_def=excluded.base_def,
  base_speed=excluded.base_speed, crit_rate=excluded.crit_rate, skill_power=excluded.skill_power,
  enabled=true, in_shop=false, shop_eligible=false, recruit_eligible=false, recruit_enabled=false,
  reward_pool_eligible=false, random_drop_eligible=false, fusion_pool_enabled=false,
  is_nft_exclusive=false, fixed_base_stats=true, drop_weight=0, sort_order=excluded.sort_order,
  nft_class_label='Celestial', description=excluded.description;