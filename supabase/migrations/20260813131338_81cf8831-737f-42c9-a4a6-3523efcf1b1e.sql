-- ============================================================================
-- Market fee treasury accounting
-- The 5% fee is ALREADY excluded from the seller credit (seller gets net only).
-- What was missing: the fee had no accounting home, so it was invisible revenue.
-- Money never moves on-chain here: every external TON payment lands in the
-- single official hot wallet, and this ledger records which part of that
-- balance belongs to players (liabilities) vs to the game (fee revenue).
-- ============================================================================

create table if not exists public.market_revenue_ledger (
  id uuid primary key default gen_random_uuid(),
  entry_type text not null check (entry_type in ('MARKET_SALE','MARKET_FEE','SELLER_CREDIT')),
  transaction_id uuid not null references public.market_transactions(id) on delete cascade,
  listing_id uuid,
  buyer_user_id uuid,
  seller_user_id uuid,
  item_type text,
  item_instance_id uuid,
  item_code text,
  currency text not null check (currency in ('TON','FC')),
  gross_amount_ton numeric(20,9),
  market_fee_ton numeric(20,9),
  seller_net_ton numeric(20,9),
  gross_amount_fc numeric(20,2),
  market_fee_fc numeric(20,2),
  seller_net_fc numeric(20,2),
  fee_percent numeric(6,3),
  payment_method text not null check (payment_method in ('INTERNAL_BALANCE','TON_WALLET')),
  tx_hash text,
  created_at timestamptz not null default now()
);

-- one entry of each kind per transaction: blocks double click, retry,
-- duplicated webhook and a tx verified twice
create unique index if not exists market_revenue_ledger_unique
  on public.market_revenue_ledger(transaction_id, entry_type);
create index if not exists market_revenue_ledger_created_idx
  on public.market_revenue_ledger(created_at desc);

grant all on public.market_revenue_ledger to service_role;
alter table public.market_revenue_ledger enable row level security;
-- backend/admin only: players never read market revenue
create policy "market revenue ledger service only"
  on public.market_revenue_ledger for all to service_role using (true) with check (true);

create table if not exists public.market_treasury (
  id boolean primary key default true check (id),
  gross_volume_ton numeric(20,9) not null default 0,
  market_fee_revenue_ton numeric(20,9) not null default 0,
  seller_payout_ton numeric(20,9) not null default 0,
  gross_volume_fc numeric(20,2) not null default 0,
  market_fee_revenue_fc numeric(20,2) not null default 0,
  seller_payout_fc numeric(20,2) not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.market_treasury(id) values (true) on conflict (id) do nothing;

grant all on public.market_treasury to service_role;
alter table public.market_treasury enable row level security;
create policy "market treasury service only"
  on public.market_treasury for all to service_role using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Sale + fee are booked in the very same transaction as the purchase, so a
-- rollback anywhere in market_finalize_purchase also rolls back the revenue.
-- ---------------------------------------------------------------------------
create or replace function public.market_book_sale_entries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare cur text; method text; gross numeric; fee numeric; net numeric;
begin
  cur := coalesce(new.currency, 'FC');
  -- TON purchases paid from the internal balance are already TON-backed inside
  -- the hot wallet; an external payment carries the on-chain hash.
  method := case when cur = 'TON' and coalesce(nullif(btrim(coalesce(new.tx_hash,'')),''), null) is not null
                 then 'TON_WALLET' else 'INTERNAL_BALANCE' end;

  if cur = 'TON' then
    gross := new.price_ton; fee := new.fee_ton; net := new.seller_received_ton;
  else
    gross := new.price_fc; fee := new.fee_fc; net := new.seller_received_fc;
  end if;

  insert into market_revenue_ledger(entry_type, transaction_id, listing_id, buyer_user_id, seller_user_id,
    item_type, item_instance_id, item_code, currency,
    gross_amount_ton, market_fee_ton, seller_net_ton,
    gross_amount_fc, market_fee_fc, seller_net_fc,
    fee_percent, payment_method, tx_hash)
  select e.entry_type, new.id, new.listing_id, new.buyer_user_id, new.seller_user_id,
         new.item_type, new.item_instance_id, new.item_code, cur,
         case when cur = 'TON' then gross end, case when cur = 'TON' then fee end, case when cur = 'TON' then net end,
         case when cur = 'FC' then gross end, case when cur = 'FC' then fee end, case when cur = 'FC' then net end,
         new.fee_percent, method, nullif(btrim(coalesce(new.tx_hash,'')),'')
    from (values ('MARKET_SALE'), ('MARKET_FEE')) as e(entry_type)
  on conflict (transaction_id, entry_type) do nothing;

  update market_treasury
     set gross_volume_ton = gross_volume_ton + case when cur = 'TON' then coalesce(gross,0) else 0 end,
         market_fee_revenue_ton = market_fee_revenue_ton + case when cur = 'TON' then coalesce(fee,0) else 0 end,
         gross_volume_fc = gross_volume_fc + case when cur = 'FC' then coalesce(gross,0) else 0 end,
         market_fee_revenue_fc = market_fee_revenue_fc + case when cur = 'FC' then coalesce(fee,0) else 0 end,
         updated_at = now()
   where id;

  return new;
end $$;

drop trigger if exists trg_market_book_sale on public.market_transactions;
create trigger trg_market_book_sale
  after insert on public.market_transactions
  for each row execute function public.market_book_sale_entries();

-- ---------------------------------------------------------------------------
-- Seller credit is booked only when the sale is actually released (settled).
-- Reversal removes the fee revenue again so treasury never overstates income.
-- ---------------------------------------------------------------------------
create or replace function public.market_book_settlement_entries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare cur text; method text;
begin
  cur := coalesce(new.currency, 'FC');
  method := case when cur = 'TON' and nullif(btrim(coalesce(new.tx_hash,'')),'') is not null
                 then 'TON_WALLET' else 'INTERNAL_BALANCE' end;

  if new.status = 'settled' and coalesce(old.status,'') <> 'settled' then
    insert into market_revenue_ledger(entry_type, transaction_id, listing_id, buyer_user_id, seller_user_id,
      item_type, item_instance_id, item_code, currency,
      gross_amount_ton, market_fee_ton, seller_net_ton,
      gross_amount_fc, market_fee_fc, seller_net_fc,
      fee_percent, payment_method, tx_hash)
    values ('SELLER_CREDIT', new.id, new.listing_id, new.buyer_user_id, new.seller_user_id,
      new.item_type, new.item_instance_id, new.item_code, cur,
      case when cur = 'TON' then new.price_ton end, case when cur = 'TON' then new.fee_ton end,
      case when cur = 'TON' then new.seller_received_ton end,
      case when cur = 'FC' then new.price_fc end, case when cur = 'FC' then new.fee_fc end,
      case when cur = 'FC' then new.seller_received_fc end,
      new.fee_percent, method, nullif(btrim(coalesce(new.tx_hash,'')),''))
    on conflict (transaction_id, entry_type) do nothing;

    update market_treasury
       set seller_payout_ton = seller_payout_ton + case when cur = 'TON' then coalesce(new.seller_received_ton,0) else 0 end,
           seller_payout_fc = seller_payout_fc + case when cur = 'FC' then coalesce(new.seller_received_fc,0) else 0 end,
           updated_at = now()
     where id;
  end if;

  if new.status = 'reversed' and coalesce(old.status,'') <> 'reversed' then
    delete from market_revenue_ledger where transaction_id = new.id;
    update market_treasury
       set gross_volume_ton = greatest(gross_volume_ton - case when cur = 'TON' then coalesce(new.price_ton,0) else 0 end, 0),
           market_fee_revenue_ton = greatest(market_fee_revenue_ton - case when cur = 'TON' then coalesce(new.fee_ton,0) else 0 end, 0),
           seller_payout_ton = greatest(seller_payout_ton - case when cur = 'TON' and old.status = 'settled' then coalesce(new.seller_received_ton,0) else 0 end, 0),
           gross_volume_fc = greatest(gross_volume_fc - case when cur = 'FC' then coalesce(new.price_fc,0) else 0 end, 0),
           market_fee_revenue_fc = greatest(market_fee_revenue_fc - case when cur = 'FC' then coalesce(new.fee_fc,0) else 0 end, 0),
           seller_payout_fc = greatest(seller_payout_fc - case when cur = 'FC' and old.status = 'settled' then coalesce(new.seller_received_fc,0) else 0 end, 0),
           updated_at = now()
     where id;
  end if;

  return new;
end $$;

drop trigger if exists trg_market_book_settlement on public.market_transactions;
create trigger trg_market_book_settlement
  after update of status on public.market_transactions
  for each row execute function public.market_book_settlement_entries();

-- ---------------------------------------------------------------------------
-- Backfill existing history (balances untouched)
-- ---------------------------------------------------------------------------
insert into public.market_revenue_ledger(entry_type, transaction_id, listing_id, buyer_user_id, seller_user_id,
  item_type, item_instance_id, item_code, currency,
  gross_amount_ton, market_fee_ton, seller_net_ton,
  gross_amount_fc, market_fee_fc, seller_net_fc,
  fee_percent, payment_method, tx_hash, created_at)
select e.entry_type, t.id, t.listing_id, t.buyer_user_id, t.seller_user_id,
       t.item_type, t.item_instance_id, t.item_code, coalesce(t.currency,'FC'),
       case when coalesce(t.currency,'FC') = 'TON' then t.price_ton end,
       case when coalesce(t.currency,'FC') = 'TON' then t.fee_ton end,
       case when coalesce(t.currency,'FC') = 'TON' then t.seller_received_ton end,
       case when coalesce(t.currency,'FC') = 'FC' then t.price_fc end,
       case when coalesce(t.currency,'FC') = 'FC' then t.fee_fc end,
       case when coalesce(t.currency,'FC') = 'FC' then t.seller_received_fc end,
       t.fee_percent,
       case when coalesce(t.currency,'FC') = 'TON' and nullif(btrim(coalesce(t.tx_hash,'')),'') is not null
            then 'TON_WALLET' else 'INTERNAL_BALANCE' end,
       nullif(btrim(coalesce(t.tx_hash,'')),''),
       coalesce(t.settled_at, t.created_at)
  from public.market_transactions t
  cross join (values ('MARKET_SALE'), ('MARKET_FEE')) as e(entry_type)
 where coalesce(t.status,'') <> 'reversed'
on conflict (transaction_id, entry_type) do nothing;

insert into public.market_revenue_ledger(entry_type, transaction_id, listing_id, buyer_user_id, seller_user_id,
  item_type, item_instance_id, item_code, currency,
  gross_amount_ton, market_fee_ton, seller_net_ton,
  gross_amount_fc, market_fee_fc, seller_net_fc,
  fee_percent, payment_method, tx_hash, created_at)
select 'SELLER_CREDIT', t.id, t.listing_id, t.buyer_user_id, t.seller_user_id,
       t.item_type, t.item_instance_id, t.item_code, coalesce(t.currency,'FC'),
       case when coalesce(t.currency,'FC') = 'TON' then t.price_ton end,
       case when coalesce(t.currency,'FC') = 'TON' then t.fee_ton end,
       case when coalesce(t.currency,'FC') = 'TON' then t.seller_received_ton end,
       case when coalesce(t.currency,'FC') = 'FC' then t.price_fc end,
       case when coalesce(t.currency,'FC') = 'FC' then t.fee_fc end,
       case when coalesce(t.currency,'FC') = 'FC' then t.seller_received_fc end,
       t.fee_percent,
       case when coalesce(t.currency,'FC') = 'TON' and nullif(btrim(coalesce(t.tx_hash,'')),'') is not null
            then 'TON_WALLET' else 'INTERNAL_BALANCE' end,
       nullif(btrim(coalesce(t.tx_hash,'')),''),
       coalesce(t.settled_at, t.created_at)
  from public.market_transactions t
 where t.status = 'settled'
on conflict (transaction_id, entry_type) do nothing;

update public.market_treasury set
  gross_volume_ton = coalesce((select sum(gross_amount_ton) from market_revenue_ledger where entry_type='MARKET_SALE' and currency='TON'),0),
  market_fee_revenue_ton = coalesce((select sum(market_fee_ton) from market_revenue_ledger where entry_type='MARKET_FEE' and currency='TON'),0),
  seller_payout_ton = coalesce((select sum(seller_net_ton) from market_revenue_ledger where entry_type='SELLER_CREDIT' and currency='TON'),0),
  gross_volume_fc = coalesce((select sum(gross_amount_fc) from market_revenue_ledger where entry_type='MARKET_SALE' and currency='FC'),0),
  market_fee_revenue_fc = coalesce((select sum(market_fee_fc) from market_revenue_ledger where entry_type='MARKET_FEE' and currency='FC'),0),
  seller_payout_fc = coalesce((select sum(seller_net_fc) from market_revenue_ledger where entry_type='SELLER_CREDIT' and currency='FC'),0),
  updated_at = now()
where id;

-- ---------------------------------------------------------------------------
-- Admin-only revenue report (super admin lock via admin_assert)
-- ---------------------------------------------------------------------------
create or replace function public.admin_market_revenue(p_admin_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare tre market_treasury%rowtype; res jsonb;
begin
  perform admin_assert(p_admin_id);
  select * into tre from market_treasury where id;

  select jsonb_build_object(
    'feeTon', jsonb_build_object(
      'today', coalesce(sum(market_fee_ton) filter (where currency='TON' and created_at >= date_trunc('day', now())),0),
      'days7', coalesce(sum(market_fee_ton) filter (where currency='TON' and created_at > now() - interval '7 days'),0),
      'days30', coalesce(sum(market_fee_ton) filter (where currency='TON' and created_at > now() - interval '30 days'),0),
      'lifetime', coalesce(tre.market_fee_revenue_ton,0)),
    'feeFc', jsonb_build_object(
      'today', coalesce(sum(market_fee_fc) filter (where currency='FC' and created_at >= date_trunc('day', now())),0),
      'days7', coalesce(sum(market_fee_fc) filter (where currency='FC' and created_at > now() - interval '7 days'),0),
      'days30', coalesce(sum(market_fee_fc) filter (where currency='FC' and created_at > now() - interval '30 days'),0),
      'lifetime', coalesce(tre.market_fee_revenue_fc,0)),
    'sales', jsonb_build_object(
      'count', count(*) filter (where entry_type='MARKET_FEE'),
      'grossTon', coalesce(tre.gross_volume_ton,0),
      'grossFc', coalesce(tre.gross_volume_fc,0),
      'payoutTon', coalesce(tre.seller_payout_ton,0),
      'payoutFc', coalesce(tre.seller_payout_fc,0),
      'externalTon', coalesce(sum(gross_amount_ton) filter (where entry_type='MARKET_SALE' and payment_method='TON_WALLET'),0),
      'internalTon', coalesce(sum(gross_amount_ton) filter (where entry_type='MARKET_SALE' and payment_method='INTERNAL_BALANCE'),0))
  ) into res
  from market_revenue_ledger where entry_type in ('MARKET_SALE','MARKET_FEE');

  return jsonb_build_object('ok', true, 'revenue', res, 'updatedAt', tre.updated_at);
end $$;

revoke all on function public.admin_market_revenue(bigint) from public, anon, authenticated;
grant execute on function public.admin_market_revenue(bigint) to service_role;