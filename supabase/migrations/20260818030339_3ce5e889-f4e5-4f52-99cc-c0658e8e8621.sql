CREATE TABLE IF NOT EXISTS public.myth_token_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  token_name text NOT NULL DEFAULT 'MYTH Token',
  token_symbol text NOT NULL DEFAULT 'MYTH',
  total_supply numeric NOT NULL DEFAULT 100000000,
  visible_in_game boolean NOT NULL DEFAULT true,
  status_label text NOT NULL DEFAULT 'Coming Soon',
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.myth_balances (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  amount numeric NOT NULL DEFAULT 0 CHECK (amount >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.myth_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  direction text NOT NULL CHECK (direction IN ('credit', 'debit', 'supply')),
  amount numeric NOT NULL,
  reason text NOT NULL DEFAULT 'admin_manual',
  admin_telegram_id bigint,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS myth_ledger_user_idx ON public.myth_ledger (user_id, created_at DESC);

GRANT SELECT ON public.myth_token_settings TO authenticated;
GRANT ALL ON public.myth_token_settings TO service_role;
GRANT SELECT ON public.myth_balances TO authenticated;
GRANT ALL ON public.myth_balances TO service_role;
GRANT ALL ON public.myth_ledger TO service_role;

ALTER TABLE public.myth_token_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.myth_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.myth_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "myth settings readable" ON public.myth_token_settings;
CREATE POLICY "myth settings readable" ON public.myth_token_settings FOR SELECT TO authenticated USING (true);

INSERT INTO public.myth_token_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_myth_wallet(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_cfg public.myth_token_settings; v_amount numeric := 0;
BEGIN
  SELECT * INTO v_cfg FROM public.myth_token_settings WHERE id;
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NOT NULL THEN
    SELECT COALESCE(amount, 0) INTO v_amount FROM public.myth_balances WHERE user_id = v_user;
  END IF;
  RETURN jsonb_build_object(
    'name', v_cfg.token_name,
    'symbol', v_cfg.token_symbol,
    'balance', round(COALESCE(v_amount, 0), 4),
    'totalSupply', v_cfg.total_supply,
    'visible', v_cfg.visible_in_game,
    'status', v_cfg.status_label,
    'tradable', false,
    'withdrawable', false,
    'hasUtility', false
  );
END $$;

REVOKE ALL ON FUNCTION public.get_myth_wallet(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_myth_wallet(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_myth_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cfg public.myth_token_settings; v_held numeric; v_holders integer;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT * INTO v_cfg FROM public.myth_token_settings WHERE id;
  SELECT COALESCE(SUM(amount), 0), COUNT(*) FILTER (WHERE amount > 0)
    INTO v_held, v_holders FROM public.myth_balances;
  RETURN jsonb_build_object(
    'name', v_cfg.token_name,
    'symbol', v_cfg.token_symbol,
    'totalSupply', v_cfg.total_supply,
    'playerHeld', round(v_held, 4),
    'adminReserve', round(v_cfg.total_supply - v_held, 4),
    'holders', v_holders,
    'visible', v_cfg.visible_in_game,
    'status', v_cfg.status_label,
    'recent', COALESCE((
      SELECT jsonb_agg(x) FROM (
        SELECT l.direction, l.amount, l.reason, l.created_at,
               p.telegram_id AS telegram_id, COALESCE(p.display_name, p.username, '-') AS player
          FROM public.myth_ledger l
          LEFT JOIN public.game_players p ON p.id = l.user_id
         ORDER BY l.created_at DESC LIMIT 10
      ) x), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_player(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_p record; v_amount numeric := 0;
BEGIN
  PERFORM admin_assert(p_admin_id);
  v_user := admin_resolve_player(p_ref);
  SELECT telegram_id, COALESCE(display_name, username, '-') AS name INTO v_p
    FROM public.game_players WHERE id = v_user;
  SELECT COALESCE(amount, 0) INTO v_amount FROM public.myth_balances WHERE user_id = v_user;
  RETURN jsonb_build_object('userId', v_user, 'telegramId', v_p.telegram_id, 'name', v_p.name,
    'balance', round(COALESCE(v_amount, 0), 4));
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_adjust(p_admin_id bigint, p_ref text, p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_amount numeric := round(COALESCE(p_amount, 0), 4); v_balance numeric; v_reserve numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF v_amount = 0 THEN RAISE EXCEPTION 'MYTH_INVALID_AMOUNT'; END IF;
  v_user := admin_resolve_player(p_ref);

  INSERT INTO public.myth_balances (user_id, amount) VALUES (v_user, 0)
    ON CONFLICT (user_id) DO NOTHING;
  SELECT amount INTO v_balance FROM public.myth_balances WHERE user_id = v_user FOR UPDATE;

  IF v_amount > 0 THEN
    SELECT round(s.total_supply - COALESCE((SELECT SUM(amount) FROM public.myth_balances), 0), 4)
      INTO v_reserve FROM public.myth_token_settings s WHERE s.id;
    IF v_amount > v_reserve THEN RAISE EXCEPTION 'MYTH_RESERVE_INSUFFICIENT'; END IF;
  ELSIF v_balance + v_amount < 0 THEN
    RAISE EXCEPTION 'MYTH_PLAYER_INSUFFICIENT';
  END IF;

  UPDATE public.myth_balances SET amount = amount + v_amount, updated_at = now() WHERE user_id = v_user;
  INSERT INTO public.myth_ledger (user_id, direction, amount, reason, admin_telegram_id)
  VALUES (v_user, CASE WHEN v_amount > 0 THEN 'credit' ELSE 'debit' END, abs(v_amount), 'admin_manual', p_admin_id);

  PERFORM admin_log(p_admin_id, 'myth_adjust', jsonb_build_object('userId', v_user, 'amount', v_amount));
  RETURN admin_myth_player(p_admin_id, p_ref);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_set_supply(p_admin_id bigint, p_total numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total numeric := round(GREATEST(0, COALESCE(p_total, 0)), 4); v_held numeric;
BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT COALESCE(SUM(amount), 0) INTO v_held FROM public.myth_balances;
  IF v_total < v_held THEN RAISE EXCEPTION 'MYTH_SUPPLY_BELOW_HELD'; END IF;
  UPDATE public.myth_token_settings SET total_supply = v_total, updated_at = now() WHERE id;
  INSERT INTO public.myth_ledger (direction, amount, reason, admin_telegram_id)
  VALUES ('supply', v_total, 'admin_set_supply', p_admin_id);
  PERFORM admin_log(p_admin_id, 'myth_set_supply', jsonb_build_object('totalSupply', v_total));
  RETURN admin_myth_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_set_visibility(p_admin_id bigint, p_visible boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  UPDATE public.myth_token_settings SET visible_in_game = COALESCE(p_visible, true), updated_at = now() WHERE id;
  PERFORM admin_log(p_admin_id, 'myth_set_visibility', jsonb_build_object('visible', p_visible));
  RETURN admin_myth_overview(p_admin_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_myth_rename(p_admin_id bigint, p_name text, p_symbol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  UPDATE public.myth_token_settings
     SET token_name = COALESCE(NULLIF(btrim(p_name), ''), token_name),
         token_symbol = COALESCE(NULLIF(upper(btrim(p_symbol)), ''), token_symbol),
         updated_at = now()
   WHERE id;
  PERFORM admin_log(p_admin_id, 'myth_rename', jsonb_build_object('name', p_name, 'symbol', p_symbol));
  RETURN admin_myth_overview(p_admin_id);
END $$;

REVOKE ALL ON FUNCTION public.admin_myth_overview(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_myth_player(bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_myth_adjust(bigint, text, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_myth_set_supply(bigint, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_myth_set_visibility(bigint, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_myth_rename(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_myth_overview(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_player(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_adjust(bigint, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_set_supply(bigint, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_set_visibility(bigint, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_myth_rename(bigint, text, text) TO service_role;