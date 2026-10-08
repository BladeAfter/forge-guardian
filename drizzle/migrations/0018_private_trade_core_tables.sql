-- ============================================================================
-- PRIVATE TRADE / TROCA PRIVADA
-- Direct player-to-player trading with escrow, double confirmation, atomic
-- settlement, idempotency and an anti-multiaccount risk engine.
-- Nothing here touches the public Market or the Auction.
-- ============================================================================

create table if not exists public.private_trade_settings (
  id integer primary key default 1,
  enabled boolean not null default true,
  admin_only boolean not null default false,
  max_items integer not null default 6,
  expire_hours integer not null default 24,
  min_account_days integer not null default 7,
  fee_percent numeric not null default 0,
  risk_medium integer not null default 30,
  risk_high integer not null default 60,
  risk_critical integer not null default 80,
  require_deposit_for_high_value boolean not null default false,
  high_value_min_deposit_ton numeric not null default 5,
  suspicious_cooldown_hours integer not null default 24,
  same_network_risk integer not null default 20,
  same_device_risk integer not null default 55,
  new_account_risk integer not null default 20,
  one_sided_risk integer not null default 20,
  nft_transfer_risk integer not null default 20,
  high_rarity_risk integer not null default 10,
  repeated_pair_risk integer not null default 15,
  same_wallet_risk integer not null default 30,
  updated_at timestamptz not null default now()
);
insert into public.private_trade_settings(id) values (1) on conflict (id) do nothing;

create table if not exists public.private_trades (
  id uuid primary key default gen_random_uuid(),
  code text not null default upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  initiator_user_id uuid not null references public.game_players(id) on delete cascade,
  recipient_user_id uuid not null references public.game_players(id) on delete cascade,
  status text not null default 'negotiating',
  initiator_locked boolean not null default false,
  recipient_locked boolean not null default false,
  initiator_confirmed boolean not null default false,
  recipient_confirmed boolean not null default false,
  initiator_fc numeric not null default 0,
  initiator_ton numeric not null default 0,
  initiator_myth numeric not null default 0,
  recipient_fc numeric not null default 0,
  recipient_ton numeric not null default 0,
  recipient_myth numeric not null default 0,
  initiator_escrowed boolean not null default false,
  recipient_escrowed boolean not null default false,
  risk_score integer not null default 0,
  risk_flags text[] not null default '{}',
  admin_note text,
  cancelled_by uuid,
  cancel_reason text,
  expires_at timestamptz not null default now() + interval '24 hours',
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint private_trades_status_check check (status in
    ('draft','waiting_for_partner','negotiating','offer_locked','ready_for_confirmation',
     'completed','cancelled','expired','security_review','blocked')),
  constraint private_trades_distinct_players check (initiator_user_id <> recipient_user_id)
);
create index if not exists private_trades_initiator_idx on public.private_trades(initiator_user_id, status);
create index if not exists private_trades_recipient_idx on public.private_trades(recipient_user_id, status);

create table if not exists public.private_trade_items (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references public.private_trades(id) on delete cascade,
  owner_user_id uuid not null references public.game_players(id) on delete cascade,
  side text not null check (side in ('initiator','recipient')),
  item_type text not null check (item_type in ('hero','pet','item')),
  item_instance_id uuid,
  item_code text,
  quantity integer not null default 1,
  snapshot jsonb not null default '{}',
  value_fc numeric not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists private_trade_items_trade_idx on public.private_trade_items(trade_id);
create unique index if not exists private_trade_items_instance_uq
  on public.private_trade_items(item_instance_id) where item_instance_id is not null;

create table if not exists public.private_trade_events (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid references public.private_trades(id) on delete cascade,
  actor_user_id uuid,
  event text not null,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists private_trade_events_trade_idx on public.private_trade_events(trade_id, created_at desc);

create table if not exists public.private_trade_ledger (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid references public.private_trades(id) on delete set null,
  from_user_id uuid,
  to_user_id uuid,
  fc numeric not null default 0,
  ton numeric not null default 0,
  myth numeric not null default 0,
  items jsonb not null default '[]',
  risk_score integer not null default 0,
  risk_flags text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists private_trade_ledger_trade_idx on public.private_trade_ledger(trade_id);

create table if not exists public.private_trade_idempotency (
  request_id text primary key,
  trade_id uuid,
  action text not null,
  result jsonb not null default '{}',
  created_at timestamptz not null default now()
);

grant all on public.private_trade_settings to service_role;
grant all on public.private_trades to service_role;
grant all on public.private_trade_items to service_role;
grant all on public.private_trade_events to service_role;
grant all on public.private_trade_ledger to service_role;
grant all on public.private_trade_idempotency to service_role;

alter table public.private_trade_settings enable row level security;
alter table public.private_trades enable row level security;
alter table public.private_trade_items enable row level security;
alter table public.private_trade_events enable row level security;
alter table public.private_trade_ledger enable row level security;
alter table public.private_trade_idempotency enable row level security;

-- ============================================================================
-- Settings / helpers
-- ============================================================================
create or replace function public.private_trade_settings_json()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'enabled', s.enabled, 'adminOnly', s.admin_only, 'maxItems', s.max_items,
    'expireHours', s.expire_hours, 'minAccountDays', s.min_account_days,
    'feePercent', s.fee_percent,
    'riskMedium', s.risk_medium, 'riskHigh', s.risk_high, 'riskCritical', s.risk_critical,
    'requireDepositForHighValue', s.require_deposit_for_high_value,
    'highValueMinDepositTon', s.high_value_min_deposit_ton,
    'suspiciousCooldownHours', s.suspicious_cooldown_hours,
    'weights', jsonb_build_object(
      'sameNetwork', s.same_network_risk, 'sameDevice', s.same_device_risk,
      'newAccount', s.new_account_risk, 'oneSided', s.one_sided_risk,
      'nftTransfer', s.nft_transfer_risk, 'highRarity', s.high_rarity_risk,
      'repeatedPair', s.repeated_pair_risk, 'sameWallet', s.same_wallet_risk))
  from private_trade_settings s where s.id = 1;
$$;

-- Rough FC-equivalent value of one traded asset. Security signal only: it is
-- never used to block a trade, only to flag ONE_SIDED_TRADE.
create or replace function public.private_trade_item_value(p_rarity text, p_type text, p_qty integer, p_nft boolean default false)
returns numeric language sql immutable set search_path to 'public' as $$
  select greatest(coalesce(p_qty,1),1) * (case when coalesce(p_nft,false) then 3000000 else
    case lower(coalesce(p_rarity,'common'))
      when 'common' then 2000 when 'uncommon' then 5000 when 'improved' then 8000
      when 'rare' then 25000 when 'special' then 40000 when 'epic' then 90000
      when 'legendary' then 350000 when 'mythic' then 900000
      when 'ancestral' then 1500000 when 'celestial' then 2500000
      when 'divine' then 2500000 when 'nft_exclusive' then 3000000
      else 10000 end end)
    * (case when lower(coalesce(p_type,'item')) in ('hero','pet') then 1 else 0.6 end);
$$;

create or replace function public.private_trade_high_rarity(p_rarity text)
returns boolean language sql immutable set search_path to 'public' as $$
  select lower(coalesce(p_rarity,'')) in ('legendary','mythic','ancestral','celestial','divine','nft_exclusive');
$$;

create or replace function public.private_trade_player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object('id', g.id, 'telegramId', g.telegram_id,
    'name', market_seller_label(g.id),
    'username', nullif(g.username,''), 'avatar', nullif(g.avatar_url,''),
    'accountDays', market_account_days(g.id))
  from game_players g where g.id = p_user;
$$;