import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

function authenticate(initData) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error('Telegram authentication is not configured.');
  const params = new URLSearchParams(initData), hash = params.get('hash') || '';
  params.delete('hash');
  const check = [...params.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join('\n');
  const secret = createHmac('sha256', 'WebAppData').update(token).digest();
  const expected = Buffer.from(createHmac('sha256', secret).update(check).digest('hex'), 'hex'), received = Buffer.from(hash, 'hex');
  const authDate = Number(params.get('auth_date'));
  if (received.length !== expected.length || !timingSafeEqual(received, expected) || !Number.isFinite(authDate) || Math.abs(Date.now() / 1000 - authDate) > 86400) throw new Error('Invalid or expired Telegram initData.');
  const user = JSON.parse(params.get('user') || 'null');
  if (!user?.id) throw new Error('Telegram user is missing.');
  return user;
}
const isUuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed.' });
  try {
    const user = authenticate(typeof req.body?.initData === 'string' ? req.body.initData : '');
    const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL, serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !serviceKey) return res.status(503).json({ error: 'Wallet backend is not configured.' });
    const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const hotWallet = String(process.env.TON_HOT_WALLET || '').trim();
    if (hotWallet) {
      const configured = await db.from('wallet_settings').upsert({ key: 'ton_hot_wallet', value_text: hotWallet, updated_at: new Date().toISOString() });
      if (configured.error) throw configured.error;
    }
    const action = String(req.body?.action || 'summary');
    let fn = 'get_wallet_summary', args = { p_telegram_id: user.id };
    if (action === 'deposit') {
      const amount = Number(req.body?.amountTon), address = String(req.body?.walletAddress || '');
      if (!Number.isFinite(amount) || amount <= 0 || !address) throw new Error('Valor de depósito inválido.');
      fn = 'create_wallet_deposit';
      args = { ...args, p_amount_ton: amount, p_from_wallet: address, p_idempotency_key: `deposit:${user.id}:${String(req.body?.idempotencyKey || randomUUID())}` };
    } else if (action === 'withdraw') {
      const amount = Number(req.body?.amountFc), address = String(req.body?.walletAddress || '');
      if (!Number.isInteger(amount) || amount < 100000 || amount % 100000 !== 0 || !address) throw new Error('O valor deve ser múltiplo de 100.000 FC.');
      fn = 'request_wallet_withdrawal';
      args = { ...args, p_amount_fc: amount, p_wallet_address: address, p_idempotency_key: `withdraw:${user.id}:${String(req.body?.idempotencyKey || randomUUID())}` };
    } else if (action === 'egg-order') {
      if (!isUuid(req.body?.eggId)) throw new Error('Ovo inválido.');
      fn = 'create_pet_egg_order';
      args = { ...args, p_egg_id: req.body.eggId, p_idempotency_key: `egg:${user.id}:${String(req.body?.idempotencyKey || randomUUID())}` };
    } else if (action !== 'summary') throw new Error('Ação inválida.');
    const { data, error } = await db.rpc(fn, args);
    if (error) throw error;
    if (action === 'deposit' || action === 'withdraw') {
      const walletAddress = String(req.body?.walletAddress || '').trim();
      const { data: player, error: playerError } = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
      if (playerError) throw playerError;
      if (player?.id && walletAddress) {
        const connected = await db.from('pool_wallets').upsert({ user_id: player.id, wallet_address: walletAddress, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
        if (connected.error) throw connected.error;
      }
    }
    return res.status(200).json(data);
  } catch (error) {
    return res.status(400).json({ error: error instanceof Error ? error.message : 'Wallet request failed.' });
  }
}
