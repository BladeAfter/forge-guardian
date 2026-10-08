REVOKE ALL ON FUNCTION public.pet_egg_move_from_inventory(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pet_egg_move_from_inventory(uuid, uuid) TO service_role;