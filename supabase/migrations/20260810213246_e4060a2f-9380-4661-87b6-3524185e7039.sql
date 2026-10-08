alter table public.pet_hatch_history
  add column if not exists opening_id text,
  add column if not exists status text not null default 'completed',
  add column if not exists completed_at timestamptz,
  add column if not exists failure_reason text;

update public.pet_hatch_history
set opening_id = idempotency_key,
    status = 'completed',
    completed_at = coalesce(completed_at, created_at)
where opening_id is null or completed_at is null;

alter table public.pet_hatch_history
  alter column opening_id set not null;

alter table public.pet_hatch_history
  drop constraint if exists pet_hatch_history_status_check;
alter table public.pet_hatch_history
  add constraint pet_hatch_history_status_check check (status in ('processing','completed','failed'));

create unique index if not exists pet_hatch_history_user_opening_id_key
  on public.pet_hatch_history(user_id, opening_id);
create index if not exists pet_hatch_history_user_status_created_idx
  on public.pet_hatch_history(user_id, status, created_at desc);

grant select, insert, update on public.pet_hatch_history to service_role;

create or replace function public.pet_hatch_result_json(p_history public.pet_hatch_history)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'openingId', p_history.opening_id,
    'historyId', p_history.id,
    'status', p_history.status,
    'petId', p.id,
    'name', p.name,
    'rarity', p_history.result_rarity,
    'image', p.image_baby_url,
    'duplicateFragments', p_history.duplicate_fragments,
    'createdAt', p_history.created_at,
    'completedAt', p_history.completed_at
  )
  from public.pets p
  where p.id = p_history.result_pet_id
$$;

create or replace function public.get_pet_egg_opening(p_telegram_id bigint, p_opening_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid; h public.pet_hatch_history%rowtype;
begin
  select id into u from public.game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into h from public.pet_hatch_history
   where user_id=u and (opening_id=p_opening_id or idempotency_key=p_opening_id)
   order by created_at desc limit 1;
  if h.id is null then return jsonb_build_object('status','not_found','openingId',p_opening_id); end if;
  return jsonb_build_object('result',public.pet_hatch_result_json(h),'dashboard',public.get_pet_dashboard(p_telegram_id));
end $$;

grant execute on function public.pet_hatch_result_json(public.pet_hatch_history) to service_role;
grant execute on function public.get_pet_egg_opening(bigint,text) to service_role;

create or replace function public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $function$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed_text text;
  rar text; picked pets%rowtype; existing player_pets%rowtype; prior pet_hatch_history%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0;
begin
  if length(trim(p_idempotency_key))<8 or length(p_idempotency_key)>180 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u::text||':'||p_idempotency_key,0));
  select * into prior from pet_hatch_history
   where user_id=u and (opening_id=p_idempotency_key or idempotency_key=p_idempotency_key)
   order by created_at desc limit 1;
  if prior.id is not null then
    return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
  end if;

  select * into egg from pet_eggs where id=p_egg_id and is_enabled;
  if egg.id is null then raise exception 'EGG_NOT_FOUND'; end if;
  if abs(coalesce((select sum(value::numeric) from jsonb_each_text(egg.rarity_rates)),0)-100)>0.0001 then
    raise exception 'EGG_RATES_INVALID';
  end if;
  select * into inv from player_pet_inventory where user_id=u and item_type='egg' and item_id=p_egg_id for update;
  if inv.id is null or inv.quantity<1 then raise exception 'EGG_NOT_OWNED'; end if;

  seed_text:=forge_random_seed(p_idempotency_key);
  luck:=least(10,coalesce((get_pet_bonuses(u)->>'egg_luck_percent')::numeric,0));
  rar:=roll_rarity_from_rates(egg.rarity_rates,luck);
  select * into picked from pets p where p.is_enabled and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
    order by hashtextextended(p.id::text||seed_text,0) limit 1;
  if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;

  update player_pet_inventory set quantity=quantity-1,updated_at=now() where id=inv.id;
  select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
  if existing.id is not null then
    select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';
    update player_pets set fragments=fragments+frags,updated_at=now() where id=existing.id;
  else
    insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar);
  end if;

  insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key,opening_id,status,completed_at)
    values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key,p_idempotency_key,'completed',now()) returning id into history_id;
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
    values(u,p_telegram_id,'egg',egg.slug,'pet_egg',rar,picked.id,picked.name);
  select * into prior from pet_hatch_history where id=history_id;
  return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
end $function$;

grant execute on function public.hatch_pet_egg(bigint,uuid,text) to service_role;

update public.pet_eggs
set rarity_rates='{"rare":49,"epic":49,"legendary":2}'::jsonb,updated_at=now()
where slug='epic-egg';
update public.pet_eggs
set rarity_rates='{"legendary":70,"ancestral":30}'::jsonb,updated_at=now()
where slug='ancestral-egg';