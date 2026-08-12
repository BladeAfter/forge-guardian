CREATE TABLE IF NOT EXISTS public.pvp_ad_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  cycle_date date NOT NULL DEFAULT public.game_day_key(now()),
  status text NOT NULL DEFAULT 'pending',
  source text,
  provider text NOT NULL DEFAULT 'adsgram',
  block_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  rewarded_at timestamptz,
  CONSTRAINT pvp_ad_views_status_check CHECK (status IN ('pending','rewarded'))
);

GRANT ALL ON public.pvp_ad_views TO service_role;
ALTER TABLE public.pvp_ad_views ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS pvp_ad_views_user_cycle_idx ON public.pvp_ad_views (user_id, cycle_date, status);
CREATE INDEX IF NOT EXISTS pvp_ad_views_pending_idx ON public.pvp_ad_views (user_id, created_at) WHERE status = 'pending';

INSERT INTO public.game_settings (key, value, category, label) VALUES
  ('adsgram_reward_enabled', 'true'::jsonb, 'ads', 'AdsGram rewarded ads (PvP tickets) ativo'),
  ('adsgram_pvp_reward_block_id', '"42560"'::jsonb, 'ads', 'AdsGram Reward Block ID (PvP tickets)'),
  ('adsgram_reward_daily_limit', '10'::jsonb, 'ads', 'Máximo de tickets PvP por anúncios por ciclo diário'),
  ('adsgram_interstitial_enabled', 'false'::jsonb, 'ads', 'Anúncio interstitial na entrada do jogo'),
  ('adsgram_interstitial_block_id', '""'::jsonb, 'ads', 'AdsGram Interstitial Block ID (int-XXXXX)')
ON CONFLICT (key) DO NOTHING;

-- Ads-today counter for the current 21:00 cycle. Never touches ticket balance.
CREATE OR REPLACE FUNCTION public.pvp_ads_state(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_limit int; v_used int; v_cycle date; v_block text; v_int_block text;
BEGIN
  v_limit := GREATEST(0, public.setting_num('adsgram_reward_daily_limit', 10)::int);
  v_cycle := public.game_day_key(now());
  SELECT count(*) INTO v_used FROM public.pvp_ad_views
    WHERE user_id = p_user_id AND cycle_date = v_cycle AND status = 'rewarded';
  v_block := NULLIF(trim(COALESCE(public.setting_text('adsgram_pvp_reward_block_id', '42560'), '')), '');
  v_int_block := NULLIF(trim(COALESCE(public.setting_text('adsgram_interstitial_block_id', ''), '')), '');
  RETURN jsonb_build_object(
    'enabled', public.setting_bool('adsgram_reward_enabled', true) AND v_block IS NOT NULL,
    'blockId', v_block,
    'dailyLimit', v_limit,
    'watchedToday', v_used,
    'remaining', GREATEST(0, v_limit - v_used),
    'cycleDate', v_cycle,
    'interstitialEnabled', public.setting_bool('adsgram_interstitial_enabled', false) AND v_int_block IS NOT NULL,
    'interstitialBlockId', v_int_block
  );
END;
$$;

REVOKE ALL ON FUNCTION public.pvp_ads_state(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pvp_ads_state(uuid) TO service_role;

-- Opens an ad view slot. Only checks the limit; no reward is granted here.
CREATE OR REPLACE FUNCTION public.pvp_ad_view_begin(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE u public.game_players; v_limit int; v_used int; v_cycle date; v_id uuid; v_block text;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  v_block := NULLIF(trim(COALESCE(public.setting_text('adsgram_pvp_reward_block_id','42560'),'')), '');
  IF v_block IS NULL OR NOT public.setting_bool('adsgram_reward_enabled', true) THEN
    RAISE EXCEPTION 'ADS_DISABLED';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pvp_ad_view'||u.id::text, 0));
  v_cycle := public.game_day_key(now());
  v_limit := GREATEST(0, public.setting_num('adsgram_reward_daily_limit', 10)::int);
  SELECT count(*) INTO v_used FROM public.pvp_ad_views
    WHERE user_id = u.id AND cycle_date = v_cycle AND status = 'rewarded';
  IF v_used >= v_limit THEN RAISE EXCEPTION 'ADS_DAILY_LIMIT'; END IF;

  -- Drop stale pending views (older than 10 minutes) so a closed ad never blocks the next one.
  DELETE FROM public.pvp_ad_views
    WHERE user_id = u.id AND status = 'pending' AND created_at < now() - interval '10 minutes';
  -- One live view at a time: prevents two simultaneous ads / double clicks.
  IF EXISTS (SELECT 1 FROM public.pvp_ad_views WHERE user_id = u.id AND status = 'pending') THEN
    SELECT id INTO v_id FROM public.pvp_ad_views
      WHERE user_id = u.id AND status = 'pending' ORDER BY created_at DESC LIMIT 1;
  ELSE
    INSERT INTO public.pvp_ad_views (user_id, cycle_date, status, block_id)
    VALUES (u.id, v_cycle, 'pending', v_block) RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('viewId', v_id, 'blockId', v_block, 'ads', public.pvp_ads_state(u.id));
END;
$$;

REVOKE ALL ON FUNCTION public.pvp_ad_view_begin(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pvp_ad_view_begin(bigint) TO service_role;

-- Credits exactly +1 PvP ticket for a completed ad view. Atomic and idempotent per view.
CREATE OR REPLACE FUNCTION public.pvp_ad_view_reward(p_telegram_id bigint, p_view_id uuid DEFAULT NULL, p_source text DEFAULT 'client')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE u public.game_players; v_limit int; v_used int; v_cycle date; v_view public.pvp_ad_views;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pvp_ad_view'||u.id::text, 0));
  v_cycle := public.game_day_key(now());

  IF p_view_id IS NOT NULL THEN
    SELECT * INTO v_view FROM public.pvp_ad_views
      WHERE id = p_view_id AND user_id = u.id FOR UPDATE;
    -- Already settled (client callback + Reward URL for the same view): no second reward.
    IF v_view.id IS NOT NULL AND v_view.status = 'rewarded' THEN
      RETURN jsonb_build_object('granted', false, 'reason', 'ALREADY_REWARDED', 'ads', public.pvp_ads_state(u.id), 'tickets', COALESCE(u.pvp_tickets,0));
    END IF;
  END IF;

  IF v_view.id IS NULL THEN
    SELECT * INTO v_view FROM public.pvp_ad_views
      WHERE user_id = u.id AND status = 'pending' AND created_at > now() - interval '10 minutes'
      ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  END IF;

  IF v_view.id IS NULL THEN
    RETURN jsonb_build_object('granted', false, 'reason', 'NO_PENDING_VIEW', 'ads', public.pvp_ads_state(u.id), 'tickets', COALESCE(u.pvp_tickets,0));
  END IF;

  v_limit := GREATEST(0, public.setting_num('adsgram_reward_daily_limit', 10)::int);
  SELECT count(*) INTO v_used FROM public.pvp_ad_views
    WHERE user_id = u.id AND cycle_date = v_cycle AND status = 'rewarded';
  IF v_used >= v_limit THEN
    DELETE FROM public.pvp_ad_views WHERE id = v_view.id;
    RAISE EXCEPTION 'ADS_DAILY_LIMIT';
  END IF;

  UPDATE public.pvp_ad_views
    SET status = 'rewarded', rewarded_at = now(), source = COALESCE(p_source,'client'), cycle_date = v_cycle
    WHERE id = v_view.id;

  UPDATE public.game_players
    SET pvp_tickets = COALESCE(pvp_tickets,0) + 1
    WHERE id = u.id;

  RETURN jsonb_build_object(
    'granted', true,
    'tickets', COALESCE(u.pvp_tickets,0) + 1,
    'ads', public.pvp_ads_state(u.id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.pvp_ad_view_reward(bigint, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pvp_ad_view_reward(bigint, uuid, text) TO service_role;