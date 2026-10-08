CREATE OR REPLACE FUNCTION public.distribute_community_pool(p_force boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
declare
  b pool_balance%rowtype;
  s pool_settings%rowtype;
  h uuid;
  seed text;
  ranking_total numeric;
  lottery_total numeric;
  ranking_nano bigint;
  lottery_nano bigint;
  paid_nano bigint;
  v_winner_count int;
  v_participants int;
  min_h int;
  adj record;
  remaining numeric;
  r record;
  cut numeric;
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

  ranking_total := round(b.balance_ton * s.ranking_share_percent / 100, 9);
  lottery_total := round(b.balance_ton * s.lottery_share_percent / 100, 9);
  ranking_nano := floor(ranking_total * 1000000000)::bigint;
  lottery_nano := floor(lottery_total * 1000000000)::bigint;

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

  select least(count(*), least(100, coalesce(s.ranking_winner_limit,100)))::int into v_participants from _pool_scores;

  with ranked as (
    select user_id, points, row_number() over (order by points desc, user_id)::int pos from _pool_scores
  ), alloc as (
    select * from public.pool_ranking_allocation(ranking_total, v_participants)
  )
  insert into pool_rewards(history_id,user_id,reward_type,position,amount_ton,idempotency_key)
  select h, rk.user_id, 'ranking', rk.pos, a.amount_ton,
         'pool_reward:'||h||':ranking:'||rk.user_id
  from ranked rk join alloc a on a.rank_position = rk.pos
  where a.amount_nanoton > 0
  on conflict do nothing;

  if v_participants > 0 then
    select coalesce(sum(round(amount_ton*1000000000)),0)::bigint into paid_nano
      from pool_rewards where history_id=h and reward_type='ranking';
    if paid_nano <> ranking_nano then
      raise exception 'INVALID_DISTRIBUTION: ranking allocated % of % nanoton', paid_nano, ranking_nano;
    end if;
  end if;

  with draw as (
    select user_id, points,
      row_number() over (
        order by (-ln(greatest(.000000001,
          (('x'||substr(encode(digest(seed||user_id::text,'sha256'),'hex'),1,15))::bit(60)::bigint)::numeric
          / 1152921504606846976)))/greatest(1,points)
      ) pick
    from _pool_scores
  ), winners as (
    select user_id, pick from draw where pick <= least(s.lottery_winner_count,(select count(*) from _pool_scores))
  ), cnt as (select greatest(1,count(*))::bigint n from winners),
  split as (
    select w.user_id, w.pick,
      (lottery_nano / (select n from cnt))
        + case when w.pick <= (lottery_nano % (select n from cnt)) then 1 else 0 end as nano
    from winners w
  )
  insert into pool_rewards(history_id,user_id,reward_type,amount_ton,idempotency_key)
  select h, user_id, 'lottery', (nano::numeric/1000000000), 'pool_reward:'||h||':lottery:'||user_id
  from split where nano > 0
  on conflict do nothing;

  if exists(select 1 from pool_rewards where history_id=h and reward_type='lottery') then
    select coalesce(sum(round(amount_ton*1000000000)),0)::bigint into paid_nano
      from pool_rewards where history_id=h and reward_type='lottery';
    if paid_nano <> lottery_nano then
      raise exception 'INVALID_DISTRIBUTION: raffle allocated % of % nanoton', paid_nano, lottery_nano;
    end if;
  end if;

  for adj in
    select * from pool_reward_adjustments
    where applied_at is null and delta_ton < 0
      and (pool_id is null or pool_id = b.id)
    order by created_at
  loop
    remaining := abs(adj.delta_ton);
    for r in
      select id, amount_ton from pool_rewards
      where history_id = h and user_id = adj.user_id and amount_ton > 0
      order by amount_ton desc
    loop
      exit when remaining <= 0;
      cut := least(remaining, r.amount_ton);
      if round(r.amount_ton - cut, 9) <= 0 then
        delete from pool_rewards where id = r.id;
      else
        update pool_rewards set amount_ton = round(r.amount_ton - cut, 9) where id = r.id;
      end if;
      remaining := remaining - cut;
    end loop;
    update pool_reward_adjustments
      set applied_at = now(), applied_history_id = h
      where id = adj.id;
  end loop;

  delete from pool_rewards where history_id = h and amount_ton <= 0;

  insert into pool_winners(history_id,user_id,winner_type,position,points)
  select h, r2.user_id, r2.reward_type, r2.position,
         coalesce((select points from _pool_scores sc where sc.user_id = r2.user_id),0)
  from pool_rewards r2 where r2.history_id = h
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
$function$;
