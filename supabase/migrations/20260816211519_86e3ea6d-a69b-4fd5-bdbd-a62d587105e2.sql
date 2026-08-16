CREATE TABLE IF NOT EXISTS public.marketing_pool_expenses (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  category text NOT NULL DEFAULT 'OTHER',
  description text NOT NULL,
  amount_ton numeric NOT NULL CHECK (amount_ton >= 0),
  note text,
  spent_at date NOT NULL DEFAULT (now()::date),
  created_by bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.marketing_pool_expenses TO service_role;
ALTER TABLE public.marketing_pool_expenses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "marketing_pool_expenses_server_only" ON public.marketing_pool_expenses;
CREATE POLICY "marketing_pool_expenses_server_only" ON public.marketing_pool_expenses FOR ALL USING (false) WITH CHECK (false);
CREATE INDEX IF NOT EXISTS marketing_pool_expenses_date_idx ON public.marketing_pool_expenses (spent_at DESC, created_at DESC);

INSERT INTO public.game_settings(key, value, category, label)
VALUES ('marketing_pool_total_ton', '0'::jsonb, 'marketing_pool', 'Marketing Pool total (TON)'),
       ('marketing_pool_enabled', 'false'::jsonb, 'marketing_pool', 'Marketing Pool tab enabled')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.marketing_pool_categories()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['MARKETING','DEVELOPMENT','INFLUENCERS','DESIGN','COMMUNITY','MODERATION','SERVER','OTHER']::text[];
$$;

CREATE OR REPLACE FUNCTION public.marketing_pool_dashboard(p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_total numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM game_settings WHERE key = 'marketing_pool_total_ton'), 0);
  v_enabled boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM game_settings WHERE key = 'marketing_pool_enabled'), false);
  v_spent numeric := 0;
  v_count integer := 0;
  v_updated timestamptz;
  v_limit integer := LEAST(200, GREATEST(5, COALESCE(p_limit, 50)));
BEGIN
  SELECT COALESCE(SUM(amount_ton), 0), COUNT(*), MAX(GREATEST(created_at, updated_at))
    INTO v_spent, v_count, v_updated FROM marketing_pool_expenses;
  v_updated := GREATEST(COALESCE(v_updated, to_timestamp(0)),
    COALESCE((SELECT MAX(updated_at) FROM game_settings WHERE key IN ('marketing_pool_total_ton','marketing_pool_enabled')), to_timestamp(0)));
  RETURN jsonb_build_object(
    'enabled', v_enabled,
    'totalTon', v_total,
    'spentTon', v_spent,
    'remainingTon', GREATEST(0, v_total - v_spent),
    'entries', v_count,
    'updatedAt', v_updated,
    'categories', to_jsonb(marketing_pool_categories()),
    'expenses', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'category', e.category, 'description', e.description,
        'amountTon', e.amount_ton, 'note', e.note, 'spentAt', e.spent_at
      ) ORDER BY e.spent_at DESC, e.created_at DESC)
      FROM (SELECT * FROM marketing_pool_expenses ORDER BY spent_at DESC, created_at DESC LIMIT v_limit) e
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_marketing_pool_overview(p_admin_id bigint, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  RETURN marketing_pool_dashboard(GREATEST(5, COALESCE(p_limit, 20)));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_marketing_pool_set_total(p_admin_id bigint, p_total numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_total IS NULL OR p_total < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
  INSERT INTO game_settings(key, value, category, label, updated_at, updated_by)
  VALUES ('marketing_pool_total_ton', to_jsonb(p_total), 'marketing_pool', 'Marketing Pool total (TON)', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now(), updated_by = p_admin_id;
  PERFORM admin_log(p_admin_id, 'marketing_pool_set_total', 'marketing_pool', jsonb_build_object('total', p_total));
  RETURN marketing_pool_dashboard(20);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_marketing_pool_toggle(p_admin_id bigint, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  INSERT INTO game_settings(key, value, category, label, updated_at, updated_by)
  VALUES ('marketing_pool_enabled', to_jsonb(COALESCE(p_enabled, false)), 'marketing_pool', 'Marketing Pool tab enabled', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now(), updated_by = p_admin_id;
  PERFORM admin_log(p_admin_id, 'marketing_pool_toggle', 'marketing_pool', jsonb_build_object('enabled', COALESCE(p_enabled, false)));
  RETURN marketing_pool_dashboard(20);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_marketing_pool_add_expense(
  p_admin_id bigint, p_category text, p_description text, p_amount numeric,
  p_spent_at date DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cat text := upper(btrim(COALESCE(p_category, 'OTHER'))); v_id uuid;
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF NOT (v_cat = ANY (marketing_pool_categories())) THEN RAISE EXCEPTION 'INVALID_CATEGORY'; END IF;
  IF COALESCE(btrim(p_description), '') = '' THEN RAISE EXCEPTION 'INVALID_DESCRIPTION'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  INSERT INTO marketing_pool_expenses(category, description, amount_ton, note, spent_at, created_by)
  VALUES (v_cat, btrim(p_description), p_amount, NULLIF(btrim(COALESCE(p_note, '')), ''), COALESCE(p_spent_at, now()::date), p_admin_id)
  RETURNING id INTO v_id;
  PERFORM admin_log(p_admin_id, 'marketing_pool_add_expense', v_id::text, jsonb_build_object('category', v_cat, 'amount', p_amount));
  RETURN marketing_pool_dashboard(20) || jsonb_build_object('expenseId', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_marketing_pool_update_expense(
  p_admin_id bigint, p_id uuid, p_category text DEFAULT NULL, p_description text DEFAULT NULL,
  p_amount numeric DEFAULT NULL, p_spent_at date DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cat text := NULLIF(upper(btrim(COALESCE(p_category, ''))), '');
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF v_cat IS NOT NULL AND NOT (v_cat = ANY (marketing_pool_categories())) THEN RAISE EXCEPTION 'INVALID_CATEGORY'; END IF;
  IF p_amount IS NOT NULL AND p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  UPDATE marketing_pool_expenses SET
    category = COALESCE(v_cat, category),
    description = COALESCE(NULLIF(btrim(COALESCE(p_description, '')), ''), description),
    amount_ton = COALESCE(p_amount, amount_ton),
    spent_at = COALESCE(p_spent_at, spent_at),
    note = CASE WHEN p_note IS NULL THEN note WHEN btrim(p_note) IN ('', '-') THEN NULL ELSE btrim(p_note) END,
    updated_at = now()
  WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EXPENSE_NOT_FOUND'; END IF;
  PERFORM admin_log(p_admin_id, 'marketing_pool_update_expense', p_id::text, jsonb_build_object('category', v_cat, 'amount', p_amount));
  RETURN marketing_pool_dashboard(20);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_marketing_pool_delete_expense(p_admin_id bigint, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM admin_assert(p_admin_id);
  DELETE FROM marketing_pool_expenses WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EXPENSE_NOT_FOUND'; END IF;
  PERFORM admin_log(p_admin_id, 'marketing_pool_delete_expense', p_id::text, '{}'::jsonb);
  RETURN marketing_pool_dashboard(20);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_marketing_pool_reset(p_admin_id bigint, p_mode text DEFAULT 'expenses')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_mode text := lower(COALESCE(btrim(p_mode), 'expenses'));
BEGIN
  PERFORM admin_assert(p_admin_id);
  IF v_mode NOT IN ('expenses', 'all') THEN RAISE EXCEPTION 'INVALID_MODE'; END IF;
  DELETE FROM marketing_pool_expenses;
  IF v_mode = 'all' THEN
    INSERT INTO game_settings(key, value, category, label, updated_at, updated_by)
    VALUES ('marketing_pool_total_ton', '0'::jsonb, 'marketing_pool', 'Marketing Pool total (TON)', now(), p_admin_id)
    ON CONFLICT (key) DO UPDATE SET value = '0'::jsonb, updated_at = now(), updated_by = p_admin_id;
  END IF;
  PERFORM admin_log(p_admin_id, 'marketing_pool_reset', v_mode, '{}'::jsonb);
  RETURN marketing_pool_dashboard(20);
END;
$$;

REVOKE ALL ON FUNCTION public.marketing_pool_dashboard(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_marketing_pool_overview(bigint, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_marketing_pool_set_total(bigint, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_marketing_pool_toggle(bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_marketing_pool_add_expense(bigint, text, text, numeric, date, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_marketing_pool_update_expense(bigint, uuid, text, text, numeric, date, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_marketing_pool_delete_expense(bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_marketing_pool_reset(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marketing_pool_dashboard(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_marketing_pool_overview(bigint, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_marketing_pool_set_total(bigint, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_marketing_pool_toggle(bigint, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_marketing_pool_add_expense(bigint, text, text, numeric, date, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_marketing_pool_update_expense(bigint, uuid, text, text, numeric, date, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_marketing_pool_delete_expense(bigint, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_marketing_pool_reset(bigint, text) TO service_role;