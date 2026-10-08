-- 1. CHANNEL REWARDS -------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.channel_reward_config (
  channel_key text PRIMARY KEY CHECK (channel_key IN ('news','community','payments')),
  title text NOT NULL,
  subtitle text NOT NULL,
  url text NOT NULL,
  chat_ref text,
  reward_fc numeric NOT NULL DEFAULT 5000 CHECK (reward_fc >= 0),
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.channel_reward_config TO service_role;
ALTER TABLE public.channel_reward_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages channel config" ON public.channel_reward_config;
CREATE POLICY "service role manages channel config" ON public.channel_reward_config
  TO service_role USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.user_channel_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  channel_key text NOT NULL REFERENCES public.channel_reward_config(channel_key) ON DELETE CASCADE,
  joined_verified boolean NOT NULL DEFAULT false,
  reward_claimed boolean NOT NULL DEFAULT false,
  reward_amount numeric NOT NULL DEFAULT 0,
  verified_at timestamptz,
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, channel_key)
);
GRANT ALL ON public.user_channel_rewards TO service_role;
ALTER TABLE public.user_channel_rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages channel rewards" ON public.user_channel_rewards;
CREATE POLICY "service role manages channel rewards" ON public.user_channel_rewards
  TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "no direct client access to channel rewards" ON public.user_channel_rewards;
CREATE POLICY "no direct client access to channel rewards" ON public.user_channel_rewards
  FOR SELECT TO anon, authenticated USING (false);

INSERT INTO public.channel_reward_config (channel_key,title,subtitle,url,chat_ref,reward_fc,enabled,sort_order) VALUES
  ('news','NEWS CHANNEL','Stay updated with the latest news','https://t.me/+h5n08oLrHIlmOWQx',NULL,5000,true,1),
  ('community','COMMUNITY CHAT','Chat with other players','https://t.me/+sy4Y6cd7cuIyNmEx',NULL,5000,true,2),
  ('payments','PAYMENTS CHANNEL','Deposits, withdrawals and payments','https://t.me/+M_ZLb9QUod0zZjcx',NULL,5000,true,3)
ON CONFLICT (channel_key) DO UPDATE SET url = EXCLUDED.url, updated_at = now();

CREATE OR REPLACE FUNCTION public.get_channel_rewards(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM public.game_players WHERE telegram_id = p_telegram_id;
  RETURN jsonb_build_object('channels', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'key', c.channel_key, 'title', c.title, 'subtitle', c.subtitle, 'url', c.url,
      'rewardFc', c.reward_fc, 'enabled', c.enabled,
      'verifiable', c.chat_ref IS NOT NULL,
      'joined', coalesce(r.joined_verified,false),
      'claimed', coalesce(r.reward_claimed,false),
      'rewardReceived', coalesce(r.reward_amount,0),
      'claimedAt', r.claimed_at
    ) ORDER BY c.sort_order)
    FROM public.channel_reward_config c
    LEFT JOIN public.user_channel_rewards r ON r.channel_key = c.channel_key AND r.user_id = v_user
    WHERE c.enabled
  ), '[]'::jsonb));
END; $$;

-- Membership is verified by the edge function against the Telegram Bot API; this
-- function refuses to pay when the caller could not confirm it.
CREATE OR REPLACE FUNCTION public.claim_channel_reward(p_telegram_id bigint, p_channel_key text, p_membership_ok boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players%rowtype; c public.channel_reward_config%rowtype; r public.user_channel_rewards%rowtype; v_before numeric; v_after numeric;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  SELECT * INTO c FROM public.channel_reward_config WHERE channel_key = p_channel_key AND enabled;
  IF c.channel_key IS NULL THEN RAISE EXCEPTION 'CHANNEL_NOT_AVAILABLE'; END IF;
  IF coalesce(p_membership_ok,false) IS NOT TRUE THEN RAISE EXCEPTION 'MEMBERSHIP_NOT_VERIFIED'; END IF;

  INSERT INTO public.user_channel_rewards (user_id, channel_key) VALUES (u.id, c.channel_key)
    ON CONFLICT (user_id, channel_key) DO NOTHING;
  SELECT * INTO r FROM public.user_channel_rewards WHERE user_id = u.id AND channel_key = c.channel_key FOR UPDATE;

  IF r.reward_claimed THEN
    RETURN public.get_channel_rewards(p_telegram_id) || jsonb_build_object('status','already_claimed','creditedFc',0);
  END IF;

  v_before := u.forge_coins;
  v_after := v_before + c.reward_fc;
  UPDATE public.game_players SET forge_coins = v_after, updated_at = now() WHERE id = u.id;
  UPDATE public.user_channel_rewards
     SET joined_verified = true, verified_at = coalesce(verified_at, now()),
         reward_claimed = true, reward_amount = c.reward_fc, claimed_at = now(), updated_at = now()
   WHERE id = r.id;
  INSERT INTO public.wallet_ledger (user_id, type, amount_fc, balance_before, balance_after, reference_id)
  VALUES (u.id, 'channel_join_reward', c.reward_fc, v_before, v_after, u.id::text || ':' || c.channel_key)
  ON CONFLICT DO NOTHING;

  RETURN public.get_channel_rewards(p_telegram_id) || jsonb_build_object('status','claimed','creditedFc',c.reward_fc,'balance',v_after);
END; $$;

-- 2. BATTLE PASS: HALF FC + UNIVERSAL FRAGMENTS ---------------------------
ALTER TABLE public.season_pass_rewards ADD COLUMN IF NOT EXISTS base_amount numeric;
ALTER TABLE public.season_pass_rewards DROP CONSTRAINT IF EXISTS season_pass_rewards_tier_check;
ALTER TABLE public.season_pass_rewards ADD CONSTRAINT season_pass_rewards_tier_check
  CHECK (tier IN ('free','adventurer','legendary')) NOT VALID;
UPDATE public.season_pass_rewards SET base_amount = amount WHERE base_amount IS NULL;

INSERT INTO public.game_settings (key,value,category,label) VALUES
  ('battle_pass_fc_multiplier','0.5'::jsonb,'season_pass','Battle Pass FC multiplier'),
  ('universal_fragment_rates','{"common":45,"uncommon":30,"rare":15,"epic":8,"legendary":2}'::jsonb,'season_pass','Universal fragment odds'),
  ('universal_fragment_quantity','25'::jsonb,'season_pass','Universal fragment quantity')
ON CONFLICT (key) DO NOTHING;

-- FC rewards go to 50% of the previous value (future claims only, no retroactive debit).
UPDATE public.season_pass_rewards
   SET amount = greatest(1, round(base_amount * 0.5)),
       title = to_char(greatest(1, round(base_amount * 0.5)),'FM999G999G999') || ' FC',
       updated_at = now()
 WHERE reward_type = 'fc' AND tier IN ('adventurer','legendary');

-- Forge skins are removed from the pass and replaced by Universal Fragments.
UPDATE public.season_pass_rewards
   SET reward_type = 'fragments', reward_code = 'universal_fragment',
       amount = 25, base_amount = 25, title = 'UNIVERSAL FRAGMENT x25', updated_at = now()
 WHERE reward_type = 'skin' AND coalesce(reward_code,'') <> 'season-1-mythic-egg';

CREATE OR REPLACE FUNCTION public.roll_universal_fragment_rarity()
RETURNS text LANGUAGE plpgsql SET search_path TO 'public' AS $$
DECLARE v_rates jsonb;
BEGIN
  SELECT value INTO v_rates FROM public.game_settings WHERE key = 'universal_fragment_rates';
  RETURN public.roll_rarity_from_rates(coalesce(v_rates,'{"common":45,"uncommon":30,"rare":15,"epic":8,"legendary":2}'::jsonb), 0);
END; $$;

CREATE OR REPLACE FUNCTION public.claim_season_pass_reward(p_telegram_id bigint, p_reward_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare u game_players%rowtype;r season_pass_rewards%rowtype;p player_season_pass%rowtype;s season_pass_seasons%rowtype;egg uuid;key text;v_rarity text;v_qty integer;v_extra jsonb:='{}'::jsonb;
begin
  select*into u from game_players where telegram_id=p_telegram_id for update;
  select*into r from season_pass_rewards where id=p_reward_id and enabled and tier in('adventurer','legendary');
  if r.id is null then raise exception'REWARD_LOCKED';end if;
  select*into s from season_pass_seasons where id=r.season_id and active;
  select*into p from player_season_pass where user_id=u.id and season_id=s.id for update;
  if u.id is null or s.id is null or p.tier='none'or r.level>least(s.levels,floor(p.xp/s.xp_per_level)::int+1) then raise exception'REWARD_LOCKED';end if;
  if r.tier='adventurer'and p.tier not in('adventurer','legendary')or r.tier='legendary'and p.tier<>'legendary' then raise exception'PASS_NOT_OWNED';end if;
  key:='season_reward:'||u.id||':'||r.id;
  insert into season_pass_claims(user_id,reward_id,idempotency_key)values(u.id,r.id,key)on conflict do nothing;
  if not found then return get_season_pass_dashboard(p_telegram_id);end if;

  if r.reward_code = 'universal_fragment' then
    -- Rarity is always rolled server-side and stored with the item.
    v_rarity := roll_universal_fragment_rarity();
    select coalesce((value)::text::numeric,25)::int into v_qty from game_settings where key='universal_fragment_quantity';
    v_qty := greatest(1, coalesce(v_qty, r.amount::int));
    insert into player_inventory(user_id,item_type,item_code,quantity)
    values(u.id,'fragments','universal_fragment_'||v_rarity,v_qty)
    on conflict(user_id,item_type,item_code) do update set quantity=player_inventory.quantity+excluded.quantity,updated_at=now();
    v_extra := jsonb_build_object('lastReward',jsonb_build_object('type','fragments','code','universal_fragment','rarity',v_rarity,'quantity',v_qty,
      'title',upper(v_rarity)||' UNIVERSAL FRAGMENT x'||v_qty));
  elsif r.reward_type='fc' then
    update game_players set forge_coins=forge_coins+r.amount,updated_at=now()where id=u.id;
  elsif r.reward_type='pvp_ticket' then
    update game_players set pvp_tickets=pvp_tickets+r.amount::int,updated_at=now()where id=u.id;
  elsif r.reward_type='pet_egg' then
    select id into egg from pet_eggs where slug=r.reward_code;
    insert into player_pet_inventory(user_id,item_type,item_id,quantity)values(u.id,'egg',egg,r.amount::int)
    on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))do update set quantity=player_pet_inventory.quantity+excluded.quantity,updated_at=now();
  elsif r.reward_type='pet_food' then
    insert into player_pet_inventory(user_id,item_type,quantity)values(u.id,'food',r.amount::int)
    on conflict(user_id,item_type,(coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))do update set quantity=player_pet_inventory.quantity+excluded.quantity,updated_at=now();
  else
    insert into player_inventory(user_id,item_type,item_code,quantity)values(u.id,r.reward_type,coalesce(r.reward_code,r.reward_type),r.amount::int)
    on conflict(user_id,item_type,item_code)do update set quantity=player_inventory.quantity+excluded.quantity,updated_at=now();
  end if;
  return get_season_pass_dashboard(p_telegram_id) || v_extra;
end $$;

-- 3. REWARD HISTORY: per-player only, new sources, MYTHREON branding ------
CREATE OR REPLACE FUNCTION public.get_reward_history(p_telegram_id bigint, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  v_user uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_items jsonb;
  v_total bigint;
begin
  select id into v_user from public.game_players where telegram_id = p_telegram_id;
  if v_user is null then
    return jsonb_build_object('items', '[]'::jsonb, 'total', 0);
  end if;

  with feed as (
    select 'hero'::text as reward_type, ph.hero_key as reward_key, coalesce(ph.name, hc.name, 'Hero') as reward_name,
           lower(coalesce(ph.rarity,'common')) as rarity, 1::numeric as quantity,
           coalesce(ph.image, hc.image) as image_url, 'shop'::text as source, ph.created_at as created_at
    from public.player_heroes ph
    left join public.hero_catalog hc on hc.hero_key = ph.hero_key
    where ph.user_id = v_user

    union all
    select 'pet', p.slug, coalesce(p.name,'Pet'), lower(coalesce(pp.rarity,'common')), 1,
           coalesce(p.image_baby_url, p.image_young_url, p.image_adult_url), 'egg_opening',
           coalesce(pp.obtained_at, pp.created_at)
    from public.player_pets pp
    join public.pets p on p.id = pp.pet_id
    where pp.user_id = v_user

    union all
    select case pt.item_type when 'egg' then 'egg' when 'food' then 'food' when 'fragments' then 'fragment' else coalesce(pt.item_type,'item') end,
           pt.item_ref, coalesce(pt.item_name, pt.item_ref, 'Item'), null, coalesce(pt.quantity,1),
           coalesce(e.image_url, f.icon), case when pt.event ilike 'buy%' then 'shop' else 'other' end, pt.created_at
    from public.pet_transactions pt
    left join public.pet_eggs e on e.slug = pt.item_ref or e.id::text = pt.item_ref
    left join public.pet_food_items f on f.code = pt.item_ref
    where pt.user_id = v_user and coalesce(pt.quantity,1) > 0 and pt.item_type is distinct from 'pet'

    union all
    select 'fragment', 'pet_fragments', 'Pet Fragments', null, h.duplicate_fragments, null, 'egg_opening', h.created_at
    from public.pet_hatch_history h
    where h.user_id = v_user and coalesce(h.duplicate_fragments,0) > 0

    union all
    select 'fc', 'fc', 'FC', null, b.amount, null, 'boss', b.created_at
    from public.boss_reward_transactions b
    where b.user_id = v_user and coalesce(b.amount,0) > 0

    union all
    select case when coalesce(c.reward_type,'fc') = 'fc' then 'fc' else c.reward_type end,
           coalesce(c.reward_code, c.reward_type, 'reward'),
           case when coalesce(c.reward_type,'fc') = 'fc' then 'FC' else initcap(replace(coalesce(c.reward_code, c.reward_type,'Reward'),'_',' ')) end,
           null, coalesce(nullif(c.amount_fc,0), 1), null, 'calendar', coalesce(c.claimed_at, c.created_at)
    from public.daily_calendar_claims c
    where c.user_id = v_user

    union all
    select case when spr.reward_type = 'fc' then 'fc' else 'pass_reward' end,
           coalesce(spr.reward_code, spr.reward_type), coalesce(spr.title, 'Battle Pass Reward'),
           spr.tier::text, coalesce(spr.amount,1), null, 'battle_pass', spc.claimed_at
    from public.season_pass_claims spc
    join public.season_pass_rewards spr on spr.id = spc.reward_id
    where spc.user_id = v_user

    union all
    select 'fragment', pi.item_code,
           initcap(replace(replace(pi.item_code,'universal_fragment_',''),'_',' ')) || ' Universal Fragment',
           replace(pi.item_code,'universal_fragment_','') , pi.quantity, null, 'battle_pass', pi.updated_at
    from public.player_inventory pi
    where pi.user_id = v_user and pi.item_code like 'universal_fragment_%' and pi.quantity > 0

    union all
    select 'fc', 'channel_' || ucr.channel_key, initcap(ucr.channel_key) || ' Channel Reward',
           null, ucr.reward_amount, null, 'channel', ucr.claimed_at
    from public.user_channel_rewards ucr
    where ucr.user_id = v_user and ucr.reward_claimed and coalesce(ucr.reward_amount,0) > 0

    union all
    select 'fc', 'fc', 'FC', null, pb.reward_fc, null, 'pvp', coalesce(pb.completed_at, pb.created_at)
    from public.pvp_battles pb
    where pb.attacker_id = v_user and pb.winner_id = v_user and coalesce(pb.reward_fc,0) > 0
  ), valid as (
    select * from feed where created_at is not null
  )
  select
    (select count(*) from valid),
    coalesce((
      select jsonb_agg(row_to_json(t)::jsonb)
      from (select * from valid order by created_at desc limit v_limit offset v_offset) t
    ), '[]'::jsonb)
  into v_total, v_items;

  return jsonb_build_object('items', coalesce(v_items,'[]'::jsonb), 'total', coalesce(v_total,0));
end; $$;

UPDATE public.game_settings SET value = '"MYTHREON está em manutenção."'::jsonb WHERE key = 'maintenance_message';

-- 4. ADMIN CONTROLS -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_channel_rewards_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  RETURN jsonb_build_object('channels', coalesce((
    SELECT jsonb_agg(jsonb_build_object('key',c.channel_key,'title',c.title,'rewardFc',c.reward_fc,'enabled',c.enabled,
      'claims',(SELECT count(*) FROM public.user_channel_rewards r WHERE r.channel_key=c.channel_key AND r.reward_claimed),
      'paidFc',(SELECT coalesce(sum(r.reward_amount),0) FROM public.user_channel_rewards r WHERE r.channel_key=c.channel_key AND r.reward_claimed))
      ORDER BY c.sort_order) FROM public.channel_reward_config c), '[]'::jsonb));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_channel_reward(p_admin_id bigint, p_channel_key text, p_reward_fc numeric DEFAULT NULL, p_enabled boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_old jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT to_jsonb(c) INTO v_old FROM public.channel_reward_config c WHERE c.channel_key = p_channel_key;
  IF v_old IS NULL THEN RAISE EXCEPTION 'CHANNEL_NOT_FOUND'; END IF;
  UPDATE public.channel_reward_config
     SET reward_fc = coalesce(p_reward_fc, reward_fc),
         enabled = coalesce(p_enabled, enabled),
         updated_at = now()
   WHERE channel_key = p_channel_key;
  PERFORM public.admin_log(p_admin_id,'channel_reward.update','channel',p_channel_key,v_old,
    (SELECT to_jsonb(c) FROM public.channel_reward_config c WHERE c.channel_key = p_channel_key),NULL);
  RETURN public.admin_channel_rewards_overview(p_admin_id);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_pass_fc_multiplier(p_admin_id bigint, p_multiplier numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_mult numeric := greatest(0.05, least(10, coalesce(p_multiplier, 0.5)));
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  UPDATE public.season_pass_rewards
     SET amount = greatest(1, round(coalesce(base_amount, amount) * v_mult)),
         title = to_char(greatest(1, round(coalesce(base_amount, amount) * v_mult)),'FM999G999G999') || ' FC',
         updated_at = now()
   WHERE reward_type = 'fc' AND tier IN ('adventurer','legendary');
  PERFORM public.admin_set_setting(p_admin_id,'battle_pass_fc_multiplier',to_jsonb(v_mult),'battle pass fc multiplier');
  RETURN jsonb_build_object('multiplier',v_mult,'updated',(SELECT count(*) FROM public.season_pass_rewards WHERE reward_type='fc' AND tier IN ('adventurer','legendary')));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_fragment_config(p_admin_id bigint, p_rates jsonb DEFAULT NULL, p_quantity integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_total numeric;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  IF p_rates IS NOT NULL THEN
    SELECT sum((value)::text::numeric) INTO v_total FROM jsonb_each(p_rates);
    IF coalesce(v_total,0) <= 0 THEN RAISE EXCEPTION 'INVALID_RATES'; END IF;
    PERFORM public.admin_set_setting(p_admin_id,'universal_fragment_rates',p_rates,'universal fragment odds');
  END IF;
  IF p_quantity IS NOT NULL THEN
    PERFORM public.admin_set_setting(p_admin_id,'universal_fragment_quantity',to_jsonb(greatest(1,p_quantity)),'universal fragment quantity');
    UPDATE public.season_pass_rewards
       SET amount = greatest(1,p_quantity), base_amount = greatest(1,p_quantity),
           title = 'UNIVERSAL FRAGMENT x' || greatest(1,p_quantity), updated_at = now()
     WHERE reward_code = 'universal_fragment';
  END IF;
  RETURN jsonb_build_object(
    'rates',(SELECT value FROM public.game_settings WHERE key='universal_fragment_rates'),
    'quantity',(SELECT value FROM public.game_settings WHERE key='universal_fragment_quantity'));
END; $$;