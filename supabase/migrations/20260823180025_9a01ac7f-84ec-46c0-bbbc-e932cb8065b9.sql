-- ============================================================
-- 0038 CLAN EXPLOIT RECOVERY (clan hopping / multi clan boss)
-- ============================================================

ALTER TABLE public.clan_boss_claims
  ADD COLUMN IF NOT EXISTS reversal_status text,
  ADD COLUMN IF NOT EXISTS reversed_at timestamptz;

CREATE TABLE IF NOT EXISTS public.clan_exploit_audit_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_telegram_id bigint,
  mode text NOT NULL DEFAULT 'SCAN',
  scope text NOT NULL DEFAULT 'ALL',
  stats jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.clan_exploit_audit_runs TO service_role;
ALTER TABLE public.clan_exploit_audit_runs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_exploit_participations (
  claim_id uuid PRIMARY KEY REFERENCES public.clan_boss_claims(id) ON DELETE CASCADE,
  run_id uuid REFERENCES public.clan_exploit_audit_runs(id) ON DELETE SET NULL,
  user_id uuid NOT NULL,
  clan_id uuid,
  instance_id uuid,
  boss_name text,
  cycle integer,
  window_start timestamptz,
  window_end timestamptz,
  first_attack_at timestamptz,
  legit_claim_id uuid,
  classification text NOT NULL,
  reward_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS clan_exploit_part_user_idx ON public.clan_exploit_participations(user_id, classification);
GRANT ALL ON public.clan_exploit_participations TO service_role;
ALTER TABLE public.clan_exploit_participations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.clan_exploit_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id uuid NOT NULL UNIQUE REFERENCES public.clan_boss_claims(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  clan_id uuid,
  instance_id uuid,
  admin_telegram_id bigint,
  status text NOT NULL DEFAULT 'PENDING',
  illicit jsonb NOT NULL DEFAULT '{}'::jsonb,
  recovered jsonb NOT NULL DEFAULT '{}'::jsonb,
  debt jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  executed_at timestamptz
);
CREATE INDEX IF NOT EXISTS clan_exploit_rev_user_idx ON public.clan_exploit_reversals(user_id, status);
GRANT ALL ON public.clan_exploit_reversals TO service_role;
ALTER TABLE public.clan_exploit_reversals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.exploit_recovery_debts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  asset_type text NOT NULL,
  asset_id text,
  amount numeric NOT NULL DEFAULT 0,
  source_reward_id uuid,
  reason text NOT NULL DEFAULT 'CONSUMED_ILLICIT_VALUE',
  status text NOT NULL DEFAULT 'OPEN',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS exploit_debt_unique_idx
  ON public.exploit_recovery_debts(source_reward_id, asset_type, coalesce(asset_id, ''));
CREATE INDEX IF NOT EXISTS exploit_debt_user_idx ON public.exploit_recovery_debts(user_id, status);
GRANT ALL ON public.exploit_recovery_debts TO service_role;
ALTER TABLE public.exploit_recovery_debts ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.exploit_manual_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  claim_id uuid,
  kind text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'OPEN',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS exploit_review_unique_idx
  ON public.exploit_manual_reviews(coalesce(claim_id, '00000000-0000-0000-0000-000000000000'::uuid), kind, user_id);
GRANT ALL ON public.exploit_manual_reviews TO service_role;
ALTER TABLE public.exploit_manual_reviews ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.exploit_reversal_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reversal_id uuid REFERENCES public.clan_exploit_reversals(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  asset_type text NOT NULL,
  asset_id text,
  amount numeric NOT NULL,
  balance_after numeric,
  kind text NOT NULL DEFAULT 'CLAN_BOSS_EXPLOIT_REVERSAL',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS exploit_rev_ledger_user_idx ON public.exploit_reversal_ledger(user_id, created_at DESC);
GRANT ALL ON public.exploit_reversal_ledger TO service_role;
ALTER TABLE public.exploit_reversal_ledger ENABLE ROW LEVEL SECURITY;

-- ============================ SCAN ==========================
CREATE OR REPLACE FUNCTION public.clan_exploit_scan(
  p_admin_id bigint DEFAULT NULL,
  p_user_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_run uuid; v_stats jsonb;
BEGIN
  INSERT INTO public.clan_exploit_audit_runs(admin_telegram_id, mode, scope)
  VALUES (p_admin_id, 'SCAN', CASE WHEN p_user_id IS NULL THEN 'ALL' ELSE p_user_id::text END)
  RETURNING id INTO v_run;

  WITH base AS (
    SELECT c.id AS claim_id, c.user_id, c.clan_id, c.instance_id, c.payload,
           i.boss_name, i.cycle, i.starts_at AS window_start,
           COALESCE(i.finished_at, i.ends_at) AS window_end,
           COALESCE(d.created_at, c.created_at) AS first_attack_at
      FROM public.clan_boss_claims c
      JOIN public.clan_boss_instances i ON i.id = c.instance_id
      LEFT JOIN public.clan_boss_damage d
             ON d.instance_id = c.instance_id AND d.user_id = c.user_id
     WHERE p_user_id IS NULL OR c.user_id = p_user_id
  ), classified AS (
    SELECT b.*,
      (SELECT e.claim_id FROM base e
        WHERE e.user_id = b.user_id AND e.claim_id <> b.claim_id
          AND e.clan_id IS DISTINCT FROM b.clan_id
          AND tstzrange(e.window_start, e.window_end, '[]')
              && tstzrange(b.window_start, b.window_end, '[]')
          AND (e.first_attack_at < b.first_attack_at
               OR (e.first_attack_at = b.first_attack_at AND e.claim_id < b.claim_id))
        ORDER BY e.first_attack_at ASC, e.claim_id ASC LIMIT 1) AS legit_claim_id
      FROM base b
  )
  INSERT INTO public.clan_exploit_participations (
    claim_id, run_id, user_id, clan_id, instance_id, boss_name, cycle,
    window_start, window_end, first_attack_at, legit_claim_id, classification, reward_payload)
  SELECT claim_id, v_run, user_id, clan_id, instance_id, boss_name, cycle,
         window_start, window_end, first_attack_at, legit_claim_id,
         CASE WHEN legit_claim_id IS NULL THEN 'LEGITIMATE' ELSE 'EXPLOIT_DUPLICATE_CLAN_BOSS' END,
         COALESCE(payload, '{}'::jsonb)
    FROM classified
  ON CONFLICT (claim_id) DO UPDATE SET
    run_id = EXCLUDED.run_id, legit_claim_id = EXCLUDED.legit_claim_id,
    classification = EXCLUDED.classification, reward_payload = EXCLUDED.reward_payload,
    first_attack_at = EXCLUDED.first_attack_at, window_start = EXCLUDED.window_start,
    window_end = EXCLUDED.window_end, updated_at = now();

  SELECT jsonb_build_object(
    'runId', v_run,
    'claimsScanned', count(*),
    'legitimate', count(*) FILTER (WHERE classification = 'LEGITIMATE'),
    'illicit', count(*) FILTER (WHERE classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'),
    'affectedUsers', count(DISTINCT user_id) FILTER (WHERE classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'),
    'fc', COALESCE(sum((reward_payload->>'fc')::numeric) FILTER (WHERE classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'), 0),
    'fragments', COALESCE(sum((reward_payload->>'fragments')::numeric) FILTER (WHERE classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'), 0),
    'petFood', COALESCE(sum((reward_payload->>'petFood')::numeric) FILTER (WHERE classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'), 0),
    'chests', COALESCE(sum((reward_payload->>'chests')::numeric) FILTER (WHERE classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'), 0),
    'pvpTickets', COALESCE(sum((reward_payload->>'pvpTickets')::numeric) FILTER (WHERE classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'), 0)
  ) INTO v_stats
  FROM public.clan_exploit_participations
  WHERE p_user_id IS NULL OR user_id = p_user_id;

  UPDATE public.clan_exploit_audit_runs SET stats = v_stats WHERE id = v_run;
  RETURN v_stats;
END $fn$;
REVOKE ALL ON FUNCTION public.clan_exploit_scan(bigint, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clan_exploit_scan(bigint, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.clan_exploit_scan(bigint, uuid) FROM authenticated;

-- ========================= HOLDINGS =========================
CREATE OR REPLACE FUNCTION public.clan_exploit_holdings(p_user_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT jsonb_build_object(
    'fc', COALESCE((SELECT forge_coins FROM public.game_players WHERE id = p_user_id), 0),
    'pvpTickets', COALESCE((SELECT pvp_tickets FROM public.game_players WHERE id = p_user_id), 0),
    'fragments', COALESCE((SELECT quantity FROM public.player_pet_inventory
                            WHERE user_id = p_user_id AND item_type = 'universal_fragment'
                              AND item_id IS NULL), 0),
    'petFood', COALESCE((SELECT quantity FROM public.player_pet_food
                          WHERE user_id = p_user_id AND food_code = 'pet_ration'), 0),
    'chests', COALESCE((SELECT quantity FROM public.player_inventory
                         WHERE user_id = p_user_id AND item_type = 'hero_chest'
                           AND item_code = 'rare_chest'), 0)
  )
$fn$;
REVOKE ALL ON FUNCTION public.clan_exploit_holdings(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clan_exploit_holdings(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.clan_exploit_holdings(uuid) FROM authenticated;

-- ========================== DRY RUN =========================
CREATE OR REPLACE FUNCTION public.clan_exploit_dry_run(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_hold jsonb; v_illicit jsonb; v_keep jsonb; v_items jsonb; v_reviews jsonb;
        v_asset text; v_owed numeric; v_have numeric; v_take numeric; v_since timestamptz;
        v_recobj jsonb := '{}'::jsonb; v_debtobj jsonb := '{}'::jsonb;
BEGIN
  v_hold := public.clan_exploit_holdings(p_user_id);

  SELECT min(first_attack_at) INTO v_since FROM public.clan_exploit_participations
   WHERE user_id = p_user_id AND classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS';

  SELECT jsonb_build_object(
           'fc', COALESCE(sum((p.reward_payload->>'fc')::numeric), 0),
           'fragments', COALESCE(sum((p.reward_payload->>'fragments')::numeric), 0),
           'petFood', COALESCE(sum((p.reward_payload->>'petFood')::numeric), 0),
           'chests', COALESCE(sum((p.reward_payload->>'chests')::numeric), 0),
           'pvpTickets', COALESCE(sum((p.reward_payload->>'pvpTickets')::numeric), 0)),
         COALESCE(jsonb_agg(jsonb_build_object(
           'claimId', p.claim_id, 'clan', cl.name, 'boss', p.boss_name, 'cycle', p.cycle,
           'firstAttackAt', p.first_attack_at, 'reward', p.reward_payload) ORDER BY p.first_attack_at), '[]'::jsonb)
    INTO v_illicit, v_items
    FROM public.clan_exploit_participations p
    LEFT JOIN public.clans cl ON cl.id = p.clan_id
    LEFT JOIN public.clan_exploit_reversals r ON r.claim_id = p.claim_id
   WHERE p.user_id = p_user_id AND p.classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'
     AND COALESCE(r.status, 'PENDING') NOT IN ('EXECUTED', 'PARTIAL');

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'claimId', p.claim_id, 'clan', cl.name, 'boss', p.boss_name,
           'firstAttackAt', p.first_attack_at, 'reward', p.reward_payload) ORDER BY p.first_attack_at), '[]'::jsonb)
    INTO v_keep
    FROM public.clan_exploit_participations p
    LEFT JOIN public.clans cl ON cl.id = p.clan_id
   WHERE p.user_id = p_user_id AND p.classification = 'LEGITIMATE';

  FOREACH v_asset IN ARRAY ARRAY['fc','fragments','petFood','chests','pvpTickets'] LOOP
    v_owed := floor(COALESCE((v_illicit->>v_asset)::numeric, 0));
    v_have := GREATEST(COALESCE((v_hold->>v_asset)::numeric, 0), 0);
    v_take := LEAST(v_owed, v_have);
    v_recobj := v_recobj || jsonb_build_object(v_asset, v_take);
    v_debtobj := v_debtobj || jsonb_build_object(v_asset, GREATEST(v_owed - v_take, 0));
  END LOOP;

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_reviews FROM (
    SELECT jsonb_build_object('kind', 'CHEST_OPENED_DERIVED_ASSETS', 'count', count(*)) x
      FROM public.calendar_chest_open_history h
     WHERE h.user_id = p_user_id AND v_since IS NOT NULL AND h.created_at >= v_since
    HAVING count(*) > 0
    UNION ALL
    SELECT jsonb_build_object('kind', 'FRAGMENTS_CONSUMED_IN_SUMMON', 'count', count(*),
                              'fragmentsSpent', COALESCE(sum(f.fragments_spent), 0))
      FROM public.fragment_summon_history f
     WHERE f.user_id = p_user_id AND v_since IS NOT NULL AND f.created_at >= v_since
    HAVING count(*) > 0
    UNION ALL
    SELECT jsonb_build_object('kind', 'SOLD_TO_INNOCENT_BUYER_ILLICIT_PROCEEDS', 'count', count(*),
                              'proceedsFc', COALESCE(sum(t.seller_received_fc), 0),
                              'proceedsTon', COALESCE(sum(t.seller_received_ton), 0))
      FROM public.market_transactions t
     WHERE t.seller_user_id = p_user_id AND v_since IS NOT NULL AND t.created_at >= v_since
    HAVING count(*) > 0
  ) s;

  RETURN jsonb_build_object(
    'userId', p_user_id,
    'player', (SELECT jsonb_build_object('name', g.first_name, 'username', g.username,
                        'telegramId', g.telegram_id,
                        'clanId', (SELECT clan_id FROM public.clan_members WHERE user_id = p_user_id))
                 FROM public.game_players g WHERE g.id = p_user_id),
    'holdings', v_hold,
    'keep', v_keep,
    'illicitParticipations', v_items,
    'illicitTotals', COALESCE(v_illicit, '{}'::jsonb),
    'recoverable', v_recobj,
    'recoveryDebt', v_debtobj,
    'manualReview', v_reviews,
    'alreadyReversed', (SELECT count(*) FROM public.clan_exploit_reversals
                         WHERE user_id = p_user_id AND status IN ('EXECUTED','PARTIAL')),
    'dryRun', true);
END $fn$;
REVOKE ALL ON FUNCTION public.clan_exploit_dry_run(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clan_exploit_dry_run(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.clan_exploit_dry_run(uuid) FROM authenticated;

-- ========================== EXECUTE =========================
CREATE OR REPLACE FUNCTION public.clan_exploit_execute(p_admin_id bigint, p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r record; v_asset text; v_owed numeric; v_have numeric; v_take numeric;
        v_hold jsonb; v_rec jsonb; v_debt jsonb; v_status text; v_rev uuid;
        v_claims integer := 0; v_tot_rec jsonb; v_tot_debt jsonb; v_reviews integer := 0;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text, 42));
  PERFORM 1 FROM public.game_players WHERE id = p_user_id FOR UPDATE;

  FOR r IN
    SELECT p.* FROM public.clan_exploit_participations p
     LEFT JOIN public.clan_exploit_reversals x ON x.claim_id = p.claim_id
     WHERE p.user_id = p_user_id
       AND p.classification = 'EXPLOIT_DUPLICATE_CLAN_BOSS'
       AND COALESCE(x.status, 'PENDING') NOT IN ('EXECUTED','PARTIAL')
     ORDER BY p.first_attack_at
  LOOP
    v_rec := '{}'::jsonb; v_debt := '{}'::jsonb; v_status := 'EXECUTED';

    FOREACH v_asset IN ARRAY ARRAY['fc','fragments','petFood','chests','pvpTickets'] LOOP
      v_owed := floor(COALESCE((r.reward_payload->>v_asset)::numeric, 0));
      IF v_owed > 0 THEN
        v_hold := public.clan_exploit_holdings(p_user_id);
        v_have := GREATEST(COALESCE((v_hold->>v_asset)::numeric, 0), 0);
        v_take := LEAST(v_owed, v_have);

        IF v_take > 0 THEN
          IF v_asset = 'fc' THEN
            UPDATE public.game_players SET forge_coins = forge_coins - v_take, updated_at = now()
             WHERE id = p_user_id;
          ELSIF v_asset = 'pvpTickets' THEN
            UPDATE public.game_players SET pvp_tickets = pvp_tickets - v_take::int, updated_at = now()
             WHERE id = p_user_id;
          ELSIF v_asset = 'fragments' THEN
            UPDATE public.player_pet_inventory SET quantity = quantity - v_take::int, updated_at = now()
             WHERE user_id = p_user_id AND item_type = 'universal_fragment' AND item_id IS NULL;
          ELSIF v_asset = 'petFood' THEN
            UPDATE public.player_pet_food SET quantity = quantity - v_take::int, updated_at = now()
             WHERE user_id = p_user_id AND food_code = 'pet_ration';
          ELSE
            UPDATE public.player_inventory SET quantity = quantity - v_take::int, updated_at = now()
             WHERE user_id = p_user_id AND item_type = 'hero_chest' AND item_code = 'rare_chest';
          END IF;
          v_rec := v_rec || jsonb_build_object(v_asset, v_take);
        END IF;

        IF v_owed - v_take > 0 THEN
          v_status := 'PARTIAL';
          v_debt := v_debt || jsonb_build_object(v_asset, v_owed - v_take);
          INSERT INTO public.exploit_recovery_debts(user_id, asset_type, asset_id, amount, source_reward_id, reason)
          VALUES (p_user_id, v_asset, NULL, v_owed - v_take, r.claim_id, 'CONSUMED_ILLICIT_VALUE')
          ON CONFLICT (source_reward_id, asset_type, coalesce(asset_id, '')) DO UPDATE
            SET amount = EXCLUDED.amount, updated_at = now();
        END IF;
      END IF;
    END LOOP;

    INSERT INTO public.clan_exploit_reversals(
      claim_id, user_id, clan_id, instance_id, admin_telegram_id, status, illicit, recovered, debt, notes, executed_at)
    VALUES (r.claim_id, p_user_id, r.clan_id, r.instance_id, p_admin_id, v_status,
            r.reward_payload, v_rec, v_debt,
            jsonb_build_object('legitClaimId', r.legit_claim_id, 'boss', r.boss_name, 'cycle', r.cycle), now())
    ON CONFLICT (claim_id) DO UPDATE SET
      status = EXCLUDED.status, recovered = EXCLUDED.recovered, debt = EXCLUDED.debt,
      admin_telegram_id = EXCLUDED.admin_telegram_id, executed_at = now()
    RETURNING id INTO v_rev;

    INSERT INTO public.exploit_reversal_ledger(reversal_id, user_id, asset_type, amount, kind)
    SELECT v_rev, p_user_id, k.key, -(k.value::numeric),
           CASE WHEN k.key = 'fc' THEN 'CLAN_BOSS_EXPLOIT_REVERSAL_FC'
                ELSE 'CLAN_BOSS_EXPLOIT_REVERSAL_' || upper(k.key) END
      FROM jsonb_each_text(v_rec) k;

    UPDATE public.clan_boss_claims
       SET reversal_status = 'REVERSED_FOR_EXPLOIT', reversed_at = now()
     WHERE id = r.claim_id;

    v_claims := v_claims + 1;
  END LOOP;

  INSERT INTO public.exploit_manual_reviews(user_id, claim_id, kind, details)
  SELECT p_user_id, NULL, (x->>'kind'), x
    FROM jsonb_array_elements((public.clan_exploit_dry_run(p_user_id))->'manualReview') x
  ON CONFLICT (coalesce(claim_id, '00000000-0000-0000-0000-000000000000'::uuid), kind, user_id) DO NOTHING;

  SELECT count(*) INTO v_reviews FROM public.exploit_manual_reviews
   WHERE user_id = p_user_id AND status = 'OPEN';

  SELECT jsonb_object_agg(asset, total) INTO v_tot_rec FROM (
    SELECT k.key asset, sum(k.value::numeric) total
      FROM public.clan_exploit_reversals rr, jsonb_each_text(rr.recovered) k
     WHERE rr.user_id = p_user_id GROUP BY 1) a;
  SELECT jsonb_object_agg(asset_type, total) INTO v_tot_debt FROM (
    SELECT asset_type, sum(amount) total FROM public.exploit_recovery_debts
     WHERE user_id = p_user_id AND status = 'OPEN' GROUP BY 1) b;

  INSERT INTO public.clan_exploit_audit_runs(admin_telegram_id, mode, scope, stats)
  VALUES (p_admin_id, 'EXECUTE', p_user_id::text,
          jsonb_build_object('claimsReversed', v_claims, 'recovered', COALESCE(v_tot_rec,'{}'::jsonb),
                             'debt', COALESCE(v_tot_debt,'{}'::jsonb)));

  RETURN jsonb_build_object('userId', p_user_id, 'claimsReversed', v_claims,
    'recovered', COALESCE(v_tot_rec, '{}'::jsonb), 'debt', COALESCE(v_tot_debt, '{}'::jsonb),
    'manualReviews', v_reviews);
END $fn$;
REVOKE ALL ON FUNCTION public.clan_exploit_execute(bigint, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clan_exploit_execute(bigint, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.clan_exploit_execute(bigint, uuid) FROM authenticated;
