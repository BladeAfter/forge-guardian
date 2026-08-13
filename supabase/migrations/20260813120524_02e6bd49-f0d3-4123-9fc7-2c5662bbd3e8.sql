GRANT EXECUTE ON FUNCTION public.process_global_boss_auto_attacks(int) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.global_boss_auto_attack_state_json(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.global_boss_auto_pass_tier(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.set_global_boss_auto_attack(bigint, boolean) TO postgres, service_role;