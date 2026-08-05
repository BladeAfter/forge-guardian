create table if not exists public.referral_commission_settings(
  level integer primary key check(level between 1 and 3),
  percent numeric not null check(percent>=0 and percent<=100),
  updated_at timestamptz not null default now()
);
insert into public.referral_commission_settings(level,percent) values(1,10),(2,5),(3,2)
on conflict(level) do update set percent=excluded.percent,updated_at=now();
alter table public.referral_commission_settings enable row level security;
revoke all on public.referral_commission_settings from anon,authenticated;

alter table public.referral_commissions add column if not exists idempotency_key text;
update public.referral_commissions
set idempotency_key='referral_commission:purchase:'||purchase_id||':'||user_id||':'||level
where idempotency_key is null;
create unique index if not exists referral_commissions_idempotency_idx on public.referral_commissions(idempotency_key);

create or replace function public.get_referral_dashboard_v2(
  p_telegram_id bigint,p_level integer default null,p_offset integer default 0,p_limit integer default 20
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid;v_profile game_players%rowtype;v_base jsonb;v_invites jsonb;v_filtered_count integer;v_limit integer;v_offset integer;
begin
  if p_level is not null and p_level not between 1 and 3 then raise exception 'INVALID_LEVEL_FILTER';end if;
  v_limit:=least(20,greatest(1,coalesce(p_limit,20)));v_offset:=greatest(0,coalesce(p_offset,0));
  select * into v_profile from game_players where telegram_id=p_telegram_id;
  if v_profile.id is null then raise exception 'PLAYER_NOT_FOUND';end if;v_user:=v_profile.id;
  v_base:=public.get_referral_dashboard(p_telegram_id);
  select count(*) into v_filtered_count from jsonb_array_elements(coalesce(v_base->'invites','[]'::jsonb)) x where p_level is null or (x->>'level')::integer=p_level;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_invites from(
    select value x from jsonb_array_elements(coalesce(v_base->'invites','[]'::jsonb))
    where p_level is null or (value->>'level')::integer=p_level
    order by (value->>'joinedAt')::timestamptz desc offset v_offset limit v_limit
  ) page;
  return v_base||jsonb_build_object(
    'profile',jsonb_build_object('telegramId',p_telegram_id::text,'username',v_profile.username,'firstName',v_profile.display_name,'photoUrl',v_profile.avatar_url),
    'invites',v_invites,
    'referrals',v_invites,
    'pagination',jsonb_build_object('offset',v_offset,'limit',v_limit,'hasMore',v_offset+v_limit<v_filtered_count),
    'commissionLevels',(select jsonb_agg(jsonb_build_object(
      'level',s.level,'percent',s.percent,
      'invitedCount',coalesce((v_base#>>array['counts','lv'||s.level])::integer,0),
      'totalEarnedFc',coalesce((select sum(c.amount_fc) from referral_commissions c where c.user_id=v_user and c.level=s.level),0)
    ) order by s.level) from referral_commission_settings s),
    'summary',jsonb_build_object(
      'totalInvited',coalesce((v_base#>>'{counts,total}')::integer,0),
      'totalEarnedFc',coalesce((v_base#>>'{earnings,total}')::numeric,0),
      'earnedTodayFc',coalesce((v_base#>>'{earnings,today}')::numeric,0),
      'earned7DaysFc',coalesce((v_base#>>'{earnings,days7}')::numeric,0)
    )
  );
end $$;

revoke all on function public.get_referral_dashboard_v2(bigint,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.get_referral_dashboard_v2(bigint,integer,integer,integer) to service_role;
