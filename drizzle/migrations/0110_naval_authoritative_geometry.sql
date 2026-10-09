DO $migration$ DECLARE definition text; BEGIN
 SELECT pg_get_functiondef('public.naval_action(uuid,text,jsonb)'::regprocedure) INTO definition;
 definition:=replace(definition,'(755.0,650.0,290.0),(1540.0,1040.0,240.0),(2550.0,540.0,250.0),(2530.0,1580.0,260.0),(650.0,1690.0,220.0)','(620.0,410.0,340.0),(1520.0,920.0,370.0),(2500.0,440.0,400.0),(2520.0,1540.0,390.0),(680.0,1500.0,370.0)');
 definition:=replace(definition,'  FOR target,cost IN SELECT p_user,repair_wood LOOP END LOOP;','');
 EXECUTE definition;
END $migration$;