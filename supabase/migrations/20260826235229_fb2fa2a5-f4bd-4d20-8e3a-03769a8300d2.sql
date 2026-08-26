CREATE OR REPLACE FUNCTION public.pet_egg_move_from_inventory(p_user_id uuid, p_egg_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_slug text; v_row public.player_inventory;
BEGIN
  SELECT slug INTO v_slug FROM pet_eggs WHERE id = p_egg_id;
  IF v_slug IS NULL THEN RETURN false; END IF;
  SELECT * INTO v_row FROM player_inventory
   WHERE user_id = p_user_id AND item_type = 'pet_egg'
     AND lower(replace(item_code,'_','-')) = lower(replace(v_slug,'_','-'))
     AND quantity > 0
   ORDER BY quantity DESC LIMIT 1 FOR UPDATE;
  IF v_row.id IS NULL THEN RETURN false; END IF;
  UPDATE player_inventory SET quantity = quantity - 1, updated_at = now() WHERE id = v_row.id;
  DELETE FROM player_inventory WHERE id = v_row.id AND quantity <= 0;
  INSERT INTO player_pet_inventory (user_id, item_type, item_id, quantity)
  VALUES (p_user_id, 'egg', p_egg_id, 1)
  ON CONFLICT (user_id, item_type, item_id) DO UPDATE SET quantity = player_pet_inventory.quantity + 1;
  RETURN true;
END $function$;

REVOKE ALL ON FUNCTION public.pet_egg_move_from_inventory(uuid, uuid) FROM anon, authenticated;