-- Aceleração da expedição ativa via rewarded ad (reaproveita o AdsGram já existente)
ALTER TABLE public.pet_expeditions ADD COLUMN IF NOT EXISTS ad_boosts_used integer NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.expedition_boost_ad_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  expedition_id uuid NOT NULL REFERENCES public.pet_expeditions(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','GRANTED','CANCELLED')),
  seconds_saved integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  granted_at timestamptz
);
CREATE INDEX IF NOT EXISTS expedition_boost_ad_views_user_idx ON public.expedition_boost_ad_views (user_id, expedition_id, status);
GRANT ALL ON public.expedition_boost_ad_views TO service_role;
ALTER TABLE public.expedition_boost_ad_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY "boost_ad_views_service" ON public.expedition_boost_ad_views FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.expedition_boost_limit()
RETURNS integer LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT greatest(0, coalesce(nullif(public.setting_text('expedition_ad_boost_limit', '5'), '')::int, 5))
$$;

-- Início do anúncio: valida expedição ativa + limite, devolve o bloco AdsGram
CREATE OR REPLACE FUNCTION public.expedition_boost_ad_begin(p_telegram_id bigint, p_expedition_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; e public.pet_expeditions; v_limit int := public.expedition_boost_limit();
        v_block text; v_id uuid;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;
  IF coalesce(u.banned, false) THEN RAISE EXCEPTION 'PLAYER_BANNED'; END IF;

  SELECT * INTO e FROM public.pet_expeditions WHERE id = p_expedition_id AND user_id = u.id;
  IF e.id IS NULL THEN RAISE EXCEPTION 'EXPEDITION_NOT_FOUND'; END IF;
  IF e.status <> 'ACTIVE' THEN RAISE EXCEPTION 'EXPEDITION_NOT_ACTIVE'; END IF;
  IF e.finishes_at <= now() THEN RAISE EXCEPTION 'EXPEDITION_ALREADY_READY'; END IF;
  IF coalesce(e.ad_boosts_used, 0) >= v_limit THEN RAISE EXCEPTION 'EXPEDITION_BOOST_LIMIT_REACHED'; END IF;

  v_block := nullif(trim(coalesce(public.setting_text('adsgram_pvp_reward_block_id', '42560'), '')), '');
  IF v_block IS NULL THEN RAISE EXCEPTION 'AD_REWARDS_DISABLED'; END IF;

  UPDATE public.expedition_boost_ad_views SET status = 'CANCELLED'
   WHERE user_id = u.id AND status = 'PENDING' AND created_at < now() - interval '10 minutes';

  SELECT id INTO v_id FROM public.expedition_boost_ad_views
   WHERE user_id = u.id AND expedition_id = e.id AND status = 'PENDING'
   ORDER BY created_at DESC LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.expedition_boost_ad_views (user_id, expedition_id)
    VALUES (u.id, e.id) RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('viewId', v_id, 'blockId', v_block,
    'adBoostsUsed', coalesce(e.ad_boosts_used, 0), 'maxAdBoosts', v_limit);
END $$;
REVOKE ALL ON FUNCTION public.expedition_boost_ad_begin(bigint, uuid) FROM PUBLIC, anon, authenticated;

-- Conclusão do anúncio: -20% do tempo restante atual, atômico e com limite por expedição
CREATE OR REPLACE FUNCTION public.expedition_boost_ad_claim(p_telegram_id bigint, p_view_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u public.game_players; v public.expedition_boost_ad_views; e public.pet_expeditions;
        v_limit int := public.expedition_boost_limit(); v_remaining numeric; v_saved int; v_finish timestamptz;
BEGIN
  SELECT * INTO u FROM public.game_players WHERE telegram_id = p_telegram_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'PLAYER_NOT_FOUND'; END IF;

  SELECT * INTO v FROM public.expedition_boost_ad_views WHERE id = p_view_id AND user_id = u.id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'EXPEDITION_AD_VIEW_NOT_FOUND'; END IF;
  IF v.status = 'GRANTED' THEN
    SELECT * INTO e FROM public.pet_expeditions WHERE id = v.expedition_id;
    RETURN jsonb_build_object('granted', false, 'reason', 'ALREADY_GRANTED',
      'adBoostsUsed', coalesce(e.ad_boosts_used, 0), 'maxAdBoosts', v_limit,
      'finishesAt', e.finishes_at, 'secondsSaved', 0);
  END IF;
  IF v.status <> 'PENDING' THEN RAISE EXCEPTION 'EXPEDITION_AD_VIEW_EXPIRED'; END IF;

  SELECT * INTO e FROM public.pet_expeditions WHERE id = v.expedition_id AND user_id = u.id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'EXPEDITION_NOT_FOUND'; END IF;
  IF e.status <> 'ACTIVE' THEN RAISE EXCEPTION 'EXPEDITION_NOT_ACTIVE'; END IF;
  IF coalesce(e.ad_boosts_used, 0) >= v_limit THEN
    UPDATE public.expedition_boost_ad_views SET status = 'CANCELLED' WHERE id = v.id;
    RAISE EXCEPTION 'EXPEDITION_BOOST_LIMIT_REACHED';
  END IF;

  v_remaining := greatest(0, extract(epoch from (e.finishes_at - now())));
  v_saved := floor(v_remaining * 0.20)::int;
  v_finish := now() + make_interval(secs => greatest(0, v_remaining - v_saved));

  UPDATE public.pet_expeditions
     SET finishes_at = v_finish, ad_boosts_used = coalesce(ad_boosts_used, 0) + 1
   WHERE id = e.id;
  UPDATE public.expedition_boost_ad_views
     SET status = 'GRANTED', granted_at = now(), seconds_saved = v_saved
   WHERE id = v.id;

  RETURN jsonb_build_object('granted', true, 'expeditionId', e.id, 'finishesAt', v_finish,
    'secondsSaved', v_saved, 'adBoostsUsed', coalesce(e.ad_boosts_used, 0) + 1, 'maxAdBoosts', v_limit,
    'ready', v_finish <= now());
END $$;
REVOKE ALL ON FUNCTION public.expedition_boost_ad_claim(bigint, uuid) FROM PUBLIC, anon, authenticated;

-- Estado da expedição passa a expor o contador de boosts
CREATE OR REPLACE FUNCTION public.expedition_state(p_telegram_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u uuid; busy uuid[];
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.sub_nft_sync(u);
  select coalesce(array_agg(pid), '{}') into busy
    from (select unnest(pet_ids) pid from public.pet_expeditions where user_id = u and status = 'ACTIVE') b;

  return jsonb_build_object(
    'limits', public.expedition_limits(),
    'pets', coalesce((select jsonb_agg(jsonb_build_object(
        'playerPetId', pp.id, 'name', p.name,
        'image', coalesce(sn_t.image_url, public.pet_visual_image(pp.pet_id, pp.level)),
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
        'element', m.recommended_element, 'rewards', m.reward_pool,
        'attempts', public.expedition_mission_attempts(u, m.id)) order by m.sort_order)
      from public.expedition_missions m where m.enabled), '[]'::jsonb),
    'active', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'missionRarity', m.rarity,
        'startedAt', e.started_at, 'finishesAt', e.finishes_at,
        'teamPower', e.team_power, 'successChance', e.success_chance,
        'ready', e.finishes_at <= now(),
        'adBoostsUsed', coalesce(e.ad_boosts_used, 0),
        'maxAdBoosts', public.expedition_boost_limit(),
        'pets', (select jsonb_agg(jsonb_build_object('name', p2.name, 'image', public.pet_visual_image(pp2.pet_id, pp2.level)))
                   from public.player_pets pp2 join public.pets p2 on p2.id = pp2.pet_id where pp2.id = any(e.pet_ids)))
        order by e.finishes_at)
      from public.pet_expeditions e join public.expedition_missions m on m.id = e.mission_id
      where e.user_id = u and e.status = 'ACTIVE'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'missionName', m.name, 'success', e.success, 'rewards', e.rewards, 'claimedAt', e.claimed_at)
        order by e.claimed_at desc)
      from (select * from public.pet_expeditions where user_id = u and status = 'CLAIMED' order by claimed_at desc limit 10) e
      join public.expedition_missions m on m.id = e.mission_id), '[]'::jsonb));
end $function$;
