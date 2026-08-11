// MYTHREON :: Master Admin Bot (Telegram)
// Every operation re-validates the super admin Telegram ID server-side (bot + database).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { toFriendlyTonAddress } from '../_shared/tonAddress.ts';

const SUPER_ADMIN_ID = Number(Deno.env.get('TELEGRAM_SUPER_ADMIN_ID') || '8118569391');
// Admin bot token: dedicated variables first (current name: TELEGRAM_BOT_TOKEN_Admin), then legacy names.
const BOT_TOKEN = (Deno.env.get('TELEGRAM_BOT_TOKEN_Admin') || Deno.env.get('TELEGRAM_ADMIN_BOT_TOKEN') || Deno.env.get('TELEGRAM_BOT_TOKEN') || '').trim();

const WEBHOOK_SECRET = Deno.env.get('TELEGRAM_ADMIN_WEBHOOK_SECRET') || '';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const DENIED = '⛔ Acesso não autorizado.';

/** Single source of truth for authorization. Never trust ids coming from payload fields. */
function requireAdmin(fromId: number | undefined): number {
  if (!fromId || Number(fromId) !== SUPER_ADMIN_ID) throw new Error('unauthorized');
  return SUPER_ADMIN_ID;
}

async function tg(method: string, payload: Record<string, unknown>) {
  const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    console.error(`telegram ${method} failed [${res.status}]: ${await res.text()}`);
    return null;
  }
  return await res.json().catch(() => null);
}

async function rpc(fn: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data as any;
}

const kb = (rows: { t: string; d: string }[][]) => ({
  inline_keyboard: rows.map((row) => row.map((b) => ({ text: b.t, callback_data: b.d }))),
});
const nav = (back = 'home') => [{ t: '⬅️ Voltar', d: back }, { t: '🏠 Menu', d: 'home' }];
const fmt = (n: unknown) => Number(n ?? 0).toLocaleString('pt-BR');
const esc = (s: unknown) => String(s ?? '').replace(/[<>&]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c] as string));

const MAIN_MENU = kb([
  [{ t: '👥 USUÁRIOS', d: 'm:users' }, { t: '🦸 HERÓIS', d: 'm:heroes' }],
  [{ t: '🐲 PETS', d: 'm:pets' }, { t: '⚔️ PVP', d: 'm:pvp' }],
  [{ t: '🎟 PASSE', d: 'm:pass' }, { t: '💰 POOL', d: 'm:pool' }],
  [{ t: '🤝 CONVITES', d: 'm:invites' }, { t: '🏪 LOJA DE HERÓIS', d: 'm:shop' }],
  [{ t: '💳 CARTEIRA / FC', d: 'm:wallet' }, { t: '🎯 DAILY QUESTS', d: 'm:quests' }],
  [{ t: '👑 BOSS', d: 'm:boss' }, { t: '📢 ANÚNCIOS', d: 'm:ads' }],
  [{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }],
  [{ t: '⚙️ CONFIGURAÇÕES', d: 'm:settings' }, { t: '📜 AUDITORIA', d: 'm:audit' }],
  [{ t: '📊 STATUS', d: 'm:status' }, { t: '🔧 MANUTENÇÃO', d: 'm:maint' }],
  [{ t: '📣 BROADCAST', d: 'm:cast' }, { t: '💾 SNAPSHOT', d: 'do:snapshot' }],
]);

type Ctx = { chatId: number; adminId: number; messageId?: number };

async function send(ctx: Ctx, text: string, markup?: unknown) {
  await tg('sendMessage', { chat_id: ctx.chatId, text, parse_mode: 'HTML', reply_markup: markup });
}
async function edit(ctx: Ctx, text: string, markup?: unknown) {
  if (!ctx.messageId) return send(ctx, text, markup);
  await tg('editMessageText', { chat_id: ctx.chatId, message_id: ctx.messageId, text, parse_mode: 'HTML', reply_markup: markup });
}
// ---------------------------------------------------------------- conversation state (persisted: serverless-safe)
// Edge functions are stateless per request, so pending admin actions live in the database,
// keyed by (admin_telegram_id, chat_id) and expiring after 15 minutes.
const SESSION_TTL_MS = 15 * 60 * 1000;

type AdminSession = { action: string; step: string; context: Record<string, unknown> };

async function getSession(ctx: Ctx): Promise<AdminSession | null> {
  const { data, error } = await db
    .from('admin_bot_sessions')
    .select('action, step, context, expires_at')
    .eq('admin_telegram_id', ctx.adminId)
    .eq('chat_id', ctx.chatId)
    .maybeSingle();
  if (error) { console.error('session read failed:', error.message); return null; }
  if (!data) return null;
  if (new Date(data.expires_at).getTime() < Date.now()) { await clearSession(ctx); return null; }
  return { action: data.action, step: data.step || 'awaiting_input', context: (data.context || {}) as Record<string, unknown> };
}

async function setSession(ctx: Ctx, action: string, step = 'awaiting_input', context: Record<string, unknown> = {}) {
  const { error } = await db.from('admin_bot_sessions').upsert({
    admin_telegram_id: ctx.adminId,
    chat_id: ctx.chatId,
    action,
    step,
    context,
    updated_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + SESSION_TTL_MS).toISOString(),
  }, { onConflict: 'admin_telegram_id,chat_id' });
  if (error) console.error('session write failed:', error.message);
}

async function clearSession(ctx: Ctx) {
  const { error } = await db.from('admin_bot_sessions').delete()
    .eq('admin_telegram_id', ctx.adminId).eq('chat_id', ctx.chatId);
  if (error) console.error('session clear failed:', error.message);
}

/** Prompt: persists the pending action so the next plain text reply is executed. */
async function ask(ctx: Ctx, cmd: string, question: string) {
  await setSession(ctx, cmd, 'awaiting_input');
  await tg('sendMessage', {
    chat_id: ctx.chatId,
    text: `${question}\n\n<i>Responda com o valor nesta conversa. Toque em ❌ CANCELAR para sair.</i>`,
    parse_mode: 'HTML',
    reply_markup: kb([[{ t: '❌ CANCELAR', d: 'cancel' }]]),
  });
}

/** Accepts 20, 20.5 and 20,5 — returns NaN for anything else. */
function parseAmount(raw: string): number {
  const cleaned = String(raw).trim().replace(/\s/g, '').replace(',', '.');
  if (!/^-?\d+(\.\d+)?$/.test(cleaned)) return NaN;
  return Number(cleaned);
}


// ---------------------------------------------------------------- views
async function home(ctx: Ctx, editing = false) {
  const text = '🎮 <b>MYTHREON ADMIN</b>\nControle total do jogo. Escolha um módulo:';
  editing ? await edit(ctx, text, MAIN_MENU) : await send(ctx, text, MAIN_MENU);
}

async function playerCard(ctx: Ctx, ref: string) {
  const p = await rpc('admin_player_detail', { p_admin_id: ctx.adminId, p_ref: ref });
  const lines = [
    `👤 <b>${esc(p.name)}</b> ${p.username ? '@' + esc(p.username) : ''}`,
    `🆔 <code>${p.telegram_id}</code> · interno <code>${p.id}</code>`,
    `🪙 <b>${fmt(p.forge_coins)} FC</b> · 💎 ${fmt(p.ton_balance)} TON`,
    `🏅 ${esc(p.league)} · 🏆 ${fmt(p.trophies)} · 🎟 ${fmt(p.tickets)}`,
    `⚔️ ${fmt(p.wins)}V / ${fmt(p.losses)}D · 👑 ${fmt(p.boss_defeats)} chefes`,
    `🦸 ${fmt(p.heroes_count)} heróis · 🐲 ${fmt(p.pets_count)} pets · 🤝 ${fmt(p.referrals)} convites`,
    `👛 TON Wallet: <code>${esc(walletOut(p.wallet) ?? (p.wallet ? String(p.wallet) : 'NO TON WALLET CONNECTED'))}</code>${p.wallet && !walletOut(p.wallet) ? ' ⚠️ INVÁLIDA' : ''}`,
    `🔗 Wallet Connected: ${walletOut(p.wallet) ? 'YES' : 'NO'}${p.wallet_updated_at ? ' · atualizada ' + dt(p.wallet_updated_at) : ''}`,
    `📥 ${fmt(p.deposited_ton)} TON depositado · 📤 ${fmt(p.withdrawn_ton)} TON sacado`,
    `⭐ VIP: ${p.vip_until ? esc(String(p.vip_until).slice(0, 10)) : '—'} · 💠 Premium: ${p.premium_until ? esc(String(p.premium_until).slice(0, 10)) : '—'}`,
    `🚫 Banido: ${p.banned ? 'SIM — ' + esc(p.ban_reason) : 'não'}`,
    `📅 Criado ${String(p.created_at).slice(0, 10)} · 👁 ${String(p.last_seen_at).slice(0, 16).replace('T', ' ')}`,
  ];
  const u = p.telegram_id;
  const markup = kb([
    [{ t: '+ FC', d: `fc:add:${u}` }, { t: '- FC', d: `fc:remove:${u}` }, { t: 'DEFINIR FC', d: `fc:set:${u}` }],
    [{ t: '+ TON', d: `ton:add:${u}` }, { t: '- TON', d: `ton:remove:${u}` }, { t: 'DEFINIR TON', d: `ton:set:${u}` }],
    [{ t: '🏆 TROFÉUS', d: `st:trophies:${u}` }, { t: '🎟 TICKETS', d: `st:tickets:${u}` }],
    [{ t: '🦸 DAR HERÓI', d: `gh:${u}` }, { t: '🗑 REMOVER HERÓI', d: `rh:${u}` }],
    [{ t: '🐲 DAR PET', d: `gp:${u}` }, { t: '🗑 REMOVER PET', d: `rp:${u}` }],
    [{ t: '⭐ VIP', d: `vip:vip:${u}` }, { t: '💠 PREMIUM', d: `vip:premium:${u}` }],
    [{ t: p.banned ? '✅ DESBANIR' : '🚫 BANIR', d: `${p.banned ? 'unban' : 'ban'}:${u}` }, { t: '♻️ RESETAR', d: `reset:${u}` }],
    [{ t: '📜 HISTÓRICO', d: `hist:${u}` }, { t: '🤝 ÁRVORE', d: `tree:${u}` }],
    [{ t: '🎟 BATTLE PASS', d: `bpview:${u}` }, { t: '🔎 AUDIT DEPOSITS', d: `audit1:${u}` }],
    nav('m:users'),
  ]);
  if (p.avatar_url) await tg('sendPhoto', { chat_id: ctx.chatId, photo: p.avatar_url, caption: lines.join('\n'), parse_mode: 'HTML', reply_markup: markup });
  else await send(ctx, lines.join('\n'), markup);
}

// ---------------------------------------------------------------- player search (always live from the database)
const PASS_LABEL: Record<string, string> = { none: 'SEM PASSE', adventurer: 'AVENTUREIRO', legendary: 'LENDÁRIO' };
const ago = (iso: string) => {
  const min = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (min < 60) return `${min} min`;
  if (min < 1440) return `${Math.round(min / 60)} h`;
  return `${Math.round(min / 1440)} d`;
};

/** Lists players from `game_players` (the same table the Mini App uses). Never mock data. */
async function playerSearch(ctx: Ctx, query: string, offset = 0) {
  const d = await rpc('admin_search_players', { p_admin_id: ctx.adminId, p_query: query, p_limit: 10, p_offset: offset });
  const players = (d.players ?? []) as any[];
  console.log('[ADMIN USER SEARCH]', JSON.stringify({ query, searchType: query ? 'query' : 'latest', rowsFound: players.length, total: d.total, offset }));
  if (!players.length) {
    return send(ctx, `⚠️ Nenhum jogador encontrado para <code>${esc(query)}</code>.\nTente Telegram ID, @usuário, nome, carteira ou ID interno.`,
      kb([[{ t: '🔎 PROCURAR', d: 'ask:find' }], nav('m:users')]));
  }
  if (players.length === 1 && query) return playerCard(ctx, String(players[0].telegram_id));
  const lines = players.map((p, i) => [
    `<b>${offset + i + 1}. ${esc(p.name)}</b>${p.banned ? ' 🚫' : ''}`,
    `${p.username ? '@' + esc(p.username) : 'sem @usuário'} · <code>${p.telegram_id}</code>`,
    `🪙 ${fmt(p.forge_coins)} FC · 🎟 ${esc(PASS_LABEL[p.pass_tier] ?? p.pass_tier)} · 👁 ${ago(p.last_seen_at)}`,
  ].join('\n'));
  const rows: { t: string; d: string }[][] = [];
  for (let i = 0; i < players.length; i += 5) {
    rows.push(players.slice(i, i + 5).map((p, j) => ({ t: `${offset + i + j + 1}`, d: `find:${p.telegram_id}` })));
  }
  const pageNav: { t: string; d: string }[] = [];
  const token = query ? `q:${query}` : 'all';
  if (offset > 0) pageNav.push({ t: '⬅️ ANTERIOR', d: `pg:${Math.max(0, offset - 10)}:${token}`.slice(0, 60) });
  if (d.hasMore) pageNav.push({ t: 'PRÓXIMA ➡️', d: `pg:${offset + 10}:${token}`.slice(0, 60) });
  if (pageNav.length) rows.push(pageNav);
  rows.push([{ t: '🔎 PROCURAR', d: 'ask:find' }], nav('m:users'));
  return send(ctx, `👥 <b>JOGADORES</b> (${offset + 1}–${offset + players.length} de ${fmt(d.total)})\n\n${lines.join('\n\n')}\n\nToque no número para abrir o jogador.`, kb(rows));
}

// ---------------------------------------------------------------- battle pass (manual activation)
async function passCard(ctx: Ctx, ref: string) {
  const p = await rpc('admin_player_pass', { p_admin_id: ctx.adminId, p_ref: ref });
  console.log('[ADMIN PASS]', JSON.stringify({ targetUserId: p.user_id, telegramId: p.telegram_id, currentPass: p.tier, seasonId: p.season_id }));
  const text = [
    `🎟 <b>BATTLE PASS</b>`,
    `👤 ${esc(p.name)} ${p.username ? '@' + esc(p.username) : ''}`,
    `🆔 <code>${p.telegram_id}</code>`,
    '',
    `Current Pass: <b>${esc(PASS_LABEL[p.tier] ?? p.tier)}</b>`,
    `Season: <b>${esc(p.season_name)}</b>`,
    `Nível: <b>${p.level}</b>/${p.levels} · XP ${fmt(p.xp)}`,
    `Recompensas coletadas: ${fmt(p.claimed)} · compras TON: ${fmt(p.paid_orders)}`,
  ].join('\n');
  const u = p.telegram_id;
  return send(ctx, text, kb([
    [{ t: '🎟 ACTIVATE ADVENTURER', d: `bp:adventurer:${u}` }],
    [{ t: '👑 ACTIVATE LEGENDARY', d: `bp:legendary:${u}` }],
    [{ t: '❌ REMOVE PASS', d: `bp:none:${u}` }],
    [{ t: '📜 PASS HISTORY', d: 'bphist:1' }],
    [{ t: '👤 VER JOGADOR', d: `find:${u}` }],
    nav('m:pass'),
  ]));
}

async function passConfirm(ctx: Ctx, tier: string, ref: string) {
  const p = await rpc('admin_player_pass', { p_admin_id: ctx.adminId, p_ref: ref });
  const text = [
    tier === 'none' ? '⚠️ <b>REMOVER PASSE</b>' : '⚠️ <b>CONFIRMAR ATIVAÇÃO</b>',
    `User: ${p.username ? '@' + esc(p.username) : esc(p.name)}`,
    `Telegram ID: <code>${p.telegram_id}</code>`,
    '',
    `Current: <b>${esc(PASS_LABEL[p.tier] ?? p.tier)}</b>`,
    `New: <b>${esc(PASS_LABEL[tier] ?? tier)}</b>`,
    `Season: <b>${esc(p.season_name)}</b>`,
    '',
    'XP, nível e recompensas já coletadas são preservados.',
  ].join('\n');
  return send(ctx, text, kb([[{ t: '✅ CONFIRM', d: `bpgo:${tier}:${p.telegram_id}` }, { t: '❌ CANCEL', d: `bpview:${p.telegram_id}` }]]));
}

async function passApply(ctx: Ctx, tier: string, ref: string) {
  const r = await rpc('admin_set_player_pass', { p_admin_id: ctx.adminId, p_ref: ref, p_tier: tier, p_reason: 'ativação manual pelo bot admin' });
  const p = await rpc('admin_player_pass', { p_admin_id: ctx.adminId, p_ref: ref });
  console.log('[ADMIN PASS]', JSON.stringify({ targetUserId: r.user_id, telegramId: p.telegram_id, currentPass: r.old_tier, newPass: r.tier, seasonId: r.season_id }));
  const who = p.username ? '@' + esc(p.username) : esc(p.name);
  const msg = tier === 'none'
    ? `✅ Passe removido de ${who}.`
    : `✅ <b>${esc(PASS_LABEL[tier])} PASS</b> ativado para ${who}.\nNível ${r.level} · XP ${fmt(r.xp)} preservados.`;
  return send(ctx, `${msg}\nTemporada: ${esc(r.season_name)}`, kb([
    [{ t: '🎟 VER PASSE', d: `bpview:${p.telegram_id}` }, { t: '👤 JOGADOR', d: `find:${p.telegram_id}` }], nav('m:pass'),
  ]));
}

async function passHistory(ctx: Ctx) {
  const d = await rpc('admin_pass_history', { p_admin_id: ctx.adminId, p_limit: 10 });
  const rows = (d.entries ?? []) as any[];
  const list = rows.map((e) => `• ${e.username ? '@' + esc(e.username) : esc(String(e.telegram_id ?? '—'))}: ${esc(PASS_LABEL[e.old] ?? e.old ?? '—')} → <b>${esc(PASS_LABEL[e.new] ?? e.new ?? '—')}</b> · ${String(e.created_at).slice(0, 16).replace('T', ' ')}`).join('\n');
  return send(ctx, `📜 <b>PASS HISTORY</b>\n${list || 'Nenhuma alteração manual registrada.'}`, kb([nav('m:pass')]));
}



// ---------------------------------------------------------------- hero shop (menu driven)
const RARITY_LABEL: Record<string, string> = {
  common: 'COMUM', uncommon: 'INCOMUM', rare: 'RARO', epic: 'ÉPICO', legendary: 'LENDÁRIO',
};
const RARITY_ORDER = ['common', 'uncommon', 'rare', 'epic', 'legendary'];
const pct = (n: unknown) => Number(n ?? 0).toLocaleString('pt-BR', { maximumFractionDigits: 4 });

type HeroShopOverview = {
  config: { prices: Record<string, number>; odds: Record<string, number> };
  heroes_total: number; heroes_enabled: number; by_rarity: Record<string, number>;
};
async function heroShopConfig(ctx: Ctx): Promise<HeroShopOverview> {
  return await rpc('admin_hero_shop_overview', { p_admin_id: ctx.adminId }) as HeroShopOverview;
}

async function heroShopHub(ctx: Ctx) {
  const d = await heroShopConfig(ctx);
  const p = d.config.prices;
  const text = [
    '🏪 <b>LOJA DE HERÓIS</b>',
    '',
    `💰 1x <b>${fmt(p['1'])} FC</b> · 5x <b>${fmt(p['5'])} FC</b> · 10x <b>${fmt(p['10'])} FC</b>`,
    `🎲 ${RARITY_ORDER.map((r) => `${RARITY_LABEL[r]} ${pct(d.config.odds[r])}%`).join(' · ')}`,
    `🦸 ${fmt(d.heroes_enabled)} heróis ativos de ${fmt(d.heroes_total)}`,
    '',
    'Tudo aqui vale na hora no Mini App, sem deploy.',
  ].join('\n');
  return edit(ctx, text, kb([
    [{ t: '💰 PREÇOS DE RECRUTAMENTO', d: 'hs:prices' }],
    [{ t: '🎲 CHANCES DE INVOCAÇÃO', d: 'hs:odds' }],
    [{ t: '🦸 EDITAR HERÓIS', d: 'hs:list' }],
    [{ t: '🧬 DUPLICATE FUSE SETTINGS', d: 'hs:fusion' }],
    [{ t: '⚗️ RARITY FUSION SETTINGS', d: 'rf:home' }],
    [{ t: '➕ CRIAR HERÓI', d: 'ask:hero' }, { t: '🚫 ATIVAR/DESATIVAR', d: 'ask:herotoggle' }],
    [{ t: '📦 ITENS DA LOJA', d: 'hs:store' }],
    nav(),
  ]));
}

async function heroPricesView(ctx: Ctx) {
  const p = (await heroShopConfig(ctx)).config.prices;
  const text = [
    '🎯 <b>RECRUTAMENTO DE HERÓIS</b>', '', 'Preço atual:',
    `1x — <b>${fmt(p['1'])} FC</b>`, `5x — <b>${fmt(p['5'])} FC</b>`, `10x — <b>${fmt(p['10'])} FC</b>`,
    '', 'Cada pacote é independente, então dá para criar desconto no 5x e no 10x.',
  ].join('\n');
  return edit(ctx, text, kb([
    [{ t: '✏️ ALTERAR 1x', d: 'hp:1' }],
    [{ t: '✏️ ALTERAR 5x', d: 'hp:5' }],
    [{ t: '✏️ ALTERAR 10x', d: 'hp:10' }],
    [{ t: '🔄 RESET PADRÃO', d: 'hs:resetp' }],
    nav('m:shop'),
  ]));
}

async function heroOddsView(ctx: Ctx) {
  const d = await heroShopConfig(ctx);
  const o = d.config.odds;
  const total = RARITY_ORDER.reduce((sum, r) => sum + Number(o[r] ?? 0), 0);
  const text = [
    '🎲 <b>CHANCES DE INVOCAÇÃO</b>', '',
    ...RARITY_ORDER.map((r) => `${RARITY_LABEL[r]} — <b>${pct(o[r])}%</b> (${fmt(d.by_rarity[r] ?? 0)} heróis)`),
    '', `Total: <b>${pct(total)}%</b> — precisa ser exatamente 100%.`,
  ].join('\n');
  return edit(ctx, text, kb([
    [{ t: 'COMUM', d: 'ho:common' }, { t: 'INCOMUM', d: 'ho:uncommon' }],
    [{ t: 'RARO', d: 'ho:rare' }, { t: 'ÉPICO', d: 'ho:epic' }],
    [{ t: 'LENDÁRIO', d: 'ho:legendary' }],
    [{ t: '✏️ EDITAR TODAS', d: 'ask:hodds' }, { t: '🔄 RESET PADRÃO', d: 'hs:reseto' }],
    nav('m:shop'),
  ]));
}

/** DUPLICATE FUSE settings (same hero_key copies -> stars/ATK/HP/Power, rarity never changes). */
async function fusionView(ctx: Ctx) {
  const cfg = await rpc('hero_fusion_config', {}) as any;
  const max = Number(cfg.max_stars ?? 5);
  const rows: string[] = [];
  for (let star = 1; star <= max; star += 1) {
    rows.push(`★${star} — +${cfg.bonus_percent?.[star] ?? 0}% ATK/HP · ${fmt(Number(cfg.cost_fc?.[star] ?? 0))} FC · ${cfg.duplicates?.[star] ?? 1} cópia(s) · Lv.máx ${cfg.level_cap?.[star] ?? 20}`);
  }
  const text = ['🧬 <b>DUPLICATE FUSE SETTINGS</b>', '', 'Cópias do MESMO herói · a raridade nunca muda.', '', `Máximo de estrelas: <b>★${max}</b>`, `Lv. máx ★0: <b>${cfg.level_cap?.['0'] ?? 20}</b>`, '', ...rows,
    '', 'Os stats são recalculados a partir do multiplicador (nunca somam heróis).'].join('\n');
  return edit(ctx, text, kb([
    [{ t: '✏️ EDITAR CONFIG (JSON)', d: 'ask:fusion' }],
    [{ t: '⚗️ RARITY FUSION SETTINGS', d: 'rf:home' }],
    [{ t: '🔄 RESET PADRÃO', d: 'fusr:1' }],
    nav('m:shop'),
  ]));
}

const RF_SOURCES = ['common', 'uncommon', 'rare', 'epic'] as const;
const RF_LABEL: Record<string, string> = { common: 'COMMON', uncommon: 'UNCOMMON', rare: 'RARE', epic: 'EPIC', legendary: 'LEGENDARY' };

/** Rarity fusion (5 heroes -> next rarity): cost, odds, compensation and hero pool, all live. */
async function rarityFusionView(ctx: Ctx) {
  const d = await rpc('admin_rarity_fusion_overview', { p_admin_id: ctx.adminId }) as any;
  const cfg = d.config || {};
  const tiers = cfg.tiers || {};
  const rows = RF_SOURCES.filter((k) => tiers[k]).map((k) => {
    const t = tiers[k];
    return `${RF_LABEL[k]} → ${RF_LABEL[t.target] || String(t.target).toUpperCase()}\n   Custo: <b>${fmt(Number(t.cost_fc || 0))} FC</b> · Chance: <b>${pct(t.chance)}%</b> · Falha: <b>${fmt(Number(t.fragments || 0))} frag.</b>`;
  });
  const off = (d.pool || []).filter((h: any) => !h.enabled);
  const text = ['⚗️ <b>RARITY FUSION</b>', '',
    `Status: <b>${cfg.enabled === false ? '⛔ DESATIVADA' : '✅ ATIVA'}</b> · Heróis por fusão: <b>${cfg.required_heroes ?? 5}</b>`, '',
    ...rows, '',
    `📊 Tentativas: <b>${fmt(d.attempts)}</b> · Sucessos: <b>${fmt(d.successes)}</b> · FC queimado: <b>${fmt(d.fcBurned)}</b>`,
    `🚫 Fora do pool: <b>${off.length}</b>${off.length ? ' — ' + off.slice(0, 6).map((h: any) => esc(h.name)).join(', ') : ''}`,
    '', 'Lendário nunca funde em Ancestral.'].join('\n');
  return edit(ctx, text, kb([
    [{ t: '✏️ COMMON → UNCOMMON', d: 'ask:rfcommon' }],
    [{ t: '✏️ UNCOMMON → RARE', d: 'ask:rfuncommon' }],
    [{ t: '✏️ RARE → EPIC', d: 'ask:rfrare' }],
    [{ t: '✏️ EPIC → LEGENDARY', d: 'ask:rfepic' }],
    [{ t: cfg.enabled === false ? '✅ ENABLE FUSION' : '⛔ DISABLE FUSION', d: cfg.enabled === false ? 'rf:on' : 'rf:off' }],
    [{ t: '🦸 HERO POOL', d: 'ask:rfpool' }, { t: '🧾 AUDITORIA', d: 'rf:audit' }],
    nav('m:shop'),
  ]));
}

async function rarityFusionAudit(ctx: Ctx, ref?: string) {
  const rows = await rpc('admin_rarity_fusion_audit', { p_admin_id: ctx.adminId, p_limit: 10, p_ref: ref || null }) as any[];
  const text = ['🧾 <b>AUDITORIA — RARITY FUSION</b>', '', ...(rows.length ? rows.map((r) => [
    `👤 ${r.player ? '@' + esc(r.player) : esc(r.name || '—')} · <code>${r.telegramId}</code>`,
    `   ${RF_LABEL[r.sourceRarity] || r.sourceRarity} → ${RF_LABEL[r.targetRarity] || r.targetRarity} · ${r.heroes} heróis · ${fmt(Number(r.costFc || 0))} FC`,
    `   Chance ${pct(r.chance)}% · Roll ${r.roll} · <b>${r.success ? '✅ SUCESSO' : '❌ FALHA'}</b>`,
    `   ${r.success ? 'Herói: ' + esc(r.rewardHero || '—') : 'Fragmentos: ' + fmt(Number(r.fragments || 0))} · ${String(r.createdAt).slice(0, 16).replace('T', ' ')}`,
  ].join('\n')) : ['Nenhuma fusão registrada.'])].join('\n\n');
  return send(ctx, text, kb([[{ t: '🔎 FILTRAR JOGADOR', d: 'ask:rfaudit' }], [{ t: '⚗️ RARITY FUSION', d: 'rf:home' }], nav()]));
}

async function module(ctx: Ctx, name: string) {
  switch (name) {
    case 'users':
      return edit(ctx, '👥 <b>USUÁRIOS</b>\nBusque por Telegram ID, @usuário, nome, carteira ou ID interno.',
        kb([[{ t: '🔎 PROCURAR', d: 'ask:find' }], [{ t: '🆕 LATEST USERS', d: 'pg:0:all' }], [{ t: '📋 ALL USERS', d: 'pg:0:all' }], nav()]));
    case 'heroes':
    case 'shop':
      return heroShopHub(ctx);
    case 'herolist': {
      const d = await rpc('admin_list_heroes', { p_admin_id: ctx.adminId, p_limit: 20, p_offset: 0 });
      const list = d.heroes.map((h: any) => `• <code>${esc(h.hero_key)}</code> ${esc(h.name)} — ${esc(h.rarity)} ${h.enabled ? '✅' : '⛔'}${h.in_shop ? ' 🏪' : ''} ${h.price_fc ? fmt(h.price_fc) + ' FC' : ''}`).join('\n');
      return edit(ctx, `🦸 <b>HERÓIS</b> (${d.total})\n${list}\n\nO <code>price_fc</code> do herói é o preço avulso na loja, diferente do preço de recrutamento 1x/5x/10x.`,
        kb([[{ t: '✏️ CRIAR/EDITAR (JSON)', d: 'ask:hero' }], [{ t: '🚫 ATIVAR/DESATIVAR', d: 'ask:herotoggle' }], [{ t: '🦸 DAR A USUÁRIO', d: 'ask:granthero' }], nav('m:shop')]));
    }
    case 'store': {
      const d = await rpc('admin_list_heroes', { p_admin_id: ctx.adminId, p_limit: 30, p_offset: 0 });
      const shop = d.heroes.filter((h: any) => h.in_shop);
      return edit(ctx, `📦 <b>ITENS DA LOJA</b>\n${shop.length ? shop.map((h: any) => `• ${esc(h.name)} — ${fmt(h.price_fc)} FC / ${h.price_ton ?? '—'} TON · ordem ${h.sort_order}${h.featured ? ' ⭐' : ''}`).join('\n') : 'Nenhum item avulso na loja.'}\n\nCampos: <code>in_shop</code>, <code>price_fc</code>, <code>price_ton</code>, <code>discount_percent</code>, <code>stock</code>, <code>sort_order</code>, <code>featured</code>, <code>available_until</code>.`,
        kb([[{ t: '✏️ EDITAR ITEM (JSON)', d: 'ask:hero' }], nav('m:shop')]));
    }
    case 'pets': {
      const list = await rpc('admin_list_pets', { p_admin_id: ctx.adminId, p_limit: 30, p_offset: 0 });
      const cfg = await rpc('admin_pet_config', { p_admin_id: ctx.adminId });
      return edit(ctx, `🐲 <b>PETS</b> (${list.total})\n${list.pets.map((p: any) => `• <code>${esc(p.slug)}</code> ${esc(p.name)} — ${esc(p.category)} ${p.is_enabled ? '✅' : '⛔'}`).join('\n')}\n\n🥚 Ovos: ${cfg.eggs.length} · 🍖 Comidas: ${cfg.food.length} · 🧬 Estágios: ${cfg.tiers.length}`,
        kb([[{ t: '✏️ CRIAR/EDITAR PET', d: 'ask:pet' }],
            [{ t: '🍖 COMIDAS', d: 'view:foods' }, { t: '🥚 OVOS', d: 'view:eggs' }],
            [{ t: '🧬 EVOLUÇÃO', d: 'view:tiers' }, { t: '🧩 FRAGMENTOS', d: 'ask:givefrag' }],
            [{ t: '🐲 DAR PET', d: 'ask:grantpet' }, { t: '🎁 ENVIAR ITEM', d: 'ask:giveitem' }], nav()]));
    }
    case 'pvp': {
      const d = await rpc('admin_pvp_overview', { p_admin_id: ctx.adminId, p_top: 10 });
      return edit(ctx, `⚔️ <b>PVP</b>\nVitória <b>+${d.settings.win}</b> · Derrota <b>${d.settings.loss}</b> · Ticket custo ${d.settings.ticket_cost} (máx ${d.settings.ticket_max})\nBatalhas 24h: ${fmt(d.battles_today)}\n\n<b>TOP 10</b>\n${d.ranking.map((r: any, i: number) => `${i + 1}. ${esc(r.name)} — ${fmt(r.trophies)}🏆 (${esc(r.league)})`).join('\n') || '—'}`,
        kb([[{ t: '🏅 LIGAS', d: 'view:leagues' }, { t: '⚙️ VALORES', d: 'ask:pvpset' }],
            [{ t: '📈 TOP 50', d: 'rank:50' }, { t: '📈 TOP 100', d: 'rank:100' }],
            [{ t: '♻️ RESETAR TEMPORADA', d: 'confirm:pvpreset' }], nav()]));
    }
    case 'pass': {
      const d = await rpc('admin_pass_overview', { p_admin_id: ctx.adminId });
      const s = d.season || {};
      return edit(ctx, `🎟 <b>PASSE</b>\n${esc(s.name)} · ${String(s.start_at).slice(0, 10)} → ${String(s.end_at).slice(0, 10)}\nNíveis ${s.levels} · XP/nível ${s.xp_per_level}\nAventureiro ${s.adventurer_price_ton} TON (${fmt(d.owners.adventurer)} donos) · Lendário ${s.legendary_price_ton} TON (${fmt(d.owners.legendary)} donos)\nRecompensas cadastradas: ${d.rewards.length}`,
        kb([[{ t: '🔎 SELECIONAR USUÁRIO', d: 'ask:passuser' }],
            [{ t: '📜 PASS HISTORY', d: 'bphist:1' }],
            [{ t: '💰 PREÇOS/DATAS', d: 'ask:pass' }], [{ t: '🎁 RECOMPENSA', d: 'ask:passreward' }], nav()]));
    }
    case 'pool': {
      const d = await rpc('admin_pool_overview', { p_admin_id: ctx.adminId });
      const p = d.pool || {};
      const srcLabels: Record<string, string> = { deposit: 'Depósitos', battle_pass: 'Battle Pass', egg_purchase: 'Ovos', pet_purchase: 'Pets', premium_shop: 'Loja premium', event_purchase: 'Eventos', other: 'Outros' };
      const sources = Object.entries(d.sourcesToday || {}).map(([k, v]: [string, any]) =>
        `• ${esc(srcLabels[k] || k)}: ${fmt(v.poolTon)} TON (de ${fmt(v.grossTon)} TON)`).join('\n') || '• sem receita hoje';
      return edit(ctx, `💰 <b>COMMUNITY POOL</b>\n${esc(p.week_label)} · saldo <b>${fmt(p.balance_ton)} TON</b>\nTaxa de contribuição: <b>${d.contributionPercent}%</b>\nDistribuição: ${String(p.ends_at).slice(0, 16).replace('T', ' ')}\n\n💎 Receita hoje: ${fmt(d.revenueToday)} TON → pool ${fmt(d.poolToday)} TON\n📆 Receita do ciclo: ${fmt(d.revenuePeriod)} TON → pool ${fmt(d.poolPeriod)} TON\n\n<b>ORIGENS HOJE</b>\n${sources}\n\nParticipantes ${fmt(d.participants)} · Elegíveis ${fmt(d.eligible)}\nMínimo ${d.settings?.minimum_points} pts · ranking ${d.settings?.ranking_share_percent}% · sorteio ${d.settings?.lottery_share_percent}%`,
        kb([[{ t: '⚙️ CONTRIBUTION RATE', d: 'ask:poolrate' }],
            [{ t: '➕ VALOR', d: 'pool:add' }, { t: '➖ VALOR', d: 'pool:remove' }],
            [{ t: '⚙️ CONFIG', d: 'ask:poolset' }], [{ t: '🎉 DISTRIBUIR AGORA', d: 'confirm:pooldist' }],
            [{ t: '🚫 CANCELAR CICLO', d: 'confirm:poolcancel' }], nav()]));
    }

    case 'invites': {
      const s = await rpc('admin_get_settings', { p_admin_id: ctx.adminId, p_category: 'referral' });
      return edit(ctx, `🤝 <b>CONVITES</b>\n${s.settings.map((x: any) => `• ${esc(x.label)}: <b>${x.value}%</b>`).join('\n')}\n\nComissão paga somente em depósito TON confirmado, com idempotência.`,
        kb([[{ t: 'N1 %', d: 'ref:1' }, { t: 'N2 %', d: 'ref:2' }, { t: 'N3 %', d: 'ref:3' }],
            [{ t: '🌳 ÁRVORE DO USUÁRIO', d: 'ask:tree' }], [{ t: '✂️ REMOVER VÍNCULO', d: 'ask:unlink' }], nav()]));
    }
    case 'wallet': {
      const dep = await rpc('admin_list_transactions', { p_admin_id: ctx.adminId, p_kind: 'deposit', p_status: null, p_limit: 8 });
      const wd = await rpc('admin_list_withdrawals', { p_admin_id: ctx.adminId, p_status: null, p_limit: 10 });
      const rate = await rpc('current_ton_fc_rate', {});
      const row = (t: any) => `• <code>${String(t.id).slice(0, 8)}</code> ${esc(t.player)} — ${fmt(t.amount_ton)} TON [${esc(t.status)}]`;
      const viewButtons = (wd.items as any[]).slice(0, 6).map((w) => [{ t: `👁 ${w.short_id} · ${fmt(w.net_ton ?? w.amount_ton)} TON`, d: `wd:${w.id}` }]);
      const feePercent = Number(wd.feePercent ?? 0);
      return edit(ctx, `💳 <b>CARTEIRA / ECONOMIA</b>\n💱 Taxa atual: <b>1 TON = ${fmt(rate)} FC</b>\n(vale só para depósitos confirmados após a alteração)\n💸 <b>WITHDRAWAL FEE: ${feePercent}%</b>\n\n<b>Depósitos</b>\n${dep.items.map(row).join('\n') || '—'}\n\n💸 <b>SAQUES</b>\n${withdrawalLines(wd.items)}`,
        kb([[{ t: '✅ CONFIRMAR DEPÓSITO', d: 'ask:depok' }, { t: '❌ REJEITAR', d: 'ask:depno' }],
            ...viewButtons,
            [{ t: '🟡 PENDENTES', d: 'wdlist:pending' }, { t: '✅ PAGOS', d: 'wdlist:paid' }],
            [{ t: '💳 CONNECTED WALLETS', d: 'm:wallets' }],
            [{ t: '📢 PAYOUT ANNOUNCEMENTS', d: 'pa:menu' }],
            [{ t: '💱 TON → FC RATE', d: 'ask:tonrate' }, { t: `💸 WITHDRAWAL FEE (${feePercent}%)`, d: 'ask:wdfee' }],
            [{ t: '🪙 AJUSTAR FC', d: 'ask:find' }, { t: '🔎 AUDIT DEPOSITS', d: 'ask:auditdep' }], nav()]));
    }
    case 'wallets': {
      const d = await rpc('admin_connected_wallets', { p_admin_id: ctx.adminId, p_query: null, p_limit: 12 });
      return edit(ctx, connectedWalletsText(d.items), kb([[{ t: '🔎 PESQUISAR', d: 'ask:findwallet' }], nav('m:wallet')]));
    }

    case 'missions': {
      const d = await rpc('admin_missions_overview', { p_admin_id: ctx.adminId });
      return edit(ctx, `🎯 <b>MISSÕES</b>\n${d.missions.map((m: any) => `• <code>${esc(m.code)}</code> [${esc(m.scope)}] ${esc(m.title)} → ${fmt(m.reward_amount)} ${esc(m.reward_type)} ${m.enabled ? '✅' : '⛔'}`).join('\n') || '—'}`,
        kb([[{ t: '✏️ CRIAR/EDITAR', d: 'ask:mission' }], [{ t: '♻️ RESETAR DIÁRIAS', d: 'confirm:missdaily' }, { t: '♻️ SEMANAIS', d: 'confirm:missweekly' }], nav()]));
    }
    case 'channels': {
      const d = await rpc('admin_channels_overview', { p_admin_id: ctx.adminId });
      const list = (d.channels || []).map((c: any) => `• <b>${esc(c.title)}</b> ${c.enabled ? '✅' : '⛔'}\n   ${esc(c.url)}\n   ${fmt(c.rewardFc)} FC · resgates: ${fmt(c.claims)} · pago: ${fmt(c.paidFc)} FC`).join('\n') || '—';
      return edit(ctx, `📡 <b>CANAIS OFICIAIS</b>\nA recompensa é <b>única por Telegram ID + canal</b> (one-time). Não há verificação de participação: o jogador toca JOIN, volta e toca VERIFY.\n\n${list}`,
        kb([[{ t: '✏️ EDITAR CANAL', d: 'ask:channel' }], [{ t: '👤 CLAIMS DO JOGADOR', d: 'ask:chclaims' }], nav()]));
    }


    case 'quests': {
      const d = await rpc('admin_quests_overview', { p_admin_id: ctx.adminId });
      const b = d.bonus || {};
      const list = (d.quests || []).map((q: any) => `• <code>${esc(q.code)}</code> ${esc(q.title)}\n   evento <code>${esc(q.event_key)}</code> · meta ${q.target_amount} · ${fmt(q.reward_fc)} FC ${q.enabled ? '✅' : '⛔'}`).join('\n') || '—';
      const active = (d.quests || []).filter((q: any) => q.enabled).length;
      return edit(ctx, `🎯 <b>DAILY QUESTS</b>\nFuso do reset: <b>${esc(d.timezone)}</b> · dia atual ${esc(d.questDate)}\nQuests ativas: <b>${active}</b> · Resgates hoje: ${fmt(d.claimedToday)}\n\n${list}\n\n🎁 Baú extra (5/5): <b>${esc(b.name || 'Rare Chest')}</b> — <code>${esc(b.item_code || 'rare_chest')}</code> x${b.quantity ?? 1}\n\nO progresso é gravado só pelo servidor (login, pet, boss, PvP, ovos/baús).`,
        kb([[{ t: '✏️ CRIAR/EDITAR QUEST', d: 'ask:quest' }],
            [{ t: '🔄 REPAIR DEFAULT DAILY QUESTS', d: 'view:questrepair' }],
            [{ t: '🎁 BAÚ EXTRA 5/5', d: 'ask:questbonus' }, { t: '🕒 FUSO DO RESET', d: 'ask:questtz' }],
            [{ t: '🚫 ATIVAR/DESATIVAR', d: 'ask:questtoggle' }, { t: '♻️ RESETAR HOJE', d: 'confirm:questreset' }],
            [{ t: '📦 DIAGNÓSTICO DOS BAÚS', d: 'view:chests' }], nav()]));

    }
    case 'boss': {
      const d = await rpc('admin_boss_overview', { p_admin_id: ctx.adminId });
      const b = d.boss;
      const when = (v: any) => (v ? esc(new Date(v).toLocaleString('pt-BR')) : '—');
      return edit(ctx, `👹 <b>BOSS ATUAL</b>\nStatus: ${d.active ? '🟢 ATIVO' : '🔴 INATIVO'}\nBoss: <b>${b ? esc(b.name) : '—'}</b>\nHP: ${b ? `${fmt(d.currentHp ?? b.maxHp)} / ${fmt(d.maxHp || b.maxHp)}` : '—'}\nInício: ${when(b?.startsAt)}\nFim: ${when(b?.endsAt)}\nDuração: ${b ? `${Math.round((b.durationSeconds ?? 0) / 3600)}h` : '—'}\n🎁 Recompensa: ${b ? `${fmt(b.reward)} FC` : '—'}\nParticipantes: ${fmt(d.participants ?? 0)}\nDano total: ${fmt(d.totalDamage ?? 0)}\n\n<b>Chefes</b>\n${d.templates.map((t: any) => `• <code>${esc(t.code)}</code> ${esc(t.name)} NV${t.level} — ${fmt(t.maxHp)} HP ${t.active ? '🟢' : '⚪'}`).join('\n') || '—'}\n\n<b>Top dano</b>\n${d.top_damage.map((t: any) => `• ${esc(t.name)} — ${fmt(t.damage)}`).join('\n') || '—'}`,
        kb([[{ t: '🟢 ATIVAR BOSS', d: 'ask:bossspawn' }, { t: '🔴 DESATIVAR', d: 'confirm:bossend' }],
            [{ t: '🔄 RESETAR', d: 'confirm:bosshp' }, { t: '❤️ ALTERAR HP', d: 'ask:bosshpval' }],
            [{ t: '⏱ ALTERAR DURAÇÃO', d: 'ask:bossdur' }, { t: '🎁 RECOMPENSAS', d: 'ask:bossreward' }],
            [{ t: '👹 TROCAR BOSS', d: 'ask:bossspawn' }, { t: '✏️ CRIAR/EDITAR', d: 'ask:boss' }], nav()]));
    }
    case 'ads': {
      const d = await rpc('admin_ads_overview', { p_admin_id: ctx.adminId });
      return edit(ctx, `📢 <b>ANÚNCIOS</b>\n${d.providers.map((a: any) => `• <code>${esc(a.code)}</code> ${esc(a.name)} ${a.enabled ? '✅' : '⛔'} — limite ${a.daily_limit}/dia · ${fmt(a.reward_fc)} FC · cooldown ${a.cooldown_seconds}s`).join('\n')}`,
        kb([[{ t: '✏️ EDITAR PROVEDOR', d: 'ask:ads' }], nav()]));
    }
    case 'settings': {
      const d = await rpc('admin_get_settings', { p_admin_id: ctx.adminId, p_category: null });
      const body = d.settings.map((s: any) => `• <code>${esc(s.key)}</code> = <b>${esc(JSON.stringify(s.value))}</b>`).join('\n');
      return edit(ctx, `⚙️ <b>CONFIGURAÇÕES</b>\n${body.slice(0, 3400)}`,
        kb([[{ t: '✏️ EDITAR CHAVE', d: 'ask:setting' }], nav()]));
    }
    case 'audit': {
      const d = await rpc('admin_list_audit', { p_admin_id: ctx.adminId, p_limit: 15, p_offset: 0 });
      return edit(ctx, `📜 <b>AUDITORIA</b> (${fmt(d.total)})\n${d.events.map((e: any) => `• ${String(e.created_at).slice(5, 16).replace('T', ' ')} <b>${esc(e.action)}</b> ${esc(e.target_id || '')}\n   ${esc(JSON.stringify(e.old_value))} → ${esc(JSON.stringify(e.new_value))}`).join('\n').slice(0, 3500) || '—'}`,
        kb([[{ t: '🔄 ATUALIZAR', d: 'm:audit' }], nav()]));
    }
    case 'status': {
      const s = await rpc('admin_status_overview', { p_admin_id: ctx.adminId });
      return edit(ctx, `📊 <b>STATUS</b>\n👥 ${fmt(s.players_total)} jogadores · ativos 24h ${fmt(s.players_active_24h)} · novos ${fmt(s.players_new_24h)} · banidos ${fmt(s.players_banned)}\n🪙 ${fmt(s.fc_circulating)} FC circulando\n💎 ${fmt(s.ton_deposited)} TON depositado · ${fmt(s.ton_withdrawn)} sacado\n💰 Pool ${fmt(s.pool_balance)} TON\n⚔️ ${fmt(s.pvp_battles_24h)} batalhas 24h · 👑 ${fmt(s.boss_active)} chefes ativos\n🦸 ${fmt(s.heroes_total)} heróis · 🐲 ${fmt(s.pets_total)} pets · 🤝 ${fmt(s.referrals_total)} convites\n🔧 Manutenção: ${s.maintenance ? 'ATIVA' : 'off'} · settings v${s.settings_version}`,
        kb([[{ t: '🔄 ATUALIZAR', d: 'm:status' }], nav()]));
    }
    case 'maint': {
      const on = (await rpc('admin_get_settings', { p_admin_id: ctx.adminId, p_category: 'system' })).settings
        .find((s: any) => s.key === 'maintenance_mode')?.value === true;
      return edit(ctx, `🔧 <b>MANUTENÇÃO</b>\nStatus atual: <b>${on ? 'ATIVA' : 'desativada'}</b>\nCom manutenção ativa o Mini App mostra o aviso para todos, exceto o administrador mestre.`,
        kb([[{ t: on ? '✅ DESATIVAR' : '🔧 ATIVAR', d: `maint:${on ? 'off' : 'on'}` }], [{ t: '✏️ MENSAGEM', d: 'ask:maintmsg' }], nav()]));
    }
    case 'cast':
      return edit(ctx, '📣 <b>BROADCAST</b>\nEscolha o público e depois envie a mensagem.',
        kb([[{ t: 'TODOS', d: 'cast:all' }, { t: 'VIP', d: 'cast:vip' }], [{ t: 'PREMIUM', d: 'cast:premium' }, { t: 'ATIVOS 7d', d: 'cast:active' }], [{ t: 'TOP PVP', d: 'cast:top_pvp' }], nav()]));
    default:
      return home(ctx, true);
  }
}

// ---------------------------------------------------------------- withdrawals (financial module)
const WD_STATUS_ICON: Record<string, string> = {
  pending: '🟡', processing: '🔵', approved: '🔵', paid: '✅', completed: '✅', rejected: '❌', cancelled: '❌',
};

/** Wallets only accept the user-friendly mainnet form; raw "0:…" values are converted before display. */
const walletOut = (value: unknown) => toFriendlyTonAddress(value);

const dt = (value: unknown) => value ? new Date(String(value)).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : '—';

/** Summary list: never hides the amount, flags withdrawals whose destination wallet is unknown. */
function withdrawalLines(items: any[]) {
  if (!items?.length) return '—';
  const groups: Record<string, any[]> = {};
  for (const w of items) (groups[w.status] ??= []).push(w);
  return Object.entries(groups).map(([status, rows]) => {
    const head = `${WD_STATUS_ICON[status] || '•'} <b>${esc(status.toUpperCase())}</b>`;
    const body = rows.map((w) => `• <code>${esc(w.short_id)}</code> | ${w.username || w.player ? '@' + esc(w.username || w.player) : esc(String(w.telegram_id))} | ${fmt(w.amount_fc)} FC → <b>${Number(w.net_ton ?? w.amount_ton ?? 0).toFixed(3)} TON</b> (fee ${Number(w.fee_percent ?? 0)}%)${walletOut(w.wallet_address) ? '' : (w.wallet_address ? ' ⚠️ CARTEIRA INVÁLIDA' : ' ⚠️ SEM CARTEIRA')}`).join('\n');
    return `${head}\n${body}`;
  }).join('\n\n');
}

function connectedWalletsText(items: any[]) {
  const list = (items || []).map((w) => [
    `👤 ${w.player ? '@' + esc(w.player) : '—'}`,
    `🆔 <code>${esc(String(w.telegram_id))}</code> · interno <code>${esc(String(w.user_id))}</code>`,
    `👛 <code>${esc(walletOut(w.wallet_address) ?? w.wallet_address ?? '—')}</code>${walletOut(w.wallet_address) ? '' : ' ⚠️ INVÁLIDA'}`,
    `📅 ${dt(w.connected_at)}`,
  ].join('\n')).join('\n\n') || '—';
  return `💳 <b>CONNECTED WALLETS</b>\nCarteiras TON vinculadas aos jogadores.\n\n${list}`;
}

// ---------------------------------------------------------------- payout announcements (payments channel)
// The receipt must be posted by the MYTHREON game bot, so the game token comes first.
const GAME_BOT_TOKEN = (Deno.env.get('TELEGRAM_BOT_TOKEN_GAME') || Deno.env.get('TELEGRAM_GAME_BOT_TOKEN') || Deno.env.get('TELEGRAM_BOT_TOKEN') || BOT_TOKEN).trim();

async function tgAs(token: string, method: string, payload: Record<string, unknown>) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
  });
  const body = await res.json().catch(() => null) as any;
  if (!res.ok || !body?.ok) {
    const reason = body?.description || `http_${res.status}`;
    console.error(`payments channel ${method} failed: ${reason}`);
    return { ok: false as const, error: String(reason) };
  }
  return { ok: true as const, result: body.result };
}

const fmtEn = (n: unknown) => Number(n ?? 0).toLocaleString('en-US');
const shortHash = (h: string) => (h.length > 16 ? `${h.slice(0, 6)}...${h.slice(-6)}` : h);

function payoutMessage(p: any) {
  const hash = String(p.txHash || '');
  const date = new Date(String(p.paidAt)).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  const player = p.username ? `@${esc(p.username)}` : `Telegram ID: <code>${esc(String(p.telegramId ?? '—'))}</code>`;
  return [
    '✅ <b>FC Coins Withdrawal Successful!</b>', '',
    `🚀 Amount: <b>${fmtEn(p.amountFc)} FC</b>`, '',
    `💰 Gross Value: <b>${Number(p.grossTon ?? p.amountTon ?? 0).toFixed(3)} TON</b>`, '',
    `💸 Fee (${Number(p.feePercent ?? 0)}%): <b>${Number(p.feeTon ?? 0).toFixed(3)} TON</b>`, '',
    `✅ Received: <b>${Number(p.netTon ?? p.amountTon ?? 0).toFixed(3)} TON</b>`, '',
    `🔗 TxID: <a href="https://tonviewer.com/transaction/${encodeURIComponent(hash)}">${esc(shortHash(hash))}</a>`, '',
    `👤 Player: ${player}`, '',
    `🕒 Date: ${esc(date)}`,
  ].join('\n');
}

function payoutKeyboard(appLink?: string | null, newsUrl?: string | null) {
  const rows: { text: string; url: string }[][] = [];
  const app = String(appLink || 'https://t.me/Mythreonbot/app');
  if (app) rows.push([{ text: '🎮 PLAY GAME', url: app }]);
  if (newsUrl) rows.push([{ text: '📢 NEWS CHANNEL', url: String(newsUrl) }]);
  return rows.length ? { inline_keyboard: rows } : undefined;
}

/**
 * Publishes the receipt for one completed withdrawal. Fully idempotent: the database claim
 * refuses a second post for the same withdrawal and stores the channel message id.
 */
async function announcePayout(adminId: number, withdrawalId: string): Promise<{ status: 'sent' | 'skipped' | 'failed'; detail: string }> {
  let claim: any;
  try {
    claim = await rpc('admin_payout_announcement_claim', { p_admin_id: adminId, p_withdrawal_id: withdrawalId });
  } catch (error) {
    return { status: 'failed', detail: error instanceof Error ? error.message : 'claim_failed' };
  }
  if (claim?.skip) return { status: 'skipped', detail: String(claim.skip) };
  if (claim?.enabled === false) return { status: 'skipped', detail: 'channel_disabled' };
  const chatId = String(claim.channelId || '').trim();
  if (!chatId) {
    await rpc('admin_payout_announcement_record', { p_admin_id: adminId, p_withdrawal_id: withdrawalId, p_status: 'failed', p_error: 'channel_not_configured' });
    return { status: 'failed', detail: 'channel_not_configured' };
  }
  const sent = await tgAs(GAME_BOT_TOKEN, 'sendMessage', {
    chat_id: chatId, text: payoutMessage(claim), parse_mode: 'HTML',
    disable_web_page_preview: true, reply_markup: payoutKeyboard(claim.appLink, claim.newsUrl),
  });
  if (!sent.ok) {
    await rpc('admin_payout_announcement_record', { p_admin_id: adminId, p_withdrawal_id: withdrawalId, p_status: 'failed', p_channel_id: chatId, p_error: sent.error });
    return { status: 'failed', detail: sent.error };
  }
  await rpc('admin_payout_announcement_record', {
    p_admin_id: adminId, p_withdrawal_id: withdrawalId, p_status: 'sent',
    p_channel_id: chatId, p_message_id: Number(sent.result?.message_id) || null,
  });
  return { status: 'sent', detail: String(sent.result?.message_id ?? '') };
}

function payoutOverviewText(d: any) {
  const items = (d.items as any[] || []).map((i) => {
    const icon = i.status === 'sent' ? '✅' : i.status === 'failed' ? '⚠️' : '🕒';
    return `${icon} <code>${esc(String(i.withdrawal_id).slice(0, 8))}</code> | ${i.player ? '@' + esc(i.player) : '—'} | ${fmtEn(i.amount_fc)} FC · ${Number(i.amount_ton ?? 0).toFixed(6)} TON`
      + `\n   ${i.status === 'sent' ? `msg <code>${esc(String(i.message_id ?? '—'))}</code>` : esc(i.last_error || 'aguardando envio')}`;
  }).join('\n') || '—';
  return [
    '📢 <b>PAYOUT ANNOUNCEMENTS</b>', '',
    `Channel:\n<code>${esc(d.channelId || 'NÃO CONFIGURADO')}</code>`,
    `Status: <b>${d.channelId ? 'Connected' : 'Error'}</b>${d.enabled === false ? ' (envio desativado)' : ''}`,
    `Pendentes/falhos: <b>${(d.pending || []).length}</b>`, '',
    items,
  ].join('\n');
}

async function payoutMenu(ctx: Ctx, editing = true) {
  const d = await rpc('admin_payout_announcements', { p_admin_id: ctx.adminId, p_limit: 8 });
  const markup = kb([
    [{ t: '📄 LAST PAYOUTS', d: 'pa:list' }],
    [{ t: '♻️ RETRY FAILED', d: 'pa:retry' }],
    [{ t: '🧪 SEND TEST MESSAGE', d: 'pa:test' }],
    [{ t: '⚙️ CHANNEL SETTINGS', d: 'ask:pachat' }],
    nav('m:wallet'),
  ]);
  const text = payoutOverviewText(d);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function handlePayoutAnnouncements(ctx: Ctx, action: string) {
  if (action === 'list' || action === 'menu') return payoutMenu(ctx);
  if (action === 'test') {
    const d = await rpc('admin_payout_announcements', { p_admin_id: ctx.adminId, p_limit: 1 });
    const chatId = String(d.channelId || '').trim();
    if (!chatId) return send(ctx, '⚠️ Canal de pagamentos não configurado. Use CHANNEL SETTINGS.', kb([[{ t: '⚙️ CHANNEL SETTINGS', d: 'ask:pachat' }], nav('m:wallet')]));
    const member = await tgAs(GAME_BOT_TOKEN, 'getChat', { chat_id: chatId });
    if (!member.ok) return send(ctx, `❌ <b>Erro administrativo</b>\nO bot do jogo não acessa o canal <code>${esc(chatId)}</code>.\nMotivo: <code>${esc(member.error)}</code>\n\nAdicione o bot ao canal como administrador com permissão de postar.`, kb([[{ t: '📢 PAYOUT ANNOUNCEMENTS', d: 'pa:menu' }], nav('m:wallet')]));
    const res = await tgAs(GAME_BOT_TOKEN, 'sendMessage', { chat_id: chatId, text: '✅ <b>Mythreon Payments Channel Connected</b>', parse_mode: 'HTML' });
    return send(ctx, res.ok ? `✅ Mensagem de teste publicada no canal <code>${esc(chatId)}</code>.` : `❌ Falha ao publicar: <code>${esc(res.error)}</code>\nVerifique se o bot é administrador com permissão de envio.`,
      kb([[{ t: '📢 PAYOUT ANNOUNCEMENTS', d: 'pa:menu' }], nav('m:wallet')]));
  }
  if (action === 'retry') {
    const d = await rpc('admin_payout_announcements', { p_admin_id: ctx.adminId, p_limit: 30 });
    const pending: string[] = (d.pending as string[]) || [];
    if (!pending.length) return send(ctx, '✅ Nenhum comprovante pendente.', kb([[{ t: '📢 PAYOUT ANNOUNCEMENTS', d: 'pa:menu' }], nav('m:wallet')]));
    const results: string[] = [];
    for (const id of pending.slice(0, 10)) {
      const r = await announcePayout(ctx.adminId, id);
      results.push(`${r.status === 'sent' ? '✅' : r.status === 'skipped' ? '🚫' : '⚠️'} <code>${esc(id.slice(0, 8))}</code> ${esc(r.detail)}`);
    }
    return send(ctx, `♻️ <b>RETRY FAILED</b>\n\n${results.join('\n')}`, kb([[{ t: '📢 PAYOUT ANNOUNCEMENTS', d: 'pa:menu' }], nav('m:wallet')]));
  }
  return payoutMenu(ctx);
}

async function resolveWithdrawalId(ref: string): Promise<string | null> {
  const value = String(ref || '').trim();
  if (!value) return null;
  const { data } = await db.from('wallet_withdrawals').select('id').ilike('id', `${value}%`).limit(2);
  if (!data?.length || data.length > 1) return null;
  return data[0].id as string;
}


/** Full detail card: shows the destination wallet in full, never truncated. */
async function withdrawalCard(ctx: Ctx, id: string, editing = true) {
  const w = await rpc('admin_withdrawal_detail', { p_admin_id: ctx.adminId, p_withdrawal_id: id });
  const status = String(w.status);
  const done = ['paid', 'completed'].includes(status);
  const closed = done || ['rejected', 'cancelled'].includes(status);
  // Snapshot taken when the player requested the withdrawal — never re-read from the profile.
  const friendly = walletOut(w.walletAddress);
  const lines = [
    '💸 <b>WITHDRAWAL DETAILS</b>',
    '',
    `👤 Player: ${w.username ? '@' + esc(w.username) : '—'}`,
    `🆔 Telegram ID: <code>${esc(String(w.telegramId ?? '—'))}</code>`,
    `🔑 Withdrawal ID: <code>${esc(w.shortId)}</code>`,
    '',
    `💰 FC burned: <b>${fmt(w.amountFc)} FC</b>`,
    `💎 Gross: <b>${Number(w.grossTon ?? w.amountTon ?? 0).toFixed(3)} TON</b>`,
    `💸 Fee (${Number(w.feePercent ?? 0)}%): <b>-${Number(w.feeTon ?? 0).toFixed(3)} TON</b>`,
    `✅ Net to pay: <b>${Number(w.netTon ?? w.amountTon ?? 0).toFixed(3)} TON</b>`,
    '',
    '👛 <b>TON WALLET:</b>',
    friendly
      ? `<code>${esc(friendly)}</code>`
      : (w.walletAddress
        ? `⚠️ <b>INVALID TON WALLET</b>\nSaved value:\n<code>${esc(String(w.walletAddress))}</code>`
        : '⚠️ <b>WALLET NOT FOUND — MANUAL REVIEW REQUIRED</b>'),
    '',
    `📅 Requested:\n${dt(w.createdAt)}`,
    '',
    `${WD_STATUS_ICON[status] || '•'} Status:\n<b>${esc(status.toUpperCase())}</b>`,
  ];
  if (w.txHash) lines.push('', `🧾 TX:\n<code>${esc(w.txHash)}</code>`, `📅 Paid: ${dt(w.paidAt)}`);
  if (!friendly && w.currentWallet) lines.push('', `ℹ️ Carteira atual do jogador (não vinculada a este saque):\n<code>${esc(walletOut(w.currentWallet) ?? String(w.currentWallet))}</code>`);
  if (w.refundedAt) lines.push('', `↩️ FC devolvido em ${dt(w.refundedAt)}`);

  const rows: { t: string; d: string }[][] = [];
  if (friendly) rows.push([{ t: '📋 COPY WALLET', d: `wdcp:${w.id}` }]);
  if (w.telegramId) rows.push([{ t: '🔎 VIEW USER', d: `find:${w.telegramId}` }]);
  if (!closed && friendly) rows.push([{ t: '💎 PAY WITHDRAWAL', d: `wdpay:${w.id}` }]);
  if (!closed) rows.push([{ t: '✅ MARK AS PAID', d: `wdmk:${w.id}` }, { t: '❌ REJECT', d: `wdrj:${w.id}` }]);
  if (status === 'processing' || status === 'approved') rows.push([{ t: '↩️ PAGAMENTO FALHOU', d: `wdfail:${w.id}` }]);
  if (done && w.txHash) rows.push([{ t: '📢 PUBLICAR COMPROVANTE', d: `pasend:${w.id}` }]);
  rows.push([{ t: '⬅️ BACK', d: 'm:wallet' }, { t: '🏠 Menu', d: 'home' }]);
  const markup = kb(rows);
  return editing ? edit(ctx, lines.join('\n'), markup) : send(ctx, lines.join('\n'), markup);
}

async function handleWithdrawal(ctx: Ctx, head: string, id: string) {
  switch (head) {
    case 'wd':
      return withdrawalCard(ctx, id);
    case 'wdcp': {
      const w = await rpc('admin_withdrawal_detail', { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      const friendly = walletOut(w.walletAddress);
      if (!friendly) return send(ctx, w.walletAddress ? '⚠️ INVALID TON WALLET' : '⚠️ WALLET NOT FOUND — MANUAL REVIEW REQUIRED', kb([[{ t: '⬅️ BACK', d: `wd:${id}` }]]));
      // Separate message containing ONLY the user-friendly address: tap to copy inside Telegram.
      await tg('sendMessage', { chat_id: ctx.chatId, text: friendly });
      return;
    }
    case 'wdpay': {
      const w = await rpc('admin_withdrawal_detail', { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      if (['paid', 'completed'].includes(String(w.status))) throw new Error('already_processed');
      if (!walletOut(w.walletAddress)) throw new Error('wallet_missing');
      if (Number(w.amountTon) <= 0) throw new Error('invalid_amount');
      return edit(ctx, [
        '⚠️ <b>CONFIRM WITHDRAWAL</b>', '',
        `Player: ${w.username ? '@' + esc(w.username) : esc(String(w.telegramId))}`,
        `Amount: <b>${fmt(w.amountTon)} TON</b>`, '',
        'Destination:', `<code>${esc(walletOut(w.walletAddress)!)}</code>`, '',
        'O saque será bloqueado como <b>PROCESSING</b> para evitar pagamento duplicado. Ele só ficará <b>PAID</b> depois que você informar o hash da transação.',
      ].join('\n'), kb([[{ t: '✅ CONFIRM PAYMENT', d: `wdgo:${id}` }], [{ t: '❌ CANCEL', d: `wd:${id}` }]]));
    }
    case 'wdgo': {
      // pending -> processing (atomic lock in the database)
      const w = await rpc('admin_withdrawal_lock', { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      await send(ctx, [
        '🔵 <b>WITHDRAWAL PROCESSING</b>', '',
        `Envie <b>${fmt(w.amountTon)} TON</b> para:`,
        `<code>${esc(walletOut(w.walletAddress) ?? String(w.walletAddress ?? '—'))}</code>`, '',
        'Depois toque em <b>MARK AS PAID</b> e informe o hash da transação.\nSe o pagamento falhar, use <b>PAGAMENTO FALHOU</b> — o saque volta para PENDING.',
      ].join('\n'), kb([[{ t: '✅ MARK AS PAID', d: `wdmk:${id}` }], [{ t: '↩️ PAGAMENTO FALHOU', d: `wdfail:${id}` }], [{ t: '⬅️ BACK', d: `wd:${id}` }]]));
      return;
    }
    case 'wdmk':
      return ask(ctx, `wdhash|${id}`, 'Envie o <b>hash da transação TON</b> do pagamento.\nO saque só é marcado como PAGO com o hash.');
    case 'wdfail': {
      await rpc('admin_withdrawal_unlock', { p_admin_id: ctx.adminId, p_withdrawal_id: id, p_reason: 'pagamento não confirmado' });
      await send(ctx, '❌ <b>Payment failed</b>\nNo TON was confirmed as sent.\nWithdrawal remains pending.');
      return withdrawalCard(ctx, id, false);
    }
    case 'wdrj': {
      const w = await rpc('admin_withdrawal_detail', { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      return edit(ctx, `❌ <b>REJEITAR SAQUE</b>\n<code>${esc(w.shortId)}</code> · ${fmt(w.amountTon)} TON\n\nO jogador receberá <b>${fmt(w.amountFc)} FC</b> de volta (uma única vez).`,
        kb([[{ t: '✅ CONFIRMAR REJEIÇÃO', d: `wdrjgo:${id}` }], [{ t: '❌ CANCELAR', d: `wd:${id}` }]]));
    }
    case 'wdrjgo': {
      await rpc('admin_withdrawal_reject', { p_admin_id: ctx.adminId, p_withdrawal_id: id, p_reason: 'rejeitado pelo painel admin' });
      await send(ctx, '❌ Saque rejeitado e FC devolvido ao jogador.');
      return withdrawalCard(ctx, id, false);
    }
  }
}

// ---------------------------------------------------------------- prompts
const PROMPTS: Record<string, string> = {
  find: 'Envie Telegram ID, @usuário, nome, carteira ou ID interno.',
  pachat: 'Envie o <b>chat id</b> do canal de pagamentos (ex.: <code>-1004303374351</code>) ou @canalpublico.\nO bot do jogo precisa ser administrador do canal com permissão de envio.',
  passuser: 'Envie Telegram ID, @usuário, nome, carteira ou ID interno do jogador para gerenciar o Battle Pass.',
  channel: 'Envie: <code>news|community|payments {json}</code>\nEx.: <code>news {"url":"https://t.me/+abc","reward_fc":5000,"enabled":true}</code>\n\nA recompensa é one-time por Telegram ID; não é necessário chat id.',
  chclaims: 'Envie Telegram ID, @usuário, nome, carteira ou ID interno para ver os claims dos canais oficiais.',
  chreset: '⚠️ Reset manual de claim. Envie: <code>usuário channel_key CONFIRMAR</code>\nEx.: <code>8082515829 news CONFIRMAR</code>\nIsso libera o VERIFY novamente e fica registrado na auditoria.',
  hero: 'Envie: <code>hero_key {json}</code>\nEx.: <code>pyro_knight {"name":"Cavaleiro Ígneo","rarity":"epico","price_fc":50000,"in_shop":true,"sort_order":1}</code>',
  hodds: 'Envie as 5 chances na ordem <b>comum incomum raro épico lendário</b>.\nEx.: <code>62 25 10 2.7 0.3</code>\nO total precisa fechar 100%.',
  herotoggle: 'Envie o <code>hero_key</code> para ativar/desativar o herói.',
  fusion: 'Envie o JSON da fusão (merge parcial). Ex.:\n<code>{"max_stars":5,"bonus_percent":{"1":5,"2":5,"3":7,"4":8,"5":10},"cost_fc":{"1":5000,"2":15000,"3":35000,"4":75000,"5":150000},"duplicates":{"1":5,"2":5,"3":5,"4":5,"5":5},"level_cap":{"0":20,"1":20,"2":25,"3":25,"4":30,"5":35}}</code>',
  rfcommon: 'COMMON → UNCOMMON — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>10000 80 10</code>',
  rfuncommon: 'UNCOMMON → RARE — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>25000 60 20</code>',
  rfrare: 'RARE → EPIC — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>60000 40 40</code>',
  rfepic: 'EPIC → LEGENDARY — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>150000 20 80</code>',
  rfpool: 'Envie: <code>hero_key on|off</code> para incluir/excluir o herói do sorteio da Rarity Fusion.',
  rfaudit: 'Envie Telegram ID, @usuário, nome, carteira ou ID interno para filtrar a auditoria de fusões.',
  rates: 'Envie as chances em JSON (total 100). Ex.: <code>{"comum":45,"incomum":25,"raro":15,"epico":8,"lendario":5,"mitico":1.5,"ancestral":0.5}</code>',
  granthero: 'Envie: <code>usuário hero_key [nível]</code>',
  pet: 'Envie: <code>slug {json}</code> — ex.: <code>pyron {"name":"Pyron","category":"fire","is_enabled":true}</code>',
  food: 'Envie: <code>code {json}</code> — ex.: <code>racao {"name":"Ração","xp_value":50,"rarity":"comum","enabled":true}</code>',
  grantpet: 'Envie: <code>usuário slug [raridade] [nível]</code>',
  foodprice: 'Envie: <code>code preço_fc</code> — ex.: <code>pet_ration 1000</code>',
  eggprice: 'Envie: <code>slug preço_fc [preço_ton]</code> — ex.: <code>common-egg 25000</code> ou <code>epic-egg 0 3</code>',
  egg: 'Envie: <code>slug {json}</code> — ex.: <code>common-egg {"price_fc":25000,"is_purchasable":true,"rarity_rates":{"common":75,"uncommon":20,"rare":5}}</code>',
  giveitem: 'Envie: <code>usuário tipo item quantidade</code>\nTipos: <code>ovo</code> (slug do ovo), <code>comida</code> (code), <code>fragmento</code>.\nEx.: <code>8118569391 ovo epic-egg 3</code>',
  givefrag: 'Envie: <code>usuário quantidade</code> para conceder fragmentos universais.',
  pvpset: 'Envie: <code>chave valor</code>\nChaves: pvp_trophy_win, pvp_trophy_loss, pvp_ticket_cost, pvp_ticket_start, pvp_ticket_max, pvp_ticket_regen_minutes, pvp_ticket_price_fc, pvp_win_reward_fc',
  league: 'Envie: <code>code {json}</code> — ex.: <code>bronze_5 {"name":"Bronze V","min_trophies":0,"max_trophies":19}</code>',
  setting: 'Envie: <code>chave valor</code> (valor JSON ou texto simples).',
  quest: 'Envie: <code>code {json}</code> — ex.: <code>enter_arena {"title":"ENTER THE ARENA","description":"Complete one PvP battle.","event_key":"pvp_battle","target_amount":1,"reward_fc":10000,"icon":"pvp","sort_order":4,"enabled":true}</code>\nEventos válidos: <code>daily_login, pet_fed, boss_attack, pvp_battle, reward_opened, hero_obtained</code>.',
  questtoggle: 'Envie o <code>code</code> da quest para ativar/desativar.',
  questbonus: 'Envie: <code>item_code quantidade [nome]</code> — ex.: <code>rare_chest 1 Rare Chest</code>',
  questtz: 'Envie o fuso do reset diário — ex.: <code>America/Sao_Paulo</code>',
  mission: 'Envie: <code>code {json}</code> — ex.: <code>daily_pvp_wins {"title":"Vença 3 batalhas","target_amount":3,"reward_amount":4000,"enabled":true}</code>',
  boss: 'Envie: <code>code {json}</code> — ex.: <code>golem_ancestral {"name":"Golem","max_hp":50000,"attack":300,"reward_amount":9000}</code>',
  bossspawn: 'Envie o <code>code</code> do chefe para ativar (ex.: <code>golem_ancestral</code>).',
  bosshpval: 'Envie: <code>code hp</code> — ex.: <code>golem_ancestral 50000</code>',
  bossdur: 'Envie: <code>code horas</code> — ex.: <code>golem_ancestral 24</code>',
  bossreward: 'Envie: <code>code recompensa_fc</code> — ex.: <code>golem_ancestral 9000</code>',
  ads: 'Envie: <code>code {json}</code> — ex.: <code>adsgram {"enabled":true,"daily_limit":15,"reward_fc":800}</code>',
  pass: 'Envie JSON com os campos do passe: <code>{"adventurer_price_ton":15,"legendary_price_ton":30,"levels":30,"xp_per_level":1000}</code>',
  passreward: 'Envie: <code>reward_id {json}</code> — ex.: <code>uuid {"amount":5000,"title":"5.000 FC","enabled":true}</code>',
  poolset: 'Envie: <code>chave valor</code> — minimum_points, ranking_share_percent, lottery_share_percent, ranking_winner_limit, lottery_winner_count, season_days',
  poolrate: 'Envie a nova taxa de contribuição da Community Pool em % (0-100) — ex.: <code>15</code>. Vale apenas para transações TON processadas após a alteração.',

  tree: 'Envie o usuário para ver a árvore de convites.',
  unlink: 'Envie: <code>usuário motivo</code> para remover o vínculo de indicação.',
  depok: 'Envie o ID do depósito (pode ser o prefixo mostrado).',
  depno: 'Envie o ID do depósito a rejeitar.',
  wdpaid: 'Envie o ID do saque (prefixo aceito) para abrir os detalhes e pagar.',
  wdno: 'Envie o ID do saque para abrir os detalhes e rejeitar.',
  findwallet: 'Pesquise a carteira por Telegram ID, @usuário, nome, endereço TON ou ID interno.',

  tonrate: 'Envie a nova taxa: quantos FC vale 1 TON (ex.: <code>100000</code>). Vale apenas para depósitos confirmados depois da alteração.',
  wdfee: 'Envie a nova <b>WITHDRAWAL FEE</b> em % (0 a 50). Ex.: <code>10</code>. Vale só para saques criados depois da alteração.',
  auditdep: 'Envie o Telegram ID (ou @usuário) para auditar os depósitos.',
  maintmsg: 'Envie a nova mensagem de manutenção.',
};

// ---------------------------------------------------------------- actions
async function handleCallback(ctx: Ctx, data: string) {
  const [head, ...rest] = data.split(':');

  // Navigation always leaves any pending flow in a clean state.
  if (data === 'home') { await clearSession(ctx); return home(ctx, true); }
  if (data === 'cancel') { await clearSession(ctx); return send(ctx, '❌ Ação cancelada.', MAIN_MENU); }
  if (head === 'm') { await clearSession(ctx); return module(ctx, rest[0]); }
  if (head === 'ask') { const k = rest[0]; return ask(ctx, k, PROMPTS[k] || 'Envie o valor.'); }
  // withdrawals: every financial action is resolved by withdrawal_id, never by username.
  if (head === 'pa') { await clearSession(ctx); return handlePayoutAnnouncements(ctx, rest[0] || 'menu'); }
  if (head === 'pasend') {
    await clearSession(ctx);
    const r = await announcePayout(ctx.adminId, rest.join(':'));
    await send(ctx, r.status === 'sent' ? '📢 Comprovante publicado no canal de pagamentos.' : r.status === 'skipped' ? `🚫 Não publicado: <code>${esc(r.detail)}</code>` : `⚠️ Falha: <code>${esc(r.detail)}</code>`);
    return withdrawalCard(ctx, rest.join(':'), false);
  }
  if (['wd', 'wdcp', 'wdpay', 'wdgo', 'wdmk', 'wdfail', 'wdrj', 'wdrjgo'].includes(head)) {
    await clearSession(ctx);
    return handleWithdrawal(ctx, head, rest.join(':'));
  }
  if (head === 'wdlist') {
    const status = rest[0] === 'paid' ? 'paid' : rest[0];
    const d = await rpc('admin_list_withdrawals', { p_admin_id: ctx.adminId, p_status: status, p_limit: 12 });
    const buttons = (d.items as any[]).slice(0, 8).map((w) => [{ t: `👁 ${w.short_id} · ${fmt(w.amount_ton)} TON`, d: `wd:${w.id}` }]);
    return edit(ctx, `💸 <b>WITHDRAWALS</b> — ${esc(String(status).toUpperCase())}\n\n${withdrawalLines(d.items)}`,
      kb([...buttons, [{ t: '🟡 PENDENTES', d: 'wdlist:pending' }, { t: '✅ PAGOS', d: 'wdlist:paid' }], nav('m:wallet')]));
  }

  if (head === 'poolgo') {
    const mode = rest[0] === 'remove' ? 'remove' : 'add';
    const amount = parseAmount(rest[1]) * (mode === 'remove' ? -1 : 1);
    if (!Number.isFinite(amount) || amount === 0) return send(ctx, '⚠️ Valor inválido.', MAIN_MENU);
    await clearSession(ctx);
    const r = await rpc('admin_adjust_pool_balance', { p_amount: amount, p_reason: 'painel admin' });
    await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pool.adjust', p_target_type: 'pool', p_target_id: null, p_old: null, p_new: { amount }, p_reason: 'painel admin', p_context: { financial: true } });
    return send(ctx, `✅ Pool ajustada em <b>${amount} TON</b>.\n<code>${esc(JSON.stringify(r)).slice(0, 500)}</code>`,
      kb([[{ t: '💰 POOL', d: 'm:pool' }], nav()]));
  }

  if (head === 'find') return playerCard(ctx, rest.join(':') || '');
  if (head === 'pg') {
    const offset = Number(rest[0] || 0) || 0;
    const token = rest.slice(1).join(':');
    return playerSearch(ctx, token === 'all' ? '' : token.replace(/^q:/, ''), offset);
  }
  if (head === 'bpview') return passCard(ctx, rest[0]);
  if (head === 'bp') return passConfirm(ctx, rest[0], rest[1]);
  if (head === 'bpgo') return passApply(ctx, rest[0], rest[1]);
  if (head === 'bphist') return passHistory(ctx);
  if (head === 'do' && rest[0] === 'snapshot') {
    const s = await rpc('admin_create_snapshot', { p_admin_id: ctx.adminId, p_label: 'manual' });
    return send(ctx, `💾 Snapshot registrado: <code>${s.snapshot_id}</code>`, MAIN_MENU);
  }

  if (['fc', 'ton'].includes(head)) return ask(ctx, `bal|${head}|${rest[0]}|${rest[1]}`, `Envie o valor em ${head.toUpperCase()} (modo: ${rest[0]}).`);
  if (head === 'st') return ask(ctx, `stat|${rest[0]}|${rest[1]}`, `Envie: <code>modo valor</code> (add/remove/set) para ${rest[0]}.`);
  if (head === 'gh') return ask(ctx, `granthero|${rest[0]}`, 'Envie: <code>hero_key [nível]</code>');
  if (head === 'gp') return ask(ctx, `grantpet|${rest[0]}`, 'Envie: <code>slug [raridade] [nível]</code>');
  if (head === 'rh') return ask(ctx, 'removehero', 'Envie o ID do herói do jogador (uuid).');
  if (head === 'rp') return ask(ctx, 'removepet', 'Envie o ID do pet do jogador (uuid).');
  if (head === 'vip') return ask(ctx, `vip|${rest[0]}|${rest[1]}`, `Envie a quantidade de dias de ${rest[0].toUpperCase()} (0 remove).`);
  if (head === 'ban') return ask(ctx, `ban|${rest[0]}`, 'Envie o motivo do banimento (obrigatório).');
  if (head === 'unban') {
    const r = await rpc('admin_set_ban', { p_admin_id: ctx.adminId, p_ref: rest[0], p_banned: false, p_reason: 'desbanido pelo admin' });
    return send(ctx, `✅ Jogador desbanido (<code>${r.user_id}</code>).`, MAIN_MENU);
  }
  if (head === 'reset') return send(ctx, '⚠️ Tem certeza que deseja <b>RESETAR</b> esta conta? A ação apaga heróis, pets e saldos.',
    kb([[{ t: '✅ CONFIRMAR ALTERAÇÃO', d: `reset2:${rest[0]}` }, { t: '❌ Cancelar', d: 'home' }]]));
  if (head === 'reset2') return ask(ctx, `reset|${rest[0]}`, 'Envie o motivo do reset (obrigatório).');
  if (head === 'audit1') {
    // Deposit audit: TON in, FC credited, ledger cross-check. Read-only, never touches balances.
    const a = await rpc('audit_player_deposits', { p_telegram_id: Number(rest[0]) });
    const last = a.lastDeposit;
    const lines = [
      `🔎 <b>AUDIT DEPOSITS</b> — ${a.username ? '@' + esc(a.username) : esc(String(a.telegramId))}`,
      `FC balance: <b>${fmt(a.fcBalance)}</b>`,
      `Rate: 1 TON = <b>${fmt(a.rate)} FC</b>`,
      `Total TON deposited: <b>${fmt(a.totalTonDeposited)} TON</b>`,
      `Total FC credited from deposits: <b>${fmt(a.totalFcCreditedFromDeposits)}</b>`,
      `Ledger FC from deposits: <b>${fmt(a.ledgerFcFromDeposits)}</b> ${a.mismatch ? '⚠️ DIVERGÊNCIA' : '✅'}`,
      `Depósitos pendentes: ${fmt(a.pendingCount)}`,
      last ? `Último depósito: <b>${fmt(last.amountTon)} TON</b> → ${fmt(last.amountFc)} FC\nStatus: <b>${esc(String(last.status).toUpperCase())}</b>\nTX: <code>${esc(String(last.txHash || '—'))}</code>` : 'Último depósito: —',
    ];
    return send(ctx, lines.join('\n'), MAIN_MENU);
  }
  if (head === 'hist') {
    const h = await rpc('admin_player_history', { p_admin_id: ctx.adminId, p_ref: rest[0], p_limit: 15 });
    return send(ctx, `📜 <b>Histórico</b>\n${h.events.map((e: any) => `• ${String(e.at).slice(5, 16).replace('T', ' ')} ${esc(e.action)} — ${esc(JSON.stringify(e.old))} → ${esc(JSON.stringify(e.new))}`).join('\n') || '—'}`, MAIN_MENU);
  }
  if (head === 'tree') {
    const t = await rpc('admin_referral_tree', { p_admin_id: ctx.adminId, p_ref: rest[0] });
    const lines = t.levels.map((l: any) => `${'   '.repeat(l.level - 1)}└ N${l.level} ${esc(l.user.name)} ${l.user.username ? '@' + esc(l.user.username) : ''} — ${fmt(l.user.deposited_ton)} TON`);
    return send(ctx, `🌳 <b>Árvore de convites</b>\n${lines.join('\n') || '—'}\n\n💸 Comissão total: <b>${fmt(t.total_commission_fc)} FC</b>\n${t.commissions.map((c: any) => `• N${c.level} ${fmt(c.amount_fc)} FC de ${esc(c.from)}`).join('\n')}`, MAIN_MENU);
  }
  if (head === 'hs') {
    const view = rest[0];
    if (view === 'prices') return heroPricesView(ctx);
    if (view === 'odds') return heroOddsView(ctx);
    if (view === 'list') return module(ctx, 'herolist');
    if (view === 'store') return module(ctx, 'store');
    if (view === 'fusion') return fusionView(ctx);
    if (view === 'resetp' || view === 'reseto') {
      const scope = view === 'resetp' ? 'prices' : 'odds';
      return send(ctx, `⚠️ Restaurar o padrão de <b>${scope === 'prices' ? 'preços (25.000 / 125.000 / 250.000 FC)' : 'chances (62 / 25 / 10 / 2,7 / 0,3)'}</b>?`,
        kb([[{ t: '✅ CONFIRMAR', d: `hsr:${scope}` }, { t: '❌ CANCELAR', d: 'm:shop' }]]));
    }
    return heroShopHub(ctx);
  }
  if (head === 'rf') {
    const view = rest[0];
    if (view === 'audit') return rarityFusionAudit(ctx);
    if (view === 'on' || view === 'off') {
      await rpc('admin_set_rarity_fusion_enabled', { p_admin_id: ctx.adminId, p_enabled: view === 'on' });
      await send(ctx, view === 'on' ? '✅ Rarity Fusion ativada.' : '⛔ Rarity Fusion desativada.');
      return rarityFusionView(ctx);
    }
    return rarityFusionView(ctx);
  }
  if (head === 'fusr') {
    const r = await rpc('admin_set_fusion_config', { p_admin_id: ctx.adminId, p_patch: { max_stars: 5, bonus_percent: { '1': 5, '2': 5, '3': 7, '4': 8, '5': 10 }, cost_fc: { '1': 5000, '2': 15000, '3': 35000, '4': 75000, '5': 150000 }, duplicates: { '1': 5, '2': 5, '3': 5, '4': 5, '5': 5 }, level_cap: { '0': 20, '1': 20, '2': 25, '3': 25, '4': 30, '5': 35 } }, p_reason: 'reset padrão (bot)' });
    return send(ctx, `✅ Fusão restaurada ao padrão (★${r.max_stars}).`, kb([[{ t: '🧬 DUPLICATE FUSE SETTINGS', d: 'hs:fusion' }], nav('m:shop')]));
  }
  if (head === 'hsr') {
    const r = await rpc('admin_reset_hero_shop', { p_admin_id: ctx.adminId, p_scope: rest[0] });
    return send(ctx, `🔄 Padrão restaurado.\n1x ${fmt(r.prices['1'])} · 5x ${fmt(r.prices['5'])} · 10x ${fmt(r.prices['10'])} FC\n${RARITY_ORDER.map((k) => `${RARITY_LABEL[k]} ${pct(r.odds[k])}%`).join(' · ')}`,
      kb([[{ t: '🏪 LOJA DE HERÓIS', d: 'm:shop' }], nav()]));
  }
  if (head === 'hp') {
    const count = Number(rest[0]);
    const cfg = await heroShopConfig(ctx);
    return ask(ctx, `hprice|${count}`, `Preço atual do <b>${count}x</b>: <b>${fmt(cfg.config.prices[String(count)])} FC</b>\n\nEnvie o novo preço em FC. Ex.: <code>30000</code>`);
  }
  if (head === 'hpok') {
    const count = Number(rest[0]);
    const before = (await heroShopConfig(ctx)).config.prices[String(count)];
    const r = await rpc('admin_set_hero_recruit_price', { p_admin_id: ctx.adminId, p_count: count, p_price: Number(rest[1]), p_reason: 'painel admin (bot)' });
    return send(ctx, `✅ <b>${count}x</b> atualizado.\nAntes: ${fmt(before)} FC\nDepois: <b>${fmt(r.prices[String(count)])} FC</b>\n\nJá está valendo na loja do jogo.`,
      kb([[{ t: '💰 PREÇOS', d: 'hs:prices' }], nav('m:shop')]));
  }
  if (head === 'ho') {
    const rarity = rest[0];
    const cfg = await heroShopConfig(ctx);
    return ask(ctx, `hodd|${rarity}`, `Chance atual de <b>${RARITY_LABEL[rarity]}</b>: <b>${pct(cfg.config.odds[rarity])}%</b>\n\nEnvie a nova porcentagem (ex.: <code>60</code> ou <code>2.5</code>). O total das 5 raridades precisa fechar 100%.`);
  }
  if (head === 'hoc') {
    const rarity = rest[0];
    const cfg = await heroShopConfig(ctx);
    const rates: Record<string, number> = {};
    for (const k of RARITY_ORDER) rates[k] = Number(cfg.config.odds[k] ?? 0);
    rates[rarity] = Number(rest[1]);
    const r = await rpc('admin_set_hero_summon_rates', { p_admin_id: ctx.adminId, p_rates: rates, p_reason: 'painel admin (bot)' });
    return send(ctx, `✅ <b>${RARITY_LABEL[rarity]}</b>: ${pct(cfg.config.odds[rarity])}% → <b>${pct(r.odds[rarity])}%</b>\n\n${RARITY_ORDER.map((k) => `${RARITY_LABEL[k]} ${pct(r.odds[k])}%`).join(' · ')}`,
      kb([[{ t: '🎲 CHANCES', d: 'hs:odds' }], nav('m:shop')]));
  }
  if (head === 'ref') return ask(ctx, `ref|${rest[0]}`, `Envie a nova porcentagem do nível ${rest[0]} (0-100).`);
  if (head === 'pool') return ask(ctx, `pool|${rest[0]}`, `Envie o valor em TON para ${rest[0] === 'add' ? 'adicionar' : 'remover'}.`);
  if (head === 'rank') {
    const d = await rpc('admin_pvp_overview', { p_admin_id: ctx.adminId, p_top: Number(rest[0]) });
    return send(ctx, `📈 <b>TOP ${rest[0]}</b>\n${d.ranking.map((r: any, i: number) => `${i + 1}. ${esc(r.name)} — ${fmt(r.trophies)}🏆`).join('\n').slice(0, 3500)}`, MAIN_MENU);
  }
  if (head === 'view') {
    if (rest[0] === 'questrepair') {
      // Recreates/reactivates only the five default daily quests. Never duplicates, never touches player progress.
      const r = await rpc('admin_repair_daily_quests', { p_admin_id: ctx.adminId });
      return send(ctx, `🔄 <b>DAILY QUESTS REPARADAS</b>\nQuests ativas agora: <b>${fmt(r.activeDailyCount)}</b>\nO progresso dos jogadores foi preservado.`,
        kb([[{ t: '🎯 DAILY QUESTS', d: 'm:quests' }], nav()]));
    }
    if (rest[0] === 'chests') {

      const d = await rpc('admin_chest_diagnostics', { p_admin_id: ctx.adminId });
      const chests = (d.chests || []).map((c: any) => {
        const missing = c.missing || [];
        const status = !c.enabled ? '⛔ disabled' : missing.length ? `⚠️ NO ACTIVE HEROES (${missing.map(esc).join(', ')})` : '✅ configured';
        const rates = Object.entries(c.rates || {}).map(([k, v]) => `${esc(k)} ${v}%`).join(' · ');
        return `📦 <b>${esc(String(c.code).toUpperCase())}</b>\n   ${status}\n   ${rates || 'sem taxas'}`;
      }).join('\n') || '—';
      const pools = Object.entries(d.heroPools || {}).map(([k, v]) => `• ${esc(k)}: ${Number(v) > 0 ? fmt(Number(v)) : '⚠️ NO ACTIVE HEROES'}`).join('\n');
      return send(ctx, `📦 <b>DIAGNÓSTICO DOS BAÚS</b>\n${chests}\n\n🦸 <b>HERÓIS ATIVOS POR RARIDADE</b>\n${pools}`,
        kb([[{ t: '🎁 DEFINIR BAÚ 5/5', d: 'ask:questbonus' }], nav('m:quests')]));
    }
    const cfg = await rpc('admin_pet_config', { p_admin_id: ctx.adminId });
    if (rest[0] === 'eggs') return send(ctx, `🥚 <b>OVOS</b>\n${cfg.eggs.map((e: any) => `• ${esc(e.name)} <code>${e.slug ?? e.id}</code> — ${fmt(e.price_fc)} FC / ${e.price_ton ?? '—'} TON ${e.is_enabled ? '✅' : '⛔'}\n   ${esc(JSON.stringify(e.rarity_rates))}`).join('\n')}`,
      kb([[{ t: '💰 PREÇO DO OVO', d: 'ask:eggprice' }], [{ t: '✏️ EDITAR OVO (JSON)', d: 'ask:egg' }], nav('m:pets')]));
    if (rest[0] === 'foods') return send(ctx, `🍖 <b>COMIDAS</b>\n${cfg.food.map((f: any) => `• <code>${esc(f.code)}</code> ${esc(f.name)} — +${fmt(f.xp_value)} XP · ${fmt(f.price_fc ?? 0)} FC ${f.enabled ? '✅' : '⛔'}`).join('\n')}`,
      kb([[{ t: '💰 PREÇO DA COMIDA', d: 'ask:foodprice' }], [{ t: '✏️ CRIAR/EDITAR COMIDA', d: 'ask:food' }], nav('m:pets')]));
    if (rest[0] === 'tiers') return send(ctx, `🧬 <b>EVOLUÇÃO</b>\n${cfg.tiers.map((t: any) => `• Tier ${t.tier} ${esc(t.label)} — NV${t.required_level} · ${fmt(t.fc_cost)} FC · ${t.fragment_cost} frag · x${t.primary_multiplier} · novo buff ${Math.round(t.new_buff_chance * 100)}%`).join('\n')}`, MAIN_MENU);
    if (rest[0] === 'leagues') {
      const d = await rpc('admin_pvp_overview', { p_admin_id: ctx.adminId, p_top: 1 });
      return send(ctx, `🏅 <b>LIGAS</b>\n${d.leagues.map((l: any) => `• <code>${esc(l.code)}</code> ${esc(l.icon)} ${esc(l.name)} — ${l.min_trophies}–${l.max_trophies ?? '∞'} ${l.enabled ? '✅' : '⛔'}`).join('\n')}`,
        kb([[{ t: '✏️ EDITAR LIGA', d: 'ask:league' }], nav('m:pvp')]));
    }
  }
  if (head === 'maint') {
    await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: 'maintenance_mode', p_value: rest[0] === 'on', p_reason: 'painel admin' });
    return module(ctx, 'maint');
  }
  if (head === 'cast') return ask(ctx, `cast|${rest[0]}`, `Envie a mensagem para o público <b>${rest[0]}</b>.`);
  if (head === 'castgo') {
    const [seg, ...msg] = rest;
    const t = await rpc('admin_broadcast_targets', { p_admin_id: ctx.adminId, p_segment: seg, p_limit: 2000 });
    const text = decodeURIComponent(msg.join(':'));
    let ok = 0;
    for (const id of t.targets) { await tg('sendMessage', { chat_id: id, text }); ok += 1; }
    await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'broadcast.send', p_target_type: 'system', p_target_id: seg, p_old: null, p_new: { sent: ok }, p_reason: null, p_context: {} });
    return send(ctx, `📣 Enviado para ${ok} jogadores.`, MAIN_MENU);
  }

  if (head === 'confirm') {
    const map: Record<string, string> = {
      pvpreset: 'RESETAR a temporada de PvP (todos os troféus voltam a 0)',
      pooldist: 'DISTRIBUIR a pool comunitária agora',
      poolcancel: 'CANCELAR o ciclo atual da pool',
      bossend: 'ENCERRAR o chefe ativo',
      bosshp: 'RESETAR o HP dos chefes ativos',
      questreset: 'RESETAR as daily quests de hoje (progresso e resgates)',
      missdaily: 'RESETAR as missões diárias',
      missweekly: 'RESETAR as missões semanais',
    };
    return send(ctx, `⚠️ Tem certeza que deseja <b>${map[rest[0]]}</b>?`,
      kb([[{ t: '✅ CONFIRMAR ALTERAÇÃO', d: `run:${rest[0]}` }, { t: '❌ Cancelar', d: 'home' }]]));
  }
  if (head === 'run') {
    const key = rest[0];
    if (key === 'pvpreset') { const r = await rpc('admin_reset_pvp_season', { p_admin_id: ctx.adminId, p_reason: 'reset de temporada pelo admin' }); return send(ctx, `✅ Temporada resetada (${fmt(r.players_reset)} jogadores).`, MAIN_MENU); }
    if (key === 'pooldist') { await rpc('admin_create_snapshot', { p_admin_id: ctx.adminId, p_label: 'pre_pool_distribution' }); const r = await rpc('distribute_community_pool', { p_force: true }); await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pool.distribute', p_target_type: 'pool', p_target_id: null, p_old: null, p_new: r, p_reason: 'distribuição manual', p_context: { financial: true } }); return send(ctx, `✅ Pool distribuída.\n<code>${esc(JSON.stringify(r)).slice(0, 800)}</code>`, MAIN_MENU); }
    if (key === 'poolcancel') { const r = await rpc('admin_cancel_pool', {}); await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pool.cancel', p_target_type: 'pool', p_target_id: null, p_old: null, p_new: r, p_reason: null, p_context: {} }); return send(ctx, '✅ Ciclo cancelado.', MAIN_MENU); }
    if (key === 'bossend') { const r = await rpc('admin_boss_control', { p_admin_id: ctx.adminId, p_action: 'end', p_code: null, p_reason: 'encerrado pelo admin' }); return send(ctx, `✅ Chefes encerrados (${r.affected}).`, MAIN_MENU); }
    if (key === 'bosshp') { const r = await rpc('admin_boss_control', { p_admin_id: ctx.adminId, p_action: 'reset_hp', p_code: null, p_reason: 'reset de HP' }); return send(ctx, `✅ HP resetado (${r.affected}).`, MAIN_MENU); }
    if (key === 'questreset') { const r = await rpc('admin_reset_quests', { p_admin_id: ctx.adminId, p_reason: 'reset manual das daily quests' }); return send(ctx, `✅ Daily quests resetadas (${fmt(r.cleared)} registros).`, kb([[{ t: '🎯 DAILY QUESTS', d: 'm:quests' }], nav()])); }
    if (key.startsWith('miss')) { const scope = key === 'missdaily' ? 'daily' : 'weekly'; const r = await rpc('admin_reset_missions', { p_admin_id: ctx.adminId, p_scope: scope, p_reason: 'reset manual' }); return send(ctx, `✅ Missões ${scope} resetadas (${r.cleared}).`, MAIN_MENU); }
  }
  return send(ctx, 'Comando não reconhecido.', MAIN_MENU);
}

function parseValue(raw: string): unknown {
  try { return JSON.parse(raw); } catch { return raw; }
}

async function handlePrompt(ctx: Ctx, cmd: string, input: string) {
  const [key, ...args] = cmd.split('|');
  const text = input.trim();

  switch (key) {
    case 'find': return playerSearch(ctx, text, 0);
    case 'passuser': return passCard(ctx, text);
    case 'tree': return handleCallback(ctx, `tree:${text}`);
    case 'bal': {
      const [cur, mode, user] = args;
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value < 0) throw new Error('KEEP_SESSION::⚠️ Valor inválido. Envie um número maior ou igual a 0 (ex.: <code>1000</code> ou <code>20,5</code>).');
      const r = await rpc('admin_adjust_balance', { p_admin_id: ctx.adminId, p_ref: user, p_currency: cur, p_mode: mode, p_amount: value, p_reason: 'ajuste pelo painel' });
      return send(ctx, `✅ <b>${cur.toUpperCase()}</b>\nAnterior: ${fmt(r.old_value)}\nNovo: <b>${fmt(r.new_value)}</b>`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav()]));
    }

    case 'stat': {
      const [stat, user] = args;
      const [mode, amount] = text.split(/\s+/);
      const r = await rpc('admin_adjust_pvp_stat', { p_admin_id: ctx.adminId, p_ref: user, p_stat: stat, p_mode: mode, p_amount: Number(amount), p_reason: 'ajuste pelo painel' });
      return send(ctx, `✅ ${stat}: ${fmt(r.old_value)} → <b>${fmt(r.new_value)}</b>`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav()]));
    }
    case 'granthero': {
      const parts = text.split(/\s+/);
      const user = args[0] ?? parts.shift()!;
      const r = await rpc('admin_grant_hero', { p_admin_id: ctx.adminId, p_ref: user, p_hero_key: parts[0], p_level: Number(parts[1] || 1), p_reason: 'concedido pelo painel' });
      return send(ctx, `✅ Herói <b>${esc(r.name)}</b> concedido.\n<code>${r.hero_id}</code>`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav()]));
    }
    case 'grantpet': {
      const parts = text.split(/\s+/);
      const user = args[0] ?? parts.shift()!;
      const r = await rpc('admin_grant_pet', { p_admin_id: ctx.adminId, p_ref: user, p_pet_slug: parts[0], p_rarity: parts[1] || 'raro', p_level: Number(parts[2] || 1), p_reason: 'concedido pelo painel' });
      return send(ctx, `✅ Pet <b>${esc(r.pet)}</b> (${esc(r.rarity)}) concedido.`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav()]));
    }
    case 'rfcommon': case 'rfuncommon': case 'rfrare': case 'rfepic': {
      const source = cmd.slice(2);
      const parts = text.replace(/,/g, '.').split(/[\s;]+/).map((v) => Number(v.replace(/[^\d.]/g, '')));
      if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n)) || parts[1] < 0 || parts[1] > 100) {
        return send(ctx, '⚠️ Envie 3 números: <code>custo_fc chance fragmentos</code>. Ex.: <code>10000 80 10</code>', kb([[{ t: '⚗️ RARITY FUSION', d: 'rf:home' }], nav()]));
      }
      await rpc('admin_set_rarity_fusion_tier', { p_admin_id: ctx.adminId, p_source: source, p_cost: parts[0], p_chance: parts[1], p_fragments: Math.round(parts[2]) });
      await send(ctx, `✅ ${RF_LABEL[source]} atualizado — ${fmt(parts[0])} FC · ${pct(parts[1])}% · ${fmt(Math.round(parts[2]))} frag.`);
      return rarityFusionView(ctx);
    }
    case 'rfpool': {
      const [key, mode] = text.trim().split(/[\s;]+/);
      if (!key || !['on', 'off'].includes(String(mode || '').toLowerCase())) {
        return send(ctx, '⚠️ Envie: <code>hero_key on|off</code>', kb([[{ t: '⚗️ RARITY FUSION', d: 'rf:home' }], nav()]));
      }
      const r = await rpc('admin_set_hero_fusion_pool', { p_admin_id: ctx.adminId, p_hero_key: key, p_enabled: String(mode).toLowerCase() === 'on' }) as any;
      return send(ctx, `${r.enabled ? '✅' : '🚫'} <b>${esc(r.name)}</b> (${esc(r.rarity)}) ${r.enabled ? 'entra' : 'não entra'} no sorteio da Rarity Fusion.`, kb([[{ t: '⚗️ RARITY FUSION', d: 'rf:home' }], nav()]));
    }
    case 'rfaudit': return rarityFusionAudit(ctx, text.trim());
    case 'removehero': { const r = await rpc('admin_remove_hero', { p_admin_id: ctx.adminId, p_hero_id: text, p_reason: 'removido pelo painel' }); return send(ctx, `🗑 Herói ${esc(r.name)} removido.`, MAIN_MENU); }
    case 'removepet': { const r = await rpc('admin_remove_pet', { p_admin_id: ctx.adminId, p_player_pet_id: text, p_reason: 'removido pelo painel' }); return send(ctx, `🗑 Pet removido (<code>${r.player_pet_id}</code>).`, MAIN_MENU); }
    case 'vip': { const [tier, user] = args; const r = await rpc('admin_set_membership', { p_admin_id: ctx.adminId, p_ref: user, p_tier: tier, p_days: Number(text), p_reason: 'painel admin' }); return send(ctx, `✅ ${tier.toUpperCase()} até ${r.until ? String(r.until).slice(0, 10) : 'removido'}.`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav()])); }
    case 'ban': { const r = await rpc('admin_set_ban', { p_admin_id: ctx.adminId, p_ref: args[0], p_banned: true, p_reason: text }); return send(ctx, `🚫 Jogador banido (<code>${r.user_id}</code>).`, MAIN_MENU); }
    case 'reset': { const r = await rpc('admin_reset_account', { p_admin_id: ctx.adminId, p_ref: args[0], p_reason: text }); return send(ctx, `♻️ Conta resetada (<code>${r.user_id}</code>).`, MAIN_MENU); }
    case 'hero': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_hero', { p_admin_id: ctx.adminId, p_hero_key: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Herói salvo: <b>${esc(r.name)}</b> — ${esc(r.rarity)} ${r.enabled ? '✅' : '⛔'} ${r.price_fc ? fmt(r.price_fc) + ' FC' : ''}`, MAIN_MENU); }
    case 'hprice': {
      const count = Number(args[0]);
      const price = Math.round(Number(text.replace(/[^\d]/g, '')));
      if (!Number.isFinite(price) || price < 1) return send(ctx, '⚠️ Envie apenas números. Ex.: <code>30000</code>', kb([[{ t: '💰 PREÇOS', d: 'hs:prices' }], nav('m:shop')]));
      const cfg = await heroShopConfig(ctx);
      return send(ctx, `✏️ <b>ALTERAR PREÇO ${count}x</b>\n\nAntes: <b>${fmt(cfg.config.prices[String(count)])} FC</b>\nDepois: <b>${fmt(price)} FC</b>`,
        kb([[{ t: '✅ CONFIRMAR', d: `hpok:${count}:${price}` }, { t: '❌ CANCELAR', d: 'hs:prices' }]]));
    }
    case 'hodd': {
      const rarity = args[0];
      const value = Number(text.replace(',', '.').replace(/[^\d.]/g, ''));
      if (!Number.isFinite(value) || value < 0 || value > 100) return send(ctx, '⚠️ Porcentagem inválida (0 a 100).', kb([[{ t: '🎲 CHANCES', d: 'hs:odds' }], nav('m:shop')]));
      const cfg = await heroShopConfig(ctx);
      const total = RARITY_ORDER.reduce((sum, k) => sum + (k === rarity ? value : Number(cfg.config.odds[k] ?? 0)), 0);
      if (Math.abs(total - 100) > 0.001) {
        return send(ctx, `❌ Total inválido: <b>${pct(total)}%</b>\nA soma das 5 raridades precisa ser exatamente 100%.\n\nAjuste outra raridade ou use EDITAR TODAS.`,
          kb([[{ t: '✏️ EDITAR TODAS', d: 'ask:hodds' }], [{ t: '🎲 CHANCES', d: 'hs:odds' }], nav('m:shop')]));
      }
      return send(ctx, `✏️ <b>ALTERAR CHANCE — ${RARITY_LABEL[rarity]}</b>\n\nAntes: <b>${pct(cfg.config.odds[rarity])}%</b>\nDepois: <b>${pct(value)}%</b>\nTotal: <b>${pct(total)}%</b>`,
        kb([[{ t: '✅ CONFIRMAR', d: `hoc:${rarity}:${value}` }, { t: '❌ CANCELAR', d: 'hs:odds' }]]));
    }
    case 'hodds': {
      const parts = text.replace(/,/g, '.').split(/[\s;]+/).map(Number).filter((n) => Number.isFinite(n));
      if (parts.length !== 5) return send(ctx, '⚠️ Envie 5 números: comum incomum raro épico lendário.', kb([[{ t: '🎲 CHANCES', d: 'hs:odds' }], nav('m:shop')]));
      const total = parts.reduce((a, b) => a + b, 0);
      if (Math.abs(total - 100) > 0.001) {
        return send(ctx, `❌ Total inválido: <b>${pct(total)}%</b>\nA soma precisa ser exatamente 100%.`, kb([[{ t: '🎲 CHANCES', d: 'hs:odds' }], nav('m:shop')]));
      }
      const rates: Record<string, number> = {};
      RARITY_ORDER.forEach((k, i) => { rates[k] = parts[i]; });
      const before = (await heroShopConfig(ctx)).config.odds;
      const r = await rpc('admin_set_hero_summon_rates', { p_admin_id: ctx.adminId, p_rates: rates, p_reason: 'painel admin (bot)' });
      return send(ctx, `✅ Chances salvas.\n${RARITY_ORDER.map((k) => `${RARITY_LABEL[k]}: ${pct(before[k])}% → <b>${pct(r.odds[k])}%</b>`).join('\n')}`,
        kb([[{ t: '🎲 CHANCES', d: 'hs:odds' }], nav('m:shop')]));
    }
    case 'fusion': {
      const r = await rpc('admin_set_fusion_config', { p_admin_id: ctx.adminId, p_patch: JSON.parse(text), p_reason: 'painel admin (bot)' });
      return send(ctx, `✅ Fusão atualizada — máximo ★${r.max_stars}.`, kb([[{ t: '🧬 DUPLICATE FUSE SETTINGS', d: 'hs:fusion' }], nav('m:shop')]));
    }
    case 'herotoggle': {
      const heroKey = text.split(/\s+/)[0];
      const { data: hero } = await db.from('hero_catalog').select('hero_key,name,enabled').eq('hero_key', heroKey).maybeSingle();
      if (!hero) return send(ctx, '⚠️ Herói não encontrado.', kb([[{ t: '🦸 HERÓIS', d: 'hs:list' }], nav('m:shop')]));
      const r = await rpc('admin_upsert_hero', { p_admin_id: ctx.adminId, p_hero_key: heroKey, p_patch: { enabled: !hero.enabled }, p_reason: 'painel admin (bot)' });
      return send(ctx, `${r.enabled ? '✅ Ativado' : '⛔ Desativado'}: <b>${esc(r.name)}</b>`, kb([[{ t: '🦸 HERÓIS', d: 'hs:list' }], nav('m:shop')]));
    }
    case 'rates': {
      try {
        const r = await rpc('admin_set_hero_rarity_rates', { p_admin_id: ctx.adminId, p_rates: JSON.parse(text), p_normalize: false, p_reason: 'painel admin' });
        return send(ctx, `✅ Raridades salvas:\n<code>${esc(JSON.stringify(r.rates))}</code>`, MAIN_MENU);
      } catch (e) {
        if (String(e).includes('rates_must_total_100')) {
          return send(ctx, `⚠️ O total não é 100%. Deseja normalizar automaticamente?`,
            kb([[{ t: '✅ NORMALIZAR', d: `norm:${encodeURIComponent(text)}`.slice(0, 60) }, { t: '❌ Cancelar', d: 'home' }]]));
        }
        throw e;
      }
    }
    case 'pet': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_pet', { p_admin_id: ctx.adminId, p_slug: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Pet salvo: <b>${esc(r.name)}</b>`, MAIN_MENU); }
    case 'food': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_pet_food', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Comida salva: ${esc(r.name)} — ${r.xp_value} XP`, MAIN_MENU); }
    case 'foodprice': {
      const [code, price] = text.trim().split(/\s+/);
      const r = await rpc('admin_set_pet_food_price', { p_admin_id: ctx.adminId, p_code: code, p_price: Number(price) });
      return send(ctx, `✅ ${esc(r.name)} — novo preço <b>${fmt(r.price_fc)} FC</b> (+${fmt(r.xp_value)} XP)`, kb([[{ t: '🍖 COMIDAS', d: 'view:foods' }], nav('m:pets')]));
    }
    case 'eggprice': {
      const [slug, fc, ton] = text.trim().split(/\s+/);
      const patch: Record<string, unknown> = { price_fc: Number(fc) > 0 ? Number(fc) : null, updated_at: new Date().toISOString() };
      if (ton !== undefined) patch.price_ton = Number(ton) > 0 ? Number(ton) : null;
      const { data: egg, error } = await db.from('pet_eggs').update(patch).eq('slug', slug).select('*').maybeSingle();
      if (error) throw new Error(error.message);
      if (!egg) return send(ctx, '⚠️ Ovo não encontrado.', MAIN_MENU);
      await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pet_egg.price', p_target_type: 'pet_egg', p_target_id: slug, p_old: null, p_new: patch, p_reason: 'painel admin', p_context: { financial: true } });
      return send(ctx, `✅ ${esc(egg.name)} — ${fmt(egg.price_fc ?? 0)} FC / ${egg.price_ton ?? '—'} TON`, kb([[{ t: '🥚 OVOS', d: 'view:eggs' }], nav('m:pets')]));
    }
    case 'egg': {
      const i = text.indexOf(' ');
      const patch = JSON.parse(text.slice(i + 1));
      const { data: egg, error } = await db.from('pet_eggs').update({ ...patch, updated_at: new Date().toISOString() }).eq('slug', text.slice(0, i)).select('*').maybeSingle();
      if (error) throw new Error(error.message);
      if (!egg) return send(ctx, '⚠️ Ovo não encontrado.', MAIN_MENU);
      await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pet_egg.update', p_target_type: 'pet_egg', p_target_id: egg.slug, p_old: null, p_new: patch, p_reason: 'painel admin', p_context: {} });
      return send(ctx, `✅ Ovo salvo: <b>${esc(egg.name)}</b>`, kb([[{ t: '🥚 OVOS', d: 'view:eggs' }], nav('m:pets')]));
    }
    case 'giveitem': {
      const parts = text.trim().split(/\s+/);
      const user = parts.shift()!;
      const kind = (parts.shift() || '').toLowerCase();
      const ref = parts.shift() || '';
      const quantity = Number(parts.shift() || 1);
      const player = await rpc('admin_resolve_player', { p_ref: user });
      if (!player?.telegram_id) return send(ctx, '⚠️ Jogador não encontrado.', MAIN_MENU);
      if (kind.startsWith('ovo') || kind.startsWith('egg')) {
        const { data: egg } = await db.from('pet_eggs').select('id,name').or(`slug.eq.${ref},id.eq.${ref}`).maybeSingle();
        if (!egg) return send(ctx, '⚠️ Ovo não encontrado.', MAIN_MENU);
        await rpc('admin_grant_pet_item', { p_telegram_id: player.telegram_id, p_item_type: 'egg', p_item_id: egg.id, p_quantity: quantity });
        await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pet_item.grant', p_target_type: 'player', p_target_id: String(player.telegram_id), p_old: null, p_new: { egg: egg.name, quantity }, p_reason: 'painel admin', p_context: {} });
        return send(ctx, `🎁 <b>${quantity}x ${esc(egg.name)}</b> enviado para ${esc(String(player.telegram_id))}.`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav('m:pets')]));
      }
      if (kind.startsWith('comida') || kind.startsWith('food')) {
        const r = await rpc('admin_grant_pet_food', { p_telegram_id: player.telegram_id, p_code: ref, p_quantity: quantity });
        await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pet_food.grant', p_target_type: 'player', p_target_id: String(player.telegram_id), p_old: null, p_new: { food: ref, quantity }, p_reason: 'painel admin', p_context: {} });
        return send(ctx, `🎁 <b>${quantity}x ${esc(ref)}</b> enviado.\n<code>${esc(JSON.stringify(r?.inventory ?? {})).slice(0, 300)}</code>`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav('m:pets')]));
      }
      if (kind.startsWith('frag')) {
        await rpc('admin_grant_pet_item', { p_telegram_id: player.telegram_id, p_item_type: 'universal_fragment', p_item_id: null, p_quantity: quantity });
        return send(ctx, `🧩 <b>${quantity}</b> fragmentos universais enviados.`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav('m:pets')]));
      }
      return send(ctx, '⚠️ Tipo inválido. Use ovo, comida ou fragmento.', MAIN_MENU);
    }
    case 'givefrag': {
      const [user, quantity] = text.trim().split(/\s+/);
      const player = await rpc('admin_resolve_player', { p_ref: user });
      if (!player?.telegram_id) return send(ctx, '⚠️ Jogador não encontrado.', MAIN_MENU);
      await rpc('admin_grant_pet_item', { p_telegram_id: player.telegram_id, p_item_type: 'universal_fragment', p_item_id: null, p_quantity: Number(quantity || 1) });
      await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pet_fragment.grant', p_target_type: 'player', p_target_id: String(player.telegram_id), p_old: null, p_new: { quantity: Number(quantity || 1) }, p_reason: 'painel admin', p_context: {} });
      return send(ctx, `🧩 <b>${fmt(Number(quantity || 1))}</b> fragmentos universais enviados.`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav('m:pets')]));
    }
    case 'league': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_league', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Liga salva: ${esc(r.name)} (${r.min_trophies}–${r.max_trophies ?? '∞'})`, MAIN_MENU); }
    case 'channel': {
      const i = text.indexOf(' ');
      if (i < 0) return send(ctx, '⚠️ Envie a chave do canal e o JSON.', kb([[{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }], nav()]));
      const r = await rpc('admin_update_channel', { p_admin_id: ctx.adminId, p_channel_key: text.slice(0, i).trim(), p_patch: JSON.parse(text.slice(i + 1)) });
      return send(ctx, `✅ <b>${esc(r.title)}</b> ${r.enabled ? '✅' : '⛔'}\nchat: <code>${esc(r.chatRef || 'NÃO CONFIGURADO')}</code> · ${fmt(r.rewardFc)} FC`, kb([[{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }], nav()]));
    }
    case 'chclaims': {
      const d = await rpc('admin_player_channel_claims', { p_admin_id: ctx.adminId, p_player: text.trim() });
      const rows = (d.channels || []).map((c: any) => `• <b>${esc(c.title)}</b> — ${c.claimed ? `✅ CLAIMED (+${fmt(c.rewardReceived || c.rewardFc)} FC)` : '⛔ NOT CLAIMED'}`).join('\n') || '—';
      return send(ctx, `📡 <b>CLAIMS DOS CANAIS</b>\n${esc(d.name || d.username || '')} · <code>${d.telegramId}</code>\n\n${rows}`,
        kb([[{ t: '♻️ RESET MANUAL', d: 'ask:chreset' }], [{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }], nav()]));
    }
    case 'chreset': {
      const [ref, key, confirmWord] = text.trim().split(/\s+/);
      if (!ref || !key) return send(ctx, '⚠️ Envie: <code>usuário channel_key CONFIRMAR</code>', kb([[{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }], nav()]));
      if (String(confirmWord || '').toUpperCase() !== 'CONFIRMAR') {
        return send(ctx, `⚠️ <b>Confirmação obrigatória.</b>\nEsse reset permite que o jogador receba a recompensa de <code>${esc(key)}</code> novamente.\nReenvie: <code>${esc(ref)} ${esc(key)} CONFIRMAR</code>`,
          kb([[{ t: '♻️ TENTAR NOVAMENTE', d: 'ask:chreset' }], [{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }], nav()]));
      }
      const d = await rpc('admin_reset_channel_claim', { p_admin_id: ctx.adminId, p_player: ref, p_channel_key: key });
      const rows = (d.channels || []).map((c: any) => `• <b>${esc(c.title)}</b> — ${c.claimed ? '✅ CLAIMED' : '⛔ NOT CLAIMED'}`).join('\n') || '—';
      return send(ctx, `♻️ Claim de <code>${esc(key)}</code> resetado (${fmt(d.removed || 0)} registro).\nAuditoria registrada.\n\n${rows}`,
        kb([[{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }], nav()]));
    }
    case 'quest': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_quest', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Quest salva: <b>${esc(r.title)}</b> — ${esc(r.event_key)} · meta ${r.target_amount} · ${fmt(r.reward_fc)} FC ${r.enabled ? '✅' : '⛔'}`, kb([[{ t: '🎯 DAILY QUESTS', d: 'm:quests' }], nav()])); }
    case 'questtoggle': {
      const d = await rpc('admin_quests_overview', { p_admin_id: ctx.adminId });
      const current = (d.quests || []).find((q: any) => q.code === text);
      if (!current) return send(ctx, '⚠️ Quest não encontrada.', kb([[{ t: '🎯 DAILY QUESTS', d: 'm:quests' }], nav()]));
      const r = await rpc('admin_upsert_quest', { p_admin_id: ctx.adminId, p_code: text, p_patch: { enabled: !current.enabled }, p_reason: 'toggle pelo painel' });
      return send(ctx, `✅ ${esc(r.title)} agora está ${r.enabled ? 'ATIVA ✅' : 'INATIVA ⛔'}.`, kb([[{ t: '🎯 DAILY QUESTS', d: 'm:quests' }], nav()]));
    }
    case 'questbonus': {
      const [code, qty, ...name] = text.split(/\s+/);
      const r = await rpc('admin_set_quest_bonus', { p_admin_id: ctx.adminId, p_item_type: 'hero_chest', p_item_code: code, p_name: name.join(' ') || code, p_quantity: Number(qty) || 1 });
      return send(ctx, `✅ Baú 5/5: <b>${esc(r.name)}</b> — <code>${esc(r.item_code)}</code> x${r.quantity}`, kb([[{ t: '🎯 DAILY QUESTS', d: 'm:quests' }], nav()]));
    }
    case 'questtz': { const r = await rpc('admin_set_quest_timezone', { p_admin_id: ctx.adminId, p_timezone: text }); return send(ctx, `✅ Reset diário no fuso <b>${esc(r.timezone)}</b>.`, kb([[{ t: '🎯 DAILY QUESTS', d: 'm:quests' }], nav()])); }
    case 'mission': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_mission', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Missão salva: ${esc(r.title)}`, MAIN_MENU); }
    case 'boss': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_boss', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Chefe salvo: ${esc(r.name)} — ${fmt(r.max_hp)} HP`, MAIN_MENU); }
    case 'bossspawn': {
      const r = await rpc('admin_boss_control', { p_admin_id: ctx.adminId, p_action: 'activate', p_code: text.trim(), p_reason: 'ativação manual' });
      const ends = r.endsAt ? new Date(r.endsAt).toLocaleString('pt-BR') : '—';
      return send(ctx, `✅ <b>BOSS ATIVADO</b>\n👹 ${esc(r.name ?? text)}\n❤️ HP: ${fmt(r.maxHp ?? 0)}\n⏱ Duração: ${Math.round((r.durationSeconds ?? 0) / 3600)}h\n📅 Final: ${esc(ends)}`, kb([[{ t: '👹 Boss', d: 'm:boss' }], nav()]));
    }
    case 'bosshpval': {
      const [code, hp] = text.trim().split(/\s+/);
      const r = await rpc('admin_boss_control', { p_admin_id: ctx.adminId, p_action: 'set_hp', p_code: code, p_reason: `HP alterado para ${hp}`, p_value: Number(hp) });
      return send(ctx, `❤️ HP de <b>${esc(r.name ?? code)}</b> definido para ${fmt(Number(hp))}.`, kb([[{ t: '👹 Boss', d: 'm:boss' }], nav()]));
    }
    case 'bossdur': {
      const [code, hours] = text.trim().split(/\s+/);
      const seconds = Math.round(Number(hours) * 3600);
      const r = await rpc('admin_boss_control', { p_admin_id: ctx.adminId, p_action: 'set_duration', p_code: code, p_reason: `duração ${hours}h`, p_value: seconds });
      return send(ctx, `⏱ Duração de <b>${esc(r.name ?? code)}</b>: ${hours}h · fim ${esc(r.endsAt ? new Date(r.endsAt).toLocaleString('pt-BR') : '—')}`, kb([[{ t: '👹 Boss', d: 'm:boss' }], nav()]));
    }
    case 'bossreward': {
      const [code, reward] = text.trim().split(/\s+/);
      await rpc('admin_boss_control', { p_admin_id: ctx.adminId, p_action: 'set_reward', p_code: code, p_reason: `recompensa ${reward} FC`, p_value: Number(reward) });
      return send(ctx, `🎁 Recompensa de <b>${esc(code)}</b> definida para ${fmt(Number(reward))} FC.`, kb([[{ t: '👹 Boss', d: 'm:boss' }], nav()]));
    }
    case 'ads': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_ad_provider', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Provedor ${esc(r.name)} ${r.enabled ? 'ativo' : 'inativo'} — ${fmt(r.reward_fc)} FC`, MAIN_MENU); }
    case 'setting': { const i = text.indexOf(' '); const k = i < 0 ? text : text.slice(0, i); const v = i < 0 ? '' : text.slice(i + 1); const r = await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: k, p_value: parseValue(v), p_reason: 'painel admin' }); return send(ctx, `✅ <code>${esc(k)}</code>\n${esc(JSON.stringify(r.old_value))} → <b>${esc(JSON.stringify(r.new_value))}</b>`, MAIN_MENU); }
    case 'pvpset': { const [k, v] = text.split(/\s+/); const r = await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: k, p_value: parseValue(v), p_reason: 'painel admin' }); return send(ctx, `✅ ${esc(k)}: ${esc(JSON.stringify(r.old_value))} → <b>${esc(JSON.stringify(r.new_value))}</b>`, MAIN_MENU); }
    case 'maintmsg': { await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: 'maintenance_message', p_value: text, p_reason: 'painel admin' }); return send(ctx, '✅ Mensagem atualizada.', MAIN_MENU); }
    case 'ref': { const r = await rpc('admin_set_referral_percent', { p_admin_id: ctx.adminId, p_level: Number(args[0]), p_percent: Number(text.replace(/[^\d.]/g, '')), p_reason: 'painel admin' }); return send(ctx, `✅ Nível ${r.level}: ${r.old_value}% → <b>${r.new_value}%</b>`, MAIN_MENU); }
    case 'unlink': { const i = text.indexOf(' '); const r = await rpc('admin_unlink_referral', { p_admin_id: ctx.adminId, p_ref: text.slice(0, i), p_reason: text.slice(i + 1) }); return send(ctx, `✂️ ${r.removed} vínculo(s) removido(s).`, MAIN_MENU); }
    case 'pool': {
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value <= 0) throw new Error('KEEP_SESSION::⚠️ Valor inválido. Envie um número maior que 0 (ex.: <code>20</code> ou <code>20,5</code>).');
      const mode = args[0] === 'remove' ? 'remove' : 'add';
      await setSession(ctx, `pool|${mode}`, 'awaiting_confirmation', { amount: value });
      return send(ctx, `⚠️ Confirmar <b>${mode === 'remove' ? 'REMOVER' : 'ADICIONAR'} ${value} TON</b> na Community Pool?`,
        kb([[{ t: '✅ CONFIRMAR', d: `poolgo:${mode}:${value}` }, { t: '❌ CANCELAR', d: 'cancel' }]]));
    }

    case 'poolset': { const [k, v] = text.split(/\s+/); await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: 'pool_' + k, p_value: parseValue(v), p_reason: 'painel admin' }); return send(ctx, `✅ Configuração da pool <code>${esc(k)}</code> = ${esc(v)}`, MAIN_MENU); }
    case 'poolrate': { const pct = Number(text.replace(',', '.').replace(/[^\d.]/g, '')); if (!Number.isFinite(pct) || pct < 0 || pct > 100) return send(ctx, '⚠️ Informe um percentual entre 0 e 100.', MAIN_MENU); const r = await rpc('admin_set_pool_contribution_percent', { p_admin_id: ctx.adminId, p_percent: pct }); return send(ctx, `✅ Taxa da Community Pool agora é <b>${r}%</b> de toda receita TON confirmada.`, MAIN_MENU); }

    case 'pass': {
      const patch = JSON.parse(text);
      const { data: season } = await db.from('season_pass_seasons').select('*').eq('active', true).order('start_at', { ascending: false }).limit(1).maybeSingle();
      if (!season) return send(ctx, '⚠️ Nenhuma temporada ativa.', MAIN_MENU);
      const r = await rpc('admin_update_season_pass', {
        p_season_id: season.id, p_name: patch.name ?? season.name, p_start_at: patch.start_at ?? season.start_at,
        p_end_at: patch.end_at ?? season.end_at, p_levels: patch.levels ?? season.levels, p_xp_per_level: patch.xp_per_level ?? season.xp_per_level,
        p_adventurer_price: patch.adventurer_price_ton ?? season.adventurer_price_ton, p_legendary_price: patch.legendary_price_ton ?? season.legendary_price_ton,
        p_active: patch.active ?? season.active,
      });
      await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pass.update', p_target_type: 'season', p_target_id: season.id, p_old: season, p_new: r ?? patch, p_reason: 'painel admin', p_context: {} });
      await rpc('admin_bump_settings_version', {});
      return send(ctx, '✅ Passe atualizado.', MAIN_MENU);
    }
    case 'passreward': {
      const i = text.indexOf(' '); const id = text.slice(0, i); const patch = JSON.parse(text.slice(i + 1));
      const { data: old } = await db.from('season_pass_rewards').select('*').eq('id', id).maybeSingle();
      if (!old) return send(ctx, '⚠️ Recompensa não encontrada.', MAIN_MENU);
      await rpc('admin_update_season_reward', {
        p_reward_id: id, p_tier: patch.tier ?? old.tier, p_level: patch.level ?? old.level, p_type: patch.reward_type ?? old.reward_type,
        p_code: patch.reward_code ?? old.reward_code, p_amount: patch.amount ?? old.amount, p_title: patch.title ?? old.title, p_enabled: patch.enabled ?? old.enabled,
      });
      await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pass.reward.update', p_target_type: 'season_reward', p_target_id: id, p_old: old, p_new: patch, p_reason: 'painel admin', p_context: {} });
      await rpc('admin_bump_settings_version', {});
      return send(ctx, '✅ Recompensa atualizada.', MAIN_MENU);
    }
    case 'depok': case 'depno': {
      const { data: rows } = await db.from('wallet_deposits').select('id').ilike('id', `${text}%`).limit(1);
      if (!rows?.length) return send(ctx, '⚠️ Depósito não encontrado.', MAIN_MENU);
      const r = await rpc('admin_review_deposit', { p_admin_id: ctx.adminId, p_deposit_id: rows[0].id, p_approve: key === 'depok', p_tx_hash: null, p_reason: 'painel admin' });
      return send(ctx, `✅ Depósito ${key === 'depok' ? 'confirmado' : 'rejeitado'}.\n<code>${esc(JSON.stringify(r)).slice(0, 500)}</code>`, MAIN_MENU);
    }
    case 'tonrate': {
      const value = Number(text.replace(/[^\d.]/g, ''));
      if (!Number.isFinite(value) || value <= 0) return send(ctx, '⚠️ Taxa inválida.', MAIN_MENU);
      const { error } = await db.from('economy_settings').upsert([
        { key: 'ton_to_fc_rate', value_numeric: value, updated_at: new Date().toISOString() },
        { key: 'fc_per_ton', value_numeric: value, updated_at: new Date().toISOString() },
      ], { onConflict: 'key' });
      if (error) return send(ctx, `⚠️ ${esc(error.message)}`, MAIN_MENU);
      await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'wallet.ton_fc_rate', p_target_type: 'economy', p_target_id: null, p_old: null, p_new: { rate: value }, p_reason: 'alterado pelo painel', p_context: { financial: true } });
      return send(ctx, `✅ Nova taxa: <b>1 TON = ${fmt(value)} FC</b>\nAplica-se somente a depósitos confirmados a partir de agora.`, kb([[{ t: '💳 CARTEIRA', d: 'm:wallet' }], nav()]));
    }
    case 'wdfee': {
      const value = Number(text.replace(',', '.').replace(/[^\d.]/g, ''));
      if (!Number.isFinite(value) || value < 0 || value > 50) return send(ctx, '⚠️ Informe um percentual entre 0 e 50.', MAIN_MENU);
      const r = await rpc('admin_set_withdraw_fee_percent', { p_admin_id: ctx.adminId, p_percent: value });
      return send(ctx, `✅ <b>WITHDRAWAL FEE</b> atualizada para <b>${Number(r.feePercent)}%</b>.\nSaques antigos mantêm a taxa usada na época.`, kb([[{ t: '💳 CARTEIRA', d: 'm:wallet' }], nav()]));
    }
    case 'auditdep': {
      const p = await rpc('admin_player_detail', { p_admin_id: ctx.adminId, p_ref: text });
      return handleCallback(ctx, `audit1:${p.telegram_id}`);
    }
    case 'wdpaid': case 'wdno': {
      // Legacy prompts now open the detail card — payment/rejection always go through it.
      const id = await resolveWithdrawalId(text.split(/\s+/)[0]);
      if (!id) throw new Error('KEEP_SESSION::⚠️ Saque não encontrado (ou o prefixo é ambíguo). Envie mais caracteres do ID.');
      return withdrawalCard(ctx, id, false);
    }
    case 'wdhash': {
      const [id] = args;
      const hash = text.split(/\s+/)[0];
      if (!hash || hash.length < 8) throw new Error('KEEP_SESSION::⚠️ Hash inválido. Envie o hash completo da transação TON.');
      await rpc('admin_withdrawal_mark_paid', { p_admin_id: ctx.adminId, p_withdrawal_id: id, p_tx_hash: hash });
      // Receipt goes to the payments channel automatically; a failure never reverts the payout.
      const posted = await announcePayout(ctx.adminId, id);
      await send(ctx, `✅ Saque marcado como <b>PAID</b>.\n${posted.status === 'sent' ? '📢 Comprovante publicado no canal de pagamentos.' : posted.status === 'skipped' ? `🚫 Comprovante não publicado (${esc(posted.detail)}).` : `⚠️ Falha ao publicar o comprovante: <code>${esc(posted.detail)}</code> — use RETRY FAILED.`}`);
      return withdrawalCard(ctx, id, false);
    }
    case 'pachat': {
      const chat = text.trim().split(/\s+/)[0];
      if (!/^-?\d{5,}$|^@[\w]{4,}$/.test(chat)) throw new Error('KEEP_SESSION::⚠️ Envie o chat id numérico (ex.: <code>-1004303374351</code>) ou @canalpublico.');
      await rpc("admin_set_setting", { p_admin_id: ctx.adminId, p_key: "payments_channel_chat_id", p_value: chat });
      await send(ctx, `✅ Canal de pagamentos salvo: <code>${esc(chat)}</code>`);
      return payoutMenu(ctx, false);
    }

    case 'findwallet': {
      const d = await rpc('admin_connected_wallets', { p_admin_id: ctx.adminId, p_query: text, p_limit: 12 });
      if (!d.items?.length) throw new Error('KEEP_SESSION::⚠️ Nenhuma carteira encontrada. Tente Telegram ID, @usuário, nome, endereço TON ou ID interno.');
      return send(ctx, connectedWalletsText(d.items), kb([[{ t: '🔎 PESQUISAR', d: 'ask:findwallet' }], nav('m:wallet')]));
    }

    case 'cast': {
      const seg = args[0];
      const t = await rpc('admin_broadcast_targets', { p_admin_id: ctx.adminId, p_segment: seg, p_limit: 2000 });
      return send(ctx, `📣 <b>Prévia</b> (${t.targets.length} destinatários — ${seg})\n\n${esc(text)}`,
        kb([[{ t: '✅ ENVIAR', d: `castgo:${seg}:${encodeURIComponent(text).slice(0, 40)}` }, { t: '❌ Cancelar', d: 'home' }]]));
    }
  }
  return send(ctx, 'Comando não reconhecido.', MAIN_MENU);
}

const ERRORS: Record<string, string> = {
  unauthorized: DENIED,
  player_not_found: '⚠️ Jogador não encontrado. Tente Telegram ID, @usuário, nome, carteira ou ID interno.',
  season_not_found: '⚠️ Nenhuma temporada ativa do Battle Pass.',
  invalid_tier: '⚠️ Tipo de passe inválido.',
  hero_not_found: '⚠️ Herói não encontrado.',
  pet_not_found: '⚠️ Pet não encontrado.',
  reason_required: '⚠️ O motivo é obrigatório para esta ação.',
  already_confirmed: '⚠️ Este depósito já foi confirmado.',
  already_processed: '⚠️ Este saque já foi processado.',
  withdrawal_not_found: '⚠️ Saque não encontrado.',
  withdrawal_locked: '⚠️ Este saque já está em PROCESSING. Finalize com MARK AS PAID ou libere com PAGAMENTO FALHOU.',
  wallet_missing: '⚠️ WALLET NOT FOUND — MANUAL REVIEW REQUIRED. Este saque não tem carteira TON de destino.',
  invalid_amount: '⚠️ Valor de TON inválido neste saque.',
  tx_hash_required: '⚠️ Informe o hash da transação TON para marcar como pago.',
  tx_hash_already_used: '⚠️ Este hash já foi usado em outro saque.',
  not_processing: '⚠️ Este saque não está em processamento.',

  rates_must_total_100: '❌ Total inválido. A soma das raridades precisa ser exatamente 100%.',
  invalid_price: '⚠️ Preço inválido. Use um número entre 1 e 1.000.000.000.',
  invalid_count: '⚠️ Pacote inválido. Use 1x, 5x ou 10x.',
  immutable_setting: '⚠️ O ID do administrador mestre não pode ser alterado pelo painel.',
};

Deno.serve(async (req) => {
  if (req.method === 'GET') {
    // One-time webhook registration helper, gated by a server-only setup key.
    const url = new URL(req.url);
    const setupKey = Deno.env.get('TELEGRAM_ADMIN_SETUP_KEY') || '';
    if (url.searchParams.get('setup') && setupKey && url.searchParams.get('setup') === setupKey) {
      const hookUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/admin-bot`;
      const res = await tg('setWebhook', {
        url: hookUrl,
        allowed_updates: ['message', 'callback_query'],
        drop_pending_updates: true,
        ...(WEBHOOK_SECRET ? { secret_token: WEBHOOK_SECRET } : {}),
      });
      const info = await tg('getWebhookInfo', {});
      return new Response(JSON.stringify({ setWebhook: res, info }), { headers: { 'Content-Type': 'application/json' } });
    }
    return new Response('ok');
  }
  if (req.method !== 'POST') return new Response('ok');
  if (WEBHOOK_SECRET && req.headers.get('X-Telegram-Bot-Api-Secret-Token') !== WEBHOOK_SECRET) {
    return new Response('Unauthorized', { status: 401 });
  }
  const update = await req.json().catch(() => null);
  if (!update) return new Response(JSON.stringify({ ok: true }));

  const cq = update.callback_query;
  const msg = cq?.message ?? update.message;
  const fromId = Number(cq?.from?.id ?? update.message?.from?.id ?? 0);
  const chatId = Number(msg?.chat?.id ?? 0);
  if (!chatId) return new Response(JSON.stringify({ ok: true }));

  // Hard gate: nothing administrative is even rendered for other ids.
  if (fromId !== SUPER_ADMIN_ID) {
    if (cq) await tg('answerCallbackQuery', { callback_query_id: cq.id, text: DENIED, show_alert: true });
    else await tg('sendMessage', { chat_id: chatId, text: DENIED });
    return new Response(JSON.stringify({ ok: true }));
  }

  const ctx: Ctx = { chatId, adminId: requireAdmin(fromId), messageId: cq ? msg.message_id : undefined };

  try {
    if (cq) {
      await tg('answerCallbackQuery', { callback_query_id: cq.id });
      const data = String(cq.data || '');
      if (data.startsWith('norm:')) {
        const rates = JSON.parse(decodeURIComponent(data.slice(5)));
        const r = await rpc('admin_set_hero_rarity_rates', { p_admin_id: ctx.adminId, p_rates: rates, p_normalize: true, p_reason: 'normalizado pelo painel' });
        await send(ctx, `✅ Raridades normalizadas:\n<code>${esc(JSON.stringify(r.rates))}</code>`, MAIN_MENU);
      } else {
        await handleCallback(ctx, data);
      }
      return new Response(JSON.stringify({ ok: true }));
    }

    // Forwarded message from a channel/group: only informational (channel rewards no longer use chat ids).
    const forwarded = update.message?.forward_from_chat ?? update.message?.forward_origin?.chat;
    if (forwarded?.id) {
      const id = String(forwarded.id);
      await send(ctx,
        `🔗 <b>CHAT DETECTADO</b>\n${esc(forwarded.title || forwarded.username || '—')} (${esc(forwarded.type)})\nchat id: <code>${esc(id)}</code>\n\nAs recompensas dos canais oficiais são one-time por Telegram ID e não usam chat id.`,
        kb([[{ t: '💳 CANAL DE PAGAMENTOS', d: 'ask:pachat' }], [{ t: '📡 CANAIS OFICIAIS', d: 'm:channels' }], nav()]));
      return new Response(JSON.stringify({ ok: true }));
    }

    const text = String(update.message?.text || '').trim();
    const cmdWord = text.split(/\s+/)[0].replace(/@.*/, '').toLowerCase();
    const isCommand = cmdWord.startsWith('/');

    // 1) pending conversation state wins over any normal command / menu fallback.
    // Legacy quoted "#cmd" prompts still work; the persisted session is the source of truth.
    const replied = String(update.message?.reply_to_message?.text || '');
    const quoted = replied.match(/#([^\s]+)\s*$/)?.[1];
    const session = quoted ? null : await getSession(ctx);
    const pending = quoted || session?.action || null;

    if (pending && !(isCommand && (cmdWord === '/start' || cmdWord === '/menu' || cmdWord === '/cancel'))) {
      try {
        await handlePrompt(ctx, pending, text);
        await clearSession(ctx);
      } catch (error) {
        const raw = error instanceof Error ? error.message : String(error);
        if (raw.startsWith('KEEP_SESSION::')) {
          // Validation error: keep the flow alive, never bounce back to the menu.
          await send(ctx, raw.slice('KEEP_SESSION::'.length), kb([[{ t: '❌ CANCELAR', d: 'cancel' }]]));
          return new Response(JSON.stringify({ ok: true }));
        }
        throw error;
      }
      return new Response(JSON.stringify({ ok: true }));
    }
    if (isCommand && cmdWord === '/cancel') {
      await clearSession(ctx);
      await send(ctx, '❌ Nenhuma ação pendente.', MAIN_MENU);
      return new Response(JSON.stringify({ ok: true }));
    }

    // 2) no pending action: normal commands, then the menu fallback.
    const cmd = cmdWord;
    const arg = text.slice(cmd.length).trim();
    const direct: Record<string, string> = {
      '/heroes': 'heroes', '/shop': 'shop', '/loja': 'shop', '/pets': 'pets', '/pvp': 'pvp', '/pool': 'pool', '/pass': 'pass',
      '/invites': 'invites', '/boss': 'boss', '/audit': 'audit', '/status': 'status',
      '/wallet': 'wallet', '/missions': 'missions', '/ads': 'ads', '/settings': 'settings', '/broadcast': 'cast',
    };
    if (cmd === '/start' || cmd === '/admin' || cmd === '/menu') { await clearSession(ctx); await home(ctx); }
    else if (cmd === '/user' || cmd === '/player') { arg ? await playerCard(ctx, arg) : await ask(ctx, 'find', PROMPTS.find); }
    else if (cmd === '/balance') { arg ? await playerCard(ctx, arg) : await ask(ctx, 'find', PROMPTS.find); }
    else if (cmd === '/ban') { arg ? await handleCallback(ctx, `ban:${arg}`) : await ask(ctx, 'find', PROMPTS.find); }
    else if (cmd === '/maintenance') await module({ ...ctx, messageId: undefined }, 'maint');
    else if (direct[cmd]) await module({ ...ctx, messageId: undefined }, direct[cmd]);
    else await home(ctx);
  } catch (error) {
    const raw = error instanceof Error ? error.message : String(error);
    const known = Object.keys(ERRORS).find((k) => raw.includes(k));
    console.error('admin-bot error:', raw);
    await clearSession(ctx).catch(() => {});
    await send(ctx, known ? ERRORS[known] : `⚠️ Falha: <code>${esc(raw).slice(0, 400)}</code>`, MAIN_MENU);
  }
  return new Response(JSON.stringify({ ok: true }));
});

