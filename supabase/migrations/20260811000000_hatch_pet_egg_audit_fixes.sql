-- Audit fix: hatch_pet_egg was missing a PLAYER_NOT_FOUND guard (unlike open_hero_chest),
-- which let an invalid telegram_id fall through to a misleading EGG_NOT_OWNED error instead
-- of failing fast. The rest of the function is already atomic: everything (inventory
-- decrement, pet insert/upgrade, hatch history insert, reward log) runs inside the single
-- implicit transaction of this SECURITY DEFINER function, so any exception (including the
-- new guard, or the pre-existing NO_ELIGIBLE_PET path) rolls back the whole hatch, and the
-- unique idempotency_key column plus the FOR UPDATE row locks on game_players and
-- player_pet_inventory prevent concurrent double-spends/double-hatches for the same egg or
-- the same idempotency key.
create or replace function public.hatch_pet_egg(p_telegram_id bigint, p_egg_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u uuid; egg pet_eggs%rowtype; inv player_pet_inventory%rowtype; seed_text text;
  rar text; picked pets%rowtype; existing player_pets%rowtype;
  frags int:=0; history_id uuid; luck numeric:=0;
begin
  if length(trim(p_idempotency_key))<8 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if exists(select 1 from pet_hatch_history where idempotency_key=p_idempotency_key and user_id=u) then return get_pet_dashboard(p_telegram_id); end if;
  select * into egg from pet_eggs where id=p_egg_id and is_enabled;
  if egg.id is null then raise exception 'EGG_NOT_FOUND'; end if;
  select * into inv from player_pet_inventory where user_id=u and item_type='egg' and item_id=p_egg_id for update;
  if inv.id is null or inv.quantity<1 then raise exception 'EGG_NOT_OWNED'; end if;
  update player_pet_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;

  seed_text:=forge_random_seed(p_idempotency_key);
  luck:=least(10,coalesce((get_pet_bonuses(u)->>'egg_luck_percent')::numeric,0));
  rar:=roll_rarity_from_rates(egg.rarity_rates,luck);

  select * into picked from pets p where p.is_enabled and (egg.allowed_pet_categories is null or egg.allowed_pet_categories ? p.category)
    order by random() limit 1;
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
end $function$;

-- Rarity configuration audit: bring epic egg legendary odds to 2% and make the
-- ancestral egg a guaranteed-epic-or-legendary drop split 70/30, per the spec.
update pet_eggs set rarity_rates='{"uncommon":23,"rare":50,"epic":25,"legendary":2}'::jsonb, updated_at=now()
  where slug='epic-egg';
update pet_eggs set rarity_rates='{"epic":70,"legendary":30}'::jsonb, updated_at=now()
  where slug='ancestral-egg';
