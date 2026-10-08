REVOKE ALL ON FUNCTION public.tg_hero_ownership_detach() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tg_pet_ownership_detach() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tg_hero_ownership_detach() TO service_role;
GRANT EXECUTE ON FUNCTION public.tg_pet_ownership_detach() TO service_role;