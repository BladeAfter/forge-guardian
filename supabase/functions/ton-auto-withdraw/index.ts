// Automatic TON payouts (worker).
// Picks pending withdrawal requests that are inside the admin limit + daily cap,
// signs one transfer per request from the hot wallet and confirms it in the DB.
// Anything above the limit is left untouched for manual approval in the admin bot.
import { Buffer } from 'node:buffer';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { mnemonicToPrivateKey } from 'npm:@ton/crypto@3.3.0';
import {
  TonClient,
  WalletContractV4,
  WalletContractV5R1,
  WalletContractV3R2,
  internal,
  external,
  storeMessage,
  beginCell,
  toNano,
  Address,
} from 'npm:@ton/ton@15.1.0';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

const eqAddr = (a: string, b: string) => {
  try {
    return Address.parse(a).toRawString() === Address.parse(b).toRawString();
  } catch {
    return false;
  }
};

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const secret = String(Deno.env.get('TON_AUTO_WITHDRAW_SECRET') || '');
  const provided =
    req.headers.get('x-auto-withdraw-secret') || new URL(req.url).searchParams.get('key') || '';
  if (!secret || provided !== secret) return json({ error: 'unauthorized' }, 401);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  await db.rpc('auto_withdraw_register_worker', { p_key: secret });

  try {

    const cfgRes = await db.rpc('auto_withdraw_config');
    if (cfgRes.error) throw new Error(cfgRes.error.message);
    const cfg = cfgRes.data as Record<string, unknown>;
    if (!cfg?.enabled) return json({ ok: true, skipped: 'disabled' });

    // Signing key: raw ed25519 secret key (preferred) or 24/12-word mnemonic fallback.
    const rawKey = String(Deno.env.get('TON_WITHDRAW_SECRET_KEY') || '').trim();
    let keys: { publicKey: Buffer; secretKey: Buffer };
    if (/^[0-9a-fA-F]{128}$/.test(rawKey)) {
      const sk = Buffer.from(rawKey, 'hex');
      keys = { secretKey: sk, publicKey: sk.subarray(32) };
    } else {
      const mnemonic = String(Deno.env.get('TON_WITHDRAW_MNEMONIC') || '')
        .trim()
        .split(/\s+/)
        .filter(Boolean);
      if (mnemonic.length < 12) return json({ error: 'wallet_secret_missing' }, 503);
      keys = await mnemonicToPrivateKey(mnemonic);
    }

    const expected = String(cfg.hotWallet || Deno.env.get('TON_WITHDRAW_WALLET') || '').trim();
    const candidates = [
      WalletContractV5R1.create({ workchain: 0, publicKey: keys.publicKey }),
      WalletContractV4.create({ workchain: 0, publicKey: keys.publicKey }),
      WalletContractV3R2.create({ workchain: 0, publicKey: keys.publicKey }),
    ];
    const wallet = expected
      ? candidates.find(w => eqAddr(w.address.toString({ bounceable: false }), expected))
      : candidates[0];
    if (!wallet) {
      return json(
        {
          error: 'wallet_mismatch',
          derived: candidates.map(w => w.address.toString({ bounceable: false })),
        },
        400,
      );
    }

    const apiKey = String(Deno.env.get('TONCENTER_API_KEY') || '').trim();
    const client = new TonClient({
      endpoint: `${(Deno.env.get('TONCENTER_BASE_URL') || 'https://toncenter.com').replace(/\/+$/, '')}/api/v2/jsonRPC`,
      apiKey: apiKey || undefined,
    });
    const contract = client.open(wallet);

    const claimed = await db.rpc('auto_withdraw_claim_batch');
    if (claimed.error) throw new Error(claimed.error.message);
    const items = (claimed.data?.items ?? []) as Array<{
      id: string;
      walletAddress: string;
      netTon: number | string;
      telegramId: number | null;
    }>;
    if (!items.length) return json({ ok: true, paid: 0, results: [] });

    const balance = await contract.getBalance();
    const results: Array<Record<string, unknown>> = [];

    for (const item of items) {
      const amount = Number(item.netTon);
      try {
        if (!Number.isFinite(amount) || amount <= 0) throw new Error('invalid_amount');
        const need = toNano(amount.toFixed(9)) + toNano('0.02');
        if (balance < need) throw new Error('hot_wallet_insufficient_balance');

        const dest = Address.parse(String(item.walletAddress).trim());
        const seqno = await contract.getSeqno();
        const transfer = contract.createTransfer({
          seqno,
          secretKey: keys.secretKey,
          messages: [
            internal({
              to: dest,
              value: toNano(amount.toFixed(9)),
              bounce: false,
              body: '@MythreonBot',
            }),
          ],
        });
        const ext = external({
          to: contract.address,
          init: seqno === 0 ? wallet.init : undefined,
          body: transfer,
        });
        const cell = beginCell().store(storeMessage(ext)).endCell();
        const txHash = cell.hash().toString('hex');

        await client.sendFile(cell.toBoc());

        // Confirm the transfer really left the wallet before marking it paid.
        let confirmed = false;
        for (let i = 0; i < 30; i++) {
          await sleep(2000);
          if ((await contract.getSeqno()) > seqno) {
            confirmed = true;
            break;
          }
        }
        if (!confirmed) throw new Error('transfer_not_confirmed');

        const done = await db.rpc('auto_withdraw_complete', {
          p_withdrawal_id: item.id,
          p_tx_hash: txHash,
          p_amount_ton: amount,
        });
        if (done.error) throw new Error(`db_confirm_failed:${done.error.message}`);
        results.push({ id: item.id, status: 'paid', amount, txHash });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error('[AUTO WITHDRAW] failed', item.id, message);
        await db.rpc('auto_withdraw_release', { p_withdrawal_id: item.id, p_error: message });
        results.push({ id: item.id, status: 'failed', amount, error: message });
      }
    }

    return json({ ok: true, paid: results.filter(r => r.status === 'paid').length, results });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[AUTO WITHDRAW] fatal', message);
    return json({ error: message }, 500);
  }
});
