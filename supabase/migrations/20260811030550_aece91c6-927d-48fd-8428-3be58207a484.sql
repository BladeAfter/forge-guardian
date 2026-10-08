CREATE TABLE IF NOT EXISTS public._boss_smoke (step text, payload jsonb, at timestamptz default now());
GRANT SELECT ON public._boss_smoke TO service_role;
DO $$
DECLARE a bigint; bb bigint; r jsonb;
BEGIN
  SELECT telegram_id INTO a FROM public.game_players ORDER BY created_at LIMIT 1;
  SELECT telegram_id INTO bb FROM public.game_players ORDER BY created_at OFFSET 1 LIMIT 1;
  r := public.process_boss_combat(a);
  INSERT INTO public._boss_smoke VALUES ('a', r - 'ownedHeroes' - 'heroes');
  IF bb IS NOT NULL THEN
    r := public.process_boss_combat(bb);
    INSERT INTO public._boss_smoke VALUES ('b', r - 'ownedHeroes' - 'heroes');
  END IF;
  INSERT INTO public._boss_smoke VALUES ('cycles', (SELECT jsonb_agg(to_jsonb(c)) FROM public.global_boss_cycles c));
  INSERT INTO public._boss_smoke VALUES ('participants', (SELECT jsonb_agg(to_jsonb(p)) FROM public.global_boss_participants p));
  INSERT INTO public._boss_smoke VALUES ('ranking', public.get_global_boss_ranking(a, 10));
  INSERT INTO public._boss_smoke VALUES ('history', public.get_global_boss_history(a, 5));
END $$;