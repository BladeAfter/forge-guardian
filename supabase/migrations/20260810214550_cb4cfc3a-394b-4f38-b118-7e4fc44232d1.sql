-- 1) Notifications: unique key per commission event so login never re-creates the same notice
ALTER TABLE public.player_notifications ADD COLUMN IF NOT EXISTS dedupe_key text;
CREATE UNIQUE INDEX IF NOT EXISTS player_notifications_dedupe_idx
  ON public.player_notifications (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL;

-- 2) Server-side mark-as-read (identity always resolved from the validated telegram id)
CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_telegram_id bigint, p_ids uuid[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_user uuid; v_count integer := 0;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RETURN jsonb_build_object('updated', 0); END IF;
  UPDATE public.player_notifications
     SET read_at = now()
   WHERE user_id = v_user
     AND read_at IS NULL
     AND (p_ids IS NULL OR id = ANY(p_ids));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('updated', v_count, 'profileId', v_user);
END; $$;

REVOKE ALL ON FUNCTION public.mark_notifications_read(bigint, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(bigint, uuid[]) TO service_role;

-- 3) Referral dashboard only returns UNREAD notifications for the signed-in player
CREATE OR REPLACE FUNCTION public.get_referral_dashboard(p_telegram_id bigint, p_level integer DEFAULT NULL, p_offset integer DEFAULT 0, p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_base jsonb;
BEGIN
  v_base := public.get_referral_dashboard_base(p_telegram_id, p_level, p_offset, p_limit);
  RETURN v_base;
END; $$;
