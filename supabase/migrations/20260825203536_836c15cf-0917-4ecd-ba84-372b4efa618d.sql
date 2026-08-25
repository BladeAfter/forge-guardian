-- 1) attack pacing: 5 minutes between strikes (admin adjustable)
UPDATE public.clan_boss_config SET cooldown_seconds = 300, updated_at = now() WHERE id = 1;

-- 2) never let personal HP drift far above the player's real capacity
UPDATE public.clan_boss_personal_config
   SET capacity_ceiling = 1.25,
       max_scale_up = 1.25,
       capacity_floor = 0.50,
       updated_at = now()
 WHERE id = 1;

-- 3) recalibrate stored recommendations to real damage capacity
WITH cfg AS (SELECT target_attacks_per_boss AS t FROM public.clan_boss_personal_config WHERE id = 1)
UPDATE public.clan_boss_player_profile p
   SET recommended_hp = LEAST(
         GREATEST(p.recommended_hp, 1000000),
         GREATEST(1000000, round(GREATEST(p.official_power, COALESCE(p.recent_avg_damage, 0))
                                 * (SELECT t FROM cfg) * 1.25))),
       updated_at = now()
 WHERE p.official_power > 0 OR p.recent_avg_damage > 0;

-- 4) recalibrate active personal bosses (HP scaled down proportionally, progress kept)
WITH cfg AS (SELECT target_attacks_per_boss AS t FROM public.clan_boss_personal_config WHERE id = 1),
calc AS (
  SELECT i.id,
         GREATEST(1000000, round(GREATEST(COALESCE(p.official_power, 0), COALESCE(p.recent_avg_damage, 0))
                                 * (SELECT t FROM cfg) * 1.25)) AS cap_hp
    FROM public.clan_boss_instances i
    JOIN public.clan_boss_player_profile p ON p.user_id = i.user_id
   WHERE i.is_personal = true AND i.status = 'active'
)
UPDATE public.clan_boss_instances i
   SET max_hp = c.cap_hp,
       current_hp = LEAST(i.current_hp, c.cap_hp),
       min_damage_required = round(c.cap_hp * 0.01)
  FROM calc c
 WHERE i.id = c.id AND i.max_hp > c.cap_hp;