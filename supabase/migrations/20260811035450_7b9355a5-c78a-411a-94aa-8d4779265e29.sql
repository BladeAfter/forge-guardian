CREATE OR REPLACE FUNCTION public.admin_adjust_balance(p_admin_id bigint, p_ref text, p_currency text, p_mode text, p_amount numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid; v_old numeric; v_new numeric; v_ref text;
  v_cur text := lower(COALESCE(p_currency,'fc')); v_mode text := lower(COALESCE(p_mode,'add'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_cur NOT IN ('fc','ton') THEN RAISE EXCEPTION 'invalid_currency'; END IF;
  IF v_mode NOT IN ('add','remove','set') THEN RAISE EXCEPTION 'invalid_mode'; END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  v_uid := public.admin_resolve_player(p_ref);
  v_ref := 'admin:'||p_admin_id||':'||gen_random_uuid()::text;

  IF v_cur = 'fc' THEN
    SELECT forge_coins INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    v_new := CASE v_mode WHEN 'add' THEN v_old + p_amount WHEN 'remove' THEN GREATEST(0, v_old - p_amount) ELSE p_amount END;
    UPDATE public.game_players SET forge_coins = v_new, updated_at = now() WHERE id = v_uid;
    INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
    VALUES (v_uid, 'admin_balance_adjustment', v_new - v_old, v_old, v_new, v_ref);
  ELSE
    SELECT ton_balance INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    v_new := CASE v_mode WHEN 'add' THEN v_old + p_amount WHEN 'remove' THEN GREATEST(0, v_old - p_amount) ELSE p_amount END;
    UPDATE public.game_players SET ton_balance = v_new, updated_at = now() WHERE id = v_uid;
    INSERT INTO public.wallet_ledger (user_id, type, amount_ton, balance_before, balance_after, reference_id)
    VALUES (v_uid, 'admin_balance_adjustment', v_new - v_old, v_old, v_new, v_ref);
  END IF;

  PERFORM public.admin_log(p_admin_id, 'balance.'||v_cur||'.'||v_mode, 'player', v_uid::text,
    jsonb_build_object(v_cur, v_old), jsonb_build_object(v_cur, v_new), p_reason,
    jsonb_build_object('amount', p_amount, 'financial', true));
  RETURN jsonb_build_object('user_id', v_uid, 'currency', v_cur, 'old_value', v_old, 'new_value', v_new);
END; $$;