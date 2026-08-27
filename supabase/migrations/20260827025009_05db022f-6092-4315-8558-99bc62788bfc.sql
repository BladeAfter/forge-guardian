-- ═══════════════ CLAN SHOP ECONOMY V2 ═══════════════
-- Scarce, per-clan, weekly-locked clan coin economy.

CREATE TABLE IF NOT EXISTS public.clan_coin_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  personal_weekly_cap integer NOT NULL DEFAULT 700,
  boss_coins integer[] NOT NULL DEFAULT ARRAY[5,8,12,20],
  milestone_coins jsonb NOT NULL DEFAULT '{"25":20,"50":30,"75":40,"100":60}'::jsonb,
  raid_participation integer NOT NULL DEFAULT 30,
  raid_defeat integer NOT NULL DEFAULT 50,
  raid_top_bonus integer[] NOT NULL DEFAULT ARRAY[25,15,10],
  war_participation integer NOT NULL DEFAULT 40,
  war_victory integer NOT NULL DEFAULT 60,
  target_coins_per_active integer NOT NULL DEFAULT 350,
  price_multiplier_min numeric NOT NULL DEFAULT 0.90,
  price_multiplier_max numeric NOT NULL DEFAULT 1.30,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_coin_settings TO service_role;
ALTER TABLE public.clan_coin_settings ENABLE ROW LEVEL SECURITY;
INSERT INTO public.clan_coin_settings(id) VALUES (true) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.clan_coin_source_caps (
  source_type text PRIMARY KEY,
  label text NOT NULL,
  daily_cap integer NOT NULL DEFAULT 0,
  weekly_cap integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_coin_source_caps TO service_role;
ALTER TABLE public.clan_coin_source_caps ENABLE ROW LEVEL SECURITY;
INSERT INTO public.clan_coin_source_caps(source_type,label,daily_cap,weekly_cap) VALUES
  ('PERSONAL_BOSS','Chefe Pessoal',45,315),
  ('WEEKLY_GOAL','Meta Semanal',150,150),
  ('CLAN_RAID','Clan Raid',150,150),
  ('CLAN_WAR','Guerra de Clãs',100,100),
  ('CLAN_MISSION','Missões do Clã',60,100),
  ('CONTRIBUTION','Contribuição',60,200)
ON CONFLICT (source_type) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.clan_coin_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  clan_id uuid REFERENCES public.clans(id) ON DELETE SET NULL,
  cycle_key date NOT NULL DEFAULT public.clan_week_key(),
  day_key date NOT NULL DEFAULT public.game_day_key(),
  source_type text NOT NULL,
  source_id text,
  requested integer NOT NULL DEFAULT 0,
  amount integer NOT NULL DEFAULT 0,
  capped integer NOT NULL DEFAULT 0,
  balance_before bigint NOT NULL DEFAULT 0,
  balance_after bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS clan_coin_ledger_src_uidx
  ON public.clan_coin_ledger(user_id, source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS clan_coin_ledger_week_idx ON public.clan_coin_ledger(user_id, cycle_key);
CREATE INDEX IF NOT EXISTS clan_coin_ledger_clan_idx ON public.clan_coin_ledger(clan_id, cycle_key);
GRANT ALL ON public.clan_coin_ledger TO service_role;
ALTER TABLE public.clan_coin_ledger ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.clan_coin_cfg() RETURNS public.clan_coin_settings
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.clan_coin_settings WHERE id LIMIT 1;
$$;

-- ═══ single funnel for every clan coin emission ═══
CREATE OR REPLACE FUNCTION public.clan_coin_award(
  p_user uuid, p_source text, p_source_id text, p_amount bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_coin_settings; cap public.clan_coin_source_caps;
        v_clan uuid; v_bal bigint; v_week date; v_day date;
        v_week_total bigint; v_src_week bigint; v_src_day bigint;
        v_allow bigint; v_grant bigint;
BEGIN
  cfg := public.clan_coin_cfg();
  IF NOT cfg.enabled OR COALESCE(p_amount,0) <= 0 THEN
    RETURN jsonb_build_object('status','skipped','granted',0);
  END IF;

  -- personal balance lock: caps and credit must be evaluated atomically
  SELECT clan_id, clan_points INTO v_clan, v_bal
    FROM public.clan_members WHERE user_id = p_user FOR UPDATE;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('status','no_clan','granted',0); END IF;

  v_week := public.clan_week_key();
  v_day := public.game_day_key();
  SELECT * INTO cap FROM public.clan_coin_source_caps WHERE source_type = p_source;
  IF cap.source_type IS NOT NULL AND NOT cap.enabled THEN
    RETURN jsonb_build_object('status','disabled','granted',0);
  END IF;

  SELECT COALESCE(sum(amount),0) INTO v_week_total
    FROM public.clan_coin_ledger WHERE user_id = p_user AND cycle_key = v_week;
  SELECT COALESCE(sum(amount),0) INTO v_src_week
    FROM public.clan_coin_ledger WHERE user_id = p_user AND cycle_key = v_week AND source_type = p_source;
  SELECT COALESCE(sum(amount),0) INTO v_src_day
    FROM public.clan_coin_ledger WHERE user_id = p_user AND day_key = v_day AND source_type = p_source;

  v_allow := p_amount;
  IF cfg.personal_weekly_cap > 0 THEN
    v_allow := LEAST(v_allow, GREATEST(0, cfg.personal_weekly_cap - v_week_total));
  END IF;
  IF cap.weekly_cap IS NOT NULL AND cap.weekly_cap > 0 THEN
    v_allow := LEAST(v_allow, GREATEST(0, cap.weekly_cap - v_src_week));
  END IF;
  IF cap.daily_cap IS NOT NULL AND cap.daily_cap > 0 THEN
    v_allow := LEAST(v_allow, GREATEST(0, cap.daily_cap - v_src_day));
  END IF;
  v_grant := GREATEST(0, v_allow);

  INSERT INTO public.clan_coin_ledger(user_id, clan_id, cycle_key, day_key, source_type, source_id,
                                      requested, amount, capped, balance_before, balance_after)
  VALUES (p_user, v_clan, v_week, v_day, p_source, p_source_id,
          p_amount, v_grant, p_amount - v_grant, v_bal, v_bal + v_grant)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','duplicate','granted',0); END IF;

  IF v_grant > 0 THEN
    UPDATE public.clan_members SET clan_points = clan_points + v_grant, updated_at = now()
     WHERE user_id = p_user;
  END IF;

  RETURN jsonb_build_object(
    'status', CASE WHEN v_grant = 0 THEN 'capped' WHEN v_grant < p_amount THEN 'partial' ELSE 'ok' END,
    'granted', v_grant, 'requested', p_amount,
    'weeklyTotal', v_week_total + v_grant, 'weeklyCap', cfg.personal_weekly_cap,
    'balance', v_bal + v_grant);
END $$;

-- ═══ effective active members (activity weighted, never raw member count) ═══
CREATE OR REPLACE FUNCTION public.clan_shop_effective_active(p_clan uuid)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total int; v_24h int; v_7d int; v_contrib int; v_eff int;
BEGIN
  SELECT count(*) INTO v_total FROM public.clan_members WHERE clan_id = p_clan;
  SELECT count(*) INTO v_24h FROM public.clan_members m JOIN public.game_players g ON g.id = m.user_id
   WHERE m.clan_id = p_clan AND COALESCE(g.last_seen_at, m.joined_at) > now() - interval '24 hours';
  SELECT count(*) INTO v_7d FROM public.clan_members m JOIN public.game_players g ON g.id = m.user_id
   WHERE m.clan_id = p_clan AND COALESCE(g.last_seen_at, m.joined_at) > now() - interval '7 days';
  SELECT count(DISTINCT p.user_id) INTO v_contrib
    FROM public.clan_weekly_member_progress p
    JOIN public.clan_weekly_cycles c ON c.id = p.cycle_id
   WHERE p.clan_id = p_clan AND c.week_key >= public.clan_week_key() - 7 AND p.contribution > 0;
  v_eff := round(0.55 * v_24h + 0.30 * v_7d + 0.15 * COALESCE(v_contrib,0))::int;
  RETURN GREATEST(1, LEAST(GREATEST(v_total,1), v_eff));
END $$;

CREATE TABLE IF NOT EXISTS public.clan_shop_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  week_key date NOT NULL DEFAULT public.clan_week_key(),
  effective_active_members integer NOT NULL DEFAULT 1,
  total_members integer NOT NULL DEFAULT 0,
  reference_emission bigint NOT NULL DEFAULT 0,
  forecast_emission bigint NOT NULL DEFAULT 0,
  price_multiplier numeric NOT NULL DEFAULT 1.0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clan_id, week_key)
);
GRANT ALL ON public.clan_shop_cycles TO service_role;
ALTER TABLE public.clan_shop_cycles ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_shop_stock (
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  week_key date NOT NULL DEFAULT public.clan_week_key(),
  code text NOT NULL,
  stock_total integer NOT NULL DEFAULT 0,
  stock_used integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (clan_id, week_key, code)
);
GRANT ALL ON public.clan_shop_stock TO service_role;
ALTER TABLE public.clan_shop_stock ENABLE ROW LEVEL SECURITY;

-- weekly snapshot: locked for the whole week, recalculated only on the next cycle
CREATE OR REPLACE FUNCTION public.clan_shop_cycle_ensure(p_clan uuid)
RETURNS public.clan_shop_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_coin_settings; sc public.clan_shop_cycles;
        v_week date; v_eff int; v_total int; v_ref bigint; v_fore bigint; v_ratio numeric; v_mult numeric;
BEGIN
  cfg := public.clan_coin_cfg();
  v_week := public.clan_week_key();
  SELECT * INTO sc FROM public.clan_shop_cycles WHERE clan_id = p_clan AND week_key = v_week;
  IF sc.id IS NOT NULL THEN RETURN sc; END IF;

  v_eff := public.clan_shop_effective_active(p_clan);
  SELECT count(*) INTO v_total FROM public.clan_members WHERE clan_id = p_clan;
  v_ref := GREATEST(1, v_eff::bigint * cfg.target_coins_per_active);
  SELECT COALESCE(sum(amount),0) INTO v_fore
    FROM public.clan_coin_ledger WHERE clan_id = p_clan AND cycle_key = v_week - 7;
  IF v_fore <= 0 THEN v_fore := v_ref; END IF;
  v_ratio := v_fore::numeric / v_ref::numeric;
  v_mult := round(LEAST(cfg.price_multiplier_max,
                        GREATEST(cfg.price_multiplier_min, sqrt(v_ratio))), 2);

  INSERT INTO public.clan_shop_cycles(clan_id, week_key, effective_active_members, total_members,
                                      reference_emission, forecast_emission, price_multiplier)
  VALUES (p_clan, v_week, v_eff, v_total, v_ref, v_fore, v_mult)
  ON CONFLICT (clan_id, week_key) DO UPDATE SET clan_id = EXCLUDED.clan_id
  RETURNING * INTO sc;
  RETURN sc;
END $$;

-- ═══ shop catalogue: base prices, personal limits, per-clan weekly stock ═══
ALTER TABLE public.clan_shop_config
  ADD COLUMN IF NOT EXISTS clan_weekly_stock integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS scale_stock boolean NOT NULL DEFAULT false;

UPDATE public.clan_shop_config SET cost_coins = 120, daily_limit = 3, weekly_limit = 0,
       clan_weekly_stock = 0, scale_stock = false WHERE code = 'PET_FOOD';
UPDATE public.clan_shop_config SET cost_coins = 180, daily_limit = 2, weekly_limit = 0,
       clan_weekly_stock = 0, scale_stock = false WHERE code = 'FRAGMENTS';
UPDATE public.clan_shop_config SET cost_coins = 300, daily_limit = 0, weekly_limit = 3,
       clan_weekly_stock = 0, scale_stock = false WHERE code = 'UNIVERSAL_FRAGMENTS';
UPDATE public.clan_shop_config SET cost_coins = 200, daily_limit = 0, weekly_limit = 3,
       clan_weekly_stock = 0, scale_stock = false WHERE code = 'PVP_TICKET';
UPDATE public.clan_shop_config SET cost_coins = 700, daily_limit = 0, weekly_limit = 3,
       clan_weekly_stock = 15, scale_stock = false WHERE code = 'RARE_CHEST';
UPDATE public.clan_shop_config SET cost_coins = 1800, daily_limit = 0, weekly_limit = 1,
       clan_weekly_stock = 5, scale_stock = false WHERE code = 'EPIC_CHEST';

ALTER TABLE public.clan_shop_purchases
  ADD COLUMN IF NOT EXISTS cycle_key date NOT NULL DEFAULT public.clan_week_key(),
  ADD COLUMN IF NOT EXISTS unit_price integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS price_multiplier numeric NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS clan_stock_before integer,
  ADD COLUMN IF NOT EXISTS clan_stock_after integer,
  ADD COLUMN IF NOT EXISTS personal_before integer,
  ADD COLUMN IF NOT EXISTS personal_after integer;

-- ═══ purchase: atomic, idempotent, stock aware, anti clan hopping ═══
CREATE OR REPLACE FUNCTION public.clan_shop_purchase(
  p_telegram_id bigint, p_code text, p_quantity integer DEFAULT 1, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_coins bigint; s public.clan_shop_config; sc public.clan_shop_cycles;
        v_qty integer; v_unit bigint; v_cost bigint; v_day integer; v_week integer; v_clan_level integer;
        v_stock public.clan_shop_stock; v_total_stock integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);

  -- (3) lock personal coin balance
  SELECT clan_id, clan_points INTO v_clan, v_coins
    FROM public.clan_members WHERE user_id = v_uid FOR UPDATE;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  SELECT * INTO s FROM public.clan_shop_config WHERE code = p_code AND enabled;
  IF s.code IS NULL THEN RAISE EXCEPTION 'INVALID_ITEM'; END IF;

  SELECT level INTO v_clan_level FROM public.clans WHERE id = v_clan;
  IF v_clan_level < s.required_clan_level THEN RAISE EXCEPTION 'CLAN_LEVEL_REQUIRED'; END IF;

  sc := public.clan_shop_cycle_ensure(v_clan);
  v_qty := GREATEST(1, LEAST(20, COALESCE(p_quantity, 1)));
  v_unit := round(s.cost_coins * sc.price_multiplier)::bigint;
  v_cost := v_unit * v_qty;

  -- personal limits are counted on the GLOBAL weekly cycle: switching clans never resets them
  SELECT COALESCE(sum(quantity),0) INTO v_day FROM public.clan_shop_purchases
   WHERE user_id = v_uid AND code = p_code AND purchase_day = public.game_day_key();
  IF s.daily_limit > 0 AND v_day + v_qty > s.daily_limit THEN RAISE EXCEPTION 'DAILY_LIMIT_REACHED'; END IF;

  SELECT COALESCE(sum(quantity),0) INTO v_week FROM public.clan_shop_purchases
   WHERE user_id = v_uid AND code = p_code AND week_key = public.clan_week_key();
  IF s.weekly_limit > 0 AND v_week + v_qty > s.weekly_limit THEN
    RAISE EXCEPTION 'PERSONAL_WEEKLY_LIMIT_REACHED';
  END IF;

  -- (4) lock per-clan weekly stock
  IF s.clan_weekly_stock > 0 THEN
    v_total_stock := CASE WHEN s.scale_stock
      THEN s.clan_weekly_stock * GREATEST(1, ceil(sc.effective_active_members / 10.0)::int)
      ELSE s.clan_weekly_stock END;
    INSERT INTO public.clan_shop_stock(clan_id, week_key, code, stock_total)
    VALUES (v_clan, public.clan_week_key(), p_code, v_total_stock)
    ON CONFLICT (clan_id, week_key, code) DO NOTHING;
    SELECT * INTO v_stock FROM public.clan_shop_stock
     WHERE clan_id = v_clan AND week_key = public.clan_week_key() AND code = p_code FOR UPDATE;
    IF v_stock.stock_used + v_qty > v_stock.stock_total THEN RAISE EXCEPTION 'OUT_OF_STOCK'; END IF;
  END IF;

  IF v_coins < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_CLAN_COINS'; END IF;

  INSERT INTO public.clan_shop_purchases(clan_id, user_id, code, quantity, cost_coins, idempotency_key,
                                         cycle_key, unit_price, price_multiplier,
                                         clan_stock_before, clan_stock_after, personal_before, personal_after)
  VALUES (v_clan, v_uid, p_code, v_qty, v_cost, p_idempotency_key,
          public.clan_week_key(), v_unit, sc.price_multiplier,
          v_stock.stock_used, COALESCE(v_stock.stock_used,0) + v_qty, v_week, v_week + v_qty)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','duplicate'); END IF;

  IF s.clan_weekly_stock > 0 THEN
    UPDATE public.clan_shop_stock SET stock_used = stock_used + v_qty, updated_at = now()
     WHERE clan_id = v_clan AND week_key = public.clan_week_key() AND code = p_code;
  END IF;

  UPDATE public.clan_members SET clan_points = clan_points - v_cost, updated_at = now() WHERE user_id = v_uid;
  INSERT INTO public.clan_points_ledger(clan_id, user_id, amount, reason)
  VALUES (v_clan, v_uid, -v_cost, 'clan_shop:' || p_code);

  IF s.item_type = 'pvp_ticket' THEN
    UPDATE public.game_players SET pvp_tickets = pvp_tickets + (s.quantity * v_qty), updated_at = now()
     WHERE id = v_uid;
  ELSIF s.item_type = 'universal_fragments' THEN
    PERFORM public.add_universal_fragments(v_uid, s.quantity * v_qty);
  ELSIF s.item_type = 'pet_food' THEN
    INSERT INTO public.player_pet_food(user_id, food_code, quantity)
    VALUES (v_uid, s.item_code, s.quantity * v_qty)
    ON CONFLICT (user_id, food_code) DO UPDATE
      SET quantity = public.player_pet_food.quantity + EXCLUDED.quantity;
  ELSE
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (v_uid, s.item_type, s.item_code, s.quantity * v_qty)
    ON CONFLICT (user_id, item_type, item_code) DO UPDATE
      SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
  END IF;

  RETURN jsonb_build_object('status','purchased','code', p_code, 'quantity', v_qty,
                            'unitPrice', v_unit, 'cost', v_cost, 'coins', v_coins - v_cost,
                            'clanStockLeft', CASE WHEN s.clan_weekly_stock > 0
                              THEN v_stock.stock_total - v_stock.stock_used - v_qty ELSE NULL END);
END $$;

-- legacy entry point must obey the same economy
CREATE OR REPLACE FUNCTION public.clan_shop_buy(p_telegram_id bigint, p_item text, p_quantity integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN public.clan_shop_purchase(p_telegram_id, p_item, p_quantity, NULL);
END $$;

-- ═══ shop state for the client ═══
CREATE OR REPLACE FUNCTION public.clan_shop_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_clan uuid; v_coins bigint; sc public.clan_shop_cycles;
        cfg public.clan_coin_settings; v_week bigint;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id, clan_points INTO v_clan, v_coins FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('inClan', false); END IF;
  cfg := public.clan_coin_cfg();
  sc := public.clan_shop_cycle_ensure(v_clan);
  SELECT COALESCE(sum(amount),0) INTO v_week FROM public.clan_coin_ledger
   WHERE user_id = v_uid AND cycle_key = public.clan_week_key();

  RETURN jsonb_build_object(
    'inClan', true,
    'coins', COALESCE(v_coins,0),
    'weeklyEarned', v_week,
    'weeklyCap', cfg.personal_weekly_cap,
    'priceMultiplier', sc.price_multiplier,
    'effectiveActive', sc.effective_active_members,
    'cycleEndsAt', (public.clan_week_key() + 7)::timestamptz,
    'items', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'code', s.code, 'label', s.label, 'quantity', s.quantity,
        'price', round(s.cost_coins * sc.price_multiplier),
        'basePrice', s.cost_coins,
        'dailyLimit', s.daily_limit, 'weeklyLimit', s.weekly_limit,
        'requiredClanLevel', s.required_clan_level,
        'boughtToday', COALESCE((SELECT sum(quantity) FROM public.clan_shop_purchases p
                                  WHERE p.user_id = v_uid AND p.code = s.code
                                    AND p.purchase_day = public.game_day_key()), 0),
        'boughtWeek', COALESCE((SELECT sum(quantity) FROM public.clan_shop_purchases p
                                 WHERE p.user_id = v_uid AND p.code = s.code
                                   AND p.week_key = public.clan_week_key()), 0),
        'clanStock', CASE WHEN s.clan_weekly_stock > 0 THEN
            COALESCE((SELECT st.stock_total - st.stock_used FROM public.clan_shop_stock st
                       WHERE st.clan_id = v_clan AND st.week_key = public.clan_week_key()
                         AND st.code = s.code),
                     CASE WHEN s.scale_stock
                       THEN s.clan_weekly_stock * GREATEST(1, ceil(sc.effective_active_members / 10.0)::int)
                       ELSE s.clan_weekly_stock END)
          ELSE NULL END,
        'clanStockTotal', CASE WHEN s.clan_weekly_stock > 0 THEN
            CASE WHEN s.scale_stock
              THEN s.clan_weekly_stock * GREATEST(1, ceil(sc.effective_active_members / 10.0)::int)
              ELSE s.clan_weekly_stock END
          ELSE NULL END
      ) ORDER BY s.sort_order), '[]'::jsonb) FROM public.clan_shop_config s WHERE s.enabled)
  );
END $$;

-- ═══ route every existing emission through the capped funnel ═══
DROP FUNCTION IF EXISTS public.clan_award_contribution(uuid, bigint, text, text);
CREATE OR REPLACE FUNCTION public.clan_award_contribution(
  p_user uuid, p_amount bigint, p_source_type text, p_source_id text DEFAULT NULL,
  p_coins bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; v_clan uuid; c public.clan_weekly_cycles;
        v_coins bigint; v_res jsonb; v_xp integer; v_joined timestamptz;
BEGIN
  cfg := public.clan_collective_cfg();
  IF NOT cfg.enabled OR COALESCE(p_amount,0) <= 0 THEN RETURN jsonb_build_object('status','skipped'); END IF;

  SELECT clan_id, joined_at INTO v_clan, v_joined FROM public.clan_members WHERE user_id = p_user;
  IF v_clan IS NULL THEN RETURN jsonb_build_object('status','no_clan'); END IF;

  c := public.clan_weekly_cycle_ensure(v_clan);

  INSERT INTO public.clan_contribution_ledger(clan_id, user_id, cycle_id, amount, source_type, source_id)
  VALUES (v_clan, p_user, c.id, p_amount, p_source_type, p_source_id)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','duplicate'); END IF;

  INSERT INTO public.clan_weekly_member_progress(cycle_id, user_id, clan_id, contribution, joined_at)
  VALUES (c.id, p_user, v_clan, p_amount, COALESCE(v_joined, now()))
  ON CONFLICT (cycle_id, user_id) DO UPDATE
    SET contribution = public.clan_weekly_member_progress.contribution + EXCLUDED.contribution,
        updated_at = now();

  UPDATE public.clan_weekly_cycles
     SET total_contribution = total_contribution + p_amount, updated_at = now()
   WHERE id = c.id;

  UPDATE public.clans SET clan_points = clan_points + p_amount, updated_at = now() WHERE id = v_clan;

  -- coins are scarce and capped; contribution volume no longer mints them 1:1
  v_coins := COALESCE(p_coins, floor(p_amount * cfg.coins_per_contribution)::bigint);
  v_res := public.clan_coin_award(p_user, p_source_type,
                                  COALESCE(p_source_id, c.id::text || ':' || p_amount::text), v_coins);

  v_xp := floor(p_amount * cfg.clan_xp_per_contribution)::int;
  IF v_xp > 0 THEN PERFORM public.grant_clan_xp(p_user, 'clan_contribution', v_xp); END IF;

  RETURN jsonb_build_object('status','ok','clanId', v_clan, 'amount', p_amount,
                            'coins', COALESCE((v_res->>'granted')::bigint, 0), 'coinAward', v_res);
END $$;

CREATE OR REPLACE FUNCTION public.clan_contribution_from_personal_boss(p_user uuid, p_instance uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; cc public.clan_coin_settings;
        v_nth integer; v_amount bigint; v_coins bigint;
BEGIN
  cfg := public.clan_collective_cfg();
  cc := public.clan_coin_cfg();
  SELECT COALESCE(defeated_count, 1) INTO v_nth
    FROM public.clan_boss_daily_counters
   WHERE user_id = p_user AND reset_day = public.clan_boss_reset_day(now());
  v_nth := GREATEST(1, COALESCE(v_nth, 1));
  v_amount := COALESCE(cfg.boss_points[LEAST(v_nth, array_length(cfg.boss_points,1))],
                       cfg.boss_points[array_length(cfg.boss_points,1)]);
  v_coins := COALESCE(cc.boss_coins[LEAST(v_nth, array_length(cc.boss_coins,1))],
                      cc.boss_coins[array_length(cc.boss_coins,1)]);
  RETURN public.clan_award_contribution(p_user, v_amount, 'PERSONAL_BOSS', p_instance::text, v_coins);
END $$;

-- Weekly goal milestones: fixed, capped coin values
CREATE OR REPLACE FUNCTION public.clan_milestone_claim(p_telegram_id bigint, p_pct integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg public.clan_collective_settings; cc public.clan_coin_settings;
        v_uid uuid; v_clan uuid; c public.clan_weekly_cycles; mp public.clan_weekly_member_progress;
        v_reward jsonb; v_reached timestamptz; v_coins integer; v_res jsonb;
BEGIN
  cfg := public.clan_collective_cfg();
  cc := public.clan_coin_cfg();
  v_uid := public.clan_resolve_user(p_telegram_id);
  SELECT clan_id INTO v_clan FROM public.clan_members WHERE user_id = v_uid;
  IF v_clan IS NULL THEN RAISE EXCEPTION 'NOT_IN_CLAN'; END IF;

  c := public.clan_weekly_cycle_ensure(v_clan);
  SELECT * INTO mp FROM public.clan_weekly_member_progress WHERE cycle_id = c.id AND user_id = v_uid;
  IF mp.user_id IS NULL OR mp.contribution < cfg.min_weekly_contribution THEN
    RAISE EXCEPTION 'MIN_CONTRIBUTION_REQUIRED';
  END IF;

  SELECT elem INTO v_reward FROM jsonb_array_elements(cfg.milestones) elem
   WHERE (elem->>'pct')::int = p_pct;
  IF v_reward IS NULL THEN RAISE EXCEPTION 'INVALID_MILESTONE'; END IF;
  IF c.total_contribution * 100 < c.target * p_pct THEN RAISE EXCEPTION 'MILESTONE_LOCKED'; END IF;

  SELECT min(created_at) INTO v_reached
    FROM (SELECT created_at, sum(amount) OVER (ORDER BY created_at) AS running
            FROM public.clan_contribution_ledger WHERE cycle_id = c.id) t
   WHERE running * 100 >= c.target * p_pct;
  IF v_reached IS NOT NULL AND mp.joined_at > v_reached THEN
    RAISE EXCEPTION 'JOINED_AFTER_MILESTONE';
  END IF;

  v_coins := COALESCE((cc.milestone_coins->>p_pct::text)::int, 0);
  v_reward := v_reward - 'coins';

  INSERT INTO public.clan_milestone_claims(cycle_id, clan_id, user_id, milestone_pct, payload)
  VALUES (c.id, v_clan, v_uid, p_pct, v_reward || jsonb_build_object('coins', v_coins))
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RAISE EXCEPTION 'ALREADY_CLAIMED'; END IF;

  PERFORM public.clan_boss_deliver(v_uid, v_reward);
  v_res := public.clan_coin_award(v_uid, 'WEEKLY_GOAL', c.id::text || ':' || p_pct::text, v_coins);
  IF COALESCE((v_reward->>'clanXp')::int, 0) > 0 THEN
    PERFORM public.grant_clan_xp(v_uid, 'clan_milestone', (v_reward->>'clanXp')::int);
  END IF;

  RETURN jsonb_build_object('status','claimed','milestone', p_pct, 'reward', v_reward, 'coinAward', v_res);
END $$;

-- Clan Raid: flat participation/defeat coins + small top-damage bonus (no pool split)
CREATE OR REPLACE FUNCTION public.clan_raid_settle(p_raid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.clan_raid_cycles; cfg public.clan_collective_settings; cc public.clan_coin_settings;
        snap jsonb; v_min numeric; rec record; v_share numeric; v_reward jsonb;
        v_paid integer := 0; v_coins integer; v_rank integer;
BEGIN
  cfg := public.clan_collective_cfg();
  cc := public.clan_coin_cfg();
  SELECT * INTO r FROM public.clan_raid_cycles WHERE id = p_raid FOR UPDATE;
  IF r.id IS NULL OR r.settled_at IS NOT NULL THEN RETURN jsonb_build_object('status','already'); END IF;
  IF r.status NOT IN ('DEFEATED','EXPIRED') THEN RETURN jsonb_build_object('status','active'); END IF;

  snap := COALESCE(r.rewards_snapshot, '{}'::jsonb);
  v_min := r.max_hp * COALESCE((snap->>'minDamagePct')::numeric, 0.5) / 100.0;

  IF r.status = 'DEFEATED' OR NOT cfg.raid_full_kill_required THEN
    FOR rec IN
      SELECT user_id, sum(damage) AS dmg,
             row_number() OVER (ORDER BY sum(damage) DESC) AS rnk
        FROM public.clan_raid_attacks
       WHERE raid_id = r.id GROUP BY user_id HAVING sum(damage) >= v_min
    LOOP
      v_share := CASE WHEN r.total_damage > 0 THEN LEAST(1, rec.dmg / r.total_damage) ELSE 0 END;
      v_rank := rec.rnk::int;
      v_coins := cc.raid_participation
               + CASE WHEN r.status = 'DEFEATED' THEN cc.raid_defeat ELSE 0 END
               + COALESCE(cc.raid_top_bonus[v_rank], 0);
      v_reward := jsonb_build_object(
        'fc', floor(COALESCE((snap->>'fcPool')::numeric, 0) * v_share),
        'coins', v_coins);
      INSERT INTO public.clan_raid_rewards(raid_id, clan_id, user_id, damage, payload)
      VALUES (r.id, r.clan_id, rec.user_id, rec.dmg, v_reward)
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.clan_boss_deliver(rec.user_id, v_reward - 'coins');
        PERFORM public.clan_coin_award(rec.user_id, 'CLAN_RAID', r.id::text, v_coins);
        IF COALESCE((snap->>'clanXp')::int, 0) > 0 THEN
          PERFORM public.grant_clan_xp(rec.user_id, 'clan_raid', (snap->>'clanXp')::int);
        END IF;
        v_paid := v_paid + 1;
      END IF;
    END LOOP;
  END IF;

  UPDATE public.clan_raid_cycles SET status = 'SETTLED', settled_at = now() WHERE id = r.id;
  RETURN jsonb_build_object('status','settled','rewarded', v_paid);
END $$;

DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'clan_coin_cfg()',
    'clan_coin_award(uuid,text,text,bigint)',
    'clan_shop_effective_active(uuid)',
    'clan_shop_cycle_ensure(uuid)',
    'clan_shop_purchase(bigint,text,integer,text)',
    'clan_shop_buy(bigint,text,integer)',
    'clan_shop_state(bigint)',
    'clan_award_contribution(uuid,bigint,text,text,bigint)',
    'clan_contribution_from_personal_boss(uuid,uuid)',
    'clan_milestone_claim(bigint,integer)',
    'clan_raid_settle(uuid)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role', fn);
  END LOOP;
END $$;