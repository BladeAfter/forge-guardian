CREATE TABLE public.game_bot_tutorial_deliveries (
 chat_id bigint PRIMARY KEY,
 update_id bigint NOT NULL,
 status text NOT NULL DEFAULT 'sending' CHECK (status IN ('sending','sent','failed','review')),
 message_id bigint,
 created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.game_bot_tutorial_deliveries TO service_role;
REVOKE ALL ON public.game_bot_tutorial_deliveries FROM anon, authenticated;
ALTER TABLE public.game_bot_tutorial_deliveries ENABLE ROW LEVEL SECURITY;
CREATE POLICY tutorial_service_only ON public.game_bot_tutorial_deliveries FOR ALL TO service_role USING (true) WITH CHECK (true);