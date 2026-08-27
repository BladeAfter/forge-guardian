-- ============================================================
-- CLAN TREASURY: per-clan daily contribution limits (min/max)
-- ============================================================

-- 1) PER-CLAN SETTINGS (NULL = inherit global default)
ALTER TABLE public.clans
  ADD COLUMN IF NOT EXISTS daily_contribution_min_fc numeric,
  ADD COLUMN IF NOT EXISTS daily_contribution_max_fc numeric,
  ADD COLUMN IF NOT EXISTS daily_contribution_min_myth numeric,
  ADD COLUMN IF NOT EXISTS daily_contribution_max_myth numeric;

-- 2) GLOBAL DEFAULTS + HARD CAP (admin bot configurable)
ALTER TABLE public.clan_collective_settings
  ADD COLUMN IF NOT EXISTS donation_default_min_fc numeric NOT NULL DEFAULT 10000,
  ADD COLUMN IF NOT EXISTS donation_default_max_fc numeric NOT NULL DEFAULT 1000000,
  ADD COLUMN IF NOT EXISTS donation_hard_max_fc numeric NOT NULL DEFAULT 10000000,
  ADD COLUMN IF NOT EXISTS donation_default_min_myth numeric NOT NULL DEFAULT 500,
  ADD COLUMN IF NOT EXISTS donation_default_max_myth numeric NOT NULL DEFAULT 10000,
  ADD COLUMN IF NOT EXISTS donation_hard_max_myth numeric NOT NULL DEFAULT 100000;

-- 3) DAILY COUNTER: player + clan + day + asset (survives clan hopping)
CREATE TABLE IF NOT EXISTS public.clan_daily_contributions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  game_day date NOT NULL,
  asset text NOT NULL,
  total numeric NOT NULL DEFAULT 0,
  donations integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clan_id, user_id, game_day, asset)
);
GRANT ALL ON public.clan_daily_contributions TO service_role;
ALTER TABLE public.clan_daily_contributions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clan_daily_contributions_service_only"
  ON public.clan_daily_contributions FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE INDEX IF NOT EXISTS clan_daily_contributions_lookup
  ON public.clan_daily_contributions(user_id, game_day, asset);

-- 4) EFFECTIVE LIMITS FOR A CLAN/ASSET
CREATE OR REPLACE FUNCTION public.clan_donation_limits(p_clan uuid, p_asset text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; c public.clans;
        v_min numeric; v_max numeric; v_hard numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  SELECT * INTO c FROM public.clans WHERE id = p_clan;
  IF p_asset = 'MYTH' THEN
    v_min  := COALESCE(c.daily_contribution_min_myth, cfg.donation_default_min_myth);
    v_max  := COALESCE(c.daily_contribution_max_myth, cfg.donation_default_max_myth);
    v_hard := cfg.donation_hard_max_myth;
  ELSE
    v_min  := COALESCE(c.daily_contribution_min_fc, cfg.donation_default_min_fc);
    v_max  := COALESCE(c.daily_contribution_max_fc, cfg.donation_default_max_fc);
    v_hard := cfg.donation_hard_max_fc;
  END IF;
  -- a stale per-clan value can never beat a lowered global hard cap
  v_max := LEAST(v_max, v_hard);
  v_min := LEAST(v_min, v_max);
  RETURN jsonb_build_object('asset', p_asset, 'min', v_min, 'max', v_max, 'hardMax', v_hard,
                            'configured', (CASE WHEN p_asset = 'MYTH'
                              THEN c.daily_contribution_max_myth IS NOT NULL
                              ELSE c.daily_contribution_max_fc IS NOT NULL END));
END $$;

-- 5) LEADER-ONLY CONFIGURATION RPC
CREATE OR REPLACE FUNCTION public.clan_contribution_limits_set(
  p_telegram_id text, p_asset text, p_min numeric, p_max numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; v_role text; v_hard numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  -- LEADER ONLY: co-leader/officer/member are rejected server-side
  IF lower(COALESCE(v_role,'')) <> 'leader'
     AND NOT EXISTS (SELECT 1 FROM public.clans WHERE id = v_clan AND leader_user_id = v_uid) THEN
    RAISE EXCEPTION 'LEADER_ONLY';
  END IF;
  IF p_asset NOT IN ('FC','MYTH') THEN RAISE EXCEPTION 'INVALID_ASSET'; END IF;
  IF p_min IS NULL OR p_max IS NULL THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_min < 0 THEN RAISE EXCEPTION 'INVALID_MINIMUM'; END IF;
  IF p_max <= 0 THEN RAISE EXCEPTION 'INVALID_MAXIMUM'; END IF;
  IF p_min > p_max THEN RAISE EXCEPTION 'MIN_ABOVE_MAX'; END IF;

  v_hard := CASE WHEN p_asset = 'MYTH' THEN cfg.donation_hard_max_myth ELSE cfg.donation_hard_max_fc END;
  IF p_max > v_hard THEN RAISE EXCEPTION 'ABOVE_GLOBAL_CAP'; END IF;

  IF p_asset = 'MYTH' THEN
    UPDATE public.clans SET daily_contribution_min_myth = floor(p_min),
                            daily_contribution_max_myth = floor(p_max),
                            updated_at = now() WHERE id = v_clan;
  ELSE
    UPDATE public.clans SET daily_contribution_min_fc = floor(p_min),
                            daily_contribution_max_fc = floor(p_max),
                            updated_at = now() WHERE id = v_clan;
  END IF;

  RETURN jsonb_build_object('status','saved', 'limits', public.clan_donation_limits(v_clan, p_asset));
END $$;

-- 6) MEMBER-FACING STATE: limits, today's total, remaining, next reset
CREATE OR REPLACE FUNCTION public.clan_donation_state(p_telegram_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; v_role text;
        v_day date; v_out jsonb := '[]'::jsonb; a text; lim jsonb; v_total numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;
  v_day := public.game_day_key();

  FOREACH a IN ARRAY cfg.treasury_assets LOOP
    IF a NOT IN ('FC','MYTH') THEN CONTINUE; END IF;
    lim := public.clan_donation_limits(v_clan, a);
    SELECT COALESCE(total,0) INTO v_total FROM public.clan_daily_contributions
     WHERE clan_id = v_clan AND user_id = v_uid AND game_day = v_day AND asset = a;
    v_out := v_out || jsonb_build_object(
      'asset', a,
      'min', (lim->>'min')::numeric,
      'max', (lim->>'max')::numeric,
      'hardMax', (lim->>'hardMax')::numeric,
      'today', COALESCE(v_total,0),
      'remaining', GREATEST(0, (lim->>'max')::numeric - COALESCE(v_total,0)),
      'reached', COALESCE(v_total,0) >= (lim->>'max')::numeric
    );
  END LOOP;

  RETURN jsonb_build_object(
    'inClan', true,
    'isLeader', (lower(COALESCE(v_role,'')) = 'leader'
                 OR EXISTS (SELECT 1 FROM public.clans WHERE id = v_clan AND leader_user_id = v_uid)),
    'gameDay', v_day,
    'nextResetAt', ((v_day + 1)::timestamp + make_interval(hours => public.game_day_reset_hour()))
                     AT TIME ZONE public.game_timezone(),
    'assets', v_out);
END $$;

-- 7) DONATION: atomic, server-side min/max validation on the DAILY TOTAL
CREATE OR REPLACE FUNCTION public.clan_treasury_donate(
  p_telegram_id text, p_asset text, p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_uid uuid; v_clan uuid; v_bal numeric; v_after numeric;
        v_day date; lim jsonb; v_min numeric; v_max numeric; v_today numeric; v_remaining numeric;
BEGIN
  cfg := public.clan_collective_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  IF p_asset NOT IN ('FC','MYTH') OR NOT (p_asset = ANY(cfg.treasury_assets)) THEN RAISE EXCEPTION 'INVALID_ASSET'; END IF;
  IF COALESCE(p_amount,0) <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  p_amount := floor(p_amount);

  v_day := public.game_day_key();
  lim := public.clan_donation_limits(v_clan, p_asset);
  v_min := (lim->>'min')::numeric;
  v_max := (lim->>'max')::numeric;

  -- lock (or create) the daily counter row first: two parallel donations serialise here
  INSERT INTO public.clan_daily_contributions(clan_id, user_id, game_day, asset, total, donations)
  VALUES (v_clan, v_uid, v_day, p_asset, 0, 0)
  ON CONFLICT (clan_id, user_id, game_day, asset) DO NOTHING;
  SELECT total INTO v_today FROM public.clan_daily_contributions
   WHERE clan_id = v_clan AND user_id = v_uid AND game_day = v_day AND asset = p_asset FOR UPDATE;
  v_today := COALESCE(v_today, 0);
  v_remaining := GREATEST(0, v_max - v_today);

  IF p_amount < v_min THEN
    RAISE EXCEPTION 'BELOW_MINIMUM_CONTRIBUTION|%|%', v_min, p_asset;
  END IF;
  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'DAILY_LIMIT_REACHED|%|%|%', v_today, v_max, p_asset;
  END IF;
  IF p_amount > v_remaining THEN
    RAISE EXCEPTION 'DAILY_LIMIT_EXCEEDED|%|%|%', v_today, v_remaining, p_asset;
  END IF;

  IF p_asset = 'FC' THEN
    SELECT forge_coins INTO v_bal FROM public.game_players WHERE id = v_uid FOR UPDATE;
    IF COALESCE(v_bal,0) < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;
    UPDATE public.game_players SET forge_coins = forge_coins - p_amount, updated_at = now() WHERE id = v_uid;
  ELSE
    -- MYTH is transferred from the player's own balance, never minted
    SELECT amount INTO v_bal FROM public.myth_balances WHERE user_id = v_uid FOR UPDATE;
    IF COALESCE(v_bal,0) < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_MYTH'; END IF;
    UPDATE public.myth_balances SET amount = amount - p_amount, updated_at = now() WHERE user_id = v_uid;
    INSERT INTO public.myth_ledger(user_id, direction, amount, reason)
    VALUES (v_uid, 'debit', p_amount, 'clan_treasury_donation');
  END IF;

  v_after := public.clan_treasury_move(v_clan, v_uid, p_asset, p_amount, 'CLAN_DONATION');

  UPDATE public.clan_daily_contributions
     SET total = total + p_amount, donations = donations + 1, updated_at = now()
   WHERE clan_id = v_clan AND user_id = v_uid AND game_day = v_day AND asset = p_asset;

  PERFORM public.grant_clan_xp(v_uid, 'clan_donation', GREATEST(1, floor(p_amount / 10000))::int);

  RETURN jsonb_build_object('status','donated','asset', p_asset, 'amount', p_amount,
                           'treasury', v_after,
                           'today', v_today + p_amount,
                           'max', v_max,
                           'remaining', GREATEST(0, v_max - (v_today + p_amount)));
END $$;

-- 8) LOCK DOWN EXECUTION (edge functions use service_role)
DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'clan_donation_limits(uuid,text)',
    'clan_contribution_limits_set(text,text,numeric,numeric)',
    'clan_donation_state(text)',
    'clan_treasury_donate(text,text,numeric)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role', fn);
  END LOOP;
END $$;