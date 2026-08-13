CREATE OR REPLACE FUNCTION public.get_tower_ranking(p_telegram_id bigint, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; v_limit int := LEAST(GREATEST(COALESCE(p_limit,50),1),100);
        v_top jsonb; v_you jsonb; v_total int; v_best int;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;

  WITH base AS (
    SELECT tp.user_id, tp.highest_floor, tp.updated_at,
           COALESCE((SELECT sum((x->>'power')::numeric)
                       FROM jsonb_array_elements(public.tower_team_json(tp.user_id)) x),0)::bigint AS power
      FROM public.tower_progress tp
     WHERE tp.highest_floor > 0
  ), ranked AS (
    SELECT b.*, row_number() OVER (ORDER BY b.highest_floor DESC, b.power DESC, b.updated_at ASC) AS rnk
      FROM base b
  )
  SELECT
    COALESCE((SELECT jsonb_agg(jsonb_build_object(
       'rank', r.rnk, 'userId', r.user_id,
       'name', COALESCE(NULLIF(g.display_name,''), NULLIF(g.first_name,''), NULLIF(g.username,''), 'Player'),
       'username', g.username, 'photoUrl', g.avatar_url,
       'floor', r.highest_floor, 'power', r.power, 'updatedAt', r.updated_at,
       'isYou', r.user_id = v_user) ORDER BY r.rnk)
      FROM (SELECT * FROM ranked ORDER BY rnk LIMIT v_limit) r
      JOIN public.game_players g ON g.id = r.user_id), '[]'::jsonb),
    (SELECT jsonb_build_object('rank', r.rnk, 'floor', r.highest_floor, 'power', r.power, 'updatedAt', r.updated_at)
       FROM ranked r WHERE r.user_id = v_user),
    (SELECT count(*)::int FROM ranked),
    (SELECT COALESCE(max(highest_floor),0)::int FROM ranked)
  INTO v_top, v_you, v_total, v_best;

  RETURN jsonb_build_object('totalPlayers', COALESCE(v_total,0), 'highestFloor', COALESCE(v_best,0),
                            'top', v_top, 'you', v_you);
END; $function$;

REVOKE ALL ON FUNCTION public.get_tower_ranking(bigint,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_tower_ranking(bigint,integer) TO service_role;