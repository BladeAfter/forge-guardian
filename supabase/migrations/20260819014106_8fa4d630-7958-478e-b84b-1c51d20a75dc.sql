-- ⚔️ VETERAN VAULT — Admin Bot control surface (no redeploy needed).
create or replace function public.admin_veteran_vault_overview(p_admin_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c public.veteran_vault_config; p public.veteran_vault_pool;
begin
  perform public.admin_assert(p_admin_id);
  c := public.veteran_vault_settings();
  select * into p from public.veteran_vault_pool where id;
  return jsonb_build_object(
    'enabled', c.enabled, 'salesPaused', c.sales_paused, 'vaultVersion', c.vault_version,
    'priceTon', c.price_ton, 'minAccountAgeDays', c.min_account_age_days, 'cycleDays', c.cycle_days,
    'launchAt', c.launch_at, 'initialMyth', c.initial_myth, 'passTier', c.pass_tier,
    'heroKey', c.hero_key, 'petSlug', c.pet_slug, 'equipmentChestCode', c.equipment_chest_code,
    'fragments', c.fragments, 'resourceChestCode', c.resource_chest_code, 'resourceChestQty', c.resource_chest_qty,
    'badgeEnabled', c.badge_enabled, 'frameEnabled', c.frame_enabled,
    'maxTonReward', c.max_ton_reward, 'dailyMyth', c.daily_myth, 'rewardSchedule', c.reward_schedule,
    'finalReward', c.final_reward, 'targetReferenceTon', c.target_reference_ton,
    'tonBudgetPerVault', public.veteran_vault_ton_budget(),
    'mythBudgetPerVault', public.veteran_vault_myth_budget(),
    'pool', jsonb_build_object(
      'tonFunded', coalesce(p.ton_funded,0), 'tonReserved', coalesce(p.ton_reserved,0),
      'tonDistributed', coalesce(p.ton_distributed,0),
      'tonAvailable', coalesce(p.ton_funded,0) - coalesce(p.ton_reserved,0) - coalesce(p.ton_distributed,0),
      'mythFunded', coalesce(p.myth_funded,0), 'mythReserved', coalesce(p.myth_reserved,0),
      'mythDistributed', coalesce(p.myth_distributed,0),
      'mythAvailable', coalesce(p.myth_funded,0) - coalesce(p.myth_reserved,0) - coalesce(p.myth_distributed,0)),
    'activeVaults', (select count(*) from public.veteran_vault_purchases where status='settled' and completed_at is null),
    'completedVaults', (select count(*) from public.veteran_vault_purchases where completed_at is not null),
    'tonRaised', (select coalesce(sum(price_ton),0) from public.veteran_vault_purchases where status in ('paid','settled')),
    'tonDistributed', (select coalesce(sum(ton_distributed),0) from public.veteran_vault_purchases),
    'mythDistributed', (select coalesce(sum(myth_distributed),0) from public.veteran_vault_purchases),
    'failedPayments', (select count(*) from public.veteran_vault_purchases where status='pending' and expires_at <= now()),
    'activeIntents', (select count(*) from public.veteran_vault_purchases where status='pending' and expires_at > now()),
    'recent', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('purchaseId', o.id, 'player', g.display_name, 'telegramId', g.telegram_id,
          'method', o.payment_method, 'priceTon', o.price_ton, 'status', o.status,
          'tonEarned', o.ton_distributed, 'mythEarned', o.myth_distributed,
          'createdAt', o.created_at, 'cycleEndAt', o.cycle_end_at) as x
        from public.veteran_vault_purchases o join public.game_players g on g.id = o.user_id
        order by o.created_at desc limit 10) t));
end $$;

create or replace function public.admin_veteran_vault_set(p_admin_id bigint, p_field text, p_value text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_num numeric;
begin
  perform public.admin_assert(p_admin_id);
  if p_field = 'enabled' then
    update public.veteran_vault_config set enabled = (p_value in ('1','true','t')), updated_at = now() where id;
  elsif p_field = 'paused' then
    update public.veteran_vault_config set sales_paused = (p_value in ('1','true','t')), updated_at = now() where id;
  elsif p_field = 'price' then
    v_num := p_value::numeric; if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
    update public.veteran_vault_config set price_ton = v_num, updated_at = now() where id;
  elsif p_field = 'age' then
    update public.veteran_vault_config set min_account_age_days = greatest(0, p_value::int), updated_at = now() where id;
  elsif p_field = 'cycle' then
    v_num := p_value::numeric; if v_num < 1 then raise exception 'INVALID_VALUE'; end if;
    update public.veteran_vault_config set cycle_days = v_num::int, updated_at = now() where id;
  elsif p_field = 'version' then
    if btrim(p_value) = '' then raise exception 'INVALID_VALUE'; end if;
    update public.veteran_vault_config set vault_version = btrim(p_value), launch_at = now(), updated_at = now() where id;
  elsif p_field = 'myth' then
    update public.veteran_vault_config set initial_myth = greatest(0, p_value::numeric), updated_at = now() where id;
  elsif p_field = 'pass' then
    if p_value not in ('adventurer','legendary') then raise exception 'INVALID_VALUE'; end if;
    update public.veteran_vault_config set pass_tier = p_value, updated_at = now() where id;
  elsif p_field = 'hero' then
    if not exists (select 1 from public.hero_catalog where hero_key = p_value) then raise exception 'HERO_NOT_FOUND'; end if;
    update public.veteran_vault_config set hero_key = p_value, updated_at = now() where id;
  elsif p_field = 'pet' then
    if not exists (select 1 from public.pets where slug = p_value) then raise exception 'PET_NOT_FOUND'; end if;
    update public.veteran_vault_config set pet_slug = p_value, updated_at = now() where id;
  elsif p_field = 'chest' then
    update public.veteran_vault_config set equipment_chest_code = btrim(p_value), updated_at = now() where id;
  elsif p_field = 'fragments' then
    update public.veteran_vault_config set fragments = greatest(0, p_value::int), updated_at = now() where id;
  elsif p_field = 'chests' then
    update public.veteran_vault_config set resource_chest_qty = greatest(0, p_value::int), updated_at = now() where id;
  elsif p_field = 'badge' then
    update public.veteran_vault_config set badge_enabled = (p_value in ('1','true','t')), updated_at = now() where id;
  elsif p_field = 'frame' then
    update public.veteran_vault_config set frame_enabled = (p_value in ('1','true','t')), updated_at = now() where id;
  elsif p_field = 'maxton' then
    update public.veteran_vault_config set max_ton_reward = greatest(0, p_value::numeric), updated_at = now() where id;
  elsif p_field = 'dailymyth' then
    update public.veteran_vault_config set daily_myth = greatest(0, p_value::numeric), updated_at = now() where id;
  elsif p_field = 'schedule' then
    update public.veteran_vault_config set reward_schedule = p_value::jsonb, updated_at = now() where id;
  elsif p_field = 'final' then
    update public.veteran_vault_config set final_reward = p_value::jsonb, updated_at = now() where id;
  elsif p_field = 'target' then
    update public.veteran_vault_config set target_reference_ton = greatest(0, p_value::numeric), updated_at = now() where id;
  elsif p_field = 'reference' then
    update public.veteran_vault_config set reference_values = p_value::jsonb, updated_at = now() where id;
  else raise exception 'INVALID_FIELD'; end if;
  perform public.admin_log(p_admin_id, 'veteran_vault_set', p_field, p_value);
  return public.admin_veteran_vault_overview(p_admin_id);
end $$;

-- Funding the Veteran reward pools (real TON / official MYTH reserve). Negative values withdraw funding.
create or replace function public.admin_veteran_vault_fund(p_admin_id bigint, p_currency text, p_amount numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare p public.veteran_vault_pool;
begin
  perform public.admin_assert(p_admin_id);
  if p_amount is null or p_amount = 0 then raise exception 'INVALID_VALUE'; end if;
  select * into p from public.veteran_vault_pool where id for update;
  if lower(p_currency) = 'ton' then
    if coalesce(p.ton_funded,0) + p_amount < coalesce(p.ton_reserved,0) + coalesce(p.ton_distributed,0) then
      raise exception 'VETERAN_POOL_RESERVED_LOCKED';
    end if;
    update public.veteran_vault_pool set ton_funded = ton_funded + p_amount, updated_at = now() where id;
  elsif lower(p_currency) = 'myth' then
    if coalesce(p.myth_funded,0) + p_amount < coalesce(p.myth_reserved,0) + coalesce(p.myth_distributed,0) then
      raise exception 'VETERAN_POOL_RESERVED_LOCKED';
    end if;
    update public.veteran_vault_pool set myth_funded = myth_funded + p_amount, updated_at = now() where id;
  else raise exception 'INVALID_FIELD'; end if;
  insert into public.veteran_vault_ledger(kind, ton_amount, myth_amount, note)
    values ('pool_funding', case when lower(p_currency)='ton' then p_amount else 0 end,
            case when lower(p_currency)='myth' then p_amount else 0 end, 'admin funding');
  perform public.admin_log(p_admin_id, 'veteran_vault_fund', lower(p_currency), p_amount::text);
  return public.admin_veteran_vault_overview(p_admin_id);
end $$;

revoke all on function public.admin_veteran_vault_overview(bigint) from public, anon, authenticated;
revoke all on function public.admin_veteran_vault_set(bigint, text, text) from public, anon, authenticated;
revoke all on function public.admin_veteran_vault_fund(bigint, text, numeric) from public, anon, authenticated;