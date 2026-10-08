-- 0) Audit table -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pet_rarity_mismatch_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope text NOT NULL,
  entity_id uuid,
  pet_id uuid,
  pet_slug text,
  old_rarity text,
  new_rarity text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pet_rarity_mismatch_audit TO service_role;
ALTER TABLE public.pet_rarity_mismatch_audit ENABLE ROW LEVEL SECURITY;

-- 1) Official rarity for the 9 legacy pets --------------------------------
UPDATE public.pets SET rarity = v.r, updated_at = now()
FROM (VALUES ('pyron','common'),('glacius','rare'),('lumia','legendary'),
             ('noctis','epic'),('ignara','rare'),('astra','epic'),
             ('aureon','epic'),('bastion','rare'),('season-1-drakoryn','legendary')
     ) AS v(slug, r)
WHERE public.pets.slug = v.slug AND public.pets.rarity IS NULL;

-- any other pet without rarity falls back to common
UPDATE public.pets SET rarity = 'common', updated_at = now() WHERE rarity IS NULL;

ALTER TABLE public.pets ALTER COLUMN rarity SET DEFAULT 'common';
ALTER TABLE public.pets ALTER COLUMN rarity SET NOT NULL;

-- 2) Audit + repair player copies ----------------------------------------
INSERT INTO public.pet_rarity_mismatch_audit(scope, entity_id, pet_id, pet_slug, old_rarity, new_rarity, note)
SELECT 'player_pets', pp.id, p.id, p.slug, pp.rarity, p.rarity, 'sincronizado com o template do pet'
FROM public.player_pets pp JOIN public.pets p ON p.id = pp.pet_id
WHERE coalesce(pp.rarity,'') <> p.rarity;

UPDATE public.player_pets pp SET rarity = p.rarity, updated_at = now()
FROM public.pets p WHERE p.id = pp.pet_id AND coalesce(pp.rarity,'') <> p.rarity;

-- 3) Audit + repair egg/chest pools --------------------------------------
INSERT INTO public.pet_rarity_mismatch_audit(scope, entity_id, pet_id, pet_slug, old_rarity, new_rarity, note)
SELECT 'reward_pet_pool', rp.id, p.id, p.slug, rp.rarity, p.rarity,
       'pool ' || rp.source_type || ':' || rp.source_key || ' corrigido para a raridade do template'
FROM public.reward_pet_pool rp JOIN public.pets p ON p.id = rp.pet_id
WHERE coalesce(rp.rarity,'') <> p.rarity;

-- move entries to the right rarity bucket, dropping duplicates that would collide
DELETE FROM public.reward_pet_pool rp
USING (
  SELECT rp2.id,
         row_number() OVER (PARTITION BY rp2.source_type, rp2.source_key, rp2.pet_id
                            ORDER BY (rp2.rarity = p2.rarity) DESC, rp2.id) AS rn
  FROM public.reward_pet_pool rp2 JOIN public.pets p2 ON p2.id = rp2.pet_id
) d
WHERE d.id = rp.id AND d.rn > 1;

UPDATE public.reward_pet_pool rp SET rarity = p.rarity
FROM public.pets p WHERE p.id = rp.pet_id AND coalesce(rp.rarity,'') <> p.rarity;

-- 4) Hard guards ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_player_pet_rarity()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
DECLARE v_r text;
BEGIN
  SELECT rarity INTO v_r FROM public.pets WHERE id = NEW.pet_id;
  IF v_r IS NULL THEN RAISE EXCEPTION 'PET_NOT_FOUND'; END IF;
  NEW.rarity := v_r; -- template is the single source of truth
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_player_pets_rarity ON public.player_pets;
CREATE TRIGGER trg_player_pets_rarity BEFORE INSERT OR UPDATE OF rarity, pet_id ON public.player_pets
FOR EACH ROW EXECUTE FUNCTION public.enforce_player_pet_rarity();

CREATE OR REPLACE FUNCTION public.enforce_pet_pool_rarity()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
DECLARE v_r text; v_name text;
BEGIN
  SELECT rarity, name INTO v_r, v_name FROM public.pets WHERE id = NEW.pet_id;
  IF v_r IS NULL THEN RAISE EXCEPTION 'PET_NOT_FOUND'; END IF;
  IF public.normalize_pet_rarity(NEW.rarity) <> v_r THEN
    RAISE EXCEPTION 'PET_RARITY_MISMATCH: % is % and cannot be added to % pool',
      v_name, upper(v_r), upper(coalesce(NEW.rarity,'?'));
  END IF;
  NEW.rarity := v_r;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_reward_pet_pool_rarity ON public.reward_pet_pool;
CREATE TRIGGER trg_reward_pet_pool_rarity BEFORE INSERT OR UPDATE OF rarity, pet_id ON public.reward_pet_pool
FOR EACH ROW EXECUTE FUNCTION public.enforce_pet_pool_rarity();

-- keep pools/copies in sync if an admin legitimately changes a template rarity
CREATE OR REPLACE FUNCTION public.sync_pet_rarity_cascade()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.rarity IS DISTINCT FROM OLD.rarity THEN
    UPDATE public.player_pets SET rarity = NEW.rarity, updated_at = now() WHERE pet_id = NEW.id;
    DELETE FROM public.reward_pet_pool rp USING public.reward_pet_pool ok
      WHERE rp.pet_id = NEW.id AND rp.rarity <> NEW.rarity
        AND ok.source_type = rp.source_type AND ok.source_key = rp.source_key
        AND ok.pet_id = rp.pet_id AND ok.rarity = NEW.rarity;
    UPDATE public.reward_pet_pool SET rarity = NEW.rarity WHERE pet_id = NEW.id AND rarity <> NEW.rarity;
    INSERT INTO public.pet_rarity_mismatch_audit(scope, pet_id, pet_slug, old_rarity, new_rarity, note)
    VALUES ('template_change', NEW.id, NEW.slug, OLD.rarity, NEW.rarity, 'raridade oficial alterada pelo admin');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_pets_rarity_cascade ON public.pets;
CREATE TRIGGER trg_pets_rarity_cascade AFTER UPDATE OF rarity ON public.pets
FOR EACH ROW EXECUTE FUNCTION public.sync_pet_rarity_cascade();

-- 5) Selection always keyed on the template rarity ------------------------
CREATE OR REPLACE FUNCTION public.pick_pet_for_source(p_source_type text, p_source_key text, p_rarity text, p_seed text)
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
declare total numeric; roll numeric; acc numeric:=0; r record; chosen uuid; rar text;
begin
  rar := public.normalize_pet_rarity(p_rarity);
  select coalesce(sum(rp.weight),0) into total from public.reward_pet_pool rp
    join public.pets p on p.id = rp.pet_id
   where rp.source_type=p_source_type and rp.source_key=p_source_key
     and rp.enabled and p.is_enabled and p.rarity = rar;
  if total <= 0 then return null; end if;
  roll := (hashtextextended(p_seed||':'||rar,0) & 2147483647)::numeric / 2147483647.0 * total;
  for r in select rp.pet_id, rp.weight from public.reward_pet_pool rp
      join public.pets p on p.id = rp.pet_id
     where rp.source_type=p_source_type and rp.source_key=p_source_key
       and rp.enabled and p.is_enabled and p.rarity = rar
     order by rp.pet_id loop
    acc := acc + r.weight;
    if chosen is null and roll < acc then chosen := r.pet_id; end if;
  end loop;
  return chosen;
end $$;

-- 6) Egg hatching: roll rarity, then pick a pet that already IS that rarity
CREATE OR REPLACE FUNCTION public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed_text text;
  rar text; picked pets%rowtype; picked_id uuid; existing player_pets%rowtype; prior pet_hatch_history%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0; new_pet_id uuid; is_new_pet boolean:=false; has_pool boolean;
begin
  if length(trim(p_idempotency_key))<8 or length(p_idempotency_key)>180 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_idempotency_key,0));
  select * into prior from pet_hatch_history
   where user_id=u and (opening_id=p_idempotency_key or idempotency_key=p_idempotency_key)
   order by created_at desc limit 1;
  if prior.id is not null then
    return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
  end if;

  select * into egg from pet_eggs where id=p_egg_id and is_enabled;
  if egg.id is null then raise exception 'EGG_NOT_FOUND'; end if;
  if abs(coalesce((select sum(value::numeric) from jsonb_each_text(egg.rarity_rates)),0)-100)>0.0001 then
    raise exception 'EGG_RATES_INVALID';
  end if;
  select * into inv from player_pet_inventory where user_id=u and item_type='egg' and item_id=p_egg_id for update;
  if inv.id is null or inv.quantity<1 then raise exception 'EGG_NOT_OWNED'; end if;

  seed_text:=forge_random_seed(p_idempotency_key);
  luck:=least(10,coalesce((get_pet_bonuses(u)->>'egg_luck_percent')::numeric,0));
  rar:=public.normalize_pet_rarity(roll_rarity_from_rates(egg.rarity_rates,luck));

  select exists(select 1 from reward_pet_pool rp join pets p on p.id=rp.pet_id
     where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled) into has_pool;

  if has_pool then
    -- Stage 2: only pets whose OWN template rarity equals the rolled rarity.
    picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
    if picked_id is null then
      -- no pet of that rarity in this egg: re-target the closest rarity that actually has pets
      select p.rarity into rar from reward_pet_pool rp join pets p on p.id=rp.pet_id
        where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled
        order by abs(pet_rarity_order(p.rarity) - pet_rarity_order(rar)), pet_rarity_order(p.rarity) desc limit 1;
      picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
    end if;
    select * into picked from pets where id = picked_id;
  else
    -- Legacy eggs without an explicit pool: still restricted to the rolled rarity.
    select * into picked from pets p
      where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = rar
        and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
      order by hashtextextended(p.id::text||seed_text,0) limit 1;
    if picked.id is null then
      -- fall back to the closest rarity that has eligible pets (rarity of the pet is never rewritten)
      select p.rarity into rar from pets p
        where p.is_enabled and p.availability_type = 'NORMAL'
          and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
        order by abs(pet_rarity_order(p.rarity) - pet_rarity_order(rar)), pet_rarity_order(p.rarity) desc limit 1;
      select * into picked from pets p
        where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = rar
          and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
        order by hashtextextended(p.id::text||seed_text,0) limit 1;
    end if;
  end if;
  if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;
  rar := picked.rarity; -- the pet defines the rarity, never the roll

  update player_pet_inventory set quantity=quantity-1,updated_at=now() where id=inv.id;

  select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
  if existing.id is not null then
    select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';
    update player_pets set fragments=fragments+frags,updated_at=now() where id=existing.id;
    new_pet_id:=existing.id; is_new_pet:=false;
  else
    insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar) returning id into new_pet_id;
    frags:=0; is_new_pet:=true;
  end if;

  insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key,opening_id,status,completed_at,is_new,result_player_pet_id)
    values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key,p_idempotency_key,'completed',now(),is_new_pet,new_pet_id) returning id into history_id;
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
    values(u,p_telegram_id,'egg',egg.slug,'pet_egg',rar,picked.id,picked.name);
  select * into prior from pet_hatch_history where id=history_id;
  return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
end $$;

-- 7) Admin grant always uses the template rarity --------------------------
CREATE OR REPLACE FUNCTION public.admin_grant_pet(p_admin_id bigint, p_ref text, p_pet_slug text, p_rarity text DEFAULT NULL::text, p_level integer DEFAULT 1, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid; pt public.pets; v_id uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO pt FROM public.pets WHERE slug = p_pet_slug OR id::text = p_pet_slug;
  IF pt.id IS NULL THEN RAISE EXCEPTION 'pet_not_found'; END IF;
  -- p_rarity is ignored on purpose: the pet template owns its rarity.
  INSERT INTO public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active)
  VALUES (v_uid, pt.id, pt.rarity, GREATEST(1, COALESCE(p_level,1)), 0, 'baby', 0, false)
  RETURNING id INTO v_id;
  PERFORM public.admin_log(p_admin_id,'pet.grant','player',v_uid::text,NULL,
    jsonb_build_object('player_pet_id',v_id,'pet',pt.slug,'rarity',pt.rarity), p_reason);
  RETURN jsonb_build_object('user_id',v_uid,'player_pet_id',v_id,'pet',pt.name,'rarity',pt.rarity);
END; $$;

-- 8) Season exclusive egg keeps the target pet's own rarity ---------------
CREATE OR REPLACE FUNCTION public.open_season_mythic_egg(p_telegram_id bigint, p_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare u uuid; i player_inventory%rowtype; e season_exclusive_rewards%rowtype; existing uuid; k text; pp uuid; v_rar text;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  select * into i from player_inventory where id=p_item_id and user_id=u and is_exclusive and item_type='pet_egg' and quantity>0 for update;
  if i.id is null then raise exception 'MYTHIC_EGG_NOT_OWNED'; end if;
  select * into e from season_exclusive_rewards where season_id=i.season_id and reward_code=i.exclusive_reward_code and reward_kind='mythic_egg' and enabled;
  k:='season_pass_exclusive_pet:'||e.season_id||':'||u||':legendary';
  select id into existing from season_exclusive_deliveries where idempotency_key=k;
  if existing is not null then raise exception 'MYTHIC_EGG_ALREADY_OPENED'; end if;
  select rarity into v_rar from pets where id=e.target_pet_id;
  if v_rar is null then raise exception 'PET_NOT_FOUND'; end if;
  update player_inventory set quantity=quantity-1 where id=i.id;
  insert into player_pets(user_id,pet_id,rarity,level,xp,evolution_stage,is_season_exclusive,exclusive_season_id,exclusive_badge,tradable)
    values(u,e.target_pet_id,v_rar,1,0,'baby',true,e.season_id,e.badge,false) returning id into pp;
  insert into season_exclusive_deliveries(season_id,user_id,reward_id,delivery_kind,idempotency_key)
    values(e.season_id,u,e.id,'pet',k);
  return jsonb_build_object('playerPetId',pp,'petId',e.target_pet_id,'name',e.display_name,'rarity',v_rar,'level',1,'xp',0,'evolutionStage','baby','badge',e.badge,'image',e.image_url);
end $$;

-- 9) Audit report helper for the admin bot --------------------------------
CREATE OR REPLACE FUNCTION public.admin_pet_rarity_audit(p_admin_id bigint, p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
    'open_player_mismatches', (SELECT count(*) FROM public.player_pets pp JOIN public.pets p ON p.id=pp.pet_id WHERE coalesce(pp.rarity,'') <> p.rarity),
    'open_pool_mismatches', (SELECT count(*) FROM public.reward_pet_pool rp JOIN public.pets p ON p.id=rp.pet_id WHERE coalesce(rp.rarity,'') <> p.rarity),
    'by_rarity', (SELECT jsonb_object_agg(rarity, n) FROM (SELECT rarity, count(*) n FROM public.pets WHERE is_enabled GROUP BY rarity) t),
    'recent', COALESCE((SELECT jsonb_agg(x) FROM (
        SELECT scope, pet_slug, old_rarity, new_rarity, note, created_at
        FROM public.pet_rarity_mismatch_audit ORDER BY created_at DESC LIMIT GREATEST(1, COALESCE(p_limit,20))) x), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.admin_pet_rarity_audit(bigint, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_pet_rarity_audit(bigint, integer) TO service_role;