-- Single source of truth for pet buffs: whatever percentage the UI shows must be
-- exactly what combat (Arena, Boss, Clan Boss, Tactical, farming, rewards) applies.
-- 1) pet_effective_buff now applies the rarity multiplier (it was silently ignored,
--    so combat buffs were much weaker than the values displayed on the pet card).
CREATE OR REPLACE FUNCTION public.pet_effective_buff(p_base numeric, p_rarity text, p_level integer, p_stage integer, p_key text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE raw numeric; cap numeric; lvl int;
BEGIN
  IF p_base IS NULL OR p_base <= 0 THEN RETURN coalesce(p_base, 0); END IF;
  lvl := LEAST(50, GREATEST(1, coalesce(p_level, 1)));
  -- Always from the ORIGINAL base value: no recursive compounding.
  raw := p_base
       * public.pet_rarity_multiplier(p_rarity)
       * public.pet_stage_buff_multiplier(p_stage)
       * (1 + (lvl - 1) * 0.005);
  cap := public.pet_buff_cap(p_key);
  IF cap IS NOT NULL AND raw > cap THEN
    raw := cap;
  END IF;
  RETURN round(LEAST(raw, 150), 2);
END $function$;

-- 2) get_pet_bonuses (read by the Pets screen and by gameplay bonus lookups) now
--    delegates to player_pet_buffs, the same function combat uses. No second formula.
CREATE OR REPLACE FUNCTION public.get_pet_bonuses(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_pet uuid;
begin
  select pp.id into v_pet from player_pets pp where pp.user_id = p_user and pp.is_active limit 1;
  if v_pet is null then return '{}'::jsonb; end if;
  return coalesce(public.player_pet_buffs(v_pet), '{}'::jsonb);
end $function$;