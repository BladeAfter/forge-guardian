-- 1) NFT heroes: only non-tradable, never auto locked / market locked
DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p
   WHERE p.proname='ensure_pvp_hero_stats' AND p.pronamespace='public'::regnamespace;
  d := replace(d,
    'if new.is_nft_exclusive then new.tradable:=false; new.market_locked:=true; new.locked:=true; end if;',
    'if new.is_nft_exclusive then new.tradable:=false; end if;');
  EXECUTE d;
END $$;

-- 2) Repair stale locks on NFT heroes with no active listing
UPDATE public.player_heroes h
   SET market_locked = false, locked = false, tradable = false, updated_at = now()
 WHERE h.is_nft_exclusive
   AND (coalesce(h.market_locked,false) OR coalesce(h.locked,false))
   AND NOT EXISTS (SELECT 1 FROM public.market_listings m
                    WHERE m.item_instance_id = h.id AND m.status IN ('active','reserved'));

UPDATE public.player_pets pp
   SET market_locked = false, tradable = false, updated_at = now()
 WHERE pp.nft_pet_id IS NOT NULL
   AND coalesce(pp.market_locked,false)
   AND NOT EXISTS (SELECT 1 FROM public.market_listings m
                    WHERE m.item_instance_id = pp.id AND m.status IN ('active','reserved'));

-- 3) Usage status: NFT is a category, not an "in use" lock
CREATE OR REPLACE FUNCTION public.hero_usage_status(p_hero_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT jsonb_build_object(
    'manuallyLocked', s.manual,
    'pvpAttack', s.atk,
    'pvpDefense', s.def,
    'globalBoss', s.boss,
    'clanBoss', false,
    'tower', s.tower,
    'marketplace', s.market,
    'isNft', s.nft,
    'notTradeable', s.nft,
    'inUse', (s.manual OR s.atk OR s.def OR s.boss OR s.tower OR s.market),
    'canFuse', NOT (s.manual OR s.atk OR s.def OR s.boss OR s.tower OR s.market OR s.nft),
    'reason', CASE
      WHEN s.manual THEN 'MANUAL'
      WHEN s.atk THEN 'PVP_ATTACK'
      WHEN s.def THEN 'PVP_DEFENSE'
      WHEN s.boss THEN 'BOSS'
      WHEN s.tower THEN 'TOWER'
      WHEN s.market THEN 'MARKET'
      ELSE NULL END
  )
  FROM (
    SELECT
      coalesce(ph.locked, false) AS manual,
      coalesce(ph.is_nft_exclusive, false) AS nft,
      EXISTS(SELECT 1 FROM public.pvp_team_slots t
              WHERE t.hero_id = ph.id AND t.user_id = ph.user_id AND t.team_type = 'attack') AS atk,
      EXISTS(SELECT 1 FROM public.pvp_team_slots t
              WHERE t.hero_id = ph.id AND t.user_id = ph.user_id AND t.team_type = 'defense') AS def,
      EXISTS(SELECT 1 FROM public.boss_team_slots b
              WHERE b.player_hero_id = ph.id AND b.user_id = ph.user_id) AS boss,
      EXISTS(SELECT 1 FROM public.tower_team_slots w
              WHERE w.hero_id = ph.id AND w.user_id = ph.user_id) AS tower,
      EXISTS(SELECT 1 FROM public.market_listings m
              WHERE m.item_instance_id = ph.id AND m.status = 'active') AS market
    FROM public.player_heroes ph
    WHERE ph.id = p_hero_id
  ) s;
$function$;

-- 4) Market: NFT Exclusive can never be listed (backend enforced)
CREATE OR REPLACE FUNCTION public.market_listing_nft_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
begin
  if lower(coalesce(new.item_type,'')) = 'pet'
     and exists (select 1 from public.player_pets pp
                  where pp.id = new.item_instance_id and pp.nft_pet_id is not null) then
    raise exception 'NFT_EXCLUSIVE_NOT_TRADEABLE';
  end if;
  if lower(coalesce(new.item_type,'')) = 'hero'
     and exists (select 1 from public.player_heroes ph
                  where ph.id = new.item_instance_id and coalesce(ph.is_nft_exclusive,false)) then
    raise exception 'NFT_EXCLUSIVE_NOT_TRADEABLE';
  end if;
  return new;
end $function$;