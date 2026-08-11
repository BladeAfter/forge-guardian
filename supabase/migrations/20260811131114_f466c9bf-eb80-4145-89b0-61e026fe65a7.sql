REVOKE SELECT ON public.global_boss_participants FROM anon, authenticated;

GRANT SELECT (
  id,
  boss_cycle_id,
  damage_total,
  attacks,
  reward_amount,
  reward_claimed,
  final_rank,
  last_attack_at,
  created_at,
  updated_at
) ON public.global_boss_participants TO anon, authenticated;

GRANT ALL ON public.global_boss_participants TO service_role;
