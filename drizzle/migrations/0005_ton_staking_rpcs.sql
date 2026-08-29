CREATE OR REPLACE FUNCTION public.ton_staking_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; s public.ton_staking_settings; v_balance numeric; pr public.ton_staking_preferences;
        v_plans jsonb; v_positions jsonb; v_ledger jsonb;
        v_staked numeric := 0; v_unclaimed numeric := 0; v_earned numeric := 0;
        v_monthly numeric := 0; v_active int := 0; v_next timestamptz; v_pool numeric;
BEGIN
  SELECT id, coalesce(ton_balance, 0) INTO u, v_balance FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  PERFORM public.ton_staking_accrue_user(u);
  PERFORM public.ton_staking_flush_pending(u);

  SELECT * INTO pr FROM public.ton_staking_preferences WHERE user_id = u;

  SELECT coalesce(sum(principal_ton), 0), coalesce(sum(accrued_reward_ton), 0),
         coalesce(sum(total_earned_ton), 0), count(*)::int,
         coalesce(sum(principal_ton * ((rate_snapshot + bonus_snapshot) / 100.0)), 0),
         min(unlock_at) FILTER (WHERE status = 'ACTIVE')
    INTO v_staked, v_unclaimed, v_earned, v_active, v_monthly, v_next
    FROM public.ton_staking_positions WHERE user_id = u AND status <> 'WITHDRAWN';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pl.id, 'code', pl.code, 'name', pl.name, 'lockDays', pl.lock_days,
      'monthlyRate', pl.monthly_rate, 'bonusRate', pl.bonus_rate,
      'effectiveMonthlyRate', pl.monthly_rate + pl.bonus_rate,
      'minStakeTon', CASE WHEN pl.min_stake_ton > 0 THEN pl.min_stake_ton ELSE s.min_stake_ton END,
      'maxStakeTon', CASE WHEN pl.max_stake_ton > 0 THEN pl.max_stake_ton ELSE s.max_stake_ton END,
      'rewardClaimMode', pl.reward_claim_mode,
      'autoCompoundAllowed', pl.auto_compound_allowed AND s.auto_compound_allowed,
      'earlyUnstakeAllowed', pl.early_unstake_allowed AND s.early_unstake_allowed
    ) ORDER BY pl.sort_order, pl.lock_days), '[]'::jsonb)
    INTO v_plans FROM public.ton_staking_plans pl WHERE pl.enabled;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'planId', p.plan_id, 'planName', pl.name, 'planCode', pl.code,
      'principalTon', round(p.principal_ton, 9),
      'initialPrincipalTon', round(p.initial_principal_ton, 9),
      'monthlyRate', p.rate_snapshot, 'bonusRate', p.bonus_snapshot,
      'effectiveMonthlyRate', p.rate_snapshot + p.bonus_snapshot,
      'lockDays', p.lock_days_snapshot,
      'startedAt', p.started_at, 'unlockAt', p.unlock_at,
      'accruedTon', round(p.accrued_reward_ton, 9),
      'claimedTon', round(p.claimed_reward_ton, 9),
      'compoundedTon', round(p.compounded_ton, 9),
      'earnedTon', round(p.total_earned_ton, 9),
      'status', p.status, 'autoCompound', p.auto_compound, 'source', p.source,
      'claimMode', p.claim_mode_snapshot,
      'canClaim', p.claim_mode_snapshot = 'anytime' OR now() >= p.unlock_at,
      'monthlyEstimateTon', round(p.principal_ton * ((p.rate_snapshot + p.bonus_snapshot) / 100.0), 9),
      'progressPercent', least(100, round(100 * extract(epoch FROM (now() - p.started_at))
          / greatest(1, extract(epoch FROM (p.unlock_at - p.started_at))), 2))
    ) ORDER BY p.status, p.unlock_at), '[]'::jsonb)
    INTO v_positions
    FROM public.ton_staking_positions p JOIN public.ton_staking_plans pl ON pl.id = p.plan_id
   WHERE p.user_id = u AND p.status <> 'WITHDRAWN';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'type', l.entry_type, 'amountTon', round(l.amount_ton, 9), 'createdAt', l.created_at
    ) ORDER BY l.created_at DESC), '[]'::jsonb)
    INTO v_ledger FROM (
      SELECT * FROM public.ton_staking_ledger WHERE user_id = u
        AND entry_type IN ('STAKE','CLAIM','UNSTAKE','AUTO_STAKE_FLUSH','AUTO_STAKE_MINE')
      ORDER BY created_at DESC LIMIT 8
    ) l;

  v_pool := public.ton_staking_pool_available();
  RETURN jsonb_build_object(
    'enabled', s.enabled,
    'newStakesOpen', s.enabled AND NOT s.paused
      AND (NOT coalesce(s.pool_gate_enabled, false) OR v_pool > s.reward_pool_min_available),
    'paused', s.paused,
    'balanceTon', round(v_balance, 9),
    'minStakeTon', s.min_stake_ton,
    'maxStakeTon', s.max_stake_ton,
    'monthDays', s.month_days,
    'autoCompoundAllowed', s.auto_compound_allowed,
    'earlyUnstakeAllowed', s.early_unstake_allowed,
    'earlyUnstakePenaltyPercent', s.early_unstake_penalty_percent,
    'autoStakeMinTon', s.auto_stake_min_ton,
    'allowedPercents', to_jsonb(s.allowed_percents),
    'plans', v_plans,
    'positions', v_positions,
    'ledger', v_ledger,
    'preferences', jsonb_build_object(
      'mineAutoStakeEnabled', coalesce(pr.mine_auto_stake_enabled, false),
      'mineAutoStakePercent', coalesce(pr.mine_auto_stake_percent, 0),
      'autoStakePlanId', pr.auto_stake_plan_id,
      'autoCompound', coalesce(pr.auto_compound, false),
      'pendingAutoStakeTon', round(coalesce(pr.pending_auto_stake_ton, 0), 9)
    ),
    'summary', jsonb_build_object(
      'totalStakedTon', round(v_staked, 9),
      'monthlyEstimateTon', round(v_monthly, 9),
      'unclaimedTon', round(v_unclaimed, 9),
      'totalEarnedTon', round(v_earned, 9),
      'activePositions', v_active,
      'nextMaturityAt', v_next,
      'nextMaturityDays', CASE WHEN v_next IS NULL THEN NULL
        ELSE greatest(0, ceil(extract(epoch FROM (v_next - now())) / 86400.0)) END
    )
  );
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_set_preferences(
  p_telegram_id bigint, p_enabled boolean, p_percent integer, p_plan_id uuid, p_auto_compound boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; s public.ton_staking_settings; v_percent integer;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  v_percent := coalesce(p_percent, 0);
  IF coalesce(p_enabled, false) AND NOT (v_percent = ANY (s.allowed_percents)) THEN
    RAISE EXCEPTION 'INVALID_PERCENT';
  END IF;
  IF NOT coalesce(p_enabled, false) THEN v_percent := 0; END IF;
  IF p_plan_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ton_staking_plans WHERE id = p_plan_id AND enabled) THEN
    RAISE EXCEPTION 'PLAN_NOT_FOUND';
  END IF;

  INSERT INTO public.ton_staking_preferences (user_id, mine_auto_stake_enabled, mine_auto_stake_percent, auto_stake_plan_id, auto_compound)
  VALUES (u, coalesce(p_enabled, false), v_percent, p_plan_id,
          coalesce(p_auto_compound, false) AND s.auto_compound_allowed)
  ON CONFLICT (user_id) DO UPDATE
     SET mine_auto_stake_enabled = excluded.mine_auto_stake_enabled,
         mine_auto_stake_percent = excluded.mine_auto_stake_percent,
         auto_stake_plan_id = coalesce(excluded.auto_stake_plan_id, public.ton_staking_preferences.auto_stake_plan_id),
         auto_compound = excluded.auto_compound,
         updated_at = now();

  PERFORM public.ton_staking_flush_pending(u);
  RETURN public.ton_staking_state(p_telegram_id);
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_set_position_compound(
  p_telegram_id bigint, p_position_id uuid, p_auto_compound boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; s public.ton_staking_settings; p public.ton_staking_positions;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  IF coalesce(p_auto_compound, false) AND NOT s.auto_compound_allowed THEN RAISE EXCEPTION 'COMPOUND_DISABLED'; END IF;
  PERFORM public.ton_staking_accrue(p_position_id);
  SELECT * INTO p FROM public.ton_staking_positions WHERE id = p_position_id AND user_id = u FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'POSITION_NOT_FOUND'; END IF;
  IF p.status = 'WITHDRAWN' THEN RAISE EXCEPTION 'POSITION_CLOSED'; END IF;
  UPDATE public.ton_staking_positions SET auto_compound = coalesce(p_auto_compound, false), updated_at = now()
   WHERE id = p.id;
  RETURN public.ton_staking_state(p_telegram_id);
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_stake(
  p_telegram_id bigint, p_plan_id uuid, p_amount numeric, p_auto_compound boolean DEFAULT false,
  p_request_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; s public.ton_staking_settings; pl public.ton_staking_plans;
        v_amount numeric; v_min numeric; v_max numeric; v_key text; v_cached jsonb;
        v_pos uuid; v_liability numeric; v_extra numeric; v_compound boolean;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  v_key := 'stake:' || u::text || ':' || coalesce(p_request_id, '');
  IF p_request_id IS NOT NULL THEN
    SELECT result INTO v_cached FROM public.ton_staking_idempotency WHERE key = v_key;
    IF v_cached IS NOT NULL THEN RETURN v_cached; END IF;
  END IF;

  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  IF NOT coalesce(s.enabled, true) THEN RAISE EXCEPTION 'STAKING_DISABLED'; END IF;
  IF coalesce(s.paused, false) THEN RAISE EXCEPTION 'STAKING_PAUSED'; END IF;

  SELECT * INTO pl FROM public.ton_staking_plans WHERE id = p_plan_id AND enabled;
  IF pl.id IS NULL THEN RAISE EXCEPTION 'PLAN_NOT_FOUND'; END IF;

  v_amount := round(coalesce(p_amount, 0), 9);
  v_min := CASE WHEN pl.min_stake_ton > 0 THEN pl.min_stake_ton ELSE s.min_stake_ton END;
  v_max := CASE WHEN pl.max_stake_ton > 0 THEN pl.max_stake_ton ELSE s.max_stake_ton END;
  IF v_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF v_amount < v_min THEN RAISE EXCEPTION 'AMOUNT_BELOW_MIN'; END IF;
  IF v_max > 0 AND v_amount > v_max THEN RAISE EXCEPTION 'AMOUNT_ABOVE_MAX'; END IF;

  IF coalesce(s.pool_gate_enabled, false) THEN
    v_liability := public.ton_staking_liability();
    v_extra := round(v_amount * ((pl.monthly_rate + pl.bonus_rate) / 100.0)
      * (pl.lock_days::numeric / greatest(1, s.month_days)::numeric), 9);
    IF (s.reward_pool_total - s.reward_pool_paid) - (v_liability + v_extra) < s.reward_pool_min_available THEN
      RAISE EXCEPTION 'STAKING_POOL_EXHAUSTED';
    END IF;
  END IF;

  PERFORM public.debit_ton_balance(u, v_amount, 'ton_staking_stake', v_key);

  v_compound := coalesce(p_auto_compound, false) AND pl.auto_compound_allowed AND s.auto_compound_allowed;
  INSERT INTO public.ton_staking_positions (
    user_id, plan_id, principal_ton, initial_principal_ton, rate_snapshot, bonus_snapshot,
    lock_days_snapshot, claim_mode_snapshot, unlock_at, auto_compound, source)
  VALUES (u, pl.id, v_amount, v_amount, pl.monthly_rate, pl.bonus_rate, pl.lock_days,
          pl.reward_claim_mode, now() + (pl.lock_days || ' days')::interval, v_compound, 'manual')
  RETURNING id INTO v_pos;

  INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source, request_id, note)
  VALUES (u, v_pos, 'STAKE', v_amount, 'internal_balance', p_request_id, pl.code);

  v_cached := public.ton_staking_state(p_telegram_id) || jsonb_build_object('positionId', v_pos, 'stakedTon', v_amount);
  IF p_request_id IS NOT NULL THEN
    INSERT INTO public.ton_staking_idempotency (key, user_id, result) VALUES (v_key, u, v_cached)
    ON CONFLICT (key) DO NOTHING;
  END IF;
  RETURN v_cached;
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_claim(
  p_telegram_id bigint, p_position_id uuid DEFAULT NULL, p_request_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; s public.ton_staking_settings; r record; v_total numeric := 0;
        v_key text; v_cached jsonb;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_key := 'claim:' || u::text || ':' || coalesce(p_request_id, '');
  IF p_request_id IS NOT NULL THEN
    SELECT result INTO v_cached FROM public.ton_staking_idempotency WHERE key = v_key;
    IF v_cached IS NOT NULL THEN RETURN v_cached; END IF;
  END IF;

  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  IF NOT coalesce(s.enabled, true) THEN RAISE EXCEPTION 'STAKING_DISABLED'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ton_staking_claim:' || u::text, 0));
  PERFORM public.ton_staking_accrue_user(u);

  FOR r IN SELECT * FROM public.ton_staking_positions
            WHERE user_id = u AND status <> 'WITHDRAWN'
              AND (p_position_id IS NULL OR id = p_position_id)
            ORDER BY started_at FOR UPDATE LOOP
    IF r.accrued_reward_ton > 0 AND (r.claim_mode_snapshot = 'anytime' OR now() >= r.unlock_at) THEN
      v_total := round(v_total + r.accrued_reward_ton, 9);
      UPDATE public.ton_staking_positions
         SET accrued_reward_ton = 0,
             claimed_reward_ton = round(claimed_reward_ton + r.accrued_reward_ton, 9),
             updated_at = now()
       WHERE id = r.id;
      INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source)
      VALUES (u, r.id, 'CLAIM', r.accrued_reward_ton, 'staking_reward');
    END IF;
  END LOOP;

  IF v_total <= 0 THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;

  UPDATE public.ton_staking_settings SET reward_pool_paid = round(reward_pool_paid + v_total, 9), updated_at = now() WHERE id;
  PERFORM public.credit_ton_reward(u, v_total, 'ton_staking_reward',
    CASE WHEN p_request_id IS NULL THEN gen_random_uuid()::text ELSE v_key END);

  v_cached := public.ton_staking_state(p_telegram_id) || jsonb_build_object('claimedTon', v_total);
  IF p_request_id IS NOT NULL THEN
    INSERT INTO public.ton_staking_idempotency (key, user_id, result) VALUES (v_key, u, v_cached)
    ON CONFLICT (key) DO NOTHING;
  END IF;
  RETURN v_cached;
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_unstake(
  p_telegram_id bigint, p_position_id uuid, p_request_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; s public.ton_staking_settings; pl public.ton_staking_plans; p public.ton_staking_positions;
        v_key text; v_cached jsonb; v_reward numeric; v_principal numeric; v_penalty numeric := 0; v_early boolean;
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

  v_early := now() < p.unlock_at;
  IF v_early THEN
    IF NOT (coalesce(s.early_unstake_allowed, false) AND coalesce(pl.early_unstake_allowed, false)) THEN
      RAISE EXCEPTION 'LOCK_ACTIVE';
    END IF;
    v_penalty := round(p.principal_ton * coalesce(s.early_unstake_penalty_percent, 0) / 100.0, 9);
  END IF;

  v_reward := p.accrued_reward_ton;
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
  INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source, request_id, note)
  VALUES (u, p.id, 'UNSTAKE', round(v_principal + v_reward, 9), CASE WHEN v_early THEN 'early' ELSE 'matured' END, p_request_id, pl.code);

  PERFORM public.credit_ton_reward(u, round(v_principal + v_reward, 9), 'ton_staking_unstake', v_key);

  v_cached := public.ton_staking_state(p_telegram_id)
    || jsonb_build_object('returnedTon', round(v_principal + v_reward, 9), 'penaltyTon', v_penalty, 'rewardTon', v_reward);
  INSERT INTO public.ton_staking_idempotency (key, user_id, result) VALUES (v_key, u, v_cached) ON CONFLICT (key) DO NOTHING;
  RETURN v_cached;
END $$;

CREATE OR REPLACE FUNCTION public.ton_mine_claim(p_telegram_id bigint, p_holding_id uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid; h record; v_total numeric := 0; v_amount numeric; cid uuid;
        v_staked numeric; v_auto numeric := 0; v_cash numeric;
        v_type text := CASE WHEN p_holding_id IS NULL THEN 'all' ELSE 'single' END;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ton_mine_claim:'||u::text, 0));

  FOR h IN SELECT id, template_id FROM public.ton_mine_holdings
            WHERE user_id = u AND active AND (p_holding_id IS NULL OR id = p_holding_id) LOOP
    PERFORM public.ton_mine_accrue(h.id);
    SELECT round(stored_ton, 9) INTO v_amount FROM public.ton_mine_holdings WHERE id = h.id FOR UPDATE;
    IF coalesce(v_amount,0) <= 0 THEN CONTINUE; END IF;
    UPDATE public.ton_mine_holdings
       SET stored_ton = 0, total_claimed_ton = round(coalesce(total_claimed_ton,0) + v_amount, 9)
     WHERE id = h.id;
    INSERT INTO public.ton_mine_claims(user_id, holding_id, template_id, amount_ton, claim_type)
    VALUES (u, h.id, h.template_id, v_amount, v_type) RETURNING id INTO cid;

    v_staked := public.ton_staking_route_mine(u, v_amount, cid::text);
    v_auto := round(v_auto + coalesce(v_staked, 0), 9);
    v_cash := round(v_amount - coalesce(v_staked, 0), 9);
    IF v_cash > 0 THEN
      PERFORM public.credit_ton_reward(u, v_cash, 'ton_mine_claim', cid::text, 'MINAS DE TON');
    END IF;
    v_total := round(v_total + v_amount, 9);
  END LOOP;

  IF v_total <= 0 THEN RAISE EXCEPTION 'NOTHING_TO_CLAIM'; END IF;
  RETURN public.ton_mines_state(p_telegram_id) || jsonb_build_object(
    'ok', true, 'claimedTon', v_total, 'claimType', v_type,
    'autoStakedTon', v_auto, 'creditedTon', round(v_total - v_auto, 9));
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_staking_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s public.ton_staking_settings; v_plans jsonb; v_top jsonb;
        v_staked numeric; v_positions int; v_users int; v_outstanding numeric; v_paid numeric; v_monthly numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  SELECT coalesce(sum(principal_ton), 0), count(*)::int, count(DISTINCT user_id)::int,
         coalesce(sum(accrued_reward_ton), 0), coalesce(sum(claimed_reward_ton), 0),
         coalesce(sum(principal_ton * ((rate_snapshot + bonus_snapshot) / 100.0)), 0)
    INTO v_staked, v_positions, v_users, v_outstanding, v_paid, v_monthly
    FROM public.ton_staking_positions WHERE status <> 'WITHDRAWN';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'code', code, 'name', name, 'lockDays', lock_days, 'monthlyRate', monthly_rate,
      'bonusRate', bonus_rate, 'effective', monthly_rate + bonus_rate, 'enabled', enabled,
      'claimMode', reward_claim_mode,
      'staked', (SELECT coalesce(sum(principal_ton), 0) FROM public.ton_staking_positions p
                  WHERE p.plan_id = pl.id AND p.status <> 'WITHDRAWN')
    ) ORDER BY sort_order, lock_days), '[]'::jsonb) INTO v_plans FROM public.ton_staking_plans pl;

  SELECT coalesce(jsonb_agg(x), '[]'::jsonb) INTO v_top FROM (
    SELECT jsonb_build_object('telegramId', g.telegram_id, 'name', g.name,
             'stakedTon', round(sum(p.principal_ton), 4), 'positions', count(*)) AS x
      FROM public.ton_staking_positions p JOIN public.game_players g ON g.id = p.user_id
     WHERE p.status <> 'WITHDRAWN' GROUP BY g.telegram_id, g.name
     ORDER BY sum(p.principal_ton) DESC LIMIT 10) t;

  RETURN jsonb_build_object(
    'enabled', s.enabled, 'paused', s.paused,
    'minStakeTon', s.min_stake_ton, 'maxStakeTon', s.max_stake_ton,
    'autoStakeMinTon', s.auto_stake_min_ton, 'monthDays', s.month_days,
    'autoCompoundAllowed', s.auto_compound_allowed,
    'earlyUnstakeAllowed', s.early_unstake_allowed,
    'earlyUnstakePenaltyPercent', s.early_unstake_penalty_percent,
    'accrueAfterMaturity', s.accrue_after_maturity,
    'poolGateEnabled', s.pool_gate_enabled,
    'rewardPoolTotal', s.reward_pool_total, 'rewardPoolPaid', s.reward_pool_paid,
    'rewardPoolMinAvailable', s.reward_pool_min_available,
    'poolAvailable', public.ton_staking_pool_available(),
    'liability', public.ton_staking_liability(),
    'totalStakedTon', round(v_staked, 4), 'positions', v_positions, 'stakers', v_users,
    'outstandingTon', round(v_outstanding, 4), 'claimedTon', round(v_paid, 4),
    'monthlyPayoutTon', round(v_monthly, 4),
    'plans', v_plans, 'topStakers', v_top);
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_staking_set(p_admin_id bigint, p_field text, p_value numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_value < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
  UPDATE public.ton_staking_settings SET
    min_stake_ton = CASE WHEN p_field = 'min' THEN p_value ELSE min_stake_ton END,
    max_stake_ton = CASE WHEN p_field = 'max' THEN p_value ELSE max_stake_ton END,
    auto_stake_min_ton = CASE WHEN p_field = 'automin' THEN p_value ELSE auto_stake_min_ton END,
    month_days = CASE WHEN p_field = 'monthdays' THEN greatest(1, p_value::int) ELSE month_days END,
    reward_pool_total = CASE WHEN p_field = 'pool' THEN p_value ELSE reward_pool_total END,
    reward_pool_min_available = CASE WHEN p_field = 'poolmin' THEN p_value ELSE reward_pool_min_available END,
    early_unstake_penalty_percent = CASE WHEN p_field = 'penalty' THEN p_value ELSE early_unstake_penalty_percent END,
    updated_at = now()
  WHERE id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_staking_flag(p_admin_id bigint, p_field text, p_value boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.ton_staking_settings SET
    enabled = CASE WHEN p_field = 'enabled' THEN p_value ELSE enabled END,
    paused = CASE WHEN p_field = 'paused' THEN p_value ELSE paused END,
    auto_compound_allowed = CASE WHEN p_field = 'compound' THEN p_value ELSE auto_compound_allowed END,
    early_unstake_allowed = CASE WHEN p_field = 'early' THEN p_value ELSE early_unstake_allowed END,
    accrue_after_maturity = CASE WHEN p_field = 'aftermaturity' THEN p_value ELSE accrue_after_maturity END,
    pool_gate_enabled = CASE WHEN p_field = 'poolgate' THEN p_value ELSE pool_gate_enabled END,
    updated_at = now()
  WHERE id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_ton_staking_plan_set(
  p_admin_id bigint, p_code text, p_field text, p_value text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_num numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_field IN ('rate', 'bonus', 'lock', 'min', 'max', 'sort') THEN
    v_num := replace(trim(p_value), ',', '.')::numeric;
    IF v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
  END IF;
  IF p_field = 'create' THEN
    INSERT INTO public.ton_staking_plans (code, name, lock_days, monthly_rate)
    VALUES (lower(p_code), p_value, 30, 1)
    ON CONFLICT (code) DO UPDATE SET name = excluded.name, updated_at = now();
    RETURN;
  END IF;
  UPDATE public.ton_staking_plans SET
    monthly_rate = CASE WHEN p_field = 'rate' THEN v_num ELSE monthly_rate END,
    bonus_rate = CASE WHEN p_field = 'bonus' THEN v_num ELSE bonus_rate END,
    lock_days = CASE WHEN p_field = 'lock' THEN greatest(1, v_num::int) ELSE lock_days END,
    min_stake_ton = CASE WHEN p_field = 'min' THEN v_num ELSE min_stake_ton END,
    max_stake_ton = CASE WHEN p_field = 'max' THEN v_num ELSE max_stake_ton END,
    sort_order = CASE WHEN p_field = 'sort' THEN v_num::int ELSE sort_order END,
    name = CASE WHEN p_field = 'name' THEN p_value ELSE name END,
    reward_claim_mode = CASE WHEN p_field = 'claimmode'
      THEN (CASE WHEN lower(p_value) IN ('on_unlock', 'unlock') THEN 'on_unlock' ELSE 'anytime' END)
      ELSE reward_claim_mode END,
    enabled = CASE WHEN p_field = 'enabled' THEN lower(p_value) IN ('1', 'on', 'true', 'sim') ELSE enabled END,
    updated_at = now()
  WHERE code = lower(p_code);
  IF NOT FOUND THEN RAISE EXCEPTION 'PLAN_NOT_FOUND'; END IF;
END $$;