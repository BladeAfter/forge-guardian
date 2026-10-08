SET lock_timeout = '15s';

CREATE TABLE IF NOT EXISTS public.clan_war_seasons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL,
  name text NOT NULL DEFAULT 'Clan War Season',
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL DEFAULT now() + interval '28 days',
  status text NOT NULL DEFAULT 'active',
  ton_prize_enabled boolean NOT NULL DEFAULT false,
  ton_prize_ton numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_war_seasons TO service_role;
ALTER TABLE public.clan_war_seasons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clan_war_seasons server only" ON public.clan_war_seasons;
CREATE POLICY "clan_war_seasons server only" ON public.clan_war_seasons FOR ALL USING (false);

ALTER TABLE public.clan_wars
  ADD COLUMN IF NOT EXISTS season_id uuid REFERENCES public.clan_war_seasons(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS preparation_starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS battle_starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS battle_ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS winner_clan_id uuid,
  ADD COLUMN IF NOT EXISTS finished_at timestamptz,
  ADD COLUMN IF NOT EXISTS settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS registered_by uuid,
  ADD COLUMN IF NOT EXISTS test_war boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS roster_size integer NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS attacks_per_player integer NOT NULL DEFAULT 2;
CREATE INDEX IF NOT EXISTS clan_wars_status_idx ON public.clan_wars(status);
CREATE INDEX IF NOT EXISTS clan_wars_clan_a_idx ON public.clan_wars(clan_a);
CREATE INDEX IF NOT EXISTS clan_wars_clan_b_idx ON public.clan_wars(clan_b);

CREATE TABLE IF NOT EXISTS public.clan_war_rosters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  war_id uuid NOT NULL REFERENCES public.clan_wars(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL,
  user_id uuid NOT NULL,
  sector text NOT NULL DEFAULT 'OUTER_GATE',
  team_power_snapshot bigint NOT NULL DEFAULT 0,
  attacks_total integer NOT NULL DEFAULT 2,
  attacks_used integer NOT NULL DEFAULT 0,
  points_earned integer NOT NULL DEFAULT 0,
  wins integer NOT NULL DEFAULT 0,
  losses integer NOT NULL DEFAULT 0,
  defeats_taken integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (war_id, user_id)
);
CREATE INDEX IF NOT EXISTS clan_war_rosters_war_clan_idx ON public.clan_war_rosters(war_id, clan_id);
GRANT ALL ON public.clan_war_rosters TO service_role;
ALTER TABLE public.clan_war_rosters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clan_war_rosters server only" ON public.clan_war_rosters;
CREATE POLICY "clan_war_rosters server only" ON public.clan_war_rosters FOR ALL USING (false);

CREATE TABLE IF NOT EXISTS public.clan_war_defenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  war_id uuid NOT NULL REFERENCES public.clan_wars(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL,
  user_id uuid NOT NULL,
  hero_ids uuid[] NOT NULL DEFAULT '{}',
  pet_id uuid,
  power bigint NOT NULL DEFAULT 0,
  team_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  pet_buffs jsonb NOT NULL DEFAULT '{}'::jsonb,
  locked_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (war_id, user_id)
);
GRANT ALL ON public.clan_war_defenses TO service_role;
ALTER TABLE public.clan_war_defenses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clan_war_defenses server only" ON public.clan_war_defenses;
CREATE POLICY "clan_war_defenses server only" ON public.clan_war_defenses FOR ALL USING (false);

CREATE TABLE IF NOT EXISTS public.clan_war_attacks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  war_id uuid NOT NULL REFERENCES public.clan_wars(id) ON DELETE CASCADE,
  attacker_user uuid NOT NULL,
  attacker_clan uuid NOT NULL,
  defender_user uuid NOT NULL,
  defender_clan uuid NOT NULL,
  sector text NOT NULL,
  result text NOT NULL,
  points integer NOT NULL DEFAULT 0,
  perfect boolean NOT NULL DEFAULT false,
  upset_bonus integer NOT NULL DEFAULT 0,
  attacker_power bigint NOT NULL DEFAULT 0,
  defender_power bigint NOT NULL DEFAULT 0,
  battle jsonb NOT NULL DEFAULT '{}'::jsonb,
  client_key text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS clan_war_attacks_key_idx ON public.clan_war_attacks(war_id, attacker_user, client_key) WHERE client_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS clan_war_attacks_war_idx ON public.clan_war_attacks(war_id);
GRANT ALL ON public.clan_war_attacks TO service_role;
ALTER TABLE public.clan_war_attacks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clan_war_attacks server only" ON public.clan_war_attacks;
CREATE POLICY "clan_war_attacks server only" ON public.clan_war_attacks FOR ALL USING (false);

CREATE TABLE IF NOT EXISTS public.clan_war_sector_state (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  war_id uuid NOT NULL REFERENCES public.clan_wars(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL,
  sector text NOT NULL,
  defeats integer NOT NULL DEFAULT 0,
  conquered_at timestamptz,
  UNIQUE (war_id, clan_id, sector)
);
GRANT ALL ON public.clan_war_sector_state TO service_role;
ALTER TABLE public.clan_war_sector_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clan_war_sector_state server only" ON public.clan_war_sector_state;
CREATE POLICY "clan_war_sector_state server only" ON public.clan_war_sector_state FOR ALL USING (false);

CREATE TABLE IF NOT EXISTS public.clan_war_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  war_id uuid NOT NULL REFERENCES public.clan_wars(id) ON DELETE CASCADE,
  clan_id uuid NOT NULL,
  user_id uuid NOT NULL,
  result text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (war_id, user_id)
);
GRANT ALL ON public.clan_war_rewards TO service_role;
ALTER TABLE public.clan_war_rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clan_war_rewards server only" ON public.clan_war_rewards;
CREATE POLICY "clan_war_rewards server only" ON public.clan_war_rewards FOR ALL USING (false);

CREATE TABLE IF NOT EXISTS public.clan_war_rating_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clan_id uuid NOT NULL,
  war_id uuid REFERENCES public.clan_wars(id) ON DELETE SET NULL,
  season_id uuid,
  rating_before integer NOT NULL,
  rating_after integer NOT NULL,
  delta integer NOT NULL,
  result text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (war_id, clan_id)
);
GRANT ALL ON public.clan_war_rating_history TO service_role;
ALTER TABLE public.clan_war_rating_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clan_war_rating_history server only" ON public.clan_war_rating_history;
CREATE POLICY "clan_war_rating_history server only" ON public.clan_war_rating_history FOR ALL USING (false);

ALTER TABLE public.clans
  ADD COLUMN IF NOT EXISTS war_rating integer NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS war_wins integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS war_losses integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS war_draws integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS war_points_total bigint NOT NULL DEFAULT 0;

INSERT INTO public.game_settings(key, value, category, label) VALUES
  ('clan_war_enabled', 'false'::jsonb, 'clan_war', 'Clan War ativa'),
  ('clan_war_roster_size', '20'::jsonb, 'clan_war', 'Roster'),
  ('clan_war_attacks_per_player', '2'::jsonb, 'clan_war', 'Ataques por jogador'),
  ('clan_war_preparation_hours', '12'::jsonb, 'clan_war', 'Preparacao (h)'),
  ('clan_war_battle_hours', '24'::jsonb, 'clan_war', 'Batalha (h)'),
  ('clan_war_season_weeks', '4'::jsonb, 'clan_war', 'Temporada (semanas)'),
  ('clan_war_matchmaking', 'true'::jsonb, 'clan_war', 'Matchmaking automatico'),
  ('clan_war_base_rating', '1000'::jsonb, 'clan_war', 'Rating inicial'),
  ('clan_war_points_win', '100'::jsonb, 'clan_war', 'Pontos por vitoria'),
  ('clan_war_points_perfect', '20'::jsonb, 'clan_war', 'Bonus perfect win'),
  ('clan_war_points_upset_max', '30'::jsonb, 'clan_war', 'Bonus upset maximo'),
  ('clan_war_points_loss', '10'::jsonb, 'clan_war', 'Pontos por participacao'),
  ('clan_war_defender_max_defeats', '2'::jsonb, 'clan_war', 'Derrotas ate conquistar defensor'),
  ('clan_war_conquered_points_percent', '25'::jsonb, 'clan_war', 'Percentual de pontos apos conquistado'),
  ('clan_war_sector_bonus_percent', '5'::jsonb, 'clan_war', 'Bonus por setor'),
  ('clan_war_ton_season_prize', 'false'::jsonb, 'clan_war', 'Premio TON da temporada')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.clan_war_sector_def()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $fn$
  SELECT '[
    {"code":"OUTER_GATE","order":1,"slots":6,"required":4,"requires":[],"bonus":null},
    {"code":"NORTH_TOWER","order":2,"slots":4,"required":3,"requires":["OUTER_GATE"],"bonus":"atk"},
    {"code":"SOUTH_TOWER","order":2,"slots":4,"required":3,"requires":["OUTER_GATE"],"bonus":"hp"},
    {"code":"INNER_KEEP","order":3,"slots":4,"required":3,"requires":["NORTH_TOWER","SOUTH_TOWER"],"bonus":"skill"},
    {"code":"CLAN_THRONE","order":4,"slots":2,"required":2,"requires":["INNER_KEEP"],"bonus":null}
  ]'::jsonb;
$fn$;

CREATE OR REPLACE FUNCTION public.clan_war_cfg()
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
  SELECT jsonb_build_object(
    'enabled', COALESCE((SELECT value::text = 'true' FROM public.game_settings WHERE key='clan_war_enabled'), false),
    'rosterSize', public.setting_num('clan_war_roster_size', 20)::int,
    'attacksPerPlayer', public.setting_num('clan_war_attacks_per_player', 2)::int,
    'preparationHours', public.setting_num('clan_war_preparation_hours', 12)::int,
    'battleHours', public.setting_num('clan_war_battle_hours', 24)::int,
    'seasonWeeks', public.setting_num('clan_war_season_weeks', 4)::int,
    'matchmaking', COALESCE((SELECT value::text = 'true' FROM public.game_settings WHERE key='clan_war_matchmaking'), true),
    'baseRating', public.setting_num('clan_war_base_rating', 1000)::int,
    'pointsWin', public.setting_num('clan_war_points_win', 100)::int,
    'pointsPerfect', public.setting_num('clan_war_points_perfect', 20)::int,
    'pointsUpsetMax', public.setting_num('clan_war_points_upset_max', 30)::int,
    'pointsLoss', public.setting_num('clan_war_points_loss', 10)::int,
    'defenderMaxDefeats', public.setting_num('clan_war_defender_max_defeats', 2)::int,
    'conqueredPercent', public.setting_num('clan_war_conquered_points_percent', 25)::int,
    'sectorBonusPercent', public.setting_num('clan_war_sector_bonus_percent', 5)::int,
    'tonSeasonPrize', COALESCE((SELECT value::text = 'true' FROM public.game_settings WHERE key='clan_war_ton_season_prize'), false),
    'sectors', public.clan_war_sector_def()
  );
$fn$;

CREATE OR REPLACE FUNCTION public.clan_war_league(p_rating integer)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN COALESCE(p_rating,0) >= 2400 THEN 'MYTHIC'
    WHEN p_rating >= 2000 THEN 'DIAMOND'
    WHEN p_rating >= 1700 THEN 'PLATINUM'
    WHEN p_rating >= 1400 THEN 'GOLD'
    WHEN p_rating >= 1150 THEN 'SILVER'
    ELSE 'BRONZE' END;
$fn$;

CREATE OR REPLACE FUNCTION public.clan_war_league_multiplier(p_league text)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE p_league WHEN 'MYTHIC' THEN 2.0 WHEN 'DIAMOND' THEN 1.7 WHEN 'PLATINUM' THEN 1.45
    WHEN 'GOLD' THEN 1.25 WHEN 'SILVER' THEN 1.1 ELSE 1.0 END;
$fn$;

CREATE OR REPLACE FUNCTION public.clan_war_current_season()
RETURNS public.clan_war_seasons LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE s public.clan_war_seasons; v_weeks int;
BEGIN
  SELECT * INTO s FROM public.clan_war_seasons WHERE status='active' AND now() < ends_at ORDER BY starts_at DESC LIMIT 1;
  IF s.id IS NOT NULL THEN RETURN s; END IF;
  UPDATE public.clan_war_seasons SET status='finished' WHERE status='active' AND now() >= ends_at;
  v_weeks := GREATEST(1, public.setting_num('clan_war_season_weeks', 4)::int);
  INSERT INTO public.clan_war_seasons(code, name, starts_at, ends_at)
  VALUES ('S' || to_char(now(),'YYYYMMDDHH24MI'), 'Clan War Season', now(), now() + (v_weeks || ' weeks')::interval)
  RETURNING * INTO s;
  RETURN s;
END; $fn$;
REVOKE ALL ON FUNCTION public.clan_war_current_season() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clan_war_current_season() TO service_role;