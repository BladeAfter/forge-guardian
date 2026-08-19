ALTER TABLE public.player_equipment
  ADD COLUMN IF NOT EXISTS mining_daily_myth numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS mining_last_at timestamptz;

CREATE OR REPLACE FUNCTION public.pass_exclusive_myth_rate()
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  SELECT GREATEST(COALESCE((SELECT pass_exclusive_myth_per_day FROM hero_mining_settings LIMIT 1), 1000), 0)
$fn$;

CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_now timestamptz := now(); v_ton_gain numeric := 0; v_myth_gain numeric := 0;
        v_pet_myth numeric := 0; v_eq_myth numeric := 0; v_peq_myth numeric := 0;
        v_out numeric; v_room numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;

  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE player_pets SET mining_last_at = v_now WHERE user_id = p_user_id;
    UPDATE nft_equipment SET mining_last_at = v_now WHERE owner_user_id = p_user_id;
    UPDATE player_equipment SET mining_last_at = v_now WHERE user_id = p_user_id AND COALESCE(mining_daily_myth,0) > 0;
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

  -- Reward equipment (milestone / pass weapons): mines MYTH only, never TON.
  WITH qelig AS (
    SELECT q.id, GREATEST(COALESCE(q.mining_daily_myth, 0), 0) AS myth_rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(q.mining_last_at, q.created_at, v_now)))) AS secs
      FROM player_equipment q
     WHERE q.user_id = p_user_id
       AND COALESCE(q.mining_daily_myth, 0) > 0
       AND NOT COALESCE(q.market_locked, false)
       AND NOT EXISTS (SELECT 1 FROM nft_equipment n WHERE n.player_equipment_id = q.id)
  ), qmoved AS (
    UPDATE player_equipment pq SET mining_last_at = v_now
      FROM qelig e WHERE pq.id = e.id
     RETURNING e.myth_rate AS myth_rate, e.secs AS secs
  )
  SELECT COALESCE(SUM(myth_rate * secs / 86400.0), 0) INTO v_peq_myth FROM qmoved;

  v_ton_gain := round(LEAST(GREATEST(v_ton_gain, 0), v_room), 9);
  v_myth_gain := round(GREATEST(v_myth_gain, 0) + GREATEST(v_pet_myth, 0) + GREATEST(v_eq_myth, 0) + GREATEST(v_peq_myth, 0), 9);

  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_ton_gain, 9),
         hero_mining_unclaimed_myth = round(COALESCE(hero_mining_unclaimed_myth, 0) + v_myth_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_out;

  RETURN COALESCE(v_out, 0);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.deliver_myth_sale_milestone_weapon(p_user uuid, p_code text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_tpl uuid;
BEGIN
  SELECT id INTO v_tpl FROM public.equipment_templates WHERE code = p_code;
  IF v_tpl IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.player_equipment WHERE user_id = p_user AND source_ref = v_tpl) THEN RETURN; END IF;
  INSERT INTO public.player_equipment(user_id, template_id, source, source_ref, mining_daily_myth, mining_last_at)
  VALUES (p_user, v_tpl, 'myth_sale_milestone', v_tpl, public.pass_exclusive_myth_rate(), now());
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.deliver_myth_sale_milestone_weapon(uuid, text) FROM anon, authenticated, PUBLIC;
GRANT EXECUTE ON FUNCTION public.deliver_myth_sale_milestone_weapon(uuid, text) TO service_role;