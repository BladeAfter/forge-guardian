-- 0040: FIX DUAL (TON + MYTH) MINING ACCOUNTING
DO $mig$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = 'hero_mining_accrue' AND pronamespace = 'public'::regnamespace;
  v_new := replace(v_src,
    'CASE WHEN rate > 0 AND (myth_rate <= 0 OR dual) THEN',
    'CASE WHEN rate > 0 THEN');
  IF v_new = v_src THEN RAISE EXCEPTION 'hero_mining_accrue pattern not found'; END IF;
  EXECUTE v_new;

  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = 'get_hero_mining_state' AND pronamespace = 'public'::regnamespace;
  v_new := regexp_replace(v_src,
    'CASE WHEN GREATEST\(COALESCE\(h\.mining_daily_myth,0\), hero_mining_hero_myth_rate\(h\.rarity, h\.nft_hero_id\)\) <= 0\s*THEN hero_mining_hero_rate\(h\.rarity, h\.nft_hero_id\) ELSE 0 END',
    'hero_mining_hero_rate(h.rarity, h.nft_hero_id)', 'g');
  IF v_new = v_src THEN RAISE EXCEPTION 'get_hero_mining_state pattern not found'; END IF;
  EXECUTE v_new;
END $mig$;

REVOKE ALL ON FUNCTION public.hero_mining_accrue(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_hero_mining_state(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hero_mining_accrue(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_hero_mining_state(bigint) TO service_role;

-- NFT pet yield: accrue TON and MYTH independently
CREATE OR REPLACE FUNCTION public.nft_pool_accrue()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.nft_pool_settings; r public.nft_yield_positions; secs numeric;
        gain_ton numeric; gain_myth numeric;
        touched integer := 0; total numeric := 0; total_myth numeric := 0;
begin
  s := public.nft_pool_settings_row();
  perform public.nft_pool_sync_positions();
  if not s.accrual_enabled then return jsonb_build_object('enabled', false, 'positions', 0); end if;
  for r in select * from public.nft_yield_positions where status = 'active' for update loop
    secs := greatest(0, extract(epoch from (now() - r.last_accrual_at)));
    if secs < 60 then continue; end if;
    gain_ton := round(public.nft_effective_daily(r) * (secs / 86400.0), 9);
    gain_myth := round(public.nft_effective_daily_myth(r) * (secs / 86400.0), 9);
    update public.nft_yield_positions
       set accrued_ton = accrued_ton + greatest(gain_ton, 0),
           accrued_myth = accrued_myth + greatest(gain_myth, 0),
           roi_reached = roi_reached or (greatest(gain_ton,0) > 0 and (claimed_ton + accrued_ton + gain_ton) >= roi_target_ton),
           last_accrual_at = now(), updated_at = now()
     where id = r.id;
    touched := touched + 1;
    total := total + greatest(gain_ton, 0);
    total_myth := total_myth + greatest(gain_myth, 0);
  end loop;
  update public.nft_reward_pool
     set reserved_ton = coalesce((select sum(accrued_ton) from public.nft_yield_positions where status = 'active'), 0),
         updated_at = now()
   where id;
  return jsonb_build_object('enabled', true, 'currency', 'dual', 'positions', touched,
                            'accrued', total, 'accruedMyth', total_myth);
end $function$;

-- NFT claim: pay TON and/or MYTH in the same operation
CREATE OR REPLACE FUNCTION public.nft_claim_position(p_telegram_id bigint, p_position_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; p public.nft_yield_positions; s public.nft_pool_settings;
        v_before numeric; amount numeric := 0; amount_myth numeric := 0;
        claim uuid := gen_random_uuid();
        v_min_myth numeric; v_available numeric;
begin
  select id into u from public.game_players where telegram_id = p_telegram_id;
  if u is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  perform public.nft_pool_accrue();
  s := public.nft_pool_settings_row();
  select * into p from public.nft_yield_positions
   where id = p_position_id and owner_user_id = u and status = 'active' for update;
  if p.id is null then raise exception 'NFT_NOT_FOUND'; end if;

  amount := floor(greatest(coalesce(p.accrued_ton,0),0) * 1000000) / 1000000;
  if amount < coalesce(s.min_claim_ton, 0) then amount := 0; end if;

  amount_myth := floor(greatest(coalesce(p.accrued_myth,0),0) * 1000000) / 1000000;
  select coalesce(min_claim_myth, 0) into v_min_myth from public.hero_mining_settings where id;
  v_available := public.myth_mining_pool_available();
  if amount_myth < coalesce(v_min_myth, 0) or amount_myth > coalesce(v_available, 0) then amount_myth := 0; end if;

  if amount <= 0 and amount_myth <= 0 then raise exception 'CLAIM_TOO_SMALL'; end if;

  if amount_myth > 0 then
    update public.nft_yield_positions
       set accrued_myth = greatest(0, accrued_myth - amount_myth), claimed_myth = claimed_myth + amount_myth,
           last_claim_at = now(), updated_at = now()
     where id = p.id;

    update public.myth_mining_pool
       set distributed_myth = round(distributed_myth + amount_myth, 9), updated_at = now()
     where id;

    insert into public.myth_balances (user_id, amount, updated_at)
    values (u, amount_myth, now())
    on conflict (user_id) do update set amount = round(public.myth_balances.amount + amount_myth, 9), updated_at = now();

    insert into public.myth_supply_ledger (entry_type, amount, user_id, reference_id, note)
    values ('MINING', amount_myth, u, claim::text, format('NFT #%s MYTH mining claim', p.nft_serial));

    insert into public.nft_mining_ledger (entry_type, currency, amount, user_id, reference_id)
    values ('NFT_MINING_MYTH_CLAIM', 'myth', amount_myth, u, claim::text);
  end if;

  if amount > 0 then
    v_before := public.nft_pool_settle_payment(amount);
    update public.nft_yield_positions
       set accrued_ton = greatest(0, accrued_ton - amount), claimed_ton = claimed_ton + amount,
           roi_reached = roi_reached or (claimed_ton + amount) >= roi_target_ton,
           last_claim_at = now(), updated_at = now()
     where id = p.id;
    insert into public.nft_pool_transactions(type, amount_ton, balance_before, balance_after, nft_id, user_id, telegram_id, claim_id, note)
    values ('CLAIM_PAYMENT', -amount, v_before, greatest(0, v_before - amount), p.nft_pet_id, u, p_telegram_id, claim,
            format('NFT #%s claim', p.nft_serial));
    perform public.credit_ton_reward(u, amount, 'nft_reward', claim::text, format('NFT #%s reward claim', p.nft_serial));
  end if;

  return jsonb_build_object('ok', true, 'claimId', claim,
           'currency', case when amount > 0 and amount_myth > 0 then 'hybrid'
                            when amount_myth > 0 then 'myth' else 'ton' end,
           'amountTon', amount, 'amountMyth', amount_myth)
         || public.nft_my_rewards_json(p_telegram_id);
end $function$;

REVOKE ALL ON FUNCTION public.nft_pool_accrue() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nft_claim_position(bigint, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nft_pool_accrue() TO service_role;
GRANT EXECUTE ON FUNCTION public.nft_claim_position(bigint, uuid) TO service_role;