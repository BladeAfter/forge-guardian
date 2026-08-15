-- ============ 1. SCHEMA ============
alter table public.player_season_pass add column if not exists pass_version int not null default 1;
alter table public.player_season_pass add column if not exists expires_at timestamptz;
alter table public.season_pass_rewards add column if not exists min_pass_version int not null default 1;
alter table public.hero_catalog add column if not exists is_pass_exclusive boolean not null default false;
alter table public.pets add column if not exists is_pass_exclusive boolean not null default false;
alter table public.player_heroes add column if not exists pass_exclusive boolean not null default false;
alter table public.player_pets add column if not exists pass_exclusive boolean not null default false;

create unique index if not exists player_heroes_pass_exclusive_uniq
  on public.player_heroes(user_id, hero_key) where pass_exclusive;
create unique index if not exists player_pets_pass_exclusive_uniq
  on public.player_pets(user_id, pet_id) where pass_exclusive;

alter table public.season_pass_rewards drop constraint if exists season_pass_rewards_reward_type_check;
alter table public.season_pass_rewards add constraint season_pass_rewards_reward_type_check
  check (reward_type = any (array['fc','hero_chest','pet_egg','pet_food','fragments','pvp_ticket','skin','equipment','hero_random','exclusive_chest']));

-- ============ 2. EXCLUSIVE HERO POOL ============
insert into public.hero_catalog (hero_key, name, rarity, image, enabled, description, hero_class,
  base_atk, base_hp, base_def, power, start_level, max_level, is_pass_exclusive,
  in_shop, featured, recruit_enabled, recruit_eligible, shop_eligible, reward_pool_eligible,
  random_drop_eligible, fusion_pool_enabled, drop_weight)
values
 ('pass-aetherion','Aetherion','mythic','/assets/game/heroes/exclusive/aetherion.png',true,'Guardião mítico exclusivo do Passe da Temporada.','mage',340,2600,190,5600,1,20,true,false,false,false,false,false,false,false,false,0),
 ('pass-nyxara','Nyxara','mythic','/assets/game/heroes/exclusive/nyxara.png',true,'Assassina mítica exclusiva do Passe da Temporada.','assassin',360,2300,170,5500,1,20,true,false,false,false,false,false,false,false,false,0),
 ('pass-dravok','Dravok','mythic','/assets/game/heroes/exclusive/dravok.png',true,'Guerreiro mítico exclusivo do Passe da Temporada.','warrior',330,2900,210,5700,1,20,true,false,false,false,false,false,false,false,false,0),
 ('pass-elyssara','Elyssara','mythic','/assets/game/heroes/exclusive/elyssara.png',true,'Suporte mítica exclusiva do Passe da Temporada.','support',300,2700,200,5400,1,20,true,false,false,false,false,false,false,false,false,0),
 ('pass-kaelthar','Kael''thar','mythic','/assets/game/heroes/exclusive/kaelthar.png',true,'Tanque mítico exclusivo do Passe da Temporada.','tank',290,3200,240,5800,1,20,true,false,false,false,false,false,false,false,false,0),
 ('pass-solmire','Solmire','mythic','/assets/game/heroes/exclusive/solmire.png',true,'Arqueira mítica exclusiva do Passe da Temporada.','archer',355,2400,175,5500,1,20,true,false,false,false,false,false,false,false,false,0),
 ('pass-vorthalis','Vorthalis','mythic','/assets/game/heroes/exclusive/vorthalis.png',true,'Mago mítico exclusivo do Passe da Temporada.','mage',370,2350,165,5650,1,20,true,false,false,false,false,false,false,false,false,0)
on conflict (hero_key) do update set is_pass_exclusive = true, enabled = true,
  image = excluded.image, rarity = 'mythic', in_shop = false, recruit_eligible = false,
  shop_eligible = false, reward_pool_eligible = false, random_drop_eligible = false,
  fusion_pool_enabled = false;

-- ============ 3. EXCLUSIVE PET POOL ============
insert into public.pets (name, slug, species, category, description, rarity, availability_type,
  is_season_exclusive, is_pass_exclusive, exclusive_badge, show_in_catalog, egg_eligible, is_enabled,
  image_base_url, image_baby_url, image_young_url, image_adult_url, image_ancestral_url,
  image_evo1_url, image_evo2_url, image_evo3_url, image_evo4_url, image_final_url,
  primary_attribute_key, primary_attribute_value)
select v.name, v.slug, v.species, 'mythic', v.descr, 'mythic', 'MYTHIC_EXCLUSIVE',
  true, true, 'EXCLUSIVE', false, false, true,
  v.img, v.img, v.img, v.img, v.img, v.img, v.img, v.img, v.img, v.img,
  'atk_percent', 12
from (values
 ('Sylvaris Prime','pass-sylvaris-prime','spirit','Pet mítico exclusivo do Passe da Temporada.','/assets/game/pets-exclusive/sylvaris-prime.png'),
 ('Vulkaryn Prime','pass-vulkaryn-prime','dragon','Pet mítico exclusivo do Passe da Temporada.','/assets/game/pets-exclusive/vulkaryn-prime.png'),
 ('Astravax','pass-astravax','celestial','Pet mítico exclusivo do Passe da Temporada.','/assets/game/pets-exclusive/astravax.png'),
 ('Crysalune','pass-crysalune','lunar','Pet mítico exclusivo do Passe da Temporada.','/assets/game/pets-exclusive/crysalune.png'),
 ('Thornyx','pass-thornyx','beast','Pet mítico exclusivo do Passe da Temporada.','/assets/game/pets-exclusive/thornyx.png'),
 ('Emberix','pass-emberix','phoenix','Pet mítico exclusivo do Passe da Temporada.','/assets/game/pets-exclusive/emberix.png'),
 ('Noctari','pass-noctari','shadow','Pet mítico exclusivo do Passe da Temporada.','/assets/game/pets-exclusive/noctari.png')
) as v(name, slug, species, descr, img)
where not exists (select 1 from public.pets p where p.slug = v.slug);

update public.pets set is_pass_exclusive = true, is_season_exclusive = true,
  availability_type = 'MYTHIC_EXCLUSIVE', show_in_catalog = false, egg_eligible = false,
  exclusive_badge = 'EXCLUSIVE'
where slug like 'pass-%';

-- ============ 4. HERO MINING: exclusive pass heroes never yield TON ============
CREATE OR REPLACE FUNCTION public.hero_mining_accrue(p_user_id uuid)
 RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_now timestamptz := now(); v_gain numeric := 0; v_unclaimed numeric; v_room numeric;
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;
  IF NOT hero_mining_enabled() THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;
  v_room := COALESCE(hero_mining_remaining(p_user_id), 0);
  IF v_room <= 0 THEN
    UPDATE player_heroes SET mining_last_at = v_now WHERE user_id = p_user_id;
    RETURN COALESCE((SELECT hero_mining_unclaimed_ton FROM game_players WHERE id = p_user_id), 0);
  END IF;
  WITH elig AS (
    SELECT h.id,
           CASE WHEN COALESCE(h.pass_exclusive,false) THEN 0
                ELSE hero_mining_hero_rate(h.rarity, h.nft_hero_id) END AS rate,
           GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(h.mining_last_at, h.created_at, v_now)))) AS secs
      FROM player_heroes h
     WHERE h.user_id = p_user_id
       AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
  ), moved AS (
    UPDATE player_heroes ph SET mining_last_at = v_now
      FROM elig e WHERE ph.id = e.id
     RETURNING e.rate * e.secs / 86400.0 AS gain
  )
  SELECT COALESCE(SUM(gain), 0) INTO v_gain FROM moved;
  v_gain := round(LEAST(GREATEST(v_gain, 0), v_room), 9);
  UPDATE game_players
     SET hero_mining_unclaimed_ton = round(COALESCE(hero_mining_unclaimed_ton, 0) + v_gain, 9),
         updated_at = now()
   WHERE id = p_user_id
  RETURNING hero_mining_unclaimed_ton INTO v_unclaimed;
  RETURN COALESCE(v_unclaimed, 0);
END $function$;

CREATE OR REPLACE FUNCTION public.get_hero_mining_state(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_user uuid; u game_players%rowtype; v_unclaimed numeric; v_rate numeric; v_count integer; v_min numeric;
        v_invested numeric; v_returned numeric; v_remaining numeric;
BEGIN
  SELECT id INTO v_user FROM game_players WHERE telegram_id = p_telegram_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  v_unclaimed := hero_mining_accrue(v_user);
  SELECT * INTO u FROM game_players WHERE id = v_user;
  SELECT COALESCE(min_claim_ton, 0) INTO v_min FROM hero_mining_settings WHERE id;
  v_invested := round(COALESCE(u.hero_mining_invested_ton, 0), 9);
  v_returned := round(COALESCE(u.hero_mining_returned_ton, 0), 9);
  v_remaining := GREATEST(0, round(v_invested - v_returned - COALESCE(v_unclaimed, 0), 9));
  SELECT COUNT(*), COALESCE(SUM(hero_mining_hero_rate(h.rarity, h.nft_hero_id)), 0)
    INTO v_count, v_rate
    FROM player_heroes h
   WHERE h.user_id = v_user
     AND NOT COALESCE(h.pass_exclusive, false)
     AND (h.nft_hero_id IS NOT NULL OR NOT COALESCE(h.market_locked, false))
     AND hero_mining_hero_rate(h.rarity, h.nft_hero_id) > 0;
  RETURN jsonb_build_object(
    'enabled', hero_mining_enabled(),
    'dailyRateTon', round(COALESCE(v_rate, 0), 9),
    'unclaimedTon', round(COALESCE(v_unclaimed, 0), 9),
    'lifetimeTon', round(COALESCE(u.hero_mining_lifetime_ton, 0), 9),
    'investedTon', v_invested, 'returnedTon', v_returned, 'remainingTon', v_remaining,
    'roiLimitReached', (v_invested > 0 AND v_remaining <= 0),
    'hasInvestment', (v_invested > 0),
    'eligibleHeroes', COALESCE(v_count, 0),
    'availableTon', round(COALESCE(u.ton_balance, 0), 9),
    'minClaimTon', COALESCE(v_min, 0),
    'lastClaimAt', u.hero_mining_claimed_at,
    'updatedAt', now(),
    'rates', COALESCE((SELECT jsonb_object_agg(rarity, ton_per_day) FROM hero_mining_rates), '{}'::jsonb),
    'investments', COALESCE((SELECT jsonb_agg(jsonb_build_object('sourceType', i.source_type, 'amountTon', i.amount_ton, 'createdAt', i.created_at) ORDER BY i.created_at DESC)
      FROM (SELECT * FROM hero_mining_investments WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) i), '[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'amountTon', c.amount_ton, 'heroCount', c.hero_count,
        'ratePerDay', c.rate_per_day, 'createdAt', c.created_at) ORDER BY c.created_at DESC)
      FROM (SELECT * FROM hero_mining_claims WHERE user_id = v_user ORDER BY created_at DESC LIMIT 10) c), '[]'::jsonb)
  );
END $function$;

-- ============ 5. EXCLUSIVE CHEST OPENING ============
CREATE OR REPLACE FUNCTION public.open_exclusive_chest(p_telegram_id bigint, p_inventory_item_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  u uuid; inv player_inventory%rowtype; v_kind text; hc hero_catalog%rowtype; pt pets%rowtype;
  v_id uuid; v_seed int; v_reward jsonb; v_chest_code text; v_frag int;
begin
  select id into u from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('exclusive_chest:'||u::text, 7));

  select * into inv from player_inventory
    where id = p_inventory_item_id and user_id = u and item_type = 'exclusive_chest' for update;
  if inv.id is null or inv.quantity < 1 then raise exception 'ITEM_NOT_FOUND'; end if;
  v_kind := case when inv.item_code ilike '%pet%' then 'pet' else 'hero' end;
  v_seed := (random()*1000000)::int;

  update player_inventory set quantity = quantity - 1, updated_at = now() where id = inv.id;
  delete from player_inventory where id = inv.id and quantity <= 0;

  if v_kind = 'hero' then
    select * into hc from hero_catalog c
      where c.is_pass_exclusive and coalesce(c.enabled, true)
        and not exists (select 1 from player_heroes h where h.user_id = u and h.hero_key = c.hero_key)
      order by random() limit 1;
    if hc.hero_key is not null then
      insert into player_heroes(user_id, hero_key, name, rarity, level, image, attribute_seed, pass_exclusive)
      values (u, hc.hero_key, hc.name, 'mythic', 1, hc.image, v_seed, true) returning id into v_id;
      v_reward := jsonb_build_object('kind','hero','exclusive',true,'heroId',v_id,'heroKey',hc.hero_key,
        'name',hc.name,'rarity','mythic','image',hc.image,'title',hc.name);
    end if;
  else
    select * into pt from pets p
      where p.is_pass_exclusive and coalesce(p.is_enabled, true)
        and not exists (select 1 from player_pets pp where pp.user_id = u and pp.pet_id = p.id)
      order by random() limit 1;
    if pt.id is not null then
      insert into player_pets(user_id, pet_id, rarity, level, xp, evolution_stage,
        is_season_exclusive, exclusive_badge, tradable, pass_exclusive)
      values (u, pt.id, 'mythic', 1, 0, 'baby', true, 'EXCLUSIVE', false, true) returning id into v_id;
      v_reward := jsonb_build_object('kind','pet','exclusive',true,'petId',v_id,'petSlug',pt.slug,
        'name',pt.name,'rarity','mythic','image',coalesce(pt.image_base_url, pt.image_baby_url),'title',pt.name);
    end if;
  end if;

  if v_reward is null then
    v_frag := add_universal_fragments(u, 100);
    select chest_code into v_chest_code from chest_reward_tables
      where enabled order by coalesce((rarity_rates->>'legendary')::numeric, 0) desc nulls last limit 1;
    if v_chest_code is not null then
      insert into player_inventory(user_id, item_type, item_code, quantity)
      values (u, 'hero_chest', v_chest_code, 1)
      on conflict(user_id, item_type, item_code)
        do update set quantity = player_inventory.quantity + 1, updated_at = now();
    end if;
    update game_players set forge_coins = forge_coins + 50000, updated_at = now() where id = u;
    v_reward := jsonb_build_object('kind','fallback','exclusive',true,'title','COLEÇÃO COMPLETA',
      'fragments',100,'fragmentBalance',v_frag,'chestCode',v_chest_code,'forgeCoins',50000);
  end if;

  insert into reward_open_logs(user_id, telegram_id, source, item_key, item_type, rolled_rarity, reward_id, reward_name)
  values (u, p_telegram_id, 'season_pass', inv.item_code, 'exclusive_chest', 'mythic', v_id, v_reward->>'name');

  return jsonb_build_object('reward', v_reward, 'chestCode', inv.item_code,
    'inventory', get_player_inventory(p_telegram_id));
end $function$;

REVOKE ALL ON FUNCTION public.open_exclusive_chest(bigint, uuid) FROM PUBLIC, anon, authenticated;

-- ============ 6. INVENTORY: expose exclusive chests ============
CREATE OR REPLACE FUNCTION public.get_player_inventory(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u uuid; v_chests jsonb; v_eggs jsonb; v_items jsonb;
  v_summon jsonb := public.fragment_summon_config(); v_frag_cost int := public.universal_fusion_fragment_cost();
  v_per_hero int := greatest(1, coalesce((public.fragment_summon_config()->>'fragments_per_hero')::int, 5));
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
      select jsonb_build_object('key','exclusive:'||i.id,'itemId',i.item_code,'instanceId',i.id,
        'itemType','exclusive_chest','category','chests',
        'name', case when i.item_code ilike '%pet%' then 'BAÚ MÍTICO EXCLUSIVO DE PET' else 'BAÚ MÍTICO EXCLUSIVO DE HERÓI' end,
        'description', case when i.item_code ilike '%pet%' then 'Pet mítico exclusivo do Passe' else 'Herói mítico exclusivo do Passe' end,
        'image', case when i.item_code ilike '%pet%' then '/assets/game/inventory/exclusive-pet-chest.png' else '/assets/game/inventory/exclusive-hero-chest.png' end,
        'rarity','mythic','exclusive',true,
        'quantity',i.quantity,'usable',true,'action','open-exclusive-chest')
      from player_inventory i
      where i.user_id=u and i.item_type='exclusive_chest' and i.quantity>0
      union all
      select jsonb_build_object('key',i.item_type||':'||i.item_code,'itemId',i.item_code,'instanceId',i.id,'itemType',i.item_type,
        'category',case when i.item_type ilike '%fragment%' then 'fragments' else 'other' end,
        'name',initcap(replace(i.item_code,'_',' ')),
        'description',case when i.item_type='fragments' and i.item_code='fragments'
            then v_per_hero || ' = RANDOM HERO' else initcap(replace(i.item_type,'_',' ')) end,
        'image',null,'rarity',null,
        'quantity',i.quantity,
        'usable', i.item_type='fragments' and i.item_code='fragments' and i.quantity >= v_per_hero,
        'action', case when i.item_type='fragments' and i.item_code='fragments' then 'summon-hero' end,
        'costPerUse', case when i.item_type='fragments' and i.item_code='fragments' then v_per_hero end,
        'summonRates', case when i.item_type='fragments' and i.item_code='fragments' then v_summon->'rates' end)
      from player_inventory i
      where i.user_id=u and i.item_type not in ('hero_chest','exclusive_chest') and i.quantity>0
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
        'category','fragments','name','Universal Fragment',
        'description', v_frag_cost || ' = HERO FUSION','image',null,'rarity',null,
        'quantity',pi.quantity,'usable',false,'action','view-fusion','costPerUse', v_frag_cost)
      from player_pet_inventory pi
      where pi.user_id=u and pi.item_type='universal_fragment' and pi.item_id is null and pi.quantity>0
      union all
      select jsonb_build_object('key','pet_fragment:'||pp.id,'itemId',pp.pet_id::text,'instanceId',pp.id,'itemType','pet_fragment',
        'category','fragments','name',p.name||' Fragment','description','Pet Fragment','image',p.image_baby_url,'rarity',pp.rarity,
        'quantity',pp.fragments,'usable',false,'action',null)
      from player_pets pp join pets p on p.id=pp.pet_id
      where pp.user_id=u and pp.fragments>0 and not coalesce(pp.market_locked,false)
      union all
      select jsonb_build_object('key','equipment:'||pe.id,'itemId',t.code,'instanceId',pe.id,'itemType','equipment',
        'category','equipment','name',t.name,'description',t.description,'image',t.image_url,'rarity',t.rarity,
        'quantity',1,'usable',false,'action',null,
        'slot',t.slot,'kind',t.kind,'heroClass',t.hero_class,
        'bonusAttack',t.bonus_attack,'bonusDefense',t.bonus_defense,'bonusHp',t.bonus_hp,'power',t.power,
        'equipped',pe.hero_id is not null,'equippedHeroId',pe.hero_id,'equippedHeroName',hero.name,
        'listed',false)
      from player_equipment pe
      join equipment_templates t on t.id=pe.template_id
      left join player_heroes hero on hero.id=pe.hero_id
      where pe.user_id=u and not coalesce(pe.market_locked,false)
    ) s
  );

  return jsonb_build_object('chests',v_chests,'eggs',v_eggs,'items',v_items);
end $function$;

-- ============ 7. SEASON PASS V2 REWARDS ============
update public.season_pass_rewards
   set reward_type = 'exclusive_chest',
       reward_code = case when tier = 'legendary' then 'exclusive-pet-chest' else 'exclusive-hero-chest' end,
       amount = 1,
       title = case when tier = 'legendary' then 'BAÚ MÍTICO EXCLUSIVO DE PET' else 'BAÚ MÍTICO EXCLUSIVO DE HERÓI' end,
       updated_at = now()
 where reward_code in ('season-1-aldren','season-1-mythic-egg');

insert into public.season_pass_rewards (season_id, level, tier, reward_type, reward_code, amount, title, enabled, min_pass_version)
select s.id, lv.level, t.tier,
  case
    when lv.level = 40 and t.tier = 'adventurer' then 'exclusive_chest'
    when lv.level = 50 then 'exclusive_chest'
    when lv.level % 10 = 0 then 'equipment'
    when lv.level % 5 = 0 then 'hero_chest'
    when lv.level % 4 = 0 then 'pvp_ticket'
    when lv.level % 3 = 0 then 'pet_food'
    when lv.level % 2 = 0 then 'fragments'
    else 'fc'
  end,
  case
    when lv.level = 40 and t.tier = 'adventurer' then 'exclusive-hero-chest'
    when lv.level = 50 then case when t.tier = 'legendary' then 'exclusive-pet-chest' else 'exclusive-hero-chest' end
    when lv.level % 10 = 0 then (array['weapon','armor','ring'])[1 + (lv.level % 3)]
    when lv.level % 5 = 0 then 'legend-chest'
    when lv.level % 3 = 0 then 'pet_food'
    when lv.level % 2 = 0 then 'universal_fragment'
    else null
  end,
  case
    when lv.level = 50 or (lv.level = 40 and t.tier = 'adventurer') then 1
    when lv.level % 10 = 0 then 1
    when lv.level % 5 = 0 then case when t.tier = 'legendary' then 2 else 1 end
    when lv.level % 4 = 0 then case when t.tier = 'legendary' then 10 else 5 end
    when lv.level % 3 = 0 then case when t.tier = 'legendary' then 6 else 3 end
    when lv.level % 2 = 0 then case when t.tier = 'legendary' then 40 else 20 end
    else case when t.tier = 'legendary' then 60000 else 25000 end
  end,
  case
    when lv.level = 40 and t.tier = 'adventurer' then 'BAÚ MÍTICO EXCLUSIVO DE HERÓI'
    when lv.level = 50 and t.tier = 'legendary' then 'BAÚ MÍTICO EXCLUSIVO DE PET'
    when lv.level = 50 then 'BAÚ MÍTICO EXCLUSIVO DE HERÓI'
    when lv.level % 10 = 0 then 'EQUIPAMENTO RARO'
    when lv.level % 5 = 0 then 'BAÚ LENDÁRIO'
    when lv.level % 4 = 0 then 'PVP TICKETS'
    when lv.level % 3 = 0 then 'COMIDA DE PET'
    when lv.level % 2 = 0 then 'FRAGMENTOS UNIVERSAIS'
    else 'FORGE COINS'
  end,
  true, 2
from public.season_pass_seasons s
cross join generate_series(31, 50) as lv(level)
cross join (values ('adventurer'),('legendary')) as t(tier)
where s.active
  and not exists (select 1 from public.season_pass_rewards r
                  where r.season_id = s.id and r.level = lv.level and r.tier = t.tier);

-- levels 31-50 are V2 only
update public.season_pass_rewards set min_pass_version = 2 where level > 30;

-- ============ 8. DASHBOARD + CLAIM WITH PASS VERSION ============
CREATE OR REPLACE FUNCTION public.season_pass_levels_for(p_pass_version int, p_season_levels int)
 RETURNS int LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$ SELECT CASE WHEN COALESCE(p_pass_version,1) >= 2 THEN 50 ELSE COALESCE(p_season_levels,30) END $function$;

CREATE OR REPLACE FUNCTION public.get_season_pass_dashboard(p_telegram_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u uuid; s public.season_pass_seasons%rowtype; p public.player_season_pass%rowtype;
        v_level int; v_xpl int; v_max int; v_mult numeric; v_levels int; v_ver int; v_ends timestamptz;
        v_cfg jsonb; v_limit int; v_bought int;
BEGIN
  SELECT id INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  SELECT * INTO s FROM public.season_pass_seasons WHERE active AND now() BETWEEN start_at AND end_at;
  IF u IS NULL OR s.id IS NULL THEN RAISE EXCEPTION 'SEASON_NOT_AVAILABLE'; END IF;
  INSERT INTO public.player_season_pass(user_id, season_id, tier) VALUES (u, s.id, 'none')
    ON CONFLICT (user_id, season_id) DO NOTHING;
  SELECT * INTO p FROM public.player_season_pass WHERE user_id = u AND season_id = s.id;
  v_ver := CASE WHEN p.tier = 'none' THEN 2 ELSE COALESCE(p.pass_version, 1) END;
  v_levels := public.season_pass_levels_for(v_ver, s.levels);
  v_ends := COALESCE(p.expires_at, s.end_at);
  v_xpl := GREATEST(1, s.xp_per_level);
  v_max := v_levels * v_xpl;
  v_level := LEAST(v_levels, p.xp / v_xpl + 1);
  v_mult := public.season_pass_tier_multiplier(p.tier);
  v_cfg := public.season_pass_level_purchase_config();
  v_limit := GREATEST(0, COALESCE((v_cfg->>'daily_limit')::int, 5));
  SELECT COALESCE(sum(levels_bought),0) INTO v_bought FROM public.season_pass_level_purchases
    WHERE user_id = u AND purchase_date = public.quest_today();
  RETURN jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'endsAt', v_ends, 'levels', v_levels,
      'passVersion', v_ver,
      'xpPerLevel', v_xpl, 'adventurerPriceTon', s.adventurer_price_ton,
      'legendaryPriceTon', s.legendary_price_ton,
      'upgradePriceTon', GREATEST(0, s.legendary_price_ton - s.adventurer_price_ton)),
    'player', jsonb_build_object('xp', p.xp, 'level', v_level, 'tier', p.tier,
      'passVersion', v_ver, 'expiresAt', p.expires_at,
      'totalXp', p.xp, 'maxXp', v_max, 'maxed', p.xp >= v_max,
      'xpIntoLevel', CASE WHEN p.xp >= v_max THEN v_xpl ELSE p.xp % v_xpl END,
      'xpForNextLevel', v_xpl,
      'xpMultiplier', v_mult, 'xpBonusPercent', round((v_mult - 1) * 100),
      'adventurerOwned', p.tier IN ('adventurer','legendary'), 'legendaryOwned', p.tier = 'legendary'),
    'levelPurchase', jsonb_build_object(
      'enabled', COALESCE((v_cfg->>'enabled')::boolean, true),
      'prices', COALESCE(v_cfg->'prices', '{}'::jsonb),
      'dailyLimit', v_limit,
      'boughtToday', v_bought,
      'remainingToday', GREATEST(0, v_limit - v_bought),
      'maxAvailable', LEAST(GREATEST(0, v_limit - v_bought), GREATEST(0, v_levels - v_level)),
      'balanceFc', COALESCE((SELECT forge_coins FROM public.game_players WHERE id = u), 0)),
    'xpRates', public.season_pass_xp_config(),
    'xpMultipliers', public.season_pass_xp_multipliers(),
    'xpCaps', public.season_pass_xp_caps(),
    'xpToday', COALESCE((SELECT SUM(xp_amount) FROM public.season_pass_xp_ledger
      WHERE user_id = u AND game_day = public.game_day_key()), 0),
    'rewards', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('id', r.id, 'level', r.level, 'tier', r.tier,
        'type', r.reward_type, 'code', r.reward_code, 'amount', r.amount, 'title', r.title,
        'exclusive', r.reward_type = 'exclusive_chest',
        'claimed', c.id IS NOT NULL,
        'unlocked', r.level <= v_level AND (
          (r.tier = 'adventurer' AND p.tier IN ('adventurer','legendary'))
          OR (r.tier = 'legendary' AND p.tier = 'legendary')))
        ORDER BY r.level, CASE r.tier WHEN 'adventurer' THEN 1 ELSE 2 END), '[]')
      FROM public.season_pass_rewards r
      LEFT JOIN public.season_pass_claims c ON c.reward_id = r.id AND c.user_id = u
      WHERE r.season_id = s.id AND r.enabled AND r.tier IN ('adventurer','legendary')
        AND COALESCE(r.min_pass_version, 1) <= v_ver));
END; $function$;

CREATE OR REPLACE FUNCTION public.claim_season_pass_reward(p_telegram_id bigint, p_reward_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  u game_players%rowtype; r season_pass_rewards%rowtype; p player_season_pass%rowtype; s season_pass_seasons%rowtype;
  egg uuid; v_key text; v_rarity text; v_qty integer; v_extra jsonb := '{}'::jsonb; v_food text; v_total integer;
  tpl equipment_templates%rowtype; hc hero_catalog%rowtype; v_id uuid; v_before integer; v_after integer; v_claim uuid;
  v_ver int; v_levels int;
begin
  select * into u from game_players where telegram_id = p_telegram_id for update;
  select * into r from season_pass_rewards where id = p_reward_id and enabled and tier in ('adventurer','legendary');
  if r.id is null then raise exception 'REWARD_LOCKED'; end if;
  select * into s from season_pass_seasons where id = r.season_id and active;
  select * into p from player_season_pass where user_id = u.id and season_id = s.id for update;
  if u.id is null or s.id is null or p.tier = 'none' then raise exception 'REWARD_LOCKED'; end if;
  v_ver := coalesce(p.pass_version, 1);
  v_levels := season_pass_levels_for(v_ver, s.levels);
  if coalesce(r.min_pass_version, 1) > v_ver then raise exception 'REWARD_LOCKED'; end if;
  if p.expires_at is not null and p.expires_at < now() then raise exception 'PASS_EXPIRED'; end if;
  if r.level > least(v_levels, floor(p.xp / s.xp_per_level)::int + 1) then raise exception 'REWARD_LOCKED'; end if;
  if r.tier = 'adventurer' and p.tier not in ('adventurer','legendary') or r.tier = 'legendary' and p.tier <> 'legendary' then raise exception 'PASS_NOT_OWNED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u.id::text || ':' || r.id::text, 42));
  if exists (select 1 from season_pass_claims where user_id = u.id and reward_id = r.id) then
    return get_season_pass_dashboard(p_telegram_id);
  end if;
  v_key := 'season_reward:' || u.id || ':' || r.id;
  v_claim := gen_random_uuid();

  if r.reward_type = 'exclusive_chest' then
    insert into player_inventory(user_id, item_type, item_code, quantity)
    values (u.id, 'exclusive_chest', coalesce(nullif(r.reward_code,''),'exclusive-hero-chest'), greatest(1, r.amount::int))
    on conflict(user_id, item_type, item_code) do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','exclusive_chest','code',r.reward_code,
      'quantity',greatest(1, r.amount::int),'exclusive',true,'title',r.title));
  elsif r.reward_code = 'universal_fragment' and r.reward_type <> 'fragments' then
    v_rarity := roll_universal_fragment_rarity();
    select coalesce((gs.value)::text::numeric, 25)::int into v_qty from game_settings gs where gs.key = 'universal_fragment_quantity';
    v_qty := greatest(1, coalesce(v_qty, r.amount::int));
    v_total := add_universal_fragments(u.id, v_qty);
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','fragments','code','universal_fragment','rarity',v_rarity,
      'quantity',v_qty,'balance',v_total,
      'title', upper(v_rarity) || ' UNIVERSAL FRAGMENT x' || v_qty));
  elsif r.reward_type = 'equipment' then
    select count(*) into v_before from player_equipment where user_id = u.id;
    select * into tpl from equipment_templates t
      where t.is_active and t.rarity = 'rare' and t.slot = coalesce(nullif(r.reward_code,''),'weapon')
      order by random() limit 1;
    if tpl.id is null then
      select * into tpl from equipment_templates t where t.is_active and t.rarity = 'rare' order by random() limit 1;
    end if;
    if tpl.id is null then
      insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, claim_status, error_message)
      values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, 'PASS_REWARD_FAILED', 'no active rare equipment template');
      raise exception 'REWARD_MISCONFIGURED';
    end if;
    insert into player_equipment(user_id, template_id, source, source_ref)
    values (u.id, tpl.id, 'season_pass', v_claim) returning id into v_id;
    select count(*) into v_after from player_equipment where user_id = u.id;
    if v_id is null or not exists (select 1 from player_equipment where id = v_id and user_id = u.id) then
      raise exception 'REWARD_NOT_DELIVERED';
    end if;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, inventory_before, inventory_after, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, tpl.code, 1, v_before, v_after, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','equipment','instanceId',v_id,'code',tpl.code,
      'name',tpl.name,'slot',tpl.slot,'rarity',tpl.rarity,'imageUrl',tpl.image_url,'power',tpl.power,'title',r.title));
  elsif r.reward_type = 'hero_random' then
    select * into hc from hero_catalog c
      where coalesce(c.enabled,true) and lower(c.rarity) = coalesce(nullif(lower(r.reward_code),''),'legendary')
        and not coalesce(c.is_nft_exclusive,false) and not coalesce(c.is_pass_exclusive,false)
      order by random() limit 1;
    if hc.hero_key is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_heroes(user_id, hero_key, name, rarity, level, image)
      values (u.id, hc.hero_key, hc.name, normalize_hero_rarity(hc.rarity), 1, hc.image) returning id into v_id;
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','hero','heroId',v_id,'heroKey',hc.hero_key,
      'name',hc.name,'rarity',normalize_hero_rarity(hc.rarity),'image',hc.image,'title',hc.name));
  elsif r.reward_type = 'fc' then
    update game_players set forge_coins = forge_coins + r.amount, updated_at = now() where id = u.id;
  elsif r.reward_type = 'pvp_ticket' then
    update game_players set pvp_tickets = pvp_tickets + r.amount::int, updated_at = now() where id = u.id;
  elsif r.reward_type = 'pet_egg' then
    select pe.id into egg from pet_eggs pe where pe.slug = r.reward_code;
    if egg is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (u.id, 'egg', egg, r.amount::int)
    on conflict(user_id, item_type, (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid))) do update set quantity = player_pet_inventory.quantity + excluded.quantity, updated_at = now();
  elsif r.reward_type = 'pet_food' then
    select pf.code into v_food from pet_food_items pf where pf.code = coalesce(nullif(r.reward_code, ''), 'pet_food') and pf.enabled;
    if v_food is null then
      select pf.code into v_food from pet_food_items pf where pf.code = 'pet_food' and pf.enabled;
    end if;
    if v_food is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_pet_food(user_id, food_code, quantity) values (u.id, v_food, r.amount::int)
    on conflict(user_id, food_code) do update set quantity = player_pet_food.quantity + excluded.quantity, updated_at = now();
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pet_food','code',v_food,'quantity',r.amount::int,'title',r.title));
  elsif r.reward_type = 'fragments' and coalesce(nullif(r.reward_code,''),'') in ('', 'fragments', 'universal_fragment') then
    v_qty := greatest(1, r.amount::int);
    v_total := add_universal_fragments(u.id, v_qty);
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','fragments','code','universal_fragment',
      'quantity',v_qty,'balance',v_total,'title', 'UNIVERSAL FRAGMENT x' || v_qty));
  elsif r.reward_type in ('fragments','hero_chest','skin') then
    insert into player_inventory(user_id, item_type, item_code, quantity) values (u.id, r.reward_type, coalesce(nullif(r.reward_code, ''), r.reward_type), r.amount::int)
    on conflict(user_id, item_type, item_code) do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now();
  else
    raise exception 'REWARD_MISCONFIGURED';
  end if;

  insert into season_pass_claims(user_id, reward_id, idempotency_key) values (u.id, r.id, v_key);
  return get_season_pass_dashboard(p_telegram_id) || v_extra;
end
$function$;

-- ============ 9. NEW BUYERS GET PASS V2 (30 DAYS FROM ACTIVATION) ============
CREATE OR REPLACE FUNCTION public.confirm_season_pass_order(p_order_id uuid, p_tx_hash text, p_amount_nano text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare o season_pass_orders%rowtype; p player_season_pass%rowtype; target text;
        expected numeric; received numeric; v_ver int; v_expires timestamptz;
begin
  if coalesce(trim(p_tx_hash), '') = '' then raise exception 'INVALID_TX_HASH'; end if;
  select * into o from season_pass_orders where id = p_order_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;

  if o.status = 'activated' then
    return jsonb_build_object('status', 'already_processed', 'orderId', o.id, 'tier', o.tier);
  end if;

  expected := o.amount_nano::numeric;
  received := coalesce(nullif(trim(p_amount_nano), '')::numeric, 0);
  if received < expected * 0.97 then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  if exists (select 1 from processed_ton_transactions where tx_hash = p_tx_hash
             and not (transaction_type = 'battle_pass' and reference_id = o.id::text)) then
    raise exception 'TX_ALREADY_USED';
  end if;
  if exists (select 1 from season_pass_orders where tx_hash = p_tx_hash and id <> o.id) then
    raise exception 'TX_ALREADY_USED';
  end if;
  insert into processed_ton_transactions(tx_hash, transaction_type, reference_id, user_id, amount_nano)
  values (p_tx_hash, 'battle_pass', o.id::text, o.user_id, received)
  on conflict (tx_hash) do nothing;

  insert into player_season_pass(user_id, season_id, tier) values (o.user_id, o.season_id, 'none')
    on conflict (user_id, season_id) do nothing;
  select * into p from player_season_pass where user_id = o.user_id and season_id = o.season_id for update;

  target := case when o.tier = 'legendary' or p.tier = 'legendary' then 'legendary' else 'adventurer' end;

  -- First purchase in this season activates PASS V2 (50 levels, 30 days).
  -- Players who already own a pass keep their current version and expiry untouched.
  if p.tier = 'none' then
    v_ver := 2; v_expires := now() + interval '30 days';
  else
    v_ver := coalesce(p.pass_version, 1); v_expires := p.expires_at;
  end if;

  update season_pass_orders
     set status = 'paid', tx_hash = p_tx_hash, paid_at = coalesce(paid_at, now())
   where id = o.id;

  update player_season_pass
     set tier = target,
         pass_version = v_ver,
         expires_at = v_expires,
         adventurer_owned = true,
         legendary_owned = (target = 'legendary') or legendary_owned,
         purchased_at = coalesce(purchased_at, now()),
         upgraded_at = case when target = 'legendary' and p.tier = 'adventurer' then now() else upgraded_at end,
         updated_at = now()
   where user_id = o.user_id and season_id = o.season_id;

  update season_pass_orders set status = 'activated', activated_at = now() where id = o.id;
  perform record_ton_revenue(o.user_id, o.price_ton, 'battle_pass', o.id::text, p_tx_hash);
  return jsonb_build_object('status', 'completed', 'orderId', o.id, 'tier', target,
    'priceTon', o.price_ton, 'passVersion', v_ver, 'expiresAt', v_expires);
end $function$;