DO $$
DECLARE
  v_war uuid := '10fc91dc-61b7-4a5b-9e8d-f924b490c518';
  v_clan uuid := 'c569bd4c-30b6-47d9-a2b2-23bfce0c8f72';
  r record;
BEGIN
  FOR r IN SELECT user_id FROM public.clan_war_rosters WHERE war_id = v_war AND clan_id = v_clan LOOP
    UPDATE public.game_players SET forge_coins = COALESCE(forge_coins,0) + 200000 WHERE id = r.user_id;

    INSERT INTO public.myth_balances(user_id, amount, updated_at)
    VALUES (r.user_id, 10000, now())
    ON CONFLICT (user_id) DO UPDATE SET amount = public.myth_balances.amount + 10000, updated_at = now();

    INSERT INTO public.myth_ledger(user_id, direction, amount, reason)
    VALUES (r.user_id, 'credit', 10000, 'clan_war_winner_bonus');
  END LOOP;
END $$;