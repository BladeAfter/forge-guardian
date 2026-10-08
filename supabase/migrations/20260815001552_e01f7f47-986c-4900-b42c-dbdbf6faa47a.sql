CREATE OR REPLACE FUNCTION public.expedition_claim(p_telegram_id bigint, p_expedition_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare u uuid; e public.pet_expeditions; m public.expedition_missions; entry jsonb;
        won boolean; qty int; out_rewards jsonb := '[]'::jsonb; tpl public.equipment_templates;
        v_food text;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into e from public.pet_expeditions where id = p_expedition_id and user_id = u for update;
  if e.id is null then raise exception 'EXPEDITION_NOT_FOUND'; end if;
  if e.status <> 'ACTIVE' then raise exception 'ALREADY_CLAIMED'; end if;
  if e.finishes_at > now() then raise exception 'EXPEDITION_IN_PROGRESS'; end if;
  select * into m from public.expedition_missions where id = e.mission_id;

  won := (random() * 100) <= e.success_chance;
  if won then
    for entry in select * from jsonb_array_elements(m.reward_pool) loop
      if (random() * 100) > coalesce((entry->>'chance')::numeric, 100) then continue; end if;
      qty := floor(random() * (coalesce((entry->>'max')::int,1) - coalesce((entry->>'min')::int,1) + 1))::int + coalesce((entry->>'min')::int,1);
      if qty <= 0 then continue; end if;
      case entry->>'type'
        when 'pet_food' then
          -- Never trust the configured code: fall back to a catalog item that exists.
          select f.code into v_food from public.pet_food_items f where f.code = nullif(entry->>'code','');
          if v_food is null then
            select f.code into v_food from public.pet_food_items f where f.code = 'pet_ration';
          end if;
          if v_food is null then
            select f.code into v_food from public.pet_food_items f order by coalesce(f.xp_value,0) asc limit 1;
          end if;
          if v_food is not null then
            insert into public.player_pet_food(user_id, food_code, quantity)
            values (u, v_food, qty)
            on conflict (user_id, food_code) do update set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
          end if;
        when 'universal_fragment' then
          perform public.add_universal_fragments(u, qty);
        when 'fc' then
          update public.game_players set forge_coins = coalesce(forge_coins,0) + qty, updated_at = now() where id = u;
        when 'pvp_ticket' then
          update public.game_players set pvp_tickets = coalesce(pvp_tickets,0) + qty, updated_at = now() where id = u;
        when 'equipment' then
          select * into tpl from public.equipment_templates
            where is_active and rarity = coalesce(entry->>'rarity','rare') order by random() limit 1;
          if tpl.id is not null then
            insert into public.player_equipment(user_id, template_id, source, source_ref) values (u, tpl.id, 'expedition', e.id);
          end if;
        else null;
      end case;
      out_rewards := out_rewards || jsonb_build_array(jsonb_build_object('type', entry->>'type',
        'code', coalesce(nullif(entry->>'code',''), entry->>'rarity', ''), 'quantity', qty));
    end loop;
  end if;

  update public.pet_expeditions set status = 'CLAIMED', success = won, rewards = out_rewards, claimed_at = now()
   where id = e.id;

  return jsonb_build_object('ok', true, 'success', won, 'rewards', out_rewards);
end $$;

REVOKE ALL ON FUNCTION public.expedition_claim(bigint, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expedition_claim(bigint, uuid) TO service_role;