UPDATE public.game_settings SET value = '10', updated_at = now() WHERE key = 'clan_war_attacks_per_player';
UPDATE public.clan_wars SET attacks_per_player = attacks_per_player + 4 WHERE status IN ('scheduled','preparation','battle');
UPDATE public.clan_war_rosters r SET attacks_total = r.attacks_total + 4
WHERE EXISTS (SELECT 1 FROM public.clan_wars w WHERE w.id = r.war_id AND w.status IN ('scheduled','preparation','battle'));