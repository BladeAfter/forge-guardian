-- 1) Activate the boss gate for 24h
UPDATE public.boss_templates SET active = false WHERE active;
UPDATE public.boss_templates
   SET active = true, starts_at = now(), ends_at = now() + interval '24 hours', updated_at = now()
 WHERE id = (SELECT id FROM public.boss_templates ORDER BY created_at DESC LIMIT 1);

-- 2) Restart the current global cycle window to a fresh 24h
UPDATE public.global_boss_cycles
   SET starts_at = now(), ends_at = now() + interval '24 hours', updated_at = now()
 WHERE status = 'active';

-- 3) Keep the gate window in sync with each new 24h global boss cycle,
--    so defeating a boss early immediately opens the next one.
CREATE OR REPLACE FUNCTION public.ensure_global_boss_cycle()
 RETURNS global_boss_cycles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cyc public.global_boss_cycles; b public.boss_templates; t public.global_boss_templates;
        v_pool numeric; v_next int; v_last public.global_boss_cycles; v_reason text; v_seconds int;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NOT NULL THEN
    IF cyc.ends_at IS NOT NULL AND cyc.ends_at <= now() THEN
      v_reason := CASE WHEN cyc.current_hp > 0 THEN 'expired' ELSE 'defeated' END;
      UPDATE public.global_boss_cycles
         SET status = CASE WHEN v_reason = 'expired' THEN 'expired' ELSE 'defeated' END,
             ended_reason = v_reason,
             defeated_at = CASE WHEN v_reason = 'defeated' THEN COALESCE(defeated_at, now()) ELSE defeated_at END,
             updated_at = now()
       WHERE id = cyc.id RETURNING * INTO cyc;
      PERFORM public.distribute_global_boss_rewards(cyc.id);
      RETURN NULL;
    END IF;
    RETURN cyc;
  END IF;

  SELECT * INTO v_last FROM public.global_boss_cycles ORDER BY cycle_number DESC LIMIT 1;
  v_next := COALESCE(v_last.boss_number, 0) + 1;
  IF v_next > (SELECT COALESCE(max(boss_number), 0) FROM public.global_boss_templates WHERE enabled) THEN
    RETURN NULL;
  END IF;

  t := public.global_boss_template_for_number(v_next);
  IF t.id IS NULL THEN RETURN NULL; END IF;
  b := public.active_boss_template();
  v_pool := t.reward_fc;
  v_seconds := GREATEST(300, COALESCE(t.duration_seconds, 86400));

  INSERT INTO public.global_boss_cycles
    (cycle_number, boss_key, boss_name, boss_image, boss_level, max_hp, current_hp, reward_pool_fc,
     starts_at, ends_at, template_id, boss_number, boss_subtitle, boss_theme, boss_background)
  VALUES ((SELECT COALESCE(max(cycle_number), 0) + 1 FROM public.global_boss_cycles),
          COALESCE(t.code, b.code), t.name, t.image_url, t.boss_level, t.max_hp, t.max_hp, v_pool,
          now(), now() + make_interval(secs => v_seconds),
          t.id, t.boss_number, t.subtitle, t.theme, t.background_url)
  ON CONFLICT DO NOTHING
  RETURNING * INTO cyc;
  IF cyc.id IS NULL THEN SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1; END IF;

  -- The legacy gate template follows the new cycle window (24h) automatically.
  IF cyc.id IS NOT NULL THEN
    UPDATE public.boss_templates
       SET active = true, starts_at = cyc.starts_at, ends_at = cyc.ends_at, updated_at = now()
     WHERE id = (SELECT id FROM public.boss_templates ORDER BY created_at DESC LIMIT 1);
  END IF;

  RETURN cyc;
END; $function$;