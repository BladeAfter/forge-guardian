CREATE OR REPLACE FUNCTION public.pvp_generate_bot(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
    -- PvP rule: never repeat the same hero template inside a bot team
    select hero_key,name,image,coalesce(battle_image,image) battle_image,hero_class,rarity into h
      from hero_catalog where enabled and not is_nft_exclusive and normalize_hero_rarity(rarity)=v_rar
        and not (lower(hero_key) = any(v_used)) order by random() limit 1;
    if h.hero_key is null then
      select hero_key,name,image,coalesce(battle_image,image) battle_image,hero_class,rarity into h
        from hero_catalog where enabled and not is_nft_exclusive and not (lower(hero_key) = any(v_used)) order by random() limit 1;
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

CREATE OR REPLACE FUNCTION public.search_pvp_opponents(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u game_players%rowtype;power int;power_pct numeric;trophy_range int;result jsonb;step int;
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
  power:=pvp_team_power(u.id,'attack');
  if power=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;
  if public.pvp_team_has_duplicates(u.id,'attack') then raise exception 'PVP_DUPLICATE_HERO_TEAM';end if;
  for step in 1..2 loop
    power_pct:=case step when 1 then .10 else .20 end;
    trophy_range:=case step when 1 then 200 else 400 end;
    select coalesce(jsonb_agg(to_jsonb(row_data)-'repeat_rank'-'power_gap'-'random_key' order by row_data.repeat_rank,row_data.power_gap,row_data.random_key),'[]') into result from(
      select p.id "userId",
        coalesce(nullif(trim(coalesce(p.display_name,'')),''),nullif(p.username,''),'Jogador')name,
        p.username,
        p.avatar_url "avatarUrl",
        p.pvp_trophies trophies,
        pvp_league(p.pvp_trophies)league,
        pvp_team_power(p.id,'defense') "teamPower",
        p.pvp_wins wins,
        public.pvp_dedupe_team(pvp_team_json(p.id,'defense')) "defenseTeam",
        false "isBot",
        case when i.last_shown_at>now()-interval '24 hours' then 1 else 0 end repeat_rank,
        abs(pvp_team_power(p.id,'defense')-power)power_gap,
        hashtextextended(p.id::text||clock_timestamp()::text,0)random_key
      from game_players p
      left join pvp_opponent_impressions i on i.user_id=u.id and i.opponent_id=p.id
      where p.id<>u.id and not p.pvp_banned and not coalesce(p.banned,false)
        and p.telegram_id is not null and p.telegram_id>0
        and coalesce(nullif(trim(coalesce(p.display_name,'')),''),nullif(p.username,'')) is not null
        and pvp_team_power(p.id,'defense')>0
        and abs(pvp_team_power(p.id,'defense')-power)<=greatest(1,power*power_pct)
        and abs(p.pvp_trophies-u.pvp_trophies)<=trophy_range
      order by repeat_rank,power_gap,random_key limit 3)row_data;
    if jsonb_array_length(result)>0 then
      insert into pvp_opponent_impressions(user_id,opponent_id,last_shown_at)
      select u.id,(x->>'userId')::uuid,now() from jsonb_array_elements(result)x
      on conflict(user_id,opponent_id)do update set last_shown_at=now(),shown_count=pvp_opponent_impressions.shown_count+1;
      return jsonb_build_object('opponents',result,'source','real');
    end if;
  end loop;
  return jsonb_build_object('opponents',jsonb_build_array(pvp_generate_bot(u.id)),'source','ai');
end$function$;