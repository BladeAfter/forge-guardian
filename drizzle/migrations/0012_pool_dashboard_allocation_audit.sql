CREATE OR REPLACE FUNCTION public.get_community_pool_dashboard(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare u game_players%rowtype; b pool_balance%rowtype; s pool_settings%rowtype; elig jsonb; pts int; pos int; participants int; min_h int; my_est numeric; ranking_total numeric; lottery_total numeric; allocated numeric; begin
  select * into u from game_players where telegram_id=p_telegram_id;
  select * into b from pool_balance where status='active';
  select * into s from pool_settings where id;
  if u.id is null or b.id is null then raise exception 'POOL_NOT_AVAILABLE'; end if;
  min_h := coalesce(s.minimum_heroes,5);
  elig := pool_eligibility(u.id);
  pts := (elig->>'points')::int;
  ranking_total := round(b.balance_ton*s.ranking_share_percent/100,9);
  lottery_total := round(b.balance_ton*s.lottery_share_percent/100,9);

  select count(*)::int,
         max(case when r.user_id=u.id then r.rank_position end),
         max(case when r.user_id=u.id then r.estimated_ranking_reward_ton end),
         coalesce(sum(r.estimated_ranking_reward_ton),0)
    into participants,pos,my_est,allocated
    from public.get_community_pool_ranking_with_estimates(b.id) r;

  return jsonb_build_object(
    'season',jsonb_build_object('id',b.id,'weekLabel',b.week_label,'balanceTon',b.balance_ton,'startsAt',b.starts_at,'endsAt',b.ends_at,'status',b.status,
      'rankingPoolTon',ranking_total,'rafflePoolTon',lottery_total,
      'rankingAllocatedTon',allocated,
      'rankingDistributionValid',(floor(allocated*1000000000)::bigint = floor(ranking_total*1000000000)::bigint) or participants = 0),
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
    'rankingTiers',(select coalesce(jsonb_agg(jsonb_build_object('startRank',t.start_rank,'endRank',t.end_rank,'poolPercent',t.pool_percent) order by t.start_rank),'[]') from pool_ranking_tiers t),
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
