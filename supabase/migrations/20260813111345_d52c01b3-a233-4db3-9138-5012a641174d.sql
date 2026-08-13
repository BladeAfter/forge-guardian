-- 1) Rastreabilidade: liga cada equipamento entregue à recompensa/claim do passe
alter table public.player_equipment add column if not exists source_ref uuid;
create unique index if not exists player_equipment_source_ref_key on public.player_equipment(source_ref) where source_ref is not null;

-- 2) Auditoria de recolhimento de recompensas do passe
create table if not exists public.season_pass_claim_audit(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  telegram_id bigint,
  season_id uuid,
  reward_id uuid,
  level integer,
  reward_type text,
  reward_code text,
  item_id text,
  quantity integer,
  inventory_before integer,
  inventory_after integer,
  claim_status text not null,
  error_message text,
  created_at timestamptz not null default now()
);
grant all on public.season_pass_claim_audit to service_role;
alter table public.season_pass_claim_audit enable row level security;
create policy "audit service only" on public.season_pass_claim_audit for all to service_role using (true) with check (true);

-- 3) Claim atômico: entrega o equipamento, valida a gravação e só então marca como recolhido
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
begin
  select * into u from game_players where telegram_id = p_telegram_id for update;
  select * into r from season_pass_rewards where id = p_reward_id and enabled and tier in ('adventurer','legendary');
  if r.id is null then raise exception 'REWARD_LOCKED'; end if;
  select * into s from season_pass_seasons where id = r.season_id and active;
  select * into p from player_season_pass where user_id = u.id and season_id = s.id for update;
  if u.id is null or s.id is null or p.tier = 'none' or r.level > least(s.levels, floor(p.xp / s.xp_per_level)::int + 1) then raise exception 'REWARD_LOCKED'; end if;
  if r.tier = 'adventurer' and p.tier not in ('adventurer','legendary') or r.tier = 'legendary' and p.tier <> 'legendary' then raise exception 'PASS_NOT_OWNED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(u.id::text || ':' || r.id::text, 42));
  if exists (select 1 from season_pass_claims where user_id = u.id and reward_id = r.id) then
    return get_season_pass_dashboard(p_telegram_id);
  end if;
  v_key := 'season_reward:' || u.id || ':' || r.id;
  v_claim := gen_random_uuid();

  if r.reward_code = 'universal_fragment' then
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
    -- confirma a gravação antes de considerar a recompensa entregue
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
        and not coalesce(c.is_nft_exclusive,false)
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

-- 4) Checker: recompensas de equipamento recolhidas sem item correspondente
create or replace function public.admin_check_missing_pass_rewards(p_limit integer default 200)
returns jsonb
language sql
security definer
set search_path to 'public'
as $$
  with missing as (
    select c.user_id, g.telegram_id, g.username, g.first_name, s.name as season, r.level, r.tier,
           r.title, r.reward_code, c.reward_id, c.claimed_at
    from season_pass_claims c
    join season_pass_rewards r on r.id = c.reward_id and r.reward_type = 'equipment'
    join game_players g on g.id = c.user_id
    left join season_pass_seasons s on s.id = r.season_id
    where not exists (
      select 1 from player_equipment pe
      join equipment_templates t on t.id = pe.template_id
      where pe.user_id = c.user_id and pe.source = 'season_pass'
        and (pe.source_ref = c.reward_id or t.slot = coalesce(nullif(r.reward_code,''),'weapon'))
    )
    order by c.claimed_at desc
    limit greatest(1, coalesce(p_limit, 200))
  )
  select jsonb_build_object(
    'total', (select count(*) from missing),
    'entries', coalesce((select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'telegramId', m.telegram_id,
        'username', coalesce(m.username, m.first_name),
        'season', m.season, 'level', m.level, 'tier', m.tier,
        'reward', m.title, 'slot', m.reward_code, 'rewardId', m.reward_id,
        'claimedAt', m.claimed_at, 'claimed', true, 'inventory', 'MISSING'
      ) order by m.claimed_at desc) from missing m), '[]'::jsonb));
$$;
grant execute on function public.admin_check_missing_pass_rewards(integer) to service_role;

-- 5) Reparo: entrega apenas os equipamentos comprovadamente faltantes, sem duplicar
create or replace function public.admin_repair_missing_pass_rewards(p_telegram_id bigint default null, p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare rec record; tpl equipment_templates%rowtype; v_fixed integer := 0; v_details jsonb := '[]'::jsonb;
begin
  for rec in
    select c.user_id, g.telegram_id, r.id as reward_id, r.level, r.reward_code, r.season_id
    from season_pass_claims c
    join season_pass_rewards r on r.id = c.reward_id and r.reward_type = 'equipment'
    join game_players g on g.id = c.user_id
    where (p_telegram_id is null or g.telegram_id = p_telegram_id)
      and not exists (
        select 1 from player_equipment pe
        join equipment_templates t on t.id = pe.template_id
        where pe.user_id = c.user_id and pe.source = 'season_pass'
          and (pe.source_ref = c.reward_id or t.slot = coalesce(nullif(r.reward_code,''),'weapon'))
      )
    order by c.claimed_at
  loop
    if p_dry_run then
      v_details := v_details || jsonb_build_object('telegramId', rec.telegram_id, 'level', rec.level, 'slot', rec.reward_code, 'action', 'WOULD_FIX');
      v_fixed := v_fixed + 1;
      continue;
    end if;
    select * into tpl from equipment_templates t
      where t.is_active and t.rarity = 'rare' and t.slot = coalesce(nullif(rec.reward_code,''),'weapon')
      order by random() limit 1;
    if tpl.id is null then continue; end if;
    insert into player_equipment(user_id, template_id, source, source_ref)
    values (rec.user_id, tpl.id, 'season_pass', rec.reward_id)
    on conflict (source_ref) where source_ref is not null do nothing;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, claim_status)
    values (rec.user_id, rec.telegram_id, rec.season_id, rec.reward_id, rec.level, 'equipment', rec.reward_code, tpl.code, 1, 'PASS_REWARD_REPAIRED');
    v_fixed := v_fixed + 1;
    v_details := v_details || jsonb_build_object('telegramId', rec.telegram_id, 'level', rec.level, 'slot', rec.reward_code, 'item', tpl.code, 'action', 'FIXED');
  end loop;
  return jsonb_build_object('fixed', v_fixed, 'dryRun', coalesce(p_dry_run,false), 'details', v_details);
end
$$;
grant execute on function public.admin_repair_missing_pass_rewards(bigint, boolean) to service_role;