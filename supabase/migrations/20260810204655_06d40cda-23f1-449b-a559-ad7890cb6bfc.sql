create or replace function public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare attacker game_players%rowtype;defender game_players%rowtype;atk jsonb;def jsonb;sim jsonb;battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
  v_win int; v_loss int; v_cost int; v_reward numeric; v_turns int;
begin
 v_win := public.setting_num('pvp_trophy_win',30)::int;
 v_loss := abs(public.setting_num('pvp_trophy_loss',-20)::int);
 v_cost := GREATEST(0, public.setting_num('pvp_ticket_cost',1)::int);
 v_reward := public.setting_num('pvp_win_reward_fc',2500);

 select * into attacker from game_players where telegram_id=p_telegram_id;
 if attacker.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
 if attacker.id=p_opponent_id then raise exception 'INVALID_OPPONENT';end if;
 perform 1 from game_players where id in(attacker.id,p_opponent_id) order by id for update;
 select * into attacker from game_players where id=attacker.id;
 select * into defender from game_players where id=p_opponent_id;
 if defender.id is null or defender.pvp_banned or defender.banned then raise exception 'OPPONENT_UNAVAILABLE';end if;
 if attacker.pvp_banned or attacker.banned then raise exception 'PVP_BANNED';end if;
 if attacker.pvp_tickets < v_cost then raise exception 'NO_PVP_TICKETS';end if;
 if exists(select 1 from pvp_battles where attacker_id=attacker.id and defender_id=defender.id and created_at>clock_timestamp()-interval'3 seconds') then raise exception 'BATTLE_ALREADY_STARTED';end if;
 atk:=pvp_team_json(attacker.id,'attack');def:=pvp_team_json(defender.id,'defense');
 if jsonb_array_length(atk)=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;
 if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;
 update game_players set pvp_tickets=greatest(0,pvp_tickets-v_cost) where id=attacker.id;
 seed:=gen_random_uuid()::text;sim:=simulate_pvp_battle(atk,def,seed);
 v_turns := least(50, greatest(1, coalesce(nullif(sim->>'totalTurns','')::int, nullif(sim->>'turns','')::int, jsonb_array_length(coalesce(sim->'battleLog','[]'::jsonb)), 1)));
 if sim->>'winnerSide'='attacker' then
   winner:=attacker.id;result:='attacker_win';change:=v_win;reward:=v_reward;
   update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,forge_coins=forge_coins+reward,updated_at=now() where id=attacker.id;
   update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now() where id=defender.id;
 else
   winner:=defender.id;result:='defender_win';change:=-v_loss;reward:=0;
   update game_players set pvp_trophies=greatest(0,pvp_trophies-v_loss),pvp_losses=pvp_losses+1,updated_at=now() where id=attacker.id;
   update game_players set pvp_trophies=pvp_trophies+v_win,pvp_wins=pvp_wins+1,updated_at=now() where id=defender.id;
 end if;
 insert into pvp_battles(attacker_id,defender_id,attacker_team_snapshot,defender_team_snapshot,battle_log,winner_id,result,total_turns,attacker_power,defender_power,reward_fc,trophy_change)
 values(attacker.id,defender.id,atk,def,coalesce(sim->'battleLog','[]'::jsonb),winner,result,v_turns,pvp_team_power(attacker.id,'attack'),pvp_team_power(defender.id,'defense'),reward,change)
 returning id into battle_id;
 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'totalTurns',v_turns,'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),'attackerState',coalesce(sim->'attackerState','[]'::jsonb),'defenderState',coalesce(sim->'defenderState','[]'::jsonb));
end
$fn$;