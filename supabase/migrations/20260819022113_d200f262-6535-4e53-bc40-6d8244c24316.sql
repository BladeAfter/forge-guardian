CREATE OR REPLACE FUNCTION public.admin_spending_event_rules(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v := public.spending_event_rules();
  RETURN jsonb_build_object('rules', v,
    'entries', (SELECT COUNT(*) FROM spending_event_entries),
    'scored_players', (SELECT COUNT(*) FROM spending_event_scores WHERE total_points > 0));
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_set_rate(p_admin_id bigint, p_currency text, p_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_old jsonb; v_new jsonb; v_key text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'invalid_value'; END IF;
  v_key := CASE WHEN upper(COALESCE(p_currency,'')) = 'TON' THEN 'ton_points'
                WHEN upper(COALESCE(p_currency,'')) = 'FC' THEN 'fc_points'
                ELSE NULL END;
  IF v_key IS NULL THEN RAISE EXCEPTION 'invalid_currency'; END IF;
  v_old := public.spending_event_rules();
  v_new := jsonb_set(v_old, ARRAY[v_key], to_jsonb(p_value), true);
  INSERT INTO game_settings(key, value, category, label)
  VALUES ('spending_event_rules', v_new, 'events', 'Spending Event point rules')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  PERFORM public.admin_log(p_admin_id, 'spending_event_set_rate', 'settings', 'spending_event_rules', v_old, v_new, NULL, '{}'::jsonb);
  RETURN jsonb_build_object('rules', v_new);
END $$;

CREATE OR REPLACE FUNCTION public.admin_spending_event_toggle_source(p_admin_id bigint, p_source text, p_enabled boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_old jsonb; v_new jsonb; v_src text; v_current boolean; v_next boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_src := lower(COALESCE(p_source,''));
  IF v_src NOT IN ('ton_direct_deposit','ton_to_fc','myth_sale','season_pass','packs','nft_shop','marketplace','auction','fc_spend','other_ton') THEN
    RAISE EXCEPTION 'invalid_source';
  END IF;
  v_old := public.spending_event_rules();
  v_current := COALESCE((v_old -> 'sources' ->> v_src)::boolean, true);
  v_next := COALESCE(p_enabled, NOT v_current);
  v_new := jsonb_set(v_old, ARRAY['sources', v_src], to_jsonb(v_next), true);
  INSERT INTO game_settings(key, value, category, label)
  VALUES ('spending_event_rules', v_new, 'events', 'Spending Event point rules')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  PERFORM public.admin_log(p_admin_id, 'spending_event_toggle_source', 'settings', v_src, v_old, v_new, NULL, '{}'::jsonb);
  RETURN jsonb_build_object('rules', v_new, 'source', v_src, 'enabled', v_next);
END $$;

REVOKE ALL ON FUNCTION public.admin_spending_event_rules(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_spending_event_set_rate(bigint, text, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_spending_event_toggle_source(bigint, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_rules(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_set_rate(bigint, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_spending_event_toggle_source(bigint, text, boolean) TO service_role;