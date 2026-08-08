-- setting readers -----------------------------------------
CREATE OR REPLACE FUNCTION public.setting_num(p_key text, p_default numeric)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT NULLIF(value #>> '{}','')::numeric FROM public.game_settings WHERE key = p_key), p_default);
$$;

CREATE OR REPLACE FUNCTION public.setting_text(p_key text, p_default text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT NULLIF(value #>> '{}','') FROM public.game_settings WHERE key = p_key), p_default);
$$;

CREATE OR REPLACE FUNCTION public.setting_bool(p_key text, p_default boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT (value #>> '{}')::boolean FROM public.game_settings WHERE key = p_key), p_default);
$$;

CREATE OR REPLACE FUNCTION public.setting_json(p_key text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (SELECT value FROM public.game_settings WHERE key = p_key);
$$;

-- league from table ---------------------------------------
CREATE OR REPLACE FUNCTION public.pvp_league(t integer)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v text;
BEGIN
  SELECT name INTO v FROM public.pvp_leagues
   WHERE enabled AND COALESCE(t,0) >= min_trophies AND (max_trophies IS NULL OR COALESCE(t,0) <= max_trophies)
   ORDER BY sort_order LIMIT 1;
  RETURN COALESCE(v, 'Bronze V');
END;
$$;

-- pvp battle uses dynamic settings -------------------------
CREATE OR REPLACE FUNCTION public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare attacker game_players%rowtype;defender game_players%rowtype;atk jsonb;def jsonb;sim jsonb;battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
  v_win int; v_loss int; v_cost int; v_reward numeric;
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
 values(attacker.id,defender.id,atk,def,coalesce(sim->'battleLog','[]'::jsonb),winner,result,coalesce((sim->>'totalTurns')::int,0),pvp_team_power(attacker.id,'attack'),pvp_team_power(defender.id,'defense'),reward,change)
 returning id into battle_id;
 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'totalTurns',coalesce((sim->>'totalTurns')::int,0),'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),'attackerState',coalesce(sim->'attackerState','[]'::jsonb),'defenderState',coalesce(sim->'defenderState','[]'::jsonb));
end $$;

-- runtime config for the mini app --------------------------
CREATE OR REPLACE FUNCTION public.get_runtime_config(p_telegram_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_banned boolean := false; v_reason text;
BEGIN
  IF p_telegram_id IS NOT NULL THEN
    SELECT banned, ban_reason INTO v_banned, v_reason FROM public.game_players WHERE telegram_id = p_telegram_id;
  END IF;
  RETURN jsonb_build_object(
    'settingsVersion', public.setting_num('settings_version',1)::int,
    'maintenance', public.setting_bool('maintenance_mode', false),
    'maintenanceMessage', public.setting_text('maintenance_message','Forge Village está em manutenção.'),
    'minAppVersion', public.setting_text('min_app_version','1.0.0'),
    'telegramAppLink', public.setting_text('telegram_app_link',''),
    'isSuperAdmin', COALESCE(p_telegram_id = public.admin_super_id(), false),
    'banned', COALESCE(v_banned,false),
    'banReason', v_reason,
    'pvp', jsonb_build_object(
      'trophyWin', public.setting_num('pvp_trophy_win',30)::int,
      'trophyLoss', public.setting_num('pvp_trophy_loss',-20)::int,
      'ticketCost', public.setting_num('pvp_ticket_cost',1)::int,
      'ticketMax', public.setting_num('pvp_ticket_max',10)::int
    ),
    'wallet', jsonb_build_object(
      'minWithdrawFc', public.setting_num('wallet_min_withdraw_fc',100000),
      'maxWithdrawFc', public.setting_num('wallet_max_withdraw_fc',10000000),
      'feePercent', public.setting_num('wallet_fee_percent',0)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.setting_num(text,numeric) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.setting_text(text,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.setting_bool(text,boolean) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.setting_json(text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.get_runtime_config(bigint) FROM anon, authenticated;
