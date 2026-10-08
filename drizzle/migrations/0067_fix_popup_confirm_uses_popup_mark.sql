-- Corrige a confirmação do popup para usar a função real de registro de exibição.
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

  PERFORM public.premium_offer_popup_mark(p_telegram_id, v_offer, false);
  RETURN jsonb_build_object('ok', true, 'offerId', v_offer, 'dayKey', v_day, 'recorded', true);
END $function$;