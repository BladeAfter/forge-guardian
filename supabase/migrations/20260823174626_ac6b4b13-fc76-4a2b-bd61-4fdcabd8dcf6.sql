-- 0037 — CLAN ANTI-ABUSE
CREATE TABLE IF NOT EXISTS public.clan_anti_abuse_settings (
  id smallint PRIMARY KEY DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  leave_cooldown_hours numeric NOT NULL DEFAULT 24,
  kick_cooldown_hours numeric NOT NULL DEFAULT 6,
  boss_lock_enabled boolean NOT NULL DEFAULT true,
  boss_lock_min_hours numeric NOT NULL DEFAULT 24,
  hopping_threshold_24h integer NOT NULL DEFAULT 3,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clan_anti_abuse_settings_single CHECK (id = 1)
);
GRANT ALL ON public.clan_anti_abuse_settings TO service_role;
ALTER TABLE public.clan_anti_abuse_settings ENABLE ROW LEVEL SECURITY;
INSERT INTO public.clan_anti_abuse_settings(id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.clan_membership_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL,
  clan_name text,
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz,
  leave_reason text,
  removed_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_membership_history TO service_role;
ALTER TABLE public.clan_membership_history ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS clan_membership_history_user_idx ON public.clan_membership_history(user_id, joined_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS clan_membership_history_open_idx
  ON public.clan_membership_history(user_id) WHERE left_at IS NULL;

CREATE TABLE IF NOT EXISTS public.clan_join_cooldowns (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  cooldown_until timestamptz NOT NULL,
  reason text NOT NULL DEFAULT 'VOLUNTARY_LEAVE',
  source_clan_id uuid,
  changes_24h integer NOT NULL DEFAULT 0,
  changes_7d integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_join_cooldowns TO service_role;
ALTER TABLE public.clan_join_cooldowns ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_boss_player_locks (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL,
  instance_id uuid,
  cycle integer,
  locked_at timestamptz NOT NULL DEFAULT now(),
  locked_until timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_boss_player_locks TO service_role;
ALTER TABLE public.clan_boss_player_locks ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_abuse_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  flag text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_abuse_flags TO service_role;
ALTER TABLE public.clan_abuse_flags ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS clan_abuse_flags_user_idx ON public.clan_abuse_flags(user_id, created_at DESC);

ALTER TABLE public.clan_boss_damage
  ADD COLUMN IF NOT EXISTS eligibility_status text NOT NULL DEFAULT 'ELIGIBLE';

CREATE OR REPLACE FUNCTION public.clan_anti_abuse_cfg()
RETURNS public.clan_anti_abuse_settings
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.clan_anti_abuse_settings WHERE id = 1
$$;
REVOKE ALL ON FUNCTION public.clan_anti_abuse_cfg() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_join_cooldown_json(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r public.clan_join_cooldowns; cfg public.clan_anti_abuse_settings;
BEGIN
  cfg := public.clan_anti_abuse_cfg();
  SELECT * INTO r FROM public.clan_join_cooldowns WHERE user_id = p_user_id;
  IF NOT COALESCE(cfg.enabled, true) OR r.user_id IS NULL OR r.cooldown_until <= now() THEN
    RETURN jsonb_build_object('active', false, 'remainingSeconds', 0, 'until', NULL,
      'reason', r.reason, 'changes24h', COALESCE(r.changes_24h, 0));
  END IF;
  RETURN jsonb_build_object('active', true,
    'remainingSeconds', GREATEST(0, ceil(EXTRACT(epoch FROM (r.cooldown_until - now())))::int),
    'until', r.cooldown_until, 'reason', r.reason, 'changes24h', COALESCE(r.changes_24h, 0));
END $$;
REVOKE ALL ON FUNCTION public.clan_join_cooldown_json(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_lock_json(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE l public.clan_boss_player_locks; v_clan uuid;
BEGIN
  SELECT * INTO l FROM public.clan_boss_player_locks WHERE user_id = p_user_id;
  IF l.user_id IS NULL OR l.locked_until <= now() THEN
    RETURN jsonb_build_object('active', false, 'remainingSeconds', 0, 'sameClan', true);
  END IF;
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = p_user_id;
  RETURN jsonb_build_object('active', true, 'clanId', l.clan_id, 'cycle', l.cycle,
    'until', l.locked_until,
    'remainingSeconds', GREATEST(0, ceil(EXTRACT(epoch FROM (l.locked_until - now())))::int),
    'sameClan', v_clan IS NOT NULL AND v_clan = l.clan_id);
END $$;
REVOKE ALL ON FUNCTION public.clan_boss_lock_json(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_anti_abuse_state(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_anti_abuse_settings; v_uid uuid;
BEGIN
  cfg := public.clan_anti_abuse_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  RETURN jsonb_build_object(
    'enabled', COALESCE(cfg.enabled, true),
    'leaveCooldownHours', cfg.leave_cooldown_hours,
    'kickCooldownHours', cfg.kick_cooldown_hours,
    'bossLockEnabled', cfg.boss_lock_enabled,
    'cooldown', public.clan_join_cooldown_json(v_uid),
    'bossLock', public.clan_boss_lock_json(v_uid),
    'serverTime', now());
END $$;
REVOKE ALL ON FUNCTION public.clan_anti_abuse_state(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_anti_abuse_state(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.clan_assert_can_join(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_anti_abuse_settings; r public.clan_join_cooldowns; v_secs integer;
BEGIN
  cfg := public.clan_anti_abuse_cfg();
  IF NOT COALESCE(cfg.enabled, true) THEN RETURN; END IF;
  SELECT * INTO r FROM public.clan_join_cooldowns WHERE user_id = p_user_id;
  IF r.user_id IS NOT NULL AND r.cooldown_until > now() THEN
    v_secs := GREATEST(1, ceil(EXTRACT(epoch FROM (r.cooldown_until - now())))::int);
    RAISE EXCEPTION 'CLAN_JOIN_COOLDOWN_ACTIVE' USING DETAIL = v_secs::text,
      HINT = 'remaining_seconds=' || v_secs::text;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.clan_assert_can_join(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_membership_open(p_user_id uuid, p_clan_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.clan_membership_history
     SET left_at = now(), leave_reason = COALESCE(leave_reason, 'RECONCILED')
   WHERE user_id = p_user_id AND left_at IS NULL AND clan_id <> p_clan_id;
  INSERT INTO public.clan_membership_history(user_id, clan_id, clan_name)
  SELECT p_user_id, p_clan_id, (SELECT name FROM public.clans WHERE id = p_clan_id)
   WHERE NOT EXISTS (SELECT 1 FROM public.clan_membership_history
                      WHERE user_id = p_user_id AND clan_id = p_clan_id AND left_at IS NULL);
END $$;
REVOKE ALL ON FUNCTION public.clan_membership_open(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_membership_close(
  p_user_id uuid, p_clan_id uuid, p_reason text, p_removed_by uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_anti_abuse_settings; v_hours numeric; v_until timestamptz;
        v_24h integer; v_7d integer; v_reason text;
BEGIN
  cfg := public.clan_anti_abuse_cfg();
  v_reason := COALESCE(NULLIF(p_reason, ''), 'VOLUNTARY_LEAVE');

  UPDATE public.clan_membership_history
     SET left_at = now(), leave_reason = v_reason, removed_by = p_removed_by
   WHERE user_id = p_user_id AND left_at IS NULL;
  IF NOT FOUND THEN
    INSERT INTO public.clan_membership_history(user_id, clan_id, clan_name, joined_at, left_at, leave_reason, removed_by)
    VALUES (p_user_id, p_clan_id, (SELECT name FROM public.clans WHERE id = p_clan_id), now(), now(), v_reason, p_removed_by);
  END IF;

  IF v_reason = 'VOLUNTARY_LEAVE' AND COALESCE(cfg.enabled, true) THEN
    UPDATE public.clan_boss_damage d
       SET eligibility_status = 'LEFT_CLAN_BEFORE_SETTLEMENT'
     WHERE d.user_id = p_user_id AND d.clan_id = p_clan_id AND d.eligibility_status = 'ELIGIBLE'
       AND EXISTS (SELECT 1 FROM public.clan_boss_instances b
                    WHERE b.id = d.instance_id AND b.status = 'active');
  END IF;

  IF COALESCE(cfg.enabled, true) THEN
    v_hours := CASE v_reason
                 WHEN 'VOLUNTARY_LEAVE' THEN cfg.leave_cooldown_hours
                 WHEN 'KICKED' THEN cfg.kick_cooldown_hours
                 ELSE 0 END;
    IF COALESCE(v_hours, 0) > 0 THEN
      v_until := now() + make_interval(secs => (v_hours * 3600)::int);
      SELECT count(*)::int INTO v_24h FROM public.clan_membership_history
       WHERE user_id = p_user_id AND left_at > now() - interval '24 hours';
      SELECT count(*)::int INTO v_7d FROM public.clan_membership_history
       WHERE user_id = p_user_id AND left_at > now() - interval '7 days';
      INSERT INTO public.clan_join_cooldowns(user_id, cooldown_until, reason, source_clan_id, changes_24h, changes_7d)
      VALUES (p_user_id, v_until, v_reason, p_clan_id, COALESCE(v_24h, 0), COALESCE(v_7d, 0))
      ON CONFLICT (user_id) DO UPDATE
        SET cooldown_until = GREATEST(public.clan_join_cooldowns.cooldown_until, EXCLUDED.cooldown_until),
            reason = EXCLUDED.reason, source_clan_id = EXCLUDED.source_clan_id,
            changes_24h = EXCLUDED.changes_24h, changes_7d = EXCLUDED.changes_7d, updated_at = now();

      IF COALESCE(v_24h, 0) >= GREATEST(2, cfg.hopping_threshold_24h) THEN
        INSERT INTO public.clan_abuse_flags(user_id, flag, details)
        VALUES (p_user_id, 'SUSPICIOUS_CLAN_HOPPING',
                jsonb_build_object('changes24h', v_24h, 'changes7d', v_7d, 'lastClan', p_clan_id, 'reason', v_reason));
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('reason', v_reason, 'cooldownUntil', v_until);
END $$;
REVOKE ALL ON FUNCTION public.clan_membership_close(uuid, uuid, text, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.clan_boss_lock_acquire(
  p_user_id uuid, p_clan_id uuid, p_instance_id uuid, p_cycle integer, p_ends_at timestamptz)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cfg public.clan_anti_abuse_settings; l public.clan_boss_player_locks; v_until timestamptz; v_secs integer;
BEGIN
  cfg := public.clan_anti_abuse_cfg();
  IF NOT COALESCE(cfg.enabled, true) OR NOT COALESCE(cfg.boss_lock_enabled, true) THEN RETURN; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('clanbosslock:' || p_user_id::text, 0));
  SELECT * INTO l FROM public.clan_boss_player_locks WHERE user_id = p_user_id FOR UPDATE;

  IF l.user_id IS NOT NULL AND l.locked_until > now() AND l.clan_id <> p_clan_id THEN
    v_secs := GREATEST(1, ceil(EXTRACT(epoch FROM (l.locked_until - now())))::int);
    RAISE EXCEPTION 'CLAN_BOSS_ELIGIBILITY_LOCKED' USING DETAIL = v_secs::text,
      HINT = 'remaining_seconds=' || v_secs::text;
  END IF;

  v_until := GREATEST(COALESCE(p_ends_at, now()), now() + make_interval(secs => (GREATEST(0, cfg.boss_lock_min_hours) * 3600)::int));
  IF l.user_id IS NULL THEN
    INSERT INTO public.clan_boss_player_locks(user_id, clan_id, instance_id, cycle, locked_until)
    VALUES (p_user_id, p_clan_id, p_instance_id, p_cycle, v_until)
    ON CONFLICT (user_id) DO NOTHING;
  ELSIF l.locked_until <= now() THEN
    UPDATE public.clan_boss_player_locks
       SET clan_id = p_clan_id, instance_id = p_instance_id, cycle = p_cycle,
           locked_at = now(), locked_until = v_until, updated_at = now()
     WHERE user_id = p_user_id;
  ELSE
    UPDATE public.clan_boss_player_locks
       SET instance_id = COALESCE(p_instance_id, instance_id), cycle = COALESCE(p_cycle, cycle),
           locked_until = GREATEST(locked_until, v_until), updated_at = now()
     WHERE user_id = p_user_id;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.clan_boss_lock_acquire(uuid, uuid, uuid, integer, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.join_clan(p_telegram_id bigint, p_clan_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; c public.clans%rowtype; v_count integer; v_trophies integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('clan:'||p_clan_id::text, 0));
  PERFORM pg_advisory_xact_lock(hashtextextended('clanmember:'||v_uid::text, 0));
  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
  PERFORM public.clan_assert_can_join(v_uid);
  SELECT * INTO c FROM public.clans WHERE id = p_clan_id AND NOT suspended;
  IF c.id IS NULL THEN RAISE EXCEPTION 'CLAN_NOT_FOUND'; END IF;
  SELECT pvp_trophies INTO v_trophies FROM public.game_players WHERE id = v_uid;
  IF COALESCE(v_trophies,0) < c.minimum_trophies THEN RAISE EXCEPTION 'TROPHIES_TOO_LOW'; END IF;
  SELECT count(*) INTO v_count FROM public.clan_members WHERE clan_id = c.id;
  IF v_count >= c.member_limit THEN RAISE EXCEPTION 'CLAN_FULL'; END IF;
  IF c.join_type = 'closed' THEN RAISE EXCEPTION 'CLAN_CLOSED'; END IF;
  IF c.join_type = 'approval' THEN
    INSERT INTO public.clan_join_requests(clan_id, user_id) VALUES (c.id, v_uid)
    ON CONFLICT (clan_id, user_id) DO UPDATE SET status='pending', created_at=now();
    RETURN jsonb_build_object('status','requested');
  END IF;
  INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (c.id, v_uid, 'member');
  PERFORM public.clan_membership_open(v_uid, c.id);
  RETURN jsonb_build_object('status','joined','clan', public.clan_public(c));
END; $function$;

CREATE OR REPLACE FUNCTION public.create_clan(p_telegram_id bigint, p_name text, p_tag text, p_description text, p_join_type text, p_min_trophies integer, p_emblem jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; v_cost numeric; v_bal numeric; c public.clans%rowtype; v_name text; v_tag text; v_limit integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('clan:'||v_uid::text, 0));
  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
  PERFORM public.clan_assert_can_join(v_uid);
  v_name := btrim(COALESCE(p_name,''));
  v_tag := upper(btrim(COALESCE(p_tag,'')));
  IF length(v_name) < 3 OR length(v_name) > 24 THEN RAISE EXCEPTION 'INVALID_CLAN_NAME'; END IF;
  IF v_tag !~ '^[A-Z0-9]{2,5}$' THEN RAISE EXCEPTION 'INVALID_CLAN_TAG'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE lower(name) = lower(v_name)) THEN RAISE EXCEPTION 'CLAN_NAME_TAKEN'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE upper(tag) = v_tag) THEN RAISE EXCEPTION 'CLAN_TAG_TAKEN'; END IF;
  IF COALESCE(p_join_type,'open') NOT IN ('open','approval','closed') THEN RAISE EXCEPTION 'INVALID_JOIN_TYPE'; END IF;

  v_cost := COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000);
  v_limit := GREATEST(2, COALESCE((SELECT value::text::int FROM public.game_settings WHERE key='clan_default_member_limit'), public.clan_member_limit(1)));
  SELECT forge_coins INTO v_bal FROM public.game_players WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_bal,0) < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;

  INSERT INTO public.clans(name, tag, description, leader_user_id, join_type, minimum_trophies, member_limit, emblem_config)
  VALUES (v_name, v_tag, COALESCE(btrim(p_description),''), v_uid, COALESCE(p_join_type,'open'), GREATEST(0, COALESCE(p_min_trophies,0)),
          v_limit, COALESCE(p_emblem, '{}'::jsonb))
  RETURNING * INTO c;

  INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (c.id, v_uid, 'leader');
  PERFORM public.clan_membership_open(v_uid, c.id);

  UPDATE public.game_players SET forge_coins = forge_coins - v_cost, updated_at = now() WHERE id = v_uid;
  INSERT INTO public.wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (v_uid, 'clan_create', -v_cost, v_bal, v_bal - v_cost, 'clan:'||c.id::text);

  INSERT INTO public.clan_boss_cycles(clan_id) VALUES (c.id);
  RETURN jsonb_build_object('status','created','clan', public.clan_public(c));
END; $function$;

CREATE OR REPLACE FUNCTION public.leave_clan(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; v_clan uuid; v_role text; v_next uuid; v_close jsonb;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('clanmember:'||v_uid::text, 0));
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid FOR UPDATE;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  v_close := public.clan_membership_close(v_uid, v_clan, 'VOLUNTARY_LEAVE', NULL);
  DELETE FROM public.clan_members WHERE user_id = v_uid;

  IF v_role = 'leader' THEN
    SELECT user_id INTO v_next FROM public.clan_members WHERE clan_id = v_clan
     ORDER BY public.clan_role_rank(role) DESC, contribution DESC LIMIT 1;
    IF v_next IS NULL THEN
      DELETE FROM public.clans WHERE id = v_clan;
      RETURN jsonb_build_object('status','disbanded','cooldown', public.clan_join_cooldown_json(v_uid));
    END IF;
    UPDATE public.clan_members SET role='leader' WHERE user_id = v_next;
    UPDATE public.clans SET leader_user_id = v_next, updated_at = now() WHERE id = v_clan;
  END IF;
  RETURN jsonb_build_object('status','left','cooldown', public.clan_join_cooldown_json(v_uid));
END; $function$;

CREATE OR REPLACE FUNCTION public.clan_manage(p_telegram_id bigint, p_action text, p_target uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; v_clan uuid; v_role text; v_trole text; v_count integer; c public.clans%rowtype; v_req uuid;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;

  IF p_action = 'edit' THEN
    IF public.clan_role_rank(v_role) < 3 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clans SET
      description = COALESCE(NULLIF(btrim(p_payload->>'description'),''), description),
      join_type = COALESCE(NULLIF(p_payload->>'joinType',''), join_type),
      minimum_trophies = COALESCE((p_payload->>'minimumTrophies')::int, minimum_trophies),
      emblem_config = COALESCE(p_payload->'emblem', emblem_config),
      updated_at = now()
     WHERE id = v_clan;
    RETURN jsonb_build_object('status','updated');
  END IF;

  IF p_target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  SELECT role INTO v_trole FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;

  IF p_action IN ('accept','reject') THEN
    IF public.clan_role_rank(v_role) < 2 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    PERFORM 1 FROM public.clans WHERE id = v_clan FOR UPDATE;
    SELECT id INTO v_req FROM public.clan_join_requests
      WHERE clan_id = v_clan AND user_id = p_target AND status = 'pending' FOR UPDATE;
    IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
    IF p_action = 'reject' THEN
      UPDATE public.clan_join_requests SET status='rejected' WHERE id = v_req;
      RETURN jsonb_build_object('status','rejected');
    END IF;
    SELECT count(*) INTO v_count FROM public.clan_members WHERE clan_id = v_clan;
    IF v_count >= c.member_limit THEN RAISE EXCEPTION 'CLAN_FULL'; END IF;
    IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = p_target) THEN
      UPDATE public.clan_join_requests SET status='cancelled' WHERE id = v_req;
      RAISE EXCEPTION 'TARGET_ALREADY_IN_CLAN';
    END IF;
    IF COALESCE((public.clan_anti_abuse_cfg()).enabled, true)
       AND EXISTS (SELECT 1 FROM public.clan_join_cooldowns WHERE user_id = p_target AND cooldown_until > now()) THEN
      RAISE EXCEPTION 'TARGET_CLAN_JOIN_COOLDOWN';
    END IF;
    INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (v_clan, p_target, 'member');
    PERFORM public.clan_membership_open(p_target, v_clan);
    UPDATE public.clan_join_requests SET status='accepted' WHERE id = v_req;
    RETURN jsonb_build_object('status','accepted');
  END IF;

  IF v_trole IS NULL THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;

  IF p_action = 'kick' THEN
    IF public.clan_role_rank(v_role) < 3 OR public.clan_role_rank(v_trole) >= public.clan_role_rank(v_role) THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    PERFORM public.clan_membership_close(p_target, v_clan, 'KICKED', v_uid);
    DELETE FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','kicked');
  ELSIF p_action IN ('promote','demote') THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    IF v_trole = 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role = CASE
        WHEN p_action='promote' THEN CASE v_trole WHEN 'member' THEN 'officer' WHEN 'officer' THEN 'co-leader' ELSE 'co-leader' END
        ELSE CASE v_trole WHEN 'co-leader' THEN 'officer' WHEN 'officer' THEN 'member' ELSE 'member' END END,
      updated_at = now()
     WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','role_changed');
  ELSIF p_action = 'transfer' THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role='leader' WHERE user_id = p_target AND clan_id = v_clan;
    UPDATE public.clan_members SET role='co-leader' WHERE user_id = v_uid AND clan_id = v_clan;
    UPDATE public.clans SET leader_user_id = p_target, updated_at = now() WHERE id = v_clan;
    RETURN jsonb_build_object('status','transferred');
  END IF;
  RAISE EXCEPTION 'INVALID_ACTION';
END; $function$;

INSERT INTO public.clan_membership_history(user_id, clan_id, clan_name, joined_at)
SELECT m.user_id, m.clan_id, c.name, COALESCE(m.joined_at, now())
  FROM public.clan_members m JOIN public.clans c ON c.id = m.clan_id
 WHERE NOT EXISTS (SELECT 1 FROM public.clan_membership_history h
                    WHERE h.user_id = m.user_id AND h.left_at IS NULL);