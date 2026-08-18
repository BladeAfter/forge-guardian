create table if not exists public._market_probe(k text primary key, v text);
grant all on public._market_probe to service_role;
alter table public._market_probe enable row level security;
do $$
declare tid bigint := 1310583958;
begin
  begin insert into public._market_probe values('status', left(public.market_status(tid)::text,300)) on conflict (k) do update set v=excluded.v;
  exception when others then insert into public._market_probe values('status','ERR: '||sqlerrm) on conflict (k) do update set v=excluded.v; end;
  begin insert into public._market_probe values('mine', left(public.market_my_listings(tid)::text,300)) on conflict (k) do update set v=excluded.v;
  exception when others then insert into public._market_probe values('mine','ERR: '||sqlerrm) on conflict (k) do update set v=excluded.v; end;
  begin insert into public._market_probe values('sellable', left(public.market_get_sellable(tid)::text,300)) on conflict (k) do update set v=excluded.v;
  exception when others then insert into public._market_probe values('sellable','ERR: '||sqlerrm) on conflict (k) do update set v=excluded.v; end;
  begin insert into public._market_probe values('browse', left(public.market_browse(tid,'all','all','newest',60,0,'all')::text,300)) on conflict (k) do update set v=excluded.v;
  exception when others then insert into public._market_probe values('browse','ERR: '||sqlerrm) on conflict (k) do update set v=excluded.v; end;
end $$;