CREATE TABLE IF NOT EXISTS public.myth_sale_public_stats (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  sold numeric NOT NULL DEFAULT 0,
  burned numeric NOT NULL DEFAULT 0,
  reserved numeric NOT NULL DEFAULT 0,
  available numeric NOT NULL DEFAULT 0,
  ton_raised numeric NOT NULL DEFAULT 0,
  myth_per_ton numeric NOT NULL DEFAULT 20000,
  sale_status text NOT NULL DEFAULT 'paused',
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.myth_sale_public_stats TO anon, authenticated;
GRANT ALL ON public.myth_sale_public_stats TO service_role;
ALTER TABLE public.myth_sale_public_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "MYTH sale stats are public" ON public.myth_sale_public_stats;
CREATE POLICY "MYTH sale stats are public" ON public.myth_sale_public_stats FOR SELECT USING (true);
INSERT INTO public.myth_sale_public_stats (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.myth_sale_refresh_public_stats()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s jsonb;
BEGIN
  s := public.myth_sale_stats();
  UPDATE public.myth_sale_public_stats SET
    sold = (s->>'sold')::numeric,
    burned = (s->>'burned')::numeric,
    reserved = (s->>'reserved')::numeric,
    available = (s->>'available')::numeric,
    ton_raised = (s->>'tonRaised')::numeric,
    myth_per_ton = (s->>'mythPerTon')::numeric,
    sale_status = s->>'saleStatus',
    updated_at = now()
  WHERE id;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS myth_sale_tx_stats ON public.myth_sale_transactions;
CREATE TRIGGER myth_sale_tx_stats AFTER INSERT OR UPDATE ON public.myth_sale_transactions
  FOR EACH STATEMENT EXECUTE FUNCTION public.myth_sale_refresh_public_stats();
DROP TRIGGER IF EXISTS myth_burn_stats ON public.myth_burn_history;
CREATE TRIGGER myth_burn_stats AFTER INSERT ON public.myth_burn_history
  FOR EACH STATEMENT EXECUTE FUNCTION public.myth_sale_refresh_public_stats();
DROP TRIGGER IF EXISTS myth_config_stats ON public.myth_sale_config;
CREATE TRIGGER myth_config_stats AFTER UPDATE ON public.myth_sale_config
  FOR EACH STATEMENT EXECUTE FUNCTION public.myth_sale_refresh_public_stats();
DROP TRIGGER IF EXISTS myth_intent_stats ON public.myth_payment_intents;
CREATE TRIGGER myth_intent_stats AFTER INSERT OR UPDATE ON public.myth_payment_intents
  FOR EACH STATEMENT EXECUTE FUNCTION public.myth_sale_refresh_public_stats();

DO $$ BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.myth_sale_public_stats; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
ALTER TABLE public.myth_sale_public_stats REPLICA IDENTITY FULL;