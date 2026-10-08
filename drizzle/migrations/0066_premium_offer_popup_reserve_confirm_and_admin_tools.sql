-- 🎁 AUTO POPUP das ofertas premium: reserva (sem gravar) + confirmação atômica após o modal
-- realmente aparecer, mais ferramentas de teste/diagnóstico para o Admin Bot.
ALTER TABLE public.premium_offer_impressions ADD COLUMN IF NOT EXISTS admin_reset_at timestamptz;
ALTER TABLE public.premium_offer_impressions ADD COLUMN IF NOT EXISTS admin_reset_by bigint;

-- Impressões resetadas por Admin (ferramenta de teste/suporte) deixam de contar como "visto hoje",
-- mas continuam no histórico para métricas.
CREATE OR REPLACE FUNCTION public.should_show_premium_offer_popup(p_user_id uuid, p_offer_id text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u public.game_players; m jsonb; c public.celestial_pack_config; s public.sovereign_pack_config;
        v_last date; v_today date := public.premium_offer_day_key(); v_offer text; v_freq text;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE id = p_user_id;
  IF u.id IS NULL THEN RETURN 'NOT_ELIGIBLE'; END IF;
  IF COALESCE(u.banned,false) THEN RETURN 'NOT_ELIGIBLE'; END IF;

  v_offer := upper(COALESCE(p_offer_id,''));
  IF v_offer = 'CELESTIAL_MYSTERY_PACK' THEN
    c := public.celestial_pack_settings();
    IF NOT c.enabled OR NOT c.popup_enabled OR upper(c.popup_frequency) = 'DISABLED' THEN RETURN 'INACTIVE'; END IF;
    m := public.celestial_pack_offer_meta(p_user_id);
    v_freq := c.popup_frequency;
  ELSIF v_offer = 'CELESTIAL_SOVEREIGN_PACK' THEN
    s := public.sovereign_pack_settings();
    IF NOT s.enabled OR NOT s.popup_enabled OR upper(s.popup_frequency) = 'DISABLED' THEN RETURN 'INACTIVE'; END IF;
    m := public.sovereign_pack_offer_meta(p_user_id);
    v_freq := s.popup_frequency;
  ELSE
    RETURN 'NOT_ELIGIBLE';
  END IF;

  IF (m->>'purchased')::boolean OR (m->>'processing')::boolean THEN RETURN 'PURCHASED'; END IF;
  IF NOT (m->>'windowOpen')::boolean THEN RETURN 'INACTIVE'; END IF;
  IF (m->>'soldOut')::boolean THEN RETURN 'INACTIVE'; END IF;

  SELECT max(impression_date) INTO v_last FROM public.premium_offer_impressions
   WHERE user_id = p_user_id AND offer_id = v_offer AND admin_reset_at IS NULL;
  IF v_last IS NOT NULL AND v_today < v_last + public.premium_offer_frequency_days(v_freq) THEN
    RETURN 'ALREADY_SHOWN';
  END IF;
  RETURN 'SHOW';
END $function$;

-- 1️⃣ RESERVA: o servidor escolhe 0 ou 1 oferta para o popup automático, SEM gravar impressão.
CREATE OR REPLACE FUNCTION public.premium_offer_popup_reserve(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_user uuid; v_state jsonb; v_queue jsonb; v_offer text;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  v_state := public.premium_offers_state(p_telegram_id);
  v_queue := COALESCE(v_state->'queue', '[]'::jsonb);
  IF jsonb_array_length(v_queue) = 0 THEN
    RETURN jsonb_build_object('shouldShow', false, 'reason', 'NO_ELIGIBLE_OFFER',
      'dayKey', v_state->>'dayKey');
  END IF;

  v_offer := v_queue->>0;
  RETURN jsonb_build_object(
    'shouldShow', true, 'offerId', v_offer, 'offerCode', v_offer,
    'dayKey', v_state->>'dayKey', 'timezone', v_state->>'timezone',
    'queue', v_queue);
END $function$;

-- 2️⃣ CONFIRMAÇÃO: só depois de o modal montar de verdade. Atômico via unique
-- (user_id, offer_id, impression_date): duas sessões simultâneas, uma única impressão.
CREATE OR REPLACE FUNCTION public.premium_offer_popup_confirm_shown(p_telegram_id bigint, p_offer_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_user uuid; v_offer text := upper(btrim(COALESCE(p_offer_id,'')));
        v_day date := public.premium_offer_day_key(); v_rows integer;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  IF v_offer IN ('CELESTIAL_MYSTERY_PACK','CELESTIAL_SOVEREIGN_PACK') THEN
    INSERT INTO public.premium_offer_impressions(user_id, offer_id, impression_date)
    VALUES (v_user, v_offer, v_day)
    ON CONFLICT (user_id, offer_id, impression_date) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN jsonb_build_object('ok', true, 'offerId', v_offer, 'dayKey', v_day, 'recorded', v_rows > 0);
  END IF;

  PERFORM public.mark_premium_offer_popup_seen(p_telegram_id, v_offer, false);
  RETURN jsonb_build_object('ok', true, 'offerId', v_offer, 'dayKey', v_day, 'recorded', true);
END $function$;

-- 🧪 ADMIN — RESET TODAY POPUP (teste/suporte). Não apaga histórico: marca a impressão do dia
-- como resetada pelo admin, o que a remove apenas da regra de elegibilidade.
CREATE OR REPLACE FUNCTION public.admin_premium_offer_reset_today(p_admin_id bigint, p_query text, p_offer_id text DEFAULT 'CELESTIAL_MYSTERY_PACK'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_player public.game_players; v_offer text := upper(btrim(COALESCE(p_offer_id,'CELESTIAL_MYSTERY_PACK')));
        v_day date := public.premium_offer_day_key(); v_q text := btrim(COALESCE(p_query,''));
        v_impr integer := 0; v_views integer := 0;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_q = '' THEN RAISE EXCEPTION 'PLAYER_QUERY_REQUIRED'; END IF;

  SELECT * INTO v_player FROM public.game_players
   WHERE (v_q ~ '^[0-9]+$' AND telegram_id = v_q::bigint)
      OR lower(COALESCE(username,'')) = lower(ltrim(v_q,'@'))
      OR (v_q ~* '^[0-9a-f-]{36}$' AND id = v_q::uuid)
   ORDER BY updated_at DESC NULLS LAST LIMIT 1;
  IF v_player.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  UPDATE public.premium_offer_impressions
     SET admin_reset_at = now(), admin_reset_by = p_admin_id
   WHERE user_id = v_player.id AND offer_id = v_offer AND impression_date = v_day AND admin_reset_at IS NULL;
  GET DIAGNOSTICS v_impr = ROW_COUNT;

  DELETE FROM public.premium_offer_popup_views
   WHERE user_id = v_player.id AND offer_type = v_offer AND day_key = v_day;
  GET DIAGNOSTICS v_views = ROW_COUNT;

  INSERT INTO public.admin_audit_logs(admin_id, action, target_type, target_id, new_value, reason)
  VALUES (p_admin_id, 'premium_offer_reset_today_popup', 'game_players', v_player.id::text,
          jsonb_build_object('offerId', v_offer, 'dayKey', v_day, 'impressionsReset', v_impr, 'viewsReset', v_views),
          'admin testing tool');

  RETURN jsonb_build_object('ok', true, 'offerId', v_offer, 'dayKey', v_day,
    'player', jsonb_build_object('id', v_player.id, 'telegramId', v_player.telegram_id, 'username', v_player.username),
    'impressionsReset', v_impr, 'viewsReset', v_views,
    'status', public.should_show_premium_offer_popup(v_player.id, v_offer));
END $function$;

-- 🔍 ADMIN — DIAGNÓSTICO DE ELEGIBILIDADE DO POPUP (por que apareceu / por que não apareceu).
CREATE OR REPLACE FUNCTION public.admin_premium_offer_eligibility(p_admin_id bigint, p_query text, p_offer_id text DEFAULT 'CELESTIAL_MYSTERY_PACK'::text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_player public.game_players; v_offer text := upper(btrim(COALESCE(p_offer_id,'CELESTIAL_MYSTERY_PACK')));
        v_day date := public.premium_offer_day_key(); v_q text := btrim(COALESCE(p_query,''));
        c public.celestial_pack_config; s public.sovereign_pack_config;
        m jsonb; v_status text; v_shown boolean; v_priority integer; v_enabled boolean;
        v_popup boolean; v_freq text; v_queue jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO v_player FROM public.game_players
   WHERE (v_q ~ '^[0-9]+$' AND telegram_id = v_q::bigint)
      OR lower(COALESCE(username,'')) = lower(ltrim(v_q,'@'))
      OR (v_q ~* '^[0-9a-f-]{36}$' AND id = v_q::uuid)
   ORDER BY updated_at DESC NULLS LAST LIMIT 1;
  IF v_player.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  IF v_offer = 'CELESTIAL_SOVEREIGN_PACK' THEN
    s := public.sovereign_pack_settings();
    m := public.sovereign_pack_offer_meta(v_player.id);
    v_enabled := COALESCE(s.enabled,false); v_popup := COALESCE(s.popup_enabled,false);
    v_freq := s.popup_frequency; v_priority := s.popup_priority;
  ELSE
    v_offer := 'CELESTIAL_MYSTERY_PACK';
    c := public.celestial_pack_settings();
    m := public.celestial_pack_offer_meta(v_player.id);
    v_enabled := COALESCE(c.enabled,false); v_popup := COALESCE(c.popup_enabled,false);
    v_freq := c.popup_frequency; v_priority := c.popup_priority;
  END IF;

  v_status := public.should_show_premium_offer_popup(v_player.id, v_offer);
  SELECT EXISTS (SELECT 1 FROM public.premium_offer_impressions
                  WHERE user_id = v_player.id AND offer_id = v_offer
                    AND impression_date = v_day AND admin_reset_at IS NULL) INTO v_shown;
  v_queue := COALESCE(public.premium_offers_state(v_player.telegram_id)->'queue', '[]'::jsonb);

  RETURN jsonb_build_object(
    'offerId', v_offer, 'dayKey', v_day,
    'player', jsonb_build_object('id', v_player.id, 'telegramId', v_player.telegram_id,
                                 'username', v_player.username, 'banned', COALESCE(v_player.banned,false)),
    'active', v_enabled, 'popupEnabled', v_popup, 'popupFrequency', v_freq, 'priority', v_priority,
    'windowOpen', (m->>'windowOpen')::boolean,
    'purchased', (m->>'purchased')::boolean,
    'paymentPending', (m->>'processing')::boolean,
    'soldOut', (m->>'soldOut')::boolean,
    'stock', m->'stock',
    'shownToday', v_shown,
    'eligible', v_status = 'SHOW',
    'reason', v_status,
    'queue', v_queue,
    'meta', m);
END $function$;