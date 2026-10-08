-- LEGENDARY ADVENTURER PACK entra na fila oficial de popups (prioridade 80, abaixo do Vanguard 90).
-- Continua valendo: no maximo 1 popup premium por entrada, 1x por dia por oferta.
CREATE OR REPLACE FUNCTION public.should_show_premium_offer_popup(p_user_id uuid, p_offer_id text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u public.game_players; m jsonb; c public.celestial_pack_config; s public.sovereign_pack_config;
        vg public.vanguard_pack_config; ad public.adventurer_pack_config;
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
  ELSIF v_offer = 'MYTHIC_VANGUARD_PACK' THEN
    vg := public.vanguard_pack_settings();
    IF NOT vg.enabled OR NOT vg.popup_enabled OR upper(vg.popup_frequency) = 'DISABLED' THEN RETURN 'INACTIVE'; END IF;
    m := public.vanguard_pack_offer_meta(p_user_id);
    v_freq := vg.popup_frequency;
  ELSIF v_offer = 'LEGENDARY_ADVENTURER_PACK' THEN
    ad := public.adventurer_pack_settings();
    IF NOT ad.enabled OR NOT ad.popup_enabled OR upper(ad.popup_frequency) = 'DISABLED' THEN RETURN 'INACTIVE'; END IF;
    m := public.adventurer_pack_offer_meta(p_user_id);
    v_freq := ad.popup_frequency;
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

CREATE OR REPLACE FUNCTION public.premium_offer_popup_confirm_shown(p_telegram_id bigint, p_offer_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_user uuid; v_offer text := upper(btrim(COALESCE(p_offer_id,'')));
        v_day date := public.premium_offer_day_key(); v_rows integer;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  IF v_offer IN ('CELESTIAL_MYSTERY_PACK','CELESTIAL_SOVEREIGN_PACK','MYTHIC_VANGUARD_PACK','LEGENDARY_ADVENTURER_PACK') THEN
    INSERT INTO public.premium_offer_impressions(user_id, offer_id, impression_date)
    VALUES (v_user, v_offer, v_day)
    ON CONFLICT (user_id, offer_id, impression_date) DO UPDATE
      SET admin_reset_at = NULL, admin_reset_by = NULL, shown_at = now()
      WHERE public.premium_offer_impressions.admin_reset_at IS NOT NULL;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN jsonb_build_object('ok', true, 'offerId', v_offer, 'dayKey', v_day, 'recorded', v_rows > 0);
  END IF;

  PERFORM public.premium_offer_popup_mark(p_telegram_id, v_offer, false);
  RETURN jsonb_build_object('ok', true, 'offerId', v_offer, 'dayKey', v_day, 'recorded', true);
END $function$;

CREATE OR REPLACE FUNCTION public.premium_offers_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u public.game_players; fc public.founder_pack_config; vc public.veteran_vault_v2_config;
        cc public.celestial_pack_config; sc public.sovereign_pack_config; gc public.vanguard_pack_config;
        ac public.adventurer_pack_config;
        f jsonb; v jsonb; cp jsonb; sp jsonb; vp jsonb; ap jsonb;
        meta jsonb; smeta jsonb; vmeta jsonb; ameta jsonb;
        v_day date := public.premium_offer_day_key();
        v_queue text[] := array[]::text[]; v_f_seen boolean; v_v_seen boolean; v_v_window boolean;
        v_c_status text; v_c_seen boolean; v_s_status text; v_s_seen boolean;
        v_g_status text; v_g_seen boolean; v_a_status text; v_a_seen boolean; v_ranked record;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  fc := public.founder_pack_settings();
  SELECT * INTO vc FROM public.veteran_vault_v2_config WHERE id;
  cc := public.celestial_pack_settings();
  sc := public.sovereign_pack_settings();
  gc := public.vanguard_pack_settings();
  ac := public.adventurer_pack_settings();

  f := public.founder_pack_state(p_telegram_id);
  v := public.veteran_v2_state(p_telegram_id);
  cp := public.celestial_pack_state(p_telegram_id);
  meta := public.celestial_pack_offer_meta(u.id);
  sp := public.sovereign_pack_state(p_telegram_id);
  smeta := public.sovereign_pack_offer_meta(u.id);
  vp := public.vanguard_pack_state(p_telegram_id);
  vmeta := public.vanguard_pack_offer_meta(u.id);
  ap := public.adventurer_pack_state(p_telegram_id);
  ameta := public.adventurer_pack_offer_meta(u.id);

  v_v_window := COALESCE(vc.enabled,false)
                AND now() >= COALESCE(vc.start_at, now())
                AND (vc.ends_at IS NULL OR now() < vc.ends_at);

  SELECT EXISTS (SELECT 1 FROM public.premium_offer_popup_views
                  WHERE user_id = u.id AND offer_type = 'FOUNDER_PACK' AND day_key = v_day) INTO v_f_seen;
  SELECT EXISTS (SELECT 1 FROM public.premium_offer_popup_views
                  WHERE user_id = u.id AND offer_type = 'VETERAN_VAULT' AND day_key = v_day) INTO v_v_seen;

  v_c_status := public.should_show_premium_offer_popup(u.id, 'CELESTIAL_MYSTERY_PACK');
  v_c_seen := v_c_status <> 'SHOW';
  v_s_status := public.should_show_premium_offer_popup(u.id, 'CELESTIAL_SOVEREIGN_PACK');
  v_s_seen := v_s_status <> 'SHOW';
  v_g_status := public.should_show_premium_offer_popup(u.id, 'MYTHIC_VANGUARD_PACK');
  v_g_seen := v_g_status <> 'SHOW';
  v_a_status := public.should_show_premium_offer_popup(u.id, 'LEGENDARY_ADVENTURER_PACK');
  v_a_seen := v_a_status <> 'SHOW';

  FOR v_ranked IN
    SELECT * FROM (
      VALUES
        ('CELESTIAL_SOVEREIGN_PACK', sc.popup_priority, v_s_status = 'SHOW'),
        ('CELESTIAL_MYSTERY_PACK', cc.popup_priority, v_c_status = 'SHOW'),
        ('MYTHIC_VANGUARD_PACK', gc.popup_priority, v_g_status = 'SHOW'),
        ('LEGENDARY_ADVENTURER_PACK', ac.popup_priority, v_a_status = 'SHOW'),
        ('FOUNDER_PACK', fc.popup_priority,
          COALESCE(fc.popup_enabled,false) AND fc.popup_frequency <> 'DISABLED'
          AND COALESCE((f->>'eligible')::boolean,false) AND NOT v_f_seen),
        ('VETERAN_VAULT', vc.popup_priority,
          COALESCE(vc.popup_enabled,false) AND vc.popup_frequency <> 'DISABLED' AND v_v_window
          AND COALESCE((v->>'eligible')::boolean,false) AND NOT v_v_seen)
    ) AS t(offer, priority, ok)
    WHERE t.ok ORDER BY t.priority DESC, t.offer
  LOOP
    v_queue := array_append(v_queue, v_ranked.offer);
  END LOOP;

  RETURN jsonb_build_object(
    'dayKey', v_day,
    'timezone', public.premium_offer_timezone(),
    'queue', to_jsonb(v_queue),
    'founder', f || jsonb_build_object('popupSeenToday', v_f_seen, 'popupFrequency', fc.popup_frequency,
                                       'popupPriority', fc.popup_priority),
    'veteran', v || jsonb_build_object('popupSeenToday', v_v_seen, 'popupFrequency', vc.popup_frequency,
                                       'startAt', vc.start_at, 'endsAt', vc.ends_at,
                                       'popupPriority', vc.popup_priority,
                                       'windowOpen', v_v_window),
    'celestial', cp || meta || jsonb_build_object('popupSeenToday', v_c_seen, 'popupStatus', v_c_status),
    'sovereign', sp || smeta || jsonb_build_object('popupSeenToday', v_s_seen, 'popupStatus', v_s_status),
    'vanguard', vp || vmeta || jsonb_build_object('popupSeenToday', v_g_seen, 'popupStatus', v_g_status),
    'adventurer', ap || ameta || jsonb_build_object('popupSeenToday', v_a_seen, 'popupStatus', v_a_status));
END $function$;