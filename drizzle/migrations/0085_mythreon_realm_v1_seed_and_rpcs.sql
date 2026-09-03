-- ============================================================
-- MYTHREON REALM :: V1 SEED + SERVER-SIDE RPCS
-- Everything (timers, costs, rewards, randomness) is decided here.
-- Reached only through game-api (service role).
-- ============================================================

-- ---------- REGIONS ----------
insert into public.realm_regions(id,name,tagline,order_index,image_url,recommended_power,unlock_stronghold_level,unlock_requires_region,ruin_enabled)
values
 ('greenvale','Greenvale','Vales antigos guardados por raízes vivas',1,'/assets/game/realm/region-greenvale.jpg',0,1,null,true),
 ('crystal_rift','Crystal Rift','A fenda que canta em cristal e trovão',2,'/assets/game/realm/region-crystal-rift.jpg',2500,3,'greenvale',true),
 ('abyss','Abyss','O vazio abaixo de tudo o que respira',3,'/assets/game/realm/region-abyss.jpg',8000,6,'crystal_rift',true)
on conflict (id) do update set name=excluded.name, tagline=excluded.tagline, order_index=excluded.order_index,
 image_url=excluded.image_url, recommended_power=excluded.recommended_power,
 unlock_stronghold_level=excluded.unlock_stronghold_level, unlock_requires_region=excluded.unlock_requires_region;

-- ---------- MATERIALS ----------
insert into public.realm_materials(id,name,rarity,region_id,image_url,order_index)
values
 ('iron_ore','Minério de Ferro','common','greenvale','/assets/game/realm/mat-iron-ore.png',1),
 ('magic_wood','Madeira Arcana','common','greenvale','/assets/game/realm/mat-magic-wood.png',2),
 ('rune_dust','Pó Rúnico','uncommon','greenvale','/assets/game/realm/mat-rune-dust.png',3),
 ('crystal_shard','Fragmento de Cristal','rare','crystal_rift','/assets/game/realm/mat-crystal-shard.png',4),
 ('mythril','Mythril','rare','crystal_rift','/assets/game/realm/mat-mythril.png',5),
 ('void_crystal','Cristal do Vazio','epic','abyss','/assets/game/realm/mat-void-crystal.png',6),
 ('ancient_essence','Essência Ancestral','legendary','abyss','/assets/game/realm/mat-ancient-essence.png',7)
on conflict (id) do update set name=excluded.name, rarity=excluded.rarity, region_id=excluded.region_id,
 image_url=excluded.image_url, order_index=excluded.order_index;

-- ---------- BUILDINGS ----------
insert into public.realm_building_types(id,name,description,image_url,max_level,order_index,base_fc_cost,base_seconds,cost_materials)
values
 ('castle','Castelo','Coração do Stronghold. Define o nível máximo das outras construções.','/assets/game/realm/building-castle.png',10,1,50000,1800,'{"iron_ore":10,"magic_wood":10}'),
 ('forge','Forja','Libera receitas de crafting mais avançadas.','/assets/game/realm/building-forge.png',10,2,30000,1200,'{"iron_ore":12,"rune_dust":4}'),
 ('training_ground','Campo de Treino','Aumenta o bônus de expedição dos heróis.','/assets/game/realm/building-training.png',10,3,30000,1200,'{"magic_wood":12,"iron_ore":6}'),
 ('pet_sanctuary','Santuário de Pets','Melhora o rendimento de coleta dos pets.','/assets/game/realm/building-sanctuary.png',10,4,35000,1500,'{"magic_wood":10,"rune_dust":6}'),
 ('watchtower','Torre de Vigia','Revela rotas e reduz o tempo das expedições.','/assets/game/realm/building-watchtower.png',10,5,40000,1500,'{"iron_ore":8,"rune_dust":8}')
on conflict (id) do update set name=excluded.name, description=excluded.description, image_url=excluded.image_url,
 max_level=excluded.max_level, order_index=excluded.order_index, base_fc_cost=excluded.base_fc_cost,
 base_seconds=excluded.base_seconds, cost_materials=excluded.cost_materials;

-- ---------- RECIPES ----------
insert into public.realm_recipes(id,name,category,inputs,fc_cost,craft_seconds,min_forge_level,output_kind,output_ref,output_qty,order_index)
values
 ('refine_iron','Refinar Ferro','material','{"iron_ore":5}',2000,600,1,'material','mythril',1,1),
 ('rune_powder','Moer Pó Rúnico','material','{"magic_wood":6}',2500,900,1,'material','rune_dust',2,2),
 ('crystal_cut','Lapidar Cristal','material','{"crystal_shard":3,"rune_dust":2}',6000,1800,2,'material','mythril',2,3),
 ('void_condense','Condensar Vazio','material','{"void_crystal":2,"mythril":2}',15000,3600,4,'material','ancient_essence',1,4),
 ('craft_frag_pack','Pacote de Fragmentos','item','{"iron_ore":10,"rune_dust":5}',8000,1800,2,'item','universal_fragment',10,5),
 ('craft_frag_pack_big','Pacote Maior de Fragmentos','item','{"mythril":6,"rune_dust":10}',20000,3600,3,'item','universal_fragment',30,6),
 ('craft_pet_food','Ração Arcana','item','{"magic_wood":8,"rune_dust":4}',6000,1500,1,'item','pet_food',3,7),
 ('craft_hero_xp','Tomo de XP de Herói','item','{"rune_dust":8,"crystal_shard":2}',9000,1800,2,'item','hero_xp_tome',2,8),
 ('craft_pvp_ticket','Selo de Arena','item','{"iron_ore":15,"mythril":2}',12000,2400,3,'item','pvp_ticket',2,9),
 ('craft_equipment_chest','Baú de Equipamento','item','{"mythril":8,"void_crystal":1}',25000,5400,4,'item','equipment_chest',1,10),
 ('craft_eternity_key','Chave da Eternidade','item','{"void_crystal":3,"ancient_essence":1}',40000,7200,5,'item','eternity_key',1,11),
 ('craft_void_key','Chave do Vazio','item','{"void_crystal":4,"mythril":10}',45000,7200,5,'item','void_key',1,12)
on conflict (id) do update set name=excluded.name, category=excluded.category, inputs=excluded.inputs,
 fc_cost=excluded.fc_cost, craft_seconds=excluded.craft_seconds, min_forge_level=excluded.min_forge_level,
 output_kind=excluded.output_kind, output_ref=excluded.output_ref, output_qty=excluded.output_qty,
 order_index=excluded.order_index;

-- ============================================================
-- HELPERS
-- ============================================================
create or replace function public.realm_material_add(
  p_user uuid, p_material text, p_amount numeric, p_reason text, p_source text default null)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_before numeric; v_after numeric;
begin
  insert into realm_material_balances(user_id, material_id, amount)
  values (p_user, p_material, 0)
  on conflict (user_id, material_id) do nothing;

  select amount into v_before from realm_material_balances
   where user_id=p_user and material_id=p_material for update;

  v_after := v_before + p_amount;
  if v_after < 0 then
    raise exception 'REALM_INSUFFICIENT_MATERIAL:%', p_material;
  end if;

  update realm_material_balances set amount=v_after, updated_at=now()
   where user_id=p_user and material_id=p_material;

  insert into realm_material_ledger(user_id, material_id, amount, balance_before, balance_after, reason, source_id)
  values (p_user, p_material, p_amount, v_before, v_after, p_reason, p_source);

  return v_after;
end $$;

create or replace function public.realm_ensure_profile(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into realm_profiles(user_id, current_region) values (p_user, 'greenvale')
  on conflict (user_id) do nothing;

  insert into realm_buildings(user_id, building_type, level)
  select p_user, bt.id, case when bt.id='castle' then 1 else 0 end
    from realm_building_types bt where bt.enabled
  on conflict (user_id, building_type) do nothing;
end $$;

create or replace function public.realm_building_level(p_user uuid, p_type text)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select level from realm_buildings where user_id=p_user and building_type=p_type), 0)
$$;

create or replace function public.realm_grant_item(p_user uuid, p_code text, p_qty int)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into player_inventory(user_id, item_type, item_code, quantity)
  values (p_user, 'realm', p_code, p_qty)
  on conflict (user_id, item_type, item_code) do update
    set quantity = player_inventory.quantity + excluded.quantity;
end $$;

-- ============================================================
-- STATE
-- ============================================================
create or replace function public.realm_state(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  perform realm_ensure_profile(p_user);

  -- auto-finish timers (status only; rewards are paid on claim)
  update realm_buildings set status='ready'
   where user_id=p_user and status='upgrading' and upgrade_finishes_at <= now();
  update realm_expeditions set status='ready'
   where user_id=p_user and status='running' and finishes_at <= now();
  update realm_crafting_jobs set status='ready'
   where user_id=p_user and status='running' and finishes_at <= now();

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
    'bounties', (select coalesce(jsonb_agg(to_jsonb(bo) order by bo.title),'[]'::jsonb)
                   from realm_bounties bo where bo.user_id=p_user and bo.bounty_day=(now() at time zone 'utc')::date)
  ) into v;

  return v;
end $$;

-- ============================================================
-- BUILDINGS
-- ============================================================
create or replace function public.realm_building_upgrade(p_user uuid, p_type text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare bt record; b record; v_next int; v_fc numeric; v_secs int; v_castle int; m record; v_qty numeric;
begin
  perform realm_ensure_profile(p_user);
  select * into bt from realm_building_types where id=p_type and enabled;
  if bt is null then raise exception 'REALM_BUILDING_UNKNOWN'; end if;
  select * into b from realm_buildings where user_id=p_user and building_type=p_type for update;
  if b.status <> 'idle' then raise exception 'REALM_BUILDING_BUSY'; end if;

  v_next := b.level + 1;
  if v_next > bt.max_level then raise exception 'REALM_BUILDING_MAX'; end if;

  v_castle := realm_building_level(p_user,'castle');
  if p_type <> 'castle' and v_next > v_castle then raise exception 'REALM_CASTLE_TOO_LOW'; end if;

  v_fc := round(bt.base_fc_cost * power(1.55, b.level));
  v_secs := ceil(bt.base_seconds * power(1.4, b.level));

  update game_players set forge_coins = forge_coins - v_fc
   where id=p_user and forge_coins >= v_fc;
  if not found then raise exception 'REALM_NOT_ENOUGH_FC'; end if;

  for m in select key, value::text::numeric as qty from jsonb_each_text(bt.cost_materials) t(key,value) loop
    v_qty := ceil(m.qty * power(1.35, b.level));
    perform realm_material_add(p_user, m.key, -v_qty, 'building_upgrade', p_type);
  end loop;

  update realm_buildings
     set status='upgrading', upgrade_started_at=now(),
         upgrade_finishes_at=now() + make_interval(secs => v_secs), updated_at=now()
   where user_id=p_user and building_type=p_type;

  return realm_state(p_user);
end $$;

create or replace function public.realm_building_claim(p_user uuid, p_type text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record;
begin
  select * into b from realm_buildings where user_id=p_user and building_type=p_type for update;
  if b is null then raise exception 'REALM_BUILDING_UNKNOWN'; end if;
  if b.status='idle' then return realm_state(p_user); end if;
  if b.upgrade_finishes_at is null or b.upgrade_finishes_at > now() then raise exception 'REALM_NOT_READY'; end if;

  update realm_buildings
     set level=level+1, status='idle', upgrade_started_at=null, upgrade_finishes_at=null, updated_at=now()
   where user_id=p_user and building_type=p_type;

  update realm_profiles
     set buildings_upgraded=buildings_upgraded+1,
         stronghold_level = greatest(stronghold_level, realm_building_level(p_user,'castle')),
         realm_xp = realm_xp + 25, updated_at=now()
   where user_id=p_user;

  update realm_bounties set progress=progress+1
   where user_id=p_user and bounty_type='upgrade' and status='active' and bounty_day=(now() at time zone 'utc')::date;

  return realm_state(p_user);
end $$;

-- ============================================================
-- EXPEDITIONS (gathering)
-- ============================================================
create or replace function public.realm_expedition_start(
  p_user uuid, p_region text, p_type text, p_idem text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; prof record; v_secs int; v_running int; v_tower int;
begin
  perform realm_ensure_profile(p_user);
  select * into prof from realm_profiles where user_id=p_user;
  select * into r from realm_regions where id=p_region and enabled;
  if r is null then raise exception 'REALM_REGION_UNKNOWN'; end if;
  if prof.stronghold_level < r.unlock_stronghold_level then raise exception 'REALM_REGION_LOCKED'; end if;
  if p_type not in ('gather','deep') then raise exception 'REALM_EXPEDITION_TYPE'; end if;

  select count(*) into v_running from realm_expeditions
   where user_id=p_user and status in ('running','ready');
  if v_running >= 3 then raise exception 'REALM_EXPEDITION_SLOTS_FULL'; end if;

  v_secs := case when p_type='gather' then 900 else 3600 end;
  v_tower := realm_building_level(p_user,'watchtower');
  v_secs := greatest(120, floor(v_secs * (1 - least(0.30, v_tower * 0.03))));

  insert into realm_expeditions(user_id, region_id, expedition_type, finishes_at, reward_seed, idempotency_key)
  values (p_user, p_region, p_type, now() + make_interval(secs => v_secs),
          floor(random()*9007199254740991)::bigint, p_idem)
  on conflict (user_id, idempotency_key) do nothing;

  return realm_state(p_user);
end $$;

create or replace function public.realm_expedition_claim(p_user uuid, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e record; mats record; v_reward jsonb := '{}'::jsonb; v_mult numeric; v_qty numeric; v_fc numeric;
begin
  select * into e from realm_expeditions where id=p_id and user_id=p_user for update;
  if e is null then raise exception 'REALM_EXPEDITION_UNKNOWN'; end if;
  if e.claimed_at is not null then return realm_state(p_user); end if;
  if e.finishes_at > now() then raise exception 'REALM_NOT_READY'; end if;

  v_mult := case when e.expedition_type='deep' then 3.2 else 1 end
          * (1 + realm_building_level(p_user,'training_ground') * 0.04)
          * (1 + realm_building_level(p_user,'pet_sanctuary') * 0.03);

  for mats in select id from realm_materials where enabled and region_id=e.region_id order by order_index loop
    v_qty := floor(((3 + random()*5) * v_mult));
    if v_qty > 0 then
      perform realm_material_add(p_user, mats.id, v_qty, 'expedition', e.id::text);
      v_reward := v_reward || jsonb_build_object(mats.id, v_qty);
    end if;
  end loop;

  v_fc := floor((1500 + random()*2500) * case when e.expedition_type='deep' then 3 else 1 end);
  update game_players set forge_coins = forge_coins + v_fc where id=p_user;
  v_reward := v_reward || jsonb_build_object('fc', v_fc);

  update realm_expeditions set status='claimed', claimed_at=now(), reward=v_reward where id=p_id;
  update realm_profiles set realm_xp=realm_xp+15, updated_at=now() where user_id=p_user;
  update realm_bounties set progress=progress+1
   where user_id=p_user and bounty_type='expedition' and status='active' and bounty_day=(now() at time zone 'utc')::date;

  return realm_state(p_user) || jsonb_build_object('lastReward', v_reward);
end $$;

-- ============================================================
-- CRAFTING
-- ============================================================
create or replace function public.realm_craft_start(p_user uuid, p_recipe text, p_qty int, p_idem text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rc record; m record; v_secs int; v_forge int; v_running int; v_fc numeric; v_qty int;
begin
  perform realm_ensure_profile(p_user);
  v_qty := greatest(1, least(10, coalesce(p_qty,1)));
  select * into rc from realm_recipes where id=p_recipe and enabled;
  if rc is null then raise exception 'REALM_RECIPE_UNKNOWN'; end if;

  v_forge := realm_building_level(p_user,'forge');
  if v_forge < rc.min_forge_level then raise exception 'REALM_FORGE_TOO_LOW'; end if;

  select count(*) into v_running from realm_crafting_jobs where user_id=p_user and status in ('running','ready');
  if v_running >= 2 + floor(v_forge/3) then raise exception 'REALM_CRAFT_SLOTS_FULL'; end if;

  v_fc := rc.fc_cost * v_qty;
  update game_players set forge_coins = forge_coins - v_fc where id=p_user and forge_coins >= v_fc;
  if not found then raise exception 'REALM_NOT_ENOUGH_FC'; end if;

  for m in select key, value::text::numeric as qty from jsonb_each_text(rc.inputs) t(key,value) loop
    perform realm_material_add(p_user, m.key, -(m.qty * v_qty), 'craft_start', rc.id);
  end loop;

  v_secs := greatest(60, floor(rc.craft_seconds * v_qty * (1 - least(0.35, v_forge*0.035))));

  insert into realm_crafting_jobs(user_id, recipe_id, quantity, finishes_at, idempotency_key)
  values (p_user, rc.id, v_qty, now() + make_interval(secs => v_secs), p_idem)
  on conflict (user_id, idempotency_key) do nothing;

  return realm_state(p_user);
end $$;

create or replace function public.realm_craft_claim(p_user uuid, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; rc record; v_total int; v_reward jsonb;
begin
  select * into j from realm_crafting_jobs where id=p_id and user_id=p_user for update;
  if j is null then raise exception 'REALM_CRAFT_UNKNOWN'; end if;
  if j.claimed_at is not null then return realm_state(p_user); end if;
  if j.finishes_at > now() then raise exception 'REALM_NOT_READY'; end if;

  select * into rc from realm_recipes where id=j.recipe_id;
  v_total := rc.output_qty * j.quantity;

  if rc.output_kind='material' then
    perform realm_material_add(p_user, rc.output_ref, v_total, 'craft_claim', j.id::text);
  else
    perform realm_grant_item(p_user, rc.output_ref, v_total);
  end if;

  v_reward := jsonb_build_object('kind', rc.output_kind, 'ref', rc.output_ref, 'qty', v_total, 'name', rc.name);

  update realm_crafting_jobs set status='claimed', claimed_at=now() where id=p_id;
  update realm_profiles set crafts_completed=crafts_completed+1, realm_xp=realm_xp+20, updated_at=now() where user_id=p_user;
  update realm_bounties set progress=progress+1
   where user_id=p_user and bounty_type='craft' and status='active' and bounty_day=(now() at time zone 'utc')::date;

  return realm_state(p_user) || jsonb_build_object('lastReward', v_reward);
end $$;

-- ============================================================
-- ANCIENT RUINS (roguelike, server-side rooms)
-- ============================================================
create or replace function public.realm_ruin_build_rooms(p_run uuid, p_room int)
returns void language plpgsql security definer set search_path = public as $$
declare i int; v_types text[] := array['combat','treasure','trap','shrine','elite','rest'];
begin
  for i in 0..1 loop
    insert into ancient_ruin_rooms(run_id, room_index, branch, room_type, config, status)
    values (p_run, p_room, i,
      case when p_room >= 9 then 'boss' else v_types[1 + floor(random()*array_length(v_types,1))::int] end,
      jsonb_build_object('difficulty', p_room + 1), 'open')
    on conflict (run_id, room_index, branch) do nothing;
  end loop;
end $$;

create or replace function public.realm_ruin_start(p_user uuid, p_region text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; prof record; v_run uuid;
begin
  perform realm_ensure_profile(p_user);
  select * into prof from realm_profiles where user_id=p_user;
  select * into r from realm_regions where id=p_region and enabled and ruin_enabled;
  if r is null then raise exception 'REALM_REGION_UNKNOWN'; end if;
  if prof.stronghold_level < r.unlock_stronghold_level then raise exception 'REALM_REGION_LOCKED'; end if;

  if exists(select 1 from ancient_ruin_runs where user_id=p_user and status='running') then
    return realm_state(p_user);
  end if;

  insert into ancient_ruin_runs(user_id, region_id, seed, hp)
  values (p_user, p_region, floor(random()*9007199254740991)::bigint, 100)
  returning id into v_run;

  perform realm_ruin_build_rooms(v_run, 0);
  return realm_state(p_user);
end $$;

create or replace function public.realm_ruin_choose(p_user uuid, p_run uuid, p_branch int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare run record; room record; v_dmg int; v_coins int; v_mat text; v_qty int; v_log jsonb;
begin
  select * into run from ancient_ruin_runs where id=p_run and user_id=p_user and status='running' for update;
  if run is null then raise exception 'REALM_RUN_UNKNOWN'; end if;

  select * into room from ancient_ruin_rooms
   where run_id=p_run and room_index=run.current_room and branch=p_branch and status='open' for update;
  if room is null then raise exception 'REALM_ROOM_UNKNOWN'; end if;

  v_dmg := 0; v_coins := 0; v_log := jsonb_build_object('roomType', room.room_type);

  if room.room_type in ('combat','elite','boss') then
    v_dmg := case room.room_type when 'combat' then 8 + floor(random()*10)
                                 when 'elite' then 16 + floor(random()*14)
                                 else 22 + floor(random()*18) end;
    v_coins := case room.room_type when 'combat' then 40 + floor(random()*40)
                                    when 'elite' then 110 + floor(random()*90)
                                    else 260 + floor(random()*160) end;
  elsif room.room_type='trap' then
    v_dmg := 6 + floor(random()*12);
    v_coins := 20 + floor(random()*30);
  elsif room.room_type='treasure' then
    v_coins := 90 + floor(random()*120);
    select id into v_mat from realm_materials where enabled and region_id=run.region_id order by random() limit 1;
    v_qty := 4 + floor(random()*8);
  elsif room.room_type='shrine' then
    v_coins := 30 + floor(random()*40);
    run.buffs := run.buffs || jsonb_build_array(jsonb_build_object('id','shrine_blessing','value',5));
  elsif room.room_type='rest' then
    v_dmg := -(12 + floor(random()*14));
  end if;

  if v_mat is not null and v_qty > 0 then
    perform realm_material_add(p_user, v_mat, v_qty, 'ruin_room', p_run::text);
    v_log := v_log || jsonb_build_object('material', v_mat, 'qty', v_qty);
  end if;

  update ancient_ruin_rooms set status='resolved', resolved_at=now() where id=room.id;
  update ancient_ruin_rooms set status='skipped' where run_id=p_run and room_index=run.current_room and id<>room.id;

  update ancient_ruin_runs
     set hp = greatest(0, least(100, hp - v_dmg)),
         ruin_coins = ruin_coins + v_coins,
         buffs = run.buffs,
         current_room = run.current_room + 1
   where id=p_run
   returning * into run;

  v_log := v_log || jsonb_build_object('damage', v_dmg, 'coins', v_coins, 'hp', run.hp);

  if run.hp <= 0 then
    update ancient_ruin_runs set status='failed', completed_at=now() where id=p_run;
    v_log := v_log || jsonb_build_object('result','failed');
  elsif run.current_room >= 10 then
    perform realm_ruin_finish(p_user, p_run, true);
    v_log := v_log || jsonb_build_object('result','cleared');
  else
    perform realm_ruin_build_rooms(p_run, run.current_room);
  end if;

  return realm_state(p_user) || jsonb_build_object('lastRoom', v_log);
end $$;

create or replace function public.realm_ruin_finish(p_user uuid, p_run uuid, p_cleared boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare run record; v_fc numeric; v_mat text; v_qty int; v_reward jsonb;
begin
  select * into run from ancient_ruin_runs where id=p_run and user_id=p_user for update;
  if run is null or run.status <> 'running' then return '{}'::jsonb; end if;

  v_fc := floor(run.ruin_coins * (case when p_cleared then 55 else 30 end));
  update game_players set forge_coins = forge_coins + v_fc where id=p_user;

  select id into v_mat from realm_materials where enabled and region_id=run.region_id order by random() limit 1;
  v_qty := (case when p_cleared then 18 else 8 end) + floor(random()*10);
  if v_mat is not null then
    perform realm_material_add(p_user, v_mat, v_qty, case when p_cleared then 'ruin_clear' else 'ruin_extract' end, p_run::text);
  end if;

  if p_cleared then perform realm_grant_item(p_user, 'universal_fragment', 5); end if;

  v_reward := jsonb_build_object('fc', v_fc, 'material', v_mat, 'qty', v_qty, 'cleared', p_cleared);

  update ancient_ruin_runs
     set status = case when p_cleared then 'cleared' else 'extracted' end,
         completed_at=now(), loot=v_reward
   where id=p_run;

  update realm_profiles set ruins_completed=ruins_completed+1, realm_xp=realm_xp+60, updated_at=now() where user_id=p_user;
  update realm_bounties set progress=progress+1
   where user_id=p_user and bounty_type='ruin' and status='active' and bounty_day=(now() at time zone 'utc')::date;

  return v_reward;
end $$;

create or replace function public.realm_ruin_extract(p_user uuid, p_run uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  v := realm_ruin_finish(p_user, p_run, false);
  return realm_state(p_user) || jsonb_build_object('lastReward', v);
end $$;

-- ============================================================
-- DAILY BOUNTIES
-- ============================================================
create or replace function public.realm_bounties_ensure(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_day date := (now() at time zone 'utc')::date;
begin
  perform realm_ensure_profile(p_user);
  if exists(select 1 from realm_bounties where user_id=p_user and bounty_day=v_day) then
    return realm_state(p_user);
  end if;

  insert into realm_bounties(user_id, bounty_day, bounty_type, title, target, reward, expires_at)
  values
   (p_user, v_day, 'expedition', 'Conclua 3 expedições', 3, '{"fc":40000,"fragments":5}', (v_day + 1)::timestamptz),
   (p_user, v_day, 'craft', 'Finalize 2 crafts', 2, '{"fc":30000,"fragments":3}', (v_day + 1)::timestamptz),
   (p_user, v_day, 'ruin', 'Explore 1 Ruína Ancestral', 1, '{"fc":60000,"fragments":8}', (v_day + 1)::timestamptz);

  update realm_profiles set bounties_day=v_day, updated_at=now() where user_id=p_user;
  return realm_state(p_user);
end $$;

create or replace function public.realm_bounty_claim(p_user uuid, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; v_fc numeric; v_frag int;
begin
  select * into b from realm_bounties where id=p_id and user_id=p_user for update;
  if b is null then raise exception 'REALM_BOUNTY_UNKNOWN'; end if;
  if b.status <> 'active' then return realm_state(p_user); end if;
  if b.progress < b.target then raise exception 'REALM_BOUNTY_INCOMPLETE'; end if;

  v_fc := coalesce((b.reward->>'fc')::numeric, 0);
  v_frag := coalesce((b.reward->>'fragments')::int, 0);
  if v_fc > 0 then update game_players set forge_coins = forge_coins + v_fc where id=p_user; end if;
  if v_frag > 0 then perform realm_grant_item(p_user, 'universal_fragment', v_frag); end if;

  update realm_bounties set status='claimed', claimed_at=now() where id=p_id;
  update realm_profiles set realm_xp=realm_xp+30, updated_at=now() where user_id=p_user;

  return realm_state(p_user) || jsonb_build_object('lastReward', b.reward);
end $$;