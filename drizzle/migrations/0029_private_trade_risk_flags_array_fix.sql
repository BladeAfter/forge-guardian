-- PRIVATE TRADE FIX — risk flags were appended as bare text literals, which
-- Postgres tried to cast to text[] ("malformed array literal"), aborting the
-- lock/confirm call. Flags are now appended as proper array literals.
create or replace function public.private_trade_risk_assess(p_trade uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  t private_trades%rowtype; cfg jsonb; w jsonb; score integer := 0; flags text[] := '{}';
  a_value numeric := 0; b_value numeric := 0; a_cur numeric; b_cur numeric;
  a_days integer; b_days integer; same_device boolean; same_net boolean; same_wallet boolean;
  pair_count integer; nft_move boolean; high_rar boolean; created_gap numeric; level text;
begin
  select * into t from private_trades where id = p_trade;
  if t.id is null then raise exception 'TRADE_NOT_FOUND'; end if;
  cfg := private_trade_settings_json(); w := cfg->'weights';

  select coalesce(sum(value_fc),0) into a_value from private_trade_items where trade_id = t.id and side = 'initiator';
  select coalesce(sum(value_fc),0) into b_value from private_trade_items where trade_id = t.id and side = 'recipient';
  a_cur := t.initiator_fc + t.initiator_ton * 100000 + t.initiator_myth * 2;
  b_cur := t.recipient_fc + t.recipient_ton * 100000 + t.recipient_myth * 2;
  a_value := a_value + a_cur; b_value := b_value + b_cur;

  a_days := market_account_days(t.initiator_user_id);
  b_days := market_account_days(t.recipient_user_id);

  same_device := accounts_share_device(t.initiator_user_id, t.recipient_user_id);

  select exists (
    select 1 from device_accounts da
      join device_registry dra on dra.device_hash = da.device_hash
      join device_accounts db on true
      join device_registry drb on drb.device_hash = db.device_hash
     where da.telegram_id = (select telegram_id from game_players where id = t.initiator_user_id)
       and db.telegram_id = (select telegram_id from game_players where id = t.recipient_user_id)
       and dra.last_ip_hash is not null and dra.last_ip_hash = drb.last_ip_hash
       and da.device_hash <> db.device_hash
  ) into same_net;

  select exists (
    select 1 from wallet_deposits x join wallet_deposits y on lower(y.from_wallet) = lower(x.from_wallet)
     where x.user_id = t.initiator_user_id and y.user_id = t.recipient_user_id
       and nullif(x.from_wallet,'') is not null
  ) into same_wallet;

  select count(*) into pair_count from private_trades
   where status = 'completed'
     and ((initiator_user_id = t.initiator_user_id and recipient_user_id = t.recipient_user_id)
       or (initiator_user_id = t.recipient_user_id and recipient_user_id = t.initiator_user_id))
     and completed_at > now() - interval '30 days';

  select exists (select 1 from private_trade_items i where i.trade_id = t.id
    and coalesce((i.snapshot->>'nft')::boolean, false)) into nft_move;
  select exists (select 1 from private_trade_items i where i.trade_id = t.id
    and private_trade_high_rarity(i.snapshot->>'rarity')) into high_rar;

  select abs(extract(epoch from (ga.created_at - gb.created_at)) / 86400) into created_gap
    from game_players ga, game_players gb where ga.id = t.initiator_user_id and gb.id = t.recipient_user_id;

  if same_device then
    score := score + (w->>'sameDevice')::integer; flags := flags || array['SAME_DEVICE_STRONG_MATCH'];
  end if;
  if same_net then score := score + (w->>'sameNetwork')::integer; flags := flags || array['SAME_NETWORK']; end if;
  if same_wallet then score := score + (w->>'sameWallet')::integer; flags := flags || array['SAME_WALLET']; end if;
  if least(a_days, b_days) < coalesce((cfg->>'minAccountDays')::integer, 7) then
    score := score + (w->>'newAccount')::integer; flags := flags || array['NEW_ACCOUNT'];
  end if;
  if coalesce(created_gap, 999) <= 1 then score := score + 10; flags := flags || array['ACCOUNTS_CREATED_TOGETHER']; end if;
  if greatest(a_value, b_value) > 0
     and least(a_value, b_value) < greatest(a_value, b_value) * 0.15 then
    score := score + (w->>'oneSided')::integer; flags := flags || array['ONE_SIDED_TRADE'];
  end if;
  if nft_move then score := score + (w->>'nftTransfer')::integer; flags := flags || array['NFT_TRANSFER']; end if;
  if high_rar then score := score + (w->>'highRarity')::integer; flags := flags || array['HIGH_RARITY_TRANSFER']; end if;
  if pair_count >= 3 then score := score + (w->>'repeatedPair')::integer; flags := flags || array['REPEATED_PAIR']; end if;

  if same_device and (nft_move or high_rar) then score := score + 20; flags := flags || array['SELF_TRANSFER_SUSPECT']; end if;

  score := least(100, greatest(0, score));
  level := case when score >= (cfg->>'riskCritical')::integer then 'CRITICAL'
                when score >= (cfg->>'riskHigh')::integer then 'HIGH'
                when score >= (cfg->>'riskMedium')::integer then 'MEDIUM'
                else 'LOW' end;

  update private_trades set risk_score = score, risk_flags = flags, updated_at = now() where id = t.id;
  return jsonb_build_object('score', score, 'level', level, 'flags', to_jsonb(flags),
    'valueA', a_value, 'valueB', b_value);
end $$;