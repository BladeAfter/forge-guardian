-- Buffs are authored per rarity in the template, so the rarity multiplier must NOT be
-- re-applied on top (that is what pushed every strong pet straight into the cap).
-- Official rule: effective = base * evolution_stage_multiplier * small level factor, then capped.
UPDATE public.pet_settings SET value = jsonb_build_object(
  'boss_damage_percent',60,'boss_damage_reduction_percent',45,'team_hp_percent',60,
  'pvp_attack_percent',60,'pvp_defense_percent',60,'pvp_speed_percent',30,
  'defense_percent',60,'critical_chance_percent',30,'reward_percent',40,
  'mission_reward_percent',30,'random_reward_percent',30,'drop_chance_percent',30,
  'egg_luck_percent',30,'farm_fc_percent',45,'offline_production_percent',45,
  'hero_xp_percent',45,'account_xp_percent',45,'revive_speed_percent',80,
  'mission_progress_percent',30
) WHERE key = 'bonus_caps';

CREATE OR REPLACE FUNCTION public.pet_effective_buff(p_base numeric, p_rarity text, p_level integer, p_stage integer, p_key text)
RETURNS numeric LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE raw numeric; cap numeric; lvl int;
BEGIN
  IF p_base IS NULL OR p_base <= 0 THEN RETURN coalesce(p_base, 0); END IF;
  lvl := LEAST(50, GREATEST(1, coalesce(p_level, 1)));
  -- Always from the ORIGINAL base value: no recursive compounding, no rarity re-multiplication.
  raw := p_base * public.pet_stage_buff_multiplier(p_stage) * (1 + (lvl - 1) * 0.005);
  cap := public.pet_buff_cap(p_key);
  IF cap IS NOT NULL AND raw > cap THEN
    IF raw > cap * 3 THEN RAISE WARNING 'PET_BUFF_OUT_OF_RANGE key=% raw=% cap=%', p_key, raw, cap; END IF;
    raw := cap;
  END IF;
  RETURN round(LEAST(raw, 150), 2);
END $$;

-- Mythic season-pass pets deserve mythic-grade passives (they shipped with none at all).
UPDATE public.pets
   SET base_passives = jsonb_build_object('pvp_attack_percent', 18, 'boss_damage_percent', 15, 'team_hp_percent', 15)
 WHERE slug IN ('pass-astravax','pass-thornyx','pass-emberix','pass-noctari','pass-crysalune','pass-sylvaris-prime','pass-vulkaryn-prime');
