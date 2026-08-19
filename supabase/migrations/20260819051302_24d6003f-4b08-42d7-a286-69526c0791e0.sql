ALTER TABLE public.game_players ADD COLUMN IF NOT EXISTS avatar_border text;

CREATE OR REPLACE FUNCTION public.upsert_telegram_player_profile(p_telegram_id bigint, p_first_name text, p_last_name text DEFAULT NULL::text, p_username text DEFAULT NULL::text, p_photo_url text DEFAULT NULL::text, p_language_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare player game_players%rowtype; suggested text;
begin
  if p_telegram_id is null or nullif(trim(p_first_name),'') is null then raise exception 'INVALID_TELEGRAM_PROFILE';end if;
  suggested := normalize_language_code(p_language_code);
  insert into game_players(telegram_id,first_name,last_name,display_name,username,avatar_url,last_seen_at,language)
  values(p_telegram_id,trim(p_first_name),nullif(trim(p_last_name),''),trim(concat_ws(' ',p_first_name,p_last_name)),nullif(trim(p_username),''),nullif(trim(p_photo_url),''),now(),suggested)
  on conflict(telegram_id) do update set first_name=excluded.first_name,last_name=excluded.last_name,display_name=excluded.display_name,username=excluded.username,avatar_url=excluded.avatar_url,last_seen_at=now(),updated_at=now()
  returning * into player;
  return jsonb_build_object('telegramId',player.telegram_id::text,'firstName',player.first_name,'lastName',player.last_name,'username',player.username,'photoUrl',player.avatar_url,'avatarBorder',player.avatar_border,'language',player.language,'languageLocked',player.language_locked);
end $function$;

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
      (100000::bigint, 'legendary_chest', 'hero_chest', 25, 0, '["1 Legendary Chest","25 Universal Fragments","1 Exclusive Avatar Border"]'::jsonb),
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

    IF NOT FOUND THEN
      -- Milestone already delivered: still make sure the cosmetic exists (older claims).
      IF v_ms.amount = 100000 THEN
        UPDATE public.game_players SET avatar_border = 'myth_sale_exclusive', updated_at = now()
         WHERE id = p_user AND avatar_border IS DISTINCT FROM 'myth_sale_exclusive';
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

    IF v_ms.amount = 100000 THEN
      UPDATE public.game_players SET avatar_border = 'myth_sale_exclusive', updated_at = now() WHERE id = p_user;
    END IF;

    v_delivered := v_delivered + 1;
  END LOOP;

  RETURN v_delivered;
END;
$$;

REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.deliver_myth_sale_milestones(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.deliver_myth_sale_milestones(uuid) TO service_role;