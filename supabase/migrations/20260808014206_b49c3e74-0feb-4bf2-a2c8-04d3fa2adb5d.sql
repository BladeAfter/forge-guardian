CREATE OR REPLACE FUNCTION public.pvp_league(t integer)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
select case
 when t>=5000 then 'Lendária'
 when t>=4600 then 'Mestre I' when t>=4200 then 'Mestre II' when t>=3800 then 'Mestre III'
 when t>=3400 then 'Diamante I' when t>=3100 then 'Diamante II' when t>=2800 then 'Diamante III' when t>=2500 then 'Diamante IV' when t>=2200 then 'Diamante V'
 when t>=2000 then 'Platina I' when t>=1800 then 'Platina II' when t>=1600 then 'Platina III' when t>=1400 then 'Platina IV' when t>=1200 then 'Platina V'
 when t>=1050 then 'Ouro I' when t>=900 then 'Ouro II' when t>=750 then 'Ouro III' when t>=600 then 'Ouro IV' when t>=450 then 'Ouro V'
 when t>=380 then 'Prata I' when t>=310 then 'Prata II' when t>=240 then 'Prata III' when t>=170 then 'Prata IV' when t>=100 then 'Prata V'
 when t>=80 then 'Bronze I' when t>=60 then 'Bronze II' when t>=40 then 'Bronze III' when t>=20 then 'Bronze IV'
 else 'Bronze V' end
$$;

ALTER TABLE public.game_players ALTER COLUMN pvp_trophies SET DEFAULT 0;
UPDATE public.game_players SET pvp_trophies=0 WHERE pvp_wins=0 AND pvp_losses=0 AND pvp_trophies<>0;

CREATE OR REPLACE FUNCTION public.get_pvp_ranking()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
select coalesce(jsonb_agg(x order by x.position),'[]')from(
 select row_number()over(order by pvp_trophies desc,pvp_wins desc)position,id,
 coalesce(display_name,'Jogador')name,username,avatar_url "avatarUrl",pvp_trophies trophies,
 pvp_league(pvp_trophies)league,pvp_wins wins
 from game_players where not pvp_banned order by pvp_trophies desc,pvp_wins desc limit 100)x
$$;

CREATE OR REPLACE FUNCTION public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare attacker game_players%rowtype;defender game_players%rowtype;atk jsonb;def jsonb;sim jsonb;battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
begin
 select * into attacker from game_players where telegram_id=p_telegram_id;
 if attacker.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
 if attacker.id=p_opponent_id then raise exception 'INVALID_OPPONENT';end if;
 perform 1 from game_players where id in(attacker.id,p_opponent_id) order by id for update;
 select * into attacker from game_players where id=attacker.id;
 select * into defender from game_players where id=p_opponent_id;
 if defender.id is null or defender.pvp_banned then raise exception 'OPPONENT_UNAVAILABLE';end if;
 if attacker.pvp_banned then raise exception 'PVP_BANNED';end if;
 if attacker.pvp_tickets<1 then raise exception 'NO_PVP_TICKETS';end if;
 if exists(select 1 from pvp_battles where attacker_id=attacker.id and defender_id=defender.id and created_at>clock_timestamp()-interval'3 seconds') then raise exception 'BATTLE_ALREADY_STARTED';end if;
 atk:=pvp_team_json(attacker.id,'attack');def:=pvp_team_json(defender.id,'defense');
 if jsonb_array_length(atk)=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;
 if jsonb_array_length(def)=0 then raise exception 'INVALID_DEFENSE_TEAM';end if;
 update game_players set pvp_tickets=pvp_tickets-1 where id=attacker.id;
 seed:=gen_random_uuid()::text;sim:=simulate_pvp_battle(atk,def,seed);
 if sim->>'winnerSide'='attacker' then
   winner:=attacker.id;result:='attacker_win';change:=30;reward:=2500;
   update game_players set pvp_trophies=pvp_trophies+30,pvp_wins=pvp_wins+1,forge_coins=forge_coins+reward,updated_at=now() where id=attacker.id;
   update game_players set pvp_trophies=greatest(0,pvp_trophies-20),pvp_losses=pvp_losses+1,updated_at=now() where id=defender.id;
 else
   winner:=defender.id;result:='defender_win';change:=-20;reward:=0;
   update game_players set pvp_trophies=greatest(0,pvp_trophies-20),pvp_losses=pvp_losses+1,updated_at=now() where id=attacker.id;
   update game_players set pvp_trophies=pvp_trophies+30,pvp_wins=pvp_wins+1,updated_at=now() where id=defender.id;
 end if;
 insert into pvp_battles(attacker_id,defender_id,attacker_team_snapshot,defender_team_snapshot,battle_log,winner_id,result,total_turns,attacker_power,defender_power,reward_fc,trophy_change)
 values(attacker.id,defender.id,atk,def,coalesce(sim->'battleLog','[]'::jsonb),winner,result,coalesce((sim->>'totalTurns')::int,0),pvp_team_power(attacker.id,'attack'),pvp_team_power(defender.id,'defense'),reward,change)
 returning id into battle_id;
 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'totalTurns',coalesce((sim->>'totalTurns')::int,0),'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),'attackerState',coalesce(sim->'attackerState','[]'::jsonb),'defenderState',coalesce(sim->'defenderState','[]'::jsonb));
end $$;

CREATE OR REPLACE FUNCTION public.recruit_heroes(p_telegram_id bigint, p_count integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare v_user uuid;v_cost numeric;i int;roll numeric;rarity_pick text;picked hero_catalog%rowtype;new_hero_id uuid;result jsonb:='[]'::jsonb;
begin
 if p_count not in(1,5,10) then raise exception 'Invalid recruitment count';end if;v_cost:=25000*p_count;
 insert into game_players(telegram_id,last_seen_at) values(p_telegram_id,now()) on conflict(telegram_id) do update set last_seen_at=now(),updated_at=now() returning id into v_user;
 if(select forge_coins from game_players where id=v_user for update)<v_cost then raise exception 'NOT_ENOUGH_FC';end if;
 update game_players set forge_coins=forge_coins-v_cost,updated_at=now() where id=v_user;
 for i in 1..p_count loop
   roll:=random()*100;rarity_pick:=case when roll<.3 then 'legendary' when roll<3 then 'epic' when roll<13 then 'rare' when roll<38 then 'uncommon' else 'common' end;
   select * into picked from hero_catalog where rarity=rarity_pick and enabled order by random() limit 1;
   insert into player_heroes(user_id,hero_key,name,rarity,level,image) values(v_user,picked.hero_key,picked.name,picked.rarity,1,picked.image) returning id into new_hero_id;
   result:=result||jsonb_build_array(jsonb_build_object('id',new_hero_id,'heroKey',picked.hero_key,'name',picked.name,'rarity',picked.rarity,'level',1,'image',picked.image));
 end loop;
 return jsonb_build_object('heroes',result,'balance',(select forge_coins from game_players where id=v_user));
end $$;

CREATE OR REPLACE FUNCTION public.confirm_wallet_deposit(p_deposit_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare d wallet_deposits%rowtype;
begin
 select * into d from wallet_deposits where id=p_deposit_id for update;
 if d.id is null then raise exception 'DEPOSIT_NOT_FOUND';end if;
 if d.status='credited' then return;end if;
 if d.expires_at<now() then update wallet_deposits set status='expired' where id=d.id;raise exception 'DEPOSIT_EXPIRED';end if;
 if p_amount_nano<>round(d.amount_ton*1000000000)::text then raise exception 'PAYMENT_AMOUNT_MISMATCH';end if;
 if exists(select 1 from wallet_deposits where tx_hash=p_tx_hash and id<>d.id) or exists(select 1 from pet_egg_orders where tx_hash=p_tx_hash) then raise exception 'TX_ALREADY_USED';end if;
 update wallet_deposits set status='confirmed',tx_hash=p_tx_hash,confirmed_at=now() where id=d.id;
 update game_players set forge_coins=forge_coins+d.amount_fc,updated_at=now() where id=d.user_id;
 update wallet_deposits set status='credited',credited_at=now() where id=d.id;
 perform public.distribute_referral_commission(d.user_id,'deposit:'||d.id::text,'deposit',d.amount_fc,true,'TON',d.amount_ton);
end $$;