CREATE OR REPLACE FUNCTION public.admin_clans(p_admin_id bigint, p_action text DEFAULT 'list'::text, p_ref text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE c public.clans%rowtype; v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);

  IF p_action IN ('list','ranking') THEN
    RETURN jsonb_build_object('clans', COALESCE((SELECT jsonb_agg(public.clan_public(x))
      FROM (SELECT * FROM public.clans ORDER BY level DESC, xp DESC LIMIT 30) x), '[]'::jsonb));
  END IF;

  IF p_action = 'search' THEN
    RETURN jsonb_build_object('clans', COALESCE((SELECT jsonb_agg(public.clan_public(x))
      FROM (SELECT * FROM public.clans WHERE lower(name) LIKE '%'||lower(COALESCE(p_ref,''))||'%'
        OR upper(tag) = upper(COALESCE(p_ref,'')) ORDER BY level DESC LIMIT 20) x), '[]'::jsonb));
  END IF;

  SELECT * INTO c FROM public.clans WHERE id::text = p_ref OR upper(tag) = upper(COALESCE(p_ref,''));
  IF c.id IS NULL THEN RAISE EXCEPTION 'CLAN_NOT_FOUND'; END IF;

  IF p_action = 'detail' THEN
    RETURN jsonb_build_object('clan', public.clan_public(c),
      'members', COALESCE((SELECT jsonb_agg(jsonb_build_object('userId', m.user_id, 'telegramId', g.telegram_id,
          'name', COALESCE(g.display_name,g.first_name,'Player'), 'role', m.role, 'contribution', m.contribution)
          ORDER BY public.clan_role_rank(m.role) DESC)
        FROM public.clan_members m JOIN public.game_players g ON g.id=m.user_id WHERE m.clan_id=c.id), '[]'::jsonb),
      'missions', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', mission_code, 'progress', progress, 'completed', completed))
        FROM public.clan_mission_progress WHERE clan_id=c.id AND week_key = public.clan_week_key()), '[]'::jsonb),
      'boss', (SELECT jsonb_build_object('name', name, 'currentHealth', current_health, 'maxHealth', max_health, 'status', status)
        FROM public.clan_boss_cycles WHERE clan_id=c.id AND status='active' ORDER BY started_at DESC LIMIT 1),
      'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('source', source, 'xp', xp_amount, 'at', created_at))
        FROM (SELECT * FROM public.clan_xp_ledger WHERE clan_id=c.id ORDER BY created_at DESC LIMIT 15) a), '[]'::jsonb));
  END IF;

  v_old := public.clan_public(c);

  IF p_action = 'xp' THEN
    UPDATE public.clans SET xp = GREATEST(0, xp + COALESCE((p_payload->>'xp')::int,0)),
      level = GREATEST(1, COALESCE((p_payload->>'level')::int, level)), updated_at = now() WHERE id = c.id;
  ELSIF p_action = 'edit' THEN
    UPDATE public.clans SET
      name = COALESCE(NULLIF(btrim(p_payload->>'name'),''), name),
      tag = COALESCE(NULLIF(upper(btrim(p_payload->>'tag')),''), tag),
      member_limit = COALESCE((p_payload->>'memberLimit')::int, member_limit),
      join_type = COALESCE(NULLIF(p_payload->>'joinType',''), join_type),
      minimum_trophies = COALESCE((p_payload->>'minimumTrophies')::int, minimum_trophies),
      description = COALESCE(NULLIF(btrim(p_payload->>'description'),''), description),
      updated_at = now() WHERE id = c.id;
  ELSIF p_action = 'suspend' THEN
    UPDATE public.clans SET suspended = NOT suspended, updated_at = now() WHERE id = c.id;
  ELSIF p_action = 'delete' THEN
    DELETE FROM public.clans WHERE id = c.id;
    PERFORM public.admin_log(p_admin_id, 'clans.delete', 'clan', c.id::text, v_old, NULL, 'exclusão pelo bot admin', p_payload);
    RETURN jsonb_build_object('status','deleted','clan', v_old);
  ELSIF p_action = 'boss' THEN
    UPDATE public.clan_boss_cycles SET status='ended', finished_at=now() WHERE clan_id=c.id AND status='active';
    INSERT INTO public.clan_boss_cycles(clan_id, max_health, current_health)
    VALUES (c.id, COALESCE((p_payload->>'hp')::numeric, 1000000), COALESCE((p_payload->>'hp')::numeric, 1000000));
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  PERFORM public.admin_log(p_admin_id, 'clans.'||p_action, 'clan', c.id::text, v_old,
    public.clan_public((SELECT x FROM public.clans x WHERE x.id = c.id)), 'painel admin', p_payload);
  RETURN jsonb_build_object('status','ok','clan', public.clan_public((SELECT x FROM public.clans x WHERE x.id = c.id)));
END; $function$;