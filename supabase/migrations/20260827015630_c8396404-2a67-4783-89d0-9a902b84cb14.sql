CREATE OR REPLACE FUNCTION public.roulette_spin(p_telegram_id bigint, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$

DECLARE s public.global_roulette_settings; u uuid; prev public.global_roulette_spins;
        v_nano bigint; v_ton numeric; v_before numeric; v_after numeric; sid uuid;
        v_addr text; v_comment text;
BEGIN
  SELECT * INTO s FROM public.global_roulette_settings WHERE id;
  IF s.id IS NULL OR NOT s.enabled THEN RAISE EXCEPTION 'ROULETTE_DISABLED'; END IF;
  IF s.paused THEN RAISE EXCEPTION 'ROULETTE_PAUSED'; END IF;

  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO prev FROM public.global_roulette_spins WHERE user_id = u AND idempotency_key = p_idempotency_key;
    IF prev.id IS NOT NULL THEN
      IF prev.status = 'SETTLED' THEN RETURN coalesce(prev.result_json,'{}'::jsonb) || jsonb_build_object('replay', true); END IF;
      IF prev.status IN ('PAID','RESOLVING','FAILED_RECOVERABLE') THEN RETURN public.roulette_resolve(prev.id); END IF;
      RETURN jsonb_build_object('ok', true, 'needsPayment', true, 'spinId', prev.id,
        'paymentAddress', prev.payment_address, 'paymentComment', prev.payment_comment,
        'amountNano', prev.amount_nanoton::text, 'amountTon', round(prev.amount_nanoton::numeric/1000000000, 9));
    END IF;
  END IF;

  v_nano := greatest(1, coalesce(s.spin_cost_nanoton, 5000000000));
  v_ton := round(v_nano::numeric / 1000000000, 9);

  SELECT coalesce(ton_balance,0) INTO v_before FROM public.game_players WHERE id = u FOR UPDATE;
  IF v_before >= v_ton THEN
    v_after := round(v_before - v_ton, 9);
    UPDATE public.game_players SET ton_balance = v_after, updated_at = now() WHERE id = u;
    INSERT INTO public.global_roulette_spins(user_id, payment_source, amount_nanoton, status, paid_at, idempotency_key)
    VALUES (u, 'ton_internal', v_nano, 'PAID', now(), p_idempotency_key) RETURNING id INTO sid;
    -- one ledger row per spin: reference_id must be unique per (type, reference_id)
    INSERT INTO public.wallet_ledger(user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
    VALUES (u, 'roulette_spin', 0, -v_ton, v_before, v_after, 'global_roulette:'||sid::text)
    ON CONFLICT DO NOTHING;
    BEGIN PERFORM public.record_spending_points(u, 'global_roulette_spin', 'roulette_spin:'||sid::text, 'TON', v_ton);
    EXCEPTION WHEN OTHERS THEN NULL; END;
    RETURN public.roulette_resolve(sid);
  END IF;

  -- internal balance stays untouched: the wallet pays 100% of the spin
  SELECT value_text INTO v_addr FROM public.wallet_settings WHERE key = 'ton_hot_wallet';
  IF coalesce(v_addr,'') = '' THEN RAISE EXCEPTION 'TON_HOT_WALLET_MISSING'; END IF;
  sid := gen_random_uuid();
  v_comment := 'gr' || replace(sid::text, '-', '');
  INSERT INTO public.global_roulette_spins(id, user_id, payment_source, amount_nanoton, status,
      payment_address, payment_comment, expires_at, idempotency_key)
  VALUES (sid, u, 'ton_external', v_nano, 'PAYMENT_PENDING', v_addr, v_comment,
      now() + make_interval(mins => greatest(5, coalesce(s.payment_ttl_minutes, 30))), p_idempotency_key);

  RETURN jsonb_build_object('ok', true, 'needsPayment', true, 'spinId', sid,
    'paymentAddress', v_addr, 'paymentComment', v_comment,
    'amountNano', v_nano::text, 'amountTon', v_ton, 'internalTon', v_before);
END
$fn$;

REVOKE ALL ON FUNCTION public.roulette_spin(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.roulette_spin(bigint, text) TO service_role;