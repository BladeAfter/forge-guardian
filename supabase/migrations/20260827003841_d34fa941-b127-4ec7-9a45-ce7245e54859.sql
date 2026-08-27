-- ═══════════════════════════════════════════════════════════════
-- MYTHREON — GLOBAL MYSTERY ROULETTE (schema + config)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.global_roulette_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  paused boolean NOT NULL DEFAULT false,
  spin_cost_nanoton bigint NOT NULL DEFAULT 5000000000,
  celestial_threshold_nanoton bigint NOT NULL DEFAULT 300000000000,
  weight_mythic numeric NOT NULL DEFAULT 55,
  weight_nft_hero numeric NOT NULL DEFAULT 35,
  weight_celestial numeric NOT NULL DEFAULT 10,
  normal_weight_myth numeric NOT NULL DEFAULT 70,
  normal_weight_equipment numeric NOT NULL DEFAULT 30,
  myth_shortage_behavior text NOT NULL DEFAULT 'SKIP',
  payment_ttl_minutes integer NOT NULL DEFAULT 30,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.global_roulette_settings TO service_role;
ALTER TABLE public.global_roulette_settings ENABLE ROW LEVEL SECURITY;
INSERT INTO public.global_roulette_settings(id) VALUES (true) ON CONFLICT DO NOTHING;

CREATE TABLE public.roulette_myth_reserve (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  allocated_myth numeric NOT NULL DEFAULT 1000000,
  distributed_myth numeric NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.roulette_myth_reserve TO service_role;
ALTER TABLE public.roulette_myth_reserve ENABLE ROW LEVEL SECURITY;
INSERT INTO public.roulette_myth_reserve(id) VALUES (true) ON CONFLICT DO NOTHING;

CREATE TABLE public.roulette_reward_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reward_class text NOT NULL CHECK (reward_class IN ('MYTH','NFT_EQUIPMENT','MYTHIC_HERO','NFT_HERO','CELESTIAL_HERO')),
  reward_key text NOT NULL,
  label text NOT NULL DEFAULT '',
  enabled boolean NOT NULL DEFAULT true,
  weight numeric NOT NULL DEFAULT 1,
  quantity numeric NOT NULL DEFAULT 0,
  reference_cost_nanoton bigint NOT NULL DEFAULT 0,
  requires_global_threshold boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (reward_class, reward_key)
);
GRANT ALL ON public.roulette_reward_config TO service_role;
ALTER TABLE public.roulette_reward_config ENABLE ROW LEVEL SECURITY;

CREATE SEQUENCE public.global_roulette_cycle_seq START 1;
GRANT ALL ON SEQUENCE public.global_roulette_cycle_seq TO service_role;

CREATE TABLE public.global_roulette_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_number bigint NOT NULL DEFAULT nextval('public.global_roulette_cycle_seq'),
  status text NOT NULL DEFAULT 'ACCUMULATING'
    CHECK (status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING','AWARDED','CLOSED','CANCELLED')),
  target_reward_type text NOT NULL CHECK (target_reward_type IN ('MYTHIC_HERO','NFT_HERO','CELESTIAL_HERO')),
  target_reward_id text NOT NULL,
  target_reference_cost_nanoton bigint NOT NULL,
  global_spend_nanoton bigint NOT NULL DEFAULT 0,
  threshold_reached_at timestamptz,
  winner_user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  winning_spin_id uuid,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  config_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX global_roulette_cycles_number_uidx ON public.global_roulette_cycles(cycle_number);
CREATE UNIQUE INDEX global_roulette_single_open_cycle ON public.global_roulette_cycles((true))
  WHERE status IN ('ACCUMULATING','THRESHOLD_REACHED','READY_FOR_ELIGIBLE_WINNER','AWARDING');
GRANT ALL ON public.global_roulette_cycles TO service_role;
ALTER TABLE public.global_roulette_cycles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.global_roulette_spins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  cycle_id uuid REFERENCES public.global_roulette_cycles(id) ON DELETE SET NULL,
  payment_source text NOT NULL CHECK (payment_source IN ('ton_internal','ton_external')),
  amount_nanoton bigint NOT NULL,
  payment_address text,
  payment_comment text,
  tx_hash text,
  received_nanoton bigint,
  idempotency_key text,
  normal_reward_type text,
  normal_reward_amount numeric,
  normal_reward_json jsonb,
  premium_reward_awarded boolean NOT NULL DEFAULT false,
  premium_reward_type text,
  premium_reward_id text,
  result_json jsonb,
  status text NOT NULL DEFAULT 'CREATED'
    CHECK (status IN ('CREATED','PAYMENT_PENDING','PAID','RESOLVING','SETTLED','FAILED_RECOVERABLE','EXPIRED')),
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  settled_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX global_roulette_spins_idem_uidx ON public.global_roulette_spins(user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE INDEX global_roulette_spins_user_idx ON public.global_roulette_spins(user_id, created_at DESC);
CREATE INDEX global_roulette_spins_status_idx ON public.global_roulette_spins(status);
CREATE UNIQUE INDEX global_roulette_spins_tx_uidx ON public.global_roulette_spins(tx_hash) WHERE tx_hash IS NOT NULL;
GRANT ALL ON public.global_roulette_spins TO service_role;
ALTER TABLE public.global_roulette_spins ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.global_roulette_cycles
  ADD CONSTRAINT global_roulette_cycles_winning_spin_fkey
  FOREIGN KEY (winning_spin_id) REFERENCES public.global_roulette_spins(id) ON DELETE SET NULL;

-- ONE CELESTIAL PER PLAYER — enforced by the primary key itself
CREATE TABLE public.roulette_celestial_awards (
  user_id uuid PRIMARY KEY REFERENCES public.game_players(id) ON DELETE CASCADE,
  hero_key text NOT NULL,
  player_hero_id uuid,
  cycle_id uuid REFERENCES public.global_roulette_cycles(id) ON DELETE SET NULL,
  spin_id uuid REFERENCES public.global_roulette_spins(id) ON DELETE SET NULL,
  awarded_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.roulette_celestial_awards TO service_role;
ALTER TABLE public.roulette_celestial_awards ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.global_roulette_awards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  spin_id uuid REFERENCES public.global_roulette_spins(id) ON DELETE SET NULL,
  cycle_id uuid REFERENCES public.global_roulette_cycles(id) ON DELETE SET NULL,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  reward_class text NOT NULL,
  reward_key text,
  source_type text NOT NULL,
  amount numeric,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX global_roulette_awards_cycle_idx ON public.global_roulette_awards(cycle_id);
GRANT ALL ON public.global_roulette_awards TO service_role;
ALTER TABLE public.global_roulette_awards ENABLE ROW LEVEL SECURITY;

-- ═══ touch triggers ═══
CREATE OR REPLACE FUNCTION public.roulette_touch() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE TRIGGER trg_roulette_settings_touch BEFORE UPDATE ON public.global_roulette_settings
  FOR EACH ROW EXECUTE FUNCTION public.roulette_touch();
CREATE TRIGGER trg_roulette_reward_touch BEFORE UPDATE ON public.roulette_reward_config
  FOR EACH ROW EXECUTE FUNCTION public.roulette_touch();
CREATE TRIGGER trg_roulette_cycles_touch BEFORE UPDATE ON public.global_roulette_cycles
  FOR EACH ROW EXECUTE FUNCTION public.roulette_touch();
CREATE TRIGGER trg_roulette_spins_touch BEFORE UPDATE ON public.global_roulette_spins
  FOR EACH ROW EXECUTE FUNCTION public.roulette_touch();

-- ═══ SEED — normal rewards ═══
INSERT INTO public.roulette_reward_config(reward_class, reward_key, label, weight, quantity) VALUES
  ('MYTH','myth_small','MYTH SMALL',55,5000),
  ('MYTH','myth_medium','MYTH MEDIUM',33,15000),
  ('MYTH','myth_large','MYTH LARGE',12,50000);

INSERT INTO public.roulette_reward_config(reward_class, reward_key, label, weight) VALUES
  ('NFT_EQUIPMENT','rare','NFT EQUIPMENT — RARE',60),
  ('NFT_EQUIPMENT','epic','NFT EQUIPMENT — EPIC',30),
  ('NFT_EQUIPMENT','legendary','NFT EQUIPMENT — LEGENDARY',10);

-- ═══ SEED — mystery pools ═══
INSERT INTO public.roulette_reward_config(reward_class, reward_key, label, weight, reference_cost_nanoton, requires_global_threshold)
SELECT 'MYTHIC_HERO', hero_key, name, 1, 15000000000, true
  FROM public.hero_catalog
 WHERE rarity = 'mythic' AND enabled AND coalesce(is_nft_exclusive,false) = false
ON CONFLICT DO NOTHING;

INSERT INTO public.roulette_reward_config(reward_class, reward_key, label, weight, reference_cost_nanoton, requires_global_threshold)
SELECT 'NFT_HERO', c.hero_key, c.name, 1,
       (greatest(30, ceil(coalesce(max(n.price_ton), 30) / 5) * 5) * 1000000000)::bigint, true
  FROM public.nft_heroes n
  JOIN public.hero_catalog c ON c.hero_key = n.hero_template_id
 WHERE n.owner_user_id IS NULL AND n.status = 'AVAILABLE'
 GROUP BY c.hero_key, c.name
ON CONFLICT DO NOTHING;

INSERT INTO public.roulette_reward_config(reward_class, reward_key, label, weight, reference_cost_nanoton, requires_global_threshold)
SELECT 'CELESTIAL_HERO', hero_key, name, 1, 300000000000, true
  FROM public.hero_catalog WHERE rarity = 'celestial'
ON CONFLICT DO NOTHING;