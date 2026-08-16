-- 1. Key catalog (display-only collectibles for now)
CREATE TABLE IF NOT EXISTS public.tower_key_catalog (
  code text PRIMARY KEY,
  name text NOT NULL,
  rarity text NOT NULL,
  description text NOT NULL DEFAULT '',
  image_url text,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.tower_key_catalog TO authenticated;
GRANT ALL ON public.tower_key_catalog TO service_role;
ALTER TABLE public.tower_key_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tower_key_catalog_read" ON public.tower_key_catalog;
CREATE POLICY "tower_key_catalog_read" ON public.tower_key_catalog FOR SELECT TO authenticated USING (true);

INSERT INTO public.tower_key_catalog(code,name,rarity,description,image_url,sort_order) VALUES
  ('eternity_key','Eternity Key','rare','A mysterious tower key. Its purpose will be revealed soon.','/assets/game/ui/eternity-key.png',1),
  ('void_key','Void Key','epic','A corrupted key infused with void energy. Its purpose will be revealed soon.','/assets/game/ui/void-key.png',2),
  ('celestial_key','Celestial Key','legendary','A sacred key radiating celestial power. Its purpose will be revealed soon.','/assets/game/ui/celestial-key.png',3)
ON CONFLICT (code) DO UPDATE SET name=excluded.name, rarity=excluded.rarity,
  description=excluded.description, image_url=excluded.image_url, sort_order=excluded.sort_order;

-- 2. Key drop chances per floor band (percent). Replays pay half.
CREATE OR REPLACE FUNCTION public.tower_key_chances(p_floor integer, p_first boolean)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select jsonb_build_object(
    'eternity_key', round((case
        when p_floor <= 10 then 4.0 when p_floor <= 25 then 6.0 when p_floor <= 50 then 8.0
        when p_floor <= 75 then 6.0 else 4.0 end) * (case when p_first then 1 else 0.5 end), 2),
    'void_key', round((case
        when p_floor <= 10 then 0.0 when p_floor <= 25 then 1.0 when p_floor <= 50 then 2.0
        when p_floor <= 75 then 4.0 else 6.0 end) * (case when p_first then 1 else 0.5 end), 2),
    'celestial_key', round((case
        when p_floor <= 25 then 0.0 when p_floor <= 50 then 0.3
        when p_floor <= 75 then 1.0 else 2.5 end) * (case when p_first then 1 else 0.5 end), 2)
  );
$$;

-- 3. Reworked reward table (much stronger, scales with floor)
CREATE OR REPLACE FUNCTION public.tower_floor_rewards(p_floor integer, p_first boolean)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select jsonb_build_object(
    'fragments', greatest(3, floor((12 + p_floor * 1.8) * (case when p_first then 1 else 0.5 end))::int),
    'heroXp',    greatest(80, floor((500 + p_floor * 160) * (case when p_first then 1 else 0.5 end))::int),
    'petFood',   case when p_first and p_floor % 5 = 0 then 15 when p_first then 5 else 2 end,
    'heroChest', case when p_first and p_floor % 5 = 0 then 1 when p_floor % 10 = 0 then 1 else 0 end,
    'chestCode', case
        when p_floor >= 76 then 'legendary_chest' when p_floor >= 51 then 'epic_chest'
        when p_floor >= 26 then 'rare_chest' when p_floor >= 11 then 'uncommon_chest' else 'common_chest' end,
    'forgeCoins', greatest(2000, floor((4000 + p_floor * 1200) * (case when p_first then 1 else 0.5 end))::int),
    'universalFragments', case
        when not p_first then 0
        when p_floor >= 76 then 6 when p_floor >= 51 then 4 when p_floor >= 26 then 3
        when p_floor >= 11 then 2 else (case when p_floor % 5 = 0 then 1 else 0 end) end,
    'towerKey', 0,
    'keyChances', public.tower_key_chances(p_floor, p_first)
  );
$$;

-- 4. Milestone rewards (first clear only)
CREATE OR REPLACE FUNCTION public.tower_milestone_rewards(p_floor integer)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select case p_floor
    when 10 then jsonb_build_object('forgeCoins',50000,'universalFragments',0,'chestCode',null,'keys',jsonb_build_object('eternity_key',1))
    when 25 then jsonb_build_object('forgeCoins',100000,'universalFragments',15,'chestCode',null,'keys',jsonb_build_object('void_key',1))
    when 50 then jsonb_build_object('forgeCoins',150000,'universalFragments',0,'chestCode','epic_chest','keys',jsonb_build_object('void_key',1))
    when 75 then jsonb_build_object('forgeCoins',250000,'universalFragments',25,'chestCode',null,'keys',jsonb_build_object('celestial_key',1))
    when 100 then jsonb_build_object('forgeCoins',500000,'universalFragments',0,'chestCode','legendary_chest','keys',jsonb_build_object('celestial_key',1))
    else null end;
$$;

-- 5. Granting: rewards + random key drops + milestones
CREATE OR REPLACE FUNCTION public.tower_grant_rewards(p_user uuid, p_floor integer, p_first boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare r jsonb := public.tower_floor_rewards(p_floor, p_first); v_food text; v_gear jsonb;
  v_keys jsonb := '{}'::jsonb; v_chances jsonb := r->'keyChances'; v_code text; v_qty int;
  v_ms jsonb; v_uni int; v_fc numeric;
begin
  if (r->>'fragments')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'fragments','fragments',(r->>'fragments')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  if (r->>'heroChest')::int > 0 then
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'hero_chest',coalesce(r->>'chestCode','common_chest'),(r->>'heroChest')::int)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end if;

  v_fc := coalesce((r->>'forgeCoins')::numeric,0);
  v_uni := coalesce((r->>'universalFragments')::int,0);

  if (r->>'petFood')::int > 0 then
    select code into v_food from public.pet_food_items order by coalesce(nullif(code,''),'') limit 1;
    if v_food is not null then
      insert into public.player_pet_food(user_id,food_code,quantity)
      values (p_user,v_food,(r->>'petFood')::int)
      on conflict (user_id,food_code) do update set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
    end if;
  end if;

  -- rare key drops (server-side roll only)
  for v_code in select k from public.tower_key_catalog order by sort_order loop
    if random() * 100 < coalesce((v_chances->>v_code)::numeric, 0) then
      v_keys := v_keys || jsonb_build_object(v_code, coalesce((v_keys->>v_code)::int,0) + 1);
    end if;
  end loop;

  -- milestones
  if p_first then
    v_ms := public.tower_milestone_rewards(p_floor);
    if v_ms is not null then
      v_fc := v_fc + coalesce((v_ms->>'forgeCoins')::numeric,0);
      v_uni := v_uni + coalesce((v_ms->>'universalFragments')::int,0);
      if coalesce(v_ms->>'chestCode','') <> '' then
        insert into public.player_inventory(user_id,item_type,item_code,quantity)
        values (p_user,'hero_chest',v_ms->>'chestCode',1)
        on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
      end if;
      for v_code, v_qty in select key, value::int from jsonb_each_text(coalesce(v_ms->'keys','{}'::jsonb)) loop
        v_keys := v_keys || jsonb_build_object(v_code, coalesce((v_keys->>v_code)::int,0) + v_qty);
      end loop;
      r := r || jsonb_build_object('milestone', v_ms);
    end if;
  end if;

  for v_code, v_qty in select key, value::int from jsonb_each_text(v_keys) loop
    insert into public.player_inventory(user_id,item_type,item_code,quantity)
    values (p_user,'tower_key',v_code,v_qty)
    on conflict (user_id,item_type,item_code) do update set quantity = public.player_inventory.quantity + excluded.quantity, updated_at = now();
  end loop;

  if v_fc > 0 then
    update public.game_players set forge_coins = coalesce(forge_coins,0) + v_fc, updated_at = now() where id = p_user;
  end if;
  if v_uni > 0 then perform public.add_universal_fragments(p_user, v_uni); end if;

  v_gear := public.tower_roll_equipment_drop(p_user, p_floor, p_first);
  r := r || jsonb_build_object('equipment', v_gear, 'keys', v_keys,
    'forgeCoins', v_fc, 'universalFragments', v_uni,
    'towerKey', (select coalesce(sum(value::int),0) from jsonb_each_text(v_keys)));
  return r;
end $$;