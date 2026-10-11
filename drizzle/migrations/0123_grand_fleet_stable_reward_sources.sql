DO $$DECLARE f record; d text; old_source text; new_source text; BEGIN
FOR f IN SELECT oid,proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND prokind='f' AND proname IN('realm_expedition_claim','realm_bounty_claim','realm_explore_finish','realm_ruin_finish','claim_daily_quest','clan_war_settle','distribute_global_boss_rewards') LOOP
 d:=pg_get_functiondef(f.oid);
 old_source:='txid_current()::text||'':''||'''||f.proname||'''||'':''||'||CASE WHEN f.proname='claim_daily_quest' THEN 'u' WHEN f.proname IN('clan_war_settle','distribute_global_boss_rewards') THEN 'r.user_id' ELSE 'p_user' END||'::text';
 new_source:=CASE WHEN f.proname IN('realm_expedition_claim','realm_bounty_claim') THEN 'p_id::text' WHEN f.proname IN('realm_explore_finish','realm_ruin_finish') THEN 'p_run::text' WHEN f.proname='claim_daily_quest' THEN 'p.id::text' WHEN f.proname='clan_war_settle' THEN 'w.id::text' ELSE 'cyc.id::text' END;
 IF strpos(d,old_source)=0 THEN RAISE EXCEPTION 'Missing source: %',f.proname; END IF;
 EXECUTE replace(d,old_source,new_source);
END LOOP;
-- The delivery helper can be used by other sources. Attach the bonus only to an eligible boss-cycle settlement.
SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='clan_boss_deliver';
EXECUTE regexp_replace(d,' PERFORM public.grand_fleet_credit_bonus\([^;]+;','','i');
SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='clan_boss_settle';
IF strpos(d,'PERFORM public.clan_boss_deliver(r.user_id, v_reward);')=0 THEN RAISE EXCEPTION 'Missing boss settlement hook'; END IF;
EXECUTE replace(d,'PERFORM public.clan_boss_deliver(r.user_id, v_reward);','PERFORM public.clan_boss_deliver(r.user_id, v_reward); PERFORM public.grand_fleet_credit_bonus(r.user_id,''BERRIES'',COALESCE((v_reward->>''fc'')::numeric,0),''clan_boss_settle'',b.id::text);');
SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='claim_calendar_day';
IF strpos(d,'update game_players set forge_coins=forge_coins+r.amount_fc, updated_at=now() where id=u.id;')=0 THEN RAISE EXCEPTION 'Missing calendar hook'; END IF;
EXECUTE replace(d,'update game_players set forge_coins=forge_coins+r.amount_fc, updated_at=now() where id=u.id;','update game_players set forge_coins=forge_coins+r.amount_fc, updated_at=now() where id=u.id; PERFORM public.grand_fleet_credit_bonus(u.id,''BERRIES'',r.amount_fc,''claim_calendar_day'',key);');
SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='grand_fleet_credit_bonus';
EXECUTE replace(d,'IF p_amount IS NULL OR p_amount<=0 OR p_source IS NULL OR p_type NOT IN(''realm_expedition_claim'',''realm_bounty_claim'',''realm_explore_finish'',''realm_ruin_finish'',''claim_daily_quest'',''clan_boss_deliver'',''clan_war_settle'',''distribute_global_boss_rewards'',''expedition'',''explore_extract'',''explore_finish'',''explore_complete'',''explore_victory'',''ruin_room'',''ruin_clear'',''ruin_extract'') THEN RETURN; END IF;',
'IF p_amount IS NULL OR p_amount<=0 OR p_source IS NULL OR btrim(p_source)='''' OR p_type IS NULL OR p_asset IS NULL THEN RETURN; END IF;
IF p_asset=''BERRIES'' THEN
 IF p_type NOT IN(''realm_expedition_claim'',''realm_bounty_claim'',''realm_explore_finish'',''realm_ruin_finish'',''claim_daily_quest'',''clan_boss_settle'',''clan_war_settle'',''distribute_global_boss_rewards'',''claim_calendar_day'') THEN RETURN; END IF;
ELSE
 IF p_type NOT IN(''expedition'',''explore_extracted'',''explore_cleared'',''ruin_room'',''ruin_clear'',''ruin_extract'') THEN RETURN; END IF;
END IF;');
END$$;
ALTER TABLE public.grand_fleet_bonus_ledger ADD CONSTRAINT grand_fleet_positive_bonus CHECK(reward_amount>0 AND bonus_amount=reward_amount*0.05), ADD CONSTRAINT grand_fleet_distinct_captain CHECK(member_id<>leader_id);
CREATE INDEX grand_fleet_bonus_dashboard_idx ON public.grand_fleet_bonus_ledger(clan_id,leader_id,asset);
COMMENT ON TABLE public.grand_fleet_bonus_ledger IS 'Private additive 5% gameplay-only captain rewards, deduplicated by permanent settlement source. Excludes paid pass rewards, payments, gifts, transfers, PvP loot and recursive bonuses.';