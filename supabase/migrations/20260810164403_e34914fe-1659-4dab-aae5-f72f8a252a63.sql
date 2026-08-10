create or replace function public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed bytea; seed_text text; roll numeric;
  cursor_v numeric:=0; k text; rate numeric; rar text; picked pets%rowtype; existing player_pets%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0; allowed text[]:=array[]::text[];
begin
  if length(trim(p_idempotency_key))<8 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if exists(select 1 from pet_hatch_history where idempotency_key=p_idempotency_key and user_id=u) then return get_pet_dashboard(p_telegram_id); end if;
  select * into egg from pet_eggs where id=p_egg_id and is_enabled;
  if egg.id is null then raise exception 'EGG_NOT_FOUND'; end if;
  select * into inv from player_pet_inventory where user_id=u and item_type='egg' and item_id=p_egg_id for update;
  if inv.id is null or inv.quantity<1 then raise exception 'EGG_NOT_OWNED'; end if;
  update player_pet_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;

  seed:=gen_random_bytes(32); seed_text:=encode(digest(seed,'sha256'),'hex');
  luck:=least(10,coalesce((get_pet_bonuses(u)->>'egg_luck_percent')::numeric,0));
  roll:=least(99.999,(('x'||substr(seed_text,1,8))::bit(32)::bigint%1000000)/10000.0+luck);
  foreach k in array array['common','uncommon','rare','epic','legendary','ancestral'] loop
    rate:=coalesce((egg.rarity_rates->>k)::numeric,0);
    if rate>0 then allowed:=allowed||k; cursor_v:=cursor_v+rate; if rar is null and roll<cursor_v then rar:=k; end if; end if;
  end loop;
  if rar is null then rar:=coalesce(allowed[array_length(allowed,1)],'common'); end if;

  select * into picked from pets p where p.is_enabled and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
    order by hashtextextended(p.id::text||seed_text,0) limit 1;
  if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;
  select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
  if existing.id is not null then
    select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';
    update player_pets set fragments=fragments+frags, updated_at=now() where id=existing.id;
  else
    insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar);
  end if;
  insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key)
    values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key) returning id into history_id;
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
    values(u,p_telegram_id,'egg',egg.slug,'pet_egg',rar,picked.id,picked.name);
  return jsonb_build_object('result',jsonb_build_object('historyId',history_id,'petId',picked.id,'name',picked.name,'rarity',rar,'image',picked.image_baby_url,'duplicateFragments',frags),
    'dashboard',get_pet_dashboard(p_telegram_id));
end $$;
