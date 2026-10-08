create or replace function public.get_pet_bonuses(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
DECLARE pid uuid;
BEGIN
  SELECT id INTO pid
    FROM player_pets
   WHERE user_id = p_user
     AND is_active
     AND NOT coalesce(market_locked, false)
   ORDER BY level DESC, created_at
   LIMIT 1;
  IF pid IS NULL THEN RETURN '{}'::jsonb; END IF;
  RETURN player_pet_buffs(pid);
END $$;

grant execute on function public.get_pet_bonuses(uuid) to authenticated, service_role;