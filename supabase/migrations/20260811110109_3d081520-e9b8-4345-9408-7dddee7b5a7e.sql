-- 1. Central registry: one blockchain transaction can only ever pay for one operation.
CREATE TABLE IF NOT EXISTS public.processed_ton_transactions (
  tx_hash text PRIMARY KEY,
  transaction_type text NOT NULL,
  reference_id text NOT NULL,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  amount_nano numeric NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.processed_ton_transactions TO service_role;
ALTER TABLE public.processed_ton_transactions ENABLE ROW LEVEL SECURITY;

-- 2. Deposits get explicit lifecycle states (no client ever writes these).
ALTER TABLE public.wallet_deposits DROP CONSTRAINT IF EXISTS wallet_deposits_status_check;
ALTER TABLE public.wallet_deposits ADD CONSTRAINT wallet_deposits_status_check
  CHECK (status = ANY (ARRAY['pending'::text,'confirmed'::text,'credited'::text,'expired'::text,'failed'::text,'rejected'::text]));

-- 3. A deposit can only ever credit FC once (ledger reference is the idempotency anchor).
CREATE UNIQUE INDEX IF NOT EXISTS wallet_ledger_deposit_credit_once
  ON public.wallet_ledger(reference_id) WHERE type = 'deposit_credit';

-- 4. Confirmation now trusts the real on-chain amount and never fails a paid deposit for being late.
CREATE OR REPLACE FUNCTION public.confirm_wallet_deposit(p_deposit_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  d public.wallet_deposits%rowtype;
  rate numeric;
  credit numeric;
  received_nano numeric;
  expected_nano numeric;
  confirmed_ton numeric;
  before_balance numeric;
  after_balance numeric;
  pool jsonb;
begin
  if p_tx_hash is null or nullif(trim(p_tx_hash),'') is null then raise exception 'TX_HASH_REQUIRED'; end if;

  select * into d from public.wallet_deposits where id = p_deposit_id for update;
  if d.id is null then raise exception 'DEPOSIT_NOT_FOUND'; end if;

  if d.status = 'credited' then
    return jsonb_build_object('status','already_processed','depositId',d.id,'amountFc',d.amount_fc,'amountTon',d.amount_ton);
  end if;

  received_nano := floor(p_amount_nano::numeric);
  expected_nano := round(d.amount_ton * 1000000000);
  if received_nano is null or received_nano <= 0 then raise exception 'PAYMENT_AMOUNT_INVALID'; end if;
  -- 3% tolerance absorbs wallet-side fee rounding; anything smaller is not this payment.
  if received_nano < floor(expected_nano * 97 / 100) then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
  -- Never credit more than the player ordered.
  if received_nano > expected_nano then received_nano := expected_nano; end if;

  confirmed_ton := round(received_nano / 1000000000, 9);
  if confirmed_ton < 1 then
    update public.wallet_deposits set status = 'rejected' where id = d.id;
    raise exception 'MINIMUM_DEPOSIT_1_TON';
  end if;

  -- One blockchain transaction = one operation, forever.
  if exists (select 1 from public.wallet_deposits where tx_hash = p_tx_hash and id <> d.id)
     or exists (select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
     or exists (select 1 from public.season_pass_orders where tx_hash = p_tx_hash)
     or exists (select 1 from public.processed_ton_transactions where tx_hash = p_tx_hash and reference_id <> d.id::text) then
    raise exception 'TX_ALREADY_USED';
  end if;

  rate := public.current_ton_fc_rate();
  credit := round(confirmed_ton * rate);

  select forge_coins into before_balance from public.game_players where id = d.user_id for update;
  if before_balance is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  update public.game_players
     set forge_coins = forge_coins + credit, updated_at = now()
   where id = d.user_id
   returning forge_coins into after_balance;

  insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, conversion_rate, balance_before, balance_after, reference_id, tx_hash)
  values (d.user_id, 'deposit_credit', credit, confirmed_ton, rate, before_balance, after_balance, d.id::text, p_tx_hash);

  insert into public.processed_ton_transactions(tx_hash, transaction_type, reference_id, user_id, amount_nano)
  values (p_tx_hash, 'deposit', d.id::text, d.user_id, received_nano)
  on conflict (tx_hash) do nothing;

  update public.wallet_deposits
     set status = 'credited',
         tx_hash = p_tx_hash,
         amount_ton = confirmed_ton,
         amount_fc = credit,
         conversion_rate = rate,
         confirmed_at = coalesce(confirmed_at, now()),
         credited_at = now()
   where id = d.id;

  perform public.distribute_referral_commission(d.user_id, 'deposit:'||d.id::text, 'deposit', credit, true, 'TON', confirmed_ton);

  pool := public.record_ton_revenue(d.user_id, confirmed_ton, 'deposit', d.id::text, p_tx_hash);

  return jsonb_build_object('status','credited','depositId',d.id,'amountTon',confirmed_ton,'amountFc',credit,'conversionRate',rate,'balanceBefore',before_balance,'balanceAfter',after_balance,'poolContribution',pool);
end
$function$;

REVOKE ALL ON FUNCTION public.confirm_wallet_deposit(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_wallet_deposit(uuid, text, text) TO service_role;

-- 5. Server-side list of deposits that still need on-chain reconciliation (never expires them by time).
CREATE OR REPLACE FUNCTION public.pending_wallet_deposits(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare u uuid; rows jsonb;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id,
           'amountTon', x.amount_ton,
           'amountNano', round(x.amount_ton * 1000000000)::text,
           'paymentComment', x.payment_comment,
           'fromWallet', x.from_wallet,
           'status', x.status,
           'createdAt', x.created_at
         ) order by x.created_at desc), '[]'::jsonb)
    into rows
    from (
      select * from public.wallet_deposits
       where user_id = u
         and tx_hash is null
         and status in ('pending','confirmed','expired')
       order by created_at desc
       limit 30
    ) x;
  return jsonb_build_object('userId', u, 'deposits', rows);
end
$function$;

REVOKE ALL ON FUNCTION public.pending_wallet_deposits(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pending_wallet_deposits(bigint) TO service_role;