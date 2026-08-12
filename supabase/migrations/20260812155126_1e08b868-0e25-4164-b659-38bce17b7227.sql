CREATE OR REPLACE FUNCTION public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed_text text;
  rar text; picked pets%rowtype; picked_id uuid; existing player_pets%rowtype; prior pet_hatch_history%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0; new_pet_id uuid; is_new_pet boolean:=false; has_pool boolean;
  allowed text[];
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
  rar:=public.normalize_pet_rarity(roll_rarity_from_rates(egg.rarity_rates,luck));

  -- only rarities the egg itself actually offers may ever be delivered
  select array_agg(public.normalize_pet_rarity(k)) into allowed
    from jsonb_each_text(egg.rarity_rates) as t(k, v) where v::numeric > 0;
  if allowed is null or array_length(allowed,1) = 0 then raise exception 'EGG_RATES_INVALID'; end if;

  select exists(select 1 from reward_pet_pool rp join pets p on p.id=rp.pet_id
     where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled) into has_pool;

  if has_pool then
    -- Stage 2: only pets whose OWN template rarity equals the rolled rarity.
    picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
    if picked_id is null then
      select p.rarity into rar from reward_pet_pool rp join pets p on p.id=rp.pet_id
        where rp.source_type='EGG' and rp.source_key=egg.id::text and rp.enabled and p.is_enabled
          and p.rarity = any(allowed)
        order by abs(pet_rarity_order(p.rarity) - pet_rarity_order(rar)), pet_rarity_order(p.rarity) desc limit 1;
      picked_id := pick_pet_for_source('EGG', egg.id::text, rar, seed_text);
    end if;
    select * into picked from pets where id = picked_id;
  else
    -- Legacy eggs without an explicit pool: still restricted to the rolled rarity.
    select * into picked from pets p
      where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = rar
        and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
      order by hashtextextended(p.id::text||seed_text,0) limit 1;
    if picked.id is null then
      select p.rarity into rar from pets p
        where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = any(allowed)
          and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
        order by abs(pet_rarity_order(p.rarity) - pet_rarity_order(rar)), pet_rarity_order(p.rarity) desc limit 1;
      select * into picked from pets p
        where p.is_enabled and p.availability_type = 'NORMAL' and p.rarity = rar
          and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
        order by hashtextextended(p.id::text||seed_text,0) limit 1;
    end if;
  end if;
  if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;
  rar := picked.rarity; -- the pet defines the rarity, never the roll

  update player_pet_inventory set quantity=quantity-1,updated_at=now() where id=inv.id;

  select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
  if existing.id is not null then
    select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';
    update player_pets set fragments=fragments+frags,updated_at=now() where id=existing.id;
    new_pet_id:=existing.id; is_new_pet:=false;
  else
    insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar) returning id into new_pet_id;
    frags:=0; is_new_pet:=true;
  end if;

  insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key,opening_id,status,completed_at,is_new,result_player_pet_id)
    values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key,p_idempotency_key,'completed',now(),is_new_pet,new_pet_id) returning id into history_id;
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
    values(u,p_telegram_id,'egg',egg.slug,'pet_egg',rar,picked.id,picked.name);
  select * into prior from pet_hatch_history where id=history_id;
  return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
end $$;