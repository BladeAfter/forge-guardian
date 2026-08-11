-- Boss participants: readable by the anon game client, telegram_id still excluded
GRANT SELECT (id, boss_cycle_id, user_id, damage_total, attacks, reward_amount, reward_claimed, final_rank, last_attack_at, created_at, updated_at)
  ON public.global_boss_participants TO anon;

DROP POLICY IF EXISTS "boss ranking readable by players" ON public.global_boss_participants;
CREATE POLICY "boss ranking readable by players"
ON public.global_boss_participants FOR SELECT TO anon, authenticated USING (true);

-- Boss cycles: readable by the anon game client, internal reward fields still excluded
GRANT SELECT (id, cycle_number, boss_key, boss_name, boss_image, boss_level, max_hp, current_hp, reward_pool_fc, total_damage, participants, status, starts_at, ends_at, defeated_at, created_at, updated_at)
  ON public.global_boss_cycles TO anon;

DROP POLICY IF EXISTS "boss cycles readable by players" ON public.global_boss_cycles;
CREATE POLICY "boss cycles readable by players"
ON public.global_boss_cycles FOR SELECT TO anon, authenticated USING (true);