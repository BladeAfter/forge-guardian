-- ============================================================ NFT REWARD POOL (backend only)
create table if not exists public.nft_reward_pool (
  id boolean primary key default true check (id),
  balance_ton numeric(20,9) not null default 0 check (balance_ton >= 0),
  reserved_ton numeric(20,9) not null default 0 check (reserved_ton >= 0),
  lifetime_funded_ton numeric(20,9) not null default 0,
  lifetime_paid_ton numeric(20,9) not null default 0,
  updated_at timestamptz not null default now()
);
grant all on public.nft_reward_pool to service_role;
alter table public.nft_reward_pool enable row level security;

create table if not exists public.nft_pool_settings (
  id boolean primary key default true check (id),
  tier20_daily_ton numeric(20,9) not null default 0.500000000,
  tier30_daily_ton numeric(20,9) not null default 0.800000000,
  roi_multiplier numeric(10,4) not null default 1.0,
  min_claim_ton numeric(20,9) not null default 0.010000000,
  health_factors jsonb not null default '{"HEALTHY":1.0,"STABLE":0.6,"LOW":0.3,"CRITICAL":0.0}'::jsonb,
  health_days jsonb not null default '{"HEALTHY":45,"STABLE":20,"LOW":7}'::jsonb,
  accrual_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
grant all on public.nft_pool_settings to service_role;
alter table public.nft_pool_settings enable row level security;

create table if not exists public.nft_yield_positions (
  id uuid primary key default gen_random_uuid(),
  nft_pet_id uuid not null unique references public.nft_pets(id) on delete cascade,
  owner_user_id uuid,
  nft_serial integer not null,
  tier_ton numeric(20,9) not null default 20 check (tier_ton > 0),
  daily_yield_ton numeric(20,9) not null default 0.5,
  accrued_ton numeric(20,9) not null default 0 check (accrued_ton >= 0),
  claimed_ton numeric(20,9) not null default 0 check (claimed_ton >= 0),
  roi_target_ton numeric(20,9) not null default 20,
  roi_reached boolean not null default false,
  status text not null default 'active' check (status in ('active','paused','revoked')),
  last_accrual_at timestamptz not null default now(),
  last_claim_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists nft_yield_positions_owner_idx on public.nft_yield_positions(owner_user_id);
grant all on public.nft_yield_positions to service_role;
alter table public.nft_yield_positions enable row level security;

create table if not exists public.nft_pool_transactions (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('FUND','NFT_SALE','REVENUE_SHARE','CLAIM_PAYMENT','ADMIN_ADJUSTMENT')),
  amount_ton numeric(20,9) not null,
  balance_before numeric(20,9) not null,
  balance_after numeric(20,9) not null,
  nft_id uuid,
  user_id uuid,
  telegram_id bigint,
  claim_id uuid,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists nft_pool_transactions_created_idx on public.nft_pool_transactions(created_at desc);
grant all on public.nft_pool_transactions to service_role;
alter table public.nft_pool_transactions enable row level security;

insert into public.nft_reward_pool(id) values (true) on conflict (id) do nothing;
insert into public.nft_pool_settings(id) values (true) on conflict (id) do nothing;

-- ------------------------------------------------------------ internals
create or replace function public.nft_pool_settings_row()
returns public.nft_pool_settings language sql stable security definer set search_path = public as $$
  select * from public.nft_pool_settings where id
$$;

/** Sync one yield position per delivered NFT pet unit. Tier comes from metadata (20/30). */
create or replace function public.nft_pool_sync_positions()
returns integer language plpgsql security definer set search_path = public as $$
declare s public.nft_pool_settings; created integer := 0;
begin
  s := public.nft_pool_settings_row();
  insert into public.nft_yield_positions(nft_pet_id, owner_user_id, nft_serial, tier_ton, daily_yield_ton, roi_target_ton)
  select n.id, n.owner_user_id, n.nft_serial,
         case when coalesce((n.metadata->>'tier_ton')::numeric, 20) >= 30 then 30 else 20 end,
         case when coalesce((n.metadata->>'tier_ton')::numeric, 20) >= 30 then s.tier30_daily_ton else s.tier20_daily_ton end,
         case when coalesce((n.metadata->>'tier_ton')::numeric, 20) >= 30 then 30 else 20 end * s.roi_multiplier
  from public.nft_pets n
  where n.owner_user_id is not null and n.revoked_at is null
    and not exists (select 1 from public.nft_yield_positions p where p.nft_pet_id = n.id);
  created := row_count_of_last();
  -- keep owner/status aligned with the registry
  update public.nft_yield_positions p
     set owner_user_id = n.owner_user_id,
         status = case when n.revoked_at is not null or n.owner_user_id is null then 'revoked' else
                       case when p.status = 'paused' then 'paused' else 'active' end end,
         updated_at = now()
  from public.nft_pets n
  where n.id = p.nft_pet_id
    and (p.owner_user_id is distinct from n.owner_user_id
         or (n.revoked_at is not null and p.status <> 'revoked'));
  return created;
end $$;

create or replace function public.row_count_of_last() returns integer language plpgsql as $$
declare n integer; begin get diagnostics n = row_count; return n; end $$;

/** Internal pool health. Never exposed to players. */
create or replace function public.nft_pool_health()
returns text language plpgsql stable security definer set search_path = public as $$
declare avail numeric; obligation numeric; days numeric; s public.nft_pool_settings;
begin
  s := public.nft_pool_settings_row();
  select greatest(0, balance_ton - reserved_ton) into avail from public.nft_reward_pool where id;
  select coalesce(sum(daily_yield_ton), 0) into obligation from public.nft_yield_positions where status = 'active';
  if coalesce(obligation, 0) <= 0 then return 'HEALTHY'; end if;
  days := avail / obligation;
  if days >= (s.health_days->>'HEALTHY')::numeric then return 'HEALTHY';
  elsif days >= (s.health_days->>'STABLE')::numeric then return 'STABLE';
  elsif days >= (s.health_days->>'LOW')::numeric then return 'LOW';
  else return 'CRITICAL'; end if;
end $$;

/** Effective daily yield: full rate until ROI, health-adjusted rate afterwards. */
create or replace function public.nft_effective_daily(p_position public.nft_yield_positions)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare s public.nft_pool_settings; factor numeric;
begin
  s := public.nft_pool_settings_row();
  if p_position.status <> 'active' then return 0; end if;
  if (p_position.claimed_ton + p_position.accrued_ton) < p_position.roi_target_ton and not p_position.roi_reached then
    return p_position.daily_yield_ton;
  end if;
  factor := coalesce((s.health_factors->>public.nft_pool_health())::numeric, 0);
  return round(p_position.daily_yield_ton * factor, 9);
end $$;

/** Accrual worker: adds elapsed production to every active position and refreshes reserved. */
create or replace function public.nft_pool_accrue()
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.nft_pool_settings; r record; secs numeric; gain numeric; touched integer := 0; total numeric := 0;
begin
  s := public.nft_pool_settings_row();
  perform public.nft_pool_sync_positions();
  if not s.accrual_enabled then return jsonb_build_object('enabled', false, 'positions', 0); end if;
  for r in select * from public.nft_yield_positions where status = 'active' for update loop
    secs := greatest(0, extract(epoch from (now() - r.last_accrual_at)));
    if secs < 60 then continue; end if;
    gain := round(public.nft_effective_daily(r) * (secs / 86400.0), 9);
    update public.nft_yield_positions
       set accrued_ton = accrued_ton + gain,
           roi_reached = roi_reached or (claimed_ton + accrued_ton + gain) >= roi_target_ton,
           last_accrual_at = now(), updated_at = now()
     where id = r.id;
    touched := touched + 1; total := total + gain;
  end loop;
  update public.nft_reward_pool
     set reserved_ton = coalesce((select sum(accrued_ton) from public.nft_yield_positions where status = 'active'), 0),
         updated_at = now()
   where id;
  return jsonb_build_object('enabled', true, 'positions', touched, 'accrued', total);
end $$;

/** Player-facing payload: ONLY this player's NFT. No pool balance, no health, no obligations. */
create or replace function public.nft_my_reward(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; p public.nft_yield_positions; s public.nft_pool_settings; total integer;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_pool_accrue();
  s := public.nft_pool_settings_row();
  select * into p from public.nft_yield_positions
   where owner_user_id = u and status = 'active' order by nft_serial limit 1;
  select count(*) into total from public.nft_pets;
  if p.id is null then return jsonb_build_object('hasNft', false, 'totalSupply', greatest(total, 10)); end if;
  return jsonb_build_object(
    'hasNft', true,
    'serial', p.nft_serial,
    'totalSupply', greatest(total, 10),
    'dailyYieldTon', public.nft_effective_daily(p),
    'availableTon', round(p.accrued_ton, 6),
    'lifetimeEarnedTon', round(p.claimed_ton, 6),
    'minClaimTon', s.min_claim_ton,
    'canClaim', round(p.accrued_ton, 6) >= s.min_claim_ton,
    'lastClaimAt', p.last_claim_at
  );
end $$;

/** Claim: real pool balance is the authority. Debits the pool, credits withdrawable TON. */
create or replace function public.nft_claim_reward(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; p public.nft_yield_positions; s public.nft_pool_settings;
        pool public.nft_reward_pool; amount numeric; claim uuid := gen_random_uuid();
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_pool_accrue();
  s := public.nft_pool_settings_row();
  select * into pool from public.nft_reward_pool where id for update;
  select * into p from public.nft_yield_positions
   where owner_user_id = u and status = 'active' order by nft_serial limit 1 for update;
  if p.id is null then raise exception 'NFT_NOT_FOUND'; end if;
  amount := round(p.accrued_ton, 6);
  if amount < s.min_claim_ton then raise exception 'CLAIM_TOO_SMALL'; end if;
  if pool.balance_ton < amount then raise exception 'POOL_INSUFFICIENT'; end if;

  update public.nft_reward_pool
     set balance_ton = balance_ton - amount,
         lifetime_paid_ton = lifetime_paid_ton + amount,
         reserved_ton = greatest(0, reserved_ton - amount),
         updated_at = now()
   where id;
  update public.nft_yield_positions
     set accrued_ton = accrued_ton - amount, claimed_ton = claimed_ton + amount,
         roi_reached = roi_reached or (claimed_ton + amount) >= roi_target_ton,
         last_claim_at = now(), updated_at = now()
   where id = p.id;
  insert into public.nft_pool_transactions(type, amount_ton, balance_before, balance_after, nft_id, user_id, telegram_id, claim_id, note)
  values ('CLAIM_PAYMENT', -amount, pool.balance_ton, pool.balance_ton - amount, p.nft_pet_id, u, p_telegram_id, claim,
          format('NFT #%s claim', p.nft_serial));
  perform public.credit_ton_reward(u, amount, 'nft_reward', claim::text, format('NFT #%s reward claim', p.nft_serial));

  return jsonb_build_object('ok', true, 'claimId', claim, 'amountTon', amount) || public.nft_my_reward(p_telegram_id);
end $$;

-- ------------------------------------------------------------ admin-only reads/writes
create or replace function public.admin_nft_pool_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pool public.nft_reward_pool; obligation numeric; active integer; claimable numeric; total integer;
begin
  perform public.admin_assert(p_admin_id);
  perform public.nft_pool_accrue();
  select * into pool from public.nft_reward_pool where id;
  select coalesce(sum(daily_yield_ton),0), count(*) into obligation, active
    from public.nft_yield_positions where status = 'active';
  select coalesce(sum(accrued_ton),0) into claimable from public.nft_yield_positions where status = 'active';
  select count(*) into total from public.nft_pets;
  return jsonb_build_object(
    'balanceTon', pool.balance_ton, 'reservedTon', pool.reserved_ton,
    'availableTon', greatest(0, pool.balance_ton - pool.reserved_ton),
    'dailyObligationTon', obligation, 'activeNfts', active, 'totalNfts', greatest(total, 10),
    'claimableTon', round(claimable, 6), 'lifetimePaidTon', pool.lifetime_paid_ton,
    'lifetimeFundedTon', pool.lifetime_funded_ton, 'health', public.nft_pool_health(),
    'updatedAt', pool.updated_at);
end $$;

create or replace function public.admin_nft_pool_units(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare out jsonb;
begin
  perform public.admin_assert(p_admin_id);
  perform public.nft_pool_accrue();
  select coalesce(jsonb_agg(x order by x->>'serial'), '[]'::jsonb) into out from (
    select jsonb_build_object(
      'serial', p.nft_serial, 'positionId', p.id, 'status', p.status,
      'tierTon', p.tier_ton, 'dailyYieldTon', p.daily_yield_ton,
      'effectiveDailyTon', public.nft_effective_daily(p),
      'availableTon', round(p.accrued_ton, 6), 'lifetimeEarnedTon', round(p.claimed_ton, 6),
      'roiTargetTon', p.roi_target_ton, 'roiReached', p.roi_reached,
      'lastClaimAt', p.last_claim_at,
      'owner', coalesce(g.username, g.first_name, '—'), 'ownerTelegramId', g.telegram_id
    ) as x
    from public.nft_yield_positions p left join public.game_players g on g.id = p.owner_user_id
  ) q;
  return out;
end $$;

create or replace function public.admin_nft_pool_ledger(p_admin_id bigint, p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare out jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb) into out
    from (select * from public.nft_pool_transactions order by created_at desc limit greatest(1, least(100, p_limit))) t;
  return out;
end $$;

create or replace function public.admin_nft_pool_fund(p_admin_id bigint, p_amount_ton numeric, p_type text default 'FUND', p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pool public.nft_reward_pool; amount numeric;
begin
  perform public.admin_assert(p_admin_id);
  if p_type not in ('FUND','NFT_SALE','REVENUE_SHARE','ADMIN_ADJUSTMENT') then raise exception 'INVALID_TYPE'; end if;
  amount := round(coalesce(p_amount_ton, 0), 9);
  if amount = 0 then raise exception 'INVALID_AMOUNT'; end if;
  select * into pool from public.nft_reward_pool where id for update;
  if pool.balance_ton + amount < 0 then raise exception 'POOL_INSUFFICIENT'; end if;
  update public.nft_reward_pool
     set balance_ton = balance_ton + amount,
         lifetime_funded_ton = lifetime_funded_ton + greatest(amount, 0),
         updated_at = now()
   where id;
  insert into public.nft_pool_transactions(type, amount_ton, balance_before, balance_after, telegram_id, note)
  values (p_type, amount, pool.balance_ton, pool.balance_ton + amount, p_admin_id, p_note);
  perform public.admin_log(p_admin_id, 'nft_pool_fund', null, null, jsonb_build_object('amount', amount, 'type', p_type));
  return public.admin_nft_pool_overview(p_admin_id);
end $$;

create or replace function public.admin_nft_pool_config(p_admin_id bigint, p_key text, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_assert(p_admin_id);
  if p_key not in ('tier20_daily_ton','tier30_daily_ton','roi_multiplier','min_claim_ton') then raise exception 'INVALID_KEY'; end if;
  if p_value is null or p_value < 0 then raise exception 'INVALID_VALUE'; end if;
  execute format('update public.nft_pool_settings set %I = $1, updated_at = now() where id', p_key) using p_value;
  perform public.admin_log(p_admin_id, 'nft_pool_config', null, null, jsonb_build_object('key', p_key, 'value', p_value));
  return public.admin_nft_pool_overview(p_admin_id);
end $$;

create or replace function public.admin_nft_pool_set_tier(p_admin_id bigint, p_serial integer, p_tier_ton numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.nft_pool_settings;
begin
  perform public.admin_assert(p_admin_id);
  if p_tier_ton not in (20, 30) then raise exception 'INVALID_TIER'; end if;
  s := public.nft_pool_settings_row();
  update public.nft_yield_positions
     set tier_ton = p_tier_ton,
         daily_yield_ton = case when p_tier_ton >= 30 then s.tier30_daily_ton else s.tier20_daily_ton end,
         roi_target_ton = p_tier_ton * s.roi_multiplier,
         updated_at = now()
   where nft_serial = p_serial;
  perform public.admin_log(p_admin_id, 'nft_pool_set_tier', null, null, jsonb_build_object('serial', p_serial, 'tier', p_tier_ton));
  return public.admin_nft_pool_units(p_admin_id);
end $$;

create or replace function public.admin_nft_pool_toggle(p_admin_id bigint, p_serial integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_assert(p_admin_id);
  update public.nft_yield_positions
     set status = case when status = 'active' then 'paused' else 'active' end, last_accrual_at = now(), updated_at = now()
   where nft_serial = p_serial and status in ('active','paused');
  perform public.admin_log(p_admin_id, 'nft_pool_toggle', null, null, jsonb_build_object('serial', p_serial));
  return public.admin_nft_pool_units(p_admin_id);
end $$;

-- ------------------------------------------------------------ lock down execution (backend only)
do $lock$
declare f record;
begin
  for f in select p.oid::regprocedure::text sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('nft_pool_settings_row','nft_pool_sync_positions','row_count_of_last','nft_pool_health',
                                'nft_effective_daily','nft_pool_accrue','nft_my_reward','nft_claim_reward',
                                'admin_nft_pool_overview','admin_nft_pool_units','admin_nft_pool_ledger',
                                'admin_nft_pool_fund','admin_nft_pool_config','admin_nft_pool_set_tier','admin_nft_pool_toggle')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role, postgres', f.sig);
  end loop;
end $lock$;

select cron.schedule('nft-pool-accrue', '*/10 * * * *', $cron$select public.nft_pool_accrue();$cron$)
where not exists (select 1 from cron.job where jobname = 'nft-pool-accrue');
