-- Official ranking share per position (single source of truth for both real distribution and estimates)
create or replace function public.pool_ranking_share(p_pos int)
returns numeric language sql immutable set search_path to 'public' as $$
  select case
    when p_pos=1 then 0.15
    when p_pos=2 then 0.10
    when p_pos=3 then 0.08
    when p_pos between 4 and 10 then 0.03/7
    when p_pos between 11 and 25 then 0.02/15
    when p_pos between 26 and 50 then 0.01/25
    when p_pos between 51 and 100 then 0.61/50
    else 0 end::numeric
$$;
revoke all on function public.pool_ranking_share(int) from public, anon, authenticated;

-- Real-time ranking with estimated rewards (no payout, pure projection)
create or replace function public.get_community_pool_ranking_with_estimates(p_pool_id uuid default null)
returns table(rank_position int, user_id uuid, username text, avatar_url text, points int, eligible boolean, estimated_ranking_reward_ton numeric, raffle_weight numeric)
language sql stable security definer set search_path to 'public' as $$
  with b as (select * from pool_balance where id = coalesce(p_pool_id,(select id from pool_balance where status='active' order by starts_at desc limit 1))),
  s as (select * from pool_settings where id),
  pools as (select (select balance_ton from b)*(select ranking_share_percent from s)/100 ranking_total,
                   (select balance_ton from b)*(select lottery_share_percent from s)/100 lottery_total),
  scores as (select pp.user_id, sum(pp.points)::int points from pool_points pp where pp.pool_id=(select id from b) group by pp.user_id),
  valid as (
    select sc.user_id, sc.points, coalesce(gp.display_name,'Jogador') username, gp.avatar_url
    from scores sc join game_players gp on gp.id=sc.user_id
    where sc.points >= (select minimum_points from s)
      and not coalesce(gp.pvp_banned,false)
      and (select count(*) from player_heroes h where h.user_id=sc.user_id) >= coalesce((select minimum_heroes from s),5)
  ),
  ranked as (select row_number() over (order by points desc, user_id)::int rank_position, v.* from valid v),
  capped as (select * from ranked where rank_position <= least(100,(select ranking_winner_limit from s))),
  total_points as (select coalesce(sum(points),0)::numeric tp from valid)
  select c.rank_position, c.user_id, c.username, c.avatar_url, c.points, true,
    round((select ranking_total from pools) * public.pool_ranking_share(c.rank_position), 9),
    case when (select tp from total_points) > 0 then round(c.points::numeric/(select tp from total_points),9) else 0 end
  from capped c order by c.rank_position
$$;
grant execute on function public.get_community_pool_ranking_with_estimates(uuid) to service_role;

-- Dashboard now surfaces real-time estimates
create or replace function public.get_community_pool_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u game_players%rowtype; b pool_balance%rowtype; s pool_settings%rowtype; elig jsonb; pts int; pos int; participants int; min_h int; my_est numeric; ranking_total numeric; lottery_total numeric; begin
  select * into u from game_players where telegram_id=p_telegram_id;
  select * into b from pool_balance where status='active';
  select * into s from pool_settings where id;
  if u.id is null or b.id is null then raise exception 'POOL_NOT_AVAILABLE'; end if;
  min_h := coalesce(s.minimum_heroes,5);
  elig := pool_eligibility(u.id);
  pts := (elig->>'points')::int;
  ranking_total := round(b.balance_ton*s.ranking_share_percent/100,9);
  lottery_total := round(b.balance_ton*s.lottery_share_percent/100,9);

  select count(*)::int, max(case when r.user_id=u.id then r.rank_position end), max(case when r.user_id=u.id then r.estimated_ranking_reward_ton end)
    into participants,pos,my_est
    from public.get_community_pool_ranking_with_estimates(b.id) r;

  return jsonb_build_object(
    'season',jsonb_build_object('id',b.id,'weekLabel',b.week_label,'balanceTon',b.balance_ton,'startsAt',b.starts_at,'endsAt',b.ends_at,'status',b.status,'rankingPoolTon',ranking_total,'rafflePoolTon',lottery_total),
    'player',jsonb_build_object(
      'points',pts,'position',pos,'eligible',(elig->>'eligible')::boolean,
      'walletConnected',exists(select 1 from pool_wallets where user_id=u.id),
      'accountAgeDays',floor(extract(epoch from (now()-u.created_at))/86400),
      'hasHero',(elig->>'ownedHeroes')::int>0,
      'ownedHeroes',(elig->>'ownedHeroes')::int,
      'pointsEligible',(elig->>'pointsEligible')::boolean,
      'heroesEligible',(elig->>'heroesEligible')::boolean,
      'estimatedRewardTon',coalesce(my_est,0)
    ),
    'eligibility',elig,
    'settings',jsonb_build_object('minimumPoints',s.minimum_points,'minimumHeroes',min_h,'rankingSharePercent',s.ranking_share_percent,'lotterySharePercent',s.lottery_share_percent),
    'participantCount',participants,
    'ranking',(
      select coalesce(jsonb_agg(jsonb_build_object('position',r.rank_position,'playerId',r.user_id,'name',r.username,'avatarUrl',r.avatar_url,'points',r.points,'eligible',r.eligible,'estimatedPrizeTon',r.estimated_ranking_reward_ton,'raffleWeight',r.raffle_weight) order by r.rank_position),'[]')
      from public.get_community_pool_ranking_with_estimates(b.id) r
    ),
    'history',(
      select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'weekLabel',h.week_label,'amountTon',h.amount_ton,'winnerCount',h.winner_count,'playerRewardTon',coalesce((select sum(amount_ton) from pool_rewards where history_id=h.id and user_id=u.id),0),'distributedAt',h.distributed_at) order by h.distributed_at desc),'[]')
      from (select * from pool_history order by distributed_at desc limit 12) h
    )
  );
end$function$;
revoke all on function public.get_community_pool_dashboard(bigint) from public, anon, authenticated;
grant execute on function public.get_community_pool_dashboard(bigint) to service_role;