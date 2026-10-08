-- Audit column: server-side record of which pet modifiers were applied (admin only)
alter table public.pvp_battles add column if not exists pet_debug jsonb;

-- Official single source for PvP pet modifiers (battle-time only, never persisted on heroes)
create or replace function public.pvp_apply_pet_modifiers(p_team jsonb, p_buffs jsonb)
returns jsonb language sql immutable set search_path to 'public' as $$
  select coalesce(jsonb_agg(x || jsonb_build_object(
    'finalAtk', greatest(1, round((x->>'finalAtk')::numeric * (1 + coalesce((p_buffs->>'pvp_attack_percent')::numeric,0)/100)))::int,
    'defense', round(coalesce((x->>'defense')::numeric,0) * (1 + coalesce((p_buffs->>'pvp_defense_percent')::numeric,0)/100))::int,
    'speed', greatest(1, round(coalesce((x->>'speed')::numeric,1) * (1 + coalesce((p_buffs->>'pvp_speed_percent')::numeric,0)/100)))::int,
    'critChance', greatest(0, coalesce((p_buffs->>'critical_chance_percent')::numeric,0)),
    'critMultiplier', 1.5 + coalesce((p_buffs->>'critical_damage_percent')::numeric,0)/100
  ) order by coalesce((x->>'slot')::int, 0)), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_team,'[]'::jsonb)) x
$$;

-- Simulator: honours critChance/critMultiplier coming from the team snapshot (0% without pet => identical to before)
CREATE OR REPLACE FUNCTION public.simulate_pvp_battle(a jsonb, d jsonb, seed text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ast jsonb;dst jsonb;initiative jsonb;entry jsonb;actor jsonb;target jsonb;side text;target_id text;log jsonb:='[]';
 raw numeric;reduction numeric;variance numeric;damage int;new_hp int;turn int:=0;last_turn int:=0;winner text;
 alive_a boolean;alive_d boolean;hp_a numeric;hp_d numeric;init_len int;
 idle int:=0;idle_limit int;hard_cap int:=100000;total_hp numeric;prev_hp numeric;stalled int:=0;
 crit boolean;crit_chance numeric;crit_mult numeric;
begin
 select coalesce(jsonb_agg(x||jsonb_build_object('currentHp',(x->>'finalHp')::int)),'[]')into ast from jsonb_array_elements(a)x;
 select coalesce(jsonb_agg(x||jsonb_build_object('currentHp',(x->>'finalHp')::int)),'[]')into dst from jsonb_array_elements(d)x;
 select jsonb_agg(jsonb_build_object('side',q.side,'heroId',q.hero_id)order by q.speed desc,q.level desc,q.tie)into initiative from(
   select'attacker'side,x->>'heroId'hero_id,coalesce((x->>'speed')::int,(x->>'level')::int)speed,(x->>'level')::int level,hashtextextended(seed||(x->>'heroId'),0)tie from jsonb_array_elements(a)x
   union all
   select'defender',x->>'heroId',coalesce((x->>'speed')::int,(x->>'level')::int),(x->>'level')::int,hashtextextended(seed||(x->>'heroId'),0) from jsonb_array_elements(d)x)q;
 if initiative is null or jsonb_array_length(initiative)=0 then
   return jsonb_build_object('attackerState',ast,'defenderState',dst,'battleLog',log,'winnerSide','defender','turns',1,'totalTurns',1,'stalemate',true);
 end if;
 init_len:=jsonb_array_length(initiative);
 idle_limit:=init_len*4+8;

 select coalesce(sum((x->>'currentHp')::numeric),0)into hp_a from jsonb_array_elements(ast)x;
 select coalesce(sum((x->>'currentHp')::numeric),0)into hp_d from jsonb_array_elements(dst)x;
 prev_hp:=hp_a+hp_d;

 loop
   turn:=turn+1;
   if turn>hard_cap then exit; end if;
   entry:=initiative->((turn-1)%init_len);
   side:=entry->>'side';actor:=null;target:=null;
   if side='attacker'then
     select x into actor from jsonb_array_elements(ast)x where x->>'heroId'=entry->>'heroId'and(x->>'currentHp')::int>0;
     select x into target from jsonb_array_elements(dst)x where(x->>'currentHp')::int>0 order by(x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric),hashtextextended(seed||turn::text||(x->>'heroId'),0)limit 1;
   else
     select x into actor from jsonb_array_elements(dst)x where x->>'heroId'=entry->>'heroId'and(x->>'currentHp')::int>0;
     select x into target from jsonb_array_elements(ast)x where(x->>'currentHp')::int>0 order by(x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric),hashtextextended(seed||turn::text||(x->>'heroId'),0)limit 1;
   end if;
   if actor is null or target is null then
     idle:=idle+1;
     if idle>idle_limit then exit; end if;
     continue;
   end if;
   idle:=0;
   last_turn:=turn;
   raw:=(actor->>'finalAtk')::numeric;
   reduction:=coalesce((target->>'defense')::numeric,0)/(coalesce((target->>'defense')::numeric,0)+300);
   variance:=.95+pvp_stat_unit(seed||':'||turn||':damage')*.10;
   damage:=greatest(1,round(raw*(1-reduction)*variance));
   crit_chance:=greatest(0,coalesce((actor->>'critChance')::numeric,0));
   crit_mult:=greatest(1,coalesce((actor->>'critMultiplier')::numeric,1.5));
   crit:=crit_chance>0 and pvp_stat_unit(seed||':'||turn||':crit') < crit_chance/100.0;
   if crit then damage:=greatest(1,round(damage*crit_mult)); end if;
   new_hp:=greatest(0,(target->>'currentHp')::int-damage);
   target_id:=target->>'heroId';
   if side='attacker'then
     select jsonb_agg(case when x->>'heroId'=target_id then x||jsonb_build_object('currentHp',new_hp)else x end)into dst from jsonb_array_elements(dst)x;
   else
     select jsonb_agg(case when x->>'heroId'=target_id then x||jsonb_build_object('currentHp',new_hp)else x end)into ast from jsonb_array_elements(ast)x;
   end if;
   log:=log||jsonb_build_array(jsonb_build_object('turn',turn,'side',side,'attackerId',actor->>'heroId','targetId',target_id,'damage',damage,'remainingHp',new_hp,'crit',crit));

   select coalesce(sum((x->>'currentHp')::numeric),0)into hp_a from jsonb_array_elements(ast)x;
   select coalesce(sum((x->>'currentHp')::numeric),0)into hp_d from jsonb_array_elements(dst)x;
   total_hp:=hp_a+hp_d;
   if total_hp>=prev_hp then stalled:=stalled+1; else stalled:=0; end if;
   prev_hp:=total_hp;
   if stalled>idle_limit*5 then exit; end if;

   select exists(select 1 from jsonb_array_elements(ast)x where(x->>'currentHp')::int>0),
          exists(select 1 from jsonb_array_elements(dst)x where(x->>'currentHp')::int>0) into alive_a,alive_d;
   if not alive_d then winner:='attacker';exit;
   elsif not alive_a then winner:='defender';exit;end if;
 end loop;

 if winner is null then
   select coalesce(sum((x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric)),0)into hp_a from jsonb_array_elements(ast)x;
   select coalesce(sum((x->>'currentHp')::numeric/greatest(1,(x->>'finalHp')::numeric)),0)into hp_d from jsonb_array_elements(dst)x;
   winner:=case when hp_a>=hp_d then'attacker'else'defender'end;
   return jsonb_build_object('attackerState',ast,'defenderState',dst,'battleLog',log,'winnerSide',winner,'turns',greatest(1,last_turn),'totalTurns',greatest(1,last_turn),'stalemate',true);
 end if;
 return jsonb_build_object('attackerState',ast,'defenderState',dst,'battleLog',log,'winnerSide',winner,'turns',greatest(1,last_turn),'totalTurns',greatest(1,last_turn));
end$function$;

-- start_pvp_battle: applies active-pet arena modifiers server-side, exactly once, per side
CREATE OR REPLACE FUNCTION public.start_pvp_battle(p_telegram_id bigint, p_opponent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare attacker game_players%rowtype;defender game_players%rowtype;bot public.pvp_bots;atk jsonb;def jsonb;sim jsonb;battle_id uuid;winner uuid;result text;change int;reward numeric:=0;seed text;
  v_win int; v_loss int; v_cost int; v_reward numeric; v_turns int; v_def_power int; v_mult_atk numeric:=1; v_mult_hp numeric:=1;
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
 atk:=public.pvp_apply_pet_modifiers(atk,atk_buffs);
 def:=public.pvp_apply_pet_modifiers(def,def_buffs);
 eff_atk:=(select coalesce(sum((x->>'finalAtk')::numeric),0) from jsonb_array_elements(atk)x);

 seed:=gen_random_uuid()::text;sim:=simulate_pvp_battle(atk,def,seed);
 v_turns := (greatest(1, coalesce(nullif(sim->>'totalTurns','')::int, nullif(sim->>'turns','')::int, jsonb_array_length(coalesce(sim->'battleLog','[]'::jsonb)), 1)));

 debug:=jsonb_build_object('mode','pvp','attackerPetBuffs',atk_buffs,'defenderPetBuffs',def_buffs,
   'baseTeamAtk',base_atk,'arenaAtkBonusPercent',coalesce((atk_buffs->>'pvp_attack_percent')::numeric,0),
   'effectiveTeamAtk',eff_atk,'critChancePercent',coalesce((atk_buffs->>'critical_chance_percent')::numeric,0),
   'critMultiplier',1.5+coalesce((atk_buffs->>'critical_damage_percent')::numeric,0)/100);

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

 insert into pvp_battles(attacker_id,defender_id,defender_bot_id,is_bot_battle,winner_id,result,trophy_change,reward_fc,total_turns,battle_log,attacker_team,defender_team,seed,pet_debug)
 values(attacker.id,case when bot.id is null then defender.id else null end,bot.id,bot.id is not null,winner,result,change,reward,v_turns,
   coalesce(sim->'battleLog','[]'::jsonb),atk,def,seed,debug)
 returning id into battle_id;

 return jsonb_build_object('battleId',battle_id,'result',result,'winnerId',winner,'isBotBattle',bot.id is not null,
   'totalTurns',v_turns,'rewardFc',reward,'trophyChange',change,'battleLog',coalesce(sim->'battleLog','[]'::jsonb),
   'attackerState',coalesce(sim->'attackerState',atk),'defenderState',coalesce(sim->'defenderState',def),
   'defenderPower',v_def_power);
end$function$;

-- Legacy clan boss endpoint: honour the active pet boss-damage bonus like the global boss does
CREATE OR REPLACE FUNCTION public.clan_boss_attack(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; v_clan uuid; b public.clan_boss_cycles%rowtype; v_damage numeric; v_share numeric; r record; v_bonus numeric;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('clanboss:'||v_clan::text, 0));
  SELECT * INTO b FROM public.clan_boss_cycles WHERE clan_id = v_clan AND status='active' ORDER BY started_at DESC LIMIT 1 FOR UPDATE;
  IF b.id IS NULL THEN
    INSERT INTO public.clan_boss_cycles(clan_id) VALUES (v_clan) RETURNING * INTO b;
  END IF;
  IF b.current_health <= 0 THEN RAISE EXCEPTION 'CLAN_BOSS_DEFEATED'; END IF;
  IF EXISTS (SELECT 1 FROM public.clan_boss_participants WHERE cycle_id=b.id AND user_id=v_uid AND last_attack_at > now() - interval '30 minutes')
    THEN RAISE EXCEPTION 'CLAN_BOSS_COOLDOWN'; END IF;

  v_bonus := COALESCE((public.get_pet_bonuses(v_uid)->>'boss_damage_percent')::numeric, 0);
  v_damage := GREATEST(100, public.clan_player_power(v_uid) * (0.8 + random() * 0.4) * (1 + v_bonus/100.0));
  UPDATE public.clan_boss_cycles SET current_health = GREATEST(0, current_health - v_damage) WHERE id = b.id RETURNING * INTO b;
  INSERT INTO public.clan_boss_participants(cycle_id, user_id, damage, attacks, last_attack_at)
  VALUES (b.id, v_uid, v_damage, 1, now())
  ON CONFLICT (cycle_id, user_id) DO UPDATE SET damage = clan_boss_participants.damage + EXCLUDED.damage,
    attacks = clan_boss_participants.attacks + 1, last_attack_at = now();

  IF b.current_health <= 0 THEN
    UPDATE public.clan_boss_cycles SET status='defeated', finished_at = now() WHERE id = b.id;
    FOR r IN SELECT user_id, damage FROM public.clan_boss_participants WHERE cycle_id = b.id LOOP
      v_share := GREATEST(1, floor(b.reward_points * (r.damage / GREATEST(1, b.max_health))));
      UPDATE public.clan_members SET clan_points = clan_points + v_share WHERE user_id = r.user_id;
      INSERT INTO public.clan_points_ledger(clan_id, user_id, amount, reason) VALUES (v_clan, r.user_id, v_share, 'clan_boss');
    END LOOP;
    INSERT INTO public.clan_boss_cycles(clan_id) VALUES (v_clan);
  END IF;

  RETURN jsonb_build_object('status','ok','damage', floor(v_damage), 'currentHealth', b.current_health, 'maxHealth', b.max_health,
    'petBossDamagePercent', v_bonus);
END; $function$;

-- Clan boss v2: expose the server-side pet modifier audit (values/formula unchanged)
CREATE OR REPLACE FUNCTION public.clan_boss_strike(p_telegram_id bigint, p_instance_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cfg public.clan_boss_config; v_uid uuid; v_clan uuid; b public.clan_boss_instances;
        v_last timestamptz; v_damage numeric; v_base numeric; v_power numeric; v_bonus numeric; v_buffs jsonb;
        v_crit boolean := false; v_defeated boolean := false;
BEGIN
  cfg := public.clan_boss_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('clanbossv2:'||v_clan::text, 0));
  b := public.clan_boss_ensure(v_clan);

  IF p_instance_id IS NOT NULL AND p_instance_id <> b.id THEN
    IF EXISTS (SELECT 1 FROM public.clan_boss_instances WHERE id = p_instance_id AND clan_id <> v_clan)
      THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
    RAISE EXCEPTION 'CLAN_BOSS_STALE';
  END IF;

  SELECT * INTO b FROM public.clan_boss_instances WHERE id = b.id FOR UPDATE;
  IF b.clan_id <> v_clan THEN RAISE EXCEPTION 'FORBIDDEN_CLAN_BOSS'; END IF;
  IF b.status <> 'active' OR b.current_hp <= 0 THEN RAISE EXCEPTION 'CLAN_BOSS_DEFEATED'; END IF;
  IF b.ends_at <= now() THEN RAISE EXCEPTION 'CLAN_BOSS_EXPIRED'; END IF;

  SELECT last_attack_at INTO v_last FROM public.clan_boss_damage WHERE instance_id = b.id AND user_id = v_uid;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => GREATEST(1, cfg.cooldown_seconds)) THEN
    RAISE EXCEPTION 'CLAN_BOSS_COOLDOWN';
  END IF;

  v_buffs := COALESCE(public.get_pet_bonuses(v_uid), '{}'::jsonb);
  v_power := GREATEST(1, public.clan_player_power(v_uid));
  v_bonus := COALESCE((v_buffs->>'boss_damage_percent')::numeric, 0)
           + COALESCE((v_buffs->>'team_attack_percent')::numeric, 0);
  v_base := GREATEST(100, round(v_power * (0.85 + random() * 0.3)));
  v_damage := GREATEST(100, round(v_base * (1 + v_bonus / 100.0)));
  IF random() < LEAST(0.35, COALESCE((v_buffs->>'critical_chance_percent')::numeric, 0) / 100.0) THEN
    v_crit := true;
    v_damage := round(v_damage * (1.5 + COALESCE((v_buffs->>'critical_damage_percent')::numeric, 0) / 100.0));
  END IF;
  v_damage := LEAST(v_damage, b.current_hp);

  UPDATE public.clan_boss_instances
     SET current_hp = GREATEST(0, current_hp - v_damage),
         total_damage = total_damage + v_damage,
         attacks = attacks + 1
   WHERE id = b.id RETURNING * INTO b;

  INSERT INTO public.clan_boss_damage(instance_id, clan_id, user_id, damage, attacks, last_attack_at)
  VALUES (b.id, v_clan, v_uid, v_damage, 1, now())
  ON CONFLICT (instance_id, user_id) DO UPDATE
    SET damage = public.clan_boss_damage.damage + EXCLUDED.damage,
        attacks = public.clan_boss_damage.attacks + 1,
        last_attack_at = now();

  UPDATE public.clan_boss_instances
     SET participants = COALESCE((SELECT count(*) FROM public.clan_boss_damage WHERE instance_id = b.id), 0)
   WHERE id = b.id;

  IF b.current_hp <= 0 THEN
    v_defeated := true;
    PERFORM public.clan_boss_settle(b.id, 'defeated');
    PERFORM public.clan_boss_ensure(v_clan);
  END IF;

  PERFORM public.record_clan_mission_progress(v_uid, 'clan_boss_damage', v_damage::bigint);

  RETURN jsonb_build_object('status','ok', 'damage', v_damage, 'critical', v_crit,
    'currentHp', GREATEST(0, b.current_hp), 'maxHp', b.max_hp, 'defeated', v_defeated,
    'damageBeforePet', v_base, 'petBossDamagePercent', v_bonus,
    'nextAttackAt', now() + make_interval(secs => GREATEST(1, cfg.cooldown_seconds)));
END $function$;