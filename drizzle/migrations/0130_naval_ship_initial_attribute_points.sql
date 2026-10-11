ALTER TABLE public.naval_owned_ships ADD COLUMN IF NOT EXISTS initial_points_granted integer NOT NULL DEFAULT 0;
COMMENT ON COLUMN public.naval_owned_ships.initial_points_granted IS 'Initial attribute point grant already included in available or allocated points; prevents duplicate backfills.';
UPDATE public.naval_owned_ships SET points = points + (10 - initial_points_granted), initial_points_granted = 10 WHERE initial_points_granted < 10;
ALTER TABLE public.naval_owned_ships ALTER COLUMN points SET DEFAULT 10;
ALTER TABLE public.naval_owned_ships ALTER COLUMN initial_points_granted SET DEFAULT 10;