CREATE TABLE public.naval_ship_classes(
  id text PRIMARY KEY, name text NOT NULL, rarity text NOT NULL, specialty text NOT NULL, price_ton numeric NOT NULL DEFAULT 0 CHECK(price_ton>=0),
  base_atk integer NOT NULL, base_def integer NOT NULL, base_hp integer NOT NULL, base_spd integer NOT NULL, base_acc integer NOT NULL,
  skill_bonus numeric NOT NULL DEFAULT 0, sort integer NOT NULL, enabled boolean NOT NULL DEFAULT true);
GRANT ALL ON public.naval_ship_classes TO service_role;
ALTER TABLE public.naval_ship_classes ENABLE ROW LEVEL SECURITY;
INSERT INTO public.naval_ship_classes VALUES
 ('marinheiro','Marinheiro','Comum','Equilibrado',0,100,10,1000,120,50,0,1,true),
 ('corsario','Corsário','Raro','Velocidade e esquiva',5,105,12,1050,138,60,0,2,true),
 ('destruidor','Destruidor','Épico','Ataque e canhões',10,135,12,1050,120,65,0,3,true),
 ('imperial','Imperial','Épico','Defesa e resistência',15,100,30,1350,114,50,0,4,true),
 ('fantasma','Fantasma','Lendário','Velocidade e habilidade especial',35,120,18,1150,140,70,0.25,5,true),
 ('rei_dos_mares','Rei dos Mares','Mítico','Poder supremo em todos os atributos',50,140,30,1400,135,75,0.15,6,true);

CREATE TABLE public.naval_upgrade_config(
  category text PRIMARY KEY, name text NOT NULL, stat text NOT NULL, per_level numeric NOT NULL, max_level integer NOT NULL DEFAULT 10 CHECK(max_level BETWEEN 1 AND 50),
  wood_base integer NOT NULL DEFAULT 20, iron_base integer NOT NULL DEFAULT 12, berries_base integer NOT NULL DEFAULT 500, ton_cost numeric NOT NULL DEFAULT 0 CHECK(ton_cost>=0),
  growth numeric NOT NULL DEFAULT 1.35 CHECK(growth>=1), sort integer NOT NULL);
GRANT ALL ON public.naval_upgrade_config TO service_role;
ALTER TABLE public.naval_upgrade_config ENABLE ROW LEVEL SECURITY;
INSERT INTO public.naval_upgrade_config(category,name,stat,per_level,sort) VALUES
 ('cannons','Canhões','atk',15,1),('hull','Casco','hp',150,2),('armor','Blindagem','def',6,3),
 ('sails','Velas e propulsão','spd',3,4),('aim','Sistema de mira','acc',4,5),('core','Núcleo especial','skill',0.05,6);

CREATE TABLE public.naval_fleet_settings(id boolean PRIMARY KEY DEFAULT true CHECK(id), points_per_level integer NOT NULL DEFAULT 5 CHECK(points_per_level BETWEEN 0 AND 50),
  xp_base integer NOT NULL DEFAULT 100 CHECK(xp_base>0), max_level integer NOT NULL DEFAULT 50, respec_enabled boolean NOT NULL DEFAULT false);
GRANT ALL ON public.naval_fleet_settings TO service_role;
ALTER TABLE public.naval_fleet_settings ENABLE ROW LEVEL SECURITY;
INSERT INTO public.naval_fleet_settings DEFAULT VALUES;

CREATE TABLE public.naval_owned_ships(
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE, class_id text NOT NULL REFERENCES public.naval_ship_classes(id),
  level integer NOT NULL DEFAULT 1 CHECK(level>=1), xp integer NOT NULL DEFAULT 0 CHECK(xp>=0), points integer NOT NULL DEFAULT 0 CHECK(points>=0),
  pts_atk integer NOT NULL DEFAULT 0 CHECK(pts_atk>=0), pts_def integer NOT NULL DEFAULT 0 CHECK(pts_def>=0), pts_hp integer NOT NULL DEFAULT 0 CHECK(pts_hp>=0),
  pts_spd integer NOT NULL DEFAULT 0 CHECK(pts_spd>=0), pts_acc integer NOT NULL DEFAULT 0 CHECK(pts_acc>=0),
  upgrades jsonb NOT NULL DEFAULT '{}'::jsonb, price_paid numeric NOT NULL DEFAULT 0, acquired_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,class_id));
GRANT ALL ON public.naval_owned_ships TO service_role;
ALTER TABLE public.naval_owned_ships ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.naval_ships ADD COLUMN IF NOT EXISTS active_class text NOT NULL DEFAULT 'marinheiro' REFERENCES public.naval_ship_classes(id);

CREATE OR REPLACE FUNCTION public.naval_stat(p_user uuid, p_stat text) RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $f$
  WITH a AS (SELECT coalesce((SELECT active_class FROM naval_ships WHERE user_id=p_user),'marinheiro') c),
  o AS (SELECT o.* FROM naval_owned_ships o, a WHERE o.user_id=p_user AND o.class_id=a.c),
  k AS (SELECT k.* FROM naval_ship_classes k, a WHERE k.id=a.c),
  v AS (SELECT k.*, coalesce(o.level,1) lv, coalesce(o.pts_atk,0) pa, coalesce(o.pts_def,0) pd, coalesce(o.pts_hp,0) ph, coalesce(o.pts_spd,0) ps, coalesce(o.pts_acc,0) pc, coalesce(o.upgrades,'{}'::jsonb) u FROM k LEFT JOIN o ON true)
  SELECT CASE p_stat
    WHEN 'atk' THEN base_atk+(lv-1)*8+pa*4+coalesce((u->>'cannons')::int,0)*15
    WHEN 'def' THEN base_def+(lv-1)*3+pd*2+coalesce((u->>'armor')::int,0)*6
    WHEN 'hp'  THEN base_hp+(lv-1)*100+ph*40+coalesce((u->>'hull')::int,0)*150
    WHEN 'spd' THEN least(200,base_spd+(lv-1)+ps+coalesce((u->>'sails')::int,0)*3)
    WHEN 'acc' THEN base_acc+pc*2+coalesce((u->>'aim')::int,0)*4
    WHEN 'skill' THEN skill_bonus+coalesce((u->>'core')::int,0)*0.05
  END FROM v $f$;
REVOKE ALL ON FUNCTION public.naval_stat(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.naval_stat(uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.naval_ship_xp_to_fleet() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $f$
BEGIN
  IF NEW.xp>OLD.xp THEN
    INSERT INTO naval_owned_ships(user_id,class_id) VALUES(NEW.user_id,'marinheiro') ON CONFLICT DO NOTHING;
    UPDATE naval_owned_ships SET xp=xp+(NEW.xp-OLD.xp) WHERE user_id=NEW.user_id AND class_id=NEW.active_class;
    NEW.xp:=OLD.xp;
  END IF;
  RETURN NEW;
END $f$;
REVOKE ALL ON FUNCTION public.naval_ship_xp_to_fleet() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS naval_ship_xp_to_fleet ON public.naval_ships;
CREATE TRIGGER naval_ship_xp_to_fleet BEFORE UPDATE OF xp ON public.naval_ships FOR EACH ROW EXECUTE FUNCTION public.naval_ship_xp_to_fleet();

INSERT INTO public.naval_owned_ships(user_id,class_id,level,xp,points)
  SELECT user_id,'marinheiro',level,xp,(level-1)*5 FROM public.naval_ships ON CONFLICT DO NOTHING;
UPDATE public.naval_ships SET xp=0;

DO $do$
DECLARE d text := pg_get_functiondef('public.naval_action(uuid,text,jsonb)'::regprocedure);
        st text := pg_get_functiondef('public.naval_state(uuid)'::regprocedure);
BEGIN
  d := replace(d,'(120+s.level*2)','naval_stat(s.user_id,''spd'')');
  d := replace(d,'(1000+(e.level-1)*100)','naval_stat(e.user_id,''hp'')');
  d := replace(d,'hp=1000+(level-1+CASE WHEN p_action=''upgrade'' THEN 1 ELSE 0 END)*100','hp=CASE WHEN p_action=''repair'' THEN naval_stat(p_user,''hp'') ELSE hp END');
  d := replace(d,'1000+(s.level-1)*100','naval_stat(s.user_id,''hp'')');
  d := replace(d,'greatest(10,(100+s.level*8)-(e.level*3))','greatest(10,round((naval_stat(s.user_id,''atk'')-naval_stat(e.user_id,''def''))*(0.9+least(150,naval_stat(s.user_id,''acc''))/500.0)))');
  d := replace(d,'damage:=damage*2','damage:=round(damage*(2+naval_stat(s.user_id,''skill'')))');
  IF position('1000+' in d)>0 OR position('s.level*8' in d)>0 THEN RAISE EXCEPTION 'naval_action patch incomplete'; END IF;
  EXECUTE d;
  st := replace(st,'''ship'',to_jsonb(s)','''ship'',to_jsonb(s)||jsonb_build_object(''max_hp'',naval_stat(p_user,''hp''),''class_id'',coalesce(s.active_class,''marinheiro''))');
  IF position('max_hp' in st)=0 THEN RAISE EXCEPTION 'naval_state patch incomplete'; END IF;
  EXECUTE st;
END $do$;

CREATE OR REPLACE FUNCTION public.naval_fleet_view(p_user uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $f$
DECLARE cfg naval_fleet_settings; active text; BEGIN
  SELECT * INTO cfg FROM naval_fleet_settings LIMIT 1;
  SELECT active_class INTO active FROM naval_ships WHERE user_id=p_user;
  RETURN jsonb_build_object(
   'active',coalesce(active,'marinheiro'),
   'settings',jsonb_build_object('pointsPerLevel',cfg.points_per_level,'xpBase',cfg.xp_base,'maxLevel',cfg.max_level,'respecEnabled',cfg.respec_enabled),
   'classes',(SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'rarity',rarity,'specialty',specialty,'priceTon',price_ton,'atk',base_atk,'def',base_def,'hp',base_hp,'spd',base_spd,'acc',base_acc,'skill',skill_bonus) ORDER BY sort) FROM naval_ship_classes WHERE enabled),
   'upgrades',(SELECT jsonb_agg(jsonb_build_object('category',category,'name',name,'stat',stat,'perLevel',per_level,'maxLevel',max_level,'woodBase',wood_base,'ironBase',iron_base,'berriesBase',berries_base,'tonCost',ton_cost,'growth',growth) ORDER BY sort) FROM naval_upgrade_config),
   'owned',coalesce((SELECT jsonb_agg(jsonb_build_object('classId',class_id,'level',level,'xp',xp,'xpNext',level*cfg.xp_base,'points',points,
       'allocated',jsonb_build_object('atk',pts_atk,'def',pts_def,'hp',pts_hp,'spd',pts_spd,'acc',pts_acc),'upgrades',upgrades)) FROM naval_owned_ships WHERE user_id=p_user),'[]'::jsonb),
   'balances',(SELECT jsonb_build_object('ton',greatest(0,coalesce(ton_balance,0)-coalesce(ton_reserved,0)),'berries',coalesce(forge_coins,0)) FROM game_players WHERE id=p_user),
   'materials',coalesce((SELECT jsonb_object_agg(material_id,amount) FROM realm_material_balances WHERE user_id=p_user),'{}'::jsonb));
END $f$;

CREATE OR REPLACE FUNCTION public.naval_fleet(p_user uuid, p_action text, p_input jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $f$
DECLARE cfg naval_fleet_settings; k naval_ship_classes; o naval_owned_ships; u naval_upgrade_config; s naval_ships;
  cls text := p_input->>'classId'; n integer; ok integer; lvl integer; wood integer; iron integer; berries bigint;
  a int; d int; h int; sp int; ac int; bal numeric;
BEGIN
  IF coalesce((SELECT value='true'::jsonb FROM game_settings WHERE key='game_reset_in_progress'),false) THEN RAISE EXCEPTION 'GAME_RESET'; END IF;
  IF NOT EXISTS(SELECT 1 FROM game_players WHERE id=p_user AND NOT coalesce(banned,false)) THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO cfg FROM naval_fleet_settings LIMIT 1;
  INSERT INTO naval_ships(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
  INSERT INTO naval_owned_ships(user_id,class_id) VALUES(p_user,'marinheiro') ON CONFLICT DO NOTHING;
  IF p_action='state' THEN RETURN naval_fleet_view(p_user); END IF;
  IF cls IS NULL OR length(cls)>40 THEN RAISE EXCEPTION 'FLEET_INVALID_INPUT'; END IF;
  SELECT * INTO k FROM naval_ship_classes WHERE id=cls AND enabled; IF k.id IS NULL THEN RAISE EXCEPTION 'FLEET_UNKNOWN_SHIP'; END IF;
  SELECT * INTO s FROM naval_ships WHERE user_id=p_user FOR UPDATE;

  IF p_action='buy' THEN
    INSERT INTO naval_owned_ships(user_id,class_id,price_paid) VALUES(p_user,cls,k.price_ton) ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS ok=ROW_COUNT; IF ok=0 THEN RAISE EXCEPTION 'FLEET_ALREADY_OWNED'; END IF;
    IF k.price_ton>0 THEN
      UPDATE game_players SET ton_balance=ton_balance-k.price_ton WHERE id=p_user AND (coalesce(ton_balance,0)-coalesce(ton_reserved,0))>=k.price_ton RETURNING ton_balance INTO bal;
      IF bal IS NULL THEN RAISE EXCEPTION 'FLEET_TON_REQUIRED'; END IF;
      INSERT INTO ton_reward_ledger(user_id,amount_ton,direction,source_type,source_id,note,balance_after) VALUES(p_user,k.price_ton,'debit','naval_ship',cls,'Compra de navio '||k.name,bal);
    END IF;
    RETURN naval_fleet_view(p_user);
  END IF;

  SELECT * INTO o FROM naval_owned_ships WHERE user_id=p_user AND class_id=cls FOR UPDATE;
  IF o.class_id IS NULL THEN RAISE EXCEPTION 'FLEET_NOT_OWNED'; END IF;

  IF p_action='select' THEN
    IF s.battle_id IS NOT NULL THEN RAISE EXCEPTION 'NAVAL_IN_BATTLE'; END IF;
    UPDATE naval_ships SET active_class=cls, level=least(50,o.level) WHERE user_id=p_user;
    UPDATE naval_ships SET hp=least(hp,naval_stat(p_user,'hp')::int) WHERE user_id=p_user;
  ELSIF p_action='levelup' THEN
    IF o.level>=least(50,cfg.max_level) THEN RAISE EXCEPTION 'FLEET_MAX_LEVEL'; END IF;
    IF o.xp<o.level*cfg.xp_base THEN RAISE EXCEPTION 'NAVAL_XP_REQUIRED'; END IF;
    UPDATE naval_owned_ships SET xp=xp-level*cfg.xp_base, level=level+1, points=points+cfg.points_per_level WHERE user_id=p_user AND class_id=cls;
    IF s.active_class=cls THEN UPDATE naval_ships SET level=o.level+1 WHERE user_id=p_user; END IF;
  ELSIF p_action='allocate' THEN
    a:=coalesce((p_input->>'atk')::int,0); d:=coalesce((p_input->>'def')::int,0); h:=coalesce((p_input->>'hp')::int,0); sp:=coalesce((p_input->>'spd')::int,0); ac:=coalesce((p_input->>'acc')::int,0);
    IF least(a,d,h,sp,ac)<0 OR a+d+h+sp+ac<=0 THEN RAISE EXCEPTION 'FLEET_INVALID_INPUT'; END IF;
    IF a+d+h+sp+ac>o.points THEN RAISE EXCEPTION 'FLEET_POINTS_REQUIRED'; END IF;
    UPDATE naval_owned_ships SET points=points-(a+d+h+sp+ac),pts_atk=pts_atk+a,pts_def=pts_def+d,pts_hp=pts_hp+h,pts_spd=pts_spd+sp,pts_acc=pts_acc+ac WHERE user_id=p_user AND class_id=cls;
  ELSIF p_action='upgrade' THEN
    SELECT * INTO u FROM naval_upgrade_config WHERE category=p_input->>'category'; IF u.category IS NULL THEN RAISE EXCEPTION 'FLEET_INVALID_INPUT'; END IF;
    IF s.battle_id IS NOT NULL THEN RAISE EXCEPTION 'NAVAL_IN_BATTLE'; END IF;
    lvl:=coalesce((o.upgrades->>u.category)::int,0); IF lvl>=u.max_level THEN RAISE EXCEPTION 'FLEET_MAX_LEVEL'; END IF;
    wood:=ceil(u.wood_base*power(u.growth,lvl)); iron:=ceil(u.iron_base*power(u.growth,lvl)); berries:=ceil(u.berries_base*power(u.growth,lvl));
    UPDATE realm_material_balances SET amount=amount-CASE WHEN material_id='magic_wood' THEN wood ELSE iron END,updated_at=now()
      WHERE user_id=p_user AND ((material_id='magic_wood' AND amount>=wood) OR (material_id='iron_ore' AND amount>=iron));
    GET DIAGNOSTICS n=ROW_COUNT; IF n<2 THEN RAISE EXCEPTION 'NAVAL_MATERIALS_REQUIRED'; END IF;
    UPDATE game_players SET forge_coins=forge_coins-berries WHERE id=p_user AND forge_coins>=berries; GET DIAGNOSTICS n=ROW_COUNT; IF n=0 THEN RAISE EXCEPTION 'FLEET_BERRIES_REQUIRED'; END IF;
    IF u.ton_cost>0 THEN
      UPDATE game_players SET ton_balance=ton_balance-u.ton_cost WHERE id=p_user AND (coalesce(ton_balance,0)-coalesce(ton_reserved,0))>=u.ton_cost RETURNING ton_balance INTO bal;
      IF bal IS NULL THEN RAISE EXCEPTION 'FLEET_TON_REQUIRED'; END IF;
      INSERT INTO ton_reward_ledger(user_id,amount_ton,direction,source_type,source_id,note,balance_after) VALUES(p_user,u.ton_cost,'debit','naval_upgrade',cls||':'||u.category,'Melhoria '||u.name,bal);
    END IF;
    UPDATE naval_owned_ships SET upgrades=upgrades||jsonb_build_object(u.category,lvl+1) WHERE user_id=p_user AND class_id=cls;
  ELSE RAISE EXCEPTION 'FLEET_INVALID_INPUT';
  END IF;
  RETURN naval_fleet_view(p_user);
END $f$;
REVOKE ALL ON FUNCTION public.naval_fleet_view(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.naval_fleet(uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.naval_fleet(uuid,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.naval_fleet_view(uuid) TO service_role;