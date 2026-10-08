-- =========================================================
-- ADMIN CORE :: auth, audit, settings, players
-- =========================================================

CREATE OR REPLACE FUNCTION public.admin_super_id()
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT (value #>> '{}')::bigint FROM public.game_settings WHERE key = 'super_admin_telegram_id'), 8118569391);
$$;

CREATE OR REPLACE FUNCTION public.admin_assert(p_admin_id bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_admin_id IS NULL OR p_admin_id <> public.admin_super_id() THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_log(
  p_admin_id bigint, p_action text, p_target_type text, p_target_id text,
  p_old jsonb, p_new jsonb, p_reason text DEFAULT NULL, p_context jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.admin_audit_logs (admin_id, action, target_type, target_id, old_value, new_value, reason, context)
  VALUES (p_admin_id, p_action, COALESCE(p_target_type,'system'), p_target_id, p_old, p_new, p_reason, COALESCE(p_context,'{}'::jsonb))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_bump_settings_version()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v integer;
BEGIN
  INSERT INTO public.game_settings (key, value, category, label)
  VALUES ('settings_version','1'::jsonb,'system','Versão das configurações')
  ON CONFLICT (key) DO UPDATE SET value = to_jsonb(COALESCE((public.game_settings.value #>> '{}')::int,0) + 1), updated_at = now()
  RETURNING (value #>> '{}')::int INTO v;
  RETURN v;
END;
$$;

-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_settings(p_admin_id bigint, p_category text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('key',key,'value',value,'category',category,'label',label,'updated_at',updated_at) ORDER BY category, key), '[]'::jsonb)
  INTO v FROM public.game_settings WHERE p_category IS NULL OR category = p_category;
  RETURN jsonb_build_object('settings', v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_setting(
  p_admin_id bigint, p_key text, p_value jsonb, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_key IS NULL OR length(p_key) = 0 THEN RAISE EXCEPTION 'invalid_key'; END IF;
  IF p_key = 'super_admin_telegram_id' THEN RAISE EXCEPTION 'immutable_setting'; END IF;
  SELECT value INTO v_old FROM public.game_settings WHERE key = p_key;
  INSERT INTO public.game_settings (key, value, updated_at, updated_by)
  VALUES (p_key, p_value, now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
  PERFORM public.admin_log(p_admin_id,'setting.update','setting',p_key,v_old,p_value,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN jsonb_build_object('key',p_key,'old_value',v_old,'new_value',p_value);
END;
$$;

-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_resolve_player(p_ref text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_ref text := btrim(COALESCE(p_ref,''));
BEGIN
  IF v_ref = '' THEN RAISE EXCEPTION 'player_not_found'; END IF;
  IF v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    SELECT id INTO v_id FROM public.game_players WHERE id = v_ref::uuid;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  END IF;
  IF v_ref ~ '^[0-9]+$' THEN
    SELECT id INTO v_id FROM public.game_players WHERE telegram_id = v_ref::bigint;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  END IF;
  SELECT id INTO v_id FROM public.game_players WHERE lower(username) = lower(ltrim(v_ref,'@')) LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  SELECT user_id INTO v_id FROM public.pool_wallets WHERE lower(wallet_address) = lower(v_ref) LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  SELECT id INTO v_id FROM public.game_players
   WHERE lower(COALESCE(display_name, concat_ws(' ', first_name, last_name))) LIKE '%'||lower(v_ref)||'%'
   ORDER BY last_seen_at DESC LIMIT 1;
  IF v_id IS NULL THEN RAISE EXCEPTION 'player_not_found'; END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_search_players(p_admin_id bigint, p_query text, p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; v_q text := btrim(COALESCE(p_query,''));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(row ORDER BY row->>'last_seen_at' DESC), '[]'::jsonb) INTO v
  FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'telegram_id', p.telegram_id,
      'name', COALESCE(p.display_name, concat_ws(' ', p.first_name, p.last_name), 'Jogador'),
      'username', p.username, 'forge_coins', p.forge_coins, 'trophies', p.pvp_trophies,
      'banned', p.banned, 'last_seen_at', p.last_seen_at) AS row
    FROM public.game_players p
    WHERE v_q = ''
       OR p.telegram_id::text = v_q
       OR lower(COALESCE(p.username,'')) LIKE '%'||lower(ltrim(v_q,'@'))||'%'
       OR lower(COALESCE(p.display_name, concat_ws(' ', p.first_name, p.last_name),'')) LIKE '%'||lower(v_q)||'%'
       OR p.id::text = v_q
    ORDER BY p.last_seen_at DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,10), 50))
  ) t;
  RETURN jsonb_build_object('players', v);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_player_detail(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; p public.game_players; v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO p FROM public.game_players WHERE id = v_uid;
  v := jsonb_build_object(
    'id', p.id,
    'telegram_id', p.telegram_id,
    'name', COALESCE(p.display_name, concat_ws(' ', p.first_name, p.last_name), 'Jogador'),
    'username', p.username,
    'avatar_url', p.avatar_url,
    'forge_coins', p.forge_coins,
    'ton_balance', p.ton_balance,
    'trophies', p.pvp_trophies,
    'league', public.pvp_league(p.pvp_trophies),
    'tickets', p.pvp_tickets,
    'wins', p.pvp_wins,
    'losses', p.pvp_losses,
    'boss_defeats', p.boss_defeats,
    'banned', p.banned,
    'ban_reason', p.ban_reason,
    'vip_until', p.vip_until,
    'premium_until', p.premium_until,
    'created_at', p.created_at,
    'last_seen_at', p.last_seen_at,
    'heroes_count', (SELECT count(*) FROM public.player_heroes WHERE user_id = p.id),
    'pets_count', (SELECT count(*) FROM public.player_pets WHERE user_id = p.id),
    'wallet', (SELECT wallet_address FROM public.pool_wallets WHERE user_id = p.id),
    'deposited_ton', (SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_deposits WHERE user_id = p.id AND status = 'credited'),
    'withdrawn_ton', (SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_withdrawals WHERE user_id = p.id AND status = 'paid'),
    'heroes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',h.id,'name',h.name,'rarity',h.rarity,'level',h.level) ORDER BY h.created_at DESC), '[]'::jsonb)
               FROM public.player_heroes h WHERE h.user_id = p.id),
    'pets', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pp.id,'name',pt.name,'rarity',pp.rarity,'level',pp.level,'tier',pp.evolution_tier) ORDER BY pp.created_at DESC), '[]'::jsonb)
             FROM public.player_pets pp JOIN public.pets pt ON pt.id = pp.pet_id WHERE pp.user_id = p.id),
    'referrals', (SELECT count(*) FROM public.referrals WHERE inviter_id = p.id AND level = 1)
  );
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_player_history(p_admin_id bigint, p_ref text, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('action',action,'old',old_value,'new',new_value,'reason',reason,'at',created_at) ORDER BY created_at DESC), '[]'::jsonb)
  INTO v FROM (
    SELECT * FROM public.admin_audit_logs WHERE target_type = 'player' AND target_id = v_uid::text
    ORDER BY created_at DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit,15), 50))
  ) t;
  RETURN jsonb_build_object('user_id', v_uid, 'events', v);
END;
$$;

-- ---------------------------------------------------------
-- balances
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(
  p_admin_id bigint, p_ref text, p_currency text, p_mode text, p_amount numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_old numeric; v_new numeric; v_cur text := lower(COALESCE(p_currency,'fc')); v_mode text := lower(COALESCE(p_mode,'add'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_cur NOT IN ('fc','ton') THEN RAISE EXCEPTION 'invalid_currency'; END IF;
  IF v_mode NOT IN ('add','remove','set') THEN RAISE EXCEPTION 'invalid_mode'; END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  v_uid := public.admin_resolve_player(p_ref);

  IF v_cur = 'fc' THEN
    SELECT forge_coins INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    v_new := CASE v_mode WHEN 'add' THEN v_old + p_amount WHEN 'remove' THEN GREATEST(0, v_old - p_amount) ELSE p_amount END;
    UPDATE public.game_players SET forge_coins = v_new, updated_at = now() WHERE id = v_uid;
  ELSE
    SELECT ton_balance INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    v_new := CASE v_mode WHEN 'add' THEN v_old + p_amount WHEN 'remove' THEN GREATEST(0, v_old - p_amount) ELSE p_amount END;
    UPDATE public.game_players SET ton_balance = v_new, updated_at = now() WHERE id = v_uid;
  END IF;

  PERFORM public.admin_log(p_admin_id, 'balance.'||v_cur||'.'||v_mode, 'player', v_uid::text,
    jsonb_build_object(v_cur, v_old), jsonb_build_object(v_cur, v_new), p_reason,
    jsonb_build_object('amount', p_amount, 'financial', true));
  RETURN jsonb_build_object('user_id', v_uid, 'currency', v_cur, 'old_value', v_old, 'new_value', v_new);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_adjust_pvp_stat(
  p_admin_id bigint, p_ref text, p_stat text, p_mode text, p_amount numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_old integer; v_new integer; v_stat text := lower(COALESCE(p_stat,'trophies')); v_mode text := lower(COALESCE(p_mode,'add'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_stat NOT IN ('trophies','tickets') THEN RAISE EXCEPTION 'invalid_stat'; END IF;
  IF v_mode NOT IN ('add','remove','set') THEN RAISE EXCEPTION 'invalid_mode'; END IF;
  v_uid := public.admin_resolve_player(p_ref);

  IF v_stat = 'trophies' THEN
    SELECT pvp_trophies INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
  ELSE
    SELECT pvp_tickets INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
  END IF;
  v_new := GREATEST(0, CASE v_mode WHEN 'add' THEN v_old + p_amount::int WHEN 'remove' THEN v_old - p_amount::int ELSE p_amount::int END);

  IF v_stat = 'trophies' THEN
    UPDATE public.game_players SET pvp_trophies = v_new, updated_at = now() WHERE id = v_uid;
  ELSE
    UPDATE public.game_players SET pvp_tickets = v_new, updated_at = now() WHERE id = v_uid;
  END IF;

  PERFORM public.admin_log(p_admin_id, 'pvp.'||v_stat||'.'||v_mode, 'player', v_uid::text,
    jsonb_build_object(v_stat, v_old), jsonb_build_object(v_stat, v_new), p_reason);
  RETURN jsonb_build_object('user_id', v_uid, 'stat', v_stat, 'old_value', v_old, 'new_value', v_new);
END;
$$;

-- ---------------------------------------------------------
-- heroes / pets grants
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_grant_hero(
  p_admin_id bigint, p_ref text, p_hero_key text, p_level integer DEFAULT 1, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; c public.hero_catalog; v_hero_id uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO c FROM public.hero_catalog WHERE hero_key = p_hero_key;
  IF c.hero_key IS NULL THEN RAISE EXCEPTION 'hero_not_found'; END IF;
  INSERT INTO public.player_heroes (user_id, hero_key, name, rarity, level, image)
  VALUES (v_uid, c.hero_key, c.name, public.normalize_hero_rarity(c.rarity), GREATEST(1, COALESCE(p_level,1)), c.image)
  RETURNING id INTO v_hero_id;
  PERFORM public.admin_log(p_admin_id,'hero.grant','player',v_uid::text,NULL,
    jsonb_build_object('hero_id',v_hero_id,'hero_key',c.hero_key,'level',GREATEST(1,COALESCE(p_level,1))), p_reason);
  RETURN jsonb_build_object('user_id',v_uid,'hero_id',v_hero_id,'hero_key',c.hero_key,'name',c.name);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_hero(p_admin_id bigint, p_hero_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE h public.player_heroes;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO h FROM public.player_heroes WHERE id = p_hero_id;
  IF h.id IS NULL THEN RAISE EXCEPTION 'hero_not_found'; END IF;
  DELETE FROM public.pvp_team_slots WHERE hero_id = h.id;
  DELETE FROM public.hero_combat_state WHERE hero_id = h.id;
  DELETE FROM public.player_heroes WHERE id = h.id;
  PERFORM public.admin_log(p_admin_id,'hero.remove','player',h.user_id::text,
    jsonb_build_object('hero_id',h.id,'hero_key',h.hero_key,'name',h.name), NULL, p_reason);
  RETURN jsonb_build_object('user_id',h.user_id,'hero_id',h.id,'name',h.name);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_grant_pet(
  p_admin_id bigint, p_ref text, p_pet_slug text, p_rarity text DEFAULT 'raro', p_level integer DEFAULT 1, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; pt public.pets; v_id uuid; v_rarity text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO pt FROM public.pets WHERE slug = p_pet_slug OR id::text = p_pet_slug;
  IF pt.id IS NULL THEN RAISE EXCEPTION 'pet_not_found'; END IF;
  v_rarity := public.normalize_pet_rarity(COALESCE(p_rarity,'raro'));
  INSERT INTO public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active)
  VALUES (v_uid, pt.id, v_rarity, GREATEST(1, COALESCE(p_level,1)), 0, 'baby', 0, false)
  RETURNING id INTO v_id;
  PERFORM public.admin_log(p_admin_id,'pet.grant','player',v_uid::text,NULL,
    jsonb_build_object('player_pet_id',v_id,'pet',pt.slug,'rarity',v_rarity), p_reason);
  RETURN jsonb_build_object('user_id',v_uid,'player_pet_id',v_id,'pet',pt.name,'rarity',v_rarity);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_pet(p_admin_id bigint, p_player_pet_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE pp public.player_pets;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO pp FROM public.player_pets WHERE id = p_player_pet_id;
  IF pp.id IS NULL THEN RAISE EXCEPTION 'pet_not_found'; END IF;
  DELETE FROM public.player_pets WHERE id = pp.id;
  PERFORM public.admin_log(p_admin_id,'pet.remove','player',pp.user_id::text,
    jsonb_build_object('player_pet_id',pp.id,'pet_id',pp.pet_id,'rarity',pp.rarity), NULL, p_reason);
  RETURN jsonb_build_object('user_id',pp.user_id,'player_pet_id',pp.id);
END;
$$;

-- ---------------------------------------------------------
-- ban / vip / reset
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_ban(p_admin_id bigint, p_ref text, p_banned boolean, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_old boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_banned AND COALESCE(btrim(p_reason),'') = '' THEN RAISE EXCEPTION 'reason_required'; END IF;
  v_uid := public.admin_resolve_player(p_ref);
  SELECT banned INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
  UPDATE public.game_players
     SET banned = p_banned,
         ban_reason = CASE WHEN p_banned THEN p_reason ELSE NULL END,
         banned_at = CASE WHEN p_banned THEN now() ELSE NULL END,
         pvp_banned = p_banned,
         updated_at = now()
   WHERE id = v_uid;
  PERFORM public.admin_log(p_admin_id, CASE WHEN p_banned THEN 'player.ban' ELSE 'player.unban' END,'player',v_uid::text,
    jsonb_build_object('banned',v_old), jsonb_build_object('banned',p_banned), p_reason);
  RETURN jsonb_build_object('user_id',v_uid,'banned',p_banned);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_membership(
  p_admin_id bigint, p_ref text, p_tier text, p_days integer, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_tier text := lower(COALESCE(p_tier,'vip')); v_old timestamptz; v_new timestamptz;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_tier NOT IN ('vip','premium') THEN RAISE EXCEPTION 'invalid_tier'; END IF;
  v_uid := public.admin_resolve_player(p_ref);
  v_new := CASE WHEN COALESCE(p_days,0) <= 0 THEN NULL ELSE now() + make_interval(days => p_days) END;
  IF v_tier = 'vip' THEN
    SELECT vip_until INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    UPDATE public.game_players SET vip_until = v_new, updated_at = now() WHERE id = v_uid;
  ELSE
    SELECT premium_until INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    UPDATE public.game_players SET premium_until = v_new, updated_at = now() WHERE id = v_uid;
  END IF;
  PERFORM public.admin_log(p_admin_id,'membership.'||v_tier,'player',v_uid::text,
    jsonb_build_object('until',v_old), jsonb_build_object('until',v_new), p_reason);
  RETURN jsonb_build_object('user_id',v_uid,'tier',v_tier,'until',v_new);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reset_account(p_admin_id bigint, p_ref text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF COALESCE(btrim(p_reason),'') = '' THEN RAISE EXCEPTION 'reason_required'; END IF;
  v_uid := public.admin_resolve_player(p_ref);
  SELECT jsonb_build_object('forge_coins',forge_coins,'trophies',pvp_trophies,'tickets',pvp_tickets,
    'heroes',(SELECT count(*) FROM public.player_heroes WHERE user_id = v_uid),
    'pets',(SELECT count(*) FROM public.player_pets WHERE user_id = v_uid))
  INTO v_old FROM public.game_players WHERE id = v_uid;

  DELETE FROM public.pvp_team_slots WHERE user_id = v_uid;
  DELETE FROM public.hero_combat_state WHERE combat_id IN (SELECT id FROM public.boss_combats WHERE user_id = v_uid);
  DELETE FROM public.boss_combats WHERE user_id = v_uid;
  DELETE FROM public.player_heroes WHERE user_id = v_uid;
  DELETE FROM public.player_pets WHERE user_id = v_uid;
  DELETE FROM public.player_pet_inventory WHERE user_id = v_uid;
  DELETE FROM public.player_pet_food WHERE user_id = v_uid;
  DELETE FROM public.player_inventory WHERE user_id = v_uid;
  DELETE FROM public.player_mission_progress WHERE user_id = v_uid;
  UPDATE public.game_players
     SET forge_coins = 0, ton_balance = 0, pvp_trophies = 0,
         pvp_tickets = COALESCE((SELECT (value #>> '{}')::int FROM public.game_settings WHERE key = 'pvp_ticket_start'), 5),
         pvp_wins = 0, pvp_losses = 0, boss_defeats = 0, updated_at = now()
   WHERE id = v_uid;

  PERFORM public.admin_log(p_admin_id,'player.reset','player',v_uid::text,v_old,'{}'::jsonb,p_reason,
    jsonb_build_object('dangerous',true));
  RETURN jsonb_build_object('user_id',v_uid,'reset',true);
END;
$$;

-- ---------------------------------------------------------
REVOKE ALL ON FUNCTION public.admin_super_id() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_assert(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_log(bigint,text,text,text,jsonb,jsonb,text,jsonb) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_bump_settings_version() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_get_settings(bigint,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_setting(bigint,text,jsonb,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_resolve_player(text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_search_players(bigint,text,integer) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_player_detail(bigint,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_player_history(bigint,text,integer) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_adjust_balance(bigint,text,text,text,numeric,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_adjust_pvp_stat(bigint,text,text,text,numeric,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_grant_hero(bigint,text,text,integer,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_remove_hero(bigint,uuid,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_grant_pet(bigint,text,text,text,integer,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_remove_pet(bigint,uuid,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_ban(bigint,text,boolean,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_membership(bigint,text,text,integer,text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_reset_account(bigint,text,text) FROM anon, authenticated;
