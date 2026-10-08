CREATE OR REPLACE FUNCTION public.claim_season_pass_reward(p_telegram_id bigint, p_reward_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
  if coalesce(r.min_pass_version, 1) > v_ver then raise exception 'PASS_VERSION_REQUIRED'; end if;
  if p.expires_at is not null and p.expires_at < now() then raise exception 'PASS_EXPIRED'; end if;
  if r.level > least(v_levels, floor(p.xp / s.xp_per_level)::int + 1) then raise exception 'REWARD_LOCKED'; end if;
  if r.tier = 'adventurer' and p.tier not in ('adventurer','legendary') or r.tier = 'legendary' and p.tier <> 'legendary' then raise exception 'PASS_NOT_OWNED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u.id::text || ':' || r.id::text, 42));
  if exists (select 1 from season_pass_claims where user_id = u.id and reward_id = r.id) then
    return get_season_pass_dashboard(p_telegram_id);
  end if;
  v_key := 'season_reward:' || u.id || ':' || r.id;
  v_claim := gen_random_uuid();

  if r.reward_type = 'pvp_ticket' then
    -- reward_type always wins over stray reward_code values (config noise)
    update game_players set pvp_tickets = pvp_tickets + greatest(1, r.amount::int), updated_at = now() where id = u.id
      returning pvp_tickets into v_after;
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pvp_ticket','quantity',greatest(1, r.amount::int),'balance',v_after,'title',r.title));
  elsif r.reward_type = 'fc' then
    update game_players set forge_coins = forge_coins + r.amount, updated_at = now() where id = u.id;
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','fc','quantity',r.amount,'title',r.title));
  elsif r.reward_type = 'exclusive_chest' then
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
  elsif r.reward_type = 'pet_egg' then
    select pe.id into egg from pet_eggs pe where pe.slug = r.reward_code;
    if egg is null then raise exception 'REWARD_MISCONFIGURED'; end if;
    insert into player_pet_inventory(user_id, item_type, item_id, quantity) values (u.id, 'egg', egg, r.amount::int)
    on conflict(user_id, item_type, (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid))) do update set quantity = player_pet_inventory.quantity + excluded.quantity, updated_at = now();
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pet_egg','code',r.reward_code,'quantity',r.amount::int,'title',r.title));
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
    insert into player_inventory(user_id, item_type, item_code, quantity) values (u.id, r.reward_type, coalesce(nullif(r.reward_code, ''), r.reward_type), greatest(1, r.amount::int))
    on conflict(user_id, item_type, item_code) do update set quantity = player_inventory.quantity + excluded.quantity, updated_at = now()
    returning quantity into v_after;
    if v_after is null then raise exception 'REWARD_NOT_DELIVERED'; end if;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, inventory_after, claim_status)
    values (u.id, p_telegram_id, s.id, r.id, r.level, r.reward_type, r.reward_code, coalesce(nullif(r.reward_code,''), r.reward_type), greatest(1, r.amount::int), v_after, 'PASS_REWARD_CLAIM');
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type',r.reward_type,'code',coalesce(nullif(r.reward_code,''), r.reward_type),
      'quantity',greatest(1, r.amount::int),'balance',v_after,'title',r.title));
  else
    raise exception 'REWARD_MISCONFIGURED';
  end if;

  insert into season_pass_claims(user_id, reward_id, idempotency_key) values (u.id, r.id, v_key);
  return get_season_pass_dashboard(p_telegram_id) || v_extra;
end
$function$;

CREATE OR REPLACE FUNCTION public.get_player_inventory(p_telegram_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
      -- FOUNDER PACK: premium resource chest (configurable content, opened server-side)
      select jsonb_build_object('key','resource:'||i.id,'itemId',i.item_code,'instanceId',i.id,
        'itemType','resource_chest','category','chests',
        'name','BAÚ PREMIUM DE RECURSOS','description','Founder Pack · recursos premium',
        'image',null,'rarity','legendary','quantity',i.quantity,'usable',true,'action','open-resource-chest')
      from player_inventory i
      where i.user_id=u and i.item_type='resource_chest' and i.quantity>0
      union all
      -- Tower keys: pure collectibles for now (no action, never consumed)
      select jsonb_build_object('key','tower_key:'||i.item_code,'itemId',i.item_code,'instanceId',i.id,
        'itemType','tower_key','category','keys',
        'name',coalesce(k.name, initcap(replace(i.item_code,'_',' '))),
        'description',coalesce(k.description,''),'image',k.image_url,'rarity',coalesce(k.rarity,'rare'),
        'quantity',i.quantity,'usable',false,'action',null)
      from player_inventory i left join tower_key_catalog k on k.code=i.item_code
      where i.user_id=u and i.item_type='tower_key' and i.quantity>0
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
      where i.user_id=u and i.item_type not in ('hero_chest','exclusive_chest','tower_key','resource_chest') and i.quantity>0
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
      union all
      -- PvP tickets live on game_players.pvp_tickets; surface them read-only so
      -- players can SEE pass/mission ticket rewards landing in the inventory.
      select jsonb_build_object('key','pvp_ticket','itemId','pvp_ticket','instanceId',null,'itemType','pvp_ticket',
        'category','other','name','PVP TICKET','description','Arena PvP','image',null,'rarity',null,
        'quantity',g.pvp_tickets,'usable',false,'action',null)
      from game_players g where g.id=u and coalesce(g.pvp_tickets,0)>0
    ) s
  );

  return jsonb_build_object('chests',v_chests,'eggs',v_eggs,'items',v_items);
end $function$;