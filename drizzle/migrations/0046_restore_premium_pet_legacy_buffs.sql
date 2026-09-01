CREATE OR REPLACE FUNCTION public.pet_premium_effective_buff(
  p_base numeric,
  p_rarity text,
  p_level integer,
  p_evolution_tier integer
)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT round(
    coalesce(p_base, 0)
    * public.pet_rarity_multiplier(p_rarity)
    * (1 + (LEAST(50, GREATEST(1, coalesce(p_level, 1))) - 1) * 0.02)
    * public.pet_tier_multiplier(GREATEST(0, coalesce(p_evolution_tier, 0))),
    2
  )
$function$;

CREATE OR REPLACE FUNCTION public.player_pet_buffs(p_player_pet_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  result jsonb := '{}'::jsonb;
  e record;
  b jsonb;
  stage int;
  val numeric;
  rarity text;
  premium boolean;
  secondary_cap numeric;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.secondary_buffs,
         pp.nft_pet_id, pp.sub_nft_id, coalesce(pp.veteran_line, false) AS veteran_line,
         coalesce(pp.passives_override, p.base_passives) AS base_passives,
         p.is_nft_exclusive
    INTO r
    FROM public.player_pets pp
    JOIN public.pets p ON p.id = pp.pet_id
   WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN result; END IF;

  premium := r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL OR r.veteran_line;
  rarity := CASE
    WHEN coalesce(r.is_nft_exclusive, false) OR r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL
      THEN 'nft_exclusive'
    ELSE public.normalize_pet_rarity(r.rarity)
  END;
  stage := public.pet_stage_index(r.level, r.evolution_tier);

  IF premium THEN
    FOR e IN
      SELECT key, (value #>> '{}')::numeric AS amount
      FROM jsonb_each(coalesce(r.base_passives, '{}'::jsonb))
    LOOP
      result := result || jsonb_build_object(
        e.key,
        public.pet_premium_effective_buff(e.amount, rarity, r.level, r.evolution_tier)
      );
    END LOOP;

    FOR b IN SELECT value FROM jsonb_array_elements(coalesce(r.secondary_buffs, '[]'::jsonb))
    LOOP
      val := coalesce((b->>'value')::numeric, 0)
           * (1 + (LEAST(50, GREATEST(1, coalesce(r.level, 1))) - 1) * 0.02)
           * public.pet_tier_multiplier(r.evolution_tier)
           + coalesce((result->>(b->>'key'))::numeric, 0);
      result := result || jsonb_build_object(b->>'key', round(val, 2));
    END LOOP;

    RETURN result;
  END IF;

  FOR e IN
    SELECT key, (value #>> '{}')::numeric AS amount
    FROM jsonb_each(coalesce(r.base_passives, '{}'::jsonb))
  LOOP
    result := result || jsonb_build_object(
      e.key,
      public.pet_effective_buff(e.amount, rarity, r.level, stage, e.key)
    );
  END LOOP;

  FOR b IN SELECT value FROM jsonb_array_elements(coalesce(r.secondary_buffs, '[]'::jsonb))
  LOOP
    secondary_cap := public.pet_buff_cap(b->>'key');
    val := coalesce((b->>'value')::numeric, 0) * public.pet_stage_buff_multiplier(stage)
         + coalesce((result->>(b->>'key'))::numeric, 0);
    IF secondary_cap IS NOT NULL AND secondary_cap > 0 THEN
      val := LEAST(val, secondary_cap * 1.5);
    END IF;
    result := result || jsonb_build_object(b->>'key', round(val, 2));
  END LOOP;

  RETURN result;
END
$function$;

CREATE OR REPLACE FUNCTION public.calculate_pet_combat_stats(p_player_pet_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  stage int;
  rarity text;
  effective jsonb;
  nextb jsonb := '{}'::jsonb;
  e record;
  premium boolean;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.nft_pet_id, pp.sub_nft_id,
         coalesce(pp.veteran_line, false) AS veteran_line,
         coalesce(pp.passives_override, p.base_passives) AS base_passives,
         p.is_nft_exclusive, p.name
    INTO r
    FROM public.player_pets pp
    JOIN public.pets p ON p.id = pp.pet_id
   WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;

  premium := r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL OR r.veteran_line;
  rarity := CASE
    WHEN coalesce(r.is_nft_exclusive, false) OR r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL
      THEN 'nft_exclusive'
    ELSE public.normalize_pet_rarity(r.rarity)
  END;
  stage := public.pet_stage_index(r.level, r.evolution_tier);
  effective := public.player_pet_buffs(p_player_pet_id);

  FOR e IN
    SELECT key, (value #>> '{}')::numeric AS amount
    FROM jsonb_each(coalesce(r.base_passives, '{}'::jsonb))
  LOOP
    nextb := nextb || jsonb_build_object(
      e.key,
      CASE WHEN premium
        THEN public.pet_premium_effective_buff(e.amount, rarity, r.level, LEAST(5, r.evolution_tier + 1))
        ELSE public.pet_effective_buff(e.amount, rarity, r.level, LEAST(10, stage + 1), e.key)
      END
    );
  END LOOP;

  RETURN jsonb_build_object(
    'petPlayerId', p_player_pet_id,
    'name', r.name,
    'rarity', rarity,
    'rarityOrder', public.pet_rarity_order(rarity),
    'level', r.level,
    'evolutionStage', stage,
    'evolutionTier', r.evolution_tier,
    'basePower', public.pet_rarity_base_power(rarity, rarity = 'nft_exclusive'),
    'power', public.pet_instance_power(p_player_pet_id),
    'baseBuffs', coalesce(r.base_passives, '{}'::jsonb),
    'effectiveBuffs', effective,
    'nextStageBuffs', nextb
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  ppet record;
  nxt record;
  buffs jsonb;
  nextbuffs jsonb := '{}'::jsonb;
  pkey text;
  pbase numeric;
  maxlvl int;
  nftj jsonb;
  is_nft boolean;
  premium boolean;
  stage int;
  rarity text;
  e record;
  subj jsonb;
BEGIN
  SELECT ppet2.*, p.name, p.slug, p.species, p.category,
         coalesce(ppet2.passives_override, p.base_passives) AS base_passives,
         p.active_skill, p.image_baby_url, p.image_young_url,
         p.image_adult_url, p.image_ancestral_url, p.is_nft_exclusive
    INTO ppet
    FROM public.player_pets ppet2
    JOIN public.pets p ON p.id = ppet2.pet_id
   WHERE ppet2.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;

  maxlvl := public.pet_max_level();
  buffs := public.player_pet_buffs(ppet.id);
  is_nft := coalesce(ppet.is_nft_exclusive, false)
            OR ppet.nft_pet_id IS NOT NULL
            OR ppet.sub_nft_id IS NOT NULL
            OR lower(coalesce(ppet.rarity, '')) LIKE 'nft%';
  premium := ppet.nft_pet_id IS NOT NULL OR ppet.sub_nft_id IS NOT NULL OR coalesce(ppet.veteran_line, false);
  rarity := CASE WHEN is_nft THEN 'nft_exclusive' ELSE public.normalize_pet_rarity(ppet.rarity) END;
  stage := public.pet_stage_index(ppet.level, ppet.evolution_tier);

  SELECT key, (value #>> '{}')::numeric
    INTO pkey, pbase
    FROM jsonb_each(coalesce(ppet.base_passives, '{}'::jsonb))
   ORDER BY (value #>> '{}')::numeric DESC
   LIMIT 1;

  FOR e IN
    SELECT key, (value #>> '{}')::numeric AS amount
    FROM jsonb_each(coalesce(ppet.base_passives, '{}'::jsonb))
  LOOP
    nextbuffs := nextbuffs || jsonb_build_object(
      e.key,
      CASE WHEN premium
        THEN public.pet_premium_effective_buff(e.amount, rarity, ppet.level, LEAST(5, ppet.evolution_tier + 1))
        ELSE public.pet_effective_buff(e.amount, rarity, ppet.level, LEAST(10, stage + 1), e.key)
      END
    );
  END LOOP;

  SELECT * INTO nxt
    FROM public.pet_evolution_tiers
   WHERE tier = ppet.evolution_tier + 1 AND enabled;
  SELECT jsonb_build_object('serial', n.nft_serial, 'instanceId', n.unique_instance_id,
           'status', n.status, 'minted', n.minted)
    INTO nftj FROM public.nft_pets n WHERE n.id = ppet.nft_pet_id;
  SELECT jsonb_build_object('serial', s.serial, 'instanceId', s.unique_instance_id,
           'maturityStage', s.maturity_stage, 'generation', s.generation,
           'trait', s.trait_code, 'maturesAt', s.matures_at)
    INTO subj FROM public.sub_nfts s WHERE s.id = ppet.sub_nft_id;

  RETURN jsonb_build_object(
    'id', ppet.id, 'petId', ppet.pet_id, 'name', ppet.name, 'slug', ppet.slug,
    'species', ppet.species, 'category', ppet.category, 'rarity', rarity,
    'level', ppet.level, 'maxLevel', maxlvl, 'xp', ppet.xp,
    'xpRequired', CASE WHEN ppet.level >= maxlvl THEN 0 ELSE public.pet_level_xp_required(ppet.level) END,
    'isMaxLevel', ppet.level >= maxlvl, 'evolutionTier', ppet.evolution_tier,
    'evolutionLabel', coalesce((SELECT label FROM public.pet_evolution_tiers WHERE tier = ppet.evolution_tier), 'Forma Base'),
    'evolutionStage', ppet.evolution_stage, 'growthPoints', stage,
    'growthPowerBonusPercent', round((public.pet_stage_power_multiplier(stage) - 1) * 100),
    'growthBuffBonusPercent', round((public.pet_stage_buff_multiplier(stage) - 1) * 100),
    'fragments', ppet.fragments, 'isActive', ppet.is_active,
    'image', public.pet_visual_image(ppet.pet_id, ppet.level),
    'visualStage', public.pet_visual_index(ppet.level), 'buffs', buffs,
    'nextStageBuffs', nextbuffs, 'primaryBuffKey', pkey,
    'primaryBuffValue', coalesce((buffs->>pkey)::numeric, 0),
    'secondaryBuffs', coalesce(ppet.secondary_buffs, '[]'::jsonb),
    'power', public.pet_instance_power(ppet.id),
    'nextStagePower', round(
      public.pet_rarity_base_power(rarity, is_nft)
      * (1 + (LEAST(50, GREATEST(1, ppet.level)) - 1) * 0.05)
      * public.pet_stage_power_multiplier(LEAST(10, stage + 1))
    ),
    'activeSkill', ppet.active_skill, 'isNft', is_nft,
    'nftSerial', (nftj->>'serial')::int, 'nft', nftj,
    'isSubNft', ppet.sub_nft_id IS NOT NULL, 'subNft', subj,
    'veteranLine', coalesce(ppet.veteran_line, false),
    'premiumSource', ppet.premium_source,
    'miningDailyMyth', coalesce(ppet.mining_daily_myth, 0),
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
END
$function$;

REVOKE ALL ON FUNCTION public.pet_premium_effective_buff(numeric, text, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pet_premium_effective_buff(numeric, text, integer, integer) TO service_role;