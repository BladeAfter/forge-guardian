DO $migration$ DECLARE definition text; BEGIN
 SELECT pg_get_functiondef('public.naval_action(uuid,text,jsonb)'::regprocedure) INTO definition;
 definition:=replace(definition,'least(3,floor(r.amount*.05))','least(coalesce(((SELECT value FROM game_settings WHERE key=''naval_rules'')->>''itemLootCap'')::numeric,0),floor(r.amount*coalesce(((SELECT value FROM game_settings WHERE key=''naval_rules'')->>''itemLootPercent'')::numeric,0)/100))');
 EXECUTE definition;
 SELECT pg_get_functiondef('public.naval_battle_validate()'::regprocedure) INTO definition;
 definition:=replace(definition,'IF NOT coalesce','IF coalesce((cfg->>''itemLootPercent'')::numeric,0) NOT BETWEEN .01 AND 10 OR coalesce((cfg->>''itemLootCap'')::numeric,0)<=0 OR NOT coalesce');
 EXECUTE definition;
 SELECT pg_get_functiondef('public.naval_state(uuid)'::regprocedure) INTO definition;
 definition:=replace(definition,'SELECT * INTO b FROM naval_battles WHERE id=s.battle_id;','SELECT * INTO b FROM naval_battles WHERE id=s.battle_id; IF b.id IS NULL THEN SELECT * INTO b FROM naval_battles WHERE (attacker=p_user OR defender=p_user) AND finished_at>now()-interval ''2 minutes'' ORDER BY finished_at DESC LIMIT 1; END IF;');
 EXECUTE definition;
END $migration$;