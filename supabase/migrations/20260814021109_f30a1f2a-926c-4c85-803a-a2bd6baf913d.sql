DROP FUNCTION IF EXISTS public.market_hero_locks(uuid);

CREATE OR REPLACE FUNCTION public.market_hero_locks(p_hero player_heroes)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(x), '[]'::jsonb) FROM (
    SELECT 'listed'::text AS x WHERE coalesce(p_hero.market_locked,false)
    UNION ALL SELECT 'locked' WHERE coalesce(p_hero.locked,false)
    UNION ALL SELECT 'not_tradable' WHERE coalesce(p_hero.tradable,true) = false
    UNION ALL SELECT 'exclusive' WHERE coalesce(p_hero.is_nft_exclusive,false)
    UNION ALL SELECT 'pvp_team' WHERE EXISTS (SELECT 1 FROM public.pvp_team_slots s WHERE s.hero_id = p_hero.id)
    UNION ALL SELECT 'global_boss_team' WHERE EXISTS (SELECT 1 FROM public.boss_team_slots b WHERE b.player_hero_id = p_hero.id)
    UNION ALL SELECT 'pvp_team' WHERE EXISTS (SELECT 1 FROM public.tower_team_slots t WHERE t.hero_id = p_hero.id)
  ) q;
$function$;

REVOKE ALL ON FUNCTION public.market_hero_locks(player_heroes) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_hero_locks(player_heroes) TO service_role;

CREATE OR REPLACE FUNCTION public.market_assert_hero_sellable(p_hero_id uuid)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE locks jsonb;
BEGIN
  SELECT public.market_hero_locks(h.*) INTO locks FROM public.player_heroes h WHERE h.id = p_hero_id;
  IF locks IS NULL THEN RAISE EXCEPTION 'ITEM_NOT_OWNED'; END IF;
  IF locks @> '["listed"]' THEN RAISE EXCEPTION 'ALREADY_LISTED'; END IF;
  IF locks @> '["locked"]' THEN RAISE EXCEPTION 'HERO_LOCKED'; END IF;
  IF locks @> '["exclusive"]' OR locks @> '["not_tradable"]' THEN RAISE EXCEPTION 'HERO_NOT_TRADABLE'; END IF;
  IF locks @> '["pvp_team"]' THEN RAISE EXCEPTION 'HERO_IN_PVP_TEAM'; END IF;
  IF locks @> '["global_boss_team"]' THEN RAISE EXCEPTION 'HERO_IN_BOSS_TEAM'; END IF;
END; $$;

REVOKE ALL ON FUNCTION public.market_assert_hero_sellable(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_assert_hero_sellable(uuid) TO service_role;