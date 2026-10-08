create or replace function public.claim_season_pass_reward(p_telegram_id bigint, p_reward_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
    update game_players set pvp_tickets = pvp_tickets + greatest(1, r.amount::int), updated_at = now() where id = u.id;
    v_extra := jsonb_build_object('lastReward', jsonb_build_object('type','pvp_ticket','quantity',greatest(1, r.amount::int),'title',r.title));
  elsif r.reward_type = 'fc' then
    update game_players set forge_coins = forge_coins + r.amount, updated_at = now() where id = u.id;
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