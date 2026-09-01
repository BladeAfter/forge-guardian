-- 1) Ovos míticos: permitir abrir cada ovo possuído (antes travava 1 por temporada)
create table if not exists public.season_mythic_egg_openings(
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.season_pass_seasons(id),
  user_id uuid not null references public.game_players(id),
  reward_id uuid not null references public.season_exclusive_rewards(id),
  player_pet_id uuid,
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);
grant select on public.season_mythic_egg_openings to authenticated;
grant all on public.season_mythic_egg_openings to service_role;
alter table public.season_mythic_egg_openings enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='season_mythic_egg_openings' and policyname='own openings readable') then
    create policy "own openings readable" on public.season_mythic_egg_openings
      for select to authenticated using (true);
  end if;
end $$;

create index if not exists season_mythic_egg_openings_user_idx
  on public.season_mythic_egg_openings(user_id, season_id);

create or replace function public.open_season_mythic_egg(p_telegram_id bigint, p_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare u uuid; i player_inventory%rowtype; e season_exclusive_rewards%rowtype; k text; pp uuid; v_rar text; seq int;
begin
  select id into u from game_players where telegram_id=p_telegram_id for update;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into i from player_inventory
    where id=p_item_id and user_id=u and is_exclusive and item_type='pet_egg' and quantity>0 for update;
  if i.id is null then raise exception 'MYTHIC_EGG_NOT_OWNED'; end if;
  select * into e from season_exclusive_rewards
    where season_id=i.season_id and reward_code=i.exclusive_reward_code and reward_kind='mythic_egg' and enabled;
  if e.id is null then raise exception 'MYTHIC_EGG_REWARD_NOT_FOUND'; end if;
  select rarity into v_rar from pets where id=e.target_pet_id;
  if v_rar is null then raise exception 'PET_NOT_FOUND'; end if;

  -- A posse do ovo é a única trava: cada unidade consumida gera um pet.
  select count(*)::int + 1 into seq from season_mythic_egg_openings
    where user_id=u and season_id=e.season_id and reward_id=e.id;
  k:='season_mythic_egg_open:'||e.season_id||':'||u||':'||e.id||':'||seq;

  update player_inventory set quantity=quantity-1 where id=i.id;
  insert into player_pets(user_id,pet_id,rarity,level,xp,evolution_stage,is_season_exclusive,exclusive_season_id,exclusive_badge,tradable)
    values(u,e.target_pet_id,v_rar,1,0,'baby',true,e.season_id,e.badge,false) returning id into pp;
  insert into season_mythic_egg_openings(season_id,user_id,reward_id,player_pet_id,idempotency_key)
    values(e.season_id,u,e.id,pp,k);
  return jsonb_build_object('playerPetId',pp,'petId',e.target_pet_id,'name',e.display_name,'rarity',v_rar,
    'level',1,'xp',0,'evolutionStage','baby','badge',e.badge,'image',e.image_url);
end $function$;
revoke all on function public.open_season_mythic_egg(bigint,uuid) from public, anon, authenticated;
grant execute on function public.open_season_mythic_egg(bigint,uuid) to service_role;

-- 2) Buffs de pet: garantir progressão visível por nível/estágio (antes o teto era atingido no nvl 1)
create or replace function public.pet_effective_buff(p_base numeric, p_rarity text, p_level integer, p_stage integer, p_key text)
returns numeric language plpgsql stable set search_path to 'public' as $function$
declare raw numeric; cap numeric; lvl int; growth numeric; max_growth numeric; scaled numeric;
begin
  if p_base is null or p_base <= 0 then return coalesce(p_base, 0); end if;
  lvl := least(50, greatest(1, coalesce(p_level, 1)));
  growth := public.pet_stage_buff_multiplier(p_stage) * (1 + (lvl - 1) * 0.005);
  -- Crescimento máximo possível (estágio 10 + nível 50): usado como headroom do teto.
  max_growth := public.pet_stage_buff_multiplier(10) * (1 + 49 * 0.005);
  cap := public.pet_buff_cap(p_key);
  scaled := p_base * public.pet_rarity_multiplier(p_rarity);
  -- O teto passa a ser atingido apenas no crescimento máximo, então nvl 1 e nvl 30 diferem.
  if cap is not null and cap > 0 then
    scaled := least(scaled, cap / max_growth);
  end if;
  raw := scaled * growth;
  if cap is not null and raw > cap then raw := cap; end if;
  return round(least(raw, 150), 2);
end $function$;