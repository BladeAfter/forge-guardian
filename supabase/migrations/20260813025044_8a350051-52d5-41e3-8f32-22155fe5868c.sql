CREATE TABLE IF NOT EXISTS public.equipment_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  slot text NOT NULL CHECK (slot IN ('weapon','armor','ring')),
  kind text NOT NULL CHECK (kind IN ('sword','axe','staff','bow','scepter','armor','ring')),
  hero_class text,
  rarity text NOT NULL CHECK (rarity IN ('common','uncommon','rare','epic','legendary')),
  tier int NOT NULL DEFAULT 1,
  image_url text NOT NULL,
  bonus_attack int NOT NULL DEFAULT 0,
  bonus_defense int NOT NULL DEFAULT 0,
  bonus_hp int NOT NULL DEFAULT 0,
  power int NOT NULL DEFAULT 0,
  description text NOT NULL DEFAULT '',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.equipment_templates TO authenticated;
GRANT SELECT ON public.equipment_templates TO anon;
GRANT ALL ON public.equipment_templates TO service_role;
ALTER TABLE public.equipment_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "equipment_templates_read" ON public.equipment_templates;
CREATE POLICY "equipment_templates_read" ON public.equipment_templates
  FOR SELECT TO authenticated, anon USING (is_active);

CREATE TABLE IF NOT EXISTS public.player_equipment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.game_players(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.equipment_templates(id) ON DELETE RESTRICT,
  hero_id uuid,
  level int NOT NULL DEFAULT 1,
  locked boolean NOT NULL DEFAULT false,
  source text NOT NULL DEFAULT 'admin',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS player_equipment_user_idx ON public.player_equipment(user_id);
CREATE INDEX IF NOT EXISTS player_equipment_template_idx ON public.player_equipment(template_id);

GRANT SELECT ON public.player_equipment TO authenticated;
GRANT ALL ON public.player_equipment TO service_role;
ALTER TABLE public.player_equipment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "player_equipment_owner_read" ON public.player_equipment;
CREATE POLICY "player_equipment_owner_read" ON public.player_equipment
  FOR SELECT TO authenticated
  USING (user_id IS NOT NULL AND user_id = auth.uid());

DROP TRIGGER IF EXISTS equipment_templates_touch ON public.equipment_templates;
CREATE TRIGGER equipment_templates_touch BEFORE UPDATE ON public.equipment_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS player_equipment_touch ON public.player_equipment;
CREATE TRIGGER player_equipment_touch BEFORE UPDATE ON public.player_equipment
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DO $seed$
DECLARE
  rarities text[] := ARRAY['common','uncommon','rare','epic','legendary'];
  radj     text[] := ARRAY['Rusted','Guarded','Runic','Shadowfire','Radiant'];
  kinds    text[] := ARRAY['sword','axe','staff','bow','scepter'];
  klass    text[] := ARRAY['warrior','tank','mage','archer','support'];
  wbase    jsonb := jsonb_build_object(
     'sword',   jsonb_build_array('Blade','Longsword','Claymore','Edge'),
     'axe',     jsonb_build_array('Cleaver','Battleaxe','Reaver','Splitter'),
     'staff',   jsonb_build_array('Rod','Staff','Focus','Branch'),
     'bow',     jsonb_build_array('Shortbow','Longbow','Hunterbow','Recurve'),
     'scepter', jsonb_build_array('Wand','Scepter','Sigil','Baton'));
  abase    text[] := ARRAY['Vest','Mail','Cuirass','Plate','Aegis'];
  rbase    text[] := ARRAY['Band','Signet','Loop','Seal','Halo'];
  ri int; ki int; vi int;
  v_rarity text; v_kind text; v_class text; v_name text; v_code text; v_base text;
  atk int; def int; hp int;
BEGIN
  FOR ki IN 1..5 LOOP
    v_kind := kinds[ki];
    v_class := klass[ki];
    FOR ri IN 1..5 LOOP
      v_rarity := rarities[ri];
      FOR vi IN 1..4 LOOP
        v_base := (wbase -> v_kind ->> (vi - 1));
        v_name := radj[ri] || ' ' || v_base;
        v_code := 'eq_' || v_kind || '_' || v_rarity || '_' || vi;
        atk := (ri * 40) + (vi * 8);
        def := (ri * 6) + vi;
        hp  := (ri * 30) + (vi * 5);
        INSERT INTO public.equipment_templates
          (code,name,slot,kind,hero_class,rarity,tier,image_url,bonus_attack,bonus_defense,bonus_hp,power,description)
        VALUES (v_code, v_name, 'weapon', v_kind, v_class, v_rarity, vi,
          '/assets/game/equipment/' || v_kind || '-' || v_rarity || '.png',
          atk, def, hp, atk * 2 + def + hp,
          initcap(v_rarity) || ' ' || v_kind || ' for ' || initcap(v_class) || ' heroes.')
        ON CONFLICT (code) DO NOTHING;
      END LOOP;
    END LOOP;
  END LOOP;

  FOR ri IN 1..5 LOOP
    v_rarity := rarities[ri];
    FOR vi IN 1..5 LOOP
      v_name := radj[ri] || ' ' || abase[vi];
      v_code := 'eq_armor_' || v_rarity || '_' || vi;
      atk := (ri * 5);
      def := (ri * 30) + (vi * 6);
      hp  := (ri * 90) + (vi * 20);
      INSERT INTO public.equipment_templates
        (code,name,slot,kind,hero_class,rarity,tier,image_url,bonus_attack,bonus_defense,bonus_hp,power,description)
      VALUES (v_code, v_name, 'armor', 'armor', NULL, v_rarity, vi,
        '/assets/game/equipment/armor-' || v_rarity || '.png',
        atk, def, hp, atk * 2 + def + hp,
        initcap(v_rarity) || ' armor usable by any hero class.')
      ON CONFLICT (code) DO NOTHING;
    END LOOP;
  END LOOP;

  FOR ri IN 1..5 LOOP
    v_rarity := rarities[ri];
    FOR vi IN 1..5 LOOP
      v_name := radj[ri] || ' ' || rbase[vi];
      v_code := 'eq_ring_' || v_rarity || '_' || vi;
      atk := (ri * 20) + (vi * 4);
      def := (ri * 12) + (vi * 3);
      hp  := (ri * 40) + (vi * 10);
      INSERT INTO public.equipment_templates
        (code,name,slot,kind,hero_class,rarity,tier,image_url,bonus_attack,bonus_defense,bonus_hp,power,description)
      VALUES (v_code, v_name, 'ring', 'ring', NULL, v_rarity, vi,
        '/assets/game/equipment/ring-' || v_rarity || '.png',
        atk, def, hp, atk * 2 + def + hp,
        initcap(v_rarity) || ' ring usable by any hero class.')
      ON CONFLICT (code) DO NOTHING;
    END LOOP;
  END LOOP;
END $seed$;

CREATE OR REPLACE FUNCTION public.get_player_inventory(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; v_chests jsonb; v_eggs jsonb; v_items jsonb;
begin
  select id into u from game_players where telegram_id=p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  v_chests := coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'itemCode',i.item_code,'name',coalesce(c.name,i.item_code),'subtitle',coalesce(c.subtitle,''),'quantity',i.quantity,'rarityRates',coalesce(c.rarity_rates,'{}'::jsonb)) order by i.item_code)
      from player_inventory i left join chest_reward_tables c on c.chest_code=i.item_code
      where i.user_id=u and i.item_type='hero_chest' and i.quantity>0),'[]'::jsonb);

  v_eggs := coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'slug',e.slug,'name',e.name,'image',e.image_url,'quantity',pi.quantity,'rarityRates',e.rarity_rates) order by e.name)
      from player_pet_inventory pi join pet_eggs e on e.id=pi.item_id
      where pi.user_id=u and pi.item_type='egg' and pi.quantity>0),'[]'::jsonb);

  v_items := (
    select coalesce(jsonb_agg(x order by x->>'category', x->>'name'),'[]'::jsonb) from (
      select jsonb_build_object('key','chest:'||i.id,'itemId',i.item_code,'instanceId',i.id,'itemType','chest','category','chests',
        'name',coalesce(c.name,i.item_code),'description',coalesce(c.subtitle,''),'image',null,'rarity',null,
        'quantity',i.quantity,'usable',true,'action','open-chest') as x
      from player_inventory i left join chest_reward_tables c on c.chest_code=i.item_code
      where i.user_id=u and i.item_type='hero_chest' and i.quantity>0
      union all
      select jsonb_build_object('key',i.item_type||':'||i.item_code,'itemId',i.item_code,'instanceId',i.id,'itemType',i.item_type,
        'category',case when i.item_type ilike '%fragment%' then 'fragments' else 'other' end,
        'name',initcap(replace(i.item_code,'_',' ')),'description',initcap(replace(i.item_type,'_',' ')),'image',null,'rarity',null,
        'quantity',i.quantity,'usable',false,'action',null)
      from player_inventory i
      where i.user_id=u and i.item_type<>'hero_chest' and i.quantity>0
      union all
      select jsonb_build_object('key','egg:'||e.id,'itemId',e.id::text,'instanceId',null,'itemType','egg','category','eggs',
        'name',e.name,'description','Pet Egg','image',e.image_url,
        'rarity',(select k from jsonb_each_text(coalesce(e.rarity_rates,'{}'::jsonb)) as t(k,v) order by (v)::numeric desc limit 1),
        'quantity',pi.quantity,'usable',true,'action','hatch')
      from player_pet_inventory pi join pet_eggs e on e.id=pi.item_id
      where pi.user_id=u and pi.item_type='egg' and pi.quantity>0
      union all
      select jsonb_build_object('key','food:'||f.code,'itemId',f.code,'instanceId',null,'itemType','food','category','food',
        'name',f.name,'description','Pet Food','image',f.icon,'rarity',f.rarity,
        'quantity',pf.quantity,'usable',true,'action','feed')
      from player_pet_food pf join pet_food_items f on f.code=pf.food_code
      where pf.user_id=u and pf.quantity>0
      union all
      select jsonb_build_object('key','universal_fragment','itemId','universal_fragment','instanceId',null,'itemType','universal_fragment',
        'category','fragments','name','Universal Fragment','description','Universal Fragment','image',null,'rarity',null,
        'quantity',pi.quantity,'usable',false,'action',null)
      from player_pet_inventory pi
      where pi.user_id=u and pi.item_type='universal_fragment' and pi.item_id is null and pi.quantity>0
      union all
      select jsonb_build_object('key','pet_fragment:'||pp.id,'itemId',pp.pet_id::text,'instanceId',pp.id,'itemType','pet_fragment',
        'category','fragments','name',p.name||' Fragment','description','Pet Fragment','image',p.image_baby_url,'rarity',pp.rarity,
        'quantity',pp.fragments,'usable',false,'action',null)
      from player_pets pp join pets p on p.id=pp.pet_id
      where pp.user_id=u and pp.fragments>0
      union all
      select jsonb_build_object('key','equipment:'||pe.id,'itemId',t.code,'instanceId',pe.id,'itemType','equipment',
        'category','equipment','name',t.name,'description',t.description,'image',t.image_url,'rarity',t.rarity,
        'quantity',1,'usable',false,'action',null,
        'slot',t.slot,'kind',t.kind,'heroClass',t.hero_class,
        'bonusAttack',t.bonus_attack,'bonusDefense',t.bonus_defense,'bonusHp',t.bonus_hp,'power',t.power)
      from player_equipment pe join equipment_templates t on t.id=pe.template_id
      where pe.user_id=u
    ) s
  );

  return jsonb_build_object('chests',v_chests,'eggs',v_eggs,'items',v_items);
end $function$;

REVOKE ALL ON FUNCTION public.get_player_inventory(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_player_inventory(bigint) FROM anon;
REVOKE ALL ON FUNCTION public.get_player_inventory(bigint) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_inventory(bigint) TO service_role;
