DO $$
DECLARE
  v_definition text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO v_definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'veteran_v2_deliver'
     AND pg_get_function_identity_arguments(p.oid) = 'p_purchase_id uuid';

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'veteran_v2_deliver(uuid) not found';
  END IF;

  v_patched := replace(
    v_definition,
    'VALUES (o.user_id, r.id, 1, ''veteran_vault_v2'', o.id::text, true, 1000, now())',
    'VALUES (o.user_id, r.id, 1, ''veteran_vault_v2'', o.id, true, 1000, now())'
  );
  v_patched := replace(
    v_patched,
    'WHERE id;',
    'WHERE id = true;'
  );

  IF v_patched = v_definition THEN
    RAISE EXCEPTION 'Expected Veteran delivery statements were not found';
  END IF;

  EXECUTE v_patched;
END $$;

DO $$
DECLARE
  v_definition text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO v_definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'veteran_v2_start_purchase'
     AND pg_get_function_identity_arguments(p.oid) = 'p_telegram_id bigint, p_wallet_address text, p_idempotency_key text';

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'veteran_v2_start_purchase(bigint,text,text) not found';
  END IF;

  v_patched := replace(
    v_definition,
    'FROM public.veteran_myth_pools WHERE id FOR UPDATE',
    'FROM public.veteran_myth_pools WHERE id = true FOR UPDATE'
  );

  IF v_patched = v_definition THEN
    RAISE EXCEPTION 'Expected Veteran pool lock was not found';
  END IF;

  EXECUTE v_patched;
END $$;

DO $$
DECLARE
  v_definition text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO v_definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'veteran_v2_state'
     AND pg_get_function_identity_arguments(p.oid) = 'p_telegram_id bigint';

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'veteran_v2_state(bigint) not found';
  END IF;

  v_patched := replace(
    v_definition,
    'FROM public.veteran_myth_pools WHERE id;',
    'FROM public.veteran_myth_pools WHERE id = true;'
  );
  v_patched := replace(
    v_patched,
    'FROM public.veteran_vault_v2_config WHERE id;',
    'FROM public.veteran_vault_v2_config WHERE id = true;'
  );

  IF v_patched = v_definition THEN
    RAISE EXCEPTION 'Expected Veteran state singleton queries were not found';
  END IF;

  EXECUTE v_patched;
END $$;

DO $$
DECLARE
  v_definition text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO v_definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'veteran_v2_settings'
     AND pg_get_function_identity_arguments(p.oid) = '';

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'veteran_v2_settings() not found';
  END IF;

  v_patched := replace(
    v_definition,
    'FROM public.veteran_vault_v2_config WHERE id;',
    'FROM public.veteran_vault_v2_config WHERE id = true;'
  );

  IF v_patched = v_definition THEN
    RAISE EXCEPTION 'Expected Veteran settings singleton query was not found';
  END IF;

  EXECUTE v_patched;
END $$;