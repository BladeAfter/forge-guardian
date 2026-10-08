CREATE TABLE public.user_campaign_popup (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  campaign_id text NOT NULL,
  shown_at timestamptz,
  dismissed_at timestamptz,
  clicked_join_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, campaign_id)
);

GRANT ALL ON public.user_campaign_popup TO service_role;
ALTER TABLE public.user_campaign_popup ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Campaign popup state is server-side only" ON public.user_campaign_popup FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TRIGGER update_user_campaign_popup_updated_at
BEFORE UPDATE ON public.user_campaign_popup
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Campaign popup state. The popup shows ONCE per (player, campaign_id): changing
-- giveaway_popup_campaign_id in game_settings starts a brand new campaign for everyone.
CREATE OR REPLACE FUNCTION public.get_campaign_popup(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_enabled boolean;
  v_campaign text;
  v_url text;
  v_seen boolean := false;
BEGIN
  SELECT COALESCE((value #>> '{}')::boolean, true) INTO v_enabled FROM public.game_settings WHERE key = 'giveaway_popup_enabled';
  v_enabled := COALESCE(v_enabled, true);
  SELECT NULLIF(value #>> '{}', '') INTO v_campaign FROM public.game_settings WHERE key = 'giveaway_popup_campaign_id';
  SELECT NULLIF(value #>> '{}', '') INTO v_url FROM public.game_settings WHERE key = 'giveaway_popup_group_url';
  v_campaign := COALESCE(v_campaign, 'mythreon_giveaway_aug2026');
  v_url := COALESCE(v_url, 'https://t.me/+sy4Y6cd7cuIyNmEx');

  IF NOT v_enabled THEN
    RETURN jsonb_build_object('show', false, 'reason', 'disabled');
  END IF;

  SELECT id INTO v_uid FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('show', false, 'reason', 'no_player');
  END IF;

  SELECT true INTO v_seen FROM public.user_campaign_popup
   WHERE user_id = v_uid AND campaign_id = v_campaign
     AND (shown_at IS NOT NULL OR dismissed_at IS NOT NULL OR clicked_join_at IS NOT NULL);

  RETURN jsonb_build_object(
    'show', NOT COALESCE(v_seen, false),
    'campaignId', v_campaign,
    'groupUrl', v_url,
    'reason', CASE WHEN COALESCE(v_seen, false) THEN 'already_seen' ELSE 'ok' END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_campaign_popup(p_telegram_id bigint, p_campaign_id text, p_action text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_campaign text := NULLIF(btrim(p_campaign_id), '');
BEGIN
  IF v_campaign IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_campaign');
  END IF;
  SELECT id INTO v_uid FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_player');
  END IF;

  INSERT INTO public.user_campaign_popup (user_id, campaign_id, shown_at, dismissed_at, clicked_join_at)
  VALUES (
    v_uid, v_campaign,
    now(),
    CASE WHEN p_action = 'dismiss' THEN now() ELSE NULL END,
    CASE WHEN p_action = 'join' THEN now() ELSE NULL END
  )
  ON CONFLICT (user_id, campaign_id) DO UPDATE SET
    shown_at = COALESCE(public.user_campaign_popup.shown_at, now()),
    dismissed_at = CASE WHEN p_action = 'dismiss' THEN COALESCE(public.user_campaign_popup.dismissed_at, now()) ELSE public.user_campaign_popup.dismissed_at END,
    clicked_join_at = CASE WHEN p_action = 'join' THEN COALESCE(public.user_campaign_popup.clicked_join_at, now()) ELSE public.user_campaign_popup.clicked_join_at END;

  RETURN jsonb_build_object('ok', true, 'campaignId', v_campaign);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_campaign_popup(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_campaign_popup(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_campaign_popup(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_campaign_popup(bigint, text, text) TO service_role;