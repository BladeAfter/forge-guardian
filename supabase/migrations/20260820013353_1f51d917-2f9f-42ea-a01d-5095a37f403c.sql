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

  v_patched := replace(
    v_definition,
    'INSERT INTO public.player_pet_inventory(user_id, item_type, item_id, quantity)
    VALUES (o.user_id, ''egg'', eg.id, 1)
    ON CONFLICT (user_id, item_type, item_id) DO UPDATE SET quantity = public.player_pet_inventory.quantity + 1, updated_at = now();',
    'UPDATE public.player_pet_inventory
        SET quantity = quantity + 1, updated_at = now()
      WHERE user_id = o.user_id AND item_type = ''egg'' AND item_id = eg.id;
     IF NOT FOUND THEN
       INSERT INTO public.player_pet_inventory(user_id, item_type, item_id, quantity)
       VALUES (o.user_id, ''egg'', eg.id, 1);
     END IF;'
  );

  IF v_patched = v_definition THEN
    RAISE EXCEPTION 'Expected Veteran egg inventory statement was not found';
  END IF;
  EXECUTE v_patched;
END $$;

REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.veteran_v2_deliver(uuid) TO service_role;

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

  v_patched := replace(
    v_definition,
    'INSERT INTO public.player_pet_inventory(user_id, item_type, item_id, quantity)
    VALUES (o.user_id, ''egg'', eg.id, 1)
    ON CONFLICT (user_id, item_type, item_id) DO UPDATE SET quantity = public.player_pet_inventory.quantity + 1, updated_at = now();',
    'UPDATE public.player_pet_inventory
        SET quantity = quantity + 1, updated_at = now()
      WHERE user_id = o.user_id AND item_type = ''egg'' AND item_id = eg.id;
     IF NOT FOUND THEN
       INSERT INTO public.player_pet_inventory(user_id, item_type, item_id, quantity)
       VALUES (o.user_id, ''egg'', eg.id, 1);
     END IF;'
  );
  v_patched := replace(
    v_patched,
    'VALUES (o.user_id, r.id, 1, ''veteran_vault_v2'', o.id, true, 1000, now())',
    'VALUES (o.user_id, r.id, 1, ''veteran_vault_v2'', gen_random_uuid(), true, 1000, now())'
  );

  IF v_patched = v_definition THEN
    RAISE EXCEPTION 'Expected Veteran delivery statements were not found';
  END IF;
  EXECUTE v_patched;
END $$;

REVOKE ALL ON FUNCTION public.veteran_v2_deliver(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.veteran_v2_deliver(uuid) TO service_role;

DO $$
DECLARE
  v_before_ton numeric;
  v_result jsonb;
  v_status text;
BEGIN
  SELECT ton_balance INTO v_before_ton
    FROM public.game_players
   WHERE telegram_id = 8118569391;

  IF v_before_ton IS NULL THEN
    RAISE EXCEPTION 'VETERAN_TEST_PLAYER_NOT_FOUND';
  END IF;

  BEGIN
    v_result := public.veteran_v2_start_purchase(
      8118569391,
      NULL,
      'veteran-fix-test-' || gen_random_uuid()::text
    );

    IF v_result->>'status' <> 'completed' THEN
      RAISE EXCEPTION 'VETERAN_TEST_NOT_COMPLETED: %', v_result;
    END IF;

    SELECT status INTO v_status
      FROM public.veteran_vault_v2_purchases
     WHERE id = (v_result->>'purchaseId')::uuid;

    IF v_status <> 'delivered' THEN
      RAISE EXCEPTION 'VETERAN_TEST_NOT_DELIVERED: %', v_status;
    END IF;

    RAISE EXCEPTION 'VETERAN_TEST_ROLLBACK_OK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'VETERAN_TEST_ROLLBACK_OK' THEN
        RAISE;
      END IF;
  END;

  IF (SELECT ton_balance FROM public.game_players WHERE telegram_id = 8118569391) <> v_before_ton THEN
    RAISE EXCEPTION 'VETERAN_TEST_ROLLBACK_FAILED';
  END IF;
END $$;