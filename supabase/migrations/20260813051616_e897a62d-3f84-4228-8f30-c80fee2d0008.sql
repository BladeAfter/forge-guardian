CREATE TABLE IF NOT EXISTS public.ad_reward_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  reward_period date NOT NULL,
  amount_ton numeric NOT NULL DEFAULT 0,
  ad_event_id text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending',
  source text NOT NULL DEFAULT 'client',
  block_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  rewarded_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ad_reward_claims_user_period_idx ON public.ad_reward_claims (user_id, reward_period, status);

GRANT ALL ON public.ad_reward_claims TO service_role;
ALTER TABLE public.ad_reward_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages ad reward claims" ON public.ad_reward_claims;
CREATE POLICY "service role manages ad reward claims"
  ON public.ad_reward_claims FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP TRIGGER IF EXISTS trg_ad_reward_claims_touch ON public.ad_reward_claims;
CREATE TRIGGER trg_ad_reward_claims_touch BEFORE UPDATE ON public.ad_reward_claims
FOR EACH ROW EXECUTE FUNCTION public.referral_first_ton_events_touch();

-- Next 21:00 America/Sao_Paulo boundary (server is the authority for the reset).
CREATE OR REPLACE FUNCTION public.ad_reward_period_reset_at()
RETURNS timestamptz LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE tz text := 'America/Sao_Paulo'; h int := 21; l timestamp; d date;
BEGIN
  BEGIN tz := public.game_timezone(); h := public.game_day_reset_hour(); EXCEPTION WHEN others THEN tz := 'America/Sao_Paulo'; h := 21; END;
  l := now() AT TIME ZONE tz;
  d := CASE WHEN extract(hour from l) >= h THEN (l::date + 1) ELSE l::date END;
  RETURN ((d::text||' '||lpad(h::text, 2, '0')||':00:00')::timestamp) AT TIME ZONE tz;
END $$;

CREATE OR REPLACE FUNCTION public.ad_rewards_state(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_limit int; v_reward numeric; v_used int; v_earned numeric; v_period date; v_block text; v_last timestamptz;
BEGIN
  v_limit := GREATEST(0, public.setting_num('ad_reward_daily_limit', 10)::int);
  v_reward := GREATEST(0, public.setting_num('ad_reward_ton', 0.01));
  v_period := public.game_day_key(now());
  SELECT count(*), COALESCE(sum(amount_ton), 0), max(rewarded_at) INTO v_used, v_earned, v_last
    FROM public.ad_reward_claims
    WHERE user_id = p_user_id AND reward_period = v_period AND status = 'rewarded';
  v_block := NULLIF(trim(COALESCE(public.setting_text('adsgram_pvp_reward_block_id', '42560'), '')), '');
  RETURN jsonb_build_object(
    'enabled', public.setting_bool('ad_reward_enabled', true) AND v_block IS NOT NULL AND v_reward > 0,
    'blockId', v_block,
    'rewardTon', round(v_reward, 9),
    'dailyLimit', v_limit,
    'adsCompleted', COALESCE(v_used, 0),
    'remaining', GREATEST(0, v_limit - COALESCE(v_used, 0)),
    'earnedTon', round(COALESCE(v_earned, 0), 9),
    'maxTon', round(v_reward * v_limit, 9),
    'period', v_period,
    'resetsAt', public.ad_reward_period_reset_at(),
    'lastAdAt', v_last
  );
END $$;

-- Opens an attempt. No TON is granted here; the limit is checked server-side.
CREATE OR REPLACE FUNCTION public.ad_reward_begin(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u public.game_players; v_state jsonb; v_id uuid; v_period date;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned, false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('ad_reward:'||u.id::text, 0));
  v_state := public.ad_rewards_state(u.id);
  IF NOT (v_state->>'enabled')::boolean THEN RAISE EXCEPTION 'AD_REWARDS_DISABLED'; END IF;
  IF (v_state->>'remaining')::int <= 0 THEN RAISE EXCEPTION 'AD_REWARD_DAILY_LIMIT'; END IF;
  v_period := (v_state->>'period')::date;

  -- Only one live attempt at a time (double-click protection lives in the database too).
  DELETE FROM public.ad_reward_claims
    WHERE user_id = u.id AND status = 'pending' AND created_at < now() - interval '10 minutes';
  IF EXISTS (SELECT 1 FROM public.ad_reward_claims WHERE user_id = u.id AND status = 'pending') THEN
    SELECT id INTO v_id FROM public.ad_reward_claims WHERE user_id = u.id AND status = 'pending' ORDER BY created_at DESC LIMIT 1;
  ELSE
    INSERT INTO public.ad_reward_claims(user_id, reward_period, amount_ton, ad_event_id, status, block_id)
    VALUES (u.id, v_period, 0, 'attempt:'||u.id::text||':'||gen_random_uuid()::text, 'pending', v_state->>'blockId')
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('viewId', v_id, 'blockId', v_state->>'blockId', 'ads', public.ad_rewards_state(u.id));
END $$;

-- Credits the fixed server-side reward, once per confirmed completion.
CREATE OR REPLACE FUNCTION public.ad_reward_claim(p_telegram_id bigint, p_view_id uuid DEFAULT NULL, p_source text DEFAULT 'client')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u public.game_players; v public.ad_reward_claims; v_state jsonb; v_reward numeric; v_credit jsonb; v_period date;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned, false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('ad_reward:'||u.id::text, 0));
  v_period := public.game_day_key(now());

  IF p_view_id IS NOT NULL THEN
    SELECT * INTO v FROM public.ad_reward_claims WHERE id = p_view_id AND user_id = u.id FOR UPDATE;
    IF v.id IS NOT NULL AND v.status = 'rewarded' THEN
      RETURN jsonb_build_object('granted', false, 'reason', 'ALREADY_REWARDED', 'ads', public.ad_rewards_state(u.id));
    END IF;
  END IF;
  IF v.id IS NULL THEN
    SELECT * INTO v FROM public.ad_reward_claims
      WHERE user_id = u.id AND status = 'pending' AND created_at > now() - interval '10 minutes'
      ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  END IF;
  IF v.id IS NULL THEN
    RETURN jsonb_build_object('granted', false, 'reason', 'NO_PENDING_VIEW', 'ads', public.ad_rewards_state(u.id));
  END IF;

  v_state := public.ad_rewards_state(u.id);
  IF NOT (v_state->>'enabled')::boolean THEN RAISE EXCEPTION 'AD_REWARDS_DISABLED'; END IF;
  IF (v_state->>'remaining')::int <= 0 THEN
    DELETE FROM public.ad_reward_claims WHERE id = v.id;
    RAISE EXCEPTION 'AD_REWARD_DAILY_LIMIT';
  END IF;

  v_reward := (v_state->>'rewardTon')::numeric;
  UPDATE public.ad_reward_claims
    SET status = 'rewarded', amount_ton = v_reward, rewarded_at = now(),
        reward_period = v_period, source = COALESCE(p_source, 'client')
    WHERE id = v.id;

  v_credit := public.credit_ton_reward(u.id, v_reward, 'rewarded_ad', v.id::text, 'Rewarded ad');

  RETURN jsonb_build_object('granted', true, 'rewardTon', v_reward,
    'balanceTon', v_credit->'balanceTon', 'ads', public.ad_rewards_state(u.id));
END $$;

REVOKE ALL ON FUNCTION public.ad_rewards_state(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ad_reward_begin(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ad_reward_claim(bigint, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ad_reward_period_reset_at() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ad_rewards_state(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ad_reward_begin(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.ad_reward_claim(bigint, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ad_reward_period_reset_at() TO service_role;

-- Admin Bot read-only overview.
CREATE OR REPLACE FUNCTION public.admin_ad_rewards_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_period date;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_period := public.game_day_key(now());
  RETURN jsonb_build_object(
    'period', v_period,
    'resetsAt', public.ad_reward_period_reset_at(),
    'rewardTon', public.setting_num('ad_reward_ton', 0.01),
    'dailyLimit', public.setting_num('ad_reward_daily_limit', 10),
    'adsToday', (SELECT count(*) FROM public.ad_reward_claims WHERE reward_period = v_period AND status = 'rewarded'),
    'tonToday', (SELECT COALESCE(sum(amount_ton), 0) FROM public.ad_reward_claims WHERE reward_period = v_period AND status = 'rewarded'),
    'adsTotal', (SELECT count(*) FROM public.ad_reward_claims WHERE status = 'rewarded'),
    'tonTotal', (SELECT COALESCE(sum(amount_ton), 0) FROM public.ad_reward_claims WHERE status = 'rewarded'),
    'topUsers', (SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT p.telegram_id::text AS "telegramId", COALESCE(p.display_name, 'Player') AS name, p.username,
               count(*) AS ads, sum(c.amount_ton) AS "tonEarned"
          FROM public.ad_reward_claims c JOIN public.game_players p ON p.id = c.user_id
         WHERE c.status = 'rewarded'
         GROUP BY p.telegram_id, p.display_name, p.username
         ORDER BY sum(c.amount_ton) DESC LIMIT 10) t),
    'history', (SELECT COALESCE(jsonb_agg(h), '[]'::jsonb) FROM (
        SELECT c.id, COALESCE(p.display_name, 'Player') AS name, p.username, c.amount_ton AS "amountTon",
               c.reward_period AS period, c.rewarded_at AS "rewardedAt", c.source
          FROM public.ad_reward_claims c JOIN public.game_players p ON p.id = c.user_id
         WHERE c.status = 'rewarded' ORDER BY c.rewarded_at DESC LIMIT 20) h)
  );
END $$;

REVOKE ALL ON FUNCTION public.admin_ad_rewards_overview(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_ad_rewards_overview(bigint) TO service_role;