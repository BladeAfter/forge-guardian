-- 1) Commission ledger records TON now (FC history preserved).
ALTER TABLE public.referral_commissions ADD COLUMN IF NOT EXISTS amount_ton numeric NOT NULL DEFAULT 0;
ALTER TABLE public.referral_commissions ADD COLUMN IF NOT EXISTS source_type text;
ALTER TABLE public.referral_commissions ADD COLUMN IF NOT EXISTS source_amount_ton numeric;
ALTER TABLE public.referral_commissions ALTER COLUMN amount_fc SET DEFAULT 0;

-- 2) One invited player = at most ONE commission-generating event, ever.
CREATE TABLE IF NOT EXISTS public.referral_first_ton_events (
  buyer_id uuid PRIMARY KEY,
  source_type text NOT NULL,
  source_id text NOT NULL,
  amount_ton numeric NOT NULL,
  commission_ton numeric NOT NULL DEFAULT 0,
  processed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.referral_first_ton_events TO service_role;
ALTER TABLE public.referral_first_ton_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages referral first ton events" ON public.referral_first_ton_events;
CREATE POLICY "service role manages referral first ton events"
  ON public.referral_first_ton_events FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.referral_first_ton_events_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_referral_first_ton_events_touch ON public.referral_first_ton_events;
CREATE TRIGGER trg_referral_first_ton_events_touch BEFORE UPDATE ON public.referral_first_ton_events
FOR EACH ROW EXECUTE FUNCTION public.referral_first_ton_events_touch();

-- 3) TON commission engine: idempotent, transactional, once per invited player.
CREATE OR REPLACE FUNCTION public.referral_pay_ton_commission(
  p_buyer_id uuid, p_source_type text, p_source_id text, p_amount_ton numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_current uuid := p_buyer_id; v_beneficiary uuid; v_lvl int; v_rate numeric;
        v_paid numeric; v_total numeric := 0; v_key text;
BEGIN
  IF p_buyer_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'NO_BUYER'); END IF;
  IF p_amount_ton IS NULL OR p_amount_ton <= 0 THEN RETURN jsonb_build_object('ok', false, 'reason', 'NO_TON'); END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('referral_first_ton:'||p_buyer_id::text, 0));

  INSERT INTO public.referral_first_ton_events(buyer_id, source_type, source_id, amount_ton)
  VALUES (p_buyer_id, lower(coalesce(nullif(btrim(p_source_type),''),'purchase')),
          coalesce(nullif(btrim(p_source_id),''),'-'), round(p_amount_ton, 9))
  ON CONFLICT (buyer_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'totalTon', 0);
  END IF;

  FOR v_lvl IN 1..3 LOOP
    SELECT inviter_id INTO v_beneficiary FROM public.referrals WHERE user_id = v_current;
    EXIT WHEN v_beneficiary IS NULL;
    SELECT percent INTO v_rate FROM public.referral_commission_settings WHERE level = v_lvl;
    v_rate := coalesce(v_rate, CASE v_lvl WHEN 1 THEN 10 WHEN 2 THEN 4 ELSE 1 END);
    v_paid := round(p_amount_ton * v_rate / 100, 9);
    v_key := 'tonref:'||p_buyer_id::text||':'||v_lvl;
    IF v_paid > 0 THEN
      INSERT INTO public.referral_commissions(user_id, from_user, level, purchase_id, amount_fc, amount_ton, source_type, source_amount_ton)
      VALUES (v_beneficiary, p_buyer_id, v_lvl, v_key, 0, v_paid,
              lower(coalesce(nullif(btrim(p_source_type),''),'purchase')), round(p_amount_ton, 9))
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.credit_ton_reward(v_beneficiary, v_paid, 'referral_commission', v_key, 'Referral Lv'||v_lvl);
        v_total := v_total + v_paid;
      END IF;
    END IF;
    v_current := v_beneficiary; v_beneficiary := NULL;
  END LOOP;

  UPDATE public.referral_first_ton_events SET commission_ton = v_total WHERE buyer_id = p_buyer_id;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'totalTon', v_total);
END $$;

REVOKE ALL ON FUNCTION public.referral_pay_ton_commission(uuid, text, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_pay_ton_commission(uuid, text, text, numeric) TO service_role;

-- 4) FC commissions are gone: the purchase event is still recorded (for "generated" stats), no FC is paid.
CREATE OR REPLACE FUNCTION public.distribute_referral_commission(
  p_buyer_id uuid, p_purchase_id text, p_event_type text, p_amount_fc numeric,
  p_eligible boolean, p_source_currency text DEFAULT 'FC', p_source_amount numeric DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE is_excluded boolean;
BEGIN
  IF p_amount_fc <= 0 OR p_amount_fc::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'INVALID_PURCHASE_AMOUNT'; END IF;
  is_excluded := lower(p_event_type) = ANY (ARRAY['referral_commission','withdrawal','admin_bonus','gift','free_reward','daily_login']);
  INSERT INTO public.referral_purchase_events(buyer_id, purchase_id, event_type, amount_fc, source_currency, source_amount, eligible)
  VALUES (p_buyer_id, p_purchase_id, lower(p_event_type), round(p_amount_fc, 3), upper(p_source_currency), p_source_amount,
          p_eligible AND NOT is_excluded)
  ON CONFLICT (purchase_id) DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('duplicate', true, 'totalPaid', 0); END IF;
  -- Commissions are paid in TON by public.referral_pay_ton_commission (first TON transaction only).
  RETURN jsonb_build_object('duplicate', false, 'totalPaid', 0, 'currency', 'TON');
END $$;

-- 5) Every real TON payment funnels through record_ton_revenue -> single commission hook.
CREATE OR REPLACE FUNCTION public.record_ton_revenue(
  p_user_id uuid, p_amount_ton numeric, p_source text, p_reference_id text, p_tx_hash text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s public.pool_settings%rowtype; pool uuid; pct numeric; amount numeric; key text;
  inserted boolean := false; referral jsonb;
BEGIN
  IF p_amount_ton IS NULL OR p_amount_ton <= 0 THEN
    RETURN jsonb_build_object('status','skipped','reason','no_ton_revenue');
  END IF;
  IF p_source IS NULL OR nullif(trim(p_source),'') IS NULL THEN RAISE EXCEPTION 'POOL_SOURCE_REQUIRED'; END IF;

  SELECT * INTO s FROM public.pool_settings WHERE id;
  pct := coalesce(s.community_pool_percent, 15);
  amount := round(p_amount_ton * pct / 100, 9);
  pool := public.ensure_active_pool();
  key := 'ton_revenue:'||p_source||':'||coalesce(nullif(p_tx_hash,''), coalesce(p_reference_id,''));

  INSERT INTO public.pool_revenue(pool_id, user_id, source_type, source_id, base_amount_ton, percent, amount_ton, idempotency_key, tx_hash)
  VALUES (pool, p_user_id, p_source, coalesce(p_reference_id,'-'), p_amount_ton, pct, amount, key, nullif(p_tx_hash,''))
  ON CONFLICT DO NOTHING;

  inserted := FOUND;

  IF inserted AND amount > 0 THEN
    UPDATE public.pool_balance SET balance_ton = balance_ton + amount, updated_at = now() WHERE id = pool;
  END IF;

  IF inserted THEN
    referral := public.referral_pay_ton_commission(p_user_id, p_source, coalesce(p_reference_id,'-'), p_amount_ton);
  END IF;

  RETURN jsonb_build_object(
    'status', CASE WHEN inserted THEN 'recorded' ELSE 'already_recorded' END,
    'poolId', pool, 'source', p_source, 'grossAmountTon', p_amount_ton,
    'poolPercent', pct, 'poolAmountTon', amount,
    'referralCommission', coalesce(referral, jsonb_build_object('ok', false, 'reason', 'SKIPPED'))
  );
END $$;

-- 6) Invites dashboard: TON totals, per-level TON, per-invite TON and first-transaction history.
CREATE OR REPLACE FUNCTION public.get_referral_dashboard_v2(
  p_telegram_id bigint, p_level integer DEFAULT NULL, p_offset integer DEFAULT 0, p_limit integer DEFAULT 20
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare v_user uuid; v_profile game_players%rowtype; v_base jsonb; v_invites jsonb;
        v_filtered_count integer; v_limit integer; v_offset integer;
begin
  if p_level is not null and p_level not between 1 and 3 then raise exception 'INVALID_LEVEL_FILTER'; end if;
  v_limit := least(20, greatest(1, coalesce(p_limit, 20))); v_offset := greatest(0, coalesce(p_offset, 0));
  select * into v_profile from game_players where telegram_id = p_telegram_id;
  if v_profile.id is null then raise exception 'PLAYER_NOT_FOUND'; end if; v_user := v_profile.id;
  v_base := public.get_referral_dashboard(p_telegram_id);
  select count(*) into v_filtered_count from jsonb_array_elements(coalesce(v_base->'invites','[]'::jsonb)) x
    where p_level is null or (x->>'level')::integer = p_level;
  select coalesce(jsonb_agg(x || jsonb_build_object(
      'generatedTon', coalesce((select fe.amount_ton from referral_first_ton_events fe where fe.buyer_id = (x->>'id')::uuid), 0),
      'commissionTon', coalesce((select sum(c.amount_ton) from referral_commissions c where c.user_id = v_user and c.from_user = (x->>'id')::uuid), 0),
      'firstTonType', (select fe.source_type from referral_first_ton_events fe where fe.buyer_id = (x->>'id')::uuid)
    )), '[]'::jsonb) into v_invites
  from (
    select value x from jsonb_array_elements(coalesce(v_base->'invites','[]'::jsonb))
    where p_level is null or (value->>'level')::integer = p_level
    order by (value->>'joinedAt')::timestamptz desc offset v_offset limit v_limit
  ) page;
  return v_base || jsonb_build_object(
    'profile', jsonb_build_object('telegramId', p_telegram_id::text, 'username', v_profile.username,
      'firstName', v_profile.display_name, 'photoUrl', v_profile.avatar_url),
    'invites', v_invites,
    'referrals', v_invites,
    'pagination', jsonb_build_object('offset', v_offset, 'limit', v_limit, 'hasMore', v_offset + v_limit < v_filtered_count),
    'commissionLevels', (select jsonb_agg(jsonb_build_object(
        'level', s.level, 'percent', s.percent,
        'invitedCount', coalesce((v_base#>>array['counts','lv'||s.level])::integer, 0),
        'totalEarnedFc', coalesce((select sum(c.amount_fc) from referral_commissions c where c.user_id = v_user and c.level = s.level), 0),
        'totalEarnedTon', coalesce((select sum(c.amount_ton) from referral_commissions c where c.user_id = v_user and c.level = s.level), 0)
      ) order by s.level) from referral_commission_settings s),
    'earningsTon', (select jsonb_build_object(
        'today', coalesce(sum(amount_ton) filter (where created_at >= date_trunc('day', now())), 0),
        'days7', coalesce(sum(amount_ton) filter (where created_at >= now() - interval '7 days'), 0),
        'days30', coalesce(sum(amount_ton) filter (where created_at >= now() - interval '30 days'), 0),
        'total', coalesce(sum(amount_ton), 0)
      ) from referral_commissions where user_id = v_user),
    'commissionHistory', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'level', c.level, 'name', coalesce(p.display_name, 'Player'), 'username', p.username,
        'avatar', p.avatar_url, 'sourceType', coalesce(c.source_type, 'purchase'),
        'sourceAmountTon', coalesce(c.source_amount_ton, 0), 'commissionTon', coalesce(c.amount_ton, 0),
        'createdAt', c.created_at) order by c.created_at desc), '[]'::jsonb)
      from (select * from referral_commissions where user_id = v_user and amount_ton > 0 order by created_at desc limit 50) c
      join game_players p on p.id = c.from_user),
    'summary', jsonb_build_object(
      'totalInvited', coalesce((v_base#>>'{counts,total}')::integer, 0),
      'totalEarnedFc', coalesce((v_base#>>'{earnings,total}')::numeric, 0),
      'earnedTodayFc', coalesce((v_base#>>'{earnings,today}')::numeric, 0),
      'earned7DaysFc', coalesce((v_base#>>'{earnings,days7}')::numeric, 0),
      'totalEarnedTon', coalesce((select sum(amount_ton) from referral_commissions where user_id = v_user), 0)
    )
  );
end $$;