-- 1) Expose the VETERAN line + MYTH daily rate in the pet payload the client reads.
CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
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
    -- Premium packs: superior VETERAN line, MYTH-only mining (never TON).
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
END $function$;

-- 2) VETERAN heroes never accrue TON mining (they are paid in MYTH by the premium pools).
CREATE OR REPLACE FUNCTION public.hero_mining_settle_all()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_now timestamptz := now(); v_currency text := hero_mining_currency();
        v_ton_total numeric := 0; v_myth_total numeric := 0;
BEGIN
  DROP TABLE IF EXISTS _mining_settle;
  CREATE TEMP TABLE _mining_settle ON COMMIT DROP AS
  WITH elig AS (
    SELECT h.id, h.user_id,
           CASE WHEN COALESCE(h.pass_exclusive,false) OR COALESCE(h.veteran_line,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           CASE WHEN COALESCE(h.pass_exclusive,false) OR COALESCE(h.veteran_line,false) THEN 0
                ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id IS NOT NULL
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.user_id AS user_id, e.rate AS rate, e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT user_id,
         round(SUM(CASE WHEN rate > 0 AND v_currency = 'ton' THEN rate * secs / 86400.0 ELSE 0 END), 9) AS ton_gain,
         round(SUM(CASE WHEN rate > 0 AND v_currency = 'myth' THEN myth_rate * secs / 86400.0 ELSE 0 END), 9) AS myth_gain
    FROM moved GROUP BY user_id;

  IF v_currency = 'ton' THEN
    UPDATE game_players g
       SET hero_mining_unclaimed_ton = round(COALESCE(g.hero_mining_unclaimed_ton,0)
             + LEAST(s.ton_gain, GREATEST(0, COALESCE(g.hero_mining_invested_ton,0)
               - COALESCE(g.hero_mining_returned_ton,0) - COALESCE(g.hero_mining_unclaimed_ton,0))), 9),
           updated_at = now()
      FROM _mining_settle s
     WHERE g.id = s.user_id AND s.ton_gain > 0;
    SELECT COALESCE(SUM(ton_gain),0) INTO v_ton_total FROM _mining_settle;
  ELSE
    UPDATE game_players g
       SET hero_mining_unclaimed_myth = round(COALESCE(g.hero_mining_unclaimed_myth,0) + s.myth_gain, 9),
           updated_at = now()
      FROM _mining_settle s
     WHERE g.id = s.user_id AND s.myth_gain > 0;
    SELECT COALESCE(SUM(myth_gain),0) INTO v_myth_total FROM _mining_settle;
  END IF;

  IF v_myth_total > 0 THEN
    INSERT INTO nft_mining_ledger (entry_type, currency, amount, meta)
    VALUES ('NFT_MINING_MYTH_ACCRUAL', 'myth', v_myth_total, jsonb_build_object('scope','settle_all'));
  END IF;

  RETURN jsonb_build_object('currency', v_currency, 'tonAccrued', v_ton_total, 'mythAccrued', v_myth_total, 'settledAt', v_now);
END $function$;

CREATE OR REPLACE FUNCTION public.hero_mining_settle_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_gain numeric := 0; v_secs numeric; v_room numeric := 0; v_currency text := hero_mining_currency();
BEGIN
  IF OLD.user_id IS NOT NULL AND v_currency = 'ton' THEN
    v_room := COALESCE(hero_mining_remaining(OLD.user_id), 0);
  END IF;

  IF NOT COALESCE(OLD.market_locked, false)
     AND NOT COALESCE(OLD.is_nft_exclusive, false)
     AND NOT COALESCE(OLD.veteran_line, false)
     AND hero_mining_enabled()
     AND (v_currency = 'myth' OR v_room > 0) THEN
    v_secs := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(OLD.mining_last_at, OLD.created_at, now()))));
    IF v_currency = 'myth' THEN
      v_gain := CASE WHEN hero_mining_rate(OLD.rarity) > 0
                     THEN round(hero_mining_myth_per_day() * v_secs / 86400.0, 9) ELSE 0 END;
    ELSE
      v_gain := round(LEAST(hero_mining_rate(OLD.rarity) * v_secs / 86400.0, v_room), 9);
    END IF;
  END IF;

  IF v_gain > 0 AND OLD.user_id IS NOT NULL THEN
    IF v_currency = 'myth' THEN
      UPDATE game_players
         SET hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_gain, 9),
             updated_at = now()
       WHERE id = OLD.user_id;
    ELSE
      UPDATE game_players
         SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
             updated_at = now()
       WHERE id = OLD.user_id;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN NEW.mining_last_at := now(); RETURN NEW; END IF;
  RETURN OLD;
END $function$;