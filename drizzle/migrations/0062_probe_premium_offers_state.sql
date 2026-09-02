CREATE OR REPLACE FUNCTION public._probe_premium_offers(p_telegram_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT public.premium_offers_state(p_telegram_id)
$$;