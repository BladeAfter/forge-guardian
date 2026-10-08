-- Region meta (fixed aggregation) + Admin Bot exploration settings

create or replace function public.realm_region_meta(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  select coalesce(jsonb_agg(j order by ord), '[]'::jsonb) into v
  from (
    select r.order_index as ord,
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
  ) t;
  return v;
end $$;

-- Expose it through realm_state
create or replace function public.realm_state(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
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
    'regionMeta', realm_region_meta(p_user),
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

-- Admin Bot: read every region tunable
create or replace function public.admin_realm_exploration_overview()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'regionId', r.id, 'name', r.name, 'enabled', r.enabled,
      'entryCostBase', r.entry_cost_base, 'entryCostGrowth', r.entry_cost_growth,
      'entryCostMax', r.entry_cost_max,
      'hpGrowth', r.hp_growth, 'atkGrowth', r.atk_growth, 'defGrowth', r.def_growth,
      'lootGrowth', r.loot_growth, 'lootGrowthMax', r.loot_growth_max,
      'powerBase', r.power_base, 'powerGrowth', r.power_growth,
      'bossInterval', r.boss_interval, 'maxDepth', r.max_depth,
      'sample', jsonb_build_object(
        'depth1', realm_depth_stats(r.id, 1),
        'depth5', realm_depth_stats(r.id, 5),
        'depth10', realm_depth_stats(r.id, 10))
    ) order by r.order_index), '[]'::jsonb)
  from realm_regions r
$$;

-- Admin Bot: update tunables without deploy (only provided keys change)
create or replace function public.admin_realm_exploration_set(p_region text, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update realm_regions r set
    entry_cost_base   = coalesce((p_patch->>'entryCostBase')::bigint, r.entry_cost_base),
    entry_cost_growth = coalesce((p_patch->>'entryCostGrowth')::numeric, r.entry_cost_growth),
    entry_cost_max    = coalesce((p_patch->>'entryCostMax')::bigint, r.entry_cost_max),
    hp_growth         = coalesce((p_patch->>'hpGrowth')::numeric, r.hp_growth),
    atk_growth        = coalesce((p_patch->>'atkGrowth')::numeric, r.atk_growth),
    def_growth        = coalesce((p_patch->>'defGrowth')::numeric, r.def_growth),
    loot_growth       = coalesce((p_patch->>'lootGrowth')::numeric, r.loot_growth),
    loot_growth_max   = coalesce((p_patch->>'lootGrowthMax')::numeric, r.loot_growth_max),
    power_base        = coalesce((p_patch->>'powerBase')::bigint, r.power_base),
    power_growth      = coalesce((p_patch->>'powerGrowth')::numeric, r.power_growth),
    boss_interval     = coalesce((p_patch->>'bossInterval')::int, r.boss_interval),
    max_depth         = coalesce((p_patch->>'maxDepth')::int, r.max_depth),
    enabled           = coalesce((p_patch->>'enabled')::boolean, r.enabled)
  where r.id = p_region;
  if not found then raise exception 'REALM_REGION_UNKNOWN'; end if;
  return admin_realm_exploration_overview();
end $$;

-- Admin Bot: inspect / adjust a player's depth
create or replace function public.admin_realm_player_depth(p_user uuid, p_region text, p_depth int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare row public.realm_region_progress;
begin
  row := realm_progress_row(p_user, p_region);
  if p_depth is not null then
    update realm_region_progress
       set current_depth = greatest(1, p_depth),
           highest_completed_depth = greatest(highest_completed_depth, greatest(0, p_depth - 1)),
           updated_at = now()
     where user_id = p_user and region_id = p_region
    returning * into row;
  end if;
  return to_jsonb(row) || jsonb_build_object('stats', realm_depth_stats(p_region, row.current_depth));
end $$;
