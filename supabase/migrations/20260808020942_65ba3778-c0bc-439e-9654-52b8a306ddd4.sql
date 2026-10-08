-- =========================================================
-- FORGE VILLAGE MASTER ADMIN :: base schema
-- =========================================================

CREATE TABLE IF NOT EXISTS public.game_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  category text NOT NULL DEFAULT 'general',
  label text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint
);
GRANT ALL ON public.game_settings TO service_role;
ALTER TABLE public.game_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id bigint NOT NULL,
  action text NOT NULL,
  target_type text NOT NULL DEFAULT 'system',
  target_id text,
  old_value jsonb,
  new_value jsonb,
  reason text,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON public.admin_audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_target ON public.admin_audit_logs (target_type, target_id);
GRANT ALL ON public.admin_audit_logs TO service_role;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.admin_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id bigint NOT NULL,
  label text NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.admin_snapshots TO service_role;
ALTER TABLE public.admin_snapshots ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------
-- players: ban / vip / premium
-- ---------------------------------------------------------
ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS banned boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ban_reason text,
  ADD COLUMN IF NOT EXISTS banned_at timestamptz,
  ADD COLUMN IF NOT EXISTS vip_until timestamptz,
  ADD COLUMN IF NOT EXISTS premium_until timestamptz,
  ADD COLUMN IF NOT EXISTS ton_balance numeric NOT NULL DEFAULT 0;

-- ---------------------------------------------------------
-- hero catalog / shop
-- ---------------------------------------------------------
ALTER TABLE public.hero_catalog
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS battle_image text,
  ADD COLUMN IF NOT EXISTS hero_class text NOT NULL DEFAULT 'balanced',
  ADD COLUMN IF NOT EXISTS base_atk numeric,
  ADD COLUMN IF NOT EXISTS base_hp numeric,
  ADD COLUMN IF NOT EXISTS power numeric,
  ADD COLUMN IF NOT EXISTS start_level integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS max_level integer NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS price_fc numeric,
  ADD COLUMN IF NOT EXISTS price_ton numeric,
  ADD COLUMN IF NOT EXISTS discount_percent numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS drop_weight numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stock integer,
  ADD COLUMN IF NOT EXISTS per_player_limit integer,
  ADD COLUMN IF NOT EXISTS featured boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS in_shop boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS available_from timestamptz,
  ADD COLUMN IF NOT EXISTS available_until timestamptz,
  ADD COLUMN IF NOT EXISTS buffs jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS skills jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- ---------------------------------------------------------
-- pvp leagues
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pvp_leagues (
  code text PRIMARY KEY,
  name text NOT NULL,
  icon text NOT NULL DEFAULT '🏅',
  min_trophies integer NOT NULL DEFAULT 0,
  max_trophies integer,
  reward jsonb NOT NULL DEFAULT '{}'::jsonb,
  sort_order integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pvp_leagues TO service_role;
ALTER TABLE public.pvp_leagues ENABLE ROW LEVEL SECURITY;

INSERT INTO public.pvp_leagues (code, name, icon, min_trophies, max_trophies, sort_order) VALUES
  ('bronze_5','Bronze V','🥉',0,19,1),
  ('bronze_4','Bronze IV','🥉',20,39,2),
  ('bronze_3','Bronze III','🥉',40,59,3),
  ('bronze_2','Bronze II','🥉',60,79,4),
  ('bronze_1','Bronze I','🥉',80,99,5),
  ('silver_5','Prata V','🥈',100,299,6),
  ('silver_3','Prata III','🥈',300,599,7),
  ('silver_1','Prata I','🥈',600,899,8),
  ('gold_3','Ouro III','🥇',900,1199,9),
  ('platinum_5','Platina V','💎',1200,1999,10),
  ('diamond_3','Diamante III','💠',2000,3499,11),
  ('master','Mestre','🔮',3500,4999,12),
  ('legendary','Lendária','👑',5000,NULL,13)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------
-- missions
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.game_missions (
  code text PRIMARY KEY,
  scope text NOT NULL DEFAULT 'daily',
  title text NOT NULL,
  description text,
  target_metric text NOT NULL DEFAULT 'boss_damage',
  target_amount numeric NOT NULL DEFAULT 1,
  reward_type text NOT NULL DEFAULT 'fc',
  reward_code text,
  reward_amount numeric NOT NULL DEFAULT 0,
  reward_xp integer NOT NULL DEFAULT 0,
  daily_limit integer,
  sort_order integer NOT NULL DEFAULT 100,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.game_missions TO service_role;
ALTER TABLE public.game_missions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.player_mission_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  mission_code text NOT NULL REFERENCES public.game_missions(code) ON DELETE CASCADE,
  cycle text NOT NULL,
  progress numeric NOT NULL DEFAULT 0,
  completed_at timestamptz,
  claimed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, mission_code, cycle)
);
GRANT ALL ON public.player_mission_progress TO service_role;
ALTER TABLE public.player_mission_progress ENABLE ROW LEVEL SECURITY;

INSERT INTO public.game_missions (code, scope, title, target_metric, target_amount, reward_amount, sort_order) VALUES
  ('daily_boss_hits','daily','Ataque o Chefe 10 vezes','boss_hits',10,2500,1),
  ('daily_pvp_wins','daily','Vença 3 batalhas na Arena','pvp_wins',3,4000,2),
  ('daily_feed_pet','daily','Alimente seu pet 5 vezes','pet_feeds',5,1500,3),
  ('weekly_boss_defeat','weekly','Derrote 3 chefes','boss_defeats',3,20000,4),
  ('weekly_invite','weekly','Convide 1 amigo','referrals',1,15000,5)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------
-- boss templates
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.boss_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL,
  name text NOT NULL,
  image_url text,
  level integer NOT NULL DEFAULT 1,
  max_hp numeric NOT NULL DEFAULT 10000,
  attack numeric NOT NULL DEFAULT 100,
  defense numeric NOT NULL DEFAULT 0,
  attack_interval_seconds integer NOT NULL DEFAULT 5,
  difficulty text NOT NULL DEFAULT 'normal',
  reward_amount numeric NOT NULL DEFAULT 5000,
  cooldown_seconds integer NOT NULL DEFAULT 0,
  ticket_cost integer NOT NULL DEFAULT 0,
  attack_limit integer,
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.boss_templates TO service_role;
ALTER TABLE public.boss_templates ENABLE ROW LEVEL SECURITY;

INSERT INTO public.boss_templates (code, name, level, max_hp, attack, reward_amount, active)
VALUES ('golem_ancestral','Golem Ancestral',1,12000,120,5000,true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------
-- ad providers
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ad_providers (
  code text PRIMARY KEY,
  name text NOT NULL,
  enabled boolean NOT NULL DEFAULT false,
  daily_limit integer NOT NULL DEFAULT 10,
  reward_fc numeric NOT NULL DEFAULT 500,
  cooldown_seconds integer NOT NULL DEFAULT 60,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.ad_providers TO service_role;
ALTER TABLE public.ad_providers ENABLE ROW LEVEL SECURITY;

INSERT INTO public.ad_providers (code, name, enabled, daily_limit, reward_fc) VALUES
  ('adsgram','Adsgram',false,10,500),
  ('gigapub','GigaPub',false,10,500)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------
-- dynamic settings seed
-- ---------------------------------------------------------
INSERT INTO public.game_settings (key, value, category, label) VALUES
  ('super_admin_telegram_id', '8118569391'::jsonb, 'security', 'Telegram ID do administrador mestre'),
  ('settings_version', '1'::jsonb, 'system', 'Versão das configurações'),
  ('maintenance_mode', 'false'::jsonb, 'system', 'Modo manutenção'),
  ('maintenance_message', '"Forge Village está em manutenção."'::jsonb, 'system', 'Mensagem de manutenção'),
  ('min_app_version', '"1.0.0"'::jsonb, 'system', 'Versão mínima do app'),
  ('telegram_app_link', '"https://t.me/ForgeVillageBot/app"'::jsonb, 'system', 'Link do Mini App'),
  ('hero_rarity_rates', '{"comum":45,"incomum":25,"raro":15,"epico":8,"lendario":5,"mitico":1.5,"ancestral":0.5}'::jsonb, 'heroes', 'Chances de raridade dos heróis'),
  ('pvp_trophy_win', '30'::jsonb, 'pvp', 'Troféus por vitória'),
  ('pvp_trophy_loss', '-20'::jsonb, 'pvp', 'Troféus por derrota'),
  ('pvp_ticket_start', '5'::jsonb, 'pvp', 'Tickets iniciais'),
  ('pvp_ticket_max', '10'::jsonb, 'pvp', 'Tickets máximos'),
  ('pvp_ticket_cost', '1'::jsonb, 'pvp', 'Custo de tickets por batalha'),
  ('pvp_ticket_regen_minutes', '30'::jsonb, 'pvp', 'Minutos para regenerar 1 ticket'),
  ('pvp_ticket_price_fc', '5000'::jsonb, 'pvp', 'Preço de 1 ticket em FC'),
  ('referral_percent_level_1', '10'::jsonb, 'referral', 'Comissão nível 1 (%)'),
  ('referral_percent_level_2', '5'::jsonb, 'referral', 'Comissão nível 2 (%)'),
  ('referral_percent_level_3', '2'::jsonb, 'referral', 'Comissão nível 3 (%)'),
  ('wallet_min_withdraw_fc', '100000'::jsonb, 'wallet', 'Saque mínimo (FC)'),
  ('wallet_max_withdraw_fc', '10000000'::jsonb, 'wallet', 'Saque máximo (FC)'),
  ('wallet_max_deposit_ton', '1000'::jsonb, 'wallet', 'Depósito máximo (TON)'),
  ('wallet_fee_percent', '0'::jsonb, 'wallet', 'Taxa de saque (%)'),
  ('vip_multiplier', '1.5'::jsonb, 'vip', 'Multiplicador VIP'),
  ('premium_multiplier', '2'::jsonb, 'vip', 'Multiplicador Premium')
ON CONFLICT (key) DO NOTHING;
