-- Improved admin player search: telegram id, username, name, wallet, internal id + pagination
CREATE OR REPLACE FUNCTION public.admin_search_players(p_admin_id bigint, p_query text, p_limit integer DEFAULT 10, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
  v_total integer;
  v_q text := btrim(COALESCE(p_query,''));
  v_bare text := lower(ltrim(v_q,'@'));
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit,10), 50));
  v_offset integer := GREATEST(0, COALESCE(p_offset,0));
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  SELECT count(*) INTO v_total
  FROM public.game_players p
  WHERE v_q = ''
     OR p.telegram_id::text = v_q
     OR lower(COALESCE(p.username,'')) LIKE '%'||v_bare||'%'
     OR lower(COALESCE(p.display_name,'')) LIKE '%'||v_bare||'%'
     OR lower(COALESCE(p.first_name,'')) LIKE '%'||v_bare||'%'
     OR lower(COALESCE(p.last_name,'')) LIKE '%'||v_bare||'%'
     OR lower(concat_ws(' ', p.first_name, p.last_name)) LIKE '%'||v_bare||'%'
     OR p.id::text = lower(v_q)
     OR EXISTS (SELECT 1 FROM public.pool_wallets w WHERE w.user_id = p.id AND lower(w.wallet_address) = lower(v_q));

  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v
  FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'telegram_id', p.telegram_id,
      'name', COALESCE(NULLIF(btrim(p.display_name),''), NULLIF(btrim(concat_ws(' ', p.first_name, p.last_name)),''), 'Jogador'),
      'username', p.username, 'forge_coins', p.forge_coins, 'trophies', p.pvp_trophies,
      'banned', p.banned, 'last_seen_at', p.last_seen_at,
      'pass_tier', COALESCE((SELECT sp.tier FROM public.player_season_pass sp
                              JOIN public.season_pass_seasons s ON s.id = sp.season_id AND s.active
                             WHERE sp.user_id = p.id LIMIT 1), 'none')) AS row
    FROM public.game_players p
    WHERE v_q = ''
       OR p.telegram_id::text = v_q
       OR lower(COALESCE(p.username,'')) LIKE '%'||v_bare||'%'
       OR lower(COALESCE(p.display_name,'')) LIKE '%'||v_bare||'%'
       OR lower(COALESCE(p.first_name,'')) LIKE '%'||v_bare||'%'
       OR lower(COALESCE(p.last_name,'')) LIKE '%'||v_bare||'%'
       OR lower(concat_ws(' ', p.first_name, p.last_name)) LIKE '%'||v_bare||'%'
       OR p.id::text = lower(v_q)
       OR EXISTS (SELECT 1 FROM public.pool_wallets w WHERE w.user_id = p.id AND lower(w.wallet_address) = lower(v_q))
    ORDER BY p.last_seen_at DESC
    LIMIT v_limit OFFSET v_offset
  ) t;

  RETURN jsonb_build_object('players', v, 'total', v_total, 'limit', v_limit, 'offset', v_offset,
                            'hasMore', (v_offset + v_limit) < v_total);
END;
$function$;

-- Battle pass state of one player (active season)
CREATE OR REPLACE FUNCTION public.admin_player_pass(p_admin_id bigint, p_ref text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; p public.game_players; s public.season_pass_seasons; sp public.player_season_pass;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO p FROM public.game_players WHERE id = v_uid;
  SELECT * INTO s FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RAISE EXCEPTION 'season_not_found'; END IF;
  SELECT * INTO sp FROM public.player_season_pass WHERE user_id = v_uid AND season_id = s.id;
  RETURN jsonb_build_object(
    'user_id', p.id,
    'telegram_id', p.telegram_id,
    'username', p.username,
    'name', COALESCE(NULLIF(btrim(p.display_name),''), NULLIF(btrim(concat_ws(' ', p.first_name, p.last_name)),''), 'Jogador'),
    'season_id', s.id,
    'season_name', s.name,
    'levels', s.levels,
    'xp_per_level', s.xp_per_level,
    'tier', COALESCE(sp.tier,'none'),
    'xp', COALESCE(sp.xp,0),
    'level', LEAST(s.levels, 1 + COALESCE(sp.xp,0) / GREATEST(1, s.xp_per_level)),
    'purchased_at', sp.purchased_at,
    'upgraded_at', sp.upgraded_at,
    'claimed', (SELECT count(*) FROM public.season_pass_claims c WHERE c.user_id = v_uid),
    'paid_orders', (SELECT count(*) FROM public.season_pass_orders o WHERE o.user_id = v_uid AND o.status = 'activated'));
END;
$function$;

-- Manual activation / removal of a battle pass by the super admin.
-- Never fakes a TON payment: no order and no tx_hash is created, and pool revenue is untouched.
CREATE OR REPLACE FUNCTION public.admin_set_player_pass(p_admin_id bigint, p_ref text, p_tier text, p_reason text DEFAULT 'ativado manualmente pelo admin')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; s public.season_pass_seasons; old_tier text; sp public.player_season_pass;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_tier NOT IN ('none','adventurer','legendary') THEN RAISE EXCEPTION 'invalid_tier'; END IF;
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO s FROM public.season_pass_seasons WHERE active ORDER BY start_at DESC LIMIT 1;
  IF s.id IS NULL THEN RAISE EXCEPTION 'season_not_found'; END IF;

  INSERT INTO public.player_season_pass(user_id, season_id, tier)
  VALUES (v_uid, s.id, 'none')
  ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO sp FROM public.player_season_pass WHERE user_id = v_uid AND season_id = s.id FOR UPDATE;
  old_tier := COALESCE(sp.tier,'none');

  -- XP, level and already claimed rewards are preserved: only ownership changes.
  UPDATE public.player_season_pass
     SET tier = p_tier,
         adventurer_owned = (p_tier <> 'none'),
         legendary_owned = (p_tier = 'legendary'),
         purchased_at = CASE WHEN p_tier = 'none' THEN NULL ELSE COALESCE(purchased_at, now()) END,
         upgraded_at = CASE WHEN p_tier = 'legendary' AND old_tier = 'adventurer' THEN now()
                            WHEN p_tier = 'none' THEN NULL ELSE upgraded_at END,
         updated_at = now()
   WHERE user_id = v_uid AND season_id = s.id
  RETURNING * INTO sp;

  PERFORM public.admin_log(p_admin_id, 'battle_pass_updated', 'player', v_uid::text,
    jsonb_build_object('tier', old_tier),
    jsonb_build_object('tier', p_tier, 'season_id', s.id, 'activation_source', 'admin', 'admin_telegram_id', p_admin_id),
    p_reason, jsonb_build_object('season', s.name, 'manual', true));

  RETURN jsonb_build_object('user_id', v_uid, 'season_id', s.id, 'season_name', s.name,
                            'old_tier', old_tier, 'tier', sp.tier, 'xp', sp.xp,
                            'level', LEAST(s.levels, 1 + COALESCE(sp.xp,0) / GREATEST(1, s.xp_per_level)),
                            'activation_source', 'admin');
END;
$function$;

-- Recent manual/paid pass changes for the admin panel
CREATE OR REPLACE FUNCTION public.admin_pass_history(p_admin_id bigint, p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(row ORDER BY created_at DESC), '[]'::jsonb) INTO v FROM (
    SELECT l.created_at, jsonb_build_object(
      'created_at', l.created_at,
      'old', l.old_value->>'tier',
      'new', l.new_value->>'tier',
      'source', COALESCE(l.new_value->>'activation_source','admin'),
      'telegram_id', (SELECT telegram_id FROM public.game_players g WHERE g.id::text = l.target_id),
      'username', (SELECT username FROM public.game_players g WHERE g.id::text = l.target_id)) AS row
    FROM public.admin_audit_logs l
    WHERE l.action = 'battle_pass_updated'
    ORDER BY l.created_at DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,10), 30))
  ) t;
  RETURN jsonb_build_object('entries', v);
END;
$function$;