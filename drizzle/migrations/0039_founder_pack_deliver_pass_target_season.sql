DO $mig$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.founder_pack_deliver(uuid)'::regprocedure);
  v_def := replace(
    v_def,
    '  v_season := nullif(s->>''seasonId'', '''')::uuid;',
    '  v_season := public.founder_pack_pass_season(o.user_id, s);'
  );
  IF position('founder_pack_pass_season' in v_def) = 0 THEN
    RAISE EXCEPTION 'FOUNDER_PACK_DELIVER_PATCH_FAILED';
  END IF;
  EXECUTE v_def;
END $mig$;
