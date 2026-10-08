-- 1) Per-instance passive overrides (used by Sub-NFT offspring)
alter table public.player_pets add column if not exists passives_override jsonb;

-- 2) Inherited passives: strongest of both parents, +25% superiority
create or replace function public.sub_nft_passives(p_sub_nft_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare s public.sub_nfts; res jsonb := '{}'::jsonb; e record; boost numeric := 1.25;
begin
  select * into s from public.sub_nfts where id = p_sub_nft_id;
  if s.id is null then return res; end if;
  for e in
    select key, max((value#>>'{}')::numeric) as amount
      from (
        select p.base_passives as bp
          from public.nft_pets n join public.pets p on p.id = n.pet_template_id
         where n.id in (s.parent_a_nft_id, s.parent_b_nft_id)
        union all
        select p2.base_passives
          from public.sub_nft_templates t join public.pets p2 on p2.id = t.pet_template_id
         where t.id = s.template_id
      ) src, jsonb_each(coalesce(src.bp, '{}'::jsonb))
     group by key
  loop
    res := res || jsonb_build_object(e.key, round(e.amount * boost, 2));
  end loop;
  return res;
end $$;

-- 3) Buffs / power / bonuses honour the override and treat Sub-NFTs as NFT tier
create or replace function public.player_pet_buffs(p_player_pet_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
DECLARE r record; result jsonb := '{}'::jsonb; e record; b jsonb; stage int; val numeric; rarity text; cap numeric; legacy boolean;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.secondary_buffs, pp.nft_pet_id, pp.sub_nft_id,
         coalesce(pp.passives_override, p.base_passives) AS base_passives,
         p.is_nft_exclusive
    INTO r FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN result; END IF;

  legacy := r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL;
  rarity := CASE WHEN coalesce(r.is_nft_exclusive,false) OR r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL
                 THEN 'nft_exclusive' ELSE normalize_pet_rarity(r.rarity) END;
  stage := pet_stage_index(r.level, r.evolution_tier);

  IF legacy THEN
    FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(coalesce(r.base_passives,'{}'::jsonb)) LOOP
      val := round(e.amount * pet_rarity_multiplier(rarity) * (1 + (GREATEST(1, r.level) - 1) * 0.02)
                   * pet_tier_multiplier(r.evolution_tier), 2);
      result := result || jsonb_build_object(e.key, val);
    END LOOP;
    FOR b IN SELECT value FROM jsonb_array_elements(coalesce(r.secondary_buffs,'[]'::jsonb)) LOOP
      val := coalesce((b->>'value')::numeric, 0) + coalesce((result->>(b->>'key'))::numeric, 0);
      result := result || jsonb_build_object(b->>'key', round(val, 2));
    END LOOP;
    FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(result) LOOP
      SELECT (value->>e.key)::numeric INTO cap FROM pet_settings WHERE key = 'bonus_caps';
      IF cap IS NOT NULL AND e.amount > cap THEN result := result || jsonb_build_object(e.key, cap); END IF;
    END LOOP;
    RETURN result;
  END IF;

  FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(coalesce(r.base_passives,'{}'::jsonb)) LOOP
    result := result || jsonb_build_object(e.key, pet_effective_buff(e.amount, rarity, r.level, stage, e.key));
  END LOOP;
  FOR b IN SELECT value FROM jsonb_array_elements(coalesce(r.secondary_buffs,'[]'::jsonb)) LOOP
    val := coalesce((b->>'value')::numeric, 0) * pet_stage_buff_multiplier(stage)
         + coalesce((result->>(b->>'key'))::numeric, 0);
    result := result || jsonb_build_object(b->>'key', round(LEAST(val, GREATEST(pet_buff_cap(b->>'key'), 0) * 1.5), 2));
  END LOOP;
  RETURN result;
END $$;

create or replace function public.pet_instance_power(p_player_pet_id uuid)
returns numeric language plpgsql stable security definer set search_path=public as $$
DECLARE r record; stage int; rarity text; base numeric; buff_sum numeric;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.nft_pet_id, pp.sub_nft_id, p.is_nft_exclusive
    INTO r FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN 0; END IF;
  rarity := CASE WHEN coalesce(r.is_nft_exclusive,false) OR r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL
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
    + CASE WHEN r.sub_nft_id IS NOT NULL THEN 2500 ELSE 0 END
  );
END $$;

create or replace function public.get_pet_bonuses(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r record; result jsonb := '{}'; k text; base numeric; cap numeric; final numeric; evo numeric; stage int; core numeric;
begin
  select pp.rarity, pp.level, coalesce(pp.passives_override, p.base_passives) as base_passives,
         pp.sub_nft_id, p.is_nft_exclusive, pp.nft_pet_id
    into r
    from player_pets pp join pets p on p.id = pp.pet_id
   where pp.user_id = p_user and pp.is_active;
  if not found then return result; end if;
  if r.sub_nft_id is not null then r.rarity := 'nft_exclusive'; end if;
  stage := greatest(0, coalesce(public.pet_visual_index(coalesce(r.level, 1)), 0));
  evo := 1 + 0.15 * stage;
  for k, base in select key, value::text::numeric from jsonb_each(r.base_passives) loop
    select (value->>k)::numeric into cap from pet_settings where key = 'bonus_caps';
    core := base * pet_rarity_multiplier(r.rarity);
    if cap is not null then core := least(core, cap); end if;
    final := round(core * (1 + (coalesce(r.level,1) - 1) * .02) * evo, 2);
    result := result || jsonb_build_object(k, final);
  end loop;
  return result;
end $$;

-- 4) Pet card JSON: Sub-NFTs expose inherited passives, NFT tier and a SUB-NFT flag
create or replace function public.player_pet_json(p_player_pet_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
DECLARE ppet record; nxt record; buffs jsonb; nextbuffs jsonb; pkey text; pbase numeric; maxlvl int; nftj jsonb; is_nft boolean; stage int; rarity text; e record; subj jsonb;
BEGIN
  SELECT ppet2.*, p.name, p.slug, p.species, p.category,
         coalesce(ppet2.passives_override, p.base_passives) AS base_passives, p.active_skill,
         p.image_baby_url, p.image_young_url, p.image_adult_url, p.image_ancestral_url,
         p.is_nft_exclusive
    INTO ppet FROM player_pets ppet2 JOIN pets p ON p.id = ppet2.pet_id WHERE ppet2.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  maxlvl := pet_max_level();
  buffs := player_pet_buffs(ppet.id);
  is_nft := coalesce(ppet.is_nft_exclusive, false)
            OR ppet.nft_pet_id IS NOT NULL
            OR ppet.sub_nft_id IS NOT NULL
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
  SELECT jsonb_build_object('serial', s.serial, 'instanceId', s.unique_instance_id,
      'maturityStage', s.maturity_stage, 'generation', s.generation, 'trait', s.trait_code,
      'maturesAt', s.matures_at)
    INTO subj FROM sub_nfts s WHERE s.id = ppet.sub_nft_id;
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
    'isSubNft', ppet.sub_nft_id IS NOT NULL,
    'subNft', subj,
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
END $$;

-- 5) Newly bred Sub-NFTs are born NFT tier, unlocked for battle/expedition, with inherited passives
create or replace function public.sub_nft_mint(p_owner uuid, p_req nft_breeding_requests, p_cost numeric, p_side text)
returns uuid language plpgsql security definer set search_path=public as $$
declare s public.nft_breeding_settings; tpl public.sub_nft_templates; el_a text; el_b text;
        trait text; v_id uuid; v_pet uuid; v_serial bigint;
begin
  select * into s from public.nft_breeding_settings where id;
  select coalesce(element,'neutral') into el_a from public.nft_pets where id = p_req.nft_a_id;
  select coalesce(element,'neutral') into el_b from public.nft_pets where id = p_req.nft_b_id;

  select * into tpl from public.sub_nft_templates
   where enabled and (element in (el_a, el_b) or coalesce(secondary_element,'') in (el_a, el_b))
     and not exists (select 1 from public.player_pets pp
                      where pp.user_id = p_owner and pp.pet_id = sub_nft_templates.pet_template_id)
   order by random() limit 1;
  if tpl.id is null then
    select * into tpl from public.sub_nft_templates
     where enabled and not exists (select 1 from public.player_pets pp
             where pp.user_id = p_owner and pp.pet_id = sub_nft_templates.pet_template_id)
     order by random() limit 1;
  end if;
  if tpl.id is null then
    select * into tpl from public.sub_nft_templates where enabled order by random() limit 1;
  end if;
  if tpl.id is null then raise exception 'NO_SUB_NFT_TEMPLATE'; end if;

  select code into trait from public.sub_nft_traits where enabled order by random() * (1.0 / greatest(weight,1)) limit 1;
  v_serial := nextval('public.sub_nft_serial_seq');

  insert into public.sub_nfts(serial, unique_instance_id, owner_user_id, template_id, breeding_id,
      parent_a_nft_id, parent_b_nft_id, generation, trait_code, birth_time, maturity_stage, matures_at,
      mining_rate_ton_day, mining_cap_ton)
  values (v_serial, 'SUB-NFT #' || lpad(v_serial::text, 6, '0'), p_owner, tpl.id, p_req.id,
      p_req.nft_a_id, p_req.nft_b_id, 1, trait, now(), 'EGG', now() + make_interval(hours => s.adult_hours),
      round(p_cost / 40.0, 9), round(p_cost, 9))
  returning id into v_id;

  if tpl.pet_template_id is not null then
    insert into public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments,
        is_active, tradable, market_locked, sub_nft_id, passives_override)
    values (p_owner, tpl.pet_template_id, 'nft_exclusive', 1, 0, 'baby', 0, false, false, false, v_id,
        public.sub_nft_passives(v_id))
    returning id into v_pet;
    update public.sub_nfts set player_pet_id = v_pet where id = v_id;
  end if;

  return v_id;
end $$;