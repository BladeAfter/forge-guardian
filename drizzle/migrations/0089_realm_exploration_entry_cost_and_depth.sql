-- =============================================================
-- MYTHREON REALM — EXPLORATION ENTRY COST + PROGRESSIVE DEPTH
-- Server-authoritative: FC debit, depth progression, scaling and loot.
-- =============================================================

-- 1. Per-region tunables (Admin Bot configurable, no deploy needed)
alter table public.realm_regions
  add column if not exists entry_cost_base    bigint  not null default 100000,
  add column if not exists entry_cost_growth  numeric not null default 0.05,
  add column if not exists entry_cost_max     bigint  not null default 500000,
  add column if not exists hp_growth          numeric not null default 0.12,
  add column if not exists atk_growth         numeric not null default 0.08,
  add column if not exists def_growth         numeric not null default 0.05,
  add column if not exists loot_growth        numeric not null default 0.035,
  add column if not exists loot_growth_max    numeric not null default 1.80,
  add column if not exists power_base         bigint  not null default 100000,
  add column if not exists power_growth       numeric not null default 0.20,
  add column if not exists boss_interval      int     not null default 10,
  add column if not exists max_depth          int     not null default 100;

update public.realm_regions set
  entry_cost_base = 100000, entry_cost_max = 500000, power_base = 100000
 where id = 'greenvale';
update public.realm_regions set
  entry_cost_base = 200000, entry_cost_max = 900000, power_base = 200000
 where id = 'crystal_rift';
update public.realm_regions set
  entry_cost_base = 350000, entry_cost_max = 1500000, power_base = 350000
 where id = 'abyss';

-- 2. Per-player, per-region depth progression
create table if not exists public.realm_region_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  region_id text not null references public.realm_regions(id) on delete cascade,
  highest_completed_depth int not null default 0,
  current_depth int not null default 1,
  total_runs int not null default 0,
  successful_runs int not null default 0,
  failed_runs int not null default 0,
  updated_at timestamptz not null default now(),
  unique (user_id, region_id)
);

grant select on public.realm_region_progress to authenticated;
grant all on public.realm_region_progress to service_role;
alter table public.realm_region_progress enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='realm_region_progress' and policyname='realm_progress_owner_read') then
    create policy realm_progress_owner_read on public.realm_region_progress
      for select to authenticated using (user_id = auth.uid());
  end if;
end $$;

-- 3. Run snapshot columns
alter table public.realm_explore_runs
  add column if not exists depth_level int not null default 1,
  add column if not exists entry_cost numeric not null default 0,
  add column if not exists difficulty jsonb not null default '{}'::jsonb,
  add column if not exists loot_multiplier numeric not null default 1;

-- 4. Cost / stats helpers -------------------------------------------------
create or replace function public.realm_entry_cost(p_region text, p_depth int)
returns numeric language sql stable security definer set search_path = public as $$
  select least(r.entry_cost_max::numeric,
               floor(r.entry_cost_base::numeric * (1 + (greatest(1, p_depth) - 1) * r.entry_cost_growth)))
    from realm_regions r where r.id = p_region
$$;

create or replace function public.realm_depth_tier(p_depth int)
returns text language sql immutable as $$
  select case
    when p_depth <= 5 then 'normal'
    when p_depth <= 10 then 'hard'
    when p_depth <= 20 then 'elite'
    when p_depth <= 30 then 'mythic'
    else 'abyssal' end
$$;

/** Difficulty snapshot for a region+depth. Always BASE x DEPTH MULTIPLIER (never compounded). */
create or replace function public.realm_depth_stats(p_region text, p_depth int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r record; d int; v_nodes int;
begin
  select * into r from realm_regions where id = p_region;
  if r is null then raise exception 'REALM_REGION_UNKNOWN'; end if;
  d := greatest(1, least(coalesce(p_depth, 1), r.max_depth));
  v_nodes := case when d <= 5 then 6 when d <= 15 then 8 else 10 end
             + least(2, coalesce(r.order_index, 1) - 1);
  return jsonb_build_object(
    'depth', d,
    'tier', realm_depth_tier(d),
    'hpMult',  round(1 + (d - 1) * r.hp_growth, 4),
    'atkMult', round(1 + (d - 1) * r.atk_growth, 4),
    'defMult', round(1 + (d - 1) * r.def_growth, 4),
    'lootMult', round(least(r.loot_growth_max, 1 + (d - 1) * r.loot_growth), 4),
    'entryCost', realm_entry_cost(p_region, d),
    'recommendedPower', floor(r.power_base::numeric * (1 + (d - 1) * r.power_growth)),
    'nodes', v_nodes,
    'isBossDepth', (r.boss_interval > 0 and d % r.boss_interval = 0),
    'isEliteDepth', (d % 5 = 0),
    'maxDepth', r.max_depth
  );
end $$;

create or replace function public.realm_progress_row(p_user uuid, p_region text)
returns public.realm_region_progress language plpgsql security definer set search_path = public as $$
declare row public.realm_region_progress;
begin
  insert into realm_region_progress(user_id, region_id)
  values (p_user, p_region)
  on conflict (user_id, region_id) do nothing;
  select * into row from realm_region_progress where user_id = p_user and region_id = p_region;
  return row;
end $$;

-- 5. START — atomic FC debit + depth snapshot ----------------------------
create or replace function public.realm_explore_start(p_user uuid, p_region text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r record; prof record; prog public.realm_region_progress;
  v_run uuid; v_stats jsonb; v_cost numeric; v_fc numeric; v_depth int;
begin
  perform realm_ensure_profile(p_user);
  select * into prof from realm_profiles where user_id = p_user;
  select * into r from realm_regions where id = p_region and enabled;
  if r is null then raise exception 'REALM_REGION_UNKNOWN'; end if;
  if prof.stronghold_level < r.unlock_stronghold_level then raise exception 'REALM_REGION_LOCKED'; end if;

  -- one active run at a time: never charges twice
  if exists (select 1 from realm_explore_runs where user_id = p_user and status = 'running') then
    return realm_state(p_user);
  end if;

  prog := realm_progress_row(p_user, p_region);
  v_depth := greatest(1, least(prog.current_depth, r.max_depth));
  v_stats := realm_depth_stats(p_region, v_depth);
  v_cost := (v_stats->>'entryCost')::numeric;

  -- lock the wallet row, validate and debit in the same transaction as the run insert
  select forge_coins into v_fc from game_players where id = p_user for update;
  if v_fc is null then raise exception 'REALM_PLAYER_UNKNOWN'; end if;
  if v_fc < v_cost then raise exception 'REALM_INSUFFICIENT_FC'; end if;

  update game_players set forge_coins = forge_coins - v_cost where id = p_user;

  insert into realm_explore_runs(
    user_id, region_id, hp, final_depth, depth_level, entry_cost, difficulty, loot_multiplier)
  values (
    p_user, p_region, 100, (v_stats->>'nodes')::int, v_depth, v_cost, v_stats,
    (v_stats->>'lootMult')::numeric)
  returning id into v_run;

  update realm_region_progress
     set total_runs = total_runs + 1, updated_at = now()
   where user_id = p_user and region_id = p_region;

  perform realm_explore_build(v_run, 0);
  return realm_state(p_user);
end $$;

-- 6. BUILD — depth-aware node difficulty --------------------------------
create or replace function public.realm_explore_build(p_run uuid, p_depth integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  run record; v_lanes int; i int; v_pool text[]; v_type text; v_used text[] := '{}';
  v_scale numeric; v_boss boolean;
begin
  select * into run from realm_explore_runs where id = p_run;
  if run is null then return; end if;

  v_scale := coalesce((run.difficulty->>'atkMult')::numeric, 1);
  v_boss := coalesce((run.difficulty->>'isBossDepth')::boolean, false);

  if p_depth >= run.final_depth then
    insert into realm_explore_nodes(run_id, depth, lane, node_type, status, config)
    values (p_run, p_depth, 1, 'boss', 'available',
            jsonb_build_object(
              'difficulty', ceil((p_depth + 2) * v_scale)::int,
              'depthLevel', run.depth_level,
              'greaterBoss', v_boss,
              'hpMult', coalesce(run.difficulty->>'hpMult','1')::numeric,
              'atkMult', v_scale,
              'defMult', coalesce(run.difficulty->>'defMult','1')::numeric,
              'x', 88, 'y', 50))
    on conflict (run_id, depth, lane) do nothing;
    return;
  end if;

  v_pool := case
    when p_depth = 0 then array['gather','combat','event','treasure']
    when run.depth_level >= 6 and p_depth >= 2 then array['combat','elite','elite','gather','treasure','event','trap','shrine','rest']
    when p_depth >= 3 then array['combat','elite','gather','treasure','event','trap','shrine','rest']
    else array['combat','gather','treasure','event','trap','shrine','rest']
  end;

  v_lanes := 2 + floor(random()*2)::int;
  for i in 0..(v_lanes - 1) loop
    v_type := v_pool[1 + floor(random()*array_length(v_pool,1))::int];
    if v_type = any(v_used) then
      v_type := v_pool[1 + floor(random()*array_length(v_pool,1))::int];
    end if;
    v_used := v_used || v_type;
    insert into realm_explore_nodes(run_id, depth, lane, node_type, status, config)
    values (p_run, p_depth, i, v_type, 'available',
            jsonb_build_object(
              'difficulty', ceil((p_depth + 1) * v_scale)::int,
              'depthLevel', run.depth_level,
              'hpMult', coalesce(run.difficulty->>'hpMult','1')::numeric,
              'atkMult', v_scale,
              'defMult', coalesce(run.difficulty->>'defMult','1')::numeric,
              'x', 8 + (p_depth::numeric * (76.0 / greatest(1, run.final_depth))),
              'y', case v_lanes when 2 then 30 + i*40 else 20 + i*30 end
            ))
    on conflict (run_id, depth, lane) do nothing;
  end loop;
end $$;

-- 7. FINISH — loot multiplier + depth unlock -----------------------------
create or replace function public.realm_explore_finish(p_user uuid, p_run uuid, p_outcome text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  run record; v_mult numeric; v_fc numeric; v_frag int; v_mats jsonb; k text;
  v_reward jsonb; v_next int; v_stats jsonb;
begin
  select * into run from realm_explore_runs where id = p_run and user_id = p_user for update;
  if run is null or run.status <> 'running' then return '{}'::jsonb; end if;

  if p_outcome = 'failed' then
    update realm_explore_runs set status='failed', completed_at=now(), pending=null where id = p_run;
    update realm_region_progress
       set failed_runs = failed_runs + 1, updated_at = now()
     where user_id = p_user and region_id = run.region_id;
    return jsonb_build_object('outcome','failed','lost', run.loot, 'depth', run.depth_level);
  end if;

  v_mult := coalesce(run.loot_multiplier, 1) * case when p_outcome = 'cleared' then 1.25 else 1 end;
  v_fc := floor(coalesce((run.loot->>'fc')::numeric, 0) * v_mult);
  v_frag := floor(coalesce((run.loot->>'fragments')::numeric, 0) * v_mult)::int
            + case when p_outcome = 'cleared' then 5 + floor(run.depth_level / 5)::int else 0 end;
  v_mats := coalesce(run.loot->'materials', '{}'::jsonb);

  if v_fc > 0 then
    update game_players set forge_coins = forge_coins + v_fc where id = p_user;
  end if;
  if v_frag > 0 then
    perform realm_grant_item(p_user, 'universal_fragment', v_frag);
  end if;
  for k in select jsonb_object_keys(v_mats) loop
    perform realm_material_add(p_user, k, floor((v_mats->>k)::numeric * v_mult),
                               'explore_' || p_outcome, p_run::text);
  end loop;

  v_reward := jsonb_build_object('outcome', p_outcome, 'fc', v_fc, 'fragments', v_frag,
                                 'materials', v_mats, 'depth', run.depth_level,
                                 'lootMultiplier', v_mult);

  -- only a full completion unlocks the next depth (extraction does not)
  if p_outcome = 'cleared' then
    perform realm_progress_row(p_user, run.region_id);
    select max_depth into v_next from realm_regions where id = run.region_id;
    update realm_region_progress
       set highest_completed_depth = greatest(highest_completed_depth, run.depth_level),
           current_depth = least(coalesce(v_next, 100), greatest(current_depth, run.depth_level + 1)),
           successful_runs = successful_runs + 1,
           updated_at = now()
     where user_id = p_user and region_id = run.region_id;
    select current_depth into v_next from realm_region_progress
     where user_id = p_user and region_id = run.region_id;
    v_stats := realm_depth_stats(run.region_id, v_next);
    v_reward := v_reward || jsonb_build_object('nextDepth', v_next, 'nextStats', v_stats);
  end if;

  update realm_explore_runs
     set status = case when p_outcome = 'cleared' then 'cleared' else 'extracted' end,
         completed_at = now(), pending = null, loot = v_reward
   where id = p_run;

  update realm_profiles
     set realm_xp = realm_xp + case when p_outcome = 'cleared' then 80 else 35 end,
         updated_at = now()
   where user_id = p_user;

  update realm_bounties set progress = progress + 1
   where user_id = p_user and bounty_type = 'expedition' and status = 'active'
     and bounty_day = (now() at time zone 'utc')::date;

  return v_reward;
end $$;

-- 8. Region meta for the client (cost, depth, recommended power) ---------
create or replace function public.realm_region_meta(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  select coalesce(jsonb_agg(x order by x.order_index), '[]'::jsonb) into v
  from (
    select r.order_index,
           jsonb_build_object(
             'regionId', r.id,
             'depth', greatest(1, least(coalesce(p.current_depth, 1), r.max_depth)),
             'bestDepth', coalesce(p.highest_completed_depth, 0),
             'totalRuns', coalesce(p.total_runs, 0),
             'successfulRuns', coalesce(p.successful_runs, 0),
             'failedRuns', coalesce(p.failed_runs, 0),
             'stats', realm_depth_stats(r.id, greatest(1, least(coalesce(p.current_depth, 1), r.max_depth)))
           ) as j
      from realm_regions r
      left join realm_region_progress p on p.region_id = r.id and p.user_id = p_user
     where r.enabled
  ) t(order_index, j), lateral (select t.order_index, t.j) x(order_index, j);
  return v;
end $$;
