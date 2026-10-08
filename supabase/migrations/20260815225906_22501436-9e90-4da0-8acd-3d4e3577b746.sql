-- ============================================================================
-- TACTICAL ARENA — 3v3 turn-based PvP (MVP)
-- Fully isolated from the Classic Arena: no existing table, function, trophy,
-- ticket flow or ranking is modified here.
-- ============================================================================

-- ---------------------------------------------------------------- skills
CREATE TABLE IF NOT EXISTS public.tactical_skills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  skill_key text NOT NULL UNIQUE,
  name_key text NOT NULL,
  hero_class text NOT NULL,
  skill_type text NOT NULL CHECK (skill_type IN ('DAMAGE','HEAL','SHIELD','BUFF','DEBUFF','STUN','DOT','CLEANSE')),
  power_multiplier numeric NOT NULL DEFAULT 1,
  cooldown integer NOT NULL DEFAULT 0,
  target_type text NOT NULL CHECK (target_type IN ('SINGLE_ENEMY','ALL_ENEMIES','SELF','SINGLE_ALLY','ALL_ALLIES')),
  duration integer NOT NULL DEFAULT 0,
  effect_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.tactical_skills TO authenticated;
GRANT ALL ON public.tactical_skills TO service_role;
ALTER TABLE public.tactical_skills ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tactical_skills_read" ON public.tactical_skills FOR SELECT TO authenticated USING (enabled);

-- ---------------------------------------------------------------- team / deck
CREATE TABLE IF NOT EXISTS public.tactical_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  slot integer NOT NULL CHECK (slot BETWEEN 1 AND 3),
  player_hero_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, slot),
  UNIQUE (user_id, player_hero_id)
);
GRANT ALL ON public.tactical_teams TO service_role;
ALTER TABLE public.tactical_teams ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.tactical_decks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  position integer NOT NULL CHECK (position BETWEEN 1 AND 12),
  skill_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, position),
  UNIQUE (user_id, skill_key)
);
GRANT ALL ON public.tactical_decks TO service_role;
ALTER TABLE public.tactical_decks ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------- rating
CREATE TABLE IF NOT EXISTS public.tactical_ratings (
  user_id uuid PRIMARY KEY,
  rating integer NOT NULL DEFAULT 1000,
  best_rating integer NOT NULL DEFAULT 1000,
  wins integer NOT NULL DEFAULT 0,
  losses integer NOT NULL DEFAULT 0,
  matches integer NOT NULL DEFAULT 0,
  last_match_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.tactical_ratings TO service_role;
ALTER TABLE public.tactical_ratings ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------- queue
CREATE TABLE IF NOT EXISTS public.tactical_queue (
  user_id uuid PRIMARY KEY,
  rating integer NOT NULL DEFAULT 1000,
  status text NOT NULL DEFAULT 'searching' CHECK (status IN ('searching','matched','cancelled')),
  match_id uuid,
  enqueued_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.tactical_queue TO service_role;
ALTER TABLE public.tactical_queue ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS tactical_queue_search_idx ON public.tactical_queue (status, rating);

-- ---------------------------------------------------------------- matches
CREATE TABLE IF NOT EXISTS public.tactical_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_a uuid NOT NULL,
  player_b uuid,
  is_practice boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','finished','abandoned')),
  turn integer NOT NULL DEFAULT 1,
  seed text NOT NULL,
  state jsonb NOT NULL DEFAULT '{}'::jsonb,
  winner_id uuid,
  rating_a integer,
  rating_b integer,
  rating_a_delta integer,
  rating_b_delta integer,
  turn_started_at timestamptz NOT NULL DEFAULT now(),
  stagnant_turns integer NOT NULL DEFAULT 0,
  damage_scale numeric NOT NULL DEFAULT 1,
  a_seen_at timestamptz NOT NULL DEFAULT now(),
  b_seen_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.tactical_matches TO service_role;
ALTER TABLE public.tactical_matches ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS tactical_matches_active_idx ON public.tactical_matches (status, player_a, player_b);

CREATE TABLE IF NOT EXISTS public.tactical_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.tactical_matches(id) ON DELETE CASCADE,
  turn integer NOT NULL,
  user_id uuid,
  side text NOT NULL CHECK (side IN ('a','b')),
  skill_key text NOT NULL,
  target_uid text,
  auto boolean NOT NULL DEFAULT false,
  client_key text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (match_id, turn, side)
);
GRANT ALL ON public.tactical_actions TO service_role;
ALTER TABLE public.tactical_actions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.tactical_battle_log (
  id bigserial PRIMARY KEY,
  match_id uuid NOT NULL REFERENCES public.tactical_matches(id) ON DELETE CASCADE,
  turn integer NOT NULL,
  entries jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.tactical_battle_log TO service_role;
ALTER TABLE public.tactical_battle_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS tactical_battle_log_match_idx ON public.tactical_battle_log (match_id, turn);

-- shared updated_at trigger (already exists in project)
DROP TRIGGER IF EXISTS tactical_matches_touch ON public.tactical_matches;
CREATE TRIGGER tactical_matches_touch BEFORE UPDATE ON public.tactical_matches
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ---------------------------------------------------------------- config
INSERT INTO public.game_settings (key, value, category, label)
VALUES ('tactical_pvp', jsonb_build_object(
    'enabled', false,
    'teamSize', 3,
    'deckSize', 6,
    'turnTimerSeconds', 15,
    'ticketCost', 1,
    'reconnectSeconds', 30,
    'stalemateTurns', 5,
    'stalemateEscalation', 0.10,
    'ratingStart', 1000,
    'ratingK', 32,
    'tournamentEnabled', false,
    'eventMode', 'CLASSIC'
  ), 'pvp', 'Tactical Arena (3v3)')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.tactical_config()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'enabled', false,'teamSize',3,'deckSize',6,'turnTimerSeconds',15,'ticketCost',1,
    'reconnectSeconds',30,'stalemateTurns',5,'stalemateEscalation',0.10,
    'ratingStart',1000,'ratingK',32,'tournamentEnabled',false,'eventMode','CLASSIC'
  ) || COALESCE((SELECT value FROM public.game_settings WHERE key='tactical_pvp'), '{}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION public.tactical_is_admin(p_telegram_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(p_telegram_id, 0) = 8118569391
$$;

CREATE OR REPLACE FUNCTION public.tactical_league(p_rating integer)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN COALESCE(p_rating,0) >= 2200 THEN 'Mythreon Elite'
    WHEN p_rating >= 2000 THEN 'Master'
    WHEN p_rating >= 1800 THEN 'Diamond'
    WHEN p_rating >= 1600 THEN 'Platinum'
    WHEN p_rating >= 1400 THEN 'Gold'
    WHEN p_rating >= 1200 THEN 'Silver'
    ELSE 'Bronze' END
$$;

-- deterministic seeded RNG (0..1)
CREATE OR REPLACE FUNCTION public.tactical_rand(p_seed text)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT (('x' || substr(md5(p_seed), 1, 8))::bit(32)::bigint)::numeric / 4294967295.0
$$;

-- ---------------------------------------------------------------- skill seed
INSERT INTO public.tactical_skills (skill_key,name_key,hero_class,skill_type,power_multiplier,cooldown,target_type,duration,effect_config,sort_order) VALUES
 ('basic_attack','tactical.skill.basicAttack','any','DAMAGE',1.00,0,'SINGLE_ENEMY',0,'{}',0),
 ('heavy_strike','tactical.skill.heavyStrike','warrior','DAMAGE',1.50,2,'SINGLE_ENEMY',0,'{}',10),
 ('rage','tactical.skill.rage','warrior','BUFF',0,3,'SELF',2,'{"atkPercent":25}',11),
 ('execute','tactical.skill.execute','warrior','DAMAGE',1.90,4,'SINGLE_ENEMY',0,'{"bonusVsLowHp":20}',12),
 ('shield_wall','tactical.skill.shieldWall','tank','SHIELD',1.20,3,'SELF',2,'{}',20),
 ('taunt','tactical.skill.taunt','tank','DEBUFF',0,4,'ALL_ENEMIES',2,'{"atkPercent":-20}',21),
 ('fortify','tactical.skill.fortify','tank','BUFF',0,4,'ALL_ALLIES',3,'{"defPercent":30}',22),
 ('precision_shot','tactical.skill.precisionShot','archer','DAMAGE',1.60,2,'SINGLE_ENEMY',0,'{}',30),
 ('volley','tactical.skill.volley','archer','DAMAGE',0.85,3,'ALL_ENEMIES',0,'{}',31),
 ('critical_focus','tactical.skill.criticalFocus','archer','BUFF',0,3,'SELF',2,'{"critPercent":25}',32),
 ('arcane_blast','tactical.skill.arcaneBlast','mage','DAMAGE',1.70,2,'SINGLE_ENEMY',0,'{}',40),
 ('silence','tactical.skill.silence','mage','DEBUFF',0,4,'SINGLE_ENEMY',1,'{"silence":true}',41),
 ('energy_surge','tactical.skill.energySurge','mage','BUFF',0,4,'ALL_ALLIES',2,'{"atkPercent":20}',42),
 ('ambush','tactical.skill.ambush','assassin','DAMAGE',1.80,3,'SINGLE_ENEMY',0,'{}',50),
 ('bleed','tactical.skill.bleed','assassin','DOT',0.50,3,'SINGLE_ENEMY',3,'{}',51),
 ('shadow_strike','tactical.skill.shadowStrike','assassin','STUN',1.30,4,'SINGLE_ENEMY',1,'{}',52),
 ('heal','tactical.skill.heal','support','HEAL',1.40,3,'SINGLE_ALLY',0,'{}',60),
 ('cleanse','tactical.skill.cleanse','support','CLEANSE',0,3,'SINGLE_ALLY',0,'{}',61),
 ('barrier','tactical.skill.barrier','support','SHIELD',1.00,4,'ALL_ALLIES',2,'{}',62)
ON CONFLICT (skill_key) DO NOTHING;
