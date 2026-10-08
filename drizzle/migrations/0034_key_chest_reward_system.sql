-- KEY & CHEST REWARD SYSTEM (Eternity / Void / Celestial)
-- Tower keys now open real chests. All rolls happen server-side.

CREATE TABLE IF NOT EXISTS public.key_chest_catalog (
  chest_code text PRIMARY KEY,
  name text NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  rarity text NOT NULL DEFAULT 'rare',
  key_code text NOT NULL,
  draws_min integer NOT NULL DEFAULT 2,
  draws_max integer NOT NULL DEFAULT 2,
  guaranteed_premium integer NOT NULL DEFAULT 0,
  image_url text,
  sort_order integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.key_chest_catalog TO authenticated;
GRANT SELECT ON public.key_chest_catalog TO anon;
GRANT ALL ON public.key_chest_catalog TO service_role;
ALTER TABLE public.key_chest_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS key_chest_catalog_read ON public.key_chest_catalog;
CREATE POLICY key_chest_catalog_read ON public.key_chest_catalog FOR SELECT TO authenticated, anon USING (true);

CREATE TABLE IF NOT EXISTS public.key_chest_reward_pool (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chest_code text NOT NULL REFERENCES public.key_chest_catalog(chest_code) ON DELETE CASCADE,
  reward_type text NOT NULL,
  reward_code text,
  min_amount numeric NOT NULL DEFAULT 1,
  max_amount numeric NOT NULL DEFAULT 1,
  weight numeric NOT NULL DEFAULT 100,
  is_premium boolean NOT NULL DEFAULT false,
  label text NOT NULL DEFAULT '',
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.key_chest_reward_pool TO authenticated;
GRANT ALL ON public.key_chest_reward_pool TO service_role;
ALTER TABLE public.key_chest_reward_pool ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS key_chest_pool_read ON public.key_chest_reward_pool;
CREATE POLICY key_chest_pool_read ON public.key_chest_reward_pool FOR SELECT TO authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.key_chest_open_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  telegram_id bigint,
  chest_code text NOT NULL,
  key_code text NOT NULL,
  rewards jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS key_chest_open_log_user_idx ON public.key_chest_open_log(user_id, created_at DESC);
GRANT SELECT ON public.key_chest_open_log TO authenticated;
GRANT ALL ON public.key_chest_open_log TO service_role;
ALTER TABLE public.key_chest_open_log ENABLE ROW LEVEL SECURITY;

INSERT INTO public.key_chest_catalog(chest_code,name,subtitle,rarity,key_code,draws_min,draws_max,guaranteed_premium,image_url,sort_order)
VALUES
 ('eternity_chest','BAÚ DA ETERNIDADE','Requer 1 Eternity Key · 2 recompensas','rare','eternity_key',2,2,0,'/__l5e/assets-v1/407a3f1a-03ba-4083-b84d-93211f7ecb10/eternity-chest.png',1),
 ('void_chest','BAÚ DO VAZIO','Requer 1 Void Key · 3 recompensas','epic','void_key',3,3,0,'/__l5e/assets-v1/39ea795d-06ae-4444-b586-e687a010fb84/void-chest.png',2),
 ('celestial_chest','BAÚ CELESTIAL','Requer 1 Celestial Key · 3-4 recompensas','legendary','celestial_key',3,4,1,'/__l5e/assets-v1/b8e274b2-1f0a-4de9-9693-8702f557ea8c/celestial-chest.png',3)
ON CONFLICT (chest_code) DO UPDATE SET name=excluded.name, subtitle=excluded.subtitle, rarity=excluded.rarity,
  key_code=excluded.key_code, draws_min=excluded.draws_min, draws_max=excluded.draws_max,
  guaranteed_premium=excluded.guaranteed_premium, image_url=excluded.image_url, sort_order=excluded.sort_order, updated_at=now();

DELETE FROM public.key_chest_reward_pool;
INSERT INTO public.key_chest_reward_pool(chest_code,reward_type,reward_code,min_amount,max_amount,weight,is_premium,label) VALUES
 ('eternity_chest','myth',null,75,150,22,false,'MYTH'),
 ('eternity_chest','universal_fragment',null,5,15,20,false,'FRAGMENTOS UNIVERSAIS'),
 ('eternity_chest','hero_xp',null,3000,8000,18,false,'HERO XP'),
 ('eternity_chest','pet_food','pet_food',10,25,16,false,'COMIDA DE PET'),
 ('eternity_chest','pvp_ticket',null,3,5,14,false,'TICKETS PVP'),
 ('eternity_chest','equipment','rare',1,1,9,false,'EQUIPAMENTO RARO'),
 ('eternity_chest','equipment','epic',1,1,1,true,'EQUIPAMENTO ÉPICO'),
 ('void_chest','myth',null,150,350,20,false,'MYTH'),
 ('void_chest','universal_fragment',null,10,25,18,false,'FRAGMENTOS UNIVERSAIS'),
 ('void_chest','hero_xp',null,8000,15000,16,false,'HERO XP'),
 ('void_chest','pet_food','pet_magic_fruit',20,40,14,false,'COMIDA DE PET'),
 ('void_chest','pvp_ticket',null,5,10,13,false,'TICKETS PVP'),
 ('void_chest','equipment','epic',1,1,8,true,'EQUIPAMENTO ÉPICO'),
 ('void_chest','hero_chest','epic_chest',1,1,6,true,'BAÚ DE EQUIPAMENTO ÉPICO'),
 ('void_chest','hero_fragments',null,10,20,4,false,'FRAGMENTOS DE HERÓI'),
 ('void_chest','equipment','legendary',1,1,1,true,'EQUIPAMENTO LENDÁRIO'),
 ('celestial_chest','myth',null,300,700,18,false,'MYTH'),
 ('celestial_chest','universal_fragment',null,20,50,16,false,'FRAGMENTOS UNIVERSAIS'),
 ('celestial_chest','hero_xp',null,15000,30000,14,false,'HERO XP'),
 ('celestial_chest','pet_food','pet_rare_food',40,80,12,false,'COMIDA DE PET'),
 ('celestial_chest','pvp_ticket',null,10,20,12,false,'TICKETS PVP'),
 ('celestial_chest','equipment','legendary',1,1,9,true,'EQUIPAMENTO LENDÁRIO'),
 ('celestial_chest','hero_chest','legendary_chest',1,1,7,true,'BAÚ DE EQUIPAMENTO LENDÁRIO'),
 ('celestial_chest','equipment','mythic',1,1,4,true,'EQUIPAMENTO MÍTICO'),
 ('celestial_chest','hero_fragments',null,25,50,5,true,'FRAGMENTOS DE HERÓI LENDÁRIOS'),
 ('celestial_chest','hero_chest','legend-chest',1,1,2,true,'INVOCAÇÃO PREMIUM'),
 ('celestial_chest','hero_random','celestial',1,1,0.5,true,'HERÓI CELESTIAL');

CREATE OR REPLACE FUNCTION public.key_chest_grant_hero_xp(p_user uuid, p_amount integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare cfg jsonb := public.hero_progression_config(); v_max int := coalesce((cfg->>'maxLevel')::int,20);
  h public.player_heroes; v_each int; v_count int; v_level int; v_xp int; v_need int;
  out_heroes jsonb := '[]'::jsonb;
begin
  select count(*) into v_count from public.player_heroes
    where user_id = p_user and not coalesce(market_locked,false) and level < v_max;
  if coalesce(v_count,0) = 0 then return jsonb_build_object('heroes','[]'::jsonb,'xp',0); end if;
  v_count := least(v_count, 5);
  v_each := greatest(1, ceil(p_amount::numeric / v_count)::int);
  for h in select * from public.player_heroes
      where user_id = p_user and not coalesce(market_locked,false) and level < v_max
      order by level desc, final_atk desc limit v_count loop
    v_level := greatest(1, coalesce(h.level,1));
    v_xp := greatest(0, coalesce(h.xp,0)) + v_each;
    loop
      v_need := public.hero_xp_to_next(v_level);
      exit when v_level >= v_max or v_need <= 0 or v_xp < v_need;
      v_xp := v_xp - v_need; v_level := v_level + 1;
    end loop;
    if v_level >= v_max then v_xp := 0; end if;
    update public.player_heroes set level = v_level, xp = v_xp, updated_at = now() where id = h.id;
    out_heroes := out_heroes || jsonb_build_array(jsonb_build_object('heroId',h.id,'name',h.name,
      'image',h.image,'xpAwarded',v_each,'level',v_level,'levelBefore',greatest(1,coalesce(h.level,1))));
  end loop;
  return jsonb_build_object('heroes',out_heroes,'xp',v_each * v_count);
end $$;

CREATE OR REPLACE FUNCTION public.key_chest_grant_reward(p_user uuid, p_type text, p_code text, p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare v_qty int := greatest(1, round(coalesce(p_amount,1))::int); v_total int; v_num numeric;
  tpl public.equipment_templates; hc public.hero_catalog; v_id uuid; v_food text; v_after int;
  v_rar text; v_chest public.chest_reward_tables;
begin
  if p_type = 'myth' then
    v_num := v_qty;
    insert into public.myth_balances(user_id, amount) values (p_user, v_num)
      on conflict (user_id) do update set amount = public.myth_balances.amount + excluded.amount;
    insert into public.myth_ledger(user_id, direction, amount, reason)
      values (p_user, 'credit', v_num, 'key_chest_reward');
    return jsonb_build_object('type','myth','quantity',v_qty,'title',v_qty || ' MYTH','rarity','epic');

  elsif p_type = 'universal_fragment' then
    v_total := public.add_universal_fragments(p_user, v_qty);
    return jsonb_build_object('type','universal_fragment','quantity',v_qty,'balance',v_total,
      'title', v_qty || ' FRAGMENTOS UNIVERSAIS','rarity','rare');

  elsif p_type = 'hero_fragments' then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'fragments','fragments',v_qty)
    on conflict (user_id,item_type,item_code) do update
      set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now()
    returning quantity into v_after;
    return jsonb_build_object('type','hero_fragments','quantity',v_qty,'balance',v_after,
      'title', v_qty || ' FRAGMENTOS DE HERÓI','rarity','epic');

  elsif p_type = 'hero_xp' then
    return jsonb_build_object('type','hero_xp','quantity',v_qty,'title','HERO XP +' || v_qty,
      'rarity','rare','detail', public.key_chest_grant_hero_xp(p_user, v_qty));

  elsif p_type = 'pet_food' then
    select code into v_food from public.pet_food_items where code = coalesce(nullif(p_code,''),'pet_food') and enabled;
    if v_food is null then select code into v_food from public.pet_food_items where enabled order by code limit 1; end if;
    if v_food is null then return null; end if;
    insert into public.player_pet_food(user_id,food_code,quantity) values (p_user,v_food,v_qty)
    on conflict (user_id,food_code) do update
      set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
    return jsonb_build_object('type','pet_food','code',v_food,'quantity',v_qty,
      'title', v_qty || 'x COMIDA DE PET','rarity','uncommon');

  elsif p_type = 'pvp_ticket' then
    update public.game_players set pvp_tickets = coalesce(pvp_tickets,0) + v_qty, updated_at = now()
      where id = p_user returning pvp_tickets into v_after;
    return jsonb_build_object('type','pvp_ticket','quantity',v_qty,'balance',v_after,
      'title', v_qty || 'x TICKET PVP','rarity','rare');

  elsif p_type = 'equipment' then
    v_rar := lower(coalesce(nullif(p_code,''),'rare'));
    select * into tpl from public.equipment_templates t where t.is_active and t.rarity = v_rar order by random() limit 1;
    if tpl.id is null and v_rar = 'mythic' then
      select * into tpl from public.equipment_templates t where t.is_active and t.rarity = 'legendary' order by random() limit 1;
    end if;
    if tpl.id is null then
      select * into tpl from public.equipment_templates t where t.is_active order by random() limit 1;
    end if;
    if tpl.id is null then return null; end if;
    insert into public.player_equipment(user_id, template_id, source) values (p_user, tpl.id, 'key_chest')
      returning id into v_id;
    return jsonb_build_object('type','equipment','instanceId',v_id,'code',tpl.code,'name',tpl.name,
      'slot',tpl.slot,'rarity',tpl.rarity,'image',tpl.image_url,'power',tpl.power,'quantity',1,
      'title', upper(tpl.name));

  elsif p_type = 'hero_chest' then
    select * into v_chest from public.chest_reward_tables where chest_code = p_code;
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'hero_chest',p_code,v_qty)
    on conflict (user_id,item_type,item_code) do update
      set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
    return jsonb_build_object('type','hero_chest','code',p_code,'quantity',v_qty,
      'title', coalesce(upper(v_chest.name), upper(replace(p_code,'_',' '))),'rarity','legendary');

  elsif p_type = 'hero_random' then
    select * into hc from public.hero_catalog c
      where coalesce(c.enabled,true) and lower(c.rarity) = lower(coalesce(nullif(p_code,''),'legendary'))
        and not coalesce(c.is_nft_exclusive,false) and not coalesce(c.is_pass_exclusive,false)
        and not coalesce(c.roulette_exclusive,false)
      order by random() limit 1;
    if hc.hero_key is null then return null; end if;
    insert into public.player_heroes(user_id, hero_key, name, rarity, level, image)
      values (p_user, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image)
      returning id into v_id;
    return jsonb_build_object('type','hero','heroId',v_id,'name',hc.name,
      'rarity',public.normalize_hero_rarity(hc.rarity),'image',hc.image,'quantity',1,'title',upper(hc.name));
  end if;
  return null;
end $$;

CREATE OR REPLACE FUNCTION public.open_key_chest(p_telegram_id bigint, p_inventory_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare u uuid; inv public.player_inventory; c public.key_chest_catalog; v_keys int;
  v_draws int; v_ids uuid[] := '{}'; v_need int; e public.key_chest_reward_pool;
  v_rewards jsonb := '[]'::jsonb; v_one jsonb; v_amount numeric;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into inv from public.player_inventory
    where id = p_inventory_item_id and user_id = u and item_type = 'key_chest' for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;
  select * into c from public.key_chest_catalog where chest_code = inv.item_code and enabled;
  if c.chest_code is null then raise exception 'CHEST_NOT_FOUND'; end if;

  select coalesce(quantity,0) into v_keys from public.player_inventory
    where user_id = u and item_type = 'tower_key' and item_code = c.key_code for update;
  if coalesce(v_keys,0) < 1 then raise exception 'KEY_REQUIRED'; end if;

  update public.player_inventory set quantity = quantity - 1, updated_at = now()
    where user_id = u and item_type = 'tower_key' and item_code = c.key_code;
  update public.player_inventory set quantity = quantity - 1, updated_at = now() where id = inv.id;

  v_draws := c.draws_min + floor(random() * (greatest(c.draws_max, c.draws_min) - c.draws_min + 1))::int;

  if coalesce(c.guaranteed_premium,0) > 0 then
    select coalesce(array_agg(id),'{}') into v_ids from (
      select id from public.key_chest_reward_pool
       where chest_code = c.chest_code and enabled and is_premium and weight > 0
       order by -ln(random()) / weight limit c.guaranteed_premium) q;
  end if;
  v_need := greatest(0, v_draws - coalesce(array_length(v_ids,1),0));
  if v_need > 0 then
    select v_ids || coalesce(array_agg(id),'{}') into v_ids from (
      select id from public.key_chest_reward_pool
       where chest_code = c.chest_code and enabled and weight > 0 and not (id = any(v_ids))
       order by -ln(random()) / weight limit v_need) q;
  end if;

  for e in select * from public.key_chest_reward_pool where id = any(v_ids) order by random() loop
    v_amount := e.min_amount + floor(random() * (greatest(e.max_amount, e.min_amount) - e.min_amount + 1));
    v_one := public.key_chest_grant_reward(u, e.reward_type, e.reward_code, v_amount);
    if v_one is not null then
      v_rewards := v_rewards || jsonb_build_array(v_one || jsonb_build_object('premium', e.is_premium, 'label', e.label));
    end if;
  end loop;

  insert into public.key_chest_open_log(user_id, telegram_id, chest_code, key_code, rewards)
  values (u, p_telegram_id, c.chest_code, c.key_code, v_rewards);

  return jsonb_build_object(
    'chest', jsonb_build_object('code',c.chest_code,'name',c.name,'subtitle',c.subtitle,
      'rarity',c.rarity,'image',c.image_url,'keyCode',c.key_code),
    'rewards', v_rewards,
    'inventory', public.get_player_inventory(p_telegram_id));
end $$;

ALTER TABLE public.season_pass_rewards DROP CONSTRAINT IF EXISTS season_pass_rewards_reward_type_check;
ALTER TABLE public.season_pass_rewards ADD CONSTRAINT season_pass_rewards_reward_type_check
  CHECK (reward_type = ANY (ARRAY['fc','hero_chest','pet_egg','pet_food','fragments','pvp_ticket','skin',
    'equipment','hero_random','exclusive_chest','myth','pet_random','nft_equipment','nft_pet','chest',
    'equipment_chest','evolution_pack','key_chest']));

CREATE OR REPLACE FUNCTION public.season_pass_reward_no_fc()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
declare v_code text;
begin
  if new.reward_type = 'fc' then
    v_code := case when coalesce(new.amount,0) <= 300000 then 'eternity_chest'
                   when coalesce(new.amount,0) <= 800000 then 'void_chest'
                   else 'celestial_chest' end;
    new.reward_type := 'key_chest';
    new.reward_code := v_code;
    new.amount := 1;
    new.base_amount := null;
    new.title := (select upper(name) || ' x1' from public.key_chest_catalog where chest_code = v_code);
    new.image_url := (select image_url from public.key_chest_catalog where chest_code = v_code);
  end if;
  return new;
end $$;

DROP TRIGGER IF EXISTS season_pass_rewards_no_fc ON public.season_pass_rewards;
CREATE TRIGGER season_pass_rewards_no_fc BEFORE INSERT OR UPDATE ON public.season_pass_rewards
FOR EACH ROW EXECUTE FUNCTION public.season_pass_reward_no_fc();

UPDATE public.season_pass_rewards SET reward_type = 'fc' WHERE reward_type = 'fc';