CREATE TABLE IF NOT EXISTS public.clan_boss_reward_rollback_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rollback_id text NOT NULL,
  user_id uuid NOT NULL,
  telegram_id bigint,
  clan_boss_id uuid,
  reward_id uuid,
  reward_type text NOT NULL,
  original_quantity numeric NOT NULL DEFAULT 0,
  removed_quantity numeric NOT NULL DEFAULT 0,
  preserved_quantity numeric NOT NULL DEFAULT 0,
  reward_at timestamptz,
  reason text NOT NULL DEFAULT 'clan_boss_reward_bug',
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS clan_boss_reward_rollback_unique
  ON public.clan_boss_reward_rollback_log (rollback_id, reward_type, coalesce(reward_id, '00000000-0000-0000-0000-000000000000'::uuid), user_id);

GRANT ALL ON public.clan_boss_reward_rollback_log TO service_role;

ALTER TABLE public.clan_boss_reward_rollback_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "clan boss rollback log service only"
  ON public.clan_boss_reward_rollback_log FOR SELECT USING (false);