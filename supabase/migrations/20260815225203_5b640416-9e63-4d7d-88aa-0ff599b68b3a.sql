-- ============================================================
-- FIX 1: PET POWER — ÚNICA FONTE DE VERDADE
-- pet_instance_power não cobria mythic/ancestral/exclusive/nft_exclusive
-- (caía no ELSE 500 => Astravax nível 2 = 700). player_pet_json tinha
-- uma segunda fórmula inline (9.200). Agora existe UMA função oficial.
-- ============================================================
CREATE OR REPLACE FUNCTION public.pet_rarity_base_power(p_rarity text, p_is_nft boolean DEFAULT false)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  select case
    when coalesce(p_is_nft, false) or lower(coalesce(p_rarity,'')) like 'nft%' then 12000
    else case lower(coalesce(p_rarity,''))
      when 'ancestral' then 10000
      when 'exclusive' then 9500
      when 'mythic' then 9000
      when 'legendary' then 8000
      when 'epic' then 4000
      when 'rare' then 2000
      when 'uncommon' then 1000
      else 500
    end
  end::numeric
$$;

DROP FUNCTION IF EXISTS public.pet_instance_power(uuid);
CREATE OR REPLACE FUNCTION public.pet_instance_power(p_player_pet_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  select public.pet_rarity_base_power(
             pp.rarity,
             coalesce(p.is_nft_exclusive, false) or pp.nft_pet_id is not null
           )
       + coalesce(pp.level, 1) * 100
       + coalesce((select round(sum((value#>>'{}')::numeric) * 250)
                     from jsonb_each(public.player_pet_buffs(pp.id))), 0)
  from public.player_pets pp
  join public.pets p on p.id = pp.pet_id
  where pp.id = p_player_pet_id
$$;

REVOKE ALL ON FUNCTION public.pet_rarity_base_power(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pet_instance_power(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pet_rarity_base_power(text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.pet_instance_power(uuid) TO service_role;

-- player_pet_json passa a delegar o Power para a função oficial
CREATE OR REPLACE FUNCTION public.player_pet_json(p_player_pet_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE ppet record; nxt record; buffs jsonb; pkey text; pbase numeric; maxlvl int; nftj jsonb; is_nft boolean;
BEGIN
  SELECT ppet2.*, p.name, p.slug, p.species, p.category, p.base_passives, p.active_skill,
         p.image_baby_url, p.image_young_url, p.image_adult_url, p.image_ancestral_url,
         p.is_nft_exclusive
    INTO ppet FROM player_pets ppet2 JOIN pets p ON p.id = ppet2.pet_id WHERE ppet2.id = p_player_pet_id;
  IF NOT found THEN RETURN NULL; END IF;
  maxlvl := pet_max_level();
  buffs := player_pet_buffs(ppet.id);
  is_nft := coalesce(ppet.is_nft_exclusive, false)
            OR ppet.nft_pet_id IS NOT NULL
            OR lower(coalesce(ppet.rarity,'')) LIKE 'nft%';
  SELECT key, (value#>>'{}')::numeric INTO pkey, pbase
    FROM jsonb_each(coalesce(ppet.base_passives,'{}'::jsonb)) ORDER BY (value#>>'{}')::numeric DESC LIMIT 1;
  SELECT * INTO nxt FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier + 1 AND enabled;
  SELECT jsonb_build_object('serial', n.nft_serial, 'instanceId', n.unique_instance_id,
      'status', n.status, 'minted', n.minted)
    INTO nftj FROM nft_pets n WHERE n.id = ppet.nft_pet_id;
  RETURN jsonb_build_object(
    'id', ppet.id, 'petId', ppet.pet_id, 'name', ppet.name, 'slug', ppet.slug, 'species', ppet.species,
    'category', ppet.category,
    'rarity', CASE WHEN is_nft THEN 'nft_exclusive' ELSE ppet.rarity END,
    'level', ppet.level, 'maxLevel', maxlvl,
    'xp', ppet.xp, 'xpRequired', CASE WHEN ppet.level >= maxlvl THEN 0 ELSE pet_level_xp_required(ppet.level) END,
    'isMaxLevel', ppet.level >= maxlvl,
    'evolutionTier', ppet.evolution_tier,
    'evolutionLabel', coalesce((SELECT label FROM pet_evolution_tiers WHERE tier = ppet.evolution_tier), 'Forma Base'),
    'evolutionStage', ppet.evolution_stage,
    'fragments', ppet.fragments, 'isActive', ppet.is_active,
    'image', public.pet_visual_image(ppet.pet_id, ppet.level),
    'visualStage', public.pet_visual_index(ppet.level),
    'buffs', buffs,
    'primaryBuffKey', pkey,
    'primaryBuffValue', coalesce((buffs->>pkey)::numeric, 0),
    'secondaryBuffs', coalesce(ppet.secondary_buffs,'[]'::jsonb),
    'power', public.pet_instance_power(ppet.id),
    'activeSkill', ppet.active_skill,
    'isNft', is_nft,
    'nftSerial', (nftj->>'serial')::int,
    'nft', nftj,
    'nextEvolution', CASE WHEN nxt.tier IS NULL THEN NULL ELSE jsonb_build_object(
        'tier', nxt.tier, 'label', nxt.label, 'requiredLevel', nxt.required_level,
        'fcCost', nxt.fc_cost, 'fragmentCost', nxt.fragment_cost,
        'newBuffChance', round(nxt.new_buff_chance * 100),
        'maxSecondaryBuffs', nxt.max_secondary_buffs,
        'primaryFrom', coalesce((buffs->>pkey)::numeric, 0),
        'primaryTo', round(coalesce(pbase,0) * pet_rarity_multiplier(ppet.rarity)
                     * (1 + (ppet.level - 1) * 0.02) * nxt.primary_multiplier, 2)
      ) END,
    'canEvolve', nxt.tier IS NOT NULL AND ppet.level >= nxt.required_level
  );
END $$;

-- ============================================================
-- FIX 2: STATS DE COMBATE DO BOSS RESPEITANDO RARIDADE + INSTÂNCIA
-- rarity_base_atk/hp não tinham mythic/ancestral/nft_exclusive: caíam
-- no ELSE (1.875 ATK / 100 HP), ficando abaixo de uncommon (1.975).
-- Tabela agora é monotônica e nunca reduz valores atuais.
-- ============================================================
DROP FUNCTION IF EXISTS public.rarity_base_atk(text);
CREATE OR REPLACE FUNCTION public.rarity_base_atk(r text)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  select case public.normalize_hero_rarity(r)
    when 'uncommon' then 1.975
    when 'rare' then 2.165
    when 'epic' then 2.395
    when 'legendary' then 2.680
    when 'mythic' then 3.100
    when 'ancestral' then 3.650
    when 'nft_exclusive' then 4.300
    else 1.875 end
$$;

DROP FUNCTION IF EXISTS public.rarity_base_hp(text);
CREATE OR REPLACE FUNCTION public.rarity_base_hp(r text)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  select case public.normalize_hero_rarity(r)
    when 'uncommon' then 130
    when 'rare' then 170
    when 'epic' then 220
    when 'legendary' then 300
    when 'mythic' then 420
    when 'ancestral' then 560
    when 'nft_exclusive' then 720
    else 100 end
$$;

-- Ponto médio de ATK/HP por raridade (mesma escala de hero_stat_ranges),
-- usado para refletir a qualidade real da instância no combate do boss.
CREATE OR REPLACE FUNCTION public.hero_rarity_mid_atk(r text)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  select case public.normalize_hero_rarity(r)
    when 'uncommon' then 185 when 'rare' then 240 when 'epic' then 305
    when 'legendary' then 400 when 'mythic' then 560 when 'ancestral' then 775
    when 'nft_exclusive' then 1010 else 140 end
$$;

CREATE OR REPLACE FUNCTION public.hero_rarity_mid_hp(r text)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  select case public.normalize_hero_rarity(r)
    when 'uncommon' then 1850 when 'rare' then 2400 when 'epic' then 3050
    when 'legendary' then 4000 when 'mythic' then 5600 when 'ancestral' then 7750
    when 'nft_exclusive' then 10075 else 1400 end
$$;

-- Fonte única dos stats de combate do boss por instância de herói.
CREATE OR REPLACE FUNCTION public.hero_boss_stats(p_player_hero_id uuid)
RETURNS TABLE(base_atk numeric, final_atk numeric, base_hp numeric, max_hp int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  select
    public.rarity_base_atk(h.rarity),
    round((public.rarity_base_atk(h.rarity)
       * (1 + (greatest(1, h.level) - 1) * 0.03)
       * least(1.30, greatest(1.00, coalesce(h.final_atk,0) / public.hero_rarity_mid_atk(h.rarity))))::numeric, 3),
    public.rarity_base_hp(h.rarity),
    round(public.rarity_base_hp(h.rarity)
       * (1 + (greatest(1, h.level) - 1) * 0.05)
       * least(1.30, greatest(1.00, coalesce(h.final_hp,0) / public.hero_rarity_mid_hp(h.rarity))))::int
  from public.player_heroes h where h.id = p_player_hero_id
$$;

REVOKE ALL ON FUNCTION public.hero_boss_stats(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_rarity_mid_atk(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hero_rarity_mid_hp(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_boss_stats(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_rarity_mid_atk(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.hero_rarity_mid_hp(text) TO service_role;

CREATE OR REPLACE FUNCTION public.boss_team_json(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',h.id,'heroId',h.id,'name',h.name,'image',h.image,
    'rarity',public.normalize_hero_rarity(h.rarity),'slot',ts.slot,'level',greatest(1,h.level),
    'baseAtk',s.base_atk,'finalAtk',s.final_atk,
    'baseHp',s.base_hp,'maxHp',s.max_hp,'currentHp',s.max_hp,
    'isAlive',true,'knockedOutAt',null,'reviveAt',null) order by ts.slot),'[]'::jsonb)
  from public.boss_team_slots ts
  join public.player_heroes h on h.id=ts.player_hero_id
  cross join lateral public.hero_boss_stats(h.id) s
  where ts.user_id=p_user
$$;

CREATE OR REPLACE FUNCTION public.sync_boss_team_state(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare v_combat uuid; r record; old public.hero_combat_state%rowtype;
begin
  select id into v_combat from public.boss_combats where user_id=p_user and status='active' limit 1;
  if v_combat is null then return; end if;
  update public.hero_combat_state s set slot=null,updated_at=clock_timestamp()
  where s.combat_id=v_combat and s.slot is not null
    and not exists (select 1 from public.boss_team_slots ts where ts.user_id=p_user and ts.player_hero_id=s.hero_id);
  for r in select ts.slot as team_slot, h.*, st.base_atk as b_atk, st.final_atk as f_atk, st.base_hp as b_hp, st.max_hp as m_hp
             from public.boss_team_slots ts
             join public.player_heroes h on h.id=ts.player_hero_id
             cross join lateral public.hero_boss_stats(h.id) st
             where ts.user_id=p_user loop
    select * into old from public.hero_combat_state where combat_id=v_combat and hero_id=r.id;
    insert into public.hero_combat_state(combat_id,hero_id,slot,rarity,level,base_atk,final_atk,base_hp,max_hp,current_hp,is_alive,knocked_out_at,revive_at)
    values(v_combat,r.id,r.team_slot,public.normalize_hero_rarity(r.rarity),greatest(1,r.level),r.b_atk,r.f_atk,r.b_hp,r.m_hp,
      case when old.id is null then r.m_hp else least(r.m_hp,round(old.current_hp::numeric/nullif(old.max_hp,0)*r.m_hp)) end,
      coalesce(old.is_alive,true),old.knocked_out_at,old.revive_at)
    on conflict(combat_id,hero_id) do update set slot=excluded.slot,rarity=excluded.rarity,level=excluded.level,
      base_atk=excluded.base_atk,final_atk=excluded.final_atk,base_hp=excluded.base_hp,max_hp=excluded.max_hp,
      current_hp=least(excluded.max_hp,round(hero_combat_state.current_hp::numeric/nullif(hero_combat_state.max_hp,0)*excluded.max_hp)),
      is_alive=hero_combat_state.is_alive,knocked_out_at=hero_combat_state.knocked_out_at,
      revive_at=hero_combat_state.revive_at,updated_at=clock_timestamp();
  end loop;
end $$;

-- ============================================================
-- AUDITORIA DE BALANCEAMENTO (leitura, para o Bot Admin)
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_game_balance_overview(p_admin_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE res jsonb;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  SELECT jsonb_build_object(
    'heroRarities', coalesce((select jsonb_agg(jsonb_build_object(
        'rarity', t.r,
        'bossAtk', public.rarity_base_atk(t.r),
        'bossHp', public.rarity_base_hp(t.r),
        'midAtk', public.hero_rarity_mid_atk(t.r),
        'midHp', public.hero_rarity_mid_hp(t.r),
        'instances', (select count(*) from public.player_heroes ph where public.normalize_hero_rarity(ph.rarity)=t.r),
        'avgAtk', coalesce((select round(avg(ph.final_atk)) from public.player_heroes ph where public.normalize_hero_rarity(ph.rarity)=t.r),0),
        'minAtk', coalesce((select round(min(ph.final_atk)) from public.player_heroes ph where public.normalize_hero_rarity(ph.rarity)=t.r),0),
        'maxAtk', coalesce((select round(max(ph.final_atk)) from public.player_heroes ph where public.normalize_hero_rarity(ph.rarity)=t.r),0),
        'avgHp', coalesce((select round(avg(ph.final_hp)) from public.player_heroes ph where public.normalize_hero_rarity(ph.rarity)=t.r),0)
      ) order by t.idx) from unnest(array['common','uncommon','rare','epic','legendary','mythic','ancestral','nft_exclusive'])
        with ordinality as t(r, idx)), '[]'::jsonb),
    'petRarities', coalesce((select jsonb_agg(jsonb_build_object(
        'rarity', t.r,
        'basePower', public.pet_rarity_base_power(t.r, t.r like 'nft%'),
        'instances', (select count(*) from public.player_pets pp where lower(coalesce(pp.rarity,''))=t.r)
      ) order by t.idx) from unnest(array['common','uncommon','rare','epic','legendary','mythic','ancestral','exclusive','nft_exclusive'])
        with ordinality as t(r, idx)), '[]'::jsonb),
    'petFormula', 'base_por_raridade + level*100 + buffs_totais*250 (pet_instance_power)',
    'heroFormula', '(base+bonus)*(1+growth)^(level-1)*fusao + equipamento (ensure_pvp_hero_stats)'
  ) INTO res;
  RETURN res;
END $$;

REVOKE ALL ON FUNCTION public.admin_game_balance_overview(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_game_balance_overview(bigint) TO service_role;