CREATE TABLE public.naval_ships (
 user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
 model text NOT NULL DEFAULT 'small', skin text NOT NULL DEFAULT 'black', cosmetics jsonb NOT NULL DEFAULT '{"flag":"skull","prow":"lion","decoration":"gold","trail":"foam"}',
 level integer NOT NULL DEFAULT 1 CHECK(level BETWEEN 1 AND 50), xp integer NOT NULL DEFAULT 0, reputation integer NOT NULL DEFAULT 0,
 hp integer NOT NULL DEFAULT 1000 CHECK(hp>=0), x double precision NOT NULL DEFAULT 1700, y double precision NOT NULL DEFAULT 1340,
 heading double precision NOT NULL DEFAULT 0, throttle double precision NOT NULL DEFAULT 1 CHECK(throttle BETWEEN 0 AND 1),
 seen_at timestamptz NOT NULL DEFAULT now(), moved_at timestamptz NOT NULL DEFAULT now(), shot_at timestamptz, skill_at timestamptz, protected_until timestamptz NOT NULL DEFAULT now(), battle_id uuid,
 updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.naval_ships TO service_role;
ALTER TABLE public.naval_ships ENABLE ROW LEVEL SECURITY;
CREATE POLICY naval_ships_service ON public.naval_ships TO service_role USING(true) WITH CHECK(true);
CREATE TABLE public.naval_battles (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), attacker uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
 defender uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE, status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','won','escaped','expired')),
 winner uuid, loot jsonb NOT NULL DEFAULT '{}', started_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
 CHECK(attacker<>defender)
);
GRANT ALL ON public.naval_battles TO service_role;
ALTER TABLE public.naval_battles ENABLE ROW LEVEL SECURITY;
CREATE POLICY naval_battles_service ON public.naval_battles TO service_role USING(true) WITH CHECK(true);
CREATE INDEX naval_battles_players ON public.naval_battles(attacker,defender,started_at DESC);
CREATE TABLE public.naval_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, battle_id uuid REFERENCES public.naval_battles(id) ON DELETE CASCADE,
 actor uuid NOT NULL, kind text NOT NULL, x double precision NOT NULL, y double precision NOT NULL, target_x double precision, target_y double precision,
 damage integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.naval_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.naval_events_id_seq TO service_role;
ALTER TABLE public.naval_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY naval_events_service ON public.naval_events TO service_role USING(true) WITH CHECK(true);
CREATE INDEX naval_events_recent ON public.naval_events(created_at DESC);
CREATE OR REPLACE FUNCTION public.naval_state(p_user uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s naval_ships; b naval_battles; cfg jsonb; BEGIN
 SELECT * INTO s FROM naval_ships WHERE user_id=p_user;
 SELECT * INTO b FROM naval_battles WHERE id=s.battle_id;
 cfg:=coalesce((SELECT value FROM game_settings WHERE key='naval_rules'),'{}'::jsonb);
 RETURN jsonb_build_object('ship',to_jsonb(s),'battle',CASE WHEN b.id IS NULL THEN null ELSE to_jsonb(b) END,
 'rules',jsonb_build_object('pvpEnabled',coalesce((cfg->>'pvpEnabled')::boolean,false),'lootPercent',coalesce((cfg->>'lootPercent')::numeric,0),'repairWood',coalesce((cfg->>'repairWood')::integer,5),'repairIron',coalesce((cfg->>'repairIron')::integer,3)),
 'materials',coalesce((SELECT jsonb_object_agg(material_id,amount) FROM realm_material_balances WHERE user_id=p_user),'{}'::jsonb),
 'others',coalesce((SELECT jsonb_agg(t) FROM (SELECT n.user_id,n.model,n.skin,n.cosmetics,n.level,n.hp,n.x,n.y,n.heading,n.throttle,n.battle_id,coalesce(g.display_name,g.username,'Capitão') AS name FROM naval_ships n JOIN game_players g ON g.id=n.user_id WHERE n.user_id<>p_user AND NOT coalesce(g.banned,false) AND n.seen_at>now()-interval '8 seconds' AND sqrt(power(n.x-s.x,2)+power(n.y-s.y,2))<700+s.level*10 ORDER BY n.seen_at DESC LIMIT 30) t),'[]'::jsonb),
 'events',coalesce((SELECT jsonb_agg(t) FROM (SELECT id,actor,kind,x,y,target_x,target_y,damage,created_at FROM naval_events WHERE created_at>now()-interval '6 seconds' AND sqrt(power(x-s.x,2)+power(y-s.y,2))<1000 ORDER BY id DESC LIMIT 40) t),'[]'::jsonb));
END $$;
CREATE OR REPLACE FUNCTION public.naval_action(p_user uuid,p_action text,p_input jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s naval_ships; e naval_ships; b naval_battles; cfg jsonb; target uuid; dx double precision; dy double precision; dist double precision; dt double precision; speed double precision; nx double precision; ny double precision; angle double precision; delta double precision; damage integer; cost integer; old_amount numeric; repair_wood integer; repair_iron integer;
BEGIN
 IF current_user NOT IN ('postgres','service_role','supabase_admin') AND session_user<>'postgres' THEN RAISE EXCEPTION 'NAVAL_UNAUTHORIZED'; END IF;
 IF coalesce((SELECT value='true'::jsonb FROM game_settings WHERE key='game_reset_in_progress'),false) THEN RAISE EXCEPTION 'GAME_RESET'; END IF;
 IF NOT EXISTS(SELECT 1 FROM game_players WHERE id=p_user AND NOT coalesce(banned,false)) THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
 -- Global short transaction lock serializes both sides, settlement and material use.
 PERFORM pg_advisory_xact_lock(hashtextextended('naval-world',0));
 INSERT INTO naval_ships(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM naval_ships WHERE user_id=p_user FOR UPDATE;
 cfg:=coalesce((SELECT value FROM game_settings WHERE key='naval_rules'),'{}'::jsonb);
 IF s.battle_id IS NOT NULL THEN
  SELECT * INTO b FROM naval_battles WHERE id=s.battle_id FOR UPDATE;
  IF b.status='active' AND b.started_at<now()-interval '5 minutes' THEN
   UPDATE naval_battles SET status='expired',finished_at=now() WHERE id=b.id;
   UPDATE naval_ships SET battle_id=null,protected_until=now()+interval '2 minutes' WHERE user_id IN(b.attacker,b.defender);
   s.battle_id:=null;
  END IF;
 END IF;
 IF p_action='heartbeat' THEN
  dx:=greatest(-1,least(1,coalesce((p_input->>'dx')::double precision,0))); dy:=greatest(-1,least(1,coalesce((p_input->>'dy')::double precision,0)));
  IF dx='NaN'::float8 OR dy='NaN'::float8 THEN RAISE EXCEPTION 'NAVAL_INVALID_INPUT'; END IF;
  dist:=sqrt(dx*dx+dy*dy); dt:=greatest(0,least(2,extract(epoch FROM clock_timestamp()-s.moved_at)));
  speed:=(120+s.level*2)*greatest(0,least(1,coalesce((p_input->>'throttle')::double precision,1)));
  IF s.hp=0 THEN speed:=0; END IF;
  nx:=s.x; ny:=s.y;
  IF dist>0.01 THEN nx:=greatest(70,least(3130,s.x+dx/greatest(1,dist)*speed*dt)); ny:=greatest(70,least(2063,s.y+dy/greatest(1,dist)*speed*dt)); s.heading:=atan2(dx,-dy); END IF;
  -- Shared authored island collision geometry is supplied by no client.
  IF EXISTS(SELECT 1 FROM (VALUES(755.0,650.0,290.0),(1540.0,1040.0,240.0),(2550.0,540.0,250.0),(2530.0,1580.0,260.0),(650.0,1690.0,220.0)) AS i(x,y,r) WHERE sqrt(power(nx-i.x,2)+power(ny-i.y,2))<i.r*0.7) THEN nx:=s.x; ny:=s.y; END IF;
  UPDATE naval_ships SET x=nx,y=ny,heading=s.heading,throttle=CASE WHEN dist>.01 THEN speed/(120+s.level*2) ELSE 0 END,seen_at=now(),moved_at=clock_timestamp() WHERE user_id=p_user;
 ELSIF p_action='customize' THEN
  IF s.battle_id IS NOT NULL THEN RAISE EXCEPTION 'NAVAL_IN_BATTLE'; END IF;
  IF p_input->>'model' NOT IN('small','caravel','pirate','war','legendary','special') OR p_input->>'skin' NOT IN('black','inferno','deep','storm','reaper','king') THEN RAISE EXCEPTION 'NAVAL_INVALID_INPUT'; END IF;
  IF coalesce(p_input->'cosmetics'->>'flag','skull') NOT IN('skull','sun','moon') OR coalesce(p_input->'cosmetics'->>'prow','lion') NOT IN('lion','blade','none') OR coalesce(p_input->'cosmetics'->>'decoration','gold') NOT IN('gold','silver','none') OR coalesce(p_input->'cosmetics'->>'trail','foam') NOT IN('foam','embers','mist') THEN RAISE EXCEPTION 'NAVAL_INVALID_INPUT'; END IF;
  UPDATE naval_ships SET model=p_input->>'model',skin=p_input->>'skin',cosmetics=jsonb_build_object('flag',coalesce(p_input->'cosmetics'->>'flag','skull'),'prow',coalesce(p_input->'cosmetics'->>'prow','lion'),'decoration',coalesce(p_input->'cosmetics'->>'decoration','gold'),'trail',coalesce(p_input->'cosmetics'->>'trail','foam')) WHERE user_id=p_user;
 ELSIF p_action IN('repair','upgrade') THEN
  IF s.battle_id IS NOT NULL THEN RAISE EXCEPTION 'NAVAL_IN_BATTLE'; END IF;
  IF p_action='repair' AND s.hp>=1000+(s.level-1)*100 THEN RETURN naval_state(p_user); END IF;
  IF p_action='upgrade' AND(s.level>=50 OR s.xp<s.level*100) THEN RAISE EXCEPTION 'NAVAL_XP_REQUIRED'; END IF;
  repair_wood:=greatest(1,coalesce((cfg->>'repairWood')::integer,5))*s.level; repair_iron:=greatest(1,coalesce((cfg->>'repairIron')::integer,3))*s.level;
  PERFORM 1 FROM realm_material_balances WHERE user_id=p_user ORDER BY material_id FOR UPDATE;
  IF coalesce((SELECT amount FROM realm_material_balances WHERE user_id=p_user AND material_id='magic_wood'),0)<repair_wood OR coalesce((SELECT amount FROM realm_material_balances WHERE user_id=p_user AND material_id='iron_ore'),0)<repair_iron THEN RAISE EXCEPTION 'NAVAL_MATERIALS_REQUIRED'; END IF;
  FOR target,cost IN SELECT p_user,repair_wood LOOP END LOOP;
  INSERT INTO realm_material_ledger(user_id,material_id,amount,balance_before,balance_after,reason,source_id) SELECT p_user,material_id,-CASE WHEN material_id='magic_wood' THEN repair_wood ELSE repair_iron END,amount,amount-CASE WHEN material_id='magic_wood' THEN repair_wood ELSE repair_iron END,'naval_'||p_action,gen_random_uuid()::text FROM realm_material_balances WHERE user_id=p_user AND material_id IN('magic_wood','iron_ore');
  UPDATE realm_material_balances SET amount=amount-CASE WHEN material_id='magic_wood' THEN repair_wood ELSE repair_iron END,updated_at=now() WHERE user_id=p_user AND material_id IN('magic_wood','iron_ore');
  UPDATE naval_ships SET level=level+CASE WHEN p_action='upgrade' THEN 1 ELSE 0 END,xp=xp-CASE WHEN p_action='upgrade' THEN level*100 ELSE 0 END,hp=1000+(level-1+CASE WHEN p_action='upgrade' THEN 1 ELSE 0 END)*100 WHERE user_id=p_user;
 ELSIF p_action='attack' THEN
  -- Financial stakes require explicit configuration; never invent a percentage or item pool.
  IF NOT coalesce((cfg->>'pvpEnabled')::boolean,false) OR coalesce((cfg->>'lootPercent')::numeric,0)<=0 OR coalesce(cfg->>'lootSource','') NOT IN('loser') OR jsonb_typeof(cfg->'lootItems')<>'array' THEN RAISE EXCEPTION 'NAVAL_RULES_PENDING'; END IF;
  target:=(p_input->>'target')::uuid;
  SELECT * INTO e FROM naval_ships WHERE user_id=target FOR UPDATE;
  IF e.user_id IS NULL OR target=p_user OR e.seen_at<now()-interval '8 seconds' OR e.hp=0 OR s.hp=0 THEN RAISE EXCEPTION 'NAVAL_TARGET_UNAVAILABLE'; END IF;
  IF s.battle_id IS NOT NULL OR e.battle_id IS NOT NULL THEN RAISE EXCEPTION 'NAVAL_IN_BATTLE'; END IF;
  IF e.protected_until>now() OR s.protected_until>now() OR accounts_share_device(p_user,target) THEN RAISE EXCEPTION 'NAVAL_PROTECTED'; END IF;
  IF sqrt(power(e.x-s.x,2)+power(e.y-s.y,2))>500 THEN RAISE EXCEPTION 'NAVAL_OUT_OF_RANGE'; END IF;
  IF EXISTS(SELECT 1 FROM naval_battles WHERE status='won' AND started_at>now()-interval '24 hours' AND ((attacker=p_user AND defender=target) OR(attacker=target AND defender=p_user))) THEN RAISE EXCEPTION 'NAVAL_PAIR_COOLDOWN'; END IF;
  INSERT INTO naval_battles(attacker,defender) VALUES(p_user,target) RETURNING * INTO b;
  UPDATE naval_ships SET battle_id=b.id WHERE user_id IN(p_user,target);
 ELSIF p_action IN('fire','skill','board','escape') THEN
  SELECT * INTO b FROM naval_battles WHERE id=s.battle_id AND status='active' FOR UPDATE;
  IF b.id IS NULL THEN RAISE EXCEPTION 'NAVAL_NO_BATTLE'; END IF;
  target:=CASE WHEN b.attacker=p_user THEN b.defender ELSE b.attacker END;
  SELECT * INTO e FROM naval_ships WHERE user_id=target FOR UPDATE;
  dist:=sqrt(power(e.x-s.x,2)+power(e.y-s.y,2));
  IF p_action='escape' THEN
   IF dist<650 AND e.seen_at>now()-interval '20 seconds' THEN RAISE EXCEPTION 'NAVAL_ESCAPE_DISTANCE'; END IF;
   UPDATE naval_battles SET status='escaped',finished_at=now() WHERE id=b.id;
   UPDATE naval_ships SET battle_id=null,protected_until=now()+interval '2 minutes' WHERE user_id IN(p_user,target);
  ELSE
   IF s.shot_at>now()-interval '2 seconds' THEN RAISE EXCEPTION 'NAVAL_CANNON_COOLDOWN'; END IF;
   IF p_action='skill' AND s.skill_at>now()-interval '20 seconds' THEN RAISE EXCEPTION 'NAVAL_SKILL_COOLDOWN'; END IF;
   IF dist>400+s.level*5 THEN RAISE EXCEPTION 'NAVAL_OUT_OF_RANGE'; END IF;
   angle:=atan2(e.x-s.x,-(e.y-s.y)); delta:=abs(atan2(sin(angle-s.heading),cos(angle-s.heading)));
   IF p_action<>'board' AND abs(delta-pi()/2)>.7 THEN RAISE EXCEPTION 'NAVAL_BROADSIDE_REQUIRED'; END IF;
   IF p_action='board' AND(dist>100 OR e.hp>(1000+(e.level-1)*100)*.25) THEN RAISE EXCEPTION 'NAVAL_BOARD_UNAVAILABLE'; END IF;
   damage:=greatest(10,(100+s.level*8)-(e.level*3));
   IF p_action='skill' THEN damage:=damage*2; END IF;
   IF p_action='board' THEN damage:=damage+70; END IF;
   UPDATE naval_ships SET shot_at=now(),skill_at=CASE WHEN p_action='skill' THEN now() ELSE skill_at END WHERE user_id=p_user;
   UPDATE naval_ships SET hp=greatest(0,hp-damage) WHERE user_id=target;
   INSERT INTO naval_events(battle_id,actor,kind,x,y,target_x,target_y,damage) VALUES(b.id,p_user,p_action,s.x,s.y,e.x,e.y,damage);
   IF e.hp<=damage THEN
    -- Settlement deliberately delegates to a configured allowlisted item pool; absent pool cannot start combat.
    PERFORM 1 FROM game_players WHERE id IN(p_user,target) ORDER BY id FOR UPDATE;
    old_amount:=(SELECT forge_coins FROM game_players WHERE id=target);
    old_amount:=least(coalesce((cfg->>'lootCap')::numeric,0),floor(old_amount*least(10,greatest(0,(cfg->>'lootPercent')::numeric))/100));
    IF old_amount>0 THEN
     INSERT INTO wallet_ledger(user_id,type,amount_fc,balance_before,balance_after,reference_id) SELECT id,'naval_loot',CASE WHEN id=p_user THEN old_amount ELSE -old_amount END,forge_coins,forge_coins+CASE WHEN id=p_user THEN old_amount ELSE -old_amount END,b.id::text FROM game_players WHERE id IN(p_user,target);
     UPDATE game_players SET forge_coins=forge_coins+CASE WHEN id=p_user THEN old_amount ELSE -old_amount END WHERE id IN(p_user,target);
    END IF;
    -- Only ordinary Realm materials explicitly allowlisted by admin can be taken, never heroes/pets/NFTs.
    PERFORM 1 FROM realm_material_balances WHERE user_id IN(p_user,target) ORDER BY user_id,material_id FOR UPDATE;
    b.loot:=jsonb_build_object('berries',old_amount,'items','{}'::jsonb);
    FOR cfg IN SELECT jsonb_build_object('id',r.material_id,'amount',least(3,floor(r.amount*.05))) FROM realm_material_balances r WHERE r.user_id=target AND r.material_id IN(SELECT jsonb_array_elements_text(coalesce((SELECT value->'lootItems' FROM game_settings WHERE key='naval_rules'),'[]'::jsonb))) AND r.amount>=20 LOOP
     cost:=(cfg->>'amount')::integer;
     UPDATE realm_material_balances SET amount=amount-cost,updated_at=now() WHERE user_id=target AND material_id=cfg->>'id';
     INSERT INTO realm_material_balances(user_id,material_id,amount) VALUES(p_user,cfg->>'id',cost) ON CONFLICT(user_id,material_id) DO UPDATE SET amount=realm_material_balances.amount+cost,updated_at=now();
     INSERT INTO realm_material_ledger(user_id,material_id,amount,balance_before,balance_after,reason,source_id) SELECT user_id,material_id,CASE WHEN user_id=p_user THEN cost ELSE -cost END,amount-CASE WHEN user_id=p_user THEN cost ELSE -cost END,amount,'naval_loot',b.id::text FROM realm_material_balances WHERE user_id IN(p_user,target) AND material_id=cfg->>'id';
     b.loot:=jsonb_set(b.loot,ARRAY['items',cfg->>'id'],to_jsonb(cost));
    END LOOP;
    UPDATE naval_battles SET status='won',winner=p_user,loot=b.loot,finished_at=now() WHERE id=b.id;
    UPDATE naval_ships SET battle_id=null,protected_until=now()+interval '30 minutes',xp=xp+CASE WHEN user_id=p_user THEN 50 ELSE 0 END,reputation=reputation+CASE WHEN user_id=p_user THEN 10 ELSE 0 END WHERE user_id IN(p_user,target);
   END IF;
  END IF;
 ELSIF p_action='leave' THEN
  IF s.battle_id IS NOT NULL THEN RAISE EXCEPTION 'NAVAL_IN_BATTLE'; END IF;
  UPDATE naval_ships SET seen_at=now()-interval '1 minute',throttle=0 WHERE user_id=p_user;
 ELSIF p_action<>'state' THEN RAISE EXCEPTION 'NAVAL_INVALID_INPUT';
 END IF;
 RETURN naval_state(p_user);
END $$;
REVOKE ALL ON FUNCTION public.naval_state(uuid), public.naval_action(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_state(uuid), public.naval_action(uuid,text,jsonb) TO service_role;
