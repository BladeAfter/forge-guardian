CREATE OR REPLACE FUNCTION public.pvp_league_build_rewards(p_event_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  ev public.pvp_league_events;
  f numeric; total numeric := 0; dust numeric; segtail numeric;
  base_mid numeric[] := ARRAY[2.2,2.0,1.8,1.7,1.6,1.4,1.3];
  mid_end int; n int; k numeric; w numeric; wsum numeric := 0; r int; val numeric;
BEGIN
  SELECT * INTO ev FROM public.pvp_league_events WHERE id = p_event_id;
  IF ev.id IS NULL THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;

  DELETE FROM public.pvp_league_rewards WHERE event_id = p_event_id;
  f := ev.prize_pool_ton / 40.0;            -- scales the 40 TON blueprint to any pool
  segtail := 12 * f;
  mid_end := LEAST(ev.top_limit, 10);

  INSERT INTO public.pvp_league_rewards(event_id, rank, reward_ton) VALUES
    (p_event_id, 1, round(7 * f, 6)), (p_event_id, 2, round(5 * f, 6)), (p_event_id, 3, round(4 * f, 6));

  IF ev.top_limit >= 4 THEN
    FOR r IN 4..mid_end LOOP
      INSERT INTO public.pvp_league_rewards(event_id, rank, reward_ton)
      VALUES (p_event_id, r, round(base_mid[r - 3] * f, 6));
    END LOOP;
  END IF;

  -- #11..top_limit: linear decreasing with a 3:1 first/last ratio (e.g. 0.450 -> 0.150 TON on 40/50).
  IF ev.top_limit >= 11 THEN
    n := ev.top_limit - 10;
    k := CASE WHEN n >= 4 THEN (n - 3)::numeric / 2 ELSE 0 END;
    FOR r IN 11..ev.top_limit LOOP wsum := wsum + ((ev.top_limit - r + 1) + k); END LOOP;
    FOR r IN 11..ev.top_limit LOOP
      w := (ev.top_limit - r + 1) + k;
      val := round(segtail * w / wsum, 6);
      INSERT INTO public.pvp_league_rewards(event_id, rank, reward_ton) VALUES (p_event_id, r, val);
    END LOOP;
  END IF;

  SELECT COALESCE(sum(reward_ton), 0) INTO total FROM public.pvp_league_rewards WHERE event_id = p_event_id;
  dust := round(ev.prize_pool_ton - total, 9);
  IF dust <> 0 THEN
    UPDATE public.pvp_league_rewards SET reward_ton = round(reward_ton + dust, 9)
     WHERE event_id = p_event_id AND rank = 1;
  END IF;
  SELECT COALESCE(sum(reward_ton), 0) INTO total FROM public.pvp_league_rewards WHERE event_id = p_event_id;
  RETURN total;
END $$;