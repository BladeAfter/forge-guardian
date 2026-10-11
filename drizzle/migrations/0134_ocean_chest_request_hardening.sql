CREATE OR REPLACE FUNCTION public.ocean_chest_config_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE k text; cfg jsonb:=NEW.config; region jsonb;
BEGIN
 IF jsonb_typeof(cfg) IS DISTINCT FROM 'object' OR jsonb_typeof(cfg->'enabled') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'OCEAN_INVALID_CONFIG'; END IF;
 FOREACH k IN ARRAY ARRAY['maxActive','minInterval','maxInterval','lifetime','minDistance','collectRadius','cooldown','dailyClaims','dailyTon','monthlyTon'] LOOP
  IF jsonb_typeof(cfg->k) IS DISTINCT FROM 'number' OR (cfg->>k)::numeric<0 OR (cfg->>k)::numeric>10000000 THEN RAISE EXCEPTION 'OCEAN_INVALID_CONFIG'; END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['maxActive','minInterval','maxInterval','lifetime','collectRadius','cooldown','dailyClaims'] LOOP
  IF (cfg->>k)::numeric<>trunc((cfg->>k)::numeric) THEN RAISE EXCEPTION 'OCEAN_INVALID_CONFIG'; END IF;
 END LOOP;
 IF (cfg->>'maxActive')::numeric NOT BETWEEN 1 AND 200 OR (cfg->>'minInterval')::numeric<5 OR (cfg->>'maxInterval')::numeric<(cfg->>'minInterval')::numeric OR (cfg->>'maxInterval')::numeric>86400 OR (cfg->>'lifetime')::numeric NOT BETWEEN 60 AND 86400 OR (cfg->>'minDistance')::numeric<80 OR (cfg->>'collectRadius')::numeric NOT BETWEEN 30 AND 120 OR (cfg->>'cooldown')::numeric NOT BETWEEN 2 AND 86400 OR (cfg->>'dailyClaims')::numeric NOT BETWEEN 1 AND 1000 OR (cfg->>'dailyTon')::numeric>(cfg->>'monthlyTon')::numeric THEN RAISE EXCEPTION 'OCEAN_INVALID_CONFIG'; END IF;
 PERFORM public.ocean_validate_odds(coalesce(cfg->'odds',public.ocean_default_odds()));
 IF cfg->'fallback' IS NOT NULL AND cfg->'fallback'<>'null'::jsonb THEN PERFORM public.ocean_validate_odds(cfg->'fallback',true); END IF;
 IF jsonb_typeof(cfg->'regions') IS DISTINCT FROM 'array' OR jsonb_array_length(cfg->'regions') NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'OCEAN_INVALID_REGION'; END IF;
 FOR region IN SELECT value FROM jsonb_array_elements(cfg->'regions') LOOP
  IF coalesce(region->>'id','') !~ '^[a-z0-9-]{1,40}$' OR coalesce(region->>'rarity','') NOT IN ('common','rare','epic','legendary','mythic') THEN RAISE EXCEPTION 'OCEAN_INVALID_REGION'; END IF;
  FOREACH k IN ARRAY ARRAY['minX','maxX','minY','maxY'] LOOP
   IF jsonb_typeof(region->k) IS DISTINCT FROM 'number' OR abs((region->>k)::numeric)>10000000 THEN RAISE EXCEPTION 'OCEAN_INVALID_REGION'; END IF;
  END LOOP;
  IF (region->>'minX')::numeric>=(region->>'maxX')::numeric OR (region->>'minY')::numeric>=(region->>'maxY')::numeric THEN RAISE EXCEPTION 'OCEAN_INVALID_REGION'; END IF;
  IF region ? 'odds' THEN PERFORM public.ocean_validate_odds(region->'odds'); END IF;
 END LOOP;
 IF cfg->>'eventStartsAt' IS NOT NULL THEN PERFORM (cfg->>'eventStartsAt')::timestamptz; END IF;
 IF cfg->>'eventEndsAt' IS NOT NULL THEN PERFORM (cfg->>'eventEndsAt')::timestamptz; END IF;
 IF cfg->>'eventStartsAt' IS NOT NULL AND cfg->>'eventEndsAt' IS NOT NULL AND (cfg->>'eventStartsAt')::timestamptz>=(cfg->>'eventEndsAt')::timestamptz THEN RAISE EXCEPTION 'OCEAN_INVALID_CONFIG'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER ocean_chest_config_guard BEFORE INSERT OR UPDATE OF config ON public.ocean_chest_control FOR EACH ROW EXECUTE FUNCTION public.ocean_chest_config_guard();
REVOKE ALL ON FUNCTION public.ocean_chest_config_guard() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ocean_chest_config_guard() TO service_role;
CREATE OR REPLACE FUNCTION public.ocean_chest_request(p_user uuid,p_action text DEFAULT 'state',p_id uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE emission text; result jsonb:='{}'::jsonb; ship naval_ships;
BEGIN
 IF p_action NOT IN ('state','claim','salvage') OR p_action IS NULL OR (p_action<>'state' AND p_id IS NULL) THEN RAISE EXCEPTION 'OCEAN_INVALID_INPUT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM game_players WHERE id=p_user AND NOT coalesce(banned,false)) THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('naval-world',0));
 emission:=public.ocean_chest_tick(p_user);
 IF p_action='claim' THEN
  SELECT * INTO ship FROM naval_ships WHERE user_id=p_user FOR UPDATE;
  IF ship.user_id IS NULL OR ship.seen_at<now()-interval '8 seconds' OR public.naval_ocean_land(ship.x,ship.y) THEN
   INSERT INTO public.ocean_chest_audit(user_id,kind,reference,details) VALUES(p_user,'claim_rejected',p_id::text,'{"code":"OCEAN_OUT_OF_RANGE"}');
   RETURN jsonb_build_object('error','OCEAN_OUT_OF_RANGE');
  END IF;
  result:=public.ocean_chest_claim(p_user,p_id);
 ELSIF p_action='salvage' THEN result:=public.ocean_equipment_use(p_user,p_id);
 END IF;
 IF result ? 'error' THEN RETURN result; END IF;
 RETURN public.ocean_chest_view(p_user,emission)||result;
END $$;
REVOKE ALL ON FUNCTION public.ocean_chest_request(uuid,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ocean_chest_request(uuid,text,uuid) TO service_role;
COMMENT ON FUNCTION public.ocean_chest_request(uuid,text,uuid) IS 'Atomic Telegram service request: expiration releases, validated naval pose, claim or salvage and persisted view. No wallet credits or financial workers.';