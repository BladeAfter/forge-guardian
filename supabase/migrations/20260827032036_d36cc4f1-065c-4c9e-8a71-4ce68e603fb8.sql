-- 1) NFT hero roulette goal: 80 TON
UPDATE public.roulette_reward_config
   SET reference_cost_nanoton = 80000000000, updated_at = now()
 WHERE reward_class = 'NFT_HERO';

UPDATE public.global_roulette_cycles
   SET target_reference_cost_nanoton = 80000000000
 WHERE target_reward_type = 'NFT_HERO'
   AND status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER');

-- 2) NFT mining: 0.30 TON/day
UPDATE public.nft_heroes SET mining_daily_ton = 0.300000000, updated_at = now();
UPDATE public.nft_pool_settings SET tier20_daily_ton = 0.300000000, tier30_daily_ton = 0.300000000, updated_at = now();

-- 3) MYTH reward bands: 40k .. 80k (variable)
DELETE FROM public.roulette_reward_config WHERE reward_class = 'MYTH';
INSERT INTO public.roulette_reward_config(reward_class, reward_key, label, enabled, weight, quantity, reference_cost_nanoton, requires_global_threshold, metadata)
VALUES
 ('MYTH','myth_40_50','40.000 – 50.000 MYTH', true, 40, 40000, 0, false, jsonb_build_object('min_amount',40000,'max_amount',50000,'step',1000)),
 ('MYTH','myth_50_60','50.000 – 60.000 MYTH', true, 28, 50000, 0, false, jsonb_build_object('min_amount',50000,'max_amount',60000,'step',1000)),
 ('MYTH','myth_60_70','60.000 – 70.000 MYTH', true, 20, 60000, 0, false, jsonb_build_object('min_amount',60000,'max_amount',70000,'step',1000)),
 ('MYTH','myth_70_80','70.000 – 80.000 MYTH', true, 12, 70000, 0, false, jsonb_build_object('min_amount',70000,'max_amount',80000,'step',1000));

-- 4) roll_normal: pick a random amount inside the band
CREATE OR REPLACE FUNCTION public.roulette_roll_normal(p_user uuid, p_spin uuid, p_cycle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE s public.global_roulette_settings; v_class text; v_key text; v_qty numeric; v_label text;
        v_nft uuid; v_res jsonb; v_serial int; v_meta jsonb; v_min numeric; v_max numeric; v_step numeric;
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
      v_class := 'MYTH';
    ELSIF v_class = 'MYTH' THEN
      SELECT c.reward_key, c.quantity, c.label, c.metadata INTO v_key, v_qty, v_label, v_meta
        FROM public.roulette_reward_config c
       WHERE c.reward_class='MYTH' AND c.enabled AND c.weight>0 AND c.quantity>0
       ORDER BY -ln(random())/c.weight LIMIT 1;

      IF v_key IS NOT NULL THEN
        v_min := coalesce(nullif(v_meta->>'min_amount','')::numeric, v_qty);
        v_max := coalesce(nullif(v_meta->>'max_amount','')::numeric, v_qty);
        v_step := greatest(1, coalesce(nullif(v_meta->>'step','')::numeric, 1000));
        IF v_max > v_min THEN
          v_qty := v_min + floor(random() * (floor((v_max - v_min) / v_step) + 1)) * v_step;
          v_qty := least(v_max, v_qty);
        ELSE
          v_qty := v_min;
        END IF;
      END IF;

      IF v_key IS NOT NULL AND public.roulette_pay_myth(p_user, v_qty) THEN
        INSERT INTO public.global_roulette_awards(spin_id, cycle_id, user_id, reward_class, reward_key, source_type, amount, payload)
        VALUES (p_spin, p_cycle, p_user, 'MYTH', v_key, 'GLOBAL_ROULETTE_MYTH', v_qty,
          jsonb_build_object('label', v_label, 'band', jsonb_build_object('min', v_min, 'max', v_max)));
        RETURN jsonb_build_object('class','MYTH','tier', v_key, 'label', to_char(v_qty, 'FM999G999G999')||' MYTH', 'amount', v_qty);
      END IF;
      IF coalesce(s.myth_shortage_behavior,'SKIP') = 'EQUIPMENT' THEN v_class := 'NFT_EQUIPMENT'; ELSE EXIT; END IF;
    ELSE EXIT;
    END IF;
  END LOOP;

  INSERT INTO public.global_roulette_awards(spin_id, cycle_id, user_id, reward_class, reward_key, source_type, amount, payload)
  VALUES (p_spin, p_cycle, p_user, 'NONE', null, 'GLOBAL_ROULETTE_NONE', 0, jsonb_build_object('reason','no_normal_reward_available'));
  RETURN jsonb_build_object('class','NONE','amount',0);
END $function$;

REVOKE ALL ON FUNCTION public.roulette_roll_normal(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;