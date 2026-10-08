ALTER TABLE public.season_pass_level_purchases
  ALTER COLUMN purchase_date TYPE date USING purchase_date::date;

CREATE OR REPLACE FUNCTION public.buy_season_pass_levels(p_telegram_id bigint, p_levels integer, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u public.game_players; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        cfg jsonb; v_price numeric; v_limit int; v_bought int; v_xpl int; v_level int;
        v_new_level int; v_xp_into int; v_new_xp numeric; v_before numeric; v_day date;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pass_level_buy'||u.id::text, 0));
  IF EXISTS (SELECT 1 FROM public.season_pass_level_purchases WHERE idempotency_key = p_idempotency_key) THEN
    RETURN public.get_season_pass_dashboard(p_telegram_id);
  END IF;

  cfg := public.season_pass_level_purchase_config();
  IF NOT COALESCE((cfg->>'enabled')::boolean, true) THEN RAISE EXCEPTION 'LEVEL_PURCHASE_DISABLED'; END IF;
  v_price := (cfg->'prices'->>p_levels::text)::numeric;
  IF v_price IS NULL OR p_levels <= 0 THEN RAISE EXCEPTION 'INVALID_PACK'; END IF;

  SELECT * INTO s FROM public.season_pass_seasons WHERE active AND now() BETWEEN start_at AND end_at;
  IF s.id IS NULL THEN RAISE EXCEPTION 'SEASON_NOT_AVAILABLE'; END IF;
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (u.id, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = u.id AND season_id = s.id FOR UPDATE;

  v_xpl := GREATEST(1, s.xp_per_level);
  v_level := LEAST(s.levels, (p.xp / v_xpl)::int + 1);
  IF v_level >= s.levels THEN RAISE EXCEPTION 'MAX_LEVEL_REACHED'; END IF;
  IF v_level + p_levels > s.levels THEN RAISE EXCEPTION 'LEVELS_AVAILABLE_%', s.levels - v_level; END IF;

  v_day := public.quest_today();
  v_limit := GREATEST(0, COALESCE((cfg->>'daily_limit')::int, 5));
  SELECT COALESCE(sum(levels_bought),0) INTO v_bought FROM public.season_pass_level_purchases
    WHERE user_id = u.id AND purchase_date = v_day;
  IF v_bought + p_levels > v_limit THEN RAISE EXCEPTION 'DAILY_LIMIT_%', GREATEST(0, v_limit - v_bought); END IF;

  IF COALESCE(u.forge_coins,0) < v_price THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;

  v_xp_into := (p.xp % v_xpl)::int;
  v_new_level := v_level + p_levels;
  v_new_xp := (v_new_level - 1)::numeric * v_xpl + v_xp_into;
  v_before := COALESCE(u.forge_coins,0);

  UPDATE public.game_players SET forge_coins = forge_coins - v_price WHERE id = u.id;
  UPDATE public.player_season_pass SET xp = v_new_xp, updated_at = now()
    WHERE user_id = u.id AND season_id = s.id;

  INSERT INTO public.season_pass_level_purchases
    (user_id, season_id, purchase_date, levels_bought, fc_spent, level_before, level_after, xp_before, xp_after, idempotency_key)
  VALUES (u.id, s.id, v_day, p_levels, v_price, v_level, v_new_level, p.xp, v_new_xp, p_idempotency_key);

  INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (u.id, 'battle_pass_level_purchase', -v_price, v_before, v_before - v_price, p_idempotency_key);

  RETURN public.get_season_pass_dashboard(p_telegram_id)
    || jsonb_build_object('purchase', jsonb_build_object('levelsBought', p_levels, 'fcSpent', v_price,
         'levelBefore', v_level, 'levelAfter', v_new_level));
END; $$;