CREATE OR REPLACE FUNCTION public.grant_season_pass_xp(p_user_id uuid, p_source text, p_reference_id text DEFAULT NULL, p_amount integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  s public.season_pass_seasons%rowtype; sp public.player_season_pass%rowtype;
  v_amount integer; v_before integer; v_after integer; v_max integer;
  v_lvl_before integer; v_lvl_after integer; v_ins uuid;
BEGIN
  IF p_user_id IS NULL OR COALESCE(p_source,'') = '' THEN RETURN NULL; END IF;

  SELECT * INTO s FROM public.season_pass_seasons
   WHERE active AND now() BETWEEN start_at AND end_at
   ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RETURN NULL; END IF;

  v_amount := COALESCE(p_amount, (public.season_pass_xp_config()->>p_source)::int, 0);
  IF v_amount = 0 THEN RETURN NULL; END IF;

  INSERT INTO public.player_season_pass(user_id, season_id, tier)
  VALUES (p_user_id, s.id, 'none') ON CONFLICT (user_id, season_id) DO NOTHING;

  SELECT * INTO sp FROM public.player_season_pass
   WHERE user_id = p_user_id AND season_id = s.id FOR UPDATE;

  v_max := s.levels * s.xp_per_level;
  v_before := COALESCE(sp.xp, 0);
  v_after := GREATEST(0, LEAST(v_max, v_before + v_amount));
  v_lvl_before := LEAST(s.levels, v_before / GREATEST(1, s.xp_per_level) + 1);
  v_lvl_after := LEAST(s.levels, v_after / GREATEST(1, s.xp_per_level) + 1);

  IF p_reference_id IS NULL THEN
    INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
        xp_before, xp_after, level_before, level_after)
    VALUES (p_user_id, s.id, p_source, NULL, v_after - v_before,
        v_before, v_after, v_lvl_before, v_lvl_after)
    RETURNING id INTO v_ins;
  ELSE
    INSERT INTO public.season_pass_xp_ledger(user_id, season_id, source, reference_id, xp_amount,
        xp_before, xp_after, level_before, level_after)
    VALUES (p_user_id, s.id, p_source, p_reference_id, v_after - v_before,
        v_before, v_after, v_lvl_before, v_lvl_after)
    ON CONFLICT (user_id, season_id, source, reference_id) WHERE reference_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_ins;
  END IF;

  IF v_ins IS NULL THEN
    RETURN jsonb_build_object('granted', false, 'duplicate', true,
      'xp', v_before, 'level', v_lvl_before, 'xpPerLevel', s.xp_per_level, 'levels', s.levels);
  END IF;

  UPDATE public.player_season_pass SET xp = v_after, updated_at = now()
   WHERE user_id = p_user_id AND season_id = s.id;

  RETURN jsonb_build_object('granted', true, 'amount', v_after - v_before,
    'xp', v_after, 'level', v_lvl_after, 'levelUp', v_lvl_after > v_lvl_before,
    'xpPerLevel', s.xp_per_level, 'levels', s.levels, 'maxed', v_after >= v_max);
END;
$fn$;