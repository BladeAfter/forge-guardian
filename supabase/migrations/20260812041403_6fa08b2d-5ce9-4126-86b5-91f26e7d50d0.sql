-- ===========================================================
-- MYTHREON — Player Market security layer
-- ===========================================================

-- 1. Player-level market state -------------------------------------------------
ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS market_pending_fc numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS market_trust text NOT NULL DEFAULT 'new',
  ADD COLUMN IF NOT EXISTS market_restricted_until timestamptz,
  ADD COLUMN IF NOT EXISTS market_cooldown_until timestamptz;

-- 2. Transaction lifecycle -----------------------------------------------------
ALTER TABLE public.market_transactions
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS settle_at timestamptz,
  ADD COLUMN IF NOT EXISTS settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS reversed_at timestamptz,
  ADD COLUMN IF NOT EXISTS risk_score integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS risk_flags text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS admin_id bigint,
  ADD COLUMN IF NOT EXISTS admin_notes text,
  ADD COLUMN IF NOT EXISTS spending_recorded boolean NOT NULL DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'market_transactions_status_check') THEN
    ALTER TABLE public.market_transactions
      ADD CONSTRAINT market_transactions_status_check
      CHECK (status = ANY (ARRAY['pending','review','settled','reversed']));
  END IF;
END $$;

UPDATE public.market_transactions
   SET status = 'settled', settled_at = coalesce(settled_at, created_at),
       settle_at = coalesce(settle_at, created_at), spending_recorded = true
 WHERE status = 'pending' AND created_at < now() - interval '1 minute';

CREATE INDEX IF NOT EXISTS market_transactions_status_idx ON public.market_transactions(status, settle_at);
CREATE INDEX IF NOT EXISTS market_transactions_pair_idx ON public.market_transactions(buyer_user_id, seller_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS market_transactions_seller_idx ON public.market_transactions(seller_user_id, created_at DESC);

ALTER TABLE public.market_listings
  ADD COLUMN IF NOT EXISTS risk_level text NOT NULL DEFAULT 'low';

-- 3. Configurable price ranges -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.market_price_ranges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_type text NOT NULL CHECK (item_type = ANY (ARRAY['hero','pet','item'])),
  rarity text NOT NULL,
  min_fc numeric NOT NULL CHECK (min_fc >= 0),
  max_fc numeric NOT NULL CHECK (max_fc > 0),
  recommended_fc numeric,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (item_type, rarity)
);
GRANT ALL ON public.market_price_ranges TO service_role;
ALTER TABLE public.market_price_ranges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages market_price_ranges" ON public.market_price_ranges;
CREATE POLICY "service role manages market_price_ranges" ON public.market_price_ranges
  TO service_role USING (true) WITH CHECK (true);
DROP TRIGGER IF EXISTS market_price_ranges_touch ON public.market_price_ranges;
CREATE TRIGGER market_price_ranges_touch BEFORE UPDATE ON public.market_price_ranges
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.market_price_ranges(item_type, rarity, min_fc, max_fc, recommended_fc) VALUES
  ('hero','common',10000,150000,40000),
  ('hero','uncommon',25000,300000,90000),
  ('hero','rare',50000,750000,220000),
  ('hero','epic',150000,2000000,600000),
  ('hero','legendary',500000,5000000,1500000),
  ('hero','mythic',1000000,10000000,3000000),
  ('hero','default',10000,750000,120000),
  ('pet','common',10000,150000,40000),
  ('pet','uncommon',25000,300000,90000),
  ('pet','rare',50000,750000,220000),
  ('pet','epic',150000,2000000,600000),
  ('pet','legendary',500000,5000000,1500000),
  ('pet','mythic',1000000,10000000,3000000),
  ('pet','default',10000,750000,120000),
  ('item','default',5000,250000,25000)
ON CONFLICT (item_type, rarity) DO NOTHING;

-- 4. Relationship / audit tables ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.market_pair_stats (
  buyer_user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  seller_user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  trades integer NOT NULL DEFAULT 0,
  total_fc numeric NOT NULL DEFAULT 0,
  first_trade_at timestamptz NOT NULL DEFAULT now(),
  last_trade_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (buyer_user_id, seller_user_id)
);
GRANT ALL ON public.market_pair_stats TO service_role;
ALTER TABLE public.market_pair_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages market_pair_stats" ON public.market_pair_stats;
CREATE POLICY "service role manages market_pair_stats" ON public.market_pair_stats
  TO service_role USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.market_item_ownership_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_type text NOT NULL,
  item_instance_id uuid,
  item_code text,
  from_user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  to_user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  listing_id uuid,
  transaction_id uuid,
  price_fc numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.market_item_ownership_history TO service_role;
ALTER TABLE public.market_item_ownership_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages market_ownership" ON public.market_item_ownership_history;
CREATE POLICY "service role manages market_ownership" ON public.market_item_ownership_history
  TO service_role USING (true) WITH CHECK (true);
CREATE INDEX IF NOT EXISTS market_ownership_instance_idx ON public.market_item_ownership_history(item_instance_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.market_security_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event text NOT NULL,
  listing_id uuid,
  transaction_id uuid,
  buyer_user_id uuid,
  seller_user_id uuid,
  admin_id bigint,
  price_fc numeric NOT NULL DEFAULT 0,
  fee_fc numeric NOT NULL DEFAULT 0,
  risk_score integer NOT NULL DEFAULT 0,
  risk_flags text[] NOT NULL DEFAULT '{}',
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.market_security_audit TO service_role;
ALTER TABLE public.market_security_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service role manages market_security_audit" ON public.market_security_audit;
CREATE POLICY "service role manages market_security_audit" ON public.market_security_audit
  TO service_role USING (true) WITH CHECK (true);
CREATE INDEX IF NOT EXISTS market_security_audit_idx ON public.market_security_audit(created_at DESC);

-- 5. Settings ------------------------------------------------------------------
INSERT INTO public.game_settings(key, value, category, label) VALUES
  ('market_settlement_hours', to_jsonb(72), 'marketplace', 'Retenção do FC de venda (horas)'),
  ('market_sell_requirements', '{"accountDays":7,"activeDays":3,"heroes":5}'::jsonb, 'marketplace', 'Requisitos para vender'),
  ('market_pair_limits', '{"tradesPerDay":3,"fcPerDay":2000000}'::jsonb, 'marketplace', 'Limites entre o mesmo par'),
  ('market_new_account_limits', '{"days":7,"buyFcPerDay":500000,"sellFcPerDay":250000}'::jsonb, 'marketplace', 'Limites de conta nova'),
  ('market_velocity', '{"per5m":5,"per1h":15,"per24h":40,"cooldownMinutes":360}'::jsonb, 'marketplace', 'Velocity check'),
  ('market_dynamic_range', '{"minPercent":50,"maxPercent":200,"minSamples":5,"days":30}'::jsonb, 'marketplace', 'Faixa dinâmica pela mediana')
ON CONFLICT (key) DO NOTHING;

-- 6. Settings JSON -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_settings_json()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'feePercent', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_fee_percent'), 5),
    'maxActiveListings', coalesce((select (value #>> '{}')::integer from game_settings where key = 'market_max_active_listings'), 10),
    'maxPriceFc', coalesce((select (value #>> '{}')::numeric from game_settings where key = 'market_max_price_fc'), 50000000),
    'minPrice', coalesce((select value from game_settings where key = 'market_min_price'), '{"hero":10000,"pet":10000,"item":5000}'::jsonb),
    'settlementHours', coalesce((select (value #>> '{}')::integer from game_settings where key = 'market_settlement_hours'), 72),
    'sellRequirements', coalesce((select value from game_settings where key = 'market_sell_requirements'), '{"accountDays":7,"activeDays":3,"heroes":5}'::jsonb),
    'pairLimits', coalesce((select value from game_settings where key = 'market_pair_limits'), '{"tradesPerDay":3,"fcPerDay":2000000}'::jsonb),
    'newAccountLimits', coalesce((select value from game_settings where key = 'market_new_account_limits'), '{"days":7,"buyFcPerDay":500000,"sellFcPerDay":250000}'::jsonb),
    'velocity', coalesce((select value from game_settings where key = 'market_velocity'), '{"per5m":5,"per1h":15,"per24h":40,"cooldownMinutes":360}'::jsonb),
    'dynamicRange', coalesce((select value from game_settings where key = 'market_dynamic_range'), '{"minPercent":50,"maxPercent":200,"minSamples":5,"days":30}'::jsonb)
  );
$function$;

-- 7. Wallet fingerprint --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_user_wallets(p_user uuid)
 RETURNS TABLE(address text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select distinct lower(s.a) from (
    select w.wallet_address as a from pool_wallets w where w.user_id = p_user
    union all
    select d.from_wallet from wallet_deposits d where d.user_id = p_user
    union all
    select x.wallet_address from wallet_withdrawals x where x.user_id = p_user
  ) s where nullif(trim(s.a),'') is not null;
$function$;

CREATE OR REPLACE FUNCTION public.market_shares_wallet(p_a uuid, p_b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from market_user_wallets(p_a) a
    join market_user_wallets(p_b) b on b.address = a.address
  );
$function$;

-- 8. Account maturity ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_account_days(p_user uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(floor(extract(epoch from (now() - g.created_at)) / 86400)::integer, 0)
  from game_players g where g.id = p_user;
$function$;

CREATE OR REPLACE FUNCTION public.market_active_days(p_user uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::integer from (
    select date_trunc('day', l.created_at) d from wallet_ledger l where l.user_id = p_user
    union
    select date_trunc('day', h.created_at) from player_heroes h where h.user_id = p_user
    union
    select date_trunc('day', g.created_at) from game_players g where g.id = p_user
    union
    select date_trunc('day', g.last_seen_at) from game_players g where g.id = p_user and g.last_seen_at is not null
  ) s;
$function$;

CREATE OR REPLACE FUNCTION public.market_sell_eligibility(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare req jsonb; v_days integer; v_active integer; v_heroes integer; reasons text[] := '{}'; g game_players%rowtype;
begin
  select * into g from game_players where id = p_user;
  if g.id is null then return jsonb_build_object('canSell', false, 'reasons', to_jsonb(array['PLAYER_NOT_FOUND'])); end if;
  req := (market_settings_json()->'sellRequirements');
  v_days := market_account_days(p_user);
  v_active := market_active_days(p_user);
  select count(*) into v_heroes from player_heroes where user_id = p_user;

  if v_days < coalesce((req->>'accountDays')::integer, 7) then reasons := reasons || 'ACCOUNT_TOO_NEW'; end if;
  if v_active < coalesce((req->>'activeDays')::integer, 3) then reasons := reasons || 'NOT_ENOUGH_ACTIVE_DAYS'; end if;
  if v_heroes < coalesce((req->>'heroes')::integer, 5) then reasons := reasons || 'NOT_ENOUGH_HEROES'; end if;
  if coalesce(g.banned, false) then reasons := reasons || 'BANNED'; end if;
  if g.market_restricted_until is not null and g.market_restricted_until > now() then reasons := reasons || 'RESTRICTED'; end if;

  return jsonb_build_object(
    'canSell', array_length(reasons, 1) is null,
    'reasons', to_jsonb(reasons),
    'accountDays', v_days, 'activeDays', v_active, 'heroes', v_heroes,
    'required', req);
end $function$;

-- 9. Price ranges --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_price_range(p_item_type text, p_rarity text, p_level integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  kind text := lower(coalesce(p_item_type,'item'));
  rar text := lower(coalesce(nullif(p_rarity,''),'default'));
  r market_price_ranges%rowtype; dyn jsonb; med numeric; samples integer;
  v_min numeric; v_max numeric; v_rec numeric; v_source text := 'config';
  hard_max numeric := coalesce((market_settings_json()->>'maxPriceFc')::numeric, 50000000);
begin
  select * into r from market_price_ranges where item_type = kind and rarity = rar;
  if r.id is null then select * into r from market_price_ranges where item_type = kind and rarity = 'default'; end if;
  if r.id is null then
    v_min := coalesce((market_settings_json()->'minPrice'->>kind)::numeric, 5000);
    v_max := hard_max;
    v_rec := v_min * 4;
  else
    v_min := r.min_fc; v_max := r.max_fc; v_rec := coalesce(r.recommended_fc, round((r.min_fc + r.max_fc) / 4));
  end if;

  if coalesce(p_level,1) > 1 then
    v_max := round(v_max * least(1 + (least(p_level, 100) - 1) * 0.01, 1.5));
  end if;

  dyn := market_settings_json()->'dynamicRange';
  select count(*), percentile_cont(0.5) within group (order by t.price_fc)
    into samples, med
    from market_transactions t
   where t.status = 'settled'
     and t.item_type = kind
     and lower(coalesce(t.snapshot->>'rarity','default')) = rar
     and t.created_at > now() - make_interval(days => coalesce((dyn->>'days')::integer, 30));

  if med is not null and samples >= coalesce((dyn->>'minSamples')::integer, 5) then
    v_source := 'median';
    v_min := greatest(v_min, round(med * coalesce((dyn->>'minPercent')::numeric, 50) / 100));
    v_max := least(v_max, round(med * coalesce((dyn->>'maxPercent')::numeric, 200) / 100));
    v_rec := round(med);
  end if;

  v_max := least(v_max, hard_max);
  if v_max < v_min then v_max := v_min; end if;
  v_rec := least(greatest(coalesce(v_rec, v_min), v_min), v_max);

  return jsonb_build_object('min', round(v_min), 'max', round(v_max), 'recommended', round(v_rec),
    'median', case when med is null then null else round(med) end, 'samples', coalesce(samples,0),
    'source', v_source, 'itemType', kind, 'rarity', rar);
end $function$;

-- 10. Risk assessment ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_risk_assess(p_buyer uuid, p_seller uuid, p_listing market_listings)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  flags text[] := '{}'; score integer := 0; range jsonb; pair_trades integer; pair_fc numeric;
  buyer_days integer; seller_days integer; buyer_trades integer; vel jsonb; v5 integer; v1h integer;
begin
  range := market_price_range(p_listing.item_type, p_listing.snapshot->>'rarity',
            coalesce((p_listing.snapshot->>'level')::integer, 1));
  buyer_days := market_account_days(p_buyer);
  seller_days := market_account_days(p_seller);

  if buyer_days < 7 or seller_days < 7 then flags := flags || 'NEW_ACCOUNT'; score := score + 20; end if;
  if market_shares_wallet(p_buyer, p_seller) then flags := flags || 'SAME_WALLET'; score := score + 60; end if;
  if exists (select 1 from referrals r where (r.user_id = p_buyer and r.inviter_id = p_seller)
                                          or (r.user_id = p_seller and r.inviter_id = p_buyer)) then
    flags := flags || 'REFERRAL_PAIR'; score := score + 15;
  end if;
  if p_listing.price_fc >= (range->>'max')::numeric * 0.9 then flags := flags || 'HIGH_PRICE'; score := score + 15; end if;
  if (range->>'median') is not null and p_listing.price_fc > (range->>'median')::numeric * 1.5 then
    flags := flags || 'PRICE_OUTLIER'; score := score + 20;
  end if;

  select count(*), coalesce(sum(price_fc),0) into pair_trades, pair_fc
    from market_transactions
   where buyer_user_id = p_buyer and seller_user_id = p_seller
     and status <> 'reversed' and created_at > now() - interval '24 hours';
  if pair_trades >= 2 then flags := flags || 'REPEATED_PAIR'; score := score + 20; end if;
  if pair_fc + p_listing.price_fc > coalesce((market_settings_json()->'pairLimits'->>'fcPerDay')::numeric, 2000000) * 0.8 then
    flags := flags || 'DAILY_LIMIT'; score := score + 15;
  end if;

  if exists (select 1 from market_transactions t
              where t.buyer_user_id = p_seller and t.seller_user_id = p_buyer
                and t.status <> 'reversed' and t.created_at > now() - interval '7 days') then
    flags := flags || 'CIRCULAR_TRADE'; score := score + 35;
  end if;

  if p_listing.item_instance_id is not null and exists (
      select 1 from market_item_ownership_history o
       where o.item_instance_id = p_listing.item_instance_id
         and o.from_user_id = p_buyer
         and o.created_at > now() - interval '7 days') then
    flags := flags || 'ITEM_RETURNED'; score := score + 35;
  end if;

  select count(*) into buyer_trades from market_transactions where buyer_user_id = p_buyer and status <> 'reversed';
  if buyer_trades = 0 and p_listing.price_fc >= 500000 then flags := flags || 'FIRST_TRADE_LARGE'; score := score + 25; end if;

  vel := market_settings_json()->'velocity';
  select count(*) into v5 from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '5 minutes';
  select count(*) into v1h from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '1 hour';
  if v5 >= coalesce((vel->>'per5m')::integer, 5) or v1h >= coalesce((vel->>'per1h')::integer, 15) then
    flags := flags || 'HIGH_VELOCITY'; score := score + 30;
  end if;

  return jsonb_build_object('score', least(score, 100), 'flags', to_jsonb(flags),
    'range', range, 'pairTrades', pair_trades, 'pairFc', pair_fc);
end $function$;

-- 11. Listing creation ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_price_quote(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid DEFAULT NULL, p_item_code text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; kind text := lower(coalesce(p_item_type,'')); rar text := 'default'; lvl integer := 1;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if kind = 'hero' then
    select lower(h.rarity), h.level into rar, lvl from player_heroes h where h.id = p_item_instance_id and h.user_id = u;
  elsif kind = 'pet' then
    select lower(p.rarity), p.level into rar, lvl from player_pets p where p.id = p_item_instance_id and p.user_id = u;
  else
    kind := 'item';
  end if;
  return jsonb_build_object(
    'range', market_price_range(kind, coalesce(rar,'default'), coalesce(lvl,1)),
    'settings', market_settings_json(),
    'eligibility', market_sell_eligibility(u));
end $function$;

CREATE OR REPLACE FUNCTION public.market_create_listing(p_telegram_id bigint, p_item_type text, p_item_instance_id uuid, p_item_code text, p_price_fc numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid; settings jsonb; fee numeric; max_active integer; elig jsonb; range jsonb;
  active_count integer; snap jsonb; listing_id uuid; kind text := lower(coalesce(p_item_type,''));
  h player_heroes%rowtype; pp player_pets%rowtype; inv player_inventory%rowtype; pet_row pets%rowtype;
  rar text := 'default'; lvl integer := 1; price numeric; risk text := 'low'; sell_today numeric;
  g game_players%rowtype; nal jsonb;
begin
  if kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  select * into g from game_players where telegram_id = p_telegram_id for update;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  u := g.id;

  if g.market_cooldown_until is not null and g.market_cooldown_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;

  elig := market_sell_eligibility(u);
  if not (elig->>'canSell')::boolean then raise exception 'MARKET_SELLING_LOCKED'; end if;

  settings := market_settings_json();
  fee := (settings->>'feePercent')::numeric;
  max_active := (settings->>'maxActiveListings')::integer;

  if p_price_fc is null or p_price_fc <> trunc(p_price_fc) or p_price_fc <= 0 then raise exception 'INVALID_PRICE'; end if;
  price := trunc(p_price_fc);

  select count(*) into active_count from market_listings where seller_user_id = u and status = 'active';
  if active_count >= max_active then raise exception 'TOO_MANY_ACTIVE_LISTINGS'; end if;

  if kind = 'hero' then
    select * into h from player_heroes where id = p_item_instance_id and user_id = u for update;
    if h.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if h.market_locked then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(h.locked,false) then raise exception 'HERO_LOCKED'; end if;
    if coalesce(h.tradable,true) = false then raise exception 'HERO_NOT_TRADABLE'; end if;
    if exists (select 1 from pvp_team_slots s where s.player_hero_id = h.id) then raise exception 'HERO_IN_PVP_TEAM'; end if;
    if exists (select 1 from boss_team_slots b where b.hero_id = h.id) then raise exception 'HERO_IN_BOSS_TEAM'; end if;
    rar := lower(coalesce(h.rarity,'default')); lvl := coalesce(h.level,1);
    snap := jsonb_build_object('name', h.name, 'rarity', h.rarity, 'level', h.level, 'image', h.image,
      'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0)),
      'heroKey', h.hero_key);
  elsif kind = 'pet' then
    select * into pp from player_pets where id = p_item_instance_id and user_id = u for update;
    if pp.id is null then raise exception 'ITEM_NOT_OWNED'; end if;
    if pp.market_locked then raise exception 'ALREADY_LISTED'; end if;
    if coalesce(pp.is_active,false) then raise exception 'PET_IS_ACTIVE'; end if;
    if coalesce(pp.tradable,true) = false then raise exception 'PET_NOT_TRADABLE'; end if;
    select * into pet_row from pets where id = pp.pet_id;
    rar := lower(coalesce(pp.rarity,'default')); lvl := coalesce(pp.level,1);
    snap := jsonb_build_object('name', coalesce(pet_row.name,'Pet'), 'rarity', pp.rarity, 'level', pp.level,
      'image', coalesce(pet_row.image_adult_url, pet_row.image_young_url, pet_row.image_baby_url),
      'evolution', pp.evolution_stage, 'tier', coalesce(pp.evolution_tier,0));
  else
    if p_item_code is null or length(p_item_code) < 2 then raise exception 'INVALID_ITEM'; end if;
    select * into inv from player_inventory where user_id = u and item_code = p_item_code for update;
    if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_OWNED'; end if;
    if coalesce(inv.tradable,true) = false then raise exception 'ITEM_NOT_TRADABLE'; end if;
    if inv.item_type = 'fragments' then raise exception 'ITEM_NOT_TRADABLE'; end if;
    rar := 'default'; lvl := 1;
    snap := jsonb_build_object('name', initcap(replace(inv.item_code,'_',' ')), 'rarity', 'rare', 'level', 1,
      'itemType', inv.item_type, 'code', inv.item_code);
  end if;

  -- PRICE GUARD: the seller can never pick an arbitrary value.
  range := market_price_range(kind, rar, lvl);
  if price < (range->>'min')::numeric then raise exception 'PRICE_BELOW_MINIMUM'; end if;
  if price > (range->>'max')::numeric then raise exception 'PRICE_ABOVE_MAXIMUM'; end if;

  nal := settings->'newAccountLimits';
  if market_account_days(u) < coalesce((nal->>'days')::integer, 7) then
    select coalesce(sum(price_fc),0) into sell_today from market_transactions
     where seller_user_id = u and status <> 'reversed' and created_at > now() - interval '24 hours';
    if sell_today + price > coalesce((nal->>'sellFcPerDay')::numeric, 250000) then raise exception 'DAILY_SELL_LIMIT'; end if;
  end if;

  if kind = 'hero' then
    update player_heroes set market_locked = true, updated_at = now() where id = p_item_instance_id;
  elsif kind = 'pet' then
    update player_pets set market_locked = true, updated_at = now() where id = p_item_instance_id;
  else
    update player_inventory set quantity = quantity - 1, updated_at = now() where user_id = u and item_code = p_item_code;
  end if;

  if price >= (range->>'max')::numeric * 0.95 and market_account_days(u) < 14 then risk := 'high';
  elsif price >= (range->>'max')::numeric * 0.9 then risk := 'medium';
  end if;

  insert into market_listings(seller_user_id, item_type, item_instance_id, item_code, price_fc, fee_percent, snapshot, risk_level)
  values (u, kind, case when kind = 'item' then null else p_item_instance_id end,
          case when kind = 'item' then p_item_code else null end, price, fee,
          snap || jsonb_build_object('seller', market_seller_label(u)), risk)
  returning id into listing_id;

  insert into market_security_audit(event, listing_id, seller_user_id, price_fc, details)
  values ('listing_created', listing_id, u, price, jsonb_build_object('range', range, 'riskLevel', risk));

  return jsonb_build_object('ok', true, 'listingId', listing_id, 'feePercent', fee, 'range', range,
    'settlementHours', (settings->>'settlementHours')::integer,
    'sellerReceives', price - round(price * fee / 100));
end $function$;

-- 12. Purchase -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_buy_listing(p_telegram_id bigint, p_listing_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  buyer uuid; buyer_before numeric; buyer_after numeric; g game_players%rowtype;
  l market_listings%rowtype; fee_fc numeric; received numeric; settings jsonb;
  risk jsonb; score integer; flags text[]; tx_id uuid; hold_hours integer;
  pair_trades integer; pair_fc numeric; buy_today numeric; v5 integer; v24 integer;
  vel jsonb; pl jsonb; nal jsonb; new_status text;
begin
  perform set_config('mythreon.market_txn', '1', true);
  settings := market_settings_json();

  select * into g from game_players where telegram_id = p_telegram_id for update;
  if g.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  buyer := g.id; buyer_before := g.forge_coins;
  if coalesce(g.banned,false) then raise exception 'ACCOUNT_BANNED'; end if;
  if g.market_cooldown_until is not null and g.market_cooldown_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;
  if g.market_restricted_until is not null and g.market_restricted_until > now() then raise exception 'MARKET_TEMPORARILY_LIMITED'; end if;

  select * into l from market_listings where id = p_listing_id for update;
  if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
  if l.status <> 'active' then raise exception 'ITEM_NO_LONGER_AVAILABLE'; end if;
  if l.seller_user_id = buyer then raise exception 'CANNOT_BUY_OWN_LISTING'; end if;
  if buyer_before < l.price_fc then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;

  vel := settings->'velocity';
  select count(*) into v5 from market_transactions where buyer_user_id = buyer and created_at > now() - interval '5 minutes';
  select count(*) into v24 from market_transactions where buyer_user_id = buyer and created_at > now() - interval '24 hours';
  if v5 >= coalesce((vel->>'per5m')::integer, 5) or v24 >= coalesce((vel->>'per24h')::integer, 40) then
    update game_players set market_cooldown_until = now() + make_interval(mins => coalesce((vel->>'cooldownMinutes')::integer, 360))
      where id = buyer;
    insert into market_security_audit(event, listing_id, buyer_user_id, seller_user_id, price_fc, risk_flags, details)
    values ('risk_flag', l.id, buyer, l.seller_user_id, l.price_fc, array['HIGH_VELOCITY'], jsonb_build_object('per5m', v5, 'per24h', v24));
    raise exception 'MARKET_TEMPORARILY_LIMITED';
  end if;

  pl := settings->'pairLimits';
  select count(*), coalesce(sum(price_fc),0) into pair_trades, pair_fc
    from market_transactions
   where buyer_user_id = buyer and seller_user_id = l.seller_user_id
     and status <> 'reversed' and created_at > now() - interval '24 hours';
  if pair_trades >= coalesce((pl->>'tradesPerDay')::integer, 3) then raise exception 'PAIR_TRADE_LIMIT'; end if;
  if pair_fc + l.price_fc > coalesce((pl->>'fcPerDay')::numeric, 2000000) then raise exception 'PAIR_VALUE_LIMIT'; end if;

  nal := settings->'newAccountLimits';
  if market_account_days(buyer) < coalesce((nal->>'days')::integer, 7) then
    select coalesce(sum(price_fc),0) into buy_today from market_transactions
     where buyer_user_id = buyer and status <> 'reversed' and created_at > now() - interval '24 hours';
    if buy_today + l.price_fc > coalesce((nal->>'buyFcPerDay')::numeric, 500000) then raise exception 'DAILY_BUY_LIMIT'; end if;
  end if;

  risk := market_risk_assess(buyer, l.seller_user_id, l);
  score := (risk->>'score')::integer;
  flags := array(select jsonb_array_elements_text(risk->'flags'));
  new_status := case when score >= 60 or 'SAME_WALLET' = any(flags) or 'CIRCULAR_TRADE' = any(flags)
                       or 'ITEM_RETURNED' = any(flags) then 'review' else 'pending' end;

  fee_fc := round(l.price_fc * l.fee_percent / 100);
  received := l.price_fc - fee_fc;
  hold_hours := coalesce((settings->>'settlementHours')::integer, 72);

  update game_players set forge_coins = forge_coins - l.price_fc, updated_at = now()
    where id = buyer returning forge_coins into buyer_after;

  -- Seller proceeds are held, never credited straight to the spendable balance.
  update game_players set market_pending_fc = market_pending_fc + received, updated_at = now()
    where id = l.seller_user_id;

  if l.item_type = 'hero' then
    delete from pvp_team_slots where player_hero_id = l.item_instance_id;
    delete from boss_team_slots where hero_id = l.item_instance_id;
    update player_heroes set user_id = buyer, market_locked = false, updated_at = now() where id = l.item_instance_id;
  elsif l.item_type = 'pet' then
    update player_pets set user_id = buyer, market_locked = false, is_active = false, updated_at = now() where id = l.item_instance_id;
  else
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (buyer, coalesce(l.snapshot->>'itemType','item'), l.item_code, l.quantity)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  update market_listings set status = 'sold', buyer_user_id = buyer, sold_at = now() where id = l.id;

  insert into market_transactions(listing_id, seller_user_id, buyer_user_id, item_type, item_instance_id, item_code,
    price_fc, fee_percent, fee_fc, seller_received_fc, snapshot, status, settle_at, risk_score, risk_flags)
  values (l.id, l.seller_user_id, buyer, l.item_type, l.item_instance_id, l.item_code,
    l.price_fc, l.fee_percent, fee_fc, received, l.snapshot, new_status,
    now() + make_interval(hours => hold_hours), score, flags)
  returning id into tx_id;

  insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, price_fc)
  values (l.item_type, l.item_instance_id, l.item_code, l.seller_user_id, buyer, l.id, tx_id, l.price_fc);

  insert into market_pair_stats(buyer_user_id, seller_user_id, trades, total_fc)
  values (buyer, l.seller_user_id, 1, l.price_fc)
  on conflict (buyer_user_id, seller_user_id) do update
    set trades = market_pair_stats.trades + 1,
        total_fc = market_pair_stats.total_fc + excluded.total_fc,
        last_trade_at = now();

  insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
  values (buyer, 'market_purchase', -l.price_fc, buyer_before, buyer_after, tx_id::text);

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, price_fc, fee_fc, risk_score, risk_flags, details)
  values ('sale_created', l.id, tx_id, buyer, l.seller_user_id, l.price_fc, fee_fc, score, flags,
          jsonb_build_object('status', new_status, 'settleAt', now() + make_interval(hours => hold_hours), 'pair', jsonb_build_object('trades', pair_trades, 'fc', pair_fc)));

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (l.seller_user_id, 'market_sale', 'MARKET',
    coalesce(l.snapshot->>'name','Item') || ' vendido por ' || l.price_fc::bigint || ' FC',
    received, jsonb_build_object('listingId', l.id, 'feeFc', fee_fc, 'holdHours', hold_hours, 'status', 'pending'),
    'market_sale:' || l.id::text);

  return jsonb_build_object('ok', true, 'pricePaid', l.price_fc, 'feeFc', fee_fc,
    'sellerReceived', received, 'balanceFc', buyer_after, 'itemType', l.item_type,
    'name', l.snapshot->>'name', 'settlementHours', hold_hours,
    'underReview', new_status = 'review');
end $function$;

-- 13. Settlement / reversal ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_settle_transaction(p_transaction_id uuid, p_admin_id bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t market_transactions%rowtype; before_fc numeric; after_fc numeric;
begin
  perform set_config('mythreon.market_txn', '1', true);
  select * into t from market_transactions where id = p_transaction_id for update;
  if t.id is null then raise exception 'TRANSACTION_NOT_FOUND'; end if;
  if t.status in ('settled','reversed') then return jsonb_build_object('ok', true, 'status', t.status); end if;

  select forge_coins into before_fc from game_players where id = t.seller_user_id for update;
  update game_players
     set market_pending_fc = greatest(market_pending_fc - t.seller_received_fc, 0),
         forge_coins = forge_coins + t.seller_received_fc,
         updated_at = now()
   where id = t.seller_user_id
  returning forge_coins into after_fc;

  insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
  values (t.seller_user_id, 'market_sale', t.seller_received_fc, before_fc, after_fc, t.id::text)
  on conflict do nothing;

  update market_transactions
     set status = 'settled', settled_at = now(), spending_recorded = true,
         admin_id = coalesce(p_admin_id, admin_id)
   where id = t.id;

  -- Spending Points only exist for a settled purchase, and only for the buyer.
  perform record_spending_points(t.buyer_user_id, 'market_purchase', 'market:' || t.id::text, 'FC', t.price_fc);

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, admin_id, price_fc, fee_fc, risk_score, risk_flags)
  values ('sale_settled', t.listing_id, t.id, t.buyer_user_id, t.seller_user_id, p_admin_id, t.price_fc, t.fee_fc, t.risk_score, t.risk_flags);

  insert into player_notifications(user_id, type, title, message, amount_fc, metadata, dedupe_key)
  values (t.seller_user_id, 'market_settled', 'MARKET',
    'Venda liberada: +' || t.seller_received_fc::bigint || ' FC',
    t.seller_received_fc, jsonb_build_object('transactionId', t.id), 'market_settled:' || t.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'status', 'settled');
end $function$;

CREATE OR REPLACE FUNCTION public.market_reverse_transaction(p_transaction_id uuid, p_admin_id bigint DEFAULT NULL, p_reason text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t market_transactions%rowtype; before_fc numeric; after_fc numeric;
begin
  perform set_config('mythreon.market_txn', '1', true);
  select * into t from market_transactions where id = p_transaction_id for update;
  if t.id is null then raise exception 'TRANSACTION_NOT_FOUND'; end if;
  if t.status = 'reversed' then return jsonb_build_object('ok', true, 'status', 'reversed'); end if;

  select forge_coins into before_fc from game_players where id = t.buyer_user_id for update;
  update game_players set forge_coins = forge_coins + t.price_fc, updated_at = now()
   where id = t.buyer_user_id returning forge_coins into after_fc;
  insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
  values (t.buyer_user_id, 'market_refund', t.price_fc, before_fc, after_fc, t.id::text)
  on conflict do nothing;

  if t.status = 'settled' then
    select forge_coins into before_fc from game_players where id = t.seller_user_id for update;
    update game_players set forge_coins = greatest(forge_coins - t.seller_received_fc, 0), updated_at = now()
     where id = t.seller_user_id returning forge_coins into after_fc;
    insert into wallet_ledger(user_id, type, amount_fc, balance_before, balance_after, reference_id)
    values (t.seller_user_id, 'market_sale_reversed', -t.seller_received_fc, before_fc, after_fc, t.id::text)
    on conflict do nothing;
  else
    update game_players set market_pending_fc = greatest(market_pending_fc - t.seller_received_fc, 0), updated_at = now()
     where id = t.seller_user_id;
  end if;

  if t.item_type = 'hero' then
    delete from pvp_team_slots where player_hero_id = t.item_instance_id;
    delete from boss_team_slots where hero_id = t.item_instance_id;
    update player_heroes set user_id = t.seller_user_id, market_locked = false, updated_at = now() where id = t.item_instance_id;
  elsif t.item_type = 'pet' then
    update player_pets set user_id = t.seller_user_id, market_locked = false, is_active = false, updated_at = now() where id = t.item_instance_id;
  else
    update player_inventory set quantity = greatest(quantity - 1, 0), updated_at = now()
      where user_id = t.buyer_user_id and item_code = t.item_code;
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (t.seller_user_id, coalesce(t.snapshot->>'itemType','item'), t.item_code, 1)
    on conflict (user_id, item_type, item_code)
      do update set quantity = player_inventory.quantity + 1, updated_at = now();
  end if;

  insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, price_fc)
  values (t.item_type, t.item_instance_id, t.item_code, t.buyer_user_id, t.seller_user_id, t.listing_id, t.id, 0);

  perform record_spending_reversal('market:' || t.id::text);

  update market_transactions
     set status = 'reversed', reversed_at = now(), admin_id = coalesce(p_admin_id, admin_id),
         admin_notes = coalesce(p_reason, admin_notes)
   where id = t.id;

  insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, admin_id, price_fc, fee_fc, risk_score, risk_flags, details)
  values ('sale_reversed', t.listing_id, t.id, t.buyer_user_id, t.seller_user_id, p_admin_id, t.price_fc, t.fee_fc, t.risk_score, t.risk_flags,
          jsonb_build_object('reason', p_reason));

  return jsonb_build_object('ok', true, 'status', 'reversed');
end $function$;

CREATE OR REPLACE FUNCTION public.market_run_settlements()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n integer := 0;
begin
  for r in select id from market_transactions
            where status = 'pending' and settle_at is not null and settle_at <= now()
            order by settle_at limit 200 loop
    perform market_settle_transaction(r.id, null);
    n := n + 1;
  end loop;
  return n;
end $function$;

-- 14. Spending trigger must ignore market flows -------------------------------
CREATE OR REPLACE FUNCTION public.spending_track_fc_spend()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_delta numeric;
BEGIN
  IF coalesce(current_setting('mythreon.market_txn', true), '') = '1' THEN RETURN NEW; END IF;
  v_delta := COALESCE(OLD.forge_coins, 0) - COALESCE(NEW.forge_coins, 0);
  IF v_delta <= 0 THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM wallet_withdrawals w
              WHERE w.user_id = NEW.id AND w.created_at >= transaction_timestamp()) THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM wallet_ledger l
              WHERE l.user_id = NEW.id AND l.created_at >= transaction_timestamp()
                AND l.type IN ('admin_balance_adjustment','withdrawal','withdrawal_request','withdrawal_hold','refund','transfer','market_purchase','market_refund','market_sale','market_sale_reversed')) THEN
    RETURN NEW;
  END IF;
  PERFORM public.record_spending_points(NEW.id, 'fc_spend',
    'fc:' || txid_current()::text || ':' || replace(gen_random_uuid()::text, '-', ''), 'FC', v_delta);
  RETURN NEW;
END $function$;

-- 15. Player-facing reads ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_browse(p_telegram_id bigint, p_item_type text DEFAULT 'all'::text, p_rarity text DEFAULT 'all'::text, p_sort text DEFAULT 'newest'::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; balance numeric := 0; pending numeric := 0; rows_json jsonb; lim integer := least(greatest(coalesce(p_limit,60),1),100);
begin
  select id, forge_coins, market_pending_fc into u, balance, pending from game_players where telegram_id = p_telegram_id;
  select coalesce(jsonb_agg(item), '[]'::jsonb) into rows_json from (
    select jsonb_build_object(
      'id', l.id, 'itemType', l.item_type, 'priceFc', l.price_fc, 'quantity', l.quantity,
      'createdAt', l.created_at, 'mine', (l.seller_user_id = u),
      'seller', coalesce(l.snapshot->>'seller', market_seller_label(l.seller_user_id)),
      'name', coalesce(l.snapshot->>'name','Item'),
      'rarity', lower(coalesce(l.snapshot->>'rarity','common')),
      'level', coalesce((l.snapshot->>'level')::integer, 1),
      'image', l.snapshot->>'image',
      'atk', coalesce((l.snapshot->>'atk')::numeric, 0),
      'hp', coalesce((l.snapshot->>'hp')::numeric, 0),
      'stars', coalesce((l.snapshot->>'stars')::integer, 0)
    ) as item
    from market_listings l
    where l.status = 'active'
      and (l.risk_level <> 'high' or l.seller_user_id = u)
      and (coalesce(p_item_type,'all') = 'all' or l.item_type = p_item_type)
      and (coalesce(p_rarity,'all') = 'all' or lower(coalesce(l.snapshot->>'rarity','common')) = lower(p_rarity))
    order by
      case when p_sort = 'price_low' then l.price_fc end asc nulls last,
      case when p_sort = 'price_high' then l.price_fc end desc nulls last,
      l.created_at desc
    limit lim offset greatest(coalesce(p_offset,0),0)
  ) q;

  return jsonb_build_object('listings', rows_json, 'balanceFc', coalesce(balance,0),
    'pendingFc', coalesce(pending,0),
    'settings', market_settings_json(),
    'eligibility', case when u is null then null else market_sell_eligibility(u) end,
    'activeCount', (select count(*) from market_listings where seller_user_id = u and status = 'active'));
end $function$;

CREATE OR REPLACE FUNCTION public.market_get_sellable(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; heroes jsonb; pets jsonb; items jsonb;
begin
  select id into u from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', h.id, 'name', h.name, 'rarity', h.rarity, 'level', h.level, 'image', h.image,
    'stars', coalesce(h.fusion_level,0), 'atk', round(coalesce(h.final_atk,0)), 'hp', round(coalesce(h.final_hp,0)),
    'priceRange', market_price_range('hero', h.rarity, h.level)
  ) order by h.created_at desc), '[]'::jsonb) into heroes
  from player_heroes h
  where h.user_id = u and not h.market_locked and coalesce(h.locked,false) = false
    and coalesce(h.tradable, true) = true
    and not exists (select 1 from pvp_team_slots s where s.player_hero_id = h.id)
    and not exists (select 1 from boss_team_slots b where b.hero_id = h.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', pet.name, 'rarity', p.rarity, 'level', p.level,
    'image', coalesce(pet.image_adult_url, pet.image_young_url, pet.image_baby_url),
    'evolution', p.evolution_stage, 'tier', coalesce(p.evolution_tier,0),
    'priceRange', market_price_range('pet', p.rarity, p.level)
  ) order by p.created_at desc), '[]'::jsonb) into pets
  from player_pets p join pets pet on pet.id = p.pet_id
  where p.user_id = u and not p.market_locked and not coalesce(p.is_active,false)
    and coalesce(p.tradable, true) = true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code', i.item_code, 'itemType', i.item_type, 'quantity', i.quantity,
    'priceRange', market_price_range('item', 'default', 1)
  ) order by i.item_code), '[]'::jsonb) into items
  from player_inventory i
  where i.user_id = u and i.quantity > 0 and coalesce(i.tradable, true) = true
    and i.item_type not in ('fragments');

  return jsonb_build_object('heroes', heroes, 'pets', pets, 'items', items,
    'settings', market_settings_json(), 'eligibility', market_sell_eligibility(u));
end $function$;

CREATE OR REPLACE FUNCTION public.market_my_listings(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; pending numeric := 0;
begin
  select id, market_pending_fc into u, pending from game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  return jsonb_build_object(
    'listings', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'itemType', l.item_type, 'name', coalesce(l.snapshot->>'name','Item'),
        'rarity', lower(coalesce(l.snapshot->>'rarity','common')), 'level', coalesce((l.snapshot->>'level')::integer,1),
        'image', l.snapshot->>'image', 'priceFc', l.price_fc, 'status', l.status,
        'createdAt', l.created_at, 'soldAt', l.sold_at, 'cancelledAt', l.cancelled_at,
        'feePercent', l.fee_percent
      ) order by l.created_at desc), '[]'::jsonb) from market_listings l where l.seller_user_id = u),
    'purchases', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'itemType', t.item_type, 'name', coalesce(t.snapshot->>'name','Item'),
        'rarity', lower(coalesce(t.snapshot->>'rarity','common')), 'image', t.snapshot->>'image',
        'priceFc', t.price_fc, 'createdAt', t.created_at,
        'status', case when t.status = 'settled' then 'settled' else 'processing' end,
        'seller', market_seller_label(t.seller_user_id)
      ) order by t.created_at desc), '[]'::jsonb) from market_transactions t where t.buyer_user_id = u),
    'sales', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', coalesce(t.snapshot->>'name','Item'), 'priceFc', t.price_fc,
        'receivedFc', t.seller_received_fc, 'createdAt', t.created_at,
        'settleAt', t.settle_at,
        'status', case when t.status = 'settled' then 'settled'
                       when t.status = 'reversed' then 'reversed' else 'pending' end
      ) order by t.created_at desc), '[]'::jsonb) from market_transactions t where t.seller_user_id = u),
    'pendingFc', coalesce(pending, 0),
    'settings', market_settings_json()
  );
end $function$;

-- 16. Admin surface ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_market_review_queue(p_admin_id bigint, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_assert(p_admin_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'code', upper(substr(replace(t.id::text,'-',''),1,4)),
      'itemType', t.item_type, 'name', coalesce(t.snapshot->>'name','Item'),
      'rarity', lower(coalesce(t.snapshot->>'rarity','common')),
      'priceFc', t.price_fc, 'receivedFc', t.seller_received_fc,
      'buyer', market_seller_label(t.buyer_user_id), 'seller', market_seller_label(t.seller_user_id),
      'riskScore', t.risk_score, 'flags', to_jsonb(t.risk_flags), 'status', t.status,
      'createdAt', t.created_at, 'settleAt', t.settle_at,
      'buyerAccountDays', market_account_days(t.buyer_user_id),
      'sellerAccountDays', market_account_days(t.seller_user_id),
      'median', (market_price_range(t.item_type, t.snapshot->>'rarity', coalesce((t.snapshot->>'level')::integer,1))->>'median'),
      'pairTradesToday', (select count(*) from market_transactions x
                           where x.buyer_user_id = t.buyer_user_id and x.seller_user_id = t.seller_user_id
                             and x.created_at > now() - interval '24 hours')
    ) order by t.risk_score desc, t.created_at desc), '[]'::jsonb)
    from (select * from market_transactions where status = 'review'
          order by risk_score desc, created_at desc
          limit least(greatest(coalesce(p_limit,10),1),25)) t);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_trade_detail(p_admin_id bigint, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t market_transactions%rowtype; needle text := lower(replace(coalesce(p_code,''),'-',''));
begin
  perform admin_assert(p_admin_id);
  if length(needle) < 3 then raise exception 'INVALID_CODE'; end if;
  select * into t from market_transactions
   where replace(id::text,'-','') like needle || '%'
   order by created_at desc limit 1;
  if t.id is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true,
    'id', t.id, 'code', upper(substr(replace(t.id::text,'-',''),1,4)),
    'status', t.status, 'itemType', t.item_type, 'name', coalesce(t.snapshot->>'name','Item'),
    'priceFc', t.price_fc, 'feeFc', t.fee_fc, 'receivedFc', t.seller_received_fc,
    'riskScore', t.risk_score, 'flags', to_jsonb(t.risk_flags),
    'buyer', market_seller_label(t.buyer_user_id), 'seller', market_seller_label(t.seller_user_id),
    'buyerAccountDays', market_account_days(t.buyer_user_id),
    'sellerAccountDays', market_account_days(t.seller_user_id),
    'sameWallet', market_shares_wallet(t.buyer_user_id, t.seller_user_id),
    'createdAt', t.created_at, 'settleAt', t.settle_at, 'settledAt', t.settled_at,
    'reversedAt', t.reversed_at, 'notes', t.admin_notes);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_approve_trade(p_admin_id bigint, p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_assert(p_admin_id);
  perform admin_log(p_admin_id, 'market_approve_trade', 'market', p_transaction_id::text, null, null, null, '{}'::jsonb);
  return market_settle_transaction(p_transaction_id, p_admin_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_reverse_trade(p_admin_id bigint, p_transaction_id uuid, p_reason text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_assert(p_admin_id);
  perform admin_log(p_admin_id, 'market_reverse_trade', 'market', p_transaction_id::text, null, to_jsonb(p_reason), null, '{}'::jsonb);
  return market_reverse_transaction(p_transaction_id, p_admin_id, p_reason);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_user_history(p_admin_id bigint, p_query text, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g game_players%rowtype; needle text := lower(trim(coalesce(p_query,'')));
begin
  perform admin_assert(p_admin_id);
  select * into g from game_players
   where (needle ~ '^[0-9]+$' and telegram_id = needle::bigint)
      or lower(coalesce(username,'')) = ltrim(needle,'@')
      or lower(coalesce(display_name,'')) = needle
   order by created_at limit 1;
  if g.id is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true,
    'player', jsonb_build_object('telegramId', g.telegram_id, 'label', market_seller_label(g.id),
      'accountDays', market_account_days(g.id), 'activeDays', market_active_days(g.id),
      'trust', g.market_trust, 'pendingFc', g.market_pending_fc,
      'restrictedUntil', g.market_restricted_until, 'cooldownUntil', g.market_cooldown_until,
      'eligibility', market_sell_eligibility(g.id)),
    'bought', (select coalesce(sum(price_fc),0) from market_transactions where buyer_user_id = g.id and status <> 'reversed'),
    'sold', (select coalesce(sum(price_fc),0) from market_transactions where seller_user_id = g.id and status <> 'reversed'),
    'trades', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', upper(substr(replace(t.id::text,'-',''),1,4)), 'side', case when t.buyer_user_id = g.id then 'buy' else 'sell' end,
        'name', coalesce(t.snapshot->>'name','Item'), 'priceFc', t.price_fc, 'status', t.status,
        'riskScore', t.risk_score, 'createdAt', t.created_at,
        'counterparty', market_seller_label(case when t.buyer_user_id = g.id then t.seller_user_id else t.buyer_user_id end)
      ) order by t.created_at desc), '[]'::jsonb)
      from (select * from market_transactions where buyer_user_id = g.id or seller_user_id = g.id
            order by created_at desc limit least(greatest(coalesce(p_limit,10),1),25)) t));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_user_connections(p_admin_id bigint, p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g game_players%rowtype; needle text := lower(trim(coalesce(p_query,'')));
begin
  perform admin_assert(p_admin_id);
  select * into g from game_players
   where (needle ~ '^[0-9]+$' and telegram_id = needle::bigint)
      or lower(coalesce(username,'')) = ltrim(needle,'@')
   order by created_at limit 1;
  if g.id is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true,
    'player', market_seller_label(g.id),
    'wallets', (select coalesce(jsonb_agg(w.address), '[]'::jsonb) from market_user_wallets(g.id) w),
    'sharedWallet', (select coalesce(jsonb_agg(jsonb_build_object(
        'label', market_seller_label(o.id), 'telegramId', o.telegram_id)), '[]'::jsonb)
      from game_players o where o.id <> g.id and market_shares_wallet(g.id, o.id)),
    'referrals', (select coalesce(jsonb_agg(jsonb_build_object('label', market_seller_label(r.user_id))), '[]'::jsonb)
      from referrals r where r.inviter_id = g.id),
    'invitedBy', (select market_seller_label(r.inviter_id) from referrals r where r.user_id = g.id),
    'pairs', (select coalesce(jsonb_agg(jsonb_build_object(
        'buyer', market_seller_label(s.buyer_user_id), 'seller', market_seller_label(s.seller_user_id),
        'trades', s.trades, 'totalFc', s.total_fc, 'lastTradeAt', s.last_trade_at) order by s.total_fc desc), '[]'::jsonb)
      from market_pair_stats s where s.buyer_user_id = g.id or s.seller_user_id = g.id));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_restrict_user(p_admin_id bigint, p_query text, p_hours integer DEFAULT 24)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g game_players%rowtype; needle text := lower(trim(coalesce(p_query,'')));
begin
  perform admin_assert(p_admin_id);
  select * into g from game_players
   where (needle ~ '^[0-9]+$' and telegram_id = needle::bigint)
      or lower(coalesce(username,'')) = ltrim(needle,'@')
   order by created_at limit 1;
  if g.id is null then return jsonb_build_object('found', false); end if;
  update game_players
     set market_restricted_until = case when coalesce(p_hours,24) <= 0 then null else now() + make_interval(hours => p_hours) end,
         market_trust = case when coalesce(p_hours,24) <= 0 then 'normal' else 'restricted' end,
         updated_at = now()
   where id = g.id;
  perform admin_log(p_admin_id, 'market_restrict_user', 'market', g.telegram_id::text, null, to_jsonb(p_hours), null, '{}'::jsonb);
  insert into market_security_audit(event, seller_user_id, admin_id, details)
  values ('admin_action', g.id, p_admin_id, jsonb_build_object('action','restrict','hours',p_hours));
  return jsonb_build_object('found', true, 'restrictedHours', p_hours, 'player', market_seller_label(g.id));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_set_price_range(p_admin_id bigint, p_item_type text, p_rarity text, p_min numeric, p_max numeric, p_recommended numeric DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare kind text := lower(coalesce(p_item_type,'')); rar text := lower(coalesce(nullif(p_rarity,''),'default'));
begin
  perform admin_assert(p_admin_id);
  if kind not in ('hero','pet','item') then raise exception 'INVALID_ITEM_TYPE'; end if;
  if p_min is null or p_max is null or p_min < 0 or p_max <= p_min then raise exception 'INVALID_RANGE'; end if;
  insert into market_price_ranges(item_type, rarity, min_fc, max_fc, recommended_fc)
  values (kind, rar, trunc(p_min), trunc(p_max), case when p_recommended is null then null else trunc(p_recommended) end)
  on conflict (item_type, rarity) do update
    set min_fc = excluded.min_fc, max_fc = excluded.max_fc,
        recommended_fc = coalesce(excluded.recommended_fc, market_price_ranges.recommended_fc),
        updated_at = now();
  perform admin_log(p_admin_id, 'market_set_price_range', 'market', kind || ':' || rar, null,
    jsonb_build_object('min', p_min, 'max', p_max), null, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'range', market_price_range(kind, rar, 1));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_price_ranges(p_admin_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_assert(p_admin_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'itemType', r.item_type, 'rarity', r.rarity, 'minFc', r.min_fc, 'maxFc', r.max_fc,
      'recommendedFc', r.recommended_fc) order by r.item_type, r.min_fc), '[]'::jsonb)
    from market_price_ranges r);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_set_security(p_admin_id bigint, p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare allowed text[] := array['market_settlement_hours','market_sell_requirements','market_pair_limits','market_new_account_limits','market_velocity','market_dynamic_range','market_max_active_listings','market_fee_percent'];
begin
  perform admin_assert(p_admin_id);
  if not (p_key = any(allowed)) then raise exception 'INVALID_SETTING'; end if;
  insert into game_settings(key, value, category, label, updated_by)
  values (p_key, p_value, 'marketplace', p_key, p_admin_id)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = p_admin_id;
  perform admin_log(p_admin_id, 'market_set_security', 'market', p_key, null, p_value, null, '{}'::jsonb);
  return market_settings_json();
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_security_audit(p_admin_id bigint, p_limit integer DEFAULT 15)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_assert(p_admin_id);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'event', a.event, 'priceFc', a.price_fc, 'riskScore', a.risk_score,
      'flags', to_jsonb(a.risk_flags), 'createdAt', a.created_at,
      'buyer', market_seller_label(a.buyer_user_id), 'seller', market_seller_label(a.seller_user_id),
      'code', case when a.transaction_id is null then null else upper(substr(replace(a.transaction_id::text,'-',''),1,4)) end,
      'adminId', a.admin_id) order by a.created_at desc), '[]'::jsonb)
    from (select * from market_security_audit order by created_at desc
          limit least(greatest(coalesce(p_limit,15),1),50)) a);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_market_overview(p_admin_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform admin_assert(p_admin_id);
  return jsonb_build_object(
    'settings', market_settings_json(),
    'active', (select count(*) from market_listings where status = 'active'),
    'sold', (select count(*) from market_listings where status = 'sold'),
    'cancelled', (select count(*) from market_listings where status = 'cancelled'),
    'volumeFc', (select coalesce(sum(price_fc),0) from market_transactions where status <> 'reversed'),
    'burnedFc', (select coalesce(sum(fee_fc),0) from market_transactions where status = 'settled'),
    'pendingTrades', (select count(*) from market_transactions where status = 'pending'),
    'reviewTrades', (select count(*) from market_transactions where status = 'review'),
    'reversedTrades', (select count(*) from market_transactions where status = 'reversed'),
    'heldFc', (select coalesce(sum(market_pending_fc),0) from game_players)
  );
end $function$;

-- 17. Lock down execution ------------------------------------------------------
DO $$
DECLARE fn text;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure::text
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND (p.proname LIKE 'market\_%' OR p.proname LIKE 'admin\_market\_%' OR p.proname = 'spending_track_fc_spend')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;

-- 18. Settlement cron ----------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('mythreon-market-settlements');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule('mythreon-market-settlements', '*/5 * * * *', $$SELECT public.market_run_settlements();$$);