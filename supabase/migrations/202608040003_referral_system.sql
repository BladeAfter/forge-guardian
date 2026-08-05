alter table public.game_players add column if not exists display_name text;
alter table public.game_players add column if not exists username text;
alter table public.game_players add column if not exists avatar_url text;
alter table public.game_players add column if not exists last_seen_at timestamptz not null default now();

create table if not exists public.referrals(
  id uuid primary key default gen_random_uuid(),user_id uuid not null unique references public.game_players(id) on delete cascade,
  inviter_id uuid not null references public.game_players(id),level integer not null default 1 check(level=1),created_at timestamptz not null default now(),
  check(user_id<>inviter_id)
);
create index if not exists referrals_inviter_idx on public.referrals(inviter_id);

create table if not exists public.referral_purchase_events(
  id uuid primary key default gen_random_uuid(),buyer_id uuid not null references public.game_players(id),purchase_id text not null unique,
  event_type text not null,amount_fc numeric not null check(amount_fc>0),source_currency text not null default 'FC',source_amount numeric,
  eligible boolean not null,created_at timestamptz not null default now()
);
create table if not exists public.economy_settings(key text primary key,value_numeric numeric not null check(value_numeric>0),updated_at timestamptz not null default now());
insert into public.economy_settings(key,value_numeric) values('ton_fc_rate',100000) on conflict(key) do nothing;
create table if not exists public.referral_commissions(
  id uuid primary key default gen_random_uuid(),user_id uuid not null references public.game_players(id),from_user uuid not null references public.game_players(id),
  level integer not null check(level between 1 and 3),purchase_id text not null references public.referral_purchase_events(purchase_id),
  amount_fc numeric not null check(amount_fc>0),created_at timestamptz not null default now(),unique(user_id,purchase_id,level)
);
create index if not exists referral_commissions_user_date_idx on public.referral_commissions(user_id,created_at desc);
create index if not exists referral_commissions_from_idx on public.referral_commissions(from_user);

create table if not exists public.player_notifications(
  id uuid primary key default gen_random_uuid(),user_id uuid not null references public.game_players(id) on delete cascade,
  type text not null,title text not null,message text not null,amount_fc numeric,metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,created_at timestamptz not null default now()
);
create index if not exists player_notifications_unread_idx on public.player_notifications(user_id,created_at desc) where read_at is null;

create table if not exists public.referral_bonus_rules(
  milestone integer primary key check(milestone in (10,50,100,500,1000)),bonus_fc numeric not null default 0 check(bonus_fc>=0),enabled boolean not null default false,updated_at timestamptz not null default now()
);
insert into public.referral_bonus_rules(milestone) values(10),(50),(100),(500),(1000) on conflict do nothing;
create table if not exists public.referral_bonus_claims(
  id uuid primary key default gen_random_uuid(),user_id uuid not null references public.game_players(id),milestone integer not null references public.referral_bonus_rules(milestone),
  amount_fc numeric not null check(amount_fc>=0),created_at timestamptz not null default now(),unique(user_id,milestone)
);

alter table public.referrals enable row level security;
alter table public.referral_purchase_events enable row level security;
alter table public.economy_settings enable row level security;
alter table public.referral_commissions enable row level security;
alter table public.player_notifications enable row level security;
alter table public.referral_bonus_rules enable row level security;
alter table public.referral_bonus_claims enable row level security;
revoke all on public.referrals,public.referral_purchase_events,public.economy_settings,public.referral_commissions,public.player_notifications,public.referral_bonus_rules,public.referral_bonus_claims from anon,authenticated;

create or replace function public.touch_referral_player(p_telegram_id bigint,p_name text,p_username text,p_avatar text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 insert into game_players(telegram_id,display_name,username,avatar_url,last_seen_at) values(p_telegram_id,nullif(trim(p_name),''),nullif(trim(p_username),''),nullif(trim(p_avatar),''),now())
 on conflict(telegram_id) do update set display_name=coalesce(excluded.display_name,game_players.display_name),username=coalesce(excluded.username,game_players.username),avatar_url=coalesce(excluded.avatar_url,game_players.avatar_url),last_seen_at=now(),updated_at=now()
 returning id into v_id;return v_id;
end $$;

create or replace function public.grant_referral_milestones(p_user_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare r referral_bonus_rules%rowtype; total_direct integer;
begin
 select count(*) into total_direct from referrals where inviter_id=p_user_id;
 for r in select * from referral_bonus_rules where enabled and milestone<=total_direct loop
   insert into referral_bonus_claims(user_id,milestone,amount_fc) values(p_user_id,r.milestone,r.bonus_fc) on conflict do nothing;
   if found and r.bonus_fc>0 then
     update game_players set forge_coins=forge_coins+r.bonus_fc,updated_at=now() where id=p_user_id;
     insert into player_notifications(user_id,type,title,message,amount_fc,metadata) values(p_user_id,'referral_bonus','Bônus de indicação','Meta de '||r.milestone||' convidados atingida',r.bonus_fc,jsonb_build_object('milestone',r.milestone));
   end if;
 end loop;
end $$;

create or replace function public.bind_referral(p_telegram_id bigint,p_inviter_telegram_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_user uuid;v_inviter uuid;existing uuid;cursor_id uuid;depth integer:=0;
begin
 if p_telegram_id=p_inviter_telegram_id then raise exception 'SELF_REFERRAL_BLOCKED';end if;
 select id into v_user from game_players where telegram_id=p_telegram_id;
 select id into v_inviter from game_players where telegram_id=p_inviter_telegram_id;
 if v_user is null then raise exception 'PLAYER_NOT_FOUND';end if;if v_inviter is null then raise exception 'INVITER_NOT_FOUND';end if;
 -- Lock both players in a deterministic order. This closes the race where two
 -- players try to sponsor each other at the same time.
 perform 1 from game_players where id in(v_user,v_inviter) order by id for update;
 select inviter_id into existing from referrals where user_id=v_user;
 if existing is not null then
   if existing<>v_inviter then raise exception 'SPONSOR_IMMUTABLE';end if;
   return jsonb_build_object('linked',true,'existing',true);
 end if;
 cursor_id:=v_inviter;
 while cursor_id is not null and depth<100 loop
   if cursor_id=v_user then raise exception 'REFERRAL_CYCLE_BLOCKED';end if;
   select inviter_id into cursor_id from referrals where user_id=cursor_id;depth:=depth+1;
 end loop;
 if depth>=100 then raise exception 'REFERRAL_DEPTH_INVALID';end if;
 insert into referrals(user_id,inviter_id) values(v_user,v_inviter);
 perform public.grant_referral_milestones(v_inviter);
 return jsonb_build_object('linked',true,'existing',false);
end $$;

create or replace function public.distribute_referral_commission(
 p_buyer_id uuid,p_purchase_id text,p_event_type text,p_amount_fc numeric,p_eligible boolean,p_source_currency text default 'FC',p_source_amount numeric default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare current_user uuid:=p_buyer_id;beneficiary uuid;lvl integer;rate numeric;paid numeric;total_paid numeric:=0;excluded boolean;
begin
 if p_amount_fc<=0 or p_amount_fc::text in('NaN','Infinity','-Infinity') then raise exception 'INVALID_PURCHASE_AMOUNT';end if;
 excluded:=lower(p_event_type)=any(array['referral_commission','withdrawal','admin_bonus','gift','free_reward','daily_login']);
 insert into referral_purchase_events(buyer_id,purchase_id,event_type,amount_fc,source_currency,source_amount,eligible)
 values(p_buyer_id,p_purchase_id,lower(p_event_type),round(p_amount_fc,3),upper(p_source_currency),p_source_amount,p_eligible and not excluded)
 on conflict(purchase_id) do nothing;
 if not found then return jsonb_build_object('duplicate',true,'totalPaid',0);end if;
 if not p_eligible or excluded then return jsonb_build_object('duplicate',false,'totalPaid',0);end if;
 for lvl in 1..3 loop
   select inviter_id into beneficiary from referrals where user_id=current_user;
   exit when beneficiary is null;rate:=case lvl when 1 then .10 when 2 then .05 else .02 end;paid:=round(p_amount_fc*rate,3);
   insert into referral_commissions(user_id,from_user,level,purchase_id,amount_fc) values(beneficiary,p_buyer_id,lvl,p_purchase_id,paid) on conflict do nothing;
   if found then
     update game_players set forge_coins=forge_coins+paid,updated_at=now() where id=beneficiary;
     insert into player_notifications(user_id,type,title,message,amount_fc,metadata) values(beneficiary,'referral_commission','Comissão Lv'||lvl,'+'||to_char(paid,'FM999999999990.000')||' FC',paid,jsonb_build_object('level',lvl,'purchaseId',p_purchase_id,'fromUser',p_buyer_id));
     total_paid:=total_paid+paid;
   end if;current_user:=beneficiary;
 end loop;
 return jsonb_build_object('duplicate',false,'totalPaid',total_paid);
end $$;

create or replace function public.record_eligible_purchase(p_buyer_id uuid,p_purchase_id text,p_event_type text,p_amount numeric,p_currency text,p_eligible boolean default true) returns jsonb
language plpgsql security definer set search_path=public as $$
declare amount_fc numeric;rate numeric;
begin
 if upper(p_currency)='TON' then select value_numeric into rate from economy_settings where key='ton_fc_rate';amount_fc:=round(p_amount*rate,3);
 elsif upper(p_currency)='FC' then amount_fc:=p_amount;
 else raise exception 'UNSUPPORTED_CURRENCY';end if;
 return public.distribute_referral_commission(p_buyer_id,p_purchase_id,p_event_type,amount_fc,p_eligible,upper(p_currency),p_amount);
end $$;

create or replace function public.get_referral_dashboard(p_telegram_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_user uuid;
begin
 select id into v_user from game_players where telegram_id=p_telegram_id;
 if v_user is null then raise exception 'PLAYER_NOT_FOUND';end if;
 return jsonb_build_object(
  'telegramId',p_telegram_id,
  'counts',(with recursive tree as(select r.user_id,1 lvl from referrals r where r.inviter_id=v_user union all select r.user_id,t.lvl+1 from referrals r join tree t on r.inviter_id=t.user_id where t.lvl<3) select jsonb_build_object('total',count(*),'lv1',count(*) filter(where lvl=1),'lv2',count(*) filter(where lvl=2),'lv3',count(*) filter(where lvl=3)) from tree),
  'earnings',(select jsonb_build_object('today',coalesce(sum(amount_fc) filter(where created_at>=date_trunc('day',now())),0),'yesterday',coalesce(sum(amount_fc) filter(where created_at>=date_trunc('day',now())-interval '1 day' and created_at<date_trunc('day',now())),0),'days7',coalesce(sum(amount_fc) filter(where created_at>=now()-interval '7 days'),0),'days30',coalesce(sum(amount_fc) filter(where created_at>=now()-interval '30 days'),0),'total',coalesce(sum(amount_fc),0)) from referral_commissions where user_id=v_user),
  'invites',(with recursive tree as(select r.user_id,1 lvl,r.created_at from referrals r where r.inviter_id=v_user union all select r.user_id,t.lvl+1,r.created_at from referrals r join tree t on r.inviter_id=t.user_id where t.lvl<3) select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.display_name,'Jogador'),'username',p.username,'avatar',p.avatar_url,'level',t.lvl,'joinedAt',t.created_at,'lastSeenAt',p.last_seen_at,'online',p.last_seen_at>now()-interval '5 minutes','generated',coalesce((select sum(e.amount_fc) from referral_purchase_events e where e.buyer_id=p.id and e.eligible),0),'commission',coalesce((select sum(c.amount_fc) from referral_commissions c where c.user_id=v_user and c.from_user=p.id),0)) order by t.lvl,t.created_at desc),'[]'::jsonb) from tree t join game_players p on p.id=t.user_id),
  'tree',(with recursive tree as(select r.user_id,r.inviter_id,1 lvl from referrals r where r.inviter_id=v_user union all select r.user_id,r.inviter_id,t.lvl+1 from referrals r join tree t on r.inviter_id=t.user_id where t.lvl<3) select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'parentId',t.inviter_id,'name',coalesce(p.display_name,'Jogador'),'avatar',p.avatar_url,'level',t.lvl) order by t.lvl),'[]'::jsonb) from tree t join game_players p on p.id=t.user_id),
  'ranking',(select coalesce(jsonb_agg(row_data order by position),'[]'::jsonb) from(select row_number() over(order by base.commissions desc,base.invites desc) position,base.* from(select p.id,p.display_name name,p.avatar_url avatar,(select count(*) from referrals r where r.inviter_id=p.id) invites,(select coalesce(sum(c.amount_fc),0) from referral_commissions c where c.user_id=p.id and c.created_at>=date_trunc('week',now())) commissions from game_players p) base order by base.commissions desc,base.invites desc limit 100) row_data),
  'bonuses',(select coalesce(jsonb_agg(jsonb_build_object('milestone',b.milestone,'bonusFc',b.bonus_fc,'enabled',b.enabled,'claimed',c.id is not null) order by b.milestone),'[]'::jsonb) from referral_bonus_rules b left join referral_bonus_claims c on c.milestone=b.milestone and c.user_id=v_user),
  'notifications',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'message',message,'amountFc',amount_fc,'createdAt',created_at) order by created_at desc),'[]'::jsonb) from(select * from player_notifications where user_id=v_user order by created_at desc limit 20)n)
 );
end $$;

create or replace function public.get_referral_admin_stats() returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object('totalInvites',(select count(*) from referrals),'lv1',(select count(*) from referrals),'lv2',(with recursive t as(select user_id,inviter_id,1 l from referrals union all select r.user_id,t.inviter_id,t.l+1 from referrals r join t on r.inviter_id=t.user_id where t.l<2)select count(*) from t where l=2),'lv3',(with recursive t as(select user_id,inviter_id,1 l from referrals union all select r.user_id,t.inviter_id,t.l+1 from referrals r join t on r.inviter_id=t.user_id where t.l<3)select count(*) from t where l=3),'totalPaid',(select coalesce(sum(amount_fc),0) from referral_commissions),'top100',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select p.id,p.display_name,(select count(*) from referrals r where r.inviter_id=p.id) invites,(select coalesce(sum(c.amount_fc),0) from referral_commissions c where c.user_id=p.id) paid from game_players p order by invites desc,paid desc limit 100)x));
$$;

create or replace function public.recruit_heroes(p_telegram_id bigint,p_count integer) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_user uuid;v_cost numeric;i int;roll numeric;rarity_pick text;picked hero_catalog%rowtype;new_hero_id uuid;result jsonb:='[]'::jsonb;v_purchase_id text;
begin
 if p_count not in(1,5,10) then raise exception 'Invalid recruitment count';end if;v_cost:=25000*p_count;
 insert into game_players(telegram_id,last_seen_at) values(p_telegram_id,now()) on conflict(telegram_id) do update set last_seen_at=now(),updated_at=now() returning id into v_user;
 if(select forge_coins from game_players where id=v_user for update)<v_cost then raise exception 'NOT_ENOUGH_FC';end if;
 update game_players set forge_coins=forge_coins-v_cost,updated_at=now() where id=v_user;
 for i in 1..p_count loop
   roll:=random()*100;rarity_pick:=case when roll<.3 then 'legendary' when roll<3 then 'epic' when roll<13 then 'rare' when roll<38 then 'uncommon' else 'common' end;
   select * into picked from hero_catalog where rarity=rarity_pick and enabled order by random() limit 1;
   insert into player_heroes(user_id,hero_key,name,rarity,level,image) values(v_user,picked.hero_key,picked.name,picked.rarity,1,picked.image) returning id into new_hero_id;
   result:=result||jsonb_build_array(jsonb_build_object('id',new_hero_id,'heroKey',picked.hero_key,'name',picked.name,'rarity',picked.rarity,'level',1,'image',picked.image));
 end loop;
 v_purchase_id:='hero_recruitment:'||gen_random_uuid();
 perform public.distribute_referral_commission(v_user,v_purchase_id,'hero_purchase',v_cost,true,'FC',v_cost);
 return jsonb_build_object('heroes',result,'balance',(select forge_coins from game_players where id=v_user),'purchaseId',v_purchase_id);
end $$;

revoke all on function public.touch_referral_player(bigint,text,text,text),public.bind_referral(bigint,bigint),public.distribute_referral_commission(uuid,text,text,numeric,boolean,text,numeric),public.record_eligible_purchase(uuid,text,text,numeric,text,boolean),public.get_referral_dashboard(bigint),public.get_referral_admin_stats(),public.grant_referral_milestones(uuid) from public,anon,authenticated;
grant execute on function public.touch_referral_player(bigint,text,text,text),public.bind_referral(bigint,bigint),public.distribute_referral_commission(uuid,text,text,numeric,boolean,text,numeric),public.record_eligible_purchase(uuid,text,text,numeric,text,boolean),public.get_referral_dashboard(bigint),public.get_referral_admin_stats(),public.grant_referral_milestones(uuid) to service_role;
