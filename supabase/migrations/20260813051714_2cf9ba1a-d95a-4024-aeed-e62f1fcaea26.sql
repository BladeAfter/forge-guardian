CREATE OR REPLACE FUNCTION public.get_ad_rewards(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object('ads', public.ad_rewards_state(v_id));
END $$;

REVOKE ALL ON FUNCTION public.get_ad_rewards(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ad_rewards(bigint) TO service_role;