UPDATE public.clan_boss_scaling_config
   SET cycle_lock_enabled = false,
       cycle_lock_hours = 0,
       updated_at = now()
 WHERE id = 1;