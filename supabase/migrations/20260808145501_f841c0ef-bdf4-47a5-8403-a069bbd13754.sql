create or replace function public.search_pvp_opponents(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u game_players%rowtype;power int;power_pct numeric;trophy_range int;result jsonb;step int;
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
  power:=pvp_team_power(u.id,'attack');
  if power=0 then raise exception 'ATTACK_TEAM_EMPTY';end if;
  for step in 1..3 loop
    power_pct:=case step when 1 then .20 when 2 then .35 else .50 end;
    trophy_range:=case step when 1 then 150 when 2 then 300 else 500 end;
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
        case when i.last_shown_at>now()-interval '24 hours' then 1 else 0 end repeat_rank,
        abs(pvp_team_power(p.id,'defense')-power)power_gap,
        hashtextextended(p.id::text||clock_timestamp()::date::text,0)random_key
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
      return jsonb_build_object('opponents',result);
    end if;
  end loop;
  return jsonb_build_object('opponents','[]'::jsonb);
end$function$;

create or replace function public.get_pvp_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u game_players%rowtype;
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
  return jsonb_build_object(
    'userId',u.id,'trophies',u.pvp_trophies,'league',pvp_league(u.pvp_trophies),'tickets',u.pvp_tickets,
    'wins',u.pvp_wins,'losses',u.pvp_losses,
    'attackTeam',pvp_team_json(u.id,'attack'),'defenseTeam',pvp_team_json(u.id,'defense'),
    'teamPower',pvp_team_power(u.id,'attack'),
    'ownedHeroes',(select coalesce(jsonb_agg(pvp_hero_json(h) order by h.created_at),'[]') from player_heroes h where h.user_id=u.id),
    'history',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'opponentName',coalesce(nullif(trim(coalesce(o.display_name,'')),''),nullif(o.username,''),'Jogador'),'result',case when b.winner_id=u.id then 'win' else 'loss' end,'turns',b.total_turns,'trophyChange',case when b.attacker_id=u.id then b.trophy_change else -b.trophy_change end,'rewardFc',case when b.attacker_id=u.id then b.reward_fc else 0 end,'createdAt',b.created_at) order by b.created_at desc),'[]')
      from(select * from pvp_battles where attacker_id=u.id or defender_id=u.id order by created_at desc limit 30)b
      join game_players o on o.id=case when b.attacker_id=u.id then b.defender_id else b.attacker_id end),
    'ranking',(select coalesce(jsonb_agg(x order by x.position),'[]') from(
      select row_number()over(order by pvp_trophies desc,pvp_wins desc)position,id,
        coalesce(nullif(trim(coalesce(display_name,'')),''),nullif(username,''),'Jogador')name,
        username,avatar_url "avatarUrl",pvp_trophies trophies,pvp_league(pvp_trophies)league,pvp_wins wins
      from game_players
      where not pvp_banned and not coalesce(banned,false) and telegram_id is not null and telegram_id>0
        and coalesce(nullif(trim(coalesce(display_name,'')),''),nullif(username,'')) is not null
      order by pvp_trophies desc,pvp_wins desc limit 100)x));
end$function$;