// Automatic TON deposit verifier (worker).
// Runs on a schedule and reconciles EVERY deposit that is still waiting for its payment:
// pending_payment -> blockchain match -> payment_confirmed -> FC credited (credited).
// It is fully idempotent: a deposit can only ever be credited once, and one transaction hash
// can only ever pay for one operation (enforced in the database).
import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { toFriendlyTonAddress } from '../_shared/tonAddress.ts';

const TONCENTER_BASE = (Deno.env.get('TONCENTER_BASE_URL') || 'https://toncenter.com').replace(/\/+$/, '');

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

async function fetchIncoming(hotWallet: string, pages = 5): Promise<any[]> {
  const apiKey = String(Deno.env.get('TONCENTER_API_KEY') || '').trim();
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (apiKey) headers['X-API-Key'] = apiKey;
  const all: any[] = [];
  for (let page = 0; page < pages; page++) {
    const url = `${TONCENTER_BASE}/api/v3/transactions?account=${encodeURIComponent(hotWallet)}&limit=100&offset=${page * 100}&sort=desc`;
    const response = await fetch(url, { headers });
    if (!response.ok) {
      console.error('[TON TX] toncenter error', response.status, await response.text());
      break;
    }
    const payload = await response.json().catch(() => null);
    const batch = Array.isArray(payload?.transactions) ? payload.transactions : [];
    all.push(...batch);
    if (batch.length < 100) break;
  }
  return all;
}

const msgComment = (message: any): string =>
  String(message?.message_content?.decoded?.comment ?? message?.decoded_body?.text ?? '').trim();

const txHashOf = (tx: any): string => String(tx?.hash || tx?.in_msg?.hash || '');

const sameTonAddress = (a: unknown, b: unknown): boolean => {
  const norm = (value: unknown) => {
    const raw = String(value ?? '').trim();
    if (!raw) return '';
    return (toFriendlyTonAddress(raw) || raw).toLowerCase();
  };
  const left = norm(a);
  return Boolean(left) && left === norm(b);
};

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

    const reset = await db.from('game_settings').select('value').eq('key', 'game_reset_in_progress').maybeSingle();
    if (reset.error) throw new Error('Reset availability check failed');
    if (reset.data?.value === true) return json({ ok: true, skipped: 'game_reset' });
    const epoch = await db.from('game_settings').select('value').eq('key', 'game_reset_epoch').maybeSingle();
    if (epoch.error) throw new Error('Reset epoch check failed');
    const epochSeconds = epoch.data?.value ? Date.parse(String(epoch.data.value)) / 1000 : 0;

    const settings = await db.from('wallet_settings').select('value_text').eq('key', 'ton_hot_wallet').maybeSingle();
    const hotWallet = String(settings.data?.value_text || Deno.env.get('TON_HOT_WALLET') || '').trim();
    if (!hotWallet) return json({ error: 'Hot wallet is not configured.' }, 503);

    const pending = await db
      .from('wallet_deposits')
      .select('id, user_id, amount_ton, payment_comment, from_wallet, status, created_at')
      .is('tx_hash', null)
      .in('status', ['pending', 'confirmed', 'expired'])
      .gte('created_at', new Date(Date.now() - 30 * 86_400_000).toISOString())
      .order('created_at', { ascending: false })
      .limit(200);
    if (pending.error) throw new Error(pending.error.message);
    const deposits = pending.data ?? [];
    

    const transactions = (await fetchIncoming(hotWallet)).filter(tx => !epochSeconds || Number(tx?.now ?? 0) >= epochSeconds);
    const used = new Set<string>();
    const credited: string[] = [];
    const stillPending: string[] = [];

    for (const deposit of deposits) {
      const comment = String(deposit.payment_comment || '').trim();
      const expectedNano = BigInt(Math.round(Number(deposit.amount_ton) * 1e9));
      const minNano = (expectedNano * 97n) / 100n;
      const createdAt = new Date(String(deposit.created_at)).getTime();
      console.log('[DEPOSIT VERIFY]', JSON.stringify({ orderId: deposit.id, userId: deposit.user_id, expectedNano: expectedNano.toString(), createdAt: deposit.created_at }));

      const candidate = (byComment: boolean) => transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg) return false;
        const hash = txHashOf(tx);
        if (!hash || used.has(hash)) return false;
        const value = BigInt(String(inMsg.value ?? '0'));
        if (value < minNano || value < 1_000_000_000n) return false;
        const txComment = msgComment(inMsg);
        if (byComment) return Boolean(comment) && txComment === comment;
        if (txComment) return false;
        const utime = Number(tx?.now ?? inMsg?.created_at ?? 0) * 1000;
        if (utime && utime < createdAt - 300_000) return false;
        return sameTonAddress(inMsg.source, deposit.from_wallet);
      });

      const match = candidate(true) ?? candidate(false);
      if (!match) { stillPending.push(deposit.id); continue; }

      const txHash = txHashOf(match);
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0'));
      console.log('[TON TX]', JSON.stringify({ hash: txHash, amountNano: receivedNano.toString(), destination: hotWallet, timestamp: match?.now }));
      const { data, error } = await db.rpc('confirm_wallet_deposit', { p_deposit_id: deposit.id, p_tx_hash: txHash, p_amount_nano: receivedNano.toString() });
      if (error) {
        console.error('[MATCH RESULT]', JSON.stringify({ orderId: deposit.id, matched: true, credited: false, reason: error.message }));
        stillPending.push(deposit.id);
        if (String(error.message).includes('TX_ALREADY_USED')) used.add(txHash);
        continue;
      }
      used.add(txHash);
      credited.push(deposit.id);
      console.log('[CREDIT]', JSON.stringify({ orderId: deposit.id, fcAmount: (data as any)?.amountFc, poolContribution: (data as any)?.poolContribution?.poolAmountTon ?? null }));
    }

    // Battle pass orders: activated ONLY by a payment carrying the order's own comment,
    // so a plain deposit can never activate a pass. The DB decides the tier from the order.
    const passOrders = await db
      .from('season_pass_orders')
      .select('id, user_id, tier, amount_nano, payment_comment, status, created_at')
      .is('tx_hash', null)
      .in('status', ['pending', 'paid', 'expired'])
      .gte('created_at', new Date(Date.now() - 30 * 86_400_000).toISOString())
      .order('created_at', { ascending: false })
      .limit(200);
    const passActivated: string[] = [];
    for (const order of passOrders.data ?? []) {
      const comment = String(order.payment_comment || '').trim();
      if (!comment) continue;
      const expectedNano = BigInt(String(order.amount_nano || '0'));
      const minNano = (expectedNano * 97n) / 100n;
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || msgComment(inMsg) !== comment) return false;
        const hash = txHashOf(tx);
        if (!hash || used.has(hash)) return false;
        return BigInt(String(inMsg.value ?? '0')) >= minNano;
      });
      if (!match) continue;
      const txHash = txHashOf(match);
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      const { error } = await db.rpc('confirm_season_pass_order', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
      if (error) { console.error('[PASS ACTIVATE]', JSON.stringify({ orderId: order.id, reason: error.message })); continue; }
      used.add(txHash);
      passActivated.push(order.id);
      console.log('[PASS ACTIVATE]', JSON.stringify({ orderId: order.id, tier: order.tier, txHash }));
    }

    const eggsDelivered: string[] = [];

    // Step 1 — orders already paid on-chain but whose product was never handed over: deliver now (idempotent).
    const paidUndelivered = await db
      .from('pet_egg_orders')
      .select('id, user_id, price_ton, tx_hash, status')
      .not('tx_hash', 'is', null)
      .neq('status', 'delivered')
      .gte('created_at', new Date(Date.now() - 90 * 86_400_000).toISOString())
      .limit(200);
    for (const order of paidUndelivered.data ?? []) {
      const { error } = await db.rpc('deliver_pet_egg_order', { p_order_id: order.id });
      if (error) {
        console.error('[EGG DELIVER RETRY]', JSON.stringify({ orderId: order.id, reason: error.message }));
        await db.from('ton_payment_logs').insert({ order_kind: 'egg', order_id: order.id, user_id: order.user_id, tx_hash: order.tx_hash, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: error.message });
        continue;
      }
      eggsDelivered.push(String(order.id));
      await db.from('ton_payment_logs').insert({ order_kind: 'egg', order_id: order.id, user_id: order.user_id, tx_hash: order.tx_hash, blockchain_status: 'found', fulfillment_status: 'completed' });
    }

    // Step 2 — premium egg purchases still awaiting payment: identified ONLY by the order's own
    // unique comment (never by amount), and kept verifiable for 30 days.
    const eggOrders = await db.rpc('ton_pending_purchase_orders', { p_max_age_days: 30 });
    if (eggOrders.error) console.error('[EGG RECONCILE]', eggOrders.error.message);

    for (const order of (eggOrders.data ?? []) as any[]) {
      const comment = String(order.payment_comment || '').trim();
      const expectedNano = BigInt(String(order.amount_nano || '0'));
      const minNano = (expectedNano * 97n) / 100n;
      const logRow: Record<string, unknown> = {
        order_kind: order.order_kind,
        order_id: order.order_id,
        user_id: order.user_id,
        telegram_id: order.telegram_id,
        product_id: order.product_id,
        expected_amount_nano: expectedNano.toString(),
        destination_wallet: hotWallet,
        payment_reference: comment,
      };
      if (!comment) continue;
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || msgComment(inMsg) !== comment) return false;
        const hash = txHashOf(tx);
        if (!hash || used.has(hash)) return false;
        return BigInt(String(inMsg.value ?? '0')) >= minNano;
      });
      if (!match) {
        continue;
      }
      const txHash = txHashOf(match);
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      const { error } = await db.rpc('confirm_pet_egg_purchase', { p_order_id: order.order_id, p_tx_hash: txHash, p_amount_nano: receivedNano });
      if (error) {
        console.error('[EGG DELIVER]', JSON.stringify({ orderId: order.order_id, reason: error.message }));
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: error.message });
        if (String(error.message).includes('TX_ALREADY_USED')) used.add(txHash);
        continue;
      }
      used.add(txHash);
      eggsDelivered.push(String(order.order_id));
      await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'completed' });
      console.log('[EGG DELIVER]', JSON.stringify({ orderId: order.order_id, product: order.product_id, txHash }));
    }

    // Player Market: external TON purchases. Each intent has its own unique comment and a
    // reserved listing; a tx hash can only ever pay for one intent (enforced in the database).
    const marketPaid: string[] = [];
    await db.rpc('market_expire_payment_intents');
    const intents = await db.rpc('market_pending_payment_intents', { p_max_age_minutes: 120 });
    if (intents.error) console.error('[MARKET RECONCILE]', intents.error.message);
    for (const intent of (intents.data ?? []) as any[]) {
      const comment = String(intent.payment_comment || '').trim();
      if (!comment) continue;
      const expectedNano = BigInt(String(Math.round(Number(intent.amount_nano))));
      const minNano = (expectedNano * 97n) / 100n;
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || msgComment(inMsg) !== comment) return false;
        const hash = txHashOf(tx);
        if (!hash || used.has(hash)) return false;
        return BigInt(String(inMsg.value ?? '0')) >= minNano;
      });
      if (!match) continue;
      const txHash = txHashOf(match);
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      const { error } = await db.rpc('market_confirm_payment_intent', {
        p_payment_id: intent.payment_id,
        p_tx_hash: txHash,
        p_amount_nano: receivedNano,
      });
      if (error) {
        console.error('[MARKET PAYMENT]', JSON.stringify({ paymentId: intent.payment_id, reason: error.message }));
        if (String(error.message).includes('TX_ALREADY_USED')) used.add(txHash);
        continue;
      }
      used.add(txHash);
      marketPaid.push(String(intent.payment_id));
      console.log('[MARKET PAYMENT]', JSON.stringify({ paymentId: intent.payment_id, listingId: intent.listing_id, txHash }));
    }

    // NFT purchases (pets, heroes and exclusive equipment) paid through TON Connect.
    // Previously these were only reconciled while the player kept the shop open, so a payment
    // made right before closing the mini app could stay pending forever. Now the worker
    // delivers them server-side, every minute, fully idempotently.
    const nftKinds = [
      { table: 'nft_pet_orders', kind: 'nft', confirmFn: 'nft_confirm_purchase', deliverFn: 'nft_deliver_order' },
      { table: 'nft_hero_orders', kind: 'nft_hero', confirmFn: 'nft_hero_confirm_purchase', deliverFn: 'nft_hero_deliver_order' },
      { table: 'nft_equipment_orders', kind: 'nft_equipment', confirmFn: 'nft_equipment_confirm_purchase', deliverFn: 'nft_equipment_deliver_order' },
    ] as const;
    const nftDelivered: string[] = [];

    for (const cfg of nftKinds) {
      // Step 1 — already paid on-chain but never handed over: retry delivery.
      const paid = await db
        .from(cfg.table)
        .select('id, user_id, tx_hash, status')
        .not('tx_hash', 'is', null)
        .is('delivered_at', null)
        .gte('created_at', new Date(Date.now() - 90 * 86_400_000).toISOString())
        .limit(200);
      for (const order of paid.data ?? []) {
        const { error } = await db.rpc(cfg.deliverFn, { p_order_id: order.id });
        if (error) {
          console.error('[NFT DELIVER RETRY]', JSON.stringify({ kind: cfg.kind, orderId: order.id, reason: error.message }));
          continue;
        }
        nftDelivered.push(String(order.id));
        await db.from('ton_payment_logs').insert({
          order_kind: cfg.kind, order_id: order.id, user_id: order.user_id, tx_hash: order.tx_hash,
          blockchain_status: 'found', fulfillment_status: 'completed', destination_wallet: hotWallet,
        });
      }

      // Step 2 — still awaiting payment: matched ONLY by the order's own unique comment.
      const awaiting = await db
        .from(cfg.table)
        .select('id, user_id, price_ton, amount_nano, payment_comment, status, created_at')
        .is('tx_hash', null)
        .in('status', ['pending', 'paid', 'confirmed', 'expired'])
        .gte('created_at', new Date(Date.now() - 30 * 86_400_000).toISOString())
        .order('created_at', { ascending: false })
        .limit(200);
      for (const order of awaiting.data ?? []) {
        const comment = String(order.payment_comment || '').trim();
        if (!comment) continue;
        const expectedNano = BigInt(String(order.amount_nano || '0'));
        if (expectedNano <= 0n) continue;
        const minNano = (expectedNano * 97n) / 100n;
        const match = transactions.find((tx: any) => {
          const inMsg = tx?.in_msg;
          if (!inMsg || msgComment(inMsg) !== comment) return false;
          const hash = txHashOf(tx);
          if (!hash || used.has(hash)) return false;
          return BigInt(String(inMsg.value ?? '0')) >= minNano;
        });
        const logRow: Record<string, unknown> = {
          order_kind: cfg.kind, order_id: order.id, user_id: order.user_id,
          expected_amount_nano: expectedNano.toString(), destination_wallet: hotWallet,
          payment_reference: comment,
        };
        if (!match) continue;
        const txHash = txHashOf(match);
        const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
        const { error } = await db.rpc(cfg.confirmFn, { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
        if (error) {
          console.error('[NFT DELIVER]', JSON.stringify({ kind: cfg.kind, orderId: order.id, reason: error.message }));
          await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: error.message });
          if (String(error.message).includes('TX_ALREADY_USED')) used.add(txHash);
          continue;
        }
        used.add(txHash);
        nftDelivered.push(String(order.id));
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'completed' });
        console.log('[NFT DELIVER]', JSON.stringify({ kind: cfg.kind, orderId: order.id, txHash }));
      }
    }

    // OVERPAYMENT / DUPLICATE PAYMENT SWEEP.
    // A wallet that fires the same intent twice sends the money twice while the product is (correctly)
    // delivered only once. Those extra transfers used to stay unclaimed on the hot wallet: now every
    // transfer whose comment belongs to an ALREADY SETTLED order is credited to the player's internal
    // TON balance and logged as OVERPAYMENT_DETECTED. Fully idempotent (one tx hash = one absorption).
    const duplicatesCredited: Array<{ txHash: string; amountTon: number }> = [];
    for (const tx of transactions) {
      const inMsg = tx?.in_msg;
      if (!inMsg) continue;
      const comment = msgComment(inMsg);
      if (!comment.startsWith('forge_')) continue;
      const txHash = txHashOf(tx);
      if (!txHash || used.has(txHash)) continue;
      const valueNano = BigInt(String(inMsg.value ?? '0'));
      if (valueNano <= 0n) continue;
      const { data, error } = await db.rpc('ton_absorb_duplicate_payment', {
        p_comment: comment, p_tx_hash: txHash, p_amount_nano: valueNano.toString(),
      });
      if (error) { console.error('[OVERPAYMENT_DETECTED]', JSON.stringify({ txHash, comment, reason: error.message })); continue; }
      if ((data as any)?.status !== 'credited') continue;
      used.add(txHash);
      duplicatesCredited.push({ txHash, amountTon: Number((data as any).amountTon) });
      console.log('[OVERPAYMENT_DETECTED]', JSON.stringify({ txHash, comment, kind: (data as any).kind, orderId: (data as any).orderId, amountTon: (data as any).amountTon }));
    }

    return json({ checked: deposits.length, credited, pending: stillPending, passActivated, eggsDelivered, marketPaid, nftDelivered, duplicatesCredited });




  } catch (error) {
    console.error('[FORGE ERROR] ton-reconcile', error);
    return json({ error: 'Deposit reconciliation failed.' }, 500);
  }
});
