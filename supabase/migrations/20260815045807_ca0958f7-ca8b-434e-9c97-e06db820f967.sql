CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE ppet record; nxt record; buffs jsonb; pkey text; pbase numeric; maxlvl int; totals numeric; nftj jsonb; is_nft boolean;
BEGIN
  SELECT ppet2.*, p.name, p.slug, p.species, p.category, p.base_passives, p.active_skill,
         p.image_baby_url, p.image_young_url, p.image_adult_url, p.image_ancestral_url,
         p.is_nft_exclusive
    INTO ppet FROM player_pets ppet2 JOIN pets p ON p.id = ppet2.pet_id WHERE ppet2.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  maxlvl := pet_max_level();
  buffs := player_pet_buffs(ppet.id);
  -- Single source of truth for the NFT flag: template flag, real NFT instance link or rarity marker.
  is_nft := coalesce(ppet.is_nft_exclusive, false)
            OR ppet.nft_pet_id IS NOT NULL
            OR lower(coalesce(ppet.rarity,'')) LIKE 'nft%';
  SELECT key, (value#>>'{}')::numeric INTO pkey, pbase
    FROM jsonb_each(coalesce(ppet.base_passives,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  SELECT * INTO nxt FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier + 1 AND enabled;
  SELECT coalesce(sum((value#>>'{}')::numeric),0) INTO totals FROM jsonb_each(buffs);
  SELECT jsonb_build_object('serial', n.nft_serial, 'instanceId', n.unique_instance_id,
      'status', n.status, 'minted', n.minted)
    INTO nftj FROM nft_pets n WHERE n.id = ppet.nft_pet_id;
  RETURN jsonb_build_object(
    'id', ppet.id, 'petId', ppet.pet_id, 'name', ppet.name, 'slug', ppet.slug, 'species', ppet.species,
    'category', ppet.category,
    'rarity', CASE WHEN is_nft THEN 'nft_exclusive' ELSE ppet.rarity END,
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
    'primaryBuffKey', pkey,
    'primaryBuffValue', coalesce((buffs->>pkey)::numeric, 0),
    'secondaryBuffs', coalesce(ppet.secondary_buffs,'[]'::jsonb),
    'power', (CASE WHEN is_nft THEN 12000 ELSE
              CASE ppet.rarity WHEN 'ancestral' THEN 10000 WHEN 'mythic' THEN 9000 WHEN 'legendary' THEN 8000
                WHEN 'epic' THEN 4000 WHEN 'rare' THEN 2000 WHEN 'uncommon' THEN 1000 ELSE 500 END END)
              + ppet.level * 100 + round(totals * 250),
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
        'primaryTo', round(coalesce(pbase,0) * pet_rarity_multiplier(ppet.rarity)
                     * (1 + (ppet.level - 1) * 0.02) * nxt.primary_multiplier, 2)
      ) END,
    'canEvolve', nxt.tier IS NOT NULL AND ppet.level >= nxt.required_level
  );
END $fn$;

-- Safety net: NFT pets must never stay flagged as "listed in market" without an active listing.
UPDATE public.player_pets p
   SET market_locked = false, updated_at = now()
 WHERE p.market_locked
   AND (p.nft_pet_id IS NOT NULL OR lower(coalesce(p.rarity,'')) LIKE 'nft%')
   AND NOT EXISTS (SELECT 1 FROM public.market_listings l
                    WHERE l.item_instance_id = p.id AND l.status = 'active');