CREATE OR REPLACE FUNCTION public.pool_reward_autocredit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'pending' AND NEW.amount_ton > 0 THEN
    PERFORM public.credit_ton_reward(NEW.user_id, NEW.amount_ton, 'community_pool', NEW.id::text,
      'Community Pool ' || NEW.reward_type);
    UPDATE public.pool_rewards SET status = 'paid', paid_at = now() WHERE id = NEW.id;
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.pool_reward_autocredit() FROM anon, authenticated;

DROP TRIGGER IF EXISTS pool_reward_autocredit_trg ON public.pool_rewards;
CREATE TRIGGER pool_reward_autocredit_trg
AFTER INSERT ON public.pool_rewards
FOR EACH ROW EXECUTE FUNCTION public.pool_reward_autocredit();

CREATE OR REPLACE FUNCTION public.admin_spending_event_finalize(p_admin_id bigint, p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer; v_pay jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('spending_finalize:' || p_event_id::text, 77));
  INSERT INTO spending_event_results(event_id, user_id, final_rank, final_points, reward_json, reward_status)
  SELECT p_event_id, (r->>'userId')::uuid, (r->>'position')::int, (r->>'points')::numeric,
         jsonb_build_object('label', r->>'estimatedReward'), 'pending'
    FROM jsonb_array_elements(public.get_spending_event_ranking(p_event_id, 200, 0)) r
  ON CONFLICT (event_id, user_id) DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  UPDATE spending_events SET status = 'finished', updated_at = now() WHERE id = p_event_id;
  v_pay := public.spending_event_pay_rewards(p_event_id);
  PERFORM public.admin_log(p_admin_id, 'SPENDING_EVENT_FINALIZED', 'spending_event', p_event_id::text, NULL,
    jsonb_build_object('winners', v_count, 'tonPaid', v_pay), 'ranking congelado e premios TON creditados');
  RETURN jsonb_build_object('ok', true, 'winners', v_count, 'tonPaid', v_pay);
END $$;
REVOKE ALL ON FUNCTION public.admin_spending_event_finalize(bigint, uuid) FROM anon, authenticated;