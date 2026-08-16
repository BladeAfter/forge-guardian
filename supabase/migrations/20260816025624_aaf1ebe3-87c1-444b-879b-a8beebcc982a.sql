-- 0032: direct TON deposits (TON -> internal TON balance) alongside the existing TON -> FC flow.

ALTER TABLE public.wallet_deposits
  ADD COLUMN IF NOT EXISTS deposit_type text NOT NULL DEFAULT 'ton_to_fc';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'wallet_deposits_deposit_type_check') THEN
    ALTER TABLE public.wallet_deposits
      ADD CONSTRAINT wallet_deposits_deposit_type_check CHECK (deposit_type IN ('ton_to_fc','ton_balance'));
  END IF;
END $$;

INSERT INTO public.economy_settings(key, value_numeric) VALUES
  ('direct_ton_deposit_enabled', 1),
  ('ton_to_fc_deposit_enabled', 1),
  ('min_direct_ton_deposit', 0.1)
ON CONFLICT (key) DO NOTHING;

-- Single source of truth for both deposit modes (admin-tunable, no deploy needed).
CREATE OR REPLACE FUNCTION public.wallet_deposit_config()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'fcEnabled', COALESCE((SELECT value_numeric FROM economy_settings WHERE key='ton_to_fc_deposit_enabled'),1) > 0,
    'directEnabled', COALESCE((SELECT value_numeric FROM economy_settings WHERE key='direct_ton_deposit_enabled'),1) > 0,
    'minFcTon', 1::numeric,
    'minDirectTon', GREATEST(COALESCE((SELECT value_numeric FROM economy_settings WHERE key='min_direct_ton_deposit'),0.1), 0.01),
    'fcPerTon', COALESCE((SELECT value_numeric FROM economy_settings WHERE key='fc_per_ton'),100000)
  );
$$;

REVOKE ALL ON FUNCTION public.wallet_deposit_config() FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.create_wallet_deposit(bigint, numeric, text, text);

CREATE OR REPLACE FUNCTION public.create_wallet_deposit(
  p_telegram_id bigint,
  p_amount_ton numeric,
  p_from_wallet text,
  p_idempotency_key text,
  p_deposit_type text DEFAULT 'ton_to_fc'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  u uuid;
  rate numeric;
  d wallet_deposits%rowtype;
  address text;
  cfg jsonb;
  kind text := lower(coalesce(nullif(btrim(p_deposit_type),''),'ton_to_fc'));
  min_ton numeric;
begin
  if kind not in ('ton_to_fc','ton_balance') then raise exception 'INVALID_DEPOSIT_TYPE'; end if;
  cfg := public.wallet_deposit_config();
  if kind = 'ton_balance' and not (cfg->>'directEnabled')::boolean then raise exception 'DIRECT_TON_DEPOSIT_DISABLED'; end if;
  if kind = 'ton_to_fc' and not (cfg->>'fcEnabled')::boolean then raise exception 'TON_TO_FC_DEPOSIT_DISABLED'; end if;

  min_ton := case when kind = 'ton_balance' then (cfg->>'minDirectTon')::numeric else (cfg->>'minFcTon')::numeric end;
  if p_amount_ton is null or p_amount_ton < min_ton then
    raise exception 'MINIMUM_DEPOSIT_%_TON', trim(to_char(min_ton,'FM999990.999999999'));
  end if;
  if p_amount_ton > 100000 then raise exception 'INVALID_DEPOSIT_AMOUNT'; end if;

  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select * into d from wallet_deposits where idempotency_key = p_idempotency_key;
  if d.id is not null then
    return jsonb_build_object('id',d.id,'depositType',d.deposit_type,'paymentAddress',wallet_hot_address(),
      'amountNano',round(d.amount_ton*1000000000)::text,'amountTon',d.amount_ton,
      'amountFc',case when d.deposit_type='ton_to_fc' then d.amount_fc else 0 end,
      'paymentComment',d.payment_comment,'expiresAt',d.expires_at);
  end if;

  rate := coalesce((cfg->>'fcPerTon')::numeric, 100000);
  address := wallet_hot_address();
  insert into wallet_deposits(user_id,amount_ton,amount_fc,from_wallet,payment_comment,idempotency_key,deposit_type,conversion_rate)
  values (u,p_amount_ton, case when kind='ton_to_fc' then round(p_amount_ton*rate) else 0 end,
          p_from_wallet,'forge_deposit:'||gen_random_uuid(),p_idempotency_key,kind,
          case when kind='ton_to_fc' then rate else 0 end)
  returning * into d;

  return jsonb_build_object('id',d.id,'depositType',d.deposit_type,'paymentAddress',address,
    'amountNano',round(d.amount_ton*1000000000)::text,'amountTon',d.amount_ton,
    'amountFc',case when d.deposit_type='ton_to_fc' then d.amount_fc else 0 end,
    'paymentComment',d.payment_comment,'expiresAt',d.expires_at);
end
$function$;

REVOKE ALL ON FUNCTION public.create_wallet_deposit(bigint, numeric, text, text, text) FROM PUBLIC, anon, authenticated;

-- Confirmation stays fully atomic and now honours the deposit_type saved when the intent was created.
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
  cfg jsonb;
  min_ton numeric;
  ton_result jsonb;
begin
  if p_tx_hash is null or nullif(trim(p_tx_hash),'') is null then raise exception 'TX_HASH_REQUIRED'; end if;

  select * into d from public.wallet_deposits where id = p_deposit_id for update;
  if d.id is null then raise exception 'DEPOSIT_NOT_FOUND'; end if;

  if d.status = 'credited' then
    return jsonb_build_object('status','already_processed','depositId',d.id,'depositType',d.deposit_type,
      'amountFc',d.amount_fc,'amountTon',d.amount_ton);
  end if;

  received_nano := floor(p_amount_nano::numeric);
  expected_nano := round(d.amount_ton * 1000000000);
  if received_nano is null or received_nano <= 0 then raise exception 'PAYMENT_AMOUNT_INVALID'; end if;
  -- 3% tolerance absorbs wallet-side fee rounding; anything smaller is not this payment.
  if received_nano < floor(expected_nano * 97 / 100) then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
  -- Never credit more than the player ordered.
  if received_nano > expected_nano then received_nano := expected_nano; end if;

  confirmed_ton := round(received_nano / 1000000000, 9);
  cfg := public.wallet_deposit_config();
  min_ton := case when d.deposit_type = 'ton_balance' then (cfg->>'minDirectTon')::numeric else (cfg->>'minFcTon')::numeric end;
  if confirmed_ton < min_ton then
    update public.wallet_deposits set status = 'rejected' where id = d.id;
    raise exception 'MINIMUM_DEPOSIT_%_TON', trim(to_char(min_ton,'FM999990.999999999'));
  end if;

  -- One blockchain transaction = one operation, forever.
  if exists (select 1 from public.wallet_deposits where tx_hash = p_tx_hash and id <> d.id)
     or exists (select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
     or exists (select 1 from public.season_pass_orders where tx_hash = p_tx_hash)
     or exists (select 1 from public.processed_ton_transactions where tx_hash = p_tx_hash and reference_id <> d.id::text) then
    raise exception 'TX_ALREADY_USED';
  end if;

  if d.deposit_type = 'ton_balance' then
    -- Direct TON top-up: the internal TON balance is credited 1:1 and FC is never touched.
    select coalesce(ton_balance,0) into before_balance from public.game_players where id = d.user_id for update;
    if before_balance is null then raise exception 'PLAYER_NOT_FOUND'; end if;

    ton_result := public.credit_ton_reward(d.user_id, confirmed_ton, 'direct_deposit', d.id::text,
      'TON_DIRECT_DEPOSIT '||p_tx_hash);
    after_balance := coalesce((ton_result->>'balanceTon')::numeric, before_balance + confirmed_ton);

    insert into public.wallet_ledger(user_id, type, amount_fc, amount_ton, conversion_rate, balance_before, balance_after, reference_id, tx_hash)
    values (d.user_id, 'ton_direct_deposit', 0, confirmed_ton, 0, before_balance, after_balance, d.id::text, p_tx_hash);

    insert into public.processed_ton_transactions(tx_hash, transaction_type, reference_id, user_id, amount_nano)
    values (p_tx_hash, 'ton_direct_deposit', d.id::text, d.user_id, received_nano)
    on conflict (tx_hash) do nothing;

    update public.wallet_deposits
       set status = 'credited',
           tx_hash = p_tx_hash,
           amount_ton = confirmed_ton,
           amount_fc = 0,
           conversion_rate = 0,
           confirmed_at = coalesce(confirmed_at, now()),
           credited_at = now()
     where id = d.id;

    return jsonb_build_object('status','credited','depositId',d.id,'depositType',d.deposit_type,
      'amountTon',confirmed_ton,'amountFc',0,'balanceBefore',before_balance,'balanceAfter',after_balance,
      'tonBalance',after_balance);
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

  return jsonb_build_object('status','credited','depositId',d.id,'depositType',d.deposit_type,'amountTon',confirmed_ton,
    'amountFc',credit,'conversionRate',rate,'balanceBefore',before_balance,'balanceAfter',after_balance,'poolContribution',pool);
end
$function$;

REVOKE ALL ON FUNCTION public.confirm_wallet_deposit(uuid, text, text) FROM PUBLIC, anon, authenticated;

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
           'depositType', x.deposit_type,
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

CREATE OR REPLACE FUNCTION public.get_wallet_summary(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare u game_players%rowtype; rate numeric; fee numeric;
begin
 select * into u from game_players where telegram_id=p_telegram_id;
 if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
 select value_numeric into rate from economy_settings where key='fc_per_ton';
 rate := coalesce(nullif(rate,0),100000);
 fee := public.withdraw_fee_percent();
 return jsonb_build_object('balanceFc',u.forge_coins,'equivalentTon',round(u.forge_coins/rate,4),
  'withdrawFeePercent',fee,'fcPerTon',rate,
  'depositConfig',public.wallet_deposit_config(),
  'deposits',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'depositType',deposit_type,'amountTon',amount_ton,'amountFc',amount_fc,'status',status,'txHash',tx_hash,'createdAt',created_at)order by created_at desc),'[]')from(select*from wallet_deposits where user_id=u.id order by created_at desc limit 30)x),
  'withdrawals',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'amountFc',amount_fc,'amountTon',amount_ton,'grossTon',coalesce(gross_ton,amount_ton),'feePercent',coalesce(fee_percent,0),'feeTon',coalesce(fee_ton,0),'netTon',coalesce(net_ton,amount_ton),'status',status,'createdAt',created_at)order by created_at desc),'[]')from(select*from wallet_withdrawals where user_id=u.id order by created_at desc limit 30)x),
  'eggOrders',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'eggName',e.name,'priceTon',o.price_ton,'status',o.status,'createdAt',o.created_at)order by o.created_at desc),'[]')from(select*from pet_egg_orders where user_id=u.id order by created_at desc limit 30)o join pet_eggs e on e.id=o.egg_id),
  'history',(select coalesce(jsonb_agg(z order by created_at desc),'[]')from(
   select jsonb_build_object('id',id,'type','deposit','depositType',deposit_type,'label',case when deposit_type='ton_balance' then 'Deposito direto de '||amount_ton||' TON' else 'Deposito de '||amount_ton||' TON' end,'amountFc',amount_fc,'amountTon',amount_ton,'txHash',tx_hash,'status',status,'createdAt',created_at)z,created_at from wallet_deposits where user_id=u.id
   union all select jsonb_build_object('id',id,'type','withdrawal','label','Saque de '||amount_fc||' FC','amountFc',amount_fc,'amountTon',amount_ton,'grossTon',coalesce(gross_ton,amount_ton),'feePercent',coalesce(fee_percent,0),'feeTon',coalesce(fee_ton,0),'netTon',coalesce(net_ton,amount_ton),'status',status,'createdAt',created_at),created_at from wallet_withdrawals where user_id=u.id
   union all select jsonb_build_object('id',o.id,'type','egg_order','label',e.name,'amountFc',null,'amountTon',o.price_ton,'status',o.status,'createdAt',o.created_at),o.created_at from pet_egg_orders o join pet_eggs e on e.id=o.egg_id where o.user_id=u.id
   order by created_at desc limit 50)h));
end$function$;

REVOKE ALL ON FUNCTION public.get_wallet_summary(bigint) FROM PUBLIC, anon, authenticated;

-- Admin audit can tell the two deposit types apart.
CREATE OR REPLACE FUNCTION public.admin_list_transactions(p_admin_id bigint, p_kind text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v jsonb; v_kind text := lower(COALESCE(p_kind,'deposit'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_kind = 'deposit' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v FROM (
      SELECT d.id, d.amount_ton, d.amount_fc, d.deposit_type, d.status, d.tx_hash, d.from_wallet, d.created_at,
             COALESCE(g.username, g.display_name, g.telegram_id::text) AS player
      FROM public.wallet_deposits d JOIN public.game_players g ON g.id = d.user_id
      WHERE p_status IS NULL OR d.status = p_status
      ORDER BY d.created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit,10),50))) t;
  ELSE
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v FROM (
      SELECT w.id, w.amount_fc, w.amount_ton, w.status, w.tx_hash, w.wallet_address, w.created_at,
             COALESCE(g.username, g.display_name, g.telegram_id::text) AS player
      FROM public.wallet_withdrawals w JOIN public.game_players g ON g.id = w.user_id
      WHERE p_status IS NULL OR w.status = p_status
      ORDER BY w.created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit,10),50))) t;
  END IF;
  RETURN jsonb_build_object('kind',v_kind,'items',v);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_transactions(bigint, text, text, integer) FROM PUBLIC, anon, authenticated;

-- Admin toggles/limits for both deposit methods (no deploy required).
CREATE OR REPLACE FUNCTION public.admin_deposit_settings(p_admin_id bigint, p_key text DEFAULT NULL, p_value numeric DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_key text := lower(COALESCE(btrim(p_key),''));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_key <> '' THEN
    IF v_key NOT IN ('direct_ton_deposit_enabled','ton_to_fc_deposit_enabled','min_direct_ton_deposit') THEN
      RAISE EXCEPTION 'INVALID_SETTING';
    END IF;
    IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    INSERT INTO public.economy_settings(key, value_numeric) VALUES (v_key, p_value)
    ON CONFLICT (key) DO UPDATE SET value_numeric = excluded.value_numeric, updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'deposit_settings', v_key, jsonb_build_object('value', p_value));
  END IF;
  RETURN public.wallet_deposit_config();
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_deposit_settings(bigint, text, numeric) FROM PUBLIC, anon, authenticated;