-- 💫 CELESTIAL MYSTERY PACK — popup diário server-side + oferta permanente em OFERTAS PREMIUM.
-- Founder Pack e Veteran Vault permanecem intocados (preço, recompensa e fluxo).

ALTER TABLE public.celestial_pack_config
  ADD COLUMN IF NOT EXISTS popup_priority integer NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS start_at timestamptz,
  ADD COLUMN IF NOT EXISTS ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS stock_total integer,
  ADD COLUMN IF NOT EXISTS purchase_limit integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS sold_out_visible boolean NOT NULL DEFAULT true;

UPDATE public.celestial_pack_config
   SET popup_enabled = true,
       popup_frequency = 'DAILY',
       updated_at = now()
 WHERE id;

ALTER TABLE public.founder_pack_config ADD COLUMN IF NOT EXISTS popup_priority integer NOT NULL DEFAULT 50;
ALTER TABLE public.veteran_vault_v2_config ADD COLUMN IF NOT EXISTS popup_priority integer NOT NULL DEFAULT 40;

-- Impressões diárias por conta (nunca por dispositivo): a UNIQUE garante 1 popup por dia.
CREATE TABLE IF NOT EXISTS public.premium_offer_impressions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  offer_id text NOT NULL,
  impression_date date NOT NULL,
  shown_at timestamptz NOT NULL DEFAULT now(),
  dismissed_at timestamptz,
  clicked_at timestamptz,
  purchased_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT premium_offer_impressions_unique_day UNIQUE (user_id, offer_id, impression_date)
);

GRANT ALL ON public.premium_offer_impressions TO service_role;
ALTER TABLE public.premium_offer_impressions ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS premium_offer_impressions_offer_day_idx
  ON public.premium_offer_impressions (offer_id, impression_date);

-- Frequência → intervalo mínimo em dias entre popups da mesma oferta.
CREATE OR REPLACE FUNCTION public.premium_offer_frequency_days(p_frequency text)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE upper(COALESCE(p_frequency,'DAILY'))
           WHEN 'EVERY_2_DAYS' THEN 2
           WHEN 'EVERY_3_DAYS' THEN 3
           WHEN 'ONCE_ONLY' THEN 3650
           ELSE 1
         END
$$;

-- Metadados da oferta Celestial usados pelo popup e pelo card permanente.
CREATE OR REPLACE FUNCTION public.celestial_pack_offer_meta(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.celestial_pack_config; v_heroes integer; v_sold integer; v_mine integer;
        v_pending uuid; v_paid_pending boolean; v_stock integer;
BEGIN
  c := public.celestial_pack_settings();
  SELECT count(*) INTO v_heroes FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key);
  SELECT count(*) INTO v_sold FROM public.celestial_pack_purchases
   WHERE package_version = c.package_version AND status IN ('paid','delivered');
  SELECT count(*) INTO v_mine FROM public.celestial_pack_purchases
   WHERE user_id = p_user_id AND package_version = c.package_version AND status IN ('paid','delivered');
  SELECT id INTO v_pending FROM public.celestial_pack_purchases
   WHERE user_id = p_user_id AND status = 'pending' AND expires_at > now()
   ORDER BY created_at DESC LIMIT 1;
  SELECT EXISTS (SELECT 1 FROM public.celestial_pack_purchases
                  WHERE user_id = p_user_id AND status = 'paid' AND delivered_at IS NULL) INTO v_paid_pending;
  v_stock := LEAST(v_heroes, COALESCE(NULLIF(c.stock_total,0) - v_sold, v_heroes));

  RETURN jsonb_build_object(
    'offerId','CELESTIAL_MYSTERY_PACK',
    'priceTon', c.price_ton,
    'popupEnabled', c.popup_enabled,
    'popupFrequency', c.popup_frequency,
    'popupPriority', c.popup_priority,
    'purchaseLimit', c.purchase_limit,
    'startAt', c.start_at,
    'endsAt', c.ends_at,
    'stockTotal', c.stock_total,
    'stockRemaining', GREATEST(v_stock,0),
    'soldOut', COALESCE(v_stock,0) <= 0,
    'soldOutVisible', c.sold_out_visible,
    'windowOpen', c.enabled AND NOT c.sales_paused
                  AND now() >= COALESCE(c.start_at, now())
                  AND (c.ends_at IS NULL OR now() < c.ends_at),
    'purchasedCount', v_mine,
    'purchased', v_mine >= GREATEST(c.purchase_limit,1),
    'paymentPending', v_pending IS NOT NULL,
    'pendingOrderId', v_pending,
    'processing', v_paid_pending,
    'sold', v_sold);
END $$;

-- ✅ REGRA CANÔNICA de exibição do popup (server-side, uma verdade só).
CREATE OR REPLACE FUNCTION public.should_show_premium_offer_popup(p_user_id uuid, p_offer_id text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; m jsonb; c public.celestial_pack_config;
        v_last date; v_today date := public.premium_offer_day_key();
BEGIN
  SELECT * INTO u FROM public.game_players WHERE id = p_user_id;
  IF u.id IS NULL THEN RETURN 'NOT_ELIGIBLE'; END IF;
  IF COALESCE(u.banned,false) THEN RETURN 'NOT_ELIGIBLE'; END IF;

  IF upper(p_offer_id) <> 'CELESTIAL_MYSTERY_PACK' THEN RETURN 'NOT_ELIGIBLE'; END IF;
  c := public.celestial_pack_settings();
  IF NOT c.enabled OR NOT c.popup_enabled OR upper(c.popup_frequency) = 'DISABLED' THEN RETURN 'INACTIVE'; END IF;

  m := public.celestial_pack_offer_meta(p_user_id);
  IF (m->>'purchased')::boolean OR (m->>'processing')::boolean THEN RETURN 'PURCHASED'; END IF;
  IF NOT (m->>'windowOpen')::boolean THEN RETURN 'INACTIVE'; END IF;
  IF (m->>'soldOut')::boolean THEN RETURN 'INACTIVE'; END IF;

  SELECT max(impression_date) INTO v_last FROM public.premium_offer_impressions
   WHERE user_id = p_user_id AND offer_id = 'CELESTIAL_MYSTERY_PACK';
  IF v_last IS NOT NULL
     AND v_today < v_last + public.premium_offer_frequency_days(c.popup_frequency) THEN
    RETURN 'ALREADY_SHOWN';
  END IF;
  RETURN 'SHOW';
END $$;

-- 🔒 Claim atômico: dois requests simultâneos → só um recebe SHOW.
CREATE OR REPLACE FUNCTION public.claim_daily_offer_impression(p_telegram_id bigint, p_offer_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; v_status text; v_day date := public.premium_offer_day_key(); v_rows integer;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  v_status := public.should_show_premium_offer_popup(v_user, upper(btrim(p_offer_id)));
  IF v_status <> 'SHOW' THEN
    RETURN jsonb_build_object('status', v_status, 'offerId', upper(btrim(p_offer_id)), 'dayKey', v_day);
  END IF;

  INSERT INTO public.premium_offer_impressions(user_id, offer_id, impression_date)
  VALUES (v_user, upper(btrim(p_offer_id)), v_day)
  ON CONFLICT (user_id, offer_id, impression_date) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN jsonb_build_object(
    'status', CASE WHEN v_rows > 0 THEN 'SHOW' ELSE 'ALREADY_SHOWN' END,
    'offerId', upper(btrim(p_offer_id)), 'dayKey', v_day);
END $$;

-- Eventos da impressão do dia (fechar, clicar, comprar) — nunca cria nova impressão.
CREATE OR REPLACE FUNCTION public.premium_offer_impression_event(p_telegram_id bigint, p_offer_id text, p_event text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid; v_day date := public.premium_offer_day_key(); v_event text := lower(btrim(COALESCE(p_event,'')));
BEGIN
  IF v_event NOT IN ('dismissed','clicked','purchased') THEN RAISE EXCEPTION 'INVALID_EVENT'; END IF;
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  UPDATE public.premium_offer_impressions
     SET dismissed_at = CASE WHEN v_event = 'dismissed' THEN COALESCE(dismissed_at, now()) ELSE dismissed_at END,
         clicked_at   = CASE WHEN v_event = 'clicked'   THEN COALESCE(clicked_at, now())   ELSE clicked_at END,
         purchased_at = CASE WHEN v_event = 'purchased' THEN COALESCE(purchased_at, now()) ELSE purchased_at END
   WHERE user_id = v_user AND offer_id = upper(btrim(p_offer_id))
     AND impression_date = (SELECT max(impression_date) FROM public.premium_offer_impressions
                             WHERE user_id = v_user AND offer_id = upper(btrim(p_offer_id)));

  RETURN jsonb_build_object('ok', true, 'offerId', upper(btrim(p_offer_id)), 'event', v_event, 'dayKey', v_day);
END $$;

-- 🎁 Fila de popups com PRIORIDADE (Celestial 100 > Founder 50 > Veteran 40).
CREATE OR REPLACE FUNCTION public.premium_offers_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; fc public.founder_pack_config; vc public.veteran_vault_v2_config;
        cc public.celestial_pack_config;
        f jsonb; v jsonb; cp jsonb; meta jsonb; v_day date := public.premium_offer_day_key();
        v_queue text[] := array[]::text[]; v_f_seen boolean; v_v_seen boolean; v_v_window boolean;
        v_c_status text; v_c_seen boolean;
        v_ranked record;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  fc := public.founder_pack_settings();
  SELECT * INTO vc FROM public.veteran_vault_v2_config WHERE id;
  cc := public.celestial_pack_settings();

  f := public.founder_pack_state(p_telegram_id);
  v := public.veteran_v2_state(p_telegram_id);
  cp := public.celestial_pack_state(p_telegram_id);
  meta := public.celestial_pack_offer_meta(u.id);

  v_v_window := COALESCE(vc.enabled,false)
                AND now() >= COALESCE(vc.start_at, now())
                AND (vc.ends_at IS NULL OR now() < vc.ends_at);

  SELECT EXISTS (SELECT 1 FROM public.premium_offer_popup_views
                  WHERE user_id = u.id AND offer_type = 'FOUNDER_PACK' AND day_key = v_day) INTO v_f_seen;
  SELECT EXISTS (SELECT 1 FROM public.premium_offer_popup_views
                  WHERE user_id = u.id AND offer_type = 'VETERAN_VAULT' AND day_key = v_day) INTO v_v_seen;

  v_c_status := public.should_show_premium_offer_popup(u.id, 'CELESTIAL_MYSTERY_PACK');
  v_c_seen := v_c_status <> 'SHOW';

  -- Ordena por prioridade decrescente; o cliente exibe no máximo 1 popup por sessão.
  FOR v_ranked IN
    SELECT * FROM (
      VALUES
        ('CELESTIAL_MYSTERY_PACK', cc.popup_priority, v_c_status = 'SHOW'),
        ('FOUNDER_PACK', fc.popup_priority,
          COALESCE(fc.popup_enabled,false) AND fc.popup_frequency <> 'DISABLED'
          AND COALESCE((f->>'eligible')::boolean,false) AND NOT v_f_seen),
        ('VETERAN_VAULT', vc.popup_priority,
          COALESCE(vc.popup_enabled,false) AND vc.popup_frequency <> 'DISABLED' AND v_v_window
          AND COALESCE((v->>'eligible')::boolean,false) AND NOT v_v_seen)
    ) AS t(offer, priority, ok)
    WHERE t.ok ORDER BY t.priority DESC, t.offer
  LOOP
    v_queue := array_append(v_queue, v_ranked.offer);
  END LOOP;

  RETURN jsonb_build_object(
    'dayKey', v_day,
    'timezone', public.premium_offer_timezone(),
    'queue', to_jsonb(v_queue),
    'founder', f || jsonb_build_object('popupSeenToday', v_f_seen, 'popupFrequency', fc.popup_frequency,
                                       'popupPriority', fc.popup_priority),
    'veteran', v || jsonb_build_object('popupSeenToday', v_v_seen, 'popupFrequency', vc.popup_frequency,
                                       'startAt', vc.start_at, 'endsAt', vc.ends_at,
                                       'popupPriority', vc.popup_priority,
                                       'windowOpen', v_v_window),
    'celestial', cp || meta || jsonb_build_object('popupSeenToday', v_c_seen, 'popupStatus', v_c_status));
END $$;

-- 📊 Métricas reais do popup (sem analytics fake).
CREATE OR REPLACE FUNCTION public.admin_premium_offer_metrics(p_admin_id bigint, p_offer_id text DEFAULT 'CELESTIAL_MYSTERY_PACK')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb; v_offer text := upper(btrim(COALESCE(p_offer_id,'CELESTIAL_MYSTERY_PACK')));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
      'offerId', v_offer,
      'impressions', count(*),
      'uniquePlayers', count(DISTINCT user_id),
      'dismissed', count(*) FILTER (WHERE dismissed_at IS NOT NULL),
      'clicked', count(*) FILTER (WHERE clicked_at IS NOT NULL),
      'purchaseIntents', count(*) FILTER (WHERE purchased_at IS NOT NULL),
      'today', count(*) FILTER (WHERE impression_date = public.premium_offer_day_key()))
    INTO v FROM public.premium_offer_impressions WHERE offer_id = v_offer;

  RETURN COALESCE(v,'{}'::jsonb) || jsonb_build_object(
    'confirmedPurchases', (SELECT count(*) FROM public.celestial_pack_purchases WHERE status IN ('paid','delivered')),
    'tonCollected', (SELECT COALESCE(round(SUM(price_ton),9),0) FROM public.celestial_pack_purchases WHERE status IN ('paid','delivered')));
END $$;

-- Admin Bot: novos campos configuráveis sem deploy.
CREATE OR REPLACE FUNCTION public.admin_celestial_pack_set(p_admin_id bigint, p_field text, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_num numeric; v_bool boolean; v_ts timestamptz;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_field IN ('enabled','sales_paused','popup_enabled','sold_out_visible') THEN
    v_bool := lower(COALESCE(p_value,'')) IN ('1','true','on','yes');
    IF p_field = 'enabled' THEN UPDATE public.celestial_pack_config SET enabled = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'sales_paused' THEN UPDATE public.celestial_pack_config SET sales_paused = v_bool, updated_at = now() WHERE id;
    ELSIF p_field = 'sold_out_visible' THEN UPDATE public.celestial_pack_config SET sold_out_visible = v_bool, updated_at = now() WHERE id;
    ELSE UPDATE public.celestial_pack_config SET popup_enabled = v_bool, updated_at = now() WHERE id; END IF;
  ELSIF p_field IN ('price_ton','fc_reward','legendary_chests','nft_weapons','armors','random_items','account_ton_bonus_percent','popup_priority','purchase_limit','stock_total') THEN
    v_num := COALESCE(p_value,'')::numeric;
    IF v_num < 0 THEN RAISE EXCEPTION 'INVALID_VALUE'; END IF;
    IF p_field = 'price_ton' THEN UPDATE public.celestial_pack_config SET price_ton = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'fc_reward' THEN UPDATE public.celestial_pack_config SET fc_reward = v_num, updated_at = now() WHERE id;
    ELSIF p_field = 'legendary_chests' THEN UPDATE public.celestial_pack_config SET legendary_chests = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'nft_weapons' THEN UPDATE public.celestial_pack_config SET nft_weapons = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'armors' THEN UPDATE public.celestial_pack_config SET armors = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'random_items' THEN UPDATE public.celestial_pack_config SET random_items = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'popup_priority' THEN UPDATE public.celestial_pack_config SET popup_priority = v_num::int, updated_at = now() WHERE id;
    ELSIF p_field = 'purchase_limit' THEN UPDATE public.celestial_pack_config SET purchase_limit = GREATEST(v_num::int,1), updated_at = now() WHERE id;
    ELSIF p_field = 'stock_total' THEN UPDATE public.celestial_pack_config SET stock_total = NULLIF(v_num::int,0), updated_at = now() WHERE id;
    ELSE UPDATE public.celestial_pack_config SET account_ton_bonus_percent = v_num, updated_at = now() WHERE id; END IF;
  ELSIF p_field = 'popup_frequency' THEN
    IF upper(btrim(COALESCE(p_value,''))) NOT IN ('DISABLED','DAILY','EVERY_2_DAYS','EVERY_3_DAYS','ONCE_ONLY') THEN
      RAISE EXCEPTION 'INVALID_VALUE';
    END IF;
    UPDATE public.celestial_pack_config SET popup_frequency = upper(btrim(p_value)), updated_at = now() WHERE id;
  ELSIF p_field IN ('start_at','ends_at') THEN
    v_ts := CASE WHEN COALESCE(btrim(p_value),'') IN ('','-','null','NULL') THEN NULL ELSE p_value::timestamptz END;
    IF p_field = 'start_at' THEN UPDATE public.celestial_pack_config SET start_at = v_ts, updated_at = now() WHERE id;
    ELSE UPDATE public.celestial_pack_config SET ends_at = v_ts, updated_at = now() WHERE id; END IF;
  ELSE
    RAISE EXCEPTION 'UNKNOWN_FIELD';
  END IF;
  PERFORM public.admin_log(p_admin_id,'celestial_pack.set','config',p_field,null,jsonb_build_object('value',p_value),null);
  RETURN public.admin_celestial_pack_overview(p_admin_id);
END $$;

-- Overview do bot com métricas e janela/estoque.
CREATE OR REPLACE FUNCTION public.admin_celestial_pack_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.celestial_pack_config; v_sold integer; v_ton numeric; v_heroes integer;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  c := public.celestial_pack_settings();
  SELECT count(*), COALESCE(SUM(price_ton),0) INTO v_sold, v_ton
    FROM public.celestial_pack_purchases WHERE status IN ('paid','delivered');
  SELECT count(*) INTO v_heroes FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key);
  RETURN jsonb_build_object(
    'config', to_jsonb(c), 'sold', v_sold, 'tonCollected', round(v_ton,9), 'celestialAvailable', v_heroes,
    'metrics', public.admin_premium_offer_metrics(p_admin_id,'CELESTIAL_MYSTERY_PACK'),
    'purchases', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'player', COALESCE(g.username, g.name), 'telegramId', g.telegram_id, 'status', p.status,
        'priceTon', p.price_ton, 'createdAt', p.created_at, 'deliveredAt', p.delivered_at)
        ORDER BY p.created_at DESC)
      FROM public.celestial_pack_purchases p JOIN public.game_players g ON g.id = p.user_id
      WHERE p.status IN ('paid','delivered')), '[]'::jsonb),
    'pendingReveals', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'itemId', i.id, 'userId', i.user_id, 'telegramId', g.telegram_id, 'player', COALESCE(g.username, g.name),
        'type', i.item_type, 'template', i.template_id, 'instanceId', i.instance_id, 'createdAt', i.created_at)
        ORDER BY i.created_at)
      FROM public.celestial_pack_items i JOIN public.game_players g ON g.id = i.user_id
      WHERE i.mining_pending_reveal), '[]'::jsonb));
END $$;

-- Janela e estoque também valem para a COMPRA (não só para o popup).
CREATE OR REPLACE FUNCTION public.celestial_pack_purchase_window_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c public.celestial_pack_config; m jsonb;
BEGIN
  c := public.celestial_pack_settings();
  IF now() < COALESCE(c.start_at, now()) OR (c.ends_at IS NOT NULL AND now() >= c.ends_at) THEN
    RAISE EXCEPTION 'CELESTIAL_PACK_OUTSIDE_WINDOW';
  END IF;
  m := public.celestial_pack_offer_meta(NEW.user_id);
  IF (m->>'soldOut')::boolean THEN RAISE EXCEPTION 'CELESTIAL_PACK_SOLD_OUT'; END IF;
  IF (m->>'purchased')::boolean THEN RAISE EXCEPTION 'CELESTIAL_PACK_ALREADY_PURCHASED'; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS celestial_pack_purchase_window_guard_trg ON public.celestial_pack_purchases;
CREATE TRIGGER celestial_pack_purchase_window_guard_trg
BEFORE INSERT ON public.celestial_pack_purchases
FOR EACH ROW EXECUTE FUNCTION public.celestial_pack_purchase_window_guard();