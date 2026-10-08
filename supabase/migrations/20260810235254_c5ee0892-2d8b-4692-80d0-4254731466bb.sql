ALTER TABLE public.wallet_withdrawals
  ADD COLUMN IF NOT EXISTS gross_ton numeric,
  ADD COLUMN IF NOT EXISTS fee_percent numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fee_ton numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS net_ton numeric;

UPDATE public.wallet_withdrawals
   SET gross_ton = COALESCE(gross_ton, amount_ton),
       net_ton = COALESCE(net_ton, amount_ton - COALESCE(fee_ton, 0))
 WHERE gross_ton IS NULL OR net_ton IS NULL;

INSERT INTO public.game_settings(key, value)
VALUES ('wallet_withdraw_fee_percent', '10'::jsonb)
ON CONFLICT (key) DO NOTHING;

UPDATE public.game_settings SET value = '10'::jsonb WHERE key = 'wallet_fee_percent' AND (value #>> '{}')::numeric = 0;

CREATE OR REPLACE FUNCTION public.withdraw_fee_percent()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT GREATEST(0, LEAST(50, COALESCE(
    (SELECT NULLIF(value #>> '{}','')::numeric FROM game_settings WHERE key = 'wallet_withdraw_fee_percent'),
    (SELECT NULLIF(value #>> '{}','')::numeric FROM game_settings WHERE key = 'wallet_fee_percent'),
    10)))
$$;

CREATE OR REPLACE FUNCTION public.request_wallet_withdrawal(p_telegram_id bigint, p_amount_fc numeric, p_wallet_address text, p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE u game_players%rowtype; rate numeric; w wallet_withdrawals%rowtype;
        addr text := NULLIF(TRIM(COALESCE(p_wallet_address,'')),'');
        v_fee_percent numeric; v_gross numeric; v_fee numeric; v_net numeric;
BEGIN
  IF p_amount_fc < 100000 THEN RAISE EXCEPTION 'WITHDRAWAL_MINIMUM_100000'; END IF;
  IF mod(p_amount_fc, 100000) <> 0 THEN RAISE EXCEPTION 'WITHDRAWAL_MULTIPLE_100000'; END IF;
  IF addr IS NULL THEN RAISE EXCEPTION 'WALLET_REQUIRED'; END IF;
  IF NOT public.is_valid_ton_address(addr) THEN RAISE EXCEPTION 'WALLET_INVALID'; END IF;

  SELECT * INTO w FROM wallet_withdrawals WHERE idempotency_key = p_idempotency_key;
  IF w.id IS NOT NULL THEN
    RETURN jsonb_build_object('id', w.id, 'status', w.status, 'amountFc', w.amount_fc,
      'amountTon', w.amount_ton, 'grossTon', w.gross_ton, 'feePercent', w.fee_percent,
      'feeTon', w.fee_ton, 'netTon', w.net_ton, 'walletAddress', w.wallet_address);
  END IF;

  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF u.forge_coins < p_amount_fc THEN RAISE EXCEPTION 'INSUFFICIENT_FC_BALANCE'; END IF;
  SELECT value_numeric INTO rate FROM economy_settings WHERE key = 'fc_per_ton';
  rate := COALESCE(NULLIF(rate, 0), 100000);

  v_fee_percent := public.withdraw_fee_percent();
  v_gross := round(p_amount_fc / rate, 6);
  v_fee   := round(v_gross * v_fee_percent / 100, 6);
  v_net   := round(v_gross - v_fee, 6);

  UPDATE game_players SET forge_coins = forge_coins - p_amount_fc, updated_at = now() WHERE id = u.id;
  INSERT INTO wallet_withdrawals(user_id, telegram_id, username, amount_fc, amount_ton,
    gross_ton, fee_percent, fee_ton, net_ton, wallet_address, idempotency_key)
  VALUES (u.id, u.telegram_id, COALESCE(u.username, u.display_name), p_amount_fc, v_gross,
    v_gross, v_fee_percent, v_fee, v_net, addr, p_idempotency_key)
  RETURNING * INTO w;

  INSERT INTO pool_wallets(user_id, wallet_address, updated_at) VALUES (u.id, addr, now())
  ON CONFLICT (user_id) DO UPDATE SET wallet_address = EXCLUDED.wallet_address, updated_at = now();

  PERFORM public.admin_log(0::bigint, 'WITHDRAWAL_REQUESTED', 'withdrawal', w.id::text, NULL,
    jsonb_build_object('user_id', u.id, 'telegram_id', u.telegram_id, 'wallet_address', addr,
      'amount_fc', w.amount_fc, 'gross_ton', v_gross, 'fee_percent', v_fee_percent,
      'fee_ton', v_fee, 'net_ton', v_net), 'solicitado pelo jogador',
    jsonb_build_object('financial', true));

  RETURN jsonb_build_object('id', w.id, 'status', w.status, 'amountFc', w.amount_fc,
    'amountTon', w.amount_ton, 'grossTon', v_gross, 'feePercent', v_fee_percent,
    'feeTon', v_fee, 'netTon', v_net, 'walletAddress', w.wallet_address);
END $function$;

CREATE OR REPLACE FUNCTION public.get_wallet_summary(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  'deposits',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'amountTon',amount_ton,'amountFc',amount_fc,'status',status,'createdAt',created_at)order by created_at desc),'[]')from(select*from wallet_deposits where user_id=u.id order by created_at desc limit 30)x),
  'withdrawals',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'amountFc',amount_fc,'amountTon',amount_ton,'grossTon',coalesce(gross_ton,amount_ton),'feePercent',coalesce(fee_percent,0),'feeTon',coalesce(fee_ton,0),'netTon',coalesce(net_ton,amount_ton),'status',status,'createdAt',created_at)order by created_at desc),'[]')from(select*from wallet_withdrawals where user_id=u.id order by created_at desc limit 30)x),
  'eggOrders',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'eggName',e.name,'priceTon',o.price_ton,'status',o.status,'createdAt',o.created_at)order by o.created_at desc),'[]')from(select*from pet_egg_orders where user_id=u.id order by created_at desc limit 30)o join pet_eggs e on e.id=o.egg_id),
  'history',(select coalesce(jsonb_agg(z order by created_at desc),'[]')from(
   select jsonb_build_object('id',id,'type','deposit','label','Deposito de '||amount_ton||' TON','amountFc',amount_fc,'amountTon',amount_ton,'status',status,'createdAt',created_at)z,created_at from wallet_deposits where user_id=u.id
   union all select jsonb_build_object('id',id,'type','withdrawal','label','Saque de '||amount_fc||' FC','amountFc',amount_fc,'amountTon',amount_ton,'grossTon',coalesce(gross_ton,amount_ton),'feePercent',coalesce(fee_percent,0),'feeTon',coalesce(fee_ton,0),'netTon',coalesce(net_ton,amount_ton),'status',status,'createdAt',created_at),created_at from wallet_withdrawals where user_id=u.id
   union all select jsonb_build_object('id',o.id,'type','egg_order','label',e.name,'amountFc',null,'amountTon',o.price_ton,'status',o.status,'createdAt',o.created_at),o.created_at from pet_egg_orders o join pet_eggs e on e.id=o.egg_id where o.user_id=u.id
   order by created_at desc limit 50)h));
end$function$;

CREATE OR REPLACE FUNCTION public.admin_withdrawal_detail(p_admin_id bigint, p_withdrawal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
    'id', w.id, 'shortId', left(w.id::text, 8), 'userId', w.user_id,
    'telegramId', COALESCE(w.telegram_id, g.telegram_id),
    'username', COALESCE(w.username, g.username, g.display_name),
    'walletAddress', NULLIF(TRIM(COALESCE(w.wallet_address,'')),''),
    'walletResolutionRequired', w.wallet_resolution_required,
    'currentWallet', pw.wallet_address,
    'amountFc', w.amount_fc, 'amountTon', w.amount_ton,
    'grossTon', COALESCE(w.gross_ton, w.amount_ton),
    'feePercent', COALESCE(w.fee_percent, 0),
    'feeTon', COALESCE(w.fee_ton, 0),
    'netTon', COALESCE(w.net_ton, w.amount_ton),
    'status', w.status,
    'txHash', w.tx_hash, 'createdAt', w.created_at, 'paidAt', COALESCE(w.paid_at, w.processed_at),
    'refundedAt', w.refunded_at, 'adminId', w.admin_id)
  INTO v
  FROM wallet_withdrawals w
  LEFT JOIN game_players g ON g.id = w.user_id
  LEFT JOIN pool_wallets pw ON pw.user_id = w.user_id
  WHERE w.id = p_withdrawal_id;
  IF v IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  RETURN v;
END $function$;

CREATE OR REPLACE FUNCTION public.admin_list_withdrawals(p_admin_id bigint, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 12)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v FROM (
    SELECT w.id, left(w.id::text, 8) AS short_id, w.amount_fc, w.amount_ton,
           COALESCE(w.gross_ton, w.amount_ton) AS gross_ton,
           COALESCE(w.fee_percent, 0) AS fee_percent,
           COALESCE(w.fee_ton, 0) AS fee_ton,
           COALESCE(w.net_ton, w.amount_ton) AS net_ton,
           w.status, w.tx_hash,
           NULLIF(TRIM(COALESCE(w.wallet_address,'')),'') AS wallet_address,
           w.wallet_resolution_required, w.created_at,
           COALESCE(w.telegram_id, g.telegram_id) AS telegram_id,
           COALESCE(w.username, g.username, g.display_name, g.telegram_id::text) AS player
    FROM wallet_withdrawals w LEFT JOIN game_players g ON g.id = w.user_id
    WHERE p_status IS NULL OR w.status = p_status
    ORDER BY w.created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 50))) t;
  RETURN jsonb_build_object('items', v, 'feePercent', public.withdraw_fee_percent());
END $function$;

CREATE OR REPLACE FUNCTION public.admin_payout_announcement_claim(p_admin_id bigint, p_withdrawal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE w wallet_withdrawals%rowtype; a payout_announcements%rowtype; g game_players%rowtype;
        v_chat text; v_news text; v_app text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('payout:' || p_withdrawal_id::text, 77));
  SELECT * INTO w FROM wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF w.id IS NULL THEN RAISE EXCEPTION 'withdrawal_not_found'; END IF;
  IF w.status NOT IN ('paid','completed') THEN RETURN jsonb_build_object('skip', 'not_completed', 'status', w.status); END IF;
  IF NULLIF(TRIM(COALESCE(w.tx_hash,'')),'') IS NULL THEN RETURN jsonb_build_object('skip', 'tx_hash_missing'); END IF;

  SELECT * INTO a FROM payout_announcements WHERE withdrawal_id = w.id FOR UPDATE;
  IF a.withdrawal_id IS NOT NULL AND a.status = 'sent' THEN
    RETURN jsonb_build_object('skip', 'already_sent', 'messageId', a.message_id, 'channelId', a.channel_id);
  END IF;

  INSERT INTO payout_announcements(withdrawal_id, tx_hash, status, attempts)
  VALUES (w.id, w.tx_hash, 'sending', 1)
  ON CONFLICT (withdrawal_id) DO UPDATE
     SET status = 'sending', attempts = payout_announcements.attempts + 1,
         tx_hash = EXCLUDED.tx_hash, updated_at = now();

  SELECT * INTO g FROM game_players WHERE id = w.user_id;
  SELECT value #>> '{}' INTO v_chat FROM game_settings WHERE key = 'payments_channel_chat_id';
  SELECT value #>> '{}' INTO v_app FROM game_settings WHERE key = 'telegram_app_link';
  SELECT url INTO v_news FROM channel_reward_config WHERE channel_key = 'news';

  RETURN jsonb_build_object(
    'withdrawalId', w.id,
    'amountFc', w.amount_fc,
    'amountTon', w.amount_ton,
    'grossTon', COALESCE(w.gross_ton, w.amount_ton),
    'feePercent', COALESCE(w.fee_percent, 0),
    'feeTon', COALESCE(w.fee_ton, 0),
    'netTon', COALESCE(w.net_ton, w.amount_ton),
    'txHash', w.tx_hash,
    'paidAt', COALESCE(w.paid_at, w.processed_at, now()),
    'telegramId', COALESCE(w.telegram_id, g.telegram_id),
    'username', COALESCE(NULLIF(w.username,''), g.username),
    'channelId', v_chat,
    'appLink', v_app,
    'newsUrl', v_news,
    'enabled', COALESCE((SELECT (value)::text = 'true' FROM game_settings WHERE key = 'payments_channel_enabled'), true)
  );
END $function$;

CREATE OR REPLACE FUNCTION public.admin_set_withdraw_fee_percent(p_admin_id bigint, p_percent numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_old numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_percent IS NULL OR p_percent < 0 OR p_percent > 50 THEN RAISE EXCEPTION 'fee_out_of_range'; END IF;
  v_old := public.withdraw_fee_percent();
  INSERT INTO game_settings(key, value) VALUES ('wallet_withdraw_fee_percent', to_jsonb(p_percent))
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  UPDATE game_settings SET value = to_jsonb(p_percent) WHERE key = 'wallet_fee_percent';
  PERFORM public.admin_log(p_admin_id, 'WITHDRAW_FEE_UPDATED', 'settings', 'wallet_withdraw_fee_percent',
    jsonb_build_object('percent', v_old), jsonb_build_object('percent', p_percent),
    'taxa de saque atualizada', jsonb_build_object('financial', true));
  RETURN jsonb_build_object('feePercent', public.withdraw_fee_percent());
END $function$;