ALTER TABLE public.naval_owned_ships ADD COLUMN IF NOT EXISTS cosmetics jsonb NOT NULL DEFAULT '{}'::jsonb;
COMMENT ON COLUMN public.naval_owned_ships.cosmetics IS 'Per-purchased-ship cosmetic choices; never affects naval stats or ownership.';
CREATE OR REPLACE FUNCTION public.naval_fleet_customize(p_user uuid, p_class text, p_cosmetics jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $f$
DECLARE s public.naval_ships; o public.naval_owned_ships; c jsonb; k text; v text;
BEGIN
 IF coalesce((SELECT value='true'::jsonb FROM public.game_settings WHERE key='game_reset_in_progress'),false) THEN RAISE EXCEPTION 'GAME_RESET'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.game_players WHERE id=p_user AND NOT coalesce(banned,false)) THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('naval-world',0));
 SELECT * INTO s FROM public.naval_ships WHERE user_id=p_user FOR UPDATE;
 IF s.user_id IS NULL THEN RAISE EXCEPTION 'FLEET_NOT_OWNED'; END IF;
 IF s.battle_id IS NOT NULL THEN RAISE EXCEPTION 'NAVAL_IN_BATTLE'; END IF;
 SELECT * INTO o FROM public.naval_owned_ships WHERE user_id=p_user AND class_id=p_class FOR UPDATE;
 IF o.class_id IS NULL THEN RAISE EXCEPTION 'FLEET_NOT_OWNED'; END IF;
 IF o.price_paid<=0 THEN RAISE EXCEPTION 'FLEET_PURCHASE_REQUIRED'; END IF;
 IF p_cosmetics IS NULL OR jsonb_typeof(p_cosmetics)<>'object' THEN RAISE EXCEPTION 'FLEET_INVALID_INPUT'; END IF;
 c:=jsonb_build_object('flag','skull','prow','none','decoration','none','trail','foam','hullColor','original','sailColor','original','flagColor','red')||o.cosmetics||p_cosmetics;
 FOR k,v IN SELECT * FROM jsonb_each_text(c) LOOP
   IF v IS NULL OR (CASE k
    WHEN 'flag' THEN v NOT IN('skull','sun','moon')
    WHEN 'prow' THEN v NOT IN('lion','blade','none')
    WHEN 'decoration' THEN v NOT IN('gold','silver','none')
    WHEN 'trail' THEN v NOT IN('foam','embers','mist')
    WHEN 'hullColor' THEN v NOT IN('original','red','blue','green','gold','black','white')
    WHEN 'sailColor' THEN v NOT IN('original','red','blue','green','gold','black','white')
    WHEN 'flagColor' THEN v NOT IN('red','blue','green','gold','black','white')
    ELSE true END) THEN RAISE EXCEPTION 'FLEET_INVALID_INPUT'; END IF;
 END LOOP;
 UPDATE public.naval_owned_ships SET cosmetics=c WHERE user_id=p_user AND class_id=p_class;
 IF s.active_class=p_class THEN UPDATE public.naval_ships SET cosmetics=c WHERE user_id=p_user; END IF;
END $f$;
REVOKE ALL ON FUNCTION public.naval_fleet_customize(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.naval_fleet_customize(uuid,text,jsonb) TO service_role;
DO $patch$
DECLARE d text; old text; start_at int; end_at int;
BEGIN
 d:=pg_get_functiondef('public.naval_fleet_view(uuid)'::regprocedure);
 old:='''allocated'',jsonb_build_object';
 IF position(old in d)=0 THEN RAISE EXCEPTION 'Fleet view patch anchor missing'; END IF;
 d:=replace(d,old,'''canCustomize'',price_paid>0,''cosmetics'',cosmetics,''allocated'',jsonb_build_object'); EXECUTE d;
 d:=pg_get_functiondef('public.naval_fleet(uuid,text,jsonb)'::regprocedure);
 old:='IF p_action=''buy'' THEN';
 IF position(old in d)=0 THEN RAISE EXCEPTION 'Fleet action patch anchor missing'; END IF;
 d:=replace(d,old,'IF p_action=''customize'' THEN PERFORM public.naval_fleet_customize(p_user,cls,p_input->''cosmetics''); RETURN public.naval_fleet_view(p_user); END IF; '||old);
 old:='SET active_class=cls, level=least(50,o.level)';
 IF position(old in d)=0 THEN RAISE EXCEPTION 'Fleet selection patch anchor missing'; END IF;
 d:=replace(d,old,'SET active_class=cls, cosmetics=CASE WHEN o.price_paid>0 THEN jsonb_build_object(''flag'',''skull'',''prow'',''none'',''decoration'',''none'',''trail'',''foam'',''hullColor'',''original'',''sailColor'',''original'',''flagColor'',''red'')||o.cosmetics ELSE jsonb_build_object(''flag'',''skull'',''prow'',''lion'',''decoration'',''gold'',''trail'',''foam'') END, level=least(50,o.level)'); EXECUTE d;
 d:=pg_get_functiondef('public.naval_action(uuid,text,jsonb)'::regprocedure);
 start_at:=position('ELSIF p_action=''customize'' THEN' in d); end_at:=position('ELSIF p_action IN(''repair'',''upgrade'') THEN' in d);
 IF start_at=0 OR end_at<=start_at THEN RAISE EXCEPTION 'Legacy customize patch anchor missing'; END IF;
 d:=substring(d from 1 for start_at-1)||'ELSIF p_action=''customize'' THEN PERFORM public.naval_fleet_customize(p_user,s.active_class,p_input->''cosmetics''); '||substring(d from end_at); EXECUTE d;
 d:=pg_get_functiondef('public.naval_state(uuid)'::regprocedure);
 old:='SELECT n.user_id,n.model,n.skin,n.cosmetics';
 IF position(old in d)=0 THEN RAISE EXCEPTION 'Naval peers patch anchor missing'; END IF;
 d:=replace(d,old,'SELECT n.user_id,n.active_class AS class_id,n.model,n.skin,n.cosmetics'); EXECUTE d;
END $patch$;