CREATE TABLE IF NOT EXISTS public.pvp_bots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id uuid REFERENCES public.game_players(id) ON DELETE CASCADE,
  name text NOT NULL,
  avatar_letter text NOT NULL,
  avatar_color text NOT NULL,
  power integer NOT NULL DEFAULT 0,
  league text NOT NULL DEFAULT 'Bronze V',
  trophies integer NOT NULL DEFAULT 0,
  team jsonb NOT NULL DEFAULT '[]'::jsonb,
  strategy text NOT NULL DEFAULT 'balanced',
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pvp_bots TO service_role;
ALTER TABLE public.pvp_bots ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS pvp_bots_user_idx ON public.pvp_bots(target_user_id, created_at DESC);

ALTER TABLE public.pvp_battles
  ALTER COLUMN defender_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS defender_bot_id uuid REFERENCES public.pvp_bots(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_bot_battle boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.pool_points_from_game_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
begin
  if tg_table_name='pvp_battles' then
    if new.winner_id is not null then perform award_pool_points(new.winner_id,'pvp_win',new.id::text); end if;
  elsif tg_table_name='boss_reward_transactions' then perform award_pool_points(new.user_id,'boss_defeat',new.combat_id::text);
  elsif tg_table_name='daily_calendar_claims' then perform award_pool_points(new.user_id,'daily_login',new.calendar_cycle||':'||new.day);
  end if;
  return new;
end$function$;

CREATE OR REPLACE FUNCTION public.pvp_bot_band(p_league text, p_streak int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $function$
declare lo numeric; hi numeric;
begin
  if p_league ilike 'Lend%' then lo:=.98; hi:=1.05;
  elsif p_league ilike 'Mestre%' then lo:=.97; hi:=1.06;
  elsif p_league ilike 'Diam%' then lo:=.95; hi:=1.08;
  elsif p_league ilike 'Plat%' then lo:=.94; hi:=1.10;
  elsif p_league ilike 'Ouro%' then lo:=.92; hi:=1.12;
  elsif p_league ilike 'Prata%' then lo:=.90; hi:=1.15;
  else lo:=.85; hi:=1.15; end if;
  if coalesce(p_streak,0)>=5 then lo:=greatest(lo,1.05); hi:=greatest(hi,1.10);
  elsif coalesce(p_streak,0)>=3 then lo:=greatest(lo,1.00); hi:=greatest(hi,1.08); end if;
  return jsonb_build_object('lo',lo,'hi',greatest(hi,lo+.02));
end$function$;

CREATE OR REPLACE FUNCTION public.pvp_generate_bot(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare
  u game_players%rowtype; v_power int; v_slots int; v_league text; band jsonb;
  v_streak int:=0; rec record; v_target numeric; v_share numeric; v_team jsonb:='[]'::jsonb;
  v_i int; v_rar text; r record; h record; v_k numeric; v_atk numeric; v_hp numeric; v_lvl int;
  v_hero_power numeric; v_total numeric:=0; v_name text; v_color text; v_strategy text; bot_id uuid;
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
      from hero_catalog where enabled and normalize_hero_rarity(rarity)=v_rar order by random() limit 1;
    if h.hero_key is null then
      select hero_key,name,image,coalesce(battle_image,image) battle_image,hero_class,rarity into h
        from hero_catalog where enabled order by random() limit 1;
    end if;
    if h.hero_key is null then raise exception 'NO_HERO_CATALOG'; end if;
    v_lvl:=greatest(1,least(60,round(10+random()*40)::int));
    v_atk:=r.min_atk+random()*(r.max_atk-r.min_atk);
    v_hp:=r.min_hp+random()*(r.max_hp-r.min_hp);
    v_k:=greatest(0.5,least(6.0,(v_share-v_lvl*25)/greatest(1,(v_atk*2.2+v_hp*0.18))));
    v_atk:=round(v_atk*v_k); v_hp:=round(v_hp*v_k);
    v_hero_power:=round(v_atk*2.2+v_hp*0.18+v_lvl*25);
    v_total:=v_total+v_hero_power;
    v_team:=v_team||jsonb_build_array(jsonb_build_object(
      'heroId','bot-'||gen_random_uuid()::text,'name',h.name,'imageUrl',h.image,
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
end$function$;

CREATE OR REPLACE FUNCTION public.search_pvp_opponents(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u game_players%rowtype;power int;power_pct numeric;trophy_range int;result jsonb;step int;
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
  power:=pvp_team_power(u.id,'attack');
  if power=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;
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
        pvp_team_json(p.id,'defense') "defenseTeam",
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

CREATE OR REPLACE FUNCTION public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare attacker game_players%rowtype;defender game_players%rowtype;bot public.pvp_bots;atk jsonb;def jsonb;sim jsonb;battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
  v_win int; v_loss int; v_cost int; v_reward numeric; v_turns int; v_def_power int; v_mult_atk numeric:=1; v_mult_hp numeric:=1;
begin
 v_win := public.setting_num('pvp_trophy_win',30)::int;
 v_loss := abs(public.setting_num('pvp_trophy_loss',-20)::int);
 v_cost := GREATEST(0, public.setting_num('pvp_ticket_cost',1)::int);
 v_reward := public.setting_num('pvp_win_reward_fc',2500);

 select * into attacker from game_players where telegram_id=p_telegram_id;
 if attacker.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
 if attacker.id=p_opponent_id then raise exception 'INVALID_OPPONENT';end if;
 select * into bot from pvp_bots where id=p_opponent_id;

 if bot.id is null then
   perform 1 from game_players where id in(attacker.id,p_opponent_id) order by id for update;
   select * into attacker from game_players where id=attacker.id;
   select * into defender from game_players where id=p_opponent_id;
   if defender.id is null or defender.pvp_banned or defender.banned then raise exception 'OPPONENT_UNAVAILABLE';end if;
 else
   if bot.target_user_id is distinct from attacker.id then raise exception 'OPPONENT_UNAVAILABLE';end if;
   perform 1 from game_players where id=attacker.id for update;
   select * into attacker from game_players where id=attacker.id;
 end if;

 if attacker.pvp_banned or attacker.banned then raise exception 'PVP_BANNED';end if;
 if attacker.pvp_tickets < v_cost then raise exception 'NO_PVP_TICKETS';end if;

 atk:=pvp_team_json(attacker.id,'attack');
 if jsonb_array_length(atk)=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;

 if bot.id is null then
   if exists(select 1 from pvp_battles where attacker_id=attacker.id and defender_id=defender.id and created_at>clock_timestamp()-interval'3 seconds') then raise exception 'BATTLE_ALREADY_STARTED';end if;
   def:=pvp_team_json(defender.id,'defense');
   v_def_power:=pvp_team_power(defender.id,'defense');
 else
   if bot.used_at is not null then raise exception 'OPPONENT_UNAVAILABLE';end if;
   v_mult_atk:=case bot.strategy when 'aggressive' then 1.08 when 'defensive' then .95 when 'finisher' then 1.05 when 'tactical' then 1.04 else 1 end;
   v_mult_hp:=case bot.strategy when 'aggressive' then .95 when 'defensive' then 1.10 when 'finisher' then .98 when 'tactical' then 1.04 else 1 end;
   select coalesce(jsonb_agg(x||jsonb_build_object(
       'finalAtk',greatest(1,round((x->>'finalAtk')::numeric*v_mult_atk))::int,
       'finalHp',greatest(1,round((x->>'finalHp')::numeric*v_mult_hp))::int)),'[]')
     into def from jsonb_array_elements(bot.team)x;
   if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;
   v_def_power:=bot.power;
   update pvp_bots set used_at=now() where id=bot.id;
 end if;
 if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;

 update game_players set pvp_tickets=greatest(0,pvp_tickets-v_cost) where id=attacker.id;
 seed:=gen_random_uuid()::text;sim:=simulate_pvp_battle(atk,def,seed);
 v_turns := least(50, greatest(1, coalesce(nullif(sim->>'totalTurns','')::int, nullif(sim->>'turns','')::int, jsonb_array_length(coalesce(sim->'battleLog','[]'::jsonb)), 1)));

 if sim->>'winnerSide'='attacker' then
   winner:=attacker.id;result:='attacker_win';change:=v_win;reward:=v_reward;
   update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,forge_coins=forge_coins+reward,updated_at=now() where id=attacker.id;
   if bot.id is null then
     update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now() where id=defender.id;
   end if;
 else
   winner:=case when bot.id is null then defender.id else null end;
   result:='defender_win';change:=-v_loss;reward:=0;
   update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now() where id=attacker.id;
   if bot.id is null then
     update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,updated_at=now() where id=defender.id;
   end if;
 end if;

 insert into pvp_battles(attacker_id,defender_id,defender_bot_id,is_bot_battle,attacker_team_snapshot,defender_team_snapshot,battle_log,winner_id,result,total_turns,attacker_power,defender_power,reward_fc,trophy_change)
 values(attacker.id,case when bot.id is null then defender.id else null end,bot.id,bot.id is not null,atk,def,coalesce(sim->'battleLog','[]'::jsonb),winner,result,v_turns,pvp_team_power(attacker.id,'attack'),v_def_power,reward,change)
 returning id into battle_id;

 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'totalTurns',v_turns,'rewardFc',reward,'trophyChange',change,'isBotBattle',bot.id is not null,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),'attackerState',coalesce(sim->'attackerState','[]'::jsonb),'defenderState',coalesce(sim->'defenderState','[]'::jsonb));
end$function$;

CREATE OR REPLACE FUNCTION public.get_pvp_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u game_players%rowtype;
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
  return jsonb_build_object(
    'userId',u.id,'trophies',u.pvp_trophies,'league',pvp_league(u.pvp_trophies),'tickets',u.pvp_tickets,
    'wins',u.pvp_wins,'losses',u.pvp_losses,
    'ticketShop',public.pvp_ticket_shop_state(u.id),
    'attackTeam',pvp_team_json(u.id,'attack'),'defenseTeam',pvp_team_json(u.id,'defense'),
    'teamPower',pvp_team_power(u.id,'attack'),
    'ownedHeroes',(select coalesce(jsonb_agg(pvp_hero_json(h) order by h.created_at),'[]') from player_heroes h where h.user_id=u.id),
    'history',(select coalesce(jsonb_agg(jsonb_build_object(
        'id',b.id,
        'opponentName',coalesce(nullif(trim(coalesce(o.display_name,'')),''),nullif(o.username,''),bt.name,'Jogador'),
        'isBot',coalesce(b.is_bot_battle,false),
        'result',case when b.winner_id=u.id then 'win' else 'loss' end,
        'turns',b.total_turns,
        'trophyChange',case when b.attacker_id=u.id then b.trophy_change else -b.trophy_change end,
        'rewardFc',case when b.attacker_id=u.id then b.reward_fc else 0 end,
        'createdAt',b.created_at) order by b.created_at desc),'[]')
      from(select * from pvp_battles where attacker_id=u.id or defender_id=u.id order by created_at desc limit 30)b
      left join game_players o on o.id=case when b.attacker_id=u.id then b.defender_id else b.attacker_id end
      left join pvp_bots bt on bt.id=b.defender_bot_id),
    'ranking',(select coalesce(jsonb_agg(x order by x.position),'[]') from(
      select row_number()over(order by pvp_trophies desc,pvp_wins desc)position,id,
        coalesce(nullif(trim(coalesce(display_name,'')),''),nullif(username,''),'Jogador')name,
        username,avatar_url "avatarUrl",pvp_trophies trophies,pvp_league(pvp_trophies)league,pvp_wins wins
      from game_players
      where not pvp_banned and not coalesce(banned,false) and telegram_id is not null and telegram_id>0
        and coalesce(nullif(trim(coalesce(display_name,'')),''),nullif(username,'')) is not null
      order by pvp_trophies desc,pvp_wins desc limit 100)x));
end$function$;