CREATE OR REPLACE FUNCTION public.player_pet_buffs(p_player_pet_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
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
  cel_scale numeric;
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

  rarity := CASE
    WHEN public.normalize_pet_rarity(r.rarity) = 'celestial' THEN 'celestial'
    WHEN coalesce(r.is_nft_exclusive, false) OR r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL
      THEN 'nft_exclusive'
    ELSE public.normalize_pet_rarity(r.rarity)
  END;
  stage := public.pet_stage_index(r.level, r.evolution_tier);

  -- CELESTIAL: base official values grow with level (+2% per level) and with each form stage (+5%).
  IF rarity = 'celestial' THEN
    cel_scale := (1 + (LEAST(50, GREATEST(1, coalesce(r.level, 1))) - 1) * 0.02)
               * (1 + GREATEST(0, coalesce(stage, 0)) * 0.05);
    FOR e IN
      SELECT key, (value #>> '{}')::numeric AS amount
      FROM jsonb_each(coalesce(r.base_passives, '{}'::jsonb))
    LOOP
      result := result || jsonb_build_object(e.key, round(e.amount * cel_scale, 2));
    END LOOP;
    FOR b IN SELECT value FROM jsonb_array_elements(coalesce(r.secondary_buffs, '[]'::jsonb))
    LOOP
      val := coalesce((b->>'value')::numeric, 0) * cel_scale
           + coalesce((result->>(b->>'key'))::numeric, 0);
      result := result || jsonb_build_object(b->>'key', round(val, 2));
    END LOOP;
    RETURN result;
  END IF;

  premium := r.nft_pet_id IS NOT NULL OR r.sub_nft_id IS NOT NULL OR r.veteran_line;

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
$fn$;
