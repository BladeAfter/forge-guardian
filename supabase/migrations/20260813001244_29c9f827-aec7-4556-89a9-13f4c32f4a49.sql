ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS name text
  GENERATED ALWAYS AS (coalesce(nullif(display_name, ''), nullif(username, ''), nullif(first_name, ''), 'Jogador')) STORED;