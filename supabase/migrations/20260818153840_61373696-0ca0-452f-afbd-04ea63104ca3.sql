-- MYTHREON :: INTERNAL MYTH STAKING (MYTH -> MYTH only).
-- No new supply: stake moves MYTH from myth_balances into a staking position.
-- Rewards are paid ONLY out of a fixed reward pool reserved from the existing 100M supply.

create table if not exists public.myth_staking_settings (
  id boolean primary key default true check (id),
  staking_enabled boolean not null default false,
  claims_enabled boolean not null default true,
  new_stakes_paused boolean not null default false,
  min_stake numeric not null default 1000,
  max_stake numeric not null default 0,
  reward_pool_total numeric not null default 0,
  reward_pool_distributed numeric not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.myth_staking_settings (id) values (true) on conflict (id) do nothing;

create table if not exists public.myth_staking_plans (
  code text primary key,
  label text not null,
  lock_days integer not null default 0,
  apr_percent numeric not null default 0,
  active boolean not null default false,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.myth_staking_plans (code, label, lock_days, apr_percent, active, sort_order) values
  ('flexible','FLEXIBLE',0,0,false,1),
  ('d7','7 DAYS',7,0,false,2),
  ('d30','30 DAYS',30,0,false,3),
  ('d90','90 DAYS',90,0,false,4),
  ('d180','180 DAYS',180,0,false,5)
on conflict (code) do nothing;

create table if not exists public.myth_staking_positions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  plan_code text not null references public.myth_staking_plans(code),
  amount numeric not null,
  apr_percent numeric not null,
  lock_days integer not null default 0,
  status text not null default 'active',
  accrued_myth numeric not null default 0,
  claimed_myth numeric not null default 0,
  staked_at timestamptz not null default now(),
  unlock_at timestamptz,
  last_accrual_at timestamptz not null default now(),
  closed_at timestamptz
);
create index if not exists myth_staking_positions_user_idx on public.myth_staking_positions(user_id, status);

create table if not exists public.myth_staking_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.game_players(id) on delete set null,
  position_id uuid references public.myth_staking_positions(id) on delete set null,
  entry_type text not null,
  amount numeric not null,
  admin_telegram_id bigint,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists myth_staking_ledger_user_idx on public.myth_staking_ledger(user_id, created_at desc);

create table if not exists public.myth_staking_idempotency (
  key text primary key,
  user_id uuid,
  result jsonb,
  created_at timestamptz not null default now()
);

grant select on public.myth_staking_settings to anon, authenticated;
grant select on public.myth_staking_plans to anon, authenticated;
grant select on public.myth_staking_positions to authenticated;
grant select on public.myth_staking_ledger to authenticated;
grant all on public.myth_staking_settings, public.myth_staking_plans, public.myth_staking_positions,
  public.myth_staking_ledger, public.myth_staking_idempotency to service_role;

alter table public.myth_staking_settings enable row level security;
alter table public.myth_staking_plans enable row level security;
alter table public.myth_staking_positions enable row level security;
alter table public.myth_staking_ledger enable row level security;
alter table public.myth_staking_idempotency enable row level security;

drop policy if exists myth_staking_settings_read on public.myth_staking_settings;
create policy myth_staking_settings_read on public.myth_staking_settings for select using (true);
drop policy if exists myth_staking_plans_read on public.myth_staking_plans;
create policy myth_staking_plans_read on public.myth_staking_plans for select using (true);

create or replace function public.myth_staking_accrue(p_position_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_pos public.myth_staking_positions;
  v_pool_left numeric;
  v_gain numeric;
begin
  select * into v_pos from public.myth_staking_positions where id = p_position_id for update;
  if v_pos.id is null or v_pos.status <> 'active' then return; end if;
  v_gain := v_pos.amount * (v_pos.apr_percent / 100.0)
            * (extract(epoch from (now() - v_pos.last_accrual_at)) / 31536000.0);
  if v_gain <= 0 then
    update public.myth_staking_positions set last_accrual_at = now() where id = p_position_id;
    return;
  end if;
  select greatest(0, s.reward_pool_total - s.reward_pool_distributed) into v_pool_left
  from public.myth_staking_settings s where s.id;
  v_pool_left := v_pool_left - coalesce((select sum(accrued_myth) from public.myth_staking_positions where status = 'active'), 0);
  v_gain := least(v_gain, greatest(v_pool_left, 0));
  update public.myth_staking_positions
     set accrued_myth = accrued_myth + round(v_gain, 6), last_accrual_at = now()
   where id = p_position_id;
end $$;

create or replace function public.myth_staking_accrue_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from public.myth_staking_positions where user_id = p_user_id and status = 'active' order by staked_at loop
    perform public.myth_staking_accrue(r.id);
  end loop;
end $$;

create or replace function public.get_myth_staking_dashboard(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_set public.myth_staking_settings;
  v_available numeric;
  v_staked numeric;
  v_claimable numeric;
  v_apr numeric;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.myth_staking_accrue_user(v_user);
  select * into v_set from public.myth_staking_settings where id;
  select coalesce(amount, 0) into v_available from public.myth_balances where user_id = v_user;
  select coalesce(sum(amount), 0), coalesce(sum(accrued_myth), 0) into v_staked, v_claimable
    from public.myth_staking_positions where user_id = v_user and status = 'active';
  select max(apr_percent) into v_apr from public.myth_staking_plans where active and apr_percent > 0;

  return jsonb_build_object(
    'settings', jsonb_build_object(
      'enabled', v_set.staking_enabled,
      'claimsEnabled', v_set.claims_enabled,
      'newStakesPaused', v_set.new_stakes_paused,
      'minStake', v_set.min_stake,
      'maxStake', v_set.max_stake,
      'bestApr', v_apr,
      'rewardPoolTotal', v_set.reward_pool_total,
      'rewardPoolAvailable', greatest(0, v_set.reward_pool_total - v_set.reward_pool_distributed),
      'rewardPoolDistributed', v_set.reward_pool_distributed
    ),
    'plans', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'lockDays', lock_days, 'aprPercent', apr_percent) order by sort_order)
                       from public.myth_staking_plans where active), '[]'::jsonb),
    'player', jsonb_build_object(
      'available', coalesce(v_available, 0),
      'staked', v_staked,
      'totalOwned', coalesce(v_available, 0) + v_staked,
      'claimable', v_claimable
    ),
    'positions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'planCode', p.plan_code, 'planLabel', pl.label, 'amount', p.amount,
        'aprPercent', p.apr_percent, 'lockDays', p.lock_days, 'claimable', p.accrued_myth,
        'claimed', p.claimed_myth, 'stakedAt', p.staked_at, 'unlockAt', p.unlock_at,
        'unlocked', (p.unlock_at is null or p.unlock_at <= now())) order by p.staked_at desc)
      from public.myth_staking_positions p join public.myth_staking_plans pl on pl.code = p.plan_code
      where p.user_id = v_user and p.status = 'active'), '[]'::jsonb),
    'totals', jsonb_build_object(
      'totalStaked', coalesce((select sum(amount) from public.myth_staking_positions where status = 'active'), 0),
      'stakers', coalesce((select count(distinct user_id) from public.myth_staking_positions where status = 'active'), 0)
    ),
    'serverTime', now()
  );
end $$;

create or replace function public.myth_stake(p_telegram_id bigint, p_amount numeric, p_plan text, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_set public.myth_staking_settings;
  v_plan public.myth_staking_plans;
  v_balance numeric;
  v_amount numeric := round(coalesce(p_amount, 0), 6);
  v_cached jsonb;
  v_id uuid;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select result into v_cached from public.myth_staking_idempotency where key = p_idempotency_key;
  if v_cached is not null then return v_cached || jsonb_build_object('duplicate', true); end if;

  select * into v_set from public.myth_staking_settings where id for update;
  if not v_set.staking_enabled then raise exception 'MYTH_STAKING_DISABLED'; end if;
  if v_set.new_stakes_paused then raise exception 'MYTH_STAKING_PAUSED'; end if;
  select * into v_plan from public.myth_staking_plans where code = p_plan and active;
  if v_plan.code is null then raise exception 'MYTH_STAKING_PLAN_INVALID'; end if;
  if v_amount <= 0 then raise exception 'MYTH_STAKING_INVALID_AMOUNT'; end if;
  if v_amount < v_set.min_stake then raise exception 'MYTH_STAKING_MIN_AMOUNT'; end if;

  insert into public.myth_balances (user_id, amount) values (v_user, 0) on conflict (user_id) do nothing;
  select amount into v_balance from public.myth_balances where user_id = v_user for update;
  if v_balance < v_amount then raise exception 'MYTH_STAKING_INSUFFICIENT'; end if;
  if v_set.max_stake > 0 then
    if v_amount + coalesce((select sum(amount) from public.myth_staking_positions where user_id = v_user and status = 'active'), 0) > v_set.max_stake then
      raise exception 'MYTH_STAKING_MAX_AMOUNT';
    end if;
  end if;

  update public.myth_balances set amount = amount - v_amount, updated_at = now() where user_id = v_user;
  insert into public.myth_staking_positions (user_id, plan_code, amount, apr_percent, lock_days, unlock_at)
  values (v_user, v_plan.code, v_amount, v_plan.apr_percent, v_plan.lock_days,
          case when v_plan.lock_days > 0 then now() + make_interval(days => v_plan.lock_days) else null end)
  returning id into v_id;
  insert into public.myth_ledger (user_id, direction, amount, reason) values (v_user, 'debit', v_amount, 'myth_stake');
  insert into public.myth_staking_ledger (user_id, position_id, entry_type, amount, note)
  values (v_user, v_id, 'MYTH_STAKE', v_amount, v_plan.code);

  v_cached := jsonb_build_object('ok', true, 'positionId', v_id, 'amount', v_amount, 'planCode', v_plan.code);
  insert into public.myth_staking_idempotency (key, user_id, result) values (p_idempotency_key, v_user, v_cached)
  on conflict (key) do nothing;
  return v_cached || public.get_myth_staking_dashboard(p_telegram_id);
end $$;

create or replace function public.myth_staking_claim(p_telegram_id bigint, p_position_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_set public.myth_staking_settings;
  v_cached jsonb;
  v_pool numeric;
  v_total numeric := 0;
  r record;
  v_pay numeric;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select result into v_cached from public.myth_staking_idempotency where key = p_idempotency_key;
  if v_cached is not null then return v_cached || jsonb_build_object('duplicate', true); end if;

  select * into v_set from public.myth_staking_settings where id for update;
  if not v_set.staking_enabled then raise exception 'MYTH_STAKING_DISABLED'; end if;
  if not v_set.claims_enabled then raise exception 'MYTH_STAKING_CLAIMS_DISABLED'; end if;
  perform public.myth_staking_accrue_user(v_user);
  v_pool := greatest(0, v_set.reward_pool_total - v_set.reward_pool_distributed);

  for r in select * from public.myth_staking_positions
            where user_id = v_user and status = 'active' and accrued_myth > 0
              and (p_position_id is null or id = p_position_id)
            order by staked_at for update loop
    v_pay := least(round(r.accrued_myth, 6), v_pool);
    if v_pay <= 0 then continue; end if;
    v_pool := v_pool - v_pay;
    v_total := v_total + v_pay;
    update public.myth_staking_positions
       set accrued_myth = accrued_myth - v_pay, claimed_myth = claimed_myth + v_pay
     where id = r.id;
    insert into public.myth_staking_ledger (user_id, position_id, entry_type, amount)
    values (v_user, r.id, 'MYTH_STAKING_REWARD', v_pay);
  end loop;

  if v_total <= 0 then raise exception 'MYTH_STAKING_NOTHING_TO_CLAIM'; end if;
  update public.myth_staking_settings set reward_pool_distributed = reward_pool_distributed + v_total, updated_at = now() where id;
  insert into public.myth_balances (user_id, amount) values (v_user, v_total)
  on conflict (user_id) do update set amount = public.myth_balances.amount + v_total, updated_at = now();
  insert into public.myth_ledger (user_id, direction, amount, reason) values (v_user, 'credit', v_total, 'myth_staking_reward');
  insert into public.myth_staking_ledger (user_id, entry_type, amount, note) values (v_user, 'MYTH_STAKING_CLAIM', v_total, 'claim');

  v_cached := jsonb_build_object('ok', true, 'claimed', v_total);
  insert into public.myth_staking_idempotency (key, user_id, result) values (p_idempotency_key, v_user, v_cached) on conflict (key) do nothing;
  return v_cached || public.get_myth_staking_dashboard(p_telegram_id);
end $$;

create or replace function public.myth_unstake(p_telegram_id bigint, p_position_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_cached jsonb;
  v_pos public.myth_staking_positions;
  v_set public.myth_staking_settings;
  v_pool numeric;
  v_reward numeric := 0;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select result into v_cached from public.myth_staking_idempotency where key = p_idempotency_key;
  if v_cached is not null then return v_cached || jsonb_build_object('duplicate', true); end if;

  select * into v_set from public.myth_staking_settings where id for update;
  perform public.myth_staking_accrue(p_position_id);
  select * into v_pos from public.myth_staking_positions where id = p_position_id and user_id = v_user for update;
  if v_pos.id is null or v_pos.status <> 'active' then raise exception 'MYTH_STAKING_POSITION_NOT_FOUND'; end if;
  if v_pos.unlock_at is not null and v_pos.unlock_at > now() then raise exception 'MYTH_STAKING_LOCKED'; end if;

  v_pool := greatest(0, v_set.reward_pool_total - v_set.reward_pool_distributed);
  if v_set.claims_enabled then v_reward := least(round(v_pos.accrued_myth, 6), v_pool); end if;

  update public.myth_staking_positions
     set status = 'closed', closed_at = now(), accrued_myth = accrued_myth - v_reward,
         claimed_myth = claimed_myth + v_reward
   where id = v_pos.id;
  if v_reward > 0 then
    update public.myth_staking_settings set reward_pool_distributed = reward_pool_distributed + v_reward, updated_at = now() where id;
    insert into public.myth_staking_ledger (user_id, position_id, entry_type, amount) values (v_user, v_pos.id, 'MYTH_STAKING_REWARD', v_reward);
  end if;

  insert into public.myth_balances (user_id, amount) values (v_user, v_pos.amount + v_reward)
  on conflict (user_id) do update set amount = public.myth_balances.amount + v_pos.amount + v_reward, updated_at = now();
  insert into public.myth_ledger (user_id, direction, amount, reason) values (v_user, 'credit', v_pos.amount + v_reward, 'myth_unstake');
  insert into public.myth_staking_ledger (user_id, position_id, entry_type, amount) values (v_user, v_pos.id, 'MYTH_UNSTAKE', v_pos.amount);

  v_cached := jsonb_build_object('ok', true, 'returned', v_pos.amount, 'rewards', v_reward);
  insert into public.myth_staking_idempotency (key, user_id, result) values (p_idempotency_key, v_user, v_cached) on conflict (key) do nothing;
  return v_cached || public.get_myth_staking_dashboard(p_telegram_id);
end $$;

create or replace function public.admin_myth_staking_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_set public.myth_staking_settings;
begin
  perform public.admin_assert(p_admin_id);
  select * into v_set from public.myth_staking_settings where id;
  return jsonb_build_object(
    'enabled', v_set.staking_enabled,
    'claimsEnabled', v_set.claims_enabled,
    'newStakesPaused', v_set.new_stakes_paused,
    'minStake', v_set.min_stake,
    'maxStake', v_set.max_stake,
    'rewardPoolTotal', v_set.reward_pool_total,
    'rewardPoolAvailable', greatest(0, v_set.reward_pool_total - v_set.reward_pool_distributed),
    'rewardPoolDistributed', v_set.reward_pool_distributed,
    'totalStaked', coalesce((select sum(amount) from public.myth_staking_positions where status = 'active'), 0),
    'stakers', coalesce((select count(distinct user_id) from public.myth_staking_positions where status = 'active'), 0),
    'pendingRewards', coalesce((select sum(accrued_myth) from public.myth_staking_positions where status = 'active'), 0),
    'plans', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'lockDays', lock_days, 'aprPercent', apr_percent, 'active', active) order by sort_order)
                       from public.myth_staking_plans), '[]'::jsonb)
  );
end $$;

create or replace function public.admin_myth_staking_set(p_admin_id bigint, p_field text, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_assert(p_admin_id);
  if p_field = 'enabled' then update public.myth_staking_settings set staking_enabled = (p_value <> 0), updated_at = now() where id;
  elsif p_field = 'claims' then update public.myth_staking_settings set claims_enabled = (p_value <> 0), updated_at = now() where id;
  elsif p_field = 'pause' then update public.myth_staking_settings set new_stakes_paused = (p_value <> 0), updated_at = now() where id;
  elsif p_field = 'min' then update public.myth_staking_settings set min_stake = greatest(0, p_value), updated_at = now() where id;
  elsif p_field = 'max' then update public.myth_staking_settings set max_stake = greatest(0, p_value), updated_at = now() where id;
  elsif p_field = 'pool' then update public.myth_staking_settings set reward_pool_total = greatest(0, p_value), updated_at = now() where id;
  else raise exception 'MYTH_STAKING_UNKNOWN_FIELD'; end if;
  insert into public.myth_staking_ledger (entry_type, amount, admin_telegram_id, note)
  values ('MYTH_STAKING_ADMIN_ADJUSTMENT', coalesce(p_value, 0), p_admin_id, p_field);
  return public.admin_myth_staking_overview(p_admin_id);
end $$;

create or replace function public.admin_myth_staking_plan_set(p_admin_id bigint, p_code text, p_apr numeric, p_active boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_assert(p_admin_id);
  update public.myth_staking_plans
     set apr_percent = coalesce(greatest(0, p_apr), apr_percent),
         active = coalesce(p_active, active),
         updated_at = now()
   where code = p_code;
  if not found then raise exception 'MYTH_STAKING_PLAN_INVALID'; end if;
  insert into public.myth_staking_ledger (entry_type, amount, admin_telegram_id, note)
  values ('MYTH_STAKING_ADMIN_ADJUSTMENT', coalesce(p_apr, 0), p_admin_id, 'plan:' || p_code);
  return public.admin_myth_staking_overview(p_admin_id);
end $$;

grant execute on function public.get_myth_staking_dashboard(bigint) to service_role;
grant execute on function public.myth_stake(bigint, numeric, text, text) to service_role;
grant execute on function public.myth_staking_claim(bigint, uuid, text) to service_role;
grant execute on function public.myth_unstake(bigint, uuid, text) to service_role;
grant execute on function public.admin_myth_staking_overview(bigint) to service_role;
grant execute on function public.admin_myth_staking_set(bigint, text, numeric) to service_role;
grant execute on function public.admin_myth_staking_plan_set(bigint, text, numeric, boolean) to service_role;