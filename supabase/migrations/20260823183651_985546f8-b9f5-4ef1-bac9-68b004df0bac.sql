-- Raise minimum deposit to 3 TON for both FC and direct TON balance top-ups.
-- Both values are now admin-tunable via economy_settings.

INSERT INTO public.economy_settings(key, value_numeric) VALUES
  ('min_fc_ton_deposit', 3),
  ('min_direct_ton_deposit', 3)
ON CONFLICT (key) DO UPDATE SET value_numeric = excluded.value_numeric, updated_at = now();

-- Single source of truth for both deposit modes (admin-tunable, no deploy needed).
CREATE OR REPLACE FUNCTION public.wallet_deposit_config()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'fcEnabled', COALESCE((SELECT value_numeric FROM economy_settings WHERE key='ton_to_fc_deposit_enabled'),1) > 0,
    'directEnabled', COALESCE((SELECT value_numeric FROM economy_settings WHERE key='direct_ton_deposit_enabled'),1) > 0,
    'minFcTon', GREATEST(COALESCE((SELECT value_numeric FROM economy_settings WHERE key='min_fc_ton_deposit'),3), 0.01),
    'minDirectTon', GREATEST(COALESCE((SELECT value_numeric FROM economy_settings WHERE key='min_direct_ton_deposit'),3), 0.01),
    'fcPerTon', COALESCE((SELECT value_numeric FROM economy_settings WHERE key='fc_per_ton'),100000)
  );
$$;

REVOKE ALL ON FUNCTION public.wallet_deposit_config() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_deposit_config() TO service_role;

-- Admin toggles/limits for both deposit methods (no deploy required).
CREATE OR REPLACE FUNCTION public.admin_deposit_settings(p_admin_id bigint, p_key text DEFAULT NULL, p_value numeric DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_key text := lower(COALESCE(btrim(p_key),''));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_key <> '' THEN
    IF v_key NOT IN ('direct_ton_deposit_enabled','ton_to_fc_deposit_enabled','min_direct_ton_deposit','min_fc_ton_deposit') THEN
      RAISE EXCEPTION 'INVALID_SETTING';
    END IF;
    IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    INSERT INTO public.economy_settings(key, value_numeric) VALUES (v_key, p_value)
    ON CONFLICT (key) DO UPDATE SET value_numeric = excluded.value_numeric, updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'deposit_settings', v_key, jsonb_build_object('value', p_value));
  END IF;
  RETURN public.wallet_deposit_config();
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_deposit_settings(bigint, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_deposit_settings(bigint, text, numeric) TO service_role;
