-- ============================================================
-- MYTHREON REALM :: V1 CORE SCHEMA
-- All realm progression is server-side. Every table is reached
-- ONLY through the game-api edge function (service role), so no
-- anon/authenticated grants are issued on purpose.
-- ============================================================

create table if not exists public.realm_regions(
  id text primary key,
  name text not null,
  tagline text not null default '',
  order_index int not null default 0,
  image_url text,
  recommended_power int not null default 0,
  unlock_stronghold_level int not null default 1,
  unlock_requires_region text,
  ruin_enabled boolean not null default true,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.realm_materials(
  id text primary key,
  name text not null,
  rarity text not null default 'common',
  region_id text references public.realm_regions(id),
  image_url text,
  order_index int not null default 0,
  enabled boolean not null default true
);

create table if not exists public.realm_building_types(
  id text primary key,
  name text not null,
  description text not null default '',
  image_url text,
  max_level int not null default 10,
  order_index int not null default 0,
  base_fc_cost numeric not null default 25000,
  base_seconds int not null default 900,
  cost_materials jsonb not null default '{}'::jsonb,
  enabled boolean not null default true
);

create table if not exists public.realm_recipes(
  id text primary key,
  name text not null,
  category text not null default 'material',
  inputs jsonb not null default '{}'::jsonb,
  fc_cost numeric not null default 0,
  craft_seconds int not null default 1800,
  min_forge_level int not null default 1,
  output_kind text not null default 'material',
  output_ref text not null,
  output_qty int not null default 1,
  image_url text,
  order_index int not null default 0,
  enabled boolean not null default true
);

create table if not exists public.realm_profiles(
  user_id uuid primary key references public.game_players(id) on delete cascade,
  stronghold_level int not null default 1,
  realm_level int not null default 1,
  realm_xp int not null default 0,
  current_region text references public.realm_regions(id),
  ruins_completed int not null default 0,
  crafts_completed int not null default 0,
  buildings_upgraded int not null default 0,
  bounties_day date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.realm_buildings(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  building_type text not null references public.realm_building_types(id),
  level int not null default 0,
  status text not null default 'idle',
  upgrade_started_at timestamptz,
  upgrade_finishes_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(user_id, building_type)
);

create table if not exists public.realm_material_balances(
  user_id uuid not null references public.game_players(id) on delete cascade,
  material_id text not null references public.realm_materials(id),
  amount numeric not null default 0 check (amount >= 0),
  updated_at timestamptz not null default now(),
  primary key(user_id, material_id)
);

create table if not exists public.realm_material_ledger(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  material_id text not null,
  amount numeric not null,
  balance_before numeric not null,
  balance_after numeric not null,
  reason text not null,
  source_id text,
  created_at timestamptz not null default now()
);
create index if not exists realm_material_ledger_user_idx on public.realm_material_ledger(user_id, created_at desc);

create table if not exists public.realm_expeditions(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  region_id text not null references public.realm_regions(id),
  expedition_type text not null,
  started_at timestamptz not null default now(),
  finishes_at timestamptz not null,
  status text not null default 'running',
  reward_seed bigint not null,
  reward jsonb,
  claimed_at timestamptz,
  idempotency_key text,
  unique(user_id, idempotency_key)
);
create index if not exists realm_expeditions_user_idx on public.realm_expeditions(user_id, status);

create table if not exists public.realm_crafting_jobs(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  recipe_id text not null references public.realm_recipes(id),
  quantity int not null default 1,
  started_at timestamptz not null default now(),
  finishes_at timestamptz not null,
  status text not null default 'running',
  claimed_at timestamptz,
  idempotency_key text,
  unique(user_id, idempotency_key)
);
create index if not exists realm_crafting_jobs_user_idx on public.realm_crafting_jobs(user_id, status);

create table if not exists public.ancient_ruin_runs(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  region_id text not null references public.realm_regions(id),
  seed bigint not null,
  current_room int not null default 0,
  hp int not null default 100,
  ruin_coins int not null default 0,
  buffs jsonb not null default '[]'::jsonb,
  loot jsonb not null default '{}'::jsonb,
  status text not null default 'running',
  started_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists ancient_ruin_runs_user_idx on public.ancient_ruin_runs(user_id, status);

create table if not exists public.ancient_ruin_rooms(
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.ancient_ruin_runs(id) on delete cascade,
  room_index int not null,
  branch int not null default 0,
  room_type text not null,
  config jsonb not null default '{}'::jsonb,
  status text not null default 'locked',
  resolved_at timestamptz,
  unique(run_id, room_index, branch)
);

create table if not exists public.realm_bounties(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  bounty_day date not null default (now() at time zone 'utc')::date,
  bounty_type text not null,
  title text not null,
  target int not null default 1,
  progress int not null default 0,
  reward jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  claimed_at timestamptz,
  expires_at timestamptz not null
);
create index if not exists realm_bounties_user_idx on public.realm_bounties(user_id, bounty_day);

-- RLS: locked by default, edge functions use the service role.
do $$
declare t text;
begin
  foreach t in array array['realm_regions','realm_materials','realm_building_types','realm_recipes','realm_profiles','realm_buildings','realm_material_balances','realm_material_ledger','realm_expeditions','realm_crafting_jobs','ancient_ruin_runs','ancient_ruin_rooms','realm_bounties']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

-- ============================================================
-- VISIBILITY: admin-only while the Realm is in soft launch.
-- ============================================================
insert into public.game_settings(key, value, category, label)
values ('realm_visibility', '"admin"'::jsonb, 'realm', 'MYTHREON REALM :: visibilidade (admin | all)')
on conflict (key) do nothing;
insert into public.game_settings(key, value, category, label)
values ('realm_admin_ids', '[8118569391]'::jsonb, 'realm', 'MYTHREON REALM :: Telegram IDs com acesso antecipado')
on conflict (key) do nothing;

create or replace function public.realm_access_allowed(p_telegram_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when coalesce((select value #>> '{}' from game_settings where key='realm_visibility'), 'admin') = 'all' then true
    when p_telegram_id = 8118569391 then true
    else exists (
      select 1 from jsonb_array_elements_text(coalesce((select value from game_settings where key='realm_admin_ids'), '[]'::jsonb)) v
      where v = p_telegram_id::text)
  end
$$;