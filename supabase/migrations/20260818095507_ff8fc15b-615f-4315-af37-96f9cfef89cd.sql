truncate public._market_probe;
do $$
begin
  begin
    perform public.market_buy_listing(1310583958, '62a2e4c9-44d0-45ed-8659-a667fc0d3f2e');
    insert into public._market_probe values('dup','NO_ERROR') on conflict (k) do update set v=excluded.v;
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_PROBE' then
      insert into public._market_probe values('dup', sqlerrm) on conflict (k) do update set v=excluded.v;
    end if;
  end;
end $$;