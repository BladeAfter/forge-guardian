CREATE OR REPLACE FUNCTION public.create_clan(p_telegram_id bigint, p_name text, p_tag text, p_description text, p_join_type text, p_min_trophies integer, p_emblem jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; v_cost numeric; v_bal numeric; c public.clans%rowtype; v_name text; v_tag text; v_limit integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('clan:'||v_uid::text, 0));
  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
  v_name := btrim(COALESCE(p_name,''));
  v_tag := upper(btrim(COALESCE(p_tag,'')));
  IF length(v_name) < 3 OR length(v_name) > 24 THEN RAISE EXCEPTION 'INVALID_CLAN_NAME'; END IF;
  IF v_tag !~ '^[A-Z0-9]{2,5}$' THEN RAISE EXCEPTION 'INVALID_CLAN_TAG'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE lower(name) = lower(v_name)) THEN RAISE EXCEPTION 'CLAN_NAME_TAKEN'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE upper(tag) = v_tag) THEN RAISE EXCEPTION 'CLAN_TAG_TAKEN'; END IF;
  IF COALESCE(p_join_type,'open') NOT IN ('open','approval','closed') THEN RAISE EXCEPTION 'INVALID_JOIN_TYPE'; END IF;

  v_cost := COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000);
  v_limit := GREATEST(2, COALESCE((SELECT value::text::int FROM public.game_settings WHERE key='clan_default_member_limit'), public.clan_member_limit(1)));
  SELECT forge_coins INTO v_bal FROM public.game_players WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_bal,0) < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;

  INSERT INTO public.clans(name, tag, description, leader_user_id, join_type, minimum_trophies, member_limit, emblem_config)
  VALUES (v_name, v_tag, COALESCE(btrim(p_description),''), v_uid, COALESCE(p_join_type,'open'), GREATEST(0, COALESCE(p_min_trophies,0)),
          v_limit, COALESCE(p_emblem, '{}'::jsonb))
  RETURNING * INTO c;

  INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (c.id, v_uid, 'leader');

  UPDATE public.game_players SET forge_coins = forge_coins - v_cost, updated_at = now() WHERE id = v_uid;
  INSERT INTO public.wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (v_uid, 'clan_create', -v_cost, v_bal, v_bal - v_cost, 'clan:'||c.id::text);

  INSERT INTO public.clan_boss_cycles(clan_id) VALUES (c.id);
  RETURN jsonb_build_object('status','created','clan', public.clan_public(c));
END; $function$;