CREATE TABLE IF NOT EXISTS public.global_boss_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  boss_number int NOT NULL UNIQUE,
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  subtitle text,
  theme text NOT NULL DEFAULT 'default',
  image_url text,
  background_url text,
  boss_level int NOT NULL DEFAULT 1,
  max_hp numeric NOT NULL,
  reward_fc numeric NOT NULL,
  duration_seconds int NOT NULL DEFAULT 86400,
  enabled boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.global_boss_templates TO authenticated;
GRANT SELECT ON public.global_boss_templates TO anon;
GRANT ALL ON public.global_boss_templates TO service_role;
ALTER TABLE public.global_boss_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enabled global boss templates are readable" ON public.global_boss_templates;
CREATE POLICY "Enabled global boss templates are readable"
  ON public.global_boss_templates FOR SELECT USING (enabled);

DROP TRIGGER IF EXISTS update_global_boss_templates_updated_at ON public.global_boss_templates;
CREATE TRIGGER update_global_boss_templates_updated_at
  BEFORE UPDATE ON public.global_boss_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.global_boss_templates
  (boss_number, code, name, subtitle, theme, image_url, background_url, boss_level, max_hp, reward_fc, sort_order)
VALUES
  (1,'ancestral_dragon','Ancestral Dragon','The first flame of the old world','ember','/assets/game/global-boss/ancestral-dragon.png',NULL,1,67500,20000,1),
  (2,'infernal_behemoth','Infernal Behemoth','Born inside the burning pits','infernal','/assets/game/global-boss/infernal-behemoth.png',NULL,2,100000,30000,2),
  (3,'void_harbinger','Void Harbinger','Herald of the empty between stars','void','/assets/game/global-boss/void-harbinger.png',NULL,3,150000,45000,3),
  (4,'frozen_leviathan','Frozen Leviathan','Sleeper of the frozen deep','frost','/assets/game/global-boss/frozen-leviathan.png',NULL,4,220000,65000,4),
  (5,'storm_colossus','Storm Colossus','A mountain wearing lightning','storm','/assets/game/global-boss/storm-colossus.png',NULL,5,320000,90000,5),
  (6,'plague_sovereign','Plague Sovereign','Crowned by rot and silence','plague',' /assets/game/global-boss/plague-sovereign.png',NULL,6,450000,125000,6),
  (7,'molten_tyrant','Molten Tyrant','Tyrant of the living forge','molten','/assets/game/global-boss/molten-tyrant.png',NULL,7,620000,170000,7),
  (8,'soul_reaper_king','Soul Reaper King','He harvests what remains','soul','/assets/game/global-boss/soul-reaper-king.png',NULL,8,850000,230000,8),
  (9,'abyss_lord','Abyss Lord','Master of the drowned throne','abyss','/assets/game/global-boss/abyss-lord.png',NULL,9,1150000,300000,9),
  (10,'eternal_worldbreaker','Eternal Worldbreaker','The end that never sleeps','eternal','/assets/game/global-boss/eternal-worldbreaker.png',NULL,10,1500000,400000,10)
ON CONFLICT (boss_number) DO NOTHING;

UPDATE public.global_boss_templates SET image_url = trim(image_url);

ALTER TABLE public.global_boss_cycles
  ADD COLUMN IF NOT EXISTS template_id uuid REFERENCES public.global_boss_templates(id),
  ADD COLUMN IF NOT EXISTS boss_number int,
  ADD COLUMN IF NOT EXISTS boss_subtitle text,
  ADD COLUMN IF NOT EXISTS boss_theme text,
  ADD COLUMN IF NOT EXISTS boss_background text,
  ADD COLUMN IF NOT EXISTS ended_reason text;

CREATE OR REPLACE FUNCTION public.global_boss_template_for_number(p_number int)
RETURNS public.global_boss_templates
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.global_boss_templates
   WHERE enabled AND boss_number = GREATEST(1, COALESCE(p_number, 1))
   LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.global_boss_template_for_number(int) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.ensure_global_boss_cycle()
RETURNS public.global_boss_cycles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE cyc public.global_boss_cycles; b public.boss_templates; t public.global_boss_templates;
        v_pool numeric; v_next int; v_last public.global_boss_cycles; v_reason text;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1;
  IF cyc.id IS NOT NULL THEN
    IF cyc.ends_at IS NOT NULL AND cyc.ends_at <= now() THEN
      -- Time is over: the boss is NOT counted as defeated when HP remains.
      v_reason := CASE WHEN cyc.current_hp > 0 THEN 'expired' ELSE 'defeated' END;
      UPDATE public.global_boss_cycles
         SET status = CASE WHEN v_reason = 'expired' THEN 'expired' ELSE 'defeated' END,
             ended_reason = v_reason,
             defeated_at = CASE WHEN v_reason = 'defeated' THEN COALESCE(defeated_at, now()) ELSE defeated_at END,
             updated_at = now()
       WHERE id = cyc.id RETURNING * INTO cyc;
      PERFORM public.distribute_global_boss_rewards(cyc.id);
      RETURN NULL;
    END IF;
    RETURN cyc;
  END IF;

  -- Progression: the next global boss is always the following template (1 -> 10).
  SELECT * INTO v_last FROM public.global_boss_cycles ORDER BY cycle_number DESC LIMIT 1;
  v_next := COALESCE(v_last.boss_number, 0) + 1;
  IF v_next > (SELECT COALESCE(max(boss_number), 0) FROM public.global_boss_templates WHERE enabled) THEN
    -- Stop at the last boss: "More Global Bosses coming soon".
    RETURN NULL;
  END IF;

  t := public.global_boss_template_for_number(v_next);
  IF t.id IS NULL THEN RETURN NULL; END IF;
  b := public.active_boss_template();
  v_pool := t.reward_fc;

  INSERT INTO public.global_boss_cycles
    (cycle_number, boss_key, boss_name, boss_image, boss_level, max_hp, current_hp, reward_pool_fc,
     starts_at, ends_at, template_id, boss_number, boss_subtitle, boss_theme, boss_background)
  VALUES ((SELECT COALESCE(max(cycle_number), 0) + 1 FROM public.global_boss_cycles),
          COALESCE(t.code, b.code), t.name, t.image_url, t.boss_level, t.max_hp, t.max_hp, v_pool,
          now(), now() + make_interval(secs => GREATEST(300, COALESCE(t.duration_seconds, 86400))),
          t.id, t.boss_number, t.subtitle, t.theme, t.background_url)
  ON CONFLICT DO NOTHING
  RETURNING * INTO cyc;
  IF cyc.id IS NULL THEN SELECT * INTO cyc FROM public.global_boss_cycles WHERE status = 'active' LIMIT 1; END IF;
  RETURN cyc;
END; $function$;

REVOKE ALL ON FUNCTION public.ensure_global_boss_cycle() FROM anon, authenticated;

-- Distribution must preserve the "expired" reason instead of implying a kill.
CREATE OR REPLACE FUNCTION public.distribute_global_boss_rewards(p_cycle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE cyc public.global_boss_cycles; v_total numeric; v_min numeric; v_paid numeric := 0;
        v_count int := 0; r record; v_share numeric; v_reward numeric; v_bonus numeric; v_before numeric;
        v_pet numeric; v_bonus_list jsonb; v_reason text;
BEGIN
  SELECT * INTO cyc FROM public.global_boss_cycles WHERE id = p_cycle_id FOR UPDATE;
  IF cyc.id IS NULL THEN RAISE EXCEPTION 'BOSS_CYCLE_NOT_FOUND'; END IF;
  IF cyc.status = 'completed' THEN
    RETURN jsonb_build_object('cycleId', cyc.id, 'status', cyc.status, 'alreadyDistributed', true);
  END IF;
  IF cyc.status = 'active' THEN RAISE EXCEPTION 'BOSS_STILL_ACTIVE'; END IF;

  v_reason := COALESCE(cyc.ended_reason, CASE WHEN cyc.current_hp <= 0 THEN 'defeated' ELSE 'expired' END);
  UPDATE public.global_boss_cycles SET status = 'distributing', ended_reason = v_reason, updated_at = now() WHERE id = cyc.id;

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
           SET forge_coins = forge_coins + v_reward,
               boss_defeats = boss_defeats + CASE WHEN v_reason = 'defeated' THEN 1 ELSE 0 END,
               updated_at = now()
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
     SET status = 'completed', ended_reason = v_reason,
         total_damage = GREATEST(total_damage, v_total),
         distributed_at = now(),
         defeated_at = CASE WHEN v_reason = 'defeated' THEN COALESCE(defeated_at, now()) ELSE defeated_at END,
         updated_at = now()
   WHERE id = cyc.id;
  UPDATE public.boss_combats SET status = 'rewarded', updated_at = now()
   WHERE cycle_id = cyc.id AND status IN ('active','defeated');

  RETURN jsonb_build_object('cycleId', cyc.id, 'status', 'completed', 'endedReason', v_reason,
                            'rewarded', v_count, 'totalDamage', v_total, 'paid', v_paid);
END; $function$;

REVOKE ALL ON FUNCTION public.distribute_global_boss_rewards(uuid) FROM anon, authenticated;

-- Defeat path keeps the explicit reason so history never mislabels a kill.
CREATE OR REPLACE FUNCTION public.get_global_boss_history(p_telegram_id bigint, p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'cycleId', c.id, 'cycleNumber', c.cycle_number, 'name', c.boss_name,
      'bossNumber', c.boss_number, 'bossKey', c.boss_key, 'theme', c.boss_theme,
      'status', c.status, 'endedReason', COALESCE(c.ended_reason, CASE WHEN c.current_hp <= 0 THEN 'defeated' ELSE 'expired' END),
      'maxHp', c.max_hp, 'totalDamage', c.total_damage, 'participants', c.participants,
      'rewardPoolFc', c.reward_pool_fc, 'defeatedAt', c.defeated_at, 'completedAt', c.distributed_at,
      'topName', top.name, 'topDamage', top.damage,
      'yourDamage', COALESCE(l.damage_total, p.damage_total, 0),
      'yourRank', COALESCE(l.rank, p.final_rank),
      'yourReward', COALESCE(l.reward_fc, 0)) ORDER BY c.cycle_number DESC)
    FROM (SELECT * FROM public.global_boss_cycles WHERE status IN ('completed','defeated','expired','distributing')
           ORDER BY cycle_number DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,10),1),50)) c
    LEFT JOIN public.global_boss_reward_ledger l ON l.boss_cycle_id = c.id AND l.user_id = v_user
    LEFT JOIN public.global_boss_participants p ON p.boss_cycle_id = c.id AND p.user_id = v_user
    LEFT JOIN LATERAL (
      SELECT COALESCE(NULLIF(g.display_name,''), NULLIF(g.first_name,''), NULLIF(g.username,''), 'Player') AS name,
             gp.damage_total AS damage
        FROM public.global_boss_participants gp
        JOIN public.game_players g ON g.id = gp.user_id
       WHERE gp.boss_cycle_id = c.id AND gp.damage_total > 0
       ORDER BY gp.damage_total DESC LIMIT 1) top ON true
  ), '[]'::jsonb);
END; $function$;

REVOKE ALL ON FUNCTION public.get_global_boss_history(bigint, integer) FROM anon, authenticated;
