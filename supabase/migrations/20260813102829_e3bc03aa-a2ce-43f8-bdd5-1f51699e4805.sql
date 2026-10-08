alter table public.market_item_ownership_history alter column price_fc drop not null;
alter table public.market_item_ownership_history alter column price_fc drop default;
alter table public.market_item_ownership_history add column if not exists price_ton numeric null;
alter table public.market_item_ownership_history add column if not exists currency text null;

alter table public.market_item_ownership_history drop constraint if exists market_ownership_currency_price_check;
alter table public.market_item_ownership_history add constraint market_ownership_currency_price_check check (
  currency is null
  or (currency = 'FC' and price_ton is null)
  or (currency = 'TON' and price_fc is null)
);

do $do$
declare
  def text;
  newdef text;
  fn text;
begin
  foreach fn in array array['market_finalize_purchase','market_reverse_transaction'] loop
    select pg_get_functiondef(p.oid) into def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = fn
     limit 1;
    if def is null then continue; end if;

    newdef := replace(def,
      'insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, price_fc)
  values (l.item_type, l.item_instance_id, l.item_code, l.seller_user_id, p_buyer, l.id, tx_id, coalesce(l.price_fc, 0));',
      'insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, currency, price_fc, price_ton)
  values (l.item_type, l.item_instance_id, l.item_code, l.seller_user_id, p_buyer, l.id, tx_id, cur,
          case when cur = ''FC'' then l.price_fc else null end,
          case when cur = ''TON'' then l.price_ton else null end);');

    newdef := replace(newdef,
      'insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, price_fc)
  values (t.item_type, t.item_instance_id, t.item_code, t.buyer_user_id, t.seller_user_id, t.listing_id, t.id, 0);',
      'insert into market_item_ownership_history(item_type, item_instance_id, item_code, from_user_id, to_user_id, listing_id, transaction_id, currency, price_fc, price_ton)
  values (t.item_type, t.item_instance_id, t.item_code, t.buyer_user_id, t.seller_user_id, t.listing_id, t.id,
          coalesce(t.currency, ''FC''), null, null);');

    newdef := replace(newdef,
      'insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, price_fc, fee_fc, risk_score, risk_flags, details)
  values (''sale_created'', l.id, tx_id, p_buyer, l.seller_user_id,',
      'insert into market_security_audit(event, listing_id, transaction_id, buyer_user_id, seller_user_id, currency, price_ton, fee_ton, price_fc, fee_fc, risk_score, risk_flags, details)
  values (''sale_created'', l.id, tx_id, p_buyer, l.seller_user_id, cur,
          case when cur = ''TON'' then l.price_ton else null end,
          case when cur = ''TON'' then fee_amount else null end,');

    newdef := replace(newdef,
      'insert into market_security_audit(event, listing_id, buyer_user_id, seller_user_id, price_fc, risk_flags, details)
      values (''risk_flag'', l.id, p_buyer, l.seller_user_id, l.price_fc, array[''HIGH_VELOCITY''], jsonb_build_object(''per5m'', v5, ''per24h'', v24));',
      'insert into market_security_audit(event, listing_id, buyer_user_id, seller_user_id, currency, price_fc, price_ton, risk_flags, details)
      values (''risk_flag'', l.id, p_buyer, l.seller_user_id, cur, l.price_fc, l.price_ton, array[''HIGH_VELOCITY''], jsonb_build_object(''per5m'', v5, ''per24h'', v24));');

    if newdef <> def then
      execute newdef;
    end if;
  end loop;
end $do$;