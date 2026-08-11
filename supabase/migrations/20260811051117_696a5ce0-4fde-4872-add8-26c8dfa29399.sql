-- ===================== 1. CLAN CREATION SETTINGS =====================
INSERT INTO public.game_settings(key, value, category, label)
SELECT 'clan_create_cost_fc', to_jsonb(100000::numeric), 'clans', 'Custo em FC para criar um clã (apenas novas criações)'
WHERE NOT EXISTS (SELECT 1 FROM public.game_settings WHERE key = 'clan_create_cost_fc');

INSERT INTO public.game_settings(key, value, category, label)
SELECT 'clan_default_member_limit', to_jsonb(20::int), 'clans', 'Limite de membros aplicado a clãs recém-criados'
WHERE NOT EXISTS (SELECT 1 FROM public.game_settings WHERE key = 'clan_default_member_limit');

-- create_clan: default member limit now comes from settings (never changes existing clans)
CREATE OR REPLACE FUNCTION public.create_clan(p_telegram_id bigint, p_name text, p_tag text, p_description text,
  p_join_type text, p_min_trophies integer, p_emblem jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_cost numeric; v_bal numeric; c public.clans%rowtype; v_name text; v_tag text; v_limit integer;
BEGIN
  v_uid := public.clan_resolve_user(p_telegram_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('clan:'||v_uid::text, 0));
  IF EXISTS (SELECT 1 FROM public.clan_members WHERE user_id = v_uid) THEN RAISE EXCEPTION 'ALREADY_IN_CLAN'; END IF;
  v_name := btrim(COALESCE(p_name,''));
  v_tag := upper(btrim(COALESCE(p_tag,'')));
  IF length(v_name) < 3 OR length(v_name) > 24 THEN RAISE EXCEPTION 'INVALID_CLAN_NAME'; END IF;
  IF v_tag !~ '^[A-Z0-9]{2,5}$' THEN RAISE EXCEPTION 'INVALID_CLAN_TAG'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE lower(name) = lower(v_name)) THEN RAISE EXCEPTION 'CLAN_NAME_TAKEN'; END IF;
  IF EXISTS (SELECT 1 FROM public.clans WHERE upper(tag) = v_tag) THEN RAISE EXCEPTION 'CLAN_TAG_TAKEN'; END IF;
  IF COALESCE(p_join_type,'open') NOT IN ('open','approval','closed') THEN RAISE EXCEPTION 'INVALID_JOIN_TYPE'; END IF;

  v_cost := COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000);
  v_limit := GREATEST(2, COALESCE((SELECT value::text::int FROM public.game_settings WHERE key='clan_default_member_limit'), public.clan_member_limit(1)));
  SELECT forge_coins INTO v_bal FROM public.game_players WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_bal,0) < v_cost THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;

  INSERT INTO public.clans(name, tag, description, leader_user_id, join_type, minimum_trophies, member_limit, emblem_config)
  VALUES (v_name, v_tag, COALESCE(btrim(p_description),''), v_uid, COALESCE(p_join_type,'open'), GREATEST(0, COALESCE(p_min_trophies,0)),
          v_limit, COALESCE(p_emblem, '{}'::jsonb))
  RETURNING * INTO c;

  INSERT INTO public.clan_members(clan_id, user_id, role) VALUES (c.id, v_uid, 'leader');

  UPDATE public.game_players SET forge_coins = forge_coins - v_cost, updated_at = now() WHERE id = v_uid;
  INSERT INTO public.wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id, metadata)
  VALUES (v_uid, 'clan_create', -v_cost, v_bal, v_bal - v_cost, 'clan:'||c.id::text, jsonb_build_object('clanId', c.id, 'name', c.name));

  INSERT INTO public.clan_boss_cycles(clan_id) VALUES (c.id);
  RETURN jsonb_build_object('status','created','clan', public.clan_public(c));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_clan_settings(p_admin_id bigint, p_action text DEFAULT 'get', p_value numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cost numeric; v_limit integer; v_old numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF lower(COALESCE(p_action,'get')) = 'set_cost' THEN
    IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
    v_old := COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000);
    INSERT INTO public.game_settings(key, value, category, label)
    VALUES ('clan_create_cost_fc', to_jsonb(round(p_value)), 'clans', 'Custo em FC para criar um clã (apenas novas criações)')
    ON CONFLICT (key) DO UPDATE SET value = to_jsonb(round(p_value)), updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'clans.settings.create_cost', 'clans', NULL,
      jsonb_build_object('cost', v_old), jsonb_build_object('cost', round(p_value)), 'clan creation cost change (admin bot)', '{}'::jsonb);
  ELSIF lower(COALESCE(p_action,'get')) = 'set_limit' THEN
    IF p_value IS NULL OR p_value < 2 OR p_value > 500 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
    v_old := COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_default_member_limit'), 20);
    INSERT INTO public.game_settings(key, value, category, label)
    VALUES ('clan_default_member_limit', to_jsonb(round(p_value)::int), 'clans', 'Limite de membros aplicado a clãs recém-criados')
    ON CONFLICT (key) DO UPDATE SET value = to_jsonb(round(p_value)::int), updated_at = now();
    PERFORM public.admin_log(p_admin_id, 'clans.settings.member_limit', 'clans', NULL,
      jsonb_build_object('memberLimit', v_old), jsonb_build_object('memberLimit', round(p_value)), 'clan default member limit change (admin bot)', '{}'::jsonb);
  END IF;

  v_cost := COALESCE((SELECT value::text::numeric FROM public.game_settings WHERE key='clan_create_cost_fc'), 100000);
  v_limit := COALESCE((SELECT value::text::int FROM public.game_settings WHERE key='clan_default_member_limit'), 20);
  RETURN jsonb_build_object('createCostFc', v_cost, 'defaultMemberLimit', v_limit,
    'clans', (SELECT count(*) FROM public.clans));
END; $$;

-- ===================== 2. ADMIN GIFT CENTER =====================
CREATE TABLE IF NOT EXISTS public.admin_gifts (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  gift_code text NOT NULL UNIQUE,
  admin_id bigint NOT NULL,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  telegram_id bigint,
  gift_type text NOT NULL,
  item_key text,
  item_label text,
  quantity integer NOT NULL DEFAULT 1,
  fc_amount numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'delivered',
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.admin_gifts TO service_role;
ALTER TABLE public.admin_gifts ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_admin_gifts_created ON public.admin_gifts (created_at DESC);

CREATE OR REPLACE FUNCTION public.admin_gift_catalog(p_admin_id bigint, p_kind text, p_rarity text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_kind text := lower(COALESCE(p_kind,'')); v_items jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_kind = 'hero' THEN
    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'label'), '[]'::jsonb) INTO v_items FROM (
      SELECT jsonb_build_object('key', hero_key, 'label', name, 'sub', public.normalize_hero_rarity(rarity)) AS x
      FROM public.hero_catalog
      WHERE p_rarity IS NULL OR public.normalize_hero_rarity(rarity) = public.normalize_hero_rarity(p_rarity)
    ) s;
  ELSIF v_kind = 'egg' THEN
    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'label'), '[]'::jsonb) INTO v_items FROM (
      SELECT jsonb_build_object('key', 'egg:'||id::text, 'label', name, 'sub', COALESCE(availability_label,'')) AS x
      FROM public.pet_eggs WHERE is_enabled
    ) s;
  ELSIF v_kind = 'chest' THEN
    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'label'), '[]'::jsonb) INTO v_items FROM (
      SELECT jsonb_build_object('key', 'inv:hero_chest:'||chest_code, 'label', name, 'sub', COALESCE(subtitle,'')) AS x
      FROM public.chest_reward_tables WHERE enabled
    ) s;
  ELSIF v_kind = 'pet' THEN
    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'label'), '[]'::jsonb) INTO v_items FROM (
      SELECT jsonb_build_object('key', slug, 'label', name, 'sub', COALESCE(category, species, '')) AS x
      FROM public.pets WHERE is_enabled
    ) s;
  ELSIF v_kind = 'item' THEN
    v_items := jsonb_build_array(
      jsonb_build_object('key','pvp_tickets','label','Tickets PvP','sub','pvp'),
      jsonb_build_object('key','inv:fragments:fragments','label','Fragmentos Universais','sub','fusão')
    ) || COALESCE((SELECT jsonb_agg(jsonb_build_object('key','pet_food:'||code,'label',name,'sub','pet food') ORDER BY name)
        FROM public.pet_food_items), '[]'::jsonb);
  ELSE
    v_items := '[]'::jsonb;
  END IF;
  RETURN jsonb_build_object('kind', v_kind, 'items', v_items);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_send_gift(p_admin_id bigint, p_ref text, p_type text,
  p_item_key text, p_quantity integer, p_gift_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid; v_tg bigint; v_type text := lower(COALESCE(p_type,'')); v_qty integer := GREATEST(1, COALESCE(p_quantity,1));
  v_code text := btrim(COALESCE(p_gift_code,'')); v_label text; v_res jsonb := '{}'::jsonb; v_fc numeric := 0;
  v_existing public.admin_gifts; i integer; r jsonb; v_ids jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_code = '' THEN RAISE EXCEPTION 'invalid_gift_code'; END IF;
  IF v_type NOT IN ('fc','hero','pet','egg','chest','item') THEN RAISE EXCEPTION 'invalid_gift_type'; END IF;
  IF v_qty < 1 OR v_qty > 100 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('admin_gift:'||v_code, 7));
  SELECT * INTO v_existing FROM public.admin_gifts WHERE gift_code = v_code;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('duplicate', true, 'giftCode', v_code, 'status', v_existing.status,
      'label', v_existing.item_label, 'quantity', v_existing.quantity, 'fc', v_existing.fc_amount);
  END IF;

  v_uid := public.admin_resolve_player(p_ref);
  SELECT telegram_id INTO v_tg FROM public.game_players WHERE id = v_uid;

  IF v_type = 'fc' THEN
    v_fc := GREATEST(0, COALESCE(p_item_key,'0')::numeric);
    IF v_fc <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
    v_res := public.admin_adjust_balance(p_admin_id, v_uid::text, 'fc', 'add', v_fc, 'presente administrativo '||v_code);
    v_label := to_char(v_fc, 'FM999999999999') || ' FC';
    v_qty := 1;
  ELSIF v_type = 'hero' THEN
    FOR i IN 1..v_qty LOOP
      r := public.admin_grant_hero(p_admin_id, v_uid::text, p_item_key, 1, 'presente administrativo '||v_code);
      v_ids := v_ids || jsonb_build_array(r->>'hero_id');
      v_label := r->>'name';
    END LOOP;
    v_res := jsonb_build_object('heroes', v_ids);
  ELSIF v_type = 'pet' THEN
    FOR i IN 1..v_qty LOOP
      r := public.admin_grant_pet(p_admin_id, v_uid::text, p_item_key, 'raro', 1, 'presente administrativo '||v_code);
      v_ids := v_ids || jsonb_build_array(r->>'player_pet_id');
      v_label := r->>'pet';
    END LOOP;
    v_res := jsonb_build_object('pets', v_ids);
  ELSE
    v_res := public.admin_adjust_player_item(p_admin_id, v_uid::text, p_item_key, v_qty, 'presente administrativo '||v_code);
    v_label := v_res->>'label';
  END IF;

  INSERT INTO public.admin_gifts(gift_code, admin_id, user_id, telegram_id, gift_type, item_key, item_label, quantity, fc_amount, status, result)
  VALUES (v_code, p_admin_id, v_uid, v_tg, v_type, CASE WHEN v_type='fc' THEN NULL ELSE p_item_key END,
          COALESCE(v_label, p_item_key), v_qty, v_fc, 'delivered', COALESCE(v_res,'{}'::jsonb));

  PERFORM public.admin_log(p_admin_id, 'gift.send', 'player', v_uid::text, NULL,
    jsonb_build_object('giftCode', v_code, 'type', v_type, 'item', p_item_key, 'quantity', v_qty, 'fc', v_fc),
    'presente administrativo', jsonb_build_object('gift', true));

  RETURN jsonb_build_object('duplicate', false, 'giftCode', v_code, 'status', 'delivered', 'type', v_type,
    'userId', v_uid, 'telegramId', v_tg, 'label', COALESCE(v_label, p_item_key), 'quantity', v_qty, 'fc', v_fc,
    'result', v_res);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_gift_history(p_admin_id bigint, p_limit integer DEFAULT 15)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object(
    'total', (SELECT count(*) FROM public.admin_gifts),
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'giftCode', g.gift_code, 'adminId', g.admin_id, 'type', g.gift_type,
        'label', g.item_label, 'itemKey', g.item_key, 'quantity', g.quantity, 'fc', g.fc_amount,
        'status', g.status, 'createdAt', g.created_at,
        'telegramId', g.telegram_id,
        'player', COALESCE(p.username, p.display_name, p.first_name, 'Player')
      ) ORDER BY g.created_at DESC)
      FROM (SELECT * FROM public.admin_gifts ORDER BY created_at DESC LIMIT GREATEST(1, COALESCE(p_limit,15))) g
      LEFT JOIN public.game_players p ON p.id = g.user_id), '[]'::jsonb));
END; $$;