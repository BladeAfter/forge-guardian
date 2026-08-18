truncate public._market_probe;
do $$
declare r record; tid bigint;
begin
  for r in select telegram_id from public.game_players order by updated_at desc nulls last limit 40 loop
    tid := r.telegram_id;
    begin perform public.market_status(tid); exception when others then insert into public._market_probe values('status:'||tid,sqlerrm) on conflict (k) do update set v=excluded.v; end;
    begin perform public.market_my_listings(tid); exception when others then insert into public._market_probe values('mine:'||tid,sqlerrm) on conflict (k) do update set v=excluded.v; end;
    begin perform public.market_get_sellable(tid); exception when others then insert into public._market_probe values('sellable:'||tid,sqlerrm) on conflict (k) do update set v=excluded.v; end;
    begin perform public.market_browse(tid,'all','all','newest',60,0,'all'); exception when others then insert into public._market_probe values('browse:'||tid,sqlerrm) on conflict (k) do update set v=excluded.v; end;
    begin perform public.market_browse(tid,'hero','all','price_low',60,0,'FC'); exception when others then insert into public._market_probe values('browseFC:'||tid,sqlerrm) on conflict (k) do update set v=excluded.v; end;
    begin perform public.market_browse(tid,'pet','all','price_high',60,60,'TON'); exception when others then insert into public._market_probe values('browseTON:'||tid,sqlerrm) on conflict (k) do update set v=excluded.v; end;
  end loop;
  if not exists(select 1 from public._market_probe) then insert into public._market_probe values('result','no errors on 40 recent players'); end if;
end $$;