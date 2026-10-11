ALTER TABLE public.boss_team_slots DROP CONSTRAINT boss_team_slots_slot_check;
ALTER TABLE public.boss_team_slots ADD CONSTRAINT boss_team_slots_slot_check CHECK (slot BETWEEN 1 AND 6);
ALTER TABLE public.hero_combat_state DROP CONSTRAINT hero_combat_state_slot_check;
ALTER TABLE public.hero_combat_state ADD CONSTRAINT hero_combat_state_slot_check CHECK (slot BETWEEN 1 AND 6);
DO $migration$
DECLARE signature regprocedure; definition text; revised text;
BEGIN
  FOREACH signature IN ARRAY ARRAY['public.equip_combat_hero(bigint,uuid,integer)'::regprocedure, 'public.unequip_combat_hero(bigint,integer)'::regprocedure, 'public.set_boss_team(bigint,uuid[])'::regprocedure]
  LOOP
    definition := pg_get_functiondef(signature);
    revised := replace(replace(definition, 'p_slot>5', 'p_slot>6'), 'cardinality(p_hero_ids),0)>5', 'cardinality(p_hero_ids),0)>6');
    IF revised = definition THEN RAISE EXCEPTION 'Expected five-slot guard missing in %', signature; END IF;
    EXECUTE revised;
  END LOOP;
END $migration$;
REVOKE ALL ON FUNCTION public.equip_combat_hero(bigint,uuid,integer), public.unequip_combat_hero(bigint,integer), public.set_boss_team(bigint,uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.equip_combat_hero(bigint,uuid,integer), public.unequip_combat_hero(bigint,integer), public.set_boss_team(bigint,uuid[]) TO service_role;
COMMENT ON TABLE public.boss_team_slots IS 'Six server-owned Global Boss crew slots; other combat teams retain their existing limits.';