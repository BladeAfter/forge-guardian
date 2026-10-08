DO $$
DECLARE v jsonb;
BEGIN
  v := public.clan_war_dashboard(1310583958);
  IF v IS NULL THEN RAISE EXCEPTION 'NULL_RESULT'; END IF;
  RAISE NOTICE 'ok %', left(v::text, 120);
END $$;