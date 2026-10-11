-- Run transactionally as a privileged test session; no purchases or balance writes.
BEGIN;
DO $test$
DECLARE actual jsonb; shown jsonb;
BEGIN
  shown := public.hero_effective_summon_odds();
  actual := public.hero_effective_real_summon_odds();
  IF actual IS DISTINCT FROM shown THEN RAISE EXCEPTION 'Recruit odds differ from advertised odds'; END IF;
  IF shown IS DISTINCT FROM '{"common":50,"uncommon":18,"rare":17,"epic":9,"legendary":4.5,"mythic":1.5}'::jsonb THEN
    RAISE EXCEPTION 'Current advertised chances do not match verified configuration: %', shown;
  END IF;
  IF has_function_privilege('anon','public.hero_effective_real_summon_odds()','EXECUTE') OR has_function_privilege('authenticated','public.hero_effective_real_summon_odds()','EXECUTE') THEN
    RAISE EXCEPTION 'Recruit authority is exposed to clients';
  END IF;
END $test$;
ROLLBACK;