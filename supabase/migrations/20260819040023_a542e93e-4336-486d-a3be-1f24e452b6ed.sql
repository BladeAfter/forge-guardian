CREATE OR REPLACE FUNCTION public.deliver_myth_sale_milestones(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total bigint;
  v_delivered integer := 0;
  v_ms record;
BEGIN
  IF p_user IS NULL THEN RETURN 0; END IF;
  SELECT COALESCE(SUM(myth_amount),0) INTO v_total
  FROM public.myth_sale_transactions
  WHERE user_id = p_user AND upper(status) = 'CONFIRMED';

  FOR v_ms IN
    SELECT * FROM (VALUES
      (10000::bigint, 'rare_chest', 'hero_chest', 5, 0, '["1 Rare Chest","5 Universal Fragments"]'::jsonb),
      (50000::bigint, 'epic_chest', 'hero_chest', 10, 2, '["1 Epic Chest","10 Universal Fragments","2 PvP Tickets"]'::jsonb),
      (100000::bigint, 'legendary_chest', 'hero_chest', 25, 0, '["1 Legendary Chest","25 Universal Fragments"]'::jsonb),
      (250000::bigint, 'legend-chest', 'hero_chest', 50, 0, '["1 Mythic Chest","50 Universal Fragments"]'::jsonb),
      (500000::bigint, 'mythic-egg', 'pet_egg', 100, 0, '["1 Exclusive Pet Egg","100 Universal Fragments"]'::jsonb),
      (1000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 200, 5, '["1 Exclusive Hero Chest","200 Universal Fragments","5 PvP Tickets"]'::jsonb)
    ) AS t(amount, item_code, item_type, fragments, tickets, rewards)
    ORDER BY 1
  LOOP
    CONTINUE WHEN v_total < v_ms.amount;

    INSERT INTO public.myth_sale_milestone_claims(user_id, milestone_amount, myth_total, rewards)
    VALUES (p_user, v_ms.amount, v_total, v_ms.rewards)
    ON CONFLICT (user_id, milestone_amount) DO NOTHING;

    IF NOT FOUND THEN CONTINUE; END IF;

    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (p_user, v_ms.item_type, v_ms.item_code, 1)
    ON CONFLICT (user_id, item_type, item_code)
    DO UPDATE SET quantity = public.player_inventory.quantity + 1, updated_at = now();

    IF v_ms.fragments > 0 THEN
      INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
      VALUES (p_user, 'fragments', 'fragments', v_ms.fragments)
      ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + v_ms.fragments, updated_at = now();
    END IF;

    IF v_ms.tickets > 0 THEN
      UPDATE public.game_players SET pvp_tickets = COALESCE(pvp_tickets,0) + v_ms.tickets WHERE id = p_user;
    END IF;

    v_delivered := v_delivered + 1;
  END LOOP;

  RETURN v_delivered;
END;
$$;

REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deliver_myth_sale_milestones(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.trg_myth_sale_milestones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF upper(COALESCE(NEW.status,'')) = 'CONFIRMED' THEN
    PERFORM public.deliver_myth_sale_milestones(NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS myth_sale_milestones_deliver ON public.myth_sale_transactions;
CREATE TRIGGER myth_sale_milestones_deliver
AFTER INSERT OR UPDATE OF status ON public.myth_sale_transactions
FOR EACH ROW EXECUTE FUNCTION public.trg_myth_sale_milestones();

DO $$
DECLARE r record; n integer; total integer := 0;
BEGIN
  FOR r IN SELECT DISTINCT user_id FROM public.myth_sale_transactions WHERE upper(status) = 'CONFIRMED' LOOP
    n := public.deliver_myth_sale_milestones(r.user_id);
    total := total + n;
  END LOOP;
  RAISE NOTICE 'milestones delivered: %', total;
END $$;