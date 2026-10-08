-- 1. Official start/end mirrors
ALTER TABLE public.special_events
  ADD COLUMN IF NOT EXISTS event_start_at timestamptz GENERATED ALWAYS AS (starts_at) STORED,
  ADD COLUMN IF NOT EXISTS event_end_at timestamptz GENERATED ALWAYS AS (ends_at) STORED;

-- 2. Per-event referral ledger
CREATE TABLE IF NOT EXISTS public.referral_event_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.special_events(id) ON DELETE CASCADE,
  referrer_user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  referred_user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  referred_at timestamptz NOT NULL DEFAULT now(),
  is_valid boolean NOT NULL DEFAULT true,
  invalid_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referral_event_entries_unique UNIQUE (event_id, referred_user_id),
  CONSTRAINT referral_event_entries_distinct CHECK (referrer_user_id <> referred_user_id)
);

CREATE INDEX IF NOT EXISTS idx_ref_event_entries_event_referrer
  ON public.referral_event_entries(event_id, referrer_user_id);

GRANT SELECT ON public.referral_event_entries TO authenticated;
GRANT ALL ON public.referral_event_entries TO service_role;
ALTER TABLE public.referral_event_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "no direct client writes on referral event entries"
  ON public.referral_event_entries FOR SELECT TO authenticated USING (false);

-- 3. Trigger: register new referrals into every running event
CREATE OR REPLACE FUNCTION public.referral_event_capture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE e record; v_reason text; v_valid boolean; v_invited public.game_players%rowtype;
BEGIN
  IF NEW.level <> 1 THEN RETURN NEW; END IF;
  SELECT * INTO v_invited FROM public.game_players WHERE id = NEW.user_id;

  FOR e IN
    SELECT id, starts_at, ends_at FROM public.special_events
    WHERE type = 'referral_ranking'
      AND status IN ('active','scheduled')
      AND NEW.created_at >= starts_at
      AND NEW.created_at <= ends_at
  LOOP
    v_valid := true; v_reason := NULL;
    IF v_invited.id IS NULL OR v_invited.telegram_id IS NULL THEN
      v_valid := false; v_reason := 'invited_player_missing';
    ELSIF v_invited.created_at < e.starts_at THEN
      v_valid := false; v_reason := 'account_created_before_event';
    END IF;

    INSERT INTO public.referral_event_entries
      (event_id, referrer_user_id, referred_user_id, referred_at, is_valid, invalid_reason)
    VALUES (e.id, NEW.inviter_id, NEW.user_id, NEW.created_at, v_valid, v_reason)
    ON CONFLICT (event_id, referred_user_id) DO NOTHING;
  END LOOP;

  RETURN NEW;
END; $$;

REVOKE ALL ON FUNCTION public.referral_event_capture() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_referral_event_capture ON public.referrals;
CREATE TRIGGER trg_referral_event_capture
AFTER INSERT ON public.referrals
FOR EACH ROW EXECUTE FUNCTION public.referral_event_capture();

-- 4. Ranking strictly from the event ledger
CREATE OR REPLACE FUNCTION public.event_referral_ranking(p_event_id uuid, p_limit integer DEFAULT 100)
RETURNS TABLE(user_id uuid, name text, username text, avatar_url text, valid_referrals bigint, rank_no bigint)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE e public.special_events%rowtype; v_min_quests integer;
BEGIN
  SELECT * INTO e FROM public.special_events WHERE id = p_event_id;
  IF e.id IS NULL THEN RETURN; END IF;
  v_min_quests := GREATEST(0, COALESCE((e.rules_json->>'minDailyQuests')::int, 1));

  RETURN QUERY
  WITH valid AS (
    SELECT en.referrer_user_id AS uid
    FROM public.referral_event_entries en
    JOIN public.game_players invited ON invited.id = en.referred_user_id
    JOIN public.game_players inviter ON inviter.id = en.referrer_user_id
    WHERE en.event_id = e.id
      AND en.is_valid = true
      AND en.referred_at >= e.starts_at
      AND en.referred_at <= LEAST(e.ends_at, now())
      AND invited.created_at >= e.starts_at
      AND invited.telegram_id IS NOT NULL
      AND inviter.telegram_id IS NOT NULL
      AND invited.telegram_id <> inviter.telegram_id
      AND COALESCE(invited.banned, false) = false
      AND COALESCE(inviter.banned, false) = false
      AND (
        v_min_quests = 0 OR (
          SELECT count(*) FROM public.player_quest_progress q
          WHERE q.user_id = invited.id AND q.completed_at IS NOT NULL
        ) >= v_min_quests
      )
  ), agg AS (
    SELECT uid, count(*)::bigint AS total FROM valid GROUP BY uid
  )
  SELECT a.uid,
         COALESCE(NULLIF(g.display_name,''), NULLIF(g.first_name,''), NULLIF(g.username,''), 'Warrior')::text,
         g.username, g.avatar_url, a.total,
         ROW_NUMBER() OVER (ORDER BY a.total DESC, g.created_at ASC, a.uid)
  FROM agg a JOIN public.game_players g ON g.id = a.uid
  WHERE a.total > 0
  ORDER BY a.total DESC, g.created_at ASC, a.uid
  LIMIT GREATEST(1, COALESCE(p_limit, 100));
END; $$;

REVOKE ALL ON FUNCTION public.event_referral_ranking(uuid, integer) FROM PUBLIC, anon, authenticated;

-- 5. Restart the running championship from now: everyone begins at 0 valid invites
UPDATE public.special_events
SET starts_at = now(),
    ends_at = GREATEST(ends_at, now() + interval '30 days')
WHERE status = 'active' AND type = 'referral_ranking';

DELETE FROM public.referral_event_entries en
USING public.special_events e
WHERE en.event_id = e.id AND en.referred_at < e.starts_at;