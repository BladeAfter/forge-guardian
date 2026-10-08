-- ═══════════════════════════════════════════════════════════════
-- MYTHREON — CLAN COLLECTIVE LAYER (Personal Boss stays untouched)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.clan_collective_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT true,
  boss_points integer[] NOT NULL DEFAULT ARRAY[10,15,25,40],
  weekly_target_per_active integer NOT NULL DEFAULT 500,
  weekly_target_min bigint NOT NULL DEFAULT 2000,
  weekly_target_max bigint NOT NULL DEFAULT 50000,
  min_weekly_contribution integer NOT NULL DEFAULT 50,
  active_member_days integer NOT NULL DEFAULT 7,
  coins_per_contribution numeric NOT NULL DEFAULT 1,
  clan_xp_per_contribution numeric NOT NULL DEFAULT 1,
  milestones jsonb NOT NULL DEFAULT '[
    {"pct":25,"petFood":10,"fragments":20,"coins":150,"clanXp":200},
    {"pct":50,"chests":1,"pvpTickets":5,"coins":300,"clanXp":400},
    {"pct":75,"fragments":60,"petFood":25,"coins":500,"clanXp":700},
    {"pct":100,"chests":2,"fragments":120,"pvpTickets":10,"coins":1000,"clanXp":1500}
  ]'::jsonb,
  raid_enabled boolean NOT NULL DEFAULT true,
  raid_duration_days integer NOT NULL DEFAULT 7,
  raid_attacks_per_day integer NOT NULL DEFAULT 3,
  raid_hp_per_power numeric NOT NULL DEFAULT 900,
  raid_hp_min bigint NOT NULL DEFAULT 50000000,
  raid_hp_max bigint NOT NULL DEFAULT 5000000000,
  raid_rewards jsonb NOT NULL DEFAULT '{"fcPool":3000000,"coinsPool":20000,"clanXp":3000,"minDamagePct":0.5}'::jsonb,
  treasury_assets text[] NOT NULL DEFAULT ARRAY['FC','MYTH','MATERIALS'],
  treasury_ton_enabled boolean NOT NULL DEFAULT false,
  myth_milestone_rewards boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_collective_settings TO service_role;
ALTER TABLE public.clan_collective_settings ENABLE ROW LEVEL SECURITY;
INSERT INTO public.clan_collective_settings(id) VALUES (true) ON CONFLICT DO NOTHING;

-- ═══ WEEKLY CYCLES ═══
CREATE TABLE public.clan_weekly_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  week_key date NOT NULL,
  target bigint NOT NULL DEFAULT 0,
  active_members integer NOT NULL DEFAULT 0,
  total_contribution bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED')),
  started_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clan_id, week_key)
);
GRANT ALL ON public.clan_weekly_cycles TO service_role;
ALTER TABLE public.clan_weekly_cycles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.clan_weekly_member_progress (
  cycle_id uuid NOT NULL REFERENCES public.clan_weekly_cycles(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  contribution bigint NOT NULL DEFAULT 0,
  raid_damage numeric NOT NULL DEFAULT 0,
  joined_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (cycle_id, user_id)
);
GRANT ALL ON public.clan_weekly_member_progress TO service_role;
ALTER TABLE public.clan_weekly_member_progress ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.clan_contribution_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  cycle_id uuid REFERENCES public.clan_weekly_cycles(id) ON DELETE SET NULL,
  amount bigint NOT NULL,
  source_type text NOT NULL,
  source_id text,
  game_day date NOT NULL DEFAULT public.game_day_key(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX clan_contribution_source_uniq
  ON public.clan_contribution_ledger(source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX clan_contribution_cycle_idx ON public.clan_contribution_ledger(cycle_id, user_id);
GRANT ALL ON public.clan_contribution_ledger TO service_role;
ALTER TABLE public.clan_contribution_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.clan_milestone_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES public.clan_weekly_cycles(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  milestone_pct integer NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cycle_id, user_id, milestone_pct)
);
GRANT ALL ON public.clan_milestone_claims TO service_role;
ALTER TABLE public.clan_milestone_claims ENABLE ROW LEVEL SECURITY;

-- ═══ CLAN RAID (shared boss, separate from Personal Boss) ═══
CREATE TABLE public.clan_raid_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  raid_key date NOT NULL,
  boss_name text NOT NULL DEFAULT 'Abyssal Devourer',
  boss_theme text NOT NULL DEFAULT 'abyss',
  max_hp numeric NOT NULL,
  current_hp numeric NOT NULL,
  boss_atk numeric NOT NULL DEFAULT 0,
  boss_def numeric NOT NULL DEFAULT 0,
  total_damage numeric NOT NULL DEFAULT 0,
  participants integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DEFEATED','EXPIRED','SETTLED')),
  rewards_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL,
  settled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clan_id, raid_key)
);
GRANT ALL ON public.clan_raid_cycles TO service_role;
ALTER TABLE public.clan_raid_cycles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.clan_raid_attacks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raid_id uuid NOT NULL REFERENCES public.clan_raid_cycles(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  damage numeric NOT NULL DEFAULT 0,
  attack_day date NOT NULL DEFAULT public.game_day_key(),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX clan_raid_attacks_raid_idx ON public.clan_raid_attacks(raid_id, user_id);
GRANT ALL ON public.clan_raid_attacks TO service_role;
ALTER TABLE public.clan_raid_attacks ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.clan_raid_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raid_id uuid NOT NULL REFERENCES public.clan_raid_cycles(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  damage numeric NOT NULL DEFAULT 0,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (raid_id, user_id)
);
GRANT ALL ON public.clan_raid_rewards TO service_role;
ALTER TABLE public.clan_raid_rewards ENABLE ROW LEVEL SECURITY;

-- ═══ TREASURY (never withdrawable to a personal wallet) ═══
CREATE TABLE public.clan_treasury (
  clan_id uuid PRIMARY KEY REFERENCES public.clans(id) ON DELETE CASCADE,
  fc numeric NOT NULL DEFAULT 0,
  myth numeric NOT NULL DEFAULT 0,
  materials numeric NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_treasury TO service_role;
ALTER TABLE public.clan_treasury ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.clan_treasury_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  asset text NOT NULL CHECK (asset IN ('FC','MYTH','MATERIALS')),
  amount numeric NOT NULL,
  reason text NOT NULL CHECK (reason IN ('CLAN_DONATION','CLAN_UPGRADE_PURCHASE','CLAN_BUFF_PURCHASE','CLAN_SHOP_FUNDING','CLAN_ADMIN_ADJUST')),
  balance_before numeric NOT NULL DEFAULT 0,
  balance_after numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX clan_treasury_ledger_clan_idx ON public.clan_treasury_ledger(clan_id, created_at DESC);
GRANT ALL ON public.clan_treasury_ledger TO service_role;
ALTER TABLE public.clan_treasury_ledger ENABLE ROW LEVEL SECURITY;

-- ═══ BUILDINGS / UPGRADES ═══
CREATE TABLE public.clan_upgrade_config (
  code text PRIMARY KEY,
  label text NOT NULL,
  description text NOT NULL DEFAULT '',
  max_level integer NOT NULL DEFAULT 10,
  base_cost_fc numeric NOT NULL DEFAULT 500000,
  cost_growth numeric NOT NULL DEFAULT 1.6,
  bonus_per_level numeric NOT NULL DEFAULT 0.5,
  bonus_cap numeric NOT NULL DEFAULT 5,
  bonus_kind text NOT NULL DEFAULT 'GENERIC',
  required_clan_level integer NOT NULL DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_upgrade_config TO service_role;
ALTER TABLE public.clan_upgrade_config ENABLE ROW LEVEL SECURITY;

INSERT INTO public.clan_upgrade_config(code,label,description,bonus_kind,base_cost_fc,required_clan_level) VALUES
  ('WAR_HALL','War Hall','Bônus de contribuição em Clan War e Clan XP.','WAR_CONTRIBUTION',500000,1),
  ('TREASURY','Treasury','Aumenta a eficiência das doações do clã.','TREASURY_EFFICIENCY',400000,5),
  ('FORGE','Forge','Bônus pequeno em recompensas de materiais e equipamento.','MATERIAL_REWARD',600000,1),
  ('PET_SANCTUARY','Pet Sanctuary','Bônus de XP de pets e eficiência de ração.','PET_XP',600000,1),
  ('RESEARCH_HALL','Research Hall','Desbloqueia e melhora os Clan Buffs.','BUFF_UNLOCK',800000,1)
ON CONFLICT DO NOTHING;

CREATE TABLE public.clan_upgrades (
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  code text NOT NULL REFERENCES public.clan_upgrade_config(code) ON DELETE CASCADE,
  level integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (clan_id, code)
);
GRANT ALL ON public.clan_upgrades TO service_role;
ALTER TABLE public.clan_upgrades ENABLE ROW LEVEL SECURITY;

-- ═══ BUFFS ═══
CREATE TABLE public.clan_buff_config (
  code text PRIMARY KEY,
  label text NOT NULL,
  bonus_pct numeric NOT NULL DEFAULT 3,
  max_pct numeric NOT NULL DEFAULT 5,
  duration_hours integer NOT NULL DEFAULT 72,
  cost_fc numeric NOT NULL DEFAULT 300000,
  required_research_level integer NOT NULL DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_buff_config TO service_role;
ALTER TABLE public.clan_buff_config ENABLE ROW LEVEL SECURITY;

INSERT INTO public.clan_buff_config(code,label,bonus_pct,max_pct,required_research_level) VALUES
  ('HERO_XP','Hero XP',3,5,1),
  ('PET_XP','Pet XP',3,5,1),
  ('FC_ACTIVITY','FC Rewards',2,3,2),
  ('PERSONAL_BOSS_DMG','Personal Boss DMG',2,3,3),
  ('CLAN_RAID_DMG','Clan Raid DMG',3,3,2)
ON CONFLICT DO NOTHING;

CREATE TABLE public.clan_buffs (
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  code text NOT NULL REFERENCES public.clan_buff_config(code) ON DELETE CASCADE,
  bonus_pct numeric NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL,
  activated_by uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (clan_id, code)
);
GRANT ALL ON public.clan_buffs TO service_role;
ALTER TABLE public.clan_buffs ENABLE ROW LEVEL SECURITY;

-- ═══ CLAN SHOP (Clan Coins = clan_members.clan_points) ═══
CREATE TABLE public.clan_shop_config (
  code text PRIMARY KEY,
  label text NOT NULL,
  item_type text NOT NULL,
  item_code text NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  cost_coins integer NOT NULL DEFAULT 100,
  daily_limit integer NOT NULL DEFAULT 5,
  weekly_limit integer NOT NULL DEFAULT 20,
  season_limit integer NOT NULL DEFAULT 0,
  required_clan_level integer NOT NULL DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_shop_config TO service_role;
ALTER TABLE public.clan_shop_config ENABLE ROW LEVEL SECURITY;

INSERT INTO public.clan_shop_config(code,label,item_type,item_code,quantity,cost_coins,daily_limit,weekly_limit,required_clan_level,sort_order) VALUES
  ('PET_FOOD','Pet Food x10','pet_food','pet_ration',10,50,10,40,1,1),
  ('FRAGMENTS','Fragmentos x20','fragments','fragments',20,80,10,40,1,2),
  ('UNIVERSAL_FRAGMENTS','Fragmento Universal x5','universal_fragments','universal',5,150,5,20,1,3),
  ('PVP_TICKET','PvP Ticket x3','pvp_ticket','pvp_ticket',3,75,10,40,1,4),
  ('RARE_CHEST','Baú Raro','hero_chest','rare_chest',1,300,3,12,1,5),
  ('EPIC_CHEST','Baú Épico','hero_chest','epic_chest',1,900,1,3,10,6)
ON CONFLICT DO NOTHING;

CREATE TABLE public.clan_shop_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL REFERENCES public.clans(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  code text NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  cost_coins integer NOT NULL DEFAULT 0,
  purchase_day date NOT NULL DEFAULT public.game_day_key(),
  week_key date NOT NULL DEFAULT public.clan_week_key(),
  idempotency_key text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX clan_shop_purchase_idem ON public.clan_shop_purchases(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX clan_shop_purchase_day_idx ON public.clan_shop_purchases(user_id, code, purchase_day);
GRANT ALL ON public.clan_shop_purchases TO service_role;
ALTER TABLE public.clan_shop_purchases ENABLE ROW LEVEL SECURITY;

-- ═══ PERMISSIONS ═══
ALTER TABLE public.clan_members
  ADD COLUMN IF NOT EXISTS permissions text[] NOT NULL DEFAULT ARRAY[]::text[];

-- ═══ touch triggers ═══
CREATE OR REPLACE FUNCTION public.clan_collective_touch() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE TRIGGER trg_clan_collective_settings_touch BEFORE UPDATE ON public.clan_collective_settings
  FOR EACH ROW EXECUTE FUNCTION public.clan_collective_touch();
CREATE TRIGGER trg_clan_weekly_cycles_touch BEFORE UPDATE ON public.clan_weekly_cycles
  FOR EACH ROW EXECUTE FUNCTION public.clan_collective_touch();
CREATE TRIGGER trg_clan_raid_cycles_touch BEFORE UPDATE ON public.clan_raid_cycles
  FOR EACH ROW EXECUTE FUNCTION public.clan_collective_touch();
CREATE TRIGGER trg_clan_treasury_touch BEFORE UPDATE ON public.clan_treasury
  FOR EACH ROW EXECUTE FUNCTION public.clan_collective_touch();
CREATE TRIGGER trg_clan_upgrades_touch BEFORE UPDATE ON public.clan_upgrades
  FOR EACH ROW EXECUTE FUNCTION public.clan_collective_touch();
CREATE TRIGGER trg_clan_buffs_touch BEFORE UPDATE ON public.clan_buffs
  FOR EACH ROW EXECUTE FUNCTION public.clan_collective_touch();