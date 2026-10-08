-- 1) Nova coluna: parte do rendimento perdida no resgate antecipado
ALTER TABLE public.ton_staking_settings
  ADD COLUMN IF NOT EXISTS early_unstake_reward_forfeit_percent numeric(9,4) NOT NULL DEFAULT 100.0000;

-- 2) Parâmetros econômicos conservadores
UPDATE public.ton_staking_settings SET
  enabled = true,
  paused = false,
  early_unstake_allowed = true,
  early_unstake_penalty_percent = 15.0000,
  early_unstake_reward_forfeit_percent = 100.0000,
  accrue_after_maturity = false,
  auto_compound_allowed = true,
  min_stake_ton = 1.000000000,
  max_stake_ton = 500.000000000,
  auto_stake_min_ton = 1.000000000,
  pool_gate_enabled = true,
  reward_pool_total = 500.000000000,
  reward_pool_min_available = 0.000000000,
  month_days = 30,
  updated_at = now()
WHERE id;

-- 3) Planos: taxa base 1%/mês, bônus por lock (efetivo 1.00 a 2.50%/mês),
--    resgate antecipado permitido apenas nos planos curtos/médios.
UPDATE public.ton_staking_plans SET monthly_rate = 1.0000, min_stake_ton = 1.000000000, max_stake_ton = 500.000000000, updated_at = now();
UPDATE public.ton_staking_plans SET bonus_rate = 0.0000,  early_unstake_allowed = true  WHERE code = 'd30';
UPDATE public.ton_staking_plans SET bonus_rate = 0.2500,  early_unstake_allowed = true  WHERE code = 'd60';
UPDATE public.ton_staking_plans SET bonus_rate = 0.5000,  early_unstake_allowed = true  WHERE code = 'd90';
UPDATE public.ton_staking_plans SET bonus_rate = 1.0000,  early_unstake_allowed = true  WHERE code = 'd180';
UPDATE public.ton_staking_plans SET bonus_rate = 1.5000,  early_unstake_allowed = false WHERE code = 'd365';

-- 4) Resgate antecipado: penalidade no principal + perda (parcial/total) do rendimento
CREATE OR REPLACE FUNCTION public.ton_staking_unstake(p_telegram_id bigint, p_position_id uuid, p_request_id text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE u uuid; s public.ton_staking_settings; pl public.ton_staking_plans; p public.ton_staking_positions;
        v_key text; v_cached jsonb; v_reward numeric; v_forfeit numeric := 0; v_principal numeric; v_penalty numeric := 0; v_early boolean;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_key := 'unstake:' || u::text || ':' || coalesce(p_request_id, p_position_id::text);
  SELECT result INTO v_cached FROM public.ton_staking_idempotency WHERE key = v_key;
  IF v_cached IS NOT NULL THEN RETURN v_cached; END IF;

  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  IF NOT coalesce(s.enabled, true) THEN RAISE EXCEPTION 'STAKING_DISABLED'; END IF;
  PERFORM public.ton_staking_accrue(p_position_id);

  SELECT * INTO p FROM public.ton_staking_positions WHERE id = p_position_id AND user_id = u FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'POSITION_NOT_FOUND'; END IF;
  IF p.status = 'WITHDRAWN' THEN RAISE EXCEPTION 'ALREADY_WITHDRAWN'; END IF;
  SELECT * INTO pl FROM public.ton_staking_plans WHERE id = p.plan_id;

  v_reward := p.accrued_reward_ton;
  v_early := now() < p.unlock_at;
  IF v_early THEN
    IF NOT (coalesce(s.early_unstake_allowed, false) AND coalesce(pl.early_unstake_allowed, false)) THEN
      RAISE EXCEPTION 'LOCK_ACTIVE';
    END IF;
    v_penalty := round(p.principal_ton * coalesce(s.early_unstake_penalty_percent, 0) / 100.0, 9);
    v_forfeit := round(v_reward * least(100, greatest(0, coalesce(s.early_unstake_reward_forfeit_percent, 0))) / 100.0, 9);
    v_reward := round(v_reward - v_forfeit, 9);
  END IF;

  v_principal := round(p.principal_ton - v_penalty, 9);

  UPDATE public.ton_staking_positions
     SET status = 'WITHDRAWN', withdrawn_at = now(), accrued_reward_ton = 0,
         claimed_reward_ton = round(claimed_reward_ton + v_reward, 9), updated_at = now()
   WHERE id = p.id;

  IF v_reward > 0 THEN
    UPDATE public.ton_staking_settings SET reward_pool_paid = round(reward_pool_paid + v_reward, 9), updated_at = now() WHERE id;
  END IF;
  IF v_penalty > 0 THEN
    INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source)
    VALUES (u, p.id, 'PENALTY', v_penalty, 'early_unstake');
  END IF;
  IF v_forfeit > 0 THEN
    INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source, note)
    VALUES (u, p.id, 'PENALTY', v_forfeit, 'early_unstake', 'reward_forfeit');
  END IF;
  INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source, request_id, note)
  VALUES (u, p.id, 'UNSTAKE', round(v_principal + v_reward, 9), CASE WHEN v_early THEN 'early' ELSE 'matured' END, p_request_id, pl.code);

  PERFORM public.credit_ton_reward(u, round(v_principal + v_reward, 9), 'ton_staking_unstake', v_key);

  v_cached := public.ton_staking_state(p_telegram_id)
    || jsonb_build_object('returnedTon', round(v_principal + v_reward, 9), 'penaltyTon', round(v_penalty + v_forfeit, 9),
                          'principalPenaltyTon', v_penalty, 'rewardForfeitTon', v_forfeit, 'rewardTon', v_reward);
  INSERT INTO public.ton_staking_idempotency (key, user_id, result) VALUES (v_key, u, v_cached) ON CONFLICT (key) DO NOTHING;
  RETURN v_cached;
END $function$;