CREATE OR REPLACE FUNCTION public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare attacker game_players%rowtype;defender game_players%rowtype;bot public.pvp_bots;atk jsonb;def jsonb;sim jsonb;battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
  v_win int; v_loss int; v_cost int; v_reward numeric; v_turns int; v_def_power int; v_atk_power int; v_mult_atk numeric:=1; v_mult_hp numeric:=1;
  atk_buffs jsonb:='{}'::jsonb; def_buffs jsonb:='{}'::jsonb; base_atk numeric; eff_atk numeric; debug jsonb;
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

 -- Active pet of the attacker (server-side; never trusted from the client)
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

 insert into pvp_battles(attacker_id,defender_id,defender_bot_id,is_bot_battle,winner_id,result,trophy_change,reward_fc,total_turns,battle_log,attacker_team_snapshot,defender_team_snapshot,attacker_power,defender_power,pet_debug)
 values(attacker.id,case when bot.id is null then defender.id else null end,bot.id,bot.id is not null,winner,result,change,reward,v_turns,
   coalesce(sim->'battleLog','[]'::jsonb),atk,def,coalesce(v_atk_power,0),coalesce(v_def_power,0),debug)
 returning id into battle_id;

 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'isBotBattle',bot.id is not null,
   'totalTurns',v_turns,'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),
   'attackerState',coalesce(sim->'attackerState',atk),'defenderState',coalesce(sim->'defenderState',def),
   'defenderPower',v_def_power);
end$function$;