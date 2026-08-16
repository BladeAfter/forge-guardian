CREATE OR REPLACE FUNCTION public.player_pet_buffs(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; result jsonb := '{}'::jsonb; e record; b jsonb; stage int; val numeric; rarity text; cap numeric; legacy boolean;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.secondary_buffs, pp.nft_pet_id,
         p.base_passives, p.is_nft_exclusive
    INTO r FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN result; END IF;

  -- Purchased NFT pets keep their ORIGINAL (legacy) buff values: rarity + level + tier
  -- multipliers, no stage/cap rebalance. Everything else uses the current formula.
  legacy := r.nft_pet_id IS NOT NULL;

  rarity := CASE WHEN coalesce(r.is_nft_exclusive,false) OR r.nft_pet_id IS NOT NULL
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

REVOKE ALL ON FUNCTION public.player_pet_buffs(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.player_pet_buffs(uuid) TO service_role;