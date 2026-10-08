-- ============================================================
-- RUÍNAS ANCESTRAIS — custo de entrada (FC / TON) + recompensas por tier
-- ============================================================

alter table public.ancient_ruin_runs
  add column if not exists entry_tier text not null default 'fc',
  add column if not exists entry_cost_fc bigint not null default 0,
  add column if not exists entry_cost_ton numeric(20,9) not null default 0;

alter table public.ancient_ruin_runs drop constraint if exists ancient_ruin_runs_entry_tier_chk;
alter table public.ancient_ruin_runs
  add constraint ancient_ruin_runs_entry_tier_chk check (entry_tier in ('fc','ton'));

create table if not exists public.realm_ruin_entry_config (
  id boolean primary key default true check (id),
  fc_cost bigint not null default 100000,
  ton_cost numeric(20,9) not null default 0.5,
  ton_reward_multiplier numeric not null default 1.6,
  updated_at timestamptz not null default now()
);

grant select on public.realm_ruin_entry_config to authenticated;
grant all on public.realm_ruin_entry_config to service_role;
alter table public.realm_ruin_entry_config enable row level security;
drop policy if exists "ruin entry config readable" on public.realm_ruin_entry_config;
create policy "ruin entry config readable" on public.realm_ruin_entry_config
  for select to authenticated using (true);

insert into public.realm_ruin_entry_config(id) values (true) on conflict (id) do nothing;

-- ── START: cobra a entrada antes de criar a run ───────────────
create or replace function public.realm_ruin_start(p_user uuid, p_region text, p_tier text default 'fc')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare r record; prof record; cfg record; v_run uuid; v_tier text; v_fc bigint := 0; v_ton numeric := 0; v_ok int;
begin
  perform realm_ensure_profile(p_user);
  v_tier := lower(coalesce(p_tier,'fc'));
  if v_tier not in ('fc','ton') then raise exception 'REALM_TIER_UNKNOWN'; end if;

  select * into cfg from realm_ruin_entry_config where id;
  select * into prof from realm_profiles where user_id=p_user;
  select * into r from realm_regions where id=p_region and enabled and ruin_enabled;
  if r is null then raise exception 'REALM_REGION_UNKNOWN'; end if;
  if prof.stronghold_level < r.unlock_stronghold_level then raise exception 'REALM_REGION_LOCKED'; end if;

  if exists(select 1 from ancient_ruin_runs where user_id=p_user and status='running') then
    return realm_state(p_user);
  end if;

  if v_tier = 'fc' then
    v_fc := coalesce(cfg.fc_cost, 100000);
    update game_players set forge_coins = forge_coins - v_fc
     where id = p_user and forge_coins >= v_fc;
    if not found then raise exception 'REALM_NO_FC'; end if;
  else
    v_ton := coalesce(cfg.ton_cost, 0.5);
    update game_players set ton_balance = ton_balance - v_ton
     where id = p_user and (ton_balance - coalesce(ton_reserved,0)) >= v_ton;
    if not found then raise exception 'REALM_NO_TON'; end if;
  end if;

  insert into ancient_ruin_runs(user_id, region_id, seed, hp, entry_tier, entry_cost_fc, entry_cost_ton)
  values (p_user, p_region, floor(random()*9007199254740991)::bigint, 100, v_tier, v_fc, v_ton)
  returning id into v_run;

  perform realm_ruin_build_rooms(v_run, 0);
  select 1 into v_ok;
  return realm_state(p_user);
end $function$;

-- compat: assinatura antiga entra como FC
create or replace function public.realm_ruin_start(p_user uuid, p_region text)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$ select public.realm_ruin_start(p_user, p_region, 'fc') $function$;

-- ── CHOOSE: loot escala com profundidade e com o tier de entrada ──
create or replace function public.realm_ruin_choose(p_user uuid, p_run uuid, p_branch integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare run record; room record; cfg record; v_dmg int; v_coins int; v_mat text; v_qty int; v_log jsonb; v_mult numeric;
begin
  select * into run from ancient_ruin_runs where id=p_run and user_id=p_user and status='running' for update;
  if run is null then raise exception 'REALM_RUN_UNKNOWN'; end if;

  select * into room from ancient_ruin_rooms
   where run_id=p_run and room_index=run.current_room and branch=p_branch and status='open' for update;
  if room is null then raise exception 'REALM_ROOM_UNKNOWN'; end if;

  select * into cfg from realm_ruin_entry_config where id;
  -- salas mais profundas pagam mais; entrada TON paga mais que entrada FC
  v_mult := (1 + run.current_room * 0.12)
          * (case when run.entry_tier = 'ton' then coalesce(cfg.ton_reward_multiplier, 1.6) else 1 end);

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
    v_qty := ceil((4 + floor(random()*8)) * (case when run.entry_tier='ton' then 1.8 else 1 end));
  elsif room.room_type='shrine' then
    v_coins := 30 + floor(random()*40);
    run.buffs := run.buffs || jsonb_build_array(jsonb_build_object('id','shrine_blessing','value',5));
  elsif room.room_type='rest' then
    v_dmg := -(12 + floor(random()*14));
  end if;

  v_coins := floor(v_coins * v_mult);

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
end $function$;

-- ── FINISH: recompensas por tier (entrada FC nunca paga TON) ──
create or replace function public.realm_ruin_finish(p_user uuid, p_run uuid, p_cleared boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare run record; cfg record; v_fc numeric; v_mat text; v_qty int; v_frag int; v_myth numeric := 0;
        v_key text := null; v_chest text := null; v_reward jsonb; v_premium boolean;
begin
  select * into run from ancient_ruin_runs where id=p_run and user_id=p_user for update;
  if run is null or run.status <> 'running' then return '{}'::jsonb; end if;

  select * into cfg from realm_ruin_entry_config where id;
  v_premium := run.entry_tier = 'ton';

  v_fc := floor(run.ruin_coins * (case when p_cleared then 55 else 30 end)
                * (case when v_premium then 1.5 else 1 end));
  update game_players set forge_coins = forge_coins + v_fc where id=p_user;

  select id into v_mat from realm_materials where enabled and region_id=run.region_id order by random() limit 1;
  v_qty := ceil(((case when p_cleared then 18 else 8 end) + floor(random()*10))
                * (case when v_premium then 2 else 1 end));
  if v_mat is not null then
    perform realm_material_add(p_user, v_mat, v_qty, case when p_cleared then 'ruin_clear' else 'ruin_extract' end, p_run::text);
  end if;

  v_frag := (case when p_cleared then 5 else 2 end) * (case when v_premium then 3 else 1 end);
  perform realm_grant_item(p_user, 'universal_fragment', v_frag);

  if v_premium then
    -- MYTH garantido + chaves/baús premium
    v_myth := 300 + floor(random()*500);
    if random() < 0.45 then v_key := case when random() < 0.7 then 'eternity_key' else 'void_key' end; end if;
    v_chest := case when p_cleared and random() < 0.35 then 'legendary_chest' else 'epic_chest' end;
  else
    if random() < 0.08 then v_myth := 50; end if;
    if p_cleared and random() < 0.25 then v_chest := 'rare_chest'; end if;
  end if;

  if v_myth > 0 then
    update game_players
       set hero_mining_unclaimed_myth = coalesce(hero_mining_unclaimed_myth,0) + v_myth,
           hero_mining_lifetime_myth = coalesce(hero_mining_lifetime_myth,0) + v_myth
     where id = p_user;
  end if;

  if v_key is not null then
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (p_user, 'tower_key', v_key, 1)
    on conflict (user_id, item_type, item_code) do update
      set quantity = player_inventory.quantity + 1;
  end if;

  if v_chest is not null then
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (p_user, 'resource_chest', v_chest, 1)
    on conflict (user_id, item_type, item_code) do update
      set quantity = player_inventory.quantity + 1;
  end if;

  v_reward := jsonb_build_object(
    'fc', v_fc, 'material', v_mat, 'qty', v_qty, 'cleared', p_cleared,
    'fragments', v_frag, 'myth', v_myth, 'key', v_key, 'chest', v_chest,
    'tier', run.entry_tier
  );

  update ancient_ruin_runs
     set status = case when p_cleared then 'cleared' else 'extracted' end,
         completed_at=now(), loot=v_reward
   where id=p_run;

  update realm_profiles set ruins_completed=ruins_completed+1, realm_xp=realm_xp+60, updated_at=now() where user_id=p_user;
  update realm_bounties set progress=progress+1
   where user_id=p_user and bounty_type='ruin' and status='active' and bounty_day=(now() at time zone 'utc')::date;

  return v_reward;
end $function$;

-- ── STATS: histórico para a tela de lobby das Ruínas ──────────
create or replace function public.realm_ruin_stats(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'runs', (select count(*) from ancient_ruin_runs where user_id=p_user and status <> 'running'),
    'clears', (select count(*) from ancient_ruin_runs where user_id=p_user and status='cleared'),
    'deepest', (select coalesce(max(current_room), 0) from ancient_ruin_runs where user_id=p_user),
    'bestLoot', (select coalesce(max(ruin_coins), 0) from ancient_ruin_runs where user_id=p_user),
    'recent', (
      select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
        select jsonb_build_object(
                 'at', completed_at, 'region', region_id, 'status', status,
                 'room', current_room, 'loot', ruin_coins, 'tier', entry_tier,
                 'fc', (loot->>'fc')
               ) as x
          from ancient_ruin_runs
         where user_id=p_user and status <> 'running'
         order by completed_at desc nulls last
         limit 5
      ) s
    )
  )
$function$;
