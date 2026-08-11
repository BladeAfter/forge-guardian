ALTER TABLE public.pool_settings ADD COLUMN IF NOT EXISTS minimum_heroes integer NOT NULL DEFAULT 5;

CREATE OR REPLACE FUNCTION public.pool_eligibility(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare s pool_settings%rowtype; b pool_balance%rowtype; pts int; heroes int; banned boolean; min_h int; begin
  select * into s from pool_settings where id;
  select * into b from pool_balance where status='active';
  min_h := coalesce(s.minimum_heroes,5);
  select coalesce(sum(points),0)::int into pts from pool_points where user_id=p_user_id and (b.id is null or pool_id=b.id);
  select count(*)::int into heroes from player_heroes where user_id=p_user_id;
  select coalesce(pvp_banned,false) into banned from game_players where id=p_user_id;
  return jsonb_build_object(
    'points',pts,
    'minimumPoints',coalesce(s.minimum_points,500),
    'ownedHeroes',heroes,
    'minimumHeroes',min_h,
    'pointsEligible',pts>=coalesce(s.minimum_points,500),
    'heroesEligible',heroes>=min_h,
    'banned',coalesce(banned,false),
    'eligible',pts>=coalesce(s.minimum_points,500) and heroes>=min_h and not coalesce(banned,false)
  );
end$$;

REVOKE EXECUTE ON FUNCTION public.pool_eligibility(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pool_eligibility(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_community_pool_dashboard(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare u game_players%rowtype; b pool_balance%rowtype; s pool_settings%rowtype; elig jsonb; pts int; pos int; participants int; min_h int; begin
  select * into u from game_players where telegram_id=p_telegram_id;
  select * into b from pool_balance where status='active';
  select * into s from pool_settings where id;
  if u.id is null or b.id is null then raise exception 'POOL_NOT_AVAILABLE'; end if;
  min_h := coalesce(s.minimum_heroes,5);
  elig := pool_eligibility(u.id);
  pts := (elig->>'points')::int;

  with scores as (
    select user_id, sum(points)::int points from pool_points where pool_id=b.id group by user_id
  ), valid as (
    select sc.*, row_number() over (order by sc.points desc, sc.user_id) position
    from scores sc
    join game_players gp on gp.id=sc.user_id
    where sc.points>=s.minimum_points
      and not coalesce(gp.pvp_banned,false)
      and (select count(*) from player_heroes h where h.user_id=sc.user_id)>=min_h
  )
  select count(*)::int, max(case when user_id=u.id then position::int end) into participants,pos from valid;

  return jsonb_build_object(
    'season',jsonb_build_object('id',b.id,'weekLabel',b.week_label,'balanceTon',b.balance_ton,'startsAt',b.starts_at,'endsAt',b.ends_at,'status',b.status),
    'player',jsonb_build_object(
      'points',pts,'position',pos,'eligible',(elig->>'eligible')::boolean,
      'walletConnected',exists(select 1 from pool_wallets where user_id=u.id),
      'accountAgeDays',floor(extract(epoch from (now()-u.created_at))/86400),
      'hasHero',(elig->>'ownedHeroes')::int>0,
      'ownedHeroes',(elig->>'ownedHeroes')::int,
      'pointsEligible',(elig->>'pointsEligible')::boolean,
      'heroesEligible',(elig->>'heroesEligible')::boolean
    ),
    'eligibility',elig,
    'settings',jsonb_build_object('minimumPoints',s.minimum_points,'minimumHeroes',min_h,'rankingSharePercent',s.ranking_share_percent,'lotterySharePercent',s.lottery_share_percent),
    'participantCount',participants,
    'ranking',(
      with scores as (select pp.user_id, sum(pp.points)::int points from pool_points pp where pp.pool_id=b.id group by pp.user_id),
      r as (
        select row_number() over (order by sc.points desc, sc.user_id) position, sc.*, gp.display_name, gp.avatar_url
        from scores sc join game_players gp on gp.id=sc.user_id
        where sc.points>=s.minimum_points
          and not coalesce(gp.pvp_banned,false)
          and (select count(*) from player_heroes h where h.user_id=sc.user_id)>=min_h
        order by sc.points desc limit 100
      )
      select coalesce(jsonb_agg(jsonb_build_object('position',position,'playerId',user_id,'name',coalesce(display_name,'Jogador'),'avatarUrl',avatar_url,'points',points,'eligible',true,'estimatedPrizeTon',0) order by position),'[]') from r
    ),
    'history',(
      select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'weekLabel',h.week_label,'amountTon',h.amount_ton,'winnerCount',h.winner_count,'playerRewardTon',coalesce((select sum(amount_ton) from pool_rewards where history_id=h.id and user_id=u.id),0),'distributedAt',h.distributed_at) order by h.distributed_at desc),'[]')
      from (select * from pool_history order by distributed_at desc limit 12) h
    )
  );
end$$;

REVOKE EXECUTE ON FUNCTION public.get_community_pool_dashboard(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_community_pool_dashboard(bigint) TO service_role;