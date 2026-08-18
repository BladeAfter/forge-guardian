CREATE OR REPLACE FUNCTION public.tactical_build_units(p_user uuid, p_side text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_buffs jsonb := COALESCE(public.get_pet_bonuses(p_user), '{}'::jsonb);
        v_units jsonb := '{}'::jsonb; rec record; v_uid text; v_atk numeric; v_hp numeric; v_def numeric; v_spd numeric;
        v_hp_bonus numeric := public.pet_hp_bonus_percent(COALESCE(public.get_pet_bonuses(p_user), '{}'::jsonb));
BEGIN
  FOR rec IN
    SELECT t.slot, h.* FROM public.tactical_teams t
    JOIN public.player_heroes h ON h.id = t.player_hero_id
    WHERE t.user_id = p_user ORDER BY t.slot
  LOOP
    v_uid := p_side || rec.slot::text;
    v_atk := GREATEST(1, round(COALESCE(rec.final_atk,1) * (1 + COALESCE((v_buffs->>'pvp_attack_percent')::numeric,0)/100)));
    v_hp  := GREATEST(1, round(COALESCE(rec.final_hp,1) * (1 + v_hp_bonus/100)));
    v_def := round(COALESCE(rec.final_hp,0) * 0.09 * (1 + COALESCE((v_buffs->>'pvp_defense_percent')::numeric,0)/100));
    v_spd := GREATEST(1, round((90 + COALESCE(rec.level,1)) * (1 + COALESCE((v_buffs->>'pvp_speed_percent')::numeric,0)/100)));
    v_units := v_units || jsonb_build_object(v_uid, jsonb_build_object(
      'uid', v_uid, 'side', p_side, 'slot', rec.slot, 'heroId', rec.id,
      'name', rec.name, 'image', rec.image, 'rarity', public.normalize_hero_rarity(rec.rarity),
      'level', rec.level, 'class', lower(COALESCE(rec.archetype,'warrior')),
      'atk', v_atk, 'hp', v_hp, 'maxHp', v_hp, 'def', v_def, 'speed', v_spd,
      'crit', GREATEST(5, COALESCE((v_buffs->>'critical_chance_percent')::numeric,0) + 5),
      'critMult', 1.5 + COALESCE((v_buffs->>'critical_damage_percent')::numeric,0)/100,
      'shield', 0, 'alive', true, 'statuses', '[]'::jsonb, 'cds', '{}'::jsonb,
      'isNft', COALESCE(rec.is_nft_exclusive,false)
    ));
  END LOOP;
  RETURN v_units;
END $function$;