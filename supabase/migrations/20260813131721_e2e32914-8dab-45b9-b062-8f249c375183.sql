-- Every `flags || 'LITERAL'` resolved the untyped literal as a text[] literal and
-- crashed with "malformed array literal", so ANY purchase that raised a risk flag
-- (e.g. an account younger than 7 days) failed. Cast the literals to text.
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

  if buyer_days < 7 or seller_days < 7 then flags := flags || 'NEW_ACCOUNT'::text; score := score + 20; end if;
  if market_shares_wallet(p_buyer, p_seller) then flags := flags || 'SAME_WALLET'::text; score := score + 60; end if;
  if exists (select 1 from referrals r where (r.user_id = p_buyer and r.inviter_id = p_seller)
                                          or (r.user_id = p_seller and r.inviter_id = p_buyer)) then
    flags := flags || 'REFERRAL_PAIR'::text; score := score + 15;
  end if;
  if p_listing.price_fc >= (range->>'max')::numeric * 0.9 then flags := flags || 'HIGH_PRICE'::text; score := score + 15; end if;
  if (range->>'median') is not null and p_listing.price_fc > (range->>'median')::numeric * 1.5 then
    flags := flags || 'PRICE_OUTLIER'::text; score := score + 20;
  end if;

  select count(*), coalesce(sum(price_fc),0) into pair_trades, pair_fc
    from market_transactions
   where buyer_user_id = p_buyer and seller_user_id = p_seller
     and status <> 'reversed' and created_at > now() - interval '24 hours';
  if pair_trades >= 2 then flags := flags || 'REPEATED_PAIR'::text; score := score + 20; end if;
  if pair_fc + p_listing.price_fc > coalesce((market_settings_json()->'pairLimits'->>'fcPerDay')::numeric, 2000000) * 0.8 then
    flags := flags || 'DAILY_LIMIT'::text; score := score + 15;
  end if;

  if exists (select 1 from market_transactions t
              where t.buyer_user_id = p_seller and t.seller_user_id = p_buyer
                and t.status <> 'reversed' and t.created_at > now() - interval '7 days') then
    flags := flags || 'CIRCULAR_TRADE'::text; score := score + 35;
  end if;

  if p_listing.item_instance_id is not null and exists (
      select 1 from market_item_ownership_history o
       where o.item_instance_id = p_listing.item_instance_id
         and o.from_user_id = p_buyer
         and o.created_at > now() - interval '7 days') then
    flags := flags || 'ITEM_RETURNED'::text; score := score + 35;
  end if;

  select count(*) into buyer_trades from market_transactions where buyer_user_id = p_buyer and status <> 'reversed';
  if buyer_trades = 0 and p_listing.price_fc >= 500000 then flags := flags || 'FIRST_TRADE_LARGE'::text; score := score + 25; end if;

  vel := market_settings_json()->'velocity';
  select count(*) into v5 from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '5 minutes';
  select count(*) into v1h from market_transactions where buyer_user_id = p_buyer and created_at > now() - interval '1 hour';
  if v5 >= coalesce((vel->>'per5m')::integer, 5) or v1h >= coalesce((vel->>'per1h')::integer, 15) then
    flags := flags || 'HIGH_VELOCITY'::text; score := score + 30;
  end if;

  return jsonb_build_object('score', least(score, 100), 'flags', to_jsonb(flags),
    'range', range, 'pairTrades', pair_trades, 'pairFc', pair_fc);
end $function$;