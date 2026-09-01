-- O valor depositado que serve para atingir o mínimo de depósito fica travado (não sacável).
CREATE OR REPLACE FUNCTION public.player_ton_withdraw_locked(p_user_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT round(GREATEST(0, LEAST(
    GREATEST(public.withdraw_min_deposit_ton(), 0),
    public.player_ton_deposit_total(p_user_id),
    COALESCE((SELECT ton_balance FROM game_players WHERE id = p_user_id), 0)
  )), 6);
$function$;

GRANT EXECUTE ON FUNCTION public.player_ton_withdraw_locked(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_ton_wallet(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE u game_players%rowtype; v_dep numeric; v_req numeric; v_locked numeric;
BEGIN
  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_req := public.withdraw_min_deposit_ton();
  v_dep := public.player_ton_deposit_total(u.id);
  v_locked := public.player_ton_withdraw_locked(u.id);
  RETURN jsonb_build_object(
    'balanceFc', u.forge_coins,
    'availableTon', COALESCE(u.ton_balance,0),
    'lockedTon', v_locked,
    'withdrawableTon', GREATEST(0, round(COALESCE(u.ton_balance,0) - v_locked, 6)),
    'reservedTon', COALESCE(u.ton_reserved,0),
    'feePercent', public.withdraw_fee_percent_for_user(u.id),
    'defaultFeePercent', public.withdraw_fee_percent(),
    'mythStaked', public.myth_staked_amount(u.id),
    'mythFeeThreshold', public.myth_staking_fee_threshold(),
    'mythFeePercent', public.myth_staking_fee_percent(),
    'minWithdrawTon', public.min_withdraw_ton(),
    'depositRequirementTon', v_req,
    'depositTotalTon', v_dep,
    'depositRequirementMet', (v_req <= 0 OR v_dep >= v_req),
    'rewards', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'amountTon', amount_ton, 'direction', direction,
        'sourceType', source_type, 'sourceId', source_id, 'status', status,
        'note', note, 'createdAt', created_at) ORDER BY created_at DESC), '[]')
      FROM (SELECT * FROM ton_reward_ledger WHERE user_id = u.id ORDER BY created_at DESC LIMIT 40) l),
    'withdrawals', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'grossTon', COALESCE(gross_ton, amount_ton), 'feePercent', COALESCE(fee_percent,0),
        'feeTon', COALESCE(fee_ton,0), 'netTon', COALESCE(net_ton, amount_ton),
        'status', status, 'source', source, 'createdAt', created_at) ORDER BY created_at DESC), '[]')
      FROM (SELECT * FROM wallet_withdrawals WHERE user_id = u.id ORDER BY created_at DESC LIMIT 30) w)
  );
END $function$;
