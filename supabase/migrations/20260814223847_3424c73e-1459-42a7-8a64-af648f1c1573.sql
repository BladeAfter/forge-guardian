-- ============================================================================
-- MYTHREON :: ANTI-FAKE / ANTI-MULTIACCOUNT
-- Up to 3 distinct Telegram accounts per device. 4th+ => access blocked (never banned).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.device_registry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_hash text NOT NULL UNIQUE,
  platform text,
  user_agent_hash text,
  last_ip_hash text,
  risk_status text NOT NULL DEFAULT 'ok',      -- ok | blocked | allowlisted
  risk_score integer NOT NULL DEFAULT 0,
  seen_count bigint NOT NULL DEFAULT 0,
  notes text,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.device_registry TO service_role;
ALTER TABLE public.device_registry ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.device_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_hash text NOT NULL,
  telegram_id bigint NOT NULL,
  player_id uuid,
  slot integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'allowed',      -- allowed | blocked
  admin_bypass boolean NOT NULL DEFAULT false,
  sessions bigint NOT NULL DEFAULT 1,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT device_accounts_unique UNIQUE (device_hash, telegram_id)
);
CREATE INDEX IF NOT EXISTS device_accounts_telegram_idx ON public.device_accounts(telegram_id);
CREATE INDEX IF NOT EXISTS device_accounts_device_idx ON public.device_accounts(device_hash);
GRANT ALL ON public.device_accounts TO service_role;
ALTER TABLE public.device_accounts ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.device_allowlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  telegram_id bigint,
  device_hash text,
  reason text,
  created_by bigint,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS device_allowlist_tg_idx ON public.device_allowlist(telegram_id) WHERE telegram_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS device_allowlist_device_idx ON public.device_allowlist(device_hash) WHERE device_hash IS NOT NULL;
GRANT ALL ON public.device_allowlist TO service_role;
ALTER TABLE public.device_allowlist ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.device_review_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  telegram_id bigint NOT NULL,
  device_hash text NOT NULL,
  message text,
  status text NOT NULL DEFAULT 'pending',       -- pending | approved | rejected
  reviewed_by bigint,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS device_review_status_idx ON public.device_review_requests(status, created_at DESC);
GRANT ALL ON public.device_review_requests TO service_role;
ALTER TABLE public.device_review_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.anti_fake_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event text NOT NULL,
  device_hash text,
  telegram_id bigint,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS anti_fake_logs_event_idx ON public.anti_fake_logs(event, created_at DESC);
GRANT ALL ON public.anti_fake_logs TO service_role;
ALTER TABLE public.anti_fake_logs ENABLE ROW LEVEL SECURITY;

INSERT INTO public.game_settings(key, value, category, label)
VALUES ('anti_fake', jsonb_build_object('enabled', true, 'max_accounts_per_device', 3), 'security', 'Anti-fake / multiconta')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------- helpers
CREATE OR REPLACE FUNCTION public.anti_fake_log(p_event text, p_device_hash text, p_telegram_id bigint, p_metadata jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.anti_fake_logs(event, device_hash, telegram_id, metadata)
  VALUES (upper(p_event), p_device_hash, p_telegram_id, coalesce(p_metadata, '{}'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.anti_fake_max_accounts()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT greatest(1, coalesce((SELECT (value->>'max_accounts_per_device')::int FROM public.game_settings WHERE key = 'anti_fake'), 3));
$$;

/**
 * Boot gate. Atomic per device (advisory lock) so simultaneous 4th/5th accounts
 * can never both win a slot. Never bans, never deletes, never touches balances.
 */
CREATE OR REPLACE FUNCTION public.check_device_access(
  p_telegram_id bigint,
  p_device_hash text,
  p_platform text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hash text := nullif(btrim(coalesce(p_device_hash, '')), '');
  v_limit int := public.anti_fake_max_accounts();
  v_enabled boolean := coalesce((SELECT (value->>'enabled')::boolean FROM public.game_settings WHERE key = 'anti_fake'), true);
  v_admin bigint := public.admin_super_id();
  v_player uuid;
  v_row public.device_accounts;
  v_registry public.device_registry;
  v_distinct int;
  v_slot int;
  v_status text;
  v_access text;
  v_allowlisted boolean;
  v_is_admin boolean := p_telegram_id = v_admin;
BEGIN
  IF p_telegram_id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  -- No device signal (or protection off): never lock a player out because of a missing signal.
  IF v_hash IS NULL OR NOT v_enabled THEN
    RETURN jsonb_build_object('access', 'allowed', 'status', 'unknown_device', 'reason', NULL, 'limit', v_limit);
  END IF;

  SELECT id INTO v_player FROM public.game_players WHERE telegram_id = p_telegram_id;

  PERFORM pg_advisory_xact_lock(hashtextextended('anti_fake_device:' || v_hash, 0));

  INSERT INTO public.device_registry(device_hash, platform, user_agent_hash, last_ip_hash, seen_count)
  VALUES (v_hash, nullif(btrim(coalesce(p_platform, '')), ''), nullif(p_metadata->>'uaHash', ''), nullif(p_metadata->>'ipHash', ''), 1)
  ON CONFLICT (device_hash) DO UPDATE
    SET last_seen_at = now(), updated_at = now(), seen_count = public.device_registry.seen_count + 1,
        platform = coalesce(nullif(btrim(coalesce(p_platform, '')), ''), public.device_registry.platform),
        user_agent_hash = coalesce(nullif(p_metadata->>'uaHash', ''), public.device_registry.user_agent_hash),
        last_ip_hash = coalesce(nullif(p_metadata->>'ipHash', ''), public.device_registry.last_ip_hash)
  RETURNING * INTO v_registry;

  PERFORM public.anti_fake_log('ANTI_FAKE_DEVICE_SEEN', v_hash, p_telegram_id, jsonb_build_object('platform', v_registry.platform));

  SELECT EXISTS (
    SELECT 1 FROM public.device_allowlist
    WHERE (telegram_id IS NOT NULL AND telegram_id = p_telegram_id)
       OR (device_hash IS NOT NULL AND device_hash = v_hash)
  ) INTO v_allowlisted;

  SELECT * INTO v_row FROM public.device_accounts WHERE device_hash = v_hash AND telegram_id = p_telegram_id;

  IF v_row.id IS NULL THEN
    -- Distinct accounts only: repeated logins of the same Telegram ID never consume a new slot.
    SELECT count(*) INTO v_distinct FROM public.device_accounts WHERE device_hash = v_hash;
    v_slot := v_distinct + 1;
    v_status := CASE
      WHEN v_is_admin OR v_allowlisted OR v_registry.risk_status = 'allowlisted' THEN 'allowed'
      WHEN v_slot > v_limit THEN 'blocked'
      ELSE 'allowed' END;
    INSERT INTO public.device_accounts(device_hash, telegram_id, player_id, slot, status, admin_bypass)
    VALUES (v_hash, p_telegram_id, v_player, v_slot, v_status, v_is_admin AND v_slot > v_limit)
    ON CONFLICT (device_hash, telegram_id) DO UPDATE
      SET last_seen_at = now(), updated_at = now(), sessions = public.device_accounts.sessions + 1
    RETURNING * INTO v_row;
    PERFORM public.anti_fake_log('ANTI_FAKE_ACCOUNT_LINKED', v_hash, p_telegram_id, jsonb_build_object('slot', v_row.slot, 'status', v_row.status));
    IF v_slot > v_limit THEN
      PERFORM public.anti_fake_log('ANTI_FAKE_LIMIT_REACHED', v_hash, p_telegram_id, jsonb_build_object('slot', v_slot, 'limit', v_limit));
      UPDATE public.device_registry SET risk_score = least(100, risk_score + 25), updated_at = now() WHERE device_hash = v_hash;
    END IF;
  ELSE
    UPDATE public.device_accounts
       SET last_seen_at = now(), updated_at = now(), sessions = sessions + 1,
           player_id = coalesce(v_player, player_id),
           status = CASE WHEN v_is_admin OR v_allowlisted THEN 'allowed' ELSE status END,
           admin_bypass = admin_bypass OR (v_is_admin AND status = 'blocked')
     WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  SELECT count(*) INTO v_distinct FROM public.device_accounts WHERE device_hash = v_hash;

  IF v_is_admin AND v_row.status = 'blocked' THEN
    UPDATE public.device_accounts SET status = 'allowed', admin_bypass = true, updated_at = now() WHERE id = v_row.id RETURNING * INTO v_row;
  END IF;

  v_access := CASE
    WHEN v_allowlisted OR v_registry.risk_status = 'allowlisted' THEN 'allowlisted'
    WHEN v_row.admin_bypass THEN 'admin_bypass'
    WHEN v_row.status = 'blocked' THEN 'blocked'
    ELSE 'allowed' END;

  IF v_access = 'blocked' THEN
    PERFORM public.anti_fake_log('ANTI_FAKE_ACCESS_BLOCKED', v_hash, p_telegram_id, jsonb_build_object('slot', v_row.slot, 'accounts', v_distinct));
  END IF;

  RETURN jsonb_build_object(
    'access', CASE WHEN v_access = 'blocked' THEN 'blocked' ELSE 'allowed' END,
    'status', v_access,
    'reason', CASE WHEN v_access = 'blocked' THEN 'MULTIPLE_ACCOUNTS_DETECTED' ELSE NULL END,
    'code', CASE WHEN v_access = 'blocked' THEN 'MULTI_ACCOUNT_LIMIT' ELSE NULL END,
    'limit', v_limit,
    'slot', v_row.slot,
    'accounts', v_distinct,
    'adminBypass', v_row.admin_bypass,
    'pendingReview', EXISTS (SELECT 1 FROM public.device_review_requests r WHERE r.telegram_id = p_telegram_id AND r.status = 'pending')
  );
END $$;

/** Fast, cache-friendly gate used by every protected feature (rewards, PvP, market...). */
CREATE OR REPLACE FUNCTION public.device_access_blocked(p_telegram_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT (value->>'enabled')::boolean FROM public.game_settings WHERE key = 'anti_fake'), true)
     AND p_telegram_id <> public.admin_super_id()
     AND NOT EXISTS (SELECT 1 FROM public.device_allowlist WHERE telegram_id = p_telegram_id)
     AND EXISTS (SELECT 1 FROM public.device_accounts WHERE telegram_id = p_telegram_id AND status = 'blocked')
     AND NOT EXISTS (SELECT 1 FROM public.device_accounts WHERE telegram_id = p_telegram_id AND status = 'allowed');
$$;

/** Player-facing review request (no automatic unblock). */
CREATE OR REPLACE FUNCTION public.device_request_review(p_telegram_id bigint, p_device_hash text, p_message text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_hash text := nullif(btrim(coalesce(p_device_hash, '')), ''); v_id uuid;
BEGIN
  IF v_hash IS NULL THEN RAISE EXCEPTION 'DEVICE_UNKNOWN'; END IF;
  SELECT id INTO v_id FROM public.device_review_requests
   WHERE telegram_id = p_telegram_id AND device_hash = v_hash AND status = 'pending';
  IF v_id IS NULL THEN
    INSERT INTO public.device_review_requests(telegram_id, device_hash, message)
    VALUES (p_telegram_id, v_hash, left(coalesce(p_message, ''), 500))
    RETURNING id INTO v_id;
    PERFORM public.anti_fake_log('ANTI_FAKE_REVIEW_REQUESTED', v_hash, p_telegram_id, '{}'::jsonb);
  END IF;
  RETURN jsonb_build_object('ok', true, 'requestId', v_id, 'status', 'pending');
END $$;

-- ---------------------------------------------------------------- admin
CREATE OR REPLACE FUNCTION public.admin_antifake_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
    'enabled', coalesce((SELECT (value->>'enabled')::boolean FROM public.game_settings WHERE key = 'anti_fake'), true),
    'limit', public.anti_fake_max_accounts(),
    'devices', (SELECT count(*) FROM public.device_registry),
    'linkedAccounts', (SELECT count(*) FROM public.device_accounts),
    'blockedAccounts', (SELECT count(*) FROM public.device_accounts WHERE status = 'blocked'),
    'pendingReviews', (SELECT count(*) FROM public.device_review_requests WHERE status = 'pending'),
    'allowlisted', (SELECT count(*) FROM public.device_allowlist),
    'blockedDevices', coalesce((
      SELECT jsonb_agg(x ORDER BY x->>'lastSeen' DESC) FROM (
        SELECT jsonb_build_object(
          'deviceHash', d.device_hash,
          'short', right(d.device_hash, 10),
          'platform', d.platform,
          'accounts', (SELECT count(*) FROM public.device_accounts a WHERE a.device_hash = d.device_hash),
          'blocked', (SELECT count(*) FROM public.device_accounts a WHERE a.device_hash = d.device_hash AND a.status = 'blocked'),
          'lastSeen', d.last_seen_at
        ) AS x
        FROM public.device_registry d
        WHERE EXISTS (SELECT 1 FROM public.device_accounts a WHERE a.device_hash = d.device_hash AND a.status = 'blocked')
        ORDER BY d.last_seen_at DESC LIMIT 15
      ) s), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.admin_antifake_search(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ref text := btrim(coalesce(p_ref, '')); v_tg bigint; v_player record; v_devices jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_ref ~ '^\d+$' THEN v_tg := v_ref::bigint;
  ELSE
    SELECT telegram_id INTO v_tg FROM public.game_players
     WHERE lower(coalesce(username, '')) = lower(replace(v_ref, '@', ''))
        OR lower(coalesce(display_name, '')) LIKE '%' || lower(v_ref) || '%'
     ORDER BY created_at LIMIT 1;
  END IF;
  IF v_tg IS NULL THEN RETURN jsonb_build_object('found', false); END IF;
  SELECT telegram_id, username, display_name, created_at INTO v_player FROM public.game_players WHERE telegram_id = v_tg;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'deviceHash', a.device_hash,
    'short', right(a.device_hash, 10),
    'slot', a.slot,
    'status', a.status,
    'adminBypass', a.admin_bypass,
    'accountsOnDevice', (SELECT count(*) FROM public.device_accounts b WHERE b.device_hash = a.device_hash),
    'firstSeen', a.first_seen_at,
    'lastSeen', a.last_seen_at
  ) ORDER BY a.last_seen_at DESC), '[]'::jsonb) INTO v_devices
  FROM public.device_accounts a WHERE a.telegram_id = v_tg;

  RETURN jsonb_build_object(
    'found', true,
    'telegramId', v_tg,
    'username', v_player.username,
    'name', v_player.display_name,
    'registeredAt', v_player.created_at,
    'deviceCount', jsonb_array_length(v_devices),
    'devices', v_devices,
    'blocked', public.device_access_blocked(v_tg),
    'allowlisted', EXISTS (SELECT 1 FROM public.device_allowlist WHERE telegram_id = v_tg),
    'pendingReview', EXISTS (SELECT 1 FROM public.device_review_requests WHERE telegram_id = v_tg AND status = 'pending')
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_antifake_reviews(p_admin_id bigint, p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'telegramId', r.telegram_id, 'deviceHash', r.device_hash, 'short', right(r.device_hash, 10),
    'message', r.message, 'status', r.status, 'createdAt', r.created_at,
    'username', (SELECT username FROM public.game_players g WHERE g.telegram_id = r.telegram_id),
    'accountsOnDevice', (SELECT count(*) FROM public.device_accounts a WHERE a.device_hash = r.device_hash)
  ) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v
  FROM (SELECT * FROM public.device_review_requests WHERE status = 'pending' ORDER BY created_at DESC LIMIT greatest(1, coalesce(p_limit, 10))) r;
  RETURN jsonb_build_object('requests', v);
END $$;

CREATE OR REPLACE FUNCTION public.admin_antifake_unblock(p_admin_id bigint, p_ref text, p_reason text DEFAULT 'admin review')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ref text := btrim(coalesce(p_ref, '')); v_tg bigint; v_hash text; v_count int := 0;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_ref ~ '^\d+$' THEN v_tg := v_ref::bigint; ELSE v_hash := v_ref; END IF;

  IF v_tg IS NOT NULL THEN
    UPDATE public.device_accounts SET status = 'allowed', updated_at = now()
     WHERE telegram_id = v_tg AND status = 'blocked';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    UPDATE public.device_review_requests SET status = 'approved', reviewed_by = p_admin_id, reviewed_at = now()
     WHERE telegram_id = v_tg AND status = 'pending';
  ELSE
    UPDATE public.device_accounts SET status = 'allowed', updated_at = now()
     WHERE device_hash = v_hash AND status = 'blocked';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    UPDATE public.device_registry SET risk_status = 'ok', risk_score = 0, updated_at = now() WHERE device_hash = v_hash;
    UPDATE public.device_review_requests SET status = 'approved', reviewed_by = p_admin_id, reviewed_at = now()
     WHERE device_hash = v_hash AND status = 'pending';
  END IF;

  IF v_count = 0 THEN RETURN jsonb_build_object('ok', false, 'reason', 'NOTHING_BLOCKED'); END IF;
  PERFORM public.anti_fake_log('ANTI_FAKE_ADMIN_UNBLOCK', v_hash, v_tg, jsonb_build_object('adminId', p_admin_id, 'reason', p_reason, 'rows', v_count));
  PERFORM public.admin_log(p_admin_id, 'MULTIACCOUNT_DEVICE_UNBLOCKED', 'anti_fake', coalesce(v_hash, v_tg::text),
    jsonb_build_object('admin_id', p_admin_id, 'target_telegram_id', v_tg, 'device_hash', v_hash, 'reason', p_reason, 'timestamp', now()));
  RETURN jsonb_build_object('ok', true, 'unblocked', v_count, 'telegramId', v_tg, 'deviceHash', v_hash);
END $$;

CREATE OR REPLACE FUNCTION public.admin_antifake_allowlist(p_admin_id bigint, p_ref text, p_reason text DEFAULT 'admin review', p_remove boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ref text := btrim(coalesce(p_ref, '')); v_tg bigint; v_hash text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_ref ~ '^\d+$' THEN v_tg := v_ref::bigint; ELSE v_hash := v_ref; END IF;

  IF p_remove THEN
    DELETE FROM public.device_allowlist WHERE (v_tg IS NOT NULL AND telegram_id = v_tg) OR (v_hash IS NOT NULL AND device_hash = v_hash);
  ELSE
    INSERT INTO public.device_allowlist(telegram_id, device_hash, reason, created_by)
    VALUES (v_tg, v_hash, left(coalesce(p_reason, ''), 300), p_admin_id)
    ON CONFLICT DO NOTHING;
    IF v_tg IS NOT NULL THEN
      UPDATE public.device_accounts SET status = 'allowed', updated_at = now() WHERE telegram_id = v_tg AND status = 'blocked';
    ELSE
      UPDATE public.device_registry SET risk_status = 'allowlisted', updated_at = now() WHERE device_hash = v_hash;
      UPDATE public.device_accounts SET status = 'allowed', updated_at = now() WHERE device_hash = v_hash AND status = 'blocked';
    END IF;
  END IF;
  PERFORM public.admin_log(p_admin_id, CASE WHEN p_remove THEN 'MULTIACCOUNT_ALLOWLIST_REMOVED' ELSE 'MULTIACCOUNT_ALLOWLIST_ADDED' END,
    'anti_fake', coalesce(v_hash, v_tg::text),
    jsonb_build_object('admin_id', p_admin_id, 'target_telegram_id', v_tg, 'device_hash', v_hash, 'reason', p_reason, 'timestamp', now()));
  RETURN jsonb_build_object('ok', true, 'telegramId', v_tg, 'deviceHash', v_hash, 'removed', p_remove);
END $$;

CREATE OR REPLACE FUNCTION public.admin_antifake_set_enabled(p_admin_id bigint, p_enabled boolean, p_limit integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  INSERT INTO public.game_settings(key, value, category, label, updated_at, updated_by)
  VALUES ('anti_fake', jsonb_build_object('enabled', coalesce(p_enabled, true), 'max_accounts_per_device', greatest(1, coalesce(p_limit, public.anti_fake_max_accounts()))), 'security', 'Anti-fake / multiconta', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET
    value = public.game_settings.value
      || jsonb_build_object('enabled', coalesce(p_enabled, true))
      || jsonb_build_object('max_accounts_per_device', greatest(1, coalesce(p_limit, public.anti_fake_max_accounts()))),
    updated_at = now(), updated_by = p_admin_id;
  RETURN public.admin_antifake_overview(p_admin_id);
END $$;

-- ---------------------------------------------------------------- referrals on the same device
CREATE OR REPLACE FUNCTION public.accounts_share_device(p_a uuid, p_b uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.device_accounts a
    JOIN public.device_accounts b ON b.device_hash = a.device_hash
    JOIN public.game_players ga ON ga.telegram_id = a.telegram_id AND ga.id = p_a
    JOIN public.game_players gb ON gb.telegram_id = b.telegram_id AND gb.id = p_b
    WHERE p_a IS NOT NULL AND p_b IS NOT NULL AND p_a <> p_b
  );
$$;

-- Referral commission: never pay between accounts sharing a device.
CREATE OR REPLACE FUNCTION public.referral_pay_ton_commission(p_buyer_id uuid, p_source_type text, p_source_id text, p_amount_ton numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_current uuid := p_buyer_id; v_beneficiary uuid; v_lvl int; v_rate numeric;
        v_paid numeric; v_total numeric := 0; v_key text; v_src text; v_skipped int := 0;
BEGIN
  IF p_buyer_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'NO_BUYER'); END IF;
  IF p_amount_ton IS NULL OR p_amount_ton <= 0 THEN RETURN jsonb_build_object('ok', false, 'reason', 'NO_TON'); END IF;

  v_src := lower(coalesce(nullif(btrim(p_source_type),''),'purchase'));

  PERFORM pg_advisory_xact_lock(hashtextextended('referral_first_ton:'||p_buyer_id::text, 0));

  INSERT INTO public.referral_first_ton_events(buyer_id, source_type, source_id, amount_ton)
  VALUES (p_buyer_id, v_src, coalesce(nullif(btrim(p_source_id),''),'-'), round(p_amount_ton, 9))
  ON CONFLICT (buyer_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'totalTon', 0);
  END IF;

  FOR v_lvl IN 1..3 LOOP
    SELECT inviter_id INTO v_beneficiary FROM public.referrals WHERE user_id = v_current;
    EXIT WHEN v_beneficiary IS NULL;
    -- ANTI-FAKE: self/multiaccount referral on the same device is logged and never paid.
    IF public.accounts_share_device(p_buyer_id, v_beneficiary) THEN
      v_skipped := v_skipped + 1;
      PERFORM public.anti_fake_log('ANTI_FAKE_SELF_REFERRAL', NULL,
        (SELECT telegram_id FROM public.game_players WHERE id = p_buyer_id),
        jsonb_build_object('level', v_lvl, 'beneficiary', v_beneficiary, 'reason', 'SELF_MULTIACCOUNT_REFERRAL'));
      v_current := v_beneficiary; v_beneficiary := NULL;
      CONTINUE;
    END IF;
    SELECT percent INTO v_rate FROM public.referral_commission_settings WHERE level = v_lvl;
    v_rate := coalesce(v_rate, CASE v_lvl WHEN 1 THEN 10 WHEN 2 THEN 4 ELSE 1 END);
    v_paid := round(p_amount_ton * v_rate / 100, 9);
    v_key := 'tonref:'||p_buyer_id::text||':'||v_lvl;
    IF v_paid > 0 THEN
      INSERT INTO public.referral_commissions(user_id, from_user, level, purchase_id, amount_fc, amount_ton, source_type, source_amount_ton)
      VALUES (v_beneficiary, p_buyer_id, v_lvl, v_key, null, v_paid, v_src, round(p_amount_ton, 9))
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.credit_ton_reward(v_beneficiary, v_paid, 'referral_commission', v_key, 'Referral Lv'||v_lvl);
        v_total := v_total + v_paid;
        RAISE LOG 'REFERRAL_COMMISSION referred_user_id=% referrer_user_id=% level=% transaction_id=% transaction_type=% transaction_ton=% percentage=% commission_ton=% status=paid',
          p_buyer_id, v_beneficiary, v_lvl, coalesce(nullif(btrim(p_source_id),''),'-'), v_src, round(p_amount_ton,9), v_rate, v_paid;
      END IF;
    END IF;
    v_current := v_beneficiary; v_beneficiary := NULL;
  END LOOP;

  UPDATE public.referral_first_ton_events SET commission_ton = v_total WHERE buyer_id = p_buyer_id;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'totalTon', v_total, 'skippedSameDevice', v_skipped);
END $$;

-- SECURITY DEFINER surface stays service_role only (edge functions / admin bot).
REVOKE ALL ON FUNCTION public.check_device_access(bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.device_request_review(bigint, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.device_access_blocked(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.anti_fake_log(text, text, bigint, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.anti_fake_max_accounts() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.accounts_share_device(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_antifake_overview(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_antifake_search(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_antifake_reviews(bigint, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_antifake_unblock(bigint, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_antifake_allowlist(bigint, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_antifake_set_enabled(bigint, boolean, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_device_access(bigint, text, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.device_request_review(bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.device_access_blocked(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_antifake_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_antifake_search(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_antifake_reviews(bigint, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_antifake_unblock(bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_antifake_allowlist(bigint, text, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_antifake_set_enabled(bigint, boolean, integer) TO service_role;