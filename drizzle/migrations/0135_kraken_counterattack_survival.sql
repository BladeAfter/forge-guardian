CREATE OR REPLACE FUNCTION public.kraken_damage_to_hero(p_attack numeric, p_rarity text, p_max_hp numeric, p_reduction numeric DEFAULT 0)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $function$
  SELECT least(
    greatest(1, round(greatest(0, coalesce(p_attack, 0)) * public.rarity_resistance(p_rarity) * (1 - least(100, greatest(0, coalesce(p_reduction, 0))) / 100))),
    greatest(1, floor(greatest(0, coalesce(p_max_hp, 0)) * 0.35))
  );
$function$;
REVOKE ALL ON FUNCTION public.kraken_damage_to_hero(numeric,text,numeric,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kraken_damage_to_hero(numeric,text,numeric,numeric) TO service_role;
COMMENT ON FUNCTION public.kraken_damage_to_hero(numeric,text,numeric,numeric) IS 'Authoritative global boss counterattack: preserves rarity/pet mitigation and caps each hit at 35 percent of maximum hero HP, never current HP; low-health heroes can still be knocked out.';
DO $migration$
DECLARE definition text; revised text;
BEGIN
  definition := pg_get_functiondef('public.process_boss_combat(bigint,timestamptz)'::regprocedure);
  revised := replace(definition,
    'target.current_hp:=greatest(0,target.current_hp-greatest(1,round(c.boss_attack*public.rarity_resistance(target.rarity)*(1-damage_reduction/100))));',
    'target.current_hp:=greatest(0,target.current_hp-public.kraken_damage_to_hero(c.boss_attack,target.rarity,target.max_hp,damage_reduction));');
  IF revised = definition THEN RAISE EXCEPTION 'Expected Kraken counterattack formula missing'; END IF;
  EXECUTE revised;
END $migration$;