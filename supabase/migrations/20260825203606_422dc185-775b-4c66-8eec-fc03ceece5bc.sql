UPDATE public.clan_boss_personal_config SET min_hp = 50000, updated_at = now() WHERE id = 1;

WITH cfg AS (SELECT target_attacks_per_boss AS t, min_hp AS mh FROM public.clan_boss_personal_config WHERE id = 1)
UPDATE public.clan_boss_player_profile p
   SET recommended_hp = GREATEST((SELECT mh FROM cfg),
         LEAST(p.recommended_hp,
               round(GREATEST(p.official_power, COALESCE(p.recent_avg_damage, 0)) * (SELECT t FROM cfg) * 1.25))),
       updated_at = now();

WITH cfg AS (SELECT target_attacks_per_boss AS t, min_hp AS mh FROM public.clan_boss_personal_config WHERE id = 1),
calc AS (
  SELECT i.id,
         GREATEST((SELECT mh FROM cfg),
                  round(GREATEST(COALESCE(p.official_power, 0), COALESCE(p.recent_avg_damage, 0))
                        * (SELECT t FROM cfg) * 1.25)) AS cap_hp
    FROM public.clan_boss_instances i
    JOIN public.clan_boss_player_profile p ON p.user_id = i.user_id
   WHERE i.is_personal = true AND i.status = 'active'
)
UPDATE public.clan_boss_instances i
   SET max_hp = c.cap_hp,
       current_hp = LEAST(i.current_hp, c.cap_hp),
       min_damage_required = GREATEST(1, round(c.cap_hp * 0.01))
  FROM calc c
 WHERE i.id = c.id AND i.max_hp > c.cap_hp;