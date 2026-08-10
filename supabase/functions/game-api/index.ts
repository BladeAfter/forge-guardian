import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';

type TelegramUser = {
  id: number;
  first_name?: string;
  last_name?: string;
  username?: string;
  photo_url?: string;
};

const encoder = new TextEncoder();

async function hmac(key: ArrayBuffer | Uint8Array, message: string): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey('raw', key as ArrayBuffer, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(message));
  return new Uint8Array(signature);
}

const toHex = (bytes: Uint8Array) => [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Mini App initData is signed by the GAME bot. Extra names are kept as fallback candidates so a token rename/swap never locks players out. */
const GAME_TOKEN_VARS = ['TELEGRAM_BOT_TOKEN_GAME', 'TELEGRAM_GAME_BOT_TOKEN', 'TELEGRAM_BOT_TOKEN'] as const;
const gameBotToken = () => {
  for (const name of GAME_TOKEN_VARS) {
    const token = String(Deno.env.get(name) || '').trim();
    if (token) return token;
  }
  return '';
};
const candidateBotTokens = () =>
  GAME_TOKEN_VARS.map((name) => String(Deno.env.get(name) || '').trim())
    .filter((token, index, all) => token && all.indexOf(token) === index);


const AUTH_MAX_AGE_SECONDS = Math.max(300, Number(Deno.env.get('TELEGRAM_AUTH_MAX_AGE_SECONDS') || 86_400));

export class TelegramAuthError extends Error {
  constructor(public reason: string, message: string) {
    super(message);
  }
}

export type TelegramAuthResult = { user: TelegramUser; authDate: number; ageSeconds: number };

/**
 * Validates the signed Telegram Mini App initData server-side (official algorithm).
 * The raw initData string is used exactly as Telegram provided it — never decoded or re-encoded.
 */
export async function validateTelegramInitData(initData: string): Promise<TelegramAuthResult> {
  const tokens = candidateBotTokens();
  if (!tokens.length) throw new TelegramAuthError('bot_token_missing', 'A autenticação do Telegram não está configurada.');
  if (!initData) throw new TelegramAuthError('init_data_missing', 'Sessão do Telegram ausente. Abra o jogo pelo Telegram.');

  const params = new URLSearchParams(initData);
  const hash = (params.get('hash') || '').toLowerCase();
  params.delete('hash');
  const check = [...params.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');

  const authDate = Number(params.get('auth_date'));
  const ageSeconds = Number.isFinite(authDate) ? Math.round(Date.now() / 1000 - authDate) : Number.NaN;

  if (!hash) throw new TelegramAuthError('hash_missing', 'Sessão do Telegram inválida (assinatura ausente).');
  let matched = false;
  for (const token of tokens) {
    const secret = await hmac(encoder.encode('WebAppData'), token);
    if (safeEqual(toHex(await hmac(secret, check)), hash)) {
      matched = true;
      break;
    }
  }
  if (!matched) {
    // Signature mismatch means the initData was signed by a bot whose token is not configured here.
    throw new TelegramAuthError('signature_mismatch', 'Assinatura do Telegram não confere com o bot configurado. Verifique o token do bot do jogo.');
  }
  if (!Number.isFinite(authDate)) throw new TelegramAuthError('auth_date_missing', 'Sessão do Telegram inválida (auth_date ausente).');
  if (ageSeconds > AUTH_MAX_AGE_SECONDS) {
    throw new TelegramAuthError('auth_date_expired', 'Sessão do Telegram expirada. Feche e abra o jogo novamente.');
  }

  const user = JSON.parse(params.get('user') || 'null') as TelegramUser | null;
  if (!user?.id) throw new TelegramAuthError('user_missing', 'Usuário do Telegram não encontrado.');
  return { user, authDate, ageSeconds };
}

/** Reads initData from the header first (single API client contract) and falls back to the body. */
function readInitData(req: Request, body: Record<string, any>): string {
  const header = req.headers.get('X-Telegram-Init-Data') || '';
  if (header) return header;
  return typeof body.initData === 'string' ? body.initData : '';
}

async function botUsername(token: string): Promise<string | null> {
  if (!token) return null;
  try {
    const response = await fetch(`https://api.telegram.org/bot${token}/getMe`);
    const payload = await response.json().catch(() => null);
    return payload?.ok && payload?.result?.username ? String(payload.result.username).replace(/^@/, '') : null;
  } catch {
    return null;
  }
}

const isUuid = (value: unknown): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

// The Mini App sends the raw initData in a custom header, so it must be allowed by CORS.
const cors: Record<string, string> = {
  ...corsHeaders,
  'Access-Control-Allow-Headers': `${(corsHeaders as Record<string, string>)['Access-Control-Allow-Headers'] ?? 'authorization, apikey, content-type'}, x-telegram-init-data`,
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

function serviceClient() {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('O backend do Forge Village não está configurado.');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

type Db = ReturnType<typeof serviceClient>;

async function rpc(db: Db, fn: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data;
}

async function handleBoss(db: Db, user: TelegramUser, body: Record<string, any>) {
  const action = String(body.action || 'process');
  // Hero shop pricing/odds are admin-controlled settings, read live on every open.
  if (action === 'shop') return await rpc(db, 'get_hero_shop_config', {});
  // Team management (equip/unequip/team) never requires an active boss; only `attack` does.
  const fn = action === 'equip' ? 'equip_combat_hero'
    : action === 'unequip' ? 'unequip_combat_hero'
    : action === 'team' ? 'set_boss_team'
    : action === 'claim' ? 'claim_boss_reward'
    : action === 'recruit' ? 'recruit_heroes'
    : action === 'attack' ? 'attack_boss'
    : action === 'get' ? 'get_boss_combat'
    : 'process_boss_combat';
  const args: Record<string, unknown> = { p_telegram_id: user.id };
  if (action === 'equip' || action === 'unequip') {
    const slot = Number(body.slot);
    if (!Number.isInteger(slot) || slot < 1 || slot > 5) throw new Error('Slot inválido.');
    args.p_slot = slot;
  }
  if (action === 'equip') {
    if (!isUuid(body.hero_id)) throw new Error('Herói inválido.');
    args.p_hero_id = body.hero_id;
  }
  if (action === 'team') args.p_hero_ids = Array.isArray(body.heroIds) ? body.heroIds : [];
  if (action === 'recruit') args.p_count = Number(body.count);
  const data = await rpc(db, fn, args);
  if (action !== 'recruit' && data && typeof data === 'object') {
    const pets = await db.rpc('get_pet_dashboard', { p_telegram_id: user.id });
    if (!pets.error) {
      return { ...(data as Record<string, unknown>), petSummary: { activePet: pets.data?.activePet ?? null, bonuses: pets.data?.bonuses ?? {} } };
    }
  }
  return data;
}

async function handlePets(db: Db, user: TelegramUser, body: Record<string, any>) {
  const action = String(body.action || 'dashboard');
  let fn = 'get_pet_dashboard';
  const args: Record<string, unknown> = { p_telegram_id: user.id };
  const requestKey = (prefix: string) => {
    const key = String(body.idempotencyKey || crypto.randomUUID());
    if (key.length < 8 || key.length > 100) throw new Error('Chave de requisição inválida.');
    return `${prefix}:${user.id}:${key}`;
  };
  if (action === 'activate') {
    if (!isUuid(body.playerPetId)) throw new Error('Pet inválido.');
    fn = 'activate_pet';
    args.p_player_pet_id = body.playerPetId;
  } else if (action === 'feed') {
    // Feeding only grants XP/levels. Food type and XP value are resolved server-side.
    if (!isUuid(body.playerPetId)) throw new Error('Pet inválido.');
    const quantity = Number(body.quantity ?? body.amount);
    const foodCode = String(body.foodCode || '');
    if (!/^[a-z0-9_]{3,40}$/.test(foodCode)) throw new Error('Comida inválida.');
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 100) throw new Error('Quantidade de comida inválida.');
    fn = 'feed_pet_item';
    args.p_player_pet_id = body.playerPetId;
    args.p_food_code = foodCode;
    args.p_quantity = quantity;
    args.p_idempotency_key = requestKey('pet_feed_item');
  } else if (action === 'evolve') {
    // Evolution consumes Forge Coins + this pet's fragments and rolls buffs server-side.
    if (!isUuid(body.playerPetId)) throw new Error('Pet inválido.');
    fn = 'evolve_pet';
    args.p_player_pet_id = body.playerPetId;
    args.p_idempotency_key = requestKey('pet_evolve');
  } else if (action === 'hatch') {
    if (!isUuid(body.eggId)) throw new Error('Ovo inválido.');
    fn = 'hatch_pet_egg';
    args.p_egg_id = body.eggId;
    args.p_idempotency_key = requestKey('pet_hatch');
  } else if (action === 'buy-egg') {
    // Egg price, purchasability and balance are all resolved server-side.
    if (!isUuid(body.eggId)) throw new Error('Ovo inválido.');
    const quantity = Number(body.quantity ?? 1);
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 50) throw new Error('Quantidade inválida.');
    fn = 'buy_pet_egg';
    args.p_egg_id = body.eggId;
    args.p_quantity = quantity;
    args.p_idempotency_key = requestKey('pet_egg_buy');
  } else if (action === 'buy-food') {
    const quantity = Number(body.quantity ?? 1);
    const foodCode = String(body.foodCode || '');
    if (!/^[a-z0-9_]{3,40}$/.test(foodCode)) throw new Error('Comida inválida.');
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 500) throw new Error('Quantidade inválida.');
    fn = 'buy_pet_food';
    args.p_food_code = foodCode;
    args.p_quantity = quantity;
    args.p_idempotency_key = requestKey('pet_food_buy');
  } else if (action !== 'dashboard') throw new Error('Ação inválida.');


  const data = await rpc(db, fn, args) as any;
  const store = await db.rpc('get_pet_egg_store', { p_telegram_id: user.id });
  if (!store.error && data && typeof data === 'object') {
    if (data.dashboard) data.dashboard.eggs = store.data;
    else data.eggs = store.data;
  }
  return data;
}


async function handlePvp(db: Db, user: TelegramUser, body: Record<string, any>) {
  const action = String(body.action || 'dashboard');
  // The hero collection must never depend on PvP matchmaking or stats.
  if (action === 'heroes') {
    const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
    if (player.error) throw new Error(player.error.message);
    if (!player.data?.id) return { heroes: [] };
    const heroes = await db
      .from('player_heroes')
      .select('id,name,rarity,level,image,archetype,final_atk,final_hp,is_season_exclusive,exclusive_badge')
      .eq('user_id', player.data.id)
      .order('created_at', { ascending: false });
    if (heroes.error) throw new Error(heroes.error.message);
    return {
      heroes: (heroes.data ?? []).map((hero) => ({
        heroId: hero.id,
        name: hero.name,
        rarity: hero.rarity,
        level: hero.level,
        imageUrl: hero.image,
        archetype: hero.archetype,
        finalAtk: Math.round(Number(hero.final_atk) || 0),
        finalHp: Math.round(Number(hero.final_hp) || 0),
        defense: Math.round((Number(hero.final_hp) || 0) * 0.09),
        speed: 90 + (Number(hero.level) || 1),
        power: Math.round((Number(hero.final_atk) || 0) * 2 + (Number(hero.final_hp) || 0)),
        exclusiveBadge: hero.is_season_exclusive ? hero.exclusive_badge : null,
      })),
    };
  }

  let fn = 'get_pvp_dashboard';
  let args: Record<string, unknown> = { p_telegram_id: user.id };
  if (action === 'search') fn = 'search_pvp_opponents';
  else if (action === 'history') fn = 'get_pvp_history';
  else if (action === 'ranking') { fn = 'get_pvp_ranking'; args = {}; }
  else if (action === 'equip') {
    const slot = Number(body.slot);
    const teamType = String(body.teamType);
    if (!Number.isInteger(slot) || slot < 1 || slot > 5 || !['attack', 'defense'].includes(teamType) || !isUuid(body.heroId)) {
      throw new Error('Slot de equipe inválido.');
    }
    fn = 'save_pvp_team_slot';
    args = { ...args, p_team_type: teamType, p_slot: slot, p_hero_id: body.heroId };
  } else if (action === 'remove') {
    const slot = Number(body.slot);
    const teamType = String(body.teamType);
    if (!Number.isInteger(slot) || slot < 1 || slot > 5 || !['attack', 'defense'].includes(teamType)) throw new Error('Slot de equipe inválido.');
    fn = 'remove_pvp_team_slot';
    args = { ...args, p_team_type: teamType, p_slot: slot };
  } else if (action === 'battle') {
    if (!isUuid(body.opponentId)) throw new Error('Adversário inválido.');
    fn = 'start_pvp_battle';
    args = { ...args, p_opponent_id: body.opponentId };
  } else if (action !== 'dashboard') throw new Error('Ação inválida.');

  const data = await rpc(db, fn, args) as any;
  if (action === 'battle' && Array.isArray(data?.battleLog)) {
    data.battleLog = data.battleLog.filter((entry: any) => Number.isInteger(entry?.turn));
  }
  return data;
}

const TONCENTER_BASE = (Deno.env.get('TONCENTER_BASE_URL') || 'https://toncenter.com').replace(/\/+$/, '');

/** Reads the hot wallet transactions from TonCenter (v3) and returns the incoming ones. */
async function fetchHotWalletIncoming(hotWallet: string): Promise<any[]> {
  const apiKey = String(Deno.env.get('TONCENTER_API_KEY') || '').trim();
  if (!apiKey) throw new Error('A verificação on-chain não está configurada (TONCENTER_API_KEY).');
  const url = `${TONCENTER_BASE}/api/v3/transactions?account=${encodeURIComponent(hotWallet)}&limit=100&offset=0&sort=desc`;
  const response = await fetch(url, { headers: { 'X-API-Key': apiKey, Accept: 'application/json' } });
  if (!response.ok) {
    const details = await response.text();
    console.error(`[FORGE ERROR] toncenter [${response.status}]: ${details}`);
    throw new Error(`Não foi possível consultar a blockchain TON (${response.status}).`);
  }
  const payload = await response.json().catch(() => null);
  return Array.isArray(payload?.transactions) ? payload.transactions : [];
}

const msgComment = (message: any): string =>
  String(message?.message_content?.decoded?.comment ?? message?.decoded_body?.text ?? '').trim();

/**
 * Confirms pending deposits of this player by matching the payment comment and value
 * against real incoming transfers to the project hot wallet.
 */
async function verifyPendingDeposits(db: Db, user: TelegramUser) {
  const settings = await db.from('wallet_settings').select('value_text').eq('key', 'ton_hot_wallet').maybeSingle();
  if (settings.error) throw new Error(settings.error.message);
  const hotWallet = String(settings.data?.value_text || Deno.env.get('TON_HOT_WALLET') || '').trim();
  if (!hotWallet) throw new Error('A carteira de recebimento não está configurada.');

  const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
  if (player.error) throw new Error(player.error.message);
  if (!player.data?.id) throw new Error('Jogador não encontrado.');

  const pending = await db
    .from('wallet_deposits')
    .select('id, amount_ton, payment_comment, status')
    .eq('user_id', player.data.id)
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
    .limit(20);
  if (pending.error) throw new Error(pending.error.message);
  const deposits = pending.data ?? [];
  if (!deposits.length) return { checked: 0, confirmed: [], pending: [] };

  const transactions = await fetchHotWalletIncoming(hotWallet);
  const confirmed: string[] = [];
  const stillPending: string[] = [];

  for (const deposit of deposits) {
    const comment = String(deposit.payment_comment || '').trim();
    const expectedNano = BigInt(Math.round(Number(deposit.amount_ton) * 1e9));
    // 1% tolerance covers wallet fee rounding on the sender side.
    const minNano = (expectedNano * 99n) / 100n;
    const match = transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg) return false;
      const value = BigInt(String(inMsg.value ?? '0'));
      const sameComment = comment ? msgComment(inMsg) === comment : false;
      return sameComment && value >= minNano;
    });
    if (match) {
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const amountNano = String(match.in_msg?.value ?? expectedNano.toString());
      await rpc(db, 'confirm_wallet_deposit', { p_deposit_id: deposit.id, p_tx_hash: txHash, p_amount_nano: amountNano });
      confirmed.push(deposit.id);
    } else {
      stillPending.push(deposit.id);
    }
  }

  const summary = await rpc(db, 'get_wallet_summary', { p_telegram_id: user.id });
  return { checked: deposits.length, confirmed, pending: stillPending, summary };
}

async function handleWallet(db: Db, user: TelegramUser, body: Record<string, any>) {
  const hotWallet = String(Deno.env.get('TON_HOT_WALLET') || '').trim();
  if (hotWallet) {
    const configured = await db.from('wallet_settings').upsert({ key: 'ton_hot_wallet', value_text: hotWallet, updated_at: new Date().toISOString() });
    if (configured.error) throw new Error(configured.error.message);
  }
  const action = String(body.action || 'summary');
  if (action === 'verify-deposit') return await verifyPendingDeposits(db, user);
  let fn = 'get_wallet_summary';
  let args: Record<string, unknown> = { p_telegram_id: user.id };
  if (action === 'deposit') {
    const amount = Number(body.amountTon);
    const address = String(body.walletAddress || '');
    if (!Number.isFinite(amount) || amount <= 0 || !address) throw new Error('Valor de depósito inválido.');
    fn = 'create_wallet_deposit';
    args = { ...args, p_amount_ton: amount, p_from_wallet: address, p_idempotency_key: `deposit:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'withdraw') {
    const amount = Number(body.amountFc);
    const address = String(body.walletAddress || '');
    if (!Number.isInteger(amount) || amount < 100_000 || amount % 100_000 !== 0 || !address) throw new Error('O valor deve ser múltiplo de 100.000 FC.');
    fn = 'request_wallet_withdrawal';
    args = { ...args, p_amount_fc: amount, p_wallet_address: address, p_idempotency_key: `withdraw:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'egg-order') {
    if (!isUuid(body.eggId)) throw new Error('Ovo inválido.');
    fn = 'create_pet_egg_order';
    args = { ...args, p_egg_id: body.eggId, p_idempotency_key: `egg:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action !== 'summary') throw new Error('Ação inválida.');

  const data = await rpc(db, fn, args);
  if (action === 'deposit' || action === 'withdraw') {
    const walletAddress = String(body.walletAddress || '').trim();
    const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
    if (player.error) throw new Error(player.error.message);
    if (player.data?.id && walletAddress) {
      const connected = await db.from('pool_wallets').upsert(
        { user_id: player.data.id, wallet_address: walletAddress, updated_at: new Date().toISOString() },
        { onConflict: 'user_id' },
      );
      if (connected.error) throw new Error(connected.error.message);
    }
  }
  return data;
}

async function handleCalendar(db: Db, user: TelegramUser, body: Record<string, any>) {
  const action = String(body.action || 'dashboard');
  if (action === 'claim') {
    const day = Number(body.day);
    if (!Number.isInteger(day) || day < 1 || day > 30) throw new Error('Dia inválido.');
    return rpc(db, 'claim_calendar_day', { p_telegram_id: user.id, p_day: day });
  }
  if (action === 'open-chest') {
    if (!isUuid(body.inventoryItemId)) throw new Error('Baú inválido.');
    // The rarity roll always happens in the database: the client only names the item it owns.
    const source = ['calendar', 'shop', 'pass', 'mission', 'event'].includes(String(body.source)) ? String(body.source) : 'calendar';
    return rpc(db, 'open_hero_chest', { p_telegram_id: user.id, p_inventory_item_id: body.inventoryItemId, p_source: source });
  }
  if (action === 'inventory') return rpc(db, 'get_player_inventory', { p_telegram_id: user.id });
  if (action !== 'dashboard') throw new Error('Ação inválida.');
  return rpc(db, 'get_calendar_dashboard', { p_telegram_id: user.id });
}

async function handleSeasonPass(db: Db, user: TelegramUser, body: Record<string, any>) {
  const action = String(body.action || 'dashboard');
  let fn = 'get_season_pass_dashboard';
  let args: Record<string, unknown> = { p_telegram_id: user.id };
  if (action === 'order') {
    if (!['adventurer', 'legendary'].includes(body.tier)) throw new Error('Passe inválido.');
    fn = 'create_season_pass_order';
    args = { ...args, p_tier: body.tier, p_idempotency_key: `season:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'claim') {
    if (!isUuid(body.rewardId)) throw new Error('Recompensa inválida.');
    fn = 'claim_season_pass_reward';
    args = { ...args, p_reward_id: body.rewardId };
  } else if (action === 'open-mythic-egg') {
    if (!isUuid(body.itemId)) throw new Error('Item inválido.');
    fn = 'open_season_mythic_egg';
    args = { ...args, p_item_id: body.itemId };
  } else if (action !== 'dashboard') throw new Error('Ação inválida.');
  return rpc(db, fn, args);
}

async function botIdentity() {
  const token = gameBotToken();
  const configured = String(Deno.env.get('TELEGRAM_BOT_USERNAME') || '').trim().replace(/^@/, '');
  const appShortName = String(Deno.env.get('TELEGRAM_APP_SHORT_NAME') || '').trim() || null;
  if (configured) return { botUsername: configured, appShortName };
  const response = await fetch(`https://api.telegram.org/bot${token}/getMe`);
  const payload = await response.json().catch(() => null);
  const username = payload?.ok && payload?.result?.username ? String(payload.result.username).replace(/^@/, '') : '';
  if (!username) throw new Error('Não foi possível identificar o bot do Telegram.');
  return { botUsername: username, appShortName };
}

async function handleReferral(db: Db, user: TelegramUser, body: Record<string, any>) {
  const fullName = [user.first_name, user.last_name].filter(Boolean).join(' ');
  await rpc(db, 'touch_referral_player', {
    p_telegram_id: user.id,
    p_name: fullName,
    p_username: user.username || '',
    p_avatar: user.photo_url || '',
  });
  if (body.action === 'bind') {
    const inviterId = Number(body.inviterTelegramId);
    if (!Number.isSafeInteger(inviterId) || inviterId <= 0) throw new Error('Indicador inválido.');
    return rpc(db, 'bind_referral', { p_telegram_id: user.id, p_inviter_telegram_id: inviterId });
  }
  const level = body.level == null ? null : Number(body.level);
  if (level !== null && ![1, 2, 3].includes(level)) throw new Error('Filtro de nível inválido.');
  const offset = Math.max(0, Number(body.offset) || 0);
  const limit = Math.min(20, Math.max(1, Number(body.limit) || 20));
  const dashboard = await rpc(db, 'get_referral_dashboard_v2', { p_telegram_id: user.id, p_level: level, p_offset: offset, p_limit: limit }) as Record<string, unknown>;
  const identity = await botIdentity();
  const route = identity.appShortName ? `${identity.botUsername}/${identity.appShortName}` : identity.botUsername;
  const link = `https://t.me/${route}?startapp=${user.id}`;
  return { ...dashboard, ...identity, telegramId: user.id, link, referralLink: link };
}

const handlers: Record<string, (db: Db, user: TelegramUser, body: Record<string, any>) => Promise<unknown>> = {
  boss: handleBoss,
  pets: handlePets,
  pvp: handlePvp,
  wallet: handleWallet,
  calendar: handleCalendar,
  'season-pass': handleSeasonPass,
  referral: handleReferral,
  /** Daily quests: progress is only written by server-side event hooks, never by the client. */
  quests: async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    if (action === 'dashboard') return rpc(db, 'get_daily_quests', { p_telegram_id: user.id });
    if (action === 'claim-chest') return rpc(db, 'claim_daily_quest_chest', { p_telegram_id: user.id });
    if (action === 'claim') {
      const code = String(body.code || '');
      if (!/^[a-z0-9_]{3,40}$/.test(code)) throw new Error('QUEST_NOT_FOUND');
      return rpc(db, 'claim_daily_quest', { p_telegram_id: user.id, p_quest_code: code });
    }
    throw new Error('Ação inválida.');
  },
  /** Read-only feed of rewards already delivered to the player (never grants anything). */
  rewards: async (db, user, body) => {
    const limit = Math.min(Math.max(Number(body.limit ?? 5) || 5, 1), 100);
    const offset = Math.max(Number(body.offset ?? 0) || 0, 0);
    return rpc(db, 'get_reward_history', { p_telegram_id: user.id, p_limit: limit, p_offset: offset });
  },
  pool: async (db, user) => {
    return rpc(db, 'get_community_pool_dashboard', { p_telegram_id: user.id });
  },

  profile: async (db, user) => {
    if (!user.first_name) throw new Error('Usuário do Telegram não encontrado.');
    return rpc(db, 'upsert_telegram_player_profile', {
      p_telegram_id: user.id,
      p_first_name: user.first_name,
      p_last_name: user.last_name || null,
      p_username: user.username || null,
      p_photo_url: user.photo_url || null,
    });
  },
};

async function healthReport() {
  const report: Record<string, unknown> = {
    ok: false,
    app: 'Forge Village',
    backend: 'online',
    database: 'offline',
    telegram_auth: gameBotToken() ? 'configured' : 'missing',
    telegram_auth_max_age_seconds: AUTH_MAX_AGE_SECONDS,
    game_bot_token_source: GAME_TOKEN_VARS.find((name) => String(Deno.env.get(name) || '').trim()) ?? 'missing',
    accepted_bot_tokens: candidateBotTokens().length,
    game_bot_username: await botUsername(gameBotToken()),
    admin_bot_token_separated: Boolean(Deno.env.get('TELEGRAM_BOT_TOKEN_Admin') || Deno.env.get('TELEGRAM_ADMIN_BOT_TOKEN')),

    ton_onchain_check: Deno.env.get('TONCENTER_API_KEY') ? 'configured' : 'missing',
    time: new Date().toISOString(),
  };
  try {
    const db = serviceClient();
    const { error } = await db.from('game_settings').select('key', { count: 'exact', head: true });
    if (error) throw new Error(error.message);
    report.database = 'online';
    report.ok = report.telegram_auth === 'configured';
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('[FORGE ERROR]', { route: 'health', stage: 'database', message });
    report.database_error = message;
  }
  return report;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const feature = new URL(req.url).pathname.split('/').filter(Boolean).pop() || '';
  // Public, secret-free diagnostics endpoint. No initData required.
  if (feature === 'health') {
    const report = await healthReport();
    return json(report, report.ok ? 200 : 503);
  }

  if (req.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);

  // Dedicated auth probe: validates the session without touching any game data.
  if (feature === 'auth') {
    const probeBody = (await req.json().catch(() => ({}))) as Record<string, any>;
    const initData = readInitData(req, probeBody);
    try {
      const { user, authDate, ageSeconds } = await validateTelegramInitData(initData);
      return json({ ok: true, telegramId: user.id, username: user.username ?? null, authDate, ageSeconds, botUsername: await botUsername(gameBotToken()) });
    } catch (error) {
      const reason = error instanceof TelegramAuthError ? error.reason : 'unknown';
      const message = error instanceof Error ? error.message : 'Falha na autenticação do Telegram.';
      console.error('[TELEGRAM AUTH FAILED]', { route: 'auth', reason, initDataPresent: Boolean(initData), initDataLength: initData.length, authDate: new URLSearchParams(initData).get('auth_date') });
      return json({ ok: false, error: message, reason, code: 'TELEGRAM_AUTH', botUsername: await botUsername(gameBotToken()) }, 401);
    }
  }

  const handler = handlers[feature];
  if (!handler) return json({ error: `Recurso desconhecido: ${feature}` }, 404);

  let body: Record<string, any> = {};
  try {
    body = (await req.json()) as Record<string, any>;
  } catch {
    return json({ error: 'Corpo da requisição inválido.' }, 400);
  }

  let user: TelegramUser;
  const initData = readInitData(req, body);
  try {
    user = (await validateTelegramInitData(initData)).user;
  } catch (error) {
    const reason = error instanceof TelegramAuthError ? error.reason : 'unknown';
    const message = error instanceof Error ? error.message : 'Falha na autenticação do Telegram.';
    console.error('[TELEGRAM AUTH FAILED]', { feature, reason, initDataPresent: Boolean(initData), initDataLength: initData.length, authDate: new URLSearchParams(initData).get('auth_date') });
    return json({ error: message, reason, code: 'TELEGRAM_AUTH' }, 401);
  }

  try {
    const db = serviceClient();
    const data = await handler(db, user, body);
    return json(data ?? null);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Falha na requisição.';
    console.error('[FORGE API ERROR]', { feature, action: body.action ?? null, telegramId: user.id, message });
    return json({ error: message }, 400);
  }
});
