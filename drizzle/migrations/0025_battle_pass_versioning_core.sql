-- ============================================================
-- BATTLE PASS VERSIONING: pass_versions + audience + activation
-- A pass version is a season container (season_pass_seasons row)
-- with one pass_versions row per pass type (5 TON = adventurer,
-- 20 TON = legendary). Entitlement/XP/claims are already keyed by
-- season_id, so a new version never reuses old purchases.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.pass_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pass_type text NOT NULL CHECK (pass_type IN ('adventurer','legendary')),
  version_number integer NOT NULL,
  season_id uuid NOT NULL REFERENCES public.season_pass_seasons(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'DRAFT'
    CHECK (status IN ('DRAFT','PREVIEW','SCHEDULED','ACTIVE','ARCHIVED','CANCELLED')),
  price_ton_snapshot numeric NOT NULL DEFAULT 0,
  levels integer NOT NULL DEFAULT 50,
  xp_per_level integer NOT NULL DEFAULT 1000,
  audience_mode text NOT NULL DEFAULT 'ADMIN_ONLY'
    CHECK (audience_mode IN ('ADMIN_ONLY','PREVIOUS_PASS_COMPLETERS','ALL_PLAYERS','NEW_PLAYERS_ONLY')),
  audience_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  activate_at timestamptz,
  activated_at timestamptz,
  archived_at timestamptz,
  cloned_from_version_id uuid REFERENCES public.pass_versions(id),
  created_by bigint,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pass_type, version_number)
);

GRANT SELECT ON public.pass_versions TO authenticated;
GRANT ALL ON public.pass_versions TO service_role;
ALTER TABLE public.pass_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pass versions readable" ON public.pass_versions;
CREATE POLICY "pass versions readable" ON public.pass_versions
  FOR SELECT TO authenticated USING (status IN ('ACTIVE','ARCHIVED'));

CREATE UNIQUE INDEX IF NOT EXISTS pass_versions_one_active
  ON public.pass_versions(pass_type) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS pass_versions_season_idx ON public.pass_versions(season_id);

CREATE TABLE IF NOT EXISTS public.pass_version_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid REFERENCES public.pass_versions(id) ON DELETE SET NULL,
  season_id uuid,
  pass_type text,
  action text NOT NULL,
  admin_id bigint,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pass_version_audit TO service_role;
ALTER TABLE public.pass_version_audit ENABLE ROW LEVEL SECURITY;

-- ---------- Backfill: current live season becomes V1 (ACTIVE) ----------
INSERT INTO public.pass_versions (pass_type, version_number, season_id, status, price_ton_snapshot, levels, xp_per_level, audience_mode, activated_at)
SELECT t.pass_type, 1, s.id, 'ACTIVE',
       CASE WHEN t.pass_type = 'adventurer' THEN s.adventurer_price_ton ELSE s.legendary_price_ton END,
       GREATEST(s.levels, 1), GREATEST(s.xp_per_level, 1), 'ALL_PLAYERS', COALESCE(s.start_at, now())
  FROM public.season_pass_seasons s
  CROSS JOIN (VALUES ('adventurer'),('legendary')) AS t(pass_type)
 WHERE s.active
   AND NOT EXISTS (SELECT 1 FROM public.pass_versions v WHERE v.pass_type = t.pass_type)
 ORDER BY s.start_at DESC
 LIMIT 2;

-- ---------- Helpers ----------
CREATE OR REPLACE FUNCTION public.pass_user_is_admin(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.game_players g
                  WHERE g.id = p_user_id AND g.telegram_id = public.admin_super_id());
$$;

-- Did the user complete a version of the given pass type (any archived/active season)?
CREATE OR REPLACE FUNCTION public.pass_type_completed(p_user_id uuid, p_pass_type text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.player_season_pass psp
      JOIN public.season_pass_seasons s ON s.id = psp.season_id
     WHERE psp.user_id = p_user_id
       AND (
         (p_pass_type = 'adventurer' AND psp.tier IN ('adventurer','legendary'))
         OR (p_pass_type = 'legendary' AND psp.tier = 'legendary')
       )
       AND COALESCE(psp.xp,0) >= GREATEST(s.levels,1) * GREATEST(s.xp_per_level,1)
  );
$$;

CREATE OR REPLACE FUNCTION public.pass_audience_allows(p_version_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v public.pass_versions%rowtype; types text[]; v_since timestamptz; v_created timestamptz;
BEGIN
  IF p_user_id IS NULL THEN RETURN false; END IF;
  SELECT * INTO v FROM public.pass_versions WHERE id = p_version_id;
  IF v.id IS NULL THEN RETURN false; END IF;

  IF v.audience_mode = 'ALL_PLAYERS' THEN RETURN true; END IF;

  IF v.audience_mode = 'ADMIN_ONLY' THEN RETURN public.pass_user_is_admin(p_user_id); END IF;

  IF v.audience_mode = 'PREVIOUS_PASS_COMPLETERS' THEN
    SELECT COALESCE(
      (SELECT array_agg(x) FROM jsonb_array_elements_text(COALESCE(v.audience_config->'eligible_previous','[]'::jsonb)) x),
      ARRAY[v.pass_type]) INTO types;
    RETURN EXISTS (SELECT 1 FROM unnest(types) tt WHERE public.pass_type_completed(p_user_id, tt))
        OR public.pass_user_is_admin(p_user_id);
  END IF;

  IF v.audience_mode = 'NEW_PLAYERS_ONLY' THEN
    v_since := COALESCE((v.audience_config->>'new_players_since')::timestamptz, v.created_at);
    SELECT created_at INTO v_created FROM public.game_players WHERE id = p_user_id;
    RETURN COALESCE(v_created, now()) >= v_since OR public.pass_user_is_admin(p_user_id);
  END IF;

  RETURN false;
END $$;

-- The season a given player should currently see/play.
-- Audience only controls VISIBILITY of an upcoming version, never entitlement.
CREATE OR REPLACE FUNCTION public.pass_user_season_id(p_user_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_season uuid;
BEGIN
  SELECT v.season_id INTO v_season
    FROM public.pass_versions v
   WHERE v.status IN ('DRAFT','PREVIEW','SCHEDULED')
     AND public.pass_audience_allows(v.id, p_user_id)
   ORDER BY v.version_number DESC, v.created_at DESC
   LIMIT 1;
  IF v_season IS NOT NULL THEN RETURN v_season; END IF;

  SELECT v.season_id INTO v_season FROM public.pass_versions v
   WHERE v.status = 'ACTIVE' ORDER BY v.version_number DESC LIMIT 1;
  IF v_season IS NOT NULL THEN RETURN v_season; END IF;

  SELECT id INTO v_season FROM public.season_pass_seasons
   WHERE active ORDER BY start_at DESC LIMIT 1;
  RETURN v_season;
END $$;

GRANT EXECUTE ON FUNCTION public.pass_user_is_admin(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.pass_type_completed(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.pass_audience_allows(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.pass_user_season_id(uuid) TO service_role;

-- ---------- Player-facing version info + history ----------
CREATE OR REPLACE FUNCTION public.pass_version_info(p_user_id uuid, p_season_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'seasonId', p_season_id,
    'versions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', v.id, 'passType', v.pass_type, 'versionNumber', v.version_number,
        'status', v.status, 'priceTon', v.price_ton_snapshot,
        'audienceMode', v.audience_mode, 'activateAt', v.activate_at)
        ORDER BY v.pass_type)
        FROM public.pass_versions v WHERE v.season_id = p_season_id), '[]'::jsonb),
    'previewOnly', COALESCE((SELECT bool_or(v.status IN ('DRAFT','PREVIEW','SCHEDULED'))
                               FROM public.pass_versions v WHERE v.season_id = p_season_id), false),
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'seasonId', s.id, 'name', s.name,
        'versionNumber', (SELECT max(v2.version_number) FROM public.pass_versions v2 WHERE v2.season_id = s.id),
        'status', CASE WHEN s.id = p_season_id THEN 'ACTIVE' ELSE
          COALESCE((SELECT max(v3.status) FROM public.pass_versions v3 WHERE v3.season_id = s.id), 'ARCHIVED') END,
        'tier', psp.tier, 'xp', COALESCE(psp.xp,0),
        'level', LEAST(GREATEST(s.levels,1), COALESCE(psp.xp,0) / GREATEST(s.xp_per_level,1) + 1),
        'levels', GREATEST(s.levels,1),
        'completed', COALESCE(psp.xp,0) >= GREATEST(s.levels,1) * GREATEST(s.xp_per_level,1),
        'pendingClaims', (SELECT count(*) FROM public.season_pass_rewards r
                           WHERE r.season_id = s.id AND r.enabled
                             AND r.level <= LEAST(GREATEST(s.levels,1), COALESCE(psp.xp,0) / GREATEST(s.xp_per_level,1) + 1)
                             AND ((r.tier = 'adventurer' AND psp.tier IN ('adventurer','legendary'))
                                  OR (r.tier = 'legendary' AND psp.tier = 'legendary'))
                             AND NOT EXISTS (SELECT 1 FROM public.season_pass_claims c
                                              WHERE c.reward_id = r.id AND c.user_id = p_user_id)))
        ORDER BY s.start_at DESC)
        FROM public.player_season_pass psp
        JOIN public.season_pass_seasons s ON s.id = psp.season_id
       WHERE psp.user_id = p_user_id AND s.id <> p_season_id), '[]'::jsonb));
$$;
GRANT EXECUTE ON FUNCTION public.pass_version_info(uuid, uuid) TO service_role;

-- ---------- Admin: overview ----------
CREATE OR REPLACE FUNCTION public.admin_pass_versions_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object('versions', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', v.id, 'passType', v.pass_type, 'versionNumber', v.version_number, 'status', v.status,
      'seasonId', v.season_id, 'seasonName', s.name,
      'priceTon', v.price_ton_snapshot, 'levels', v.levels, 'xpPerLevel', v.xp_per_level,
      'audienceMode', v.audience_mode, 'audienceConfig', v.audience_config,
      'activateAt', v.activate_at, 'activatedAt', v.activated_at, 'archivedAt', v.archived_at,
      'rewards', (SELECT count(*) FROM public.season_pass_rewards r WHERE r.season_id = v.season_id AND r.tier = v.pass_type),
      'purchases', (SELECT count(*) FROM public.player_season_pass psp WHERE psp.season_id = v.season_id
                     AND ((v.pass_type = 'adventurer' AND psp.tier IN ('adventurer','legendary'))
                       OR (v.pass_type = 'legendary' AND psp.tier = 'legendary'))),
      'completed', (SELECT count(*) FROM public.player_season_pass psp WHERE psp.season_id = v.season_id
                     AND ((v.pass_type = 'adventurer' AND psp.tier IN ('adventurer','legendary'))
                       OR (v.pass_type = 'legendary' AND psp.tier = 'legendary'))
                     AND COALESCE(psp.xp,0) >= GREATEST(v.levels,1) * GREATEST(v.xp_per_level,1)))
      ORDER BY v.pass_type, v.version_number DESC)
      FROM public.pass_versions v JOIN public.season_pass_seasons s ON s.id = v.season_id), '[]'::jsonb));
END $$;

-- ---------- Admin: create (optionally cloning) the next version ----------
CREATE OR REPLACE FUNCTION public.admin_pass_version_create(
  p_admin_id bigint, p_name text DEFAULT NULL, p_clone boolean DEFAULT true,
  p_adventurer_price numeric DEFAULT NULL, p_legendary_price numeric DEFAULT NULL,
  p_levels integer DEFAULT NULL, p_xp_per_level integer DEFAULT NULL,
  p_days integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE cur public.season_pass_seasons%rowtype; v_season uuid; v_next int;
        v_adv numeric; v_leg numeric; v_levels int; v_xpl int; v_name text; v_src uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('pass_versioning', 0));

  IF EXISTS (SELECT 1 FROM public.pass_versions WHERE status IN ('DRAFT','PREVIEW','SCHEDULED')) THEN
    RAISE EXCEPTION 'DRAFT_ALREADY_EXISTS';
  END IF;

  SELECT s.* INTO cur FROM public.season_pass_seasons s
    JOIN public.pass_versions v ON v.season_id = s.id AND v.status = 'ACTIVE'
   ORDER BY v.version_number DESC LIMIT 1;
  IF cur.id IS NULL THEN
    SELECT * INTO cur FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  END IF;
  IF cur.id IS NULL THEN RAISE EXCEPTION 'NO_CURRENT_SEASON'; END IF;

  SELECT COALESCE(max(version_number),0) + 1 INTO v_next FROM public.pass_versions;
  v_adv := GREATEST(COALESCE(p_adventurer_price, cur.adventurer_price_ton), 0.000000001);
  v_leg := GREATEST(COALESCE(p_legendary_price, cur.legendary_price_ton), 0.000000001);
  v_levels := GREATEST(COALESCE(p_levels, cur.levels), 1);
  v_xpl := GREATEST(COALESCE(p_xp_per_level, cur.xp_per_level), 1);
  v_name := COALESCE(NULLIF(btrim(p_name),''), 'SEASON ' || v_next);

  INSERT INTO public.season_pass_seasons(name, start_at, end_at, levels, xp_per_level,
      adventurer_price_ton, legendary_price_ton, active)
  VALUES (v_name, now(), now() + make_interval(days => GREATEST(COALESCE(p_days,30),1)),
      v_levels, v_xpl, v_adv, v_leg, false)
  RETURNING id INTO v_season;

  IF COALESCE(p_clone, true) THEN
    INSERT INTO public.season_pass_rewards(season_id, level, tier, reward_type, reward_code, amount, title, enabled, base_amount, min_pass_version)
    SELECT v_season, r.level, r.tier, r.reward_type, r.reward_code, r.amount, r.title, r.enabled, r.base_amount, r.min_pass_version
      FROM public.season_pass_rewards r WHERE r.season_id = cur.id;
  END IF;

  FOR v_src IN SELECT id FROM public.pass_versions WHERE season_id = cur.id LOOP NULL; END LOOP;

  INSERT INTO public.pass_versions(pass_type, version_number, season_id, status, price_ton_snapshot,
      levels, xp_per_level, audience_mode, audience_config, created_by,
      cloned_from_version_id)
  SELECT t.pass_type, v_next, v_season, 'DRAFT',
         CASE WHEN t.pass_type = 'adventurer' THEN v_adv ELSE v_leg END,
         v_levels, v_xpl, 'ADMIN_ONLY', '{}'::jsonb, p_admin_id,
         (SELECT v.id FROM public.pass_versions v WHERE v.season_id = cur.id AND v.pass_type = t.pass_type LIMIT 1)
    FROM (VALUES ('adventurer'),('legendary')) AS t(pass_type);

  INSERT INTO public.pass_version_audit(version_id, season_id, action, admin_id, payload)
  SELECT v.id, v_season, 'CREATE', p_admin_id,
         jsonb_build_object('cloned', COALESCE(p_clone,true), 'from_season', cur.id, 'version', v_next)
    FROM public.pass_versions v WHERE v.season_id = v_season;

  RETURN public.admin_pass_versions_overview(p_admin_id);
END $$;

-- ---------- Admin: audience / status / schedule ----------
CREATE OR REPLACE FUNCTION public.admin_pass_version_set_audience(
  p_admin_id bigint, p_version_id uuid, p_mode text, p_config jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_mode NOT IN ('ADMIN_ONLY','PREVIOUS_PASS_COMPLETERS','ALL_PLAYERS','NEW_PLAYERS_ONLY') THEN
    RAISE EXCEPTION 'INVALID_AUDIENCE';
  END IF;
  UPDATE public.pass_versions
     SET audience_mode = p_mode,
         audience_config = COALESCE(p_config, '{}'::jsonb),
         status = CASE WHEN status = 'DRAFT' THEN 'PREVIEW' ELSE status END,
         updated_at = now()
   WHERE id = p_version_id AND status IN ('DRAFT','PREVIEW','SCHEDULED');
  IF NOT FOUND THEN RAISE EXCEPTION 'VERSION_NOT_EDITABLE'; END IF;
  INSERT INTO public.pass_version_audit(version_id, action, admin_id, payload)
  VALUES (p_version_id, 'SET_AUDIENCE', p_admin_id, jsonb_build_object('mode', p_mode, 'config', p_config));
  RETURN public.admin_pass_versions_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_pass_version_schedule(
  p_admin_id bigint, p_version_id uuid, p_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_at IS NULL OR p_at <= now() THEN RAISE EXCEPTION 'INVALID_SCHEDULE'; END IF;
  UPDATE public.pass_versions SET status = 'SCHEDULED', activate_at = p_at, updated_at = now()
   WHERE id = p_version_id AND status IN ('DRAFT','PREVIEW','SCHEDULED');
  IF NOT FOUND THEN RAISE EXCEPTION 'VERSION_NOT_EDITABLE'; END IF;
  INSERT INTO public.pass_version_audit(version_id, action, admin_id, payload)
  VALUES (p_version_id, 'SCHEDULE', p_admin_id, jsonb_build_object('activate_at', p_at));
  RETURN public.admin_pass_versions_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_pass_version_cancel(p_admin_id bigint, p_version_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_season uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT season_id INTO v_season FROM public.pass_versions WHERE id = p_version_id AND status IN ('DRAFT','PREVIEW','SCHEDULED');
  IF v_season IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_EDITABLE'; END IF;
  UPDATE public.pass_versions SET status = 'CANCELLED', updated_at = now()
   WHERE season_id = v_season AND status IN ('DRAFT','PREVIEW','SCHEDULED');
  INSERT INTO public.pass_version_audit(version_id, season_id, action, admin_id, payload)
  VALUES (p_version_id, v_season, 'CANCEL', p_admin_id, '{}'::jsonb);
  RETURN public.admin_pass_versions_overview(p_admin_id);
END $$;

-- ---------- Activation (atomic; old version archived, never reused) ----------
CREATE OR REPLACE FUNCTION public.pass_version_activate_season(p_season_id uuid, p_admin_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_prev uuid; v_count int;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pass_versioning', 0));
  SELECT count(*) INTO v_count FROM public.pass_versions
   WHERE season_id = p_season_id AND status IN ('DRAFT','PREVIEW','SCHEDULED');
  IF v_count = 0 THEN RAISE EXCEPTION 'VERSION_NOT_ACTIVATABLE'; END IF;

  SELECT v.season_id INTO v_prev FROM public.pass_versions v WHERE v.status = 'ACTIVE' LIMIT 1;

  UPDATE public.pass_versions SET status = 'ARCHIVED', archived_at = now(), updated_at = now()
   WHERE status = 'ACTIVE';
  UPDATE public.season_pass_seasons SET active = false, updated_at = now() WHERE active AND id <> p_season_id;

  UPDATE public.pass_versions SET status = 'ACTIVE', activated_at = now(), updated_at = now()
   WHERE season_id = p_season_id AND status IN ('DRAFT','PREVIEW','SCHEDULED');
  UPDATE public.season_pass_seasons
     SET active = true,
         start_at = LEAST(COALESCE(start_at, now()), now()),
         end_at = GREATEST(COALESCE(end_at, now() + interval '30 days'), now() + interval '1 day'),
         updated_at = now()
   WHERE id = p_season_id;

  INSERT INTO public.pass_version_audit(version_id, season_id, action, admin_id, payload)
  SELECT v.id, p_season_id, 'ACTIVATE', p_admin_id,
         jsonb_build_object('previous_season', v_prev, 'version', v.version_number, 'pass_type', v.pass_type)
    FROM public.pass_versions v WHERE v.season_id = p_season_id AND v.status = 'ACTIVE';

  RETURN jsonb_build_object('seasonId', p_season_id, 'previousSeasonId', v_prev, 'activated', v_count);
END $$;

CREATE OR REPLACE FUNCTION public.admin_pass_version_activate(p_admin_id bigint, p_version_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_season uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT season_id INTO v_season FROM public.pass_versions WHERE id = p_version_id;
  IF v_season IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  PERFORM public.pass_version_activate_season(v_season, p_admin_id);
  RETURN public.admin_pass_versions_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.pass_versions_run_scheduled()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_season uuid; v_done int := 0;
BEGIN
  FOR v_season IN
    SELECT DISTINCT season_id FROM public.pass_versions
     WHERE status = 'SCHEDULED' AND activate_at IS NOT NULL AND activate_at <= now()
  LOOP
    PERFORM public.pass_version_activate_season(v_season, NULL);
    v_done := v_done + 1;
  END LOOP;
  RETURN jsonb_build_object('activatedSeasons', v_done);
END $$;

CREATE OR REPLACE FUNCTION public.admin_pass_version_purchases(p_admin_id bigint, p_version_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v public.pass_versions%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO v FROM public.pass_versions WHERE id = p_version_id;
  IF v.id IS NULL THEN RAISE EXCEPTION 'VERSION_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'passType', v.pass_type, 'versionNumber', v.version_number, 'status', v.status,
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('telegramId', g.telegram_id, 'username', g.username,
        'tier', psp.tier, 'xp', COALESCE(psp.xp,0),
        'level', LEAST(GREATEST(v.levels,1), COALESCE(psp.xp,0) / GREATEST(v.xp_per_level,1) + 1),
        'purchasedAt', psp.purchased_at) ORDER BY psp.purchased_at DESC NULLS LAST)
        FROM public.player_season_pass psp JOIN public.game_players g ON g.id = psp.user_id
       WHERE psp.season_id = v.season_id AND psp.tier <> 'none'
       LIMIT 50), '[]'::jsonb));
END $$;
