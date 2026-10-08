create or replace function public.realm_state(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
    'tonBalance', (select greatest(0, ton_balance - coalesce(ton_reserved,0)) from game_players where id=p_user),
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
    'ruinEntry', (select to_jsonb(c) from realm_ruin_entry_config c where c.id),
    'ruinStats', realm_ruin_stats(p_user),
    'exploreRun', (select to_jsonb(er) from realm_explore_runs er where er.id = v_run),
    'exploreNodes', (select coalesce(jsonb_agg(to_jsonb(en) order by en.depth, en.lane),'[]'::jsonb)
                       from realm_explore_nodes en where en.run_id = v_run),
    'bounties', (select coalesce(jsonb_agg(to_jsonb(bo) order by bo.title),'[]'::jsonb)
                   from realm_bounties bo where bo.user_id=p_user and bo.bounty_day=(now() at time zone 'utc')::date)
  ) into v;

  return v;
end $function$;
