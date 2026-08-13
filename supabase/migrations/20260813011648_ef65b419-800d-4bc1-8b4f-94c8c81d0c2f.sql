-- 1. Rarity vocabulary
CREATE OR REPLACE FUNCTION public.normalize_pet_rarity(v text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $function$
  select case lower(trim(coalesce(v,'common')))
    when 'uncommon' then 'uncommon' when 'incomum' then 'uncommon'
    when 'rare' then 'rare' when 'raro' then 'rare' when 'rara' then 'rare'
    when 'epic' then 'epic' when 'epico' then 'epic' when 'épico' then 'epic' when 'epica' then 'epic' when 'épica' then 'epic'
    when 'legendary' then 'legendary' when 'lendario' then 'legendary' when 'lendário' then 'legendary' when 'lendaria' then 'legendary' when 'lendária' then 'legendary'
    when 'mythic' then 'mythic' when 'mitico' then 'mythic' when 'mítico' then 'mythic' when 'mitica' then 'mythic' when 'mítica' then 'mythic'
    when 'ancestral' then 'ancestral'
    when 'nft_exclusive' then 'nft_exclusive' when 'nft-exclusive' then 'nft_exclusive'
    when 'nft exclusive' then 'nft_exclusive' when 'nft' then 'nft_exclusive'
    when 'nft_exclusivo' then 'nft_exclusive' when 'nft exclusivo' then 'nft_exclusive'
    else 'common' end
$function$;

-- 2. Config row for the new top category
INSERT INTO public.pet_rarity_config (rarity,label,label_pt,sort_order,multiplier,power,attr_min,attr_max,color_primary,color_secondary,glow,enabled)
VALUES ('nft_exclusive','NFT EXCLUSIVE','NFT EXCLUSIVO',8,4.2,22000,38,50,'#22d3ee','#a78bfa','rgba(34,211,238,.85)',true)
ON CONFLICT (rarity) DO UPDATE SET label=excluded.label,label_pt=excluded.label_pt,sort_order=excluded.sort_order,
  multiplier=greatest(public.pet_rarity_config.multiplier,excluded.multiplier),
  power=greatest(public.pet_rarity_config.power,excluded.power),
  attr_min=excluded.attr_min,attr_max=excluded.attr_max,color_primary=excluded.color_primary,
  color_secondary=excluded.color_secondary,glow=excluded.glow,enabled=true,updated_at=now();

-- 3. Constraints
ALTER TABLE public.player_pets DROP CONSTRAINT IF EXISTS player_pets_rarity_check;
ALTER TABLE public.player_pets ADD CONSTRAINT player_pets_rarity_check
  CHECK (rarity = ANY (ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral','nft_exclusive']));

ALTER TABLE public.calendar_chest_open_history DROP CONSTRAINT IF EXISTS calendar_chest_open_history_result_rarity_check;
ALTER TABLE public.calendar_chest_open_history ADD CONSTRAINT calendar_chest_open_history_result_rarity_check
  CHECK (result_rarity = ANY (ARRAY['common','uncommon','rare','epic','legendary','mythic','ancestral']));

-- 4. Promote existing NFT templates + already delivered NFT player pets (no duplicates, no ownership change)
UPDATE public.pets SET rarity='nft_exclusive', egg_eligible=false, availability_type='NFT_EXCLUSIVE', updated_at=now()
 WHERE is_nft_exclusive AND rarity <> 'nft_exclusive';

UPDATE public.player_pets pp SET rarity='nft_exclusive', updated_at=now()
 WHERE pp.rarity <> 'nft_exclusive'
   AND (pp.nft_pet_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.pets p WHERE p.id=pp.pet_id AND p.is_nft_exclusive));

-- 5. Hard guard: NFT pets can never enter random pools
CREATE OR REPLACE FUNCTION public.reward_pet_pool_block_nft()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.pets p WHERE p.id = NEW.pet_id AND (p.is_nft_exclusive OR p.rarity='nft_exclusive')) THEN
    RAISE EXCEPTION 'NFT_PET_NOT_DRAWABLE';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_reward_pet_pool_block_nft ON public.reward_pet_pool;
CREATE TRIGGER trg_reward_pet_pool_block_nft BEFORE INSERT OR UPDATE ON public.reward_pet_pool
FOR EACH ROW EXECUTE FUNCTION public.reward_pet_pool_block_nft();

CREATE OR REPLACE FUNCTION public.pet_eggs_block_nft_rates()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.rarity_rates IS NOT NULL AND EXISTS (
    SELECT 1 FROM jsonb_each_text(NEW.rarity_rates) t(k,v)
     WHERE public.normalize_pet_rarity(k) = 'nft_exclusive' AND coalesce(v::numeric,0) > 0
  ) THEN
    RAISE EXCEPTION 'NFT_RARITY_NOT_ALLOWED_IN_EGGS';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_pet_eggs_block_nft_rates ON public.pet_eggs;
CREATE TRIGGER trg_pet_eggs_block_nft_rates BEFORE INSERT OR UPDATE ON public.pet_eggs
FOR EACH ROW EXECUTE FUNCTION public.pet_eggs_block_nft_rates();

-- 6. Admin grant keeps template rarity and refuses NFT templates (must use the NFT flow)
CREATE OR REPLACE FUNCTION public.admin_grant_pet(p_admin_id bigint, p_ref text, p_pet_slug text, p_rarity text DEFAULT NULL::text, p_level integer DEFAULT 1, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_uid uuid; pt public.pets; v_id uuid;
BEGIN
  PERFORM public.admin_assert(p_admin_id);
  v_uid := public.admin_resolve_player(p_ref);
  SELECT * INTO pt FROM public.pets WHERE slug = p_pet_slug OR id::text = p_pet_slug;
  IF pt.id IS NULL THEN RAISE EXCEPTION 'pet_not_found'; END IF;
  IF pt.is_nft_exclusive OR pt.rarity = 'nft_exclusive' THEN RAISE EXCEPTION 'USE_NFT_FLOW'; END IF;
  -- p_rarity is ignored on purpose: the pet template owns its rarity.
  INSERT INTO public.player_pets (user_id, pet_id, rarity, level, xp, evolution_stage, fragments, is_active)
  VALUES (v_uid, pt.id, public.normalize_pet_rarity(pt.rarity), GREATEST(1, COALESCE(p_level,1)), 0, 'baby', 0, false)
  RETURNING id INTO v_id;
  PERFORM public.admin_log(p_admin_id,'pet.grant','player',v_uid::text,NULL,
    jsonb_build_object('player_pet_id',v_id,'pet',pt.slug,'rarity',pt.rarity), p_reason);
  RETURN jsonb_build_object('user_id',v_uid,'player_pet_id',v_id,'pet',pt.name,'rarity',pt.rarity);
END; $function$;