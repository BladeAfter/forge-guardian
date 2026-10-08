-- Pet growth points: EVERY 10 levels (form change) AND EVERY evolution tier must raise stats.
-- Before: stage = MAX(floor(level/10), tier), so an evolution "ate" the level milestone
-- (e.g. tier 3 pet crossing level 30 gained nothing). Now both sources ADD up (cap 10 points).
CREATE OR REPLACE FUNCTION public.pet_stage_index(p_level integer, p_tier integer DEFAULT 0)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT LEAST(10, GREATEST(0,
      LEAST(5, floor(LEAST(50, GREATEST(1, coalesce(p_level,1))) / 10.0)::int)
    + LEAST(5, GREATEST(0, coalesce(p_tier,0)))
  ))
$$;

-- +8% power per growth point (level milestone or evolution), max +80%.
CREATE OR REPLACE FUNCTION public.pet_stage_power_multiplier(p_stage integer)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT 1 + 0.08 * LEAST(10, GREATEST(0, coalesce(p_stage,0)))
$$;

-- +10% buff per growth point, max +100% (per-buff caps in pet_buff_cap still apply).
CREATE OR REPLACE FUNCTION public.pet_stage_buff_multiplier(p_stage integer)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT 1 + 0.10 * LEAST(10, GREATEST(0, coalesce(p_stage,0)))
$$;

-- Preview of the next growth point must follow the new 10-point ceiling.
CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $function$
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
      pet_effective_buff(e.amount, rarity, ppet.level, LEAST(10, stage + 1), e.key));
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
    'growthPoints', stage,
    'growthPowerBonusPercent', round((public.pet_stage_power_multiplier(stage) - 1) * 100),
    'growthBuffBonusPercent', round((public.pet_stage_buff_multiplier(stage) - 1) * 100),
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
        * public.pet_stage_power_multiplier(LEAST(10, stage + 1))),
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
END $function$;