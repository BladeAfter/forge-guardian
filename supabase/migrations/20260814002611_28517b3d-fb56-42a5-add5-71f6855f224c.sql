DO $$
DECLARE v_u uuid; v_bot jsonb; v_bot_id uuid; v_res jsonb;
  v_t int; v_tr int; v_w int; v_l int; v_fc numeric;
BEGIN
  SELECT id, pvp_tickets, pvp_trophies, pvp_wins, pvp_losses, forge_coins
    INTO v_u, v_t, v_tr, v_w, v_l, v_fc
  FROM public.game_players WHERE telegram_id = 8118569391;

  v_bot := public.pvp_generate_bot(v_u);
  v_bot_id := (v_bot->>'userId')::uuid;
  RAISE NOTICE 'BOT_GENERATED id=% name=% power=% team=%', v_bot_id, v_bot->>'name', v_bot->>'teamPower', jsonb_array_length(v_bot->'defenseTeam');

  v_res := public.start_pvp_battle(8118569391, v_bot_id);
  RAISE NOTICE 'BATTLE_RESULT result=% turns=% isBot=% reward=% trophyChange=% logLen=%',
    v_res->>'result', v_res->>'totalTurns', v_res->>'isBotBattle', v_res->>'rewardFc', v_res->>'trophyChange', jsonb_array_length(v_res->'battleLog');

  DELETE FROM public.pvp_reward_settlements WHERE battle_id = (v_res->>'battleId')::uuid;
  DELETE FROM public.pvp_battles WHERE id = (v_res->>'battleId')::uuid;
  DELETE FROM public.pvp_bots WHERE id = v_bot_id;
  UPDATE public.game_players
     SET pvp_tickets = v_t, pvp_trophies = v_tr, pvp_wins = v_w, pvp_losses = v_l, forge_coins = v_fc
   WHERE id = v_u;
  RAISE NOTICE 'TEST_CLEANUP_OK';
END $$;