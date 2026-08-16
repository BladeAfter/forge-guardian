CREATE OR REPLACE FUNCTION public.admin_player_pass(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; p public.game_players; s public.season_pass_seasons; sp public.player_season_pass; v_xpl int; v_ver int; v_levels int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO p FROM public.game_players WHERE id = v_uid;
  SELECT * INTO s FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RAISE EXCEPTION 'season_not_found'; END IF;
  SELECT * INTO sp FROM public.player_season_pass WHERE user_id = v_uid AND season_id = s.id;
  v_xpl := GREATEST(1, s.xp_per_level);
  v_ver := CASE WHEN COALESCE(sp.tier,'none') = 'none' THEN 2 ELSE COALESCE(sp.pass_version, 1) END;
  v_levels := public.season_pass_levels_for(v_ver, s.levels);
  RETURN jsonb_build_object(
    'user_id', p.id, 'telegram_id', p.telegram_id, 'username', p.username,
    'name', COALESCE(NULLIF(btrim(p.display_name),''), NULLIF(btrim(concat_ws(' ', p.first_name, p.last_name)),''), 'Jogador'),
    'season_id', s.id, 'season_name', s.name, 'levels', v_levels, 'xp_per_level', v_xpl,
    'tier', COALESCE(sp.tier,'none'), 'xp', COALESCE(sp.xp,0),
    'pass_version', v_ver,
    'legacy_pass', COALESCE(sp.tier,'none') <> 'none' AND COALESCE(sp.pass_version,1) < 2,
    'current_pass_version', 2,
    'expires_at', sp.expires_at,
    'locked_rewards', (SELECT count(*) FROM public.season_pass_rewards r
      WHERE r.season_id = s.id AND r.enabled AND COALESCE(r.min_pass_version,1) > v_ver),
    'level', LEAST(v_levels, COALESCE(sp.xp,0) / v_xpl + 1),
    'xp_into_level', COALESCE(sp.xp,0) % v_xpl,
    'purchased_at', sp.purchased_at, 'upgraded_at', sp.upgraded_at,
    'claimed', (SELECT count(*) FROM public.season_pass_claims c WHERE c.user_id = v_uid),
    'paid_orders', (SELECT count(*) FROM public.season_pass_orders o WHERE o.user_id = v_uid AND o.status = 'activated'),
    'xp_events', (SELECT count(*) FROM public.season_pass_xp_ledger l WHERE l.user_id = v_uid AND l.season_id = s.id));
END; $function$;