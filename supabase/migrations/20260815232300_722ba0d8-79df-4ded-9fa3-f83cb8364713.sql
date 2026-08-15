CREATE OR REPLACE FUNCTION public.admin_tactical_ranking(p_admin_id bigint, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
        'name', r.name, 'telegramId', r.telegram_id, 'rating', r.rating,
        'league', public.tactical_league(r.rating), 'wins', r.wins, 'losses', r.losses)
      ORDER BY r.rating DESC)
    FROM (
      SELECT COALESCE(g.display_name, g.username, 'Player') AS name, g.telegram_id,
             t.rating, t.wins, t.losses
      FROM public.tactical_ratings t
      JOIN public.game_players g ON g.id = t.user_id
      WHERE t.matches > 0
      ORDER BY t.rating DESC
      LIMIT GREATEST(1, LEAST(50, p_limit))
    ) r), '[]'::jsonb);
END $$;

REVOKE ALL ON FUNCTION public.admin_tactical_ranking(bigint, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_tactical_ranking(bigint, integer) FROM anon;
REVOKE ALL ON FUNCTION public.admin_tactical_ranking(bigint, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tactical_ranking(bigint, integer) TO service_role;