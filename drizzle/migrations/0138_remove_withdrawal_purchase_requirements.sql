CREATE OR REPLACE FUNCTION public.withdraw_requires_v2_pass(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT false; $$;

CREATE OR REPLACE FUNCTION public.withdraw_min_deposit_ton()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT 0::numeric; $$;

COMMENT ON FUNCTION public.withdraw_requires_v2_pass(uuid) IS 'Compatibility helper: withdrawals do not require any season pass purchase.';
COMMENT ON FUNCTION public.withdraw_min_deposit_ton() IS 'Compatibility helper: withdrawals do not require prior deposits; legacy wallet setting is ignored.';

CREATE OR REPLACE FUNCTION public.get_ton_wallet(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u game_players%rowtype; v_dep numeric; v_req numeric; v_locked numeric; v_pass boolean;
BEGIN
  SELECT * INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_req := public.withdraw_min_deposit_ton();
  v_dep := public.player_ton_deposit_total(u.id);
  v_locked := public.player_ton_withdraw_locked(u.id);
  v_pass := NOT public.withdraw_requires_v2_pass(u.id);
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
    'passRequirementMet', v_pass,
    'passRequirementTon', 0,
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
END
$function$;

REVOKE ALL ON FUNCTION public.withdraw_requires_v2_pass(uuid), public.withdraw_min_deposit_ton(), public.get_ton_wallet(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_requires_v2_pass(uuid), public.withdraw_min_deposit_ton(), public.get_ton_wallet(bigint) TO service_role;