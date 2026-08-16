CREATE OR REPLACE FUNCTION public.clan_manage(p_telegram_id bigint, p_action text, p_target uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid; v_clan uuid; v_role text; v_trole text; v_count integer; c public.clans%rowtype; v_req uuid;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, role INTO v_clan, v_role FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;
  SELECT * INTO c FROM public.clans WHERE id = v_clan;

  IF p_action = 'edit' THEN
    IF public.clan_role_rank(v_role) < 3 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clans SET
      description = COALESCE(NULLIF(btrim(p_payload->>'description'),''), description),
      join_type = COALESCE(NULLIF(p_payload->>'joinType',''), join_type),
      minimum_trophies = COALESCE((p_payload->>'minimumTrophies')::int, minimum_trophies),
      emblem_config = COALESCE(p_payload->'emblem', emblem_config),
      updated_at = now()
     WHERE id = v_clan;
    RETURN jsonb_build_object('status','updated');
  END IF;

  IF p_target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  SELECT role INTO v_trole FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;

  IF p_action IN ('accept','reject') THEN
    IF public.clan_role_rank(v_role) < 2 THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    PERFORM 1 FROM public.clans WHERE id = v_clan FOR UPDATE;
    SELECT id INTO v_req FROM public.clan_join_requests
      WHERE clan_id = v_clan AND user_id = p_target AND status = 'pending' FOR UPDATE;
    IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
    IF p_action = 'reject' THEN
      UPDATE public.clan_join_requests SET status='rejected' WHERE id = v_req;
      RETURN jsonb_build_object('status','rejected');
    END IF;
    SELECT count(*) INTO v_count FROM public.clan_members WHERE clan_id = v_clan;
    IF v_count >= c.member_limit THEN RAISE EXCEPTION 'CLAN_FULL'; END IF;
    -- The applicant joined another clan meanwhile: drop the stale request and
    -- report it as the TARGET being taken, never as the manager themselves.
    IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = p_target) THEN
      UPDATE public.clan_join_requests SET status='cancelled' WHERE id = v_req;
      RAISE EXCEPTION 'TARGET_ALREADY_IN_CLAN';
    END IF;
    INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (v_clan, p_target, 'member');
    UPDATE public.clan_join_requests SET status='accepted' WHERE id = v_req;
    RETURN jsonb_build_object('status','accepted');
  END IF;

  IF v_trole IS NULL THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;

  IF p_action = 'kick' THEN
    IF public.clan_role_rank(v_role) < 3 OR public.clan_role_rank(v_trole) >= public.clan_role_rank(v_role) THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    DELETE FROM public.clan_members WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','kicked');
  ELSIF p_action IN ('promote','demote') THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    IF v_trole = 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role = CASE
        WHEN p_action='promote' THEN CASE v_trole WHEN 'member' THEN 'officer' WHEN 'officer' THEN 'co-leader' ELSE 'co-leader' END
        ELSE CASE v_trole WHEN 'co-leader' THEN 'officer' WHEN 'officer' THEN 'member' ELSE 'member' END END,
      updated_at = now()
     WHERE user_id = p_target AND clan_id = v_clan;
    RETURN jsonb_build_object('status','role_changed');
  ELSIF p_action = 'transfer' THEN
    IF v_role <> 'leader' THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
    UPDATE public.clan_members SET role='leader' WHERE user_id = p_target AND clan_id = v_clan;
    UPDATE public.clan_members SET role='co-leader' WHERE user_id = v_uid AND clan_id = v_clan;
    UPDATE public.clans SET leader_user_id = p_target, updated_at = now() WHERE id = v_clan;
    RETURN jsonb_build_object('status','transferred');
  END IF;
  RAISE EXCEPTION 'INVALID_ACTION';
END; $function$;

REVOKE ALL ON FUNCTION public.clan_manage(bigint, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clan_manage(bigint, text, uuid, jsonb) TO service_role;