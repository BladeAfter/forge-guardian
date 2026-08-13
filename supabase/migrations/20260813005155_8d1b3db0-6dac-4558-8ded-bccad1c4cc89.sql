-- PvP-only rule: no duplicated hero template inside the same PvP team.

CREATE OR REPLACE FUNCTION public.pvp_hero_template_key(h public.player_heroes)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS
$$select lower(coalesce(nullif(btrim(h.hero_template_id),''), nullif(btrim(h.hero_key),''), h.id::text))$$;

CREATE OR REPLACE FUNCTION public.pvp_hero_json(h public.player_heroes)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS
$$select jsonb_build_object('heroId',h.id,'templateId',public.pvp_hero_template_key(h),'heroKey',h.hero_key,'name',h.name,'imageUrl',h.image,'rarity',normalize_hero_rarity(h.rarity),'level',h.level,'archetype',h.archetype,'finalAtk',h.final_atk,'finalHp',h.final_hp,'defense',0,'speed',h.level,'power',round(h.final_atk*2.2+h.final_hp*.18+h.level*25))$$;

-- keeps only the first hero (lowest slot) per template inside a team snapshot
CREATE OR REPLACE FUNCTION public.pvp_dedupe_team(p_team jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS
$$
select coalesce(jsonb_agg(x.h order by x.ord),'[]'::jsonb) from (
  select h, ord, row_number() over (
      partition by lower(coalesce(nullif(h->>'templateId',''), nullif(h->>'heroKey',''), h->>'name', h->>'heroId'))
      order by ord) rn
  from jsonb_array_elements(coalesce(p_team,'[]'::jsonb)) with ordinality t(h,ord)
) x where x.rn = 1
$$;

CREATE OR REPLACE FUNCTION public.pvp_team_has_duplicates(p_user uuid, p_type text)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS
$$
select exists(
  select 1 from public.pvp_team_slots s
  join public.player_heroes h on h.id = s.hero_id
  where s.user_id = p_user and s.team_type = p_type
  group by public.pvp_hero_template_key(h) having count(*) > 1)
$$;

CREATE OR REPLACE FUNCTION public.save_pvp_team_slot(p_telegram_id bigint, p_team_type text, p_slot integer, p_hero_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; v_tpl text;
begin
  if p_team_type not in('attack','defense') or p_slot not between 1 and 5 then raise exception 'INVALID_TEAM_SLOT';end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND';end if;
  select public.pvp_hero_template_key(h) into v_tpl from player_heroes h where h.id=p_hero_id and h.user_id=u;
  if v_tpl is null then raise exception 'HERO_NOT_OWNED';end if;
  -- PvP exclusive: same hero template cannot occupy two slots of the same team
  if exists(select 1 from pvp_team_slots s join player_heroes h on h.id=s.hero_id
            where s.user_id=u and s.team_type=p_team_type and s.slot<>p_slot
              and public.pvp_hero_template_key(h)=v_tpl) then
    raise exception 'PVP_DUPLICATE_HERO';
  end if;
  delete from pvp_team_slots where user_id=u and team_type=p_team_type and hero_id=p_hero_id and slot<>p_slot;
  insert into pvp_team_slots(user_id,team_type,slot,hero_id) values(u,p_team_type,p_slot,p_hero_id)
    on conflict(user_id,team_type,slot) do update set hero_id=excluded.hero_id,updated_at=now();
  return get_pvp_dashboard(p_telegram_id);
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
    'attackTeamHasDuplicates',public.pvp_team_has_duplicates(u.id,'attack'),
    'defenseTeamHasDuplicates',public.pvp_team_has_duplicates(u.id,'defense'),
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

 atk:=pvp_team_json(attacker.id,'attack');
 if jsonb_array_length(atk)=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;
 -- PvP exclusive rule: validate BEFORE consuming any ticket
 if public.pvp_team_has_duplicates(attacker.id,'attack') then raise exception 'PVP_DUPLICATE_HERO_TEAM';end if;

 if bot.id is null then
   if exists(select 1 from pvp_battles where attacker_id=attacker.id and defender_id=defender.id and created_at>clock_timestamp()-interval'3 seconds') then raise exception 'BATTLE_ALREADY_STARTED';end if;
   def:=public.pvp_dedupe_team(pvp_team_json(defender.id,'defense'));
   v_def_power:=(select coalesce(sum((x->>'power')::numeric),0)::int from jsonb_array_elements(def)x);
 else
   if bot.used_at is not null then raise exception 'OPPONENT_UNAVAILABLE';end if;
   v_mult_atk:=case bot.strategy when 'aggressive' then 1.08 when 'defensive' then .95 when 'finisher' then 1.05 when 'tactical' then 1.04 else 1 end;
   v_mult_hp:=case bot.strategy when 'aggressive' then .95 when 'defensive' then 1.10 when 'finisher' then .98 when 'tactical' then 1.04 else 1 end;
   select coalesce(jsonb_agg(x||jsonb_build_object(
       'finalAtk',greatest(1,round((x->>'finalAtk')::numeric*v_mult_atk))::int,
       'finalHp',greatest(1,round((x->>'finalHp')::numeric*v_mult_hp))::int)),'[]')
     into def from jsonb_array_elements(public.pvp_dedupe_team(bot.team))x;
   if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;
   v_def_power:=bot.power;
   update pvp_bots set used_at=now() where id=bot.id;
 end if;
 if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;

 if attacker.pvp_tickets < v_cost then raise exception 'NO_PVP_TICKETS';end if;
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

 insert into pvp_battles(attacker_id,defender_id,defender_bot_id,is_bot_battle,winner_id,result,trophy_change,reward_fc,total_turns,battle_log,attacker_team,defender_team,seed)
 values(attacker.id,case when bot.id is null then defender.id else null end,bot.id,bot.id is not null,winner,result,change,reward,v_turns,
   coalesce(sim->'battleLog','[]'::jsonb),atk,def,seed)
 returning id into battle_id;

 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'isBotBattle',bot.id is not null,
   'totalTurns',v_turns,'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),
   'attackerState',coalesce(sim->'attackerState',atk),'defenderState',coalesce(sim->'defenderState',def),
   'defenderPower',v_def_power);
end$function$;
