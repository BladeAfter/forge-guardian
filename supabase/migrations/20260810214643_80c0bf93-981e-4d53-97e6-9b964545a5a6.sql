DROP FUNCTION IF EXISTS public.get_referral_dashboard(bigint, integer, integer, integer);

-- Base dashboard: only notifications this player has not read yet.
CREATE OR REPLACE FUNCTION public.get_referral_dashboard(p_telegram_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
declare v_user uuid;
begin
 select id into v_user from game_players where telegram_id=p_telegram_id;
 if v_user is null then raise exception 'PLAYER_NOT_FOUND';end if;
 return jsonb_build_object(
  'telegramId',p_telegram_id,
  'counts',(with recursive tree as(select r.user_id,1 lvl from referrals r where r.inviter_id=v_user union all select r.user_id,t.lvl+1 from referrals r join tree t on r.inviter_id=t.user_id where t.lvl<3) select jsonb_build_object('total',count(*),'lv1',count(*) filter(where lvl=1),'lv2',count(*) filter(where lvl=2),'lv3',count(*) filter(where lvl=3)) from tree),
  'earnings',(select jsonb_build_object('today',coalesce(sum(amount_fc) filter(where created_at>=date_trunc('day',now())),0),'yesterday',coalesce(sum(amount_fc) filter(where created_at>=date_trunc('day',now())-interval '1 day' and created_at<date_trunc('day',now())),0),'days7',coalesce(sum(amount_fc) filter(where created_at>=now()-interval '7 days'),0),'days30',coalesce(sum(amount_fc) filter(where created_at>=now()-interval '30 days'),0),'total',coalesce(sum(amount_fc),0)) from referral_commissions where user_id=v_user),
  'invites',(with recursive tree as(select r.user_id,1 lvl,r.created_at from referrals r where r.inviter_id=v_user union all select r.user_id,t.lvl+1,r.created_at from referrals r join tree t on r.inviter_id=t.user_id where t.lvl<3) select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.display_name,'Jogador'),'username',p.username,'avatar',p.avatar_url,'level',t.lvl,'joinedAt',t.created_at,'lastSeenAt',p.last_seen_at,'online',p.last_seen_at>now()-interval '5 minutes','generated',coalesce((select sum(e.amount_fc) from referral_purchase_events e where e.buyer_id=p.id and e.eligible),0),'commission',coalesce((select sum(c.amount_fc) from referral_commissions c where c.user_id=v_user and c.from_user=p.id),0)) order by t.lvl,t.created_at desc),'[]'::jsonb) from tree t join game_players p on p.id=t.user_id),
  'tree',(with recursive tree as(select r.user_id,r.inviter_id,1 lvl from referrals r where r.inviter_id=v_user union all select r.user_id,r.inviter_id,t.lvl+1 from referrals r join tree t on r.inviter_id=t.user_id where t.lvl<3) select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'parentId',t.inviter_id,'name',coalesce(p.display_name,'Jogador'),'avatar',p.avatar_url,'level',t.lvl) order by t.lvl),'[]'::jsonb) from tree t join game_players p on p.id=t.user_id),
  'ranking',(select coalesce(jsonb_agg(row_data order by position),'[]'::jsonb) from(select row_number() over(order by base.commissions desc,base.invites desc) position,base.* from(select p.id,p.display_name name,p.avatar_url avatar,(select count(*) from referrals r where r.inviter_id=p.id) invites,(select coalesce(sum(c.amount_fc),0) from referral_commissions c where c.user_id=p.id and c.created_at>=date_trunc('week',now())) commissions from game_players p) base order by base.commissions desc,base.invites desc limit 100) row_data),
  'bonuses',(select coalesce(jsonb_agg(jsonb_build_object('milestone',b.milestone,'bonusFc',b.bonus_fc,'enabled',b.enabled,'claimed',c.id is not null) order by b.milestone),'[]'::jsonb) from referral_bonus_rules b left join referral_bonus_claims c on c.milestone=b.milestone and c.user_id=v_user),
  'notifications',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'message',message,'amountFc',amount_fc,'createdAt',created_at) order by created_at desc),'[]'::jsonb) from(select * from player_notifications where user_id=v_user and read_at is null order by created_at desc limit 20)n)
 );
end $$;

REVOKE ALL ON FUNCTION public.get_referral_dashboard(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_referral_dashboard(bigint) TO service_role;

-- Admin helper: store the real Telegram chat id for an official channel.
CREATE OR REPLACE FUNCTION public.admin_set_channel_chat_ref(p_admin_id bigint, p_channel_key text, p_chat_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.channel_reward_config%rowtype;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.channel_reward_config
     SET chat_ref = nullif(trim(p_chat_ref),''), updated_at = now()
   WHERE channel_key = p_channel_key
  RETURNING * INTO c;
  IF c.channel_key IS NULL THEN RAISE EXCEPTION 'CHANNEL_NOT_AVAILABLE'; END IF;
  PERFORM public.admin_log(p_admin_id,'channel.chat_ref','channel',p_channel_key,null,jsonb_build_object('chat_ref',c.chat_ref),'captura via encaminhamento','{}'::jsonb);
  RETURN jsonb_build_object('key',c.channel_key,'title',c.title,'chatRef',c.chat_ref,'rewardFc',c.reward_fc,'enabled',c.enabled);
END; $$;

REVOKE ALL ON FUNCTION public.admin_set_channel_chat_ref(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_channel_chat_ref(bigint, text, text) TO service_role;
