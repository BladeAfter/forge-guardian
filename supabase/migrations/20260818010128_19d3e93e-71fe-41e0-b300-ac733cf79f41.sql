CREATE OR REPLACE FUNCTION public.admin_hero_mining_set_limit(p_admin_id bigint, p_ref text, p_amount_ton numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid;
  v_others numeric;
  v_delta numeric;
  v_target numeric := round(GREATEST(0, COALESCE(p_amount_ton, 0)), 9);
  v_total numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  v_user := admin_resolve_player(p_ref);
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  DELETE FROM hero_mining_investments
   WHERE user_id = v_user AND source_type = 'admin_manual';

  SELECT round(COALESCE(SUM(amount_ton), 0), 9) INTO v_others
    FROM hero_mining_investments WHERE user_id = v_user;

  v_delta := round(v_target - COALESCE(v_others, 0), 9);
  IF v_delta > 0 THEN
    INSERT INTO hero_mining_investments (user_id, source_type, reference, amount_ton)
    VALUES (v_user, 'admin_manual', 'admin_manual:' || v_user::text || ':' || extract(epoch from now())::bigint, v_delta);
  END IF;

  v_total := hero_mining_sync_invested(v_user);
  PERFORM hero_mining_accrue(v_user);

  PERFORM admin_log(p_admin_id, 'hero_mining_set_limit', v_user::text,
    jsonb_build_object('targetTon', v_target, 'investedTon', v_total));

  RETURN admin_hero_mining_user(p_admin_id, p_ref);
END $function$;