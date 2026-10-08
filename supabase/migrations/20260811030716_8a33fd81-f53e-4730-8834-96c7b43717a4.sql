CREATE TABLE IF NOT EXISTS public._boss_smoke2 (step text, payload jsonb, at timestamptz default now());
DO $$
DECLARE a bigint; bb bigint; r jsonb; ua uuid; ub uuid; cid uuid;
BEGIN
  SELECT telegram_id, id INTO a, ua FROM public.game_players ORDER BY created_at LIMIT 1;
  SELECT telegram_id, id INTO bb, ub FROM public.game_players ORDER BY created_at OFFSET 1 LIMIT 1;
  SELECT id INTO cid FROM public.global_boss_cycles WHERE status='active' LIMIT 1;
  -- Two players with 75% / 25% of the damage.
  PERFORM public.record_global_boss_damage(cid, ua, 7500);
  PERFORM public.record_global_boss_damage(cid, ub, 2500);
  INSERT INTO public._boss_smoke2 VALUES ('before_balances',
    (SELECT jsonb_agg(jsonb_build_object('id', id, 'fc', forge_coins)) FROM public.game_players WHERE id IN (ua, ub)));
  r := public.admin_global_boss(8118569391, 'end', null, 'smoke test');
  INSERT INTO public._boss_smoke2 VALUES ('end', r);
  INSERT INTO public._boss_smoke2 VALUES ('ledger',
    (SELECT jsonb_agg(to_jsonb(l)) FROM public.global_boss_reward_ledger l WHERE l.boss_cycle_id = cid));
  INSERT INTO public._boss_smoke2 VALUES ('after_balances',
    (SELECT jsonb_agg(jsonb_build_object('id', id, 'fc', forge_coins)) FROM public.game_players WHERE id IN (ua, ub)));
  -- Second call must not pay twice.
  INSERT INTO public._boss_smoke2 VALUES ('again', public.distribute_global_boss_rewards(cid));
  INSERT INTO public._boss_smoke2 VALUES ('after_again',
    (SELECT jsonb_agg(jsonb_build_object('id', id, 'fc', forge_coins)) FROM public.game_players WHERE id IN (ua, ub)));
  INSERT INTO public._boss_smoke2 VALUES ('state_after', public.process_boss_combat(a) - 'heroes' - 'ownedHeroes');
  INSERT INTO public._boss_smoke2 VALUES ('history', public.get_global_boss_history(a, 5));
END $$;