-- 1. distinguish sale-supply burns from in-game utility burns
alter table public.myth_burn_history add column if not exists burn_kind text not null default 'SUPPLY';
alter table public.myth_burn_history add column if not exists user_id uuid references public.game_players(id) on delete set null;
alter table public.myth_burn_history add column if not exists source text;
alter table public.myth_burn_history add column if not exists source_id text;
do $$ begin
  alter table public.myth_burn_history add constraint myth_burn_history_kind_chk check (burn_kind in ('SUPPLY','UTILITY'));
exception when duplicate_object then null; end $$;

-- 2. official utility settings (single row)
create table if not exists public.myth_utility_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default true,
  myth_per_ton numeric not null default 20000 check (myth_per_ton > 0),
  fc_per_ton numeric not null default 100000 check (fc_per_ton > 0),
  discount_percent numeric not null default 8 check (discount_percent >= 0 and discount_percent < 100),
  jetton_master_address text,
  onchain_burn_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
grant all on public.myth_utility_settings to service_role;
alter table public.myth_utility_settings enable row level security;
insert into public.myth_utility_settings(id, jetton_master_address)
values (true, 'EQDu8MxkLwH_p-UaiL1VSCQ7KM5XcCgkUEl20_GPr-X3p-nf')
on conflict (id) do nothing;

-- 3. per-feature control
create table if not exists public.myth_utility_features (
  feature_code text primary key,
  label text not null,
  enabled boolean not null default true,
  pricing_mode text not null default 'AUTO_FC' check (pricing_mode in ('AUTO_FC','AUTO_TON','CUSTOM')),
  custom_myth numeric,
  updated_at timestamptz not null default now()
);
grant all on public.myth_utility_features to service_role;
alter table public.myth_utility_features enable row level security;

insert into public.myth_utility_features(feature_code, label, pricing_mode) values
  ('FOOD_PURCHASE','Pet Food','AUTO_FC'),
  ('EGG_PURCHASE','Pet Eggs','AUTO_FC'),
  ('HERO_FUSE','Hero Fusion Fee','AUTO_FC'),
  ('HERO_UPGRADE','Hero Rarity Fusion','AUTO_FC'),
  ('PET_UPGRADE','Pet Upgrade / Evolution','AUTO_FC'),
  ('PASS_PURCHASE','Season Pass','AUTO_TON'),
  ('PASS_LEVELS','Season Pass Levels','AUTO_FC'),
  ('TOWER_ENTRY','Tower of Eternity','AUTO_TON'),
  ('EXCLUSIVE_PURCHASE','Exclusive Shop','AUTO_TON'),
  ('EVENT_PURCHASE','Event Shop','AUTO_FC')
on conflict (feature_code) do nothing;

-- 4. detailed utility burn ledger
create table if not exists public.myth_utility_burns (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  feature_code text not null,
  source_id text,
  idempotency_key text,
  amount_myth numeric not null check (amount_myth > 0),
  amount_base_units numeric not null default 0,
  reference_myth_per_ton numeric not null,
  utility_discount_percent numeric not null,
  balance_before numeric not null,
  balance_after numeric not null,
  game_burn_status text not null default 'GAME_CONFIRMED'
    check (game_burn_status in ('GAME_CONFIRMED','FAILED_REVIEW')),
  onchain_burn_status text not null default 'PENDING_ONCHAIN'
    check (onchain_burn_status in ('NOT_APPLICABLE','PENDING_ONCHAIN','ONCHAIN_CONFIRMED','FAILED_REVIEW')),
  onchain_tx_hash text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz
);
create unique index if not exists myth_utility_burns_idem_uq
  on public.myth_utility_burns(feature_code, idempotency_key) where idempotency_key is not null;
create index if not exists myth_utility_burns_user_idx on public.myth_utility_burns(user_id, created_at desc);
create index if not exists myth_utility_burns_onchain_idx on public.myth_utility_burns(onchain_burn_status, created_at);
grant all on public.myth_utility_burns to service_role;
alter table public.myth_utility_burns enable row level security;

-- 5. config accessor
create or replace function public.myth_utility_config()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'enabled', s.enabled,
    'mythPerTon', s.myth_per_ton,
    'fcPerTon', s.fc_per_ton,
    'mythPerFc', round(s.myth_per_ton / s.fc_per_ton, 8),
    'discountPercent', s.discount_percent,
    'onchainBurnEnabled', s.onchain_burn_enabled,
    'features', coalesce((select jsonb_object_agg(f.feature_code, jsonb_build_object(
        'label', f.label, 'enabled', f.enabled, 'pricingMode', f.pricing_mode, 'customMyth', f.custom_myth))
      from public.myth_utility_features f), '{}'::jsonb)
  ) from public.myth_utility_settings s where s.id
$$;

-- 6. single official price resolver (server-side source of truth)
create or replace function public.myth_utility_price(p_feature text, p_fc numeric default 0, p_ton numeric default 0)
returns numeric language plpgsql stable security definer set search_path to 'public' as $$
declare s public.myth_utility_settings; f public.myth_utility_features; v_base numeric := 0;
begin
  select * into s from public.myth_utility_settings where id;
  if not coalesce(s.enabled, false) then return null; end if;
  select * into f from public.myth_utility_features where feature_code = p_feature;
  if f.feature_code is null or not f.enabled then return null; end if;

  if f.pricing_mode = 'CUSTOM' then
    if coalesce(f.custom_myth, 0) <= 0 then return null; end if;
    return ceil(f.custom_myth);
  elsif f.pricing_mode = 'AUTO_TON' then
    if coalesce(p_ton, 0) <= 0 then return null; end if;
    v_base := p_ton * s.myth_per_ton;
  else
    if coalesce(p_fc, 0) <= 0 then return null; end if;
    v_base := p_fc / s.fc_per_ton * s.myth_per_ton;
  end if;

  return ceil(v_base * (100 - s.discount_percent) / 100);
end $$;

-- 7. atomic charge + burn (available MYTH only; staked MYTH is never touched)
create or replace function public.myth_utility_charge(
  p_user uuid, p_feature text, p_amount numeric,
  p_source_id text default null, p_idempotency_key text default null, p_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.myth_utility_settings; v_amount numeric; v_before numeric; v_after numeric;
        v_staked numeric; v_burn public.myth_burn_history; v_row public.myth_utility_burns;
        v_supply_before numeric; v_supply_after numeric; v_existing public.myth_utility_burns;
begin
  select * into s from public.myth_utility_settings where id;
  if not coalesce(s.enabled, false) then raise exception 'MYTH_UTILITY_DISABLED'; end if;
  if not exists (select 1 from public.myth_utility_features where feature_code = p_feature and enabled) then
    raise exception 'MYTH_PAYMENT_NOT_ENABLED';
  end if;
  v_amount := ceil(coalesce(p_amount, 0));
  if v_amount <= 0 then raise exception 'MYTH_INVALID_AMOUNT'; end if;

  if p_idempotency_key is not null then
    select * into v_existing from public.myth_utility_burns
      where feature_code = p_feature and idempotency_key = p_idempotency_key;
    if v_existing.id is not null then
      return jsonb_build_object('duplicate', true, 'burnId', v_existing.id, 'amountMyth', v_existing.amount_myth);
    end if;
  end if;

  insert into public.myth_balances(user_id, amount) values (p_user, 0) on conflict (user_id) do nothing;
  select amount into v_before from public.myth_balances where user_id = p_user for update;
  v_staked := public.myth_staked_amount(p_user);
  if coalesce(v_before, 0) < v_amount then raise exception 'INSUFFICIENT_MYTH'; end if;

  v_after := round(v_before - v_amount, 6);
  update public.myth_balances set amount = v_after, updated_at = now() where user_id = p_user;
  insert into public.myth_ledger(user_id, direction, amount, reason)
  values (p_user, 'debit', v_amount, 'myth_utility:' || lower(p_feature));

  select coalesce((public.myth_sale_stats()->>'effectiveSupply')::numeric, 0) into v_supply_before;
  v_supply_after := greatest(0, v_supply_before - v_amount);

  insert into public.myth_burn_history(amount, reason, supply_before, supply_after, burn_kind, user_id, source, source_id)
  values (v_amount, 'MYTH_UTILITY_BURN:' || p_feature, v_supply_before, v_supply_after, 'UTILITY', p_user, p_feature, p_source_id)
  returning * into v_burn;

  insert into public.myth_utility_burns(user_id, feature_code, source_id, idempotency_key, amount_myth,
    amount_base_units, reference_myth_per_ton, utility_discount_percent, balance_before, balance_after,
    game_burn_status, onchain_burn_status, meta, confirmed_at)
  values (p_user, p_feature, p_source_id, p_idempotency_key, v_amount,
    round(v_amount * 1000000000), s.myth_per_ton, s.discount_percent, v_before, v_after,
    'GAME_CONFIRMED',
    case when s.onchain_burn_enabled then 'PENDING_ONCHAIN' else 'PENDING_ONCHAIN' end,
    coalesce(p_meta, '{}'::jsonb) || jsonb_build_object('supplyBurnId', v_burn.id), now())
  returning * into v_row;

  insert into public.myth_supply_ledger(entry_type, amount, user_id, reference_id, note)
  values ('BURN', v_amount, p_user, v_row.id::text, 'MYTH_UTILITY_BURN:' || p_feature);

  return jsonb_build_object('ok', true, 'burnId', v_row.id, 'amountMyth', v_amount,
    'balanceBefore', v_before, 'balanceAfter', v_after, 'staked', v_staked,
    'effectiveSupply', v_supply_after, 'gameBurnStatus', 'GAME_CONFIRMED', 'onchainBurnStatus', v_row.onchain_burn_status);
end $$;

revoke execute on function public.myth_utility_config() from public, anon, authenticated;
revoke execute on function public.myth_utility_price(text, numeric, numeric) from public, anon, authenticated;
revoke execute on function public.myth_utility_charge(uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.myth_utility_config() to service_role;
grant execute on function public.myth_utility_price(text, numeric, numeric) to service_role;
grant execute on function public.myth_utility_charge(uuid, text, numeric, text, text, jsonb) to service_role;