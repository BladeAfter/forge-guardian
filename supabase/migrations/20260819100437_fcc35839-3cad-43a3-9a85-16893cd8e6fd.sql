CREATE OR REPLACE FUNCTION public.deliver_myth_sale_milestones(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
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
      (10000::bigint, 'rare_chest', 'hero_chest', 5, 0, NULL::text, '["1 Rare Chest","5 Universal Fragments"]'::jsonb),
      (50000::bigint, 'epic_chest', 'hero_chest', 10, 2, NULL::text, '["1 Epic Chest","10 Universal Fragments","2 PvP Tickets"]'::jsonb),
      (100000::bigint, 'legendary_chest', 'hero_chest', 25, 0, NULL::text, '["1 Legendary Chest","25 Universal Fragments","1 Exclusive Avatar Border"]'::jsonb),
      (250000::bigint, 'legend-chest', 'hero_chest', 50, 0, NULL::text, '["1 Mythic Chest","50 Universal Fragments","1 Premium Title"]'::jsonb),
      (500000::bigint, 'mythic-egg', 'pet_egg', 100, 0, NULL::text, '["1 Exclusive Pet Egg","100 Universal Fragments"]'::jsonb),
      (1000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 200, 5, 'nfteq_weapon_ms01', '["1 Exclusive Hero Chest","200 Universal Fragments","5 PvP Tickets","NFT Weapon: Mythblade Ascendant"]'::jsonb),
      (1500000::bigint, 'legend-chest', 'hero_chest', 250, 8, NULL::text, '["1 Mythic Chest","250 Universal Fragments","8 PvP Tickets"]'::jsonb),
      (2000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 300, 10, 'nfteq_weapon_ms02', '["1 Exclusive Hero Chest","300 Universal Fragments","10 PvP Tickets","NFT Weapon: Myth Reaver"]'::jsonb),
      (3000000::bigint, 'mythic-egg', 'pet_egg', 400, 12, NULL::text, '["1 Exclusive Pet Egg","400 Universal Fragments","12 PvP Tickets"]'::jsonb),
      (4000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 500, 15, 'nfteq_weapon_ms03', '["1 Exclusive Hero Chest","500 Universal Fragments","15 PvP Tickets","NFT Weapon: Scepter of Eternity"]'::jsonb),
      (5000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 650, 20, NULL::text, '["1 Exclusive Hero Chest","650 Universal Fragments","20 PvP Tickets"]'::jsonb),
      (6000000::bigint, 'mythic-egg', 'pet_egg', 800, 25, 'nfteq_weapon_ms04', '["1 Exclusive Pet Egg","800 Universal Fragments","25 PvP Tickets","NFT Weapon: Mythveil Longbow"]'::jsonb),
      (7000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 1000, 30, NULL::text, '["1 Exclusive Hero Chest","1000 Universal Fragments","30 PvP Tickets"]'::jsonb),
      (8000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 1300, 35, 'nfteq_weapon_ms05', '["1 Exclusive Hero Chest","1300 Universal Fragments","35 PvP Tickets","NFT Weapon: Mythsong Staff"]'::jsonb),
      (9000000::bigint, 'mythic-egg', 'pet_egg', 1600, 40, NULL::text, '["1 Exclusive Pet Egg","1600 Universal Fragments","40 PvP Tickets"]'::jsonb),
      (10000000::bigint, 'exclusive-hero-chest', 'exclusive_chest', 2000, 50, 'nfteq_weapon_ms06', '["1 Exclusive Hero Chest","2000 Universal Fragments","50 PvP Tickets","NFT Weapon: Godshard of Mythreon"]'::jsonb)
    ) AS t(amount, item_code, item_type, fragments, tickets, weapon_code, rewards)
    ORDER BY 1
  LOOP
    CONTINUE WHEN v_total < v_ms.amount;

    INSERT INTO public.myth_sale_milestone_claims(user_id, milestone_amount, myth_total, rewards)
    VALUES (p_user, v_ms.amount, v_total, v_ms.rewards)
    ON CONFLICT (user_id, milestone_amount) DO NOTHING;

    IF NOT FOUND THEN
      IF v_ms.amount = 100000 THEN
        UPDATE public.game_players SET avatar_border = 'myth_sale_exclusive', updated_at = now()
         WHERE id = p_user AND avatar_border IS DISTINCT FROM 'myth_sale_exclusive';
      END IF;
      IF v_ms.amount = 250000 THEN
        UPDATE public.game_players SET premium_title = 'MYTH LEGEND', updated_at = now()
         WHERE id = p_user AND COALESCE(premium_title,'') = '';
      END IF;
      IF v_ms.weapon_code IS NOT NULL THEN
        PERFORM public.deliver_myth_sale_milestone_weapon(p_user, v_ms.weapon_code);
      END IF;
      CONTINUE;
    END IF;

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

    IF v_ms.weapon_code IS NOT NULL THEN
      PERFORM public.deliver_myth_sale_milestone_weapon(p_user, v_ms.weapon_code);
    END IF;

    IF v_ms.amount = 100000 THEN
      UPDATE public.game_players SET avatar_border = 'myth_sale_exclusive', updated_at = now() WHERE id = p_user;
    END IF;

    IF v_ms.amount = 250000 THEN
      UPDATE public.game_players SET premium_title = 'MYTH LEGEND', updated_at = now()
       WHERE id = p_user AND COALESCE(premium_title,'') = '';
    END IF;

    v_delivered := v_delivered + 1;
  END LOOP;

  RETURN v_delivered;
END;
$fn$;