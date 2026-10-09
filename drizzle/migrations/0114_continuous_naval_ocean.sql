CREATE OR REPLACE FUNCTION public.naval_ocean_land(p_x double precision, p_y double precision)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE cx integer:=floor(p_x/2400)::integer; cy integer:=floor(p_y/2400)::integer; gx integer; gy integer; seed integer; ix double precision; iy double precision; radius double precision;
BEGIN
 IF EXISTS(SELECT 1 FROM (VALUES(620.0,410.0,340.0),(1520.0,920.0,370.0),(2500.0,440.0,400.0),(2520.0,1540.0,390.0),(680.0,1500.0,370.0)) AS i(x,y,r) WHERE sqrt(power(p_x-i.x,2)+power(p_y-i.y,2))<i.r*0.7) THEN RETURN true; END IF;
 FOR gx IN cx-1..cx+1 LOOP FOR gy IN cy-1..cy+1 LOOP
  IF gx BETWEEN -1 AND 1 AND gy BETWEEN -1 AND 1 THEN CONTINUE; END IF;
  seed:=(((gx::bigint*73+gy::bigint*151)%997+997)%997)::integer;
  IF seed%4=0 THEN CONTINUE; END IF;
  ix:=gx::double precision*2400+600+seed%1200; iy:=gy::double precision*2400+600+(seed*37)%1200; radius:=180+seed%260;
  IF sqrt(power(p_x-ix,2)+power(p_y-iy,2))<radius*0.7 THEN RETURN true; END IF;
 END LOOP; END LOOP;
 RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.naval_ocean_land(double precision,double precision) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_ocean_land(double precision,double precision) TO service_role;
DO $$
DECLARE definition text; original text:='nx:=greatest(70,least(3130,s.x+dx/greatest(1,dist)*speed*dt)); ny:=greatest(70,least(2063,s.y+dy/greatest(1,dist)*speed*dt));'; old_collision text:='IF EXISTS(SELECT 1 FROM (VALUES(620.0,410.0,340.0),(1520.0,920.0,370.0),(2500.0,440.0,400.0),(2520.0,1540.0,390.0),(680.0,1500.0,370.0)) AS i(x,y,r) WHERE sqrt(power(nx-i.x,2)+power(ny-i.y,2))<i.r*0.7) THEN';
BEGIN
 SELECT pg_get_functiondef('public.naval_action(uuid,text,jsonb)'::regprocedure) INTO definition;
 IF strpos(definition,original)=0 OR strpos(definition,old_collision)=0 THEN RAISE EXCEPTION 'Naval movement definition changed; review before replacing'; END IF;
 definition:=replace(definition,original,'nx:=s.x+dx/greatest(1,dist)*speed*dt; ny:=s.y+dy/greatest(1,dist)*speed*dt;');
 definition:=replace(definition,old_collision,'IF public.naval_ocean_land(nx,ny) THEN');
 EXECUTE definition;
END $$;
REVOKE ALL ON FUNCTION public.naval_action(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_action(uuid,text,jsonb) TO service_role;