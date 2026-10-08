-- 1) Estados separados de meta e prêmio
ALTER TABLE public.global_roulette_cycles
  ADD COLUMN IF NOT EXISTS reward_status text NOT NULL DEFAULT 'PENDING',
  ADD COLUMN IF NOT EXISTS reward_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reward_last_error text,
  ADD COLUMN IF NOT EXISTS reward_delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS reward_delivery_key text;

-- 2) Ledger de entregas idempotente
CREATE TABLE IF NOT EXISTS public.global_roulette_reward_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES public.global_roulette_cycles(id) ON DELETE CASCADE,
  reward_slot text NOT NULL DEFAULT 'PREMIUM',
  delivery_key text NOT NULL,
  user_id uuid NOT NULL,
  reward_type text NOT NULL,
  reward_key text,
  source text NOT NULL DEFAULT 'EVENT_THRESHOLD_REWARD',
  spin_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  delivered_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS grrd_cycle_slot_uk ON public.global_roulette_reward_deliveries(cycle_id, reward_slot);
CREATE UNIQUE INDEX IF NOT EXISTS grrd_delivery_key_uk ON public.global_roulette_reward_deliveries(delivery_key);
GRANT SELECT ON public.global_roulette_reward_deliveries TO authenticated;
GRANT ALL ON public.global_roulette_reward_deliveries TO service_role;
ALTER TABLE public.global_roulette_reward_deliveries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS grrd_self_read ON public.global_roulette_reward_deliveries;
CREATE POLICY grrd_self_read ON public.global_roulette_reward_deliveries FOR SELECT TO authenticated USING (true);

-- 3) Backfill: ciclos já premiados corretamente = DELIVERED
INSERT INTO public.global_roulette_reward_deliveries
  (cycle_id, reward_slot, delivery_key, user_id, reward_type, reward_key, spin_id, payload, delivered_at)
SELECT c.id, 'PREMIUM', 'cycle:' || c.id::text || ':PREMIUM', c.winner_user_id,
       c.target_reward_type, c.target_reward_id, c.winning_spin_id, '{"backfill":true}'::jsonb,
       coalesce(c.completed_at, now())
  FROM public.global_roulette_cycles c
 WHERE c.status = 'AWARDED' AND c.winner_user_id IS NOT NULL
ON CONFLICT (cycle_id, reward_slot) DO NOTHING;

UPDATE public.global_roulette_cycles c
   SET reward_status = 'DELIVERED',
       reward_delivered_at = coalesce(c.reward_delivered_at, c.completed_at, now()),
       reward_delivery_key = coalesce(c.reward_delivery_key, 'cycle:' || c.id::text || ':PREMIUM')
 WHERE EXISTS (SELECT 1 FROM public.global_roulette_reward_deliveries d WHERE d.cycle_id = c.id);

-- 4) Mint de unidade NFT quando o estoque do alvo do ciclo acabou (nunca substitui por outro herói)
CREATE OR REPLACE FUNCTION public.roulette_mint_nft_unit(p_template text, p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_serial integer; c public.hero_catalog;
BEGIN
  SELECT * INTO c FROM public.hero_catalog WHERE hero_key = p_template;
  IF c.hero_key IS NULL THEN RETURN NULL; END IF;
  SELECT coalesce(max(nft_serial), 0) + 1 INTO v_serial FROM public.nft_heroes WHERE hero_template_id = p_template;
  INSERT INTO public.nft_heroes (hero_template_id, nft_serial, unique_instance_id, status, minted,
      mining_daily_ton, mining_daily_myth, mining_dual, for_sale, metadata)
  VALUES (p_template, v_serial, p_template || '#' || v_serial::text, 'AVAILABLE', false,
      0, 0, false, false, jsonb_build_object('mining_enabled', false, 'source', p_reason, 'minted_for_reward', true))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- 5) grant premium: usa estoque; se esgotado, minta a unidade exata do alvo
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
    IF v_nft IS NULL THEN
      v_nft := public.roulette_mint_nft_unit(cyc.target_reward_id, 'GLOBAL_ROULETTE');
    END IF;
    IF v_nft IS NULL THEN RAISE EXCEPTION 'REWARD_TEMPLATE_NOT_FOUND:%', cyc.target_reward_id; END IF;
    UPDATE public.nft_heroes
       SET mining_daily_ton = 0, mining_daily_myth = 0, mining_dual = false,
           metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('mining_enabled', false, 'source','GLOBAL_ROULETTE')
     WHERE id = v_nft;
    v_res := public.nft_hero_assign_unit(v_nft, p_user, 'GLOBAL_ROULETTE_NFT_HERO');
    UPDATE public.player_heroes SET mining_daily_myth = 0, premium_source = 'GLOBAL_ROULETTE_NFT_HERO'
     WHERE id = (v_res->>'playerHeroId')::uuid;
    v_out := jsonb_build_object('class','NFT_HERO','heroKey', cyc.target_reward_id, 'name', coalesce(v_res->>'heroName', c.name),
      'serial', v_res->>'serial', 'image', c.image, 'mining', false,
      'atk', v_res->>'atk', 'hp', v_res->>'hp', 'power', c.power, 'playerHeroId', v_res->>'playerHeroId');
  ELSE
    IF c.hero_key IS NULL THEN RAISE EXCEPTION 'REWARD_TEMPLATE_NOT_FOUND:%', cyc.target_reward_id; END IF;
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

-- 6) Settlement transacional e idempotente (>= meta, overshoot nunca bloqueia)
CREATE OR REPLACE FUNCTION public.roulette_settle_cycle_reward(p_cycle uuid, p_user uuid DEFAULT NULL, p_spin uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_roulette_cycles; v_user uuid := p_user; v_spin uuid := p_spin;
        v_key text; v_out jsonb; v_err text;
BEGIN
  SELECT * INTO cyc FROM public.global_roulette_cycles WHERE id = p_cycle FOR UPDATE;
  IF cyc.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'CYCLE_NOT_FOUND'); END IF;
  v_key := 'cycle:' || cyc.id::text || ':PREMIUM';

  -- idempotência: já entregue
  IF EXISTS (SELECT 1 FROM public.global_roulette_reward_deliveries d WHERE d.cycle_id = cyc.id AND d.reward_slot='PREMIUM') THEN
    UPDATE public.global_roulette_cycles
       SET reward_status='DELIVERED', reward_delivery_key = v_key,
           reward_delivered_at = coalesce(reward_delivered_at, now()), status = 'AWARDED'
     WHERE id = cyc.id;
    RETURN jsonb_build_object('ok', true, 'already', true, 'rewardStatus', 'DELIVERED');
  END IF;

  -- regra: spent >= target (nunca igualdade exata)
  IF cyc.global_spend_nanoton < cyc.target_reference_cost_nanoton THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'THRESHOLD_NOT_REACHED');
  END IF;

  IF cyc.threshold_reached_at IS NULL THEN
    UPDATE public.global_roulette_cycles SET threshold_reached_at = now(), status='THRESHOLD_REACHED' WHERE id = cyc.id;
    cyc.threshold_reached_at := now();
  END IF;

  -- vencedor: informado, ou primeiro giro liquidado a partir do threshold
  IF v_user IS NULL THEN
    SELECT s.user_id, s.id INTO v_user, v_spin FROM public.global_roulette_spins s
     WHERE s.cycle_id = cyc.id AND s.status='SETTLED'
       AND coalesce(s.settled_at, s.created_at) >= cyc.threshold_reached_at
       AND (cyc.target_reward_type <> 'CELESTIAL_HERO' OR NOT public.roulette_user_has_celestial(s.user_id))
     ORDER BY coalesce(s.settled_at, s.created_at) LIMIT 1;
  END IF;
  IF v_user IS NULL THEN
    UPDATE public.global_roulette_cycles
       SET reward_status = 'PENDING', reward_last_error = 'NO_ELIGIBLE_WINNER', reward_attempts = reward_attempts + 1
     WHERE id = cyc.id;
    RETURN jsonb_build_object('ok', false, 'reason', 'NO_ELIGIBLE_WINNER', 'rewardStatus', 'PENDING');
  END IF;

  UPDATE public.global_roulette_cycles
     SET reward_status='DELIVERING', reward_attempts = reward_attempts + 1, status='AWARDING' WHERE id = cyc.id;

  BEGIN
    v_out := public.roulette_grant_premium(v_user, cyc.id, v_spin);
    IF v_out IS NULL THEN RAISE EXCEPTION 'GRANT_RETURNED_NULL'; END IF;

    INSERT INTO public.global_roulette_reward_deliveries
      (cycle_id, reward_slot, delivery_key, user_id, reward_type, reward_key, spin_id, payload)
    VALUES (cyc.id, 'PREMIUM', v_key, v_user, cyc.target_reward_type, cyc.target_reward_id, v_spin, v_out);

    UPDATE public.global_roulette_cycles
       SET reward_status='DELIVERED', reward_delivered_at = now(), reward_delivery_key = v_key,
           reward_last_error = NULL, status='AWARDED', winner_user_id = v_user,
           winning_spin_id = coalesce(v_spin, winning_spin_id), completed_at = coalesce(completed_at, now())
     WHERE id = cyc.id;

    IF v_spin IS NOT NULL THEN
      UPDATE public.global_roulette_spins
         SET premium_reward_awarded = true, premium_reward_type = cyc.target_reward_type,
             premium_reward_id = cyc.target_reward_id
       WHERE id = v_spin;
    END IF;

    PERFORM public.roulette_open_cycle();
    RETURN jsonb_build_object('ok', true, 'rewardStatus', 'DELIVERED', 'userId', v_user, 'reward', v_out);
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
    -- direito ao prêmio preservado: FAILED permite retry
    UPDATE public.global_roulette_cycles
       SET reward_status='FAILED', reward_last_error = v_err,
           status = CASE WHEN cyc.target_reward_type='CELESTIAL_HERO' THEN 'READY_FOR_ELIGIBLE_WINNER' ELSE 'THRESHOLD_REACHED' END
     WHERE id = cyc.id;
    RETURN jsonb_build_object('ok', false, 'reason', 'DELIVERY_FAILED', 'error', v_err, 'rewardStatus', 'FAILED');
  END;
END $$;

-- 7) Auditoria de recuperação (nada é entregue aqui)
CREATE OR REPLACE FUNCTION public.roulette_reward_recovery_audit()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'cycleNumber'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
      'cycleId', c.id, 'cycleNumber', c.cycle_number, 'cycleStatus', c.status,
      'rewardStatus', c.reward_status, 'rewardType', c.target_reward_type,
      'rewardKey', c.target_reward_id,
      'rewardName', (SELECT name FROM public.hero_catalog WHERE hero_key = c.target_reward_id),
      'targetTon', round(c.target_reference_cost_nanoton::numeric/1e9, 4),
      'spentTon', round(c.global_spend_nanoton::numeric/1e9, 4),
      'thresholdReached', c.global_spend_nanoton >= c.target_reference_cost_nanoton,
      'deliveryRecordExists', EXISTS (SELECT 1 FROM public.global_roulette_reward_deliveries d WHERE d.cycle_id = c.id),
      'ownershipExists', EXISTS (SELECT 1 FROM public.global_roulette_awards a
          WHERE a.cycle_id = c.id AND a.reward_class = c.target_reward_type),
      'candidateUserId', (SELECT s.user_id FROM public.global_roulette_spins s
          WHERE s.cycle_id = c.id AND s.status='SETTLED'
            AND coalesce(s.settled_at, s.created_at) >= coalesce(c.threshold_reached_at, s.created_at)
          ORDER BY coalesce(s.settled_at, s.created_at) LIMIT 1),
      'lastError', c.reward_last_error, 'attempts', c.reward_attempts,
      'action', 'RECOVER') AS x
      FROM public.global_roulette_cycles c
     WHERE c.global_spend_nanoton >= c.target_reference_cost_nanoton
       AND c.reward_status <> 'DELIVERED'
       AND NOT EXISTS (SELECT 1 FROM public.global_roulette_reward_deliveries d WHERE d.cycle_id = c.id)
  ) t;
$$;

-- 8) resolve: threshold nunca fica sem tentativa de settlement auditável
CREATE OR REPLACE FUNCTION public.roulette_resolve(p_spin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE sp public.global_roulette_spins; cyc public.global_roulette_cycles;
        normal jsonb; premium jsonb := NULL; settle jsonb; res jsonb;
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
     AND cyc.status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING') THEN
    IF cyc.threshold_reached_at IS NULL THEN
      UPDATE public.global_roulette_cycles
         SET threshold_reached_at = now(), status='THRESHOLD_REACHED',
             reward_status = CASE WHEN reward_status='DELIVERED' THEN 'DELIVERED' ELSE 'PENDING' END
       WHERE id = cyc.id;
    END IF;
    -- giro atual é o candidato; elegibilidade celestial validada dentro do settlement
    IF cyc.target_reward_type='CELESTIAL_HERO' AND public.roulette_user_has_celestial(sp.user_id) THEN
      UPDATE public.global_roulette_cycles SET status='READY_FOR_ELIGIBLE_WINNER' WHERE id = cyc.id;
    ELSE
      settle := public.roulette_settle_cycle_reward(cyc.id, sp.user_id, sp.id);
      IF coalesce((settle->>'ok')::boolean, false) AND NOT coalesce((settle->>'already')::boolean, false) THEN
        premium := settle->'reward';
      END IF;
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

-- 9) Admin Bot: pendências, falhas, retry, recheck e histórico
CREATE OR REPLACE FUNCTION public.admin_roulette_reward_recovery(p_admin_id bigint, p_action text DEFAULT 'audit', p_cycle uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_target uuid; v_res jsonb; v_count integer := 0; r record;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_action = 'retry' OR p_action = 'recheck' THEN
    IF p_cycle IS NOT NULL THEN
      v_res := public.roulette_settle_cycle_reward(p_cycle, NULL, NULL);
      v_count := CASE WHEN coalesce((v_res->>'ok')::boolean,false) THEN 1 ELSE 0 END;
    ELSE
      FOR r IN SELECT c.id FROM public.global_roulette_cycles c
                WHERE c.global_spend_nanoton >= c.target_reference_cost_nanoton
                  AND c.reward_status <> 'DELIVERED'
                  AND NOT EXISTS (SELECT 1 FROM public.global_roulette_reward_deliveries d WHERE d.cycle_id = c.id)
                ORDER BY c.cycle_number LOOP
        v_res := public.roulette_settle_cycle_reward(r.id, NULL, NULL);
        IF coalesce((v_res->>'ok')::boolean,false) THEN v_count := v_count + 1; END IF;
      END LOOP;
    END IF;
  END IF;
  RETURN jsonb_build_object(
    'action', p_action, 'recovered', v_count, 'lastResult', v_res,
    'pending', public.roulette_reward_recovery_audit(),
    'failed', coalesce((SELECT jsonb_agg(jsonb_build_object('cycleId', c.id, 'number', c.cycle_number,
        'rewardStatus', c.reward_status, 'error', c.reward_last_error, 'attempts', c.reward_attempts))
      FROM public.global_roulette_cycles c WHERE c.reward_status IN ('FAILED','MANUAL_REVIEW')), '[]'::jsonb),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object('cycleId', d.cycle_id,
        'number', (SELECT cycle_number FROM public.global_roulette_cycles c2 WHERE c2.id = d.cycle_id),
        'player', (SELECT coalesce(username, first_name, telegram_id::text) FROM public.game_players g WHERE g.id = d.user_id),
        'rewardType', d.reward_type, 'rewardKey', d.reward_key, 'deliveredAt', d.delivered_at) ORDER BY d.delivered_at DESC)
      FROM (SELECT * FROM public.global_roulette_reward_deliveries ORDER BY delivered_at DESC LIMIT 15) d), '[]'::jsonb));
END $$;

-- 10) Overview: status do prêmio separado do status da meta
CREATE OR REPLACE FUNCTION public.admin_roulette_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.global_roulette_settings; cyc public.global_roulette_cycles; r public.roulette_myth_reserve; base jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO s FROM public.global_roulette_settings WHERE id;
  SELECT * INTO r FROM public.roulette_myth_reserve WHERE id;
  SELECT * INTO cyc FROM public.global_roulette_cycles
   WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING')
   ORDER BY cycle_number LIMIT 1;
  base := jsonb_build_object(
    'settings', jsonb_build_object('enabled', s.enabled, 'paused', s.paused,
      'spinCostTon', round(s.spin_cost_nanoton::numeric/1e9, 9),
      'celestialThresholdTon', round(s.celestial_threshold_nanoton::numeric/1e9, 9),
      'weightMythic', s.weight_mythic, 'weightNftHero', s.weight_nft_hero, 'weightCelestial', s.weight_celestial,
      'normalWeightMyth', s.normal_weight_myth, 'normalWeightEquipment', s.normal_weight_equipment,
      'mythShortageBehavior', s.myth_shortage_behavior, 'paymentTtlMinutes', s.payment_ttl_minutes),
    'mythReserve', jsonb_build_object('allocated', r.allocated_myth, 'distributed', r.distributed_myth,
      'available', greatest(0, r.allocated_myth - r.distributed_myth)),
    'cycle', CASE WHEN cyc.id IS NULL THEN NULL ELSE jsonb_build_object('id', cyc.id, 'number', cyc.cycle_number,
      'status', cyc.status, 'rewardStatus', cyc.reward_status, 'rewardError', cyc.reward_last_error,
      'rewardDeliveredAt', cyc.reward_delivered_at,
      'targetType', cyc.target_reward_type, 'targetId', cyc.target_reward_id,
      'targetName', (SELECT name FROM public.hero_catalog WHERE hero_key = cyc.target_reward_id),
      'requiredTon', round(cyc.target_reference_cost_nanoton::numeric/1e9, 9),
      'spentTon', round(cyc.global_spend_nanoton::numeric/1e9, 9),
      'remainingTon', round(greatest(0, cyc.target_reference_cost_nanoton - cyc.global_spend_nanoton)::numeric/1e9, 9),
      'thresholdReachedAt', cyc.threshold_reached_at, 'startedAt', cyc.started_at) END,
    'audit', (SELECT jsonb_build_object(
        'totalSpins', count(*) FILTER (WHERE status='SETTLED'),
        'totalTonReceived', round(coalesce(sum(amount_nanoton) FILTER (WHERE status='SETTLED'),0)::numeric/1e9, 9),
        'pendingPayments', count(*) FILTER (WHERE status='PAYMENT_PENDING'),
        'stuck', count(*) FILTER (WHERE status IN ('PAID','RESOLVING','FAILED_RECOVERABLE'))
      ) FROM public.global_roulette_spins),
    'distributed', (SELECT jsonb_build_object(
        'mythTotal', coalesce(sum(amount) FILTER (WHERE reward_class='MYTH'),0),
        'equipment', count(*) FILTER (WHERE reward_class='NFT_EQUIPMENT'),
        'mythicHeroes', count(*) FILTER (WHERE reward_class='MYTHIC_HERO'),
        'nftHeroes', count(*) FILTER (WHERE reward_class='NFT_HERO'),
        'celestials', count(*) FILTER (WHERE reward_class='CELESTIAL_HERO')
      ) FROM public.global_roulette_awards),
    'cyclesAwarded', (SELECT count(*) FROM public.global_roulette_cycles WHERE status='AWARDED'));
  RETURN base || jsonb_build_object(
    'pendingRewards', public.roulette_reward_recovery_audit(),
    'failedRewards', coalesce((SELECT count(*) FROM public.global_roulette_cycles WHERE reward_status IN ('FAILED','MANUAL_REVIEW')), 0));
END $$;
