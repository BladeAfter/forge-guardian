-- ============ CONFIG TABLES ============
CREATE TABLE public.pet_food_items (
  code text PRIMARY KEY,
  name text NOT NULL,
  rarity text NOT NULL DEFAULT 'common',
  xp_value integer NOT NULL DEFAULT 50,
  icon text NOT NULL DEFAULT 'ration',
  sort_order integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pet_food_items TO service_role;
ALTER TABLE public.pet_food_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.player_pet_food (
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  food_code text NOT NULL REFERENCES public.pet_food_items(code) ON DELETE CASCADE,
  quantity integer NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, food_code)
);
GRANT ALL ON public.player_pet_food TO service_role;
ALTER TABLE public.player_pet_food ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.pet_evolution_tiers (
  tier integer PRIMARY KEY CHECK (tier BETWEEN 1 AND 10),
  label text NOT NULL,
  required_level integer NOT NULL,
  fc_cost numeric NOT NULL DEFAULT 0,
  fragment_cost integer NOT NULL DEFAULT 0,
  primary_multiplier numeric NOT NULL DEFAULT 1,
  new_buff_chance numeric NOT NULL DEFAULT 0,
  max_secondary_buffs integer NOT NULL DEFAULT 1,
  evolution_stage text NOT NULL DEFAULT 'young',
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pet_evolution_tiers TO service_role;
ALTER TABLE public.pet_evolution_tiers ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.pet_buff_pool (
  buff_key text PRIMARY KEY,
  categories jsonb NOT NULL DEFAULT '[]'::jsonb,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pet_buff_pool TO service_role;
ALTER TABLE public.pet_buff_pool ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.pet_evolutions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  player_pet_id uuid NOT NULL REFERENCES public.player_pets(id) ON DELETE CASCADE,
  evolution_from integer NOT NULL,
  evolution_to integer NOT NULL,
  level_at_evolution integer NOT NULL,
  fc_spent numeric NOT NULL DEFAULT 0,
  fragments_spent integer NOT NULL DEFAULT 0,
  unlocked_buff text,
  unlocked_buff_value numeric,
  unlocked_buff_rarity text,
  idempotency_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.pet_evolutions TO service_role;
ALTER TABLE public.pet_evolutions ENABLE ROW LEVEL SECURITY;

-- ============ PLAYER PET COLUMNS ============
ALTER TABLE public.player_pets
  ADD COLUMN IF NOT EXISTS evolution_tier integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS secondary_buffs jsonb NOT NULL DEFAULT '[]'::jsonb;

-- ============ SEED CONFIG ============
INSERT INTO public.pet_food_items (code,name,rarity,xp_value,icon,sort_order) VALUES
  ('pet_ration','Ração de Pet','common',50,'ration',1),
  ('pet_food','Comida de Pet','common',100,'food',2),
  ('pet_meat','Carne','uncommon',250,'meat',3),
  ('pet_magic_fruit','Fruta Mágica','rare',500,'fruit',4),
  ('pet_rare_food','Comida Rara','epic',1000,'rare',5)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.pet_evolution_tiers (tier,label,required_level,fc_cost,fragment_cost,primary_multiplier,new_buff_chance,max_secondary_buffs,evolution_stage) VALUES
  (1,'Evolução I',5,5000,10,1.25,0.25,1,'young'),
  (2,'Evolução II',10,15000,25,1.50,0.35,2,'young'),
  (3,'Evolução III',20,40000,50,2.00,0.50,2,'adult'),
  (4,'Evolução IV',30,80000,100,2.50,0.70,3,'adult'),
  (5,'Forma Suprema',50,150000,200,3.125,1.00,3,'ancestral')
ON CONFLICT (tier) DO NOTHING;

INSERT INTO public.pet_buff_pool (buff_key,categories) VALUES
  ('boss_damage_percent','["dragon","beast","magical"]'),
  ('team_hp_percent','["dragon","beast","magical","bird"]'),
  ('team_attack_percent','["dragon","beast"]'),
  ('defense_percent','["magical","beast"]'),
  ('pvp_attack_percent','["dragon","beast","bird"]'),
  ('pvp_defense_percent','["magical","dragon"]'),
  ('critical_chance_percent','["beast","bird"]'),
  ('critical_damage_percent','["beast","dragon"]'),
  ('farm_fc_percent','["bird","magical"]'),
  ('pet_xp_percent','["bird","magical","beast"]'),
  ('revive_speed_percent','["bird","magical"]'),
  ('pvp_speed_percent','["bird","beast"]')
ON CONFLICT (buff_key) DO NOTHING;

INSERT INTO public.pet_settings (key,value) VALUES
  ('level_curve','{"base":500,"growth":1.3,"max_level":50,"round_to":50}'::jsonb),
  ('secondary_buff_rarities','[{"rarity":"common","value":2,"weight":55},{"rarity":"rare","value":4,"weight":28},{"rarity":"epic","value":6,"weight":13},{"rarity":"legendary","value":10,"weight":4}]'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();

-- Convert the legacy generic food stack into the new named food inventory.
INSERT INTO public.player_pet_food (user_id, food_code, quantity)
SELECT user_id, 'pet_food', quantity
FROM public.player_pet_inventory
WHERE item_type = 'food' AND item_id IS NULL AND quantity > 0
ON CONFLICT (user_id, food_code) DO UPDATE SET quantity = public.player_pet_food.quantity + excluded.quantity;

-- ============ HELPERS ============
CREATE OR REPLACE FUNCTION public.pet_level_xp_required(p_level integer)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cfg jsonb; base numeric; growth numeric; step numeric; lvl int;
BEGIN
  SELECT value INTO cfg FROM pet_settings WHERE key = 'level_curve';
  base := coalesce((cfg->>'base')::numeric, 500);
  growth := coalesce((cfg->>'growth')::numeric, 1.3);
  step := greatest(1, coalesce((cfg->>'round_to')::numeric, 50));
  lvl := greatest(1, coalesce(p_level, 1));
  RETURN (round(base * power(growth, lvl - 1) / step) * step)::int;
END $$;

CREATE OR REPLACE FUNCTION public.pet_max_level()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT (value->>'max_level')::int FROM pet_settings WHERE key = 'level_curve'), 50)
$$;

-- Primary buff multiplier granted by the pet's current evolution tier.
CREATE OR REPLACE FUNCTION public.pet_tier_multiplier(p_tier integer)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT primary_multiplier FROM pet_evolution_tiers WHERE tier = p_tier), 1)
$$;

-- Full buff map of one owned pet: scaled base passives + unlocked secondary buffs.
CREATE OR REPLACE FUNCTION public.player_pet_buffs(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; result jsonb := '{}'::jsonb; e record; b jsonb; cap numeric; val numeric;
BEGIN
  SELECT pp.rarity, pp.level, pp.evolution_tier, pp.secondary_buffs, p.base_passives
    INTO r FROM player_pets pp JOIN pets p ON p.id = pp.pet_id WHERE pp.id = p_player_pet_id;
  IF NOT found THEN RETURN result; END IF;
  FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(coalesce(r.base_passives,'{}'::jsonb)) LOOP
    val := round(e.amount * pet_rarity_multiplier(r.rarity) * (1 + (r.level - 1) * 0.02) * pet_tier_multiplier(r.evolution_tier), 2);
    result := result || jsonb_build_object(e.key, val);
  END LOOP;
  FOR b IN SELECT value FROM jsonb_array_elements(coalesce(r.secondary_buffs,'[]'::jsonb)) LOOP
    val := coalesce((b->>'value')::numeric, 0) + coalesce((result->>(b->>'key'))::numeric, 0);
    result := result || jsonb_build_object(b->>'key', round(val, 2));
  END LOOP;
  -- Apply configured caps so evolutions can never break the economy.
  FOR e IN SELECT key, (value#>>'{}')::numeric AS amount FROM jsonb_each(result) LOOP
    SELECT (value->>e.key)::numeric INTO cap FROM pet_settings WHERE key = 'bonus_caps';
    IF cap IS NOT NULL AND e.amount > cap THEN result := result || jsonb_build_object(e.key, cap); END IF;
  END LOOP;
  RETURN result;
END $$;

-- Bonuses applied to the rest of the game come from the active pet only.
CREATE OR REPLACE FUNCTION public.get_pet_bonuses(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE pid uuid;
BEGIN
  SELECT id INTO pid FROM player_pets WHERE user_id = p_user AND is_active LIMIT 1;
  IF pid IS NULL THEN RETURN '{}'::jsonb; END IF;
  RETURN player_pet_buffs(pid);
END $$;

REVOKE ALL ON FUNCTION public.pet_level_xp_required(integer) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_max_level() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_tier_multiplier(integer) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.player_pet_buffs(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pet_level_xp_required(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_max_level() TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_tier_multiplier(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.player_pet_buffs(uuid) TO service_role;
