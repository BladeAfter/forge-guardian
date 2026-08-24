DO $$
DECLARE v_pool uuid;
BEGIN
  SELECT id INTO v_pool FROM public.pool_balance WHERE status = 'active' ORDER BY starts_at DESC LIMIT 1;
  IF v_pool IS NULL THEN
    INSERT INTO public.pool_balance (balance_ton, starts_at, ends_at, status, week_label)
    VALUES (50, now(), now() + interval '7 days', 'active', 'Temporada ' || to_char(now(), 'IYYY-IW'))
    RETURNING id INTO v_pool;
  ELSE
    UPDATE public.pool_balance
       SET balance_ton = 50,
           starts_at = now(),
           ends_at = now() + interval '7 days',
           updated_at = now()
     WHERE id = v_pool;
  END IF;

  DELETE FROM public.pool_points WHERE pool_id = v_pool;
END $$;

UPDATE public.pool_settings SET season_days = 7, updated_at = now();