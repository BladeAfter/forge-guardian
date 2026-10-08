alter table public.referral_commissions drop constraint if exists referral_commissions_amount_fc_check;
alter table public.referral_commissions drop constraint if exists referral_commissions_purchase_id_fkey;
alter table public.referral_commissions alter column amount_fc drop not null;
alter table public.referral_commissions alter column amount_fc set default null;
alter table public.referral_commissions alter column amount_ton drop default;
alter table public.referral_commissions alter column amount_ton set not null;

alter table public.referral_commissions drop constraint if exists referral_commissions_amount_ton_check;
alter table public.referral_commissions add constraint referral_commissions_amount_ton_check
  check (amount_ton > 0 or coalesce(amount_fc,0) > 0);

create unique index if not exists referral_commissions_first_ton_uniq
  on public.referral_commissions(from_user, level, source_type)
  where source_type is not null;

CREATE OR REPLACE FUNCTION public.referral_pay_ton_commission(p_buyer_id uuid, p_source_type text, p_source_id text, p_amount_ton numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_current uuid := p_buyer_id; v_beneficiary uuid; v_lvl int; v_rate numeric;
        v_paid numeric; v_total numeric := 0; v_key text; v_src text;
BEGIN
  IF p_buyer_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'NO_BUYER'); END IF;
  IF p_amount_ton IS NULL OR p_amount_ton <= 0 THEN RETURN jsonb_build_object('ok', false, 'reason', 'NO_TON'); END IF;

  v_src := lower(coalesce(nullif(btrim(p_source_type),''),'purchase'));

  PERFORM pg_advisory_xact_lock(hashtextextended('referral_first_ton:'||p_buyer_id::text, 0));

  INSERT INTO public.referral_first_ton_events(buyer_id, source_type, source_id, amount_ton)
  VALUES (p_buyer_id, v_src, coalesce(nullif(btrim(p_source_id),''),'-'), round(p_amount_ton, 9))
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
      VALUES (v_beneficiary, p_buyer_id, v_lvl, v_key, null, v_paid, v_src, round(p_amount_ton, 9))
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        PERFORM public.credit_ton_reward(v_beneficiary, v_paid, 'referral_commission', v_key, 'Referral Lv'||v_lvl);
        v_total := v_total + v_paid;
        RAISE LOG 'REFERRAL_COMMISSION referred_user_id=% referrer_user_id=% level=% transaction_id=% transaction_type=% transaction_ton=% percentage=% commission_ton=% status=paid',
          p_buyer_id, v_beneficiary, v_lvl, coalesce(nullif(btrim(p_source_id),''),'-'), v_src, round(p_amount_ton,9), v_rate, v_paid;
      END IF;
    END IF;
    v_current := v_beneficiary; v_beneficiary := NULL;
  END LOOP;

  UPDATE public.referral_first_ton_events SET commission_ton = v_total WHERE buyer_id = p_buyer_id;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'totalTon', v_total);
END $function$;