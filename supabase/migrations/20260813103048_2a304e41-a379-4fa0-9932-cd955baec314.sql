CREATE OR REPLACE FUNCTION public.admin_referral_tree(p_admin_id bigint, p_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  RETURN jsonb_build_object(
    'user_id', v_uid,
    'levels', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'level', r.level,
        'user', jsonb_build_object('id',g.id,'telegram_id',g.telegram_id,'name',COALESCE(g.display_name,g.username,'Jogador'),
          'username',g.username,'avatar_url',g.avatar_url,
          'deposited_ton',(SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_deposits d WHERE d.user_id = g.id AND d.status = 'credited'))
      ) ORDER BY r.level, g.created_at), '[]'::jsonb)
      FROM public.referrals r JOIN public.game_players g ON g.id = r.user_id WHERE r.inviter_id = v_uid),
    'commissions', (SELECT COALESCE(jsonb_agg(jsonb_build_object('level',c.level,'amount_ton',COALESCE(c.amount_ton,0),
        'source_type',COALESCE(c.source_type,'purchase'),'source_amount_ton',COALESCE(c.source_amount_ton,0),
        'from',COALESCE(f.username,f.display_name),'at',c.created_at) ORDER BY c.created_at DESC),'[]'::jsonb)
      FROM (SELECT * FROM public.referral_commissions WHERE user_id = v_uid ORDER BY created_at DESC LIMIT 20) c
      JOIN public.game_players f ON f.id = c.from_user),
    'total_commission_ton', (SELECT COALESCE(sum(amount_ton),0) FROM public.referral_commissions WHERE user_id = v_uid));
END;
$function$;