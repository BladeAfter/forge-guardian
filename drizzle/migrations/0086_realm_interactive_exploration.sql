-- ============================================================
-- MYTHREON REALM — INTERACTIVE EXPLORATION (server-authoritative)
-- Node-based exploration runs: paths, events, quick combat,
-- gradual loot and extract-or-continue. Old timer expeditions
-- stay untouched as the secondary/AFK system.
-- ============================================================

create table if not exists public.realm_explore_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  region_id text not null,
  seed bigint not null default floor(random()*9007199254740991)::bigint,
  hp int not null default 100,
  depth int not null default 0,
  final_depth int not null default 5,
  risk int not null default 0,
  loot jsonb not null default '{}'::jsonb,
  log jsonb not null default '[]'::jsonb,
  pending jsonb,
  auto boolean not null default false,
  status text not null default 'running',
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.realm_explore_nodes (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.realm_explore_runs(id) on delete cascade,
  depth int not null,
  lane int not null,
  node_type text not null,
  status text not null default 'locked',
  config jsonb not null default '{}'::jsonb,
  resolved_at timestamptz,
  unique (run_id, depth, lane)
);

create index if not exists realm_explore_runs_user_idx on public.realm_explore_runs(user_id, status);
create index if not exists realm_explore_nodes_run_idx on public.realm_explore_nodes(run_id, depth);

grant select on public.realm_explore_runs to authenticated;
grant all on public.realm_explore_runs to service_role;
grant select on public.realm_explore_nodes to authenticated;
grant all on public.realm_explore_nodes to service_role;

alter table public.realm_explore_runs enable row level security;
alter table public.realm_explore_nodes enable row level security;

drop policy if exists "own explore runs" on public.realm_explore_runs;
create policy "own explore runs" on public.realm_explore_runs
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "own explore nodes" on public.realm_explore_nodes;
create policy "own explore nodes" on public.realm_explore_nodes
  for select to authenticated using (
    exists (select 1 from public.realm_explore_runs r where r.id = run_id and r.user_id = auth.uid())
  );

-- ------------------------------------------------------------
-- Build the next depth of the path (2-3 branching nodes, boss at the end)
-- ------------------------------------------------------------
create or replace function public.realm_explore_build(p_run uuid, p_depth int)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare run record; v_lanes int; i int; v_pool text[]; v_type text; v_used text[] := '{}';
begin
  select * into run from realm_explore_runs where id = p_run;
  if run is null then return; end if;

  if p_depth >= run.final_depth then
    insert into realm_explore_nodes(run_id, depth, lane, node_type, status, config)
    values (p_run, p_depth, 1, 'boss', 'available',
            jsonb_build_object('difficulty', p_depth + 2, 'x', 88, 'y', 50))
    on conflict (run_id, depth, lane) do nothing;
    return;
  end if;

  v_pool := case
    when p_depth = 0 then array['gather','combat','event','treasure']
    when p_depth >= 3 then array['combat','elite','gather','treasure','event','trap','shrine','rest']
    else array['combat','gather','treasure','event','trap','shrine','rest']
  end;

  v_lanes := 2 + floor(random()*2)::int; -- 2 or 3 branches
  for i in 0..(v_lanes - 1) loop
    v_type := v_pool[1 + floor(random()*array_length(v_pool,1))::int];
    if v_type = any(v_used) then
      v_type := v_pool[1 + floor(random()*array_length(v_pool,1))::int];
    end if;
    v_used := v_used || v_type;
    insert into realm_explore_nodes(run_id, depth, lane, node_type, status, config)
    values (p_run, p_depth, i, v_type, 'available',
            jsonb_build_object(
              'difficulty', p_depth + 1,
              'x', 8 + (p_depth::numeric * (76.0 / greatest(1, run.final_depth))),
              'y', case v_lanes when 2 then 30 + i*40 else 20 + i*30 end
            ))
    on conflict (run_id, depth, lane) do nothing;
  end loop;
end $$;

-- ------------------------------------------------------------
-- Start a run
-- ------------------------------------------------------------
create or replace function public.realm_explore_start(p_user uuid, p_region text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare r record; prof record; v_run uuid; v_final int;
begin
  perform realm_ensure_profile(p_user);
  select * into prof from realm_profiles where user_id = p_user;
  select * into r from realm_regions where id = p_region and enabled;
  if r is null then raise exception 'REALM_REGION_UNKNOWN'; end if;
  if prof.stronghold_level < r.unlock_stronghold_level then raise exception 'REALM_REGION_LOCKED'; end if;

  if exists (select 1 from realm_explore_runs where user_id = p_user and status = 'running') then
    return realm_state(p_user);
  end if;

  v_final := 5 + least(2, coalesce(r.order_index, 0));

  insert into realm_explore_runs(user_id, region_id, hp, final_depth)
  values (p_user, p_region, 100, v_final)
  returning id into v_run;

  perform realm_explore_build(v_run, 0);
  return realm_state(p_user);
end $$;

-- ------------------------------------------------------------
-- Finish (extract / cleared / failed) — loot is only credited here
-- ------------------------------------------------------------
create or replace function public.realm_explore_finish(p_user uuid, p_run uuid, p_outcome text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare run record; v_mult numeric; v_fc numeric; v_frag int; v_mats jsonb; k text; v_reward jsonb;
begin
  select * into run from realm_explore_runs where id = p_run and user_id = p_user for update;
  if run is null or run.status <> 'running' then return '{}'::jsonb; end if;

  if p_outcome = 'failed' then
    update realm_explore_runs
       set status = 'failed', completed_at = now(), pending = null
     where id = p_run;
    return jsonb_build_object('outcome', 'failed', 'lost', run.loot);
  end if;

  v_mult := case when p_outcome = 'cleared' then 1.25 else 1 end;
  v_fc := floor(coalesce((run.loot->>'fc')::numeric, 0) * v_mult);
  v_frag := floor(coalesce((run.loot->>'fragments')::numeric, 0) * v_mult)::int
            + case when p_outcome = 'cleared' then 5 else 0 end;
  v_mats := coalesce(run.loot->'materials', '{}'::jsonb);

  if v_fc > 0 then
    update game_players set forge_coins = forge_coins + v_fc where id = p_user;
  end if;
  if v_frag > 0 then
    perform realm_grant_item(p_user, 'universal_fragment', v_frag);
  end if;
  for k in select jsonb_object_keys(v_mats) loop
    perform realm_material_add(p_user, k, floor((v_mats->>k)::numeric * v_mult), 'explore_' || p_outcome, p_run::text);
  end loop;

  v_reward := jsonb_build_object('outcome', p_outcome, 'fc', v_fc, 'fragments', v_frag, 'materials', v_mats);

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

-- ------------------------------------------------------------
-- Apply a node (with an optional choice) — the core gameplay roll
-- ------------------------------------------------------------
create or replace function public.realm_explore_apply(p_user uuid, p_run uuid, p_node uuid, p_option text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  run record; node record; v_diff int; v_dmg int := 0; v_fc numeric := 0; v_frag int := 0;
  v_mat text; v_qty numeric := 0; v_loot jsonb; v_mats jsonb; v_log jsonb; v_rounds jsonb := '[]'::jsonb;
  i int; v_win boolean := true; v_type text;
begin
  select * into run from realm_explore_runs where id = p_run and user_id = p_user and status = 'running' for update;
  if run is null then raise exception 'REALM_RUN_UNKNOWN'; end if;
  select * into node from realm_explore_nodes where id = p_node and run_id = p_run for update;
  if node is null or node.depth <> run.depth or node.status not in ('available','active') then
    raise exception 'REALM_NODE_UNKNOWN';
  end if;

  v_type := node.node_type;
  v_diff := greatest(1, coalesce((node.config->>'difficulty')::int, 1));
  select id into v_mat from realm_materials where enabled and region_id = run.region_id order by random() limit 1;

  if v_type in ('combat','elite','boss') then
    for i in 1..3 loop
      v_rounds := v_rounds || jsonb_build_array(jsonb_build_object(
        'round', i,
        'playerHit', 40 + floor(random()*60)::int * v_diff,
        'enemyHit', 5 + floor(random()*8)::int
      ));
    end loop;
    v_dmg := case v_type when 'combat' then 6 + floor(random()*10)::int
                          when 'elite' then 14 + floor(random()*12)::int
                          else 20 + floor(random()*16)::int end;
    if p_option = 'careful' then v_dmg := greatest(2, v_dmg - 6); end if;
    v_fc := floor((350 + random()*450) * v_diff
              * case v_type when 'elite' then 2.2 when 'boss' then 3.4 else 1 end);
    v_qty := floor((2 + random()*4) * v_diff);
    if v_type in ('elite','boss') then v_frag := 1 + floor(random()*3)::int; end if;

  elsif v_type = 'gather' then
    if p_option = 'force' then
      v_qty := floor((6 + random()*8) * v_diff);
      v_dmg := 8 + floor(random()*12)::int;
      if random() < 0.35 then v_frag := 1; end if;
    elsif p_option = 'ignore' then
      v_qty := 0;
    else
      v_qty := floor((3 + random()*5) * v_diff);
    end if;
    v_fc := floor(120 * v_diff * (case when p_option = 'ignore' then 0 else 1 end));

  elsif v_type = 'treasure' then
    if p_option = 'force' then
      v_fc := floor((900 + random()*1200) * v_diff);
      v_frag := 2 + floor(random()*3)::int;
      if random() < 0.45 then v_dmg := 10 + floor(random()*14)::int; end if;
    elsif p_option = 'ignore' then
      v_fc := 0;
    else
      v_fc := floor((450 + random()*550) * v_diff);
      if random() < 0.3 then v_frag := 1; end if;
    end if;

  elsif v_type = 'event' then
    if p_option = 'accept' then
      if random() < 0.6 then
        v_fc := floor((600 + random()*900) * v_diff);
        v_frag := 1 + floor(random()*2)::int;
      else
        v_dmg := 12 + floor(random()*16)::int;
      end if;
    elsif p_option = 'offer' then
      v_qty := floor((4 + random()*6) * v_diff);
      v_dmg := 4 + floor(random()*6)::int;
    else
      v_fc := floor(150 * v_diff);
    end if;

  elsif v_type = 'shrine' then
    if p_option = 'empower' then
      v_fc := floor((500 + random()*600) * v_diff);
      v_dmg := 8 + floor(random()*8)::int;
    else
      v_dmg := -(18 + floor(random()*14)::int);
    end if;

  elsif v_type = 'rest' then
    v_dmg := -(22 + floor(random()*16)::int);

  elsif v_type = 'trap' then
    if p_option = 'careful' then
      v_dmg := 4 + floor(random()*6)::int;
    else
      v_dmg := 10 + floor(random()*14)::int;
      v_fc := floor((300 + random()*400) * v_diff);
    end if;
  end if;

  -- accumulate loot on the run (nothing is credited before extraction)
  v_loot := coalesce(run.loot, '{}'::jsonb);
  v_mats := coalesce(v_loot->'materials', '{}'::jsonb);
  if v_mat is not null and v_qty > 0 then
    v_mats := v_mats || jsonb_build_object(v_mat, coalesce((v_mats->>v_mat)::numeric, 0) + v_qty);
  end if;
  v_loot := jsonb_build_object(
    'fc', coalesce((v_loot->>'fc')::numeric, 0) + v_fc,
    'fragments', coalesce((v_loot->>'fragments')::numeric, 0) + v_frag,
    'materials', v_mats
  );

  update realm_explore_nodes set status = 'resolved', resolved_at = now() where id = p_node;
  update realm_explore_nodes set status = 'skipped'
   where run_id = p_run and depth = run.depth and id <> p_node;

  v_log := jsonb_build_object(
    'nodeType', v_type, 'option', p_option, 'damage', v_dmg,
    'fc', v_fc, 'fragments', v_frag, 'material', v_mat, 'materialQty', v_qty,
    'rounds', case when v_type in ('combat','elite','boss') then v_rounds else '[]'::jsonb end,
    'win', v_win
  );

  update realm_explore_runs
     set hp = greatest(0, least(100, hp - v_dmg)),
         loot = v_loot,
         depth = run.depth + 1,
         risk = least(100, (run.depth + 1) * (100 / greatest(1, run.final_depth + 1))),
         pending = null,
         log = (coalesce(log, '[]'::jsonb) || jsonb_build_array(v_log))
   where id = p_run
  returning * into run;

  v_log := v_log || jsonb_build_object('hp', run.hp, 'depth', run.depth, 'risk', run.risk, 'loot', run.loot);

  if run.hp <= 0 then
    perform realm_explore_finish(p_user, p_run, 'failed');
    v_log := v_log || jsonb_build_object('result', 'failed');
  elsif v_type = 'boss' or run.depth > run.final_depth then
    v_log := v_log || jsonb_build_object('result', 'cleared',
      'reward', realm_explore_finish(p_user, p_run, 'cleared'));
  else
    perform realm_explore_build(p_run, run.depth);
    v_log := v_log || jsonb_build_object('result', 'ongoing');
  end if;

  return v_log;
end $$;

-- ------------------------------------------------------------
-- Enter a node: interactive types open a choice, the rest resolve now
-- ------------------------------------------------------------
create or replace function public.realm_explore_enter(p_user uuid, p_run uuid, p_node uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare run record; node record; v_pending jsonb; v_log jsonb;
begin
  select * into run from realm_explore_runs where id = p_run and user_id = p_user and status = 'running' for update;
  if run is null then raise exception 'REALM_RUN_UNKNOWN'; end if;
  select * into node from realm_explore_nodes where id = p_node and run_id = p_run;
  if node is null or node.depth <> run.depth or node.status = 'resolved' then raise exception 'REALM_NODE_UNKNOWN'; end if;

  if node.node_type in ('gather','treasure','event','shrine','trap') then
    v_pending := jsonb_build_object(
      'nodeId', p_node,
      'nodeType', node.node_type,
      'options', case node.node_type
        when 'gather'   then jsonb_build_array('safe','force','ignore')
        when 'treasure' then jsonb_build_array('safe','force','ignore')
        when 'event'    then jsonb_build_array('accept','offer','ignore')
        when 'shrine'   then jsonb_build_array('bless','empower')
        else jsonb_build_array('careful','force')
      end
    );
    update realm_explore_nodes set status = 'active' where id = p_node;
    update realm_explore_runs set pending = v_pending where id = p_run;
    return realm_state(p_user) || jsonb_build_object('lastNode', v_pending || jsonb_build_object('result','pending'));
  end if;

  v_log := realm_explore_apply(p_user, p_run, p_node, 'default');
  return realm_state(p_user) || jsonb_build_object('lastNode', v_log);
end $$;

-- ------------------------------------------------------------
-- Resolve a pending choice
-- ------------------------------------------------------------
create or replace function public.realm_explore_choose(p_user uuid, p_run uuid, p_option text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare run record; v_node uuid; v_log jsonb;
begin
  select * into run from realm_explore_runs where id = p_run and user_id = p_user and status = 'running';
  if run is null or run.pending is null then raise exception 'REALM_RUN_UNKNOWN'; end if;
  v_node := (run.pending->>'nodeId')::uuid;
  if not (run.pending->'options' ? p_option) then raise exception 'REALM_OPTION_UNKNOWN'; end if;
  v_log := realm_explore_apply(p_user, p_run, v_node, p_option);
  return realm_state(p_user) || jsonb_build_object('lastNode', v_log);
end $$;

-- ------------------------------------------------------------
-- Extract now (bank the loot)
-- ------------------------------------------------------------
create or replace function public.realm_explore_extract(p_user uuid, p_run uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v jsonb;
begin
  v := realm_explore_finish(p_user, p_run, 'extracted');
  return realm_state(p_user) || jsonb_build_object('lastReward', v);
end $$;

-- ------------------------------------------------------------
-- AUTO EXPLORE — safe choices until the end (or extraction on low HP)
-- ------------------------------------------------------------
create or replace function public.realm_explore_auto(p_user uuid, p_run uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare run record; node record; v_log jsonb := '[]'::jsonb; v_step jsonb; guard int := 0;
begin
  loop
    guard := guard + 1;
    exit when guard > 20;
    select * into run from realm_explore_runs where id = p_run and user_id = p_user and status = 'running';
    exit when run is null;

    if run.hp <= 35 and run.depth > 0 then
      v_step := realm_explore_finish(p_user, p_run, 'extracted');
      v_log := v_log || jsonb_build_array(jsonb_build_object('result','auto-extract','reward',v_step));
      exit;
    end if;

    select * into node from realm_explore_nodes
     where run_id = p_run and depth = run.depth and status in ('available','active')
     order by case node_type when 'rest' then 0 when 'shrine' then 1 when 'gather' then 2
                             when 'treasure' then 3 when 'event' then 4 when 'combat' then 5
                             when 'trap' then 6 else 7 end
     limit 1;
    exit when node is null;

    v_step := realm_explore_apply(p_user, p_run, node.id,
      case node.node_type
        when 'gather' then 'safe' when 'treasure' then 'safe' when 'event' then 'accept'
        when 'shrine' then 'bless' when 'trap' then 'careful' else 'default' end);
    v_log := v_log || jsonb_build_array(v_step);
    exit when (v_step->>'result') <> 'ongoing';
  end loop;

  return realm_state(p_user) || jsonb_build_object('autoLog', v_log);
end $$;

-- ------------------------------------------------------------
-- Abandon a stuck run
-- ------------------------------------------------------------
create or replace function public.realm_explore_abandon(p_user uuid, p_run uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update realm_explore_runs set status = 'failed', completed_at = now(), pending = null
   where id = p_run and user_id = p_user and status = 'running';
  return realm_state(p_user);
end $$;

-- ------------------------------------------------------------
-- Expose the active run in realm_state
-- ------------------------------------------------------------
create or replace function public.realm_state(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v jsonb; v_run uuid;
begin
  perform realm_ensure_profile(p_user);

  update realm_buildings set status='ready'
   where user_id=p_user and status='upgrading' and upgrade_finishes_at <= now();
  update realm_expeditions set status='ready'
   where user_id=p_user and status='running' and finishes_at <= now();
  update realm_crafting_jobs set status='ready'
   where user_id=p_user and status='running' and finishes_at <= now();

  select id into v_run from realm_explore_runs
   where user_id=p_user and status='running' order by started_at desc limit 1;

  select jsonb_build_object(
    'profile', (select to_jsonb(rp) from realm_profiles rp where rp.user_id=p_user),
    'fc', (select forge_coins from game_players where id=p_user),
    'regions', (select coalesce(jsonb_agg(to_jsonb(r) order by r.order_index),'[]'::jsonb) from realm_regions r where r.enabled),
    'materials', (select coalesce(jsonb_agg(to_jsonb(m) order by m.order_index),'[]'::jsonb) from realm_materials m where m.enabled),
    'buildingTypes', (select coalesce(jsonb_agg(to_jsonb(bt) order by bt.order_index),'[]'::jsonb) from realm_building_types bt where bt.enabled),
    'recipes', (select coalesce(jsonb_agg(to_jsonb(rc) order by rc.order_index),'[]'::jsonb) from realm_recipes rc where rc.enabled),
    'buildings', (select coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb) from realm_buildings b where b.user_id=p_user),
    'balances', (select coalesce(jsonb_object_agg(mb.material_id, mb.amount),'{}'::jsonb) from realm_material_balances mb where mb.user_id=p_user),
    'expeditions', (select coalesce(jsonb_agg(to_jsonb(e) order by e.started_at desc),'[]'::jsonb) from realm_expeditions e where e.user_id=p_user and e.status in ('running','ready')),
    'crafting', (select coalesce(jsonb_agg(to_jsonb(c) order by c.started_at desc),'[]'::jsonb) from realm_crafting_jobs c where c.user_id=p_user and c.status in ('running','ready')),
    'ruinRun', (select to_jsonb(rr) from ancient_ruin_runs rr where rr.user_id=p_user and rr.status='running' order by rr.started_at desc limit 1),
    'ruinRooms', (select coalesce(jsonb_agg(to_jsonb(ro) order by ro.room_index, ro.branch),'[]'::jsonb)
                    from ancient_ruin_rooms ro
                   where ro.run_id = (select id from ancient_ruin_runs where user_id=p_user and status='running' order by started_at desc limit 1)),
    'exploreRun', (select to_jsonb(er) from realm_explore_runs er where er.id = v_run),
    'exploreNodes', (select coalesce(jsonb_agg(to_jsonb(en) order by en.depth, en.lane),'[]'::jsonb)
                       from realm_explore_nodes en where en.run_id = v_run),
    'bounties', (select coalesce(jsonb_agg(to_jsonb(bo) order by bo.title),'[]'::jsonb)
                   from realm_bounties bo where bo.user_id=p_user and bo.bounty_day=(now() at time zone 'utc')::date)
  ) into v;

  return v;
end $$;