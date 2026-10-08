-- ============================================================
-- OFFICIAL PET COMBAT SYSTEM (power, rarity hierarchy, evolution scaling)
-- Nothing here touches TON yield / mining / claims / ownership.
-- ============================================================

-- 1. Rarity normalization now understands the "exclusive" tier (was silently
--    collapsing to 'common', making Exclusive pets weaker than Ancestral).
CREATE OR REPLACE FUNCTION public.normalize_pet_rarity(v text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select case lower(trim(coalesce(v,'common')))
    when 'uncommon' then 'uncommon' when 'incomum' then 'uncommon'
    when 'rare' then 'rare' when 'raro' then 'rare' when 'rara' then 'rare'
    when 'epic' then 'epic' when 'epico' then 'epic' when 'épico' then 'epic' when 'epica' then 'epic' when 'épica' then 'epic'
    when 'legendary' then 'legendary' when 'lendario' then 'legendary' when 'lendário' then 'legendary' when 'lendaria' then 'legendary' when 'lendária' then 'legendary'
    when 'mythic' then 'mythic' when 'mitico' then 'mythic' when 'mítico' then 'mythic' when 'mitica' then 'mythic' when 'mítica' then 'mythic'
    when 'ancestral' then 'ancestral'
    when 'exclusive' then 'exclusive' when 'exclusivo' then 'exclusive' when 'exclusiva' then 'exclusive'
    when 'nft_exclusive' then 'nft_exclusive' when 'nft-exclusive' then 'nft_exclusive'
    when 'nft exclusive' then 'nft_exclusive' when 'nft' then 'nft_exclusive'
    when 'nft_exclusivo' then 'nft_exclusive' when 'nft exclusivo' then 'nft_exclusive'
    else 'common' end
$$;

-- 2. Official hierarchy + official base power per rarity.
INSERT INTO public.pet_rarity_config (rarity, label, label_pt, sort_order, multiplier, power, attr_min, attr_max, color_primary, color_secondary, glow)
VALUES ('exclusive','Exclusive','Exclusivo',8,3.9,31000,14,18,'#f0abfc','#fdf4ff','rgba(240,171,252,.5)')
ON CONFLICT (rarity) DO NOTHING;

UPDATE public.pet_rarity_config SET sort_order = 9 WHERE rarity = 'nft_exclusive';

UPDATE public.pet_rarity_config c SET power = v.power, multiplier = v.mult, sort_order = v.ord
FROM (VALUES
  ('common',10000,1.00,1),('uncommon',11500,1.25,2),('rare',13500,1.60,3),
  ('epic',16000,2.10,4),('legendary',19000,2.80,5),('mythic',22500,3.20,6),
  ('ancestral',27000,3.60,7),('exclusive',31000,3.90,8),('nft_exclusive',35000,4.20,9)
) AS v(rarity, power, mult, ord)
WHERE c.rarity = v.rarity;

-- Players may reach level 50 (UI already shows /50) and may own exclusive pets.
ALTER TABLE public.player_pets DROP CONSTRAINT IF EXISTS player_pets_level_check;
ALTER TABLE public.player_pets ADD CONSTRAINT player_pets_level_check CHECK (level >= 1 AND level <= 50);
ALTER TABLE public.player_pets DROP CONSTRAINT IF EXISTS player_pets_rarity_check;
ALTER TABLE public.player_pets ADD CONSTRAINT player_pets_rarity_check
  CHECK (rarity = ANY (ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral','exclusive','nft_exclusive']));

-- 3. Evolution stage (one visual stage every 10 levels) and its official multipliers.
CREATE OR REPLACE FUNCTION public.pet_stage_index(p_level integer, p_tier integer DEFAULT 0)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT LEAST(5, GREATEST(0, GREATEST(floor(coalesce(p_level,1) / 10.0)::int, coalesce(p_tier,0))))
$$;

-- Power grows +8% per stage, buffs grow +10% per stage — always from the BASE value.
CREATE OR REPLACE FUNCTION public.pet_stage_power_multiplier(p_stage integer)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT 1 + 0.08 * LEAST(5, GREATEST(0, coalesce(p_stage,0)))
$$;

CREATE OR REPLACE FUNCTION public.pet_stage_buff_multiplier(p_stage integer)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT 1 + 0.10 * LEAST(5, GREATEST(0, coalesce(p_stage,0)))
$$;

CREATE OR REPLACE FUNCTION public.pet_rarity_base_power(p_rarity text, p_is_nft boolean DEFAULT false)
RETURNS numeric LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT coalesce((SELECT c.power FROM public.pet_rarity_config c
                    WHERE c.rarity = CASE WHEN coalesce(p_is_nft,false) THEN 'nft_exclusive'
                                          ELSE public.normalize_pet_rarity(p_rarity) END), 10000)::numeric
$$;

-- 4. Safety caps per buff type (raised so evolutions still have headroom).
UPDATE public.pet_settings SET value = jsonb_build_object(
  'boss_damage_percent',40,'boss_damage_reduction_percent',30,'team_hp_percent',40,
  'pvp_attack_percent',40,'pvp_defense_percent',40,'pvp_speed_percent',20,
  'defense_percent',40,'critical_chance_percent',20,'reward_percent',20,
  'mission_reward_percent',20,'random_reward_percent',20,'drop_chance_percent',20,
  'egg_luck_percent',20,'farm_fc_percent',30,'offline_production_percent',30,
  'hero_xp_percent',30,'account_xp_percent',30,'revive_speed_percent',60,
  'mission_progress_percent',20
) WHERE key = 'bonus_caps';

CREATE OR REPLACE FUNCTION public.pet_buff_cap(p_key text)
RETURNS numeric LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT coalesce((SELECT (value->>p_key)::numeric FROM public.pet_settings WHERE key = 'bonus_caps'), 40)
$$;

-- 5. Effective buffs: ALWAYS recomputed from the base value (never compounded).
--    effective = base * rarity_multiplier * level_multiplier * stage_multiplier, then capped.
CREATE OR REPLACE FUNCTION public.pet_effective_buff(p_base numeric, p_rarity text, p_level integer, p_stage integer, p_key text)
RETURNS numeric LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE raw numeric; cap numeric;
BEGIN
  IF p_base IS NULL OR p_base <= 0 THEN RETURN coalesce(p_base, 0); END IF;
  raw := p_base
       * public.pet_rarity_multiplier(p_rarity)
       * (1 + (LEAST(50, GREATEST(1, coalesce(p_level,1))) - 1) * 0.02)
       * public.pet_stage_buff_multiplier(p_stage);
  cap := public.pet_buff_cap(p_key);
  IF cap IS NOT NULL AND raw > cap THEN
    IF raw > cap * 3 THEN RAISE WARNING 'PET_BUFF_OUT_OF_RANGE key=% raw=% cap=%', p_key, raw, cap; END IF;
    raw := cap;
  END IF;
  RETURN round(LEAST(raw, 150), 2);
END $$;

CREATE OR REPLACE FUNCTION public.player_pet_buffs(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; result jsonb := '{}'::jsonb; e record; b jsonb; stage int; val numeric; rarity text;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.secondary_buffs, pp.nft_pet_id,
         p.base_passives, p.is_nft_exclusive
    INTO r FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN result; END IF;
  rarity := CASE WHEN coalesce(r.is_nft_exclusive,false) OR r.nft_pet_id IS NOT NULL
                 THEN 'nft_exclusive' ELSE normalize_pet_rarity(r.rarity) END;
  stage := pet_stage_index(r.level, r.evolution_tier);
  FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(coalesce(r.base_passives,'{}'::jsonb)) LOOP
    result := result || jsonb_build_object(e.key, pet_effective_buff(e.amount, rarity, r.level, stage, e.key));
  END LOOP;
  -- Secondary buffs are flat additions on top of the (already capped) primary value, then capped again.
  FOR b IN SELECT value FROM jsonb_array_elements(coalesce(r.secondary_buffs,'[]'::jsonb)) LOOP
    val := coalesce((b->>'value')::numeric, 0) * pet_stage_buff_multiplier(stage)
         + coalesce((result->>(b->>'key'))::numeric, 0);
    result := result || jsonb_build_object(b->>'key', round(LEAST(val, GREATEST(pet_buff_cap(b->>'key'), 0) * 1.5), 2));
  END LOOP;
  RETURN result;
END $$;

-- 6. ONE official power formula. Rarity gaps (>=1500) are always larger than the
--    maximum buff contribution (400), so a higher rarity can never be weaker.
CREATE OR REPLACE FUNCTION public.pet_instance_power(p_player_pet_id uuid)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; stage int; rarity text; base numeric; buff_sum numeric;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.nft_pet_id, p.is_nft_exclusive
    INTO r FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN 0; END IF;
  rarity := CASE WHEN coalesce(r.is_nft_exclusive,false) OR r.nft_pet_id IS NOT NULL
                 THEN 'nft_exclusive' ELSE normalize_pet_rarity(r.rarity) END;
  stage := pet_stage_index(r.level, r.evolution_tier);
  base := pet_rarity_base_power(rarity, rarity = 'nft_exclusive');
  SELECT coalesce(sum((value#>>'{}')::numeric), 0) INTO buff_sum
    FROM jsonb_each(player_pet_buffs(p_player_pet_id));
  RETURN round(
      base
      * (1 + (LEAST(50, GREATEST(1, coalesce(r.level,1))) - 1) * 0.05)
      * pet_stage_power_multiplier(stage)
    + LEAST(coalesce(buff_sum,0), 200) * 2
  );
END $$;

-- 7. Single source of truth consumed by pets, PvP, boss, clan boss, expeditions and evolution.
CREATE OR REPLACE FUNCTION public.calculate_pet_combat_stats(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; stage int; rarity text; effective jsonb; nextb jsonb := '{}'::jsonb; e record;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.nft_pet_id, p.base_passives, p.is_nft_exclusive, p.name
    INTO r FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  rarity := CASE WHEN coalesce(r.is_nft_exclusive,false) OR r.nft_pet_id IS NOT NULL
                 THEN 'nft_exclusive' ELSE normalize_pet_rarity(r.rarity) END;
  stage := pet_stage_index(r.level, r.evolution_tier);
  effective := player_pet_buffs(p_player_pet_id);
  FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(coalesce(r.base_passives,'{}'::jsonb)) LOOP
    nextb := nextb || jsonb_build_object(e.key,
      pet_effective_buff(e.amount, rarity, r.level, LEAST(5, stage + 1), e.key));
  END LOOP;
  RETURN jsonb_build_object(
    'petPlayerId', p_player_pet_id, 'name', r.name, 'rarity', rarity,
    'rarityOrder', pet_rarity_order(rarity), 'level', r.level,
    'evolutionStage', stage, 'evolutionTier', r.evolution_tier,
    'basePower', pet_rarity_base_power(rarity, rarity = 'nft_exclusive'),
    'power', pet_instance_power(p_player_pet_id),
    'baseBuffs', coalesce(r.base_passives, '{}'::jsonb),
    'effectiveBuffs', effective,
    'nextStageBuffs', nextb
  );
END $$;

-- 8. Evolution preview now reuses the official capped formula (was raw
--    base * rarity * level * tier, which produced values such as +337%).
CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE ppet record; nxt record; buffs jsonb; nextbuffs jsonb; pkey text; pbase numeric; maxlvl int; nftj jsonb; is_nft boolean; stage int; rarity text; e record;
BEGIN
  SELECT ppet2.*, p.name, p.slug, p.species, p.category, p.base_passives, p.active_skill,
         p.image_baby_url, p.image_young_url, p.image_adult_url, p.image_ancestral_url,
         p.is_nft_exclusive
    INTO ppet FROM player_pets ppet2 JOIN pets p ON p.id = ppet2.pet_id WHERE ppet2.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  maxlvl := pet_max_level();
  buffs := player_pet_buffs(ppet.id);
  is_nft := coalesce(ppet.is_nft_exclusive, false)
            OR ppet.nft_pet_id IS NOT NULL
            OR lower(coalesce(ppet.rarity,'')) LIKE 'nft%';
  rarity := CASE WHEN is_nft THEN 'nft_exclusive' ELSE normalize_pet_rarity(ppet.rarity) END;
  stage := pet_stage_index(ppet.level, ppet.evolution_tier);
  SELECT key, (value#>>'{}')::numeric INTO pkey, pbase
    FROM jsonb_each(coalesce(ppet.base_passives,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  nextbuffs := '{}'::jsonb;
  FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(coalesce(ppet.base_passives,'{}'::jsonb)) LOOP
    nextbuffs := nextbuffs || jsonb_build_object(e.key,
      pet_effective_buff(e.amount, rarity, ppet.level, LEAST(5, stage + 1), e.key));
  END LOOP;
  SELECT * INTO nxt FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier + 1 AND enabled;
  SELECT jsonb_build_object('serial', n.nft_serial, 'instanceId', n.unique_instance_id,
      'status', n.status, 'minted', n.minted)
    INTO nftj FROM nft_pets n WHERE n.id = ppet.nft_pet_id;
  RETURN jsonb_build_object(
    'id', ppet.id, 'petId', ppet.pet_id, 'name', ppet.name, 'slug', ppet.slug, 'species', ppet.species,
    'category', ppet.category,
    'rarity', rarity,
    'level', ppet.level, 'maxLevel', maxlvl,
    'xp', ppet.xp, 'xpRequired', CASE WHEN ppet.level >= maxlvl THEN 0 ELSE pet_level_xp_required(ppet.level) END,
    'isMaxLevel', ppet.level >= maxlvl,
    'evolutionTier', ppet.evolution_tier,
    'evolutionLabel', coalesce((SELECT label FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier), 'Forma Base'),
    'evolutionStage', ppet.evolution_stage,
    'fragments', ppet.fragments, 'isActive', ppet.is_active,
    'image', public.pet_visual_image(ppet.pet_id, ppet.level),
    'visualStage', public.pet_visual_index(ppet.level),
    'buffs', buffs,
    'nextStageBuffs', nextbuffs,
    'primaryBuffKey', pkey,
    'primaryBuffValue', coalesce((buffs->>pkey)::numeric, 0),
    'secondaryBuffs', coalesce(ppet.secondary_buffs,'[]'::jsonb),
    'power', public.pet_instance_power(ppet.id),
    'nextStagePower', round(
        public.pet_rarity_base_power(rarity, is_nft)
        * (1 + (LEAST(50, GREATEST(1, ppet.level)) - 1) * 0.05)
        * public.pet_stage_power_multiplier(LEAST(5, stage + 1))),
    'activeSkill', ppet.active_skill,
    'isNft', is_nft,
    'nftSerial', (nftj->>'serial')::int,
    'nft', nftj,
    'nextEvolution', CASE WHEN nxt.tier IS NULL THEN NULL ELSE jsonb_build_object(
        'tier', nxt.tier, 'label', nxt.label, 'requiredLevel', nxt.required_level,
        'fcCost', nxt.fc_cost, 'fragmentCost', nxt.fragment_cost,
        'newBuffChance', round(nxt.new_buff_chance * 100),
        'maxSecondaryBuffs', nxt.max_secondary_buffs,
        'primaryFrom', coalesce((buffs->>pkey)::numeric, 0),
        'primaryTo', coalesce((nextbuffs->>pkey)::numeric, coalesce((buffs->>pkey)::numeric, 0))
      ) END,
    'canEvolve', nxt.tier IS NOT NULL AND ppet.level >= nxt.required_level
  );
END $$;

-- 9. Fix the mythic season-pass templates that shipped with NO passive at all
--    (their bonus only existed in primary_attribute_*, which no formula reads).
UPDATE public.pets SET base_passives = jsonb_build_object(
    'pvp_attack_percent', coalesce(primary_attribute_value, 12),
    'boss_damage_percent', 10,
    'team_hp_percent', 10
  )
WHERE is_enabled AND base_passives = '{}'::jsonb;

-- 10. Audit view of every owned pet against the official formula.
CREATE OR REPLACE FUNCTION public.admin_pet_power_audit()
RETURNS TABLE(player_pet_id uuid, pet_name text, rarity text, rarity_order int, level int,
              evolution_stage int, power numeric, buff_sum numeric, has_zero_buff boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT pp.id, p.name,
         CASE WHEN coalesce(p.is_nft_exclusive,false) OR pp.nft_pet_id IS NOT NULL
              THEN 'nft_exclusive' ELSE normalize_pet_rarity(pp.rarity) END,
         pet_rarity_order(CASE WHEN coalesce(p.is_nft_exclusive,false) OR pp.nft_pet_id IS NOT NULL
              THEN 'nft_exclusive' ELSE normalize_pet_rarity(pp.rarity) END),
         pp.level, pet_stage_index(pp.level, pp.evolution_tier),
         pet_instance_power(pp.id),
         coalesce((SELECT sum((value#>>'{}')::numeric) FROM jsonb_each(player_pet_buffs(pp.id))), 0),
         coalesce((SELECT sum((value#>>'{}')::numeric) FROM jsonb_each(player_pet_buffs(pp.id))), 0) <= 0
    FROM player_pets pp JOIN pets p ON p.id = pp.pet_id
   ORDER BY 4 DESC, 7 DESC
$$;

GRANT EXECUTE ON FUNCTION public.calculate_pet_combat_stats(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pet_stage_index(integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pet_stage_power_multiplier(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pet_stage_buff_multiplier(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pet_effective_buff(numeric, text, integer, integer, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pet_buff_cap(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_pet_power_audit() TO service_role;
