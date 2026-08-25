UPDATE public.clan_boss_scaling_config
SET def_scaling = 2.0,
    atk_scaling = 2.0,
    scaling_version = scaling_version + 1,
    updated_at = now()
WHERE id = 1;

UPDATE public.clan_boss_instances
SET boss_def = COALESCE(boss_def, 0) * 2,
    boss_atk = COALESCE(boss_atk, 0) * 2,
    def_multiplier = COALESCE(def_multiplier, 1) * 2,
    atk_multiplier = COALESCE(atk_multiplier, 1) * 2
WHERE status = 'active';