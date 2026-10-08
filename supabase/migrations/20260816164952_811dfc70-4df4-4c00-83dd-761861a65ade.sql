CREATE OR REPLACE FUNCTION public.create_wallet_deposit(p_telegram_id bigint, p_amount_ton numeric, p_from_wallet text, p_idempotency_key text, p_deposit_type text DEFAULT 'ton_to_fc'::text)
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

  -- Only ONE deposit intent can be open per player. Older unpaid intents are expired here so a
  -- comment-less transfer can never be matched against a stale intent of the other type
  -- (that was crediting FC for payments the player made to the internal TON balance).
  update wallet_deposits
     set status = 'expired'
   where user_id = u
     and tx_hash is null
     and status in ('pending','confirmed');

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

-- Reconciler only considers intents still open OR the newest expired ones; expired intents remain
-- matchable by their exact on-chain comment so a paid-but-superseded intent is never lost.
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
           'commentOnly', (x.status = 'expired'),
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