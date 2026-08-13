-- 1. Starter pack state on the player row
ALTER TABLE public.game_players
  ADD COLUMN IF NOT EXISTS starter_pack_claimed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS starter_pack_claimed_at timestamptz;

-- 2. Uncommon-only hero chest (NFT heroes are already excluded by roll_hero_for_rarity)
INSERT INTO public.chest_reward_tables(chest_code, name, subtitle, rarity_rates, enabled)
VALUES ('uncommon_hero_chest', 'Baú de Herói Incomum', 'Incomum', '{"uncommon":100}'::jsonb, true)
ON CONFLICT (chest_code) DO UPDATE
  SET name = excluded.name, subtitle = excluded.subtitle,
      rarity_rates = excluded.rarity_rates, enabled = true, updated_at = now();

-- 3. Cutoff + eligibility
CREATE OR REPLACE FUNCTION public.starter_pack_cutoff()
RETURNS timestamptz LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  select '2026-08-13T00:00:00-03:00'::timestamptz;
$$;

CREATE OR REPLACE FUNCTION public.get_starter_pack_status(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
declare pl public.game_players;
begin
  select * into pl from public.game_players where telegram_id = p_telegram_id;
  if pl.id is null then
    return jsonb_build_object('show', false, 'eligible', false, 'claimed', false);
  end if;
  return jsonb_build_object(
    'show', (pl.created_at >= public.starter_pack_cutoff()) and not coalesce(pl.starter_pack_claimed, false) and not coalesce(pl.banned, false),
    'eligible', pl.created_at >= public.starter_pack_cutoff(),
    'claimed', coalesce(pl.starter_pack_claimed, false),
    'claimedAt', pl.starter_pack_claimed_at,
    'rewards', jsonb_build_object('fc', 50000, 'eggCode', 'common-egg', 'eggQuantity', 1,
                                  'chestCode', 'uncommon_hero_chest', 'chestQuantity', 2)
  );
end $$;

-- 4. Atomic, idempotent claim
CREATE OR REPLACE FUNCTION public.claim_starter_pack(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare pl public.game_players; v_egg uuid; v_updated int;
begin
  select * into pl from public.game_players where telegram_id = p_telegram_id for update;
  if pl.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if pl.banned then raise exception 'PLAYER_BANNED'; end if;
  if pl.created_at < public.starter_pack_cutoff() then raise exception 'STARTER_PACK_NOT_ELIGIBLE'; end if;

  -- single-writer guard: only the transaction that flips the flag delivers the pack
  update public.game_players
    set starter_pack_claimed = true, starter_pack_claimed_at = now(),
        forge_coins = coalesce(forge_coins, 0) + 50000, updated_at = now()
    where id = pl.id and coalesce(starter_pack_claimed, false) = false;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    return jsonb_build_object('claimed', true, 'alreadyClaimed', true,
      'message', 'Starter Pack already claimed',
      'status', public.get_starter_pack_status(p_telegram_id));
  end if;

  select id into v_egg from public.pet_eggs where slug = 'common-egg' and is_enabled;
  if v_egg is null then raise exception 'STARTER_EGG_NOT_FOUND'; end if;
  insert into public.player_pet_inventory(user_id, item_type, item_id, quantity)
  values (pl.id, 'egg', v_egg, 1)
  on conflict (user_id, item_type, (coalesce(item_id,'00000000-0000-0000-0000-000000000000'::uuid)))
  do update set quantity = public.player_pet_inventory.quantity + 1, updated_at = now();

  insert into public.player_inventory(user_id, item_type, item_code, quantity)
  values (pl.id, 'hero_chest', 'uncommon_hero_chest', 2)
  on conflict (user_id, item_type, item_code)
  do update set quantity = public.player_inventory.quantity + 2, updated_at = now();

  return jsonb_build_object(
    'claimed', true, 'alreadyClaimed', false,
    'granted', jsonb_build_object('fc', 50000, 'eggCode', 'common-egg', 'eggQuantity', 1,
                                  'chestCode', 'uncommon_hero_chest', 'chestQuantity', 2),
    'balance', (select forge_coins from public.game_players where id = pl.id),
    'status', public.get_starter_pack_status(p_telegram_id)
  );
end $$;

REVOKE ALL ON FUNCTION public.get_starter_pack_status(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_starter_pack(bigint) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.starter_pack_cutoff() FROM anon, authenticated;

-- 5. Tower: floors 1-10 at 50% difficulty (progression preserved, rewards/costs untouched)
CREATE OR REPLACE FUNCTION public.tower_boss_for_floor(p_floor integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
declare f int := greatest(1, least(100, coalesce(p_floor,1)));
  b public.tower_bosses; tier int; step int; mult numeric; hp numeric; atk numeric; def numeric; dmult numeric;
begin
  select * into b from public.tower_bosses where floor_index = ((f - 1) % 10) + 1;
  if b.boss_key is null then raise exception 'TOWER_BOSS_MISSING'; end if;
  tier := ceil(f / 10.0)::int;            -- 1..10
  step := ((f - 1) % 10);                 -- 0..9 inside the tier
  dmult := case when f <= 10 then 0.50 else 1.0 end;  -- beginner curve on the first tier only
  mult := power(1.55, tier - 1) * (1 + 0.06 * step);
  hp  := round(b.base_hp * mult * dmult);
  atk := round(b.base_atk * power(1.34, tier - 1) * (1 + 0.04 * step) * dmult);
  def := round(b.base_def * power(1.22, tier - 1) * (1 + 0.03 * step) * dmult);
  return jsonb_build_object(
    'heroId','tower-boss','name',b.name,'bossKey',b.boss_key,'theme',b.theme,'role',b.role,
    'behavior',b.behavior,'floor',f,'tier',tier,'rarity','boss',
    'finalHp',hp,'finalAtk',atk,'defense',def,'speed',b.base_speed + tier,
    'level',f,'imageUrl',null,'difficultyMultiplier',dmult,
    'recommendedPower', round(hp * 0.35 + atk * 6)::bigint,
    'entryCost', public.tower_entry_cost(f)
  );
end $$;
