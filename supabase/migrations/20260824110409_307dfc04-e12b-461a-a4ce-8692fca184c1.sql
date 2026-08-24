ALTER TABLE public.clan_boss_scaling_config
  ADD COLUMN IF NOT EXISTS fixed_hp numeric NOT NULL DEFAULT 0;

UPDATE public.clan_boss_scaling_config
   SET fixed_hp = 500000000,
       max_hp_cap = 500000000,
       updated_at = now()
 WHERE id = 1;

CREATE OR REPLACE FUNCTION public.clan_boss_apply_fixed_hp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_fixed numeric;
BEGIN
  SELECT fixed_hp INTO v_fixed FROM public.clan_boss_scaling_config WHERE id = 1;
  IF COALESCE(v_fixed, 0) > 0 THEN
    NEW.max_hp := round(v_fixed);
    NEW.current_hp := LEAST(COALESCE(NEW.current_hp, round(v_fixed)), round(v_fixed));
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.clan_boss_apply_fixed_hp() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_clan_boss_fixed_hp ON public.clan_boss_instances;
CREATE TRIGGER trg_clan_boss_fixed_hp
BEFORE INSERT ON public.clan_boss_instances
FOR EACH ROW EXECUTE FUNCTION public.clan_boss_apply_fixed_hp();

UPDATE public.clan_boss_instances
   SET max_hp = 500000000,
       current_hp = LEAST(current_hp, 500000000)
 WHERE status = 'active';