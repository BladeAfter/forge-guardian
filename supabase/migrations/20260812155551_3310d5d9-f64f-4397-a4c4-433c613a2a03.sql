CREATE OR REPLACE FUNCTION public.hero_effective_summon_odds()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_total numeric := 0; v_out jsonb := '{}'::jsonb; r record; v_sum numeric; v_top text;
BEGIN
  FOR r IN
    SELECT e.key AS rarity, (e.value #>> '{}')::numeric AS chance
      FROM jsonb_each(public.hero_summon_rates()) e
     WHERE e.key <> 'ancestral'
       AND (e.value #>> '{}')::numeric > 0
       AND public.hero_rarity_recruitable(e.key)
       AND EXISTS (SELECT 1 FROM public.hero_catalog c
                    WHERE c.rarity = e.key AND c.enabled AND c.recruit_enabled)
  LOOP
    v_total := v_total + r.chance;
    v_out := v_out || jsonb_build_object(r.rarity, r.chance);
  END LOOP;

  IF v_total <= 0 THEN RETURN '{}'::jsonb; END IF;

  SELECT jsonb_object_agg(key, round((value #>> '{}')::numeric * 100 / v_total, 2))
    INTO v_out FROM jsonb_each(v_out);

  -- absorb the rounding residual on the most likely rarity so the list always shows 100%
  SELECT sum((value #>> '{}')::numeric) INTO v_sum FROM jsonb_each(v_out);
  SELECT key INTO v_top FROM jsonb_each(v_out)
    ORDER BY (value #>> '{}')::numeric DESC, key ASC LIMIT 1;
  IF v_top IS NOT NULL AND v_sum <> 100 THEN
    v_out := v_out || jsonb_build_object(v_top,
      round((v_out #>> ARRAY[v_top])::numeric + (100 - v_sum), 2));
  END IF;
  RETURN v_out;
END; $$;

REVOKE ALL ON FUNCTION public.hero_effective_summon_odds() FROM anon, authenticated;