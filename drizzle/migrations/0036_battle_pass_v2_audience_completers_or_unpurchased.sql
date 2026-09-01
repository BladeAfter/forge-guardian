-- V2 visibility rule: anyone who already FINISHED a paid pass (5 TON or 20 TON) and
-- anyone who never bought a pass (including brand-new players) sees V2.
-- A player still holding an UNFINISHED paid pass stays on V1 until it is completed.

CREATE OR REPLACE FUNCTION public.pass_has_incomplete_paid(p_user_id uuid, p_exclude_season uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.player_season_pass psp
      JOIN public.season_pass_seasons s ON s.id = psp.season_id
     WHERE psp.user_id = p_user_id
       AND (p_exclude_season IS NULL OR psp.season_id <> p_exclude_season)
       AND COALESCE(psp.tier,'none') IN ('adventurer','legendary')
       AND COALESCE(psp.xp,0) < GREATEST(s.levels,1) * GREATEST(s.xp_per_level,1)
  );
$$;

GRANT EXECUTE ON FUNCTION public.pass_has_incomplete_paid(uuid, uuid) TO service_role;

ALTER TABLE public.pass_versions DROP CONSTRAINT IF EXISTS pass_versions_audience_mode_check;
ALTER TABLE public.pass_versions ADD CONSTRAINT pass_versions_audience_mode_check
  CHECK (audience_mode IN ('ADMIN_ONLY','PREVIOUS_PASS_COMPLETERS','ALL_PLAYERS','NEW_PLAYERS_ONLY','COMPLETERS_OR_UNPURCHASED'));

CREATE OR REPLACE FUNCTION public.pass_audience_allows(p_version_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v public.pass_versions%rowtype; types text[]; v_since timestamptz; v_created timestamptz;
BEGIN
  IF p_user_id IS NULL THEN RETURN false; END IF;
  SELECT * INTO v FROM public.pass_versions WHERE id = p_version_id;
  IF v.id IS NULL THEN RETURN false; END IF;

  IF v.audience_mode = 'ALL_PLAYERS' THEN RETURN true; END IF;

  IF v.audience_mode = 'ADMIN_ONLY' THEN RETURN public.pass_user_is_admin(p_user_id); END IF;

  IF v.audience_mode = 'COMPLETERS_OR_UNPURCHASED' THEN
    -- Finished a paid pass, or has no paid pass at all -> V2. Otherwise finish V1 first.
    RETURN public.pass_user_is_admin(p_user_id)
        OR NOT public.pass_has_incomplete_paid(p_user_id, v.season_id);
  END IF;

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
