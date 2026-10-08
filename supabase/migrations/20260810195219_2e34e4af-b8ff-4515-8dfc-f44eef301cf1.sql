alter table public.wallet_deposits add column if not exists conversion_rate numeric not null default 100000;

create unique index if not exists wallet_deposits_tx_hash_unique on public.wallet_deposits(tx_hash) where tx_hash is not null;

alter table public.game_players alter column forge_coins set default 0;
alter table public.game_players alter column forge_coins set not null;

create table if not exists public.wallet_ledger(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  type text not null,
  amount_fc numeric not null default 0,
  amount_ton numeric,
  conversion_rate numeric,
  balance_before numeric not null default 0,
  balance_after numeric not null default 0,
  reference_id text,
  tx_hash text,
  created_at timestamptz not null default now()
);

grant all on public.wallet_ledger to service_role;
alter table public.wallet_ledger enable row level security;
drop policy if exists "service role manages wallet ledger" on public.wallet_ledger;
create policy "service role manages wallet ledger" on public.wallet_ledger for all to service_role using(true) with check(true);
create index if not exists wallet_ledger_user_idx on public.wallet_ledger(user_id, created_at desc);
create unique index if not exists wallet_ledger_reference_unique on public.wallet_ledger(type, reference_id) where reference_id is not null;

insert into public.economy_settings(key, value_numeric, updated_at)
values ('ton_to_fc_rate', 100000, now())
on conflict (key) do update set value_numeric = excluded.value_numeric, updated_at = now();

insert into public.economy_settings(key, value_numeric, updated_at)
values ('fc_per_ton', 100000, now())
on conflict (key) do update set value_numeric = excluded.value_numeric, updated_at = now();

create or replace function public.current_ton_fc_rate()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select value_numeric from public.economy_settings where key = 'ton_to_fc_rate'),
    (select value_numeric from public.economy_settings where key = 'fc_per_ton'),
    100000
  );
$$;

drop function if exists public.confirm_wallet_deposit(uuid, text, text);

create or replace function public.confirm_wallet_deposit(p_deposit_id uuid, p_tx_hash text, p_amount_nano text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.wallet_deposits%rowtype;
  rate numeric;
  credit numeric;
  before_balance numeric;
  after_balance numeric;
begin
  -- Lock the deposit row: the whole credit runs inside this single transaction.
  select * into d from public.wallet_deposits where id = p_deposit_id for update;
  if d.id is null then raise exception 'DEPOSIT_NOT_FOUND'; end if;

  if d.status = 'credited' then
    return jsonb_build_object('status','already_processed','depositId',d.id,'amountFc',d.amount_fc,'amountTon',d.amount_ton);
  end if;

  if d.expires_at < now() then
    update public.wallet_deposits set status = 'expired' where id = d.id;
    raise exception 'DEPOSIT_EXPIRED';
  end if;

  if p_amount_nano <> round(d.amount_ton * 1000000000)::text then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;

  if exists (select 1 from public.wallet_deposits where tx_hash = p_tx_hash and id <> d.id)
     or exists (select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
     or exists (select 1 from public.season_pass_orders where tx_hash = p_tx_hash) then
    raise exception 'TX_ALREADY_USED';
  end if;

  -- The backend, never the client, decides how many coins a verified TON amount is worth.
  rate := public.current_ton_fc_rate();
  credit := round(d.amount_ton * rate);

  select forge_coins into before_balance from public.game_players where id = d.user_id for update;
  if before_balance is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  update public.game_players
     set forge_coins = forge_coins + credit, updated_at = now()
   where id = d.user_id
   returning forge_coins into after_balance;

  insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, conversion_rate, balance_before, balance_after, reference_id, tx_hash)
  values (d.user_id, 'deposit_credit', credit, d.amount_ton, rate, before_balance, after_balance, d.id::text, p_tx_hash);

  update public.wallet_deposits
     set status = 'credited',
         tx_hash = p_tx_hash,
         amount_fc = credit,
         conversion_rate = rate,
         confirmed_at = coalesce(confirmed_at, now()),
         credited_at = now()
   where id = d.id;

  perform public.distribute_referral_commission(d.user_id, 'deposit:'||d.id::text, 'deposit', credit, true, 'TON', d.amount_ton);

  return jsonb_build_object('status','credited','depositId',d.id,'amountTon',d.amount_ton,'amountFc',credit,'conversionRate',rate,'balanceBefore',before_balance,'balanceAfter',after_balance);
end
$$;

grant execute on function public.confirm_wallet_deposit(uuid, text, text) to service_role;
grant execute on function public.current_ton_fc_rate() to service_role;

create or replace function public.audit_player_deposits(p_telegram_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare u public.game_players%rowtype; last_deposit public.wallet_deposits%rowtype; credited_fc numeric; deposited_ton numeric; ledger_fc numeric;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(sum(amount_ton),0), coalesce(sum(amount_fc),0)
    into deposited_ton, credited_fc
    from public.wallet_deposits where user_id = u.id and status = 'credited';

  select coalesce(sum(amount_fc),0) into ledger_fc
    from public.wallet_ledger where user_id = u.id and type = 'deposit_credit';

  select * into last_deposit from public.wallet_deposits where user_id = u.id order by created_at desc limit 1;

  return jsonb_build_object(
    'playerId', u.id,
    'telegramId', u.telegram_id::text,
    'username', u.username,
    'fcBalance', u.forge_coins,
    'rate', public.current_ton_fc_rate(),
    'totalTonDeposited', deposited_ton,
    'totalFcCreditedFromDeposits', credited_fc,
    'ledgerFcFromDeposits', ledger_fc,
    'mismatch', credited_fc <> ledger_fc,
    'lastDeposit', case when last_deposit.id is null then null else jsonb_build_object(
      'id', last_deposit.id,
      'amountTon', last_deposit.amount_ton,
      'amountFc', last_deposit.amount_fc,
      'status', last_deposit.status,
      'txHash', last_deposit.tx_hash,
      'creditedAt', last_deposit.credited_at,
      'createdAt', last_deposit.created_at) end,
    'pendingCount', (select count(*) from public.wallet_deposits where user_id = u.id and status = 'pending')
  );
end
$$;

grant execute on function public.audit_player_deposits(bigint) to service_role;