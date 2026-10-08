
-- ============ 0020: NFT BREEDING + SUB-NFT + PET EXPEDITIONS ============

-- 1. SETTINGS ---------------------------------------------------------------
create table if not exists public.nft_breeding_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default true,
  max_breeds integer not null default 3,
  cooldown_days numeric not null default 7,
  cost_breed_1 numeric not null default 5,
  cost_breed_2 numeric not null default 7.5,
  cost_breed_3 numeric not null default 10,
  request_ttl_minutes integer not null default 30,
  baby_hours integer not null default 48,
  juvenile_hours integer not null default 96,
  adult_hours integer not null default 144,
  sub_rate_per_ton numeric not null default 0.018,
  min_claim_ton numeric not null default 0.05,
  sub_breeding_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
grant all on public.nft_breeding_settings to service_role;
alter table public.nft_breeding_settings enable row level security;
insert into public.nft_breeding_settings(id) values (true) on conflict do nothing;

-- 2. NFT PARENT COLUMNS -----------------------------------------------------
alter table public.nft_pets
  add column if not exists breed_count integer not null default 0,
  add column if not exists breeding_cooldown_until timestamptz,
  add column if not exists breeding_locked boolean not null default false,
  add column if not exists element text,
  add column if not exists appearance_family text;

-- 3. SUB-NFT TEMPLATES ------------------------------------------------------
create table if not exists public.sub_nft_templates (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  element text not null,
  secondary_element text,
  appearance_family text,
  image_url text not null,
  description text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant all on public.sub_nft_templates to service_role;
alter table public.sub_nft_templates enable row level security;

-- 4. TRAITS -----------------------------------------------------------------
create table if not exists public.sub_nft_traits (
  code text primary key,
  name text not null,
  effect_key text not null,           -- expedition_time | mission_reward | mission_success | long_mission_success | materials
  effect_value numeric not null,
  weight integer not null default 10,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
grant all on public.sub_nft_traits to service_role;
alter table public.sub_nft_traits enable row level security;

insert into public.sub_nft_traits(code, name, effect_key, effect_value) values
  ('swift','Swift','expedition_time',-5),
  ('fortunate','Fortunate','mission_reward',5),
  ('guardian','Guardian','mission_success',8),
  ('explorer','Explorer','long_mission_success',10),
  ('gatherer','Gatherer','materials',10)
on conflict (code) do nothing;

-- 5. BREEDING REQUESTS ------------------------------------------------------
create table if not exists public.nft_breeding_requests (
  id uuid primary key default gen_random_uuid(),
  initiator_user_id uuid not null references public.game_players(id) on delete cascade,
  partner_user_id uuid not null references public.game_players(id) on delete cascade,
  nft_a_id uuid not null references public.nft_pets(id) on delete cascade,
  nft_b_id uuid not null references public.nft_pets(id) on delete cascade,
  breed_number_a integer not null,
  breed_number_b integer not null,
  cost_a numeric not null,
  cost_b numeric not null,
  paid_a boolean not null default false,
  paid_b boolean not null default false,
  self_breed boolean not null default false,
  status text not null default 'pending', -- pending | accepted | completed | declined | expired
  expires_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint nft_breeding_distinct check (nft_a_id <> nft_b_id)
);
create index if not exists nft_breeding_requests_open_idx on public.nft_breeding_requests(status) where status in ('pending','accepted');
grant all on public.nft_breeding_requests to service_role;
alter table public.nft_breeding_requests enable row level security;

-- 6. SUB-NFTS ---------------------------------------------------------------
create sequence if not exists public.sub_nft_serial_seq start 1;
create table if not exists public.sub_nfts (
  id uuid primary key default gen_random_uuid(),
  serial bigint not null default nextval('public.sub_nft_serial_seq'),
  unique_instance_id text not null unique,
  owner_user_id uuid references public.game_players(id) on delete set null,
  template_id uuid not null references public.sub_nft_templates(id),
  player_pet_id uuid references public.player_pets(id) on delete set null,
  breeding_id uuid references public.nft_breeding_requests(id) on delete set null,
  parent_a_nft_id uuid references public.nft_pets(id) on delete set null,
  parent_b_nft_id uuid references public.nft_pets(id) on delete set null,
  generation integer not null default 1,
  trait_code text references public.sub_nft_traits(code),
  birth_time timestamptz not null default now(),
  maturity_stage text not null default 'EGG',   -- EGG | BABY | JUVENILE | ADULT
  matures_at timestamptz not null,
  mining_status text not null default 'PENDING', -- PENDING | ACTIVE | COMPLETE
  mining_rate_ton_day numeric not null default 0,
  mining_cap_ton numeric not null default 0,
  lifetime_mined_ton numeric not null default 0,
  unclaimed_ton numeric not null default 0,
  accrued_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sub_nfts_owner_idx on public.sub_nfts(owner_user_id);
grant all on public.sub_nfts to service_role;
alter table public.sub_nfts enable row level security;

alter table public.player_pets add column if not exists sub_nft_id uuid references public.sub_nfts(id) on delete set null;

-- 7. BREEDING HISTORY -------------------------------------------------------
create table if not exists public.nft_breeding_history (
  id uuid primary key default gen_random_uuid(),
  breeding_id uuid references public.nft_breeding_requests(id) on delete set null,
  parent_a_nft_id uuid,
  parent_b_nft_id uuid,
  owner_a_user_id uuid,
  owner_b_user_id uuid,
  cost_a numeric not null default 0,
  cost_b numeric not null default 0,
  breed_number_a integer,
  breed_number_b integer,
  egg_a_sub_nft_id uuid,
  egg_b_sub_nft_id uuid,
  created_at timestamptz not null default now()
);
grant all on public.nft_breeding_history to service_role;
alter table public.nft_breeding_history enable row level security;

-- 8. EXPEDITIONS ------------------------------------------------------------
create table if not exists public.expedition_missions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  rarity text not null default 'COMMON',
  duration_hours numeric not null,
  required_power integer not null,
  recommended_element text,
  reward_pool jsonb not null default '[]'::jsonb,
  base_success integer not null default 70,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now()
);
grant all on public.expedition_missions to service_role;
alter table public.expedition_missions enable row level security;

create table if not exists public.pet_expeditions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.game_players(id) on delete cascade,
  mission_id uuid not null references public.expedition_missions(id),
  pet_ids uuid[] not null,
  team_power integer not null default 0,
  success_chance integer not null default 0,
  status text not null default 'ACTIVE',   -- ACTIVE | CLAIMED
  success boolean,
  rewards jsonb not null default '[]'::jsonb,
  started_at timestamptz not null default now(),
  finishes_at timestamptz not null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists pet_expeditions_active_idx on public.pet_expeditions(user_id) where status = 'ACTIVE';
grant all on public.pet_expeditions to service_role;
alter table public.pet_expeditions enable row level security;

insert into public.expedition_missions(code,name,rarity,duration_hours,required_power,recommended_element,base_success,sort_order,reward_pool) values
 ('forgotten_forest','Forgotten Forest','COMMON',2,6000,'nature',70,1,
   '[{"type":"pet_food","code":"basic_kibble","min":3,"max":8,"chance":100},{"type":"universal_fragment","min":1,"max":3,"chance":60},{"type":"fc","min":500,"max":1500,"chance":80}]'::jsonb),
 ('crystal_cavern','Crystal Cavern','UNCOMMON',4,12000,'arcane',70,2,
   '[{"type":"pet_food","code":"basic_kibble","min":5,"max":12,"chance":100},{"type":"universal_fragment","min":2,"max":5,"chance":70},{"type":"fc","min":1500,"max":4000,"chance":90},{"type":"pvp_ticket","min":1,"max":2,"chance":25}]'::jsonb),
 ('ember_wastes','Ember Wastes','RARE',8,25000,'fire',70,3,
   '[{"type":"universal_fragment","min":4,"max":9,"chance":85},{"type":"fc","min":4000,"max":9000,"chance":95},{"type":"equipment","rarity":"rare","min":1,"max":1,"chance":35},{"type":"pvp_ticket","min":1,"max":3,"chance":35}]'::jsonb),
 ('abyssal_ruins','Abyssal Ruins','EPIC',12,40000,'shadow',70,4,
   '[{"type":"universal_fragment","min":6,"max":14,"chance":90},{"type":"fc","min":8000,"max":18000,"chance":95},{"type":"equipment","rarity":"epic","min":1,"max":1,"chance":30},{"type":"pvp_ticket","min":2,"max":4,"chance":45}]'::jsonb),
 ('celestial_gate','Celestial Gate','LEGENDARY',24,70000,'holy',70,5,
   '[{"type":"universal_fragment","min":10,"max":25,"chance":95},{"type":"fc","min":18000,"max":40000,"chance":100},{"type":"equipment","rarity":"epic","min":1,"max":2,"chance":45},{"type":"pvp_ticket","min":3,"max":6,"chance":60}]'::jsonb)
on conflict (code) do nothing;

-- 9. HELPERS ----------------------------------------------------------------
create or replace function public.breeding_settings()
returns public.nft_breeding_settings language sql stable security definer set search_path = public as $$
  select * from public.nft_breeding_settings where id
$$;

create or replace function public.breeding_cost(p_breed_number integer)
returns numeric language sql stable security definer set search_path = public as $$
  select case p_breed_number when 1 then s.cost_breed_1 when 2 then s.cost_breed_2 else s.cost_breed_3 end
  from public.nft_breeding_settings s where s.id
$$;

create or replace function public.pet_instance_power(p_player_pet_id uuid)
returns integer language sql stable security definer set search_path = public as $$
  select (case pp.rarity when 'legendary' then 8000 when 'epic' then 4000 when 'rare' then 2000
            when 'uncommon' then 1000 else 500 end)
       + pp.level * 100
       + coalesce((select round(sum((value#>>'{}')::numeric) * 250) from jsonb_each(public.player_pet_buffs(pp.id))), 0)
  from public.player_pets pp where pp.id = p_player_pet_id
$$;

-- Availability of a parent NFT for a new breeding
create or replace function public.nft_breeding_block_reason(p_nft_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare n public.nft_pets; s public.nft_breeding_settings;
begin
  select * into s from public.nft_breeding_settings where id;
  select * into n from public.nft_pets where id = p_nft_id;
  if n.id is null then return 'NFT_NOT_FOUND'; end if;
  if n.owner_user_id is null or n.status <> 'OWNED' then return 'NFT_NOT_OWNED'; end if;
  if n.breeding_locked then return 'NFT_LOCKED'; end if;
  if n.breed_count >= s.max_breeds then return 'MAX_BREEDING_REACHED'; end if;
  if n.breeding_cooldown_until is not null and n.breeding_cooldown_until > now() then return 'BREEDING_COOLDOWN'; end if;
  if exists (select 1 from public.nft_breeding_requests r
              where r.status in ('pending','accepted') and r.expires_at > now()
                and (r.nft_a_id = p_nft_id or r.nft_b_id = p_nft_id)) then return 'NFT_IN_BREEDING'; end if;
  return null;
end $$;

-- Expire stale requests and refund whoever already paid
create or replace function public.nft_breeding_expire_stale()
returns integer language plpgsql security definer set search_path = public as $$
declare r record; c integer := 0;
begin
  for r in select * from public.nft_breeding_requests
            where status in ('pending','accepted') and expires_at <= now() for update skip locked loop
    if r.paid_a then
      perform public.credit_ton_reward((select owner_user_id from public.nft_pets where id = r.nft_a_id),
        r.cost_a, 'breeding_refund', r.id::text, 'Breeding expirado - reembolso');
      perform public.record_spending_reversal('breeding:'||r.id::text||':a');
    end if;
    if r.paid_b then
      perform public.credit_ton_reward((select owner_user_id from public.nft_pets where id = r.nft_b_id),
        r.cost_b, 'breeding_refund', r.id::text, 'Breeding expirado - reembolso');
      perform public.record_spending_reversal('breeding:'||r.id::text||':b');
    end if;
    update public.nft_breeding_requests set status = 'expired', updated_at = now() where id = r.id;
    c := c + 1;
  end loop;
  return c;
end $$;

-- Maturity + mining accrual for one owner's sub-NFTs
create or replace function public.sub_nft_sync(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s public.nft_breeding_settings; r record; stage text; gain numeric; remaining numeric; hours numeric;
begin
  select * into s from public.nft_breeding_settings where id;
  for r in select * from public.sub_nfts where owner_user_id = p_user_id for update loop
    hours := extract(epoch from (now() - r.birth_time)) / 3600.0;
    stage := case when hours >= s.adult_hours then 'ADULT'
                  when hours >= s.juvenile_hours then 'JUVENILE'
                  when hours >= s.baby_hours then 'BABY' else 'EGG' end;
    remaining := greatest(0, r.mining_cap_ton - r.lifetime_mined_ton);
    gain := 0;
    if stage = 'ADULT' and remaining > 0 then
      gain := least(remaining,
        round(r.mining_rate_ton_day * (extract(epoch from (now() - greatest(r.accrued_at, r.matures_at))) / 86400.0), 9));
      if gain < 0 then gain := 0; end if;
    end if;
    update public.sub_nfts
       set maturity_stage = stage,
           lifetime_mined_ton = lifetime_mined_ton + gain,
           unclaimed_ton = unclaimed_ton + gain,
           accrued_at = now(),
           mining_status = case when stage <> 'ADULT' then 'PENDING'
                                when (lifetime_mined_ton + gain) >= mining_cap_ton then 'COMPLETE'
                                else 'ACTIVE' end,
           updated_at = now()
     where id = r.id;
  end loop;
end $$;

-- 10. BREEDING FLOW ---------------------------------------------------------
create or replace function public.nft_breeding_request_create(p_telegram_id bigint, p_my_nft_id uuid, p_partner_nft_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.nft_breeding_settings; u uuid; a public.nft_pets; b public.nft_pets; reason text; req public.nft_breeding_requests;
begin
  select * into s from public.nft_breeding_settings where id;
  if not s.enabled then raise exception 'BREEDING_DISABLED'; end if;
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if p_my_nft_id = p_partner_nft_id then raise exception 'SAME_NFT_NOT_ALLOWED'; end if;
  perform public.nft_breeding_expire_stale();

  select * into a from public.nft_pets where id = p_my_nft_id for update;
  select * into b from public.nft_pets where id = p_partner_nft_id for update;
  if a.owner_user_id is distinct from u then raise exception 'NOT_YOUR_NFT'; end if;
  reason := public.nft_breeding_block_reason(a.id); if reason is not null then raise exception '%', reason; end if;
  reason := public.nft_breeding_block_reason(b.id); if reason is not null then raise exception '%', reason; end if;

  insert into public.nft_breeding_requests(initiator_user_id, partner_user_id, nft_a_id, nft_b_id,
      breed_number_a, breed_number_b, cost_a, cost_b, self_breed, status, expires_at)
  values (u, b.owner_user_id, a.id, b.id, a.breed_count + 1, b.breed_count + 1,
      public.breeding_cost(a.breed_count + 1), public.breeding_cost(b.breed_count + 1),
      b.owner_user_id = u, case when b.owner_user_id = u then 'accepted' else 'pending' end,
      now() + make_interval(mins => s.request_ttl_minutes))
  returning * into req;

  return jsonb_build_object('ok', true, 'requestId', req.id, 'status', req.status,
    'costA', req.cost_a, 'costB', req.cost_b, 'selfBreed', req.self_breed, 'expiresAt', req.expires_at);
end $$;

create or replace function public.nft_breeding_respond(p_telegram_id bigint, p_request_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; req public.nft_breeding_requests;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  select * into req from public.nft_breeding_requests where id = p_request_id for update;
  if req.id is null then raise exception 'REQUEST_NOT_FOUND'; end if;
  if req.partner_user_id <> u then raise exception 'NOT_YOUR_REQUEST'; end if;
  if req.status <> 'pending' then raise exception 'REQUEST_NOT_PENDING'; end if;
  update public.nft_breeding_requests set status = case when p_accept then 'accepted' else 'declined' end,
     updated_at = now() where id = req.id;
  return jsonb_build_object('ok', true, 'status', case when p_accept then 'accepted' else 'declined' end);
end $$;

-- Rolls a sub-NFT for one owner
create or replace function public.sub_nft_mint(p_owner uuid, p_req public.nft_breeding_requests, p_cost numeric, p_side text)
returns uuid language plpgsql security definer set search_path = public as $$
declare s public.nft_breeding_settings; tpl public.sub_nft_templates; el_a text; el_b text;
        trait text; sn public.sub_nfts; v_pet uuid; v_id uuid; v_serial bigint;
begin
  select * into s from public.nft_breeding_settings where id;
  select coalesce(element,'neutral') into el_a from public.nft_pets where id = p_req.nft_a_id;
  select coalesce(element,'neutral') into el_b from public.nft_pets where id = p_req.nft_b_id;

  select * into tpl from public.sub_nft_templates
   where enabled and (element in (el_a, el_b) or coalesce(secondary_element,'') in (el_a, el_b))
   order by random() limit 1;
  if tpl.id is null then
    select * into tpl from public.sub_nft_templates where enabled order by random() limit 1;
  end if;
  if tpl.id is null then raise exception 'NO_SUB_NFT_TEMPLATE'; end if;

  select code into trait from public.sub_nft_traits where enabled order by random() * (1.0 / greatest(weight,1)) limit 1;
  v_serial := nextval('public.sub_nft_serial_seq');

  insert into public.sub_nfts(serial, unique_instance_id, owner_user_id, template_id, breeding_id,
      parent_a_nft_id, parent_b_nft_id, generation, trait_code, birth_time, maturity_stage, matures_at,
      mining_rate_ton_day, mining_cap_ton)
  values (v_serial, 'SUB-NFT #' || lpad(v_serial::text, 6, '0'), p_owner, tpl.id, p_req.id,
      p_req.nft_a_id, p_req.nft_b_id, 1, trait, now(), 'EGG', now() + make_interval(hours => s.adult_hours),
      round(p_cost * s.sub_rate_per_ton, 9), round(p_cost, 9))
  returning id into v_id;

  return v_id;
end $$;

create or replace function public.nft_breeding_pay(p_telegram_id bigint, p_request_id uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; req public.nft_breeding_requests; s public.nft_breeding_settings;
        side text; amount numeric; owner_a uuid; owner_b uuid; egg_a uuid; egg_b uuid; reason text;
begin
  select * into s from public.nft_breeding_settings where id;
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended('breeding:'||p_request_id::text, 0));
  perform public.nft_breeding_expire_stale();

  select * into req from public.nft_breeding_requests where id = p_request_id for update;
  if req.id is null then raise exception 'REQUEST_NOT_FOUND'; end if;
  if req.status = 'completed' then return jsonb_build_object('ok', true, 'status', 'already_completed'); end if;
  if req.status not in ('pending','accepted') then raise exception 'REQUEST_NOT_OPEN'; end if;
  if req.expires_at <= now() then raise exception 'BREEDING_EXPIRED'; end if;

  select owner_user_id into owner_a from public.nft_pets where id = req.nft_a_id for update;
  select owner_user_id into owner_b from public.nft_pets where id = req.nft_b_id for update;
  if owner_a is null or owner_b is null then raise exception 'NFT_NOT_OWNED'; end if;

  if req.self_breed then
    if u <> owner_a or u <> owner_b then raise exception 'NOT_YOUR_REQUEST'; end if;
    side := 'both';
  elsif u = owner_a and req.initiator_user_id = u then side := 'a';
  elsif u = owner_b then side := 'b';
  else raise exception 'NOT_YOUR_REQUEST'; end if;

  if side in ('a','both') and not req.paid_a then
    amount := req.cost_a;
    perform public.debit_ton_balance(owner_a, amount, 'nft_breeding', req.id::text || ':a', 'NFT Breeding');
    perform public.record_spending_points(owner_a, 'nft_breeding', 'breeding:'||req.id::text||':a', 'TON', amount);
    perform public.referral_pay_ton_commission(owner_a, 'nft_breeding', req.id::text||':a', amount);
    update public.nft_breeding_requests set paid_a = true, updated_at = now() where id = req.id;
    req.paid_a := true;
  end if;
  if side in ('b','both') and not req.paid_b then
    amount := req.cost_b;
    perform public.debit_ton_balance(owner_b, amount, 'nft_breeding', req.id::text || ':b', 'NFT Breeding');
    perform public.record_spending_points(owner_b, 'nft_breeding', 'breeding:'||req.id::text||':b', 'TON', amount);
    perform public.referral_pay_ton_commission(owner_b, 'nft_breeding', req.id::text||':b', amount);
    update public.nft_breeding_requests set paid_b = true, updated_at = now() where id = req.id;
    req.paid_b := true;
  end if;

  if not (req.paid_a and req.paid_b) then
    return jsonb_build_object('ok', true, 'status', 'waiting_partner', 'paidA', req.paid_a, 'paidB', req.paid_b);
  end if;

  -- both paid: final validation then atomic delivery
  if (select breed_count from public.nft_pets where id = req.nft_a_id) >= s.max_breeds
     or (select breed_count from public.nft_pets where id = req.nft_b_id) >= s.max_breeds then
    raise exception 'MAX_BREEDING_REACHED';
  end if;

  update public.nft_pets set breed_count = breed_count + 1,
      breeding_cooldown_until = now() + make_interval(mins => (s.cooldown_days * 24 * 60)::int), updated_at = now()
   where id in (req.nft_a_id, req.nft_b_id);

  egg_a := public.sub_nft_mint(owner_a, req, req.cost_a, 'a');
  egg_b := public.sub_nft_mint(owner_b, req, req.cost_b, 'b');

  update public.nft_breeding_requests set status = 'completed', completed_at = now(), updated_at = now() where id = req.id;

  insert into public.nft_breeding_history(breeding_id, parent_a_nft_id, parent_b_nft_id, owner_a_user_id, owner_b_user_id,
      cost_a, cost_b, breed_number_a, breed_number_b, egg_a_sub_nft_id, egg_b_sub_nft_id)
  values (req.id, req.nft_a_id, req.nft_b_id, owner_a, owner_b, req.cost_a, req.cost_b,
      req.breed_number_a, req.breed_number_b, egg_a, egg_b);

  return jsonb_build_object('ok', true, 'status', 'completed', 'eggA', egg_a, 'eggB', egg_b);
end $$;

-- 11. CLAIM SUB-NFT MINING --------------------------------------------------
create or replace function public.sub_nft_claim(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; s public.nft_breeding_settings; total numeric;
begin
  select * into s from public.nft_breeding_settings where id;
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);
  select coalesce(sum(unclaimed_ton), 0) into total from public.sub_nfts where owner_user_id = u;
  if total < s.min_claim_ton then raise exception 'CLAIM_BELOW_MINIMUM'; end if;
  update public.sub_nfts set unclaimed_ton = 0, updated_at = now() where owner_user_id = u and unclaimed_ton > 0;
  perform public.credit_ton_reward(u, round(total, 9), 'sub_nft_mining', gen_random_uuid()::text, 'Sub-NFT mining claim');
  return jsonb_build_object('ok', true, 'claimedTon', round(total, 9));
end $$;

-- 12. BREEDING DASHBOARD ----------------------------------------------------
create or replace function public.nft_breeding_state(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; s public.nft_breeding_settings;
begin
  select * into s from public.nft_breeding_settings where id;
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_breeding_expire_stale();
  perform public.sub_nft_sync(u);

  return jsonb_build_object(
    'enabled', s.enabled,
    'settings', jsonb_build_object('maxBreeds', s.max_breeds, 'cooldownDays', s.cooldown_days,
        'costs', jsonb_build_array(s.cost_breed_1, s.cost_breed_2, s.cost_breed_3),
        'ttlMinutes', s.request_ttl_minutes, 'minClaimTon', s.min_claim_ton,
        'maturity', jsonb_build_object('babyHours', s.baby_hours, 'juvenileHours', s.juvenile_hours, 'adultHours', s.adult_hours)),
    'tonBalance', (select round(coalesce(ton_balance,0), 4) from public.game_players where id = u),
    'myNfts', coalesce((select jsonb_agg(jsonb_build_object(
          'nftId', n.id, 'serial', n.nft_serial, 'instance', n.unique_instance_id,
          'name', p.name, 'image', p.image_adult_url, 'element', coalesce(n.element,'neutral'),
          'breedCount', n.breed_count, 'maxBreeds', s.max_breeds,
          'cooldownUntil', n.breeding_cooldown_until,
          'nextCost', public.breeding_cost(n.breed_count + 1),
          'blockReason', public.nft_breeding_block_reason(n.id)
        ) order by n.nft_serial)
      from public.nft_pets n join public.pets p on p.id = n.pet_template_id
      where n.owner_user_id = u), '[]'::jsonb),
    'incoming', coalesce((select jsonb_agg(jsonb_build_object(
          'requestId', r.id, 'status', r.status, 'yourCost', r.cost_b, 'expiresAt', r.expires_at,
          'paidYou', r.paid_b, 'paidPartner', r.paid_a,
          'fromName', gp.display_name, 'fromUsername', gp.username,
          'yourNft', (select jsonb_build_object('serial', nb.nft_serial, 'name', pb.name, 'image', pb.image_adult_url)
                        from public.nft_pets nb join public.pets pb on pb.id = nb.pet_template_id where nb.id = r.nft_b_id),
          'partnerNft', (select jsonb_build_object('serial', na.nft_serial, 'name', pa.name, 'image', pa.image_adult_url)
                        from public.nft_pets na join public.pets pa on pa.id = na.pet_template_id where na.id = r.nft_a_id))
        order by r.created_at desc)
      from public.nft_breeding_requests r join public.game_players gp on gp.id = r.initiator_user_id
      where r.partner_user_id = u and not r.self_breed and r.status in ('pending','accepted') and r.expires_at > now()), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object(
          'requestId', r.id, 'status', r.status, 'yourCost', r.cost_a, 'partnerCost', r.cost_b,
          'selfBreed', r.self_breed, 'expiresAt', r.expires_at, 'paidYou', r.paid_a, 'paidPartner', r.paid_b,
          'partnerName', gp.display_name,
          'yourNft', (select jsonb_build_object('serial', na.nft_serial, 'name', pa.name, 'image', pa.image_adult_url)
                        from public.nft_pets na join public.pets pa on pa.id = na.pet_template_id where na.id = r.nft_a_id),
          'partnerNft', (select jsonb_build_object('serial', nb.nft_serial, 'name', pb.name, 'image', pb.image_adult_url)
                        from public.nft_pets nb join public.pets pb on pb.id = nb.pet_template_id where nb.id = r.nft_b_id))
        order by r.created_at desc)
      from public.nft_breeding_requests r join public.game_players gp on gp.id = r.partner_user_id
      where r.initiator_user_id = u and r.status in ('pending','accepted') and r.expires_at > now()), '[]'::jsonb),
    'subNfts', coalesce((select jsonb_agg(jsonb_build_object(
          'id', sn.id, 'instance', sn.unique_instance_id, 'serial', sn.serial,
          'name', t.name, 'image', t.image_url, 'element', t.element,
          'stage', sn.maturity_stage, 'birthTime', sn.birth_time, 'maturesAt', sn.matures_at,
          'generation', sn.generation, 'trait', sn.trait_code,
          'traitName', (select tr.name from public.sub_nft_traits tr where tr.code = sn.trait_code),
          'miningStatus', sn.mining_status, 'rateTonDay', sn.mining_rate_ton_day,
          'capTon', sn.mining_cap_ton, 'minedTon', round(sn.lifetime_mined_ton, 6),
          'unclaimedTon', round(sn.unclaimed_ton, 6),
          'parents', jsonb_build_object(
              'a', (select jsonb_build_object('serial', na.nft_serial, 'name', pa.name) from public.nft_pets na join public.pets pa on pa.id = na.pet_template_id where na.id = sn.parent_a_nft_id),
              'b', (select jsonb_build_object('serial', nb.nft_serial, 'name', pb.name) from public.nft_pets nb join public.pets pb on pb.id = nb.pet_template_id where nb.id = sn.parent_b_nft_id))
        ) order by sn.serial desc)
      from public.sub_nfts sn join public.sub_nft_templates t on t.id = sn.template_id
      where sn.owner_user_id = u), '[]'::jsonb),
    'unclaimedTon', (select round(coalesce(sum(unclaimed_ton),0), 6) from public.sub_nfts where owner_user_id = u)
  );
end $$;

create or replace function public.nft_breeding_search_partner(p_telegram_id bigint, p_query text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; q text;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  q := lower(trim(coalesce(p_query, '')));
  if length(q) < 2 then raise exception 'QUERY_TOO_SHORT'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'nftId', n.id, 'serial', n.nft_serial, 'name', p.name, 'image', p.image_adult_url,
      'element', coalesce(n.element,'neutral'), 'breedCount', n.breed_count,
      'nextCost', public.breeding_cost(n.breed_count + 1),
      'ownerName', gp.display_name, 'ownerUsername', gp.username, 'ownerTelegramId', gp.telegram_id)
    order by n.nft_serial)
    from public.nft_pets n
    join public.game_players gp on gp.id = n.owner_user_id
    join public.pets p on p.id = n.pet_template_id
    where n.owner_user_id is not null and n.owner_user_id <> u
      and public.nft_breeding_block_reason(n.id) is null
      and (lower(coalesce(gp.username,'')) like '%'||q||'%'
        or lower(coalesce(gp.display_name,'')) like '%'||q||'%'
        or gp.telegram_id::text = q
        or lower(coalesce(n.unique_instance_id,'')) like '%'||q||'%')), '[]'::jsonb);
end $$;

-- 13. EXPEDITIONS FLOW ------------------------------------------------------
create or replace function public.expedition_success_chance(p_power integer, p_required integer, p_bonus numeric)
returns integer language sql immutable security definer set search_path = public as $$
  select greatest(15, least(95, round(70 + ((p_power::numeric / greatest(p_required,1)) - 1) * 50 + coalesce(p_bonus,0))))::int
$$;

create or replace function public.expedition_state(p_telegram_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; busy uuid[];
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);
  select coalesce(array_agg(pid), '{}') into busy
    from (select unnest(pet_ids) pid from public.pet_expeditions where user_id = u and status = 'ACTIVE') b;

  return jsonb_build_object(
    'pets', coalesce((select jsonb_agg(jsonb_build_object(
        'playerPetId', pp.id, 'name', p.name,
        'image', coalesce(sn_t.image_url, p.image_adult_url, p.image_baby_url),
        'rarity', pp.rarity, 'level', pp.level, 'power', public.pet_instance_power(pp.id),
        'isSubNft', sn.id is not null, 'stage', sn.maturity_stage,
        'trait', sn.trait_code,
        'eligible', (sn.id is null or sn.maturity_stage = 'ADULT') and not (pp.id = any(busy)),
        'busy', pp.id = any(busy)) order by public.pet_instance_power(pp.id) desc)
      from public.player_pets pp
      join public.pets p on p.id = pp.pet_id
      left join public.sub_nfts sn on sn.player_pet_id = pp.id or sn.id = pp.sub_nft_id
      left join public.sub_nft_templates sn_t on sn_t.id = sn.template_id
      where pp.user_id = u), '[]'::jsonb),
    'missions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'code', m.code, 'name', m.name, 'rarity', m.rarity,
        'durationHours', m.duration_hours, 'requiredPower', m.required_power,
        'element', m.recommended_element, 'rewards', m.reward_pool) order by m.sort_order)
      from public.expedition_missions m where m.enabled), '[]'::jsonb),
    'active', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'missionRarity', m.rarity,
        'startedAt', e.started_at, 'finishesAt', e.finishes_at,
        'teamPower', e.team_power, 'successChance', e.success_chance,
        'ready', e.finishes_at <= now(),
        'pets', (select jsonb_agg(jsonb_build_object('name', p2.name, 'image', coalesce(p2.image_adult_url, p2.image_baby_url)))
                   from public.player_pets pp2 join public.pets p2 on p2.id = pp2.pet_id where pp2.id = any(e.pet_ids)))
        order by e.finishes_at)
      from public.pet_expeditions e join public.expedition_missions m on m.id = e.mission_id
      where e.user_id = u and e.status = 'ACTIVE'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'success', e.success, 'rewards', e.rewards, 'claimedAt', e.claimed_at)
        order by e.claimed_at desc)
      from (select * from public.pet_expeditions where user_id = u and status = 'CLAIMED' order by claimed_at desc limit 10) e
      join public.expedition_missions m on m.id = e.mission_id), '[]'::jsonb));
end $$;

create or replace function public.expedition_start(p_telegram_id bigint, p_mission_id uuid, p_pet_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; m public.expedition_missions; total int := 0; bonus numeric := 0; chance int;
        pid uuid; sn public.sub_nfts; dur numeric; e public.pet_expeditions;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select * into m from public.expedition_missions where id = p_mission_id and enabled;
  if m.id is null then raise exception 'MISSION_NOT_FOUND'; end if;
  if array_length(p_pet_ids, 1) is distinct from 3 then raise exception 'TEAM_MUST_HAVE_3_PETS'; end if;
  if (select count(distinct x) from unnest(p_pet_ids) x) <> 3 then raise exception 'DUPLICATED_PET'; end if;

  dur := m.duration_hours;
  foreach pid in array p_pet_ids loop
    if not exists (select 1 from public.player_pets where id = pid and user_id = u) then raise exception 'PET_NOT_YOURS'; end if;
    if exists (select 1 from public.pet_expeditions where user_id = u and status = 'ACTIVE' and pid = any(pet_ids)) then
      raise exception 'PET_ON_EXPEDITION'; end if;
    select * into sn from public.sub_nfts where player_pet_id = pid or id = (select sub_nft_id from public.player_pets where id = pid);
    if sn.id is not null and sn.maturity_stage <> 'ADULT' then raise exception 'SUB_NFT_NOT_ADULT'; end if;
    total := total + public.pet_instance_power(pid);
    if sn.trait_code is not null then
      select case tr.effect_key
               when 'mission_success' then tr.effect_value
               when 'long_mission_success' then case when m.duration_hours >= 8 then tr.effect_value else 0 end
               else 0 end
        into bonus from public.sub_nft_traits tr where tr.code = sn.trait_code and tr.enabled;
      bonus := coalesce(bonus, 0);
      if sn.trait_code = 'swift' then dur := dur * 0.95; end if;
    end if;
  end loop;

  chance := public.expedition_success_chance(total, m.required_power, bonus);

  insert into public.pet_expeditions(user_id, mission_id, pet_ids, team_power, success_chance, finishes_at)
  values (u, m.id, p_pet_ids, total, chance, now() + make_interval(mins => (dur * 60)::int))
  returning * into e;

  return jsonb_build_object('ok', true, 'expeditionId', e.id, 'teamPower', total, 'successChance', chance, 'finishesAt', e.finishes_at);
end $$;

create or replace function public.expedition_claim(p_telegram_id bigint, p_expedition_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid; e public.pet_expeditions; m public.expedition_missions; entry jsonb;
        won boolean; qty int; out_rewards jsonb := '[]'::jsonb; tpl public.equipment_templates;
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
          insert into public.player_pet_food(user_id, food_code, quantity)
          values (u, coalesce(entry->>'code','basic_kibble'), qty)
          on conflict (user_id, food_code) do update set quantity = public.player_pet_food.quantity + excluded.quantity, updated_at = now();
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
        'code', coalesce(entry->>'code', entry->>'rarity', ''), 'quantity', qty));
    end loop;
  end if;

  update public.pet_expeditions set status = 'CLAIMED', success = won, rewards = out_rewards, claimed_at = now()
   where id = e.id;

  return jsonb_build_object('ok', true, 'success', won, 'rewards', out_rewards);
end $$;

-- 14. LOCK DOWN EXECUTION ---------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array['breeding_settings(  )','breeding_cost(integer)','pet_instance_power(uuid)',
      'nft_breeding_block_reason(uuid)','nft_breeding_expire_stale()','sub_nft_sync(uuid)',
      'nft_breeding_request_create(bigint,uuid,uuid)','nft_breeding_respond(bigint,uuid,boolean)',
      'sub_nft_mint(uuid,public.nft_breeding_requests,numeric,text)','nft_breeding_pay(bigint,uuid,text)',
      'sub_nft_claim(bigint)','nft_breeding_state(bigint)','nft_breeding_search_partner(bigint,text)',
      'expedition_success_chance(integer,integer,numeric)','expedition_state(bigint)',
      'expedition_start(bigint,uuid,uuid[])','expedition_claim(bigint,uuid)']
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', replace(fn,'(  )','()'));
    execute format('grant execute on function public.%s to service_role', replace(fn,'(  )','()'));
  end loop;
end $$;
