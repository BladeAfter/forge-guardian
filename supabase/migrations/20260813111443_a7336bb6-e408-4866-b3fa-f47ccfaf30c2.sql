drop index if exists public.player_equipment_source_ref_key;
create unique index if not exists player_equipment_user_source_ref_key on public.player_equipment(user_id, source_ref) where source_ref is not null;

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
    on conflict (user_id, source_ref) where source_ref is not null do nothing;
    insert into season_pass_claim_audit(user_id, telegram_id, season_id, reward_id, level, reward_type, reward_code, item_id, quantity, claim_status)
    values (rec.user_id, rec.telegram_id, rec.season_id, rec.reward_id, rec.level, 'equipment', rec.reward_code, tpl.code, 1, 'PASS_REWARD_REPAIRED');
    v_fixed := v_fixed + 1;
    v_details := v_details || jsonb_build_object('telegramId', rec.telegram_id, 'level', rec.level, 'slot', rec.reward_code, 'item', tpl.code, 'action', 'FIXED');
  end loop;
  return jsonb_build_object('fixed', v_fixed, 'dryRun', coalesce(p_dry_run,false), 'details', v_details);
end
$$;
grant execute on function public.admin_repair_missing_pass_rewards(bigint, boolean) to service_role;