-- 1) NFT equipment mining columns
ALTER TABLE public.nft_equipment
  ADD COLUMN IF NOT EXISTS mining_daily_myth numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS mining_last_at timestamptz;

-- unsold shop units mine 1000 MYTH/day; already sold units untouched
UPDATE public.nft_equipment
   SET mining_daily_myth = 1000
 WHERE status = 'AVAILABLE' AND owner_user_id IS NULL;

-- 2) restore hero/pet shop yields (heroes 100 MYTH, pets 1500 MYTH)
UPDATE public.nft_heroes SET mining_daily_myth = 100 WHERE status = 'AVAILABLE';
UPDATE public.nft_pets SET daily_yield_myth = 1500 WHERE status = 'AVAILABLE';

-- 3) accrue MYTH for owned NFT equipment
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_pet_myth numeric := 0; v_eq_myth numeric := 0; v_out numeric; v_room numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE player_pets SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE nft_equipment SET mining_last_at = v_now WHERE owner_user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;

  v_room := GREATEST(COALESCE(hero_mining_remaining(p_user_id), 0), 0);

  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(
             COALESCE(h.mining_daily_myth, 0),
             CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                  ELSE hero_mining_hero_myth_rate(h.rarity, h.nft_hero_id) END
           ) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate AS rate, e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT
    COALESCE(SUM(CASE WHEN myth_rate <= 0 AND rate > 0 THEN rate * secs / 86400.0 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN myth_rate > 0 THEN myth_rate * secs / 86400.0 ELSE 0 END), 0)
    INTO v_ton_gain, v_myth_gain
    FROM moved;

  WITH pelig AS (
    SELECT p.id, GREATEST(COALESCE(p.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(p.mining_last_at, p.created_at, v_now)))) AS secs
      FROM player_pets p
     WHERE p.user_id = p_user_id
       AND COALESCE(p.mining_daily_myth, 0) > 0
       AND NOT COALESCE(p.market_locked, false)
  ), pmoved AS (
    UPDATE player_pets pp SET mining_last_at = v_now
      FROM pelig e WHERE pp.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_pet_myth FROM pmoved;

  WITH eelig AS (
    SELECT n.id, GREATEST(COALESCE(n.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(n.mining_last_at, n.assigned_at, n.created_at, v_now)))) AS secs
      FROM nft_equipment n
     WHERE n.owner_user_id = p_user_id
       AND n.status <> 'BURNED'
       AND COALESCE(n.mining_daily_myth, 0) > 0
  ), emoved AS (
    UPDATE nft_equipment ne SET mining_last_at = v_now
      FROM eelig e WHERE ne.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_eq_myth FROM emoved;

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := round(GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0) + GREATEST(v_eq_myth, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END $fn$;

REVOKE ALL ON FUNCTION public.hero_mining_accrue(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_mining_accrue(uuid) TO service_role;

-- 4) show equipment yield in the shop payload
CREATE OR REPLACE FUNCTION public.nft_equipment_shop_json(p_telegram_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
declare u uuid; items jsonb; total int; sold int;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(x order by (x->>'serial')::int), '[]'::jsonb), count(*),
         count(*) filter (where x->>'status' = 'SOLD_OUT')
    into items, total, sold
  from (
    select jsonb_build_object(
      'id', n.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'name', t.name, 'code', t.code, 'image', t.image_url,
      'slot', t.slot, 'kind', t.kind, 'heroClass', t.hero_class, 'rarity', 'nft_exclusive',
      'bonusAttack', coalesce(t.bonus_attack,0), 'bonusDefense', coalesce(t.bonus_defense,0),
      'bonusHp', coalesce(t.bonus_hp,0), 'power', coalesce(t.power,0),
      'description', t.description,
      'mythPerDay', round(coalesce(n.mining_daily_myth,0), 9),
      'priceTon', round(coalesce(n.price_ton,15), 9), 'supply', 1,
      'status', case when n.status = 'AVAILABLE' and n.owner_user_id is null then 'AVAILABLE' else 'SOLD_OUT' end,
      'ownedByMe', (u is not null and n.owner_user_id = u)
    ) as x
    from public.nft_equipment n
    join public.equipment_templates t on t.id = n.template_id
    where n.status <> 'BURNED'
      and (
        (n.for_sale and n.owner_user_id is null and n.status = 'AVAILABLE')
        or (u is not null and n.owner_user_id = u)
      )
  ) q;
  return jsonb_build_object(
    'totalSupply', coalesce(total,0), 'sold', coalesce(sold,0),
    'available', coalesce(total,0) - coalesce(sold,0), 'items', items,
    'balanceTon', coalesce((select round(greatest(ton_balance - coalesce(ton_reserved,0),0), 9) from public.game_players where id = u), 0)
  );
end $fn$;

REVOKE ALL ON FUNCTION public.nft_equipment_shop_json(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nft_equipment_shop_json(bigint) TO service_role;