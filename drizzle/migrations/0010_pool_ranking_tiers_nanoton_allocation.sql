-- 1) Configurable ranking tiers (single source of truth for ranking distribution)
CREATE TABLE IF NOT EXISTS public.pool_ranking_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  start_rank int NOT NULL CHECK (start_rank >= 1),
  end_rank int NOT NULL CHECK (end_rank >= 1),
  pool_percent numeric(9,6) NOT NULL CHECK (pool_percent >= 0),
  reward_mode text NOT NULL DEFAULT 'EQUAL_SPLIT',
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_rank >= start_rank)
);
CREATE UNIQUE INDEX IF NOT EXISTS pool_ranking_tiers_range_key ON public.pool_ranking_tiers(start_rank, end_rank);

GRANT SELECT ON public.pool_ranking_tiers TO authenticated;
GRANT ALL ON public.pool_ranking_tiers TO service_role;
ALTER TABLE public.pool_ranking_tiers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ranking tiers readable" ON public.pool_ranking_tiers;
CREATE POLICY "ranking tiers readable" ON public.pool_ranking_tiers FOR SELECT TO authenticated USING (true);

-- Seed a monotonically decreasing curve that sums to exactly 100%
INSERT INTO public.pool_ranking_tiers(start_rank,end_rank,pool_percent) VALUES
  (1,1,15),(2,2,10),(3,3,8),(4,10,21),(11,25,18),(26,50,15),(51,100,13)
ON CONFLICT (start_rank,end_rank) DO UPDATE SET pool_percent=excluded.pool_percent, updated_at=now();

-- 2) Deterministic nanoton allocator: sum(amounts) == pool, always
CREATE OR REPLACE FUNCTION public.pool_ranking_allocation(p_ranking_total numeric, p_participants int)
RETURNS TABLE(rank_position int, amount_nanoton bigint, amount_ton numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_nano bigint := floor(coalesce(p_ranking_total,0) * 1000000000)::bigint;
  v_limit int;
BEGIN
  v_limit := least(coalesce(p_participants,0), coalesce((select ranking_winner_limit from pool_settings where id), 100));
  IF v_total_nano <= 0 OR v_limit <= 0 THEN RETURN; END IF;

  RETURN QUERY
  WITH ranks AS (SELECT generate_series(1, v_limit) AS pos),
  weighted AS (
    SELECT r.pos,
           t.pool_percent / greatest(1, (t.end_rank - t.start_rank + 1))::numeric AS weight
    FROM ranks r
    JOIN pool_ranking_tiers t ON r.pos BETWEEN t.start_rank AND t.end_rank
  ),
  wsum AS (SELECT sum(weight) sw FROM weighted),
  base AS (
    SELECT w.pos, floor(v_total_nano::numeric * w.weight / (SELECT sw FROM wsum))::bigint AS nano
    FROM weighted w WHERE (SELECT sw FROM wsum) > 0
  ),
  leftover AS (SELECT v_total_nano - coalesce(sum(nano),0) AS rest FROM base),
  final AS (
    SELECT b.pos, b.nano
           + CASE WHEN row_number() OVER (ORDER BY b.nano DESC, b.pos) <= (SELECT rest FROM leftover) THEN 1 ELSE 0 END AS nano
    FROM base b
  )
  SELECT f.pos::int, f.nano, (f.nano::numeric / 1000000000) FROM final f ORDER BY f.pos;
END $$;

REVOKE ALL ON FUNCTION public.pool_ranking_allocation(numeric,int) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pool_ranking_allocation(numeric,int) TO service_role;

-- 3) Validation / preview helper
CREATE OR REPLACE FUNCTION public.pool_ranking_distribution_status(p_ranking_total numeric DEFAULT NULL, p_participants int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total numeric := p_ranking_total;
  v_alloc_nano bigint;
  v_expected_nano bigint;
BEGIN
  IF v_total IS NULL THEN
    SELECT round(b.balance_ton * s.ranking_share_percent / 100, 9)
      INTO v_total
      FROM pool_balance b, pool_settings s
     WHERE b.status='active' AND s.id ORDER BY b.starts_at DESC LIMIT 1;
  END IF;
  v_expected_nano := floor(coalesce(v_total,0) * 1000000000)::bigint;
  SELECT coalesce(sum(amount_nanoton),0) INTO v_alloc_nano
    FROM public.pool_ranking_allocation(v_total, p_participants);

  RETURN jsonb_build_object(
    'rankingPoolTon', coalesce(v_total,0),
    'participants', p_participants,
    'expectedNanoton', v_expected_nano,
    'allocatedNanoton', v_alloc_nano,
    'unallocatedNanoton', v_expected_nano - v_alloc_nano,
    'valid', v_expected_nano = v_alloc_nano,
    'status', CASE WHEN v_expected_nano = v_alloc_nano THEN 'DISTRIBUTION_VALID' ELSE 'INVALID_DISTRIBUTION' END,
    'tierPercentSum', (SELECT coalesce(sum(pool_percent),0) FROM pool_ranking_tiers),
    'tiers', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'startRank',t.start_rank,'endRank',t.end_rank,'poolPercent',t.pool_percent,'rewardMode',t.reward_mode,
        'rewardPerPlayerTon',(SELECT round(avg(a.amount_ton),9) FROM public.pool_ranking_allocation(v_total,p_participants) a WHERE a.rank_position BETWEEN t.start_rank AND t.end_rank),
        'totalTierAllocationTon',(SELECT coalesce(sum(a.amount_ton),0) FROM public.pool_ranking_allocation(v_total,p_participants) a WHERE a.rank_position BETWEEN t.start_rank AND t.end_rank)
      ) ORDER BY t.start_rank),'[]') FROM pool_ranking_tiers t)
  );
END $$;

REVOKE ALL ON FUNCTION public.pool_ranking_distribution_status(numeric,int) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pool_ranking_distribution_status(numeric,int) TO service_role;

-- 4) Admin: edit a tier (with validation) and read distribution
CREATE OR REPLACE FUNCTION public.admin_pool_ranking_tiers(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ranking numeric; v_raffle numeric; v_participants int; BEGIN
  PERFORM admin_assert(p_admin_id);
  SELECT round(b.balance_ton*s.ranking_share_percent/100,9), round(b.balance_ton*s.lottery_share_percent/100,9)
    INTO v_ranking, v_raffle FROM pool_balance b, pool_settings s WHERE b.status='active' AND s.id ORDER BY b.starts_at DESC LIMIT 1;
  SELECT least(100, coalesce((select ranking_winner_limit from pool_settings where id),100)) INTO v_participants;
  RETURN jsonb_build_object(
    'totalPoolTon', coalesce(v_ranking,0)+coalesce(v_raffle,0),
    'rankingPoolTon', coalesce(v_ranking,0),
    'rafflePoolTon', coalesce(v_raffle,0),
    'ranking', public.pool_ranking_distribution_status(v_ranking, v_participants)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_pool_ranking_tier_set(p_admin_id bigint, p_start int, p_end int, p_percent numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_sum numeric; BEGIN
  PERFORM admin_assert(p_admin_id);
  IF p_end < p_start OR p_start < 1 THEN RAISE EXCEPTION 'INVALID_RANGE'; END IF;
  INSERT INTO pool_ranking_tiers(start_rank,end_rank,pool_percent)
  VALUES (p_start,p_end,p_percent)
  ON CONFLICT (start_rank,end_rank) DO UPDATE SET pool_percent=excluded.pool_percent, updated_at=now();
  SELECT coalesce(sum(pool_percent),0) INTO v_sum FROM pool_ranking_tiers;
  RETURN jsonb_build_object('tierPercentSum', v_sum, 'valid', v_sum = 100,
    'ranking', public.admin_pool_ranking_tiers(p_admin_id));
END $$;

REVOKE ALL ON FUNCTION public.admin_pool_ranking_tiers(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_pool_ranking_tier_set(bigint,int,int,numeric) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_pool_ranking_tiers(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_pool_ranking_tier_set(bigint,int,int,numeric) TO service_role;

-- 5) Estimates now come from the allocator (same function used by settlement)
CREATE OR REPLACE FUNCTION public.get_community_pool_ranking_with_estimates(p_pool_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(rank_position integer, user_id uuid, username text, avatar_url text, points integer, eligible boolean, estimated_ranking_reward_ton numeric, raffle_weight numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  with b as (select * from pool_balance where id = coalesce(p_pool_id,(select id from pool_balance where status='active' order by starts_at desc limit 1))),
  s as (select * from pool_settings where id),
  ranking_total as (select round((select balance_ton from b) * (select ranking_share_percent from s) / 100, 9) v),
  scores as (select pp.user_id, sum(pp.points)::int points from pool_points pp where pp.pool_id=(select id from b) group by pp.user_id),
  valid as (
    select sc.user_id, sc.points, coalesce(gp.display_name,'Jogador') username, gp.avatar_url
    from scores sc join game_players gp on gp.id=sc.user_id
    where sc.points >= (select minimum_points from s)
      and not coalesce(gp.pvp_banned,false)
      and (select count(*) from player_heroes h where h.user_id=sc.user_id) >= coalesce((select minimum_heroes from s),5)
  ),
  ranked as (select row_number() over (order by points desc, user_id)::int rank_position, v.* from valid v),
  capped as (select * from ranked where rank_position <= least(100,(select ranking_winner_limit from s))),
  alloc as (select * from public.pool_ranking_allocation((select v from ranking_total), (select count(*)::int from capped))),
  total_points as (select coalesce(sum(points),0)::numeric tp from valid)
  select c.rank_position, c.user_id, c.username, c.avatar_url, c.points, true,
    coalesce(a.amount_ton, 0),
    case when (select tp from total_points) > 0 then round(c.points::numeric/(select tp from total_points),9) else 0 end
  from capped c
  left join alloc a on a.rank_position = c.rank_position
  order by c.rank_position
$$;
