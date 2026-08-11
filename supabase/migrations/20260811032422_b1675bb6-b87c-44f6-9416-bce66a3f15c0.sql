CREATE OR REPLACE FUNCTION public.create_wallet_deposit(p_telegram_id bigint, p_amount_ton numeric, p_from_wallet text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; rate numeric; d wallet_deposits%rowtype; address text;
begin
  -- Minimum deposit is 1 TON (= 100,000 FC). Backend is the authority.
  if p_amount_ton is null or p_amount_ton < 1 then raise exception 'MINIMUM_DEPOSIT_1_TON'; end if;
  if p_amount_ton > 100000 then raise exception 'INVALID_DEPOSIT_AMOUNT'; end if;
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into d from wallet_deposits where idempotency_key=p_idempotency_key;
  if d.id is not null then
    return jsonb_build_object('id',d.id,'paymentAddress',wallet_hot_address(),'amountNano',round(d.amount_ton*1000000000)::text,'amountTon',d.amount_ton,'amountFc',d.amount_fc,'paymentComment',d.payment_comment,'expiresAt',d.expires_at);
  end if;
  select value_numeric into rate from economy_settings where key='fc_per_ton';
  address := wallet_hot_address();
  insert into wallet_deposits(user_id,amount_ton,amount_fc,from_wallet,payment_comment,idempotency_key)
  values (u,p_amount_ton,round(p_amount_ton*rate),p_from_wallet,'forge_deposit:'||gen_random_uuid(),p_idempotency_key)
  returning * into d;
  return jsonb_build_object('id',d.id,'paymentAddress',address,'amountNano',round(d.amount_ton*1000000000)::text,'amountTon',d.amount_ton,'amountFc',d.amount_fc,'paymentComment',d.payment_comment,'expiresAt',d.expires_at);
end$function$;

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
  confirmed_ton numeric;
  before_balance numeric;
  after_balance numeric;
  pool jsonb;
begin
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

  -- The real confirmed on-chain value drives the conversion and must respect the 1 TON floor.
  confirmed_ton := round(p_amount_nano::numeric / 1000000000, 9);
  if confirmed_ton < 1 then
    update public.wallet_deposits set status = 'rejected' where id = d.id;
    raise exception 'MINIMUM_DEPOSIT_1_TON';
  end if;

  if exists (select 1 from public.wallet_deposits where tx_hash = p_tx_hash and id <> d.id)
     or exists (select 1 from public.pet_egg_orders where tx_hash = p_tx_hash)
     or exists (select 1 from public.season_pass_orders where tx_hash = p_tx_hash) then
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

  update public.wallet_deposits
     set status = 'credited',
         tx_hash = p_tx_hash,
         amount_fc = credit,
         conversion_rate = rate,
         confirmed_at = coalesce(confirmed_at, now()),
         credited_at = now()
   where id = d.id;

  perform public.distribute_referral_commission(d.user_id, 'deposit:'||d.id::text, 'deposit', credit, true, 'TON', d.amount_ton);

  pool := public.record_ton_revenue(d.user_id, confirmed_ton, 'deposit', d.id::text, p_tx_hash);

  return jsonb_build_object('status','credited','depositId',d.id,'amountTon',confirmed_ton,'amountFc',credit,'conversionRate',rate,'balanceBefore',before_balance,'balanceAfter',after_balance,'poolContribution',pool);
end
$function$;