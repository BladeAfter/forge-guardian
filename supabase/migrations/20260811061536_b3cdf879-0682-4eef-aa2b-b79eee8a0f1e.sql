ALTER TABLE public.pet_hatch_history
  ADD COLUMN IF NOT EXISTS is_new boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS result_player_pet_id uuid;

-- Backfill: historical rows with no duplicate fragments were new pets.
UPDATE public.pet_hatch_history SET is_new = true WHERE duplicate_fragments = 0 AND is_new = false;

CREATE OR REPLACE FUNCTION public.pet_hatch_result_json(p_history pet_hatch_history)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'openingId', p_history.opening_id,
    'historyId', p_history.id,
    'status', p_history.status,
    'petId', p.id,
    'playerPetId', p_history.result_player_pet_id,
    'resultType', case when p_history.is_new then 'new_pet' else 'duplicate' end,
    'isNew', p_history.is_new,
    'name', p.name,
    'rarity', lower(trim(p_history.result_rarity)),
    'image', p.image_baby_url,
    'duplicateFragments', p_history.duplicate_fragments,
    'fragmentsReceived', p_history.duplicate_fragments,
    'createdAt', p_history.created_at,
    'completedAt', p_history.completed_at
  )
  from public.pets p
  where p.id = p_history.result_pet_id
$function$;

CREATE OR REPLACE FUNCTION public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed_text text;
  rar text; picked pets%rowtype; existing player_pets%rowtype; prior pet_hatch_history%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0; new_pet_id uuid; is_new_pet boolean:=false;
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
  rar:=lower(trim(roll_rarity_from_rates(egg.rarity_rates,luck)));
  select * into picked from pets p where p.is_enabled and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
    order by hashtextextended(p.id::text||seed_text,0) limit 1;
  if picked.id is null then raise exception 'NO_ELIGIBLE_PET'; end if;

  update player_pet_inventory set quantity=quantity-1,updated_at=now() where id=inv.id;

  -- Ownership check is scoped to this player only (never the global catalog).
  select * into existing from player_pets where user_id=u and pet_id=picked.id for update;
  if existing.id is not null then
    select coalesce((value->>rar)::int,10) into frags from pet_settings where key='duplicate_fragments';
    update player_pets set fragments=fragments+frags,updated_at=now() where id=existing.id;
    new_pet_id:=existing.id;
    is_new_pet:=false;
  else
    insert into player_pets(user_id,pet_id,rarity) values(u,picked.id,rar) returning id into new_pet_id;
    frags:=0;
    is_new_pet:=true;
  end if;

  insert into pet_hatch_history(user_id,egg_id,result_pet_id,result_rarity,duplicate_fragments,seed_hash,idempotency_key,opening_id,status,completed_at,is_new,result_player_pet_id)
    values(u,egg.id,picked.id,rar,frags,seed_text,p_idempotency_key,p_idempotency_key,'completed',now(),is_new_pet,new_pet_id) returning id into history_id;
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name)
    values(u,p_telegram_id,'egg',egg.slug,'pet_egg',rar,picked.id,picked.name);
  select * into prior from pet_hatch_history where id=history_id;
  return jsonb_build_object('result',pet_hatch_result_json(prior),'dashboard',get_pet_dashboard(p_telegram_id));
end $function$;

REVOKE ALL ON FUNCTION public.hatch_pet_egg(bigint,uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_hatch_result_json(pet_hatch_history) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hatch_pet_egg(bigint,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_hatch_result_json(pet_hatch_history) TO service_role;