CREATE TABLE IF NOT EXISTS public.pvp_ticket_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  purchase_date date NOT NULL,
  tickets integer NOT NULL CHECK (tickets > 0),
  amount_fc numeric NOT NULL CHECK (amount_fc >= 0),
  daily_count_before integer NOT NULL DEFAULT 0,
  daily_count_after integer NOT NULL DEFAULT 0,
  idempotency_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.pvp_ticket_purchases TO service_role;
ALTER TABLE public.pvp_ticket_purchases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service role manages pvp ticket purchases" ON public.pvp_ticket_purchases
  TO service_role USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS pvp_ticket_purchases_user_date_idx
  ON public.pvp_ticket_purchases(user_id, purchase_date);

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS update_pvp_ticket_purchases_updated_at ON public.pvp_ticket_purchases;
CREATE TRIGGER update_pvp_ticket_purchases_updated_at BEFORE UPDATE ON public.pvp_ticket_purchases
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Active Battle Pass (any tier) on the currently active season.
CREATE OR REPLACE FUNCTION public.has_active_season_pass(p_user_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT ps.tier FROM public.player_season_pass ps
  JOIN public.season_pass_seasons s ON s.id = ps.season_id
  WHERE ps.user_id = p_user_id AND ps.tier <> 'none' AND s.active
  ORDER BY CASE ps.tier WHEN 'legendary' THEN 2 ELSE 1 END DESC
  LIMIT 1
$$;

-- Ticket packs: {"1":5000,"3":13500,"5":20000}
CREATE OR REPLACE FUNCTION public.pvp_ticket_packs()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT value FROM public.game_settings WHERE key = 'pvp_ticket_packs'),
                  '{"1":5000,"3":13500,"5":20000}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION public.pvp_ticket_shop_state(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tier text; v_limit int; v_bought int; v_packs jsonb;
BEGIN
  v_tier := public.has_active_season_pass(p_user_id);
  v_limit := CASE WHEN v_tier IS NULL
    THEN public.setting_num('pvp_ticket_free_daily_limit', 10)
    ELSE public.setting_num('pvp_ticket_pass_daily_limit', 20) END;
  SELECT COALESCE(sum(tickets),0) INTO v_bought FROM public.pvp_ticket_purchases
    WHERE user_id = p_user_id AND purchase_date = public.quest_today();
  v_packs := public.pvp_ticket_packs();
  RETURN jsonb_build_object(
    'dailyLimit', v_limit,
    'boughtToday', v_bought,
    'remaining', GREATEST(0, v_limit - v_bought),
    'passTier', v_tier,
    'hasPass', v_tier IS NOT NULL,
    'freeLimit', public.setting_num('pvp_ticket_free_daily_limit', 10),
    'passLimit', public.setting_num('pvp_ticket_pass_daily_limit', 20),
    'packs', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tickets',(k)::int,'priceFc',(v)::numeric) ORDER BY (k)::int),'[]'::jsonb)
              FROM jsonb_each_text(v_packs) AS e(k, v))
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.buy_pvp_tickets(p_telegram_id bigint, p_quantity integer, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u public.game_players; v_price numeric; v_tier text; v_limit int; v_bought int; v_before numeric;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF COALESCE(u.banned,false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pvp_ticket_buy'||u.id::text, 0));

  IF EXISTS (SELECT 1 FROM public.pvp_ticket_purchases WHERE idempotency_key = p_idempotency_key) THEN
    RETURN public.get_pvp_dashboard(p_telegram_id);
  END IF;

  v_price := (public.pvp_ticket_packs() ->> p_quantity::text)::numeric;
  IF v_price IS NULL THEN RAISE EXCEPTION 'INVALID_PACK'; END IF;

  v_tier := public.has_active_season_pass(u.id);
  v_limit := CASE WHEN v_tier IS NULL
    THEN public.setting_num('pvp_ticket_free_daily_limit', 10)
    ELSE public.setting_num('pvp_ticket_pass_daily_limit', 20) END;
  SELECT COALESCE(sum(tickets),0) INTO v_bought FROM public.pvp_ticket_purchases
    WHERE user_id = u.id AND purchase_date = public.quest_today();

  IF v_bought + p_quantity > v_limit THEN
    RAISE EXCEPTION 'DAILY_LIMIT_%', GREATEST(0, v_limit - v_bought);
  END IF;
  IF COALESCE(u.forge_coins,0) < v_price THEN RAISE EXCEPTION 'INSUFFICIENT_FC'; END IF;

  v_before := COALESCE(u.forge_coins,0);
  UPDATE public.game_players
    SET forge_coins = forge_coins - v_price,
        pvp_tickets = COALESCE(pvp_tickets,0) + p_quantity
    WHERE id = u.id;

  INSERT INTO public.pvp_ticket_purchases (user_id, purchase_date, tickets, amount_fc, daily_count_before, daily_count_after, idempotency_key)
  VALUES (u.id, public.quest_today(), p_quantity, v_price, v_bought, v_bought + p_quantity, p_idempotency_key);

  INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (u.id, 'pvp_ticket_purchase', -v_price, v_before, v_before - v_price, p_idempotency_key);

  RETURN public.get_pvp_dashboard(p_telegram_id);
END;
$$;

-- Dashboard now carries the ticket shop state so the arena counter can render the buy sheet.
CREATE OR REPLACE FUNCTION public.get_pvp_dashboard(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare u game_players%rowtype;
begin
  select * into u from game_players where telegram_id=p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND';end if;
  return jsonb_build_object(
    'userId',u.id,'trophies',u.pvp_trophies,'league',pvp_league(u.pvp_trophies),'tickets',u.pvp_tickets,
    'wins',u.pvp_wins,'losses',u.pvp_losses,
    'ticketShop',public.pvp_ticket_shop_state(u.id),
    'attackTeam',pvp_team_json(u.id,'attack'),'defenseTeam',pvp_team_json(u.id,'defense'),
    'teamPower',pvp_team_power(u.id,'attack'),
    'ownedHeroes',(select coalesce(jsonb_agg(pvp_hero_json(h) order by h.created_at),'[]') from player_heroes h where h.user_id=u.id),
    'history',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'opponentName',coalesce(nullif(trim(coalesce(o.display_name,'')),''),nullif(o.username,''),'Jogador'),'result',case when b.winner_id=u.id then 'win' else 'loss' end,'turns',b.total_turns,'trophyChange',case when b.attacker_id=u.id then b.trophy_change else -b.trophy_change end,'rewardFc',case when b.attacker_id=u.id then b.reward_fc else 0 end,'createdAt',b.created_at) order by b.created_at desc),'[]')
      from(select * from pvp_battles where attacker_id=u.id or defender_id=u.id order by created_at desc limit 30)b
      join game_players o on o.id=case when b.attacker_id=u.id then b.defender_id else b.attacker_id end),
    'ranking',(select coalesce(jsonb_agg(x order by x.position),'[]') from(
      select row_number()over(order by pvp_trophies desc,pvp_wins desc)position,id,
        coalesce(nullif(trim(coalesce(display_name,'')),''),nullif(username,''),'Jogador')name,
        username,avatar_url "avatarUrl",pvp_trophies trophies,pvp_league(pvp_trophies)league,pvp_wins wins
      from game_players
      where not pvp_banned and not coalesce(banned,false) and telegram_id is not null and telegram_id>0
        and coalesce(nullif(trim(coalesce(display_name,'')),''),nullif(username,'')) is not null
      order by pvp_trophies desc,pvp_wins desc limit 100)x));
end
$$;

-- Admin: ticket settings in the PvP overview
CREATE OR REPLACE FUNCTION public.admin_pvp_overview(p_admin_id bigint, p_top integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.trophies DESC),'[]'::jsonb) INTO v FROM (
    SELECT id, telegram_id, COALESCE(display_name, username,'Jogador') AS name, username,
           pvp_trophies AS trophies, pvp_wins AS wins, pvp_losses AS losses, public.pvp_league(pvp_trophies) AS league, banned
    FROM public.game_players WHERE NOT pvp_banned ORDER BY pvp_trophies DESC, pvp_wins DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_top,10),100))
  ) t;
  RETURN jsonb_build_object(
    'leagues',(SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.sort_order),'[]'::jsonb) FROM public.pvp_leagues l),
    'settings', jsonb_build_object('win', public.setting_num('pvp_trophy_win',30), 'loss', public.setting_num('pvp_trophy_loss',-20),
      'ticket_start', public.setting_num('pvp_ticket_start',5),'ticket_max', public.setting_num('pvp_ticket_max',10),
      'ticket_cost', public.setting_num('pvp_ticket_cost',1),'ticket_regen_minutes', public.setting_num('pvp_ticket_regen_minutes',30),
      'ticket_price_fc', public.setting_num('pvp_ticket_price_fc',5000),
      'free_daily_limit', public.setting_num('pvp_ticket_free_daily_limit',10),
      'pass_daily_limit', public.setting_num('pvp_ticket_pass_daily_limit',20),
      'packs', public.pvp_ticket_packs()),
    'tickets_sold_today',(SELECT COALESCE(sum(tickets),0) FROM public.pvp_ticket_purchases WHERE purchase_date = public.quest_today()),
    'fc_spent_today',(SELECT COALESCE(sum(amount_fc),0) FROM public.pvp_ticket_purchases WHERE purchase_date = public.quest_today()),
    'battles_today',(SELECT count(*) FROM public.pvp_battles WHERE created_at > now() - interval '1 day'),
    'ranking', v);
END;
$$;

-- Admin: set a ticket pack price (quantity -> FC)
CREATE OR REPLACE FUNCTION public.admin_set_pvp_ticket_pack(p_admin_id bigint, p_quantity integer, p_price_fc numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 50 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;
  IF p_price_fc IS NULL OR p_price_fc < 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;
  v_old := public.pvp_ticket_packs();
  v_new := v_old || jsonb_build_object(p_quantity::text, p_price_fc);
  INSERT INTO public.game_settings(key, value, category, label, updated_at, updated_by)
  VALUES ('pvp_ticket_packs', v_new, 'pvp', 'PvP ticket packs', now(), p_admin_id)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = p_admin_id;
  PERFORM public.admin_log(p_admin_id,'pvp.ticket_pack','setting','pvp_ticket_packs',v_old,v_new,NULL);
  PERFORM public.admin_bump_settings_version();
  RETURN jsonb_build_object('packs', v_new);
END;
$$;

-- Admin: player detail shows PvP ticket purchases and pass tier
CREATE OR REPLACE FUNCTION public.admin_player_detail(p_admin_id bigint, p_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
    'tickets_bought_today', (SELECT COALESCE(sum(tickets),0) FROM public.pvp_ticket_purchases WHERE user_id = p.id AND purchase_date = public.quest_today()),
    'ticket_daily_limit', (public.pvp_ticket_shop_state(p.id) ->> 'dailyLimit')::int,
    'pass_tier', public.has_active_season_pass(p.id),
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