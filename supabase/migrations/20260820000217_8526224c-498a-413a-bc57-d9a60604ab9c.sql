create or replace function public.myth_sale_stats()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
DECLARE cfg public.myth_sale_config; tok public.myth_token_settings;
  v_sold numeric; v_burned numeric; v_supply_burn numeric; v_utility_burn numeric;
  v_reserved numeric; v_raised numeric; v_avail numeric; v_last timestamptz;
BEGIN
  PERFORM public.myth_expire_payment_intents();
  SELECT * INTO cfg FROM public.myth_sale_config WHERE id;
  SELECT * INTO tok FROM public.myth_token_settings WHERE id;
  SELECT COALESCE(SUM(myth_amount),0), COALESCE(SUM(amount_ton),0), MAX(created_at)
    INTO v_sold, v_raised, v_last FROM public.myth_sale_transactions WHERE status = 'CONFIRMED';
  SELECT COALESCE(SUM(amount) FILTER (WHERE burn_kind = 'SUPPLY'), 0),
         COALESCE(SUM(amount) FILTER (WHERE burn_kind = 'UTILITY'), 0)
    INTO v_supply_burn, v_utility_burn FROM public.myth_burn_history;
  v_burned := v_supply_burn + v_utility_burn;
  SELECT COALESCE(SUM(myth_amount),0) INTO v_reserved FROM public.myth_payment_intents
   WHERE status = 'pending' AND expires_at > now();
  -- Utility burns destroy tokens already sold: they must NOT reduce the sale stock again.
  v_avail := GREATEST(0, cfg.sale_allocation - v_sold - v_supply_burn - v_reserved);
  RETURN jsonb_build_object(
    'symbol', tok.token_symbol, 'name', tok.token_name,
    'saleStatus', cfg.sale_status,
    'mythPerTon', cfg.myth_per_ton,
    'minPurchase', cfg.min_purchase_myth,
    'intentMinutes', cfg.intent_minutes,
    'initialSupply', tok.total_supply,
    'originalSupply', tok.total_supply,
    'saleAllocation', cfg.sale_allocation,
    'effectiveSupply', GREATEST(0, tok.total_supply - v_burned),
    'sold', round(v_sold, 4),
    'totalSoldCumulative', round(v_sold, 4),
    'burned', round(v_burned, 4),
    'totalBurnedCumulative', round(v_burned, 4),
    'supplyBurned', round(v_supply_burn, 4),
    'utilityBurned', round(v_utility_burn, 4),
    'reserved', round(v_reserved, 4),
    'reservedSaleSupply', round(v_reserved, 4),
    'available', round(v_avail, 4),
    'saleAvailable', round(v_avail, 4),
    'tonRaised', round(v_raised, 9),
    'burnedPercent', CASE WHEN tok.total_supply > 0 THEN round(v_burned / tok.total_supply * 100, 4) ELSE 0 END,
    'soldPercent', CASE WHEN cfg.sale_allocation > 0 THEN round(v_sold / cfg.sale_allocation * 100, 4) ELSE 0 END,
    'lastSaleAt', v_last,
    'serverTime', now()
  );
END $$;

create or replace function public.get_myth_utility_state(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_user uuid; v_balance numeric := 0; v_staked numeric := 0; v_spent numeric := 0; s jsonb;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is not null then
    select coalesce(amount, 0) into v_balance from public.myth_balances where user_id = v_user;
    v_staked := public.myth_staked_amount(v_user);
    select coalesce(sum(amount_myth), 0) into v_spent from public.myth_utility_burns where user_id = v_user;
  end if;
  s := public.myth_sale_stats();
  return public.myth_utility_config() || jsonb_build_object(
    'balance', round(coalesce(v_balance, 0), 4),
    'available', round(coalesce(v_balance, 0), 4),
    'staked', round(coalesce(v_staked, 0), 4),
    'totalOwned', round(coalesce(v_balance, 0) + coalesce(v_staked, 0), 4),
    'mySpentMyth', round(v_spent, 4),
    'burned', s->'burned',
    'utilityBurned', s->'utilityBurned',
    'effectiveSupply', s->'effectiveSupply',
    'originalSupply', s->'originalSupply',
    'burnedPercent', s->'burnedPercent'
  );
end $$;

revoke execute on function public.get_myth_utility_state(bigint) from public, anon, authenticated;
grant execute on function public.get_myth_utility_state(bigint) to service_role;