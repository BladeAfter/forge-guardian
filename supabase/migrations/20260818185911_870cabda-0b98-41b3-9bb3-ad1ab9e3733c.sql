-- 1) Detach on DELETE (previously only on ownership UPDATE)
CREATE OR REPLACE FUNCTION public.tg_hero_ownership_detach_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  perform public.detach_hero_everywhere(old.id);
  return old;
end
$$;

CREATE OR REPLACE FUNCTION public.tg_pet_ownership_detach_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  perform public.detach_pet_everywhere(old.id);
  return old;
end
$$;

DROP TRIGGER IF EXISTS trg_hero_detach_on_delete ON public.player_heroes;
CREATE TRIGGER trg_hero_detach_on_delete
AFTER DELETE ON public.player_heroes
FOR EACH ROW EXECUTE FUNCTION public.tg_hero_ownership_detach_delete();

DROP TRIGGER IF EXISTS trg_pet_detach_on_delete ON public.player_pets;
CREATE TRIGGER trg_pet_detach_on_delete
AFTER DELETE ON public.player_pets
FOR EACH ROW EXECUTE FUNCTION public.tg_pet_ownership_detach_delete();

-- 2) Clean up existing stale references to heroes/pets that no longer exist
-- or that no longer belong to the referencing player
DELETE FROM public.tactical_teams t
WHERE t.player_hero_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.player_heroes ph
    WHERE ph.id = t.player_hero_id AND ph.user_id = t.user_id
  );

DELETE FROM public.pvp_team_slots s
WHERE s.hero_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.player_heroes ph
    WHERE ph.id = s.hero_id AND ph.user_id = s.user_id
  );

DELETE FROM public.boss_team_slots s
WHERE s.player_hero_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.player_heroes ph
    WHERE ph.id = s.player_hero_id AND ph.user_id = s.user_id
  );

DELETE FROM public.tower_team_slots s
WHERE s.hero_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.player_heroes ph
    WHERE ph.id = s.hero_id AND ph.user_id = s.user_id
  );

UPDATE public.player_equipment e
SET hero_id = NULL, updated_at = now()
WHERE e.hero_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.player_heroes ph
    WHERE ph.id = e.hero_id AND ph.user_id = e.user_id
  );

UPDATE public.clan_war_defenses d
SET hero_ids = (
      SELECT COALESCE(array_agg(hid), '{}'::uuid[])
      FROM unnest(d.hero_ids) hid
      WHERE EXISTS (
        SELECT 1 FROM public.player_heroes ph
        WHERE ph.id = hid AND ph.user_id = d.user_id
      )
    ),
    updated_at = now()
WHERE EXISTS (
  SELECT 1 FROM unnest(d.hero_ids) hid
  WHERE NOT EXISTS (
    SELECT 1 FROM public.player_heroes ph
    WHERE ph.id = hid AND ph.user_id = d.user_id
  )
);

UPDATE public.clan_war_defenses d
SET pet_id = NULL, updated_at = now()
WHERE d.pet_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.player_pets pp
    WHERE pp.id = d.pet_id AND pp.user_id = d.user_id
  );