create table if not exists public.pool_reward_adjustments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  pool_id uuid,
  delta_ton numeric not null,
  reason text,
  applied_history_id uuid,
  applied_at timestamptz,
  created_by_admin bigint,
  created_at timestamptz not null default now()
);

grant all on public.pool_reward_adjustments to service_role;

alter table public.pool_reward_adjustments enable row level security;

create index if not exists pool_reward_adjustments_pending_idx
  on public.pool_reward_adjustments(user_id) where applied_at is null;

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

  -- manual deductions (e.g. already reimbursed off-cycle) applied before payout
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
      update pool_rewards set amount_ton = round(r.amount_ton - cut, 9) where id = r.id;
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
$fn$;

revoke all on function public.distribute_community_pool(boolean) from public;
grant execute on function public.distribute_community_pool(boolean) to service_role;