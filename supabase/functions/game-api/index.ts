import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { toFriendlyTonAddress } from '../_shared/tonAddress.ts';

type TelegramUser = {
  id: number;
  first_name?: string;
  last_name?: string;
  username?: string;
  photo_url?: string;
  language_code?: string;
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

/**
 * Membership check used by partner channels with validation enabled. Uses the GAME
 * bot (the one players interact with) and only trusts the explicit member statuses.
 * Any transport/permission failure returns false so a reward is never paid blindly.
 */
export async function telegramIsChatMember(chatId: string, telegramUserId: number): Promise<boolean> {
  const token = gameBotToken();
  if (!token) return false;
  try {
    const response = await fetch(`https://api.telegram.org/bot${token}/getChatMember`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, user_id: telegramUserId }),
    });
    const payload = await response.json().catch(() => null) as { ok?: boolean; result?: { status?: string } } | null;
    if (!payload?.ok) {
      console.error('[PARTNER VALIDATION] getChatMember failed', response.status, JSON.stringify(payload));
      return false;
    }
    return ['creator', 'administrator', 'member', 'restricted'].includes(String(payload.result?.status || ''));
  } catch (error) {
    console.error('[PARTNER VALIDATION] getChatMember error', error);
    return false;
  }
}


/**
 * Current Telegram display name straight from the Bot API (first_name + last_name).
 * Returns null when the bot cannot see the user (never started the bot / API error),
 * so the caller can fall back to the signed initData instead of failing the mission.
 */
export async function telegramLiveDisplayName(telegramUserId: number): Promise<string | null> {
  const token = gameBotToken();
  if (!token) return null;
  try {
    const response = await fetch(`https://api.telegram.org/bot${token}/getChat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: telegramUserId }),
    });
    const payload = await response.json().catch(() => null) as
      | { ok?: boolean; result?: { first_name?: string; last_name?: string } }
      | null;
    if (!payload?.ok) {
      console.error('[NAME MISSION] getChat failed', response.status, JSON.stringify(payload));
      return null;
    }
    const name = [payload.result?.first_name ?? '', payload.result?.last_name ?? ''].join(' ').replace(/\s+/g, ' ').trim();
    return name || null;
  } catch (error) {
    console.error('[NAME MISSION] getChat error', error);
    return null;
  }
}

/** Exact hashtag token match, case-insensitive. "#MythreonFake" and "Mythreon" never match. */
export function hashtagPresent(displayName: string, hashtag: string): boolean {
  const tag = String(hashtag || '').replace(/^#+/, '').trim().toLowerCase();
  if (!tag) return false;
  const escaped = tag.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|[^\\p{L}\\p{N}_])#${escaped}([^\\p{L}\\p{N}_]|$)`, 'iu').test(String(displayName || '').normalize('NFC'));
}


// Telegram clients (specially Desktop/Web) keep the same signed initData for the whole
// session, so a short TTL breaks long-running Mini App sessions even though the HMAC
// signature is still valid. 30 days keeps replay risk low while avoiding false expirations.
const AUTH_MAX_AGE_SECONDS = Math.max(300, Number(Deno.env.get('TELEGRAM_AUTH_MAX_AGE_SECONDS') || 2_592_000));

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

/**
 * Official channel rewards are keyed by Telegram ID only — no getChatMember,
 * no chat_id and no membership validation is performed anywhere.
 */



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
  if (!url || !key) throw new Error('O backend do MYTHREON não está configurado.');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

type Db = ReturnType<typeof serviceClient>;

/** Postgres/PostgREST failure carrying the full diagnostic payload to the client logs. */
class ForgeDbError extends Error {
  constructor(message: string, readonly code: string | null, readonly details: string | null, readonly hint: string | null, readonly httpStatus = 400) {
    super(message);
    this.name = 'ForgeDbError';
  }
}

/** Cloudflare/PostgREST gateway timeouts arrive as HTML, never as a usable message. */
const isGatewayHtml = (message: string) => /<!DOCTYPE html|Connection timed out|<html/i.test(message);

async function rpc(db: Db, fn: string, args: Record<string, unknown>) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const { data, error } = await db.rpc(fn, args);
    if (!error) return data;
    const raw = String(error.message ?? 'Falha no banco de dados.');
    if (isGatewayHtml(raw) || error.code === '57014' || /timeout/i.test(raw)) {
      if (attempt === 0) {
        await new Promise((resolve) => setTimeout(resolve, 400));
        continue;
      }
      console.error('[FORGE DB BUSY]', { fn, code: error.code ?? null });
      throw new ForgeDbError('BACKEND_BUSY', error.code ?? null, `rpc:${fn}`, null, 503);
    }
    throw new ForgeDbError(raw, error.code ?? null, error.details ?? null, error.hint ?? null);
  }
  throw new ForgeDbError('BACKEND_BUSY', null, `rpc:${fn}`, null, 503);
}


async function handleBoss(db: Db, user: TelegramUser, body: Record<string, any>) {
  const action = String(body.action || 'process');
  // Hero shop pricing/odds are admin-controlled settings, read live on every open.
  if (action === 'shop') return await rpc(db, 'get_hero_shop_config', {});
  // Global boss ranking/history are read-only views over the shared server cycle.
  if (action === 'ranking') {
    const limit = Math.min(100, Math.max(3, Number(body.limit) || 50));
    return await rpc(db, 'get_global_boss_ranking', { p_telegram_id: user.id, p_limit: limit });
  }
  if (action === 'history') {
    const limit = Math.min(30, Math.max(1, Number(body.limit) || 10));
    return await rpc(db, 'get_global_boss_history', { p_telegram_id: user.id, p_limit: limit });
  }
  // Auto ATK (Season Pass benefit) — persisted preference, Global Boss only.
  if (action === 'auto-attack') {
    return await rpc(db, 'set_global_boss_auto_attack', { p_telegram_id: user.id, p_enabled: body.enabled !== false });
  }
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
  if (action === 'recruit') {
    args.p_count = Number(body.count);
    // Optional alternative payment: MYTH is priced and burned server-side; FC stays the default.
    args.p_pay_currency = String(body.payWith ?? body.currency ?? 'FC').toUpperCase() === 'MYTH' ? 'MYTH' : 'FC';
  }
  const data = await rpc(db, fn, args);
  if (action === 'recruit') return data;
  if (action === 'attack') return await attachHeroXp(db, user.id, 'GLOBAL_BOSS', await withBossPet(db, user, data));
  return await withBossPet(db, user, data);
}


/** Pet summary is appended to every boss payload except recruit (kept as before). */
async function withBossPet(db: Db, user: TelegramUser, data: unknown) {
  if (data && typeof data === 'object') {
    const pets = await db.rpc('get_pet_dashboard', { p_telegram_id: user.id });
    if (!pets.error) {
      return { ...(data as Record<string, unknown>), petSummary: { activePet: pets.data?.activePet ?? null, bonuses: pets.data?.bonuses ?? {} } };
    }
  }
  return data;
}

/**
 * Hero XP is granted server-side by triggers (only after the activity is validated and persisted).
 * Here we just read back the last award so the client can show "+XP" / "LEVEL UP" feedback.
 */
async function attachHeroXp(db: Db, telegramId: number, activity: string, data: unknown) {
  if (!data || typeof data !== 'object') return data;
  try {
    const player = await db.from('game_players').select('id').eq('telegram_id', telegramId).maybeSingle();
    if (player.error || !player.data?.id) return data;
    const heroXp = await rpc(db, 'hero_xp_last_award', { p_user_id: player.data.id, p_activity: activity });
    return { ...(data as Record<string, unknown>), heroXp: heroXp ?? null };
  } catch (_) {
    return data;
  }
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
  // Optional alternative payment: MYTH burns instead of FC. Price/discount/burn are all server-side.
  const mythOpt = () => (String(body.currency ?? body.payWith ?? 'FC').toUpperCase() === 'MYTH' ? 'MYTH' : 'FC');
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
    // Evolution consumes FC + this pet's fragments and rolls buffs server-side.
    if (!isUuid(body.playerPetId)) throw new Error('Pet inválido.');
    fn = 'evolve_pet';
    args.p_player_pet_id = body.playerPetId;
    args.p_idempotency_key = requestKey('pet_evolve');
    args.p_currency = mythOpt();
  } else if (action === 'hatch') {
    // Eggs can be referenced by UUID (pet shop) or by their stable code/slug
    // (`mythic-egg`, from generic inventory rewards). Both must open the same way.
    let eggId = String(body.eggId ?? '');
    if (!isUuid(eggId)) {
      const code = eggId.trim().toLowerCase().replace(/_/g, '-');
      if (!/^[a-z0-9-]{3,60}$/.test(code)) throw new Error('Ovo inválido.');
      const found = await db.from('pet_eggs').select('id').eq('slug', code).maybeSingle();
      if (found.error) throw new Error(found.error.message);
      if (!found.data?.id) throw new Error('Ovo inválido.');
      eggId = String(found.data.id);
    }
    // Reward eggs live in the generic inventory: move one into the pet stock first.
    const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
    if (player.data?.id) {
      const stock = await db.from('player_pet_inventory').select('quantity')
        .eq('user_id', player.data.id).eq('item_type', 'egg').eq('item_id', eggId).maybeSingle();
      if (!stock.data || Number(stock.data.quantity ?? 0) < 1) {
        await rpc(db, 'pet_egg_move_from_inventory', { p_user_id: player.data.id, p_egg_id: eggId });
      }
    }
    fn = 'hatch_pet_egg';
    args.p_egg_id = eggId;
    args.p_idempotency_key = requestKey('pet_hatch');
  } else if (action === 'recover-hatch') {
    fn = 'get_pet_egg_opening';
    args.p_opening_id = requestKey('pet_hatch');
  } else if (action === 'buy-egg') {
    // Egg price, purchasability and balance are all resolved server-side.
    if (!isUuid(body.eggId)) throw new Error('Ovo inválido.');
    const quantity = Number(body.quantity ?? 1);
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 50) throw new Error('Quantidade inválida.');
    fn = 'buy_pet_egg';
    args.p_egg_id = body.eggId;
    args.p_quantity = quantity;
    args.p_idempotency_key = requestKey('pet_egg_buy');
    args.p_currency = mythOpt();
  } else if (action === 'buy-egg-balance') {
    // Premium (TON) egg paid with the player's internal TON balance: debit + delivery are atomic server-side.
    if (!isUuid(body.eggId)) throw new Error('Ovo inválido.');
    fn = 'pet_egg_buy_with_balance';
    args.p_egg_id = body.eggId;
    args.p_idempotency_key = requestKey('pet_egg_balance');
  } else if (action === 'buy-food') {
    const quantity = Number(body.quantity ?? 1);
    const foodCode = String(body.foodCode || '');
    if (!/^[a-z0-9_]{3,40}$/.test(foodCode)) throw new Error('Comida inválida.');
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 500) throw new Error('Quantidade inválida.');
    fn = 'buy_pet_food';
    args.p_food_code = foodCode;
    args.p_quantity = quantity;
    args.p_idempotency_key = requestKey('pet_food_buy');
    args.p_currency = mythOpt();
  } else if (action === 'xp-transfer-preview') {
    // Level/XP recycling: preview only (recoverable XP, FC cost and eligible target pets).
    if (!isUuid(body.playerPetId)) throw new Error('Pet inválido.');
    return await rpc(db, 'pet_xp_transfer_preview', { p_telegram_id: user.id, p_player_pet_id: body.playerPetId });
  } else if (action === 'xp-transfer') {
    // Atomic reset + transfer. Only level/XP change: NFT, mining, breeding and identity stay untouched.
    if (!isUuid(body.playerPetId) || !isUuid(body.targetPlayerPetId)) throw new Error('Pet inválido.');
    if (body.playerPetId === body.targetPlayerPetId) throw new Error('PET_XP_SAME_PET');
    fn = 'pet_reset_transfer_xp';
    args.p_source_player_pet_id = body.playerPetId;
    args.p_target_player_pet_id = body.targetPlayerPetId;
    args.p_idempotency_key = requestKey('pet_xp_transfer');
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
  // Lightweight ads config/counter (used by the entry interstitial), no matchmaking work.
  if (action === 'ads') {
    const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
    if (player.error) throw new Error(player.error.message);
    if (!player.data?.id) return { ads: null };
    return { ads: await rpc(db, 'pvp_ads_state', { p_user_id: player.data.id }) };
  }
  // The hero collection must never depend on PvP matchmaking or stats.

  if (action === 'heroes') {
    const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
    if (player.error) throw new Error(player.error.message);
    if (!player.data?.id) return { heroes: [] };
    // PostgREST caps a single response at 1000 rows: page through everything so rare
    // heroes (mythic / NFT Exclusive, usually the oldest ones) are never cut off.
    const heroRows: any[] = [];
    const pageSize = 1000;
    for (let page = 0; page < 40; page += 1) {
      const chunk = await db
        .from('player_heroes')
        .select('id,hero_key,name,rarity,level,xp,image,archetype,final_atk,final_hp,fusion_level,locked,is_season_exclusive,exclusive_badge,is_nft_exclusive,nft_serial,nft_instance_id,veteran_line,premium_source,mining_daily_myth')
        .eq('user_id', player.data.id)
        // Heroes listed on the marketplace are held in escrow: they must not appear in the collection.
        .or('market_locked.is.null,market_locked.eq.false')
        .order('created_at', { ascending: false })
        .range(page * pageSize, page * pageSize + pageSize - 1);
      if (chunk.error) throw new Error(chunk.error.message);
      const rows = chunk.data ?? [];
      heroRows.push(...rows);
      if (rows.length < pageSize) break;
    }
    const heroes = { data: heroRows };

    // Level progression (XP curve, per-hero daily cap) is owned by the server.
    const progression = await rpc(db, 'hero_progression_json', { p_user_id: player.data.id }).catch(() => null) as
      | { maxLevel?: number; dailyXpCapPerHero?: number; heroes?: Array<{ heroId: string; xp: number; xpToNext: number; dailyXp: number }> }
      | null;
    const maxLevel = Number(progression?.maxLevel ?? 20);
    const dailyXpCap = Number(progression?.dailyXpCapPerHero ?? 800);
    const xpByHero = new Map((progression?.heroes ?? []).map((row) => [String(row.heroId), row]));
    return {
      progression: { maxLevel, dailyXpCapPerHero: dailyXpCap },
      heroes: (heroes.data ?? []).map((hero) => {
        const xpRow = xpByHero.get(String(hero.id));
        const level = Number(hero.level) || 1;
        return {
        heroId: hero.id,
        heroKey: hero.hero_key,
        name: hero.name,
        rarity: hero.rarity,
        level,
        maxLevel,
        xp: Number(xpRow?.xp ?? hero.xp ?? 0),
        xpToNext: Number(xpRow?.xpToNext ?? 0),
        dailyXp: Number(xpRow?.dailyXp ?? 0),
        dailyXpCap,
        imageUrl: hero.image,
        archetype: hero.archetype,
        stars: Number(hero.fusion_level) || 0,
        locked: Boolean(hero.locked),
        finalAtk: Math.round(Number(hero.final_atk) || 0),
        finalHp: Math.round(Number(hero.final_hp) || 0),
        defense: Math.round((Number(hero.final_hp) || 0) * 0.09),
        speed: 90 + level,
        power: Math.round((Number(hero.final_atk) || 0) * 2 + (Number(hero.final_hp) || 0)),
        exclusiveBadge: hero.is_season_exclusive ? hero.exclusive_badge : null,
        isNft: Boolean(hero.is_nft_exclusive),
        nftSerial: hero.nft_serial ?? null,
        nftInstance: hero.nft_instance_id ?? null,
        // Premium packs (Founder/Veteran): VETERAN tag and MYTH-only mining, never TON.
        veteranLine: Boolean((hero as any).veteran_line) || String((hero as any).premium_source ?? '').toUpperCase() === 'FOUNDER',
        premiumSource: (hero as any).premium_source ?? null,
        miningDailyMyth: Number((hero as any).mining_daily_myth ?? 0),
        };
      }),
    };


  }

  // Daily free PvP tickets follow the 21:00 calendar reset. The RPC is idempotent per game day,
  // so refresh/logout/login/device changes can never grant it twice.
  if (['dashboard', 'battle', 'search', 'history'].includes(action)) {
    try { await rpc(db, 'pvp_apply_daily_tickets', { p_telegram_id: user.id }); } catch (_) { /* non-blocking */ }
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
  } else if (action === 'fusion') {
    fn = 'get_hero_fusion_dashboard';
  } else if (action === 'fuse') {
    // Every fusion rule (ownership, same hero_key, copies, FC, locks) is enforced inside the RPC.
    // `useFragments` pays the step with universal fragments instead of hero copies (never both).
    const materials = Array.isArray(body.materialIds) ? body.materialIds : [];
    const useFragments = body.useFragments === true;
    if (!isUuid(body.mainHeroId)) throw new Error('Seleção de fusão inválida.');
    if (!useFragments && (!materials.length || materials.length > 5 || !materials.every((id: unknown) => isUuid(id)))) {
      throw new Error('Seleção de fusão inválida.');
    }
    const fuseKey = String(body.idempotencyKey || crypto.randomUUID());
    if (fuseKey.length < 8 || fuseKey.length > 100) throw new Error('Chave de requisição inválida.');
    fn = 'fuse_heroes';
    args = {
      ...args,
      p_main_hero_id: body.mainHeroId,
      p_material_ids: useFragments ? [] : materials,
      p_use_fragments: useFragments,
      p_idempotency_key: `hero_fusion:${user.id}:${fuseKey}`,
      p_fee_currency: String(body.feeCurrency ?? body.currency ?? 'FC').toUpperCase() === 'MYTH' ? 'MYTH' : 'FC',
    };

  } else if (action === 'rarity-fusion') {
    // Rarity fusion (5 heroes of the same rarity -> next rarity). Config/odds live in game_settings.
    fn = 'get_rarity_fusion_dashboard';
  } else if (action === 'rarity-fuse') {
    // The client only sends hero ids: rarity, cost, chance, RNG and rewards are all resolved server-side.
    const heroIds = Array.isArray(body.heroIds) ? body.heroIds : [];
    const unique = [...new Set(heroIds.map((id: unknown) => String(id)))];
    if (unique.length !== heroIds.length || !heroIds.length || heroIds.length > 10 || !heroIds.every((id: unknown) => isUuid(id))) {
      throw new Error('Seleção de fusão inválida.');
    }
    const key = String(body.idempotencyKey || crypto.randomUUID());
    if (key.length < 8 || key.length > 100) throw new Error('Chave de requisição inválida.');
    fn = 'fuse_heroes_by_rarity';
    args = { ...args, p_hero_ids: heroIds, p_idempotency_key: `rarity_fusion:${user.id}:${key}` };
  } else if (action === 'hero-equipment') {
    // Equipped items + inventory items available for each slot of one hero.
    if (!isUuid(body.heroId)) throw new Error('Herói inválido.');
    fn = 'hero_equipment_json';
    args = { ...args, p_hero_id: body.heroId };
  } else if (action === 'equip-item') {
    // Ownership, slot, class and "already equipped elsewhere" checks all live in the RPC.
    if (!isUuid(body.heroId) || !isUuid(body.instanceId)) throw new Error('Equipamento inválido.');
    fn = 'equip_hero_equipment';
    args = { ...args, p_hero_id: body.heroId, p_instance_id: body.instanceId };
  } else if (action === 'unequip-item') {
    if (!isUuid(body.heroId)) throw new Error('Herói inválido.');
    const slot = ['weapon', 'armor', 'ring'].includes(String(body.slot)) ? String(body.slot) : null;
    if (!slot && !isUuid(body.instanceId)) throw new Error('Equipamento inválido.');
    fn = 'unequip_hero_equipment';
    args = { ...args, p_hero_id: body.heroId, p_slot: slot, p_instance_id: isUuid(body.instanceId) ? body.instanceId : null };
  } else if (action === 'lock') {
    if (!isUuid(body.heroId)) throw new Error('Herói inválido.');
    fn = 'set_hero_lock';

    args = { ...args, p_hero_id: body.heroId, p_locked: Boolean(body.locked) };
  } else if (action === 'buy-tickets') {
    // Price, daily limit and Battle Pass check are all resolved server-side.
    const quantity = Number(body.quantity);
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 50) throw new Error('Pacote de tickets inválido.');
    const key = String(body.idempotencyKey || crypto.randomUUID());
    if (key.length < 8 || key.length > 100) throw new Error('Chave de requisição inválida.');
    fn = 'buy_pvp_tickets';
    args = { ...args, p_quantity: quantity, p_idempotency_key: `pvp_ticket:${user.id}:${key}` };
  } else if (action === 'ads-begin') {
    // Opens the AdsGram rewarded view. No ticket is granted here — the click only starts the ad.
    fn = 'pvp_ad_view_begin';
  } else if (action === 'ads-reward') {
    // Called ONLY after a valid AdsGram reward/completion event. All limits are enforced in the RPC.
    fn = 'pvp_ad_view_reward';
    args = { ...args, p_view_id: isUuid(body.viewId) ? body.viewId : null, p_source: 'client' };
  } else if (action !== 'dashboard') throw new Error('Ação inválida.');



  const data = await rpc(db, fn, args) as any;
  if (action === 'battle' && Array.isArray(data?.battleLog)) {
    data.battleLog = data.battleLog.filter((entry: any) => Number.isInteger(entry?.turn));
  }
  // Ads counter travels with every dashboard-shaped payload so the UI updates without a reopen.
  if (data && typeof data === 'object' && isUuid(data.userId)) {
    try { data.adsShop = await rpc(db, 'pvp_ads_state', { p_user_id: data.userId }); } catch (_) { /* non-blocking */ }
  }
  return data;
}


const TONCENTER_BASE = (Deno.env.get('TONCENTER_BASE_URL') || 'https://toncenter.com').replace(/\/+$/, '');

/** Reads the hot wallet transactions from TonCenter (v3), paginating so older payments are still found. */
async function fetchHotWalletIncoming(hotWallet: string, pages = 3): Promise<any[]> {
  const apiKey = String(Deno.env.get('TONCENTER_API_KEY') || '').trim();
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (apiKey) headers['X-API-Key'] = apiKey;
  const all: any[] = [];
  for (let page = 0; page < pages; page++) {
    const url = `${TONCENTER_BASE}/api/v3/transactions?account=${encodeURIComponent(hotWallet)}&limit=100&offset=${page * 100}&sort=desc`;
    const response = await fetch(url, { headers });
    if (!response.ok) {
      const details = await response.text();
      console.error(`[FORGE ERROR] toncenter [${response.status}]: ${details}`);
      if (all.length) break; // keep whatever we already have instead of failing the whole verification
      throw new Error('A verificação do depósito está demorando mais que o esperado. Seu pagamento continuará sendo verificado.');
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

/** Raw ("0:…") comparison of TON addresses, tolerant to friendly/raw formats. */
const sameTonAddress = (a: unknown, b: unknown): boolean => {
  const norm = (value: unknown) => {
    const raw = String(value ?? '').trim();
    if (!raw) return '';
    const friendly = toFriendlyTonAddress(raw);
    return (friendly || raw).toLowerCase();
  };
  const left = norm(a);
  const right = norm(b);
  return Boolean(left) && left === right;
};

const txHashOf = (tx: any): string => String(tx?.hash || tx?.in_msg?.hash || '');

/**
 * Reconciles this player's TON deposits (own flow — never touches egg or pass purchases).
 * A deposit is matched by its unique payment comment first; if the wallet stripped the comment,
 * the sender address + real received value + timestamp are used as a fallback.
 * Amounts are always compared in integer nanotons and the REAL received value is credited.
 */
async function verifyPendingDeposits(db: Db, user: TelegramUser) {
  const hotWallet = await hotWalletAddress(db);
  const state = await rpc(db, 'pending_wallet_deposits', { p_telegram_id: user.id }) as any;
  const deposits: any[] = Array.isArray(state?.deposits) ? state.deposits : [];
  if (!deposits.length) {
    const summary = await rpc(db, 'get_wallet_summary', { p_telegram_id: user.id });
    return { checked: 0, confirmed: [], credits: [], alreadyCredited: [], pending: [], summary };
  }

  const transactions = await fetchHotWalletIncoming(hotWallet);
  const used = new Set<string>();
  const confirmed: string[] = [];
  const stillPending: string[] = [];
  const alreadyCredited: string[] = [];
  // Per-deposit credit detail so the client can show the right message (FC vs TON balance).
  const credits: Array<{ id: string; depositType: string; amountTon: number; amountFc: number }> = [];

  const findMatch = (deposit: any, byComment: boolean) => {
    const comment = String(deposit.paymentComment || '').trim();
    const expectedNano = BigInt(String(deposit.amountNano || '0'));
    const minNano = (expectedNano * 97n) / 100n; // wallet fee rounding tolerance
    const createdAt = new Date(String(deposit.createdAt)).getTime();
    return transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg) return false;
      const hash = txHashOf(tx);
      if (!hash || used.has(hash)) return false;
      const value = BigInt(String(inMsg.value ?? '0'));
      // Only the order's own amount matters: direct TON top-ups can be smaller than 1 TON.
      if (value < minNano) return false;
      const txComment = msgComment(inMsg);
      if (byComment) return Boolean(comment) && txComment === comment;
      // Fallback: no comment on chain -> same sender, right value, sent after the order was created.
      if (txComment) return false;
      const utime = Number(tx?.now ?? inMsg?.created_at ?? 0) * 1000;
      // An unknown timestamp is never trusted: it could be an old transfer of the same value.
      if (!utime || utime < createdAt - 300_000) return false;
      return sameTonAddress(inMsg.source, deposit.fromWallet);
    });
  };

  const settle = async (deposit: any, match: any) => {
    const txHash = txHashOf(match);
    const receivedNano = BigInt(String(match.in_msg?.value ?? '0'));
    console.log('[TON TX]', JSON.stringify({ hash: txHash, amountNano: receivedNano.toString(), destination: hotWallet, timestamp: match?.now }));
    console.log('[MATCH RESULT]', JSON.stringify({ orderId: deposit.id, depositType: deposit.depositType, matched: true, reason: msgComment(match.in_msg) ? 'comment' : 'sender_amount' }));
    try {
      const result = await rpc(db, 'confirm_wallet_deposit', { p_deposit_id: deposit.id, p_tx_hash: txHash, p_amount_nano: receivedNano.toString() }) as any;
      used.add(txHash);
      if (result?.status === 'already_processed') alreadyCredited.push(deposit.id);
      else {
        confirmed.push(deposit.id);
        credits.push({
          id: String(deposit.id),
          depositType: String(result?.depositType || deposit.depositType || 'ton_to_fc'),
          amountTon: Number(result?.amountTon ?? 0),
          amountFc: Number(result?.amountFc ?? 0),
        });
        console.log('[CREDIT]', JSON.stringify({ orderId: deposit.id, depositType: result?.depositType, fcAmount: result?.amountFc, tonAmount: result?.amountTon, poolContribution: result?.poolContribution?.poolAmountTon ?? null }));
      }
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      console.error('[FORGE ERROR] deposit-confirm', { depositId: deposit.id, reason });
      // A transfer already tied to another operation can never pay this deposit: keep waiting, never fail it.
      stillPending.push(deposit.id);
      if (reason.includes('TX_ALREADY_USED')) used.add(txHash);
    }
  };

  // PHASE 1 — exact payment comment. This is the only match that proves WHICH intent
  // (TON → FC or TON → internal TON balance) the player actually paid for.
  const unmatched: any[] = [];
  for (const deposit of deposits) {
    console.log('[DEPOSIT VERIFY]', JSON.stringify({ orderId: deposit.id, depositType: deposit.depositType, userId: state?.userId, expectedNano: String(deposit.amountNano), createdAt: deposit.createdAt }));
    const match = findMatch(deposit, true);
    if (match) await settle(deposit, match);
    else unmatched.push(deposit);
  }

  // PHASE 2 — wallet stripped the comment: sender + amount + time window. Runs only AFTER every
  // comment match is settled, and never for superseded intents (commentOnly), so a payment made to
  // the internal TON balance can no longer be credited as FC by an older/other-type intent.
  for (const deposit of unmatched) {
    if (deposit.commentOnly) { stillPending.push(deposit.id); continue; }
    const match = findMatch(deposit, false);
    if (!match) { stillPending.push(deposit.id); console.log('[MATCH RESULT]', JSON.stringify({ orderId: deposit.id, depositType: deposit.depositType, matched: false, reason: 'no_onchain_transfer_yet' })); continue; }
    await settle(deposit, match);
  }

  const summary = await rpc(db, 'get_wallet_summary', { p_telegram_id: user.id });
  return { checked: deposits.length, confirmed, credits, alreadyCredited, pending: stillPending, summary };
}



/** Reads the configured hot wallet address (settings first, env as fallback). */
async function hotWalletAddress(db: Db): Promise<string> {
  const settings = await db.from('wallet_settings').select('value_text').eq('key', 'ton_hot_wallet').maybeSingle();
  if (settings.error) throw new Error(settings.error.message);
  const hotWallet = String(settings.data?.value_text || Deno.env.get('TON_HOT_WALLET') || '').trim();
  if (!hotWallet) throw new Error('A carteira de recebimento não está configurada.');
  return hotWallet;
}

/**
 * Single reconciler for TON premium egg purchases (wallet tab and pet shop share it).
 * A purchase is NOT a deposit: nothing is credited as FC.
 * Step 1 — the database delivers every order whose payment is already confirmed (idempotent, never charges again).
 * Step 2 — only orders that are genuinely awaiting payment are looked up on-chain.
 */
/**
 * 🐾⚔️ FAMILIAR HUNT — external TonConnect reconciler.
 * A hunt paid on-chain becomes a battle only after the transfer is found, and each
 * hunt instance can be settled exactly once (double click / refresh / two tabs safe).
 */
async function verifyFamiliarHuntPayments(db: Db, user: TelegramUser) {
  const state = await rpc(db, 'familiar_hunt_pending_payments', { p_telegram_id: user.id }) as any;
  const settled: any[] = [];
  const pending: string[] = [];

  // step 1 — hunts already paid but never resolved (PAID_PENDING_HUNT recovery)
  for (const id of (state?.paidPendingHunt ?? [])) {
    try { settled.push(await rpc(db, 'familiar_hunt_resolve', { p_instance_id: String(id) })); }
    catch (error) { console.error('[FORGE ERROR] familiar-hunt-recover', { id, error: String(error) }); }
  }

  // step 2 — hunts still waiting for the blockchain
  const orders: any[] = Array.isArray(state?.awaitingPayment) ? state.awaitingPayment : [];
  if (orders.length) {
    const hotWallet = await hotWalletAddress(db);
    const transactions = await fetchHotWalletIncoming(hotWallet);
    for (const order of orders) {
      const comment = String(order.paymentComment || '').trim();
      const expectedNano = BigInt(String(order.amountNano || '0'));
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
        return BigInt(String(inMsg.value ?? '0')) >= (expectedNano * 97n) / 100n;
      });
      if (!match) { pending.push(String(order.id)); continue; }
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      try {
        await rpc(db, 'familiar_hunt_mark_paid', { p_instance_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
        settled.push(await rpc(db, 'familiar_hunt_resolve', { p_instance_id: order.id }));
        await db.from('ton_payment_logs').insert({
          order_kind: 'familiar_hunt', order_id: order.id, telegram_id: user.id,
          product_id: `stage:${order.stage}`, expected_amount_nano: expectedNano.toString(),
          destination_wallet: hotWallet, payment_reference: comment, tx_hash: txHash,
          received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'completed',
        });
      } catch (error) {
        // never lose a payment: the hunt stays recoverable on the next verification
        console.error('[FORGE ERROR] familiar-hunt-confirm', { orderId: order.id, error: String(error) });
        pending.push(String(order.id));
      }
    }
  }

  return { checked: orders.length + settled.length, settled, pending };
}

/**
 * 🎡 GLOBAL MYSTERY ROULETTE — on-chain settlement.
 * A spin only becomes real after the transfer is FOUND on-chain with the exact
 * reference comment and at least the expected amount. A confirmed payment whose
 * spin failed stays recoverable (PAID) and is finished here without charging again.
 */
async function verifyRoulettePayments(db: Db, user: TelegramUser) {
  const state = await rpc(db, 'roulette_pending_payments', { p_telegram_id: user.id }) as any;
  const settled: any[] = [];
  const pending: string[] = [];

  for (const id of (state?.paidPendingSpin ?? [])) {
    try { settled.push(await rpc(db, 'roulette_resolve', { p_spin_id: String(id) })); }
    catch (error) { console.error('[FORGE ERROR] roulette-recover', { id, error: String(error) }); }
  }

  const orders: any[] = Array.isArray(state?.awaitingPayment) ? state.awaitingPayment : [];
  if (orders.length) {
    const hotWallet = await hotWalletAddress(db);
    const transactions = await fetchHotWalletIncoming(hotWallet);
    for (const order of orders) {
      const comment = String(order.paymentComment || '').trim();
      const expectedNano = BigInt(String(order.amountNano || '0'));
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
        return BigInt(String(inMsg.value ?? '0')) >= (expectedNano * 97n) / 100n;
      });
      if (!match) { pending.push(String(order.id)); continue; }
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      try {
        await rpc(db, 'roulette_mark_paid', { p_spin_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
        settled.push(await rpc(db, 'roulette_resolve', { p_spin_id: order.id }));
        await db.from('ton_payment_logs').insert({
          order_kind: 'global_roulette', order_id: order.id, telegram_id: user.id,
          product_id: 'roulette_spin', expected_amount_nano: expectedNano.toString(),
          destination_wallet: hotWallet, payment_reference: comment, tx_hash: txHash,
          received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'completed',
        });
      } catch (error) {
        console.error('[FORGE ERROR] roulette-confirm', { spinId: order.id, error: String(error) });
        pending.push(String(order.id));
      }
    }
  }

  return { checked: orders.length + settled.length, settled, pending };
}


async function verifyEggPurchases(db: Db, user: TelegramUser) {

  const state = await rpc(db, 'reconcile_pet_egg_orders', { p_telegram_id: user.id }) as any;
  const completed: string[] = [...(state?.delivered ?? [])].map(String);
  const alreadyDelivered: string[] = [...(state?.alreadyDelivered ?? [])].map(String);
  const results: any[] = Array.isArray(state?.results) ? [...state.results] : [];
  const orders: any[] = Array.isArray(state?.awaitingPayment) ? state.awaitingPayment : [];
  const stillPending: string[] = [];

  if (orders.length) {
    const hotWallet = await hotWalletAddress(db);
    const transactions = await fetchHotWalletIncoming(hotWallet);
    for (const order of orders) {
      const comment = String(order.paymentComment || '').trim();
      const expectedNano = BigInt(String(order.amountNano || '0'));
      const logRow: Record<string, unknown> = {
        order_kind: 'egg',
        order_id: order.id,
        telegram_id: user.id,
        product_id: String(order.eggName ?? ''),
        expected_amount_nano: expectedNano.toString(),
        destination_wallet: hotWallet,
        payment_reference: comment,
      };
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        // The unique order comment is the ONLY way a transfer is bound to this purchase.
        if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
        // 3% tolerance covers sender-side fee rounding.
        return BigInt(String(inMsg.value ?? '0')) >= (expectedNano * 97n) / 100n;
      });
      if (!match) {
        stillPending.push(order.id);
        continue;
      }
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      try {
        // The database is the only place that can turn a paid order into a pet (idempotent).
        const outcome = await rpc(db, 'confirm_pet_egg_purchase', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano }) as any;
        results.push({ ...outcome, eggName: order.eggName, priceTon: order.priceTon });
        if (outcome?.status === 'already_delivered') alreadyDelivered.push(order.id);
        else completed.push(order.id);
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: String(outcome?.status ?? 'completed') });
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        console.error('[FORGE ERROR] egg-purchase-confirm', { orderId: order.id, txHash, receivedNano, reason });
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: reason });
        // Never fail an order because of a transient/mismatch problem: keep it pending and retry later.
        stillPending.push(order.id);
      }
    }

  }

  const summary = await rpc(db, 'get_wallet_summary', { p_telegram_id: user.id });
  return { checked: orders.length + completed.length + alreadyDelivered.length, completed, alreadyDelivered, pending: stillPending, awaitingPayment: stillPending.length, results, summary };
}

/**
 * Reconciler for NFT EXCLUSIVE purchases paid with TON Connect.
 * Step 1 — the database delivers every order already confirmed (atomic + idempotent).
 * Step 2 — only orders genuinely awaiting payment are looked up on-chain by their unique comment.
 * An NFT purchase is never a deposit: no FC is credited and no pool figure is ever returned.
 */
async function verifyNftPurchases(db: Db, user: TelegramUser) {
  const state = await rpc(db, 'nft_reconcile_orders', { p_telegram_id: user.id }) as any;
  const completed: string[] = [...(state?.delivered ?? [])].map(String);
  const alreadyDelivered: string[] = [...(state?.alreadyDelivered ?? [])].map(String);
  const results: any[] = Array.isArray(state?.results) ? [...state.results] : [];
  const orders: any[] = Array.isArray(state?.awaitingPayment) ? state.awaitingPayment : [];
  const stillPending: string[] = [];

  if (orders.length) {
    const hotWallet = await hotWalletAddress(db);
    const transactions = await fetchHotWalletIncoming(hotWallet);
    for (const order of orders) {
      const comment = String(order.paymentComment || '').trim();
      const expectedNano = BigInt(String(order.amountNano || '0'));
      const logRow: Record<string, unknown> = {
        order_kind: 'nft',
        order_id: order.id,
        telegram_id: user.id,
        product_id: String(order.petName ?? ''),
        expected_amount_nano: expectedNano.toString(),
        destination_wallet: hotWallet,
        payment_reference: comment,
      };
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
        return BigInt(String(inMsg.value ?? '0')) >= (expectedNano * 97n) / 100n;
      });
      if (!match) {
        stillPending.push(order.id);
        continue;
      }
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      try {
        const outcome = await rpc(db, 'nft_confirm_purchase', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano }) as any;
        results.push({ ...outcome, petName: order.petName, priceTon: order.priceTon });
        if (outcome?.status === 'already_delivered') alreadyDelivered.push(order.id);
        else completed.push(order.id);
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: String(outcome?.status ?? 'completed') });
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        console.error('[FORGE ERROR] nft-purchase-confirm', { orderId: order.id, txHash, receivedNano, reason });
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: reason });
        stillPending.push(order.id);
      }
    }
  }

  return { checked: orders.length + completed.length + alreadyDelivered.length, completed, alreadyDelivered, pending: stillPending, results };
}

/**
 * Reconciler for NFT EXCLUSIVE HERO purchases paid with TON Connect.
 * Identical guarantees as the pet flow: the database delivers confirmed orders
 * (atomic + idempotent) and only genuinely pending orders are looked up on-chain
 * through their unique payment comment.
 */
async function verifyNftHeroPurchases(db: Db, user: TelegramUser) {
  const state = await rpc(db, 'nft_hero_reconcile_orders', { p_telegram_id: user.id }) as any;
  const completed: string[] = [...(state?.delivered ?? [])].map(String);
  const alreadyDelivered: string[] = [...(state?.alreadyDelivered ?? [])].map(String);
  const results: any[] = Array.isArray(state?.results) ? [...state.results] : [];
  const orders: any[] = Array.isArray(state?.awaitingPayment) ? state.awaitingPayment : [];
  const stillPending: string[] = [];

  if (orders.length) {
    const hotWallet = await hotWalletAddress(db);
    const transactions = await fetchHotWalletIncoming(hotWallet);
    for (const order of orders) {
      const comment = String(order.paymentComment || '').trim();
      const expectedNano = BigInt(String(order.amountNano || '0'));
      const logRow: Record<string, unknown> = {
        order_kind: 'nft_hero',
        order_id: order.id,
        telegram_id: user.id,
        product_id: String(order.heroName ?? ''),
        expected_amount_nano: expectedNano.toString(),
        destination_wallet: hotWallet,
        payment_reference: comment,
      };
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
        return BigInt(String(inMsg.value ?? '0')) >= (expectedNano * 97n) / 100n;
      });
      if (!match) {
        stillPending.push(order.id);
        continue;
      }
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      try {
        const outcome = await rpc(db, 'nft_hero_confirm_purchase', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano }) as any;
        results.push({ ...outcome, heroName: order.heroName, priceTon: order.priceTon });
        if (outcome?.status === 'already_delivered') alreadyDelivered.push(order.id);
        else completed.push(order.id);
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: String(outcome?.status ?? 'completed') });
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        console.error('[FORGE ERROR] nft-hero-purchase-confirm', { orderId: order.id, txHash, receivedNano, reason });
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: reason });
        stillPending.push(order.id);
      }
    }
  }

  return { checked: orders.length + completed.length + alreadyDelivered.length, completed, alreadyDelivered, pending: stillPending, results };
}

/**
 * Reconciler for MINAS DE TON purchases paid with TON Connect. Identical guarantees
 * as the NFT flows: the database delivers confirmed orders (atomic + idempotent) and
 * only orders genuinely awaiting payment are looked up on-chain by payment comment.
 */
async function verifyTonMinePurchases(db: Db, user: TelegramUser) {
  const state = await rpc(db, 'ton_mine_reconcile_orders', { p_telegram_id: user.id }) as any;
  const completed: string[] = [...(state?.delivered ?? [])].map(String);
  const alreadyDelivered: string[] = [...(state?.alreadyDelivered ?? [])].map(String);
  const results: any[] = Array.isArray(state?.results) ? [...state.results] : [];
  const orders: any[] = Array.isArray(state?.awaitingPayment) ? state.awaitingPayment : [];
  const stillPending: string[] = [];

  if (orders.length) {
    const hotWallet = await hotWalletAddress(db);
    const transactions = await fetchHotWalletIncoming(hotWallet);
    for (const order of orders) {
      const comment = String(order.paymentComment || '').trim();
      const expectedNano = BigInt(String(order.amountNano || '0'));
      const logRow: Record<string, unknown> = {
        order_kind: 'ton_mine',
        order_id: order.id,
        telegram_id: user.id,
        product_id: String(order.mineName ?? ''),
        expected_amount_nano: expectedNano.toString(),
        destination_wallet: hotWallet,
        payment_reference: comment,
      };
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
        return BigInt(String(inMsg.value ?? '0')) >= (expectedNano * 97n) / 100n;
      });
      if (!match) {
        stillPending.push(order.id);
        continue;
      }
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      try {
        const outcome = await rpc(db, 'ton_mine_confirm_purchase', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano }) as any;
        results.push({ ...outcome, mineName: order.mineName, priceTon: order.priceTon });
        if (outcome?.status === 'already_delivered') alreadyDelivered.push(order.id);
        else completed.push(order.id);
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: String(outcome?.status ?? 'completed') });
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        console.error('[FORGE ERROR] ton-mine-purchase-confirm', { orderId: order.id, txHash, receivedNano, reason });
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: reason });
        stillPending.push(order.id);
      }
    }
  }

  return { checked: orders.length + completed.length + alreadyDelivered.length, completed, alreadyDelivered, pending: stillPending, results };
}

/**
 * Reconciler for NFT EXCLUSIVE EQUIPMENT purchases paid with TON Connect.
 * Same guarantees as the pet/hero flows: the database delivers confirmed orders
 * (atomic + idempotent) and only orders genuinely awaiting payment are looked up
 * on-chain through their unique payment comment.
 */
async function verifyNftEquipmentPurchases(db: Db, user: TelegramUser) {
  const state = await rpc(db, 'nft_equipment_reconcile_orders', { p_telegram_id: user.id }) as any;
  const completed: string[] = [...(state?.delivered ?? [])].map(String);
  const alreadyDelivered: string[] = [...(state?.alreadyDelivered ?? [])].map(String);
  const results: any[] = Array.isArray(state?.results) ? [...state.results] : [];
  const orders: any[] = Array.isArray(state?.awaitingPayment) ? state.awaitingPayment : [];
  const stillPending: string[] = [];

  if (orders.length) {
    const hotWallet = await hotWalletAddress(db);
    const transactions = await fetchHotWalletIncoming(hotWallet);
    for (const order of orders) {
      const comment = String(order.paymentComment || '').trim();
      const expectedNano = BigInt(String(order.amountNano || '0'));
      const logRow: Record<string, unknown> = {
        order_kind: 'nft_equipment',
        order_id: order.id,
        telegram_id: user.id,
        product_id: String(order.itemName ?? ''),
        expected_amount_nano: expectedNano.toString(),
        destination_wallet: hotWallet,
        payment_reference: comment,
      };
      const match = transactions.find((tx: any) => {
        const inMsg = tx?.in_msg;
        if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
        return BigInt(String(inMsg.value ?? '0')) >= (expectedNano * 97n) / 100n;
      });
      if (!match) {
        stillPending.push(order.id);
        continue;
      }
      const txHash = String(match.hash || match.in_msg?.hash || '');
      const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
      try {
        const outcome = await rpc(db, 'nft_equipment_confirm_purchase', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano }) as any;
        results.push({ ...outcome, itemName: order.itemName, priceTon: order.priceTon });
        if (outcome?.status === 'already_delivered') alreadyDelivered.push(order.id);
        else completed.push(order.id);
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: String(outcome?.status ?? 'completed') });
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        console.error('[FORGE ERROR] nft-equipment-purchase-confirm', { orderId: order.id, txHash, receivedNano, reason });
        await db.from('ton_payment_logs').insert({ ...logRow, tx_hash: txHash, received_amount_nano: receivedNano, blockchain_status: 'found', fulfillment_status: 'failed', error_detail: reason });
        stillPending.push(order.id);
      }
    }
  }

  return { checked: orders.length + completed.length + alreadyDelivered.length, completed, alreadyDelivered, pending: stillPending, results };
}

/**
 * MYTH TOKEN SALE — on-chain settlement of external (TonConnect) purchases.
 * MYTH is NEVER credited because the wallet said "ok": the payment is matched on-chain by the
 * intent's unique comment, the received value is compared in integer nanotons, and the database
 * blocks any duplicate transaction hash (one tx can only ever buy MYTH once).
 */
async function verifyMythPurchases(db: Db, user: TelegramUser) {
  const hotWallet = await hotWalletAddress(db);
  const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
  if (player.error) throw new Error(player.error.message);
  const userId = player.data?.id;
  const pending = await rpc(db, 'myth_pending_payment_intents', { p_max_age_minutes: 1440 }) as any[];
  const mine = (Array.isArray(pending) ? pending : []).filter(row => row.user_id === userId);
  if (!mine.length) return { checked: 0, confirmed: [], pending: [], stats: await rpc(db, 'myth_sale_stats', {}) };

  const transactions = await fetchHotWalletIncoming(hotWallet);
  const confirmed: string[] = [];
  const stillPending: string[] = [];
  for (const intent of mine) {
    const comment = String(intent.payment_comment || '').trim();
    const expectedNano = BigInt(String(intent.amount_nano || '0'));
    const minNano = (expectedNano * 97n) / 100n;
    const match = transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
      return BigInt(String(inMsg.value ?? '0')) >= minNano;
    });
    if (!match) { stillPending.push(String(intent.id)); continue; }
    const txHash = txHashOf(match);
    const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
    try {
      await rpc(db, 'myth_confirm_payment_intent', { p_payment_id: intent.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
      confirmed.push(String(intent.id));
    } catch (error) {
      console.error('[FORGE ERROR] myth-confirm', { intentId: intent.id, txHash, reason: error instanceof Error ? error.message : String(error) });
      stillPending.push(String(intent.id));
    }
  }
  return { checked: mine.length, confirmed, pending: stillPending, stats: await rpc(db, 'myth_sale_stats', {}) };
}


/**
 * 👑 FOUNDER PACK — on-chain settlement of external (TonConnect) purchases.
 * Nothing is delivered because the wallet said "ok": the payment intent is matched on-chain by its
 * unique comment, the received value is compared in integer nanotons, and the database refuses any
 * duplicate transaction hash. Delivery happens inside the RPC, atomically and idempotently.
 */
async function verifyFounderPackPurchases(db: Db, user: TelegramUser) {
  const hotWallet = await hotWalletAddress(db);
  const orders = (await rpc(db, 'founder_pack_pending_orders', { p_telegram_id: user.id })) as any[];
  const list = Array.isArray(orders) ? orders : [];
  if (!list.length) return { checked: 0, confirmed: [], pending: [], state: await rpc(db, 'founder_pack_state', { p_telegram_id: user.id }) };

  const transactions = await fetchHotWalletIncoming(hotWallet);
  const confirmed: string[] = [];
  const stillPending: string[] = [];
  for (const order of list) {
    const comment = String(order.paymentComment || '').trim();
    const expectedNano = BigInt(String(order.amountNano || '0'));
    const minNano = (expectedNano * 97n) / 100n;
    const match = transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
      return BigInt(String(inMsg.value ?? '0')) >= minNano;
    });
    if (!match) { stillPending.push(String(order.id)); continue; }
    const txHash = txHashOf(match);
    const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
    try {
      await rpc(db, 'founder_pack_confirm_order', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
      confirmed.push(String(order.id));
    } catch (error) {
      console.error('[FORGE ERROR] founder-pack-confirm', { orderId: order.id, txHash, reason: error instanceof Error ? error.message : String(error) });
      stillPending.push(String(order.id));
    }
  }
  return { checked: list.length, confirmed, pending: stillPending, state: await rpc(db, 'founder_pack_state', { p_telegram_id: user.id }) };
}

/**
 * ⚔️ VETERAN VAULT — on-chain settlement of external (TonConnect) purchases.
 * Payments are matched by their unique comment and integer nanoton value; delivery + cycle activation
 * happen inside the RPC, atomically and idempotently. A signed wallet tx alone delivers nothing.
 */
async function verifyVeteranVaultPurchases(db: Db, user: TelegramUser) {
  const hotWallet = await hotWalletAddress(db);
  const orders = (await rpc(db, 'veteran_vault_pending_orders', { p_telegram_id: user.id })) as any[];
  const list = Array.isArray(orders) ? orders : [];
  if (!list.length) return { checked: 0, confirmed: [], pending: [], state: await rpc(db, 'veteran_vault_state', { p_telegram_id: user.id }) };

  const transactions = await fetchHotWalletIncoming(hotWallet);
  const confirmed: string[] = [];
  const stillPending: string[] = [];
  for (const order of list) {
    const comment = String(order.paymentComment || '').trim();
    const expectedNano = BigInt(String(order.amountNano || '0'));
    const minNano = (expectedNano * 97n) / 100n;
    const match = transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
      return BigInt(String(inMsg.value ?? '0')) >= minNano;
    });
    if (!match) { stillPending.push(String(order.id)); continue; }
    const txHash = txHashOf(match);
    const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
    try {
      await rpc(db, 'veteran_vault_confirm_order', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
      confirmed.push(String(order.id));
    } catch (error) {
      console.error('[FORGE ERROR] veteran-vault-confirm', { orderId: order.id, txHash, reason: error instanceof Error ? error.message : String(error) });
      stillPending.push(String(order.id));
    }
  }
  return { checked: list.length, confirmed, pending: stillPending, state: await rpc(db, 'veteran_vault_state', { p_telegram_id: user.id }) };
}

/**
 * ⚔️ VETERAN VAULT V2 — on-chain settlement of TonConnect purchases (100 TON premium pack).
 * Matching is done by unique comment + integer nanoton value; delivery, MYTH mining rates and the
 * +10% owner boost are applied inside the RPC, atomically and idempotently.
 */
async function verifyVeteranV2Purchases(db: Db, user: TelegramUser) {
  const hotWallet = await hotWalletAddress(db);
  const state = async () => await rpc(db, 'veteran_v2_state', { p_telegram_id: user.id });
  const player = await db.from('game_players').select('id').eq('telegram_id', user.id).maybeSingle();
  if (player.error) throw new Error(player.error.message);
  const userId = player.data?.id;
  if (!userId) return { checked: 0, confirmed: [], pending: [], state: await state() };

  const pending = await db.from('veteran_vault_v2_purchases')
    .select('id,payment_comment,expected_nanoton,expires_at')
    .eq('user_id', userId).eq('status', 'pending').gt('expires_at', new Date().toISOString());
  if (pending.error) throw new Error(pending.error.message);
  const list = pending.data ?? [];
  if (!list.length) return { checked: 0, confirmed: [], pending: [], state: await state() };

  const transactions = await fetchHotWalletIncoming(hotWallet);
  const confirmed: string[] = [];
  const stillPending: string[] = [];
  for (const order of list) {
    const comment = String(order.payment_comment || '').trim();
    const expectedNano = BigInt(String(order.expected_nanoton || '0'));
    const minNano = (expectedNano * 97n) / 100n;
    const match = transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg || !comment || msgComment(inMsg) !== comment) return false;
      return BigInt(String(inMsg.value ?? '0')) >= minNano;
    });
    if (!match) { stillPending.push(String(order.id)); continue; }
    const txHash = txHashOf(match);
    const receivedNano = BigInt(String(match.in_msg?.value ?? '0')).toString();
    try {
      await rpc(db, 'veteran_v2_confirm_order', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano });
      confirmed.push(String(order.id));
    } catch (error) {
      console.error('[FORGE ERROR] veteran-v2-confirm', { orderId: order.id, txHash, reason: error instanceof Error ? error.message : String(error) });
      stillPending.push(String(order.id));
    }
  }
  return { checked: list.length, confirmed, pending: stillPending, state: await state() };
}

async function handleWallet(db: Db, user: TelegramUser, body: Record<string, any>) {

  const hotWallet = String(Deno.env.get('TON_HOT_WALLET') || '').trim();
  if (hotWallet) {
    const configured = await db.from('wallet_settings').upsert({ key: 'ton_hot_wallet', value_text: hotWallet, updated_at: new Date().toISOString() });
    if (configured.error) throw new Error(configured.error.message);
  }
  const action = String(body.action || 'summary');
  if (action === 'verify-deposit') return await verifyPendingDeposits(db, user);
  if (action === 'verify-egg-purchases') return await verifyEggPurchases(db, user);
  if (action === 'veteran-vault-verify') return await verifyVeteranVaultPurchases(db, user);
  if (action === 'veteran-v2-verify') return await verifyVeteranV2Purchases(db, user);

  let fn = 'get_wallet_summary';
  let args: Record<string, unknown> = { p_telegram_id: user.id };
  if (action === 'deposit') {
    const amount = Number(body.amountTon);
    const address = String(body.walletAddress || '');
    if (!Number.isFinite(amount) || amount <= 0 || !address) throw new Error('Valor de depósito inválido.');
    // The deposit destination (FC purchase or direct internal TON) is frozen here, at intent
    // creation, and can never be changed by the client afterwards. Minimums live in the DB config.
    const depositType = String(body.depositType || 'ton_to_fc') === 'ton_balance' ? 'ton_balance' : 'ton_to_fc';
    fn = 'create_wallet_deposit';
    args = { ...args, p_amount_ton: amount, p_from_wallet: address, p_deposit_type: depositType, p_idempotency_key: `deposit:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'ton-wallet') {
    // Withdrawable TON balance (rewards only) — never derived from FC.
    fn = 'get_ton_wallet';
  } else if (action === 'withdraw-ton') {
    const amount = Number(body.amountTon);
    const address = toFriendlyTonAddress(body.walletAddress);
    if (!String(body.walletAddress || '').trim()) throw new Error('Connect your TON wallet before requesting a withdrawal.');
    if (!address) throw new Error('Endereço TON inválido.');
    if (!Number.isFinite(amount) || amount <= 0) throw new Error('Valor de saque inválido.');
    fn = 'request_ton_withdrawal';
    args = { ...args, p_amount_ton: amount, p_wallet_address: address, p_idempotency_key: `withdraw-ton:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'withdraw') {
    // FC → TON withdrawal was removed with the FC/TON separation.
    throw new Error('FC_WITHDRAWAL_DISABLED');


  } else if (action === 'myth') {
    // MYTH Token: read-only decorative balance. No purchase, swap, withdrawal or conversion exists.
    fn = 'get_myth_wallet';
  } else if (action === 'myth-sale') {
    // MYTH TOKEN SALE dashboard: every aggregate (sold/burned/available/raised) comes from the DB.
    fn = 'get_myth_sale_dashboard';
  } else if (action === 'myth-buy') {
    // The DB alone decides the payment method: internal TON when it covers 100%, TonConnect otherwise.
    const amount = Math.floor(Number(body.mythAmount));
    if (!Number.isFinite(amount) || amount <= 0) throw new Error('MYTH_INVALID_AMOUNT');
    const wallet = toFriendlyTonAddress(body.walletAddress);
    fn = 'myth_start_purchase';
    args = { ...args, p_myth_amount: amount, p_wallet_address: wallet, p_idempotency_key: `myth:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'myth-utility') {
    // MYTH utility: live balance, discount, conversion rates, per-feature toggles and burn totals.
    fn = 'get_myth_utility_state';
  } else if (action === 'myth-verify') {
    return await verifyMythPurchases(db, user);

  // INTERNAL MYTH STAKING (MYTH -> MYTH only): the DB owns settings, APR, locks and the reward pool.
  // Nothing here touches FC, TON, withdrawable TON or the token sale.
  } else if (action === 'myth-staking') {
    fn = 'get_myth_staking_dashboard';
  } else if (action === 'myth-stake') {
    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0) throw new Error('MYTH_STAKING_INVALID_AMOUNT');
    fn = 'myth_stake';
    args = { ...args, p_amount: amount, p_plan: String(body.planCode || ''), p_idempotency_key: `myth-stake:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'myth-staking-claim') {
    fn = 'myth_staking_claim';
    args = { ...args, p_position_id: isUuid(body.positionId) ? body.positionId : null, p_idempotency_key: `myth-claim:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'myth-unstake') {
    if (!isUuid(body.positionId)) throw new Error('MYTH_STAKING_POSITION_NOT_FOUND');
    fn = 'myth_unstake';
    args = { ...args, p_position_id: body.positionId, p_idempotency_key: `myth-unstake:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };



  // ---------------- 👑 MYTHREON FOUNDER PACK (25 TON, new players only) ----------------
  // Eligibility, price, snapshot, payment and delivery are 100% server-side.
  } else if (action === 'founder-pack') {
    fn = 'founder_pack_state';
  } else if (action === 'founder-pack-buy') {
    // The DB decides the method: internal TON when it covers 100% of the price, TonConnect otherwise.
    fn = 'founder_pack_start_purchase';
    args = { ...args, p_wallet_address: toFriendlyTonAddress(body.walletAddress), p_idempotency_key: `founder:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'founder-pack-verify') {
    return await verifyFounderPackPurchases(db, user);
  // ---------------- ⚔️ MYTHREON VETERAN VAULT (55 TON, veteran players only) ----------------
  // Eligibility (account age / pre-launch account), price, reward pools, 45-day cycle and every
  // credited TON/MYTH are owned by the database. The client only displays server truth.
  } else if (action === 'veteran-vault') {
    fn = 'veteran_vault_state';
  } else if (action === 'veteran-vault-buy') {
    fn = 'veteran_vault_start_purchase';
    args = { ...args, p_wallet_address: toFriendlyTonAddress(body.walletAddress), p_idempotency_key: `veteran:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'veteran-vault-claim') {
    fn = 'veteran_vault_claim';
    args = { ...args, p_idempotency_key: `veteran-claim:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  // ---------------- ⚔️ VETERAN VAULT V2 (100 TON premium pack, MYTH-only mining + owner boost) ----------------
  } else if (action === 'veteran-v2') {
    fn = 'veteran_v2_state';
  } else if (action === 'veteran-v2-buy') {
    fn = 'veteran_v2_start_purchase';
    args = { ...args, p_wallet_address: toFriendlyTonAddress(body.walletAddress), p_idempotency_key: `veteranv2:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };

  // ---------------- 🎁 PREMIUM OFFERS DAILY POPUP QUEUE (server-owned, 1x/day per offer) ----------------
  } else if (action === 'premium-offers') {
    fn = 'premium_offers_state';
  } else if (action === 'premium-offer-seen') {
    fn = 'premium_offer_popup_mark';
    args = { ...args, p_offer_type: String(body.offerType || ''), p_dismissed: Boolean(body.dismissed) };

  } else if (action === 'founder-frame') {
    fn = 'founder_frame_set';
    args = { ...args, p_equipped: Boolean(body.equipped) };
  } else if (action === 'entitlements') {
    fn = 'get_player_entitlements';
  } else if (action === 'egg-order') {

    if (!isUuid(body.eggId)) throw new Error('Ovo inválido.');
    fn = 'create_pet_egg_order';
    args = { ...args, p_egg_id: body.eggId, p_idempotency_key: `egg:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action !== 'summary') throw new Error('Ação inválida.');

  const data = await rpc(db, fn, args);
  if (action === 'deposit' || action === 'withdraw-ton') {
    const walletAddress = toFriendlyTonAddress(body.walletAddress) ?? '';
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
  if (action === 'open-exclusive-chest') {
    // Mythic exclusive chest: the pool roll and duplicate protection live in the RPC.
    if (!isUuid(body.inventoryItemId)) throw new Error('Baú inválido.');
    return rpc(db, 'open_exclusive_chest', { p_telegram_id: user.id, p_inventory_item_id: body.inventoryItemId });
  }
  if (action === 'open-legend-chest') {
    // Legend Chest: always grants a random LEGENDARY equipment piece (server-side roll).
    if (!isUuid(body.inventoryItemId)) throw new Error('Baú inválido.');
    return rpc(db, 'open_legend_chest', { p_telegram_id: user.id, p_inventory_item_id: body.inventoryItemId });
  }
  if (action === 'open-resource-chest') {
    // FOUNDER PACK premium resource chest: contents are configured in the DB and granted server-side.
    if (!isUuid(body.inventoryItemId)) throw new Error('Baú inválido.');
    return rpc(db, 'open_resource_chest', { p_telegram_id: user.id, p_inventory_item_id: body.inventoryItemId });
  }
  if (action === 'open-key-chest') {
    // KEY CHEST (Eternity / Void / Celestial): consumes the matching Tower key and
    // rolls every reward inside the RPC — the client never decides a drop.
    if (!isUuid(body.inventoryItemId)) throw new Error('Baú inválido.');
    return rpc(db, 'open_key_chest', { p_telegram_id: user.id, p_inventory_item_id: body.inventoryItemId });
  }


  if (action === 'summon-hero') {
    // 5 fragments -> 1 random common/uncommon hero. Cost, odds, roll and the new
    // hero instance are all resolved atomically inside the RPC (idempotent).
    const key = String(body.idempotencyKey || crypto.randomUUID());
    if (key.length < 8 || key.length > 100) throw new Error('Chave de requisição inválida.');
    return rpc(db, 'summon_hero_with_fragments', { p_telegram_id: user.id, p_idempotency_key: `fragment_summon:${user.id}:${key}` });
  }
  if (action === 'inventory') return rpc(db, 'get_player_inventory', { p_telegram_id: user.id });

  if (action !== 'dashboard') throw new Error('Ação inválida.');
  return rpc(db, 'get_calendar_dashboard', { p_telegram_id: user.id });
}

/**
 * Single reconciler for TON battle pass purchases.
 * A pass purchase is NOT a deposit: no FC is credited — the paid tier becomes owned by THIS player.
 */
async function verifyPassPurchases(db: Db, user: TelegramUser) {
  const orders = await rpc(db, 'pending_season_pass_orders', { p_telegram_id: user.id }) as any[];
  if (!Array.isArray(orders) || !orders.length) return { checked: 0, completed: [], pending: [], results: [] as any[] };

  const hotWallet = await hotWalletAddress(db);
  const transactions = await fetchHotWalletIncoming(hotWallet);
  const completed: string[] = [];
  const stillPending: string[] = [];
  const results: any[] = [];

  const usedHashes = new Set<string>();
  for (const order of orders) {
    // A pass is only ever activated by a payment carrying THIS order's comment.
    // Plain deposits (or any other purchase) can never activate a pass.
    const comment = String(order.paymentComment || '').trim();
    const expectedNano = BigInt(String(order.amountNano || '0'));
    const minNano = (expectedNano * 97n) / 100n; // 3% tolerance for wallet/network fees
    const match = !comment ? undefined : transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg || msgComment(inMsg) !== comment) return false;
      const hash = String(tx.hash || inMsg.hash || '');
      if (!hash || usedHashes.has(hash)) return false;
      return BigInt(String(inMsg.value ?? '0')) >= minNano;
    });
    if (!match) { stillPending.push(order.id); continue; }
    const txHash = String(match.hash || match.in_msg?.hash || '');
    const receivedNano = String(match.in_msg?.value ?? '0');
    try {
      // Only the database turns a confirmed payment into pass ownership (atomic + idempotent).
      const outcome = await rpc(db, 'confirm_season_pass_order', { p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: receivedNano }) as any;
      usedHashes.add(txHash);
      results.push({ ...outcome, tier: outcome?.tier ?? order.tier, priceTon: order.priceTon });
      completed.push(order.id);
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      console.error('[FORGE ERROR] pass-purchase-confirm', { orderId: order.id, reason });
      if (reason.includes('TX_ALREADY_USED')) { usedHashes.add(txHash); stillPending.push(order.id); }
      else if (reason.includes('INVALID_PAYMENT_AMOUNT')) stillPending.push(order.id);
      else throw error;
    }
  }

  const dashboard = await rpc(db, 'get_season_pass_dashboard', { p_telegram_id: user.id });
  return { checked: orders.length, completed, pending: stillPending, results, dashboard };
}

/**
 * Reconciler for LOCKED pass rewards paid with TonConnect (the 2.5 TON exclusive chest unlock).
 * A chest is only delivered by a payment carrying THIS order's unique comment.
 */
async function verifyLockedRewardPurchases(db: Db, user: TelegramUser) {
  const orders = await rpc(db, 'pending_pass_locked_reward_orders', { p_telegram_id: user.id }) as any[];
  if (!Array.isArray(orders) || !orders.length) return { checked: 0, completed: [], pending: [], results: [] as any[] };
  const transactions = await fetchHotWalletIncoming(await hotWalletAddress(db));
  const completed: string[] = [];
  const stillPending: string[] = [];
  const results: any[] = [];
  const usedHashes = new Set<string>();
  for (const order of orders) {
    const comment = String(order.paymentComment || '').trim();
    const minNano = (BigInt(String(order.amountNano || '0')) * 97n) / 100n;
    const match = !comment ? undefined : transactions.find((tx: any) => {
      const inMsg = tx?.in_msg;
      if (!inMsg || msgComment(inMsg) !== comment) return false;
      const hash = String(tx.hash || inMsg.hash || '');
      if (!hash || usedHashes.has(hash)) return false;
      return BigInt(String(inMsg.value ?? '0')) >= minNano;
    });
    if (!match) { stillPending.push(order.id); continue; }
    const txHash = String(match.hash || match.in_msg?.hash || '');
    try {
      const outcome = await rpc(db, 'confirm_pass_locked_reward_order', {
        p_order_id: order.id, p_tx_hash: txHash, p_amount_nano: String(match.in_msg?.value ?? '0'),
      }) as any;
      usedHashes.add(txHash);
      results.push(outcome);
      completed.push(order.id);
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      console.error('[FORGE ERROR] pass-locked-reward-confirm', { orderId: order.id, reason });
      if (reason.includes('TX_ALREADY_USED') || reason.includes('INVALID_PAYMENT_AMOUNT')) stillPending.push(order.id);
      else throw error;
    }
  }
  const dashboard = await rpc(db, 'get_season_pass_dashboard', { p_telegram_id: user.id });
  const inventory = await rpc(db, 'get_player_inventory', { p_telegram_id: user.id });
  return { checked: orders.length, completed, pending: stillPending, results, dashboard, inventory };
}

async function handleSeasonPass(db: Db, user: TelegramUser, body: Record<string, any>) {
  const action = String(body.action || 'dashboard');
  if (action === 'verify') return await verifyPassPurchases(db, user);
  if (action === 'verify-locked-reward') return await verifyLockedRewardPurchases(db, user);

  let fn = 'get_season_pass_dashboard';
  let args: Record<string, unknown> = { p_telegram_id: user.id };
  if (action === 'order') {
    if (!['adventurer', 'legendary'].includes(body.tier)) throw new Error('Passe inválido.');
    fn = 'create_season_pass_order';
    args = { ...args, p_tier: body.tier, p_idempotency_key: `season:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'order-internal-ton') {
    // One-tap purchase: the DB charges 100% of the price from the internal TON balance
    // or fails with INSUFFICIENT_TON_BALANCE so the client falls back to TonConnect.
    if (!['adventurer', 'legendary'].includes(body.tier)) throw new Error('Passe inválido.');
    fn = 'season_pass_buy_with_internal_ton';
    args = { ...args, p_tier: body.tier, p_idempotency_key: `passton:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };
  } else if (action === 'order-myth') {
    // Alternative pass payment: burns MYTH from the available balance (staked MYTH is never touched).
    if (!['adventurer', 'legendary'].includes(body.tier)) throw new Error('Passe inválido.');
    fn = 'season_pass_buy_with_myth';
    args = { ...args, p_tier: body.tier, p_idempotency_key: `passmyth:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}` };

  } else if (action === 'claim') {
    if (!isUuid(body.rewardId)) throw new Error('Recompensa inválida.');
    fn = 'claim_season_pass_reward';
    args = { ...args, p_reward_id: body.rewardId };
  } else if (action === 'open-mythic-egg') {
    if (!isUuid(body.itemId)) throw new Error('Item inválido.');
    fn = 'open_season_mythic_egg';
    args = { ...args, p_item_id: body.itemId };
  } else if (action === 'buy-level') {
    // Only the backend decides price, daily limit and the resulting level.
    const levels = Number(body.levels);
    if (![1, 3, 5].includes(levels)) throw new Error('Pacote de níveis inválido.');
    fn = 'buy_season_pass_levels';
    args = {
      ...args,
      p_levels: levels,
      p_idempotency_key: `passlevel:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
      p_currency: String(body.currency ?? 'FC').toUpperCase() === 'MYTH' ? 'MYTH' : 'FC',
    };
  } else if (action === 'buy-locked-reward') {
    // Locked exclusive chest (NEW PASS REQUIRED): the DB charges the internal TON balance
    // when it covers 100% of the price, otherwise it returns a TonConnect intent.
    if (!isUuid(body.rewardId)) throw new Error('Recompensa inválida.');
    fn = 'buy_pass_locked_reward';
    args = {
      ...args,
      p_reward_id: body.rewardId,
      p_wallet_address: toFriendlyTonAddress(body.walletAddress),
      p_idempotency_key: `passlocked:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
    };
  } else if (action === 'recent-xp') {

    // Battle Pass XP feed for client toasts: the server owns multipliers, caps and final XP.
    fn = 'get_recent_pass_xp';
    args = { ...args, p_since: typeof body.since === 'string' && body.since ? body.since : null };
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
  /**
   * TACTICAL ARENA (3v3, turn based). Completely separate from the Classic Arena:
   * own team, deck, rating, leagues, queue and matches. The client only sends
   * skill + target + matchId — damage, order, crit, cooldowns, timer, winner,
   * rating and ticket consumption are all resolved inside the RPCs.
   */
  tactical: async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    const id = user.id;
    if (action === 'dashboard') return rpc(db, 'tactical_dashboard', { p_telegram_id: id });
    if (action === 'save-team') {
      const slot = Number(body.slot);
      if (!Number.isInteger(slot) || slot < 1 || slot > 3 || !isUuid(body.heroId)) throw new Error('INVALID_SLOT');
      return rpc(db, 'tactical_save_team', { p_telegram_id: id, p_slot: slot, p_hero_id: body.heroId });
    }
    if (action === 'remove-team') {
      const slot = Number(body.slot);
      if (!Number.isInteger(slot) || slot < 1 || slot > 3) throw new Error('INVALID_SLOT');
      return rpc(db, 'tactical_remove_team', { p_telegram_id: id, p_slot: slot });
    }
    if (action === 'save-deck') {
      const keys = Array.isArray(body.skillKeys) ? body.skillKeys.map((k: unknown) => String(k).slice(0, 40)) : [];
      return rpc(db, 'tactical_save_deck', { p_telegram_id: id, p_skill_keys: keys });
    }
    if (action === 'queue-join') return rpc(db, 'tactical_queue_join', { p_telegram_id: id, p_practice: body.practice === true });
    if (action === 'queue-cancel') return rpc(db, 'tactical_queue_cancel', { p_telegram_id: id });
    if (action === 'queue-status') return rpc(db, 'tactical_queue_status', { p_telegram_id: id });
    if (action === 'match') {
      if (!isUuid(body.matchId)) throw new Error('TACTICAL_MATCH_NOT_FOUND');
      return rpc(db, 'tactical_match_tick', { p_telegram_id: id, p_match_id: body.matchId });
    }
    if (action === 'action') {
      if (!isUuid(body.matchId)) throw new Error('TACTICAL_MATCH_NOT_FOUND');
      return rpc(db, 'tactical_submit_action', {
        p_telegram_id: id,
        p_match_id: body.matchId,
        p_skill_key: String(body.skillKey || 'basic_attack').slice(0, 40),
        p_target_uid: body.targetUid ? String(body.targetUid).slice(0, 8) : null,
        p_client_key: body.clientKey ? String(body.clientKey).slice(0, 80) : null,
      });
    }
    if (action === 'history') return rpc(db, 'tactical_history', { p_telegram_id: id, p_limit: Number(body.limit) || 20 });
    if (action === 'ranking') return rpc(db, 'tactical_ranking', { p_telegram_id: id, p_limit: Number(body.limit) || 50 });
    throw new Error('INVALID_ACTION');
  },
  /**
   * Tower of Eternity (solo dungeon, 100 floors). Fully isolated from the Global Boss
   * and from the Clan Boss: progress, attempts, FC cost, boss scaling, the turn-based
   * simulation and the rewards all live inside the RPCs.
   */
  tower: async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    // Same pet buff pipeline as the Boss: the active pet is resolved server-side and
    // exposed as `petSummary` so the client can render the companion + its buffs.
    const withPet = async (data: unknown) => {
      if (!data || typeof data !== 'object') return data;
      const pets = await db.rpc('get_pet_dashboard', { p_telegram_id: user.id });
      if (pets.error) return data;
      const summary = { activePet: pets.data?.activePet ?? null, bonuses: pets.data?.bonuses ?? {} };
      const out = { ...(data as Record<string, unknown>), petSummary: summary };
      const dash = out.dashboard;
      if (dash && typeof dash === 'object') out.dashboard = { ...(dash as Record<string, unknown>), petSummary: summary };
      return out;
    };
    if (action === 'dashboard') return withPet(await rpc(db, 'get_tower_dashboard', { p_telegram_id: user.id }));
    if (action === 'equip') {
      const slot = Number(body.slot);
      if (!Number.isInteger(slot) || slot < 1 || slot > 5) throw new Error('INVALID_SLOT');
      if (!isUuid(body.heroId)) throw new Error('HERO_NOT_FOUND');
      return withPet(await rpc(db, 'save_tower_team_slot', { p_telegram_id: user.id, p_slot: slot, p_hero_id: body.heroId }));
    }
    if (action === 'remove') {
      const slot = Number(body.slot);
      if (!Number.isInteger(slot) || slot < 1 || slot > 5) throw new Error('INVALID_SLOT');
      return withPet(await rpc(db, 'remove_tower_team_slot', { p_telegram_id: user.id, p_slot: slot }));
    }
    if (action === 'enter') {
      // Entry can be paid with FC (default) or with the internal TON balance. Debit happens server-side.
      const raw = String(body.payWith ?? 'fc').toLowerCase();
      const payWith = raw === 'ton' ? 'ton' : raw === 'myth' ? 'myth' : 'fc';
      return attachHeroXp(db, user.id, 'DUNGEON', await withPet(await rpc(db, 'tower_enter_floor', { p_telegram_id: user.id, p_pay_currency: payWith })));
    }
    // Tower ranking: read-only leaderboard (highest floor, then team power, then who got there first).
    if (action === 'ranking') {
      const limit = Math.min(Math.max(Number(body.limit) || 50, 1), 100);
      return await rpc(db, 'get_tower_ranking', { p_telegram_id: user.id, p_limit: limit });
    }
    throw new Error('INVALID_ACTION');
  },

  /**
   * Starter Pack: welcome gift for accounts created on/after 2026-08-13 (UTC-3).
   * Delivery is fully server-side and idempotent (one claim per player, ever).
   */
  'starter-pack': async (db, user, body) => {
    const action = String(body.action || 'status');
    if (action === 'claim') return rpc(db, 'claim_starter_pack', { p_telegram_id: user.id });
    if (action !== 'status') throw new Error('INVALID_ACTION');
    return rpc(db, 'get_starter_pack_status', { p_telegram_id: user.id });
  },

  wallet: handleWallet,
  calendar: handleCalendar,
  'season-pass': handleSeasonPass,
  referral: handleReferral,
  /**
   * Clans: membership, roles, chat, missions, clan boss and clan shop.
   * The database owns every rule (XP, points, limits) — the client only asks.
   */
  clan: async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    if (action === 'dashboard') {
      // Anti-abuse state (join cooldown + clan boss lock) rides along so the UI can show real counters.
      const [dash, antiAbuse] = await Promise.all([
        rpc(db, 'get_clan_dashboard', { p_telegram_id: user.id }),
        rpc(db, 'clan_anti_abuse_state', { p_telegram_id: user.id }).catch(() => null),
      ]);
      return { ...(dash as Record<string, unknown>), antiAbuse };
    }
    if (action === 'search') return rpc(db, 'search_clans', { p_telegram_id: user.id, p_query: String(body.query || '').slice(0, 40) });
    if (action === 'create') {
      return rpc(db, 'create_clan', {
        p_telegram_id: user.id,
        p_name: String(body.name || '').slice(0, 24),
        p_tag: String(body.tag || '').slice(0, 5),
        p_description: String(body.description || '').slice(0, 200),
        p_join_type: ['open', 'approval', 'closed'].includes(String(body.joinType)) ? String(body.joinType) : 'open',
        p_min_trophies: Math.max(0, Number(body.minimumTrophies) || 0),
        p_emblem: body.emblem && typeof body.emblem === 'object' ? body.emblem : {},
      });
    }
    if (action === 'join') {
      if (!isUuid(body.clanId)) throw new Error('CLAN_NOT_FOUND');
      return rpc(db, 'join_clan', { p_telegram_id: user.id, p_clan_id: body.clanId });
    }
    if (action === 'leave') return rpc(db, 'leave_clan', { p_telegram_id: user.id });
    if (action === 'manage') {
      const manageAction = String(body.manageAction || '');
      if (!['edit', 'kick', 'promote', 'demote', 'transfer', 'accept', 'reject'].includes(manageAction)) throw new Error('INVALID_ACTION');
      return rpc(db, 'clan_manage', {
        p_telegram_id: user.id,
        p_action: manageAction,
        p_target: isUuid(body.targetId) ? body.targetId : null,
        p_payload: body.payload && typeof body.payload === 'object' ? body.payload : {},
      });
    }
    if (action === 'chat') {
      const chatAction = ['list', 'send', 'delete'].includes(String(body.chatAction)) ? String(body.chatAction) : 'list';
      return rpc(db, 'clan_chat', {
        p_telegram_id: user.id,
        p_action: chatAction,
        p_body: typeof body.body === 'string' ? body.body.slice(0, 300) : null,
        p_message_id: isUuid(body.messageId) ? body.messageId : null,
      });
    }
    // Clan boss (Abyssal Warlord): isolated from the global boss. The instance id is
    // only a staleness hint — the RPC re-resolves the caller's clan and refuses anything else.
    if (action === 'boss-state') return rpc(db, 'get_clan_boss', { p_telegram_id: user.id });
    if (action === 'boss-strike') {
      return attachHeroXp(db, user.id, 'CLAN_BOSS', await rpc(db, 'clan_boss_strike', {
        p_telegram_id: user.id,
        p_instance_id: isUuid(body.instanceId) ? body.instanceId : null,
      }));
    }

    if (action === 'boss-attack') return rpc(db, 'clan_boss_attack', { p_telegram_id: user.id });
    // Season Pass benefit: offline Auto ATK preference for the CLAN boss only.
    // Independent from the global boss toggle (set_global_boss_auto_attack).
    if (action === 'boss-auto-attack') {
      return rpc(db, 'set_clan_boss_auto_attack', { p_telegram_id: user.id, p_enabled: body.enabled !== false });
    }
    if (action === 'shop') {
      const item = String(body.item || '');
      if (!['pet_food', 'pvp_ticket', 'fragments', 'hero_chest'].includes(item)) throw new Error('INVALID_ITEM');
      return rpc(db, 'clan_shop_buy', { p_telegram_id: user.id, p_item: item, p_quantity: Math.max(1, Math.min(20, Number(body.quantity) || 1)) });
    }

    // ═══ COLLECTIVE LAYER — Personal Boss stays individual; these are the shared systems ═══
    if (action === 'hub') {
      await rpc(db, 'clan_hub_prepare', { p_telegram_id: user.id }).catch(() => null);
      return rpc(db, 'clan_hub_state', { p_telegram_id: user.id });
    }
    if (action === 'milestone-claim') {
      return rpc(db, 'clan_milestone_claim', { p_telegram_id: user.id, p_pct: Number(body.pct) || 0 });
    }
    // Dedicated collective raid screen: boss, HP, day/phase, ranking. Server is the only authority.
    if (action === 'raid-state') return rpc(db, 'clan_raid_state', { p_telegram_id: user.id });
    if (action === 'raid-attack') {
      const key = typeof body.clientKey === 'string' ? body.clientKey.slice(0, 80) : null;
      return rpc(db, 'clan_raid_attack', { p_telegram_id: user.id, p_key: key });
    }

    if (action === 'treasury-donate') {
      const asset = String(body.asset || 'FC').toUpperCase();
      if (!['FC', 'MYTH'].includes(asset)) throw new Error('INVALID_ASSET');
      const amount = Number(body.amount);
      if (!Number.isFinite(amount) || amount <= 0) throw new Error('INVALID_AMOUNT');
      return rpc(db, 'clan_treasury_donate', { p_telegram_id: user.id, p_asset: asset, p_amount: amount });
    }
    // Per-clan daily donation limits: state is read-only, the setter is leader-only in SQL.
    if (action === 'donation-state') {
      return rpc(db, 'clan_donation_state', { p_telegram_id: user.id });
    }
    // Real treasury donation history: FC and MYTH kept separate, aggregated server-side.
    if (action === 'contribution-summary') {
      const period = String(body.period || 'week').toLowerCase();
      return rpc(db, 'clan_contribution_summary', { p_telegram_id: user.id, p_period: ['today', 'week', 'total'].includes(period) ? period : 'week' });
    }
    if (action === 'contribution-detail') {
      return rpc(db, 'clan_contribution_detail', { p_telegram_id: user.id, p_target: body.userId ? String(body.userId) : null });
    }
    if (action === 'contribution-history') {
      return rpc(db, 'clan_contribution_history', {
        p_telegram_id: user.id,
        p_target: body.userId ? String(body.userId) : null,
        p_limit: Math.max(1, Math.min(100, Number(body.limit) || 50)),
      });
    }
    if (action === 'contribution-limits-set') {
      const asset = String(body.asset || 'FC').toUpperCase();
      if (!['FC', 'MYTH'].includes(asset)) throw new Error('INVALID_ASSET');
      const min = Math.floor(Number(body.min));
      const max = Math.floor(Number(body.max));
      if (!Number.isFinite(min) || !Number.isFinite(max)) throw new Error('INVALID_AMOUNT');
      return rpc(db, 'clan_contribution_limits_set', {
        p_telegram_id: user.id, p_asset: asset, p_min: min, p_max: max,
      });
    }

    if (action === 'upgrade-buy') {
      // Leader/vice check and treasury debit both live server-side in the RPC.
      return rpc(db, 'clan_upgrade_buy', {
        p_telegram_id: user.id,
        p_code: String(body.code || '').slice(0, 40),
        p_key: body.clientKey ? String(body.clientKey).slice(0, 80) : null,
      });
    }

    if (action === 'buff-activate') {
      return rpc(db, 'clan_buff_activate', { p_telegram_id: user.id, p_code: String(body.code || '').slice(0, 40) });
    }
    // Weekly-locked prices, personal limits and per-clan stock all come from the server.
    if (action === 'clan-shop-state') {
      return rpc(db, 'clan_shop_state', { p_telegram_id: user.id });
    }
    if (action === 'clan-shop-buy') {

      return rpc(db, 'clan_shop_purchase', {
        p_telegram_id: user.id,
        p_code: String(body.code || '').slice(0, 40),
        p_quantity: Math.max(1, Math.min(20, Number(body.quantity) || 1)),
        p_idempotency_key: typeof body.clientKey === 'string' ? body.clientKey.slice(0, 64) : null,
      });
    }
    throw new Error('Ação inválida.');
  },

  /**
   * Clan War: 20v20 season warfare. Every mutation is a server RPC — the client only
   * picks heroes for defense and chooses which enemy roster slot to attack.
   */
  'clan-war': async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    if (action === 'dashboard') return rpc(db, 'clan_war_dashboard', { p_telegram_id: user.id });
    if (action === 'join') return rpc(db, 'clan_war_join', { p_telegram_id: user.id });
    if (action === 'leave-queue') return rpc(db, 'clan_war_leave_queue', { p_telegram_id: user.id });
    if (action === 'defense') {
      const heroIds = Array.isArray(body.heroIds) ? body.heroIds.filter((id: unknown) => isUuid(id)).slice(0, 5) : [];
      if (heroIds.length === 0) throw new Error('INVALID_TEAM');
      const petId = isUuid(body.petId) ? body.petId : null;
      return rpc(db, 'clan_war_set_defense', { p_telegram_id: user.id, p_hero_ids: heroIds, p_pet_id: petId });
    }
    if (action === 'attack') {
      if (!isUuid(body.defender)) throw new Error('TARGET_NOT_FOUND');
      const clientKey = typeof body.clientKey === 'string' ? body.clientKey.slice(0, 64) : null;
      return attachHeroXp(db, user.id, 'PVP', await rpc(db, 'clan_war_attack', {
        p_telegram_id: user.id,
        p_defender: body.defender,
        p_client_key: clientKey,
      }));
    }
    if (action === 'roster-candidates') return rpc(db, 'clan_war_roster_candidates', { p_telegram_id: user.id });
    if (action === 'set-roster') {
      const userIds = Array.isArray(body.userIds) ? body.userIds.filter((id: unknown) => isUuid(id)).slice(0, 40) : [];
      return rpc(db, 'clan_war_set_roster', { p_telegram_id: user.id, p_user_ids: userIds });
    }
    throw new Error('Ação inválida.');

  },



  /** Daily quests: progress is only written by server-side event hooks, never by the client. */
  quests: async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    if (action === 'dashboard') return rpc(db, 'get_daily_quests', { p_telegram_id: user.id });
    if (action === 'claim-chest') return rpc(db, 'claim_daily_quest_chest', { p_telegram_id: user.id });
    if (action === 'claim') {
      const code = String(body.code || '');
      if (!/^[a-z0-9_]{3,40}$/.test(code)) throw new Error('QUEST_NOT_FOUND');
      return attachHeroXp(db, user.id, 'MISSION', await rpc(db, 'claim_daily_quest', { p_telegram_id: user.id, p_quest_code: code }));
    }
    throw new Error('Ação inválida.');
  },
  /** Read-only feed of rewards already delivered to THIS player (never grants anything). */
  rewards: async (db, user, body) => {
    const limit = Math.min(Math.max(Number(body.limit ?? 5) || 5, 1), 100);
    const offset = Math.max(Number(body.offset ?? 0) || 0, 0);
    const payload = await rpc(db, 'get_reward_history', { p_telegram_id: user.id, p_limit: limit, p_offset: offset }) as Record<string, unknown>;
    console.log('[RECENTLY UNLOCKED]', { telegramId: user.id, count: Array.isArray(payload?.items) ? payload.items.length : 0, total: payload?.total ?? 0 });
    return payload;
  },
  /** Unread notifications are marked as read server-side so they never reappear on the next launch. */
  notifications: async (db, user, body) => {
    const action = String(body.action || 'mark-read');
    if (action !== 'mark-read') throw new Error('Ação inválida.');
    const ids = Array.isArray(body.ids) ? body.ids.filter((id: unknown) => isUuid(id)) : null;
    const result = await rpc(db, 'mark_notifications_read', { p_telegram_id: user.id, p_ids: ids && ids.length ? ids : null });
    console.log('[NOTIFICATIONS]', { telegramId: user.id, marked: (result as any)?.updated ?? 0 });
    return result;
  },
  /**
   * Official channel rewards: one-time 5,000 FC per channel, keyed by the authenticated
   * Telegram ID. JOIN only opens the link; VERIFY credits once and stays claimed forever.
   */
  channels: async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    if (action === 'dashboard') return rpc(db, 'get_channel_rewards', { p_telegram_id: user.id });
    if (action !== 'verify') throw new Error('Ação inválida.');
    const key = String(body.channelKey || '');
    if (!['news', 'community', 'payments'].includes(key)) throw new Error('CHANNEL_NOT_AVAILABLE');
    const result = await rpc(db, 'claim_channel_reward', { p_telegram_id: user.id, p_channel_key: key }) as Record<string, unknown>;
    console.log('[CHANNEL VERIFY]', { telegramId: user.id, channelKey: key, status: result?.status, creditedFc: result?.creditedFc });
    return result;
  },


  /**
   * REWARDS tab: AdsGram rewarded ads paying real TON into the withdrawable balance.
   * The server owns the reward value, the daily limit and the 21:00 (America/Sao_Paulo)
   * reset. `begin` only opens a view; TON is credited by `reward` after AdsGram confirms.
   */
  ads: async (db, user, body) => {
    const action = String(body.action || 'state');
    if (action === 'state') return rpc(db, 'get_ad_rewards', { p_telegram_id: user.id });
    if (action === 'begin') return rpc(db, 'ad_reward_begin', { p_telegram_id: user.id });
    if (action === 'reward') {
      return rpc(db, 'ad_reward_claim', {
        p_telegram_id: user.id,
        p_view_id: isUuid(body.viewId) ? body.viewId : null,
        p_source: 'client',
      });
    }
    throw new Error('INVALID_ACTION');
  },

  /**
   * Promotional campaign popup (e.g. MYTHREON GIVEAWAY). Shown ONCE per player per
   * campaign_id: switching the campaign id in settings starts a new campaign for everyone.
   * It never grants rewards — it is promotional only.
   */
  'campaign-popup': async (db, user, body) => {
    const action = String(body.action || 'status');
    if (action === 'status') return rpc(db, 'get_campaign_popup', { p_telegram_id: user.id });
    if (action === 'dismiss' || action === 'join' || action === 'shown') {
      const campaignId = String(body.campaignId || '').slice(0, 120);
      if (!campaignId) throw new Error('INVALID_REQUEST');
      return rpc(db, 'mark_campaign_popup', { p_telegram_id: user.id, p_campaign_id: campaignId, p_action: action });
    }
    throw new Error('INVALID_ACTION');
  },

  /** Special events (EVENTS tab). Ranking and prizes are computed server-side only. */
  events: async (db, user) => {
    return rpc(db, 'get_special_events_dashboard', { p_telegram_id: user.id });
  },

  /**
   * Spending Event (SPENDING EVENT tab). Points, ranking, totals and estimated
   * rewards are computed server-side from confirmed spends only.
   * `popup` / `popup-seen` only drive the entry highlight: they never change the event itself.
   */
  'spending-event': async (db, user, body) => {
    const action = String(body.action || 'dashboard');
    if (action === 'popup') return rpc(db, 'get_spending_event_popup', { p_telegram_id: user.id });
    if (action === 'popup-seen') return rpc(db, 'mark_spending_event_popup_seen', { p_telegram_id: user.id });
    const limit = Math.min(200, Math.max(5, Number(body.limit) || 20));
    return rpc(db, 'get_spending_event_dashboard', { p_telegram_id: user.id, p_limit: limit });
  },

  /**
   * POOL MARKETING tab: read-only project expense transparency. Totals, expenses and
   * the tab toggle are written exclusively by the admin bot — players can only read.
   */
  'marketing-pool': async (db, _user, body) => {
    const limit = Math.min(200, Math.max(5, Number(body.limit) || 50));
    return rpc(db, 'marketing_pool_dashboard', { p_limit: limit });
  },

  /**
   * Player market (FC or TON). Eligibility, fees, market locks, reservations and the
   * atomic purchase all live inside the RPCs — the client can only ask.
   * TON purchases first use the internal available TON balance; an external wallet
   * payment always goes through a payment intent that reserves the listing.
   */
  market: async (db, user, body) => {
    const action = String(body.action || 'browse');
    // Single source of truth for the maintenance switch (server-validated identity).
    if (action === 'status') return rpc(db, 'market_status', { p_telegram_id: user.id });
    if (action === 'quote') {
      const itemType = String(body.itemType || 'item');
      return rpc(db, 'market_price_quote', {
        p_telegram_id: user.id,
        p_item_type: ['hero', 'pet', 'item'].includes(itemType) ? itemType : 'item',
        p_item_instance_id: isUuid(body.itemInstanceId) ? body.itemInstanceId : null,
        p_item_code: body.itemCode ? String(body.itemCode) : null,
      });
    }
    if (action === 'browse') {
      const itemType = ['all', 'hero', 'pet', 'item'].includes(String(body.itemType)) ? String(body.itemType) : 'all';
      const rarity = /^[a-z]{3,20}$/.test(String(body.rarity || '')) ? String(body.rarity) : 'all';
      const sort = ['newest', 'price_low', 'price_high'].includes(String(body.sort)) ? String(body.sort) : 'newest';
      const currency = ['FC', 'TON'].includes(String(body.currency || '').toUpperCase())
        ? String(body.currency).toUpperCase()
        : 'all';
      return rpc(db, 'market_browse', {
        p_telegram_id: user.id,
        p_item_type: itemType,
        p_rarity: rarity,
        p_sort: sort,
        p_limit: Math.min(100, Math.max(1, Number(body.limit) || 60)),
        p_offset: Math.max(0, Number(body.offset) || 0),
        p_currency: currency,
      });
    }
    if (action === 'sellable') return rpc(db, 'market_get_sellable', { p_telegram_id: user.id });
    if (action === 'mine') return rpc(db, 'market_my_listings', { p_telegram_id: user.id });
    // Read-only premium preview of one listing / auction lot (real instance attributes).
    if (action === 'details') {
      const source = String(body.source || 'market') === 'auction' ? 'auction' : 'market';
      const id = source === 'auction' ? body.auctionId ?? body.listingId : body.listingId;
      if (!isUuid(id)) throw new Error('INVALID_LISTING');
      return rpc(db, 'market_item_details', { p_telegram_id: user.id, p_source: source, p_id: id });
    }
    if (action === 'create') {
      const itemType = String(body.itemType || '');
      if (!['hero', 'pet', 'item'].includes(itemType)) throw new Error('INVALID_ITEM_TYPE');
      const currency = String(body.currency || 'FC').toUpperCase() === 'TON' ? 'TON' : 'FC';
      let priceFc: number | null = null;
      let priceTon: number | null = null;
      if (currency === 'TON') {
        priceTon = Math.round(Number(body.priceTon) * 1000) / 1000;
        if (!Number.isFinite(priceTon) || priceTon <= 0) throw new Error('INVALID_PRICE');
      } else {
        priceFc = Number(body.priceFc);
        if (!Number.isInteger(priceFc) || priceFc <= 0) throw new Error('INVALID_PRICE');
      }
      // Stackable/instance item codes are namespaced: `food:x`, `ufrag`, `pfrag:<uuid>`, `equip:<uuid>`
      // or a plain inventory code (chests, fragments).
      if (itemType === 'item') {
        if (!/^[a-z0-9_:-]{2,60}$/.test(String(body.itemCode || '').toLowerCase())) throw new Error('INVALID_ITEM');
      } else if (!isUuid(body.itemInstanceId)) throw new Error('INVALID_ITEM');
      const quantity = Math.max(1, Math.min(9999, Math.trunc(Number(body.quantity) || 1)));
      if (itemType !== 'item' && quantity !== 1) throw new Error('INVALID_QUANTITY');
      return rpc(db, 'market_create_listing', {
        p_telegram_id: user.id,
        p_item_type: itemType,
        p_item_instance_id: itemType === 'item' ? null : body.itemInstanceId,
        p_item_code: itemType === 'item' ? String(body.itemCode).toLowerCase() : null,
        p_price_fc: priceFc,
        p_currency: currency,
        p_price_ton: priceTon,
        p_quantity: quantity,
      });
    }
    if (action === 'cancel') {
      if (!isUuid(body.listingId)) throw new Error('INVALID_LISTING');
      return rpc(db, 'market_cancel_listing', { p_telegram_id: user.id, p_listing_id: body.listingId });
    }
    if (action === 'buy') {
      if (!isUuid(body.listingId)) throw new Error('INVALID_LISTING');
      return rpc(db, 'market_buy_listing', { p_telegram_id: user.id, p_listing_id: body.listingId });
    }
    // External TON payment: reserves the listing for this buyer and returns the exact payment data.
    if (action === 'payment-intent') {
      if (!isUuid(body.listingId)) throw new Error('INVALID_LISTING');
      const wallet = String(body.walletAddress || '').trim();
      if (wallet.length < 10) throw new Error('WALLET_REQUIRED');
      return rpc(db, 'market_create_payment_intent', {
        p_telegram_id: user.id,
        p_listing_id: body.listingId,
        p_wallet_address: wallet,
      });
    }
    if (action === 'payment-status') {
      if (!isUuid(body.paymentId)) throw new Error('INVALID_PAYMENT');
      return rpc(db, 'market_payment_status', { p_telegram_id: user.id, p_payment_id: body.paymentId });
    }
    if (action === 'payment-cancel') {
      if (!isUuid(body.paymentId)) throw new Error('INVALID_PAYMENT');
      return rpc(db, 'market_cancel_payment_intent', { p_telegram_id: user.id, p_payment_id: body.paymentId });
    }
    throw new Error('INVALID_ACTION');
  },

  /**
   * AUCTION — trading exclusively with the INTERNAL TON balance.
   * No FC, no TonConnect during a bid: `auction_place_bid` reserves the player's
   * available TON (and releases the previous highest bidder). Eligibility
   * (Legendary+ heroes, NFT Exclusive heroes/pets/equipment), fee, anti-snipe
   * extension and settlement all live in the RPCs — the client only renders.
   */
  auction: async (db, user, body) => {
    const action = String(body.action || 'browse');
    if (action === 'browse') {
      const itemType = ['all', 'hero', 'pet', 'equipment'].includes(String(body.itemType)) ? String(body.itemType) : 'all';
      const sort = ['ending', 'newest', 'price_low', 'price_high'].includes(String(body.sort)) ? String(body.sort) : 'ending';
      return rpc(db, 'auction_browse', {
        p_telegram_id: user.id,
        p_item_type: itemType,
        p_sort: sort,
        p_limit: Math.min(100, Math.max(1, Number(body.limit) || 60)),
        p_offset: Math.max(0, Number(body.offset) || 0),
      });
    }
    if (action === 'sellable') return rpc(db, 'auction_sellable', { p_telegram_id: user.id });
    if (action === 'mine') return rpc(db, 'auction_mine', { p_telegram_id: user.id });
    if (action === 'create') {
      const itemType = String(body.itemType || '');
      if (!['hero', 'pet', 'equipment'].includes(itemType)) throw new Error('INVALID_ITEM_TYPE');
      if (!isUuid(body.itemInstanceId)) throw new Error('INVALID_ITEM');
      const startingBid = Math.round(Number(body.startingBidTon) * 1e6) / 1e6;
      if (!Number.isFinite(startingBid) || startingBid <= 0) throw new Error('INVALID_PRICE');
      const duration = Math.trunc(Number(body.durationHours));
      if (!Number.isFinite(duration) || duration <= 0 || duration > 168) throw new Error('INVALID_DURATION');
      return rpc(db, 'auction_create', {
        p_telegram_id: user.id,
        p_item_type: itemType,
        p_item_instance_id: body.itemInstanceId,
        p_starting_bid_ton: startingBid,
        p_duration_hours: duration,
      });
    }
    if (action === 'bid') {
      if (!isUuid(body.auctionId)) throw new Error('AUCTION_NOT_FOUND');
      const amount = Math.round(Number(body.amountTon) * 1e6) / 1e6;
      if (!Number.isFinite(amount) || amount <= 0) throw new Error('INVALID_BID');
      const key = String(body.idempotencyKey || crypto.randomUUID()).slice(0, 80);
      return rpc(db, 'auction_place_bid', {
        p_telegram_id: user.id,
        p_auction_id: body.auctionId,
        p_amount_ton: amount,
        p_idempotency_key: key,
      });
    }
    if (action === 'cancel') {
      if (!isUuid(body.auctionId)) throw new Error('AUCTION_NOT_FOUND');
      return rpc(db, 'auction_cancel', { p_telegram_id: user.id, p_auction_id: body.auctionId });
    }
    throw new Error('INVALID_ACTION');
  },

  /**
   * PRIVATE TRADE — direct player ⇄ player trading. It never creates a Market or
   * Auction listing: `private_trades.recipient_user_id` is the only authorised
   * partner. Items/currency go into escrow on LOCK OFFER, both sides must confirm
   * and `private_trade_settle` runs the whole swap in one transaction. Risk score
   * and anti-multiaccount flags stay server-side (admin only).
   */
  'private-trade': async (db, user, body) => {
    const action = String(body.action || 'list');
    if (action === 'list') return rpc(db, 'private_trade_list', { p_telegram_id: user.id });
    // Tradable assets for the item picker: includes NFT / legendary / mythic instances.
    if (action === 'assets') return rpc(db, 'private_trade_assets', { p_telegram_id: user.id });
    if (action === 'search') {
      return rpc(db, 'private_trade_search_player', { p_telegram_id: user.id, p_query: String(body.query || '').slice(0, 64) });
    }
    if (action === 'create') {
      return rpc(db, 'private_trade_create', {
        p_telegram_id: user.id,
        p_query: String(body.query || '').slice(0, 64),
        p_request_id: String(body.requestId || crypto.randomUUID()).slice(0, 80),
      });
    }
    if (!isUuid(body.tradeId)) throw new Error('TRADE_NOT_FOUND');
    if (action === 'view') return rpc(db, 'private_trade_view', { p_telegram_id: user.id, p_trade: body.tradeId });
    if (action === 'add-item') {
      const itemType = String(body.itemType || '');
      if (!['hero', 'pet', 'item'].includes(itemType)) throw new Error('INVALID_ITEM_TYPE');
      if (itemType !== 'item' && !isUuid(body.itemInstanceId)) throw new Error('INVALID_ITEM');
      return rpc(db, 'private_trade_add_item', {
        p_telegram_id: user.id,
        p_trade: body.tradeId,
        p_item_type: itemType,
        p_instance_id: itemType === 'item' ? null : body.itemInstanceId,
        p_item_code: itemType === 'item' ? String(body.itemCode || '') : null,
        p_quantity: Math.max(1, Math.trunc(Number(body.quantity) || 1)),
      });
    }
    if (action === 'remove-item') {
      if (!isUuid(body.itemId)) throw new Error('ITEM_NOT_IN_TRADE');
      return rpc(db, 'private_trade_remove_item', { p_telegram_id: user.id, p_trade: body.tradeId, p_item_id: body.itemId });
    }
    if (action === 'currency') {
      return rpc(db, 'private_trade_set_currency', {
        p_telegram_id: user.id,
        p_trade: body.tradeId,
        p_fc: Math.max(0, Math.trunc(Number(body.fc) || 0)),
        p_ton: Math.max(0, Math.round((Number(body.ton) || 0) * 1e9) / 1e9),
        p_myth: Math.max(0, Math.round((Number(body.myth) || 0) * 1e4) / 1e4),
      });
    }
    if (action === 'lock') {
      return rpc(db, 'private_trade_lock', {
        p_telegram_id: user.id,
        p_trade: body.tradeId,
        p_locked: body.locked !== false,
        p_request_id: String(body.requestId || crypto.randomUUID()).slice(0, 80),
      });
    }
    if (action === 'confirm') {
      return rpc(db, 'private_trade_confirm', {
        p_telegram_id: user.id,
        p_trade: body.tradeId,
        p_request_id: String(body.requestId || crypto.randomUUID()).slice(0, 80),
      });
    }
    if (action === 'cancel') {
      return rpc(db, 'private_trade_cancel', {
        p_telegram_id: user.id,
        p_trade: body.tradeId,
        p_reason: body.reason ? String(body.reason).slice(0, 120) : null,
      });
    }
    throw new Error('INVALID_ACTION');
  },






  /**
   * Partner channels. The Mini App only ever receives NAME + REWARD + claimed flag;
   * the real destination URL is resolved server-side by `go` and never listed.
   * When the admin enabled validation for a partner, the reward is only paid after
   * Telegram confirms the player is a member of the configured chat.
   */
  partners: async (db, user, body) => {
    const action = String(body.action || 'list');
    if (action === 'list') return rpc(db, 'get_partner_channels', { p_telegram_id: user.id });
    if (!isUuid(body.partnerId)) throw new Error('INVALID_PARTNER');
    if (action === 'go') return rpc(db, 'partner_channel_visit', { p_telegram_id: user.id, p_partner_id: body.partnerId });
    if (action === 'claim') {
      const target = (await rpc(db, 'partner_validation_target', { p_partner_id: body.partnerId })) as
        | { validationEnabled?: boolean; chatId?: string | null }
        | null;
      let verified: boolean | null = null;
      if (target?.validationEnabled) {
        const chatId = String(target.chatId || '').trim();
        if (!chatId) throw new Error('PARTNER_VALIDATION_UNAVAILABLE');
        verified = await telegramIsChatMember(chatId, user.id);
        if (!verified) throw new Error('PARTNER_NOT_JOINED');
      }
      return rpc(db, 'claim_partner_reward', {
        p_telegram_id: user.id,
        p_partner_id: body.partnerId,
        p_membership_verified: verified,
      });
    }
    throw new Error('INVALID_ACTION');
  },

  /**
   * MISSION: ADD #MYTHREON TO YOUR TELEGRAM NAME.
   * The display name is NEVER read from the client. On VERIFY the server asks the
   * Telegram Bot API for the current profile (getChat) and falls back to the signed
   * initData only when the Bot API cannot answer for that user. The RPC re-validates
   * the hashtag and pays at most once per Telegram ID, atomically.
   */
  namemission: async (db, user, body) => {
    const action = String(body.action || 'state');
    if (action === 'state') return rpc(db, 'get_name_mission_state', { p_telegram_id: user.id });
    if (action !== 'verify') throw new Error('INVALID_ACTION');

    const state = (await rpc(db, 'get_name_mission_state', { p_telegram_id: user.id })) as
      | { enabled?: boolean; hashtag?: string; claimed?: boolean }
      | null;
    if (state?.claimed) return { ...(state as object), status: 'already_claimed', verified: true, creditedFc: 0 };
    if (state?.enabled !== true) throw new Error('NAME_MISSION_DISABLED');

    const hashtag = String(state?.hashtag || '#Mythreon');
    const live = await telegramLiveDisplayName(user.id);
    const fallback = [user.first_name ?? '', user.last_name ?? ''].join(' ').replace(/\s+/g, ' ').trim();
    const displayName = live ?? fallback;
    const source = live !== null ? 'bot_api' : 'init_data';

    if (!hashtagPresent(displayName, hashtag)) {
      return {
        ...(state as object),
        status: 'not_verified',
        verified: false,
        reason: 'HASHTAG_NOT_FOUND',
        // The client uses this to ask for a reopen when only the cached session was available.
        stale: source === 'init_data',
        source,
        displayName,
      };
    }

    const rawInitData = typeof body.initData === 'string' ? body.initData : '';
    const authDate = rawInitData ? Number(new URLSearchParams(rawInitData).get('auth_date')) || null : null;
    const claim = (await rpc(db, 'claim_name_mission', {
      p_telegram_id: user.id,
      p_display_name: displayName,
      p_source: source,
      p_auth_date: authDate,
    })) as Record<string, unknown>;
    return { ...claim, verified: true, source, displayName };
  },




  pool: async (db, user, body) => {
    // Daily activity scoring progress (PvP / bosses / pet feed / expeditions).
    // Read-only: points and XP are granted by DB triggers, never by the client.
    if (String(body?.action || '') === 'activity') {
      return rpc(db, 'get_activity_progress', { p_telegram_id: user.id });
    }
    // The main event slot: while PVP LEAGUE ARENA is DRAFT the Community Pool keeps rendering.
    const [dashboard, league] = await Promise.all([
      rpc(db, 'get_community_pool_dashboard', { p_telegram_id: user.id }),
      rpc(db, 'pvp_league_dashboard', { p_telegram_id: user.id }).catch(() => null),
    ]);
    const active = league && (league as { active?: boolean }).active === true;
    return { ...(dashboard as Record<string, unknown>), pvpLeague: active ? league : null };
  },

  /**
   * Hero TON mining. Production is accrued from the server clock only (offline included);
   * the client never sends amounts. CLAIM ALL credits the withdrawable TON balance.
   */
  mining: async (db, user, body) => {
    const action = String(body.action || 'status');
    if (action === 'status') return rpc(db, 'get_hero_mining_state', { p_telegram_id: user.id });
    if (action === 'claim') return rpc(db, 'claim_hero_mining', { p_telegram_id: user.id });
    // RARE HERO MYTH MINING: proportional slice of a fixed daily budget with
    // diminishing returns. Rates/units/emission are computed server-side only.
    if (action === 'rare-status') return rpc(db, 'rare_myth_mining_state', { p_telegram_id: user.id });
    if (action === 'rare-claim') return rpc(db, 'rare_myth_mining_claim', { p_telegram_id: user.id });
    throw new Error('INVALID_ACTION');
  },



  profile: async (db, user) => {
    if (!user.first_name) throw new Error('Usuário do Telegram não encontrado.');
    return rpc(db, 'upsert_telegram_player_profile', {
      p_telegram_id: user.id,
      p_first_name: user.first_name,
      p_last_name: user.last_name || null,
      p_username: user.username || null,
      p_photo_url: user.photo_url || null,
      // Suggests the Telegram language on the first login only; a manual choice locks it.
      p_language_code: user.language_code || null,
    });
  },

  /** Persists the player's manual interface language (pt, en, es, ru). */
  language: async (db, user, body) => {
    const language = String(body.language || '').toLowerCase();
    if (!['pt', 'en', 'es', 'ru', 'tr'].includes(language)) throw new Error('INVALID_LANGUAGE');
    const result = await rpc(db, 'set_player_language', { p_telegram_id: user.id, p_language: language });
    console.log('[LANGUAGE]', { telegramId: user.id, language });
    return result;
  },

  /**
   * NFT EXCLUSIVE rewards. Returns ONLY the authenticated player's own unit:
   * daily yield, available to claim and lifetime earned. The NFT Reward Pool
   * (balance, reserved, health, revenue) is backend-only and NEVER exposed here.
   */
  nft: async (db, user, body) => {
    const action = String(body.action || 'my');
    try {
      if (action === 'my') return await rpc(db, 'nft_my_reward', { p_telegram_id: user.id });
      if (action === 'claim') return await rpc(db, 'nft_claim_reward', { p_telegram_id: user.id });
      // Player-only list of the NFTs they own (no pool data is ever returned).
      if (action === 'mine') return await rpc(db, 'nft_my_rewards_json', { p_telegram_id: user.id });
      if (action === 'claim-one') {
        return await rpc(db, 'nft_claim_position', { p_telegram_id: user.id, p_position_id: String(body.positionId ?? '') });
      }
      // BUY NFT store: sale data only (price, tier yield, supply, status).
      if (action === 'shop') return await rpc(db, 'nft_shop_json', { p_telegram_id: user.id });
      if (action === 'buy-balance') {
        if (!isUuid(body.nftId)) throw new Error('INVALID_NFT');
        return await rpc(db, 'nft_buy_with_balance', {
          p_telegram_id: user.id,
          p_nft_id: body.nftId,
          p_idempotency_key: `nft:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'order') {
        if (!isUuid(body.nftId)) throw new Error('INVALID_NFT');
        return await rpc(db, 'nft_create_order', {
          p_telegram_id: user.id,
          p_nft_id: body.nftId,
          p_idempotency_key: `nft:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'verify-purchases') return await verifyNftPurchases(db, user);
    } catch (error) {

      // The real backend reason must be observable; the UI keeps a friendly text.
      console.error('[NFT]', { telegramId: user.id, action, error: error instanceof Error ? error.message : error });
      throw error;
    }
    throw new Error('Ação inválida.');
  },

  /**
   * NFT EXCLUSIVE HEROES store (1/1 supply each). Same rules as the NFT pets:
   * every purchase is resolved server-side and atomically, and the daily yield is
   * paid through the existing hero TON mining (with the same ROI cap).
   */
  'nft-hero': async (db, user, body) => {
    const action = String(body.action || 'shop');
    try {
      if (action === 'shop') return await rpc(db, 'nft_hero_shop_json', { p_telegram_id: user.id });
      if (action === 'mine') return await rpc(db, 'nft_hero_my_json', { p_telegram_id: user.id });
      if (action === 'buy-balance') {
        if (!isUuid(body.nftId)) throw new Error('INVALID_NFT');
        return await rpc(db, 'nft_hero_buy_with_balance', {
          p_telegram_id: user.id,
          p_nft_id: body.nftId,
          p_idempotency_key: `nfth:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'order') {
        if (!isUuid(body.nftId)) throw new Error('INVALID_NFT');
        return await rpc(db, 'nft_hero_create_order', {
          p_telegram_id: user.id,
          p_nft_id: body.nftId,
          p_idempotency_key: `nfth:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'verify-purchases') return await verifyNftHeroPurchases(db, user);
    } catch (error) {
      console.error('[NFT HERO]', { telegramId: user.id, action, error: error instanceof Error ? error.message : error });
      throw error;
    }
    throw new Error('Ação inválida.');
  },

  /**
   * MINAS DE TON: permanent passive TON investment. Every number (accrual, storage
   * cap, loyalty bonus, limits and visibility) is resolved server-side; the client
   * only renders the returned state.
   */
  'ton-mines': async (db, user, body) => {
    const action = String(body.action || 'state');
    try {
      if (action === 'state') return await rpc(db, 'ton_mines_state', { p_telegram_id: user.id });
      if (action === 'buy-balance') {
        if (!isUuid(body.mineId)) throw new Error('INVALID_MINE');
        return await rpc(db, 'ton_mine_buy_with_balance', {
          p_telegram_id: user.id,
          p_template_id: body.mineId,
          p_idempotency_key: `tonmine:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'order') {
        if (!isUuid(body.mineId)) throw new Error('INVALID_MINE');
        return await rpc(db, 'ton_mine_create_order', {
          p_telegram_id: user.id,
          p_template_id: body.mineId,
          p_idempotency_key: `tonmine:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'verify-purchases') return await verifyTonMinePurchases(db, user);
      if (action === 'claim') {
        const holdingId = body.holdingId ? String(body.holdingId) : null;
        if (holdingId && !isUuid(holdingId)) throw new Error('INVALID_MINE');
        return await rpc(db, 'ton_mine_claim', { p_telegram_id: user.id, p_holding_id: holdingId });
      }
    } catch (error) {
      console.error('[TON MINES]', { telegramId: user.id, action, error: error instanceof Error ? error.message : error });
      throw error;
    }
    throw new Error('Ação inválida.');
  },

  /**
   * 💎 TON STAKING: internal TON locked for a period, yielding a server-side
   * accrual. Rates, lock terms, limits, pool and auto-staking rules are all
   * resolved in Postgres; the client only renders the returned state.
   */
  'ton-staking': async (db, user, body) => {
    const action = String(body.action || 'state');
    try {
      if (action === 'state') return await rpc(db, 'ton_staking_state', { p_telegram_id: user.id });
      if (action === 'stake') {
        if (!isUuid(body.planId)) throw new Error('PLAN_NOT_FOUND');
        const amount = Number(body.amountTon);
        if (!Number.isFinite(amount) || amount <= 0) throw new Error('INVALID_AMOUNT');
        return await rpc(db, 'ton_staking_stake', {
          p_telegram_id: user.id,
          p_plan_id: body.planId,
          p_amount: amount,
          p_auto_compound: Boolean(body.autoCompound),
          p_request_id: String(body.idempotencyKey || crypto.randomUUID()),
        });
      }
      if (action === 'claim') {
        const positionId = body.positionId ? String(body.positionId) : null;
        if (positionId && !isUuid(positionId)) throw new Error('POSITION_NOT_FOUND');
        return await rpc(db, 'ton_staking_claim', {
          p_telegram_id: user.id,
          p_position_id: positionId,
          p_request_id: String(body.idempotencyKey || crypto.randomUUID()),
        });
      }
      if (action === 'unstake') {
        if (!isUuid(body.positionId)) throw new Error('POSITION_NOT_FOUND');
        return await rpc(db, 'ton_staking_unstake', {
          p_telegram_id: user.id,
          p_position_id: body.positionId,
          p_request_id: String(body.idempotencyKey || crypto.randomUUID()),
        });
      }
      if (action === 'preferences') {
        const planId = body.planId && isUuid(body.planId) ? String(body.planId) : null;
        return await rpc(db, 'ton_staking_set_preferences', {
          p_telegram_id: user.id,
          p_enabled: Boolean(body.enabled),
          p_percent: Number(body.percent) || 0,
          p_plan_id: planId,
          p_auto_compound: Boolean(body.autoCompound),
        });
      }
      if (action === 'position-compound') {
        if (!isUuid(body.positionId)) throw new Error('POSITION_NOT_FOUND');
        return await rpc(db, 'ton_staking_set_position_compound', {
          p_telegram_id: user.id,
          p_position_id: body.positionId,
          p_auto_compound: Boolean(body.autoCompound),
        });
      }
    } catch (error) {
      console.error('[TON STAKING]', { telegramId: user.id, action, error: error instanceof Error ? error.message : error });
      throw error;
    }
    throw new Error('Ação inválida.');
  },

  /** MYTHREON ARSENAL: the player's full equipment collection (normal + NFT 1/1). */
  arsenal: async (db, user) => await rpc(db, 'arsenal_json', { p_telegram_id: user.id }),


  /**
   * NFT EXCLUSIVE EQUIPMENT store (1/1 supply each). Class validation for weapons,
   * supply and payment are all resolved server-side; a sold unit never returns to sale.
   */
  'nft-equip': async (db, user, body) => {
    const action = String(body.action || 'shop');
    try {
      if (action === 'shop') return await rpc(db, 'nft_equipment_shop_json', { p_telegram_id: user.id });
      if (action === 'buy-balance') {
        if (!isUuid(body.nftId)) throw new Error('INVALID_NFT');
        return await rpc(db, 'nft_equipment_buy_with_balance', {
          p_telegram_id: user.id,
          p_nft_id: body.nftId,
          p_idempotency_key: `nfteq:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'order') {
        if (!isUuid(body.nftId)) throw new Error('INVALID_NFT');
        return await rpc(db, 'nft_equipment_create_order', {
          p_telegram_id: user.id,
          p_nft_id: body.nftId,
          p_idempotency_key: `nfteq:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
        });
      }
      if (action === 'verify-purchases') return await verifyNftEquipmentPurchases(db, user);
    } catch (error) {
      console.error('[NFT EQUIP]', { telegramId: user.id, action, error: error instanceof Error ? error.message : error });
      throw error;
    }
    throw new Error('Ação inválida.');
  },



  /**
   * NFT BREEDING (UNIQUE NFT x UNIQUE NFT -> SUB-NFT). Every rule (breed count owned by
   * the NFT instance, cooldown, cost tier, expiry/refund, egg minting) is enforced
   * server-side inside a single transaction per RPC.
   */
  breeding: async (db, user, body) => {
    const action = String(body.action || 'state');
    if (action === 'state') return rpc(db, 'nft_breeding_state', { p_telegram_id: user.id });
    if (action === 'search') {
      return rpc(db, 'nft_breeding_search_partner', { p_telegram_id: user.id, p_query: String(body.query || '').slice(0, 40) });
    }
    if (action === 'request') {
      if (!isUuid(body.myNftId) || !isUuid(body.partnerNftId)) throw new Error('INVALID_NFT');
      if (body.myNftId === body.partnerNftId) throw new Error('SAME_NFT_NOT_ALLOWED');
      return rpc(db, 'nft_breeding_request_create', {
        p_telegram_id: user.id,
        p_my_nft_id: body.myNftId,
        p_partner_nft_id: body.partnerNftId,
      });
    }
    if (action === 'respond') {
      if (!isUuid(body.requestId)) throw new Error('INVALID_REQUEST');
      return rpc(db, 'nft_breeding_respond', {
        p_telegram_id: user.id,
        p_request_id: body.requestId,
        p_accept: Boolean(body.accept),
      });
    }
    if (action === 'pay') {
      if (!isUuid(body.requestId)) throw new Error('INVALID_REQUEST');
      return rpc(db, 'nft_breeding_pay', {
        p_telegram_id: user.id,
        p_request_id: body.requestId,
        p_idempotency_key: `breed:${user.id}:${String(body.idempotencyKey || crypto.randomUUID())}`,
      });
    }
    if (action === 'claim-mining') return rpc(db, 'sub_nft_claim', { p_telegram_id: user.id });
    throw new Error('INVALID_ACTION');
  },

  /** PET EXPEDITIONS (AFK missions). Timers and rolls are server-side only. */
  /**
   * ANTI-FAKE / ANTI-MULTIACCOUNT. The device identity is a client-generated opaque
   * hash (no personal data). The decision (allowed/blocked) is ALWAYS taken here +
   * in the database, so patching the client JS can never grant access.
   */
  device: async (db, user, body) => {
    const action = String(body.action || 'check');
    const deviceHash = String(body.deviceHash || '').trim().slice(0, 128);
    if (deviceHash && !/^[a-f0-9]{32,128}$/i.test(deviceHash)) throw new Error('INVALID_DEVICE');
    if (action === 'review') {
      return await rpc(db, 'device_request_review', {
        p_telegram_id: user.id,
        p_device_hash: deviceHash,
        p_message: String(body.message || '').slice(0, 500),
      });
    }
    if (action !== 'check') throw new Error('INVALID_ACTION');
    // Only technical signals are persisted, and IP is stored hashed as a risk signal only —
    // it can never block a player by itself.
    const metadata: Record<string, unknown> = {
      uaHash: typeof body.uaHash === 'string' ? body.uaHash.slice(0, 64) : null,
      ipHash: typeof body.ipHash === 'string' ? body.ipHash.slice(0, 64) : null,
      tzOffset: Number.isFinite(Number(body.tzOffset)) ? Number(body.tzOffset) : null,
    };
    return await rpc(db, 'check_device_access', {
      p_telegram_id: user.id,
      p_device_hash: deviceHash,
      p_platform: String(body.platform || '').slice(0, 40) || null,
      p_metadata: metadata,
    });
  },

  expeditions: async (db, user, body) => {
    const action = String(body.action || 'state');
    if (action === 'state') return rpc(db, 'expedition_state', { p_telegram_id: user.id });
    if (action === 'start') {
      const petIds = Array.isArray(body.petIds) ? body.petIds.map(String) : [];
      if (!isUuid(body.missionId)) throw new Error('MISSION_NOT_FOUND');
      if (petIds.length !== 3 || petIds.some((id) => !isUuid(id))) throw new Error('TEAM_MUST_HAVE_3_PETS');
      if (new Set(petIds).size !== 3) throw new Error('DUPLICATED_PET');
      return rpc(db, 'expedition_start', { p_telegram_id: user.id, p_mission_id: body.missionId, p_pet_ids: petIds });
    }
    // Extra attempts are per (player, mission, game day): 5 via rewarded ads + 5 via FC, independent.
    if (action === 'ad-begin') {
      if (!isUuid(body.missionId)) throw new Error('MISSION_NOT_FOUND');
      return rpc(db, 'expedition_extra_ad_begin', { p_telegram_id: user.id, p_mission_id: body.missionId });
    }
    if (action === 'ad-claim') {
      if (!isUuid(body.viewId)) throw new Error('EXPEDITION_AD_VIEW_NOT_FOUND');
      return rpc(db, 'expedition_extra_ad_claim', { p_telegram_id: user.id, p_view_id: body.viewId });
    }
    if (action === 'buy-extra') {
      if (!isUuid(body.missionId)) throw new Error('MISSION_NOT_FOUND');
      const key = String(body.idempotencyKey || '').slice(0, 80);
      if (key.length < 8) throw new Error('INVALID_REQUEST_KEY');
      return rpc(db, 'expedition_extra_buy_fc', { p_telegram_id: user.id, p_mission_id: body.missionId, p_idempotency_key: key });
    }
    // AD BOOST: rewarded ad that cuts 20% of the ACTIVE expedition remaining time (max 5 per expedition).
    if (action === 'boost-ad-begin') {
      if (!isUuid(body.expeditionId)) throw new Error('EXPEDITION_NOT_FOUND');
      return rpc(db, 'expedition_boost_ad_begin', { p_telegram_id: user.id, p_expedition_id: body.expeditionId });
    }
    if (action === 'boost-ad-claim') {
      if (!isUuid(body.viewId)) throw new Error('EXPEDITION_AD_VIEW_NOT_FOUND');
      return rpc(db, 'expedition_boost_ad_claim', { p_telegram_id: user.id, p_view_id: body.viewId });
    }
    if (action === 'claim') {

      if (!isUuid(body.expeditionId)) throw new Error('EXPEDITION_NOT_FOUND');
      return attachHeroXp(db, user.id, 'EXPEDITION', await rpc(db, 'expedition_claim', { p_telegram_id: user.id, p_expedition_id: body.expeditionId }));
    }
    throw new Error('INVALID_ACTION');
  },

  /**
   * 🐾⚔️ FAMILIAR HUNT — LINEAR stage progression (fully separate from `expeditions`).
   * The stage, the entry payment, the fight and every reward roll are resolved server-side.
   * FC / internal TON are charged atomically with the hunt; an external TonConnect payment
   * only becomes a battle after the transfer is found on-chain (idempotent recovery).
   */
  'familiar-hunt': async (db, user, body) => {
    const action = String(body.action || 'state');
    if (action === 'state') return rpc(db, 'familiar_hunt_state', { p_telegram_id: user.id });
    if (action === 'start') {
      const petIds = Array.isArray(body.petIds) ? body.petIds.map(String) : [];
      if (petIds.length !== 3 || petIds.some((id) => !isUuid(id))) throw new Error('TEAM_MUST_HAVE_3_PETS');
      if (new Set(petIds).size !== 3) throw new Error('DUPLICATED_PET');
      const key = String(body.idempotencyKey || '').slice(0, 80) || null;
      // entry currency: FC or TON. Internal TON is used only when it covers 100% of the entry;
      // otherwise the DB returns a payment intent for the FULL amount (never a mixed payment).
      const currency = String(body.currency || 'fc').toLowerCase();
      if (currency !== 'fc' && currency !== 'ton') throw new Error('INVALID_CURRENCY');
      return rpc(db, 'familiar_hunt_start', {
        p_telegram_id: user.id, p_pet_ids: petIds, p_currency: currency, p_idempotency_key: key,
      });
    }
    if (action === 'verify-payments') return await verifyFamiliarHuntPayments(db, user);
    throw new Error('INVALID_ACTION');
  },

  /**
   * 🎡 GLOBAL MYSTERY ROULETTE. Every decision (reward, cycle spend, premium eligibility,
   * winner) is taken by the database inside a single locked transaction. The client can
   * only ask for a spin and render the result the backend already committed.
   */
  roulette: async (db, user, body) => {
    const action = String(body.action || 'state');
    if (action === 'state') return rpc(db, 'roulette_state', { p_telegram_id: user.id });
    if (action === 'spin') {
      const key = String(body.idempotencyKey || '').slice(0, 80);
      if (key.length < 8) throw new Error('INVALID_REQUEST_KEY');
      return rpc(db, 'roulette_spin', { p_telegram_id: user.id, p_idempotency_key: key });
    }
    if (action === 'verify-payments') return await verifyRoulettePayments(db, user);
    throw new Error('INVALID_ACTION');
  },

};





async function healthReport() {
  const report: Record<string, unknown> = {
    ok: false,
    app: 'MYTHREON',
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
    // BAN gate: a banned account reaches NO feature at all (including `device`), so the
    // ban applied in the admin bot is real and the client shows the BANNED card.
    {
      const ban = await db
        .from('game_players')
        .select('banned, ban_reason, banned_at')
        .eq('telegram_id', user.id)
        .maybeSingle();
      if (!ban.error && ban.data?.banned === true) {
        console.error('[ACCOUNT BANNED]', { feature, telegramId: user.id });
        return json({
          access: 'banned',
          code: 'ACCOUNT_BANNED',
          reason: ban.data.ban_reason ?? null,
          bannedAt: ban.data.banned_at ?? null,
          error: 'ACCOUNT_BANNED',
        }, 403);
      }
    }
    // ANTI-FAKE gate: a device that already reached the account limit can only talk to
    // the `device` route (status + review request). Every other feature is server-blocked.
    if (feature !== 'device') {
      const blocked = await db.rpc('device_access_blocked', { p_telegram_id: user.id });
      if (!blocked.error && blocked.data === true) {
        console.error('[ANTI FAKE BLOCKED]', { feature, telegramId: user.id });
        return json({ access: 'blocked', reason: 'MULTIPLE_ACCOUNTS_DETECTED', code: 'MULTI_ACCOUNT_LIMIT', error: 'MULTIPLE_ACCOUNTS_DETECTED' }, 403);
      }
    }

    // Real activity only: every authenticated call refreshes last_seen_at, throttled server-side
    // to once per minute. The client never sends a timestamp.
    void db.rpc('touch_player_activity', { p_telegram_id: user.id });
    const data = await handler(db, user, body);
    return json(data ?? null);
  } catch (error) {
    const dbError = error instanceof ForgeDbError ? error : null;
    const message = error instanceof Error ? error.message : 'Falha na requisição.';
    const safeMessage = isGatewayHtml(message) ? 'BACKEND_BUSY' : message.slice(0, 400);
    const status = dbError?.httpStatus ?? (safeMessage === 'BACKEND_BUSY' ? 503 : 400);
    console.error('[FORGE API ERROR]', {
      feature,
      action: body.action ?? null,
      telegramId: user.id,
      message: safeMessage,
      code: dbError?.code ?? null,
      details: dbError?.details ?? null,
      hint: dbError?.hint ?? null,
    });
    return json({ error: safeMessage, code: dbError?.code ?? null, details: dbError?.details ?? null, hint: dbError?.hint ?? null }, status);
  }
});

