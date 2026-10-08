truncate public._market_probe;
do $$
declare l record;
begin
  for l in select id, currency, item_type from public.market_listings where status='active' limit 12 loop
    begin
      perform public.market_buy_listing(1310583958, l.id);
      insert into public._market_probe values('buy:'||l.id,'OK-rolled-back') on conflict (k) do update set v=excluded.v;
      raise exception 'ROLLBACK_PROBE';
    exception when others then
      if sqlerrm <> 'ROLLBACK_PROBE' then
        insert into public._market_probe values('buy:'||l.id, l.item_type||'/'||l.currency||' -> '||sqlerrm) on conflict (k) do update set v=excluded.v;
      else
        insert into public._market_probe values('buy:'||l.id, l.item_type||'/'||l.currency||' -> OK') on conflict (k) do update set v=excluded.v;
      end if;
    end;
  end loop;
end $$;