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

/** Validates the signed Telegram Mini App initData server-side. Never trust client-sent ids. */
export async function validateTelegramInitData(initData: string): Promise<TelegramUser> {
  const token = Deno.env.get('TELEGRAM_BOT_TOKEN');
  if (!token) throw new Error('A autenticação do Telegram não está configurada.');
  if (!initData) throw new Error('Sessão do Telegram ausente. Abra o jogo pelo Telegram.');

  const params = new URLSearchParams(initData);
  const hash = params.get('hash') || '';
  params.delete('hash');
  const check = [...params.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');

  const secret = await hmac(encoder.encode('WebAppData'), token);
  const expected = toHex(await hmac(secret, check));
  const authDate = Number(params.get('auth_date'));
  if (!safeEqual(expected, hash.toLowerCase()) || !Number.isFinite(authDate) || Math.abs(Date.now() / 1000 - authDate) > 86_400) {
    throw new Error('Sessão do Telegram inválida ou expirada.');
  }

  const user = JSON.parse(params.get('user') || 'null') as TelegramUser | null;
  if (!user?.id) throw new Error('Usuário do Telegram não encontrado.');
  return user;
}

const isUuid = (value: unknown): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

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
  const fn = action === 'equip' ? 'equip_combat_hero'
    : action === 'team' ? 'set_boss_team'
    : action === 'claim' ? 'claim_boss_reward'
    : action === 'recruit' ? 'recruit_heroes'
    : action === 'get' ? 'get_boss_combat'
    : 'process_boss_combat';
  const args: Record<string, unknown> = { p_telegram_id: user.id };
  if (action === 'equip') {
    const slot = Number(body.slot);
    if (!Number.isInteger(slot) || slot < 1 || slot > 5) throw new Error('Slot inválido.');
    if (!isUuid(body.hero_id)) throw new Error('Herói inválido.');
    args.p_hero_id = body.hero_id;
    args.p_slot = slot;
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

async function handleWallet(db: Db, user: TelegramUser, body: Record<string, any>) {
  const hotWallet = String(Deno.env.get('TON_HOT_WALLET') || '').trim();
  if (hotWallet) {
    const configured = await db.from('wallet_settings').upsert({ key: 'ton_hot_wallet', value_text: hotWallet, updated_at: new Date().toISOString() });
    if (configured.error) throw new Error(configured.error.message);
  }
  const action = String(body.action || 'summary');
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
    return rpc(db, 'open_calendar_hero_chest', { p_telegram_id: user.id, p_inventory_item_id: body.inventoryItemId });
  }
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
  const token = Deno.env.get('TELEGRAM_BOT_TOKEN')!;
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);

  const feature = new URL(req.url).pathname.split('/').filter(Boolean).pop() || '';
  const handler = handlers[feature];
  if (!handler) return json({ error: `Recurso desconhecido: ${feature}` }, 404);

  let body: Record<string, any> = {};
  try {
    body = (await req.json()) as Record<string, any>;
  } catch {
    return json({ error: 'Corpo da requisição inválido.' }, 400);
  }

  let user: TelegramUser;
  try {
    user = await validateTelegramInitData(typeof body.initData === 'string' ? body.initData : '');
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Falha na autenticação do Telegram.';
    console.error('[FORGE API ERROR]', { feature, stage: 'auth', message });
    return json({ error: message, code: 'TELEGRAM_AUTH' }, 401);
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
