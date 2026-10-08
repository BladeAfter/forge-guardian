UPDATE public.clan_boss_instances i
   SET rewards_snapshot = (SELECT c.rewards FROM public.clan_boss_config c WHERE c.id = 1)
 WHERE i.status = 'active';