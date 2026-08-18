CREATE OR REPLACE FUNCTION public.clan_member_limit(p_level integer)
 RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $function$
  SELECT LEAST(150, 18 + GREATEST(1, COALESCE(p_level,1)) * 2)
$function$;

CREATE OR REPLACE FUNCTION public.clan_war_league(p_rating integer)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $function$
  SELECT CASE
    WHEN COALESCE(p_rating,0) >= 2400 THEN 'MYTHIC'
    WHEN p_rating >= 2000 THEN 'DIAMOND'
    WHEN p_rating >= 1700 THEN 'PLATINUM'
    WHEN p_rating >= 1400 THEN 'GOLD'
    WHEN p_rating >= 1150 THEN 'SILVER'
    ELSE 'BRONZE' END;
$function$;

CREATE OR REPLACE FUNCTION public.clan_war_league_multiplier(p_league text)
 RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $function$
  SELECT CASE p_league WHEN 'MYTHIC' THEN 2.0 WHEN 'DIAMOND' THEN 1.7 WHEN 'PLATINUM' THEN 1.45
    WHEN 'GOLD' THEN 1.25 WHEN 'SILVER' THEN 1.1 ELSE 1.0 END;
$function$;

CREATE OR REPLACE FUNCTION public.clan_war_sector_def()
 RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $function$
  SELECT '[
    {"code":"OUTER_GATE","order":1,"slots":6,"required":4,"requires":[],"bonus":null},
    {"code":"NORTH_TOWER","order":2,"slots":4,"required":3,"requires":["OUTER_GATE"],"bonus":"atk"},
    {"code":"SOUTH_TOWER","order":2,"slots":4,"required":3,"requires":["OUTER_GATE"],"bonus":"hp"},
    {"code":"INNER_KEEP","order":3,"slots":4,"required":3,"requires":["NORTH_TOWER","SOUTH_TOWER"],"bonus":"skill"},
    {"code":"CLAN_THRONE","order":4,"slots":2,"required":2,"requires":["INNER_KEEP"],"bonus":null}
  ]'::jsonb;
$function$;

CREATE OR REPLACE FUNCTION public.marketing_pool_categories()
 RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $function$
  SELECT ARRAY['MARKETING','DEVELOPMENT','INFLUENCERS','DESIGN','COMMUNITY','MODERATION','SERVER','OTHER']::text[];
$function$;

CREATE OR REPLACE FUNCTION public.clan_war_cfg()
 RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT jsonb_build_object(
    'enabled', COALESCE((SELECT value::text = 'true' FROM public.game_settings WHERE key='clan_war_enabled'), false),
    'rosterSize', public.setting_num('clan_war_roster_size', 20)::int,
    'attacksPerPlayer', public.setting_num('clan_war_attacks_per_player', 2)::int,
    'preparationHours', public.setting_num('clan_war_preparation_hours', 12)::int,
    'battleHours', public.setting_num('clan_war_battle_hours', 24)::int,
    'seasonWeeks', public.setting_num('clan_war_season_weeks', 4)::int,
    'matchmaking', COALESCE((SELECT value::text = 'true' FROM public.game_settings WHERE key='clan_war_matchmaking'), true),
    'baseRating', public.setting_num('clan_war_base_rating', 1000)::int,
    'pointsWin', public.setting_num('clan_war_points_win', 100)::int,
    'pointsPerfect', public.setting_num('clan_war_points_perfect', 20)::int,
    'pointsUpsetMax', public.setting_num('clan_war_points_upset_max', 30)::int,
    'pointsLoss', public.setting_num('clan_war_points_loss', 10)::int,
    'defenderMaxDefeats', public.setting_num('clan_war_defender_max_defeats', 2)::int,
    'conqueredPercent', public.setting_num('clan_war_conquered_points_percent', 25)::int,
    'sectorBonusPercent', public.setting_num('clan_war_sector_bonus_percent', 5)::int,
    'tonSeasonPrize', COALESCE((SELECT value::text = 'true' FROM public.game_settings WHERE key='clan_war_ton_season_prize'), false),
    'sectors', public.clan_war_sector_def()
  );
$function$;

-- Todo o acesso do jogo passa pelas Edge Functions (service_role); nenhuma funcao
-- SECURITY DEFINER deve ser chamavel diretamente pelo cliente, exceto get_game_state,
-- que valida o initData do Telegram internamente.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prosecdef
       AND p.proname <> 'get_game_state'
       AND (has_function_privilege('anon', p.oid, 'execute')
         OR has_function_privilege('authenticated', p.oid, 'execute'))
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, authenticated, PUBLIC', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;