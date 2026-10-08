-- =========================================================
-- PET CMS: rarities (+ MYTHIC), attribute pool, source pools
-- =========================================================

CREATE TABLE IF NOT EXISTS public.pet_rarity_config (
  rarity text PRIMARY KEY,
  label text NOT NULL,
  label_pt text NOT NULL,
  sort_order integer NOT NULL,
  multiplier numeric NOT NULL DEFAULT 1,
  power integer NOT NULL DEFAULT 500,
  attr_min numeric NOT NULL DEFAULT 3,
  attr_max numeric NOT NULL DEFAULT 5,
  color_primary text NOT NULL DEFAULT '#9ca3af',
  color_secondary text NOT NULL DEFAULT '#f8fafc',
  glow text NOT NULL DEFAULT 'rgba(156,163,175,.45)',
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.pet_rarity_config TO authenticated, anon;
GRANT ALL ON public.pet_rarity_config TO service_role;
ALTER TABLE public.pet_rarity_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Rarity config is public read" ON public.pet_rarity_config;
CREATE POLICY "Rarity config is public read" ON public.pet_rarity_config FOR SELECT USING (true);

INSERT INTO public.pet_rarity_config (rarity,label,label_pt,sort_order,multiplier,power,attr_min,attr_max,color_primary,color_secondary,glow) VALUES
  ('common','COMMON','COMUM',1,1,500,3,5,'#9ca3af','#f8fafc','rgba(156,163,175,.45)'),
  ('uncommon','UNCOMMON','INCOMUM',2,1.25,1000,5,8,'#22c55e','#86efac','rgba(34,197,94,.50)'),
  ('rare','RARE','RARO',3,1.6,2000,8,12,'#38bdf8','#93c5fd','rgba(56,189,248,.55)'),
  ('epic','EPIC','ÉPICO',4,2.1,4000,12,18,'#a855f7','#d8b4fe','rgba(168,85,247,.60)'),
  ('legendary','LEGENDARY','LENDÁRIO',5,2.8,8000,18,25,'#facc15','#fde68a','rgba(250,204,21,.70)'),
  ('mythic','MYTHIC','MÍTICO',6,3.2,12000,25,35,'#be123c','#f0b429','rgba(190,18,60,.72)'),
  ('ancestral','ANCESTRAL','ANCESTRAL',7,3.6,16000,30,40,'#ef4444','#fbbf24','rgba(239,68,68,.78)')
ON CONFLICT (rarity) DO NOTHING;

-- Attribute pool used to auto-roll a pet's signature bonus
CREATE TABLE IF NOT EXISTS public.pet_attribute_pool (
  buff_key text PRIMARY KEY,
  label text NOT NULL,
  allowed_rarities jsonb NOT NULL DEFAULT '[]'::jsonb, -- [] = every rarity
  weight integer NOT NULL DEFAULT 100 CHECK (weight >= 0),
  min_override numeric,
  max_override numeric,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.pet_attribute_pool TO authenticated;
GRANT ALL ON public.pet_attribute_pool TO service_role;
ALTER TABLE public.pet_attribute_pool ENABLE ROW LEVEL SECURITY;

INSERT INTO public.pet_attribute_pool (buff_key,label,weight) VALUES
  ('boss_damage_percent','Dano contra o Chefe',100),
  ('team_hp_percent','HP da equipe',100),
  ('team_attack_percent','Ataque da equipe',90),
  ('defense_percent','Defesa',90),
  ('pvp_attack_percent','Ataque na Arena',80),
  ('pvp_defense_percent','Defesa na Arena',80),
  ('pvp_speed_percent','Velocidade na Arena',60),
  ('critical_chance_percent','Chance de crítico',60),
  ('critical_damage_percent','Dano crítico',60),
  ('farm_fc_percent','Ganho de FC',100),
  ('offline_production_percent','Produção offline',70),
  ('mission_reward_percent','Recompensa de missões',70),
  ('reward_percent','Recompensas gerais',70),
  ('drop_chance_percent','Chance de itens raros',60),
  ('egg_luck_percent','Sorte em ovos',40),
  ('hero_xp_percent','XP dos heróis',80),
  ('account_xp_percent','XP da conta',60),
  ('revive_speed_percent','Velocidade de reanimação',50)
ON CONFLICT (buff_key) DO NOTHING;

-- Catalog-level pet metadata
ALTER TABLE public.pets
  ADD COLUMN IF NOT EXISTS rarity text,
  ADD COLUMN IF NOT EXISTS availability_type text NOT NULL DEFAULT 'NORMAL',
  ADD COLUMN IF NOT EXISTS show_in_catalog boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS hide_name_until_discovered boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS obtainable_from jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS primary_attribute_key text,
  ADD COLUMN IF NOT EXISTS primary_attribute_value numeric;

DO $$ BEGIN
  ALTER TABLE public.pets ADD CONSTRAINT pets_availability_type_check
    CHECK (availability_type IN ('NORMAL','LIMITED','EVENT','MYTHIC_EXCLUSIVE','ADMIN_ONLY'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Explicit reward pools (source -> creature). Eggs today, chests/events later.
CREATE TABLE IF NOT EXISTS public.reward_pet_pool (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text NOT NULL CHECK (source_type IN ('EGG','CHEST','EVENT','BATTLE_PASS','CLAN_BOSS','GLOBAL_BOSS','PVP','ADMIN_GIFT')),
  source_key text NOT NULL,
  pet_id uuid NOT NULL REFERENCES public.pets(id) ON DELETE CASCADE,
  rarity text NOT NULL,
  weight integer NOT NULL DEFAULT 100 CHECK (weight >= 0),
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_type, source_key, pet_id, rarity)
);
CREATE INDEX IF NOT EXISTS reward_pet_pool_source_idx ON public.reward_pet_pool (source_type, source_key, rarity) WHERE enabled;
GRANT ALL ON public.reward_pet_pool TO service_role;
ALTER TABLE public.reward_pet_pool ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS reward_pet_pool_touch ON public.reward_pet_pool;
CREATE TRIGGER reward_pet_pool_touch BEFORE UPDATE ON public.reward_pet_pool
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================
-- Rarity helpers now aware of mythic/ancestral
-- =========================================================
CREATE OR REPLACE FUNCTION public.normalize_pet_rarity(v text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  select case lower(trim(coalesce(v,'common')))
    when 'uncommon' then 'uncommon' when 'incomum' then 'uncommon'
    when 'rare' then 'rare' when 'raro' then 'rare' when 'rara' then 'rare'
    when 'epic' then 'epic' when 'epico' then 'epic' when 'épico' then 'epic' when 'epica' then 'epic' when 'épica' then 'epic'
    when 'legendary' then 'legendary' when 'lendario' then 'legendary' when 'lendário' then 'legendary' when 'lendaria' then 'legendary' when 'lendária' then 'legendary'
    when 'mythic' then 'mythic' when 'mitico' then 'mythic' when 'mítico' then 'mythic' when 'mitica' then 'mythic' when 'mítica' then 'mythic'
    when 'ancestral' then 'ancestral'
    else 'common' end
$$;

CREATE OR REPLACE FUNCTION public.pet_rarity_multiplier(v text)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public AS $$
  select coalesce((select c.multiplier from public.pet_rarity_config c where c.rarity = public.normalize_pet_rarity(v)), 1)
$$;

CREATE OR REPLACE FUNCTION public.pet_rarity_order(v text)
RETURNS integer LANGUAGE sql STABLE SET search_path = public AS $$
  select coalesce((select c.sort_order from public.pet_rarity_config c where c.rarity = public.normalize_pet_rarity(v)), 1)
$$;

CREATE OR REPLACE FUNCTION public.roll_rarity_from_rates(p_rates jsonb, p_luck numeric DEFAULT 0)
RETURNS text LANGUAGE plpgsql SET search_path = public AS $$
declare roll numeric; cursor_v numeric:=0; k text; rate numeric; rar text; allowed text[]:=array[]::text[];
begin
  roll:=least(99.999,random()*100+greatest(0,coalesce(p_luck,0)));
  for k in select c.rarity from public.pet_rarity_config c where c.enabled order by c.sort_order loop
    rate:=coalesce((p_rates->>k)::numeric,0);
    if rate>0 then
      allowed:=allowed||k; cursor_v:=cursor_v+rate;
      if rar is null and roll<cursor_v then rar:=k; end if;
    end if;
  end loop;
  return coalesce(rar,allowed[array_length(allowed,1)],'common');
end $$;

-- =========================================================
-- Two-stage hatch: rarity -> weighted pet inside that rarity pool
-- =========================================================
CREATE OR REPLACE FUNCTION public.pick_pet_for_source(p_source_type text, p_source_key text, p_rarity text, p_seed text)
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path = public AS $$
declare total numeric; roll numeric; acc numeric:=0; r record; chosen uuid;
begin
  select coalesce(sum(rp.weight),0) into total from public.reward_pet_pool rp
    join public.pets p on p.id = rp.pet_id
   where rp.source_type=p_source_type and rp.source_key=p_source_key
     and rp.rarity=p_rarity and rp.enabled and p.is_enabled;
  if total <= 0 then return null; end if;
  roll := (hashtextextended(p_seed||':'||p_rarity,0) & 2147483647)::numeric / 2147483647.0 * total;
  for r in select rp.pet_id, rp.weight from public.reward_pet_pool rp
      join public.pets p on p.id = rp.pet_id
     where rp.source_type=p_source_type and rp.source_key=p_source_key
       and rp.rarity=p_rarity and rp.enabled and p.is_enabled
     order by rp.pet_id loop
    acc := acc + r.weight;
    if chosen is null and roll < acc then chosen := r.pet_id; end if;
  end loop;
  return chosen;
end $$;

CREATE OR REPLACE FUNCTION public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
  rar:=lower(trim(roll_rarity_from_rates(egg.rarity_rates,luck)));

  select exists(select 1 from reward_pet_pool rp join pets p on p.id=rp.pet_id
     where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled) into has_pool;

  if has_pool then
    -- Stage 2: explicit pool for the rolled rarity, then fall back to the closest configured rarity.
    picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
    if picked_id is null then
      select rp.rarity into rar from reward_pet_pool rp join pets p on p.id=rp.pet_id
        where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled
        order by abs(pet_rarity_order(rp.rarity) - pet_rarity_order(rar)), pet_rarity_order(rp.rarity) desc limit 1;
      picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
    end if;
    select * into picked from pets where id = picked_id;
  else
    -- Legacy behaviour: any enabled, generally-obtainable pet allowed by the egg categories.
    select * into picked from pets p
      where p.is_enabled and p.availability_type = 'NORMAL'
        and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
        and (p.rarity is null or p.rarity = rar)
      order by hashtextextended(p.id::text||seed_text,0) limit 1;
    if picked.id is null then
      select * into picked from pets p
        where p.is_enabled and p.availability_type = 'NORMAL'
          and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
        order by hashtextextended(p.id::text||seed_text,0) limit 1;
    end if;
  end if;
  if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;
  if picked.rarity is not null then rar := picked.rarity; end if;

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

-- =========================================================
-- Admin CMS RPCs
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_pet_rarities(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN coalesce((select jsonb_agg(to_jsonb(c) order by c.sort_order) from public.pet_rarity_config c),'[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_roll_pet_attribute(p_admin_id bigint, p_rarity text, p_exclude text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r text; cfg public.pet_rarity_config; total numeric; roll numeric; acc numeric:=0; row_a record; chosen record; lo numeric; hi numeric; val numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  r := public.normalize_pet_rarity(p_rarity);
  SELECT * INTO cfg FROM public.pet_rarity_config WHERE rarity = r;
  SELECT coalesce(sum(a.weight),0) INTO total FROM public.pet_attribute_pool a
    WHERE a.enabled AND (a.allowed_rarities = '[]'::jsonb OR a.allowed_rarities ? r)
      AND (p_exclude IS NULL OR a.buff_key <> p_exclude);
  IF total <= 0 THEN
    SELECT coalesce(sum(a.weight),0) INTO total FROM public.pet_attribute_pool a WHERE a.enabled;
  END IF;
  IF total <= 0 THEN RAISE EXCEPTION 'ATTRIBUTE_POOL_EMPTY'; END IF;
  roll := random() * total;
  FOR row_a IN SELECT * FROM public.pet_attribute_pool a
      WHERE a.enabled AND (a.allowed_rarities = '[]'::jsonb OR a.allowed_rarities ? r)
        AND (p_exclude IS NULL OR a.buff_key <> p_exclude)
      ORDER BY a.buff_key LOOP
    acc := acc + row_a.weight;
    IF chosen IS NULL AND roll < acc THEN chosen := row_a; END IF;
  END LOOP;
  IF chosen IS NULL THEN
    SELECT * INTO chosen FROM public.pet_attribute_pool WHERE enabled ORDER BY random() LIMIT 1;
  END IF;
  lo := coalesce(chosen.min_override, cfg.attr_min, 3);
  hi := greatest(lo, coalesce(chosen.max_override, cfg.attr_max, 5));
  val := round((lo + random() * (hi - lo))::numeric, 0);
  RETURN jsonb_build_object('key', chosen.buff_key, 'label', chosen.label, 'value', val, 'rarity', r, 'min', lo, 'max', hi);
END $$;

CREATE OR REPLACE FUNCTION public.admin_create_pet_visual(
  p_admin_id bigint, p_name text, p_image_url text, p_rarity text,
  p_attribute_key text, p_attribute_value numeric,
  p_category text DEFAULT 'beast', p_sources jsonb DEFAULT '[]'::jsonb,
  p_availability text DEFAULT 'NORMAL', p_show_in_catalog boolean DEFAULT true,
  p_description text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_slug text; v_base text; n int:=1; v_rarity text; v_id uuid; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF coalesce(trim(p_name),'') = '' THEN RAISE EXCEPTION 'PET_NAME_REQUIRED'; END IF;
  IF coalesce(trim(p_image_url),'') = '' THEN RAISE EXCEPTION 'PET_IMAGE_REQUIRED'; END IF;
  v_rarity := public.normalize_pet_rarity(p_rarity);
  IF NOT EXISTS (SELECT 1 FROM public.pet_rarity_config WHERE rarity = v_rarity) THEN RAISE EXCEPTION 'INVALID_RARITY'; END IF;
  IF coalesce(p_attribute_value,0) <= 0 OR coalesce(trim(p_attribute_key),'') = '' THEN RAISE EXCEPTION 'ATTRIBUTE_REQUIRED'; END IF;

  v_base := regexp_replace(lower(unaccent_fallback(trim(p_name))), '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  IF v_base = '' THEN v_base := 'pet'; END IF;
  v_slug := v_base;
  WHILE EXISTS (SELECT 1 FROM public.pets WHERE slug = v_slug) LOOP
    n := n + 1; v_slug := v_base || '-' || n;
  END LOOP;

  INSERT INTO public.pets (name, slug, species, category, description, base_passives,
      image_baby_url, image_young_url, image_adult_url, image_ancestral_url,
      is_enabled, rarity, availability_type, show_in_catalog, obtainable_from,
      primary_attribute_key, primary_attribute_value)
  VALUES (trim(p_name), v_slug, coalesce(nullif(trim(p_category),''),'beast'), coalesce(nullif(trim(p_category),''),'beast'),
      p_description, jsonb_build_object(p_attribute_key, p_attribute_value),
      p_image_url, p_image_url, p_image_url, p_image_url,
      true, v_rarity, coalesce(p_availability,'NORMAL'), coalesce(p_show_in_catalog,true), coalesce(p_sources,'[]'::jsonb),
      p_attribute_key, p_attribute_value)
  RETURNING id INTO v_id;

  SELECT to_jsonb(p) INTO v_new FROM public.pets p WHERE p.id = v_id;
  PERFORM public.admin_log(p_admin_id,'PET_CREATED','pet',v_id::text,NULL,v_new,'editor visual');
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END $$;

-- Slug helper that survives accented names without the unaccent extension.
CREATE OR REPLACE FUNCTION public.unaccent_fallback(v text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  select translate(coalesce(v,''),
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')
$$;

CREATE OR REPLACE FUNCTION public.admin_update_pet_visual(p_admin_id bigint, p_pet_id uuid, p_patch jsonb, p_reason text DEFAULT 'editor visual')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb; v_img text; v_rarity text; v_key text; v_val numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(p) INTO v_old FROM public.pets p WHERE p.id = p_pet_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'PET_NOT_FOUND'; END IF;
  v_img := p_patch->>'image_url';
  v_rarity := CASE WHEN p_patch ? 'rarity' THEN public.normalize_pet_rarity(p_patch->>'rarity') END;
  v_key := p_patch->>'primary_attribute_key';
  v_val := CASE WHEN p_patch ? 'primary_attribute_value' THEN (p_patch->>'primary_attribute_value')::numeric END;

  UPDATE public.pets p SET
    name = coalesce(nullif(trim(coalesce(p_patch->>'name','')),''), p.name),
    description = coalesce(p_patch->>'description', p.description),
    category = coalesce(nullif(trim(coalesce(p_patch->>'category','')),''), p.category),
    rarity = coalesce(v_rarity, p.rarity),
    availability_type = coalesce(p_patch->>'availability_type', p.availability_type),
    show_in_catalog = coalesce((p_patch->>'show_in_catalog')::boolean, p.show_in_catalog),
    hide_name_until_discovered = coalesce((p_patch->>'hide_name_until_discovered')::boolean, p.hide_name_until_discovered),
    obtainable_from = coalesce(p_patch->'obtainable_from', p.obtainable_from),
    is_enabled = coalesce((p_patch->>'is_enabled')::boolean, p.is_enabled),
    image_baby_url = coalesce(v_img, p.image_baby_url),
    image_young_url = coalesce(v_img, p.image_young_url),
    image_adult_url = coalesce(v_img, p.image_adult_url),
    image_ancestral_url = coalesce(v_img, p.image_ancestral_url),
    primary_attribute_key = coalesce(v_key, p.primary_attribute_key),
    primary_attribute_value = coalesce(v_val, p.primary_attribute_value),
    base_passives = CASE WHEN v_key IS NOT NULL AND v_val IS NOT NULL
        THEN jsonb_build_object(v_key, v_val) ELSE p.base_passives END,
    updated_at = now()
  WHERE p.id = p_pet_id;

  SELECT to_jsonb(p) INTO v_new FROM public.pets p WHERE p.id = p_pet_id;
  PERFORM public.admin_log(p_admin_id,
    CASE WHEN v_rarity IS NOT NULL THEN 'PET_RARITY_CHANGED' ELSE 'PET_UPDATED' END,
    'pet', p_pet_id::text, v_old, v_new, p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION public.admin_pet_catalog(p_admin_id bigint, p_search text DEFAULT NULL, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; t int;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT count(*) INTO t FROM public.pets p
    WHERE p_search IS NULL OR p.name ILIKE '%'||p_search||'%' OR p.slug ILIKE '%'||p_search||'%';
  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v FROM (
    SELECT p.id, p.slug, p.name, p.rarity, p.category, p.is_enabled, p.show_in_catalog,
           p.availability_type, p.image_baby_url AS image_url,
           p.primary_attribute_key, p.primary_attribute_value,
           (SELECT count(*) FROM public.player_pets pp WHERE pp.pet_id = p.id) AS owners
      FROM public.pets p
     WHERE p_search IS NULL OR p.name ILIKE '%'||p_search||'%' OR p.slug ILIKE '%'||p_search||'%'
     ORDER BY public.pet_rarity_order(coalesce(p.rarity,'common')) DESC, p.name
     LIMIT greatest(1, least(coalesce(p_limit,20),50)) OFFSET greatest(0, coalesce(p_offset,0))
  ) x;
  RETURN jsonb_build_object('total', t, 'pets', v);
END $$;

CREATE OR REPLACE FUNCTION public.admin_pet_detail_cms(p_admin_id bigint, p_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(p) || jsonb_build_object(
      'owners', (SELECT count(*) FROM public.player_pets pp WHERE pp.pet_id = p.id),
      'eggs', coalesce((SELECT jsonb_agg(jsonb_build_object('eggId',e.id,'name',e.name,'rarity',rp.rarity,'weight',rp.weight,'enabled',rp.enabled) ORDER BY e.name)
              FROM public.reward_pet_pool rp JOIN public.pet_eggs e ON e.id::text = rp.source_key
             WHERE rp.source_type='EGG' AND rp.pet_id = p.id), '[]'::jsonb))
    INTO v FROM public.pets p WHERE p.id = p_pet_id;
  IF v IS NULL THEN RAISE EXCEPTION 'PET_NOT_FOUND'; END IF;
  RETURN v;
END $$;

-- ---------- EGGS ----------
CREATE OR REPLACE FUNCTION public.admin_egg_list(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',e.id,'slug',e.slug,'name',e.name,'image',e.image_url,'priceFc',e.price_fc,'priceTon',e.price_ton,
      'isEnabled',e.is_enabled,'isPurchasable',e.is_purchasable,'rates',e.rarity_rates,
      'poolCount',(SELECT count(*) FROM public.reward_pet_pool rp WHERE rp.source_type='EGG' AND rp.source_key=e.id::text AND rp.enabled)
    ) ORDER BY e.name) FROM public.pet_eggs e), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_egg_detail(p_admin_id bigint, p_egg_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(e) || jsonb_build_object(
    'pool', coalesce((SELECT jsonb_agg(jsonb_build_object('petId',p.id,'name',p.name,'rarity',rp.rarity,'weight',rp.weight,'enabled',rp.enabled)
              ORDER BY public.pet_rarity_order(rp.rarity), p.name)
            FROM public.reward_pet_pool rp JOIN public.pets p ON p.id = rp.pet_id
           WHERE rp.source_type='EGG' AND rp.source_key = e.id::text), '[]'::jsonb))
  INTO v FROM public.pet_eggs e WHERE e.id = p_egg_id;
  IF v IS NULL THEN RAISE EXCEPTION 'EGG_NOT_FOUND'; END IF;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.admin_create_egg_visual(p_admin_id bigint, p_name text, p_image_url text,
  p_currency text, p_price numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_slug text; v_base text; n int:=1; v_id uuid; v_new jsonb; v_cur text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF coalesce(trim(p_name),'')='' THEN RAISE EXCEPTION 'EGG_NAME_REQUIRED'; END IF;
  IF coalesce(trim(p_image_url),'')='' THEN RAISE EXCEPTION 'EGG_IMAGE_REQUIRED'; END IF;
  v_cur := upper(coalesce(p_currency,'FC'));
  IF v_cur NOT IN ('FC','TON','EVENT','NONE') THEN RAISE EXCEPTION 'INVALID_CURRENCY'; END IF;
  IF v_cur IN ('FC','TON') AND coalesce(p_price,0) <= 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;

  v_base := trim(both '-' from regexp_replace(lower(public.unaccent_fallback(trim(p_name))), '[^a-z0-9]+', '-', 'g'));
  IF v_base = '' THEN v_base := 'egg'; END IF;
  v_slug := v_base;
  WHILE EXISTS (SELECT 1 FROM public.pet_eggs WHERE slug = v_slug) LOOP n := n+1; v_slug := v_base||'-'||n; END LOOP;

  INSERT INTO public.pet_eggs (name, slug, image_url, rarity_rates, price_fc, price_ton, is_enabled, is_purchasable)
  VALUES (trim(p_name), v_slug, p_image_url, '{"common":100}'::jsonb,
    CASE WHEN v_cur='FC' THEN p_price END, CASE WHEN v_cur='TON' THEN p_price END,
    true, v_cur IN ('FC','TON'))
  RETURNING id INTO v_id;
  SELECT to_jsonb(e) INTO v_new FROM public.pet_eggs e WHERE e.id=v_id;
  PERFORM public.admin_log(p_admin_id,'EGG_CREATED','pet_egg',v_id::text,NULL,v_new,'editor visual');
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_egg_price_visual(p_admin_id bigint, p_egg_id uuid, p_currency text, p_price numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb; v_cur text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_cur := upper(coalesce(p_currency,'FC'));
  IF v_cur NOT IN ('FC','TON','EVENT','NONE') THEN RAISE EXCEPTION 'INVALID_CURRENCY'; END IF;
  IF v_cur IN ('FC','TON') AND coalesce(p_price,0) <= 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;
  SELECT to_jsonb(e) INTO v_old FROM public.pet_eggs e WHERE e.id = p_egg_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'EGG_NOT_FOUND'; END IF;
  UPDATE public.pet_eggs SET
    price_fc = CASE WHEN v_cur='FC' THEN p_price ELSE NULL END,
    price_ton = CASE WHEN v_cur='TON' THEN p_price ELSE NULL END,
    is_purchasable = v_cur IN ('FC','TON'),
    availability_label = CASE WHEN v_cur='EVENT' THEN coalesce(availability_label,'EVENT ONLY') ELSE availability_label END,
    updated_at = now()
  WHERE id = p_egg_id;
  SELECT to_jsonb(e) INTO v_new FROM public.pet_eggs e WHERE e.id = p_egg_id;
  PERFORM public.admin_log(p_admin_id,'EGG_PRICE_CHANGED','pet_egg',p_egg_id::text,v_old,v_new,'editor visual');
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_egg_odds(p_admin_id bigint, p_egg_id uuid, p_rates jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb; total numeric; k text; rate numeric; clean jsonb := '{}'::jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(e) INTO v_old FROM public.pet_eggs e WHERE e.id = p_egg_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'EGG_NOT_FOUND'; END IF;
  FOR k IN SELECT rarity FROM public.pet_rarity_config ORDER BY sort_order LOOP
    rate := coalesce((p_rates->>k)::numeric, 0);
    IF rate < 0 THEN RAISE EXCEPTION 'NEGATIVE_RATE'; END IF;
    IF rate > 0 THEN
      IF NOT EXISTS (SELECT 1 FROM public.reward_pet_pool rp JOIN public.pets p ON p.id = rp.pet_id
             WHERE rp.source_type='EGG' AND rp.source_key = p_egg_id::text AND rp.rarity = k AND rp.enabled AND p.is_enabled) THEN
        RAISE EXCEPTION 'NO_PET_FOR_RARITY:%', k;
      END IF;
      clean := clean || jsonb_build_object(k, rate);
    END IF;
  END LOOP;
  SELECT coalesce(sum(value::numeric),0) INTO total FROM jsonb_each_text(clean);
  IF abs(total - 100) > 0.0001 THEN RAISE EXCEPTION 'RATES_MUST_SUM_100:%', total; END IF;
  UPDATE public.pet_eggs SET rarity_rates = clean, updated_at = now() WHERE id = p_egg_id;
  SELECT to_jsonb(e) INTO v_new FROM public.pet_eggs e WHERE e.id = p_egg_id;
  PERFORM public.admin_log(p_admin_id,'EGG_ODDS_CHANGED','pet_egg',p_egg_id::text,v_old,v_new,'editor visual');
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION public.admin_toggle_egg_pet(p_admin_id bigint, p_egg_id uuid, p_pet_id uuid, p_rarity text, p_weight integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rar text; v_exists uuid; v_added boolean;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF NOT EXISTS (SELECT 1 FROM public.pet_eggs WHERE id = p_egg_id) THEN RAISE EXCEPTION 'EGG_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pets WHERE id = p_pet_id) THEN RAISE EXCEPTION 'PET_NOT_FOUND'; END IF;
  v_rar := public.normalize_pet_rarity(p_rarity);
  SELECT id INTO v_exists FROM public.reward_pet_pool
    WHERE source_type='EGG' AND source_key = p_egg_id::text AND pet_id = p_pet_id AND rarity = v_rar;
  IF v_exists IS NOT NULL THEN
    DELETE FROM public.reward_pet_pool WHERE id = v_exists;
    v_added := false;
  ELSE
    INSERT INTO public.reward_pet_pool (source_type, source_key, pet_id, rarity, weight)
    VALUES ('EGG', p_egg_id::text, p_pet_id, v_rar, greatest(1, coalesce(p_weight,100)));
    v_added := true;
  END IF;
  PERFORM public.admin_log(p_admin_id,'PET_POOL_UPDATED','pet_egg',p_egg_id::text,NULL,
    jsonb_build_object('pet_id',p_pet_id,'rarity',v_rar,'added',v_added),'editor visual');
  PERFORM public.admin_bump_settings_version();
  RETURN jsonb_build_object('added', v_added, 'rarity', v_rar);
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_egg_pet_weight(p_admin_id bigint, p_egg_id uuid, p_pet_id uuid, p_rarity text, p_weight integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.reward_pet_pool SET weight = greatest(0, coalesce(p_weight,100))
   WHERE source_type='EGG' AND source_key = p_egg_id::text AND pet_id = p_pet_id AND rarity = public.normalize_pet_rarity(p_rarity);
  IF NOT FOUND THEN RAISE EXCEPTION 'POOL_ENTRY_NOT_FOUND'; END IF;
  PERFORM public.admin_log(p_admin_id,'PET_POOL_UPDATED','pet_egg',p_egg_id::text,NULL,
    jsonb_build_object('pet_id',p_pet_id,'weight',p_weight),'editor visual');
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_update_egg_visual(p_admin_id bigint, p_egg_id uuid, p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(e) INTO v_old FROM public.pet_eggs e WHERE e.id = p_egg_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'EGG_NOT_FOUND'; END IF;
  UPDATE public.pet_eggs SET
    name = coalesce(nullif(trim(coalesce(p_patch->>'name','')),''), name),
    image_url = coalesce(nullif(trim(coalesce(p_patch->>'image_url','')),''), image_url),
    is_enabled = coalesce((p_patch->>'is_enabled')::boolean, is_enabled),
    availability_label = coalesce(p_patch->>'availability_label', availability_label),
    updated_at = now()
  WHERE id = p_egg_id;
  SELECT to_jsonb(e) INTO v_new FROM public.pet_eggs e WHERE e.id = p_egg_id;
  PERFORM public.admin_log(p_admin_id,'EGG_UPDATED','pet_egg',p_egg_id::text,v_old,v_new,'editor visual');
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_pet_rarities(bigint) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_roll_pet_attribute(bigint,text,text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_create_pet_visual(bigint,text,text,text,text,numeric,text,jsonb,text,boolean,text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_pet_visual(bigint,uuid,jsonb,text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_pet_catalog(bigint,text,integer,integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_pet_detail_cms(bigint,uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_egg_list(bigint) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_egg_detail(bigint,uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_create_egg_visual(bigint,text,text,text,numeric) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_set_egg_price_visual(bigint,uuid,text,numeric) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_set_egg_odds(bigint,uuid,jsonb) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_toggle_egg_pet(bigint,uuid,uuid,text,integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_set_egg_pet_weight(bigint,uuid,uuid,text,integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_egg_visual(bigint,uuid,jsonb) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.pick_pet_for_source(text,text,text,text) FROM anon, authenticated;

-- Catalog now exposes rarity/availability and keeps silhouettes for undiscovered pets.
CREATE OR REPLACE FUNCTION public.get_pet_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  SELECT id INTO u FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  RETURN jsonb_build_object(
    'activePet', (SELECT player_pet_json(id) FROM player_pets WHERE user_id = u AND is_active LIMIT 1),
    'playerPets', coalesce((SELECT jsonb_agg(player_pet_json(t.id))
        FROM (SELECT id FROM player_pets WHERE user_id = u ORDER BY is_active DESC, level DESC, created_at) t), '[]'::jsonb),
    'catalog', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'slug', p.slug, 'species', p.species, 'category', p.category,
          'description', coalesce(p.description,''), 'basePassives', p.base_passives, 'activeSkill', p.active_skill,
          'rarity', p.rarity, 'availabilityType', p.availability_type,
          'hideName', p.hide_name_until_discovered,
          'images', jsonb_build_object('baby',p.image_baby_url,'young',p.image_young_url,'adult',p.image_adult_url,'ancestral',p.image_ancestral_url),
          'discovered', exists(SELECT 1 FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id),
          'bestRarity', (SELECT pp.rarity FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id ORDER BY pet_rarity_order(pp.rarity) DESC LIMIT 1),
          'bestLevel', (SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id),
          'sources', coalesce((SELECT jsonb_agg(DISTINCT e.name) FROM reward_pet_pool rp
                JOIN pet_eggs e ON e.id::text = rp.source_key
               WHERE rp.source_type='EGG' AND rp.pet_id = p.id AND rp.enabled AND e.is_enabled),
             coalesce((SELECT jsonb_agg(e.name ORDER BY e.name) FROM pet_eggs e
               WHERE e.is_enabled AND p.availability_type='NORMAL'
                 AND NOT EXISTS (SELECT 1 FROM reward_pet_pool rp2 WHERE rp2.source_type='EGG' AND rp2.source_key=e.id::text)
                 AND (e.allowed_pet_categories IS NULL OR e.allowed_pet_categories ? p.category)), '[]'::jsonb))
        ) ORDER BY p.name) FROM pets p WHERE p.show_in_catalog AND (p.is_enabled OR exists(SELECT 1 FROM player_pets pp WHERE pp.user_id=u AND pp.pet_id=p.id))), '[]'::jsonb),
    'foods', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'code', f.code, 'name', f.name, 'rarity', f.rarity, 'xpValue', f.xp_value, 'icon', f.icon, 'priceFc', f.price_fc,
          'quantity', coalesce((SELECT quantity FROM player_pet_food pf WHERE pf.user_id = u AND pf.food_code = f.code), 0)
        ) ORDER BY f.sort_order) FROM pet_food_items f WHERE f.enabled), '[]'::jsonb),
    'fragments', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'playerPetId', pp.id, 'petName', p.name, 'image', p.image_baby_url, 'rarity', pp.rarity, 'quantity', pp.fragments
        ) ORDER BY pp.fragments DESC) FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.user_id = u), '[]'::jsonb),
    'inventory', jsonb_build_object(
        'food', coalesce((SELECT sum(quantity) FROM player_pet_food WHERE user_id = u), 0),
        'universalFragments', coalesce((SELECT quantity FROM player_pet_inventory WHERE user_id = u AND item_type = 'universal_fragment' AND item_id IS NULL), 0)),
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', h.id, 'eggName', e.name, 'petName', p.name, 'rarity', h.result_rarity,
          'duplicateFragments', h.duplicate_fragments, 'createdAt', h.created_at
        ) ORDER BY h.created_at DESC) FROM pet_hatch_history h
        JOIN pet_eggs e ON e.id = h.egg_id LEFT JOIN pets p ON p.id = h.result_pet_id
        WHERE h.user_id = u), '[]'::jsonb),
    'evolutionTiers', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'tier', t.tier, 'label', t.label, 'requiredLevel', t.required_level, 'fcCost', t.fc_cost,
          'fragmentCost', t.fragment_cost, 'newBuffChance', round(t.new_buff_chance*100)
        ) ORDER BY t.tier) FROM pet_evolution_tiers t WHERE t.enabled), '[]'::jsonb),
    'rarities', coalesce((SELECT jsonb_agg(jsonb_build_object('rarity',c.rarity,'label',c.label,'order',c.sort_order,
          'primary',c.color_primary,'secondary',c.color_secondary,'glow',c.glow) ORDER BY c.sort_order)
        FROM pet_rarity_config c WHERE c.enabled), '[]'::jsonb),
    'bonuses', get_pet_bonuses(u),
    'balance', coalesce((SELECT forge_coins FROM game_players WHERE id = u), 0)
  );
END $$;