-- 1) Balance adjustments must always leave a ledger trail
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(p_admin_id bigint, p_ref text, p_currency text, p_mode text, p_amount numeric, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_old numeric; v_new numeric; v_cur text := lower(COALESCE(p_currency,'fc')); v_mode text := lower(COALESCE(p_mode,'add'));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF v_cur NOT IN ('fc','ton') THEN RAISE EXCEPTION 'invalid_currency'; END IF;
  IF v_mode NOT IN ('add','remove','set') THEN RAISE EXCEPTION 'invalid_mode'; END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  v_uid := public.admin_resolve_player(p_ref);

  IF v_cur = 'fc' THEN
    SELECT forge_coins INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    v_new := CASE v_mode WHEN 'add' THEN v_old + p_amount WHEN 'remove' THEN GREATEST(0, v_old - p_amount) ELSE p_amount END;
    UPDATE public.game_players SET forge_coins = v_new, updated_at = now() WHERE id = v_uid;
    INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
    VALUES (v_uid, 'admin_balance_adjustment', v_new - v_old, v_old, v_new, 'admin:'||p_admin_id);
  ELSE
    SELECT ton_balance INTO v_old FROM public.game_players WHERE id = v_uid FOR UPDATE;
    v_new := CASE v_mode WHEN 'add' THEN v_old + p_amount WHEN 'remove' THEN GREATEST(0, v_old - p_amount) ELSE p_amount END;
    UPDATE public.game_players SET ton_balance = v_new, updated_at = now() WHERE id = v_uid;
    INSERT INTO public.wallet_ledger (user_id, type, amount_ton, balance_before, balance_after, reference_id)
    VALUES (v_uid, 'admin_balance_adjustment', v_new - v_old, v_old, v_new, 'admin:'||p_admin_id);
  END IF;

  PERFORM public.admin_log(p_admin_id, 'balance.'||v_cur||'.'||v_mode, 'player', v_uid::text,
    jsonb_build_object(v_cur, v_old), jsonb_build_object(v_cur, v_new), p_reason,
    jsonb_build_object('amount', p_amount, 'financial', true));
  RETURN jsonb_build_object('user_id', v_uid, 'currency', v_cur, 'old_value', v_old, 'new_value', v_new);
END; $$;

-- 2) Pet history must survive pet removal
ALTER TABLE public.pet_upgrade_history ALTER COLUMN player_pet_id DROP NOT NULL;
ALTER TABLE public.pet_evolution_history ALTER COLUMN player_pet_id DROP NOT NULL;
ALTER TABLE public.pet_upgrade_history DROP CONSTRAINT IF EXISTS pet_upgrade_history_player_pet_id_fkey;
ALTER TABLE public.pet_upgrade_history ADD CONSTRAINT pet_upgrade_history_player_pet_id_fkey
  FOREIGN KEY (player_pet_id) REFERENCES public.player_pets(id) ON DELETE SET NULL;
ALTER TABLE public.pet_evolution_history DROP CONSTRAINT IF EXISTS pet_evolution_history_player_pet_id_fkey;
ALTER TABLE public.pet_evolution_history ADD CONSTRAINT pet_evolution_history_player_pet_id_fkey
  FOREIGN KEY (player_pet_id) REFERENCES public.player_pets(id) ON DELETE SET NULL;
ALTER TABLE public.pet_action_idempotency DROP CONSTRAINT IF EXISTS pet_action_idempotency_player_pet_id_fkey;
ALTER TABLE public.pet_action_idempotency ADD CONSTRAINT pet_action_idempotency_player_pet_id_fkey
  FOREIGN KEY (player_pet_id) REFERENCES public.player_pets(id) ON DELETE CASCADE;

-- 3) Player hero list for the admin bot
CREATE OR REPLACE FUNCTION public.admin_player_heroes(p_admin_id bigint, p_ref text, p_rarity text DEFAULT NULL, p_limit integer DEFAULT 12, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_total integer; v_rows jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT count(*) INTO v_total FROM public.player_heroes h
   WHERE h.user_id = v_uid AND (p_rarity IS NULL OR lower(h.rarity) = lower(p_rarity));
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.rarity, t.name), '[]'::jsonb) INTO v_rows FROM (
    SELECT h.id, h.name, h.hero_key, h.rarity, h.level, COALESCE(h.fusion_level,0) AS fusion_level,
           COALESCE(h.final_atk,0) AS final_atk, COALESCE(h.final_hp,0) AS final_hp,
           EXISTS (SELECT 1 FROM public.pvp_team_slots s WHERE s.hero_id = h.id) AS in_pvp,
           EXISTS (SELECT 1 FROM public.boss_team_slots b WHERE b.player_hero_id = h.id) AS in_boss
      FROM public.player_heroes h
     WHERE h.user_id = v_uid AND (p_rarity IS NULL OR lower(h.rarity) = lower(p_rarity))
     ORDER BY h.rarity, h.name
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit,12), 30)) OFFSET GREATEST(0, COALESCE(p_offset,0))
  ) t;
  RETURN jsonb_build_object('user_id', v_uid, 'total', v_total, 'heroes', v_rows);
END; $$;

-- 4) Safe hero removal (unequip first, keep history)
CREATE OR REPLACE FUNCTION public.admin_remove_player_hero(p_admin_id bigint, p_hero_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE h public.player_heroes;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO h FROM public.player_heroes WHERE id = p_hero_id FOR UPDATE;
  IF h.id IS NULL THEN RAISE EXCEPTION 'hero_not_found'; END IF;
  DELETE FROM public.pvp_team_slots WHERE hero_id = h.id;
  DELETE FROM public.boss_team_slots WHERE player_hero_id = h.id;
  DELETE FROM public.hero_combat_state WHERE hero_id = h.id;
  DELETE FROM public.player_heroes WHERE id = h.id;
  PERFORM public.admin_log(p_admin_id,'hero.remove','player',h.user_id::text,
    jsonb_build_object('hero_id',h.id,'hero_key',h.hero_key,'name',h.name,'rarity',h.rarity,'level',h.level), NULL, p_reason);
  RETURN jsonb_build_object('user_id',h.user_id,'hero_id',h.id,'name',h.name,'rarity',h.rarity);
END; $$;

-- 5) Player pets + active pet control
CREATE OR REPLACE FUNCTION public.admin_player_pets(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_rows jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.is_active DESC, t.name), '[]'::jsonb) INTO v_rows FROM (
    SELECT pp.id, COALESCE(p.name, 'Pet') AS name, p.slug, pp.rarity, pp.level, pp.xp,
           COALESCE(pp.evolution_tier,1) AS evolution_tier, pp.evolution_stage, COALESCE(pp.is_active,false) AS is_active
      FROM public.player_pets pp
      LEFT JOIN public.pets p ON p.id = pp.pet_id
     WHERE pp.user_id = v_uid
  ) t;
  RETURN jsonb_build_object('user_id', v_uid, 'pets', v_rows);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_player_active_pet(p_admin_id bigint, p_player_pet_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE pp public.player_pets;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO pp FROM public.player_pets WHERE id = p_player_pet_id FOR UPDATE;
  IF pp.id IS NULL THEN RAISE EXCEPTION 'pet_not_found'; END IF;
  UPDATE public.player_pets SET is_active = (id = pp.id), updated_at = now() WHERE user_id = pp.user_id;
  PERFORM public.admin_log(p_admin_id,'pet.activate','player',pp.user_id::text,NULL,
    jsonb_build_object('player_pet_id',pp.id), p_reason);
  RETURN jsonb_build_object('user_id',pp.user_id,'player_pet_id',pp.id);
END; $$;

-- 6) Item inventory (real internal keys)
CREATE OR REPLACE FUNCTION public.admin_player_items(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_items jsonb; v_catalog jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);

  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.label), '[]'::jsonb) INTO v_items FROM (
    SELECT 'pvp_tickets'::text AS key, 'Tickets PvP'::text AS label, COALESCE(gp.pvp_tickets,0)::int AS quantity
      FROM public.game_players gp WHERE gp.id = v_uid
    UNION ALL
    SELECT 'pet_food:'||f.food_code, COALESCE(fi.name, f.food_code), f.quantity::int
      FROM public.player_pet_food f LEFT JOIN public.pet_food_items fi ON fi.code = f.food_code
     WHERE f.user_id = v_uid AND f.quantity > 0
    UNION ALL
    SELECT 'inv:'||i.item_type||':'||i.item_code, i.item_type||' · '||i.item_code, i.quantity::int
      FROM public.player_inventory i WHERE i.user_id = v_uid AND i.quantity > 0
    UNION ALL
    SELECT 'egg:'||pi.item_id::text, COALESCE(e.name,'Ovo'), pi.quantity::int
      FROM public.player_pet_inventory pi LEFT JOIN public.pet_eggs e ON e.id = pi.item_id
     WHERE pi.user_id = v_uid AND pi.item_type = 'egg' AND pi.quantity > 0
    UNION ALL
    SELECT 'pet_fragments', 'Fragmentos de Pet', COALESCE(SUM(pp.fragments),0)::int
      FROM public.player_pets pp WHERE pp.user_id = v_uid
  ) t;

  SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.sort, c.label), '[]'::jsonb) INTO v_catalog FROM (
    SELECT 1 AS sort, 'pvp_tickets'::text AS key, 'Tickets PvP'::text AS label
    UNION ALL SELECT 2, 'pet_food:'||code, name FROM public.pet_food_items WHERE enabled
    UNION ALL SELECT 3, 'inv:fragments:fragments', 'Fragmentos Universais'
    UNION ALL SELECT 4, 'inv:hero_chest:common_hero_chest', 'Baú Common'
    UNION ALL SELECT 4, 'inv:hero_chest:rare_chest', 'Baú Rare'
    UNION ALL SELECT 5, 'egg:'||id::text, 'Ovo · '||name FROM public.pet_eggs WHERE is_enabled
  ) c;

  RETURN jsonb_build_object('user_id', v_uid, 'items', v_items, 'catalog', v_catalog);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_adjust_player_item(p_admin_id bigint, p_ref text, p_item_key text, p_delta integer, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid; v_before integer := 0; v_after integer := 0; v_key text := btrim(COALESCE(p_item_key,''));
  v_parts text[]; v_label text := v_key;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_delta IS NULL OR p_delta = 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;
  v_uid := public.admin_resolve_player(p_ref);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_uid::text || v_key, 42));
  v_parts := string_to_array(v_key, ':');

  IF v_key = 'pvp_tickets' THEN
    SELECT COALESCE(pvp_tickets,0) INTO v_before FROM public.game_players WHERE id = v_uid FOR UPDATE;
    v_after := v_before + p_delta;
    IF v_after < 0 THEN RAISE EXCEPTION 'insufficient_inventory:%', v_before; END IF;
    UPDATE public.game_players SET pvp_tickets = v_after, updated_at = now() WHERE id = v_uid;
    v_label := 'Tickets PvP';

  ELSIF v_parts[1] = 'pet_food' THEN
    SELECT name INTO v_label FROM public.pet_food_items WHERE code = v_parts[2];
    IF v_label IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;
    SELECT COALESCE(quantity,0) INTO v_before FROM public.player_pet_food WHERE user_id = v_uid AND food_code = v_parts[2] FOR UPDATE;
    v_before := COALESCE(v_before,0); v_after := v_before + p_delta;
    IF v_after < 0 THEN RAISE EXCEPTION 'insufficient_inventory:%', v_before; END IF;
    INSERT INTO public.player_pet_food (user_id, food_code, quantity, updated_at)
    VALUES (v_uid, v_parts[2], v_after, now())
    ON CONFLICT (user_id, food_code) DO UPDATE SET quantity = v_after, updated_at = now();

  ELSIF v_parts[1] = 'inv' THEN
    IF v_parts[2] IS NULL OR v_parts[3] IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;
    SELECT COALESCE(quantity,0) INTO v_before FROM public.player_inventory
     WHERE user_id = v_uid AND item_type = v_parts[2] AND item_code = v_parts[3] FOR UPDATE;
    v_before := COALESCE(v_before,0); v_after := v_before + p_delta;
    IF v_after < 0 THEN RAISE EXCEPTION 'insufficient_inventory:%', v_before; END IF;
    INSERT INTO public.player_inventory (user_id, item_type, item_code, quantity, updated_at)
    VALUES (v_uid, v_parts[2], v_parts[3], v_after, now())
    ON CONFLICT (user_id, item_type, item_code) DO UPDATE SET quantity = v_after, updated_at = now();
    v_label := v_parts[2]||' · '||v_parts[3];

  ELSIF v_parts[1] = 'egg' THEN
    SELECT name INTO v_label FROM public.pet_eggs WHERE id = v_parts[2]::uuid;
    IF v_label IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;
    SELECT COALESCE(quantity,0) INTO v_before FROM public.player_pet_inventory
     WHERE user_id = v_uid AND item_type = 'egg' AND item_id = v_parts[2]::uuid FOR UPDATE;
    v_before := COALESCE(v_before,0); v_after := v_before + p_delta;
    IF v_after < 0 THEN RAISE EXCEPTION 'insufficient_inventory:%', v_before; END IF;
    INSERT INTO public.player_pet_inventory (user_id, item_type, item_id, quantity, updated_at)
    VALUES (v_uid, 'egg', v_parts[2]::uuid, v_after, now())
    ON CONFLICT (user_id, item_type, item_id) DO UPDATE SET quantity = v_after, updated_at = now();
    v_label := 'Ovo · '||v_label;
  ELSE
    RAISE EXCEPTION 'item_not_found';
  END IF;

  PERFORM public.admin_log(p_admin_id, CASE WHEN p_delta > 0 THEN 'item.add' ELSE 'item.remove' END, 'player', v_uid::text,
    jsonb_build_object('item', v_key, 'quantity', v_before), jsonb_build_object('item', v_key, 'quantity', v_after), p_reason,
    jsonb_build_object('delta', p_delta));
  RETURN jsonb_build_object('user_id', v_uid, 'key', v_key, 'label', v_label, 'before', v_before, 'after', v_after);
END; $$;