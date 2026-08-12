-- ======================================================= NFT HERO ADMIN CONTROL
CREATE OR REPLACE FUNCTION public.admin_nft_hero_overview(p_admin_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select jsonb_build_object(
    'templates', coalesce((select jsonb_agg(jsonb_build_object(
        'heroKey', c.hero_key, 'name', c.name, 'class', coalesce(c.nft_class_label, c.hero_class),
        'archetype', c.hero_class, 'image', c.image,
        'baseAtk', c.base_atk, 'baseHp', c.base_hp, 'baseDef', c.base_def, 'speed', c.base_speed,
        'crit', c.crit_rate, 'skillPower', c.skill_power, 'growth', c.growth_multiplier, 'maxLevel', c.max_level,
        'minted', (select count(*) from nft_heroes n where n.hero_template_id = c.hero_key),
        'available', (select count(*) from nft_heroes n where n.hero_template_id = c.hero_key and n.status = 'AVAILABLE'),
        'owned', (select count(*) from nft_heroes n where n.hero_template_id = c.hero_key and n.status = 'OWNED')
      ) order by c.sort_order, c.name) from hero_catalog c where c.is_nft_exclusive), '[]'::jsonb),
    'totals', jsonb_build_object(
      'units', (select count(*) from nft_heroes),
      'available', (select count(*) from nft_heroes where status = 'AVAILABLE'),
      'owned', (select count(*) from nft_heroes where status = 'OWNED'),
      'revoked', (select count(*) from nft_heroes where status = 'REVOKED'))
  ) into res;
  return res;
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_create(p_admin_id bigint, p_hero_key text, p_quantity integer DEFAULT 1)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare c public.hero_catalog; qty int; i int; nxt int; created jsonb := '[]'::jsonb; row_id uuid; inst text; slug text;
begin
  perform public.admin_assert(p_admin_id);
  qty := greatest(1, least(50, coalesce(p_quantity, 1)));
  select * into c from hero_catalog
    where is_nft_exclusive and (hero_key = p_hero_key or lower(name) like '%'||lower(p_hero_key)||'%'
      or hero_key like '%'||lower(p_hero_key)||'%') limit 1;
  if c.hero_key is null then raise exception 'NFT_HERO_TEMPLATE_NOT_FOUND'; end if;
  slug := upper(regexp_replace(split_part(c.hero_key,'-',2), '[^a-zA-Z0-9]', '', 'g'));
  if slug = '' then slug := upper(regexp_replace(c.name, '[^a-zA-Z0-9]', '', 'g')); end if;
  select coalesce(max(nft_serial),0) into nxt from nft_heroes where hero_template_id = c.hero_key;
  for i in 1..qty loop
    nxt := nxt + 1;
    inst := 'NFT-HERO-' || slug || '-' || lpad(nxt::text, 4, '0');
    insert into nft_heroes (hero_template_id, nft_serial, unique_instance_id, status, created_by_admin, minted)
      values (c.hero_key, nxt, inst, 'AVAILABLE', p_admin_id, false)
      returning id into row_id;
    insert into nft_hero_history (nft_hero_id, action, admin_telegram_id, metadata)
      values (row_id, 'CREATED', p_admin_id, jsonb_build_object('serial', nxt, 'instance', inst));
    created := created || jsonb_build_object('id', row_id, 'serial', nxt, 'instance', inst);
  end loop;
  perform public.admin_log(p_admin_id,'nft_hero.create','hero',c.hero_key,null,jsonb_build_object('quantity',qty),'NFT hero units created');
  return jsonb_build_object('hero', c.name, 'heroKey', c.hero_key, 'created', created);
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_available(p_admin_id bigint, p_hero_key text DEFAULT NULL, p_limit integer DEFAULT 30)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
      'heroKey', c.hero_key, 'hero', c.name) order by c.sort_order, n.nft_serial), '[]'::jsonb)
    into res
  from nft_heroes n join hero_catalog c on c.hero_key = n.hero_template_id
  where n.status = 'AVAILABLE' and (p_hero_key is null or c.hero_key = p_hero_key)
  limit greatest(1, least(60, coalesce(p_limit, 30)));
  return res;
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_give(p_admin_id bigint, p_ref text, p_nft_id uuid, p_reason text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare v_uid uuid; n public.nft_heroes; c public.hero_catalog; v_hero uuid; g record; ph public.player_heroes;
begin
  perform public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  select * into n from nft_heroes where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_HERO_NOT_FOUND'; end if;
  if n.status = 'OWNED' or n.owner_user_id is not null then raise exception 'NFT_HERO_ALREADY_OWNED'; end if;
  if n.status = 'BURNED' then raise exception 'NFT_HERO_BURNED'; end if;
  select * into c from hero_catalog where hero_key = n.hero_template_id;

  insert into player_heroes (user_id, hero_key, name, rarity, level, image, archetype,
      is_nft_exclusive, nft_hero_id, nft_serial, nft_instance_id, tradable, market_locked, locked)
    values (v_uid, c.hero_key, c.name, 'nft_exclusive', greatest(1, coalesce(n.level,1)), c.image, c.hero_class,
      true, n.id, n.nft_serial, n.unique_instance_id, false, true, true)
    returning id into v_hero;
  select * into ph from player_heroes where id = v_hero;

  update nft_heroes set owner_user_id = v_uid, player_hero_id = v_hero, status = 'OWNED',
      assigned_at = now(), revoked_at = null, updated_at = now()
   where id = n.id;
  insert into nft_hero_history (nft_hero_id, action, admin_telegram_id, to_user_id, reason)
    values (n.id, 'DELIVERED', p_admin_id, v_uid, p_reason);
  perform public.admin_log(p_admin_id,'nft_hero.give','player',v_uid::text,null,
    jsonb_build_object('nft', n.unique_instance_id, 'hero', c.hero_key, 'player_hero_id', v_hero), p_reason);

  select name, telegram_id into g from game_players where id = v_uid;
  return jsonb_build_object('hero', c.name, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
    'playerName', g.name, 'telegramId', g.telegram_id, 'playerHeroId', v_hero,
    'atk', round(ph.final_atk), 'hp', round(ph.final_hp),
    'power', round(ph.final_atk * 2 + ph.final_hp));
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_revoke(p_admin_id bigint, p_nft_id uuid, p_reason text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare n public.nft_heroes; c public.hero_catalog; prev uuid;
begin
  perform public.admin_assert(p_admin_id);
  select * into n from nft_heroes where id = p_nft_id for update;
  if n.id is null then raise exception 'NFT_HERO_NOT_FOUND'; end if;
  select * into c from hero_catalog where hero_key = n.hero_template_id;
  prev := n.owner_user_id;
  if n.player_hero_id is not null then
    delete from pvp_team_slots where hero_id = n.player_hero_id;
    delete from boss_team_slots where player_hero_id = n.player_hero_id;
    delete from hero_combat_state where hero_id = n.player_hero_id;
    perform set_config('mythreon.nft_hero_revoke','1', true);
    delete from player_heroes where id = n.player_hero_id;
    perform set_config('mythreon.nft_hero_revoke','0', true);
  end if;
  update nft_heroes set owner_user_id = null, player_hero_id = null, status = 'AVAILABLE',
      revoked_at = now(), assigned_at = null, updated_at = now()
   where id = n.id;
  insert into nft_hero_history (nft_hero_id, action, admin_telegram_id, from_user_id, reason)
    values (n.id, 'REVOKED', p_admin_id, prev, p_reason);
  perform public.admin_log(p_admin_id,'nft_hero.revoke','hero',n.unique_instance_id,null,
    jsonb_build_object('from', prev), p_reason);
  return jsonb_build_object('instance', n.unique_instance_id, 'hero', c.name, 'serial', n.nft_serial);
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_search(p_admin_id bigint, p_query text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare q text; res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  q := '%' || trim(coalesce(p_query,'')) || '%';
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'hero', c.name, 'heroKey', c.hero_key, 'serial', n.nft_serial,
      'instance', n.unique_instance_id, 'status', n.status, 'level', coalesce(ph.level, n.level),
      'atk', round(coalesce(ph.final_atk,0)), 'hp', round(coalesce(ph.final_hp,0)),
      'power', round(coalesce(ph.final_atk,0) * 2 + coalesce(ph.final_hp,0)),
      'owner', case when g.id is null then null else jsonb_build_object('name', g.name, 'telegramId', g.telegram_id, 'userId', g.id) end
    ) order by n.created_at desc), '[]'::jsonb) into res
  from nft_heroes n
  join hero_catalog c on c.hero_key = n.hero_template_id
  left join game_players g on g.id = n.owner_user_id
  left join player_heroes ph on ph.id = n.player_hero_id
  where n.unique_instance_id ilike q or c.name ilike q or c.hero_key ilike q
     or coalesce(g.name,'') ilike q or coalesce(g.telegram_id::text,'') ilike q
     or n.id::text = trim(coalesce(p_query,''));
  return res;
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_registry(p_admin_id bigint, p_limit integer DEFAULT 15, p_offset integer DEFAULT 0)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare rows_json jsonb; total int;
begin
  perform public.admin_assert(p_admin_id);
  select count(*) into total from nft_heroes;
  select coalesce(jsonb_agg(x order by (x->>'createdAt') desc), '[]'::jsonb) into rows_json from (
    select jsonb_build_object(
      'id', n.id, 'hero', c.name, 'heroKey', c.hero_key,
      'serial', n.nft_serial, 'instance', n.unique_instance_id, 'status', n.status,
      'level', coalesce(ph.level, n.level), 'minted', n.minted,
      'createdAt', n.created_at, 'assignedAt', n.assigned_at,
      'owner', case when g.id is null then null else jsonb_build_object('name', g.name, 'telegramId', g.telegram_id, 'userId', g.id) end
    ) as x
    from nft_heroes n
    join hero_catalog c on c.hero_key = n.hero_template_id
    left join game_players g on g.id = n.owner_user_id
    left join player_heroes ph on ph.id = n.player_hero_id
    order by n.created_at desc
    limit greatest(1, least(50, coalesce(p_limit,15))) offset greatest(0, coalesce(p_offset,0))
  ) t;
  return jsonb_build_object('total', total, 'units', rows_json);
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_history(p_admin_id bigint, p_limit integer DEFAULT 20)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select coalesce(jsonb_agg(jsonb_build_object(
      'action', h.action, 'createdAt', h.created_at, 'reason', h.reason,
      'instance', n.unique_instance_id, 'hero', c.name,
      'to', (select name from game_players where id = h.to_user_id),
      'from', (select name from game_players where id = h.from_user_id)
    ) order by h.created_at desc), '[]'::jsonb) into res
  from (select * from nft_hero_history order by created_at desc limit greatest(1, least(50, coalesce(p_limit,20)))) h
  join nft_heroes n on n.id = h.nft_hero_id
  join hero_catalog c on c.hero_key = n.hero_template_id;
  return res;
end $fn$;

CREATE OR REPLACE FUNCTION public.admin_nft_hero_stats(p_admin_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare res jsonb;
begin
  perform public.admin_assert(p_admin_id);
  select jsonb_build_object(
    'ancestralAvgPower', coalesce((select round(avg(final_atk*2+final_hp)) from player_heroes where rarity='ancestral'),0),
    'nftAvgPower', coalesce((select round(avg(final_atk*2+final_hp)) from player_heroes where is_nft_exclusive),0),
    'nftOwners', (select count(distinct owner_user_id) from nft_heroes where status='OWNED'),
    'byHero', coalesce((select jsonb_agg(jsonb_build_object(
        'hero', c.name, 'heroKey', c.hero_key,
        'owned', (select count(*) from nft_heroes n where n.hero_template_id=c.hero_key and n.status='OWNED'),
        'avgPower', coalesce((select round(avg(ph.final_atk*2+ph.final_hp)) from player_heroes ph where ph.hero_key=c.hero_key),0),
        'topPower', coalesce((select round(max(ph.final_atk*2+ph.final_hp)) from player_heroes ph where ph.hero_key=c.hero_key),0)
      ) order by c.sort_order) from hero_catalog c where c.is_nft_exclusive), '[]'::jsonb)
  ) into res;
  return res;
end $fn$;

-- Admin balancing: tune each NFT hero individually (stats, growth, level cap, skills).
CREATE OR REPLACE FUNCTION public.admin_nft_hero_set_stats(p_admin_id bigint, p_hero_key text, p_patch jsonb, p_reason text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare c public.hero_catalog;
begin
  perform public.admin_assert(p_admin_id);
  select * into c from hero_catalog where hero_key = p_hero_key and is_nft_exclusive;
  if c.hero_key is null then raise exception 'NFT_HERO_TEMPLATE_NOT_FOUND'; end if;
  update hero_catalog set
    base_atk = coalesce((p_patch->>'base_atk')::numeric, base_atk),
    base_hp = coalesce((p_patch->>'base_hp')::numeric, base_hp),
    base_def = coalesce((p_patch->>'base_def')::numeric, base_def),
    base_speed = coalesce((p_patch->>'base_speed')::numeric, base_speed),
    crit_rate = coalesce((p_patch->>'crit_rate')::numeric, crit_rate),
    skill_power = coalesce((p_patch->>'skill_power')::numeric, skill_power),
    growth_multiplier = greatest(0.5, least(2, coalesce((p_patch->>'growth_multiplier')::numeric, growth_multiplier))),
    max_level = greatest(1, least(200, coalesce((p_patch->>'max_level')::int, max_level))),
    hero_class = coalesce(nullif(p_patch->>'hero_class',''), hero_class),
    skills = coalesce(p_patch->'skills', skills),
    updated_at = now()
  where hero_key = c.hero_key;
  perform public.admin_log(p_admin_id,'nft_hero.balance','hero',c.hero_key,to_jsonb(c),p_patch,p_reason);
  select * into c from hero_catalog where hero_key = p_hero_key;
  return jsonb_build_object('heroKey', c.hero_key, 'name', c.name, 'baseAtk', c.base_atk, 'baseHp', c.base_hp,
    'baseDef', c.base_def, 'speed', c.base_speed, 'crit', c.crit_rate, 'skillPower', c.skill_power,
    'growth', c.growth_multiplier, 'maxLevel', c.max_level, 'class', c.hero_class);
end $fn$;

-- ---------------------------------------------------------------- fusion guards
CREATE OR REPLACE FUNCTION public.fuse_heroes(p_telegram_id bigint, p_main_hero_id uuid, p_material_ids uuid[])
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
declare u uuid; balance numeric; cfg jsonb := hero_fusion_config(); main player_heroes%rowtype;
  required int; cost numeric; max_stars int; ids uuid[]; used int; after_row player_heroes%rowtype; after_balance numeric;
begin
  select id, forge_coins into u, balance from game_players where telegram_id = p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into main from player_heroes where id = p_main_hero_id and user_id = u for update;
  if main.id is null then raise exception 'HERO_NOT_OWNED'; end if;
  if main.is_nft_exclusive then raise exception 'NFT_HERO_UNIQUE'; end if;
  if exists(select 1 from player_heroes where id = any(coalesce(p_material_ids,'{}'::uuid[])) and is_nft_exclusive) then
    raise exception 'NFT_HERO_UNIQUE';
  end if;
  max_stars := coalesce((cfg->>'max_stars')::int, 5);
  if main.fusion_level >= max_stars then raise exception 'HERO_MAX_STARS'; end if;
  required := coalesce((cfg->'duplicates'->>(main.fusion_level+1)::text)::int, 1);
  cost := coalesce((cfg->'cost_fc'->>(main.fusion_level+1)::text)::numeric, 0);

  select coalesce(array_agg(id), '{}') into ids from (
    select ph.id from player_heroes ph
    where ph.user_id = u and ph.id <> main.id and ph.hero_key = main.hero_key
      and ph.id = any(coalesce(p_material_ids, '{}'::uuid[]))
      and not ph.locked and not ph.is_nft_exclusive
      and not exists(select 1 from pvp_team_slots t where t.hero_id = ph.id)
      and not exists(select 1 from boss_team_slots b where b.player_hero_id = ph.id)
    order by ph.fusion_level, ph.level
    limit required
    for update
  ) s;
  used := coalesce(array_length(ids,1), 0);
  if used < required then raise exception 'NOT_ENOUGH_DUPLICATES'; end if;
  if balance < cost then raise exception 'NOT_ENOUGH_FORGE_COINS'; end if;

  update game_players set forge_coins = forge_coins - cost, updated_at = now() where id = u returning forge_coins into after_balance;
  delete from hero_combat_state where hero_id = any(ids);
  delete from player_heroes where id = any(ids) and user_id = u;
  update player_heroes set fusion_level = fusion_level + 1, updated_at = now() where id = main.id returning * into after_row;

  insert into hero_fusion_history(user_id, hero_id, hero_key, from_stars, to_stars, materials_consumed, material_ids, cost_fc, atk_before, atk_after, hp_before, hp_after)
  values (u, main.id, main.hero_key, main.fusion_level, after_row.fusion_level, used, ids, cost, main.final_atk, after_row.final_atk, main.final_hp, after_row.final_hp);

  return jsonb_build_object(
    'heroId', main.id, 'name', after_row.name, 'fromStars', main.fusion_level, 'toStars', after_row.fusion_level,
    'atkBefore', round(main.final_atk), 'atkAfter', round(after_row.final_atk),
    'hpBefore', round(main.final_hp), 'hpAfter', round(after_row.final_hp),
    'bonusPercent', coalesce((cfg->'bonus_percent'->>after_row.fusion_level::text)::numeric, 0),
    'maxLevel', hero_max_level(after_row.fusion_level),
    'costFc', cost, 'consumed', used, 'balance', after_balance,
    'dashboard', get_hero_fusion_dashboard(p_telegram_id)
  );
end $fn$;

CREATE OR REPLACE FUNCTION public.nft_hero_block_rarity_fusion()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$ BEGIN RETURN NEW; END; $fn$;
