-- Node difficulty stays base (loot is scaled once, at finish); depth scales enemy pressure.
create or replace function public.realm_explore_build(p_run uuid, p_depth integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  run record; v_lanes int; i int; v_pool text[]; v_type text; v_used text[] := '{}';
  v_hp numeric; v_atk numeric; v_def numeric; v_boss boolean;
begin
  select * into run from realm_explore_runs where id = p_run;
  if run is null then return; end if;

  v_hp  := coalesce((run.difficulty->>'hpMult')::numeric, 1);
  v_atk := coalesce((run.difficulty->>'atkMult')::numeric, 1);
  v_def := coalesce((run.difficulty->>'defMult')::numeric, 1);
  v_boss := coalesce((run.difficulty->>'isBossDepth')::boolean, false);

  if p_depth >= run.final_depth then
    insert into realm_explore_nodes(run_id, depth, lane, node_type, status, config)
    values (p_run, p_depth, 1, 'boss', 'available',
            jsonb_build_object('difficulty', p_depth + 2, 'depthLevel', run.depth_level,
              'greaterBoss', v_boss, 'hpMult', v_hp, 'atkMult', v_atk, 'defMult', v_def,
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
            jsonb_build_object('difficulty', p_depth + 1, 'depthLevel', run.depth_level,
              'hpMult', v_hp, 'atkMult', v_atk, 'defMult', v_def,
              'x', 8 + (p_depth::numeric * (76.0 / greatest(1, run.final_depth))),
              'y', case v_lanes when 2 then 30 + i*40 else 20 + i*30 end))
    on conflict (run_id, depth, lane) do nothing;
  end loop;
end $$;

-- Enemy damage / trap severity scale with depth (loot untouched here).
create or replace function public.realm_explore_apply(p_user uuid, p_run uuid, p_node uuid, p_option text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  run record; node record; v_diff int; v_dmg int := 0; v_fc numeric := 0; v_frag int := 0;
  v_mat text; v_qty numeric := 0; v_loot jsonb; v_mats jsonb; v_log jsonb; v_rounds jsonb := '[]'::jsonb;
  i int; v_win boolean := true; v_type text; v_atk numeric; v_hpm numeric;
begin
  select * into run from realm_explore_runs where id = p_run and user_id = p_user and status = 'running' for update;
  if run is null then raise exception 'REALM_RUN_UNKNOWN'; end if;
  select * into node from realm_explore_nodes where id = p_node and run_id = p_run for update;
  if node is null or node.depth <> run.depth or node.status not in ('available','active') then
    raise exception 'REALM_NODE_UNKNOWN';
  end if;

  v_type := node.node_type;
  v_diff := greatest(1, coalesce((node.config->>'difficulty')::int, 1));
  v_atk := greatest(1, coalesce((node.config->>'atkMult')::numeric, 1));
  v_hpm := greatest(1, coalesce((node.config->>'hpMult')::numeric, 1));
  select id into v_mat from realm_materials where enabled and region_id = run.region_id order by random() limit 1;

  if v_type in ('combat','elite','boss') then
    for i in 1..(2 + least(3, floor(v_hpm)::int)) loop
      v_rounds := v_rounds || jsonb_build_array(jsonb_build_object(
        'round', i,
        'playerHit', 40 + floor(random()*60)::int * v_diff,
        'enemyHit', ceil((5 + floor(random()*8)::int) * v_atk)::int
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

  -- depth pressure: only harmful damage scales (healing keeps its value)
  if v_dmg > 0 then v_dmg := ceil(v_dmg * v_atk)::int; end if;

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
    'depthLevel', run.depth_level,
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
