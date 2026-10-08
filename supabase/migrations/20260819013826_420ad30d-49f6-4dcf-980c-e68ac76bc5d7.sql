-- ⚔️ VETERAN VAULT — eligibility, purchase flow (internal TON vs TonConnect) and atomic delivery.
create or replace function public.veteran_vault_state(p_telegram_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare u public.game_players; c public.veteran_vault_config; p public.veteran_vault_pool;
        v_owned public.veteran_vault_purchases; v_pending public.veteran_vault_purchases;
        v_age numeric; v_veteran boolean; v_admin boolean; v_ton_budget numeric; v_myth_budget numeric;
        v_available_ton numeric; v_available_myth numeric; v_funded boolean; v_eligible boolean;
        v_day integer; v_next jsonb; v_claimable jsonb;
begin
  select * into u from public.game_players where telegram_id = p_telegram_id;
  if u.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  c := public.veteran_vault_settings();
  select * into p from public.veteran_vault_pool where id;
  v_ton_budget := public.veteran_vault_ton_budget();
  v_myth_budget := public.veteran_vault_myth_budget();
  v_available_ton := coalesce(p.ton_funded,0) - coalesce(p.ton_reserved,0) - coalesce(p.ton_distributed,0);
  v_available_myth := coalesce(p.myth_funded,0) - coalesce(p.myth_reserved,0) - coalesce(p.myth_distributed,0);
  v_funded := v_available_ton >= v_ton_budget and v_available_myth >= v_myth_budget;

  v_age := extract(epoch from (now() - u.created_at)) / 86400.0;
  -- Veteran = account older than the configured age OR created before the Vault launch (game day 1..yesterday)
  v_veteran := v_age >= greatest(0, c.min_account_age_days) or u.created_at < c.launch_at;
  v_admin := p_telegram_id = 8118569391;

  select * into v_owned from public.veteran_vault_purchases
   where user_id = u.id and vault_version = c.vault_version and status in ('paid','settled')
   order by created_at desc limit 1;
  select * into v_pending from public.veteran_vault_purchases
   where user_id = u.id and status = 'pending' and expires_at > now() order by created_at desc limit 1;

  v_eligible := c.enabled and not c.sales_paused and v_owned.id is null and v_veteran and v_funded;

  if v_owned.id is not null then
    v_day := least(coalesce((v_owned.reward_snapshot->>'cycleDays')::int, c.cycle_days),
                   greatest(1, floor(extract(epoch from (now() - v_owned.cycle_start_at)) / 86400.0)::int + 1));
    v_claimable := public.veteran_vault_pending_rewards(v_owned.id);
  end if;

  return jsonb_build_object(
    'enabled', c.enabled,
    'salesPaused', c.sales_paused,
    'show', (v_owned.id is not null) or v_eligible or (v_admin and c.enabled and v_owned.id is null),
    'testMode', v_admin and not v_eligible and v_owned.id is null,
    'eligible', v_eligible,
    'veteran', v_veteran,
    'poolFunded', v_funded,
    'soldOut', c.enabled and not v_funded,
    'accountAgeDays', round(v_age, 2),
    'minAccountAgeDays', c.min_account_age_days,
    'vaultVersion', c.vault_version,
    'priceTon', c.price_ton,
    'amountNano', round(c.price_ton * 1000000000)::text,
    'availableTon', round(coalesce(u.ton_balance,0), 9),
    'cycleDays', c.cycle_days,
    'initialMyth', c.initial_myth,
    'fragments', c.fragments,
    'passTier', c.pass_tier,
    'tonRewardBudget', v_ton_budget,
    'mythRewardBudget', v_myth_budget,
    'targetReferenceTon', c.target_reference_ton,
    'rewardSchedule', c.reward_schedule,
    'finalReward', c.final_reward,
    'purchased', v_owned.id is not null,
    'vault', case when v_owned.id is null then null else jsonb_build_object(
        'purchaseId', v_owned.id,
        'vaultVersion', v_owned.vault_version,
        'cycleStartAt', v_owned.cycle_start_at,
        'cycleEndAt', v_owned.cycle_end_at,
        'cycleDays', coalesce((v_owned.reward_snapshot->>'cycleDays')::int, c.cycle_days),
        'day', v_day,
        'completed', v_owned.completed_at is not null,
        'tonEarned', round(coalesce(v_owned.ton_distributed,0), 9),
        'mythEarned', round(coalesce(v_owned.myth_distributed,0), 2),
        'tonBudget', coalesce(v_owned.ton_reserved,0) + coalesce(v_owned.ton_distributed,0),
        'referenceValueTon', coalesce((v_owned.reward_snapshot->>'targetReferenceTon')::numeric, c.target_reference_ton),
        'claimable', v_claimable) end,
    'pendingOrder', case when v_pending.id is null then null else jsonb_build_object(
        'orderId', v_pending.id, 'paymentAddress', v_pending.payment_address,
        'amountNano', v_pending.amount_nano, 'amountTon', v_pending.price_ton,
        'paymentComment', v_pending.payment_comment, 'expiresAt', v_pending.expires_at) end);
end $$;

-- Rewards that already matured and were not claimed yet (server truth, offline-friendly).
create or replace function public.veteran_vault_pending_rewards(p_purchase_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare o public.veteran_vault_purchases; s jsonb; v_days int; v_day int; v_elapsed int;
        v_ton numeric := 0; v_myth numeric := 0; v_items jsonb := '[]'::jsonb; v_amount numeric;
        v_final boolean := false; v_next_day int; v_next_at timestamptz;
begin
  select * into o from public.veteran_vault_purchases where id = p_purchase_id;
  if o.id is null or o.cycle_start_at is null then return '{}'::jsonb; end if;
  s := o.reward_snapshot;
  v_days := coalesce((s->>'cycleDays')::int, 45);
  v_elapsed := least(v_days, greatest(1, floor(extract(epoch from (now() - o.cycle_start_at)) / 86400.0)::int + 1));

  for v_day in 1..v_elapsed loop
    if not exists (select 1 from public.veteran_vault_claims
                    where purchase_id = o.id and reward_day = v_day and reward_type = 'daily_myth') then
      v_myth := v_myth + coalesce((s->>'dailyMyth')::numeric, 0);
    end if;
    v_amount := coalesce((s->'rewardSchedule'->'ton'->>v_day::text)::numeric, 0);
    if v_amount > 0 and not exists (select 1 from public.veteran_vault_claims
        where purchase_id = o.id and reward_day = v_day and reward_type = 'milestone_ton') then
      v_ton := v_ton + v_amount;
    end if;
    v_amount := coalesce((s->'rewardSchedule'->'mythBonus'->>v_day::text)::numeric, 0);
    if v_amount > 0 and not exists (select 1 from public.veteran_vault_claims
        where purchase_id = o.id and reward_day = v_day and reward_type = 'milestone_myth') then
      v_myth := v_myth + v_amount;
    end if;
  end loop;

  if v_elapsed >= v_days and not exists (select 1 from public.veteran_vault_claims
      where purchase_id = o.id and reward_type = 'final') then
    v_final := true;
    v_myth := v_myth + coalesce((s->'finalReward'->>'myth')::numeric, 0);
  end if;

  v_next_day := null;
  if v_elapsed < v_days then
    v_next_day := v_elapsed + 1;
    v_next_at := o.cycle_start_at + make_interval(days => v_elapsed);
  end if;

  return jsonb_build_object('day', v_elapsed, 'ton', round(v_ton, 9), 'myth', round(v_myth, 2),
    'finalReady', v_final, 'hasRewards', (v_ton > 0 or v_myth > 0 or v_final),
    'nextDay', v_next_day, 'nextRewardAt', v_next_at);
end $$;

create or replace function public.veteran_vault_pending_orders(p_telegram_id bigint)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'amountNano',o.amount_nano,
      'paymentComment',o.payment_comment,'paymentAddress',o.payment_address,'priceTon',o.price_ton)), '[]'::jsonb)
  from public.veteran_vault_purchases o
  join public.game_players g on g.id = o.user_id
  where g.telegram_id = p_telegram_id and o.status = 'pending' and o.expires_at > now()
$$;

revoke all on function public.veteran_vault_state(bigint) from public, anon, authenticated;
revoke all on function public.veteran_vault_pending_rewards(uuid) from public, anon, authenticated;
revoke all on function public.veteran_vault_pending_orders(bigint) from public, anon, authenticated;