create table if not exists public._diag_log(id bigserial primary key, msg text, created_at timestamptz default now());
do $$
begin
  begin
    perform public.open_legend_chest(5154918326, '23558b43-0551-4537-a024-8b7444c47eb5'::uuid);
    raise exception 'DIAG_SUCCESS';
  exception when others then
    insert into public._diag_log(msg) values ('legendary_chest: ' || SQLSTATE || ' :: ' || SQLERRM);
  end;
  begin
    perform public.open_legend_chest(5154918326, '82b8448d-c69b-498b-ae97-248c88e30d97'::uuid);
    raise exception 'DIAG_SUCCESS';
  exception when others then
    insert into public._diag_log(msg) values ('legend-chest: ' || SQLSTATE || ' :: ' || SQLERRM);
  end;
end $$;