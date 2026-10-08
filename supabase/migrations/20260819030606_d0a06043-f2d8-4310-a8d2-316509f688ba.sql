CREATE TABLE IF NOT EXISTS public.myth_sale_milestone_claims (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  milestone_amount bigint NOT NULL,
  myth_total bigint NOT NULL DEFAULT 0,
  rewards jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, milestone_amount)
);
GRANT SELECT ON public.myth_sale_milestone_claims TO authenticated;
GRANT ALL ON public.myth_sale_milestone_claims TO service_role;
ALTER TABLE public.myth_sale_milestone_claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Players read their own milestone deliveries"
  ON public.myth_sale_milestone_claims FOR SELECT TO authenticated
  USING (user_id = auth.uid());