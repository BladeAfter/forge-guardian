CREATE OR REPLACE FUNCTION public.admin_player_detail(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; p public.game_players; v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO p FROM public.game_players WHERE id = v_uid;
  v := jsonb_build_object(
    'id', p.id,
    'telegram_id', p.telegram_id,
    'name', COALESCE(p.display_name, concat_ws(' ', p.first_name, p.last_name), 'Jogador'),
    'username', p.username,
    'avatar_url', p.avatar_url,
    'forge_coins', p.forge_coins,
    'ton_balance', p.ton_balance,
    'trophies', p.pvp_trophies,
    'league', public.pvp_league(p.pvp_trophies),
    'tickets', p.pvp_tickets,
    'wins', p.pvp_wins,
    'losses', p.pvp_losses,
    'boss_defeats', p.boss_defeats,
    'banned', p.banned,
    'ban_reason', p.ban_reason,
    'vip_until', p.vip_until,
    'premium_until', p.premium_until,
    'created_at', p.created_at,
    'last_seen_at', p.last_seen_at,
    'heroes_count', (SELECT count(*) FROM public.player_heroes WHERE user_id = p.id),
    'pets_count', (SELECT count(*) FROM public.player_pets WHERE user_id = p.id),
    'wallet', (SELECT wallet_address FROM public.pool_wallets WHERE user_id = p.id),
    'wallet_updated_at', (SELECT updated_at FROM public.pool_wallets WHERE user_id = p.id),
    'deposited_ton', (SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_deposits WHERE user_id = p.id AND status = 'credited'),
    'withdrawn_ton', (SELECT COALESCE(sum(amount_ton),0) FROM public.wallet_withdrawals WHERE user_id = p.id AND status = 'paid'),
    'heroes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',h.id,'name',h.name,'rarity',h.rarity,'level',h.level) ORDER BY h.created_at DESC), '[]'::jsonb)
               FROM public.player_heroes h WHERE h.user_id = p.id),
    'pets', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pp.id,'name',pt.name,'rarity',pp.rarity,'level',pp.level,'tier',pp.evolution_tier) ORDER BY pp.created_at DESC), '[]'::jsonb)
             FROM public.player_pets pp JOIN public.pets pt ON pt.id = pp.pet_id WHERE pp.user_id = p.id),
    'referrals', (SELECT count(*) FROM public.referrals WHERE inviter_id = p.id AND level = 1)
  );
  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_player_detail(bigint,text) FROM anon, authenticated;
