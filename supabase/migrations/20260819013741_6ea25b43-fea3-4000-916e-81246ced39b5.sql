-- ⚔️ MYTHREON VETERAN VAULT — premium pack for veteran players with a 45-day reward cycle.
create table if not exists public.veteran_vault_config (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  sales_paused boolean not null default false,
  vault_version text not null default 'VETERAN_V1',
  price_ton numeric not null default 50,
  min_account_age_days integer not null default 7,
  cycle_days integer not null default 45,
  launch_at timestamptz not null default now(),
  initial_myth numeric not null default 150000,
  pass_tier text not null default 'legendary',
  hero_key text,
  pet_slug text,
  equipment_chest_code text not null default 'legendary_chest',
  fragments integer not null default 200,
  resource_chest_code text not null default 'premium_resource_chest',
  resource_chest_qty integer not null default 2,
  badge_enabled boolean not null default true,
  frame_enabled boolean not null default true,
  max_ton_reward numeric not null default 9,
  daily_myth numeric not null default 2000,
  reward_schedule jsonb not null default jsonb_build_object(
    'ton', jsonb_build_object('7',1,'14',1,'21',1.5,'30',2,'37',1.5,'45',2),
    'mythBonus', jsonb_build_object('7',5000,'14',5000,'21',7500,'30',10000,'45',15000)),
  final_reward jsonb not null default jsonb_build_object(
    'myth', 25000, 'fragments', 100, 'chest', 'premium_resource_chest', 'chestQty', 1, 'badge', 'veteran_badge_ii'),
  reference_values jsonb not null default jsonb_build_object(
    'pass',5,'myth',6,'hero',8,'pet',6,'equipment',3,'fragmentsChests',3,'cosmetics',2),
  target_reference_ton numeric not null default 50,
  updated_at timestamptz not null default now()
);
insert into public.veteran_vault_config(id) values (true) on conflict (id) do nothing;
grant all on public.veteran_vault_config to service_role;
alter table public.veteran_vault_config enable row level security;

create table if not exists public.veteran_vault_pool (
  id boolean primary key default true check (id),
  ton_funded numeric not null default 0,
  ton_reserved numeric not null default 0,
  ton_distributed numeric not null default 0,
  myth_funded numeric not null default 0,
  myth_reserved numeric not null default 0,
  myth_distributed numeric not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.veteran_vault_pool(id) values (true) on conflict (id) do nothing;
grant all on public.veteran_vault_pool to service_role;
alter table public.veteran_vault_pool enable row level security;

create table if not exists public.veteran_vault_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  telegram_id bigint not null,
  vault_version text not null,
  price_ton numeric not null,
  amount_nano text not null,
  reward_snapshot jsonb not null default '{}'::jsonb,
  payment_method text not null default 'ton_connect',
  status text not null default 'pending',
  payment_address text,
  payment_comment text,
  idempotency_key text unique,
  tx_hash text,
  ton_reserved numeric not null default 0,
  myth_reserved numeric not null default 0,
  ton_distributed numeric not null default 0,
  myth_distributed numeric not null default 0,
  cycle_start_at timestamptz,
  cycle_end_at timestamptz,
  delivery jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '1 hour',
  confirmed_at timestamptz,
  settled_at timestamptz,
  completed_at timestamptz
);
create unique index if not exists veteran_vault_purchases_owned_uidx
  on public.veteran_vault_purchases(user_id, vault_version) where status in ('paid','settled');
create unique index if not exists veteran_vault_purchases_tx_uidx
  on public.veteran_vault_purchases(tx_hash) where tx_hash is not null;
grant all on public.veteran_vault_purchases to service_role;
alter table public.veteran_vault_purchases enable row level security;

create table if not exists public.veteran_vault_claims (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.veteran_vault_purchases(id) on delete cascade,
  user_id uuid not null references public.game_players(id) on delete cascade,
  reward_day integer not null,
  reward_type text not null,
  ton_amount numeric not null default 0,
  myth_amount numeric not null default 0,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (purchase_id, reward_day, reward_type)
);
grant all on public.veteran_vault_claims to service_role;
alter table public.veteran_vault_claims enable row level security;

create table if not exists public.veteran_vault_ledger (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid references public.veteran_vault_purchases(id) on delete set null,
  user_id uuid references public.game_players(id) on delete set null,
  kind text not null,
  ton_amount numeric not null default 0,
  myth_amount numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);
grant all on public.veteran_vault_ledger to service_role;
alter table public.veteran_vault_ledger enable row level security;

create or replace function public.veteran_vault_settings()
returns public.veteran_vault_config language sql stable security definer set search_path to 'public' as $$
  select * from public.veteran_vault_config where id
$$;

-- Total real TON promised by the configured schedule (never above max_ton_reward).
create or replace function public.veteran_vault_ton_budget()
returns numeric language sql stable security definer set search_path to 'public' as $$
  select least(c.max_ton_reward,
    coalesce((select sum(value::numeric) from jsonb_each_text(c.reward_schedule->'ton')), 0))
  from public.veteran_vault_config c where c.id
$$;

create or replace function public.veteran_vault_myth_budget()
returns numeric language sql stable security definer set search_path to 'public' as $$
  select c.daily_myth * greatest(1, c.cycle_days)
       + coalesce((select sum(value::numeric) from jsonb_each_text(c.reward_schedule->'mythBonus')), 0)
       + coalesce((c.final_reward->>'myth')::numeric, 0)
  from public.veteran_vault_config c where c.id
$$;

create or replace function public.veteran_vault_snapshot()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'vaultVersion', c.vault_version, 'priceTon', c.price_ton, 'cycleDays', c.cycle_days,
    'initialMyth', c.initial_myth, 'passTier', c.pass_tier, 'heroKey', c.hero_key, 'petSlug', c.pet_slug,
    'equipmentChestCode', c.equipment_chest_code, 'fragments', c.fragments,
    'resourceChestCode', c.resource_chest_code, 'resourceChestQty', c.resource_chest_qty,
    'badge', c.badge_enabled, 'frame', c.frame_enabled,
    'dailyMyth', c.daily_myth, 'rewardSchedule', c.reward_schedule, 'finalReward', c.final_reward,
    'tonBudget', public.veteran_vault_ton_budget(), 'mythBudget', public.veteran_vault_myth_budget(),
    'referenceValues', c.reference_values, 'targetReferenceTon', c.target_reference_ton,
    'seasonId', (select id from public.season_pass_seasons where active order by created_at desc limit 1))
  from public.veteran_vault_config c where c.id
$$;

revoke all on function public.veteran_vault_settings() from public, anon, authenticated;
revoke all on function public.veteran_vault_snapshot() from public, anon, authenticated;
revoke all on function public.veteran_vault_ton_budget() from public, anon, authenticated;
revoke all on function public.veteran_vault_myth_budget() from public, anon, authenticated;