ALTER TABLE public.global_boss_cycles ADD COLUMN reward_policy jsonb;
CREATE TABLE public.global_boss_ton_claims (
 boss_cycle_id uuid NOT NULL REFERENCES public.global_boss_cycles(id), user_id uuid NOT NULL, rank integer NOT NULL,
 amount numeric(20,9) NOT NULL CHECK(amount>0), payment_status text NOT NULL DEFAULT 'pending_review' CHECK(payment_status IN ('pending_review','paid','failed')),
 transaction_hash text UNIQUE, created_at timestamptz NOT NULL DEFAULT now(), paid_at timestamptz, PRIMARY KEY(boss_cycle_id,user_id));
GRANT ALL ON public.global_boss_ton_claims TO service_role;
ALTER TABLE public.global_boss_ton_claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY boss_ton_claims_service ON public.global_boss_ton_claims TO service_role USING(true) WITH CHECK(true);
COMMENT ON TABLE public.global_boss_ton_claims IS 'TON entitlements awaiting funded, audited payment; never credits a wallet or enables financial workers.';
CREATE OR REPLACE FUNCTION public.boss_pool_share(p_pool numeric,p_count bigint,p_index bigint,p_precision integer) RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path=public AS $$
 SELECT CASE WHEN p_count>0 AND p_index BETWEEN 1 AND p_count THEN (floor(p_pool*power(10::numeric,p_precision)/p_count)+CASE WHEN p_index<=mod(floor(p_pool*power(10::numeric,p_precision)),p_count) THEN 1 ELSE 0 END)/power(10::numeric,p_precision) ELSE 0 END $$;
CREATE OR REPLACE FUNCTION public.boss_rank_reward(p_cycle uuid,p_rank bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE policy jsonb; n bigint; top_n bigint; reward numeric; currency text;
BEGIN
 SELECT reward_policy INTO policy FROM public.global_boss_cycles WHERE id=p_cycle;
 IF policy IS NULL THEN RETURN NULL; END IF;
 SELECT count(*) INTO n FROM public.global_boss_participants WHERE boss_cycle_id=p_cycle AND damage_total>0;
 top_n:=least(n,(policy->>'topPlaces')::bigint);
 currency:=CASE WHEN p_rank<=top_n THEN 'TON' ELSE 'BERRIES' END;
 reward:=CASE WHEN p_rank<=top_n THEN public.boss_pool_share((policy->>'tonPool')::numeric,top_n,p_rank,9) ELSE public.boss_pool_share((policy->>'berriesPool')::numeric,n-top_n,p_rank-top_n,0) END;
 RETURN jsonb_build_object('rewardCurrency',currency,'estimatedReward',reward,'rewardPoolTon',(policy->>'tonPool')::numeric,'rewardPoolFc',(policy->>'berriesPool')::numeric,'topPlaces',(policy->>'topPlaces')::integer);
END $$;
CREATE OR REPLACE FUNCTION public.boss_cycle_reward_policy() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NEW.reward_policy IS NULL THEN SELECT value INTO NEW.reward_policy FROM public.game_settings WHERE key='global_boss_rank_reward_policy'; END IF;
 IF NEW.reward_policy IS NOT NULL THEN
  IF NEW.reward_policy->>'split' IS DISTINCT FROM 'equal' OR (NEW.reward_policy->>'tonPool')::numeric<0 OR (NEW.reward_policy->>'berriesPool')::numeric<0 OR (NEW.reward_policy->>'topPlaces')::integer NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'BOSS_INVALID_REWARD_POLICY'; END IF;
  NEW.reward_pool_fc:=(NEW.reward_policy->>'berriesPool')::numeric; NEW.minimum_damage_percent:=0; NEW.minimum_damage_fixed:=0; NEW.minimum_reward_fc:=0; NEW.rank_bonus_enabled:=false;
 END IF; RETURN NEW;
END $$;
CREATE TRIGGER boss_cycle_reward_policy BEFORE INSERT ON public.global_boss_cycles FOR EACH ROW EXECUTE FUNCTION public.boss_cycle_reward_policy();
CREATE OR REPLACE FUNCTION public.settle_ranked_boss_pools(p_cycle_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE cyc public.global_boss_cycles; r record; quote jsonb; reward numeric; currency text; before_fc numeric; total numeric; paid_fc numeric:=0; pending_ton numeric:=0; rewarded integer:=0; reason text;
BEGIN
 SELECT * INTO cyc FROM public.global_boss_cycles WHERE id=p_cycle_id FOR UPDATE;
 IF cyc.id IS NULL THEN RAISE EXCEPTION 'BOSS_CYCLE_NOT_FOUND'; END IF;
 IF cyc.status='completed' THEN RETURN jsonb_build_object('cycleId',cyc.id,'status','completed','alreadyDistributed',true); END IF;
 IF cyc.status='active' THEN RAISE EXCEPTION 'BOSS_STILL_ACTIVE'; END IF;
 IF cyc.reward_policy IS NULL THEN RAISE EXCEPTION 'BOSS_POLICY_REQUIRED'; END IF;
 reason:=coalesce(cyc.ended_reason,CASE WHEN cyc.current_hp<=0 THEN 'defeated' ELSE 'expired' END);
 SELECT coalesce(sum(damage_total),0) INTO total FROM public.global_boss_participants WHERE boss_cycle_id=cyc.id;
 UPDATE public.global_boss_cycles SET status='distributing',ended_reason=reason,updated_at=now() WHERE id=cyc.id;
 FOR r IN SELECT p.*,row_number() OVER(ORDER BY damage_total DESC,created_at,id) AS rnk FROM public.global_boss_participants p WHERE boss_cycle_id=cyc.id AND damage_total>0 ORDER BY damage_total DESC,created_at,id LOOP
  quote:=public.boss_rank_reward(cyc.id,r.rnk); reward:=(quote->>'estimatedReward')::numeric; currency:=quote->>'rewardCurrency';
  INSERT INTO public.global_boss_reward_ledger(boss_cycle_id,user_id,damage_total,share_percent,reward_fc,rank) VALUES(cyc.id,r.user_id,r.damage_total,CASE WHEN total>0 THEN round(r.damage_total/total*100,4) ELSE 0 END,CASE WHEN currency='BERRIES' THEN reward ELSE 0 END,r.rnk) ON CONFLICT(boss_cycle_id,user_id) DO NOTHING;
  IF NOT FOUND THEN CONTINUE; END IF;
  IF currency='TON' AND reward>0 THEN
   INSERT INTO public.global_boss_ton_claims(boss_cycle_id,user_id,rank,amount) VALUES(cyc.id,r.user_id,r.rnk,reward) ON CONFLICT DO NOTHING;
   pending_ton:=pending_ton+reward;
  ELSIF currency='BERRIES' AND reward>0 THEN
   SELECT forge_coins INTO before_fc FROM public.game_players WHERE id=r.user_id FOR UPDATE;
   UPDATE public.game_players SET forge_coins=forge_coins+reward,updated_at=now() WHERE id=r.user_id;
   PERFORM public.grand_fleet_credit_bonus(r.user_id,'BERRIES',reward,'distribute_global_boss_rewards',cyc.id::text);
   INSERT INTO public.wallet_ledger(user_id,type,amount_fc,balance_before,balance_after,reference_id) VALUES(r.user_id,'global_boss_reward',reward,coalesce(before_fc,0),coalesce(before_fc,0)+reward,cyc.id::text||':'||r.user_id::text) ON CONFLICT DO NOTHING;
   paid_fc:=paid_fc+reward;
  END IF;
  UPDATE public.game_players SET boss_defeats=boss_defeats+CASE WHEN reason='defeated' THEN 1 ELSE 0 END WHERE id=r.user_id;
  UPDATE public.global_boss_participants SET reward_amount=CASE WHEN currency='BERRIES' THEN reward ELSE 0 END,final_rank=r.rnk,reward_claimed=true,updated_at=now() WHERE id=r.id;
  rewarded:=rewarded+1;
 END LOOP;
 UPDATE public.global_boss_cycles SET status='completed',ended_reason=reason,total_damage=greatest(total_damage,total),distributed_at=now(),defeated_at=CASE WHEN reason='defeated' THEN coalesce(defeated_at,now()) ELSE defeated_at END,updated_at=now() WHERE id=cyc.id;
 UPDATE public.boss_combats SET status='rewarded',updated_at=now() WHERE cycle_id=cyc.id AND status IN ('active','defeated');
 RETURN jsonb_build_object('cycleId',cyc.id,'status','completed','rewarded',rewarded,'paid',paid_fc,'pendingTon',pending_ton,'tonPaymentStatus','pending_review');
END $$;
DO $migration$
DECLARE src text;
BEGIN
 src:=pg_get_functiondef('public.distribute_global_boss_rewards(uuid)'::regprocedure);
 IF position('IF cyc.status = ''active'' THEN RAISE EXCEPTION ''BOSS_STILL_ACTIVE''; END IF;' IN src)=0 THEN RAISE EXCEPTION 'Unexpected distributor definition'; END IF;
 src:=replace(src,'IF cyc.status = ''active'' THEN RAISE EXCEPTION ''BOSS_STILL_ACTIVE''; END IF;','IF cyc.status = ''active'' THEN RAISE EXCEPTION ''BOSS_STILL_ACTIVE''; END IF; IF cyc.reward_policy IS NOT NULL THEN RETURN public.settle_ranked_boss_pools(cyc.id); END IF;'); EXECUTE src;
 src:=pg_get_functiondef('public.get_global_boss_ranking(bigint,integer)'::regprocedure);
 src:=replace(src,'ORDER BY p.damage_total DESC, p.created_at','ORDER BY p.damage_total DESC, p.created_at, p.id');
 src:=replace(src,'''estimatedReward'', CASE WHEN cyc.total_damage > 0 AND r.damage_total >= v_min','''rewardCurrency'', coalesce(public.boss_rank_reward(cyc.id,r.rnk)->>''rewardCurrency'',''BERRIES''), ''estimatedReward'', CASE WHEN cyc.reward_policy IS NOT NULL THEN (public.boss_rank_reward(cyc.id,r.rnk)->>''estimatedReward'')::numeric WHEN cyc.total_damage > 0 AND r.damage_total >= v_min');
 src:=replace(src,'''rewardPoolFc'', cyc.reward_pool_fc,','''rewardPoolFc'', cyc.reward_pool_fc, ''rewardPoolTon'', (cyc.reward_policy->>''tonPool'')::numeric, ''topPlaces'', (cyc.reward_policy->>''topPlaces'')::integer,');
 IF position('''rewardCurrency''' IN src)=0 THEN RAISE EXCEPTION 'Unexpected ranking definition'; END IF; EXECUTE src;
 src:=pg_get_functiondef('public.global_boss_overlay(uuid)'::regprocedure);
 src:=replace(src,'SELECT count(*) + 1 INTO v_rank FROM public.global_boss_participants
      WHERE boss_cycle_id = cyc.id AND damage_total > v_dmg;','SELECT rnk INTO v_rank FROM (SELECT user_id,row_number() OVER(ORDER BY damage_total DESC,created_at,id) AS rnk FROM public.global_boss_participants WHERE boss_cycle_id=cyc.id AND damage_total>0) ranked WHERE user_id=p_user;');
 src:=replace(src,'''estimatedReward'', v_est,','''estimatedReward'', CASE WHEN cyc.reward_policy IS NOT NULL THEN coalesce((public.boss_rank_reward(cyc.id,v_rank)->>''estimatedReward'')::numeric,0) ELSE v_est END, ''rewardCurrency'', coalesce(public.boss_rank_reward(cyc.id,v_rank)->>''rewardCurrency'',''BERRIES''),');
 src:=replace(src,'''rewardPoolFc'', cyc.reward_pool_fc,','''rewardPoolFc'', cyc.reward_pool_fc, ''rewardPoolTon'', (cyc.reward_policy->>''tonPool'')::numeric, ''topPlaces'', (cyc.reward_policy->>''topPlaces'')::integer,');
 src:=replace(src,'''rewardFc'', l.reward_fc,','''rewardFc'', l.reward_fc, ''rewardTon'', (SELECT amount FROM public.global_boss_ton_claims WHERE boss_cycle_id=l.boss_cycle_id AND user_id=l.user_id), ''paymentStatus'', (SELECT payment_status FROM public.global_boss_ton_claims WHERE boss_cycle_id=l.boss_cycle_id AND user_id=l.user_id),');
 IF position('''rewardCurrency''' IN src)=0 THEN RAISE EXCEPTION 'Unexpected overlay definition'; END IF; EXECUTE src;
 src:=pg_get_functiondef('public.ocean_chest_view(uuid,text)'::regprocedure);
 src:=replace(src,'jsonb_build_object(''emission'',','jsonb_build_object(''poolTon'', (SELECT (value #>> ''{}'')::numeric FROM public.game_settings WHERE key=''ocean_chest_pool_ton''),''emission'','); EXECUTE src;
END $migration$;
REVOKE ALL ON FUNCTION public.boss_pool_share(numeric,bigint,bigint,integer),public.boss_rank_reward(uuid,bigint),public.boss_cycle_reward_policy(),public.settle_ranked_boss_pools(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.boss_pool_share(numeric,bigint,bigint,integer),public.boss_rank_reward(uuid,bigint),public.boss_cycle_reward_policy(),public.settle_ranked_boss_pools(uuid) TO service_role;