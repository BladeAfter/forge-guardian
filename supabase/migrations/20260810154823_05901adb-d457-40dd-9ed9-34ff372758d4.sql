create or replace function public.get_boss_combat(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.boss_combats%rowtype; defeats_count int; v_user uuid; b public.boss_templates; v_active boolean;
begin
  insert into public.game_players(telegram_id) values(p_telegram_id)
  on conflict(telegram_id) do update set updated_at=now() returning id into v_user;
  b:=public.active_boss_template();
  v_active:=b.code is not null;
  select * into c from public.boss_combats where user_id=v_user and status in ('active','defeated')
  order by case status when 'defeated' then 0 else 1 end, created_at desc limit 1;
  -- An active boss must be visible right away, even before the first attack.
  if c.id is null and v_active then
    perform public.ensure_boss_combat(p_telegram_id);
    select * into c from public.boss_combats where user_id=v_user and status in ('active','defeated')
    order by case status when 'defeated' then 0 else 1 end, created_at desc limit 1;
  end if;
  select boss_defeats into defeats_count from public.game_players where id=v_user;
  if c.id is null then
    return jsonb_build_object('id',null,'bossId',b.id,'bossName',coalesce(b.name,'Nenhum chefe ativo'),
      'bossLevel',coalesce(b.level,1),'bossMaxHp',coalesce(b.max_hp,0),'bossCurrentHp',coalesce(b.max_hp,0),
      'bossAttack',coalesce(b.attack,0),'bossAttackIntervalSeconds',coalesce(b.attack_interval_seconds,60),
      'rewardAmount',coalesce(b.reward_amount,0),'status','inactive','bossActive',v_active,
      'bossStartsAt',b.starts_at,'bossEndsAt',b.ends_at,
      'totalDamageDealt',0,'defeats',coalesce(defeats_count,0),'startedAt',now(),'lastProcessedAt',now(),
      'nextHeroAttackAt',null,'bossLastAttackAt',null,'bossNextAttackAt',null,'defeatedAt',null,
      'rewardClaimedAt',null,'teamChangeAvailableAt',null,'serverNow',clock_timestamp(),
      'heroes',public.boss_team_json(v_user),
      'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from public.player_heroes h where h.user_id=v_user),'[]'::jsonb));
  end if;
  return jsonb_build_object('id',c.id,'bossId',c.boss_id,'bossName',c.boss_name,'bossLevel',c.boss_level,
    'bossMaxHp',c.boss_max_hp,'bossCurrentHp',c.boss_current_hp,'bossAttack',c.boss_attack,
    'bossAttackIntervalSeconds',c.boss_attack_interval_seconds,'rewardAmount',c.reward_amount,'status',c.status,
    'bossActive',v_active,'bossStartsAt',b.starts_at,'bossEndsAt',b.ends_at,
    'totalDamageDealt',c.total_damage_dealt,'defeats',defeats_count,'startedAt',c.started_at,
    'lastProcessedAt',c.last_processed_at,'nextHeroAttackAt',c.next_hero_attack_at,'bossLastAttackAt',c.boss_last_attack_at,
    'bossNextAttackAt',c.boss_next_attack_at,'defeatedAt',c.defeated_at,'rewardClaimedAt',c.reward_claimed_at,
    'teamChangeAvailableAt',c.team_change_available_at,'serverNow',clock_timestamp(),
    'heroes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'heroId',s.hero_id,'name',h.name,'image',h.image,'rarity',s.rarity,'slot',s.slot,'level',s.level,'baseAtk',s.base_atk,'finalAtk',s.final_atk,'baseHp',s.base_hp,'maxHp',s.max_hp,'currentHp',s.current_hp,'isAlive',s.is_alive,'knockedOutAt',s.knocked_out_at,'reviveAt',s.revive_at) order by s.slot) from public.hero_combat_state s join public.player_heroes h on h.id=s.hero_id where s.combat_id=c.id and s.slot is not null),public.boss_team_json(v_user)),
    'ownedHeroes',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'heroKey',h.hero_key,'name',h.name,'image',h.image,'rarity',public.normalize_hero_rarity(h.rarity),'level',h.level) order by h.created_at) from public.player_heroes h where h.user_id=v_user),'[]'::jsonb));
end $$;

revoke all on function public.get_boss_combat(bigint) from public, anon, authenticated;
grant execute on function public.get_boss_combat(bigint) to service_role;