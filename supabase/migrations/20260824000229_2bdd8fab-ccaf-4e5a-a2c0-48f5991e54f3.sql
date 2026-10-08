ALTER TABLE public.clan_boss_scaling_config
  ADD COLUMN IF NOT EXISTS cycle_lock_hours numeric NOT NULL DEFAULT 2;

UPDATE public.clan_boss_scaling_config SET cycle_lock_hours = 2 WHERE id = 1;

CREATE OR REPLACE FUNCTION public.clan_boss_cycle_lock(p_clan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE sc public.clan_boss_scaling_config; v_next timestamptz; v_lock numeric;
BEGIN
  sc := public.clan_boss_scaling_cfg();
  IF NOT sc.cycle_lock_enabled THEN RETURN jsonb_build_object('locked', false); END IF;
  v_lock := GREATEST(0, COALESCE(sc.cycle_lock_hours, 2));
  SELECT MAX(
           LEAST(
             COALESCE(cycle_ends_at, starts_at + make_interval(hours => sc.cycle_hours)),
             COALESCE(finished_at, ends_at, starts_at + make_interval(hours => sc.cycle_hours))
               + make_interval(mins => round(v_lock * 60)::int)
           )
         )
    INTO v_next
    FROM public.clan_boss_instances WHERE clan_id = p_clan_id;
  IF v_next IS NULL OR v_next <= now() THEN RETURN jsonb_build_object('locked', false); END IF;
  RETURN jsonb_build_object('locked', true, 'nextBossAt', v_next,
    'secondsRemaining', GREATEST(0, ceil(EXTRACT(epoch FROM (v_next - now())))::int));
END $function$;