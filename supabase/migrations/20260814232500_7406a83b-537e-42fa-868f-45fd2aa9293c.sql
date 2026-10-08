-- ============================================================
-- Pet visual evolution: one visual form per 10 levels (max 6).
-- Purely cosmetic: rarity, buffs, XP, feeding, evolution tiers,
-- breeding, mining, expeditions and economy stay untouched.
-- ============================================================
ALTER TABLE public.pets
  ADD COLUMN IF NOT EXISTS image_base_url text,
  ADD COLUMN IF NOT EXISTS image_evo1_url text,
  ADD COLUMN IF NOT EXISTS image_evo2_url text,
  ADD COLUMN IF NOT EXISTS image_evo3_url text,
  ADD COLUMN IF NOT EXISTS image_evo4_url text,
  ADD COLUMN IF NOT EXISTS image_final_url text;

UPDATE public.pets SET image_base_url = image_baby_url WHERE image_base_url IS NULL;

-- Level -> visual slot (0 = base ... 5 = final form).
CREATE OR REPLACE FUNCTION public.pet_visual_index(p_level int)
RETURNS int LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT LEAST(5, GREATEST(0, floor(COALESCE(p_level, 1) / 10.0)::int));
$$;

-- Picks the artwork for a pet at a given level, falling back to the closest
-- available art (lower slots first, then higher) so a single image still works.
CREATE OR REPLACE FUNCTION public.pet_visual_image(p_pet_id uuid, p_level int)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; imgs text[]; idx int; i int;
BEGIN
  SELECT * INTO r FROM public.pets WHERE id = p_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  imgs := ARRAY[
    COALESCE(NULLIF(r.image_base_url,''), NULLIF(r.image_baby_url,'')),
    COALESCE(NULLIF(r.image_evo1_url,''), NULLIF(r.image_young_url,'')),
    COALESCE(NULLIF(r.image_evo2_url,''), NULLIF(r.image_adult_url,'')),
    NULLIF(r.image_evo3_url,''),
    NULLIF(r.image_evo4_url,''),
    COALESCE(NULLIF(r.image_final_url,''), NULLIF(r.image_ancestral_url,''))
  ];
  idx := public.pet_visual_index(p_level) + 1;
  FOR i IN REVERSE idx..1 LOOP
    IF imgs[i] IS NOT NULL THEN RETURN imgs[i]; END IF;
  END LOOP;
  FOR i IN idx..6 LOOP
    IF imgs[i] IS NOT NULL THEN RETURN imgs[i]; END IF;
  END LOOP;
  RETURN NULL;
END $$;

REVOKE ALL ON FUNCTION public.pet_visual_image(uuid, int) FROM anon, authenticated;

-- ---------- owned pet payload ----------
CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE ppet record; nxt record; buffs jsonb; pkey text; pbase numeric; maxlvl int; totals numeric; nftj jsonb;
BEGIN
  SELECT ppet2.*, p.name, p.slug, p.species, p.category, p.base_passives, p.active_skill,
         p.image_baby_url, p.image_young_url, p.image_adult_url, p.image_ancestral_url,
         p.is_nft_exclusive
    INTO ppet FROM player_pets ppet2 JOIN pets p ON p.id = ppet2.pet_id WHERE ppet2.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  maxlvl := pet_max_level();
  buffs := player_pet_buffs(ppet.id);
  SELECT key, (value#>>'{}')::numeric INTO pkey, pbase
    FROM jsonb_each(coalesce(ppet.base_passives,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  SELECT * INTO nxt FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier + 1 AND enabled;
  SELECT coalesce(sum((value#>>'{}')::numeric),0) INTO totals FROM jsonb_each(buffs);
  SELECT jsonb_build_object('serial', n.nft_serial, 'instanceId', n.unique_instance_id,
      'status', n.status, 'minted', n.minted)
    INTO nftj FROM nft_pets n WHERE n.id = ppet.nft_pet_id;
  RETURN jsonb_build_object(
    'id', ppet.id, 'petId', ppet.pet_id, 'name', ppet.name, 'slug', ppet.slug, 'species', ppet.species,
    'category', ppet.category, 'rarity', ppet.rarity, 'level', ppet.level, 'maxLevel', maxlvl,
    'xp', ppet.xp, 'xpRequired', CASE WHEN ppet.level >= maxlvl THEN 0 ELSE pet_level_xp_required(ppet.level) END,
    'isMaxLevel', ppet.level >= maxlvl,
    'evolutionTier', ppet.evolution_tier,
    'evolutionLabel', coalesce((SELECT label FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier), 'Forma Base'),
    'evolutionStage', ppet.evolution_stage,
    'fragments', ppet.fragments, 'isActive', ppet.is_active,
    -- Cosmetic form driven by level (0..5). Falls back to legacy art.
    'image', public.pet_visual_image(ppet.pet_id, ppet.level),
    'visualStage', public.pet_visual_index(ppet.level),
    'buffs', buffs,
    'primaryBuffKey', pkey,
    'primaryBuffValue', coalesce((buffs->>pkey)::numeric, 0),
    'secondaryBuffs', coalesce(ppet.secondary_buffs,'[]'::jsonb),
    'power', (CASE ppet.rarity WHEN 'legendary' THEN 8000 WHEN 'epic' THEN 4000 WHEN 'rare' THEN 2000
              WHEN 'uncommon' THEN 1000 ELSE 500 END) + ppet.level * 100 + round(totals * 250),
    'activeSkill', ppet.active_skill,
    'isNft', coalesce(ppet.is_nft_exclusive, false),
    'nft', nftj,
    'nextEvolution', CASE WHEN nxt.tier IS NULL THEN NULL ELSE jsonb_build_object(
        'tier', nxt.tier, 'label', nxt.label, 'requiredLevel', nxt.required_level,
        'fcCost', nxt.fc_cost, 'fragmentCost', nxt.fragment_cost,
        'newBuffChance', round(nxt.new_buff_chance * 100),
        'maxSecondaryBuffs', nxt.max_secondary_buffs,
        'primaryFrom', coalesce((buffs->>pkey)::numeric, 0),
        'primaryTo', round(coalesce(pbase,0) * pet_rarity_multiplier(ppet.rarity)
                     * (1 + (ppet.level - 1) * 0.02) * nxt.primary_multiplier, 2)
      ) END,
    'canEvolve', nxt.tier IS NOT NULL AND ppet.level >= nxt.required_level
  );
END $function$;

-- ---------- XP transfer targets ----------
CREATE OR REPLACE FUNCTION public.pet_xp_transfer_preview(p_telegram_id bigint, p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE u uuid; src player_pets%rowtype; total int; cost numeric; bal numeric; targets jsonb;
BEGIN
  SELECT id, forge_coins INTO u, bal FROM game_players WHERE telegram_id = p_telegram_id;
  IF u IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO src FROM player_pets WHERE id = p_player_pet_id AND user_id = u;
  IF src.id IS NULL THEN RAISE EXCEPTION 'PET_NOT_OWNED'; END IF;

  total := pet_total_xp(src.level, src.xp);
  cost := pet_xp_transfer_cost(src.level);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', c.name, 'rarity', p.rarity,
      'image', public.pet_visual_image(p.pet_id, p.level),
      'level', p.level, 'xp', p.xp, 'capacity', pet_xp_capacity(p.level, p.xp),
      'canReceive', pet_xp_capacity(p.level, p.xp) >= total AND NOT coalesce(p.market_locked, false)
    ) ORDER BY p.level DESC), '[]'::jsonb)
  INTO targets
  FROM player_pets p JOIN pets c ON c.id = p.pet_id
  WHERE p.user_id = u AND p.id <> src.id;

  RETURN jsonb_build_object(
    'sourceId', src.id, 'level', src.level, 'xp', src.xp, 'totalXp', total,
    'costFc', cost, 'balance', coalesce(bal, 0), 'targets', targets);
END $function$;

-- ---------- expeditions ----------
CREATE OR REPLACE FUNCTION public.expedition_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; busy uuid[];
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);
  select coalesce(array_agg(pid), '{}') into busy
    from (select unnest(pet_ids) pid from public.pet_expeditions where user_id = u and status = 'ACTIVE') b;

  return jsonb_build_object(
    'limits', public.expedition_limits(),
    'pets', coalesce((select jsonb_agg(jsonb_build_object(
        'playerPetId', pp.id, 'name', p.name,
        'image', coalesce(sn_t.image_url, public.pet_visual_image(pp.pet_id, pp.level)),
        'rarity', pp.rarity, 'level', pp.level, 'power', public.pet_instance_power(pp.id),
        'isSubNft', sn.id is not null, 'stage', sn.maturity_stage,
        'trait', sn.trait_code,
        'eligible', (sn.id is null or sn.maturity_stage = 'ADULT') and not (pp.id = any(busy)),
        'busy', pp.id = any(busy)) order by public.pet_instance_power(pp.id) desc)
      from public.player_pets pp
      join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates sn_t on sn_t.id = sn.template_id
      where pp.user_id = u), '[]'::jsonb),
    'missions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'code', m.code, 'name', m.name, 'rarity', m.rarity,
        'durationHours', m.duration_hours, 'requiredPower', m.required_power,
        'element', m.recommended_element, 'rewards', m.reward_pool,
        'attempts', public.expedition_mission_attempts(u, m.id)) order by m.sort_order)
      from public.expedition_missions m where m.enabled), '[]'::jsonb),
    'active', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'missionRarity', m.rarity,
        'startedAt', e.started_at, 'finishesAt', e.finishes_at,
        'teamPower', e.team_power, 'successChance', e.success_chance,
        'ready', e.finishes_at <= now(),
        'pets', (select jsonb_agg(jsonb_build_object('name', p2.name, 'image', public.pet_visual_image(pp2.pet_id, pp2.level)))
                   from public.player_pets pp2 join public.pets p2 on p2.id = pp2.pet_id where pp2.id = any(e.pet_ids)))
        order by e.finishes_at)
      from public.pet_expeditions e join public.expedition_missions m on m.id = e.mission_id
      where e.user_id = u and e.status = 'ACTIVE'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'success', e.success, 'rewards', e.rewards, 'claimedAt', e.claimed_at)
        order by e.claimed_at desc)
      from (select * from public.pet_expeditions where user_id = u and status = 'CLAIMED' order by claimed_at desc limit 10) e
      join public.expedition_missions m on m.id = e.mission_id), '[]'::jsonb));
end $function$;

-- ---------- marketplace + catalog: swap the fixed art for the level-based one ----------
DO $do$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = 'market_get_sellable'
    AND pronamespace = 'public'::regnamespace;
  src := replace(src,
    'coalesce(pet.image_adult_url, pet.image_young_url, pet.image_baby_url) as image',
    'public.pet_visual_image(p.pet_id, p.level) as image');
  EXECUTE src;

  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = 'get_pet_dashboard'
    AND pronamespace = 'public'::regnamespace;
  src := replace(src,
    '''images'', jsonb_build_object(''baby'',p.image_baby_url,''young'',p.image_young_url,''adult'',p.image_adult_url,''ancestral'',p.image_ancestral_url),',
    '''images'', jsonb_build_object(''baby'',p.image_baby_url,''young'',p.image_young_url,''adult'',p.image_adult_url,''ancestral'',p.image_ancestral_url),'
    || ' ''image'', public.pet_visual_image(p.id, coalesce((SELECT max(pp.level) FROM player_pets pp WHERE pp.user_id = u AND pp.pet_id = p.id AND NOT coalesce(pp.market_locked,false)), 1)),');
  EXECUTE src;
END $do$;

-- ---------- admin: manage the six artworks ----------
CREATE OR REPLACE FUNCTION public.admin_set_pet_stage_image(p_admin_id bigint, p_pet_id uuid, p_stage text, p_url text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_stage text; v_new jsonb; v_old jsonb; v_url text;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_stage := lower(btrim(coalesce(p_stage,'')));
  IF v_stage NOT IN ('base','evo1','evo2','evo3','evo4','final') THEN RAISE EXCEPTION 'INVALID_STAGE'; END IF;
  SELECT to_jsonb(p) INTO v_old FROM public.pets p WHERE p.id = p_pet_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'PET_NOT_FOUND'; END IF;
  v_url := nullif(btrim(coalesce(p_url,'')), '');

  UPDATE public.pets SET
    image_base_url  = CASE WHEN v_stage = 'base'  THEN v_url ELSE image_base_url  END,
    image_evo1_url  = CASE WHEN v_stage = 'evo1'  THEN v_url ELSE image_evo1_url  END,
    image_evo2_url  = CASE WHEN v_stage = 'evo2'  THEN v_url ELSE image_evo2_url  END,
    image_evo3_url  = CASE WHEN v_stage = 'evo3'  THEN v_url ELSE image_evo3_url  END,
    image_evo4_url  = CASE WHEN v_stage = 'evo4'  THEN v_url ELSE image_evo4_url  END,
    image_final_url = CASE WHEN v_stage = 'final' THEN v_url ELSE image_final_url END,
    updated_at = now()
  WHERE id = p_pet_id;

  SELECT to_jsonb(p) INTO v_new FROM public.pets p WHERE p.id = p_pet_id;
  PERFORM public.admin_log(p_admin_id,'PET_STAGE_IMAGE_SET','pet',p_pet_id::text,v_old,v_new,'visual stage ' || v_stage);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END $$;

REVOKE ALL ON FUNCTION public.admin_set_pet_stage_image(bigint, uuid, text, text) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_pet_stage_images(p_admin_id bigint, p_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT * INTO r FROM public.pets WHERE id = p_pet_id;
  IF NOT found THEN RAISE EXCEPTION 'PET_NOT_FOUND'; END IF;
  RETURN jsonb_build_object('id', r.id, 'name', r.name, 'rarity', r.rarity,
    'base', r.image_base_url, 'evo1', r.image_evo1_url, 'evo2', r.image_evo2_url,
    'evo3', r.image_evo3_url, 'evo4', r.image_evo4_url, 'final', r.image_final_url,
    'legacy', jsonb_build_object('baby', r.image_baby_url, 'young', r.image_young_url,
      'adult', r.image_adult_url, 'ancestral', r.image_ancestral_url));
END $$;

REVOKE ALL ON FUNCTION public.admin_pet_stage_images(bigint, uuid) FROM anon, authenticated;

-- keep the generic pet upsert able to receive the new fields
CREATE OR REPLACE FUNCTION public.admin_upsert_pet(p_admin_id bigint, p_slug text, p_patch jsonb, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(p) INTO v_old FROM public.pets p WHERE p.slug = p_slug;
  IF v_old IS NULL THEN
    INSERT INTO public.pets (name, slug, species, category, is_enabled)
    VALUES (COALESCE(p_patch->>'name', p_slug), p_slug, COALESCE(p_patch->>'species','beast'), COALESCE(p_patch->>'category','fire'), COALESCE((p_patch->>'is_enabled')::boolean,true));
  END IF;
  UPDATE public.pets p SET
    name = COALESCE(p_patch->>'name', p.name),
    species = COALESCE(p_patch->>'species', p.species),
    category = COALESCE(p_patch->>'category', p.category),
    description = COALESCE(p_patch->>'description', p.description),
    base_passives = COALESCE(p_patch->'base_passives', p.base_passives),
    active_skill = COALESCE(p_patch->'active_skill', p.active_skill),
    image_baby_url = COALESCE(p_patch->>'image_baby_url', p.image_baby_url),
    image_young_url = COALESCE(p_patch->>'image_young_url', p.image_young_url),
    image_adult_url = COALESCE(p_patch->>'image_adult_url', p.image_adult_url),
    image_ancestral_url = COALESCE(p_patch->>'image_ancestral_url', p.image_ancestral_url),
    image_base_url = COALESCE(p_patch->>'image_base_url', p.image_base_url),
    image_evo1_url = COALESCE(p_patch->>'image_evo1_url', p.image_evo1_url),
    image_evo2_url = COALESCE(p_patch->>'image_evo2_url', p.image_evo2_url),
    image_evo3_url = COALESCE(p_patch->>'image_evo3_url', p.image_evo3_url),
    image_evo4_url = COALESCE(p_patch->>'image_evo4_url', p.image_evo4_url),
    image_final_url = COALESCE(p_patch->>'image_final_url', p.image_final_url),
    is_enabled = COALESCE((p_patch->>'is_enabled')::boolean, p.is_enabled),
    updated_at = now()
  WHERE p.slug = p_slug;
  SELECT to_jsonb(p) INTO v_new FROM public.pets p WHERE p.slug = p_slug;
  PERFORM public.admin_log(p_admin_id, CASE WHEN v_old IS NULL THEN 'pet.create' ELSE 'pet.update' END,'pet',p_slug,v_old,v_new,p_reason);
  PERFORM public.admin_bump_settings_version();
  RETURN v_new;
END; $function$;

-- visual editor: the single image also seeds the base form
CREATE OR REPLACE FUNCTION public.admin_update_pet_visual(p_admin_id bigint, p_pet_id uuid, p_patch jsonb, p_reason text DEFAULT 'editor visual'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
    image_base_url = coalesce(v_img, p.image_base_url),
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
END $function$;