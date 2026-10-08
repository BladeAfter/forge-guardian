CREATE OR REPLACE FUNCTION public.admin_roulette_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s public.global_roulette_settings; cyc public.global_roulette_cycles; r public.roulette_myth_reserve;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO s FROM public.global_roulette_settings WHERE id;
  SELECT * INTO r FROM public.roulette_myth_reserve WHERE id;
  SELECT * INTO cyc FROM public.global_roulette_cycles
   WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING')
   ORDER BY cycle_number LIMIT 1;
  RETURN jsonb_build_object(
    'settings', jsonb_build_object('enabled', s.enabled, 'paused', s.paused,
      'spinCostTon', round(s.spin_cost_nanoton::numeric/1e9, 9),
      'celestialThresholdTon', round(s.celestial_threshold_nanoton::numeric/1e9, 9),
      'weightMythic', s.weight_mythic, 'weightNftHero', s.weight_nft_hero, 'weightCelestial', s.weight_celestial,
      'normalWeightMyth', s.normal_weight_myth, 'normalWeightEquipment', s.normal_weight_equipment,
      'mythShortageBehavior', s.myth_shortage_behavior, 'paymentTtlMinutes', s.payment_ttl_minutes),
    'mythReserve', jsonb_build_object('allocated', r.allocated_myth, 'distributed', r.distributed_myth,
      'available', greatest(0, r.allocated_myth - r.distributed_myth)),
    'cycle', CASE WHEN cyc.id IS NULL THEN NULL ELSE jsonb_build_object('id', cyc.id, 'number', cyc.cycle_number,
      'status', cyc.status, 'targetType', cyc.target_reward_type, 'targetId', cyc.target_reward_id,
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
END $$;

CREATE OR REPLACE FUNCTION public.admin_roulette_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_num numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_num := nullif(regexp_replace(coalesce(p_value,''), '[^0-9.\-]', '', 'g'), '')::numeric;
  CASE lower(p_field)
    WHEN 'enabled' THEN UPDATE public.global_roulette_settings SET enabled = lower(p_value) IN ('1','true','on','yes') WHERE id;
    WHEN 'paused' THEN UPDATE public.global_roulette_settings SET paused = lower(p_value) IN ('1','true','on','yes') WHERE id;
    WHEN 'spin_cost_ton' THEN
      IF coalesce(v_num,0) <= 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
      UPDATE public.global_roulette_settings SET spin_cost_nanoton = round(v_num * 1e9)::bigint WHERE id;
    WHEN 'celestial_threshold_ton' THEN
      IF coalesce(v_num,0) <= 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
      UPDATE public.global_roulette_settings SET celestial_threshold_nanoton = round(v_num * 1e9)::bigint WHERE id;
    WHEN 'weight_mythic' THEN UPDATE public.global_roulette_settings SET weight_mythic = greatest(0, coalesce(v_num,0)) WHERE id;
    WHEN 'weight_nft_hero' THEN UPDATE public.global_roulette_settings SET weight_nft_hero = greatest(0, coalesce(v_num,0)) WHERE id;
    WHEN 'weight_celestial' THEN UPDATE public.global_roulette_settings SET weight_celestial = greatest(0, coalesce(v_num,0)) WHERE id;
    WHEN 'normal_weight_myth' THEN UPDATE public.global_roulette_settings SET normal_weight_myth = greatest(0, coalesce(v_num,0)) WHERE id;
    WHEN 'normal_weight_equipment' THEN UPDATE public.global_roulette_settings SET normal_weight_equipment = greatest(0, coalesce(v_num,0)) WHERE id;
    WHEN 'myth_shortage_behavior' THEN UPDATE public.global_roulette_settings
      SET myth_shortage_behavior = CASE WHEN upper(p_value)='EQUIPMENT' THEN 'EQUIPMENT' ELSE 'SKIP' END WHERE id;
    WHEN 'myth_reserve' THEN
      IF v_num IS NULL OR v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
      UPDATE public.roulette_myth_reserve SET allocated_myth = v_num, updated_at = now() WHERE id;
    ELSE RAISE EXCEPTION 'UNKNOWN_FIELD';
  END CASE;
  PERFORM public.admin_log(p_admin_id, 'roulette.set', 'global_roulette', p_field, NULL,
    jsonb_build_object('value', p_value), NULL);
  RETURN public.admin_roulette_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_roulette_reward_list(p_admin_id bigint, p_class text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_target text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT target_reward_id INTO v_target FROM public.global_roulette_cycles
   WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING') LIMIT 1;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('key', reward_key, 'label', label, 'enabled', enabled,
      'weight', weight, 'quantity', quantity,
      'referenceTon', round(reference_cost_nanoton::numeric/1e9, 9),
      'isActiveTarget', reward_key = v_target,
      'stock', CASE WHEN reward_class='NFT_HERO' THEN
        (SELECT count(*) FROM public.nft_heroes n WHERE n.hero_template_id = reward_key AND n.owner_user_id IS NULL AND n.status='AVAILABLE')
        WHEN reward_class='NFT_EQUIPMENT' THEN
        (SELECT count(*) FROM public.nft_equipment n JOIN public.equipment_templates t ON t.id=n.template_id
          WHERE n.owner_user_id IS NULL AND n.status='AVAILABLE' AND lower(t.rarity)=lower(reward_key))
        ELSE NULL END)
      ORDER BY label)
    FROM public.roulette_reward_config WHERE reward_class = upper(p_class)), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_roulette_reward_set(p_admin_id bigint, p_class text, p_key text, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_num numeric; v_bool boolean; v_target text; v_class text := upper(p_class);
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_num := nullif(regexp_replace(coalesce(p_value,''), '[^0-9.\-]', '', 'g'), '')::numeric;
  v_bool := lower(coalesce(p_value,'')) IN ('1','true','on','yes');
  SELECT target_reward_id INTO v_target FROM public.global_roulette_cycles
   WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING') LIMIT 1;

  IF lower(p_field) = 'enabled' AND NOT v_bool AND p_key = v_target THEN
    RAISE EXCEPTION 'REWARD_IS_ACTIVE_CYCLE_TARGET';
  END IF;

  CASE lower(p_field)
    WHEN 'enabled' THEN UPDATE public.roulette_reward_config SET enabled = v_bool WHERE reward_class=v_class AND reward_key=p_key;
    WHEN 'weight' THEN UPDATE public.roulette_reward_config SET weight = greatest(0, coalesce(v_num,0)) WHERE reward_class=v_class AND reward_key=p_key;
    WHEN 'quantity' THEN UPDATE public.roulette_reward_config SET quantity = greatest(0, coalesce(v_num,0)) WHERE reward_class=v_class AND reward_key=p_key;
    WHEN 'reference_ton' THEN
      IF coalesce(v_num,0) <= 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
      UPDATE public.roulette_reward_config SET reference_cost_nanoton = round(v_num*1e9)::bigint
       WHERE reward_class=v_class AND reward_key=p_key;
    ELSE RAISE EXCEPTION 'UNKNOWN_FIELD';
  END CASE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REWARD_NOT_FOUND'; END IF;
  PERFORM public.admin_log(p_admin_id, 'roulette.reward.set', 'roulette_reward', v_class||':'||p_key, NULL,
    jsonb_build_object('field', p_field, 'value', p_value), NULL);
  RETURN public.admin_roulette_reward_list(p_admin_id, v_class);
END $$;

-- Explicit, audited cancellation. The only way to drop the current secret target.
CREATE OR REPLACE FUNCTION public.admin_roulette_cycle_cancel(p_admin_id bigint, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_roulette_cycles; v_new uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtext('global_mystery_roulette_cycle'));
  SELECT * INTO cyc FROM public.global_roulette_cycles
   WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING')
   ORDER BY cycle_number LIMIT 1 FOR UPDATE;
  IF cyc.id IS NULL THEN RAISE EXCEPTION 'NO_OPEN_CYCLE'; END IF;
  UPDATE public.global_roulette_cycles SET status='CANCELLED', completed_at = now() WHERE id = cyc.id;
  PERFORM public.admin_log(p_admin_id, 'roulette.cycle.cancel', 'global_roulette_cycle', cyc.id::text,
    jsonb_build_object('targetType', cyc.target_reward_type, 'targetId', cyc.target_reward_id,
      'spendNano', cyc.global_spend_nanoton), jsonb_build_object('status','CANCELLED'), p_reason);
  v_new := public.roulette_open_cycle();
  RETURN jsonb_build_object('cancelled', cyc.cycle_number, 'newCycleId', v_new);
END $$;

CREATE OR REPLACE FUNCTION public.admin_roulette_history(p_admin_id bigint, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'cycles', coalesce((SELECT jsonb_agg(jsonb_build_object('number', c.cycle_number, 'status', c.status,
        'targetType', c.target_reward_type, 'targetId', c.target_reward_id,
        'requiredTon', round(c.target_reference_cost_nanoton::numeric/1e9,9),
        'spentTon', round(c.global_spend_nanoton::numeric/1e9,9),
        'winner', (SELECT coalesce('@'||p.username, p.telegram_id::text) FROM public.game_players p WHERE p.id = c.winner_user_id),
        'completedAt', c.completed_at) ORDER BY c.cycle_number DESC)
      FROM (SELECT * FROM public.global_roulette_cycles ORDER BY cycle_number DESC LIMIT greatest(1, p_limit)) c), '[]'::jsonb),
    'celestialWinners', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'player', coalesce('@'||p.username, p.telegram_id::text), 'hero', a.hero_key, 'at', a.awarded_at)
        ORDER BY a.awarded_at DESC)
      FROM public.roulette_celestial_awards a JOIN public.game_players p ON p.id = a.user_id), '[]'::jsonb),
    'pendingIntents', coalesce((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'status', s.status,
        'player', coalesce('@'||p.username, p.telegram_id::text),
        'ton', round(s.amount_nanoton::numeric/1e9,9), 'createdAt', s.created_at) ORDER BY s.created_at DESC)
      FROM (SELECT * FROM public.global_roulette_spins
             WHERE status IN ('PAYMENT_PENDING','PAID','RESOLVING','FAILED_RECOVERABLE')
             ORDER BY created_at DESC LIMIT 20) s JOIN public.game_players p ON p.id = s.user_id), '[]'::jsonb));
END $$;

DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY['admin_roulette_overview','admin_roulette_set','admin_roulette_reward_list',
    'admin_roulette_reward_set','admin_roulette_cycle_cancel','admin_roulette_history'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I FROM PUBLIC, anon, authenticated', fn);
  END LOOP;
END $$;

SELECT cron.schedule('global-roulette-reconcile', '*/10 * * * *',
  $$ SELECT public.roulette_reconcile(1440); $$);