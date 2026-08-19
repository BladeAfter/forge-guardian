-- =========================================================
-- VETERAN VAULT V2 — schema
-- =========================================================
ALTER TABLE public.hero_catalog        ADD COLUMN IF NOT EXISTS veteran_line boolean NOT NULL DEFAULT false;
ALTER TABLE public.pets                ADD COLUMN IF NOT EXISTS veteran_line boolean NOT NULL DEFAULT false;
ALTER TABLE public.pets                ADD COLUMN IF NOT EXISTS veteran_role text;
ALTER TABLE public.pet_eggs            ADD COLUMN IF NOT EXISTS veteran_line boolean NOT NULL DEFAULT false;
ALTER TABLE public.pet_eggs            ADD COLUMN IF NOT EXISTS veteran_dragon_pet_id uuid REFERENCES public.pets(id);
ALTER TABLE public.equipment_templates ADD COLUMN IF NOT EXISTS veteran_line boolean NOT NULL DEFAULT false;
ALTER TABLE public.player_heroes       ADD COLUMN IF NOT EXISTS veteran_line boolean NOT NULL DEFAULT false;
ALTER TABLE public.player_pets         ADD COLUMN IF NOT EXISTS veteran_line boolean NOT NULL DEFAULT false;
ALTER TABLE public.player_equipment    ADD COLUMN IF NOT EXISTS veteran_line boolean NOT NULL DEFAULT false;

-- config -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.veteran_vault_v2_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  sales_paused boolean NOT NULL DEFAULT false,
  package_version text NOT NULL DEFAULT 'VETERAN_VAULT_V1',
  price_ton numeric NOT NULL DEFAULT 100,
  popup_enabled boolean NOT NULL DEFAULT true,
  popup_frequency text NOT NULL DEFAULT 'UNTIL_PURCHASED'
    CHECK (popup_frequency IN ('ONCE_PER_SESSION','ONCE_PER_DAY','UNTIL_PURCHASED','DISABLED')),
  boost_percent numeric NOT NULL DEFAULT 10,
  hero_daily_myth numeric NOT NULL DEFAULT 10000,
  pet_daily_myth numeric NOT NULL DEFAULT 5000,
  dragon_daily_myth numeric NOT NULL DEFAULT 20000,
  myth_reward numeric NOT NULL DEFAULT 1000000,
  legendary_chests integer NOT NULL DEFAULT 5,
  fragments integer NOT NULL DEFAULT 200,
  weapons_per_purchase integer NOT NULL DEFAULT 2,
  myth_reference_rate numeric NOT NULL DEFAULT 40000,   -- MYTH per 1 TON (reference only)
  reward_configuration_version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.veteran_vault_v2_config(id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- MYTH pools ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.veteran_myth_pools (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  reward_funded numeric NOT NULL DEFAULT 0,
  reward_distributed numeric NOT NULL DEFAULT 0,
  mining_funded numeric NOT NULL DEFAULT 0,
  mining_distributed numeric NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.veteran_myth_pools(id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- purchases ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.veteran_vault_v2_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  telegram_id bigint NOT NULL,
  package_version text NOT NULL,
  price_ton numeric NOT NULL,
  expected_nanoton text NOT NULL,
  payment_method text NOT NULL DEFAULT 'ton_connect' CHECK (payment_method IN ('internal_ton','ton_connect')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','delivered','expired')),
  payment_address text,
  payment_comment text,
  idempotency_key text UNIQUE,
  tx_hash text,
  boost_percent_snapshot numeric NOT NULL DEFAULT 10,
  myth_reward_snapshot numeric NOT NULL DEFAULT 0,
  reward_configuration_version integer NOT NULL DEFAULT 1,
  reward_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  delivery jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '1 hour',
  confirmed_at timestamptz,
  delivered_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS veteran_v2_owned_uidx
  ON public.veteran_vault_v2_purchases(user_id, package_version)
  WHERE status IN ('paid','delivered');
CREATE UNIQUE INDEX IF NOT EXISTS veteran_v2_tx_uidx
  ON public.veteran_vault_v2_purchases(tx_hash) WHERE tx_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS veteran_v2_user_idx ON public.veteran_vault_v2_purchases(user_id);

-- ownership ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.veteran_vault_v2_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  purchase_id uuid NOT NULL REFERENCES public.veteran_vault_v2_purchases(id) ON DELETE CASCADE,
  item_type text NOT NULL CHECK (item_type IN ('hero','pet','egg','dragon','weapon')),
  template_id text NOT NULL,
  instance_id uuid,
  source text NOT NULL DEFAULT 'VETERAN_VAULT_V2',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS veteran_v2_items_user_idx ON public.veteran_vault_v2_items(user_id);

-- ledger -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.veteran_vault_v2_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid REFERENCES public.veteran_vault_v2_purchases(id) ON DELETE SET NULL,
  user_id uuid REFERENCES public.game_players(id) ON DELETE CASCADE,
  kind text NOT NULL,
  ton_amount numeric NOT NULL DEFAULT 0,
  myth_amount numeric NOT NULL DEFAULT 0,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS veteran_v2_ledger_user_idx ON public.veteran_vault_v2_ledger(user_id);

-- no direct client access: everything flows through SECURITY DEFINER RPCs
ALTER TABLE public.veteran_vault_v2_config    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veteran_vault_v2_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veteran_vault_v2_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veteran_vault_v2_ledger    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veteran_myth_pools         ENABLE ROW LEVEL SECURITY;

GRANT ALL ON public.veteran_vault_v2_config    TO service_role;
GRANT ALL ON public.veteran_vault_v2_purchases TO service_role;
GRANT ALL ON public.veteran_vault_v2_items     TO service_role;
GRANT ALL ON public.veteran_vault_v2_ledger    TO service_role;
GRANT ALL ON public.veteran_myth_pools         TO service_role;