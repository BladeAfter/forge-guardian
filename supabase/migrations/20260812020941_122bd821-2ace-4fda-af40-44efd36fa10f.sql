CREATE TABLE IF NOT EXISTS public.spending_event_popup_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.spending_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  times_seen integer NOT NULL DEFAULT 0,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, user_id)
);

GRANT ALL ON public.spending_event_popup_views TO service_role;

ALTER TABLE public.spending_event_popup_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service role manages spending popup views" ON public.spending_event_popup_views;
CREATE POLICY "service role manages spending popup views"
  ON public.spending_event_popup_views FOR ALL TO service_role
  USING (true) WITH CHECK (true);

CREATE TRIGGER spending_event_popup_views_touch
  BEFORE UPDATE ON public.spending_event_popup_views
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.game_settings (key, value)
VALUES ('spending_event_popup', '{"enabled": true, "frequency": "daily"}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Popup payload: never blocks anything, purely informational.
CREATE OR REPLACE FUNCTION public.get_spending_event_popup(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  ev public.spending_events;
  v_cfg jsonb;
  v_enabled boolean;
  v_freq text;
  v_uid uuid;
  v_view public.spending_event_popup_views;
  v_points numeric := 0; v_fc numeric := 0; v_ton numeric := 0;
  v_pos integer; v_reward text; v_participants integer := 0;
BEGIN
  SELECT COALESCE(value, '{}'::jsonb) INTO v_cfg FROM public.game_settings WHERE key = 'spending_event_popup';
  v_enabled := COALESCE((v_cfg->>'enabled')::boolean, true);
  v_freq := COALESCE(NULLIF(v_cfg->>'frequency',''), 'daily');
  IF NOT v_enabled THEN
    RETURN jsonb_build_object('show', false, 'reason', 'disabled');
  END IF;

  SELECT * INTO ev FROM public.active_spending_event();
  IF ev.id IS NULL OR ev.status <> 'active' THEN
    RETURN jsonb_build_object('show', false, 'reason', 'no_active_event');
  END IF;

  SELECT id INTO v_uid FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('show', false, 'reason', 'no_player');
  END IF;

  SELECT * INTO v_view FROM public.spending_event_popup_views WHERE event_id = ev.id AND user_id = v_uid;

  IF v_view.id IS NOT NULL THEN
    IF v_freq = 'event' THEN
      RETURN jsonb_build_object('show', false, 'reason', 'already_seen');
    END IF;
    IF (v_view.last_seen_at AT TIME ZONE 'UTC')::date = (now() AT TIME ZONE 'UTC')::date THEN
      RETURN jsonb_build_object('show', false, 'reason', 'seen_today');
    END IF;
  END IF;

  SELECT COALESCE(SUM(spending_points), 0),
         COALESCE(SUM(CASE WHEN currency = 'FC' THEN original_amount ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN currency = 'TON' THEN original_amount ELSE 0 END), 0)
    INTO v_points, v_fc, v_ton
    FROM public.spending_event_entries WHERE event_id = ev.id AND user_id = v_uid;

  SELECT COUNT(*) INTO v_participants FROM (
    SELECT user_id FROM public.spending_event_entries WHERE event_id = ev.id
    GROUP BY user_id HAVING COALESCE(SUM(spending_points), 0) > 0
  ) participants;

  IF v_points > 0 THEN
    SELECT COUNT(*) + 1 INTO v_pos FROM (
      SELECT user_id, COALESCE(SUM(spending_points), 0) AS pts
      FROM public.spending_event_entries WHERE event_id = ev.id
      GROUP BY user_id
    ) totals WHERE totals.pts > v_points;

    SELECT label INTO v_reward FROM public.spending_event_rewards
     WHERE (event_id = ev.id OR event_id IS NULL)
       AND v_pos BETWEEN position_from AND position_to
     ORDER BY (event_id IS NULL), position_from LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'show', true,
    'firstTime', v_view.id IS NULL,
    'frequency', v_freq,
    'event', jsonb_build_object(
      'id', ev.id, 'name', ev.name, 'status', ev.status,
      'startsAt', ev.starts_at, 'endsAt', ev.ends_at, 'topLimit', ev.top_limit
    ),
    'player', jsonb_build_object(
      'points', round(v_points), 'fcSpent', round(v_fc), 'tonSpent', v_ton,
      'position', v_pos, 'estimatedReward', v_reward
    ),
    'totals', jsonb_build_object('participants', v_participants),
    'serverTime', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_spending_event_popup_seen(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE ev public.spending_events; v_uid uuid;
BEGIN
  SELECT * INTO ev FROM public.active_spending_event();
  IF ev.id IS NULL THEN RETURN jsonb_build_object('ok', false); END IF;
  SELECT id INTO v_uid FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false); END IF;

  INSERT INTO public.spending_event_popup_views (event_id, user_id, times_seen, first_seen_at, last_seen_at)
  VALUES (ev.id, v_uid, 1, now(), now())
  ON CONFLICT (event_id, user_id) DO UPDATE
    SET times_seen = public.spending_event_popup_views.times_seen + 1,
        last_seen_at = now();

  RETURN jsonb_build_object('ok', true, 'eventId', ev.id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_popup_config(
  p_admin_id bigint,
  p_enabled boolean DEFAULT NULL,
  p_frequency text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(value, '{"enabled": true, "frequency": "daily"}'::jsonb) INTO v_old
    FROM public.game_settings WHERE key = 'spending_event_popup';
  v_old := COALESCE(v_old, '{"enabled": true, "frequency": "daily"}'::jsonb);
  v_new := v_old;

  IF p_enabled IS NOT NULL THEN
    v_new := jsonb_set(v_new, '{enabled}', to_jsonb(p_enabled), true);
  END IF;
  IF p_frequency IS NOT NULL THEN
    IF p_frequency NOT IN ('daily', 'event') THEN RAISE EXCEPTION 'invalid_frequency'; END IF;
    v_new := jsonb_set(v_new, '{frequency}', to_jsonb(p_frequency), true);
  END IF;

  INSERT INTO public.game_settings (key, value) VALUES ('spending_event_popup', v_new)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  IF v_new <> v_old THEN
    PERFORM public.admin_log(p_admin_id, 'spending_event_popup_config', 'settings', 'spending_event_popup', v_old, v_new, NULL, '{}'::jsonb);
  END IF;

  RETURN jsonb_build_object('config', v_new);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_spending_event_popup(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_spending_event_popup_seen(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_spending_event_popup_config(bigint, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_spending_event_popup(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_spending_event_popup_seen(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_popup_config(bigint, boolean, text) TO service_role;