-- ═══ helpers ═══
CREATE OR REPLACE FUNCTION public.roulette_user_has_celestial(p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.roulette_celestial_awards WHERE user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.player_heroes WHERE user_id = p_user AND lower(rarity) = 'celestial');
$$;

-- Secretly picks the premium target of a brand new cycle and opens it.
CREATE OR REPLACE FUNCTION public.roulette_open_cycle()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.global_roulette_settings; v_class text; v_key text; v_cost bigint; v_id uuid; v_step bigint;
BEGIN
  SELECT * INTO s FROM public.global_roulette_settings WHERE id;
  v_step := greatest(1, coalesce(s.spin_cost_nanoton, 5000000000));

  SELECT k INTO v_class FROM (
    SELECT 'MYTHIC_HERO'::text AS k, coalesce(s.weight_mythic,0) AS w
     WHERE EXISTS (SELECT 1 FROM public.roulette_reward_config WHERE reward_class='MYTHIC_HERO' AND enabled)
    UNION ALL
    SELECT 'NFT_HERO', coalesce(s.weight_nft_hero,0)
     WHERE EXISTS (
       SELECT 1 FROM public.roulette_reward_config c WHERE c.reward_class='NFT_HERO' AND c.enabled
        AND EXISTS (SELECT 1 FROM public.nft_heroes n WHERE n.hero_template_id=c.reward_key AND n.owner_user_id IS NULL AND n.status='AVAILABLE'))
    UNION ALL
    SELECT 'CELESTIAL_HERO', coalesce(s.weight_celestial,0)
     WHERE EXISTS (SELECT 1 FROM public.roulette_reward_config WHERE reward_class='CELESTIAL_HERO' AND enabled)
  ) pool WHERE w > 0 ORDER BY -ln(random()) / w LIMIT 1;

  IF v_class IS NULL THEN RAISE EXCEPTION 'ROULETTE_NO_PREMIUM_POOL'; END IF;

  SELECT c.reward_key, c.reference_cost_nanoton INTO v_key, v_cost
    FROM public.roulette_reward_config c
   WHERE c.reward_class = v_class AND c.enabled AND c.weight > 0
     AND (v_class <> 'NFT_HERO' OR EXISTS (
       SELECT 1 FROM public.nft_heroes n WHERE n.hero_template_id=c.reward_key AND n.owner_user_id IS NULL AND n.status='AVAILABLE'))
   ORDER BY -ln(random()) / c.weight LIMIT 1;
  IF v_key IS NULL THEN RAISE EXCEPTION 'ROULETTE_NO_PREMIUM_POOL'; END IF;

  -- CELESTIAL is always gated by the fixed global threshold (300 TON by default)
  IF v_class = 'CELESTIAL_HERO' THEN v_cost := coalesce(s.celestial_threshold_nanoton, 300000000000); END IF;
  v_cost := greatest(v_step, ceil(coalesce(v_cost, v_step)::numeric / v_step)::bigint * v_step);

  INSERT INTO public.global_roulette_cycles(status, target_reward_type, target_reward_id,
      target_reference_cost_nanoton, config_snapshot)
  VALUES ('ACCUMULATING', v_class, v_key, v_cost,
      jsonb_build_object('spinCostNano', s.spin_cost_nanoton, 'celestialThresholdNano', s.celestial_threshold_nanoton,
        'weights', jsonb_build_object('mythic', s.weight_mythic, 'nftHero', s.weight_nft_hero, 'celestial', s.weight_celestial)))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- Serialised access to the single open cycle (advisory lock + row lock).
CREATE OR REPLACE FUNCTION public.roulette_lock_open_cycle()
RETURNS public.global_roulette_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.global_roulette_cycles;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('global_mystery_roulette_cycle'));
  SELECT * INTO c FROM public.global_roulette_cycles
   WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING')
   ORDER BY cycle_number LIMIT 1 FOR UPDATE;
  IF c.id IS NULL THEN
    PERFORM public.roulette_open_cycle();
    SELECT * INTO c FROM public.global_roulette_cycles
     WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING')
     ORDER BY cycle_number LIMIT 1 FOR UPDATE;
  END IF;
  RETURN c;
END $$;

-- MYTH never gets minted: it can only leave the roulette reserve.
CREATE OR REPLACE FUNCTION public.roulette_pay_myth(p_user uuid, p_amount numeric)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.roulette_myth_reserve;
BEGIN
  IF coalesce(p_amount,0) <= 0 THEN RETURN false; END IF;
  SELECT * INTO r FROM public.roulette_myth_reserve WHERE id FOR UPDATE;
  IF r.id IS NULL OR (r.allocated_myth - r.distributed_myth) < p_amount THEN
    RAISE LOG 'ROULETTE_MYTH_RESERVE_EMPTY requested=% available=%', p_amount, coalesce(r.allocated_myth - r.distributed_myth, 0);
    RETURN false;
  END IF;
  UPDATE public.roulette_myth_reserve SET distributed_myth = distributed_myth + p_amount, updated_at = now() WHERE id;
  INSERT INTO public.myth_balances(user_id, amount) VALUES (p_user, p_amount)
    ON CONFLICT (user_id) DO UPDATE SET amount = public.myth_balances.amount + excluded.amount, updated_at = now();
  INSERT INTO public.myth_ledger(user_id, direction, amount, reason) VALUES (p_user, 'credit', p_amount, 'global_roulette');
  RETURN true;
END $$;

-- Normal reward (MYTH / NFT EQUIPMENT). Always rolled, independent of the mystery goal.
CREATE OR REPLACE FUNCTION public.roulette_roll_normal(p_user uuid, p_spin uuid, p_cycle uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.global_roulette_settings; v_class text; v_key text; v_qty numeric; v_label text;
        v_nft uuid; v_res jsonb; v_serial int; v_name text;
BEGIN
  SELECT * INTO s FROM public.global_roulette_settings WHERE id;

  SELECT k INTO v_class FROM (
    SELECT 'MYTH'::text k, coalesce(s.normal_weight_myth,0) w
     WHERE EXISTS (SELECT 1 FROM public.roulette_reward_config WHERE reward_class='MYTH' AND enabled)
    UNION ALL
    SELECT 'NFT_EQUIPMENT', coalesce(s.normal_weight_equipment,0)
     WHERE EXISTS (SELECT 1 FROM public.roulette_reward_config WHERE reward_class='NFT_EQUIPMENT' AND enabled)
  ) p WHERE w > 0 ORDER BY -ln(random())/w LIMIT 1;

  FOR i IN 1..2 LOOP
    IF v_class = 'NFT_EQUIPMENT' THEN
      SELECT c.reward_key, c.label INTO v_key, v_label FROM public.roulette_reward_config c
       WHERE c.reward_class='NFT_EQUIPMENT' AND c.enabled AND c.weight>0
       ORDER BY -ln(random())/c.weight LIMIT 1;
      SELECT n.id, n.nft_serial INTO v_nft, v_serial
        FROM public.nft_equipment n JOIN public.equipment_templates t ON t.id = n.template_id
       WHERE n.owner_user_id IS NULL AND n.status='AVAILABLE' AND lower(t.rarity) = lower(v_key)
       ORDER BY random() LIMIT 1 FOR UPDATE OF n SKIP LOCKED;
      IF v_nft IS NOT NULL THEN
        v_res := public.nft_equipment_assign_unit(v_nft, p_user, 'GLOBAL_ROULETTE_EQUIPMENT');
        INSERT INTO public.global_roulette_awards(spin_id, cycle_id, user_id, reward_class, reward_key, source_type, amount, payload)
        VALUES (p_spin, p_cycle, p_user, 'NFT_EQUIPMENT', v_key, 'GLOBAL_ROULETTE_EQUIPMENT', 1, v_res);
        RETURN jsonb_build_object('class','NFT_EQUIPMENT','rarity', v_key, 'name', v_res->>'name',
          'slot', v_res->>'slot', 'serial', v_serial, 'amount', 1);
      END IF;
      v_class := 'MYTH'; -- no NFT unit in stock: fall back to the MYTH tier roll
    ELSIF v_class = 'MYTH' THEN
      SELECT c.reward_key, c.quantity, c.label INTO v_key, v_qty, v_label FROM public.roulette_reward_config c
       WHERE c.reward_class='MYTH' AND c.enabled AND c.weight>0 AND c.quantity>0
       ORDER BY -ln(random())/c.weight LIMIT 1;
      IF v_key IS NOT NULL AND public.roulette_pay_myth(p_user, v_qty) THEN
        INSERT INTO public.global_roulette_awards(spin_id, cycle_id, user_id, reward_class, reward_key, source_type, amount, payload)
        VALUES (p_spin, p_cycle, p_user, 'MYTH', v_key, 'GLOBAL_ROULETTE_MYTH', v_qty, jsonb_build_object('label', v_label));
        RETURN jsonb_build_object('class','MYTH','tier', v_key, 'label', v_label, 'amount', v_qty);
      END IF;
      IF coalesce(s.myth_shortage_behavior,'SKIP') = 'EQUIPMENT' THEN v_class := 'NFT_EQUIPMENT'; ELSE EXIT; END IF;
    ELSE EXIT;
    END IF;
  END LOOP;

  INSERT INTO public.global_roulette_awards(spin_id, cycle_id, user_id, reward_class, reward_key, source_type, amount, payload)
  VALUES (p_spin, p_cycle, p_user, 'NONE', null, 'GLOBAL_ROULETTE_NONE', 0, jsonb_build_object('reason','no_normal_reward_available'));
  RETURN jsonb_build_object('class','NONE','amount',0);
END $$;

-- Premium delivery. Returns NULL when it could not be delivered (cycle stays pending).
CREATE OR REPLACE FUNCTION public.roulette_grant_premium(p_user uuid, p_cycle uuid, p_spin uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_roulette_cycles; c public.hero_catalog; v_hero uuid; ph public.player_heroes;
        v_nft uuid; v_res jsonb; v_out jsonb;
BEGIN
  SELECT * INTO cyc FROM public.global_roulette_cycles WHERE id = p_cycle;
  IF cyc.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO c FROM public.hero_catalog WHERE hero_key = cyc.target_reward_id;

  IF cyc.target_reward_type = 'NFT_HERO' THEN
    SELECT n.id INTO v_nft FROM public.nft_heroes n
     WHERE n.hero_template_id = cyc.target_reward_id AND n.owner_user_id IS NULL AND n.status='AVAILABLE'
     ORDER BY n.nft_serial LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF v_nft IS NULL THEN RETURN NULL; END IF;
    -- MINING OFF before ownership is set (the yield guard freezes the rates afterwards)
    UPDATE public.nft_heroes
       SET mining_daily_ton = 0, mining_daily_myth = 0, mining_dual = false,
           metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('mining_enabled', false, 'source','GLOBAL_ROULETTE')
     WHERE id = v_nft;
    v_res := public.nft_hero_assign_unit(v_nft, p_user, 'GLOBAL_ROULETTE_NFT_HERO');
    UPDATE public.player_heroes SET mining_daily_myth = 0, premium_source = 'GLOBAL_ROULETTE_NFT_HERO'
     WHERE id = (v_res->>'playerHeroId')::uuid;
    v_out := jsonb_build_object('class','NFT_HERO','heroKey', cyc.target_reward_id, 'name', v_res->>'heroName',
      'serial', v_res->>'serial', 'image', c.image, 'mining', false,
      'atk', v_res->>'atk', 'hp', v_res->>'hp', 'power', c.power);
  ELSE
    IF c.hero_key IS NULL THEN RETURN NULL; END IF;
    IF cyc.target_reward_type = 'CELESTIAL_HERO' AND public.roulette_user_has_celestial(p_user) THEN RETURN NULL; END IF;
    INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image, archetype, premium_source)
    VALUES (p_user, c.hero_key, c.name, public.normalize_hero_rarity(c.rarity), greatest(1, c.start_level), c.image,
            c.hero_class, 'GLOBAL_ROULETTE_' || cyc.target_reward_type)
    RETURNING id INTO v_hero;
    SELECT * INTO ph FROM public.player_heroes WHERE id = v_hero;
    IF cyc.target_reward_type = 'CELESTIAL_HERO' THEN
      INSERT INTO public.roulette_celestial_awards(user_id, hero_key, player_hero_id, cycle_id, spin_id)
      VALUES (p_user, c.hero_key, v_hero, p_cycle, p_spin);
    END IF;
    v_out := jsonb_build_object('class', cyc.target_reward_type, 'heroKey', c.hero_key, 'name', c.name,
      'rarity', public.normalize_hero_rarity(c.rarity), 'image', c.image, 'power', c.power,
      'atk', round(coalesce(ph.final_atk,0)), 'hp', round(coalesce(ph.final_hp,0)), 'playerHeroId', v_hero);
  END IF;

  INSERT INTO public.global_roulette_awards(spin_id, cycle_id, user_id, reward_class, reward_key, source_type, amount, payload)
  VALUES (p_spin, p_cycle, p_user, cyc.target_reward_type, cyc.target_reward_id,
          'GLOBAL_ROULETTE_' || cyc.target_reward_type, 1, v_out);
  RETURN v_out;
END $$;

-- ═══ RESOLVE — atomic, idempotent, concurrency safe ═══
CREATE OR REPLACE FUNCTION public.roulette_resolve(p_spin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE sp public.global_roulette_spins; cyc public.global_roulette_cycles;
        normal jsonb; premium jsonb := NULL; v_eligible boolean; res jsonb;
BEGIN
  SELECT * INTO sp FROM public.global_roulette_spins WHERE id = p_spin_id FOR UPDATE;
  IF sp.id IS NULL THEN RAISE EXCEPTION 'SPIN_NOT_FOUND'; END IF;
  IF sp.status = 'SETTLED' THEN RETURN coalesce(sp.result_json,'{}'::jsonb) || jsonb_build_object('replay', true); END IF;
  IF sp.status NOT IN ('PAID','RESOLVING','FAILED_RECOVERABLE') THEN RAISE EXCEPTION 'SPIN_NOT_PAID'; END IF;
  UPDATE public.global_roulette_spins SET status='RESOLVING' WHERE id = sp.id;

  IF sp.cycle_id IS NULL THEN
    cyc := public.roulette_lock_open_cycle();
    UPDATE public.global_roulette_cycles
       SET global_spend_nanoton = global_spend_nanoton + sp.amount_nanoton WHERE id = cyc.id
     RETURNING * INTO cyc;
    UPDATE public.global_roulette_spins SET cycle_id = cyc.id WHERE id = sp.id;
  ELSE
    PERFORM pg_advisory_xact_lock(hashtext('global_mystery_roulette_cycle'));
    SELECT * INTO cyc FROM public.global_roulette_cycles WHERE id = sp.cycle_id FOR UPDATE;
  END IF;

  normal := public.roulette_roll_normal(sp.user_id, sp.id, cyc.id);

  IF cyc.global_spend_nanoton >= cyc.target_reference_cost_nanoton
     AND cyc.status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER') THEN
    IF cyc.threshold_reached_at IS NULL THEN
      UPDATE public.global_roulette_cycles SET threshold_reached_at = now(), status='THRESHOLD_REACHED' WHERE id = cyc.id;
    END IF;
    v_eligible := (cyc.target_reward_type <> 'CELESTIAL_HERO') OR NOT public.roulette_user_has_celestial(sp.user_id);
    IF v_eligible THEN
      UPDATE public.global_roulette_cycles SET status='AWARDING' WHERE id = cyc.id;
      premium := public.roulette_grant_premium(sp.user_id, cyc.id, sp.id);
      IF premium IS NULL THEN
        -- goal is NOT charged again: the prize waits for the next valid/eligible spin
        UPDATE public.global_roulette_cycles
           SET status = CASE WHEN cyc.target_reward_type='CELESTIAL_HERO' THEN 'READY_FOR_ELIGIBLE_WINNER' ELSE 'THRESHOLD_REACHED' END
         WHERE id = cyc.id;
      ELSE
        UPDATE public.global_roulette_cycles
           SET status='AWARDED', winner_user_id = sp.user_id, winning_spin_id = sp.id, completed_at = now()
         WHERE id = cyc.id;
        UPDATE public.global_roulette_spins
           SET premium_reward_awarded = true, premium_reward_type = cyc.target_reward_type,
               premium_reward_id = cyc.target_reward_id
         WHERE id = sp.id;
        PERFORM public.roulette_open_cycle();
      END IF;
    ELSE
      UPDATE public.global_roulette_cycles SET status='READY_FOR_ELIGIBLE_WINNER' WHERE id = cyc.id;
    END IF;
  END IF;

  res := jsonb_build_object('ok', true, 'spinId', sp.id,
    'amountTon', round(sp.amount_nanoton::numeric / 1000000000, 9),
    'paymentSource', sp.payment_source, 'normal', normal, 'premium', premium);
  UPDATE public.global_roulette_spins
     SET status='SETTLED', settled_at = now(), result_json = res,
         normal_reward_type = normal->>'class',
         normal_reward_amount = nullif(normal->>'amount','')::numeric,
         normal_reward_json = normal
   WHERE id = sp.id;
  RETURN res;
END $$;

-- ═══ SPIN — internal TON in full, or a full-amount TonConnect intent ═══
CREATE OR REPLACE FUNCTION public.roulette_spin(p_telegram_id bigint, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
    INSERT INTO public.wallet_ledger(user_id, type, amount_fc, amount_ton, balance_before, balance_after, reference_id)
    VALUES (u, 'roulette_spin', 0, -v_ton, v_before, v_after, 'global_roulette');
    INSERT INTO public.global_roulette_spins(user_id, payment_source, amount_nanoton, status, paid_at, idempotency_key)
    VALUES (u, 'ton_internal', v_nano, 'PAID', now(), p_idempotency_key) RETURNING id INTO sid;
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
END $$;

CREATE OR REPLACE FUNCTION public.roulette_mark_paid(p_spin_id uuid, p_tx_hash text, p_amount_nano text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE sp public.global_roulette_spins; v_ton numeric;
BEGIN
  SELECT * INTO sp FROM public.global_roulette_spins WHERE id = p_spin_id FOR UPDATE;
  IF sp.id IS NULL THEN RAISE EXCEPTION 'SPIN_NOT_FOUND'; END IF;
  IF sp.status IN ('PAID','RESOLVING','SETTLED') THEN RETURN jsonb_build_object('ok', true, 'alreadyPaid', true); END IF;
  IF coalesce(nullif(p_amount_nano,'')::numeric, 0) < sp.amount_nanoton::numeric * 0.97 THEN
    RAISE EXCEPTION 'PAYMENT_AMOUNT_MISMATCH';
  END IF;
  v_ton := round(sp.amount_nanoton::numeric / 1000000000, 9);
  UPDATE public.global_roulette_spins
     SET status='PAID', paid_at = now(), tx_hash = nullif(p_tx_hash,''),
         received_nanoton = nullif(p_amount_nano,'')::numeric
   WHERE id = sp.id;
  BEGIN PERFORM public.record_spending_points(sp.user_id, 'global_roulette_spin', 'roulette_spin:'||sp.id::text, 'TON', v_ton);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM public.referral_pay_ton_commission(sp.user_id, 'global_roulette_spin', 'roulette_spin:'||sp.id::text, v_ton);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.roulette_pending_payments(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'awaitingPayment', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'paymentComment', payment_comment,
        'amountNano', amount_nanoton::text)) FROM public.global_roulette_spins
       WHERE user_id = u AND status = 'PAYMENT_PENDING' AND created_at > now() - interval '2 days'), '[]'::jsonb),
    'paidPendingSpin', coalesce((SELECT jsonb_agg(id) FROM public.global_roulette_spins
       WHERE user_id = u AND status IN ('PAID','RESOLVING','FAILED_RECOVERABLE')), '[]'::jsonb));
END $$;

-- Public state: never leaks the cycle target, the global spend or the remaining TON.
CREATE OR REPLACE FUNCTION public.roulette_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.global_roulette_settings; u uuid; v_ton numeric;
BEGIN
  SELECT * INTO s FROM public.global_roulette_settings WHERE id;
  SELECT id, coalesce(ton_balance,0) INTO u, v_ton FROM public.game_players WHERE telegram_id = p_telegram_id;
  RETURN jsonb_build_object(
    'enabled', coalesce(s.enabled,false), 'paused', coalesce(s.paused,false),
    'spinCostNano', coalesce(s.spin_cost_nanoton,5000000000)::text,
    'spinCostTon', round(coalesce(s.spin_cost_nanoton,5000000000)::numeric/1000000000, 9),
    'internalTon', coalesce(v_ton,0),
    'normalRewards', coalesce((SELECT jsonb_agg(jsonb_build_object('class', reward_class, 'key', reward_key,
        'label', label, 'amount', quantity) ORDER BY reward_class, quantity)
      FROM public.roulette_reward_config WHERE enabled AND reward_class IN ('MYTH','NFT_EQUIPMENT')), '[]'::jsonb),
    'mysteryCategories', jsonb_build_array('MYTHIC_HERO','NFT_HERO','CELESTIAL_HERO'),
    'mySpins', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'at', settled_at,
        'normal', normal_reward_json, 'premium', premium_reward_awarded) ORDER BY settled_at DESC)
      FROM (SELECT * FROM public.global_roulette_spins WHERE user_id = u AND status='SETTLED'
             ORDER BY settled_at DESC LIMIT 10) t), '[]'::jsonb));
END $$;

-- ═══ RECOVERY / RECONCILIATION ═══
CREATE OR REPLACE FUNCTION public.roulette_reconcile(p_max_age_minutes integer DEFAULT 1440)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; v_fixed int := 0; v_expired int := 0;
BEGIN
  FOR r IN SELECT id FROM public.global_roulette_spins
            WHERE status IN ('PAID','RESOLVING','FAILED_RECOVERABLE')
              AND created_at > now() - make_interval(mins => greatest(10, p_max_age_minutes)) LOOP
    BEGIN PERFORM public.roulette_resolve(r.id); v_fixed := v_fixed + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.global_roulette_spins SET status='FAILED_RECOVERABLE' WHERE id = r.id;
    END;
  END LOOP;
  UPDATE public.global_roulette_spins SET status='EXPIRED'
   WHERE status='PAYMENT_PENDING' AND expires_at < now() - interval '2 days';
  GET DIAGNOSTICS v_expired = ROW_COUNT;
  IF NOT EXISTS (SELECT 1 FROM public.global_roulette_cycles
                  WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING')) THEN
    PERFORM public.roulette_open_cycle();
  END IF;
  RETURN jsonb_build_object('resolved', v_fixed, 'expired', v_expired);
END $$;

-- The roulette is reachable only through the service role (edge functions / admin bot).
DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY['roulette_user_has_celestial','roulette_open_cycle','roulette_lock_open_cycle',
    'roulette_pay_myth','roulette_roll_normal','roulette_grant_premium','roulette_resolve','roulette_spin',
    'roulette_mark_paid','roulette_pending_payments','roulette_state','roulette_reconcile','roulette_touch'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I FROM PUBLIC, anon, authenticated', fn);
  END LOOP;
END $$;

SELECT public.roulette_open_cycle();