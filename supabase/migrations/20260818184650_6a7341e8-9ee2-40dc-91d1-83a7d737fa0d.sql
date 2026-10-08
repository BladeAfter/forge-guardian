-- Ownership transfer must strip the item from every team of the previous owner.
CREATE OR REPLACE FUNCTION public.detach_hero_everywhere(p_hero uuid, p_owner uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if p_hero is null then return; end if;
  delete from pvp_team_slots where hero_id = p_hero;
  delete from boss_team_slots where player_hero_id = p_hero;
  delete from tower_team_slots where hero_id = p_hero;
  delete from tactical_teams where player_hero_id = p_hero;
  delete from hero_combat_state where hero_id = p_hero;
  update clan_war_defenses
     set hero_ids = array_remove(hero_ids, p_hero), updated_at = now()
   where p_hero = any(hero_ids);
  update pet_expeditions
     set hero_ids = array_remove(hero_ids, p_hero)
   where p_hero = any(hero_ids);
  -- Equipment stays with the seller: the hero leaves unequipped.
  update player_equipment set hero_id = null, updated_at = now() where hero_id = p_hero;
end $$;

CREATE OR REPLACE FUNCTION public.detach_pet_everywhere(p_pet uuid, p_owner uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if p_pet is null then return; end if;
  update clan_war_defenses set pet_id = null, updated_at = now() where pet_id = p_pet;
  update pet_expeditions set pet_ids = array_remove(pet_ids, p_pet) where p_pet = any(pet_ids);
end $$;

REVOKE ALL ON FUNCTION public.detach_hero_everywhere(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.detach_pet_everywhere(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.detach_hero_everywhere(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.detach_pet_everywhere(uuid, uuid) TO service_role;

-- Runs on every transfer path (market, auction, admin, breeding) and when listed.
CREATE OR REPLACE FUNCTION public.tg_hero_ownership_detach()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if new.user_id is distinct from old.user_id
     or (coalesce(new.market_locked,false) and not coalesce(old.market_locked,false)) then
    perform public.detach_hero_everywhere(new.id, old.user_id);
  end if;
  return new;
end $$;

CREATE OR REPLACE FUNCTION public.tg_pet_ownership_detach()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if new.user_id is distinct from old.user_id
     or (coalesce(new.market_locked,false) and not coalesce(old.market_locked,false)) then
    perform public.detach_pet_everywhere(new.id, old.user_id);
  end if;
  return new;
end $$;

DROP TRIGGER IF EXISTS trg_hero_ownership_detach ON public.player_heroes;
CREATE TRIGGER trg_hero_ownership_detach
AFTER UPDATE OF user_id, market_locked ON public.player_heroes
FOR EACH ROW EXECUTE FUNCTION public.tg_hero_ownership_detach();

DROP TRIGGER IF EXISTS trg_pet_ownership_detach ON public.player_pets;
CREATE TRIGGER trg_pet_ownership_detach
AFTER UPDATE OF user_id, market_locked ON public.player_pets
FOR EACH ROW EXECUTE FUNCTION public.tg_pet_ownership_detach();

-- One-off repair of rows left behind by past sales.
DELETE FROM public.pvp_team_slots s USING public.player_heroes h WHERE h.id = s.hero_id AND h.user_id <> s.user_id;
DELETE FROM public.boss_team_slots s USING public.player_heroes h WHERE h.id = s.player_hero_id AND h.user_id <> s.user_id;
DELETE FROM public.tower_team_slots s USING public.player_heroes h WHERE h.id = s.hero_id AND h.user_id <> s.user_id;
DELETE FROM public.tactical_teams s USING public.player_heroes h WHERE h.id = s.player_hero_id AND h.user_id <> s.user_id;
UPDATE public.player_equipment e SET hero_id = NULL, updated_at = now()
  FROM public.player_heroes h WHERE h.id = e.hero_id AND h.user_id <> e.user_id;
UPDATE public.clan_war_defenses d SET hero_ids = (
    SELECT coalesce(array_agg(x), '{}'::uuid[]) FROM unnest(d.hero_ids) x
     JOIN public.player_heroes h ON h.id = x AND h.user_id = d.user_id
  ), updated_at = now()
 WHERE EXISTS (SELECT 1 FROM unnest(d.hero_ids) x JOIN public.player_heroes h ON h.id = x WHERE h.user_id <> d.user_id);
UPDATE public.clan_war_defenses d SET pet_id = NULL, updated_at = now()
  FROM public.player_pets p WHERE p.id = d.pet_id AND p.user_id <> d.user_id;