ALTER TABLE public.calendar_chest_open_history
  ADD COLUMN IF NOT EXISTS result_hero_key text,
  ADD COLUMN IF NOT EXISTS result_hero_name text,
  ADD COLUMN IF NOT EXISTS result_hero_image text;

ALTER TABLE public.calendar_chest_open_history ALTER COLUMN result_hero_id DROP NOT NULL;

UPDATE public.calendar_chest_open_history h
SET result_hero_key = coalesce(h.result_hero_key, ph.hero_key),
    result_hero_name = coalesce(h.result_hero_name, ph.name),
    result_hero_image = coalesce(h.result_hero_image, ph.image)
FROM public.player_heroes ph
WHERE ph.id = h.result_hero_id
  AND (h.result_hero_key IS NULL OR h.result_hero_name IS NULL);

ALTER TABLE public.calendar_chest_open_history
  DROP CONSTRAINT calendar_chest_open_history_result_hero_id_fkey;
ALTER TABLE public.calendar_chest_open_history
  ADD CONSTRAINT calendar_chest_open_history_result_hero_id_fkey
  FOREIGN KEY (result_hero_id) REFERENCES public.player_heroes(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.open_hero_chest(p_telegram_id bigint, p_inventory_item_id uuid, p_source text DEFAULT 'calendar')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
declare
  u uuid; inv player_inventory%rowtype; cfg chest_reward_tables%rowtype;
  rar text; allowed text[]; hero record; pick record;
  basea numeric; baseh int; seed int; new_id uuid; open_no int; key text; fallback_from text;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hero_chest:'||u::text,0));

  select * into inv from player_inventory where id=p_inventory_item_id and user_id=u for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;

  select * into cfg from chest_reward_tables where chest_code=inv.item_code and enabled;
  if cfg.chest_code is null then raise exception 'CHEST_NOT_CONFIGURED'; end if;

  seed:=(random()*1000000)::int;
  select r.rarity, r.allowed into rar, allowed from roll_chest_rarity(cfg) r;
  select * into pick from roll_hero_for_rarity(rar,allowed);
  hero:=pick.hero; rar:=pick.final_rarity; fallback_from:=pick.fallback_from;

  basea:=round((case rar when 'ancestral' then 3.05 when 'legendary' then 2.68 when 'epic' then 2.395 when 'rare' then 2.165 when 'uncommon' then 1.975 else 1.875 end)*(.95+(random()*100)::int/1000.0),3);
  baseh:=round((case rar when 'ancestral' then 340 when 'legendary' then 280 when 'epic' then 220 when 'rare' then 170 when 'uncommon' then 130 else 100 end)*(.95+(random()*100)::int/1000.0));

  select count(*)+1 into open_no from calendar_chest_open_history where inventory_item_id=inv.id;
  key:='chest_open:'||inv.id||':'||open_no;

  update player_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;
  insert into player_heroes(user_id,hero_key,name,rarity,level,image,base_atk,base_hp,attribute_seed)
    values(u,hero.hero_key,hero.name,rar,1,hero.image,basea,baseh,seed) returning id into new_id;
  insert into calendar_chest_open_history(user_id,inventory_item_id,result_hero_id,result_rarity,idempotency_key,result_hero_key,result_hero_name,result_hero_image)
    values(u,inv.id,new_id,rar,key,hero.hero_key,hero.name,hero.image);
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name,fallback_from)
    values(u,p_telegram_id,coalesce(nullif(p_source,''),'calendar'),inv.item_code,'hero_chest',rar,new_id,hero.name,fallback_from);

  return jsonb_build_object('hero',jsonb_build_object('id',new_id,'name',hero.name,'image',hero.image,'rarity',rar,'level',1,'baseAtk',basea,'baseHp',baseh),
    'chest',jsonb_build_object('code',cfg.chest_code,'name',cfg.name,'subtitle',cfg.subtitle),
    'inventory',get_player_inventory(p_telegram_id));
end
$fn$;