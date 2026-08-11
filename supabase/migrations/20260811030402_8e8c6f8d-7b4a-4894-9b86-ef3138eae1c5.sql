-- =========================================================================
-- GLOBAL BOSS: one shared boss for the whole server.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.global_boss_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_number integer NOT NULL,
  boss_key text NOT NULL,
  boss_name text NOT NULL,
  boss_image text,
  boss_level integer NOT NULL DEFAULT 1,
  max_hp numeric NOT NULL CHECK (max_hp > 0),
  current_hp numeric NOT NULL CHECK (current_hp >= 0),
  reward_pool_fc numeric NOT NULL DEFAULT 0 CHECK (reward_pool_fc >= 0),
  total_damage numeric NOT NULL DEFAULT 0,
  participants integer NOT NULL DEFAULT 0,
  minimum_damage_percent numeric NOT NULL DEFAULT 0.1,
  minimum_damage_fixed numeric NOT NULL DEFAULT 0,
  minimum_reward_fc numeric NOT NULL DEFAULT 0,
  rank_bonus_enabled boolean NOT NULL DEFAULT false,
  rank_bonus jsonb NOT NULL DEFAULT '[5,3,2]'::jsonb,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','defeated','distributing','completed')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  defeated_at timestamptz,
  distributed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS global_boss_cycles_one_active
  ON public.global_boss_cycles ((status = 'active')) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS global_boss_cycles_number ON public.global_boss_cycles (cycle_number);

GRANT SELECT ON public.global_boss_cycles TO authenticated;
GRANT ALL ON public.global_boss_cycles TO service_role;
ALTER TABLE public.global_boss_cycles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages global boss" ON public.global_boss_cycles;
CREATE POLICY "service role manages global boss" ON public.global_boss_cycles TO service_role USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.global_boss_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  boss_cycle_id uuid NOT NULL REFERENCES public.global_boss_cycles(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  telegram_id bigint,
  damage_total numeric NOT NULL DEFAULT 0,
  attacks integer NOT NULL DEFAULT 0,
  reward_amount numeric NOT NULL DEFAULT 0,
  reward_claimed boolean NOT NULL DEFAULT false,
  final_rank integer,
  last_attack_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (boss_cycle_id, user_id)
);
CREATE INDEX IF NOT EXISTS global_boss_participants_rank_idx
  ON public.global_boss_participants (boss_cycle_id, damage_total DESC);
GRANT SELECT ON public.global_boss_participants TO authenticated;
GRANT ALL ON public.global_boss_participants TO service_role;
ALTER TABLE public.global_boss_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages boss participants" ON public.global_boss_participants;
CREATE POLICY "service role manages boss participants" ON public.global_boss_participants TO service_role USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.global_boss_reward_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  boss_cycle_id uuid NOT NULL REFERENCES public.global_boss_cycles(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  damage_total numeric NOT NULL DEFAULT 0,
  share_percent numeric NOT NULL DEFAULT 0,
  reward_fc numeric NOT NULL DEFAULT 0,
  rank integer,
  distributed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (boss_cycle_id, user_id)
);
GRANT SELECT ON public.global_boss_reward_ledger TO authenticated;
GRANT ALL ON public.global_boss_reward_ledger TO service_role;
ALTER TABLE public.global_boss_reward_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages boss reward ledger" ON public.global_boss_reward_ledger;
CREATE POLICY "service role manages boss reward ledger" ON public.global_boss_reward_ledger TO service_role USING (true) WITH CHECK (true);

ALTER TABLE public.boss_combats ADD COLUMN IF NOT EXISTS cycle_id uuid REFERENCES public.global_boss_cycles(id) ON DELETE SET NULL;

-- The shared HP is authoritative; the mirrored per-player row may lag behind it.
ALTER TABLE public.boss_combats DROP CONSTRAINT IF EXISTS boss_combats_check;
ALTER TABLE public.boss_combats ADD CONSTRAINT boss_combats_check
  CHECK (boss_level >= 1 AND boss_max_hp > 0 AND boss_current_hp >= 0 AND boss_attack > 0);

-- =========================================================================
-- Cycle lifecycle
-- =========================================================================
CREATE OR REPLACE FUNCTION public.ensure_global_boss_cycle()
RETURNS public.global_boss_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; b public.boss_templates; v_pool numeric;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NOT NULL THEN
    IF cyc.ends_at IS NOT NULL AND cyc.ends_at <= now() THEN
      UPDATE public.global_boss_cycles SET status = 'defeated', defeated_at = COALESCE(defeated_at, now()), updated_at = now()
        WHERE id = cyc.id RETURNING * INTO cyc;
      PERFORM public.distribute_global_boss_rewards(cyc.id);
      SELECT * INTO cyc FROM public.global_boss_cycles WHERE id = cyc.id;
      RETURN NULL;
    END IF;
    RETURN cyc;
  END IF;

  b := public.active_boss_template();
  IF b.code IS NULL THEN RETURN NULL; END IF;
  v_pool := COALESCE((SELECT (value#>>'{}')::numeric FROM public.game_settings WHERE key = 'global_boss_reward_pool_fc'), b.reward_amount);

  INSERT INTO public.global_boss_cycles
    (cycle_number, boss_key, boss_name, boss_image, boss_level, max_hp, current_hp, reward_pool_fc, starts_at, ends_at)
  VALUES ((SELECT COALESCE(max(cycle_number), 0) + 1 FROM public.global_boss_cycles),
          b.code, b.name, b.image_url, b.level, b.max_hp, b.max_hp, v_pool,
          COALESCE(b.starts_at, now()), COALESCE(b.ends_at, now() + make_interval(secs => GREATEST(300, COALESCE(b.duration_seconds, 86400)))))
  ON CONFLICT DO NOTHING
  RETURNING * INTO cyc;
  IF cyc.id IS NULL THEN SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1; END IF;
  RETURN cyc;
END; $$;

-- Atomic, idempotent proportional distribution.
CREATE OR REPLACE FUNCTION public.distribute_global_boss_rewards(p_cycle_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; v_total numeric; v_min numeric; v_paid numeric := 0;
        v_count int := 0; r record; v_share numeric; v_reward numeric; v_bonus numeric; v_before numeric;
        v_pet numeric; v_bonus_list jsonb;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE id = p_cycle_id FOR UPDATE;
  IF cyc.id IS NULL THEN RAISE EXCEPTION 'BOSS_CYCLE_NOT_FOUND'; END IF;
  IF cyc.status = 'completed' THEN
    RETURN jsonb_build_object('cycleId', cyc.id, 'status', cyc.status, 'alreadyDistributed', true);
  END IF;
  IF cyc.status = 'active' THEN RAISE EXCEPTION 'BOSS_STILL_ACTIVE'; END IF;

  UPDATE public.global_boss_cycles SET status = 'distributing', updated_at = now() WHERE id = cyc.id;

  SELECT COALESCE(sum(damage_total), 0) INTO v_total FROM public.global_boss_participants WHERE boss_cycle_id = cyc.id;
  v_min := GREATEST(COALESCE(cyc.minimum_damage_fixed, 0), cyc.max_hp * COALESCE(cyc.minimum_damage_percent, 0) / 100.0);
  v_bonus_list := COALESCE(cyc.rank_bonus, '[]'::jsonb);

  IF v_total > 0 THEN
    FOR r IN
      SELECT p.*, row_number() OVER (ORDER BY p.damage_total DESC, p.created_at) AS rnk
        FROM public.global_boss_participants p
       WHERE p.boss_cycle_id = cyc.id AND p.damage_total > 0
       ORDER BY p.damage_total DESC
    LOOP
      v_share := r.damage_total / v_total;
      IF r.damage_total < v_min THEN
        v_reward := COALESCE(cyc.minimum_reward_fc, 0);
      ELSE
        v_reward := cyc.reward_pool_fc * v_share;
        IF cyc.rank_bonus_enabled AND r.rnk <= jsonb_array_length(v_bonus_list) THEN
          v_bonus := COALESCE((v_bonus_list->>(r.rnk - 1)::int)::numeric, 0);
          v_reward := v_reward * (1 + v_bonus / 100.0);
        END IF;
      END IF;
      -- Pet reward bonus stays personal and never changes other players' share.
      v_pet := GREATEST(0, COALESCE((public.get_pet_bonuses(r.user_id)->>'reward_percent')::numeric, 0));
      v_reward := round(v_reward * (1 + v_pet / 100.0));

      UPDATE public.global_boss_participants
         SET reward_amount = v_reward, final_rank = r.rnk, updated_at = now()
       WHERE id = r.id;

      INSERT INTO public.global_boss_reward_ledger (boss_cycle_id, user_id, damage_total, share_percent, reward_fc, rank)
      VALUES (cyc.id, r.user_id, r.damage_total, round(v_share * 100, 4), v_reward, r.rnk)
      ON CONFLICT (boss_cycle_id, user_id) DO NOTHING;
      IF NOT FOUND THEN CONTINUE; END IF;

      IF v_reward > 0 THEN
        SELECT forge_coins INTO v_before FROM public.game_players WHERE id = r.user_id FOR UPDATE;
        UPDATE public.game_players
           SET forge_coins = forge_coins + v_reward, boss_defeats = boss_defeats + 1, updated_at = now()
         WHERE id = r.user_id;
        INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
        VALUES (r.user_id, 'global_boss_reward', v_reward, COALESCE(v_before, 0), COALESCE(v_before, 0) + v_reward,
                cyc.id::text || ':' || r.user_id::text)
        ON CONFLICT DO NOTHING;
        v_paid := v_paid + v_reward;
      END IF;
      UPDATE public.global_boss_participants SET reward_claimed = true, updated_at = now() WHERE id = r.id;
      v_count := v_count + 1;
    END LOOP;
  END IF;

  UPDATE public.global_boss_cycles
     SET status = 'completed', total_damage = GREATEST(total_damage, v_total),
         distributed_at = now(), defeated_at = COALESCE(defeated_at, now()), updated_at = now()
   WHERE id = cyc.id;
  UPDATE public.boss_combats SET status = 'rewarded', updated_at = now()
   WHERE cycle_id = cyc.id AND status IN ('active','defeated');

  RETURN jsonb_build_object('cycleId', cyc.id, 'status', 'completed', 'rewarded', v_count,
                            'totalDamage', v_total, 'paid', v_paid);
END; $$;

-- =========================================================================
-- Damage recording (server authoritative, never above remaining HP)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.record_global_boss_damage(p_cycle_id uuid, p_user uuid, p_damage numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tg bigint;
BEGIN
  IF COALESCE(p_damage, 0) <= 0 THEN RETURN; END IF;
  SELECT telegram_id INTO v_tg FROM public.game_players WHERE id = p_user;
  INSERT INTO public.global_boss_participants (boss_cycle_id, user_id, telegram_id, damage_total, attacks, last_attack_at)
  VALUES (p_cycle_id, p_user, v_tg, p_damage, 1, now())
  ON CONFLICT (boss_cycle_id, user_id) DO UPDATE
    SET damage_total = public.global_boss_participants.damage_total + EXCLUDED.damage_total,
        attacks = public.global_boss_participants.attacks + 1,
        telegram_id = COALESCE(public.global_boss_participants.telegram_id, EXCLUDED.telegram_id),
        last_attack_at = now(), updated_at = now();
  UPDATE public.global_boss_cycles c
     SET total_damage = c.total_damage + p_damage,
         participants = (SELECT count(*) FROM public.global_boss_participants WHERE boss_cycle_id = c.id AND damage_total > 0),
         updated_at = now()
   WHERE c.id = p_cycle_id;
END; $$;

-- =========================================================================
-- Read models
-- =========================================================================
CREATE OR REPLACE FUNCTION public.global_boss_overlay(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; v_dmg numeric := 0; v_rank int; v_share numeric := 0;
        v_min numeric; v_est numeric := 0; v_last jsonb;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NULL THEN
    SELECT * INTO cyc FROM public.global_boss_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;
  SELECT l.reward_fc, l.rank, l.damage_total, c.boss_name, c.cycle_number
    INTO v_last
    FROM public.global_boss_reward_ledger l JOIN public.global_boss_cycles c ON c.id = l.boss_cycle_id
   WHERE l.user_id = p_user ORDER BY l.distributed_at DESC LIMIT 1;
  IF cyc.id IS NULL THEN RETURN '{}'::jsonb; END IF;

  SELECT damage_total INTO v_dmg FROM public.global_boss_participants WHERE boss_cycle_id = cyc.id AND user_id = p_user;
  v_dmg := COALESCE(v_dmg, 0);
  IF v_dmg > 0 THEN
    SELECT count(*) + 1 INTO v_rank FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND damage_total > v_dmg;
  END IF;
  v_min := GREATEST(COALESCE(cyc.minimum_damage_fixed, 0), cyc.max_hp * COALESCE(cyc.minimum_damage_percent, 0) / 100.0);
  IF cyc.total_damage > 0 THEN
    v_share := v_dmg / cyc.total_damage;
    v_est := CASE WHEN v_dmg >= v_min THEN round(cyc.reward_pool_fc * v_share) ELSE COALESCE(cyc.minimum_reward_fc, 0) END;
  END IF;

  RETURN jsonb_build_object(
    'bossName', cyc.boss_name, 'bossLevel', cyc.boss_level,
    'bossMaxHp', cyc.max_hp, 'bossCurrentHp', cyc.current_hp,
    'rewardAmount', cyc.reward_pool_fc, 'totalDamageDealt', v_dmg,
    'bossActive', cyc.status = 'active',
    'globalBoss', jsonb_build_object(
      'cycleId', cyc.id, 'cycleNumber', cyc.cycle_number, 'name', cyc.boss_name, 'image', cyc.boss_image,
      'status', cyc.status, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp,
      'rewardPoolFc', cyc.reward_pool_fc, 'totalDamage', cyc.total_damage, 'participants', cyc.participants,
      'startsAt', cyc.starts_at, 'endsAt', cyc.ends_at, 'defeatedAt', cyc.defeated_at,
      'minimumDamage', v_min, 'minimumRewardFc', cyc.minimum_reward_fc,
      'rankBonusEnabled', cyc.rank_bonus_enabled,
      'yourDamage', v_dmg, 'yourRank', v_rank, 'yourSharePercent', round(v_share * 100, 4),
      'estimatedReward', v_est,
      'lastReward', v_last));
END; $$;

CREATE OR REPLACE FUNCTION public.get_global_boss_ranking(p_telegram_id bigint, p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE cyc public.global_boss_cycles; v_user uuid; v_limit int := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
        v_min numeric; v_top jsonb; v_you jsonb;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NULL THEN SELECT * INTO cyc FROM public.global_boss_cycles ORDER BY created_at DESC LIMIT 1; END IF;
  IF cyc.id IS NULL THEN RETURN jsonb_build_object('cycle', null, 'top', '[]'::jsonb, 'you', null); END IF;
  v_min := GREATEST(COALESCE(cyc.minimum_damage_fixed, 0), cyc.max_hp * COALESCE(cyc.minimum_damage_percent, 0) / 100.0);

  WITH ranked AS (
    SELECT p.user_id, p.damage_total, row_number() OVER (ORDER BY p.damage_total DESC, p.created_at) AS rnk
      FROM public.global_boss_participants p
     WHERE p.boss_cycle_id = cyc.id AND p.damage_total > 0
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'rank', r.rnk, 'userId', r.user_id,
           'name', COALESCE(NULLIF(g.display_name, ''), NULLIF(g.first_name, ''), NULLIF(g.username, ''), 'Player'),
           'username', g.username, 'photoUrl', g.avatar_url,
           'damage', r.damage_total,
           'sharePercent', CASE WHEN cyc.total_damage > 0 THEN round(100 * r.damage_total / cyc.total_damage, 4) ELSE 0 END,
           'estimatedReward', CASE WHEN cyc.total_damage > 0 AND r.damage_total >= v_min
                                   THEN round(cyc.reward_pool_fc * r.damage_total / cyc.total_damage)
                                   ELSE COALESCE(cyc.minimum_reward_fc, 0) END,
           'isYou', r.user_id = v_user) ORDER BY r.rnk), '[]'::jsonb)
    INTO v_top
    FROM (SELECT * FROM ranked ORDER BY rnk LIMIT v_limit) r
    JOIN public.game_players g ON g.id = r.user_id;

  WITH ranked AS (
    SELECT p.user_id, p.damage_total, row_number() OVER (ORDER BY p.damage_total DESC, p.created_at) AS rnk
      FROM public.global_boss_participants p
     WHERE p.boss_cycle_id = cyc.id AND p.damage_total > 0
  )
  SELECT jsonb_build_object('rank', r.rnk, 'damage', r.damage_total,
           'sharePercent', CASE WHEN cyc.total_damage > 0 THEN round(100 * r.damage_total / cyc.total_damage, 4) ELSE 0 END,
           'estimatedReward', CASE WHEN cyc.total_damage > 0 AND r.damage_total >= v_min
                                   THEN round(cyc.reward_pool_fc * r.damage_total / cyc.total_damage)
                                   ELSE COALESCE(cyc.minimum_reward_fc, 0) END)
    INTO v_you FROM ranked r WHERE r.user_id = v_user;

  RETURN jsonb_build_object(
    'cycle', jsonb_build_object('cycleId', cyc.id, 'cycleNumber', cyc.cycle_number, 'name', cyc.boss_name,
      'status', cyc.status, 'maxHp', cyc.max_hp, 'currentHp', cyc.current_hp, 'rewardPoolFc', cyc.reward_pool_fc,
      'totalDamage', cyc.total_damage, 'participants', cyc.participants, 'minimumDamage', v_min),
    'top', v_top, 'you', v_you);
END; $$;

CREATE OR REPLACE FUNCTION public.get_global_boss_history(p_telegram_id bigint, p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'cycleId', c.id, 'cycleNumber', c.cycle_number, 'name', c.boss_name, 'status', c.status,
      'maxHp', c.max_hp, 'totalDamage', c.total_damage, 'participants', c.participants,
      'rewardPoolFc', c.reward_pool_fc, 'defeatedAt', c.defeated_at,
      'yourDamage', COALESCE(l.damage_total, p.damage_total, 0),
      'yourRank', COALESCE(l.rank, p.final_rank),
      'yourReward', COALESCE(l.reward_fc, 0)) ORDER BY c.cycle_number DESC)
    FROM (SELECT * FROM public.global_boss_cycles WHERE status IN ('completed','defeated','distributing')
           ORDER BY cycle_number DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,10),1),50)) c
    LEFT JOIN public.global_boss_reward_ledger l ON l.boss_cycle_id = c.id AND l.user_id = v_user
    LEFT JOIN public.global_boss_participants p ON p.boss_cycle_id = c.id AND p.user_id = v_user
  ), '[]'::jsonb);
END; $$;