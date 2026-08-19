create table if not exists public.diag_tmp(id bigserial primary key, label text, value jsonb, created_at timestamptz default now());
grant all on public.diag_tmp to service_role;
alter table public.diag_tmp enable row level security;
do $$
declare t timestamptz := clock_timestamp(); n int; c int; begin
  select count(*) into c from player_heroes ph join game_players g on g.id=ph.user_id where g.telegram_id=1310583958;
  select jsonb_array_length(public.get_hero_fusion_dashboard(1310583958)->'heroes') into n;
  insert into public.diag_tmp(label,value) values('fusion', jsonb_build_object('heroes',c,'json',n,'ms',extract(milliseconds from clock_timestamp()-t)));
end $$;