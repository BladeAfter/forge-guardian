ALTER TABLE public.pvp_opponent_impressions ADD COLUMN IF NOT EXISTS search_power integer;
ALTER TABLE public.pvp_bots ADD COLUMN IF NOT EXISTS attacker_power integer;

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
      insert into pvp_opponent_impressions(user_id,opponent_id,last_shown_at,search_power)
      select u.id,(x->>'userId')::uuid,now(),power from jsonb_array_elements(result)x
      on conflict(user_id,opponent_id)do update set last_shown_at=now(),shown_count=pvp_opponent_impressions.shown_count+1,search_power=excluded.search_power;
      return jsonb_build_object('opponents',result,'source','real');
    end if;
  end loop;
  return jsonb_build_object('opponents',jsonb_build_array(pvp_generate_bot(u.id)),'source','ai');
end$function$;

CREATE OR REPLACE FUNCTION public.pvp_bot_set_attacker_power() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  IF NEW.attacker_power IS NULL AND NEW.target_user_id IS NOT NULL THEN
    NEW.attacker_power := public.pvp_team_power(NEW.target_user_id,'attack');
  END IF;
  RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_pvp_bot_attacker_power ON public.pvp_bots;
CREATE TRIGGER trg_pvp_bot_attacker_power BEFORE INSERT ON public.pvp_bots
FOR EACH ROW EXECUTE FUNCTION public.pvp_bot_set_attacker_power();

CREATE OR REPLACE FUNCTION public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cur_power int; v_search_power int; attacker game_players%rowtype;defender game_players%rowtype;bot public.pvp_bots;atk jsonb;def jsonb;sim jsonb;v_battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
  v_win int; v_loss int; v_cost int; v_reward numeric; v_turns int; v_def_power int; v_atk_power int; v_mult_atk numeric:=1; v_mult_hp numeric:=1;
  atk_buffs jsonb:='{}'::jsonb; def_buffs jsonb:='{}'::jsonb; base_atk numeric; eff_atk numeric; debug jsonb;
  v_trophies_after int; v_fc_after numeric; v_xp int; v_opp_type text;
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
 if public.pvp_team_has_duplicates(attacker.id,'attack') then raise exception 'PVP_DUPLICATE_HERO_TEAM';end if;

 -- ANTI-SWAP: matchmaking snapshot revalidation
 v_cur_power:=public.pvp_team_power(attacker.id,'attack');
 if bot.id is null then
   select i.search_power into v_search_power from pvp_opponent_impressions i
    where i.user_id=attacker.id and i.opponent_id=defender.id and i.last_shown_at>now()-interval '2 hours';
 else
   v_search_power:=bot.attacker_power;
 end if;
 if coalesce(v_search_power,0)>0 and v_cur_power > (v_search_power*1.10 + 500) then
   raise exception 'PVP_TEAM_CHANGED';
 end if;

 if bot.id is null then
   if exists(select 1 from pvp_battles where attacker_id=attacker.id and defender_id=defender.id and created_at>clock_timestamp()-interval'3 seconds') then raise exception 'BATTLE_ALREADY_STARTED';end if;
   def:=public.pvp_dedupe_team(pvp_team_json(defender.id,'defense'));
   v_def_power:=(select coalesce(sum((x->>'power')::numeric),0)::int from jsonb_array_elements(def)x);
   def_buffs:=coalesce(public.get_pet_bonuses(defender.id),'{}'::jsonb);
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

 atk_buffs:=coalesce(public.get_pet_bonuses(attacker.id),'{}'::jsonb);
 base_atk:=(select coalesce(sum((x->>'finalAtk')::numeric),0) from jsonb_array_elements(atk)x);
 v_atk_power:=(select coalesce(sum((x->>'power')::numeric),0)::int from jsonb_array_elements(atk)x);
 atk:=public.pvp_apply_pet_modifiers(atk,atk_buffs);
 def:=public.pvp_apply_pet_modifiers(def,def_buffs);
 eff_atk:=(select coalesce(sum((x->>'finalAtk')::numeric),0) from jsonb_array_elements(atk)x);

 seed:=gen_random_uuid()::text;sim:=simulate_pvp_battle(atk,def,seed);
 v_turns := (greatest(1, coalesce(nullif(sim->>'totalTurns','')::int, nullif(sim->>'turns','')::int, jsonb_array_length(coalesce(sim->'battleLog','[]'::jsonb)), 1)));

 debug:=jsonb_build_object('mode','pvp','attackerPetBuffs',atk_buffs,'defenderPetBuffs',def_buffs,
   'baseTeamAtk',base_atk,'arenaAtkBonusPercent',coalesce((atk_buffs->>'pvp_attack_percent')::numeric,0),
   'effectiveTeamAtk',eff_atk,'critChancePercent',coalesce((atk_buffs->>'critical_chance_percent')::numeric,0),
   'critMultiplier',1.5+coalesce((atk_buffs->>'critical_damage_percent')::numeric,0)/100,'seed',seed);

 if sim->>'winnerSide'='attacker' then
   winner:=attacker.id;result:='attacker_win';change:=v_win;reward:=v_reward;
   update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,forge_coins=forge_coins+reward,updated_at=now()
     where id=attacker.id returning pvp_trophies, forge_coins into v_trophies_after, v_fc_after;
   if bot.id is null then
     update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now() where id=defender.id;
   end if;
 else
   winner:=case when bot.id is null then defender.id else null end;
   result:='defender_win';change:=-v_loss;reward:=0;
   update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now()
     where id=attacker.id returning pvp_trophies, forge_coins into v_trophies_after, v_fc_after;
   if bot.id is null then
     update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,updated_at=now() where id=defender.id;
   end if;
 end if;

 insert into pvp_battles(attacker_id,defender_id,defender_bot_id,is_bot_battle,winner_id,result,trophy_change,reward_fc,total_turns,battle_log,attacker_team_snapshot,defender_team_snapshot,attacker_power,defender_power,pet_debug)
 values(attacker.id,case when bot.id is null then defender.id else null end,bot.id,bot.id is not null,winner,result,change,reward,v_turns,
   coalesce(sim->'battleLog','[]'::jsonb),atk,def,coalesce(v_atk_power,0),coalesce(v_def_power,0),debug)
 returning id into v_battle_id;

 select coalesce(sum(xp_amount),0)::int into v_xp from season_pass_xp_ledger
  where user_id=attacker.id and reference_id in ('pvp:'||v_battle_id::text,'pvp_win:'||v_battle_id::text);

 v_opp_type := case when bot.id is null then 'REAL_PLAYER' else 'AI_BOT' end;
 insert into pvp_reward_settlements(battle_id,player_id,opponent_id,opponent_type,result,trophies_awarded,fc_awarded,xp_awarded,status)
 values(v_battle_id,attacker.id,case when bot.id is null then defender.id else bot.id end,v_opp_type,result,change,reward,coalesce(v_xp,0),'settled')
 on conflict (battle_id) do nothing;

 raise notice 'PVP_REWARD_SETTLEMENT battle=% player=% result=% trophies=% xp=% fc=% opponent=% status=settled',
   v_battle_id, attacker.telegram_id, result, change, coalesce(v_xp,0), reward, v_opp_type;

 return jsonb_build_object('battleId',v_battle_id,'result',result,'winnerId',winner,'isBotBattle',bot.id is not null,
   'totalTurns',v_turns,'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),
   'attackerState',coalesce(sim->'attackerState',atk),'defenderState',coalesce(sim->'defenderState',def),
   'defenderPower',v_def_power,
   'trophiesAfter',v_trophies_after,'balanceFc',v_fc_after,'xpAwarded',coaleske(v_fc_after,0),'opponentType',v_opp_type);
end$function$;