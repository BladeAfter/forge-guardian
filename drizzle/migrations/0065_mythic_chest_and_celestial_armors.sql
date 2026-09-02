-- 🟣 Baú Mítico (tier acima do Lendário) + armaduras Míticas e Celestiais reais.
ALTER TABLE public.equipment_templates DROP CONSTRAINT IF EXISTS equipment_templates_rarity_check;
ALTER TABLE public.equipment_templates ADD CONSTRAINT equipment_templates_rarity_check
  CHECK (rarity = ANY (ARRAY['common','uncommon','rare','epic','legendary','mythic','celestial','nft_exclusive']));

CREATE OR REPLACE FUNCTION public.roll_chest_rarity(
  p_common numeric DEFAULT 0, p_uncommon numeric DEFAULT 0, p_rare numeric DEFAULT 0,
  p_epic numeric DEFAULT 0, p_legendary numeric DEFAULT 0, p_ancestral numeric DEFAULT 0,
  p_mythic numeric DEFAULT 0, p_celestial numeric DEFAULT 0)
RETURNS TABLE(rarity text, allowed text[]) LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $function$
declare
  keys text[] := array['common','uncommon','rare','epic','legendary','ancestral','mythic','celestial'];
  vals numeric[] := array[coalesce(p_common,0),coalesce(p_uncommon,0),coalesce(p_rare,0),coalesce(p_epic,0),
                          coalesce(p_legendary,0),coalesce(p_ancestral,0),coalesce(p_mythic,0),coalesce(p_celestial,0)];
  total numeric := 0; cursor_v numeric := 0; roll numeric; i int; picked text; allow text[] := array[]::text[];
begin
  for i in 1..8 loop
    if vals[i] < 0 then raise exception 'CHEST_RATES_INVALID'; end if;
    total := total + vals[i];
  end loop;
  if abs(total - 100) > 0.01 then raise exception 'CHEST_RATES_SUM_INVALID'; end if;

  roll := random() * total;
  for i in 1..8 loop
    if vals[i] > 0 then
      allow := allow || keys[i];
      cursor_v := cursor_v + vals[i];
      if picked is null and roll < cursor_v then picked := keys[i]; end if;
    end if;
  end loop;

  rarity := coalesce(picked, allow[array_length(allow,1)], 'common');
  allowed := allow;
  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.open_hero_chest(p_telegram_id bigint, p_inventory_item_id uuid, p_source text DEFAULT 'calendar'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare
  u uuid; inv player_inventory%rowtype; cfg chest_reward_tables%rowtype;
  rar text; allowed text[]; hero record; pick record;
  basea numeric; baseh numeric; seed int; new_id uuid; open_no int; key text; fallback_from text;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hero_chest:'||u::text,0));

  select * into inv from player_inventory where id=p_inventory_item_id and user_id=u for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;

  select * into cfg from chest_reward_tables where chest_code=inv.item_code and enabled;
  if cfg.chest_code is null then raise exception 'CHEST_NOT_CONFIGURED'; end if;

  seed:=(random()*1000000)::int;
  select r.rarity, r.allowed into rar, allowed from roll_chest_rarity(
    coalesce((cfg.rarity_rates->>'common')::numeric,0),
    coalesce((cfg.rarity_rates->>'uncommon')::numeric,0),
    coalesce((cfg.rarity_rates->>'rare')::numeric,0),
    coalesce((cfg.rarity_rates->>'epic')::numeric,0),
    coalesce((cfg.rarity_rates->>'legendary')::numeric,0),
    coalesce((cfg.rarity_rates->>'ancestral')::numeric,0),
    coalesce((cfg.rarity_rates->>'mythic')::numeric,0),
    coalesce((cfg.rarity_rates->>'celestial')::numeric,0)
  ) r;

  select * into pick from roll_hero_for_rarity(rar,allowed);
  hero:=pick.hero; rar:=pick.final_rarity; fallback_from:=pick.fallback_from;

  select count(*)+1 into open_no from calendar_chest_open_history where inventory_item_id=inv.id;
  key:='chest_open:'||inv.id||':'||open_no;

  update player_inventory set quantity=quantity-1, updated_at=now() where id=inv.id;
  insert into player_heroes(user_id,hero_key,name,rarity,level,image,attribute_seed)
    values(u,hero.hero_key,hero.name,rar,1,hero.image,seed) returning id into new_id;
  select ph.base_atk, ph.base_hp into basea, baseh from player_heroes ph where ph.id=new_id;
  insert into calendar_chest_open_history(user_id,inventory_item_id,result_hero_id,result_rarity,idempotency_key,result_hero_key,result_hero_name,result_hero_image)
    values(u,inv.id,new_id,rar,key,hero.hero_key,hero.name,hero.image);
  insert into reward_open_logs(user_id,telegram_id,source,item_key,item_type,rolled_rarity,reward_id,reward_name,fallback_from)
    values(u,p_telegram_id,coalesce(nullif(p_source,''),'calendar'),inv.item_code,'hero_chest',rar,new_id,hero.name,fallback_from);

  return jsonb_build_object('hero',jsonb_build_object('id',new_id,'name',hero.name,'image',hero.image,'rarity',rar,'level',1,'baseAtk',basea,'baseHp',baseh),
    'chest',jsonb_build_object('code',cfg.chest_code,'name',cfg.name,'subtitle',cfg.subtitle),
    'inventory',get_player_inventory(p_telegram_id));
end;
$function$;

INSERT INTO public.chest_reward_tables(chest_code, name, subtitle, rarity_rates, enabled)
VALUES ('mythic_chest', 'Baú Mítico', 'Mítico', '{"legendary": 40, "mythic": 60}'::jsonb, true)
ON CONFLICT (chest_code) DO UPDATE
  SET name = EXCLUDED.name, subtitle = EXCLUDED.subtitle,
      rarity_rates = EXCLUDED.rarity_rates, enabled = true, updated_at = now();

INSERT INTO public.equipment_templates(code, name, slot, kind, rarity, tier, image_url,
  bonus_attack, bonus_defense, bonus_hp, power, description, is_active)
VALUES
  ('eq_armor_mythic_1','Mythic Voidplate','armor','armor','mythic',6,'/assets/game/equipment/armor-mythic.jpg',40,300,850,1180,'Placa mitica forjada em obsidiana viva.',true),
  ('eq_armor_mythic_2','Mythic Runeplate','armor','armor','mythic',6,'/assets/game/equipment/armor-mythic.jpg',44,315,890,1240,'Runas miticas selam o portador contra a morte.',true),
  ('eq_armor_mythic_3','Mythic Doomplate','armor','armor','mythic',6,'/assets/game/equipment/armor-mythic.jpg',48,330,930,1300,'A armadura dos campeoes miticos.',true),
  ('eq_armor_celestial_1','Celestial Aegis','armor','armor','celestial',7,'/assets/game/equipment/armor-celestial.jpg',60,400,1150,1620,'Egide celestial coroada por asas divinas.',true),
  ('eq_armor_celestial_2','Celestial Sovereign Plate','armor','armor','celestial',7,'/assets/game/equipment/armor-celestial.jpg',66,420,1200,1700,'A placa dos soberanos celestiais de Mythreon.',true)
ON CONFLICT (code) DO UPDATE
  SET name = EXCLUDED.name, rarity = EXCLUDED.rarity, tier = EXCLUDED.tier,
      image_url = EXCLUDED.image_url, bonus_attack = EXCLUDED.bonus_attack,
      bonus_defense = EXCLUDED.bonus_defense, bonus_hp = EXCLUDED.bonus_hp,
      power = EXCLUDED.power, description = EXCLUDED.description, is_active = true, updated_at = now();

CREATE OR REPLACE FUNCTION public.admin_premium_offer_metrics(p_admin_id bigint, p_offer_id text DEFAULT 'CELESTIAL_MYSTERY_PACK'::text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v jsonb; v_offer text := upper(btrim(COALESCE(p_offer_id,'CELESTIAL_MYSTERY_PACK')));
        v_count integer := 0; v_ton numeric := 0;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
      'offerId', v_offer,
      'impressions', count(*),
      'uniquePlayers', count(DISTINCT user_id),
      'dismissed', count(*) FILTER (WHERE dismissed_at IS NOT NULL),
      'clicked', count(*) FILTER (WHERE clicked_at IS NOT NULL),
      'purchaseIntents', count(*) FILTER (WHERE purchased_at IS NOT NULL),
      'today', count(*) FILTER (WHERE impression_date = public.premium_offer_day_key()))
    INTO v FROM public.premium_offer_impressions WHERE offer_id = v_offer;

  IF v_offer = 'CELESTIAL_SOVEREIGN_PACK' THEN
    SELECT count(*), COALESCE(round(SUM(price_ton),9),0) INTO v_count, v_ton
      FROM public.sovereign_pack_purchases WHERE status IN ('paid','delivered');
  ELSIF v_offer = 'CELESTIAL_MYSTERY_PACK' THEN
    SELECT count(*), COALESCE(round(SUM(price_ton),9),0) INTO v_count, v_ton
      FROM public.celestial_pack_purchases WHERE status IN ('paid','delivered');
  END IF;

  RETURN COALESCE(v,'{}'::jsonb) || jsonb_build_object('confirmedPurchases', v_count, 'tonCollected', v_ton);
END $function$;

CREATE OR REPLACE FUNCTION public.celestial_pack_deliver(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE o public.celestial_pack_purchases; c public.celestial_pack_config;
        hc public.hero_catalog; np public.nft_pets;
        v_hero uuid; v_delivery jsonb := '{}'::jsonb; v_weapons jsonb := '[]'::jsonb;
        v_armors jsonb := '[]'::jsonb; v_random jsonb := '[]'::jsonb;
        r record; v_peq uuid; v_assign jsonb; v_pick jsonb; v_pool jsonb; i integer;
BEGIN
  SELECT * INTO o FROM public.celestial_pack_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'CELESTIAL_PACK_ORDER_NOT_FOUND'; END IF;
  IF o.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'alreadyDelivered', true, 'purchaseId', o.id, 'delivery', o.delivery);
  END IF;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'CELESTIAL_PACK_NOT_PAID'; END IF;
  c := public.celestial_pack_settings();

  SELECT * INTO hc FROM public.hero_catalog h
   WHERE lower(h.rarity) = 'celestial' AND h.enabled
     AND NOT EXISTS (SELECT 1 FROM public.player_heroes ph WHERE ph.hero_key = h.hero_key)
   ORDER BY random() LIMIT 1;
  IF hc.hero_key IS NULL THEN RAISE EXCEPTION 'CELESTIAL_HERO_SOLD_OUT'; END IF;
  INSERT INTO public.player_heroes(user_id, hero_key, name, rarity, level, image,
      mining_daily_myth, mining_ton_override, mining_pending_reveal, mining_last_at, premium_source)
  VALUES (o.user_id, hc.hero_key, hc.name, public.normalize_hero_rarity(hc.rarity), 1, hc.image,
      0, 0, true, now(), 'CELESTIAL_PACK')
  RETURNING id INTO v_hero;
  INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id, mining_pending_reveal)
  VALUES (o.user_id, o.id, 'hero', hc.hero_key, v_hero, true);
  v_delivery := v_delivery || jsonb_build_object('hero', jsonb_build_object(
    'id', v_hero, 'heroKey', hc.hero_key, 'name', hc.name, 'miningStatus', 'MINING_TO_BE_REVEALED'));

  SELECT * INTO np FROM public.nft_pets
   WHERE owner_user_id IS NULL AND status <> 'BURNED'
   ORDER BY for_sale ASC, created_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF np.id IS NULL THEN RAISE EXCEPTION 'CELESTIAL_PACK_NFT_PET_UNAVAILABLE'; END IF;
  UPDATE public.nft_pets
     SET daily_yield_ton = 0, daily_yield_myth = 0, mining_pending_reveal = true,
         mining_revealed_at = NULL, updated_at = now()
   WHERE id = np.id;
  v_assign := public.nft_assign_unit(np.id, o.user_id, 'celestial_pack');
  INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id, mining_pending_reveal)
  VALUES (o.user_id, o.id, 'nft_pet', np.unique_instance_id, np.id, true);
  v_delivery := v_delivery || jsonb_build_object('nftPet', v_assign || jsonb_build_object(
    'nftPetId', np.id, 'miningStatus', 'MINING_TO_BE_REVEALED'));

  IF COALESCE(o.fc_snapshot, 0) > 0 THEN
    UPDATE public.game_players SET forge_coins = COALESCE(forge_coins,0) + o.fc_snapshot, updated_at = now()
     WHERE id = o.user_id;
    v_delivery := v_delivery || jsonb_build_object('forgeCoins', o.fc_snapshot);
  END IF;

  IF COALESCE(c.legendary_chests,0) > 0 THEN
    INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
    VALUES (o.user_id, 'hero_chest', 'legendary_chest', c.legendary_chests)
    ON CONFLICT (user_id, item_type, item_code)
      DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
    v_delivery := v_delivery || jsonb_build_object('legendaryChests', c.legendary_chests);
  END IF;

  FOR r IN SELECT n.id FROM public.nft_equipment n
            JOIN public.equipment_templates t ON t.id = n.template_id
           WHERE n.owner_user_id IS NULL AND n.status <> 'BURNED' AND lower(COALESCE(t.slot,'')) = 'weapon'
           ORDER BY n.for_sale ASC, n.created_at ASC
           LIMIT GREATEST(0, COALESCE(c.nft_weapons,2)) LOOP
    v_assign := public.nft_equipment_assign_unit(r.id, o.user_id, 'celestial_pack');
    INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'nft_weapon', v_assign->>'name', (v_assign->>'instanceId')::uuid);
    v_weapons := v_weapons || jsonb_build_array(v_assign);
  END LOOP;

  FOR r IN SELECT * FROM public.equipment_templates
           WHERE is_active AND NOT COALESCE(is_nft,false)
             AND lower(COALESCE(slot,'')) IN ('armor','chest','armour')
             AND lower(COALESCE(rarity,'')) IN ('legendary','mythic')
           ORDER BY random() LIMIT GREATEST(0, COALESCE(c.armors,2)) LOOP
    INSERT INTO public.player_equipment(user_id, template_id, level, source, source_ref)
    VALUES (o.user_id, r.id, 1, 'celestial_pack', gen_random_uuid())
    RETURNING id INTO v_peq;
    INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id, instance_id)
    VALUES (o.user_id, o.id, 'armor', r.code, v_peq);
    v_armors := v_armors || jsonb_build_array(jsonb_build_object('id', v_peq, 'code', r.code, 'name', r.name));
  END LOOP;

  v_pool := COALESCE(c.random_items_pool, '[]'::jsonb);
  IF jsonb_array_length(v_pool) > 0 THEN
    FOR i IN 1..GREATEST(0, COALESCE(c.random_items,0)) LOOP
      v_pick := v_pool -> floor(random() * jsonb_array_length(v_pool))::int;
      INSERT INTO public.player_inventory(user_id, item_type, item_code, quantity)
      VALUES (o.user_id, v_pick->>'type', v_pick->>'code', GREATEST(1, COALESCE((v_pick->>'qty')::int, 1)))
      ON CONFLICT (user_id, item_type, item_code)
        DO UPDATE SET quantity = public.player_inventory.quantity + EXCLUDED.quantity, updated_at = now();
      INSERT INTO public.celestial_pack_items(user_id, purchase_id, item_type, template_id)
      VALUES (o.user_id, o.id, 'random_item', v_pick->>'code');
      v_random := v_random || jsonb_build_array(v_pick);
    END LOOP;
  END IF;

  IF COALESCE(o.bonus_percent_snapshot,0) > 0 THEN
    PERFORM public.ton_mining_bonus_grant(o.user_id, 'CELESTIAL_MYSTERY_PACK',
      o.bonus_percent_snapshot, 'Celestial Mystery Pack');
  END IF;

  INSERT INTO public.player_entitlements(user_id, code, source) VALUES (o.user_id, 'CELESTIAL_PACK_OWNER', 'celestial_pack')
    ON CONFLICT (user_id, code) DO NOTHING;

  v_delivery := v_delivery || jsonb_build_object(
    'nftWeapons', v_weapons, 'armors', v_armors, 'randomItems', v_random,
    'accountBonusPercent', o.bonus_percent_snapshot);

  UPDATE public.celestial_pack_purchases
     SET status = 'delivered', delivered_at = now(), delivery = v_delivery WHERE id = o.id;

  INSERT INTO public.celestial_pack_ledger(purchase_id, user_id, kind, fc_amount, note)
    VALUES (o.id, o.user_id, 'delivery', o.fc_snapshot, 'celestial mystery pack delivered (mining to be revealed)');

  INSERT INTO public.player_notifications(user_id, type, title, message, metadata, dedupe_key)
  VALUES (o.user_id, 'celestial_pack', 'CELESTIAL MYSTERY PACK ATIVO',
          'Recompensas entregues. As taxas de mineracao do Heroi Celestial e do Pet NFT serao reveladas em breve.',
          v_delivery, 'celestial_pack:' || o.id::text)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'purchaseId', o.id, 'delivery', v_delivery);
END $function$;