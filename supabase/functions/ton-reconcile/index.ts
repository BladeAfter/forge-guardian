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
    

    const transactions = await fetchIncoming(hotWallet);
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

    // Premium egg purchases: identified ONLY by the order's own unique comment (never by amount),
    // and kept verifiable for 30 days so a slow transfer is still delivered automatically.
    const eggOrders = await db.rpc('ton_pending_purchase_orders', { p_max_age_days: 30 });
    if (eggOrders.error) console.error('[EGG RECONCILE]', eggOrders.error.message);
    const eggsDelivered: string[] = [];
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
        await db.from('ton_payment_logs').insert({ ...logRow, blockchain_status: 'not_found', fulfillment_status: 'pending' });
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

    return json({ checked: deposits.length, credited, pending: stillPending, passActivated, eggsDelivered });

  } catch (error) {
    console.error('[FORGE ERROR] ton-reconcile', error);
    return json({ error: 'Deposit reconciliation failed.' }, 500);
  }
});
