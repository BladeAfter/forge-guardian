CREATE OR REPLACE FUNCTION public.admin_adjust_player_item(p_admin_id bigint, p_ref text, p_item_key text, p_delta integer, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid; v_before integer := 0; v_after integer := 0; v_key text := btrim(COALESCE(p_item_key,''));
  v_parts text[]; v_label text := v_key; v_rows integer;
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
    UPDATE public.player_pet_inventory SET quantity = v_after, updated_at = now()
     WHERE user_id = v_uid AND item_type = 'egg' AND item_id = v_parts[2]::uuid;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
      INSERT INTO public.player_pet_inventory (user_id, item_type, item_id, quantity, updated_at)
      VALUES (v_uid, 'egg', v_parts[2]::uuid, v_after, now());
    END IF;
    v_label := 'Ovo · '||v_label;
  ELSE
    RAISE EXCEPTION 'item_not_found';
  END IF;

  PERFORM public.admin_log(p_admin_id, CASE WHEN p_delta > 0 THEN 'item.add' ELSE 'item.remove' END, 'player', v_uid::text,
    jsonb_build_object('item', v_key, 'quantity', v_before), jsonb_build_object('item', v_key, 'quantity', v_after), p_reason,
    jsonb_build_object('delta', p_delta));
  RETURN jsonb_build_object('user_id', v_uid, 'key', v_key, 'label', v_label, 'before', v_before, 'after', v_after);
END; $$;