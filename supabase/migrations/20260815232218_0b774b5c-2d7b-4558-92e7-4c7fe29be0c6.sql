CREATE OR REPLACE FUNCTION public.tactical_start_match(p_a uuid, p_b uuid, p_practice boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cfg jsonb := public.tactical_config(); v_cost int := COALESCE((v_cfg->>'ticketCost')::int,1);
        v_match uuid; v_units jsonb; v_b_units jsonb; v_deck_a jsonb; v_deck_b jsonb; v_seed text;
        v_rating_a int; v_rating_b int;
BEGIN
  PERFORM public.tactical_validate_entry(p_a, NOT p_practice);
  IF NOT p_practice THEN PERFORM public.tactical_validate_entry(p_b, true); END IF;

  -- pgcrypto digest() is not installed on this project: md5 + random is enough for a battle seed.
  v_seed := md5(p_a::text || COALESCE(p_b::text,'ai') || clock_timestamp()::text || random()::text);
  v_units := public.tactical_build_units(p_a, 'a');
  IF p_practice THEN
    -- Practice/test mirror: same official stats, AI controlled, no rating and no ticket.
    v_b_units := (SELECT jsonb_object_agg(replace(key,'a','b'),
        value || jsonb_build_object('uid', replace(key,'a','b'), 'side','b'))
      FROM jsonb_each(v_units));
    v_deck_b := public.tactical_deck_json(p_a);
  ELSE
    v_b_units := public.tactical_build_units(p_b, 'b');
    v_deck_b := public.tactical_deck_json(p_b);
  END IF;
  v_deck_a := public.tactical_deck_json(p_a);

  SELECT rating INTO v_rating_a FROM public.tactical_ratings WHERE user_id = p_a;
  IF NOT p_practice THEN SELECT rating INTO v_rating_b FROM public.tactical_ratings WHERE user_id = p_b; END IF;

  INSERT INTO public.tactical_matches (player_a, player_b, is_practice, seed, state, rating_a, rating_b)
  VALUES (p_a, CASE WHEN p_practice THEN NULL ELSE p_b END, p_practice, v_seed,
    jsonb_build_object(
      'units', v_units || v_b_units,
      'decks', jsonb_build_object('a', v_deck_a, 'b', v_deck_b),
      'names', jsonb_build_object(
        'a', (SELECT COALESCE(display_name, username, 'Player') FROM public.game_players WHERE id = p_a),
        'b', CASE WHEN p_practice THEN 'AI TRAINING'
             ELSE (SELECT COALESCE(display_name, username, 'Player') FROM public.game_players WHERE id = p_b) END),
      'avatars', jsonb_build_object(
        'a', (SELECT avatar_url FROM public.game_players WHERE id = p_a),
        'b', CASE WHEN p_practice THEN NULL ELSE (SELECT avatar_url FROM public.game_players WHERE id = p_b) END)
    ), v_rating_a, v_rating_b)
  RETURNING id INTO v_match;

  -- Tickets are charged ONLY here: match found + battle initialized.
  IF NOT p_practice THEN
    UPDATE public.game_players SET pvp_tickets = pvp_tickets - v_cost WHERE id IN (p_a, p_b);
  END IF;
  RETURN v_match;
END $$;

REVOKE ALL ON FUNCTION public.tactical_start_match(uuid, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tactical_start_match(uuid, uuid, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.tactical_start_match(uuid, uuid, boolean) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.tactical_start_match(uuid, uuid, boolean) TO service_role;