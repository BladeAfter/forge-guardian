-- ============================================================================
-- 💎 TON STAKING (internal TON, server-side, transactional, idempotent)
-- Integrated with MINAS DE TON: mine claims may be routed into staking.
-- Nothing about mine prices/yield/storage/loyalty changes here.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.ton_staking_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  paused boolean NOT NULL DEFAULT false,
  min_stake_ton numeric(30,9) NOT NULL DEFAULT 1,
  max_stake_ton numeric(30,9) NOT NULL DEFAULT 0,
  auto_stake_min_ton numeric(30,9) NOT NULL DEFAULT 1,
  allowed_percents integer[] NOT NULL DEFAULT '{25,50,75,100}',
  auto_compound_allowed boolean NOT NULL DEFAULT true,
  early_unstake_allowed boolean NOT NULL DEFAULT false,
  early_unstake_penalty_percent numeric(8,4) NOT NULL DEFAULT 0,
  month_days integer NOT NULL DEFAULT 30,
  accrue_after_maturity boolean NOT NULL DEFAULT false,
  reward_pool_total numeric(30,9) NOT NULL DEFAULT 0,
  reward_pool_paid numeric(30,9) NOT NULL DEFAULT 0,
  reward_pool_min_available numeric(30,9) NOT NULL DEFAULT 0,
  pool_gate_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.ton_staking_settings (id) VALUES (true) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.ton_staking_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  lock_days integer NOT NULL,
  monthly_rate numeric(10,4) NOT NULL DEFAULT 0,
  bonus_rate numeric(10,4) NOT NULL DEFAULT 0,
  min_stake_ton numeric(30,9) NOT NULL DEFAULT 0,
  max_stake_ton numeric(30,9) NOT NULL DEFAULT 0,
  reward_claim_mode text NOT NULL DEFAULT 'anytime',
  auto_compound_allowed boolean NOT NULL DEFAULT true,
  early_unstake_allowed boolean NOT NULL DEFAULT false,
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ton_staking_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  plan_id uuid NOT NULL REFERENCES public.ton_staking_plans(id),
  principal_ton numeric(30,9) NOT NULL,
  initial_principal_ton numeric(30,9) NOT NULL,
  rate_snapshot numeric(10,4) NOT NULL,
  bonus_snapshot numeric(10,4) NOT NULL DEFAULT 0,
  lock_days_snapshot integer NOT NULL,
  claim_mode_snapshot text NOT NULL DEFAULT 'anytime',
  started_at timestamptz NOT NULL DEFAULT now(),
  unlock_at timestamptz NOT NULL,
  last_accrual_at timestamptz NOT NULL DEFAULT now(),
  accrued_reward_ton numeric(30,9) NOT NULL DEFAULT 0,
  claimed_reward_ton numeric(30,9) NOT NULL DEFAULT 0,
  compounded_ton numeric(30,9) NOT NULL DEFAULT 0,
  total_earned_ton numeric(30,9) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'ACTIVE',
  auto_compound boolean NOT NULL DEFAULT false,
  source text NOT NULL DEFAULT 'manual',
  withdrawn_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ton_staking_positions_user_idx ON public.ton_staking_positions(user_id, status);

CREATE TABLE IF NOT EXISTS public.ton_staking_preferences (
  user_id uuid PRIMARY KEY,
  mine_auto_stake_enabled boolean NOT NULL DEFAULT false,
  mine_auto_stake_percent integer NOT NULL DEFAULT 0,
  auto_stake_plan_id uuid REFERENCES public.ton_staking_plans(id),
  auto_compound boolean NOT NULL DEFAULT false,
  pending_auto_stake_ton numeric(30,9) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ton_staking_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  position_id uuid,
  entry_type text NOT NULL,
  amount_ton numeric(30,9) NOT NULL DEFAULT 0,
  source text,
  request_id text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ton_staking_ledger_user_idx ON public.ton_staking_ledger(user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ton_staking_ledger_request_idx ON public.ton_staking_ledger(entry_type, request_id) WHERE request_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.ton_staking_idempotency (
  key text PRIMARY KEY,
  user_id uuid,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.ton_staking_settings TO service_role;
GRANT ALL ON public.ton_staking_plans TO service_role;
GRANT ALL ON public.ton_staking_positions TO service_role;
GRANT ALL ON public.ton_staking_preferences TO service_role;
GRANT ALL ON public.ton_staking_ledger TO service_role;
GRANT ALL ON public.ton_staking_idempotency TO service_role;

ALTER TABLE public.ton_staking_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ton_staking_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ton_staking_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ton_staking_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ton_staking_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ton_staking_idempotency ENABLE ROW LEVEL SECURITY;

INSERT INTO public.ton_staking_plans (code, name, lock_days, monthly_rate, bonus_rate, sort_order)
VALUES
  ('d30',  '30 DIAS',  30,  1.0000, 0.0000, 1),
  ('d60',  '60 DIAS',  60,  1.0000, 0.2500, 2),
  ('d90',  '90 DIAS',  90,  1.0000, 0.5000, 3),
  ('d180', '180 DIAS', 180, 1.0000, 1.0000, 4),
  ('d365', '365 DIAS', 365, 1.0000, 1.5000, 5)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.ton_staking_outstanding()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT coalesce(sum(accrued_reward_ton), 0) FROM public.ton_staking_positions WHERE status <> 'WITHDRAWN'
$$;

CREATE OR REPLACE FUNCTION public.ton_staking_pool_available()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT round(greatest(0, s.reward_pool_total - s.reward_pool_paid - public.ton_staking_outstanding()), 9)
  FROM public.ton_staking_settings s WHERE s.id
$$;

CREATE OR REPLACE FUNCTION public.ton_staking_liability()
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT round(coalesce(sum(greatest(0,
      p.principal_ton * ((p.rate_snapshot + p.bonus_snapshot) / 100.0)
        * (p.lock_days_snapshot::numeric / greatest(1, (SELECT month_days FROM public.ton_staking_settings WHERE id))::numeric)
      - p.claimed_reward_ton)), 0), 9)
  FROM public.ton_staking_positions p WHERE p.status <> 'WITHDRAWN'
$$;

CREATE OR REPLACE FUNCTION public.ton_staking_accrue(p_position_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p public.ton_staking_positions; s public.ton_staking_settings;
        v_end timestamptz; v_secs numeric; v_eff numeric; v_gain numeric; v_avail numeric;
BEGIN
  SELECT * INTO p FROM public.ton_staking_positions WHERE id = p_position_id FOR UPDATE;
  IF p.id IS NULL OR p.status = 'WITHDRAWN' THEN RETURN; END IF;
  SELECT * INTO s FROM public.ton_staking_settings WHERE id;

  v_end := now();
  IF NOT coalesce(s.accrue_after_maturity, false) THEN v_end := least(now(), p.unlock_at); END IF;
  v_secs := greatest(0, extract(epoch FROM (v_end - p.last_accrual_at)));

  IF v_secs > 0 AND coalesce(s.enabled, true) THEN
    v_eff := (p.rate_snapshot + coalesce(p.bonus_snapshot, 0)) / 100.0;
    v_gain := round(p.principal_ton * v_eff * (v_secs / (greatest(1, coalesce(s.month_days, 30))::numeric * 86400.0)), 9);
    IF coalesce(s.pool_gate_enabled, false) THEN
      v_avail := public.ton_staking_pool_available();
      v_gain := least(v_gain, greatest(coalesce(v_avail, 0), 0));
    END IF;
    IF v_gain > 0 THEN
      IF p.auto_compound THEN
        UPDATE public.ton_staking_positions
           SET principal_ton = round(principal_ton + v_gain, 9),
               compounded_ton = round(compounded_ton + v_gain, 9),
               total_earned_ton = round(total_earned_ton + v_gain, 9),
               updated_at = now()
         WHERE id = p.id;
        INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source)
        VALUES (p.user_id, p.id, 'COMPOUND', v_gain, 'accrual');
      ELSE
        UPDATE public.ton_staking_positions
           SET accrued_reward_ton = round(accrued_reward_ton + v_gain, 9),
               total_earned_ton = round(total_earned_ton + v_gain, 9),
               updated_at = now()
         WHERE id = p.id;
      END IF;
    END IF;
  END IF;

  UPDATE public.ton_staking_positions
     SET last_accrual_at = now(),
         status = CASE WHEN status = 'ACTIVE' AND now() >= unlock_at THEN 'MATURED' ELSE status END,
         updated_at = now()
   WHERE id = p.id;
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_accrue_user(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.ton_staking_positions
            WHERE user_id = p_user_id AND status <> 'WITHDRAWN' ORDER BY started_at LOOP
    PERFORM public.ton_staking_accrue(r.id);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_flush_pending(p_user_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE pr public.ton_staking_preferences; s public.ton_staking_settings; pl public.ton_staking_plans;
        v_min numeric; v_amount numeric; v_pos uuid; v_compound boolean;
BEGIN
  SELECT * INTO pr FROM public.ton_staking_preferences WHERE user_id = p_user_id FOR UPDATE;
  IF pr.user_id IS NULL OR coalesce(pr.pending_auto_stake_ton, 0) <= 0 THEN RETURN 0; END IF;
  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  IF NOT coalesce(s.enabled, true) OR coalesce(s.paused, false) THEN RETURN 0; END IF;
  SELECT * INTO pl FROM public.ton_staking_plans WHERE id = pr.auto_stake_plan_id AND enabled;
  IF pl.id IS NULL THEN
    SELECT * INTO pl FROM public.ton_staking_plans WHERE enabled ORDER BY sort_order, lock_days LIMIT 1;
  END IF;
  IF pl.id IS NULL THEN RETURN 0; END IF;

  v_min := greatest(coalesce(s.auto_stake_min_ton, 1),
                    CASE WHEN pl.min_stake_ton > 0 THEN pl.min_stake_ton ELSE s.min_stake_ton END);
  v_amount := round(pr.pending_auto_stake_ton, 9);
  IF v_amount < v_min THEN RETURN 0; END IF;

  v_compound := coalesce(pr.auto_compound, false) AND pl.auto_compound_allowed AND s.auto_compound_allowed;

  INSERT INTO public.ton_staking_positions (
    user_id, plan_id, principal_ton, initial_principal_ton, rate_snapshot, bonus_snapshot,
    lock_days_snapshot, claim_mode_snapshot, unlock_at, auto_compound, source)
  VALUES (p_user_id, pl.id, v_amount, v_amount, pl.monthly_rate, pl.bonus_rate,
          pl.lock_days, pl.reward_claim_mode, now() + (pl.lock_days || ' days')::interval,
          v_compound, 'mine_auto_stake')
  RETURNING id INTO v_pos;

  UPDATE public.ton_staking_preferences
     SET pending_auto_stake_ton = round(pending_auto_stake_ton - v_amount, 9), updated_at = now()
   WHERE user_id = p_user_id;

  INSERT INTO public.ton_staking_ledger (user_id, position_id, entry_type, amount_ton, source, note)
  VALUES (p_user_id, v_pos, 'AUTO_STAKE_FLUSH', v_amount, 'mine_auto_stake', pl.code);
  RETURN v_amount;
END $$;

CREATE OR REPLACE FUNCTION public.ton_staking_route_mine(p_user_id uuid, p_amount numeric, p_source_id text)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE pr public.ton_staking_preferences; s public.ton_staking_settings; v_part numeric;
BEGIN
  IF coalesce(p_amount, 0) <= 0 THEN RETURN 0; END IF;
  SELECT * INTO s FROM public.ton_staking_settings WHERE id;
  IF NOT coalesce(s.enabled, true) THEN RETURN 0; END IF;
  SELECT * INTO pr FROM public.ton_staking_preferences WHERE user_id = p_user_id FOR UPDATE;
  IF pr.user_id IS NULL OR NOT coalesce(pr.mine_auto_stake_enabled, false)
     OR coalesce(pr.mine_auto_stake_percent, 0) <= 0 THEN RETURN 0; END IF;

  v_part := round(p_amount * least(100, pr.mine_auto_stake_percent)::numeric / 100.0, 9);
  IF v_part <= 0 THEN RETURN 0; END IF;

  UPDATE public.ton_staking_preferences
     SET pending_auto_stake_ton = round(pending_auto_stake_ton + v_part, 9), updated_at = now()
   WHERE user_id = p_user_id;
  INSERT INTO public.ton_staking_ledger (user_id, entry_type, amount_ton, source, request_id)
  VALUES (p_user_id, 'AUTO_STAKE_MINE', v_part, 'mine_claim', p_source_id)
  ON CONFLICT DO NOTHING;

  PERFORM public.ton_staking_flush_pending(p_user_id);
  RETURN v_part;
END $$;