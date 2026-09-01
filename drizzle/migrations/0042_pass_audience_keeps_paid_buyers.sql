-- Uma compra já feita na temporada nunca pode ser revogada por regra de audiência.
create or replace function public.pass_audience_allows(p_version_id uuid, p_user_id uuid)
returns boolean language plpgsql stable security definer set search_path to 'public' as $function$
DECLARE v public.pass_versions%rowtype; types text[]; v_since timestamptz; v_created timestamptz; v_paid boolean;
BEGIN
  IF p_user_id IS NULL THEN RETURN false; END IF;
  SELECT * INTO v FROM public.pass_versions WHERE id = p_version_id;
  IF v.id IS NULL THEN RETURN false; END IF;

  -- Já pagou um tier desta temporada -> sempre elegível.
  SELECT EXISTS (SELECT 1 FROM public.player_season_pass psp
                  WHERE psp.user_id = p_user_id AND psp.season_id = v.season_id
                    AND COALESCE(psp.tier,'none') IN ('adventurer','legendary')) INTO v_paid;
  IF v_paid THEN RETURN true; END IF;

  IF v.audience_mode = 'ALL_PLAYERS' THEN RETURN true; END IF;

  IF v.audience_mode = 'ADMIN_ONLY' THEN RETURN public.pass_user_is_admin(p_user_id); END IF;

  IF v.audience_mode = 'COMPLETERS_OR_UNPURCHASED' THEN
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
END $function$;