BEGIN;
UPDATE public.global_boss_cycles SET ends_at=now()+interval '1 day' WHERE status='active';
UPDATE public.boss_templates SET ends_at=now()+interval '1 day' WHERE active;
-- Exercise authoritative combat inside a rollback: no persistent player or balance changes.
DO $test$
DECLARE u uuid; tg bigint; ids uuid[]; c uuid; before_damage numeric; after_damage numeric;
  before_hp numeric; after_hp numeric; attack_at timestamptz; result jsonb;
BEGIN
  SELECT h.user_id, p.telegram_id, array_agg(h.id ORDER BY h.id) INTO u,tg,ids
  FROM public.player_heroes h JOIN public.game_players p ON p.id=h.user_id
  GROUP BY h.user_id,p.telegram_id HAVING count(*)>=6 LIMIT 1;
  IF u IS NULL THEN RAISE EXCEPTION 'Six owned heroes required for transactional combat test'; END IF;
  UPDATE public.global_boss_cycles SET current_hp=1000000000,max_hp=1000000000 WHERE status='active';
  result:=public.set_boss_team(tg,ids[1:6]);
  IF (SELECT count(*) FROM public.boss_team_slots WHERE user_id=u)<>6 THEN
    RAISE EXCEPTION 'Six crew were not persisted';
  END IF;
  SELECT id INTO c FROM public.boss_combats WHERE user_id=u AND status='active';
  IF c IS NULL THEN RAISE EXCEPTION 'Active combat required'; END IF;
  UPDATE public.hero_combat_state SET current_hp=max_hp,is_alive=true,revive_protected=false WHERE combat_id=c;
  UPDATE public.boss_combats SET last_processed_at=clock_timestamp()-interval '2 seconds',
    next_hero_attack_at=clock_timestamp()-interval '1 second',
    boss_next_attack_at=clock_timestamp()-interval '1 second' WHERE id=c;
  SELECT total_damage_dealt,next_hero_attack_at INTO before_damage,attack_at FROM public.boss_combats WHERE id=c;
  SELECT sum(current_hp) INTO before_hp FROM public.hero_combat_state WHERE combat_id=c AND slot IS NOT NULL;
  result:=public.observe_boss_combat(tg);
  SELECT total_damage_dealt INTO after_damage FROM public.boss_combats WHERE id=c;
  SELECT sum(current_hp) INTO after_hp FROM public.hero_combat_state WHERE combat_id=c AND slot IS NOT NULL;
  IF after_damage<>before_damage THEN RAISE EXCEPTION 'Observation consumed manual damage'; END IF;
  IF after_hp>=before_hp THEN RAISE EXCEPTION 'Kraken counterattack did not damage crew'; END IF;
  IF (SELECT next_hero_attack_at FROM public.boss_combats WHERE id=c)<>attack_at THEN
    RAISE EXCEPTION 'Observation consumed manual cooldown';
  END IF;
  result:=public.attack_boss(tg);
  SELECT total_damage_dealt INTO after_damage FROM public.boss_combats WHERE id=c;
  IF after_damage<=before_damage THEN RAISE EXCEPTION 'Manual attack did not damage Kraken'; END IF;
  before_damage:=after_damage;
  result:=public.attack_boss(tg);
  SELECT total_damage_dealt INTO after_damage FROM public.boss_combats WHERE id=c;
  IF after_damage<>before_damage THEN RAISE EXCEPTION 'Repeated attack bypassed shared cooldown'; END IF;
  IF jsonb_array_length(result->'heroes')<>6 THEN RAISE EXCEPTION 'Six crew not returned'; END IF;
  BEGIN
    PERFORM public.equip_combat_hero(tg,ids[1],7);
    RAISE EXCEPTION 'Seventh slot accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'INVALID_SLOT' THEN RAISE; END IF;
  END;
  IF has_function_privilege('anon','public.observe_boss_combat(bigint)','EXECUTE')
    OR has_function_privilege('authenticated','public.observe_boss_combat(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'Observation must remain server-only';
  END IF;
  RAISE NOTICE 'Six crew, Kraken damage, counterattack, observation and cooldown verified';
END $test$;
ROLLBACK;