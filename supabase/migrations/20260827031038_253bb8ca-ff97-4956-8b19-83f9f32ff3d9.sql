-- ═══ CLAN TREASURY CONTRIBUTION HISTORY (read-only aggregation, economy untouched) ═══
-- Source of truth: public.clan_treasury_ledger (real donation ledger, per asset).
-- Reversals are stored as negative CLAN_DONATION_* rows, so plain SUM() nets them out.

CREATE INDEX IF NOT EXISTS idx_ctl_clan_user_asset_created
  ON public.clan_treasury_ledger (clan_id, user_id, asset, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ctl_clan_reason_created
  ON public.clan_treasury_ledger (clan_id, reason, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ccl_clan_user_day
  ON public.clan_contribution_ledger (clan_id, user_id, game_day);

-- Only settled donations count. PENDING/FAILED/CANCELLED variants are excluded by name.
CREATE OR REPLACE FUNCTION public.clan_donation_reason_valid(p_reason text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p_reason LIKE 'CLAN_DONATION%'
     AND p_reason NOT IN ('CLAN_DONATION_PENDING','CLAN_DONATION_FAILED','CLAN_DONATION_CANCELLED')
$$;

-- Window start for a period, aligned to the official game day / game week.
CREATE OR REPLACE FUNCTION public.clan_period_start(p_period text)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE lower(coalesce(p_period,'week'))
           WHEN 'today' THEN public.game_day_start()
           WHEN 'week'  THEN public.game_day_start(public.clan_week_key())
           ELSE '-infinity'::timestamptz
         END
$$;

-- ══ RANKING: per-member FC / MYTH donated + contribution points, for one period ══
CREATE OR REPLACE FUNCTION public.clan_contribution_summary(p_telegram_id bigint, p_period text DEFAULT 'week')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid; v_clan uuid; v_period text; v_since timestamptz;
        v_day date; v_cycle uuid; v_rows jsonb;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;

  v_period := lower(coalesce(p_period,'week'));
  IF v_period NOT IN ('today','week','total') THEN v_period := 'week'; END IF;
  v_since := public.clan_period_start(v_period);
  v_day := public.game_day_key();
  SELECT id INTO v_cycle FROM public.clan_weekly_cycles
   WHERE clan_id = v_clan AND week_key = public.clan_week_key();

  WITH donations AS (
    SELECT l.user_id, l.asset, l.amount, l.created_at
      FROM public.clan_treasury_ledger l
     WHERE l.clan_id = v_clan
       AND public.clan_donation_reason_valid(l.reason)
       AND (v_period = 'total' OR l.created_at >= v_since)
  ), agg AS (
    SELECT user_id,
           COALESCE(SUM(amount) FILTER (WHERE asset = 'FC'), 0)   AS fc,
           COALESCE(SUM(amount) FILTER (WHERE asset = 'MYTH'), 0) AS myth,
           COUNT(*) FILTER (WHERE amount > 0)                     AS donations,
           MAX(created_at)                                        AS last_at
      FROM donations GROUP BY user_id
  ), points AS (
    SELECT cl.user_id, COALESCE(SUM(cl.amount), 0) AS pts
      FROM public.clan_contribution_ledger cl
     WHERE cl.clan_id = v_clan
       AND (v_period = 'total'
            OR (v_period = 'today' AND cl.game_day = v_day)
            OR (v_period = 'week'  AND cl.cycle_id = v_cycle))
     GROUP BY cl.user_id
  )
  SELECT COALESCE(jsonb_agg(x ORDER BY x.points DESC, x.fc DESC, x.myth DESC), '[]'::jsonb) INTO v_rows
    FROM (
      SELECT m.user_id AS "userId", g.username, m.role,
             COALESCE(a.fc, 0)::numeric        AS fc,
             COALESCE(a.myth, 0)::numeric      AS myth,
             COALESCE(p.pts, 0)::bigint        AS points,
             COALESCE(a.donations, 0)::int     AS "donationCount",
             a.last_at                         AS "lastDonationAt"
        FROM public.clan_members m
        JOIN public.game_players g ON g.id = m.user_id
        LEFT JOIN agg a ON a.user_id = m.user_id
        LEFT JOIN points p ON p.user_id = m.user_id
       WHERE m.clan_id = v_clan
    ) x;

  RETURN jsonb_build_object(
    'inClan', true, 'period', v_period, 'gameDay', v_day,
    'nextResetAt', public.game_day_start(v_day + 1),
    'members', v_rows,
    'me', public.clan_contribution_detail(p_telegram_id, v_uid) -> 'totals'
  );
END $$;

-- ══ DETAIL: today / week / all-time split per asset for one member ══
CREATE OR REPLACE FUNCTION public.clan_contribution_detail(p_telegram_id bigint, p_target uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid; v_clan uuid; v_target uuid; v_target_clan uuid;
        v_day date; v_cycle uuid; v_week timestamptz; v_today timestamptz;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;
  v_target := COALESCE(p_target, v_uid);
  SELECT clan_id INTO v_target_clan FROM public.clan_members WHERE user_id = v_target;
  IF v_target_clan IS DISTINCT FROM v_clan THEN RAISE EXCEPTION 'NOT_SAME_CLAN'; END IF;

  v_day := public.game_day_key();
  v_today := public.game_day_start(v_day);
  v_week := public.game_day_start(public.clan_week_key());
  SELECT id INTO v_cycle FROM public.clan_weekly_cycles
   WHERE clan_id = v_clan AND week_key = public.clan_week_key();

  RETURN (
    WITH d AS (
      SELECT l.asset, l.amount, l.created_at
        FROM public.clan_treasury_ledger l
       WHERE l.clan_id = v_clan AND l.user_id = v_target
         AND public.clan_donation_reason_valid(l.reason)
    )
    SELECT jsonb_build_object(
      'inClan', true,
      'userId', v_target,
      'username', (SELECT username FROM public.game_players WHERE id = v_target),
      'totals', jsonb_build_object(
        'today', jsonb_build_object(
          'fc',   COALESCE((SELECT SUM(amount) FROM d WHERE asset='FC'   AND created_at >= v_today), 0),
          'myth', COALESCE((SELECT SUM(amount) FROM d WHERE asset='MYTH' AND created_at >= v_today), 0),
          'points', COALESCE((SELECT SUM(amount) FROM public.clan_contribution_ledger
                               WHERE clan_id=v_clan AND user_id=v_target AND game_day=v_day), 0)),
        'week', jsonb_build_object(
          'fc',   COALESCE((SELECT SUM(amount) FROM d WHERE asset='FC'   AND created_at >= v_week), 0),
          'myth', COALESCE((SELECT SUM(amount) FROM d WHERE asset='MYTH' AND created_at >= v_week), 0),
          'points', COALESCE((SELECT contribution FROM public.clan_weekly_member_progress
                               WHERE cycle_id=v_cycle AND user_id=v_target), 0)),
        'total', jsonb_build_object(
          'fc',   COALESCE((SELECT SUM(amount) FROM d WHERE asset='FC'), 0),
          'myth', COALESCE((SELECT SUM(amount) FROM d WHERE asset='MYTH'), 0),
          'points', COALESCE((SELECT SUM(amount) FROM public.clan_contribution_ledger
                               WHERE clan_id=v_clan AND user_id=v_target), 0))
      ),
      'donationCount', (SELECT COUNT(*) FROM d WHERE amount > 0),
      'lastDonationAt', (SELECT MAX(created_at) FROM d)
    )
  );
END $$;

-- ══ HISTORY: real ledger rows, newest first ══
CREATE OR REPLACE FUNCTION public.clan_contribution_history(p_telegram_id bigint, p_target uuid DEFAULT NULL, p_limit int DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid; v_clan uuid; v_target uuid; v_target_clan uuid; v_limit int;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;
  v_target := COALESCE(p_target, v_uid);
  SELECT clan_id INTO v_target_clan FROM public.clan_members WHERE user_id = v_target;
  IF v_target_clan IS DISTINCT FROM v_clan THEN RAISE EXCEPTION 'NOT_SAME_CLAN'; END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);

  RETURN jsonb_build_object(
    'inClan', true, 'userId', v_target,
    'username', (SELECT username FROM public.game_players WHERE id = v_target),
    'entries', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', l.id, 'asset', l.asset, 'amount', l.amount,
               'reason', l.reason, 'createdAt', l.created_at,
               'reversed', l.amount < 0) ORDER BY l.created_at DESC)
        FROM (SELECT * FROM public.clan_treasury_ledger
               WHERE clan_id = v_clan AND user_id = v_target
                 AND public.clan_donation_reason_valid(reason)
               ORDER BY created_at DESC LIMIT v_limit) l
    ), '[]'::jsonb)
  );
END $$;

REVOKE ALL ON FUNCTION public.clan_contribution_summary(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_contribution_detail(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clan_contribution_history(bigint, uuid, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_contribution_summary(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_contribution_detail(bigint, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.clan_contribution_history(bigint, uuid, int) TO service_role;