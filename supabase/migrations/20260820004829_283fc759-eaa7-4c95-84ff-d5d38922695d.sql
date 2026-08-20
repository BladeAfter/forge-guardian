do $$
declare r record; j jsonb;
begin
  for r in select id, item_type from market_listings where status in ('active','reserved') limit 40 loop
    j := public.market_item_details(8118569391, 'market', r.id);
    if j->'item'->>'name' is null then
      raise exception 'EMPTY_DETAILS % %', r.item_type, r.id;
    end if;
  end loop;
  for r in select id from auctions order by created_at desc limit 10 loop
    j := public.market_item_details(8118569391, 'auction', r.id);
    if j->'item'->>'name' is null then raise exception 'EMPTY_AUCTION_DETAILS %', r.id; end if;
  end loop;
end $$;