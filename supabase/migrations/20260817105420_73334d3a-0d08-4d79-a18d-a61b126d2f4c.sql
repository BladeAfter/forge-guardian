create or replace function public.distribute_community_pool(p_force boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  b pool_balance%rowtype;
  s pool_settings%rowtype;
  h uuid;
  seed text;
  ranking_total numeric;
  lottery_total numeric;
  v_winner_count int;
  min_h int;
begin
  perform pg_advisory_xact_lock(hashtext('community_pool_distribution'));
  select * into b from pool_balance where status='active' for update;
  if b.id is null then raise exception 'NO_ACTIVE_POOL'; end if;
  if not p_force and b.ends_at > now() then raise exception 'POOL_NOT_DUE'; end if;
  update pool_balance set status='distributing', updated_at=now() where id=b.id;

  select * into s from pool_settings where id;
  min_h := coalesce(s.minimum_heroes, 5);
  seed := encode(gen_random_bytes(32),'hex');

  insert into pool_history(pool_id,week_label,amount_ton,winner_count,seed_hash)
  values (b.id,b.week_label,b.balance_ton,0,encode(digest(seed,'sha256'),'hex'))
  returning id into h;

  ranking_total := b.balance_ton * s.ranking_share_percent / 100;
  lottery_total := b.balance_ton * s.lottery_share_percent / 100;

  create temporary table if not exists _pool_scores(user_id uuid primary key, points int) on commit drop;
  delete from _pool_scores;
  insert into _pool_scores(user_id, points)
  select pp.user_id, sum(pp.points)::int
  from pool_points pp
  join game_players gp on gp.id = pp.user_id
  where pp.pool_id = b.id
    and not coalesce(gp.pvp_banned,false)
    and (select count(*) from player_heroes x where x.user_id = pp.user_id) >= min_h
  group by pp.user_id
  having sum(pp.points) >= coalesce(s.minimum_points,500);

  with ranked as (
    select user_id, points, row_number() over (order by points desc, user_id) pos from _pool_scores
  ), awards as (
    select *, public.pool_ranking_share(pos::int) share from ranked
    where pos <= least(100, s.ranking_winner_limit)
  )
  insert into pool_rewards(history_id,user_id,reward_type,position,amount_ton,idempotency_key)
  select h, user_id, 'ranking', pos, greatest(.000000001, round(ranking_total * share, 9)),
         'pool_reward:'||h||':ranking:'||user_id
  from awards
  on conflict do nothing;

  with draw as (
    select user_id, points,
      row_number() over (
        order by (-ln(greatest(.000000001,
          (('x'||substr(encode(digest(seed||user_id::text,'sha256'),'hex'),1,15))::bit(60)::bigint)::numeric
          / 1152921504606846976)))/greatest(1,points)
      ) pick
    from _pool_scores
  )
  insert into pool_rewards(history_id,user_id,reward_type,amount_ton,idempotency_key)
  select h, user_id, 'lottery',
         round(lottery_total / greatest(1, least(s.lottery_winner_count,(select count(*) from _pool_scores))), 9),
         'pool_reward:'||h||':lottery:'||user_id
  from draw where pick <= s.lottery_winner_count
  on conflict do nothing;

  insert into pool_winners(history_id,user_id,winner_type,position,points)
  select h, r.user_id, r.reward_type, r.position,
         coalesce((select points from _pool_scores sc where sc.user_id = r.user_id),0)
  from pool_rewards r where r.history_id = h
  on conflict do nothing;

  select count(distinct user_id)::int into v_winner_count from pool_rewards where history_id = h;
  update pool_history set winner_count = v_winner_count where id = h;

  update pool_balance
    set status='distributed', distribution_key='pool_distribution:'||b.id, updated_at=now()
    where id=b.id;

  insert into pool_balance(week_label,starts_at,ends_at)
  values ('Temporada '||to_char(now(),'IYYY-IW'), now(), now()+make_interval(days=>s.season_days));

  return h;
end
$fn$;

revoke all on function public.distribute_community_pool(boolean) from public;
grant execute on function public.distribute_community_pool(boolean) to service_role;