CREATE OR REPLACE FUNCTION public.naval_validate_row() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$ BEGIN
 IF NEW.x='NaN'::float8 OR NEW.y='NaN'::float8 OR NEW.heading='NaN'::float8 OR NEW.throttle='NaN'::float8 OR NEW.x<60 OR NEW.x>3140 OR NEW.y<60 OR NEW.y>2073 THEN RAISE EXCEPTION 'NAVAL_INVALID_INPUT'; END IF;
 IF TG_OP='UPDATE' AND (NEW.x<>OLD.x OR NEW.y<>OLD.y) AND EXISTS(SELECT 1 FROM (VALUES(620.0,410.0,340.0),(1520.0,920.0,370.0),(2500.0,440.0,400.0),(2520.0,1540.0,390.0),(680.0,1500.0,370.0)) AS i(x,y,r) WHERE sqrt(power(NEW.x-i.x,2)+power(NEW.y-i.y,2))<i.r*.7) THEN NEW.x:=OLD.x; NEW.y:=OLD.y; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER naval_validate_row BEFORE INSERT OR UPDATE ON public.naval_ships FOR EACH ROW EXECUTE FUNCTION public.naval_validate_row();
CREATE OR REPLACE FUNCTION public.naval_battle_validate() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$ DECLARE cfg jsonb; BEGIN
 cfg:=coalesce((SELECT value FROM game_settings WHERE key='naval_rules'),'{}'::jsonb);
 IF NOT coalesce((cfg->>'pvpEnabled')::boolean,false) OR coalesce((cfg->>'lootPercent')::numeric,0) NOT BETWEEN .01 AND 10 OR coalesce((cfg->>'lootCap')::numeric,0)<=0 OR cfg->>'lootSource'<>'loser' OR jsonb_typeof(cfg->'lootItems') IS DISTINCT FROM 'array' OR jsonb_array_length(cfg->'lootItems')=0 THEN RAISE EXCEPTION 'NAVAL_RULES_PENDING'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER naval_battle_validate BEFORE INSERT ON public.naval_battles FOR EACH ROW EXECUTE FUNCTION public.naval_battle_validate();
REVOKE ALL ON FUNCTION public.naval_validate_row(),public.naval_battle_validate() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_validate_row(),public.naval_battle_validate() TO service_role;