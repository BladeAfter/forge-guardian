-- ============================================================ NFT EXCLUSIVE HERO TIER
-- 1) rarity normalization gains the new top tier (ancestral values are untouched).
CREATE OR REPLACE FUNCTION public.normalize_hero_rarity(value text)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $fn$
  select case lower(trim(coalesce(value,'common')))
    when 'common' then 'common' when 'comum' then 'common' when 'uncommon' then 'uncommon' when 'incomum' then 'uncommon'
    when 'rare' then 'rare' when 'raro' then 'rare' when 'rara' then 'rare' when 'epic' then 'epic' when 'épico' then 'epic'
    when 'epico' then 'epic' when 'épica' then 'epic' when 'epica' then 'epic' when 'legendary' then 'legendary'
    when 'lendário' then 'legendary' when 'lendario' then 'legendary' when 'lendária' then 'legendary' when 'lendaria' then 'legendary'
    when 'mythic' then 'mythic' when 'mítico' then 'mythic' when 'mitico' then 'mythic' when 'mítica' then 'mythic' when 'mitica' then 'mythic'
    when 'ancestral' then 'ancestral' when 'ancient' then 'ancestral'
    when 'nft_exclusive' then 'nft_exclusive' when 'nft-exclusive' then 'nft_exclusive' when 'nft exclusive' then 'nft_exclusive'
    when 'nft' then 'nft_exclusive'
    else 'common' end
$fn$;

-- 2) stat ranges: NFT = ancestral +30% ATK/HP and +5% growth rate (compounding keeps it above at every level).
CREATE OR REPLACE FUNCTION public.hero_stat_ranges(p_rarity text)
 RETURNS TABLE(min_atk numeric, max_atk numeric, min_hp numeric, max_hp numeric, min_ag numeric, max_ag numeric, min_hg numeric, max_hg numeric)
 LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $fn$
  select s.min_atk,s.max_atk,s.min_hp,s.max_hp,s.min_ag,s.max_ag,s.min_hg,s.max_hg from (values
    ('common',100,180,1000,1800,.025,.030,.040,.045),
    ('uncommon',140,230,1400,2300,.028,.033,.042,.048),
    ('rare',180,300,1800,3000,.031,.036,.045,.051),
    ('epic',230,380,2300,3800,.034,.039,.048,.054),
    ('legendary',300,500,3000,5000,.037,.042,.051,.057),
    ('mythic',420,700,4200,7000,.040,.045,.054,.060),
    ('ancestral',600,950,6000,9500,.043,.048,.057,.063),
    ('nft_exclusive',780,1235,7800,12350,.04515,.05040,.05985,.06615)
  ) s(rarity,min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg)
  where s.rarity = public.normalize_hero_rarity(p_rarity);
$fn$;

-- 3) class flavour for NFT heroes (distribution differs per class, average stays at the tier level).
CREATE OR REPLACE FUNCTION public.hero_nft_class_mult(p_archetype text)
 RETURNS TABLE(atk_mult numeric, hp_mult numeric, def_mult numeric, speed_bonus numeric, crit_bonus numeric, skill_mult numeric)
 LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $fn$
  select m.atk_mult, m.hp_mult, m.def_mult, m.speed_bonus, m.crit_bonus, m.skill_mult from (values
    ('warrior',  1.08, 1.02, 1.20, 8,  10, 1.25),
    ('assassin', 1.12, 0.96, 1.10, 18, 18, 1.25),
    ('tank',     0.94, 1.12, 1.40, 4,  6,  1.20),
    ('mage',     1.12, 0.98, 1.15, 10, 12, 1.35),
    ('archer',   1.08, 0.98, 1.12, 16, 16, 1.28),
    ('support',  0.98, 1.08, 1.25, 8,  8,  1.35)
  ) m(archetype, atk_mult, hp_mult, def_mult, speed_bonus, crit_bonus, skill_mult)
  where m.archetype = lower(coalesce(p_archetype,'warrior'));
$fn$;

-- 4) catalog: explicit eligibility flags + admin balancing fields.
ALTER TABLE public.hero_catalog
  ADD COLUMN IF NOT EXISTS is_nft_exclusive boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS recruit_eligible boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS shop_eligible boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS reward_pool_eligible boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS random_drop_eligible boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS base_def numeric,
  ADD COLUMN IF NOT EXISTS base_speed numeric,
  ADD COLUMN IF NOT EXISTS crit_rate numeric,
  ADD COLUMN IF NOT EXISTS skill_power numeric,
  ADD COLUMN IF NOT EXISTS growth_multiplier numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS nft_class_label text,
  ADD COLUMN IF NOT EXISTS nft_passive jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.hero_catalog_enforce_recruit_flag()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
BEGIN
  NEW.rarity := public.normalize_hero_rarity(NEW.rarity);
  IF NEW.rarity = 'ancestral' THEN NEW.recruit_enabled := false; END IF;
  IF NEW.rarity = 'nft_exclusive' THEN NEW.is_nft_exclusive := true; END IF;
  IF NEW.is_nft_exclusive THEN
    NEW.recruit_enabled := false; NEW.recruit_eligible := false;
    NEW.fusion_pool_enabled := false; NEW.in_shop := false; NEW.shop_eligible := false;
    NEW.reward_pool_eligible := false; NEW.random_drop_eligible := false;
    NEW.drop_weight := 0; NEW.price_fc := NULL; NEW.price_ton := NULL;
  END IF;
  RETURN NEW;
END;
$fn$;

-- 5) player heroes: NFT ownership metadata + derived combat stats.
ALTER TABLE public.player_heroes
  ADD COLUMN IF NOT EXISTS is_nft_exclusive boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS nft_hero_id uuid,
  ADD COLUMN IF NOT EXISTS nft_serial integer,
  ADD COLUMN IF NOT EXISTS nft_instance_id text,
  ADD COLUMN IF NOT EXISTS defense numeric,
  ADD COLUMN IF NOT EXISTS speed numeric,
  ADD COLUMN IF NOT EXISTS crit_rate numeric,
  ADD COLUMN IF NOT EXISTS skill_power numeric;

CREATE OR REPLACE FUNCTION public.ensure_pvp_hero_stats()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
declare r text;seed text;min_atk numeric;max_atk numeric;min_hp numeric;max_hp numeric;min_ag numeric;max_ag numeric;min_hg numeric;max_hg numeric;
  atk_mult numeric:=1;hp_mult numeric:=1;fuse numeric:=1;kinds text[]:=array['warrior','assassin','tank','mage','archer','support'];
  nft boolean;c public.hero_catalog;m record;def_mult numeric:=1;spd_bonus numeric:=0;crit_bonus numeric:=0;skl_mult numeric:=1;
begin
  r:=normalize_hero_rarity(new.rarity);
  new.rarity:=r;
  nft:=(r='nft_exclusive') or coalesce(new.is_nft_exclusive,false);
  if nft then new.is_nft_exclusive:=true; r:='nft_exclusive'; new.rarity:='nft_exclusive'; end if;
  new.hero_template_id:=coalesce(new.hero_template_id,new.hero_key,new.name);
  seed:=coalesce(new.stats_seed,new.id::text||':'||new.hero_template_id||':'||new.user_id::text||':'||new.created_at::text);
  new.stats_seed:=seed;
  if nft then
    select * into c from hero_catalog where hero_key=new.hero_key;
    new.archetype:=coalesce(nullif(new.archetype,''),c.hero_class,'warrior');
  end if;
  new.archetype:=coalesce(new.archetype,kinds[1+(abs(hashtextextended(seed||':kind',0))%6)::int]);
  if array_position(kinds,new.archetype) is null then new.archetype:='warrior'; end if;
  select g.min_atk,g.max_atk,g.min_hp,g.max_hp,g.min_ag,g.max_ag,g.min_hg,g.max_hg
    into min_atk,max_atk,min_hp,max_hp,min_ag,max_ag,min_hg,max_hg
    from hero_stat_ranges(r) g;
  case new.archetype
    when 'warrior' then hp_mult:=1.15;
    when 'assassin' then atk_mult:=1.15;hp_mult:=.9;
    when 'tank' then atk_mult:=.85;hp_mult:=1.3;
    when 'mage' then atk_mult:=1.2;hp_mult:=.85;
    when 'archer' then atk_mult:=1.1;
    when 'support' then atk_mult:=.9;hp_mult:=1.1;
    else new.archetype:='warrior';hp_mult:=1.15;
  end case;
  if nft then
    -- Admin-tunable base stats win over the tier range; class flavour keeps NFT classes distinct.
    select * into m from hero_nft_class_mult(new.archetype);
    atk_mult:=atk_mult*coalesce(m.atk_mult,1); hp_mult:=hp_mult*coalesce(m.hp_mult,1);
    def_mult:=coalesce(m.def_mult,1); spd_bonus:=coalesce(m.speed_bonus,0);
    crit_bonus:=coalesce(m.crit_bonus,0); skl_mult:=coalesce(m.skill_mult,1);
    if c.base_atk is not null then min_atk:=c.base_atk*0.97; max_atk:=c.base_atk*1.03; end if;
    if c.base_hp is not null then min_hp:=c.base_hp*0.97; max_hp:=c.base_hp*1.03; end if;
    if coalesce(c.growth_multiplier,1) <> 1 then
      min_ag:=min_ag*c.growth_multiplier; max_ag:=max_ag*c.growth_multiplier;
      min_hg:=min_hg*c.growth_multiplier; max_hg:=max_hg*c.growth_multiplier;
    end if;
  end if;
  if new.base_atk is null or new.base_atk < min_atk then
    new.base_atk:=least(max_atk*atk_mult, greatest(min_atk, round((min_atk+pvp_stat_unit(seed||':atk')*(max_atk-min_atk))*atk_mult)));
  end if;
  if new.base_hp is null or new.base_hp < min_hp then
    new.base_hp:=least(max_hp*hp_mult, greatest(min_hp, round((min_hp+pvp_stat_unit(seed||':hp')*(max_hp-min_hp))*hp_mult)));
  end if;
  if new.attack_growth is null or new.attack_growth <= 0 or (nft and new.attack_growth < min_ag) then
    new.attack_growth:=round(min_ag+pvp_stat_unit(seed||':ag')*(max_ag-min_ag),5);end if;
  if new.hp_growth is null or new.hp_growth <= 0 or (nft and new.hp_growth < min_hg) then
    new.hp_growth:=round(min_hg+pvp_stat_unit(seed||':hg')*(max_hg-min_hg),5);end if;
  new.level:=greatest(1,coalesce(new.level,1));
  new.fusion_level:=greatest(0,coalesce(new.fusion_level,0));
  fuse:=hero_fusion_multiplier(new.fusion_level);
  new.final_atk:=greatest(1,round((new.base_atk+coalesce(new.bonus_atk,0))*power(1+new.attack_growth,new.level-1)*fuse));
  new.final_hp:=greatest(1,round((new.base_hp+coalesce(new.bonus_hp,0))*power(1+new.hp_growth,new.level-1)*fuse));
  new.defense:=greatest(1,round(coalesce(c.base_def,new.final_hp*0.09)*def_mult));
  new.speed:=greatest(1,round(coalesce(c.base_speed,90)+new.level+spd_bonus));
  new.crit_rate:=greatest(0,round(coalesce(c.crit_rate,5)+crit_bonus,2));
  new.skill_power:=greatest(1,round(coalesce(c.skill_power,new.final_atk*0.5)*skl_mult));
  new.stats_generated_at:=coalesce(new.stats_generated_at,now());
  if new.is_nft_exclusive then new.tradable:=false; new.market_locked:=true; new.locked:=true; end if;
  return new;
end $fn$;

-- 6) unique NFT registry.
CREATE TABLE IF NOT EXISTS public.nft_heroes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hero_template_id text NOT NULL REFERENCES public.hero_catalog(hero_key) ON DELETE RESTRICT,
  nft_serial integer NOT NULL,
  unique_instance_id text NOT NULL,
  owner_user_id uuid REFERENCES public.game_players(id) ON DELETE SET NULL,
  player_hero_id uuid,
  level integer NOT NULL DEFAULT 1,
  xp numeric NOT NULL DEFAULT 0,
  stars integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'AVAILABLE',
  minted boolean NOT NULL DEFAULT false,
  created_by_admin bigint,
  assigned_at timestamptz,
  revoked_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nft_heroes_unique_instance UNIQUE (unique_instance_id),
  CONSTRAINT nft_heroes_template_serial UNIQUE (hero_template_id, nft_serial),
  CONSTRAINT nft_heroes_status_chk CHECK (status IN ('AVAILABLE','OWNED','REVOKED','BURNED'))
);
GRANT SELECT ON public.nft_heroes TO authenticated;
GRANT ALL ON public.nft_heroes TO service_role;
ALTER TABLE public.nft_heroes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nft_heroes_owner_read" ON public.nft_heroes;
CREATE POLICY "nft_heroes_owner_read" ON public.nft_heroes FOR SELECT TO authenticated
  USING (owner_user_id IS NOT NULL AND owner_user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.nft_hero_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nft_hero_id uuid NOT NULL REFERENCES public.nft_heroes(id) ON DELETE CASCADE,
  action text NOT NULL,
  admin_telegram_id bigint,
  from_user_id uuid,
  to_user_id uuid,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.nft_hero_history TO service_role;
ALTER TABLE public.nft_hero_history ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS nft_heroes_owner_idx ON public.nft_heroes(owner_user_id);
CREATE INDEX IF NOT EXISTS nft_hero_history_nft_idx ON public.nft_hero_history(nft_hero_id, created_at DESC);
CREATE INDEX IF NOT EXISTS player_heroes_nft_idx ON public.player_heroes(nft_hero_id);

CREATE OR REPLACE FUNCTION public.nft_heroes_touch()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS nft_heroes_touch_trg ON public.nft_heroes;
CREATE TRIGGER nft_heroes_touch_trg BEFORE UPDATE ON public.nft_heroes FOR EACH ROW EXECUTE FUNCTION public.nft_heroes_touch();

-- 7) NFT heroes can never be consumed/sold/deleted outside an admin revoke.
CREATE OR REPLACE FUNCTION public.player_heroes_protect_nft()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
BEGIN
  IF OLD.is_nft_exclusive AND coalesce(current_setting('mythreon.nft_hero_revoke', true),'0') <> '1' THEN
    RAISE EXCEPTION 'NFT_HERO_UNIQUE';
  END IF;
  RETURN OLD;
END;
$fn$;
DROP TRIGGER IF EXISTS player_heroes_protect_nft_trg ON public.player_heroes;
CREATE TRIGGER player_heroes_protect_nft_trg BEFORE DELETE ON public.player_heroes
  FOR EACH ROW EXECUTE FUNCTION public.player_heroes_protect_nft();

-- 8) the 10 NFT EXCLUSIVE heroes.
INSERT INTO public.hero_catalog (hero_key, name, rarity, image, hero_class, nft_class_label, description,
    base_atk, base_hp, base_def, base_speed, crit_rate, skill_power, growth_multiplier, max_level,
    is_nft_exclusive, enabled, in_shop, featured, drop_weight, sort_order, skills, nft_passive)
VALUES
 ('nft-kaelion','Kaelion, o Rei Caído','nft_exclusive','/assets/game/heroes-nft/kaelion.jpg','warrior','Guerreiro',
  'Rei guerreiro caído: dano físico extremo, crítico devastador e execução dos feridos.',
  1180, 10200, 1050, 96, 28, 1600, 1.00, 60, true, true, false, true, 0, 1,
  '[{"type":"attack","name":"Lâmina do Rei","desc":"Golpe frontal com energia carmesim."},{"type":"special","name":"Julgamento Carmesim","desc":"Dano massivo em linha, +50% crítico."},{"type":"passive","name":"King''s Execution","desc":"Quanto menor o HP do inimigo, maior o dano (até +45%)."}]'::jsonb,
  '{"key":"kings_execution","bonus_max":45}'::jsonb),
 ('nft-seraphyne','Seraphyne, Luz Eterna','nft_exclusive','/assets/game/heroes-nft/seraphyne.jpg','support','Curandeira',
  'Guardiã celestial: cura, escudos, buffs e ressurreição.',
  980, 11400, 1180, 92, 16, 1750, 1.00, 60, true, true, false, false, 0, 2,
  '[{"type":"attack","name":"Feixe Sagrado","desc":"Dano sagrado em um alvo."},{"type":"special","name":"Bênção Radiante","desc":"Cura a equipe e concede escudo."},{"type":"passive","name":"Eternal Light","desc":"Uma vez por batalha protege um aliado de dano fatal."}]'::jsonb,
  '{"key":"eternal_light","uses_per_battle":1}'::jsonb),
 ('nft-dravenor','Dravenor, Senhor das Cinzas','nft_exclusive','/assets/game/heroes-nft/dravenor.jpg','tank','Tank',
  'Fortaleza vulcânica: HP altíssimo, redução de dano, provocação e contra-ataque.',
  900, 13600, 1500, 88, 12, 1450, 1.00, 60, true, true, false, false, 0, 3,
  '[{"type":"attack","name":"Maça de Magma","desc":"Golpe pesado com queimadura."},{"type":"special","name":"Provocação Ardente","desc":"Provoca inimigos e reduz o dano recebido."},{"type":"passive","name":"Molten Fortress","desc":"Cada dano recebido acumula resistência temporária."}]'::jsonb,
  '{"key":"molten_fortress","stack_resist":3,"max_resist":30}'::jsonb),
 ('nft-nyxara','Nyxara, Filha da Noite','nft_exclusive','/assets/game/heroes-nft/nyxara.jpg','assassin','Assassina',
  'Assassina sombria: velocidade, crítico, evasão e execução.',
  1280, 9100, 980, 112, 34, 1620, 1.00, 60, true, true, false, false, 0, 4,
  '[{"type":"attack","name":"Lâminas Gêmeas","desc":"Dois golpes rápidos."},{"type":"special","name":"Dança das Sombras","desc":"Múltiplos ataques com evasão elevada."},{"type":"passive","name":"Shadow Hunt","desc":"Prioriza o inimigo com menor HP e ganha bônus crítico."}]'::jsonb,
  '{"key":"shadow_hunt","crit_bonus":25}'::jsonb),
 ('nft-astrion','Astrion, Mago Cósmico','nft_exclusive','/assets/game/heroes-nft/astrion.jpg','mage','Mago',
  'Arquimago cósmico: dano mágico massivo, área, controle e quebra de resistência.',
  1300, 9600, 1010, 98, 24, 1900, 1.00, 60, true, true, false, false, 0, 5,
  '[{"type":"attack","name":"Estilhaço Astral","desc":"Projétil arcano perfurante."},{"type":"special","name":"Cosmic Collapse","desc":"Dano em área com chance de reduzir defesa mágica."},{"type":"passive","name":"Singularidade","desc":"Cada habilidade aumenta o poder da próxima."}]'::jsonb,
  '{"key":"cosmic_collapse","def_shred":20}'::jsonb),
 ('nft-valtherion','Valtherion, Guardião Real','nft_exclusive','/assets/game/heroes-nft/valtherion.jpg','tank','Paladino',
  'Paladino real: proteção de aliados, cura e dano sagrado.',
  1010, 12900, 1460, 90, 15, 1520, 1.00, 60, true, true, false, false, 0, 6,
  '[{"type":"attack","name":"Espada Real","desc":"Corte sagrado."},{"type":"special","name":"Égide do Reino","desc":"Escudo para a equipe e cura contínua."},{"type":"passive","name":"Juramento Real","desc":"Redireciona parte do dano dos aliados para si."}]'::jsonb,
  '{"key":"royal_oath","redirect_percent":18}'::jsonb),
 ('nft-elyra','Elyra, Arqueira Celestial','nft_exclusive','/assets/game/heroes-nft/elyra.jpg','archer','Arqueira',
  'Arqueira celestial: múltiplos ataques, crítico e perfuração de defesa.',
  1220, 9400, 1000, 110, 30, 1580, 1.00, 60, true, true, false, false, 0, 7,
  '[{"type":"attack","name":"Flecha de Luz","desc":"Tiro perfurante."},{"type":"special","name":"Chuva Celestial","desc":"Rajada de flechas em todos os inimigos."},{"type":"passive","name":"Precisão Divina","desc":"Ignora parte da defesa do alvo."}]'::jsonb,
  '{"key":"divine_precision","def_pierce":25}'::jsonb),
 ('nft-mordrakar','Mordrakar, Cavaleiro Abissal','nft_exclusive','/assets/game/heroes-nft/mordrakar.jpg','warrior','Guerreiro/Tank',
  'Cavaleiro do abismo: roubo de vida, dano sombrio e redução de cura inimiga.',
  1150, 11800, 1280, 94, 22, 1560, 1.00, 60, true, true, false, false, 0, 8,
  '[{"type":"attack","name":"Corte Abissal","desc":"Golpe sombrio com roubo de vida."},{"type":"special","name":"Maldição do Vazio","desc":"Reduz a cura recebida pelos inimigos."},{"type":"passive","name":"Sede do Abismo","desc":"Converte parte do dano causado em vida."}]'::jsonb,
  '{"key":"abyss_thirst","lifesteal":20,"heal_reduction":30}'::jsonb),
 ('nft-solarius','Solarius Prime','nft_exclusive','/assets/game/heroes-nft/solarius-prime.jpg','mage','Guerreiro/Mago',
  'Avatar solar: dano híbrido, queimadura e explosões em área.',
  1260, 10400, 1120, 100, 26, 1820, 1.00, 60, true, true, false, false, 0, 9,
  '[{"type":"attack","name":"Lâmina Solar","desc":"Corte flamejante híbrido."},{"type":"special","name":"Explosão Solar","desc":"Dano em área com queimadura."},{"type":"passive","name":"Núcleo Estelar","desc":"Queimaduras acumulam e aumentam o dano em área."}]'::jsonb,
  '{"key":"stellar_core","burn_stacks":5}'::jsonb),
 ('nft-eternis','Eternis, O Primeiro','nft_exclusive','/assets/game/heroes-nft/eternis.jpg','warrior','Especial / Híbrido',
  'O Primeiro: ataque, defesa, controle, sustain e dano em área — a unidade definitiva.',
  1350, 12600, 1400, 102, 30, 2000, 1.05, 60, true, true, false, true, 0, 10,
  '[{"type":"attack","name":"Sentença Primordial","desc":"Golpe híbrido físico e arcano."},{"type":"special","name":"Colapso Eterno","desc":"Dano em área, controle e cura própria."},{"type":"passive","name":"Primeiro Legado","desc":"Ganha atributos acumulados a cada turno da batalha."}]'::jsonb,
  '{"key":"first_legacy","per_turn_bonus":3,"max_bonus":30}'::jsonb)
ON CONFLICT (hero_key) DO UPDATE SET
  name=EXCLUDED.name, rarity=EXCLUDED.rarity, image=EXCLUDED.image, hero_class=EXCLUDED.hero_class,
  nft_class_label=EXCLUDED.nft_class_label, description=EXCLUDED.description,
  base_atk=EXCLUDED.base_atk, base_hp=EXCLUDED.base_hp, base_def=EXCLUDED.base_def,
  base_speed=EXCLUDED.base_speed, crit_rate=EXCLUDED.crit_rate, skill_power=EXCLUDED.skill_power,
  growth_multiplier=EXCLUDED.growth_multiplier, is_nft_exclusive=true, skills=EXCLUDED.skills,
  nft_passive=EXCLUDED.nft_passive, updated_at=now();

-- 9) keep NFT heroes out of every automatic pool.
CREATE OR REPLACE FUNCTION public.roll_hero_for_rarity(p_rarity text, p_allowed text[], OUT hero hero_catalog, OUT final_rarity text, OUT fallback_from text)
 RETURNS record LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
declare rar text:=p_rarity;
begin
  loop
    select * into hero from hero_catalog where enabled and not is_nft_exclusive and rarity=rar order by random() limit 1;
    exit when hero.hero_key is not null;
    if array_position(p_allowed,rar) is null or array_position(p_allowed,rar)=1 then exit; end if;
    fallback_from:=coalesce(fallback_from,rar);
    rar:=p_allowed[array_position(p_allowed,rar)-1];
  end loop;
  if hero.hero_key is null then
    select * into hero from hero_catalog where enabled and not is_nft_exclusive order by random() limit 1;
    if hero.hero_key is null then raise exception 'NO_ELIGIBLE_HERO'; end if;
    fallback_from:=coalesce(fallback_from,rar);
    rar:=hero.rarity;
  end if;
  final_rarity:=rar;
end $fn$;

CREATE OR REPLACE FUNCTION public.hero_effective_summon_odds()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_total numeric := 0; v_out jsonb := '{}'::jsonb; r record; v_sum numeric; v_top text;
BEGIN
  FOR r IN
    SELECT e.key AS rarity, (e.value #>> '{}')::numeric AS chance
      FROM jsonb_each(public.hero_summon_rates()) e
     WHERE e.key NOT IN ('ancestral','nft_exclusive')
       AND (e.value #>> '{}')::numeric > 0
       AND public.hero_rarity_recruitable(e.key)
       AND EXISTS (SELECT 1 FROM public.hero_catalog c
                    WHERE c.rarity = e.key AND c.enabled AND c.recruit_enabled AND NOT c.is_nft_exclusive)
  LOOP
    v_total := v_total + r.chance;
    v_out := v_out || jsonb_build_object(r.rarity, r.chance);
  END LOOP;
  IF v_total <= 0 THEN RETURN '{}'::jsonb; END IF;
  SELECT jsonb_object_agg(key, round((value #>> '{}')::numeric * 100 / v_total, 2))
    INTO v_out FROM jsonb_each(v_out);
  SELECT sum((value #>> '{}')::numeric) INTO v_sum FROM jsonb_each(v_out);
  SELECT key INTO v_top FROM jsonb_each(v_out)
    ORDER BY (value #>> '{}')::numeric DESC, key ASC LIMIT 1;
  IF v_top IS NOT NULL AND v_sum <> 100 THEN
    v_out := v_out || jsonb_build_object(v_top,
      round((v_out #>> ARRAY[v_top])::numeric + (100 - v_sum), 2));
  END IF;
  RETURN v_out;
END; $fn$;
