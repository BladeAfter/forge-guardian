DO $migration$
DECLARE definition text; revised text;
BEGIN
  definition := pg_get_functiondef('public.process_boss_combat(bigint,timestamptz)'::regprocedure);
  revised := replace(definition, 'if c.next_hero_attack_at<=special_at then', 'if c.next_hero_attack_at<=special_at and coalesce(current_setting(''app.kraken_observer'', true), ''off'') <> ''on'' then');
  IF revised = definition THEN RAISE EXCEPTION 'Expected hero tick branch missing'; END IF;
  EXECUTE revised;
  definition := pg_get_functiondef('public.attack_boss(bigint)'::regprocedure);
  revised := replace(definition, 'v_result := public.process_boss_combat(p_telegram_id);', 'PERFORM public.ensure_boss_combat(p_telegram_id);
  PERFORM 1 FROM public.boss_combats WHERE user_id = u AND status = ''active'' FOR UPDATE;
  UPDATE public.boss_combats SET next_hero_attack_at = clock_timestamp()
    WHERE user_id = u AND status = ''active'' AND next_hero_attack_at <= clock_timestamp();
  v_result := public.process_boss_combat(p_telegram_id);');
  IF revised = definition THEN RAISE EXCEPTION 'Expected manual attack settlement missing'; END IF;
  EXECUTE revised;
END $migration$;
CREATE OR REPLACE FUNCTION public.observe_boss_combat(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE result jsonb; previous text := coalesce(current_setting('app.kraken_observer', true), 'off');
BEGIN
  PERFORM set_config('app.kraken_observer', 'on', true);
  result := public.process_boss_combat(p_telegram_id);
  PERFORM set_config('app.kraken_observer', previous, true);
  RETURN result;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.kraken_observer', previous, true);
  RAISE;
END $function$;
REVOKE ALL ON FUNCTION public.observe_boss_combat(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.observe_boss_combat(bigint) TO service_role;
COMMENT ON FUNCTION public.observe_boss_combat(bigint) IS 'Global Boss observation settles enemy/revive events without consuming regular manual hero attacks; automatic scheduler keeps its existing processor.';