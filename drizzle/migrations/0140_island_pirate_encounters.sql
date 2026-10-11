CREATE TABLE public.island_pirate_config (island_index integer PRIMARY KEY CHECK (island_index BETWEEN 0 AND 4), settings jsonb NOT NULL DEFAULT '{}'::jsonb, updated_at timestamptz NOT NULL DEFAULT now());
GRANT ALL ON public.island_pirate_config TO service_role;
ALTER TABLE public.island_pirate_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY island_pirate_config_service ON public.island_pirate_config TO service_role USING (true) WITH CHECK (true);
CREATE TABLE public.island_pirate_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE, island_index integer NOT NULL CHECK (island_index BETWEEN 0 AND 4), game_day date NOT NULL DEFAULT public.game_day_key(), version integer NOT NULL DEFAULT 0, state jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,island_index,game_day));
GRANT ALL ON public.island_pirate_sessions TO service_role;
ALTER TABLE public.island_pirate_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY island_pirate_sessions_service ON public.island_pirate_sessions TO service_role USING (true) WITH CHECK (true);
CREATE TABLE public.island_pirate_claims (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE, session_id uuid NOT NULL REFERENCES public.island_pirate_sessions(id) ON DELETE CASCADE, enemy_id text NOT NULL, reward jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(session_id,enemy_id));
GRANT ALL ON public.island_pirate_claims TO service_role;
ALTER TABLE public.island_pirate_claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY island_pirate_claims_service ON public.island_pirate_claims TO service_role USING (true) WITH CHECK (true);
CREATE OR REPLACE FUNCTION public.island_pirate_guard(p_user uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.game_players WHERE id=p_user AND NOT coalesce(banned,false)) THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
 IF public.setting_bool('game_reset_in_progress',false) THEN RAISE EXCEPTION 'GAME_RESET'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.island_pirate_begin(p_user uuid,p_island integer,p_state jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.island_pirate_sessions; ship public.naval_ships; dx float8; dy float8; gx integer; gy integer; seed integer; near boolean:=false; i record; epoch timestamptz;
BEGIN
 PERFORM public.island_pirate_guard(p_user);
 SELECT * INTO ship FROM public.naval_ships WHERE user_id=p_user;
 IF ship.user_id IS NULL OR ship.battle_id IS NOT NULL OR abs(ship.throttle)>.01 THEN RAISE EXCEPTION 'ISLAND_DOCK_REQUIRED'; END IF;
 FOR i IN SELECT * FROM (VALUES(0,810.0,700.0),(1,1570.0,1260.0),(2,2350.0,850.0),(3,2130.0,1700.0),(4,1080.0,1500.0)) t(idx,x,y) LOOP
 IF i.idx=p_island AND sqrt(power(ship.x-i.x,2)+power(ship.y-i.y,2))<=150 THEN near:=true; END IF;
 END LOOP;
 FOR gx IN floor(ship.x/2400)::int-1..floor(ship.x/2400)::int+1 LOOP FOR gy IN floor(ship.y/2400)::int-1..floor(ship.y/2400)::int+1 LOOP
 IF gx BETWEEN -1 AND 1 AND gy BETWEEN -1 AND 1 THEN CONTINUE; END IF;
 seed:=(((gx::bigint*73+gy::bigint*151)%997+997)%997)::int;
 IF seed%4=0 OR seed%5<>p_island THEN CONTINUE; END IF;
 dx:=gx::float8*2400+600+seed%1200;dy:=gy::float8*2400+600+(seed*37)%1200+180+seed%260+100;
 IF sqrt(power(ship.x-dx,2)+power(ship.y-dy,2))<=150 THEN near:=true; END IF;
 END LOOP; END LOOP;
 IF NOT near THEN RAISE EXCEPTION 'ISLAND_DOCK_REQUIRED'; END IF;
 INSERT INTO public.island_pirate_sessions(user_id,island_index,state) VALUES(p_user,p_island,p_state) ON CONFLICT(user_id,island_index,game_day) DO NOTHING;
 SELECT * INTO s FROM public.island_pirate_sessions WHERE user_id=p_user AND island_index=p_island AND game_day=public.game_day_key();
 SELECT nullif(value#>>'{}','')::timestamptz INTO epoch FROM public.game_settings WHERE key='game_reset_epoch';
 IF epoch IS NOT NULL AND s.created_at<epoch THEN RAISE EXCEPTION 'GAME_RESET'; END IF;
 RETURN to_jsonb(s);
END $$;
CREATE OR REPLACE FUNCTION public.island_pirate_commit(p_user uuid,p_session uuid,p_version integer,p_state jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.island_pirate_sessions; epoch timestamptz;
BEGIN
 PERFORM public.island_pirate_guard(p_user);
 SELECT * INTO s FROM public.island_pirate_sessions WHERE id=p_session AND user_id=p_user FOR UPDATE;
 IF s.id IS NULL OR s.game_day<>public.game_day_key() THEN RAISE EXCEPTION 'ISLAND_SESSION_EXPIRED'; END IF;
 SELECT nullif(value#>>'{}','')::timestamptz INTO epoch FROM public.game_settings WHERE key='game_reset_epoch';
 IF epoch IS NOT NULL AND s.created_at<epoch THEN RAISE EXCEPTION 'GAME_RESET'; END IF;
 IF s.version<>p_version THEN RETURN jsonb_build_object('conflict',true,'session',to_jsonb(s)); END IF;
 UPDATE public.island_pirate_sessions SET state=p_state,version=version+1,updated_at=clock_timestamp() WHERE id=s.id RETURNING * INTO s;
 RETURN jsonb_build_object('conflict',false,'session',to_jsonb(s));
END $$;
CREATE OR REPLACE FUNCTION public.island_pirate_open(p_user uuid,p_session uuid,p_enemy text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.island_pirate_sessions; e jsonb; loot jsonb; receipt public.island_pirate_claims; it jsonb; tpl public.equipment_templates; before_fc numeric; after_fc numeric; qty integer; epoch timestamptz;
BEGIN
 PERFORM public.island_pirate_guard(p_user);
 SELECT * INTO s FROM public.island_pirate_sessions WHERE id=p_session AND user_id=p_user FOR UPDATE;
 IF s.id IS NULL OR s.game_day<>public.game_day_key() THEN RAISE EXCEPTION 'ISLAND_SESSION_EXPIRED'; END IF;
 SELECT nullif(value#>>'{}','')::timestamptz INTO epoch FROM public.game_settings WHERE key='game_reset_epoch';
 IF epoch IS NOT NULL AND s.created_at<epoch THEN RAISE EXCEPTION 'GAME_RESET'; END IF;
 SELECT * INTO receipt FROM public.island_pirate_claims WHERE session_id=s.id AND enemy_id=p_enemy;
 IF receipt.id IS NOT NULL THEN RETURN jsonb_build_object('duplicate',true,'reward',receipt.reward,'session',to_jsonb(s)); END IF;
 SELECT value INTO e FROM jsonb_array_elements(s.state->'enemies') WHERE value->>'id'=p_enemy;
 IF e IS NULL OR (e->>'hp')::numeric>0 OR e->'loot' IS NULL OR (s.state->'player'->>'hp')::numeric<=0 THEN RAISE EXCEPTION 'ISLAND_CHEST_UNAVAILABLE'; END IF;
 IF sqrt(power((s.state->'player'->>'x')::numeric-(e->>'x')::numeric,2)+power((s.state->'player'->>'z')::numeric-(e->>'z')::numeric,2))>4 THEN RAISE EXCEPTION 'ISLAND_OUT_OF_RANGE'; END IF;
 loot:=e->'loot';
 INSERT INTO public.island_pirate_claims(user_id,session_id,enemy_id,reward) VALUES(p_user,s.id,p_enemy,loot) RETURNING * INTO receipt;
 SELECT forge_coins INTO before_fc FROM public.game_players WHERE id=p_user FOR UPDATE;
 after_fc:=before_fc+greatest(0,least(1000,coalesce((loot->>'berries')::numeric,0)));
 UPDATE public.game_players SET forge_coins=after_fc,updated_at=now() WHERE id=p_user;
 INSERT INTO public.wallet_ledger(user_id,type,amount_fc,balance_before,balance_after,reference_id) VALUES(p_user,'island_pirate_loot',after_fc-before_fc,before_fc,after_fc,receipt.id::text);
 FOR it IN SELECT value FROM jsonb_array_elements(coalesce(loot->'items','[]'::jsonb)) LOOP
 qty:=greatest(1,least(3,(it->>'quantity')::int));
 IF it->>'kind'='material' THEN
 IF NOT EXISTS(SELECT 1 FROM public.realm_materials WHERE id=it->>'code') THEN RAISE EXCEPTION 'ISLAND_INVALID_LOOT'; END IF;
 PERFORM public.realm_material_add(p_user,it->>'code',qty,'island_pirate_loot',receipt.id::text);
 ELSIF it->>'kind'='equipment' THEN
 SELECT * INTO tpl FROM public.equipment_templates WHERE id=(it->>'code')::uuid AND is_active AND NOT coalesce(is_nft,false) AND NOT coalesce(veteran_line,false) AND NOT coalesce(founder_line,false) AND rarity IN ('common','uncommon','rare');
 IF tpl.id IS NULL THEN RAISE EXCEPTION 'ISLAND_INVALID_LOOT'; END IF;
 INSERT INTO public.player_equipment(user_id,template_id,level,source,source_ref) VALUES(p_user,tpl.id,1,'island_pirate_loot',receipt.id);
 ELSIF it->>'kind'='exclusive' AND it->>'code'=('island_trophy_'||s.island_index::text) THEN
 INSERT INTO public.player_inventory(user_id,item_type,item_code,quantity,is_exclusive,tradable) VALUES(p_user,'realm',it->>'code',1,true,false) ON CONFLICT(user_id,item_type,item_code) DO UPDATE SET quantity=public.player_inventory.quantity+1,updated_at=now();
 ELSE RAISE EXCEPTION 'ISLAND_INVALID_LOOT'; END IF;
 END LOOP;
 UPDATE public.island_pirate_sessions SET state=jsonb_set(state,'{enemies}',(SELECT jsonb_agg(CASE WHEN value->>'id'=p_enemy THEN value||jsonb_build_object('claimed',true) ELSE value END) FROM jsonb_array_elements(state->'enemies'))),version=version+1,updated_at=clock_timestamp() WHERE id=s.id RETURNING * INTO s;
 RETURN jsonb_build_object('duplicate',false,'reward',loot,'balance',after_fc,'session',to_jsonb(s));
END $$;
REVOKE ALL ON FUNCTION public.island_pirate_guard(uuid),public.island_pirate_begin(uuid,integer,jsonb),public.island_pirate_commit(uuid,uuid,integer,jsonb),public.island_pirate_open(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.island_pirate_guard(uuid),public.island_pirate_begin(uuid,integer,jsonb),public.island_pirate_commit(uuid,uuid,integer,jsonb),public.island_pirate_open(uuid,uuid,text) TO service_role;
COMMENT ON TABLE public.island_pirate_sessions IS 'Server-only, daily per-island NPC encounters; approved poses, cooldowns and single-use chest loot. Browser never writes state.';