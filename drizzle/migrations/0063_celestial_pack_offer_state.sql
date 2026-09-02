DROP FUNCTION IF EXISTS public._probe_premium_offers(bigint);

-- Estado da oferta para o cliente: state do pacote + metadados de janela/estoque/limite/popup.
CREATE OR REPLACE FUNCTION public.celestial_pack_offer_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN public.celestial_pack_state(p_telegram_id) || public.celestial_pack_offer_meta(v_user);
END $$;