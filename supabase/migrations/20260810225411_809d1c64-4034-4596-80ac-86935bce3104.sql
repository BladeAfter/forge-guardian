CREATE TABLE IF NOT EXISTS public.admin_bot_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_telegram_id bigint NOT NULL,
  chat_id bigint NOT NULL,
  action text NOT NULL,
  step text NOT NULL DEFAULT 'awaiting_input',
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '15 minutes',
  CONSTRAINT admin_bot_sessions_unique UNIQUE (admin_telegram_id, chat_id)
);

GRANT ALL ON public.admin_bot_sessions TO service_role;

ALTER TABLE public.admin_bot_sessions ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS admin_bot_sessions_expires_idx ON public.admin_bot_sessions (expires_at);

CREATE OR REPLACE FUNCTION public.admin_bot_sessions_touch()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS admin_bot_sessions_touch_trg ON public.admin_bot_sessions;
CREATE TRIGGER admin_bot_sessions_touch_trg
BEFORE UPDATE ON public.admin_bot_sessions
FOR EACH ROW EXECUTE FUNCTION public.admin_bot_sessions_touch();