-- 1) Boss combat now uses the hero's REAL stats (single source of truth)
CREATE OR REPLACE FUNCTION public.hero_boss_stats(p_player_hero_id uuid)
 RETURNS TABLE(base_atk numeric, final_atk numeric, base_hp numeric, max_hp integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    greatest(1, coalesce(h.base_atk, h.final_atk, 1))::numeric,
    greatest(1, round((coalesce(h.final_atk, h.base_atk, 1) + coalesce(h.equip_atk, 0))::numeric, 2)),
    greatest(1, coalesce(h.base_hp, h.final_hp, 1))::numeric,
    greatest(1, round(coalesce(h.final_hp, h.base_hp, 1) + coalesce(h.equip_hp, 0)))::int
  from public.player_heroes h where h.id = p_player_hero_id
$function$;

REVOKE ALL ON FUNCTION public.hero_boss_stats(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hero_boss_stats(uuid) TO service_role;

-- 2) Rebuild every active combat state with the corrected stats and full heal
UPDATE public.hero_combat_state s
   SET base_atk = st.base_atk,
       final_atk = st.final_atk,
       base_hp = st.base_hp,
       max_hp = st.max_hp,
       current_hp = st.max_hp,
       is_alive = true,
       knocked_out_at = null,
       revive_at = null,
       revive_protected = false,
       revive_attack_used = false,
       revive_attack_at = null,
       revive_protected_until = null,
       rarity = public.normalize_hero_rarity(h.rarity),
       level = greatest(1, h.level),
       updated_at = now()
  FROM public.player_heroes h
  CROSS JOIN LATERAL public.hero_boss_stats(h.id) st
 WHERE h.id = s.hero_id;

-- 3) Season Pass V2: unlock the full 50-level track already seeded in rewards
UPDATE public.season_pass_seasons s
   SET levels = GREATEST(s.levels, (SELECT COALESCE(max(r.level), s.levels)
                                      FROM public.season_pass_rewards r
                                     WHERE r.season_id = s.id AND r.enabled)),
       updated_at = now()
 WHERE s.active;