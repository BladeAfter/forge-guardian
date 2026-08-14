CREATE OR REPLACE FUNCTION public.get_activity_progress(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RETURN jsonb_build_object('activities', '[]'::jsonb); END IF;
  RETURN public.activity_daily_progress(v_user);
END; $$;

REVOKE ALL ON FUNCTION public.get_activity_progress(bigint) FROM PUBLIC, anon, authenticated;