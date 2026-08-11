-- 1. Fix broken trigger: pet_action_idempotency has NO "id" column (PK = idempotency_key)
CREATE OR REPLACE FUNCTION public.quest_hook_pet_feed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.action LIKE 'feed%' THEN
    PERFORM public.record_quest_event(NEW.user_id, 'pet_fed', 1);
    PERFORM public.grant_season_pass_xp(NEW.user_id, 'pet_feed', 'feed:' || NEW.idempotency_key);
  END IF;
  RETURN NEW;
END;
$$;

-- 2. Audit columns for feeding
ALTER TABLE public.pet_upgrade_history
  ADD COLUMN IF NOT EXISTS action text NOT NULL DEFAULT 'upgrade',
  ADD COLUMN IF NOT EXISTS food_code text,
  ADD COLUMN IF NOT EXISTS xp_before integer,
  ADD COLUMN IF NOT EXISTS xp_added integer,
  ADD COLUMN IF NOT EXISTS xp_after integer;

-- 3. Atomic feeding with lock + audit
CREATE OR REPLACE FUNCTION public.feed_pet_item(p_telegram_id bigint, p_player_pet_id uuid, p_food_code text, p_quantity integer, p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE u uuid; pet player_pets%rowtype; food pet_food_items%rowtype; have int; gain int;
        lvl int; v_xp int; need int; gained int := 0; maxlvl int; payload jsonb;
        xp_before int;
BEGIN
  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 100 OR length(coalesce(p_idempotency_key,'')) < 8 THEN
    RAISE EXCEPTION 'INVALID_FEED_REQUEST';
  END IF;
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pet_feed:' || p_player_pet_id::text, 0));

  SELECT result INTO payload FROM pet_action_idempotency WHERE idempotency_key = p_idempotency_key AND user_id = u;
  IF payload IS NOT NULL THEN RETURN payload; END IF;

  SELECT * INTO pet FROM player_pets WHERE id = p_player_pet_id AND user_id = u FOR UPDATE;
  IF pet.id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;
  SELECT * INTO food FROM pet_food_items WHERE code = p_food_code AND enabled;
  IF food.code IS NULL THEN RAISE EXCEPTION 'FOOD_NOT_FOUND'; END IF;
  maxlvl := pet_max_level();
  IF pet.level >= maxlvl THEN RAISE EXCEPTION 'PET_MAX_LEVEL'; END IF;

  SELECT quantity INTO have FROM player_pet_food WHERE user_id = u AND food_code = food.code FOR UPDATE;
  IF coalesce(have,0) < p_quantity THEN RAISE EXCEPTION 'NOT_ENOUGH_PET_FOOD'; END IF;
  UPDATE player_pet_food SET quantity = quantity - p_quantity, updated_at = now()
    WHERE user_id = u AND food_code = food.code;

  gain := food.xp_value * p_quantity;
  xp_before := pet.xp;
  lvl := pet.level; v_xp := pet.xp + gain;
  LOOP
    EXIT WHEN lvl >= maxlvl;
    need := pet_level_xp_required(lvl);
    EXIT WHEN v_xp < need;
    v_xp := v_xp - need; lvl := lvl + 1; gained := gained + 1;
  END LOOP;
  IF lvl >= maxlvl THEN v_xp := 0; END IF;
  UPDATE player_pets SET level = lvl, xp = v_xp, updated_at = now() WHERE id = pet.id;

  INSERT INTO pet_upgrade_history (user_id, player_pet_id, old_level, new_level, food_spent, action, food_code, xp_before, xp_added, xp_after)
  VALUES (u, pet.id, pet.level, lvl, p_quantity, 'feed', food.code, xp_before, gain, v_xp);

  payload := jsonb_build_object('dashboard', get_pet_dashboard(p_telegram_id),
    'feedResult', jsonb_build_object('xpGained', gain, 'levelsGained', gained, 'level', lvl, 'xp', v_xp,
      'foodName', food.name, 'quantity', p_quantity));
  INSERT INTO pet_action_idempotency VALUES (p_idempotency_key, u, pet.id, 'feed_item', payload, now());
  RETURN payload;
END
$$;
