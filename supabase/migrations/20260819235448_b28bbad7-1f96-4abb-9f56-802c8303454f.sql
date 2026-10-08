create or replace function public.admin_premium_offers_set(p_admin_id bigint, p_offer text, p_field text, p_value text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_bool boolean; v_num numeric; v_ts timestamptz;
begin
  perform public.admin_assert(p_admin_id);
  v_bool := lower(coalesce(p_value,'')) in ('1','true','t','on','yes');

  if p_offer = 'TIMEZONE' then
    if p_value is null or length(trim(p_value)) = 0 then raise exception 'INVALID_VALUE'; end if;
    perform (now() at time zone p_value);
    insert into public.premium_offer_settings(id, reset_timezone) values (true, p_value)
      on conflict (id) do update set reset_timezone = excluded.reset_timezone, updated_at = now();
  elsif p_offer = 'FOUNDER_PACK' then
    if p_field = 'enabled' then
      update public.founder_pack_config set enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'popup' then
      update public.founder_pack_config set popup_enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'frequency' then
      if p_value not in ('ONCE_PER_SESSION','ONCE_PER_DAY','UNTIL_PURCHASED','DISABLED') then raise exception 'INVALID_VALUE'; end if;
      update public.founder_pack_config set popup_frequency = p_value, updated_at = now() where id;
    elsif p_field = 'price' then
      v_num := p_value::numeric; if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
      update public.founder_pack_config set price_ton = v_num, pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'myth' then
      update public.founder_pack_config set myth_amount = greatest(0, p_value::numeric), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'fragments' then
      update public.founder_pack_config set fragments = greatest(0, p_value::int), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'start' then
      v_ts := p_value::timestamptz;
      update public.founder_pack_config set start_at = v_ts, updated_at = now() where id;
    elsif p_field = 'end' then
      v_ts := nullif(p_value,'')::timestamptz;
      update public.founder_pack_config set ends_at = v_ts, updated_at = now() where id;
    elsif p_field = 'newaccount' then
      update public.founder_pack_config set require_new_account = v_bool, updated_at = now() where id;
    elsif p_field = 'heromyth' then
      update public.founder_pack_config set hero_daily_myth = greatest(0, p_value::numeric), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'petmyth' then
      update public.founder_pack_config set pet_daily_myth = greatest(0, p_value::numeric), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'chests' then
      update public.founder_pack_config set legendary_chests = greatest(1, p_value::int), pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'weapon' then
      if not exists (select 1 from public.equipment_templates where code = p_value) then raise exception 'WEAPON_NOT_FOUND'; end if;
      update public.founder_pack_config set weapon_code = p_value, pack_version = pack_version + 1, updated_at = now() where id;
    elsif p_field = 'pool' then
      v_num := greatest(0, p_value::numeric);
      insert into public.premium_myth_mining_pools(offer_type, allocated_myth) values ('FOUNDER_PACK', v_num)
        on conflict (offer_type) do update set allocated_myth = public.premium_myth_mining_pools.allocated_myth + v_num, updated_at = now();
      update public.myth_mining_pool set allocated_myth = allocated_myth + v_num, updated_at = now() where id;
    else raise exception 'UNKNOWN_FIELD';
    end if;
  elsif p_offer = 'VETERAN_VAULT' then
    if p_field = 'enabled' then
      update public.veteran_vault_v2_config set enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'popup' then
      update public.veteran_vault_v2_config set popup_enabled = v_bool, updated_at = now() where id;
    elsif p_field = 'frequency' then
      if p_value not in ('ONCE_PER_SESSION','ONCE_PER_DAY','UNTIL_PURCHASED','DISABLED') then raise exception 'INVALID_VALUE'; end if;
      update public.veteran_vault_v2_config set popup_frequency = p_value, updated_at = now() where id;
    elsif p_field = 'price' then
      v_num := p_value::numeric; if v_num <= 0 then raise exception 'INVALID_VALUE'; end if;
      update public.veteran_vault_v2_config set price_ton = v_num, updated_at = now() where id;
    elsif p_field = 'start' then
      update public.veteran_vault_v2_config set start_at = p_value::timestamptz, updated_at = now() where id;
    elsif p_field = 'end' then
      update public.veteran_vault_v2_config set ends_at = nullif(p_value,'')::timestamptz, updated_at = now() where id;
    elsif p_field = 'boost' then
      update public.veteran_vault_v2_config set boost_percent = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'heromyth' then
      update public.veteran_vault_v2_config set hero_daily_myth = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'petmyth' then
      update public.veteran_vault_v2_config set pet_daily_myth = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'dragonmyth' then
      update public.veteran_vault_v2_config set dragon_daily_myth = greatest(0, p_value::numeric), updated_at = now() where id;
    elsif p_field = 'pool' then
      v_num := greatest(0, p_value::numeric);
      insert into public.premium_myth_mining_pools(offer_type, allocated_myth) values ('VETERAN_VAULT', v_num)
        on conflict (offer_type) do update set allocated_myth = public.premium_myth_mining_pools.allocated_myth + v_num, updated_at = now();
      update public.myth_mining_pool set allocated_myth = allocated_myth + v_num, updated_at = now() where id;
    else raise exception 'UNKNOWN_FIELD';
    end if;
  else raise exception 'UNKNOWN_OFFER';
  end if;

  perform public.admin_log(p_admin_id, 'premium_offers.set', 'config', p_offer || ':' || p_field, null,
    jsonb_build_object('offer', p_offer, 'field', p_field, 'value', p_value), null);
  return public.admin_premium_offers_overview(p_admin_id);
end $$;

revoke execute on function public.admin_premium_offers_set(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_premium_offers_set(bigint, text, text, text) to service_role;