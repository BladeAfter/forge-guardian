// MYTHREON :: Master Admin Bot (Telegram)
// Every operation re-validates the super admin Telegram ID server-side (bot + database).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { toFriendlyTonAddress } from "../_shared/tonAddress.ts";
import { createPetCms } from "./petCms.ts";

const SUPER_ADMIN_ID = Number(Deno.env.get("TELEGRAM_SUPER_ADMIN_ID") || "8118569391");
// Admin bot token: dedicated variables first (current name: TELEGRAM_BOT_TOKEN_Admin), then legacy names.
const BOT_TOKEN = (
  Deno.env.get("TELEGRAM_BOT_TOKEN_Admin") ||
  Deno.env.get("TELEGRAM_ADMIN_BOT_TOKEN") ||
  Deno.env.get("TELEGRAM_BOT_TOKEN") ||
  ""
).trim();

// Webhook secret: explicit variable when configured, otherwise deterministically derived from the
// bot token so the webhook check ALWAYS fails closed (never skipped because a variable is unset).
async function deriveWebhookSecret(seed: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`admin-bot-webhook:${seed}`));
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}
const WEBHOOK_SECRET =
  (Deno.env.get("TELEGRAM_ADMIN_WEBHOOK_SECRET") || "").trim() ||
  (BOT_TOKEN ? await deriveWebhookSecret(BOT_TOKEN) : "");

/** Constant-shape comparison for the secret header. */
function secretMatches(header: string | null): boolean {
  if (!WEBHOOK_SECRET || !header || header.length !== WEBHOOK_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < header.length; i++) diff |= header.charCodeAt(i) ^ WEBHOOK_SECRET.charCodeAt(i);
  return diff === 0;
}

/** Every GET maintenance action requires the server-only setup key. Missing key = no access. */
function setupKeyOk(url: URL): boolean {
  const setupKey = (Deno.env.get("TELEGRAM_ADMIN_SETUP_KEY") || "").trim();
  const provided = String(url.searchParams.get("key") || url.searchParams.get("setup") || "");
  if (!setupKey || !provided || provided.length !== setupKey.length) return false;
  let diff = 0;
  for (let i = 0; i < provided.length; i++) diff |= provided.charCodeAt(i) ^ setupKey.charCodeAt(i);
  return diff === 0;
}

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const DENIED = "⛔ Acesso não autorizado.";

/** Single source of truth for authorization. Never trust ids coming from payload fields. */
function requireAdmin(fromId: number | undefined): number {
  if (!fromId || Number(fromId) !== SUPER_ADMIN_ID) throw new Error("unauthorized");
  return SUPER_ADMIN_ID;
}

async function tg(method: string, payload: Record<string, unknown>) {
  const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
const nav = (back = "home") => [
  { t: "⬅️ Voltar", d: back },
  { t: "🏠 Menu", d: "home" },
];
const fmt = (n: unknown) => Number(n ?? 0).toLocaleString("pt-BR");
const esc = (s: unknown) =>
  String(s ?? "").replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" })[c] as string);

const MAIN_MENU = kb([
  [
    { t: "👥 USUÁRIOS", d: "m:users" },
    { t: "🦸 HERÓIS", d: "m:heroes" },
  ],
  [
    { t: "🐲 PETS", d: "m:pets" },
    { t: "⚔️ PVP", d: "m:pvp" },
  ],
  [
    { t: "🎟 PASSE", d: "m:pass" },
    { t: "💰 POOL", d: "m:pool" },
  ],
  [
    { t: "🤝 CONVITES", d: "m:invites" },
    { t: "🏪 LOJA DE HERÓIS", d: "m:shop" },
  ],
  [
    { t: "💳 CARTEIRA / FC", d: "m:wallet" },
    { t: "🎯 DAILY QUESTS", d: "m:quests" },
  ],
  [
    { t: "👑 BOSS", d: "m:boss" },
    { t: "📢 ANÚNCIOS", d: "m:ads" },
  ],
  [
    { t: "📡 CANAIS OFICIAIS", d: "m:channels" },
    { t: "🏰 CLÃS", d: "m:clans" },
  ],
  [
    { t: "🎁 PRESENTES", d: "m:gifts" },
    { t: "🎉 EVENTOS", d: "m:events" },
  ],
  [{ t: "💳 RECUPERAÇÃO DE PAGAMENTOS", d: "m:precovery" }],
  [{ t: "🛒 MARKETPLACE", d: "m:market" }],
  [{ t: "💰 SPENDING EVENT", d: "m:spending" }],
  [{ t: "👹 CLAN BOSS", d: "m:clanboss" }],
  [{ t: "🤝 PARTNERS", d: "m:partners" }],
  [{ t: "💎 NFT PETS", d: "nft:hub" }],
  [{ t: "⛏ MINERAÇÃO TON", d: "hm:hub" }],
  [{ t: "⛏ MINAS DE TON", d: "tm:hub" }],
  [{ t: "💎 TON STAKING", d: "ts:hub" }],
  [{ t: "🧩 FRAGMENTOS", d: "fg:hub" }],
  [{ t: "🗺 EXPEDIÇÕES", d: "xe:hub" }],
  [{ t: "🎁 GIVEAWAY POPUP", d: "gw:hub" }],
  [{ t: "⚔️ PVP LEAGUE ARENA", d: "pl:hub" }],
  [{ t: "⚔️ TACTICAL PVP (3V3)", d: "tp:hub" }],
  [{ t: "⚙ POOL / PASS ACTIVITY", d: "ar:hub" }],
  [{ t: "🛡 ANTI-FAKE", d: "af:hub" }],
  [{ t: "#️⃣ MISSÃO #MYTHREON", d: "nm:hub" }],
  [{ t: "📣 POOL MARKETING", d: "mp:hub" }],
  [{ t: "🏰 CLAN WAR (20V20)", d: "cw:hub" }],
  [{ t: "🪙 MYTH TOKEN", d: "my:hub" }],
  [{ t: "🐾 FAMILIAR HUNT", d: "fh:hub" }],
  [{ t: "🎡 GLOBAL ROULETTE", d: "rl:hub" }],

  [{ t: "👑 FOUNDER PACK", d: "fp:hub" }],

  [{ t: "⚔️ VETERAN VAULT", d: "vv:hub" }],
  [{ t: "⚔️ VETERAN VAULT (PREMIUM)", d: "v2:hub" }],
  [{ t: "🎁 OFERTAS PREMIUM (POPUPS)", d: "po:hub" }],
  [{ t: "🔥 MYTH UTILITY (PAGAMENTOS)", d: "mu:hub" }],

  [
    { t: "⚙️ CONFIGURAÇÕES", d: "m:settings" },
    { t: "📜 AUDITORIA", d: "m:audit" },
  ],
  [
    { t: "📊 STATUS", d: "m:status" },
    { t: "🔧 MANUTENÇÃO", d: "m:maint" },
  ],
  [
    { t: "📣 BROADCAST", d: "m:cast" },
    { t: "💾 SNAPSHOT", d: "do:snapshot" },
  ],
]);

type Ctx = { chatId: number; adminId: number; messageId?: number };

async function send(ctx: Ctx, text: string, markup?: unknown) {
  await tg("sendMessage", { chat_id: ctx.chatId, text, parse_mode: "HTML", reply_markup: markup });
}
async function edit(ctx: Ctx, text: string, markup?: unknown) {
  if (!ctx.messageId) return send(ctx, text, markup);
  await tg("editMessageText", {
    chat_id: ctx.chatId,
    message_id: ctx.messageId,
    text,
    parse_mode: "HTML",
    reply_markup: markup,
  });
}
// ---------------------------------------------------------------- conversation state (persisted: serverless-safe)
// Edge functions are stateless per request, so pending admin actions live in the database,
// keyed by (admin_telegram_id, chat_id) and expiring after 15 minutes.
const SESSION_TTL_MS = 15 * 60 * 1000;

type AdminSession = { action: string; step: string; context: Record<string, unknown> };

async function getSession(ctx: Ctx): Promise<AdminSession | null> {
  const { data, error } = await db
    .from("admin_bot_sessions")
    .select("action, step, context, expires_at")
    .eq("admin_telegram_id", ctx.adminId)
    .eq("chat_id", ctx.chatId)
    .maybeSingle();
  if (error) {
    console.error("session read failed:", error.message);
    return null;
  }
  if (!data) return null;
  if (new Date(data.expires_at).getTime() < Date.now()) {
    await clearSession(ctx);
    return null;
  }
  return {
    action: data.action,
    step: data.step || "awaiting_input",
    context: (data.context || {}) as Record<string, unknown>,
  };
}

async function setSession(ctx: Ctx, action: string, step = "awaiting_input", context: Record<string, unknown> = {}) {
  const { error } = await db.from("admin_bot_sessions").upsert(
    {
      admin_telegram_id: ctx.adminId,
      chat_id: ctx.chatId,
      action,
      step,
      context,
      updated_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + SESSION_TTL_MS).toISOString(),
    },
    { onConflict: "admin_telegram_id,chat_id" },
  );
  if (error) console.error("session write failed:", error.message);
  return !error;
}

async function clearSession(ctx: Ctx) {
  const { error } = await db
    .from("admin_bot_sessions")
    .delete()
    .eq("admin_telegram_id", ctx.adminId)
    .eq("chat_id", ctx.chatId);
  if (error) console.error("session clear failed:", error.message);
}

// 🐲 Visual pet/egg CMS (buttons + photos only). Keeps its own persisted session ('petcms').
const petCms = createPetCms({
  db,
  botToken: BOT_TOKEN,
  tg,
  rpc,
  kb,
  nav,
  fmt,
  esc,
  send,
  edit,
  setSession,
  getSession,
  clearSession,
});

/** Deposit methods hub: the player picks the destination before paying, admin controls both here. */
async function depositSettingsHub(ctx: Ctx) {
  const cfg = await rpc("admin_deposit_settings", { p_admin_id: ctx.adminId, p_key: null, p_value: null });
  const on = (v: unknown) => (v ? "✅ ATIVO" : "⛔ DESATIVADO");
  return edit(
    ctx,
    `💠 <b>MÉTODOS DE DEPÓSITO</b>\n\n🪙 <b>TON → FC</b>: ${on(cfg.fcEnabled)}\nMínimo <b>${fmt(cfg.minFcTon)} TON</b> · 1 TON = <b>${fmt(cfg.fcPerTon)} FC</b>\n\n💎 <b>TON → SALDO TON</b>: ${on(cfg.directEnabled)}\nMínimo <b>${cfg.minDirectTon} TON</b> · creditado 1:1 no TON sacável (nunca vira FC)`,
    kb([
      [
        {
          t: cfg.fcEnabled ? "⛔ DESATIVAR TON → FC" : "✅ ATIVAR TON → FC",
          d: `dp:toggle:ton_to_fc_deposit_enabled:${cfg.fcEnabled ? 0 : 1}`,
        },
      ],
      [
        {
          t: cfg.directEnabled ? "⛔ DESATIVAR TON → TON" : "✅ ATIVAR TON → TON",
          d: `dp:toggle:direct_ton_deposit_enabled:${cfg.directEnabled ? 0 : 1}`,
        },
      ],
      [{ t: `💠 MÍNIMO DIRETO (${cfg.minDirectTon} TON)`, d: "dp:ask:depmin" }],
      nav("m:wallet"),
    ]),
  );
}

/** Prompt: persists the pending action so the next plain text reply is executed. */
async function ask(ctx: Ctx, cmd: string, question: string) {
  await setSession(ctx, cmd, "awaiting_input");
  await tg("sendMessage", {
    chat_id: ctx.chatId,
    text: `${question}\n\n<i>Responda com o valor nesta conversa. Toque em ❌ CANCELAR para sair.</i>`,
    parse_mode: "HTML",
    reply_markup: kb([[{ t: "❌ CANCELAR", d: "cancel" }]]),
  });
}

/** Accepts 20, 20.5 and 20,5 — returns NaN for anything else. */
function parseAmount(raw: string): number {
  const cleaned = String(raw).trim().replace(/\s/g, "").replace(",", ".");
  if (!/^-?\d+(\.\d+)?$/.test(cleaned)) return NaN;
  return Number(cleaned);
}

/** TON display with full 9-decimal precision (never used for math/storage). */
function fmtTon(value: unknown): string {
  const n = Number(value);
  return (Number.isFinite(n) ? n : 0).toFixed(9);
}

// ---------------------------------------------------------------- views
async function home(ctx: Ctx, editing = false) {
  const text = "🎮 <b>MYTHREON ADMIN</b>\nControle total do jogo. Escolha um módulo:";
  editing ? await edit(ctx, text, MAIN_MENU) : await send(ctx, text, MAIN_MENU);
}

async function playerCard(ctx: Ctx, ref: string) {
  const p = await rpc("admin_player_detail", { p_admin_id: ctx.adminId, p_ref: ref });
  const lines = [
    `👤 <b>${esc(p.name)}</b> ${p.username ? "@" + esc(p.username) : ""}`,
    `🆔 <code>${p.telegram_id}</code> · interno <code>${p.id}</code>`,
    `🪙 <b>${fmt(p.forge_coins)} FC</b> · 💎 ${fmt(p.ton_balance)} TON`,
    `🏅 ${esc(p.league)} · 🏆 ${fmt(p.trophies)} · 🎟 ${fmt(p.tickets)}`,
    `🛒 Comprados hoje: ${fmt(p.tickets_bought_today ?? 0)} / ${fmt(p.ticket_daily_limit ?? 10)} · Passe: ${p.pass_tier ? esc(String(p.pass_tier).toUpperCase()) : "NO"}`,

    `⚔️ ${fmt(p.wins)}V / ${fmt(p.losses)}D · 👑 ${fmt(p.boss_defeats)} chefes`,
    `🦸 ${fmt(p.heroes_count)} heróis · 🐲 ${fmt(p.pets_count)} pets · 🤝 ${fmt(p.referrals)} convites`,
    `👛 TON Wallet: <code>${esc(walletOut(p.wallet) ?? (p.wallet ? String(p.wallet) : "NO TON WALLET CONNECTED"))}</code>${p.wallet && !walletOut(p.wallet) ? " ⚠️ INVÁLIDA" : ""}`,
    `🔗 Wallet Connected: ${walletOut(p.wallet) ? "YES" : "NO"}${p.wallet_updated_at ? " · atualizada " + dt(p.wallet_updated_at) : ""}`,
    `📥 ${fmt(p.deposited_ton)} TON depositado · 📤 ${fmt(p.withdrawn_ton)} TON sacado`,
    `⭐ VIP: ${p.vip_until ? esc(String(p.vip_until).slice(0, 10)) : "—"} · 💠 Premium: ${p.premium_until ? esc(String(p.premium_until).slice(0, 10)) : "—"}`,
    `🚫 Banido: ${p.banned ? "SIM — " + esc(p.ban_reason) : "não"}`,
    `📅 Criado ${String(p.created_at).slice(0, 10)} · 👁 ${String(p.last_seen_at).slice(0, 16).replace("T", " ")}`,
  ];
  const u = p.telegram_id;
  const markup = kb([
    [
      { t: "💰 FC", d: `uf:${u}` },
      { t: "🦸 HERÓIS", d: `uh:${u}:0` },
    ],
    [
      { t: "🎒 ITENS", d: `ui:${u}` },
      { t: "🐲 PETS", d: `up:${u}` },
    ],
    [
      { t: "🎟 PASSE", d: `bpview:${u}` },
      { t: "⚔ PVP", d: `st:trophies:${u}` },
    ],
    [
      { t: "⭐ VIP", d: `vip:vip:${u}` },
      { t: "💠 PREMIUM", d: `vip:premium:${u}` },
    ],
    [
      { t: p.banned ? "✅ DESBANIR" : "🚫 BANIR", d: `${p.banned ? "unban" : "ban"}:${u}` },
      { t: "♻️ RESETAR", d: `reset:${u}` },
    ],
    [
      { t: "📜 HISTÓRICO", d: `hist:${u}` },
      { t: "🤝 ÁRVORE", d: `tree:${u}` },
    ],
    [{ t: "🔎 AUDIT DEPOSITS", d: `audit1:${u}` }],

    nav("m:users"),
  ]);
  // Avatar URLs can expire/404 and Telegram cannot render .svg userpics
  // (answers 400 "failed to get HTTP URL content"). Never leave the admin
  // without a reply: fall back to the text card.
  const photo = p.avatar_url && !/\.svg(\?|$)/i.test(String(p.avatar_url)) ? String(p.avatar_url) : null;
  const sent = photo
    ? await tg("sendPhoto", {
        chat_id: ctx.chatId,
        photo,
        caption: lines.join("\n"),
        parse_mode: "HTML",
        reply_markup: markup,
      })
    : null;
  if (!sent) await send(ctx, lines.join("\n"), markup);
}

// ---------------------------------------------------------------- player search (always live from the database)
const PASS_LABEL: Record<string, string> = { none: "SEM PASSE", adventurer: "AVENTUREIRO", legendary: "LENDÁRIO" };
const ago = (iso: string) => {
  const min = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (min < 60) return `${min} min`;
  if (min < 1440) return `${Math.round(min / 60)} h`;
  return `${Math.round(min / 1440)} d`;
};

/** Lists players from `game_players` (the same table the Mini App uses). Never mock data. */
async function playerSearch(ctx: Ctx, query: string, offset = 0) {
  const d = await rpc("admin_search_players", {
    p_admin_id: ctx.adminId,
    p_query: query,
    p_limit: 10,
    p_offset: offset,
  });
  const players = (d.players ?? []) as any[];
  console.log(
    "[ADMIN USER SEARCH]",
    JSON.stringify({
      query,
      searchType: query ? "query" : "latest",
      rowsFound: players.length,
      total: d.total,
      offset,
    }),
  );
  if (!players.length) {
    return send(
      ctx,
      `⚠️ Nenhum jogador encontrado para <code>${esc(query)}</code>.\nTente Telegram ID, @usuário, nome, carteira ou ID interno.`,
      kb([[{ t: "🔎 PROCURAR", d: "ask:find" }], nav("m:users")]),
    );
  }
  if (players.length === 1 && query) return playerCard(ctx, String(players[0].telegram_id));
  const lines = players.map((p, i) =>
    [
      `<b>${offset + i + 1}. ${esc(p.name)}</b>${p.banned ? " 🚫" : ""}`,
      `${p.username ? "@" + esc(p.username) : "sem @usuário"} · <code>${p.telegram_id}</code>`,
      `🪙 ${fmt(p.forge_coins)} FC · 🎟 ${esc(PASS_LABEL[p.pass_tier] ?? p.pass_tier)} · 👁 ${ago(p.last_seen_at)}`,
    ].join("\n"),
  );
  const rows: { t: string; d: string }[][] = [];
  for (let i = 0; i < players.length; i += 5) {
    rows.push(players.slice(i, i + 5).map((p, j) => ({ t: `${offset + i + j + 1}`, d: `find:${p.telegram_id}` })));
  }
  const pageNav: { t: string; d: string }[] = [];
  const token = query ? `q:${query}` : "all";
  if (offset > 0) pageNav.push({ t: "⬅️ ANTERIOR", d: `pg:${Math.max(0, offset - 10)}:${token}`.slice(0, 60) });
  if (d.hasMore) pageNav.push({ t: "PRÓXIMA ➡️", d: `pg:${offset + 10}:${token}`.slice(0, 60) });
  if (pageNav.length) rows.push(pageNav);
  rows.push([{ t: "🔎 PROCURAR", d: "ask:find" }], nav("m:users"));
  return send(
    ctx,
    `👥 <b>JOGADORES</b> (${offset + 1}–${offset + players.length} de ${fmt(d.total)})\n\n${lines.join("\n\n")}\n\nToque no número para abrir o jogador.`,
    kb(rows),
  );
}

// ---------------------------------------------------------------- battle pass (manual activation)
async function passCard(ctx: Ctx, ref: string) {
  const p = await rpc("admin_player_pass", { p_admin_id: ctx.adminId, p_ref: ref });
  console.log(
    "[ADMIN PASS]",
    JSON.stringify({ targetUserId: p.user_id, telegramId: p.telegram_id, currentPass: p.tier, seasonId: p.season_id }),
  );
  const text = [
    `🎟 <b>BATTLE PASS</b>`,
    `👤 ${esc(p.name)} ${p.username ? "@" + esc(p.username) : ""}`,
    `🆔 <code>${p.telegram_id}</code>`,
    "",
    `Current Pass: <b>${esc(PASS_LABEL[p.tier] ?? p.tier)}</b>`,
    `Versão: <b>V${p.pass_version ?? 1}</b>${p.legacy_pass ? " (LEGACY — sem novos exclusivos)" : " (ATUAL)"}`,
    `Exclusivos bloqueados por versão: <b>${fmt(p.locked_rewards ?? 0)}</b>`,
    p.expires_at ? `Expira: ${String(p.expires_at).slice(0, 10)}` : "Expira: —",
    `Season: <b>${esc(p.season_name)}</b>`,
    `Nível: <b>${p.level}</b>/${p.levels} · XP <b>${fmt(p.xp_into_level ?? 0)}</b>/${fmt(p.xp_per_level)} (total ${fmt(p.xp)})`,
    `Recompensas coletadas: ${fmt(p.claimed)} · compras TON: ${fmt(p.paid_orders)}`,
  ].join("\n");
  const u = p.telegram_id;
  return send(
    ctx,
    text,
    kb([
      [{ t: "🎟 ACTIVATE ADVENTURER", d: `bp:adventurer:${u}` }],
      [{ t: "👑 ACTIVATE LEGENDARY", d: `bp:legendary:${u}` }],
      [{ t: "❌ REMOVE PASS", d: `bp:none:${u}` }],
      [
        { t: "➕ ADD XP", d: `passxp:add:${u}` },
        { t: "➖ REMOVE XP", d: `passxp:remove:${u}` },
      ],
      [{ t: "🎚 SET LEVEL", d: `passxp:level:${u}` }],
      [{ t: "📜 PASS HISTORY", d: "bphist:1" }],
      [{ t: "👤 VER JOGADOR", d: `find:${u}` }],
      nav("m:pass"),
    ]),
  );
}

async function passConfirm(ctx: Ctx, tier: string, ref: string) {
  const p = await rpc("admin_player_pass", { p_admin_id: ctx.adminId, p_ref: ref });
  const text = [
    tier === "none" ? "⚠️ <b>REMOVER PASSE</b>" : "⚠️ <b>CONFIRMAR ATIVAÇÃO</b>",
    `User: ${p.username ? "@" + esc(p.username) : esc(p.name)}`,
    `Telegram ID: <code>${p.telegram_id}</code>`,
    "",
    `Current: <b>${esc(PASS_LABEL[p.tier] ?? p.tier)}</b>`,
    `New: <b>${esc(PASS_LABEL[tier] ?? tier)}</b>`,
    `Season: <b>${esc(p.season_name)}</b>`,
    "",
    "XP, nível e recompensas já coletadas são preservados.",
  ].join("\n");
  return send(
    ctx,
    text,
    kb([
      [
        { t: "✅ CONFIRM", d: `bpgo:${tier}:${p.telegram_id}` },
        { t: "❌ CANCEL", d: `bpview:${p.telegram_id}` },
      ],
    ]),
  );
}

async function passApply(ctx: Ctx, tier: string, ref: string) {
  const r = await rpc("admin_set_player_pass", {
    p_admin_id: ctx.adminId,
    p_ref: ref,
    p_tier: tier,
    p_reason: "ativação manual pelo bot admin",
  });
  const p = await rpc("admin_player_pass", { p_admin_id: ctx.adminId, p_ref: ref });
  console.log(
    "[ADMIN PASS]",
    JSON.stringify({
      targetUserId: r.user_id,
      telegramId: p.telegram_id,
      currentPass: r.old_tier,
      newPass: r.tier,
      seasonId: r.season_id,
    }),
  );
  const who = p.username ? "@" + esc(p.username) : esc(p.name);
  const msg =
    tier === "none"
      ? `✅ Passe removido de ${who}.`
      : `✅ <b>${esc(PASS_LABEL[tier])} PASS</b> ativado para ${who}.\nNível ${r.level} · XP ${fmt(r.xp)} preservados.`;
  return send(
    ctx,
    `${msg}\nTemporada: ${esc(r.season_name)}`,
    kb([
      [
        { t: "🎟 VER PASSE", d: `bpview:${p.telegram_id}` },
        { t: "👤 JOGADOR", d: `find:${p.telegram_id}` },
      ],
      nav("m:pass"),
    ]),
  );
}

async function passHistory(ctx: Ctx) {
  const d = await rpc("admin_pass_history", { p_admin_id: ctx.adminId, p_limit: 10 });
  const rows = (d.entries ?? []) as any[];
  const list = rows
    .map(
      (e) =>
        `• ${e.username ? "@" + esc(e.username) : esc(String(e.telegram_id ?? "—"))}: ${esc(PASS_LABEL[e.old] ?? e.old ?? "—")} → <b>${esc(PASS_LABEL[e.new] ?? e.new ?? "—")}</b> · ${String(e.created_at).slice(0, 16).replace("T", " ")}`,
    )
    .join("\n");
  return send(ctx, `📜 <b>PASS HISTORY</b>\n${list || "Nenhuma alteração manual registrada."}`, kb([nav("m:pass")]));
}

// ---------------------------------------------------------------- hero shop (menu driven)
const RARITY_LABEL: Record<string, string> = {
  common: "COMUM",
  uncommon: "INCOMUM",
  rare: "RARO",
  epic: "ÉPICO",
  legendary: "LENDÁRIO",
  mythic: "MÍTICO",
  ancestral: "ANCESTRAL",
};
const RARITY_ORDER = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "ancestral"];
const pct = (n: unknown) => Number(n ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 4 });

type HeroShopOverview = {
  config: {
    prices: Record<string, number>;
    odds: Record<string, number>;
    baseOdds?: Record<string, number>;
    rarityEnabled?: Record<string, boolean>;
  };
  rarity_flags?: Record<string, boolean>;
  heroes_total: number;
  heroes_enabled: number;
  by_rarity: Record<string, number>;
};
// Rarities that can be switched on/off in the shop. Ancestral is event/admin exclusive.
const SHOP_RARITIES = ["common", "uncommon", "rare", "epic", "legendary", "mythic"];
type RarityFlagRow = { rarity: string; enabled: boolean; base: number; effective: number; heroes: number };
async function heroShopConfig(ctx: Ctx): Promise<HeroShopOverview> {
  return (await rpc("admin_hero_shop_overview", { p_admin_id: ctx.adminId })) as HeroShopOverview;
}

async function heroShopHub(ctx: Ctx) {
  const d = await heroShopConfig(ctx);
  const p = d.config.prices;
  const text = [
    "🏪 <b>LOJA DE HERÓIS</b>",
    "",
    `💰 1x <b>${fmt(p["1"])} FC</b> · 5x <b>${fmt(p["5"])} FC</b> · 10x <b>${fmt(p["10"])} FC</b>`,
    `🎲 ${SHOP_RARITIES.map((r) => `${(d.rarity_flags?.[r] ?? true) ? "🟢" : "🔴"} ${RARITY_LABEL[r]} ${pct(d.config.odds[r] ?? 0)}%`).join(" · ")}`,
    `🦸 ${fmt(d.heroes_enabled)} heróis ativos de ${fmt(d.heroes_total)}`,
    "",
    "Tudo aqui vale na hora no Mini App, sem deploy.",
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      [{ t: "💰 PREÇOS DE RECRUTAMENTO", d: "hs:prices" }],
      [{ t: "🎲 CHANCES DE INVOCAÇÃO", d: "hs:odds" }],
      [{ t: "🎚 RARIDADES", d: "hr:home" }],
      [{ t: "🦸 EDITAR HERÓIS", d: "hs:list" }],
      [{ t: "🧬 DUPLICATE FUSE SETTINGS", d: "hs:fusion" }],
      [{ t: "⚗️ RARITY FUSION SETTINGS", d: "rf:home" }],
      [
        { t: "➕ CRIAR HERÓI", d: "hw:new" },
        { t: "✏️ EDITAR HERÓI", d: "hw:edit" },
      ],
      [{ t: "📦 ITENS DA LOJA", d: "hs:store" }],
      nav(),
    ]),
  );
}

async function rarityFlags(ctx: Ctx): Promise<{ rarities: RarityFlagRow[]; total_effective: number }> {
  return await rpc("admin_hero_rarity_flags", { p_admin_id: ctx.adminId });
}

/** Availability switchboard: disabling a rarity keeps its base chance stored. */
async function rarityFlagsView(ctx: Ctx) {
  const d = await rarityFlags(ctx);
  const text = [
    "🎚 <b>RARIDADES DA LOJA</b>",
    "",
    ...d.rarities.map(
      (r) =>
        `${r.enabled ? "🟢" : "🔴"} <b>${RARITY_LABEL[r.rarity]}</b> — base ${pct(r.base)}% · loja ${r.enabled ? `${pct(r.effective)}%` : "fora"} · ${fmt(r.heroes)} heróis`,
    ),
    "",
    `Σ ativos: <b>${pct(d.total_effective)}%</b> (normalizado automaticamente).`,
    "",
    "Desativar não zera a chance base: a raridade sai da loja, das odds e do sorteio, e volta igual ao reativar.",
    "ANCESTRAL não entra aqui — segue exclusivo de eventos e presentes do admin.",
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      ...d.rarities.map((r) => [{ t: `${r.enabled ? "🟢" : "🔴"} ${RARITY_LABEL[r.rarity]}`, d: `hr:v:${r.rarity}` }]),
      nav("m:shop"),
    ]),
  );
}

async function rarityFlagDetail(ctx: Ctx, rarity: string) {
  const d = await rarityFlags(ctx);
  const row = d.rarities.find((r) => r.rarity === rarity);
  if (!row) return rarityFlagsView(ctx);
  const text = [
    `<b>${RARITY_LABEL[rarity]}</b>`,
    "",
    `Status atual: ${row.enabled ? "🟢 <b>ATIVO</b>" : "🔴 <b>DESATIVADO</b>"}`,
    `Chance base: <b>${pct(row.base)}%</b>`,
    `Na loja agora: <b>${row.enabled ? `${pct(row.effective)}%` : "—"}</b>`,
    `Heróis recrutáveis: <b>${fmt(row.heroes)}</b>`,
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      [row.enabled ? { t: "🔴 DESATIVAR", d: `hr:set:${rarity}:0` } : { t: "🟢 ATIVAR", d: `hr:set:${rarity}:1` }],
      [{ t: "⬅️ VOLTAR", d: "hr:home" }],
    ]),
  );
}

async function heroPricesView(ctx: Ctx) {
  const p = (await heroShopConfig(ctx)).config.prices;
  const text = [
    "🎯 <b>RECRUTAMENTO DE HERÓIS</b>",
    "",
    "Preço atual:",
    `1x — <b>${fmt(p["1"])} FC</b>`,
    `5x — <b>${fmt(p["5"])} FC</b>`,
    `10x — <b>${fmt(p["10"])} FC</b>`,
    "",
    "Cada pacote é independente, então dá para criar desconto no 5x e no 10x.",
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      [{ t: "✏️ ALTERAR 1x", d: "hp:1" }],
      [{ t: "✏️ ALTERAR 5x", d: "hp:5" }],
      [{ t: "✏️ ALTERAR 10x", d: "hp:10" }],
      [{ t: "🔄 RESET PADRÃO", d: "hs:resetp" }],
      nav("m:shop"),
    ]),
  );
}

async function heroOddsView(ctx: Ctx) {
  const d = await heroShopConfig(ctx);
  const o = d.config.odds;
  const total = RARITY_ORDER.filter((r) => r !== "ancestral").reduce((sum, r) => sum + Number(o[r] ?? 0), 0);
  const text = [
    "🎲 <b>CHANCES DE INVOCAÇÃO</b>",
    "",
    ...RARITY_ORDER.filter((r) => r !== "ancestral").map(
      (r) => `${RARITY_LABEL[r]} — <b>${pct(o[r])}%</b> (${fmt(d.by_rarity[r] ?? 0)} heróis)`,
    ),
    "",
    `Total: <b>${pct(total)}%</b> — precisa ser exatamente 100%.`,
    "ANCESTRAL — <b>0%</b> · exclusivo de eventos e presentes do admin.",
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      [
        { t: "COMUM", d: "ho:common" },
        { t: "INCOMUM", d: "ho:uncommon" },
      ],
      [
        { t: "RARO", d: "ho:rare" },
        { t: "ÉPICO", d: "ho:epic" },
      ],
      [
        { t: "LENDÁRIO", d: "ho:legendary" },
        { t: "MÍTICO", d: "ho:mythic" },
      ],
      [
        { t: "✏️ EDITAR TODAS", d: "ask:hodds" },
        { t: "🔄 RESET PADRÃO", d: "hs:reseto" },
      ],
      [{ t: "🕵️ CHANCES REAIS (SORTEIO)", d: "hs:roddz" }],
      nav("m:shop"),
    ]),
  );
}

/** Hidden roll odds: players keep seeing the public percentages, the server rolls with these. */
async function heroRealOddsView(ctx: Ctx) {
  const d = (await rpc("admin_hero_real_odds", { p_admin_id: ctx.adminId })) as any;
  const rates = d.rates ?? {};
  const odds = d.odds ?? {};
  const pub = d.publicOdds ?? {};
  const list = RARITY_ORDER.filter((r) => r !== "ancestral");
  const total = list.reduce((sum, r) => sum + Number(rates[r] ?? 0), 0);
  const text = [
    "🕵️ <b>CHANCES REAIS DO SORTEIO</b>",
    "",
    "Só o servidor usa estes valores. No jogo o jogador continua vendo as chances públicas.",
    "",
    ...list.map(
      (r) =>
        `${RARITY_LABEL[r]} — real <b>${pct(rates[r])}%</b> (efetivo ${pct(odds[r] ?? 0)}%) · vitrine ${pct(pub[r] ?? 0)}%`,
    ),
    "",
    `Total real: <b>${pct(total)}%</b> — precisa fechar 100%.`,
    d.custom ? "" : "⚠️ Ainda usando as chances públicas como fallback.",
  ]
    .filter(Boolean)
    .join("\n");
  return edit(
    ctx,
    text,
    kb([
      [{ t: "✏️ EDITAR CHANCES REAIS", d: "ask:hoddsreal" }],
      [{ t: "🎲 CHANCES PÚBLICAS", d: "hs:odds" }],
      nav("m:shop"),
    ]),
  );
}

/** DUPLICATE FUSE settings (same hero_key copies -> stars/ATK/HP/Power, rarity never changes). */
async function fusionView(ctx: Ctx) {
  const cfg = (await rpc("hero_fusion_config", {})) as any;
  const max = Number(cfg.max_stars ?? 5);
  const rows: string[] = [];
  for (let star = 1; star <= max; star += 1) {
    rows.push(
      `★${star} — +${cfg.bonus_percent?.[star] ?? 0}% ATK/HP · ${fmt(Number(cfg.cost_fc?.[star] ?? 0))} FC · ${cfg.duplicates?.[star] ?? 1} cópia(s) · Lv.máx ${cfg.level_cap?.[star] ?? 20}`,
    );
  }
  const text = [
    "🧬 <b>DUPLICATE FUSE SETTINGS</b>",
    "",
    "Cópias do MESMO herói · a raridade nunca muda.",
    "",
    `Máximo de estrelas: <b>★${max}</b>`,
    `Lv. máx ★0: <b>${cfg.level_cap?.["0"] ?? 20}</b>`,
    "",
    ...rows,
    "",
    "Os stats são recalculados a partir do multiplicador (nunca somam heróis).",
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      [{ t: "✏️ EDITAR CONFIG (JSON)", d: "ask:fusion" }],
      [{ t: "⚗️ RARITY FUSION SETTINGS", d: "rf:home" }],
      [{ t: "🔄 RESET PADRÃO", d: "fusr:1" }],
      nav("m:shop"),
    ]),
  );
}

const RF_SOURCES = ["common", "uncommon", "rare", "epic"] as const;
const RF_LABEL: Record<string, string> = {
  common: "COMMON",
  uncommon: "UNCOMMON",
  rare: "RARE",
  epic: "EPIC",
  legendary: "LEGENDARY",
};

/** Rarity fusion (5 heroes -> next rarity): cost, odds, compensation and hero pool, all live. */
async function rarityFusionView(ctx: Ctx) {
  const d = (await rpc("admin_rarity_fusion_overview", { p_admin_id: ctx.adminId })) as any;
  const cfg = d.config || {};
  const tiers = cfg.tiers || {};
  const rows = RF_SOURCES.filter((k) => tiers[k]).map((k) => {
    const t = tiers[k];
    return `${RF_LABEL[k]} → ${RF_LABEL[t.target] || String(t.target).toUpperCase()}\n   Custo: <b>${fmt(Number(t.cost_myth || 0))} MYTH</b> · Chance: <b>${pct(t.chance)}%</b> · Falha: <b>${fmt(Number(t.fragments || 0))} frag.</b>`;
  });
  const off = (d.pool || []).filter((h: any) => !h.enabled);
  const text = [
    "⚗️ <b>RARITY FUSION</b>",
    "",
    `Status: <b>${cfg.enabled === false ? "⛔ DESATIVADA" : "✅ ATIVA"}</b> · Heróis por fusão: <b>${cfg.required_heroes ?? 5}</b>`,
    "",
    ...rows,
    "",
    `📊 Tentativas: <b>${fmt(d.attempts)}</b> · Sucessos: <b>${fmt(d.successes)}</b> · FC queimado: <b>${fmt(d.fcBurned)}</b>`,
    `🚫 Fora do pool: <b>${off.length}</b>${
      off.length
        ? " — " +
          off
            .slice(0, 6)
            .map((h: any) => esc(h.name))
            .join(", ")
        : ""
    }`,
    "",
    "Lendário nunca funde em Ancestral.",
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      [{ t: "✏️ COMMON → UNCOMMON", d: "ask:rfcommon" }],
      [{ t: "✏️ UNCOMMON → RARE", d: "ask:rfuncommon" }],
      [{ t: "✏️ RARE → EPIC", d: "ask:rfrare" }],
      [{ t: "✏️ EPIC → LEGENDARY", d: "ask:rfepic" }],
      [
        {
          t: cfg.enabled === false ? "✅ ENABLE FUSION" : "⛔ DISABLE FUSION",
          d: cfg.enabled === false ? "rf:on" : "rf:off",
        },
      ],
      [
        { t: "🦸 HERO POOL", d: "ask:rfpool" },
        { t: "🧾 AUDITORIA", d: "rf:audit" },
      ],
      nav("m:shop"),
    ]),
  );
}

async function rarityFusionAudit(ctx: Ctx, ref?: string) {
  const rows = (await rpc("admin_rarity_fusion_audit", {
    p_admin_id: ctx.adminId,
    p_limit: 10,
    p_ref: ref || null,
  })) as any[];
  const text = [
    "🧾 <b>AUDITORIA — RARITY FUSION</b>",
    "",
    ...(rows.length
      ? rows.map((r) =>
          [
            `👤 ${r.player ? "@" + esc(r.player) : esc(r.name || "—")} · <code>${r.telegramId}</code>`,
            `   ${RF_LABEL[r.sourceRarity] || r.sourceRarity} → ${RF_LABEL[r.targetRarity] || r.targetRarity} · ${r.heroes} heróis · ${fmt(Number(r.costFc || 0))} FC`,
            `   Chance ${pct(r.chance)}% · Roll ${r.roll} · <b>${r.success ? "✅ SUCESSO" : "❌ FALHA"}</b>`,
            `   ${r.success ? "Herói: " + esc(r.rewardHero || "—") : "Fragmentos: " + fmt(Number(r.fragments || 0))} · ${String(r.createdAt).slice(0, 16).replace("T", " ")}`,
          ].join("\n"),
        )
      : ["Nenhuma fusão registrada."]),
  ].join("\n\n");
  return send(
    ctx,
    text,
    kb([[{ t: "🔎 FILTRAR JOGADOR", d: "ask:rfaudit" }], [{ t: "⚗️ RARITY FUSION", d: "rf:home" }], nav()]),
  );
}

// ---------------------------------------------------------------- hero wizard (no JSON, no manual urls)
// Every hero lives in the single central catalog (public.hero_catalog); the game reads only from it,
// so an image uploaded here shows up in shop, collection, PvP, boss, fusion and chests with no deploy.
const HW_RARITIES: [string, string][] = [
  ["common", "⚪ COMMON"],
  ["uncommon", "🟢 UNCOMMON"],
  ["rare", "🔵 RARE"],
  ["epic", "🟣 EPIC"],
  ["legendary", "🟡 LEGENDARY"],
  ["mythic", "🔴 MYTHIC"],
  ["ancestral", "🌟 ANCESTRAL"],
];
const HW_CLASSES: [string, string][] = [
  ["warrior", "⚔️ Warrior"],
  ["archer", "🏹 Archer"],
  ["tank", "🛡 Tank"],
  ["mage", "✨ Mage"],
  ["support", "💚 Support"],
  ["assassin", "🗡 Assassin"],
];
const HW_DEFAULT_STATS: Record<string, [number, number]> = {
  common: [100, 1000],
  uncommon: [125, 1250],
  rare: [160, 1600],
  epic: [210, 2100],
  legendary: [300, 3000],
  mythic: [420, 4200],
  ancestral: [580, 5800],
};
const HW_RARITY_LABEL = Object.fromEntries(HW_RARITIES) as Record<string, string>;
const HW_CLASS_LABEL = Object.fromEntries(HW_CLASSES) as Record<string, string>;
const HW_CANCEL = [{ t: "❌ CANCELAR", d: "cancel" }];

type HeroDraft = {
  mode: "create" | "quick" | "duplicate" | "edit";
  hero_key?: string;
  name?: string;
  image?: string;
  image_path?: string;
  rarity?: string;
  hero_class?: string;
  base_atk?: number;
  base_hp?: number;
  in_shop?: boolean;
  price_fc?: number | null;
  enabled?: boolean;
  field?: string;
};

/** Persists the wizard step before answering, so the next message is always interpreted correctly. */
async function hwStep(ctx: Ctx, step: string, draft: HeroDraft, text: string, rows: { t: string; d: string }[][] = []) {
  await setSession(ctx, "herowiz", step, draft as Record<string, unknown>);
  await send(ctx, text, kb([...rows, HW_CANCEL]));
}

async function heroManagementHub(ctx: Ctx) {
  const d = await rpc("admin_list_heroes", { p_admin_id: ctx.adminId, p_limit: 1, p_offset: 0 });
  await clearSession(ctx);
  return edit(
    ctx,
    [
      "🦸 <b>HERO MANAGEMENT</b>",
      `Catálogo central: <b>${fmt(d.total)}</b> heróis.`,
      "",
      "Tudo por botões: nome, foto enviada aqui no Telegram, raridade, classe, stats e loja.",
      "A imagem enviada aparece automaticamente em toda a Mythreon (loja, coleção, PvP, chefe, fusão, baús).",
    ].join("\n"),
    kb([
      [{ t: "➕ CREATE HERO", d: "hw:new" }],
      [{ t: "⚡ QUICK CREATE", d: "hw:quick" }],
      [{ t: "✏️ EDIT HERO", d: "hw:edit" }],
      [{ t: "📋 DUPLICATE HERO", d: "hw:dup" }],
      [{ t: "🛡 PROGRESSÃO (XP / NÍVEL)", d: "hprog:hub" }],
      [{ t: "⚖️ GAME BALANCE (RARIDADES)", d: "gbal:hub" }],
      [{ t: "⚔️ NFT HEROES (EXCLUSIVOS)", d: "nfth:hub" }],
      [{ t: "🛒 HERO SHOP", d: "m:shop" }],
      [{ t: "📚 ALL HEROES", d: "m:herolist" }],
      nav(),
    ]),
  );
}

async function hwAskName(ctx: Ctx, draft: HeroDraft) {
  const title =
    draft.mode === "quick"
      ? "⚡ <b>QUICK CREATE</b>"
      : draft.mode === "duplicate"
        ? "📋 <b>DUPLICAR HERÓI</b>"
        : "🦸 <b>CRIAR NOVO HERÓI</b>";
  return hwStep(ctx, "waiting_name", draft, `${title}\n\nDigite o <b>nome do herói</b>:`);
}

async function hwAskImage(ctx: Ctx, draft: HeroDraft) {
  return hwStep(
    ctx,
    "waiting_image",
    draft,
    `🖼 <b>ENVIE A IMAGEM DO HERÓI</b>\n\nEnvie a foto diretamente nesta conversa.\nHerói: <b>${esc(draft.name)}</b>`,
    [[{ t: "⏭ PULAR", d: "hw:skipimg" }]],
  );
}

async function hwAskRarity(ctx: Ctx, draft: HeroDraft) {
  return hwStep(
    ctx,
    "waiting_rarity",
    draft,
    `⭐ <b>RARIDADE</b> de <b>${esc(draft.name)}</b>:`,
    HW_RARITIES.map(([k, label]) => [{ t: label, d: `hw:rar:${k}` }]),
  );
}

async function hwAskClass(ctx: Ctx, draft: HeroDraft) {
  return hwStep(
    ctx,
    "waiting_class",
    draft,
    `🎭 <b>CLASSE</b> de <b>${esc(draft.name)}</b>:`,
    HW_CLASSES.map(([k, label]) => [{ t: label, d: `hw:cls:${k}` }]),
  );
}

async function hwAskAtk(ctx: Ctx, draft: HeroDraft) {
  return hwStep(ctx, "waiting_atk", draft, `⚔️ <b>ATK</b>\n\nEnvie o ataque base (ex.: <code>120</code>):`);
}

async function hwAskHp(ctx: Ctx, draft: HeroDraft) {
  return hwStep(ctx, "waiting_hp", draft, `❤️ <b>HP</b>\n\nEnvie a vida base (ex.: <code>1200</code>):`);
}

async function hwAskShop(ctx: Ctx, draft: HeroDraft) {
  return hwStep(ctx, "waiting_shop", draft, "🛒 <b>Disponível na Loja de Heróis?</b>", [
    [
      { t: "✅ SIM", d: "hw:shop:1" },
      { t: "❌ NÃO", d: "hw:shop:0" },
    ],
  ]);
}

async function hwAskPrice(ctx: Ctx, draft: HeroDraft) {
  return hwStep(
    ctx,
    "waiting_price",
    draft,
    "💰 <b>Preço em FC</b>\n\nEnvie apenas o número (ex.: <code>50000</code>):",
  );
}

function hwPreviewText(draft: HeroDraft) {
  const stats = HW_DEFAULT_STATS[draft.rarity || "common"] || HW_DEFAULT_STATS.common;
  const atk = Number(draft.base_atk ?? stats[0]);
  const hp = Number(draft.base_hp ?? stats[1]);
  return [
    draft.mode === "edit" ? "✏️ <b>HERO</b>" : "🦸 <b>NEW HERO</b>",
    "",
    `<b>${esc(draft.name)}</b>`,
    `Rarity: <b>${esc((HW_RARITY_LABEL[draft.rarity || "common"] || draft.rarity || "").replace(/^\S+\s/, ""))}</b>`,
    `Class: <b>${esc((HW_CLASS_LABEL[draft.hero_class || "warrior"] || draft.hero_class || "").replace(/^\S+\s/, ""))}</b>`,
    `⚔️ ATK: <b>${fmt(atk)}</b>`,
    `❤️ HP: <b>${fmt(hp)}</b>`,
    `🛒 Shop: <b>${draft.in_shop ? "YES" : "NO"}</b>`,
    draft.in_shop ? `💰 Price: <b>${fmt(draft.price_fc || 0)} FC</b>` : "💰 Price: —",
    draft.image ? "" : "\n⚠️ Sem imagem — o herói usará a arte padrão.",
  ]
    .filter(Boolean)
    .join("\n");
}

async function hwPreview(ctx: Ctx, draft: HeroDraft) {
  await setSession(ctx, "herowiz", "preview", draft as Record<string, unknown>);
  const markup = kb([
    [{ t: "✅ CREATE HERO", d: "hw:save" }],
    [
      { t: "✏️ EDIT", d: "hw:restart" },
      { t: "🖼 TROCAR IMAGEM", d: "hw:reimg" },
    ],
    HW_CANCEL,
  ]);
  const caption = hwPreviewText(draft);
  if (draft.image) {
    const r = await tg("sendPhoto", {
      chat_id: ctx.chatId,
      photo: draft.image,
      caption,
      parse_mode: "HTML",
      reply_markup: markup,
    });
    if (r?.ok) return;
  }
  return send(ctx, caption, markup);
}

/** Downloads the Telegram photo and stores it in the hero-images bucket. Never keeps base64 in the database. */
async function hwUploadPhoto(fileId: string, baseName: string): Promise<{ url: string; path: string }> {
  const info = await tg("getFile", { file_id: fileId });
  const filePath = info?.result?.file_path;
  if (!filePath) throw new Error("image_download_failed");
  const res = await fetch(`https://api.telegram.org/file/bot${BOT_TOKEN}/${filePath}`);
  if (!res.ok) throw new Error("image_download_failed");
  const bytes = new Uint8Array(await res.arrayBuffer());
  const ext = (filePath.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
  const contentType = ext === "png" ? "image/png" : ext === "webp" ? "image/webp" : "image/jpeg";
  const slug =
    (baseName || "hero")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 40) || "hero";
  const path = `heroes/${slug}-${Date.now()}.${ext}`;
  const up = await db.storage.from("hero-images").upload(path, bytes, { contentType, upsert: true });
  if (up.error) throw new Error(`image_upload_failed: ${up.error.message}`);
  // Bucket is private: a long-lived signed url keeps the art readable by every player without extra config.
  const signed = await db.storage.from("hero-images").createSignedUrl(path, 60 * 60 * 24 * 365 * 10);
  if (signed.error || !signed.data?.signedUrl) throw new Error("image_url_failed");
  return { url: signed.data.signedUrl, path };
}

async function hwSave(ctx: Ctx, draft: HeroDraft) {
  const stats = HW_DEFAULT_STATS[draft.rarity || "common"] || HW_DEFAULT_STATS.common;
  const atk = Number(draft.base_atk ?? stats[0]);
  const hp = Number(draft.base_hp ?? stats[1]);
  const key = draft.hero_key || (await rpc("admin_next_hero_key", { p_admin_id: ctx.adminId, p_name: draft.name }));
  const patch: Record<string, unknown> = {
    name: draft.name,
    rarity: draft.rarity || "common",
    hero_class: draft.hero_class || "warrior",
    base_atk: atk,
    base_hp: hp,
    power: Math.round(atk * 10 + hp),
    in_shop: !!draft.in_shop,
    price_fc: draft.in_shop ? Number(draft.price_fc || 0) : 0,
    enabled: draft.enabled ?? true,
  };
  if (draft.image) patch.image = draft.image;
  const r = await rpc("admin_upsert_hero", {
    p_admin_id: ctx.adminId,
    p_hero_key: key,
    p_patch: patch,
    p_reason: "wizard do bot admin",
  });
  await clearSession(ctx);
  return send(
    ctx,
    `✅ Herói salvo: <b>${esc(r.name)}</b>\n<code>${esc(r.hero_key)}</code> · ${esc(r.rarity)} · ⚔️ ${fmt(r.base_atk)} · ❤️ ${fmt(r.base_hp)}${r.in_shop ? ` · 🛒 ${fmt(r.price_fc)} FC` : ""}\n\nJá disponível na Mythreon (sem deploy).`,
    kb([[{ t: "✏️ EDITAR ESTE HERÓI", d: `hw:e:${r.hero_key}` }], [{ t: "🦸 HERO MANAGEMENT", d: "m:heroes" }], nav()]),
  );
}

async function hwHeroList(ctx: Ctx, query: string, next: "edit" | "dup") {
  const d = await rpc("admin_search_heroes", { p_admin_id: ctx.adminId, p_query: query || null, p_limit: 12 });
  const heroes = d.heroes as any[];
  if (!heroes.length) {
    return hwStep(
      ctx,
      next === "edit" ? "edit_search" : "dup_search",
      { mode: next === "edit" ? "edit" : "duplicate" },
      "🔎 Nenhum herói encontrado. Envie outro nome:",
    );
  }
  await clearSession(ctx);
  const rows = heroes.map((h) => [
    {
      t: `${h.enabled ? "" : "⛔ "}${h.name} · ${String(h.rarity).toUpperCase()}`,
      d: `hw:${next === "edit" ? "e" : "d"}:${h.hero_key}`,
    },
  ]);
  return send(
    ctx,
    `🦸 <b>SELECIONE O HERÓI</b> (${heroes.length})`,
    kb([...rows, [{ t: "🔎 PESQUISAR", d: next === "edit" ? "hw:edit" : "hw:dup" }], nav("m:heroes")]),
  );
}

async function hwEditMenu(ctx: Ctx, heroKey: string) {
  const h = await rpc("admin_hero_detail", { p_admin_id: ctx.adminId, p_hero_key: heroKey });
  await setSession(ctx, "herowiz", "edit_menu", { mode: "edit", hero_key: heroKey } as Record<string, unknown>);
  const text = [
    "✏️ <b>EDITAR HERÓI</b>",
    "",
    `<b>${esc(h.name)}</b> · <code>${esc(h.hero_key)}</code>`,
    `⭐ ${esc(String(h.rarity).toUpperCase())} · 🎭 ${esc(h.hero_class)}`,
    `⚔️ ATK ${fmt(h.base_atk)} · ❤️ HP ${fmt(h.base_hp)}`,
    `🛒 Loja: ${h.in_shop ? `✅ ${fmt(h.price_fc)} FC` : "❌"} · 👁 Ativo: ${h.enabled ? "✅" : "⛔"}`,
    `🎲 Recruit: ${String(h.rarity) === "ancestral" ? "⛔ ANCESTRAL (exclusivo evento/admin)" : h.recruit_enabled ? "✅" : "⛔"}`,
  ].join("\n");
  const markup = kb([
    [{ t: "🖼 Trocar imagem", d: "hw:f:image" }],
    [
      { t: "✏️ Nome", d: "hw:f:name" },
      { t: "⭐ Raridade", d: "hw:f:rarity" },
    ],
    [
      { t: "⚔️ ATK", d: "hw:f:atk" },
      { t: "❤️ HP", d: "hw:f:hp" },
    ],
    [
      { t: "🎭 Classe", d: "hw:f:class" },
      { t: "💰 Preço", d: "hw:f:price" },
    ],
    [
      { t: `🛒 Loja ${h.in_shop ? "ON→OFF" : "OFF→ON"}`, d: "hw:t:shop" },
      { t: `👁 Ativo ${h.enabled ? "ON→OFF" : "OFF→ON"}`, d: "hw:t:enabled" },
    ],
    ...(String(h.rarity) === "ancestral"
      ? []
      : [[{ t: `🎲 Recruit ${h.recruit_enabled ? "ON→OFF" : "OFF→ON"}`, d: "hw:t:recruit" }]]),
    [{ t: "🗑 Remover", d: "hw:del" }],
    [{ t: "📋 DUPLICAR", d: `hw:d:${h.hero_key}` }],
    nav("m:heroes"),
  ]);
  if (h.image && /^https?:\/\//.test(String(h.image))) {
    const r = await tg("sendPhoto", {
      chat_id: ctx.chatId,
      photo: h.image,
      caption: text,
      parse_mode: "HTML",
      reply_markup: markup,
    });
    if (r?.ok) return;
  }
  return send(ctx, text, markup);
}

/** Applies a single field change on an existing hero and returns to its menu. */
async function hwEditApply(ctx: Ctx, heroKey: string, patch: Record<string, unknown>) {
  await rpc("admin_upsert_hero", {
    p_admin_id: ctx.adminId,
    p_hero_key: heroKey,
    p_patch: patch,
    p_reason: "edição pelo bot admin",
  });
  return hwEditMenu(ctx, heroKey);
}

async function heroWizardCallback(ctx: Ctx, rest: string[]) {
  const action = rest[0];
  const arg = rest.slice(1).join(":");
  const session = await getSession(ctx);
  const draft: HeroDraft = (session?.action === "herowiz" ? session.context : {}) as HeroDraft;

  if (action === "new") return hwAskName(ctx, { mode: "create" });
  if (action === "quick") return hwAskName(ctx, { mode: "quick" });
  if (action === "edit")
    return hwStep(
      ctx,
      "edit_search",
      { mode: "edit" },
      "🔎 Envie o <b>nome</b> (ou parte) do herói.\nEnvie <code>*</code> para listar todos.",
    );
  if (action === "dup")
    return hwStep(
      ctx,
      "dup_search",
      { mode: "duplicate" },
      "🔎 Envie o <b>nome</b> do herói que será duplicado.\nEnvie <code>*</code> para listar todos.",
    );
  if (action === "e") return hwEditMenu(ctx, arg);

  if (action === "d") {
    const h = await rpc("admin_hero_detail", { p_admin_id: ctx.adminId, p_hero_key: arg });
    const stats = HW_DEFAULT_STATS[h.rarity] || HW_DEFAULT_STATS.common;
    return hwAskName(ctx, {
      mode: "duplicate",
      rarity: h.rarity,
      hero_class: h.hero_class || "warrior",
      base_atk: Number(h.base_atk ?? stats[0]),
      base_hp: Number(h.base_hp ?? stats[1]),
      in_shop: !!h.in_shop,
      price_fc: Number(h.price_fc || 0),
      enabled: true,
    });
  }

  if (action === "skipimg") {
    if (draft.mode === "edit") return hwEditMenu(ctx, draft.hero_key!);
    return draft.mode === "create" ? hwAskRarity(ctx, draft) : hwAskRarity(ctx, draft);
  }

  if (action === "rar") {
    draft.rarity = arg;
    if (draft.mode === "edit") return hwEditApply(ctx, draft.hero_key!, { rarity: arg });
    if (draft.mode === "create") return hwAskClass(ctx, draft);
    const stats = HW_DEFAULT_STATS[arg] || HW_DEFAULT_STATS.common;
    if (draft.base_atk == null) draft.base_atk = stats[0];
    if (draft.base_hp == null) draft.base_hp = stats[1];
    if (!draft.hero_class) draft.hero_class = "warrior";
    return hwPreview(ctx, draft);
  }

  if (action === "cls") {
    draft.hero_class = arg;
    if (draft.mode === "edit") return hwEditApply(ctx, draft.hero_key!, { hero_class: arg });
    return hwAskAtk(ctx, draft);
  }

  if (action === "shop") {
    draft.in_shop = arg === "1";
    if (!draft.in_shop) {
      draft.price_fc = 0;
      return hwPreview(ctx, draft);
    }
    return hwAskPrice(ctx, draft);
  }

  if (action === "restart") return hwAskName(ctx, { ...draft, name: undefined });
  if (action === "reimg") return hwAskImage(ctx, draft);
  if (action === "save") {
    if (!draft.name)
      return send(
        ctx,
        "⚠️ Fluxo expirado. Comece novamente.",
        kb([[{ t: "🦸 HERO MANAGEMENT", d: "m:heroes" }], nav()]),
      );
    return hwSave(ctx, draft);
  }

  if (action === "f") {
    const key = draft.hero_key;
    if (!key)
      return send(ctx, "⚠️ Selecione o herói novamente.", kb([[{ t: "✏️ EDIT HERO", d: "hw:edit" }], nav("m:heroes")]));
    const d2: HeroDraft = { mode: "edit", hero_key: key, field: arg };
    if (arg === "image")
      return hwStep(ctx, "edit_image", d2, "🖼 <b>TROCAR IMAGEM</b>\n\nEnvie a nova imagem nesta conversa.");
    if (arg === "rarity")
      return hwStep(
        ctx,
        "edit_rarity",
        d2,
        "⭐ Nova raridade:",
        HW_RARITIES.map(([k, l]) => [{ t: l, d: `hw:rar:${k}` }]),
      );
    if (arg === "class")
      return hwStep(
        ctx,
        "edit_class",
        d2,
        "🎭 Nova classe:",
        HW_CLASSES.map(([k, l]) => [{ t: l, d: `hw:cls:${k}` }]),
      );
    const labels: Record<string, string> = {
      name: "✏️ Envie o novo <b>nome</b>:",
      atk: "⚔️ Envie o novo <b>ATK</b>:",
      hp: "❤️ Envie o novo <b>HP</b>:",
      price: "💰 Envie o novo <b>preço em FC</b>:",
    };
    return hwStep(ctx, `edit_${arg}`, d2, labels[arg] || "Envie o novo valor:");
  }

  if (action === "t") {
    const key = draft.hero_key;
    if (!key)
      return send(ctx, "⚠️ Selecione o herói novamente.", kb([[{ t: "✏️ EDIT HERO", d: "hw:edit" }], nav("m:heroes")]));
    const h = await rpc("admin_hero_detail", { p_admin_id: ctx.adminId, p_hero_key: key });
    const patch =
      arg === "shop"
        ? { in_shop: !h.in_shop }
        : arg === "recruit"
          ? { recruit_enabled: !h.recruit_enabled }
          : { enabled: !h.enabled };
    return hwEditApply(ctx, key, patch);
  }

  if (action === "del") {
    if (!draft.hero_key)
      return send(ctx, "⚠️ Selecione o herói novamente.", kb([[{ t: "✏️ EDIT HERO", d: "hw:edit" }], nav("m:heroes")]));
    await setSession(ctx, "herowiz", "edit_menu", draft as Record<string, unknown>);
    return send(
      ctx,
      `🗑 Remover <b>${esc(draft.hero_key)}</b> do catálogo?\nSe algum jogador já possui o herói, ele será apenas desativado.`,
      kb([
        [
          { t: "🗑 CONFIRMAR", d: "hw:delyes" },
          { t: "⬅️ Voltar", d: `hw:e:${draft.hero_key}` },
        ],
      ]),
    );
  }
  if (action === "delyes") {
    if (!draft.hero_key)
      return send(ctx, "⚠️ Selecione o herói novamente.", kb([[{ t: "✏️ EDIT HERO", d: "hw:edit" }], nav("m:heroes")]));
    const r = await rpc("admin_delete_catalog_hero", {
      p_admin_id: ctx.adminId,
      p_hero_key: draft.hero_key,
      p_reason: "removido pelo bot admin",
    });
    await clearSession(ctx);
    return send(
      ctx,
      r.mode === "deleted"
        ? `🗑 <b>${esc(r.name)}</b> removido do catálogo.`
        : `⛔ <b>${esc(r.name)}</b> desativado (${fmt(r.owned)} jogadores possuem este herói).`,
      kb([[{ t: "🦸 HERO MANAGEMENT", d: "m:heroes" }], nav()]),
    );
  }

  return heroManagementHub(ctx);
}

/** Text replies inside the wizard: the persisted step decides the meaning, never the menu. */
async function heroWizardText(ctx: Ctx, step: string, draft: HeroDraft, text: string) {
  const num = () => {
    const v = parseAmount(text);
    if (!Number.isFinite(v) || v < 0) return null;
    return Math.round(v);
  };
  switch (step) {
    case "waiting_name": {
      if (text.length < 2) return hwStep(ctx, "waiting_name", draft, "⚠️ Nome muito curto. Digite o nome do herói:");
      draft.name = text.slice(0, 60);
      return hwAskImage(ctx, draft);
    }
    case "waiting_rarity":
      return hwAskRarity(ctx, draft);
    case "waiting_class":
      return hwAskClass(ctx, draft);
    case "waiting_atk": {
      const v = num();
      if (!v) return hwStep(ctx, "waiting_atk", draft, "⚠️ Envie um número válido para o ATK:");
      draft.base_atk = v;
      return hwAskHp(ctx, draft);
    }
    case "waiting_hp": {
      const v = num();
      if (!v) return hwStep(ctx, "waiting_hp", draft, "⚠️ Envie um número válido para o HP:");
      draft.base_hp = v;
      return hwAskShop(ctx, draft);
    }
    case "waiting_price": {
      const v = num();
      if (v == null) return hwStep(ctx, "waiting_price", draft, "⚠️ Envie um número válido de FC:");
      draft.price_fc = v;
      return hwPreview(ctx, draft);
    }
    case "waiting_shop":
      return hwAskShop(ctx, draft);
    case "waiting_image":
      return hwAskImage(ctx, draft);
    case "edit_search":
      return hwHeroList(ctx, text === "*" ? "" : text, "edit");
    case "dup_search":
      return hwHeroList(ctx, text === "*" ? "" : text, "dup");
    case "edit_name":
      return hwEditApply(ctx, draft.hero_key!, { name: text.slice(0, 60) });
    case "edit_atk": {
      const v = num();
      if (!v) return hwStep(ctx, "edit_atk", draft, "⚠️ Envie um número válido para o ATK:");
      return hwEditApply(ctx, draft.hero_key!, { base_atk: v, power: Math.round(v * 10) });
    }
    case "edit_hp": {
      const v = num();
      if (!v) return hwStep(ctx, "edit_hp", draft, "⚠️ Envie um número válido para o HP:");
      return hwEditApply(ctx, draft.hero_key!, { base_hp: v });
    }
    case "edit_price": {
      const v = num();
      if (v == null) return hwStep(ctx, "edit_price", draft, "⚠️ Envie um número válido de FC:");
      return hwEditApply(ctx, draft.hero_key!, { price_fc: v, in_shop: v > 0 });
    }
    case "edit_image":
      return hwStep(ctx, "edit_image", draft, "🖼 Envie a nova imagem como <b>foto</b> nesta conversa.");
    default:
      return heroManagementHub(ctx);
  }
}

/** Photos are only meaningful while the wizard is waiting for one. */
async function heroWizardPhoto(ctx: Ctx, step: string, draft: HeroDraft, fileId: string) {
  const uploaded = await hwUploadPhoto(fileId, draft.name || draft.hero_key || "hero");
  draft.image = uploaded.url;
  draft.image_path = uploaded.path;
  if (step === "edit_image" && draft.hero_key) {
    await send(ctx, "✅ Imagem atualizada — já aparece no jogo.");
    return hwEditApply(ctx, draft.hero_key, { image: uploaded.url });
  }
  if (draft.mode === "edit" && draft.hero_key) return hwEditApply(ctx, draft.hero_key, { image: uploaded.url });
  await send(ctx, "✅ Imagem recebida e armazenada.");
  if (draft.mode === "create") return hwAskRarity(ctx, draft);
  if (draft.mode === "duplicate" && draft.rarity) return hwPreview(ctx, draft);
  return hwAskRarity(ctx, draft);
}

// ---------------------------------------------------------------- clans module (RPC admin_clans)
const clanRpc = (ctx: Ctx, action: string, ref: string | null = null, payload: Record<string, unknown> = {}) =>
  rpc("admin_clans", { p_admin_id: ctx.adminId, p_action: action, p_ref: ref, p_payload: payload }) as Promise<any>;

const CLAN_JOIN_LABEL: Record<string, string> = { open: "ABERTO", approval: "APROVAÇÃO", closed: "FECHADO" };

const clanRow = (c: any) =>
  `${c.suspended ? "⛔" : "🏰"} <b>${esc(c.name)}</b> [${esc(c.tag)}] · NV${c.level} · ${fmt(c.members)}/${fmt(c.memberLimit)} · ${fmt(c.clanPoints)} pts`;

function clanListText(title: string, clans: any[]) {
  if (!clans?.length) return `${title}\n\nNenhum clã encontrado.`;
  return `${title}\n\n${clans
    .map((c, i) => `${i + 1}. ${clanRow(c)}`)
    .join("\n")
    .slice(0, 3400)}`;
}

const clanPickerRows = (clans: any[]) =>
  clans.slice(0, 10).map((c: any) => [{ t: `${c.suspended ? "⛔" : "🏰"} ${c.name} [${c.tag}]`, d: `cl:d:${c.id}` }]);

async function clansHub(ctx: Ctx) {
  const d = await clanRpc(ctx, "list");
  const total = (d.clans || []).length;
  return edit(
    ctx,
    `🏰 <b>CLÃS</b>\nGestão completa dos clãs do Mythreon.\nClãs listados: <b>${fmt(total)}</b>${total ? `\n\n🥇 ${clanRow(d.clans[0])}` : ""}`,
    kb([
      [
        { t: "📋 ALL CLANS", d: "cl:all" },
        { t: "🔎 SEARCH CLAN", d: "ask:clsearch" },
      ],
      [{ t: "📈 CLAN RANKING", d: "cl:rank" }],
      [{ t: "⚙️ CONFIGURAÇÃO DO CLÃ", d: "cl:cfg" }],
      [{ t: "🛡 CLAN ANTI-ABUSE", d: "cl:aa" }],
      [{ t: "🔥 CLAN HUB (COLETIVO)", d: "cl:hub" }],
      [{ t: "📜 AUDIT", d: "cl:audit" }],
      nav(),
    ]),
  );
}

// ---------------------------------------------------------------- 🎉 EVENTS (special events: independent from the weekly pool)
const evRpc = (ctx: Ctx, action: string, ref: string | null = null, payload: Record<string, unknown> = {}) =>
  rpc("admin_events", { p_admin_id: ctx.adminId, p_action: action, p_ref: ref, p_payload: payload }) as Promise<any>;

const EV_STATUS: Record<string, string> = {
  scheduled: "🕒 AGENDADO",
  active: "🟢 ATIVO",
  finished: "🏁 ENCERRADO",
  cancelled: "⛔ CANCELADO",
};
const evDate = (v: unknown) =>
  String(v ?? "")
    .slice(0, 16)
    .replace("T", " ");

function eventsText(d: any) {
  const e = d.event;
  if (!e)
    return "🎉 <b>EVENTOS ESPECIAIS</b>\n\nNenhum evento cadastrado ainda.\nCrie o primeiro com “➕ CRIAR EVENTO”.";
  const rules = e.rules || {};
  const dist = Array.isArray(rules.distribution) ? rules.distribution : [];
  const pay = d.payoutSummary || {};
  return [
    "🎉 <b>EVENTOS ESPECIAIS</b>",
    "<i>Camada independente — não afeta a Pool Semanal.</i>",
    "",
    `🏆 <b>${esc(e.name)}</b> ${EV_STATUS[e.status] ?? esc(e.status)}`,
    `<code>${esc(e.eventKey)}</code> · tipo <code>${esc(e.type)}</code>`,
    `💎 Prêmio total: <b>${fmt(e.prizePoolTon)} TON</b>`,
    `📅 ${evDate(e.startsAt)} → ${evDate(e.endsAt)}`,
    "",
    `👥 Participantes válidos: <b>${fmt(d.participantCount)}</b>`,
    `🤝 Convites válidos no total: <b>${fmt(d.totalValidReferrals)}</b>`,
    `🛡 Regras: mín. ${rules.minDailyQuests ?? 1} daily quest · TOP ${rules.topLimit ?? 100} · modo <b>${esc(rules.distributionMode ?? "fixed")}</b>`,
    dist.length
      ? `🏅 Faixas: ${dist
          .slice(0, 6)
          .map((x: any) => `#${x.from}${x.to !== x.from ? "-" + x.to : ""}=${x.ton ?? x.totalTon}`)
          .join(" · ")}${dist.length > 6 ? " …" : ""}`
      : "",
    "",
    `💸 Pagamentos: ${fmt(pay.rows)} linhas · pendentes ${fmt(pay.pending)} · pagos ${fmt(pay.paid)} (${fmt(pay.paidTon)} TON) · falhas ${fmt(pay.failed)}`,
    "",
    "<b>TOP 10</b>",
    (d.ranking || [])
      .slice(0, 10)
      .map(
        (r: any) =>
          `${r.position}. ${esc(r.username ? "@" + r.username : r.name)} — ${fmt(r.validReferrals)} convites · ${fmt(r.rewardTon)} TON`,
      )
      .join("\n") || "—",
  ]
    .filter(Boolean)
    .join("\n");
}

async function eventsHub(ctx: Ctx, ref: string | null = null, editing = true) {
  const d = await evRpc(ctx, "view", ref, { limit: 10 });
  const key = d.event?.eventKey ?? "";
  const markup = kb([
    [
      { t: "➕ CRIAR EVENTO", d: "ask:evcreate" },
      { t: "📋 TODOS OS EVENTOS", d: "ev:list" },
    ],
    [
      { t: "💎 EDITAR PRÊMIO", d: `ask:evprize|${key}` },
      { t: "📅 EDITAR DATAS", d: `ask:evdates|${key}` },
    ],
    [
      { t: "🛡 EDITAR REGRAS", d: `ask:evrules|${key}` },
      { t: "🏅 TABELA DE PRÊMIOS", d: `ask:evdist|${key}` },
    ],
    [
      { t: "📈 RANKING TOP 100", d: `ev:rank|${key}` },
      { t: "📜 AUDITORIA", d: "ev:audit" },
    ],
    [
      { t: "🏁 ENCERRAR + SNAPSHOT", d: `evconfirm:finish|${key}` },
      { t: "💸 DISTRIBUIR", d: `evconfirm:distribute|${key}` },
    ],
    [{ t: "⛔ CANCELAR EVENTO", d: `evconfirm:cancel|${key}` }],
    nav(),
  ]);
  const text = eventsText(d);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function eventsList(ctx: Ctx) {
  const d = await evRpc(ctx, "list");
  const rows = (d.events || []) as any[];
  const body =
    rows
      .map(
        (e) =>
          `• ${EV_STATUS[e.status] ?? e.status} <b>${esc(e.name)}</b>\n   <code>${esc(e.eventKey)}</code> · ${fmt(e.prizePoolTon)} TON · ${evDate(e.startsAt)} → ${evDate(e.endsAt)}`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `📋 <b>TODOS OS EVENTOS</b>\n${body}`,
    kb([
      ...rows
        .slice(0, 8)
        .map((e) => [
          { t: `${e.status === "active" ? "🟢" : "•"} ${e.name}`.slice(0, 40), d: `ev:open|${e.eventKey}` },
        ]),
      nav("m:events"),
    ]),
  );
}

async function eventsRanking(ctx: Ctx, ref: string | null) {
  const d = await evRpc(ctx, "view", ref, { limit: 100 });
  const body =
    (d.ranking || [])
      .map(
        (r: any) =>
          `${r.position}. ${esc(r.username ? "@" + r.username : r.name)} — ${fmt(r.validReferrals)} · ${fmt(r.rewardTon)} TON`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `📈 <b>RANKING TOP 100</b>\n${esc(d.event?.name ?? "")}\n\n${body}`.slice(0, 3800),
    kb([nav("m:events")]),
  );
}

async function eventsAudit(ctx: Ctx) {
  const d = await evRpc(ctx, "view", null, { limit: 1 });
  const body =
    (d.audit || [])
      .map((a: any) => `• ${evDate(a.at)} <code>${esc(a.action)}</code> ${esc(JSON.stringify(a.value)).slice(0, 90)}`)
      .join("\n") || "—";
  return edit(
    ctx,
    `📜 <b>AUDITORIA DE EVENTOS</b>\n${body}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "ev:audit" }], nav("m:events")]),
  );
}

// ---------------------------------------------------------------- 💳 PAYMENT RECOVERY
// Manual fallback for payments the automatic blockchain reconciler did not resolve.
// Every action is idempotent (a second approval only answers "already processed"),
// requires a reason + explicit confirmation, and is written to payment_recovery_audit.
const prRpc = (ctx: Ctx, action: string, ref: string | null = null, payload: Record<string, unknown> = {}) =>
  rpc("admin_payment_recovery", {
    p_admin_id: ctx.adminId,
    p_action: action,
    p_ref: ref,
    p_payload: payload,
  }) as Promise<any>;

// ---------------------------------------------------------------- 🛒 marketplace (FC only)
const MK_TYPE: Record<string, string> = { hero: "🦸", pet: "🐲", item: "🎒" };
const mkLine = (l: any) =>
  `${MK_TYPE[l.itemType] ?? "•"} <b>${esc(l.name)}</b> ${l.rarity ? `· ${esc(l.rarity)}` : ""}\n   ${fmt(l.priceFc)} FC · ${esc(l.status)} · vendedor ${esc(l.seller ?? "—")}\n   <code>${esc(l.id)}</code>`;

async function marketHub(ctx: Ctx, status = "active") {
  const o = (await rpc("admin_market_overview", { p_admin_id: ctx.adminId })) as any;
  const listings = (await rpc("admin_market_listings", {
    p_admin_id: ctx.adminId,
    p_status: status,
    p_limit: 10,
  })) as any[];
  const s = o.settings || {};
  const st = o.status || {};
  const enabled = st.enabled !== false;
  const min = s.minPrice || {};
  const body = (listings || []).map(mkLine).join("\n") || "—";
  return edit(
    ctx,
    [
      "🛒 <b>MARKETPLACE (FC)</b>",
      `Status: ${enabled ? "🟢 <b>MARKET ATIVO</b>" : "🔴 <b>MARKET EM MANUTENÇÃO</b>"}`,
      `Admin bypass: <b>${fmt(st.bypassCount ?? 1)}</b> user(s)`,
      `Taxa atual: <b>${Number(s.feePercent ?? 5)}%</b> (queimada, não vai para a pool TON)`,
      `Limite por jogador: <b>${fmt(s.maxActiveListings ?? 20)}</b> anúncios ativos`,
      `Preço mínimo: herói ${fmt(min.hero ?? 0)} FC · pet ${fmt(min.pet ?? 0)} FC · item ${fmt(min.item ?? 0)} FC`,
      "",
      `Ativos <b>${fmt(o.active)}</b> · vendidos ${fmt(o.sold)} · cancelados ${fmt(o.cancelled)}`,
      `Volume total: <b>${fmt(o.volumeFc)} FC</b> · queimado ${fmt(o.burnedFc)} FC`,
      "",
      `<b>${status === "all" ? "ÚLTIMOS" : status.toUpperCase()}</b>`,
      body.slice(0, 2500),
    ].join("\n"),
    kb([
      [enabled ? { t: "🔴 DESATIVAR MARKET", d: "mk:toggle|off" } : { t: "🟢 ATIVAR MARKET", d: "mk:toggle|on" }],
      [
        { t: "🟢 ATIVOS", d: "mk:list|active" },
        { t: "🔵 VENDIDOS", d: "mk:list|sold" },
        { t: "⚪️ TODOS", d: "mk:list|all" },
      ],
      [
        { t: "🔍 BUSCAR ANÚNCIO", d: "ask:mksearch" },
        { t: "👤 POR JOGADOR", d: "ask:mkuser" },
      ],
      [
        { t: "💸 TAXA DO MERCADO", d: "ask:mkfee" },
        { t: "🚧 LIMITE DE ANÚNCIOS", d: "ask:mklimit" },
      ],
      [
        { t: "🏷 PREÇO MÍNIMO", d: "ask:mkmin" },
        { t: "🗑 CANCELAR ANÚNCIO", d: "ask:mkcancel" },
      ],
      [{ t: "🏪 MARKET FEES", d: "mk:revenue" }],
      [
        { t: "📜 AUDITORIA DE VENDAS", d: "mk:audit" },
        { t: "🛡 MARKET SECURITY", d: "mk:sec" },
      ],
      [{ t: "🔨 LEILÃO (TON)", d: "auc:hub" }],
      nav(),
    ]),
  );
}

/**
 * AUCTION hub — the auction trades ONLY internal TON (never FC, never TonConnect).
 * Every value here is applied instantly by `admin_auction_set`; no deploy needed.
 */
async function auctionHub(ctx: Ctx) {
  const o = (await rpc("admin_auction_overview", { p_telegram_id: ctx.adminId })) as any;
  const s = o.settings || {};
  const on = s.enabled !== false;
  return edit(
    ctx,
    [
      "🔨 <b>LEILÃO (TON INTERNO)</b>",
      `Status: ${on ? "🟢 <b>ATIVO</b>" : "🔴 <b>DESATIVADO</b>"}`,
      `Taxa: <b>${Number(s.feePercent ?? 5)}%</b> em TON`,
      `Lance inicial mínimo: <b>${Number(s.minStartingBidTon ?? 0.1)} TON</b>`,
      `Incremento mínimo: <b>${Number(s.minIncrementTon ?? 0.1)} TON</b>`,
      `Anti-snipe: ${s.antiSnipeEnabled === false ? "🔴 off" : `🟢 janela <b>${Number(s.antiSnipeWindowMinutes ?? 2)}min</b> · extensão <b>${Number(s.antiSnipeExtensionMinutes ?? 2)}min</b>`}`,
      `Durações: <b>${(s.durations || []).join("h · ")}h</b>`,
      "",
      `Ativos <b>${fmt(o.active)}</b> · vendidos ${fmt(o.sold)} · expirados ${fmt(o.expired)}`,
      `Volume: <b>${Number(o.volumeTon ?? 0)} TON</b> · taxa arrecadada <b>${Number(o.feeTon ?? 0)} TON</b>`,
    ].join("\n"),
    kb([
      [on ? { t: "🔴 DESATIVAR LEILÃO", d: "auc:toggle|off" } : { t: "🟢 ATIVAR LEILÃO", d: "auc:toggle|on" }],
      [
        { t: "💸 TAXA (%)", d: "ask:aucfee" },
        { t: "🏷 LANCE MÍNIMO", d: "ask:aucmin" },
      ],
      [
        { t: "➕ INCREMENTO MÍNIMO", d: "ask:aucinc" },
        { t: "⏱ DURAÇÕES", d: "ask:aucdur" },
      ],
      [
        s.antiSnipeEnabled === false
          ? { t: "🟢 ATIVAR ANTI-SNIPE", d: "auc:snipe|on" }
          : { t: "🔴 DESATIVAR ANTI-SNIPE", d: "auc:snipe|off" },
      ],
      [
        { t: "⏳ JANELA ANTI-SNIPE", d: "ask:aucwin" },
        { t: "⏩ EXTENSÃO", d: "ask:aucext" },
      ],
      [{ t: "🛒 MARKETPLACE", d: "m:market" }],
      nav(),
    ]),
  );
}

// Market fee revenue: the 5% never leaves the official hot wallet — this screen
// shows how much of that balance belongs to the game instead of to the players.
async function marketRevenue(ctx: Ctx) {
  const r = (await rpc("admin_market_revenue", { p_admin_id: ctx.adminId })) as any;
  const rev = r?.revenue || {};
  const ton = rev.feeTon || {};
  const fc = rev.feeFc || {};
  const s = rev.sales || {};
  return edit(
    ctx,
    [
      "🏪 <b>MARKET FEES</b>",
      "<i>Receita do jogo retida na hot wallet oficial (sem transferência extra).</i>",
      "",
      "💎 <b>TAXA EM TON</b>",
      `Hoje: <b>${fmtTon(ton.today)} TON</b>`,
      `7 dias: <b>${fmtTon(ton.days7)} TON</b>`,
      `30 dias: <b>${fmtTon(ton.days30)} TON</b>`,
      `Lifetime: <b>${fmtTon(ton.lifetime)} TON</b>`,
      "",
      "🪙 <b>TAXA EM FC</b>",
      `Hoje: <b>${fmt(fc.today)} FC</b> · 7d ${fmt(fc.days7)} FC · 30d ${fmt(fc.days30)} FC`,
      `Lifetime: <b>${fmt(fc.lifetime)} FC</b>`,
      "",
      "📊 <b>VOLUME</b>",
      `Vendas: <b>${fmt(s.count)}</b>`,
      `Gross: <b>${fmtTon(s.grossTon)} TON</b> · ${fmt(s.grossFc)} FC`,
      `Pago a vendedores: <b>${fmtTon(s.payoutTon)} TON</b> · ${fmt(s.payoutFc)} FC`,
      `TON externo (wallet): ${fmtTon(s.externalTon)} TON · interno: ${fmtTon(s.internalTon)} TON`,
    ].join("\n"),
    kb([[{ t: "🔄 ATUALIZAR", d: "mk:revenue" }], nav("m:market")]),
  );
}

async function marketAudit(ctx: Ctx) {
  const rows = (await rpc("admin_market_audit", { p_admin_id: ctx.adminId, p_limit: 15 })) as any[];
  const body =
    (rows || [])
      .map(
        (t: any) =>
          `${MK_TYPE[t.itemType] ?? "•"} <b>${esc(t.name)}</b> — ${fmt(t.priceFc)} FC\n   ${esc(t.seller ?? "—")} → ${esc(t.buyer ?? "—")} · taxa ${fmt(t.feeFc)} FC · recebeu ${fmt(t.received)} FC\n   ${prWhen(t.createdAt)}`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `📜 <b>AUDITORIA DO MERCADO</b>\n${body.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "mk:audit" }], nav("m:market")]),
  );
}

// ---------------------------------------------------------------- 🛡 MARKET SECURITY
// Read-only views + guarded actions on top of the market security RPCs. Every rule
// (risk scoring, escrow window, price bands, restrictions) lives in the database.
const mkFlags = (flags: unknown) => {
  const list = Array.isArray(flags) ? flags : [];
  return list.length ? list.map((f: unknown) => `<code>${esc(String(f))}</code>`).join(" ") : "—";
};
const mkRisk = (score: unknown) => {
  const value = Number(score ?? 0);
  return `${value >= 80 ? "🔴" : value >= 50 ? "🟠" : "🟡"} <b>${value}</b>`;
};

/** Writes one whitelisted security setting (the RPC validates the key and audits it). */
const mkSecSet = (ctx: Ctx, key: string, value: unknown) =>
  rpc("admin_market_set_security", { p_admin_id: ctx.adminId, p_key: key, p_value: value }) as Promise<any>;

async function mkSecurityHub(ctx: Ctx) {
  const o = (await rpc("admin_market_overview", { p_admin_id: ctx.adminId })) as any;
  const queue = (await rpc("admin_market_review_queue", { p_admin_id: ctx.adminId, p_limit: 5 })) as any[];
  const s = o.settings || {};
  const req = s.sellRequirements || {};
  const pair = s.pairLimits || {};
  const vel = s.velocity || {};
  const dyn = s.dynamicRange || {};
  const pending =
    (queue || [])
      .map(
        (t: any) =>
          `${MK_TYPE[t.itemType] ?? "•"} <code>#${esc(t.code)}</code> <b>${esc(t.name)}</b> — ${fmt(t.priceFc)} FC\n   ${mkRisk(t.riskScore)} · ${mkFlags(t.flags)}\n   ${esc(t.seller ?? "—")} → ${esc(t.buyer ?? "—")}`,
      )
      .join("\n") || "Nenhuma negociação em revisão. ✅";
  return edit(
    ctx,
    [
      "🛡 <b>MARKET SECURITY</b>",
      "<i>Antifraude do mercado entre jogadores. Tudo é validado no banco.</i>",
      "",
      `⏳ Retenção (escrow): <b>${fmt(s.settlementHours ?? 72)}h</b>`,
      `👤 Requisitos p/ vender: conta <b>${fmt(req.accountDays ?? 7)}d</b> · ativo <b>${fmt(req.activeDays ?? 3)}d</b> · heróis <b>${fmt(req.heroes ?? 5)}</b>`,
      `👥 Limite por par/24h: <b>${fmt(pair.tradesPerDay ?? 3)}</b> trades · <b>${fmt(pair.fcPerDay ?? 0)} FC</b>`,
      `⚡️ Velocidade: 5m <b>${fmt(vel.per5m ?? 5)}</b> · 1h <b>${fmt(vel.per1h ?? 15)}</b> · 24h <b>${fmt(vel.per24h ?? 40)}</b> · cooldown <b>${fmt(vel.cooldownMinutes ?? 360)}min</b>`,
      `📊 Faixa dinâmica: <b>${fmt(dyn.minPercent ?? 50)}%</b>–<b>${fmt(dyn.maxPercent ?? 200)}%</b> da mediana · min amostras <b>${fmt(dyn.minSamples ?? 5)}</b> · janela <b>${fmt(dyn.days ?? 30)}d</b>`,
      "",
      `<b>EM REVISÃO (${fmt((queue || []).length)})</b>`,
      pending.slice(0, 2200),
    ].join("\n"),
    kb([
      [
        { t: "🚨 FILA DE REVISÃO", d: "mk:review" },
        { t: "🔎 VER NEGOCIAÇÃO", d: "ask:mktrade" },
      ],
      [
        { t: "🏷 FAIXAS DE PREÇO", d: "mk:ranges" },
        { t: "✏️ DEFINIR FAIXA", d: "ask:mkrange" },
      ],
      [
        { t: "⛔️ RESTRINGIR JOGADOR", d: "ask:mkrestrict" },
        { t: "🧾 HISTÓRICO DO JOGADOR", d: "ask:mkhist" },
      ],
      [
        { t: "⏳ RETENÇÃO (H)", d: "ask:mksettle" },
        { t: "👤 REQUISITOS", d: "ask:mkreq" },
      ],
      [
        { t: "👥 LIMITE POR PAR", d: "ask:mkpair" },
        { t: "⚡️ VELOCIDADE", d: "ask:mkvel" },
      ],
      [{ t: "📊 FAIXA DINÂMICA", d: "ask:mkdyn" }],
      [{ t: "📜 AUDITORIA DE SEGURANÇA", d: "mk:secaudit" }],
      nav("m:market"),
    ]),
  );
}

async function mkReviewQueue(ctx: Ctx) {
  const queue = (await rpc("admin_market_review_queue", { p_admin_id: ctx.adminId, p_limit: 10 })) as any[];
  const rows = queue || [];
  const body =
    rows
      .map((t: any) =>
        [
          `${MK_TYPE[t.itemType] ?? "•"} <code>#${esc(t.code)}</code> <b>${esc(t.name)}</b> · ${esc(t.rarity ?? "—")}`,
          `   ${fmt(t.priceFc)} FC (mediana ${fmt(t.median ?? 0)}) · vendedor recebe ${fmt(t.receivedFc)} FC`,
          `   ${mkRisk(t.riskScore)} · ${mkFlags(t.flags)}`,
          `   ${esc(t.seller ?? "—")} (${fmt(t.sellerAccountDays)}d) → ${esc(t.buyer ?? "—")} (${fmt(t.buyerAccountDays)}d) · par 24h: ${fmt(t.pairTradesToday)}`,
        ].join("\n"),
      )
      .join("\n\n") || "Nenhuma negociação em revisão. ✅";
  return edit(
    ctx,
    `🚨 <b>FILA DE REVISÃO</b>\n${body.slice(0, 3400)}`,
    kb([
      ...rows.slice(0, 5).map((t: any) => [{ t: `🔎 #${t.code}`, d: `mk:trade|${t.code}` }]),
      [{ t: "🔄 ATUALIZAR", d: "mk:review" }],
      nav("mk:sec"),
    ]),
  );
}

async function mkTradeCard(ctx: Ctx, code: string, editing = true) {
  const d = (await rpc("admin_market_trade_detail", { p_admin_id: ctx.adminId, p_code: code })) as any;
  if (!d?.found) {
    const text = `⚠️ Nenhuma negociação encontrada para <code>${esc(code)}</code>.`;
    return editing ? edit(ctx, text, kb([nav("mk:sec")])) : send(ctx, text, kb([nav("mk:sec")]));
  }
  const text = [
    `🔎 <b>NEGOCIAÇÃO #${esc(d.code)}</b>`,
    `${MK_TYPE[d.itemType] ?? "•"} <b>${esc(d.name)}</b> · status <b>${esc(d.status)}</b>`,
    "",
    `Preço: <b>${fmt(d.priceFc)} FC</b> · taxa ${fmt(d.feeFc)} FC · vendedor recebe <b>${fmt(d.receivedFc)} FC</b>`,
    `Risco: ${mkRisk(d.riskScore)} · ${mkFlags(d.flags)}`,
    `Mesma carteira: <b>${d.sameWallet ? "SIM ⚠️" : "não"}</b>`,
    "",
    `Vendedor: ${esc(d.seller ?? "—")} (conta ${fmt(d.sellerAccountDays)}d)`,
    `Comprador: ${esc(d.buyer ?? "—")} (conta ${fmt(d.buyerAccountDays)}d)`,
    "",
    `Criada: ${prWhen(d.createdAt)}`,
    `Libera em: ${prWhen(d.settleAt)}${d.settledAt ? ` · liquidada ${prWhen(d.settledAt)}` : ""}`,
    d.reversedAt ? `Revertida: ${prWhen(d.reversedAt)}` : "",
    d.notes ? `Notas: <i>${esc(String(d.notes)).slice(0, 200)}</i>` : "",
  ]
    .filter(Boolean)
    .join("\n");
  const actions = ["review", "pending"].includes(String(d.status))
    ? [
        [
          { t: "✅ APROVAR E PAGAR", d: `mk:appr|${d.id}` },
          { t: "↩️ REVERTER", d: `mk:rev|${d.id}` },
        ],
      ]
    : [];
  const markup = kb([...actions, [{ t: "🚨 FILA", d: "mk:review" }], nav("mk:sec")]);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function mkRanges(ctx: Ctx) {
  const rows = (await rpc("admin_market_price_ranges", { p_admin_id: ctx.adminId })) as any[];
  const body =
    (rows || [])
      .map(
        (r: any) =>
          `${MK_TYPE[r.itemType] ?? "•"} <b>${esc(r.itemType)}</b> · ${esc(r.rarity)} — ${fmt(r.minFc)} a ${fmt(r.maxFc)} FC · recomendado ${r.recommendedFc ? fmt(r.recommendedFc) : "auto"}`,
      )
      .join("\n") || "Nenhuma faixa configurada (o mercado usa o preço mínimo global).";
  return edit(
    ctx,
    `🏷 <b>FAIXAS DE PREÇO</b>\n<i>A faixa exibida ao jogador se ajusta pela mediana das vendas recentes.</i>\n\n${body.slice(0, 3400)}`,
    kb([[{ t: "✏️ DEFINIR FAIXA", d: "ask:mkrange" }], [{ t: "🔄 ATUALIZAR", d: "mk:ranges" }], nav("mk:sec")]),
  );
}

async function mkSecurityAudit(ctx: Ctx) {
  const rows = (await rpc("admin_market_security_audit", { p_admin_id: ctx.adminId, p_limit: 15 })) as any[];
  const body =
    (rows || [])
      .map((a: any) =>
        [
          `• <code>${esc(a.event)}</code>${a.code ? ` #${esc(a.code)}` : ""} ${a.priceFc ? `— ${fmt(a.priceFc)} FC` : ""}`,
          `   ${mkRisk(a.riskScore)} · ${mkFlags(a.flags)}`,
          `   ${esc(a.seller ?? "—")} → ${esc(a.buyer ?? "—")} · ${prWhen(a.createdAt)}${a.adminId ? ` · admin <code>${esc(String(a.adminId))}</code>` : ""}`,
        ].join("\n"),
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `📜 <b>AUDITORIA DE SEGURANÇA</b>\n${body.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "mk:secaudit" }], nav("mk:sec")]),
  );
}

/** Player security dossier: shared wallets, referral links and trading pairs. */
async function mkUserHistory(ctx: Ctx, query: string) {
  const d = (await rpc("admin_market_user_history", { p_admin_id: ctx.adminId, p_query: query, p_limit: 10 })) as any;
  if (!d?.found) return send(ctx, `⚠️ Jogador não encontrado: <code>${esc(query)}</code>`, kb([nav("mk:sec")]));
  const p = d.player || {};
  const wallets =
    (d.sharedWallet || [])
      .map((w: any) => `⚠️ ${esc(w.label)} · <code>${esc(String(w.telegramId))}</code>`)
      .join("\n") || "nenhuma";
  const pairs =
    (d.pairs || [])
      .slice(0, 8)
      .map((s: any) => `• ${esc(s.seller)} → ${esc(s.buyer)} · ${fmt(s.trades)} trades · ${fmt(s.totalFc)} FC`)
      .join("\n") || "—";
  return send(
    ctx,
    [
      `🧾 <b>DOSSIÊ DE MERCADO</b>`,
      `👤 ${esc(p.label ?? "—")} · <code>${esc(String(p.telegramId ?? "—"))}</code>`,
      `Conta: <b>${fmt(p.accountDays)}d</b> · dias ativos <b>${fmt(p.activeDays)}</b> · trust <b>${esc(String(p.trust ?? "normal"))}</b>`,
      `Pendente em escrow: <b>${fmt(p.pendingFc)} FC</b>`,
      `Restrito até: ${prWhen(p.restrictedUntil)} · cooldown ${prWhen(p.cooldownUntil)}`,
      "",
      `<b>CARTEIRAS COMPARTILHADAS</b>\n${wallets}`,
      "",
      `Convidado por: ${esc(d.invitedBy ?? "—")} · indicados: <b>${fmt((d.referrals || []).length)}</b>`,
      "",
      `<b>PARES DE NEGOCIAÇÃO</b>\n${pairs}`,
    ]
      .join("\n")
      .slice(0, 3800),
    kb([[{ t: "⛔️ RESTRINGIR", d: "ask:mkrestrict" }], nav("mk:sec")]),
  );
}

const PR_KIND: Record<string, string> = {
  deposit: "💰 DEPOSIT",
  premium_egg: "🥚 PREMIUM_EGG",
  battle_pass: "🎟 BATTLE_PASS",
};

const prWhen = (v: unknown) =>
  v ? esc(new Date(String(v)).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })) : "—";
const prWho = (r: any) => esc(r.username ? "@" + r.username : r.name || r.telegramId || "—");
const prLine = (r: any) =>
  `• ${PR_KIND[r.kind] ?? esc(r.kind)} <code>#${esc(r.shortId)}</code> — ${fmt(r.amountTon)} TON\n   ${prWho(r)} · ${esc(r.status)}${r.paymentConfirmed ? " · 🔗 pago" : " · ⏳ sem tx"} · ${prWhen(r.createdAt)}`;

async function prHub(ctx: Ctx, kind: string | null = null, page = 1, editing = true) {
  const d = await prRpc(ctx, "list", null, { kind, page, size: 6 });
  const rows = (d.rows || []) as any[];
  const text = [
    "💳 <b>RECUPERAÇÃO DE PAGAMENTOS</b>",
    "<i>Somente pagamentos que não concluíram sozinhos. A verificação automática continua ativa.</i>",
    "",
    `🔎 Filtro: <b>${kind ? (PR_KIND[kind] ?? kind) : "TODOS"}</b> · pendentes: <b>${fmt(d.total)}</b> · página ${d.page}/${d.pages}`,
    "",
    rows.map(prLine).join("\n") || "Nenhum pagamento pendente. ✅",
  ].join("\n");
  const markup = kb(
    [
      ...rows.map((r) => [
        {
          t: `${PR_KIND[r.kind]?.slice(0, 2) ?? "•"} #${r.shortId} · ${Number(r.amountTon)} TON · ${r.username ? "@" + r.username : r.telegramId}`.slice(
            0,
            46,
          ),
          d: `pr:o|${r.orderId}`,
        },
      ]),
      [
        ...(d.page > 1 ? [{ t: "⬅️ ANTERIOR", d: `pr:pg|${kind ?? ""}|${d.page - 1}` }] : []),
        ...(d.page < d.pages ? [{ t: "PRÓXIMA ➡️", d: `pr:pg|${kind ?? ""}|${d.page + 1}` }] : []),
      ],
      [
        { t: "💰 DEPÓSITOS", d: "pr:f|deposit" },
        { t: "🥚 OVOS", d: "pr:f|premium_egg" },
      ],
      [
        { t: "🎟 PASSES", d: "pr:f|battle_pass" },
        { t: "🌐 TODOS", d: "pr:f|" },
      ],
      [
        { t: "🔎 PESQUISAR", d: "ask:prsearch" },
        { t: "🔄 ATUALIZAR", d: `pr:pg|${kind ?? ""}|${d.page}` },
      ],
      [
        { t: "✅ APROVADOS MANUALMENTE", d: "pr:res|approved" },
        { t: "⛔ RECUSADOS", d: "pr:res|rejected" },
      ],
      [
        { t: "📜 AUDITORIA", d: "pr:audit" },
        { t: "🛰 VERIFICAR BLOCKCHAIN", d: "pr:verify" },
      ],
      nav(),
    ].filter((row) => row.length),
  );
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function prSearch(ctx: Ctx, query: string) {
  const d = await prRpc(ctx, "search", query, {});
  const rows = (d.rows || []) as any[];
  return send(
    ctx,
    `🔎 <b>RESULTADO</b> — <code>${esc(query)}</code>\n\n${rows.map(prLine).join("\n") || "Nada encontrado."}`,
    kb([
      ...rows.map((r) => [{ t: `#${r.shortId} · ${PR_KIND[r.kind] ?? r.kind}`.slice(0, 46), d: `pr:o|${r.orderId}` }]),
      nav("m:precovery"),
    ]),
  );
}

async function prCard(ctx: Ctx, orderId: string, editing = true) {
  const d = await prRpc(ctx, "view", orderId, {});
  const o = d.order;
  const text = [
    `💳 <b>${PR_KIND[o.kind] ?? esc(o.kind)}</b> <code>#${esc(o.shortId)}</code>`,
    "",
    `👤 ${prWho(o)} · ID <code>${esc(o.telegramId)}</code>${o.banned ? " ⛔ BANIDO" : ""}`,
    `💎 Valor: <b>${fmt(o.amountTon)} TON</b>${o.expectedFc ? ` → <b>${fmt(o.expectedFc)} FC</b>` : ""}`,
    o.productLabel ? `📦 Produto: <b>${esc(o.productLabel)}</b>` : "",
    `📌 Situação: <b>${esc(o.status)}</b> · ${o.paymentConfirmed ? "🔗 tx registrada" : "⏳ sem tx on-chain"}`,
    o.txHash ? `🔗 <code>${esc(String(o.txHash).slice(0, 40))}</code>` : "",
    `🕒 Criado: ${prWhen(o.createdAt)} · pago: ${prWhen(o.paidAt)} · entregue: ${prWhen(o.deliveredAt)}`,
    o.manuallyApproved
      ? `✅ Aprovado manualmente por <code>${esc(o.approvedByAdmin)}</code> em ${prWhen(o.approvedAt)}\n   Motivo: ${esc(o.approvalReason ?? "—")}`
      : "",
    o.txConflict
      ? `\n🚨 <b>CONFLITO</b>: esta transação já foi usada em <b>${esc(o.txConflict)}</b>. Aprovar entregaria o prêmio duas vezes.`
      : "",
    o.finished ? "\n✅ Este pedido já foi concluído — nada a recuperar." : "",
    "",
    "<b>HISTÓRICO</b>",
    (d.audit || [])
      .map(
        (a: any) =>
          `• ${prWhen(a.at)} <code>${esc(a.action)}</code> ${esc(a.previousStatus)} → ${esc(a.newStatus)}${a.reason ? " · " + esc(a.reason) : ""}`,
      )
      .join("\n") || "—",
  ]
    .filter(Boolean)
    .join("\n");
  const actions = o.finished
    ? []
    : [
        [{ t: "✅ APROVAR MANUALMENTE", d: `pr:ask|approve|${orderId}` }],
        ...(o.deliveryPending ? [[{ t: "♻️ REENVIAR ENTREGA", d: `pr:ask|retry|${orderId}` }]] : []),
        [{ t: "⛔ RECUSAR", d: `pr:ask|reject|${orderId}` }],
      ];
  const markup = kb([...actions, [{ t: "🔄 ATUALIZAR", d: `pr:o|${orderId}` }], nav("m:precovery")]);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

const PR_ACTION_LABEL: Record<string, string> = {
  approve: "APROVAR MANUALMENTE e entregar o prêmio deste pagamento",
  retry: "REENVIAR a entrega deste pagamento já pago",
  reject: "RECUSAR este pagamento (nada será entregue)",
};

/** Reason first, then an explicit confirmation — the reason is kept in the persisted session. */
async function prAskReason(ctx: Ctx, action: string, orderId: string) {
  return ask(
    ctx,
    `prreason|${action}|${orderId}`,
    `📝 <b>${PR_ACTION_LABEL[action] ?? action}</b>\nEnvie o <b>motivo</b> desta ação (fica registrado na auditoria).\nEx.: <code>tx confirmada manualmente na tonviewer</code>`,
  );
}

async function prConfirm(ctx: Ctx, action: string, orderId: string, reason: string) {
  const d = await prRpc(ctx, "view", orderId, {});
  const o = d.order;
  await setSession(ctx, "prpending", "confirm", { action, orderId, reason });
  return send(
    ctx,
    [
      `⚠️ Confirme: <b>${PR_ACTION_LABEL[action] ?? action}</b>`,
      "",
      `${PR_KIND[o.kind] ?? esc(o.kind)} <code>#${esc(o.shortId)}</code> · ${prWho(o)}`,
      `💎 ${fmt(o.amountTon)} TON${o.expectedFc ? ` → ${fmt(o.expectedFc)} FC` : ""}`,
      `📝 Motivo: <i>${esc(reason)}</i>`,
      o.txConflict ? `\n🚨 CONFLITO detectado (${esc(o.txConflict)}) — a ação será bloqueada.` : "",
    ]
      .filter(Boolean)
      .join("\n"),
    kb([
      [
        { t: "✅ CONFIRMAR", d: `pr:go|${action}|${orderId}` },
        { t: "❌ Cancelar", d: "m:precovery" },
      ],
    ]),
  );
}

async function prRun(ctx: Ctx, action: string, orderId: string) {
  const session = await getSession(ctx);
  const reason = session?.action === "prpending" ? String((session.context as any)?.reason || "") : "";
  await clearSession(ctx);
  const d = await prRpc(ctx, action, orderId, { reason: reason || null });
  const status = d.result?.status;
  const messages: Record<string, string> = {
    delivered: "✅ Pagamento recuperado e prêmio entregue.",
    already_processed: "ℹ️ Nada feito: este pedido já havia sido processado (proteção contra duplicidade).",
    payment_conflict: `🚨 Bloqueado: a transação já foi usada em <b>${esc(d.result?.conflictWith ?? "")}</b>.`,
    rejected: "⛔ Pagamento recusado e registrado na auditoria.",
  };
  await send(ctx, messages[status] ?? `Resultado: <code>${esc(JSON.stringify(d.result)).slice(0, 500)}</code>`);
  return prCard({ ...ctx, messageId: undefined }, orderId, false);
}

async function prResolved(ctx: Ctx, mode: string) {
  const d = await prRpc(ctx, "resolved", null, { mode });
  const rows = (d.rows || []) as any[];
  const body =
    rows
      .map(
        (r) =>
          `• ${PR_KIND[r.kind] ?? esc(r.kind)} <code>#${esc(r.shortId)}</code> ${fmt(r.amountTon)} TON · ${prWho(r)}\n   ${esc(r.status)} · ${prWhen(r.approvedAt)} · ${esc(r.reason ?? "—")}`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `${mode === "rejected" ? "⛔ <b>RECUSADOS</b>" : "✅ <b>APROVADOS MANUALMENTE</b>"}\n\n${body}`.slice(0, 3800),
    kb([
      ...rows.slice(0, 8).map((r) => [{ t: `#${r.shortId} · ${r.status}`.slice(0, 46), d: `pr:o|${r.orderId}` }]),
      nav("m:precovery"),
    ]),
  );
}

async function prAudit(ctx: Ctx) {
  const d = await prRpc(ctx, "audit", null, {});
  const body =
    (d.rows || [])
      .map(
        (a: any) =>
          `• ${prWhen(a.at)} <code>${esc(a.action)}</code> ${esc(a.type)} #${esc(a.orderId)} · ${fmt(a.amountTon)} TON\n   ${esc(a.previousStatus)} → ${esc(a.newStatus)}${a.reason ? " · " + esc(a.reason) : ""}`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `📜 <b>AUDITORIA DE RECUPERAÇÃO</b>\n\n${body}`.slice(0, 3800),
    kb([[{ t: "🔄 ATUALIZAR", d: "pr:audit" }], nav("m:precovery")]),
  );
}

/** Runs the automatic on-chain reconciler on demand, before any manual decision. */
async function prVerifyOnChain(ctx: Ctx) {
  const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/ton-reconcile`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
    },
    body: JSON.stringify({ source: "admin_bot_payment_recovery" }),
  });
  const body = await res.text();
  await send(ctx, `🛰 <b>VERIFICAÇÃO ON-CHAIN</b> (${res.status})\n<code>${esc(body).slice(0, 700)}</code>`);
  return prHub(ctx, null, 1, false);
}

async function prCallback(ctx: Ctx, rest: string[]) {
  const [sub, a = "", b = ""] = rest.join(":").split("|");
  switch (sub) {
    case "o":
      return prCard(ctx, a);
    case "f":
      return prHub(ctx, a || null, 1);
    case "pg":
      return prHub(ctx, a || null, Math.max(1, Number(b) || 1));
    case "res":
      return prResolved(ctx, a || "approved");
    case "audit":
      return prAudit(ctx);
    case "verify":
      return prVerifyOnChain(ctx);
    case "ask":
      return prAskReason(ctx, a, b);
    case "go":
      return prRun(ctx, a, b);
    default:
      return prHub(ctx);
  }
}

/** Central clan configuration: creation cost + default member limit (never touches existing clans). */
async function clanSettingsView(ctx: Ctx, editing = true) {
  const s = (await rpc("admin_clan_settings", { p_admin_id: ctx.adminId, p_action: "get", p_value: null })) as any;
  const text = [
    "🏰 <b>CLAN SETTINGS</b>",
    "",
    "💰 Custo atual para criar clã:",
    `<b>${fmt(s.createCostFc)} FC</b>`,
    "",
    `👥 Limite de membros de novos clãs: <b>${fmt(s.defaultMemberLimit)}</b>`,
    `🏰 Clãs existentes: ${fmt(s.clans)} (não são afetados por estas alterações)`,
  ].join("\n");
  const markup = kb([
    [{ t: "💰 ALTERAR PREÇO DE CRIAÇÃO", d: "cl:ask:clcost" }],
    [{ t: "👥 ALTERAR LIMITE DE MEMBROS", d: "cl:ask:clsetlimit" }],
    nav("m:clans"),
  ]);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function clansList(ctx: Ctx, action: "list" | "ranking" | "search", ref: string | null = null) {
  const d = await clanRpc(ctx, action, ref);
  const title =
    action === "ranking"
      ? "📈 <b>CLAN RANKING</b> (nível · XP)"
      : action === "search"
        ? `🔎 <b>SEARCH CLAN</b> — <code>${esc(ref ?? "")}</code>`
        : "📋 <b>ALL CLANS</b>";
  return edit(
    ctx,
    clanListText(title, d.clans || []),
    kb([...clanPickerRows(d.clans || []), [{ t: "🔎 SEARCH CLAN", d: "ask:clsearch" }], nav("m:clans")]),
  );
}

async function clanCard(ctx: Ctx, ref: string, editing = true) {
  const d = await clanRpc(ctx, "detail", ref);
  const c = d.clan;
  const boss = d.boss;
  const text = [
    `${c.suspended ? "⛔ <b>SUSPENSO</b>\n" : ""}🏰 <b>${esc(c.name)}</b> [${esc(c.tag)}]`,
    `<code>${esc(c.id)}</code>`,
    "",
    `⭐ Nível <b>${c.level}</b> · XP ${fmt(c.xp)}/${fmt(c.xpNeeded)}`,
    `🏅 ${fmt(c.clanPoints)} clan points · 💪 ${fmt(c.power)} poder`,
    `👥 ${fmt(c.members)}/${fmt(c.memberLimit)} membros · entrada ${CLAN_JOIN_LABEL[c.joinType] || esc(c.joinType)} · 🏆 mín. ${fmt(c.minimumTrophies)}`,
    `👑 Chefe: ${boss ? `${esc(boss.name || "Clan Boss")} — ${fmt(boss.currentHealth)}/${fmt(boss.maxHealth)} HP` : "nenhum ciclo ativo"}`,
    `🎯 Missões da semana: ${(d.missions || []).filter((m: any) => m.completed).length}/${(d.missions || []).length}`,
  ].join("\n");
  const rows = [
    [
      { t: "👥 MEMBERS", d: `cl:mem:${c.id}` },
      { t: "✏️ EDIT CLAN", d: `cl:edit:${c.id}` },
    ],
    [
      { t: "⭐ CLAN XP", d: `cl:xp:${c.id}` },
      { t: "🎯 CLAN MISSIONS", d: `cl:miss:${c.id}` },
    ],
    [
      { t: "👑 CLAN BOSS", d: `cl:boss:${c.id}` },
      { t: "🔎 RAID AUDIT", d: `cl:ra:${c.id}` },
      { t: "📜 AUDIT", d: `cl:audit:${c.id}` },
    ],

    [
      { t: c.suspended ? "✅ REATIVAR" : "⛔ SUSPEND", d: `cl:susp:${c.id}` },
      { t: "🗑 DELETE", d: `cl:del:${c.id}` },
    ],
    [{ t: "🔄 ATUALIZAR", d: `cl:d:${c.id}` }],
    nav("cl:all"),
  ];
  return editing ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

const CLAN_ROLE_ICON: Record<string, string> = { leader: "👑", "co-leader": "🛡", officer: "⚔️", member: "👤" };

async function clanMembers(ctx: Ctx, ref: string) {
  const d = await clanRpc(ctx, "detail", ref);
  const list =
    (d.members || [])
      .map(
        (m: any) =>
          `${CLAN_ROLE_ICON[m.role] || "👤"} <b>${esc(m.name)}</b> · ${esc(m.role)}\n   🆔 <code>${esc(String(m.telegramId ?? "—"))}</code> · contribuição ${fmt(m.contribution)}`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `👥 <b>MEMBERS</b> — ${esc(d.clan.name)} [${esc(d.clan.tag)}]\n${fmt(d.clan.members)}/${fmt(d.clan.memberLimit)}\n\n${list.slice(0, 3400)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: `cl:mem:${d.clan.id}` }], nav(`cl:d:${d.clan.id}`)]),
  );
}

async function clanMissions(ctx: Ctx, ref: string) {
  const d = await clanRpc(ctx, "detail", ref);
  const list =
    (d.missions || [])
      .map((m: any) => `${m.completed ? "✅" : "⏳"} <code>${esc(m.code)}</code> — progresso ${fmt(m.progress)}`)
      .join("\n") || "Nenhuma missão registrada nesta semana.";
  return edit(
    ctx,
    `🎯 <b>CLAN MISSIONS</b> — ${esc(d.clan.name)}\nMissões semanais alimentadas por ações reais dos membros.\n\n${list.slice(0, 3400)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: `cl:miss:${d.clan.id}` }], nav(`cl:d:${d.clan.id}`)]),
  );
}

async function clanXpMenu(ctx: Ctx, ref: string) {
  const d = await clanRpc(ctx, "detail", ref);
  const c = d.clan;
  return edit(
    ctx,
    `⭐ <b>CLAN XP</b> — ${esc(c.name)}\nNível <b>${c.level}</b> · XP ${fmt(c.xp)}/${fmt(c.xpNeeded)}\nAjustes ficam registrados na auditoria.`,
    kb([
      [
        { t: "+1.000", d: `cl:xpgo:${c.id}:1000` },
        { t: "+10.000", d: `cl:xpgo:${c.id}:10000` },
        { t: "+50.000", d: `cl:xpgo:${c.id}:50000` },
      ],
      [
        { t: "−1.000", d: `cl:xpgo:${c.id}:-1000` },
        { t: "−10.000", d: `cl:xpgo:${c.id}:-10000` },
      ],
      [
        { t: "✏️ XP MANUAL", d: `cl:ask:clxp:${c.id}` },
        { t: "🎚 DEFINIR NÍVEL", d: `cl:ask:cllvl:${c.id}` },
      ],
      nav(`cl:d:${c.id}`),
    ]),
  );
}

async function clanBossMenu(ctx: Ctx, ref: string) {
  const d = await clanRpc(ctx, "detail", ref);
  const c = d.clan;
  const b = d.boss;
  return edit(
    ctx,
    `👑 <b>CLAN BOSS</b> — ${esc(c.name)}\n${b ? `Ativo: ${esc(b.name || "Clan Boss")} — ${fmt(b.currentHealth)}/${fmt(b.maxHealth)} HP` : "Nenhum ciclo ativo."}\n\nIniciar um novo ciclo encerra o atual.`,
    kb([
      [
        { t: "▶️ 1M HP", d: `cl:bossgo:${c.id}:1000000` },
        { t: "▶️ 5M HP", d: `cl:bossgo:${c.id}:5000000` },
      ],
      [
        { t: "▶️ 5M HP", d: `cl:bossgo:${c.id}:5000000` },
        { t: "✏️ HP MANUAL", d: `cl:ask:clbosshp:${c.id}` },
      ],
      nav(`cl:d:${c.id}`),
    ]),
  );
}

async function clanEditMenu(ctx: Ctx, ref: string) {
  const d = await clanRpc(ctx, "detail", ref);
  const c = d.clan;
  return edit(
    ctx,
    `✏️ <b>EDIT CLAN</b> — ${esc(c.name)} [${esc(c.tag)}]\nDescrição: ${esc(c.description || "—")}\nEntrada: ${CLAN_JOIN_LABEL[c.joinType] || esc(c.joinType)} · limite ${fmt(c.memberLimit)} · 🏆 mín. ${fmt(c.minimumTrophies)}`,
    kb([
      [
        { t: "📝 NOME", d: `cl:ask:clname:${c.id}` },
        { t: "🔖 TAG", d: `cl:ask:cltag:${c.id}` },
      ],
      [
        { t: "💬 DESCRIÇÃO", d: `cl:ask:cldesc:${c.id}` },
        { t: "👥 LIMITE", d: `cl:ask:cllimit:${c.id}` },
      ],
      [{ t: "🏆 TROFÉUS MÍN.", d: `cl:ask:cltrophy:${c.id}` }],
      [
        { t: "ABERTO", d: `cl:join:${c.id}:open` },
        { t: "APROVAÇÃO", d: `cl:join:${c.id}:approval` },
        { t: "FECHADO", d: `cl:join:${c.id}:closed` },
      ],
      nav(`cl:d:${c.id}`),
    ]),
  );
}

async function clanAudit(ctx: Ctx, ref?: string) {
  if (ref) {
    const d = await clanRpc(ctx, "detail", ref);
    const list =
      (d.audit || [])
        .map((a: any) => `• ${String(a.at).slice(5, 16).replace("T", " ")} <b>${esc(a.source)}</b> +${fmt(a.xp)} XP`)
        .join("\n") || "—";
    return edit(
      ctx,
      `📜 <b>AUDIT</b> — ${esc(d.clan.name)}\nÚltimos ganhos de Clan XP:\n\n${list.slice(0, 3400)}`,
      kb([[{ t: "🔄 ATUALIZAR", d: `cl:audit:${d.clan.id}` }], nav(`cl:d:${d.clan.id}`)]),
    );
  }
  const a = (await rpc("admin_list_audit", { p_admin_id: ctx.adminId, p_limit: 40, p_offset: 0 })) as any;
  const events = (a.events || []).filter((e: any) => String(e.action || "").startsWith("clans")).slice(0, 12);
  const list =
    events
      .map(
        (e: any) =>
          `• ${String(e.created_at).slice(5, 16).replace("T", " ")} <b>${esc(e.action)}</b> <code>${esc(e.target_id || "")}</code>`,
      )
      .join("\n") || "Nenhuma ação administrativa de clãs registrada.";
  return edit(
    ctx,
    `📜 <b>CLAN AUDIT</b>\nAções administrativas sobre clãs:\n\n${list.slice(0, 3400)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "cl:audit" }], nav("m:clans")]),
  );
}

/** Every clan callback. Mutations always re-render the affected menu with fresh server data. */

/** 🔥 CLAN HUB: collective layer (weekly goal, raid, treasury, upgrades, buffs, shop). */
async function csRpc(ctx: Ctx, action: string, payload: Record<string, unknown> = {}) {
  return (await rpc("admin_clan_system", { p_action: action, p_payload: payload })) as any;
}

async function clanHubView(ctx: Ctx) {
  const d = await csRpc(ctx, "overview");
  const s = d.settings || {};
  const st = d.stats || {};
  return edit(
    ctx,
    [
      "🔥 <b>CLAN HUB — PROGRESSÃO COLETIVA</b>",
      "",
      `STATUS: <b>${s.enabled ? "ATIVO" : "OFF"}</b> · RAID: <b>${s.raid_enabled ? "ON" : "OFF"}</b>`,
      `PONTOS POR BOSS PESSOAL: <b>${(s.boss_points || []).join(" / ")}</b>`,
      `META SEMANAL POR MEMBRO ATIVO: <b>${fmt(s.weekly_target_per_active ?? 0)}</b>`,
      `CLAN COINS POR PONTO: <b>${s.coins_per_contribution}</b> · XP: <b>${s.clan_xp_per_contribution}</b>`,
      `RAID: <b>${s.raid_attacks_per_day}</b> ataques/dia · <b>${s.raid_duration_days}</b> dias`,
      "",
      `📊 Clãs com ciclo: <b>${fmt(st.clansWithCycle ?? 0)}</b>`,
      `🎯 Contribuição da semana: <b>${fmt(st.weeklyContribution ?? 0)}</b>`,
      `👹 Raids ativas: <b>${fmt(st.activeRaids ?? 0)}</b>`,
      `💰 Tesouro total: <b>${fmt(st.treasuryFc ?? 0)} FC</b>`,
      "",
      "O Boss Pessoal continua individual — aqui só ajustamos a camada coletiva.",
    ].join("\n"),
    kb([
      [
        { t: s.enabled ? "🔴 DESATIVAR" : "🟢 ATIVAR", d: `cl:hbtg:${s.enabled ? 0 : 1}` },
        { t: s.raid_enabled ? "👹 RAID OFF" : "👹 RAID ON", d: `cl:hbraid:${s.raid_enabled ? 0 : 1}` },
      ],
      [300, 500, 800, 1200].map((v) => ({ t: `META ${v}`, d: `cl:hbtarget:${v}` })),
      [
        { t: "PTS 10/15/25/40", d: "cl:hbpts:10-15-25-40" },
        { t: "PTS 20/30/50/80", d: "cl:hbpts:20-30-50-80" },
      ],
      [1, 2, 3, 5].map((v) => ({ t: `RAID ${v}/dia`, d: `cl:hbatk:${v}` })),
      [{ t: "⚔ CLAN RAID SETTINGS", d: "cl:rs" }],
      [{ t: "💰 LIMITES DE DOAÇÃO", d: "cl:ds" }],
      [{ t: "♻️ ENCERRAR RAIDS ATIVAS", d: "cl:hbrreset" }],


      nav("m:clans"),
    ]),
  );
}
/** 💰 DONATION LIMITS: global defaults and hard caps for per-clan treasury contribution rules. */
async function clanDonationSettingsView(ctx: Ctx) {
  const d = await csRpc(ctx, "overview");
  const s = d.settings || {};
  return edit(
    ctx,
    [
      "💰 <b>LIMITES DE DOAÇÃO DO TESOURO</b>",
      "",
      "<b>FC</b>",
      `MÍNIMO PADRÃO: <b>${fmt(s.donation_default_min_fc ?? 0)}</b>`,
      `MÁXIMO DIÁRIO PADRÃO: <b>${fmt(s.donation_default_max_fc ?? 0)}</b>`,
      `HARD CAP GLOBAL: <b>${fmt(s.donation_hard_max_fc ?? 0)}</b>`,
      "",
      "<b>MYTH</b>",
      `MÍNIMO PADRÃO: <b>${fmt(s.donation_default_min_myth ?? 0)}</b>`,
      `MÁXIMO DIÁRIO PADRÃO: <b>${fmt(s.donation_default_max_myth ?? 0)}</b>`,
      `HARD CAP GLOBAL: <b>${fmt(s.donation_hard_max_myth ?? 0)}</b>`,
      "",
      "Os padrões valem para clãs que ainda não configuraram limites próprios.",
      "O hard cap é o teto que nenhum líder pode ultrapassar.",
    ].join("\n"),
    kb([
      [5_000, 10_000, 25_000, 50_000].map((v) => ({ t: `FC MIN ${fmt(v)}`, d: `cl:dst:donation_default_min_fc:${v}` })),
      [500_000, 1_000_000, 2_000_000, 5_000_000].map((v) => ({ t: `FC MAX ${fmt(v)}`, d: `cl:dst:donation_default_max_fc:${v}` })),
      [5_000_000, 10_000_000, 25_000_000, 50_000_000].map((v) => ({ t: `FC CAP ${fmt(v)}`, d: `cl:dst:donation_hard_max_fc:${v}` })),
      [100, 500, 1_000, 2_500].map((v) => ({ t: `MYTH MIN ${fmt(v)}`, d: `cl:dst:donation_default_min_myth:${v}` })),
      [5_000, 10_000, 25_000, 50_000].map((v) => ({ t: `MYTH MAX ${fmt(v)}`, d: `cl:dst:donation_default_max_myth:${v}` })),
      [50_000, 100_000, 250_000, 500_000].map((v) => ({ t: `MYTH CAP ${fmt(v)}`, d: `cl:dst:donation_hard_max_myth:${v}` })),
      nav("cl:hub"),
    ]),
  );
}


/** ⚔ CLAN RAID SETTINGS: collective boss target/deadline, health gates, pacing and calibration. */
async function clanRaidSettingsView(ctx: Ctx) {
  const s = ((await rpc("admin_clan_raid_settings", {})) as any) || {};
  return edit(
    ctx,
    [
      "⚔ <b>CLAN RAID SETTINGS</b>",
      "",
      `RAID: <b>${s.raid_enabled ? "ON" : "OFF"}</b> · HEALTH GATES: <b>${s.raid_health_gates_enabled ? "ON" : "OFF"}</b>`,
      `TARGET KILL: <b>${s.raid_target_kill_days} dias</b> · DEADLINE: <b>${s.raid_deadline_days} dias</b>`,
      `DURAÇÃO MÍNIMA (KILL UNLOCK): <b>${s.raid_min_kill_days ?? 5} dias</b>`,

      `ATAQUES/DIA: <b>${s.raid_attacks_per_day}</b>`,
      `SAFETY FACTOR: <b>${s.raid_safety_factor}</b>`,
      `PESOS DPS: 24h <b>${s.raid_dps_weight_24h}</b> · 3d <b>${s.raid_dps_weight_3d}</b> · 7d <b>${s.raid_dps_weight_7d}</b>`,
      `HP MAX +: <b>${s.raid_max_hp_increase_pct}%</b> · HP MAX −: <b>${s.raid_max_hp_decrease_pct}%</b>`,
      `CATCH-UP: <b>${s.raid_catchup_enabled ? "ON" : "OFF"}</b> (cap ${s.raid_catchup_max_pct}%)`,
      `FULL KILL REQUIRED: <b>${s.raid_full_kill_required ? "ON" : "OFF"}</b>`,
      "",
      "HP é calculado por clã: DPS efetivo × target × safety factor.",
      "As fases liberam 1/target do HP por dia — o boss não morre antes do dia alvo.",
      `A raid nunca cai abaixo de 1 HP antes do DIA ${s.raid_min_kill_days ?? 5} (todos têm chance de atacar).`,
    ].join("\n"),
    kb([
      [
        { t: s.raid_enabled ? "🔴 RAID OFF" : "🟢 RAID ON", d: `cl:rst:raid_enabled:${s.raid_enabled ? 0 : 1}` },
        { t: s.raid_health_gates_enabled ? "🔓 GATES OFF" : "🔒 GATES ON", d: `cl:rst:raid_health_gates_enabled:${s.raid_health_gates_enabled ? 0 : 1}` },
      ],
      [3, 4, 5, 6].map((v) => ({ t: `TARGET ${v}d`, d: `cl:rst:raid_target_kill_days:${v}` })),
      [1, 2, 3, 4].map((v) => ({ t: `🛡 MÍN ${v}d`, d: `cl:rst:raid_min_kill_days:${v}` })),
      [5, 6, 7].map((v) => ({ t: `🛡 MÍN ${v}d`, d: `cl:rst:raid_min_kill_days:${v}` })),
      [5, 7, 10, 14].map((v) => ({ t: `PRAZO ${v}d`, d: `cl:rst:raid_deadline_days:${v}` })),
      [1, 2, 3, 5].map((v) => ({ t: `ATK ${v}/dia`, d: `cl:rst:raid_attacks_per_day:${v}` })),

      [0.85, 0.95, 1, 1.1].map((v) => ({ t: `SAFE ${v}`, d: `cl:rst:raid_safety_factor:${v}` })),
      [10, 20, 30, 50].map((v) => ({ t: `HP+ ${v}%`, d: `cl:rst:raid_max_hp_increase_pct:${v}` })),
      [10, 25, 40, 50].map((v) => ({ t: `HP− ${v}%`, d: `cl:rst:raid_max_hp_decrease_pct:${v}` })),
      [
        { t: s.raid_catchup_enabled ? "🔴 CATCH-UP OFF" : "🟢 CATCH-UP ON", d: `cl:rst:raid_catchup_enabled:${s.raid_catchup_enabled ? 0 : 1}` },
        { t: s.raid_full_kill_required ? "🎁 KILL OPCIONAL" : "🎁 KILL OBRIGATÓRIO", d: `cl:rst:raid_full_kill_required:${s.raid_full_kill_required ? 0 : 1}` },
      ],
      [10, 15, 20, 30].map((v) => ({ t: `CATCH ${v}%`, d: `cl:rst:raid_catchup_max_pct:${v}` })),
      [50_000_000_000, 100_000_000_000, 500_000_000_000].map((v) => ({ t: `HP CAP ${fmt(v / 1_000_000_000)}B`, d: `cl:rst:raid_hp_max:${v}` })),
      [{ t: "♻️ REBASE HP DAS RAIDS ATIVAS", d: "cl:rbz" }],
      [{ t: "🔄 ATUALIZAR", d: "cl:rs" }],
      nav("cl:hub"),
    ]),
  );
}

/** Per-clan raid audit: power, active members, effective DPS, expected vs actual progress. */
async function clanRaidAuditView(ctx: Ctx, clanId: string) {
  const d = ((await rpc("admin_clan_raid_audit", { p_clan: clanId })) as any) || {};
  return edit(
    ctx,
    [
      "🔎 <b>CLAN RAID AUDIT</b>",
      "",
      `CLAN POWER: <b>${fmt(Number(d.clanPower ?? 0))}</b>`,
      `ACTIVE MEMBERS: <b>${fmt(Number(d.activeMembers ?? 0))}</b>`,
      `EFFECTIVE DAILY DPS: <b>${fmt(Math.round(Number(d.effectiveDps ?? 0)))}</b>`,
      `RAID HP: <b>${fmt(Number(d.currentHp ?? 0))} / ${fmt(Number(d.maxHp ?? 0))}</b>`,
      `TARGET CLEAR: <b>${d.targetDays ?? "-"}d</b> · DEADLINE: <b>${d.deadlineDays ?? "-"}d</b>`,
      `CURRENT DAY: <b>${d.day ?? 0}/${d.deadlineDays ?? 7}</b>`,
      `EXPECTED PROGRESS: <b>${d.expectedProgress ?? 0}%</b>`,
      `ACTUAL PROGRESS: <b>${d.actualProgress ?? 0}%</b>`,
      `STATUS: <b>${d.status ?? "-"}</b>`,
    ].join("\n"),
    kb([[{ t: "🔄 ATUALIZAR", d: `cl:ra:${clanId}` }], nav(`cl:d:${clanId}`)]),
  );
}



/** 🛡 CLAN ANTI-ABUSE: cooldowns, clan boss single-clan lock, audits and manual clears. */
async function aaRpc(ctx: Ctx, action = "get", value: string | null = null, target: string | null = null) {
  return (await rpc("admin_clan_anti_abuse", {
    p_admin_id: ctx.adminId,
    p_action: action,
    p_value: value,
    p_target: target,
  })) as any;
}

const AA_HOURS = ["0", "12", "24", "48", "72"];

async function clanAntiAbuseView(ctx: Ctx, action = "get", value?: string) {
  const d = await aaRpc(ctx, action, value ?? null);
  return edit(
    ctx,
    [
      "🛡 <b>CLAN ANTI-ABUSE</b>",
      "",
      `STATUS: <b>${d.enabled ? "ACTIVE" : "OFF"}</b>`,
      `VOLUNTARY LEAVE COOLDOWN: <b>${d.leaveCooldownHours}h</b>`,
      `KICK COOLDOWN: <b>${d.kickCooldownHours}h</b>`,
      `CLAN BOSS SINGLE-CLAN LOCK: <b>${d.bossLockEnabled ? "ON" : "OFF"}</b>`,
      "",
      `⏳ Cooldowns ativos: <b>${fmt(d.activeCooldownCount ?? 0)}</b>`,
      `🔒 Boss locks ativos: <b>${fmt(d.bossLockCount ?? 0)}</b>`,
      "",
      "Global Boss, PvP e Clan War não são afetados por estas regras.",
    ].join("\n"),
    kb([
      AA_HOURS.map((h) => ({ t: `SAIR ${h}h`, d: `cl:aaleave:${h}` })),
      AA_HOURS.map((h) => ({ t: `KICK ${h}h`, d: `cl:aakick:${h}` })),
      [
        { t: d.enabled ? "🔴 DESATIVAR" : "🟢 ATIVAR", d: "cl:aatg" },
        { t: d.bossLockEnabled ? "🔓 BOSS LOCK OFF" : "🔒 BOSS LOCK ON", d: "cl:aatgl" },
      ],
      [
        { t: "⏳ VIEW COOLDOWNS", d: "cl:aacds" },
        { t: "🔒 VIEW BOSS LOCKS", d: "cl:aalocks" },
      ],
      [
        { t: "🚩 CLAN HOPPING", d: "cl:aaflags" },
        { t: "🔎 PLAYER AUDIT", d: "ask:claaudit" },
      ],
      nav("m:clans"),
    ]),
  );
}

async function clanAntiAbuseList(ctx: Ctx, kind: "cooldowns" | "locks" | "flags") {
  const d = await aaRpc(ctx);
  const rows =
    kind === "cooldowns"
      ? (d.activeCooldowns || []).map(
          (c: any) =>
            `⏳ <b>${esc(c.name)}</b> · <code>${esc(String(c.telegramId ?? "—"))}</code>\n   até ${esc(String(c.until).slice(0, 16).replace("T", " "))} · ${esc(c.reason ?? "—")} · trocas 24h ${fmt(c.changes24h ?? 0)}`,
        )
      : kind === "locks"
        ? (d.bossLocks || []).map(
            (l: any) =>
              `🔒 <b>${esc(l.name)}</b> · <code>${esc(String(l.telegramId ?? "—"))}</code>\n   clã ${esc(l.clan ?? "—")} · até ${esc(String(l.until).slice(0, 16).replace("T", " "))}`,
          )
        : (d.flags || []).map(
            (f: any) =>
              `🚩 <b>${esc(f.name)}</b> · <code>${esc(String(f.telegramId ?? "—"))}</code>\n   ${esc(f.flag)} · ${esc(String(f.at).slice(0, 16).replace("T", " "))}`,
          );
  const title =
    kind === "cooldowns"
      ? "⏳ <b>ACTIVE COOLDOWNS</b>"
      : kind === "locks"
        ? "🔒 <b>ACTIVE BOSS LOCKS</b>"
        : "🚩 <b>SUSPICIOUS CLAN HOPPING</b>";
  return edit(
    ctx,
    `${title}\n\n${rows.length ? rows.join("\n\n").slice(0, 3400) : "Nada registrado."}`,
    kb([[{ t: "🔎 PLAYER AUDIT", d: "ask:claaudit" }], nav("cl:aa")]),
  );
}

async function clanAntiAbuseConfirm(ctx: Ctx, target: string, kind: "cooldown" | "lock") {
  const d = await aaRpc(ctx, "get", null, target);
  const name = d.audit?.notFound ? esc(target) : esc(String(d.audit?.name ?? target));
  return edit(
    ctx,
    `⚠️ <b>CLEAR CLAN ${kind === "cooldown" ? "COOLDOWN" : "BOSS LOCK"} FOR ${name}?</b>\n\nA ação fica registrada na auditoria administrativa.`,
    kb([
      [
        { t: "✅ CONFIRM", d: `cl:${kind === "cooldown" ? "aaclrcd" : "aaclrlk"}:${target}` },
        { t: "❌ CANCEL", d: `cl:aaudit:${target}` },
      ],
      nav("cl:aa"),
    ]),
  );
}

async function clanAntiAbuseAudit(ctx: Ctx, target: string, action = "get") {
  const d = await aaRpc(ctx, action, null, target);
  const a = d.audit;
  if (!a || a.notFound) {
    return edit(
      ctx,
      `🔎 <b>CLAN ABUSE AUDIT</b>\n\nJogador não encontrado: <code>${esc(target)}</code>`,
      kb([[{ t: "🔎 BUSCAR OUTRO", d: "ask:claaudit" }], nav("cl:aa")]),
    );
  }
  const history = (a.history || [])
    .slice(0, 8)
    .map(
      (h: any) =>
        `• ${esc(h.clan ?? "—")} · entrou ${esc(String(h.joinedAt).slice(0, 16).replace("T", " "))}${h.leftAt ? ` · saiu ${esc(String(h.leftAt).slice(0, 16).replace("T", " "))} (${esc(h.reason ?? "—")})` : " · <b>ativo</b>"}`,
    )
    .join("\n");
  const damage = (a.bossDamage || [])
    .slice(0, 6)
    .map((x: any) => `• ${esc(x.clan ?? "—")} · ${fmt(x.damage)} dano · ${esc(x.status ?? "ELIGIBLE")}`)
    .join("\n");
  return edit(
    ctx,
    [
      `🔎 <b>CLAN ABUSE AUDIT</b> — ${esc(String(a.name))}`,
      `🆔 <code>${esc(String(a.telegramId ?? "—"))}</code>`,
      `Clã atual: <b>${esc(a.currentClan ?? "—")}</b>`,
      `Recompensas de Clan Boss recebidas: <b>${fmt(a.rewards ?? 0)}</b>`,
      "",
      `⏳ Cooldown: <b>${a.cooldown?.active ? `${Math.ceil((a.cooldown.remainingSeconds ?? 0) / 60)} min` : "livre"}</b>`,
      `🔒 Boss lock: <b>${a.bossLock?.active ? `${Math.ceil((a.bossLock.remainingSeconds ?? 0) / 60)} min` : "livre"}</b>`,
      `🚩 Flags: <b>${fmt((a.flags || []).length)}</b>`,
      "",
      `<b>HISTÓRICO</b>\n${history || "—"}`,
      "",
      `<b>CLAN BOSS</b>\n${damage || "—"}`,
    ]
      .join("\n")
      .slice(0, 3800),
    kb([
      [
        { t: "🧹 CLEAR COOLDOWN", d: `cl:aacfcd:${a.telegramId}` },
        { t: "🧹 CLEAR BOSS LOCK", d: `cl:aacflk:${a.telegramId}` },
      ],
      [{ t: "🔎 BUSCAR OUTRO", d: "ask:claaudit" }],
      nav("cl:aa"),
    ]),
  );
}

async function clansCallback(ctx: Ctx, rest: string[]) {
  const [op, a, b] = rest;
  switch (op) {
    case "all":
      return clansList(ctx, "list");
    case "rank":
      return clansList(ctx, "ranking");
    case "d":
      return clanCard(ctx, a);
    case "mem":
      return clanMembers(ctx, a);
    case "miss":
      return clanMissions(ctx, a);
    case "xp":
      return clanXpMenu(ctx, a);
    case "boss":
      return clanBossMenu(ctx, a);
    case "edit":
      return clanEditMenu(ctx, a);
    case "audit":
      return clanAudit(ctx, a);
    case "cfg":
      return clanSettingsView(ctx);
    // 🛡 Anti-abuse: join cooldown, clan boss single-clan lock, audits and manual clears.
    case "aa":
      return clanAntiAbuseView(ctx);
    case "aatg":
      return clanAntiAbuseView(ctx, "toggle");
    case "aatgl":
      return clanAntiAbuseView(ctx, "toggle_boss_lock");
    case "aaleave":
      return clanAntiAbuseView(ctx, "set_leave", a);
    case "aakick":
      return clanAntiAbuseView(ctx, "set_kick", a);
    case "aacds":
      return clanAntiAbuseList(ctx, "cooldowns");
    case "aalocks":
      return clanAntiAbuseList(ctx, "locks");
    case "hub":
      return clanHubView(ctx);
    case "hbtg":
      await csRpc(ctx, "set_setting", { field: "enabled", value: String(a) === "1" });
      return clanHubView(ctx);
    case "hbraid":
      await csRpc(ctx, "set_setting", { field: "raid_enabled", value: String(a) === "1" });
      return clanHubView(ctx);
    case "hbtarget":
      await csRpc(ctx, "set_setting", { field: "weekly_target_per_active", value: Number(a) });
      return clanHubView(ctx);
    case "hbatk":
      await csRpc(ctx, "set_setting", { field: "raid_attacks_per_day", value: Number(a) });
      return clanHubView(ctx);
    case "hbpts":
      await csRpc(ctx, "set_setting", { field: "boss_points", value: String(a).split("-").map((n) => Number(n)) });
      return clanHubView(ctx);
    case "hbrreset":
      await csRpc(ctx, "reset_raid", {});
      return clanHubView(ctx);
    // ⚔ Clan Raid: pacing, health gates and auto-calibration of the collective boss.
    case "rs":
      return clanRaidSettingsView(ctx);
    case "rst": {
      const field = String(a ?? "");
      const boolFields = ["raid_enabled", "raid_health_gates_enabled", "raid_catchup_enabled", "raid_full_kill_required"];
      const value = boolFields.includes(field) ? String(b) === "1" : Number(b);
      await csRpc(ctx, "set_setting", { field, value });
      return clanRaidSettingsView(ctx);
    }
    case "ra":
      return clanRaidAuditView(ctx, String(a ?? ""));

    // ♻️ Rebase: recalcula HP das raids ativas preservando o dano legítimo já causado.
    case "rbz": {
      await rpc("clan_raid_rebase_all", { p_reason: "admin_bot_rebase" });
      return clanRaidSettingsView(ctx);
    }

    // 💰 Donation limits: global defaults and hard caps for per-clan treasury rules.
    case "ds":
      return clanDonationSettingsView(ctx);
    case "dst":
      await csRpc(ctx, "set_setting", { field: String(a ?? ""), value: Number(b) });
      return clanDonationSettingsView(ctx);

    case "aaflags":
      return clanAntiAbuseList(ctx, "flags");
    case "aaudit":
      return clanAntiAbuseAudit(ctx, String(a ?? ""));
    case "aacfcd":
      return clanAntiAbuseConfirm(ctx, String(a ?? ""), "cooldown");
    case "aacflk":
      return clanAntiAbuseConfirm(ctx, String(a ?? ""), "lock");
    case "aaclrcd":
      return clanAntiAbuseAudit(ctx, String(a ?? ""), "clear_cooldown");
    case "aaclrlk":
      return clanAntiAbuseAudit(ctx, String(a ?? ""), "clear_boss_lock");
    case "costgo": {
      const r = (await rpc("admin_clan_settings", {
        p_admin_id: ctx.adminId,
        p_action: "set_cost",
        p_value: Number(a),
      })) as any;
      await send(
        ctx,
        `✅ <b>CUSTO ATUALIZADO</b>\n\nNovo custo para criar clã: <b>${fmt(r.createCostFc)} FC</b>\nClãs já criados permanecem intactos.`,
      );
      return clanSettingsView({ ...ctx, messageId: undefined }, false);
    }
    case "limitgo": {
      const r = (await rpc("admin_clan_settings", {
        p_admin_id: ctx.adminId,
        p_action: "set_limit",
        p_value: Number(a),
      })) as any;
      await send(
        ctx,
        `✅ <b>LIMITE ATUALIZADO</b>\n\nNovos clãs passam a ser criados com <b>${fmt(r.defaultMemberLimit)}</b> membros.`,
      );
      return clanSettingsView({ ...ctx, messageId: undefined }, false);
    }
    case "ask":
      return ask(ctx, `${a}|${b}`, PROMPTS[a] || "Envie o valor.");

    case "xpgo": {
      const r = await clanRpc(ctx, "xp", a, { xp: Number(b) });
      await send(
        ctx,
        `✅ XP ajustado: <b>${esc(r.clan.name)}</b> — NV${r.clan.level} · ${fmt(r.clan.xp)}/${fmt(r.clan.xpNeeded)}`,
      );
      return clanXpMenu({ ...ctx, messageId: undefined }, a);
    }
    case "bossgo": {
      await clanRpc(ctx, "boss", a, { hp: Number(b) });
      await send(ctx, `👑 Novo ciclo do chefe do clã iniciado com <b>${fmt(Number(b))} HP</b>.`);
      return clanBossMenu({ ...ctx, messageId: undefined }, a);
    }
    case "join": {
      const r = await clanRpc(ctx, "edit", a, { joinType: b });
      await send(ctx, `✅ Entrada definida como <b>${CLAN_JOIN_LABEL[b] || esc(b)}</b> em ${esc(r.clan.name)}.`);
      return clanEditMenu({ ...ctx, messageId: undefined }, a);
    }
    case "susp": {
      const d = await clanRpc(ctx, "detail", a);
      return edit(
        ctx,
        `${d.clan.suspended ? "✅" : "⛔"} <b>${d.clan.suspended ? "REATIVAR" : "SUSPEND"} CLAN</b>\n${esc(d.clan.name)} [${esc(d.clan.tag)}] · ${fmt(d.clan.members)} membros\n\nConfirma a alteração?`,
        kb([
          [
            { t: "✅ CONFIRMAR", d: `cl:suspgo:${a}` },
            { t: "❌ CANCELAR", d: `cl:d:${a}` },
          ],
        ]),
      );
    }
    case "suspgo": {
      const r = await clanRpc(ctx, "suspend", a);
      await send(ctx, `${r.clan.suspended ? "⛔ Clã suspenso" : "✅ Clã reativado"}: <b>${esc(r.clan.name)}</b>.`);
      return clanCard({ ...ctx, messageId: undefined }, a, false);
    }
    case "del": {
      const d = await clanRpc(ctx, "detail", a);
      return edit(
        ctx,
        `🗑 <b>DELETE CLAN</b>\n${esc(d.clan.name)} [${esc(d.clan.tag)}] · ${fmt(d.clan.members)} membros · ${fmt(d.clan.clanPoints)} pts\n\n⚠️ Ação irreversível: membros, chat, missões e histórico do clã são removidos.`,
        kb([[{ t: "🗑 EXCLUIR DEFINITIVAMENTE", d: `cl:delgo:${a}` }], [{ t: "❌ CANCELAR", d: `cl:d:${a}` }]]),
      );
    }
    case "delgo": {
      const r = await clanRpc(ctx, "delete", a);
      await clearSession(ctx);
      return send(
        ctx,
        `🗑 Clã <b>${esc(r.clan?.name ?? "—")}</b> excluído.`,
        kb([[{ t: "📋 ALL CLANS", d: "cl:all" }], nav("m:clans")]),
      );
    }
    default:
      return clansHub(ctx);
  }
}

/** Text replies for the clan prompts (session key format: "clxp|<clanId>"). */
async function clansPrompt(ctx: Ctx, key: string, ref: string, text: string) {
  const int = () => Math.round(parseAmount(text.replace(/[^\d.,-]/g, "")));
  switch (key) {
    case "clsearch":
      return clansList(ctx, "search", text);
    case "claaudit":
      return clanAntiAbuseAudit(ctx, text.trim());
    case "clcost": {
      const value = Math.round(parseAmount(text.replace(/[^\d.,-]/g, "")));
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um valor em FC maior ou igual a 0 (ex.: <code>75000</code>).");
      const s = (await rpc("admin_clan_settings", { p_admin_id: ctx.adminId, p_action: "get", p_value: null })) as any;
      return send(
        ctx,
        [
          "🏰 <b>ALTERAR CUSTO DO CLÃ</b>",
          "",
          `Atual: <b>${fmt(s.createCostFc)} FC</b>`,
          `Novo: <b>${fmt(value)} FC</b>`,
          "",
          "Clãs já criados não são alterados.",
        ].join("\n"),
        kb([
          [
            { t: "✅ CONFIRMAR", d: `cl:costgo:${value}` },
            { t: "❌ CANCELAR", d: "cl:cfg" },
          ],
        ]),
      );
    }
    case "clsetlimit": {
      const value = Math.round(parseAmount(text.replace(/[^\d.,-]/g, "")));
      if (!Number.isFinite(value) || value < 2 || value > 500)
        throw new Error("KEEP_SESSION::⚠️ Envie um limite entre 2 e 500 (ex.: <code>30</code>).");
      const s = (await rpc("admin_clan_settings", { p_admin_id: ctx.adminId, p_action: "get", p_value: null })) as any;
      return send(
        ctx,
        [
          "👥 <b>LIMITE DE MEMBROS (NOVOS CLÃS)</b>",
          "",
          `Atual: <b>${fmt(s.defaultMemberLimit)}</b>`,
          `Novo: <b>${fmt(value)}</b>`,
        ].join("\n"),
        kb([
          [
            { t: "✅ CONFIRMAR", d: `cl:limitgo:${value}` },
            { t: "❌ CANCELAR", d: "cl:cfg" },
          ],
        ]),
      );
    }

    case "clxp": {
      const value = int();
      if (!Number.isFinite(value) || value === 0)
        throw new Error(
          "KEEP_SESSION::⚠️ Envie um número diferente de 0 (ex.: <code>25000</code> ou <code>-5000</code>).",
        );
      const r = await clanRpc(ctx, "xp", ref, { xp: value });
      await send(
        ctx,
        `✅ XP ajustado em ${fmt(value)}: <b>${esc(r.clan.name)}</b> — NV${r.clan.level} · ${fmt(r.clan.xp)}/${fmt(r.clan.xpNeeded)}`,
      );
      return clanXpMenu({ ...ctx, messageId: undefined }, ref);
    }
    case "cllvl": {
      const value = int();
      if (!Number.isFinite(value) || value < 1) throw new Error("KEEP_SESSION::⚠️ Envie um nível maior ou igual a 1.");
      const r = await clanRpc(ctx, "xp", ref, { level: value });
      await send(ctx, `✅ Nível definido: <b>${esc(r.clan.name)}</b> — NV${r.clan.level}`);
      return clanXpMenu({ ...ctx, messageId: undefined }, ref);
    }
    case "clbosshp": {
      const value = int();
      if (!Number.isFinite(value) || value <= 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um HP maior que 0 (ex.: <code>2500000</code>).");
      await clanRpc(ctx, "boss", ref, { hp: value });
      await send(ctx, `👑 Novo ciclo iniciado com <b>${fmt(value)} HP</b>.`);
      return clanBossMenu({ ...ctx, messageId: undefined }, ref);
    }
    case "clname":
    case "cltag":
    case "cldesc":
    case "cllimit":
    case "cltrophy": {
      const patch: Record<string, unknown> = {};
      if (key === "clname") {
        if (text.length < 3 || text.length > 24)
          throw new Error("KEEP_SESSION::⚠️ O nome deve ter de 3 a 24 caracteres.");
        patch.name = text;
      } else if (key === "cltag") {
        if (!/^[A-Za-z0-9]{2,5}$/.test(text))
          throw new Error("KEEP_SESSION::⚠️ A tag deve ter de 2 a 5 letras/números.");
        patch.tag = text.toUpperCase();
      } else if (key === "cldesc") {
        patch.description = text.slice(0, 200);
      } else {
        const value = int();
        if (!Number.isFinite(value) || value < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
        if (key === "cllimit") {
          if (value < 1 || value > 500) throw new Error("KEEP_SESSION::⚠️ O limite deve ficar entre 1 e 500.");
          patch.memberLimit = value;
        } else patch.minimumTrophies = value;
      }
      const r = await clanRpc(ctx, "edit", ref, patch);
      await send(ctx, `✅ Clã atualizado: <b>${esc(r.clan.name)}</b> [${esc(r.clan.tag)}]`);
      return clanEditMenu({ ...ctx, messageId: undefined }, ref);
    }
    default:
      return clansHub(ctx);
  }
}

async function module(ctx: Ctx, name: string) {
  switch (name) {
    case "users":
      return edit(
        ctx,
        "👥 <b>USUÁRIOS</b>\nBusque por Telegram ID, @usuário, nome, carteira ou ID interno.",
        kb([
          [{ t: "🔎 PROCURAR", d: "ask:find" }],
          [{ t: "🆕 LATEST USERS", d: "pg:0:all" }],
          [{ t: "📋 ALL USERS", d: "pg:0:all" }],
          nav(),
        ]),
      );
    case "heroes":
      return heroManagementHub(ctx);
    case "shop":
      return heroShopHub(ctx);
    case "herolist": {
      const d = await rpc("admin_list_heroes", { p_admin_id: ctx.adminId, p_limit: 20, p_offset: 0 });
      const list = d.heroes
        .map(
          (h: any) =>
            `• <code>${esc(h.hero_key)}</code> ${esc(h.name)} — ${esc(h.rarity)} ${h.enabled ? "✅" : "⛔"}${h.in_shop ? " 🏪" : ""} ${h.price_fc ? fmt(h.price_fc) + " FC" : ""}`,
        )
        .join("\n");
      return edit(
        ctx,
        `🦸 <b>HERÓIS</b> (${d.total})\n${list}\n\nO <code>price_fc</code> do herói é o preço avulso na loja, diferente do preço de recrutamento 1x/5x/10x.`,
        kb([
          [
            { t: "➕ CREATE HERO", d: "hw:new" },
            { t: "✏️ EDIT HERO", d: "hw:edit" },
          ],
          [{ t: "🦸 DAR A USUÁRIO", d: "ask:granthero" }],
          nav("m:heroes"),
        ]),
      );
    }

    case "store": {
      const d = await rpc("admin_list_heroes", { p_admin_id: ctx.adminId, p_limit: 30, p_offset: 0 });
      const shop = d.heroes.filter((h: any) => h.in_shop);
      return edit(
        ctx,
        `📦 <b>ITENS DA LOJA</b>\n${shop.length ? shop.map((h: any) => `• ${esc(h.name)} — ${fmt(h.price_fc)} FC / ${h.price_ton ?? "—"} TON · ordem ${h.sort_order}${h.featured ? " ⭐" : ""}`).join("\n") : "Nenhum item avulso na loja."}\n\nCampos: <code>in_shop</code>, <code>price_fc</code>, <code>price_ton</code>, <code>discount_percent</code>, <code>stock</code>, <code>sort_order</code>, <code>featured</code>, <code>available_until</code>.`,
        kb([[{ t: "✏️ EDITAR HERÓI", d: "hw:edit" }], nav("m:shop")]),
      );
    }
    case "pets": {
      const list = await rpc("admin_list_pets", { p_admin_id: ctx.adminId, p_limit: 30, p_offset: 0 });
      const cfg = await rpc("admin_pet_config", { p_admin_id: ctx.adminId });
      return edit(
        ctx,
        `🐲 <b>PETS</b> (${list.total})\n${list.pets.map((p: any) => `• <code>${esc(p.slug)}</code> ${esc(p.name)} — ${esc(p.category)} ${p.is_enabled ? "✅" : "⛔"}`).join("\n")}\n\n🥚 Ovos: ${cfg.eggs.length} · 🍖 Comidas: ${cfg.food.length} · 🧬 Estágios: ${cfg.tiers.length}`,
        kb([
          [{ t: "🐲 PET CMS (EDITOR VISUAL)", d: "pw:hub" }],
          [
            { t: "➕ CRIAR PET", d: "pw:new" },
            { t: "🥚 OVOS (CMS)", d: "pw:eggs" },
          ],
          [
            { t: "🍖 COMIDAS", d: "view:foods" },
            { t: "🥚 OVOS (LEGADO)", d: "view:eggs" },
          ],
          [
            { t: "🧬 EVOLUÇÃO", d: "view:tiers" },
            { t: "🧩 FRAGMENTOS", d: "ask:givefrag" },
          ],
          [
            { t: "🐲 DAR PET", d: "ask:grantpet" },
            { t: "🎁 ENVIAR ITEM", d: "ask:giveitem" },
          ],
          [{ t: "💎 NFT PETS (EXCLUSIVOS)", d: "nft:hub" }],
          nav(),
        ]),
      );
    }
    case "pvp": {
      const d = await rpc("admin_pvp_overview", { p_admin_id: ctx.adminId, p_top: 10 });
      return edit(
        ctx,
        `⚔️ <b>PVP</b>\nVitória <b>+${d.settings.win}</b> · Derrota <b>${d.settings.loss}</b> · Ticket custo ${d.settings.ticket_cost} (máx ${d.settings.ticket_max})\nBatalhas 24h: ${fmt(d.battles_today)}\n\n<b>TOP 10</b>\n${d.ranking.map((r: any, i: number) => `${i + 1}. ${esc(r.name)} — ${fmt(r.trophies)}🏆 (${esc(r.league)})`).join("\n") || "—"}`,
        kb([
          [
            { t: "🏅 LIGAS", d: "view:leagues" },
            { t: "⚙️ VALORES", d: "ask:pvpset" },
          ],
          [{ t: "🎟 TICKET SETTINGS", d: "view:pvptickets" }],
          [
            { t: "📈 TOP 50", d: "rank:50" },
            { t: "📈 TOP 100", d: "rank:100" },
          ],
          [{ t: "♻️ RESETAR TEMPORADA", d: "confirm:pvpreset" }],
          nav(),
        ]),
      );
    }

    case "pass": {
      const d = await rpc("admin_pass_overview", { p_admin_id: ctx.adminId });
      const s = d.season || {};
      return edit(
        ctx,
        `🎟 <b>PASSE</b>\n${esc(s.name)} · ${String(s.start_at).slice(0, 10)} → ${String(s.end_at).slice(0, 10)}\nNíveis ${s.levels} · XP/nível ${s.xp_per_level}\nAventureiro ${s.adventurer_price_ton} TON (${fmt(d.owners.adventurer)} donos) · Lendário ${s.legendary_price_ton} TON (${fmt(d.owners.legendary)} donos)\nRecompensas cadastradas: ${d.rewards.length}`,
        kb([
          [{ t: "🔎 SELECIONAR USUÁRIO", d: "ask:passuser" }],
          [{ t: "📜 PASS HISTORY", d: "bphist:1" }],
          [{ t: "⚡ XP SETTINGS", d: "view:passxp" }],
          [{ t: "🎁 REWARDS (MAPA)", d: "view:passrewards" }],
          [{ t: "🪜 LEVEL PURCHASE", d: "m:passlevels" }],
          [{ t: "🔍 CHECK MISSING REWARDS", d: "view:passmissing" }],
          [{ t: "💰 PREÇOS/DATAS", d: "ask:pass" }],
          [{ t: "🎁 RECOMPENSA", d: "ask:passreward" }],
          nav(),
        ]),
      );
    }
    case "passlevels": {
      const { data: row } = await db
        .from("game_settings")
        .select("value")
        .eq("key", "season_pass_level_purchase")
        .maybeSingle();
      const cfg = (row?.value ?? {}) as any;
      const prices = cfg.prices ?? {};
      const { data: today } = await db
        .from("season_pass_level_purchases")
        .select("levels_bought,fc_spent")
        .gte("created_at", new Date(Date.now() - 86400000).toISOString());
      const lv = (today ?? []).reduce((a: number, r: any) => a + Number(r.levels_bought || 0), 0);
      const fc = (today ?? []).reduce((a: number, r: any) => a + Number(r.fc_spent || 0), 0);
      return edit(
        ctx,
        `🪜 <b>LEVEL PURCHASE SETTINGS</b>\nStatus: <b>${cfg.enabled === false ? "❌ DESATIVADO" : "✅ ATIVO"}</b>\nLimite diário: <b>${fmt(Number(cfg.daily_limit ?? 5))} níveis</b>\n\n<b>PREÇOS</b>\n${[1, 3, 5].map((n) => `• +${n} nível(is): <b>${fmt(Number(prices[String(n)] ?? 0))} FC</b>`).join("\n")}\n\nÚltimas 24h: <b>${fmt(lv)}</b> níveis · <b>${fmt(fc)} FC</b> queimados.`,
        kb([
          [{ t: "💰 EDITAR PREÇO", d: "ask:passlevelprice" }],
          [{ t: "🚧 LIMITE DIÁRIO", d: "ask:passlevellimit" }],
          [
            {
              t: cfg.enabled === false ? "✅ ATIVAR" : "⛔ DESATIVAR",
              d: `passlvtoggle:${cfg.enabled === false ? "on" : "off"}`,
            },
          ],
          nav("m:pass"),
        ]),
      );
    }
    case "passrewards": {
      const d = await rpc("admin_pass_overview", { p_admin_id: ctx.adminId });
      const rows = (d.rewards || [])
        .slice()
        .sort((a: any, b: any) => a.level - b.level || String(a.tier).localeCompare(String(b.tier)));
      const trackLabel: Record<string, string> = { free: "Free", adventurer: "Adventurer", legendary: "Legendary" };
      // Shows the stable reward key each level delivers, so misconfigured item keys are visible.
      const lines = rows.map(
        (r: any) =>
          `Lv.${r.level} · ${trackLabel[r.tier] || r.tier} · <code>${esc(r.reward_type)}</code> · key <code>${esc(r.reward_code || r.reward_type)}</code> · x${fmt(r.amount)}${r.enabled ? "" : " · ❌ off"}\n<code>${esc(r.id)}</code>`,
      );
      const chunk = lines.slice(0, 40).join("\n\n") || "sem recompensas cadastradas";
      return edit(
        ctx,
        `🎁 <b>MAPA DE RECOMPENSAS</b>\nPet Food entrega no inventário real de comida (chave <code>pet_food</code>).\n\n${chunk}${lines.length > 40 ? `\n\n… +${lines.length - 40} níveis` : ""}`,
        kb([[{ t: "🎁 EDITAR RECOMPENSA", d: "ask:passreward" }], [{ t: "⬅️ PASSE", d: "view:pass" }], nav()]),
      );
    }

    // Equipment rewards marked as claimed but with no matching item in the player's inventory.
    case "passmissing": {
      const d = await rpc("admin_check_missing_pass_rewards", { p_limit: 100 });
      const entries = (d?.entries || []) as any[];
      const lines = entries
        .slice(0, 30)
        .map(
          (e) =>
            `• @${esc(String(e.username ?? e.telegramId))} · <code>${e.telegramId}</code>\n   ${esc(e.season ?? "")} · Lv.${e.level} · ${esc(e.tier)} · ${esc(e.reward ?? e.slot)}\n   Claimed: <b>YES</b> · Inventory: <b>MISSING</b>`,
        );
      return edit(
        ctx,
        `🔍 <b>CHECK MISSING PASS REWARDS</b>\nInconsistências: <b>${fmt(Number(d?.total ?? 0))}</b>\n\n${lines.join("\n") || "✅ Nenhuma recompensa de equipamento faltando."}${entries.length > 30 ? `\n\n… +${entries.length - 30}` : ""}`,
        kb([
          [{ t: "🛠 FIX MISSING REWARDS", d: "passfix:all" }],
          [{ t: "🔄 REVERIFICAR", d: "view:passmissing" }],
          [{ t: "⬅️ PASSE", d: "view:pass" }],
          nav(),
        ]),
      );
    }

    case "pool": {
      const d = await rpc("admin_pool_overview", { p_admin_id: ctx.adminId });
      const p = d.pool || {};
      const srcLabels: Record<string, string> = {
        deposit: "Depósitos",
        battle_pass: "Battle Pass",
        egg_purchase: "Ovos",
        pet_purchase: "Pets",
        premium_shop: "Loja premium",
        event_purchase: "Eventos",
        other: "Outros",
      };
      const sources =
        Object.entries(d.sourcesToday || {})
          .map(
            ([k, v]: [string, any]) => `• ${esc(srcLabels[k] || k)}: ${fmt(v.poolTon)} TON (de ${fmt(v.grossTon)} TON)`,
          )
          .join("\n") || "• sem receita hoje";
      return edit(
        ctx,
        `💰 <b>COMMUNITY POOL</b>\n${esc(p.week_label)} · saldo <b>${fmt(p.balance_ton)} TON</b>\nTaxa de contribuição: <b>${d.contributionPercent}%</b>\nDistribuição: ${String(p.ends_at).slice(0, 16).replace("T", " ")}\n\n💎 Receita hoje: ${fmt(d.revenueToday)} TON → pool ${fmt(d.poolToday)} TON\n📆 Receita do ciclo: ${fmt(d.revenuePeriod)} TON → pool ${fmt(d.poolPeriod)} TON\n\n<b>ORIGENS HOJE</b>\n${sources}\n\nParticipantes ${fmt(d.participants)} · Elegíveis ${fmt(d.eligible)}\nMínimo ${d.settings?.minimum_points} pts · ranking ${d.settings?.ranking_share_percent}% · sorteio ${d.settings?.lottery_share_percent}%`,
        kb([
          [{ t: "⚙️ CONTRIBUTION RATE", d: "ask:poolrate" }],
          [{ t: "🏆 EVENT REWARD DISTRIBUTION", d: "view:pooltiers" }],
          [
            { t: "➕ VALOR", d: "pool:add" },
            { t: "➖ VALOR", d: "pool:remove" },
          ],
          [{ t: "⚙️ CONFIG", d: "ask:poolset" }],
          [{ t: "🎉 DISTRIBUIR AGORA", d: "confirm:pooldist" }],
          [{ t: "🚫 CANCELAR CICLO", d: "confirm:poolcancel" }],
          nav(),
        ]),
      );
    }

    case "pooltiers": {
      const d = (await rpc("admin_pool_ranking_tiers", { p_admin_id: ctx.adminId })) as any;
      const r = d.ranking || {};
      const tiers = (r.tiers || []) as any[];
      const label = (t: any) => (t.startRank === t.endRank ? `#${t.startRank}` : `#${t.startRank}–${t.endRank}`);
      const lines =
        tiers
          .map(
            (t) =>
              `• ${label(t)}: <b>${Number(t.poolPercent)}%</b> → ${fmt(t.rewardPerPlayerTon ?? 0)} TON cada · total ${fmt(t.totalTierAllocationTon ?? 0)} TON`,
          )
          .join("\n") || "sem faixas configuradas";
      const unalloc = Number(r.unallocatedNanoton || 0) / 1e9;
      const status = r.valid
        ? "✅ <b>DISTRIBUTION VALID</b>"
        : `❌ <b>INVALID_DISTRIBUTION</b> · ${fmt(unalloc)} TON UNALLOCATED`;
      return edit(
        ctx,
        `🏆 <b>EVENT REWARD DISTRIBUTION</b>\n\nTOTAL POOL: <b>${fmt(d.totalPoolTon)} TON</b>\nRANKING: <b>${fmt(d.rankingPoolTon)} TON</b>\nRAFFLE: <b>${fmt(d.rafflePoolTon)} TON</b>\n\nRANKING ALLOCATED: <b>${fmt(Number(r.allocatedNanoton || 0) / 1e9)} / ${fmt(r.rankingPoolTon)} TON</b>\nSoma das faixas: <b>${Number(r.tierPercentSum || 0)}%</b>\n\n<b>PREVIEW (${fmt(r.participants)} posições)</b>\n${lines}\n\n${status}`,
        kb([
          [{ t: "✏️ EDITAR FAIXA", d: "ask:pooltier" }],
          [{ t: "🔄 RECALCULAR", d: "view:pooltiers" }],
          [{ t: "⬅️ POOL", d: "view:pool" }],
          nav(),
        ]),
      );
    }



    case "invites": {
      const s = await rpc("admin_get_settings", { p_admin_id: ctx.adminId, p_category: "referral" });
      return edit(
        ctx,
        `🤝 <b>CONVITES</b>\n${s.settings.map((x: any) => `• ${esc(x.label)}: <b>${x.value}%</b>`).join("\n")}\n\nComissão paga somente em depósito TON confirmado, com idempotência.`,
        kb([
          [
            { t: "N1 %", d: "ref:1" },
            { t: "N2 %", d: "ref:2" },
            { t: "N3 %", d: "ref:3" },
          ],
          [{ t: "🌳 ÁRVORE DO USUÁRIO", d: "ask:tree" }],
          [{ t: "✂️ REMOVER VÍNCULO", d: "ask:unlink" }],
          nav(),
        ]),
      );
    }
    case "wallet": {
      const dep = await rpc("admin_list_transactions", {
        p_admin_id: ctx.adminId,
        p_kind: "deposit",
        p_status: null,
        p_limit: 8,
      });
      const wd = await rpc("admin_list_withdrawals", { p_admin_id: ctx.adminId, p_status: null, p_limit: 10 });
      const rate = await rpc("current_ton_fc_rate", {});
      const row = (t: any) =>
        `• <code>${String(t.id).slice(0, 8)}</code> ${esc(t.player)} — ${fmt(t.amount_ton)} TON [${esc(t.status)}]`;
      const viewButtons = (wd.items as any[])
        .slice(0, 6)
        .map((w) => [{ t: `👁 ${w.short_id} · ${fmt(w.net_ton ?? w.amount_ton)} TON`, d: `wd:${w.id}` }]);
      const feePercent = Number(wd.feePercent ?? 0);
      return edit(
        ctx,
        `💳 <b>CARTEIRA / ECONOMIA</b>\n💱 Taxa atual: <b>1 TON = ${fmt(rate)} FC</b>\n(vale só para depósitos confirmados após a alteração)\n💸 <b>WITHDRAWAL FEE: ${feePercent}%</b>\n\n<b>Depósitos</b>\n${dep.items.map(row).join("\n") || "—"}\n\n💸 <b>SAQUES</b>\n${withdrawalLines(wd.items)}`,
        kb([
          [
            { t: "✅ CONFIRMAR DEPÓSITO", d: "ask:depok" },
            { t: "❌ REJEITAR", d: "ask:depno" },
          ],
          ...viewButtons,
          [
            { t: "🟡 PENDENTES", d: "wdlist:pending" },
            { t: "✅ PAGOS", d: "wdlist:paid" },
          ],
          [{ t: "💳 CONNECTED WALLETS", d: "m:wallets" }],
          [{ t: "🔥 HOT WALLET", d: "m:hotwallet" }],
          [{ t: "💠 MÉTODOS DE DEPÓSITO", d: "dp:hub" }],
          [{ t: "📢 PAYOUT ANNOUNCEMENTS", d: "pa:menu" }],
          [
            { t: "💱 TON → FC RATE", d: "ask:tonrate" },
            { t: `💸 WITHDRAWAL FEE (${feePercent}%)`, d: "ask:wdfee" },
          ],
          [
            { t: "🪙 AJUSTAR FC", d: "ask:find" },
            { t: "💎 AJUSTAR TON", d: "ask:tonadj" },
          ],
          [
            { t: "📜 ÚLTIMOS AJUSTES TON", d: "tonhist:1" },
            { t: "🔎 AUDIT DEPOSITS", d: "ask:auditdep" },
          ],
          nav(),
        ]),
      );
    }
    case "hotwallet":
      return hotWalletHub(ctx);
    case "wallets": {
      const d = await rpc("admin_connected_wallets", { p_admin_id: ctx.adminId, p_query: null, p_limit: 12 });
      return edit(
        ctx,
        connectedWalletsText(d.items),
        kb([[{ t: "🔎 PESQUISAR", d: "ask:findwallet" }], nav("m:wallet")]),
      );
    }

    case "missions": {
      const d = await rpc("admin_missions_overview", { p_admin_id: ctx.adminId });
      return edit(
        ctx,
        `🎯 <b>MISSÕES</b>\n${d.missions.map((m: any) => `• <code>${esc(m.code)}</code> [${esc(m.scope)}] ${esc(m.title)} → ${fmt(m.reward_amount)} ${esc(m.reward_type)} ${m.enabled ? "✅" : "⛔"}`).join("\n") || "—"}`,
        kb([
          [{ t: "✏️ CRIAR/EDITAR", d: "ask:mission" }],
          [
            { t: "♻️ RESETAR DIÁRIAS", d: "confirm:missdaily" },
            { t: "♻️ SEMANAIS", d: "confirm:missweekly" },
          ],
          nav(),
        ]),
      );
    }
    case "channels": {
      const d = await rpc("admin_channels_overview", { p_admin_id: ctx.adminId });
      const list =
        (d.channels || [])
          .map(
            (c: any) =>
              `• <b>${esc(c.title)}</b> ${c.enabled ? "✅" : "⛔"}\n   ${esc(c.url)}\n   ${fmt(c.rewardFc)} FC · resgates: ${fmt(c.claims)} · pago: ${fmt(c.paidFc)} FC`,
          )
          .join("\n") || "—";
      return edit(
        ctx,
        `📡 <b>CANAIS OFICIAIS</b>\nA recompensa é <b>única por Telegram ID + canal</b> (one-time). Não há verificação de participação: o jogador toca JOIN, volta e toca VERIFY.\n\n${list}`,
        kb([[{ t: "✏️ EDITAR CANAL", d: "ask:channel" }], [{ t: "👤 CLAIMS DO JOGADOR", d: "ask:chclaims" }], nav()]),
      );
    }

    case "quests": {
      const d = await rpc("admin_quests_overview", { p_admin_id: ctx.adminId });
      const b = d.bonus || {};
      const list =
        (d.quests || [])
          .map(
            (q: any) =>
              `• <code>${esc(q.code)}</code> ${esc(q.title)}\n   evento <code>${esc(q.event_key)}</code> · meta ${q.target_amount} · ${fmt(q.reward_fc)} FC ${q.enabled ? "✅" : "⛔"}`,
          )
          .join("\n") || "—";
      const active = (d.quests || []).filter((q: any) => q.enabled).length;
      return edit(
        ctx,
        `🎯 <b>DAILY QUESTS</b>\nFuso do reset: <b>${esc(d.timezone)}</b> · dia atual ${esc(d.questDate)}\nQuests ativas: <b>${active}</b> · Resgates hoje: ${fmt(d.claimedToday)}\n\n${list}\n\n🎁 Daily Quest Chest: <b>${esc(b.name || "Common Hero Chest")}</b> — <code>${esc(b.item_code || "common_hero_chest")}</code> x${b.quantity ?? 1}\nRequired: <b>${active}/${active}</b> quests\n\nO progresso é gravado só pelo servidor (login, pet, boss, PvP, ovos/baús).`,
        kb([
          [{ t: "✏️ CRIAR/EDITAR QUEST", d: "ask:quest" }],
          [{ t: "🔄 REPAIR DEFAULT DAILY QUESTS", d: "view:questrepair" }],
          [
            { t: "🎁 BAÚ EXTRA 5/5", d: "ask:questbonus" },
            { t: "🕒 FUSO DO RESET", d: "ask:questtz" },
          ],
          [
            { t: "🚫 ATIVAR/DESATIVAR", d: "ask:questtoggle" },
            { t: "♻️ RESETAR HOJE", d: "confirm:questreset" },
          ],
          [{ t: "📦 DIAGNÓSTICO DOS BAÚS", d: "view:chests" }],
          nav(),
        ]),
      );
    }
    case "clans":
      return clansHub(ctx);
    case "events":
      return eventsHub(ctx);
    case "precovery":
      return prHub(ctx);
    case "market":
      return marketHub(ctx);
    case "spending":
      return spendHub(ctx);
    case "clanboss":
      return cbHub(ctx);
    case "partners":
      return partnersHub(ctx);

    case "gifts":
      return giftHub(ctx);

    case "boss":
      return bossPanel(ctx);

    case "ads": {
      const d = await rpc("admin_ads_overview", { p_admin_id: ctx.adminId });
      return edit(
        ctx,
        `📢 <b>ANÚNCIOS</b>\n${d.providers.map((a: any) => `• <code>${esc(a.code)}</code> ${esc(a.name)} ${a.enabled ? "✅" : "⛔"} — limite ${a.daily_limit}/dia · ${fmt(a.reward_fc)} FC · cooldown ${a.cooldown_seconds}s`).join("\n")}`,
        kb([[{ t: "✏️ EDITAR PROVEDOR", d: "ask:ads" }], nav()]),
      );
    }
    case "settings": {
      const d = await rpc("admin_get_settings", { p_admin_id: ctx.adminId, p_category: null });
      const body = d.settings
        .map((s: any) => `• <code>${esc(s.key)}</code> = <b>${esc(JSON.stringify(s.value))}</b>`)
        .join("\n");
      return edit(
        ctx,
        `⚙️ <b>CONFIGURAÇÕES</b>\n${body.slice(0, 3400)}`,
        kb([[{ t: "✏️ EDITAR CHAVE", d: "ask:setting" }], nav()]),
      );
    }
    case "audit": {
      const d = await rpc("admin_list_audit", { p_admin_id: ctx.adminId, p_limit: 15, p_offset: 0 });
      return edit(
        ctx,
        `📜 <b>AUDITORIA</b> (${fmt(d.total)})\n${
          d.events
            .map(
              (e: any) =>
                `• ${String(e.created_at).slice(5, 16).replace("T", " ")} <b>${esc(e.action)}</b> ${esc(e.target_id || "")}\n   ${esc(JSON.stringify(e.old_value))} → ${esc(JSON.stringify(e.new_value))}`,
            )
            .join("\n")
            .slice(0, 3500) || "—"
        }`,
        kb([[{ t: "🔄 ATUALIZAR", d: "m:audit" }], nav()]),
      );
    }
    case "status": {
      const s = await rpc("admin_status_overview", { p_admin_id: ctx.adminId });
      const g = await rpc("admin_game_day_state", { p_admin_id: ctx.adminId });
      const mins = Math.max(0, Math.round((Date.parse(g.nextResetAt) - Date.now()) / 60000));
      return edit(
        ctx,
        `📊 <b>STATUS</b>\n👥 ${fmt(s.players_total)} jogadores · ativos 24h ${fmt(s.players_active_24h)} · novos ${fmt(s.players_new_24h)} · banidos ${fmt(s.players_banned)}\n🪙 ${fmt(s.fc_circulating)} FC circulando\n💎 ${fmt(s.ton_deposited)} TON depositado · ${fmt(s.ton_withdrawn)} sacado\n💰 Pool ${fmt(s.pool_balance)} TON\n⚔️ ${fmt(s.pvp_battles_24h)} batalhas 24h · 👑 ${fmt(s.boss_active)} chefes ativos\n🦸 ${fmt(s.heroes_total)} heróis · 🐲 ${fmt(s.pets_total)} pets · 🤝 ${fmt(s.referrals_total)} convites\n🔧 Manutenção: ${s.maintenance ? "ATIVA" : "off"} · settings v${s.settings_version}\n\n📅 <b>CALENDÁRIO</b>\nCURRENT GAME DAY: <b>Day ${g.gameDayNumber}</b> (<code>${g.gameDay}</code>)\nSERVER TIME: <code>${esc(g.serverLocalTime)}</code> ${esc(g.timezone)}\nNEXT GAME DAY: <b>${String(g.resetHour).padStart(2, "0")}:00</b> · em ${Math.floor(mins / 60)}h ${mins % 60}m\nGAME LAUNCH: <code>${String(g.launchAt).slice(0, 16).replace("T", " ")}</code>\nClaims hoje: ${fmt(g.claimsToday)} · corrigidos pelo bug: ${fmt(g.repairedClaims)}`,
        kb([[{ t: "🔄 ATUALIZAR", d: "m:status" }], nav()]),
      );
    }

    case "maint": {
      const on =
        (await rpc("admin_get_settings", { p_admin_id: ctx.adminId, p_category: "system" })).settings.find(
          (s: any) => s.key === "maintenance_mode",
        )?.value === true;
      return edit(
        ctx,
        `🔧 <b>MANUTENÇÃO</b>\nStatus atual: <b>${on ? "ATIVA" : "desativada"}</b>\nCom manutenção ativa o Mini App mostra o aviso para todos, exceto o administrador mestre.`,
        kb([
          [{ t: on ? "✅ DESATIVAR" : "🔧 ATIVAR", d: `maint:${on ? "off" : "on"}` }],
          [{ t: "✏️ MENSAGEM", d: "ask:maintmsg" }],
          nav(),
        ]),
      );
    }
    case "cast":
      return edit(
        ctx,
        "📣 <b>BROADCAST</b>\nEscolha o público e depois envie a mensagem.",
        kb([
          [
            { t: "TODOS", d: "cast:all" },
            { t: "VIP", d: "cast:vip" },
          ],
          [
            { t: "PREMIUM", d: "cast:premium" },
            { t: "ATIVOS 7d", d: "cast:active" },
          ],
          [{ t: "TOP PVP", d: "cast:top_pvp" }],
          nav(),
        ]),
      );
    default:
      return home(ctx, true);
  }
}

// ---------------------------------------------------------------- withdrawals (financial module)
const WD_STATUS_ICON: Record<string, string> = {
  pending: "🟡",
  processing: "🔵",
  approved: "🔵",
  paid: "✅",
  completed: "✅",
  rejected: "❌",
  cancelled: "❌",
};

/** Wallets only accept the user-friendly mainnet form; raw "0:…" values are converted before display. */
const walletOut = (value: unknown) => toFriendlyTonAddress(value);

const dt = (value: unknown) =>
  value ? new Date(String(value)).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—";

/** Summary list: never hides the amount, flags withdrawals whose destination wallet is unknown. */
function withdrawalLines(items: any[]) {
  if (!items?.length) return "—";
  const groups: Record<string, any[]> = {};
  for (const w of items) (groups[w.status] ??= []).push(w);
  return Object.entries(groups)
    .map(([status, rows]) => {
      const head = `${WD_STATUS_ICON[status] || "•"} <b>${esc(status.toUpperCase())}</b>`;
      const body = rows
        .map(
          (w) =>
            `• <code>${esc(w.short_id)}</code> | ${w.username || w.player ? "@" + esc(w.username || w.player) : esc(String(w.telegram_id))} | ${fmt(w.amount_fc)} FC → <b>${Number(w.net_ton ?? w.amount_ton ?? 0).toFixed(3)} TON</b> (fee ${Number(w.fee_percent ?? 0)}%)${walletOut(w.wallet_address) ? "" : w.wallet_address ? " ⚠️ CARTEIRA INVÁLIDA" : " ⚠️ SEM CARTEIRA"}`,
        )
        .join("\n");
      return `${head}\n${body}`;
    })
    .join("\n\n");
}

function connectedWalletsText(items: any[]) {
  const list =
    (items || [])
      .map((w) =>
        [
          `👤 ${w.player ? "@" + esc(w.player) : "—"}`,
          `🆔 <code>${esc(String(w.telegram_id))}</code> · interno <code>${esc(String(w.user_id))}</code>`,
          `👛 <code>${esc(walletOut(w.wallet_address) ?? w.wallet_address ?? "—")}</code>${walletOut(w.wallet_address) ? "" : " ⚠️ INVÁLIDA"}`,
          `📅 ${dt(w.connected_at)}`,
        ].join("\n"),
      )
      .join("\n\n") || "—";
  return `💳 <b>CONNECTED WALLETS</b>\nCarteiras TON vinculadas aos jogadores.\n\n${list}`;
}

// ---------------------------------------------------------------- payout announcements (payments channel)
// The receipt must be posted by the MYTHREON game bot, so the game token comes first.
const GAME_BOT_TOKEN = (
  Deno.env.get("TELEGRAM_BOT_TOKEN_GAME") ||
  Deno.env.get("TELEGRAM_GAME_BOT_TOKEN") ||
  Deno.env.get("TELEGRAM_BOT_TOKEN") ||
  BOT_TOKEN
).trim();

async function tgAs(token: string, method: string, payload: Record<string, unknown>) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const body = (await res.json().catch(() => null)) as any;
  if (!res.ok || !body?.ok) {
    const reason = body?.description || `http_${res.status}`;
    console.error(`payments channel ${method} failed: ${reason}`);
    return { ok: false as const, error: String(reason) };
  }
  return { ok: true as const, result: body.result };
}

const fmtEn = (n: unknown) => Number(n ?? 0).toLocaleString("en-US");
const shortHash = (h: string) => (h.length > 16 ? `${h.slice(0, 6)}...${h.slice(-6)}` : h);

function payoutMessage(p: any) {
  const hash = String(p.txHash || "");
  const date = new Date(String(p.paidAt)).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
  const player = p.username ? `@${esc(p.username)}` : `Telegram ID: <code>${esc(String(p.telegramId ?? "—"))}</code>`;
  return [
    "✅ <b>FC Coins Withdrawal Successful!</b>",
    "",
    `🚀 Amount: <b>${fmtEn(p.amountFc)} FC</b>`,
    "",
    `💰 Gross Value: <b>${Number(p.grossTon ?? p.amountTon ?? 0).toFixed(3)} TON</b>`,
    "",
    `💸 Fee (${Number(p.feePercent ?? 0)}%): <b>${Number(p.feeTon ?? 0).toFixed(3)} TON</b>`,
    "",
    `✅ Received: <b>${Number(p.netTon ?? p.amountTon ?? 0).toFixed(3)} TON</b>`,
    "",
    `🔗 TxID: <a href="https://tonviewer.com/transaction/${encodeURIComponent(hash)}">${esc(shortHash(hash))}</a>`,
    "",
    `👤 Player: ${player}`,
    "",
    `🕒 Date: ${esc(date)}`,
  ].join("\n");
}

function payoutKeyboard(appLink?: string | null, newsUrl?: string | null) {
  const rows: { text: string; url: string }[][] = [];
  const app = String(appLink || "https://t.me/Mythreonbot/app");
  if (app) rows.push([{ text: "🎮 PLAY GAME", url: app }]);
  if (newsUrl) rows.push([{ text: "📢 NEWS CHANNEL", url: String(newsUrl) }]);
  return rows.length ? { inline_keyboard: rows } : undefined;
}

/**
 * Publishes the receipt for one completed withdrawal. Fully idempotent: the database claim
 * refuses a second post for the same withdrawal and stores the channel message id.
 */
async function announcePayout(
  adminId: number,
  withdrawalId: string,
): Promise<{ status: "sent" | "skipped" | "failed"; detail: string }> {
  let claim: any;
  try {
    claim = await rpc("admin_payout_announcement_claim", { p_admin_id: adminId, p_withdrawal_id: withdrawalId });
  } catch (error) {
    return { status: "failed", detail: error instanceof Error ? error.message : "claim_failed" };
  }
  if (claim?.skip) return { status: "skipped", detail: String(claim.skip) };
  if (claim?.enabled === false) return { status: "skipped", detail: "channel_disabled" };
  const chatId = String(claim.channelId || "").trim();
  if (!chatId) {
    await rpc("admin_payout_announcement_record", {
      p_admin_id: adminId,
      p_withdrawal_id: withdrawalId,
      p_status: "failed",
      p_error: "channel_not_configured",
    });
    return { status: "failed", detail: "channel_not_configured" };
  }
  const sent = await tgAs(GAME_BOT_TOKEN, "sendMessage", {
    chat_id: chatId,
    text: payoutMessage(claim),
    parse_mode: "HTML",
    disable_web_page_preview: true,
    reply_markup: payoutKeyboard(claim.appLink, claim.newsUrl),
  });
  if (!sent.ok) {
    await rpc("admin_payout_announcement_record", {
      p_admin_id: adminId,
      p_withdrawal_id: withdrawalId,
      p_status: "failed",
      p_channel_id: chatId,
      p_error: sent.error,
    });
    return { status: "failed", detail: sent.error };
  }
  await rpc("admin_payout_announcement_record", {
    p_admin_id: adminId,
    p_withdrawal_id: withdrawalId,
    p_status: "sent",
    p_channel_id: chatId,
    p_message_id: Number(sent.result?.message_id) || null,
  });
  return { status: "sent", detail: String(sent.result?.message_id ?? "") };
}

function payoutOverviewText(d: any) {
  const items =
    ((d.items as any[]) || [])
      .map((i) => {
        const icon = i.status === "sent" ? "✅" : i.status === "failed" ? "⚠️" : "🕒";
        return (
          `${icon} <code>${esc(String(i.withdrawal_id).slice(0, 8))}</code> | ${i.player ? "@" + esc(i.player) : "—"} | ${fmtEn(i.amount_fc)} FC · ${Number(i.amount_ton ?? 0).toFixed(6)} TON` +
          `\n   ${i.status === "sent" ? `msg <code>${esc(String(i.message_id ?? "—"))}</code>` : esc(i.last_error || "aguardando envio")}`
        );
      })
      .join("\n") || "—";
  return [
    "📢 <b>PAYOUT ANNOUNCEMENTS</b>",
    "",
    `Channel:\n<code>${esc(d.channelId || "NÃO CONFIGURADO")}</code>`,
    `Status: <b>${d.channelId ? "Connected" : "Error"}</b>${d.enabled === false ? " (envio desativado)" : ""}`,
    `Pendentes/falhos: <b>${(d.pending || []).length}</b>`,
    "",
    items,
  ].join("\n");
}

async function payoutMenu(ctx: Ctx, editing = true) {
  const d = await rpc("admin_payout_announcements", { p_admin_id: ctx.adminId, p_limit: 8 });
  const markup = kb([
    [{ t: "📄 LAST PAYOUTS", d: "pa:list" }],
    [{ t: "♻️ RETRY FAILED", d: "pa:retry" }],
    [{ t: "🧪 SEND TEST MESSAGE", d: "pa:test" }],
    [{ t: "⚙️ CHANNEL SETTINGS", d: "ask:pachat" }],
    nav("m:wallet"),
  ]);
  const text = payoutOverviewText(d);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function handlePayoutAnnouncements(ctx: Ctx, action: string) {
  if (action === "list" || action === "menu") return payoutMenu(ctx);
  if (action === "test") {
    const d = await rpc("admin_payout_announcements", { p_admin_id: ctx.adminId, p_limit: 1 });
    const chatId = String(d.channelId || "").trim();
    if (!chatId)
      return send(
        ctx,
        "⚠️ Canal de pagamentos não configurado. Use CHANNEL SETTINGS.",
        kb([[{ t: "⚙️ CHANNEL SETTINGS", d: "ask:pachat" }], nav("m:wallet")]),
      );
    const member = await tgAs(GAME_BOT_TOKEN, "getChat", { chat_id: chatId });
    if (!member.ok)
      return send(
        ctx,
        `❌ <b>Erro administrativo</b>\nO bot do jogo não acessa o canal <code>${esc(chatId)}</code>.\nMotivo: <code>${esc(member.error)}</code>\n\nAdicione o bot ao canal como administrador com permissão de postar.`,
        kb([[{ t: "📢 PAYOUT ANNOUNCEMENTS", d: "pa:menu" }], nav("m:wallet")]),
      );
    const res = await tgAs(GAME_BOT_TOKEN, "sendMessage", {
      chat_id: chatId,
      text: "✅ <b>Mythreon Payments Channel Connected</b>",
      parse_mode: "HTML",
    });
    return send(
      ctx,
      res.ok
        ? `✅ Mensagem de teste publicada no canal <code>${esc(chatId)}</code>.`
        : `❌ Falha ao publicar: <code>${esc(res.error)}</code>\nVerifique se o bot é administrador com permissão de envio.`,
      kb([[{ t: "📢 PAYOUT ANNOUNCEMENTS", d: "pa:menu" }], nav("m:wallet")]),
    );
  }
  if (action === "retry") {
    const d = await rpc("admin_payout_announcements", { p_admin_id: ctx.adminId, p_limit: 30 });
    const pending: string[] = (d.pending as string[]) || [];
    if (!pending.length)
      return send(
        ctx,
        "✅ Nenhum comprovante pendente.",
        kb([[{ t: "📢 PAYOUT ANNOUNCEMENTS", d: "pa:menu" }], nav("m:wallet")]),
      );
    const results: string[] = [];
    for (const id of pending.slice(0, 10)) {
      const r = await announcePayout(ctx.adminId, id);
      results.push(
        `${r.status === "sent" ? "✅" : r.status === "skipped" ? "🚫" : "⚠️"} <code>${esc(id.slice(0, 8))}</code> ${esc(r.detail)}`,
      );
    }
    return send(
      ctx,
      `♻️ <b>RETRY FAILED</b>\n\n${results.join("\n")}`,
      kb([[{ t: "📢 PAYOUT ANNOUNCEMENTS", d: "pa:menu" }], nav("m:wallet")]),
    );
  }
  return payoutMenu(ctx);
}

async function resolveWithdrawalId(ref: string): Promise<string | null> {
  const value = String(ref || "").trim();
  if (!value) return null;
  const { data } = await db.from("wallet_withdrawals").select("id").ilike("id", `${value}%`).limit(2);
  if (!data?.length || data.length > 1) return null;
  return data[0].id as string;
}

/** Full detail card: shows the destination wallet in full, never truncated. */
async function withdrawalCard(ctx: Ctx, id: string, editing = true) {
  const w = await rpc("admin_withdrawal_detail", { p_admin_id: ctx.adminId, p_withdrawal_id: id });
  const status = String(w.status);
  const done = ["paid", "completed"].includes(status);
  const closed = done || ["rejected", "cancelled"].includes(status);
  // Snapshot taken when the player requested the withdrawal — never re-read from the profile.
  const friendly = walletOut(w.walletAddress);
  const lines = [
    "💸 <b>WITHDRAWAL DETAILS</b>",
    "",
    `👤 Player: ${w.username ? "@" + esc(w.username) : "—"}`,
    `🆔 Telegram ID: <code>${esc(String(w.telegramId ?? "—"))}</code>`,
    `🔑 Withdrawal ID: <code>${esc(w.shortId)}</code>`,
    "",
    `💰 FC burned: <b>${fmt(w.amountFc)} FC</b>`,
    `💎 Gross: <b>${Number(w.grossTon ?? w.amountTon ?? 0).toFixed(3)} TON</b>`,
    `💸 Fee (${Number(w.feePercent ?? 0)}%): <b>-${Number(w.feeTon ?? 0).toFixed(3)} TON</b>`,
    `✅ Net to pay: <b>${Number(w.netTon ?? w.amountTon ?? 0).toFixed(3)} TON</b>`,
    "",
    "👛 <b>TON WALLET:</b>",
    friendly
      ? `<code>${esc(friendly)}</code>`
      : w.walletAddress
        ? `⚠️ <b>INVALID TON WALLET</b>\nSaved value:\n<code>${esc(String(w.walletAddress))}</code>`
        : "⚠️ <b>WALLET NOT FOUND — MANUAL REVIEW REQUIRED</b>",
    "",
    `📅 Requested:\n${dt(w.createdAt)}`,
    "",
    `${WD_STATUS_ICON[status] || "•"} Status:\n<b>${esc(status.toUpperCase())}</b>`,
  ];
  if (w.txHash) lines.push("", `🧾 TX:\n<code>${esc(w.txHash)}</code>`, `📅 Paid: ${dt(w.paidAt)}`);
  if (!friendly && w.currentWallet)
    lines.push(
      "",
      `ℹ️ Carteira atual do jogador (não vinculada a este saque):\n<code>${esc(walletOut(w.currentWallet) ?? String(w.currentWallet))}</code>`,
    );
  if (w.refundedAt) lines.push("", `↩️ FC devolvido em ${dt(w.refundedAt)}`);

  const rows: { t: string; d: string }[][] = [];
  if (friendly) rows.push([{ t: "📋 COPY WALLET", d: `wdcp:${w.id}` }]);
  if (w.telegramId) rows.push([{ t: "🔎 VIEW USER", d: `find:${w.telegramId}` }]);
  if (!closed && friendly) rows.push([{ t: "💎 PAY WITHDRAWAL", d: `wdpay:${w.id}` }]);
  if (!closed)
    rows.push([
      { t: "✅ MARK AS PAID", d: `wdmk:${w.id}` },
      { t: "❌ REJECT", d: `wdrj:${w.id}` },
    ]);
  if (status === "processing" || status === "approved") rows.push([{ t: "↩️ PAGAMENTO FALHOU", d: `wdfail:${w.id}` }]);
  if (done && w.txHash) rows.push([{ t: "📢 PUBLICAR COMPROVANTE", d: `pasend:${w.id}` }]);
  rows.push([
    { t: "⬅️ BACK", d: "m:wallet" },
    { t: "🏠 Menu", d: "home" },
  ]);
  const markup = kb(rows);
  return editing ? edit(ctx, lines.join("\n"), markup) : send(ctx, lines.join("\n"), markup);
}

async function handleWithdrawal(ctx: Ctx, head: string, id: string) {
  switch (head) {
    case "wd":
      return withdrawalCard(ctx, id);
    case "wdcp": {
      const w = await rpc("admin_withdrawal_detail", { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      const friendly = walletOut(w.walletAddress);
      if (!friendly)
        return send(
          ctx,
          w.walletAddress ? "⚠️ INVALID TON WALLET" : "⚠️ WALLET NOT FOUND — MANUAL REVIEW REQUIRED",
          kb([[{ t: "⬅️ BACK", d: `wd:${id}` }]]),
        );
      // Separate message containing ONLY the user-friendly address: tap to copy inside Telegram.
      await tg("sendMessage", { chat_id: ctx.chatId, text: friendly });
      return;
    }
    case "wdpay": {
      const w = await rpc("admin_withdrawal_detail", { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      if (["paid", "completed"].includes(String(w.status))) throw new Error("already_processed");
      if (!walletOut(w.walletAddress)) throw new Error("wallet_missing");
      if (Number(w.amountTon) <= 0) throw new Error("invalid_amount");
      return edit(
        ctx,
        [
          "⚠️ <b>CONFIRM WITHDRAWAL</b>",
          "",
          `Player: ${w.username ? "@" + esc(w.username) : esc(String(w.telegramId))}`,
          `Amount: <b>${fmt(w.amountTon)} TON</b>`,
          "",
          "Destination:",
          `<code>${esc(walletOut(w.walletAddress)!)}</code>`,
          "",
          "O saque será bloqueado como <b>PROCESSING</b> para evitar pagamento duplicado. Ele só ficará <b>PAID</b> depois que você informar o hash da transação.",
        ].join("\n"),
        kb([[{ t: "✅ CONFIRM PAYMENT", d: `wdgo:${id}` }], [{ t: "❌ CANCEL", d: `wd:${id}` }]]),
      );
    }
    case "wdgo": {
      // pending -> processing (atomic lock in the database)
      const w = await rpc("admin_withdrawal_lock", { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      await send(
        ctx,
        [
          "🔵 <b>WITHDRAWAL PROCESSING</b>",
          "",
          `Envie <b>${fmt(w.amountTon)} TON</b> para:`,
          `<code>${esc(walletOut(w.walletAddress) ?? String(w.walletAddress ?? "—"))}</code>`,
          "",
          "Depois toque em <b>MARK AS PAID</b> e informe o hash da transação.\nSe o pagamento falhar, use <b>PAGAMENTO FALHOU</b> — o saque volta para PENDING.",
        ].join("\n"),
        kb([
          [{ t: "✅ MARK AS PAID", d: `wdmk:${id}` }],
          [{ t: "↩️ PAGAMENTO FALHOU", d: `wdfail:${id}` }],
          [{ t: "⬅️ BACK", d: `wd:${id}` }],
        ]),
      );
      return;
    }
    case "wdmk":
      return ask(
        ctx,
        `wdhash|${id}`,
        "Envie o <b>hash da transação TON</b> do pagamento.\nO saque só é marcado como PAGO com o hash.",
      );
    case "wdfail": {
      await rpc("admin_withdrawal_unlock", {
        p_admin_id: ctx.adminId,
        p_withdrawal_id: id,
        p_reason: "pagamento não confirmado",
      });
      await send(ctx, "❌ <b>Payment failed</b>\nNo TON was confirmed as sent.\nWithdrawal remains pending.");
      return withdrawalCard(ctx, id, false);
    }
    case "wdrj": {
      const w = await rpc("admin_withdrawal_detail", { p_admin_id: ctx.adminId, p_withdrawal_id: id });
      return edit(
        ctx,
        `❌ <b>REJEITAR SAQUE</b>\n<code>${esc(w.shortId)}</code> · ${fmt(w.amountTon)} TON\n\nO jogador receberá <b>${fmt(w.amountFc)} FC</b> de volta (uma única vez).`,
        kb([[{ t: "✅ CONFIRMAR REJEIÇÃO", d: `wdrjgo:${id}` }], [{ t: "❌ CANCELAR", d: `wd:${id}` }]]),
      );
    }
    case "wdrjgo": {
      await rpc("admin_withdrawal_reject", {
        p_admin_id: ctx.adminId,
        p_withdrawal_id: id,
        p_reason: "rejeitado pelo painel admin",
      });
      await send(ctx, "❌ Saque rejeitado e FC devolvido ao jogador.");
      return withdrawalCard(ctx, id, false);
    }
  }
}

// ---------------------------------------------------------------- prompts
// ---------------------------------------------------------------- 🎡 GLOBAL MYSTERY ROULETTE
// TUDO aqui é ADMIN-ONLY: o ciclo atual (categoria secreta, herói alvo, meta e gasto global)
// NUNCA é exposto ao jogador. O bot apenas lê/escreve configuração — nenhum prêmio é entregue aqui.
const RL_CLASSES: Record<string, string> = {
  mh: "MYTHIC_HERO",
  nh: "NFT_HERO",
  ch: "CELESTIAL_HERO",
  my: "MYTH",
  eq: "NFT_EQUIPMENT",
};

async function rlHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_roulette_overview", { p_admin_id: ctx.adminId })) as any;
  const s = d.settings ?? {};
  const c = d.cycle ?? null;
  const a = d.audit ?? {};
  const dist = d.distributed ?? {};
  const res = d.mythReserve ?? {};
  const text = [
    "🎡 <b>GLOBAL MYSTERY ROULETTE</b>",
    "<i>Ciclo global · prêmio premium secreto · 100% server-side</i>",
    "",
    `<b>Status:</b> ${s.enabled ? "✅ ATIVA" : "⛔ DESATIVADA"}${s.paused ? " · ⏸ PAUSADA" : ""}`,
    `<b>Giro:</b> 💎 ${fmt(s.spinCostTon)} TON · <b>Meta Celestial:</b> 💎 ${fmt(s.celestialThresholdTon)} TON`,
    `<b>Pesos mystery:</b> Mítico ${fmt(s.weightMythic)} · NFT ${fmt(s.weightNftHero)} · Celestial ${fmt(s.weightCelestial)}`,
    `<b>Pesos normais:</b> MYTH ${fmt(s.normalWeightMyth)} · Equip NFT ${fmt(s.normalWeightEquipment)}`,
    `<b>Reserva MYTH:</b> ${fmt(res.available)} disponível (de ${fmt(res.allocated)})`,
    "",
    c
      ? [
          `<b>CICLO #${fmt(c.number)}</b> — ${esc(String(c.status))}`,
          `Alvo: <b>${esc(String(c.targetType))}</b> · ${esc(String(c.targetName ?? c.targetId))}`,
          `Meta: 💎 ${fmt(c.requiredTon)} TON · Gasto: 💎 ${fmt(c.spentTon)} TON · Falta: 💎 ${fmt(c.remainingTon)} TON`,
          `Prêmio: <b>${esc(rlRewardLabel(String(c.rewardStatus ?? "PENDING")))}</b>${
            c.rewardDeliveredAt ? ` · ${esc(String(c.rewardDeliveredAt).slice(0, 16).replace("T", " "))}` : ""
          }${c.rewardError ? `\n⚠️ <code>${esc(String(c.rewardError))}</code>` : ""}`,
        ].join("\n")
      : "<b>CICLO:</b> nenhum ciclo aberto",
    "",
    `<b>Prêmios pendentes de recuperação:</b> ${fmt((d.pendingRewards ?? []).length)} · <b>falhas:</b> ${fmt(d.failedRewards)}`,

    "",
    `<b>Giros:</b> ${fmt(a.totalSpins)} · <b>TON recebido:</b> ${fmt(a.totalTonReceived)}`,
    `<b>Pendentes:</b> pagamento ${fmt(a.pendingPayments)} · travados ${fmt(a.stuck)}`,
    `<b>Entregas:</b> MYTH ${fmt(dist.mythTotal)} · Equip ${fmt(dist.equipment)} · Mítico ${fmt(dist.mythicHeroes)} · NFT ${fmt(dist.nftHeroes)} · Celestial ${fmt(dist.celestials)}`,
    `<b>Ciclos concluídos:</b> ${fmt(d.cyclesAwarded)}`,
  ].join("\n");
  const rows = [
    [{ t: s.enabled ? "⛔ DESATIVAR" : "✅ ATIVAR", d: `rl:set:enabled:${s.enabled ? 0 : 1}` }],
    [{ t: s.paused ? "▶️ RETOMAR" : "⏸ PAUSAR", d: `rl:set:paused:${s.paused ? 0 : 1}` }],
    [
      { t: "💎 CUSTO DO GIRO", d: "rl:ask:rlcost" },
      { t: "👑 META CELESTIAL", d: "rl:ask:rlcel" },
    ],
    [
      { t: "⚖️ PESOS MYSTERY", d: "rl:ask:rlwm" },
      { t: "⚖️ PESOS NORMAIS", d: "rl:ask:rlwn" },
    ],
    [{ t: "🪙 RESERVA MYTH", d: "rl:ask:rlres" }],
    [
      { t: "🪙 MYTH TIERS", d: "rl:pool:my" },
      { t: "🛡 EQUIP NFT", d: "rl:pool:eq" },
    ],
    [
      { t: "🔮 MÍTICOS", d: "rl:pool:mh" },
      { t: "💎 HERÓIS NFT", d: "rl:pool:nh" },
    ],
    [{ t: "👑 CELESTIAIS", d: "rl:pool:ch" }],
    [
      { t: "📜 HISTÓRICO / AUDITORIA", d: "rl:hist" },
      { t: "🛠 RECUPERAR GIROS", d: "rl:fix" },
    ],
    [{ t: "🏆 PRÊMIOS DE META (THRESHOLD)", d: "rl:rw:audit" }],
    [{ t: "❌ CANCELAR CICLO ATUAL", d: "rl:cancel" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

function rlRewardLabel(status: string) {
  const map: Record<string, string> = {
    PENDING: "⏳ PROCESSANDO",
    DELIVERING: "⏳ PROCESSANDO",
    DELIVERED: "✅ ENTREGUE",
    FAILED: "⚠️ PENDENTE DE RECUPERAÇÃO",
    MANUAL_REVIEW: "🔎 REVISÃO MANUAL",
  };
  return map[status] ?? status;
}

async function rlRewards(ctx: Ctx, action = "audit", cycle?: string) {
  const d = (await rpc("admin_roulette_reward_recovery", {
    p_admin_id: ctx.adminId,
    p_action: action,
    p_cycle: cycle ?? null,
  })) as any;
  const pending = (d.pending ?? []) as any[];
  const failed = (d.failed ?? []) as any[];
  const history = (d.history ?? []) as any[];
  const text = [
    "🏆 <b>EVENTO · PRÊMIOS DE META</b>",
    "<i>Entrega server-side, transacional e idempotente (spent ≥ meta)</i>",
    "",
    action !== "audit" ? `<b>Recuperados agora:</b> ${fmt(d.recovered)}\n` : "",
    `<b>PENDENTES DE RECUPERAÇÃO</b>\n${
      pending
        .map((p) =>
          [
            `• Ciclo #${fmt(p.cycleNumber)} · ${esc(String(p.rewardType))} — ${esc(String(p.rewardName ?? p.rewardKey))}`,
            `   Meta 💎 ${fmt(p.targetTon)} · Gasto 💎 ${fmt(p.spentTon)} · Threshold ${p.thresholdReached ? "SIM" : "NÃO"} · Entregue NÃO`,
            `   Prêmio: ${esc(rlRewardLabel(String(p.rewardStatus)))} · tentativas ${fmt(p.attempts)}${
              p.lastError ? ` · <code>${esc(String(p.lastError))}</code>` : ""
            }`,
            `   <code>${esc(String(p.cycleId))}</code>`,
          ].join("\n"),
        )
        .join("\n") || "nenhum ✅"
    }`,
    "",
    `<b>FALHAS DE ENTREGA</b>\n${
      failed
        .map((f) => `• Ciclo #${fmt(f.number)} · ${esc(String(f.rewardStatus))} · <code>${esc(String(f.error ?? "-"))}</code>`)
        .join("\n") || "nenhuma ✅"
    }`,
    "",
    `<b>HISTÓRICO DE ENTREGAS</b>\n${
      history
        .map(
          (h) =>
            `• #${fmt(h.number)} · ${esc(String(h.player ?? "-"))} · ${esc(String(h.rewardType))} ${esc(
              String(h.rewardKey ?? ""),
            )} · ${esc(String(h.deliveredAt).slice(0, 16).replace("T", " "))}`,
        )
        .join("\n") || "nenhuma ainda"
    }`,
  ]
    .filter(Boolean)
    .join("\n");
  const rows = [
    [{ t: "🔄 FORÇAR RECHECK", d: "rl:rw:recheck" }],
    [{ t: "♻️ REENTREGAR PENDENTES", d: "rl:rw:retry" }],
    [{ t: "⬅️ VOLTAR", d: "rl:hub" }],
    nav(),
  ];
  return edit(ctx, text, kb(rows));
}


async function rlPool(ctx: Ctx, code: string) {
  const cls = RL_CLASSES[code] ?? "MYTH";
  const list = (await rpc("admin_roulette_reward_list", { p_admin_id: ctx.adminId, p_class: cls })) as any[];
  const text = [
    `🎡 <b>${esc(cls)}</b>`,
    "",
    list
      .map((r) =>
        [
          `${r.enabled ? "✅" : "⛔"} <b>${esc(String(r.label || r.key))}</b> <code>${esc(String(r.key))}</code>`,
          `   peso ${fmt(r.weight)}${r.quantity ? ` · qtd ${fmt(r.quantity)}` : ""}${
            r.referenceTon ? ` · ref 💎 ${fmt(r.referenceTon)} TON` : ""
          }${r.stock !== null && r.stock !== undefined ? ` · estoque ${fmt(r.stock)}` : ""}${
            r.isActiveTarget ? " · 🎯 ALVO DO CICLO" : ""
          }`,
        ].join("\n"),
      )
      .join("\n") || "pool vazio",
    "",
    "<i>Use os botões para editar por chave.</i>",
  ].join("\n");
  const rows = [
    [{ t: "✏️ PESO", d: `rl:ask:rlw:${code}` }],
    cls === "MYTH" ? [{ t: "✏️ QUANTIDADE MYTH", d: `rl:ask:rlq:${code}` }] : [{ t: "✏️ CUSTO DE REFERÊNCIA (TON)", d: `rl:ask:rlref:${code}` }],
    [{ t: "🔁 ATIVAR / DESATIVAR", d: `rl:ask:rle:${code}` }],
    [{ t: "⬅️ VOLTAR", d: "rl:hub" }],
  ];
  return edit(ctx, text, kb(rows));
}

async function rlHist(ctx: Ctx) {
  const d = (await rpc("admin_roulette_history", { p_admin_id: ctx.adminId, p_limit: 15 })) as any;
  const cycles = (d.cycles ?? []) as any[];
  const winners = (d.celestialWinners ?? []) as any[];
  const intents = (d.pendingIntents ?? []) as any[];
  const text = [
    "🎡 <b>HISTÓRICO / AUDITORIA</b>",
    "",
    `<b>CICLOS</b>\n${
      cycles
        .map(
          (c) =>
            `• #${fmt(c.number)} ${esc(String(c.status))} · ${esc(String(c.targetType))} ${esc(String(c.targetId))} · 💎 ${fmt(
              c.spentTon,
            )}/${fmt(c.requiredTon)} TON${c.winner ? ` · 🏆 ${esc(String(c.winner))}` : ""}`,
        )
        .join("\n") || "nenhum ciclo"
    }`,
    "",
    `<b>CELESTIAIS ENTREGUES</b>\n${
      winners.map((w) => `• ${esc(String(w.player))} — ${esc(String(w.hero))}`).join("\n") || "nenhum ainda"
    }`,
    "",
    `<b>PAGAMENTOS / GIROS PENDENTES</b>\n${
      intents
        .map((i) => `• ${esc(String(i.player))} · ${esc(String(i.status))} · 💎 ${fmt(i.ton)} TON`)
        .join("\n") || "nenhum"
    }`,
  ].join("\n");
  return edit(ctx, text, kb([[{ t: "⬅️ VOLTAR", d: "rl:hub" }], nav()]));
}

async function rlCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.", b ? [b] : []);
  if (sub === "pool") return rlPool(ctx, a);
  if (sub === "hist") return rlHist(ctx);
  if (sub === "rw") return rlRewards(ctx, a ?? "audit", b);

  if (sub === "cancel") {
    const r = (await rpc("admin_roulette_cycle_cancel", { p_admin_id: ctx.adminId, p_reason: "admin bot" })) as any;
    await send(ctx, `🎡 Ciclo #${fmt(r.cancelled)} cancelado e auditado. Novo ciclo aberto.`);
    return rlHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "fix") {
    const r = (await rpc("roulette_reconcile", { p_max_age_minutes: 4320 })) as any;
    await send(ctx, `🛠 Recuperação: ${fmt(r?.resolved ?? 0)} giro(s) concluído(s).`);
    return rlHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "set") await rpc("admin_roulette_set", { p_admin_id: ctx.adminId, p_field: a, p_value: b });
  return rlHub(ctx);
}

async function rlPrompt(ctx: Ctx, key: string, args: string[], text: string) {
  const value = text.trim();
  const cls = RL_CLASSES[args[0] ?? ""] ?? "MYTH";
  const simple: Record<string, string> = {
    rlcost: "spin_cost_ton",
    rlcel: "celestial_threshold_ton",
    rlres: "myth_reserve",
  };
  if (simple[key]) {
    await rpc("admin_roulette_set", { p_admin_id: ctx.adminId, p_field: simple[key], p_value: value });
  } else if (key === "rlwm" || key === "rlwn") {
    const parts = value.split(/[\s,;/]+/).filter(Boolean);
    const fields = key === "rlwm"
      ? ["weight_mythic", "weight_nft_hero", "weight_celestial"]
      : ["normal_weight_myth", "normal_weight_equipment"];
    if (parts.length !== fields.length) throw new Error(`KEEP_SESSION::⚠️ Envie ${fields.length} números separados por espaço.`);
    for (let i = 0; i < fields.length; i += 1) {
      await rpc("admin_roulette_set", { p_admin_id: ctx.adminId, p_field: fields[i], p_value: parts[i] });
    }
  } else {
    // "<chave> <valor>" — ex.: "cel-aetherion 300"
    const [rewardKey, ...restValue] = value.split(/\s+/);
    const field = key === "rlw" ? "weight" : key === "rlq" ? "quantity" : key === "rlref" ? "reference_ton" : "enabled";
    if (!rewardKey || restValue.length === 0) throw new Error("KEEP_SESSION::⚠️ Formato: <code>chave valor</code>");
    await rpc("admin_roulette_reward_set", {
      p_admin_id: ctx.adminId, p_class: cls, p_key: rewardKey, p_field: field, p_value: restValue.join(" "),
    });
  }
  await clearSession(ctx);
  await send(ctx, "🎡 Roleta atualizada.");
  return rlHub({ ...ctx, messageId: undefined }, false);
}

const PROMPTS: Record<string, string> = {
  tmprice: "💰 Envie <code>chave preço_ton</code>.\nEx.: <code>iron 5</code>",
  tmdaily: "⛏ Envie <code>chave ton_por_dia</code>.\nEx.: <code>iron 0.11</code>",
  tmstore: "📦 Envie <code>chave dias_de_armazenamento</code> (1 a 60).\nEx.: <code>iron 7</code>",
  tmmaxper: "🔢 Envie <code>chave limite_por_jogador</code>.\nEx.: <code>iron 1</code>",
  tmname: "✏️ Envie <code>chave novo nome</code>.\nEx.: <code>iron Mina de Ferro Arcano</code>",
  tmdesc: "📝 Envie <code>chave descrição</code>.\nEx.: <code>iron Veios de ferro encantado...</code>",
  tmimage: "🖼 Envie <code>chave url_da_imagem</code>.\nEx.: <code>iron /__l5e/assets-v1/.../mine-iron.jpg</code>",
  tmtoggle: "🔁 Envie <code>chave on|off</code> para exibir ou ocultar a mina.\nEx.: <code>celestial off</code>",
  tmcreate: "➕ Envie <code>chave Nome da mina</code>.\nEx.: <code>void Mina do Vazio</code>",
  tmbonus30: "🎁 Envie o <b>bônus de fidelidade de 30 dias</b> em %.\nEx.: <code>5</code>",
  tmbonus60: "🎁 Envie o <b>bônus de fidelidade de 60 dias</b> em %.\nEx.: <code>10</code>",
  tmmaxtotal: "🔢 Envie o <b>limite total de minas</b> por jogador.\nEx.: <code>4</code>",
  tskmin: "💎 Envie o <b>stake mínimo</b> em TON. Ex.: <code>1</code>",
  tskmax: "💎 Envie o <b>stake máximo</b> por posição em TON (<code>0</code> = sem limite). Ex.: <code>500</code>",
  tskautomin: "💎 Envie o <b>mínimo do buffer de auto-staking</b> em TON. Ex.: <code>1</code>",
  tskpool: "🪙 Envie o <b>reward pool</b> total em TON destinado ao staking. Ex.: <code>500</code>",
  tskpoolmin: "🛡 Envie a <b>reserva mínima</b> do pool em TON (circuit breaker). Ex.: <code>10</code>",
  tskpenalty: "⚠️ Envie a <b>penalidade de saque antecipado</b> em %. Ex.: <code>10</code>",
  tskmonth: "🗓 Envie quantos <b>dias</b> equivalem a 1 mês de rendimento. Ex.: <code>30</code>",
  tskrate: "📈 Envie <code>plano taxa</code> (% ao mês). Ex.: <code>d30 1.2</code>",
  tskbonus: "🎁 Envie <code>plano bônus</code> (% extra ao mês). Ex.: <code>d90 0.5</code>",
  tsklock: "🔒 Envie <code>plano dias</code> de bloqueio. Ex.: <code>d60 60</code>",
  tsktoggle: "🔁 Envie <code>plano on|off</code>. Ex.: <code>d365 off</code>",
  tmallow: "➕ Envie o <b>Telegram ID</b> que poderá ver as MINAS DE TON.\nEx.: <code>8118569391</code>",
  tmdeny: "➖ Envie o <b>Telegram ID</b> que perderá o acesso às MINAS DE TON.",
  rlcost: "🎡 Envie o <b>custo do giro em TON</b>.\nEx.: <code>5</code>",
  rlcel: "👑 Envie a <b>meta global do Celestial</b> em TON.\nEx.: <code>300</code>",
  rlres: "🪙 Envie a <b>reserva de MYTH</b> disponível para a roleta.\nEx.: <code>1000000</code>",
  rlwm: "⚖️ Envie 3 pesos: <b>MÍTICO NFT CELESTIAL</b>.\nEx.: <code>55 35 10</code>",
  rlwn: "⚖️ Envie 2 pesos: <b>MYTH EQUIP</b>.\nEx.: <code>70 30</code>",
  rlw: "✏️ Envie <code>chave peso</code>.\nEx.: <code>cel-aetherion 2</code>",
  rlq: "✏️ Envie <code>chave quantidade</code>.\nEx.: <code>myth_small 5000</code>",
  rlref: "✏️ Envie <code>chave custo_ton</code>.\nEx.: <code>mx_aurenya 20</code>",
  rle: "🔁 Envie <code>chave on|off</code>.\nEx.: <code>cel-aetherion off</code>",

  fhfc: "🐾 Envie o <b>custo em FC</b> por caçada.\nEx.: <code>100000</code>",
  fhton: "🐾 Envie o <b>custo em TON</b> por caçada.\nEx.: <code>5</code>",
  fhdiff:
    "🐾 Envie o JSON de <b>dificuldade</b>.\nEx.: <code>{\"hp_base\":9000,\"hp_growth\":1.18,\"atk_base\":700,\"atk_growth\":1.15,\"boss_every\":5,\"boss_mult\":1.8}</code>",
  fhfcloot:
    "🐾 Envie o JSON da <b>loot table FC</b> (sem moedas — só itens).\nEx.: <code>[{\"type\":\"pet_food\",\"code\":\"basic_food\",\"min\":1,\"max\":3,\"weight\":40}]</code>",
  fhtonloot:
    "🐾 Envie o JSON da <b>loot table TON</b> (premium).\nEx.: <code>[{\"type\":\"fc\",\"min\":50000,\"max\":150000,\"weight\":30}]</code>",
  fhpool: "🐾 Envie o JSON do <b>stage pool</b> (nomes/temas/artes dos inimigos).",

  cbfixhp:
    "❤️ Envie o <b>HP fixo</b> do Clan Boss para todas as guildas (0 = usar escala automática).\nEx.: <code>100000000</code> para 100M",
  cbperday: "👹 Envie quantos <b>chefes por dia</b> cada guilda pode enfrentar (1 a 48).\nEx.: <code>4</code>",
  cbfcpool: "🎁 Envie o <b>pool de FC</b> pago ao derrotar o Clan Boss.\nEx.: <code>1000000</code>",
  cbclan: "🏰 Envie o <b>nome ou tag</b> do clã para configurar HP e recompensa individuais.\nEx.: <code>MythBR</code>",
  cbpglobal:
    "👹 Envie o <b>LIMITE DIÁRIO PADRÃO</b> de chefes DERROTADOS por jogador (0 a 50).\nEx.: <code>4</code>\n<i>Ataques e tentativas falhas nunca consomem o limite.</i>",
  cbpreset: "🕒 Envie a <b>hora oficial do reset diário</b> em UTC (0 a 23).\nEx.: <code>0</code> para 00:00 UTC",
  cbpfc: "🎁 Envie o <b>POOL DE FC FIXO</b> pago ao derrotar cada chefe individual (0 = usar o pool do clã/template).\nEx.: <code>400000</code> para 400k FC",
  cbpsearch: "🔍 Envie o <b>Telegram ID</b>, @usuário ou ID interno do jogador para gerenciar o chefe pessoal e o limite diário.",
  cbplimit: "🎯 Envie o <b>limite individual</b> de chefes derrotados por dia deste jogador (0 a 50).\nEx.: <code>6</code>",

  gwcamp:
    "🎁 Envie o novo <b>campaign_id</b>. Ao trocar, todos os jogadores voltam a ver o popup uma única vez.\nEx.: <code>mythreon_giveaway_sep2026</code>",
  gwurl: "🎁 Envie o <b>link do grupo</b> do Telegram.\nEx.: <code>https://t.me/+sy4Y6cd7cuIyNmEx</code>",
  xeads: "🗺 Envie o máximo de <b>ANÚNCIOS por missão por dia</b> (padrão <code>5</code>).",
  xefc: "🗺 Envie o máximo de <b>COMPRAS COM FC por missão por dia</b> (padrão <code>5</code>).",
  xefree: "🗺 Envie quantas <b>tentativas gratuitas por missão por dia</b> cada jogador recebe.\nEx.: <code>1</code>",
  xeprice: "🗺 Envie <code>raridade preço_fc</code> da tentativa extra.\nEx.: <code>epic 100000</code>",
  fgper: "🧩 Envie quantos FRAGMENTOS valem 1 herói aleatório.\nEx.: <code>5</code>",
  fgrates: "🧩 Envie <code>common uncommon</code> em % para o resgate.\nEx.: <code>70 30</code>",
  fgfusion: "🧩 Envie quantos FRAGMENTOS UNIVERSAIS substituem as cópias em 1 etapa de FUSE.\nEx.: <code>25</code>",
  nmreward: "#️⃣ Envie a <b>recompensa em FC</b> da missão #Mythreon.\nEx.: <code>50000</code>",
  nmtag: "#️⃣ Envie a <b>hashtag</b> exigida no nome do Telegram.\nEx.: <code>#Mythreon</code>",
  nmuser: "#️⃣ Envie o <b>Telegram ID</b>, @usuário ou nome do jogador para consultar o nome atual no Telegram.",
  hmrate:
    "⛏ Envie <code>raridade ton_por_dia</code> para alterar a taxa de mineração.\nEx.: <code>legendary 0.09</code>",
  depmin: "💠 Envie o valor mínimo do DEPÓSITO DIRETO DE TON (vai para o saldo TON sacável).\nEx.: <code>0.1</code>",
  hmmin:
    "⛏ Envie o valor mínimo de resgate da mineração em TON (<code>0</code> libera qualquer valor).\nEx.: <code>0.01</code>",
  hmdaily:
    "⛏ Envie o valor do <b>DAILY MINING</b> na moeda ativa.\nSe a moeda for MYTH: <code>500</code> · se for TON: <code>0.20</code>\n<i>Nenhuma conversão automática é feita — o valor informado é o valor usado.</i>",
  hmminmyth:
    "🪙 Envie o valor mínimo de resgate da mineração em MYTH (<code>0</code> libera qualquer valor).\nEx.: <code>100</code>",
  hmpool:
    "🪙 Envie a <b>alocação total</b> da MYTH MINING POOL. Ex.: <code>5000000</code>\n<i>Não pode passar do supply total nem ficar abaixo do já distribuído.</i>",
  rmbudget:
    "🎯 Envie o <b>GLOBAL DAILY BUDGET</b> de MYTH para os Heróis Raros. Ex.: <code>10000</code>\n<i>Esse é o teto total emitido por dia, não importa quantos raros existam.</i>",
  rmcap:
    "🛡 Envie o <b>PLAYER DAILY CAP</b> em MYTH (segunda proteção por jogador). Ex.: <code>100</code>",
  rmmin: "🪙 Envie o resgate mínimo do RARE MINING em MYTH. Ex.: <code>10</code>",
  rmtier:
    "📉 Envie <code>tier porcentagem</code> do peso.\n1 = raros 1–20 · 2 = 21–50 · 3 = 51–100 · 4 = 101+\nEx.: <code>2 25</code>",
  rmpool:
    "➕ Envie quanto MYTH <b>adicionar</b> à reserva de mineração. Ex.: <code>1000000</code>\n<i>Sai do supply oficial já existente — nada é criado.</i>",

  afsearch: "🛡 Envie o <b>Telegram ID</b>, @usuário ou nome do jogador para consultar dispositivos.",
  afunblock: "🛡 Envie o <b>Telegram ID</b> (ou o identificador do dispositivo) que deve ser desbloqueado.",
  afallow: "🛡 Envie o <b>Telegram ID</b> (ou identificador do dispositivo) para colocar na allowlist.",
  aflimit: "🛡 Envie o número máximo de contas por dispositivo (padrão <code>3</code>).",
  hmuser: "⛏ Envie o <b>Telegram ID</b>, @usuário ou nome do jogador para ver a mineração dele.",
  mythadd:
    "🪙 Envie <code>ID_ou_@usuario quantidade</code> para ADICIONAR MYTH ao jogador (sai da reserva do Admin Bot).\nEx.: <code>5925045925 1000</code>",
  mythsub:
    "🪙 Envie <code>ID_ou_@usuario quantidade</code> para REMOVER MYTH do jogador (volta para a reserva).\nEx.: <code>5925045925 500</code>",
  mythsee: "🪙 Envie o <b>Telegram ID</b>, @usuário ou nome para ver o saldo MYTH.",
  vvprice: "⚔️ Envie o novo <b>preço</b> do Veteran Vault em TON. Ex.: <code>50</code>",
  v2price: "⚔️ Envie o <b>preço</b> do Veteran Vault em TON. Ex.: <code>100</code>",
  pofprice: "💎 Envie o novo <b>preço do Founder Pack</b> em TON. Ex.: <code>35</code>",
  pofmyth: "🪙 Envie a quantidade de <b>MYTH</b> entregue no Founder Pack. Ex.: <code>300000</code>",
  pofheromyth: "⛏ Envie a mineração diária de <b>MYTH do herói Founder</b>. Ex.: <code>10000</code>",
  pofpetmyth: "⛏ Envie a mineração diária de <b>MYTH do pet Founder</b>. Ex.: <code>5000</code>",
  pofchests: "🗝 Envie a quantidade de <b>Baús Lendários</b> do Founder Pack. Ex.: <code>3</code>",
  pofweapon: "🗡 Envie o <b>código da arma Founder</b>. Ex.: <code>founder-warblade</code>",
  pofend: "📅 Envie a <b>data de término</b> da oferta Founder (ISO) ou <code>0</code> para sem prazo.",
  pofpool: "⛏ Envie quanto <b>MYTH</b> adicionar ao fundo de mineração do Founder Pack.",
  povprice: "💎 Envie o novo <b>preço do Veteran Vault</b> em TON. Ex.: <code>100</code>",
  povboost: "🚀 Envie o <b>bônus de MYTH</b> do Veteran Vault em %. Ex.: <code>10</code>",
  povend: "📅 Envie a <b>data de término</b> da oferta Veteran (ISO) ou <code>0</code> para sem prazo.",
  povpool: "⛏ Envie quanto <b>MYTH</b> adicionar ao fundo de mineração do Veteran Vault.",
  muton: "🪙 Envie quantos <b>MYTH</b> equivalem a 1 TON. Ex.: <code>20000</code>",
  mufc: "💰 Envie quantos <b>FC</b> equivalem a 1 TON. Ex.: <code>100000</code>",
  mudisc: "🎯 Envie o <b>desconto</b> ao pagar em MYTH, em %. Ex.: <code>8</code>",
  mucustom:
    "🔧 Envie o <b>preço fixo em MYTH</b> desta funcionalidade, ou <code>0</code> para voltar ao cálculo automático.",
  potz: "🕒 Envie o <b>fuso horário</b> do reset diário dos popups. Ex.: <code>America/Sao_Paulo</code>",
  v2version: "⚔️ Envie a <b>versão</b> do pacote. Ex.: <code>VETERAN_VAULT_V2</code>",
  v2myth: "🪙 Envie o <b>MYTH entregue na compra</b>. Ex.: <code>1000000</code>",
  v2boost: "🚀 Envie o <b>bônus de mineração MYTH</b> do comprador em %. Ex.: <code>10</code>",
  v2heromyth: "🦸 Envie a mineração diária em MYTH do herói Veteran. Ex.: <code>10000</code>",
  v2petmyth: "🐾 Envie a mineração diária em MYTH do pet Veteran. Ex.: <code>5000</code>",
  v2dragonmyth: "🐉 Envie a mineração diária em MYTH do dragão Veteran. Ex.: <code>20000</code>",
  v2weapons: "⚔️ Envie quantas <b>armas Veteran</b> cada compra entrega. Ex.: <code>2</code>",
  v2chests: "🎁 Envie a quantidade de <b>baús lendários</b>. Ex.: <code>5</code>",
  v2frag: "💎 Envie a quantidade de <b>fragmentos universais</b>. Ex.: <code>200</code>",
  v2reference: "🎯 Envie a referência <b>MYTH por TON</b>. Ex.: <code>40000</code>",
  v2freq:
    "🔁 Envie a frequência do popup: <code>ONCE_PER_SESSION</code>, <code>ONCE_PER_DAY</code>, <code>UNTIL_PURCHASED</code> ou <code>DISABLED</code>",
  vvage: "⚔️ Envie a <b>idade mínima da conta</b> em dias para ser veterano. Ex.: <code>7</code>",
  vvcycle: "⚔️ Envie a <b>duração do ciclo</b> em dias. Ex.: <code>45</code>",
  vvversion: "⚔️ Envie a nova <b>versão</b> da campanha (reinicia elegibilidade). Ex.: <code>VETERAN_V2</code>",
  vvmyth: "⚔️ Envie o <b>MYTH inicial</b> entregue na compra. Ex.: <code>150000</code>",
  vvhero: "⚔️ Envie o <code>hero_key</code> do herói exclusivo do Vault.",
  vvpet: "⚔️ Envie o <code>slug</code> do pet do Vault.",
  vvchest: "⚔️ Envie o <b>código do baú de equipamento</b>. Ex.: <code>legendary_chest</code>",
  vvfrag: "⚔️ Envie a quantidade de <b>fragmentos universais</b>. Ex.: <code>200</code>",
  vvchests: "⚔️ Envie a quantidade de <b>baús premium</b> entregues. Ex.: <code>2</code>",
  vvmaxton: "⚔️ Envie o <b>TON real máximo</b> por Vault (reserva por venda). Ex.: <code>9</code>",
  vvdailymyth: "⚔️ Envie o <b>MYTH diário</b> do ciclo. Ex.: <code>2000</code>",
  vvschedule:
    '⚔️ Envie o <b>cronograma</b> em JSON. Ex.: <code>{"ton":{"7":1,"14":1,"21":1.5,"30":2,"37":1.5,"45":2},"mythBonus":{"7":5000,"45":15000}}</code>',
  vvfinal:
    '⚔️ Envie a <b>recompensa final</b> em JSON. Ex.: <code>{"myth":25000,"fragments":100,"chest":"premium_resource_chest","chestQty":1,"badge":"veteran_badge_ii"}</code>',
  vvtarget: "⚔️ Envie o <b>valor de referência alvo</b> em TON. Ex.: <code>50</code>",
  vvfundton: "⚔️ Envie o valor de <b>TON</b> para financiar o Veteran Pool (negativo retira). Ex.: <code>100</code>",
  vvfundmyth: "⚔️ Envie o valor de <b>MYTH</b> para reservar no Veteran Pool. Ex.: <code>2000000</code>",
  fpprice: "👑 Envie o novo <b>preço</b> do Founder Pack em TON. Ex.: <code>25</code>",
  fpdays: "👑 Envie a <b>janela de elegibilidade</b> em dias (contas novas). Ex.: <code>7</code>",
  fpmyth: "👑 Envie a quantidade de <b>MYTH</b> entregue no pacote. Ex.: <code>100000</code>",
  fpfrag: "👑 Envie a quantidade de <b>fragmentos universais</b> do pacote. Ex.: <code>50</code>",
  fphero: "👑 Envie a <b>hero_key</b> do herói exclusivo entregue no pacote.",
  fppet: "👑 Envie o <b>slug</b> do pet mítico entregue no pacote.",
  fpchest: "👑 Envie o <b>código do baú</b> de equipamento (ex.: <code>legendary_chest</code>).",
  fpresource:
    '👑 Envie o conteúdo do <b>Baú Premium</b> em JSON.\nEx.: <code>{"fc":250000,"fragments":25,"pvp_tickets":10,"hero_chest":"epic_chest","hero_chest_qty":1}</code>',
  mythsupply:
    "🪙 Envie o novo <b>supply total</b> de MYTH. Ex.: <code>100000000</code>\n<i>Não pode ficar abaixo do total já distribuído.</i>",
  mythname: "🪙 Envie <code>Nome | SIMBOLO</code> para renomear o token.\nEx.: <code>MYTH Token | MYTH</code>",
  stkmin: "🔒 Envie o <b>stake mínimo</b> em MYTH. Ex.: <code>1000</code>",
  stkmax: "🔒 Envie o <b>stake máximo</b> por jogador em MYTH (<code>0</code> = sem limite). Ex.: <code>5000000</code>",
  stkpool:
    "🪙 Envie o <b>REWARD POOL</b> total do staking em MYTH.\nEx.: <code>5000000</code>\n<i>Toda recompensa sai desse pool — nada é criado do nada.</i>",
  stkapr:
    "📈 Envie <code>plano APR</code> para definir o APR anual do plano.\nPlanos: <code>flexible</code>, <code>d7</code>, <code>d30</code>, <code>d90</code>, <code>d180</code>\nEx.: <code>d30 18</code>",
  msprice: "💱 Envie quantos MYTH valem <b>1 TON</b>. Ex.: <code>20000</code>",
  msalloc:
    "🧮 Envie a <b>alocação total</b> da venda em MYTH. Ex.: <code>100000000</code>\n<i>Não pode ficar abaixo de vendido + queimado.</i>",
  msmin: "📉 Envie a <b>compra mínima</b> em MYTH. Ex.: <code>1000</code>",
  msminutes: "⏱ Envie a validade do checkout TonConnect em <b>minutos</b> (mín. 5). Ex.: <code>15</code>",
  msburn:
    "🔥 Envie <code>quantidade | motivo</code> para QUEIMAR MYTH do supply.\nEx.: <code>1000000 | queima de lançamento</code>",
  hmlimit:
    "⛏ Envie <code>ID_ou_@usuario limite_ton</code> para ajustar manualmente o LIMITE de mineração (ROI) do jogador.\nEx.: <code>5925045925 5</code> · use <code>0</code> para desativar a mineração dele.",
  nfthgive:
    "⚔️ Envie <code>ID_ou_@usuario</code> para escolher o herói NFT que será entregue.\nEx.: <code>8118569391</code>",
  nfthsearch:
    "🔎 Envie o nome do herói NFT, o <b>serial/instância</b> (<code>NFT-HERO-KAELION-0001</code>), o nome do dono ou o Telegram ID.",
  nfthmint: "⚔️ Envie <code>hero_key quantidade</code> para criar novas unidades.\nEx.: <code>kaelion 3</code>",
  nfthstat: "⚙️ Envie o <b>novo valor</b> numérico do atributo escolhido.",
  nprcset:
    "💰 Envie o <b>novo valor</b>.\nPreço/rendimento TON: ex. <code>50</code> ou <code>1.25</code>. Rendimento MYTH: ex. <code>100</code>.\n\n⚠️ Vale <b>SOMENTE para as unidades ainda na loja</b> — unidades já vendidas mantêm o rendimento congelado.",
  nprcmyth:
    "🪙 Envie o <b>rendimento diário em MYTH</b> das unidades ainda em loja.\nEx.: <code>100</code>\n\n⚠️ NFTs já vendidos NÃO são alterados (rendimento congelado).",
  hpset:
    "🎚 Envie o <b>novo valor inteiro</b>.\nEx.: XP por evento <code>40</code> · cap diário <code>800</code> · nível máximo <code>20</code>.",
  hpcurve:
    "📈 Envie <code>nível|xp</code> para redefinir a curva.\nEx.: <code>5|1200</code> = subir do Lv. 5 para o Lv. 6 exige 1.200 XP.",
  hpquest:
    "🎯 Envie <code>código_da_missão|on</code> ou <code>código_da_missão|off</code>.\nEx.: <code>daily_pvp|on</code>.",
  nprcforce:
    "☢️ <b>AÇÃO PERIGOSA — APLICAR EM NFTS EXISTENTES</b>\nIsto altera o rendimento de unidades JÁ VENDIDAS.\n\nEnvie <code>valor|motivo|CONFIRMAR</code>\nEx.: <code>0.5|correcao de erro de mint|CONFIRMAR</code>",

  neqnew:
    "⚔️ Envie <code>slot|nome|classe|atk|def|hp|preco_ton|url_imagem</code>.\nSlot: <code>weapon</code>, <code>armor</code> ou <code>ring</code>. Classe é obrigatória para armas (<code>warrior/archer/tank/mage</code>), use <code>-</code> nos demais.\nEx.: <code>weapon|Nightfall Edge|assassin|330|40|200|18|/assets/game/equipment/nft/nightfall.png</code>",
  nftgive:
    "💎 Envie <code>ID_ou_@usuario</code> para escolher a unidade NFT que será entregue.\nEx.: <code>8118569391</code>",

  nftsearch:
    "🔎 Envie o nome do pet NFT, o <b>serial/instância</b> (<code>NFT-IGNARION-0001</code>), o nome do dono ou o Telegram ID.",
  npfund: "💎 Envie o valor em <b>TON</b> para <b>aportar</b> no NFT Reward Pool.\nEx.: <code>50</code>",
  npadjust: "⚙️ Envie o ajuste em <b>TON</b> (use <code>-</code> para debitar).\nEx.: <code>-10</code>",
  nptier: "💠 Envie <code>serial tier_ton</code> para alterar o tier da unidade.\nEx.: <code>3 30</code>",
  npcfg20: "💠 Envie o novo rendimento diário do tier 20 TON. Ex.: <code>0.5</code>",
  npcfg30: "💠 Envie o novo rendimento diário do tier 30 TON. Ex.: <code>0.8</code>",
  npcfgmin: "💠 Envie o valor mínimo de resgate em TON. Ex.: <code>0.01</code>",
  nftmint: "💎 Envie <code>slug quantidade</code> para criar novas unidades.\nEx.: <code>ignarion 3</code>",
  ptname: "🤝 Envie o <b>nome</b> do parceiro (é o único texto que o jogador vê).\nEx.: <code>MYTHREON NEWS</code>",
  ptreward: "🪙 Envie a <b>recompensa em FC</b> paga uma única vez por jogador.\nEx.: <code>500</code>",
  pturl: "🔗 <b>Envie o link do parceiro/canal</b>\nEx.: <code>https://t.me/seucanal</code>",
  ptchat: "🆔 Envie o <b>CHAT ID</b> do canal/grupo (não é o link).\nEx.: <code>-1001234567890</code>",
  ptsetchat: "🆔 Envie o <b>CHAT ID</b> usado só para validar a entrada.\nEx.: <code>-1001234567890</code>",
  ptrename: "🏷 Envie o <b>novo nome</b> do parceiro.",
  ptsetreward: "🪙 Envie a <b>nova recompensa em FC</b>.",
  ptsetlink: "🔗 Envie o <b>novo link</b> (https://...).",
  ptsort: "🔢 Envie a <b>ordem</b> de exibição (1 = primeiro).",
  wlhot:
    "🔥 Envie o <b>endereço da hot wallet</b> TON que recebe os depósitos.\nEx.: <code>UQDqQU5ph38I7DKYi_cERlg30ehK9MO9msHHc56EJgUJXvrD</code>",
  wlmin: "⬇️ Envie o <b>saque mínimo em TON</b>.\nEx.: <code>1</code>",
  spname: "💰 Envie o <b>nome</b> do novo evento de gastos.\nEx.: <code>SPENDING EVENT</code>",
  spdays: "📅 Envie a <b>duração em dias</b> (1 a 90).\nEx.: <code>7</code>",
  spreward:
    "🎁 Envie a recompensa no formato <code>posição|texto</code> ou <code>de-até|texto</code>.\nEx.: <code>1|Ancestral Egg + Exclusive Hero</code>\nEx.: <code>11-12|Rare Chest + 20 Universal Fragments</code>",
  spratet: "💎 Envie quantos <b>pontos por 1 TON</b>.\nEx.: <code>100000</code>",
  spratef: "🪙 Envie quantos <b>pontos por 1 FC gasto</b>.\nEx.: <code>1</code>",
  mksearch: "🔍 Envie o nome do item ou o <b>ID do anúncio</b>.",
  mkuser: "👤 Envie Telegram ID, @usuário, nome, carteira ou ID interno para ver os anúncios do jogador.",
  mkfee: "💸 Envie a nova taxa do mercado em % (0 a 50).\nEx.: <code>5</code> ou <code>3</code>",
  mklimit: "🚧 Envie o novo limite de anúncios ativos por jogador (1 a 200).\nEx.: <code>20</code>",
  mkmin: "🏷 Envie: <code>hero|pet|item valor_fc</code>\nEx.: <code>hero 10000</code>",
  mkcancel: "🗑 Envie o <b>ID do anúncio</b> a cancelar. O item volta ao inventário do vendedor.",
  mktrade: "🔎 Envie o <b>código</b> da negociação (4 caracteres, ex.: <code>A1B2</code>) ou o ID completo.",
  mkhist: "🧾 Envie Telegram ID, @usuário ou nome para ver o dossiê de mercado (carteiras, indicações e pares).",
  mkrestrict:
    "⛔️ Envie <code>ID_ou_@usuario horas</code>\nEx.: <code>8118569391 24</code>\nUse <code>0</code> horas para liberar o jogador.",
  mkrange:
    "🏷 Envie <code>tipo raridade min max [recomendado]</code>\nEx.: <code>hero epic 50000 400000 120000</code>\nTipos: hero, pet, item · raridade curinga: <code>default</code>",
  mksettle: "⏳ Envie as horas de retenção do pagamento (escrow) antes de pagar o vendedor.\nEx.: <code>72</code>",
  mkreq: "👤 Envie <code>diasConta diasAtivo heróis</code> exigidos para vender.\nEx.: <code>7 3 5</code>",
  mkpair:
    "👥 Envie <code>tradesPorDia fcPorDia</code> permitidos entre o mesmo par de jogadores.\nEx.: <code>3 2000000</code>",
  mkvel: "⚡️ Envie <code>por5min por1h por24h cooldownMin</code>.\nEx.: <code>5 15 40 360</code>",
  mkdyn:
    "📊 Envie <code>min% max% minAmostras dias</code> da faixa dinâmica pela mediana.\nEx.: <code>50 200 5 30</code>",
  evcreate:
    "🎉 Novo evento especial.\nEnvie: <code>nome | prêmio TON | dias | (opcional) início YYYY-MM-DD HH:MM</code>\nEx.: <code>Referral Championship | 100 | 30</code>",

  evprize: "💎 Digite o novo prêmio total do evento em TON.\nEx.: <code>100</code>",
  evdates:
    "📅 Envie: <code>início YYYY-MM-DD HH:MM | fim YYYY-MM-DD HH:MM</code>\nou <code>início | dias</code>. Ex.: <code>2026-08-11 00:00 | 30</code>",
  evrules:
    "🛡 Envie: <code>mín_daily_quests | top_limit | fixed|proportional</code>\nEx.: <code>1 | 100 | fixed</code>",
  evdist: "🏅 Envie a tabela de prêmios (TON por posição):\n<code>1=25; 2=15; 3=10; 4-10=3; 11-50=0.5</code>",
  clcost: "Digite o novo custo para criação de um clã em FC.\nEx.: <code>50000</code>",
  clsetlimit: "Digite o novo limite de membros para clãs criados a partir de agora (2 a 500).\nEx.: <code>30</code>",
  giftuser: "Para qual jogador deseja enviar?\nEnvie <b>Telegram ID</b>, <b>@username</b>, nome ou ID interno.",
  giftfc: "Digite a quantidade de FC que deseja enviar.\nEx.: <code>50000</code>",
  giftqty: "Digite a quantidade que deseja enviar.\nEx.: <code>1</code>",
  clsearch: "Envie o nome (ou parte) ou a <b>tag</b> do clã. Ex.: <code>dragões</code> ou <code>DRG</code>",
  claaudit: "🔎 Envie <b>Telegram ID</b>, <b>@username</b> ou ID interno para auditar clãs e Clan Boss.",

  clxp: "Envie o XP a adicionar ou remover do clã. Ex.: <code>25000</code> ou <code>-5000</code>",
  cllvl: "Envie o novo nível do clã (mínimo 1). Ex.: <code>10</code>",
  clbosshp: "Envie o HP do novo ciclo do chefe do clã. Ex.: <code>2500000</code>",
  cbbasehp: "❤️ Envie o <b>HP base</b> do Abyssal Warlord (mínimo 1000).\nEx.: <code>1500000</code>",
  cbclanlvl: "📈 Envie o <b>% de HP por nível do clã</b> (0 a 200).\nEx.: <code>12</code>",
  cbmember: "👥 Envie o <b>% de HP por membro</b> (0 a 50).\nEx.: <code>4</code>",
  cbcycle: "🔁 Envie o <b>% de HP adicional por ciclo</b> (0 a 100).\nEx.: <code>8</code>",
  cbdur: "🕒 Envie a <b>duração do ciclo em horas</b> (1 a 720).\nEx.: <code>48</code>",
  cbcool: "⏱ Envie o <b>cooldown de ataque em segundos</b> (10 a 86400).\nEx.: <code>1800</code>",
  cbxp: "⭐ Envie o <b>XP de clã</b> concedido ao derrotar o chefe (0 a 100000).\nEx.: <code>5000</code>",
  cbmindmg: "🎯 Envie o <b>% mínimo de dano</b> para o membro receber recompensas (0 a 50).\nEx.: <code>1</code>",
  cbname: "🏷 Envie o <b>nome do chefe do clã</b>.\nEx.: <code>Abyssal Warlord</code>",
  cbrewards:
    '🎁 Envie as recompensas por dano em JSON.\nEx.: <code>{"fc_per_1m":2500,"universal_fragments":10,"rare_chests":1,"pvp_tickets":2}</code>',
  cbclan: "🏰 Envie o <b>nome</b> ou a <b>tag</b> do clã para gerenciar o ciclo do chefe.",
  cbbaltarget:
    "🎯 Envie a <b>duração alvo em horas</b> que cada Clan Boss deve sobreviver (1 a 48).\nEx.: <code>23.5</code>",
  cbbalcycle: "🕒 Envie o <b>tamanho do ciclo em horas</b> (1 rewarding boss por ciclo).\nEx.: <code>24</code>",
  cbbalhp: "❤️ Envie o <b>fator de HP</b> (multiplicador sobre a capacidade diária do clã).\nEx.: <code>0.80</code>",
  cbbaldef: "🛡 Envie o <b>fator de DEF</b> do boss (mitigação).\nEx.: <code>1.00</code>",
  cbbalatk: "⚔️ Envie o <b>fator de ATK</b> do boss.\nEx.: <code>1.00</code>",
  cbbaltooeasy: "⚡ Envie em <b>segundos</b> o limite de “fácil demais” (boss morto rápido).\nEx.: <code>28800</code>",
  cbbaltoohard: "🐢 Envie em <b>segundos</b> o limite de “difícil demais”.\nEx.: <code>129600</code>",
  cbbalclan: "🏰 Envie o <b>nome</b> ou a <b>tag</b> do clã para ver/recalcular o balanceamento.",

  clname: "Envie o novo nome do clã (3 a 24 caracteres).",
  cltag: "Envie a nova tag do clã (2 a 5 letras/números).",
  cldesc: "Envie a nova descrição do clã (até 200 caracteres).",
  cllimit: "Envie o novo limite de membros (1 a 500). Ex.: <code>150</code>",
  cltrophy: "Envie o mínimo de troféus para entrar no clã. Ex.: <code>500</code>",
  find: "Envie Telegram ID, @usuário, nome, carteira ou ID interno.",
  tonadj:
    "💎 <b>AJUSTAR TON</b>\n\nEnvie o <b>Telegram ID</b> do jogador.\nEx.: <code>8118569391</code>\n\n<i>Ajusta apenas o saldo TON interno/sacável do Mythreon. Não altera Hot Wallet nem carteira externa.</i>",
  pachat:
    "Envie o <b>chat id</b> do canal de pagamentos (ex.: <code>-1004303374351</code>) ou @canalpublico.\nO bot do jogo precisa ser administrador do canal com permissão de envio.",
  passuser: "Envie Telegram ID, @usuário, nome, carteira ou ID interno do jogador para gerenciar o Battle Pass.",
  channel:
    'Envie: <code>news|community|payments {json}</code>\nEx.: <code>news {"url":"https://t.me/+abc","reward_fc":5000,"enabled":true}</code>\n\nA recompensa é one-time por Telegram ID; não é necessário chat id.',
  chclaims: "Envie Telegram ID, @usuário, nome, carteira ou ID interno para ver os claims dos canais oficiais.",
  chreset:
    "⚠️ Reset manual de claim. Envie: <code>usuário channel_key CONFIRMAR</code>\nEx.: <code>8082515829 news CONFIRMAR</code>\nIsso libera o VERIFY novamente e fica registrado na auditoria.",
  hero: 'Envie: <code>hero_key {json}</code>\nEx.: <code>pyro_knight {"name":"Cavaleiro Ígneo","rarity":"epico","price_fc":50000,"in_shop":true,"sort_order":1}</code>',
  hodds:
    "Envie as 5 chances na ordem <b>comum incomum raro épico lendário</b>.\nEx.: <code>62 25 10 2.7 0.3</code>\nO total precisa fechar 100%.",
  hoddsreal:
    "Envie as 6 chances REAIS do sorteio na ordem <b>comum incomum raro épico lendário mítico</b>.\nEx.: <code>71.3 25 2 1 0.6 0.1</code>\nO total precisa fechar 100%. O jogador continua vendo as chances públicas.",
  herotoggle: "Envie o <code>hero_key</code> para ativar/desativar o herói.",
  fusion:
    'Envie o JSON da fusão (merge parcial). Ex.:\n<code>{"max_stars":5,"bonus_percent":{"1":5,"2":5,"3":7,"4":8,"5":10},"cost_fc":{"1":5000,"2":15000,"3":35000,"4":75000,"5":150000},"duplicates":{"1":5,"2":5,"3":5,"4":5,"5":5},"level_cap":{"0":20,"1":20,"2":25,"3":25,"4":30,"5":35}}</code>',
  rfcommon: "COMMON → UNCOMMON — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>10000 80 10</code>",
  rfuncommon: "UNCOMMON → RARE — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>25000 60 20</code>",
  rfrare: "RARE → EPIC — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>30000 60 40</code>",
  rfepic: "EPIC → LEGENDARY — envie: <code>custo_fc chance fragmentos</code>\nEx.: <code>150000 20 80</code>",
  rfpool: "Envie: <code>hero_key on|off</code> para incluir/excluir o herói do sorteio da Rarity Fusion.",
  rfaudit: "Envie Telegram ID, @usuário, nome, carteira ou ID interno para filtrar a auditoria de fusões.",
  rates:
    'Envie as chances em JSON (total 100). Ex.: <code>{"comum":45,"incomum":25,"raro":15,"epico":8,"lendario":5,"mitico":1.5,"ancestral":0.5}</code>',
  granthero: "Envie: <code>usuário hero_key [nível]</code>",
  pet: 'Envie: <code>slug {json}</code> — ex.: <code>pyron {"name":"Pyron","category":"fire","is_enabled":true}</code>',
  food: 'Envie: <code>code {json}</code> — ex.: <code>racao {"name":"Ração","xp_value":50,"rarity":"comum","enabled":true}</code>',
  grantpet: "Envie: <code>usuário slug [nível]</code> — a raridade vem sempre do catálogo do pet.",
  foodprice: "Envie: <code>code preço_fc</code> — ex.: <code>pet_ration 1000</code>",
  eggprice:
    "Envie: <code>slug preço_fc [preço_ton]</code> — ex.: <code>common-egg 25000</code> ou <code>epic-egg 0 3</code>",
  egg: 'Envie: <code>slug {json}</code> — ex.: <code>common-egg {"price_fc":25000,"is_purchasable":true,"rarity_rates":{"common":75,"uncommon":20,"rare":5}}</code>',
  giveitem:
    "Envie: <code>usuário tipo item quantidade</code>\nTipos: <code>ovo</code> (slug do ovo), <code>comida</code> (code), <code>fragmento</code>.\nEx.: <code>8118569391 ovo epic-egg 3</code>",
  givefrag: "Envie: <code>usuário quantidade</code> para conceder fragmentos universais.",
  pvpset:
    "Envie: <code>chave valor</code>\nChaves: pvp_trophy_win, pvp_trophy_loss, pvp_ticket_cost, pvp_ticket_start, pvp_ticket_max, pvp_ticket_regen_minutes, pvp_ticket_price_fc, pvp_win_reward_fc",
  tkfree: "Envie o novo limite diário de compra de tickets para jogadores SEM Battle Pass — ex.: <code>10</code>",
  tkpass: "Envie o novo limite diário de compra de tickets para jogadores COM Battle Pass — ex.: <code>20</code>",
  tkpack:
    "Envie: <code>quantidade preço_fc</code> — ex.: <code>3 13500</code> (use preço 0 e remova manualmente para desativar).",

  passxp:
    "Envie: <code>chave valor</code> (XP base da ação).\nEx.: <code>pvp_battle 40</code>\nChaves: daily_login, daily_quest, daily_quest_all, daily_chest, pvp_battle, pvp_victory, boss_attack, boss_damage_milestone, boss_reward, reward_open, pet_feed, pet_level_up, pet_evolution, hero_fuse, rarity_fusion, rarity_fusion_success, calendar_claim",
  passxpmult:
    "Envie: <code>free|adventurer|legendary valor</code>\nEx.: <code>legendary 1.4</code> (= +40% de XP do Battle Pass).",
  passxpcap:
    "Envie: <code>chave limite</code> — limite de XP base por game_day.\nEx.: <code>pet_feed 100</code> · <code>reward_open 150</code> · <code>pvp_battle 400</code>\nUse <code>0</code> para bloquear a fonte.",
  passlevelprice:
    "Envie: <code>1|3|5 preço</code> — preço em FC do pacote de níveis.\nEx.: <code>1 50000</code> · <code>3 135000</code> · <code>5 200000</code>",
  passlevellimit: "Envie o limite de níveis compráveis por game_day (0–30).\nEx.: <code>5</code>",
  league:
    'Envie: <code>code {json}</code> — ex.: <code>bronze_5 {"name":"Bronze V","min_trophies":0,"max_trophies":19}</code>',
  setting: "Envie: <code>chave valor</code> (valor JSON ou texto simples).",
  quest:
    'Envie: <code>code {json}</code> — ex.: <code>enter_arena {"title":"ENTER THE ARENA","description":"Complete one PvP battle.","event_key":"pvp_battle","target_amount":1,"reward_fc":4000,"icon":"pvp","sort_order":4,"enabled":true}</code>\nEventos válidos: <code>daily_login, pet_fed, boss_attack, pvp_battle, reward_opened, hero_obtained</code>.',
  questtoggle: "Envie o <code>code</code> da quest para ativar/desativar.",
  questbonus: "Envie: <code>item_code quantidade [nome]</code> — ex.: <code>rare_chest 1 Rare Chest</code>",
  questtz: "Envie o fuso do reset diário — ex.: <code>America/Sao_Paulo</code>",
  mission:
    'Envie: <code>code {json}</code> — ex.: <code>daily_pvp_wins {"title":"Vença 3 batalhas","target_amount":3,"reward_amount":4000,"enabled":true}</code>',
  boss: 'Envie: <code>code {json}</code> — ex.: <code>golem_ancestral {"name":"Golem","max_hp":50000,"attack":300,"reward_amount":9000}</code>',
  bossspawn: "Envie o <code>code</code> do chefe para ativar (ex.: <code>golem_ancestral</code>).",
  bosshpval: "Envie: <code>code hp</code> — ex.: <code>golem_ancestral 50000</code>",
  gbthp: "❤️ Envie o HP total deste chefe global — ex.: <code>2500000</code>",
  gbtrw: "🎁 Envie o prêmio total em FC deste chefe global — ex.: <code>600000</code>",
  gbtdur: "⏱ Envie a duração do ciclo em horas (1 a 168) — ex.: <code>24</code>",
  gbtname: "✏️ Envie o novo nome do chefe global.",
  gbtsub: "📖 Envie a nova lore/subtítulo do chefe global.",
  gbmulhp:
    "❤️ Envie o <b>HP MULTIPLIER</b> do Global Boss (aplicado sobre o HP-base de todos os chefes) — ex.: <code>4</code>",
  gbmuldef: "🛡 Envie o <b>DEFENSE MULTIPLIER</b> do Global Boss (aplicado sobre a defesa-base) — ex.: <code>3</code>",
  gbmulatk: "⚔️ Envie o <b>ATK MULTIPLIER</b> do Global Boss (1.25 = +25%) — ex.: <code>1.25</code>",

  bossdur: "Envie: <code>code horas</code> — ex.: <code>golem_ancestral 24</code>",
  bossreward:
    "⚙️ <b>CHANGE DEFAULT REWARD</b> (próximos ciclos)\nEnvie: <code>code recompensa_fc</code> — ex.: <code>golem_ancestral 9000</code>\n\nIsto <b>não</b> altera o ciclo ativo. Para o ciclo atual use <b>✏️ CHANGE CURRENT REWARD</b>.",
  ads: 'Envie: <code>code {json}</code> — ex.: <code>adsgram {"enabled":true,"daily_limit":15,"reward_fc":800}</code>',
  pass: 'Envie JSON com os campos do passe: <code>{"adventurer_price_ton":15,"legendary_price_ton":30,"levels":30,"xp_per_level":1000}</code>',
  passreward:
    'Envie: <code>reward_id {json}</code> — ex.: <code>uuid {"amount":5000,"title":"5.000 FC","enabled":true}</code>',
  poolset:
    "Envie: <code>chave valor</code> — minimum_points, ranking_share_percent, lottery_share_percent, ranking_winner_limit, lottery_winner_count, season_days",
  plset:
    "Envie: <code>chave valor</code> — <code>name</code>, <code>prize_pool_ton</code>, <code>duration_days</code>, <code>top_limit</code>, <code>min_matches</code>, <code>enabled</code> (ex.: <code>prize_pool_ton 40</code>). Só funciona enquanto o evento está em DRAFT.",
  plfind: "Envie o telegram_id, @username ou nome do jogador para ver a posição dele no evento.",
  tpset:
    "Envie: <code>chave valor</code> — <code>turnTimerSeconds</code>, <code>ticketCost</code>, <code>reconnectSeconds</code>, <code>stalemateTurns</code>, <code>stalemateEscalation</code>, <code>ratingK</code>, <code>deckSize</code>, <code>tournamentEnabled</code>, <code>eventMode</code> (ex.: <code>turnTimerSeconds 20</code>).",
  tpskill:
    "Envie: <code>skill_key campo valor</code> — campos: <code>multiplier</code>, <code>cooldown</code>, <code>duration</code>, <code>enabled</code> (ex.: <code>heavy_strike multiplier 1.6</code> ou <code>silence enabled 0</code>).",
  cwset:
    "Envie: <code>chave valor</code> — <code>rosterSize</code>, <code>attacksPerPlayer</code>, <code>preparationHours</code>, <code>battleHours</code>, <code>seasonWeeks</code>, <code>baseRating</code>, <code>pointsWin</code>, <code>pointsPerfect</code>, <code>pointsUpsetMax</code>, <code>pointsLoss</code>, <code>defenderMaxDefeats</code>, <code>conqueredPercent</code>, <code>sectorBonusPercent</code>, <code>matchmaking</code>, <code>tonSeasonPrize</code> (ex.: <code>battleHours 24</code>).",
  cwseason:
    "Envie: <code>nome | prêmio_ton</code> para abrir uma nova temporada — ex.: <code>Temporada 1 | 40</code>. Sem prêmio use <code>Temporada 1 | 0</code>.",
  poolrate:
    "Envie a nova taxa de contribuição da Community Pool em % (0-100) — ex.: <code>15</code>. Vale apenas para transações TON processadas após a alteração.",

  tree: "Envie o usuário para ver a árvore de convites.",
  unlink: "Envie: <code>usuário motivo</code> para remover o vínculo de indicação.",
  depok: "Envie o ID do depósito (pode ser o prefixo mostrado).",
  depno: "Envie o ID do depósito a rejeitar.",
  wdpaid: "Envie o ID do saque (prefixo aceito) para abrir os detalhes e pagar.",
  wdno: "Envie o ID do saque para abrir os detalhes e rejeitar.",
  findwallet: "Pesquise a carteira por Telegram ID, @usuário, nome, endereço TON ou ID interno.",

  tonrate:
    "Envie a nova taxa: quantos FC vale 1 TON (ex.: <code>100000</code>). Vale apenas para depósitos confirmados depois da alteração.",
  wdfee:
    "Envie a nova <b>WITHDRAWAL FEE</b> em % (0 a 50). Ex.: <code>10</code>. Vale só para saques criados depois da alteração.",
  auditdep: "Envie o Telegram ID (ou @usuário) para auditar os depósitos.",
  maintmsg: "Envie a nova mensagem de manutenção.",
  mptotal: "💰 Envie o novo <b>TOTAL POOL</b> em TON — ex.: <code>700</code> ou <code>1000,5</code>.",
  mpadd:
    "➕ <b>ADD EXPENSE</b>\nEnvie: <code>CATEGORIA | descrição | valor | data | nota</code>\nEx.: <code>MARKETING | Telegram Ads | 120 | 16/08/2026 | Campanha de onboarding</code>\nData e nota são opcionais (use <code>-</code> para vazio).\nCategorias: MARKETING, DEVELOPMENT, INFLUENCERS, DESIGN, COMMUNITY, MODERATION, SERVER, OTHER.",
  mpedit:
    "✏️ <b>EDIT EXPENSE</b>\nEnvie: <code>ID | CATEGORIA | descrição | valor | data | nota</code>\nUse <code>-</code> em qualquer campo que deve permanecer igual.\nEx.: <code>3f2a9c | - | Telegram Ads Q3 | 150 | - | -</code>",
  mpdel: "🗑 Envie o <b>ID do lançamento</b> (ou os primeiros caracteres) para remover.",
  prsearch:
    "🔎 Pesquise o pagamento por <b>Telegram ID</b>, <b>@usuário</b>, nome, <b>ID do pedido</b> (prefixo aceito) ou <b>hash da transação</b>.",
};

// ---------------------------------------------------------------- global boss panel
/** Every list coming from the database is normalized before rendering — the panel must open even with no active cycle. */
const arr = <T,>(value: unknown): T[] => (Array.isArray(value) ? (value as T[]) : []);

/** Difficulty block shown in every Global Boss screen — base stats are never mutated, only the multipliers. */
function difficultyLines(diff: any, extra?: any): string[] {
  const x = (v: unknown, d = 2) =>
    Number(v ?? 0)
      .toFixed(d)
      .replace(/\.0+$/, "");
  return [
    "<b>⚙️ DIFICULDADE OFICIAL</b>",
    `HP MULTIPLIER: <b>${x(diff?.hpMultiplier)}x</b> · DEFENSE: <b>${x(diff?.defenseMultiplier)}x</b> · ATK: <b>${x(diff?.atkMultiplier)}x</b>`,
    ...(extra
      ? [
          `Boss atual: DEF <b>${fmt(extra.defense)}</b> (−${((1 - Number(extra.damageFactor ?? 1)) * 100).toFixed(1)}% de dano recebido) · ATK <b>${fmt(extra.attack)}</b>`,
        ]
      : []),
  ];
}

async function bossDifficulty(ctx: Ctx) {
  return (await rpc("admin_global_boss_difficulty", { p_admin_id: ctx.adminId })) as any;
}

async function bossPanel(ctx: Ctx, editing = true) {
  const d = (await rpc("admin_boss_overview", { p_admin_id: ctx.adminId })) as any;
  const diffData = await bossDifficulty(ctx);
  const diff = diffData?.difficulty ?? null;
  const cycle = d?.cycle ?? null;
  const template = d?.template ?? null;
  const templates = arr<any>(d?.templates);
  const top = arr<any>(d?.top);
  console.log(
    "[ADMIN BOSS]",
    JSON.stringify({
      hasCycle: Boolean(cycle),
      status: cycle?.status ?? null,
      templates: templates.length,
      ranking: top.length,
      templateActive: d?.templateActive ?? null,
    }),
  );

  const when = (v: unknown) =>
    v ? esc(new Date(String(v)).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })) : "—";
  const list =
    templates
      .map(
        (t) =>
          `• <code>${esc(t.code)}</code> ${esc(t.name)} NV${t.level ?? 1} — ${fmt(t.maxHp)} HP ${t.active ? "🟢" : "⚪"}`,
      )
      .join("\n") || "—";
  const rank =
    top
      .map(
        (t) =>
          `#${t.rank} ${esc(t.name)} — ${fmt(Math.round(Number(t.damage ?? 0)))} (${Number(t.sharePercent ?? 0).toFixed(2)}%)`,
      )
      .join("\n") || "—";
  const multiplierRows = [
    [{ t: "❤️ SET HP MULTIPLIER", d: "ask:gbmulhp" }],
    [
      { t: "🛡 SET DEF MULTIPLIER", d: "ask:gbmuldef" },
      { t: "⚔️ SET ATK MULTIPLIER", d: "ask:gbmulatk" },
    ],
    [{ t: "♻️ RESTART ROTATION", d: "gbrot:ask" }],
  ];

  if (!cycle) {
    return (editing ? edit : send)(
      ctx,
      [
        "👹 <b>GLOBAL BOSS</b>",
        "Status: 🔴 <b>NO ACTIVE BOSS</b>",
        "",
        ...difficultyLines(diff),
        "",
        `Modelo padrão: <b>${template ? esc(template.name) : "—"}</b>${template ? ` — ${fmt(template.maxHp)} HP · ${fmt(template.reward)} FC` : ""}`,
        "",
        `<b>Chefes cadastrados</b>\n${list}`,
      ].join("\n"),
      kb([
        [{ t: "🗺 ROSTER GLOBAL (20)", d: "boss:roster:0" }],
        [{ t: "🟢 ATIVAR BOSS", d: "ask:bossspawn" }],
        ...multiplierRows,
        [{ t: "✏️ CRIAR/EDITAR BOSS", d: "ask:boss" }],
        [{ t: "❤️ HP PADRÃO", d: "ask:bosshpval" }],
        [{ t: "⚙️ CHANGE DEFAULT REWARD", d: "ask:bossreward" }],
        [{ t: "⏱ DURAÇÃO", d: "ask:bossdur" }],
        nav(),
      ]),
    );
  }

  const text = [
    "👹 <b>GLOBAL BOSS</b>",
    `Boss: <b>${esc(cycle.name)}</b> · ciclo #${cycle.cycleNumber ?? 1}${diffData?.cycle?.bossNumber ? ` · boss ${diffData.cycle.bossNumber}/${diffData?.bossCount ?? 20}` : ""}`,
    `Status: ${cycle.status === "active" ? "🟢 ACTIVE" : `⚪ ${esc(String(cycle.status || "").toUpperCase())}`}`,
    `HP: <b>${fmt(Math.round(Number(cycle.currentHp ?? 0)))}</b> / ${fmt(cycle.maxHp)}`,
    `🎁 <b>CURRENT REWARD:</b> <b>${fmt(cycle.rewardPoolFc)} FC</b>${cycle.distributedAt ? " (distribuído)" : ""}`,
    `⚙️ Prêmio padrão do boss: ${template ? `${fmt(template.reward)} FC` : "—"}`,
    `👥 Participantes: ${fmt(cycle.participants ?? 0)} · Dano total: ${fmt(Math.round(Number(cycle.totalDamage ?? 0)))}`,
    `Dano mínimo: ${Number(cycle.minimumDamagePercent ?? 0)}% · bônus de pódio: ${cycle.rankBonusEnabled ? "ON" : "off"}`,
    `Início: ${when(cycle.startsAt)}\nFim: ${when(cycle.endsAt)}`,
    "",
    ...difficultyLines(diff, diffData?.cycle),
    "",
    `<b>Top dano</b>\n${rank}`,
    "",
    `<b>Chefes cadastrados</b>\n${list}`,
  ].join("\n");

  return (editing ? edit : send)(
    ctx,
    text,
    kb([
      [{ t: "🗺 ROSTER GLOBAL (20)", d: "boss:roster:0" }],
      [
        { t: "🏆 VER RANKING", d: "boss:rank" },
        { t: "🔴 ENCERRAR", d: "confirm:bossend" },
      ],
      ...multiplierRows,
      [{ t: "✏️ CHANGE CURRENT REWARD", d: "boss:curreward" }],
      [{ t: "⚙️ CHANGE DEFAULT REWARD", d: "ask:bossreward" }],
      [{ t: "❤️ ALTERAR HP", d: "ask:bosshpval" }],
      [
        { t: "⏱ DURAÇÃO", d: "ask:bossdur" },
        { t: "👹 TROCAR BOSS", d: "ask:bossspawn" },
      ],
      [
        { t: "✏️ CRIAR/EDITAR BOSS", d: "ask:boss" },
        { t: "🔄 ATUALIZAR", d: "m:boss" },
      ],
      nav(),
    ]),
  );
}

/** RESTART ROTATION: confirmation card + execution. History, rankings and payouts are preserved. */
async function bossRotationFlow(ctx: Ctx, step: string) {
  const d = await bossDifficulty(ctx);
  const diff = d?.difficulty ?? null;
  const count = d?.bossCount ?? 20;
  if (step !== "go") {
    return send(
      ctx,
      [
        "⚠️ <b>RESTART GLOBAL BOSS ROTATION?</b>",
        "",
        `Current: <b>Boss ${d?.cycle?.bossNumber ?? "—"}/${count}</b>`,
        `New: <b>Boss 1/${count}</b>`,
        "",
        `HP Multiplier: <b>${Number(diff?.hpMultiplier ?? 0)}x</b>`,
        `Defense Multiplier: <b>${Number(diff?.defenseMultiplier ?? 0)}x</b>`,
        `Attack Multiplier: <b>${Number(diff?.atkMultiplier ?? 0)}x</b>`,
        "",
        "Previous history and rewards will be preserved.",
      ].join("\n"),
      kb([
        [
          { t: "✅ CONFIRM", d: "gbrot:go" },
          { t: "❌ CANCEL", d: "m:boss" },
        ],
      ]),
    );
  }
  const r = (await rpc("admin_global_boss_restart_rotation", {
    p_admin_id: ctx.adminId,
    p_reason: "restart de rotação pelo admin",
  })) as any;
  return send(
    ctx,
    [
      "✅ <b>NOVA ROTAÇÃO INICIADA</b>",
      `Ciclo: <code>${esc(r.newCycleId)}</code> (#${r.cycleNumber} · rotação ${r.rotationNumber})`,
      `👹 Boss <b>${r.bossNumber}/${count} — ${esc(r.name)}</b>`,
      `❤️ HP efetivo: <b>${fmt(r.maxHp)}</b>`,
      `🛡 Defesa efetiva: <b>${fmt(r.defense)}</b>`,
      `⚔️ ATK efetivo: <b>${fmt(r.attack)}</b>`,
      `🎁 Prêmio: ${fmt(r.rewardPoolFc)} FC`,
    ].join("\n"),
    kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
  );
}

/** Multiplier setter — always applied over BASE stats, never cumulative. */
async function bossSetMultiplier(ctx: Ctx, kind: string, raw: string) {
  const value = Number(String(raw).replace(",", ".").trim());
  if (!Number.isFinite(value) || value < 0.1 || value > 100) {
    return send(
      ctx,
      "⚠️ Valor inválido. Envie um multiplicador entre <code>0.1</code> e <code>100</code>. Ex.: <code>4</code>",
      kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
    );
  }
  const r = (await rpc("admin_global_boss_multiplier", {
    p_admin_id: ctx.adminId,
    p_kind: kind,
    p_value: value,
    p_reason: `multiplicador ${kind} = ${value}`,
  })) as any;
  const label = kind === "hp" ? "HP" : kind === "def" ? "DEFENSE" : "ATK";
  return send(
    ctx,
    [
      `✅ <b>${label} MULTIPLIER = ${value}x</b>`,
      `Antes: ${r.oldValue ?? "—"}x`,
      r.cycle
        ? `\nBoss atual: <b>${esc(r.cycle.name)}</b>\n❤️ ${fmt(r.cycle.currentHp)} / ${fmt(r.cycle.maxHp)}\n🛡 DEF ${fmt(r.cycle.defense)} · ⚔️ ATK ${fmt(r.cycle.attack)}`
        : "\nNenhum ciclo ativo — vale para o próximo boss.",
      "\nOs multiplicadores sempre partem do valor-base (nunca acumulam entre ciclos).",
    ].join("\n"),
    kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
  );
}

// ---------------------------------------------------------------- global boss roster (20 bosses)
/** Lists every Global Boss template so each one can be toggled/edited without spawning it first. */
async function bossRoster(ctx: Ctx, page = 0) {
  const d = (await rpc("admin_global_boss_roster", { p_admin_id: ctx.adminId })) as any;
  const bosses = arr<any>(d?.bosses);
  const perPage = 10;
  const slice = bosses.slice(page * perPage, page * perPage + perPage);
  const body =
    slice
      .map((b) =>
        [
          `${b.current ? "🔥" : b.enabled ? "🟢" : "⚪"} <b>#${b.bossNumber} ${esc(b.name)}</b>`,
          `   <i>${esc(b.subtitle ?? "—")}</i>`,
          `   ❤️ base ${fmt(b.maxHp)} → efetivo <b>${fmt(b.effective?.maxHp)}</b> HP`,
          `   🛡 DEF ${fmt(b.effective?.defense)} · ⚔️ ATK ${fmt(b.effective?.attack)} · 🎁 ${fmt(b.rewardFc)} FC · ⏱ ${Math.round(Number(b.durationSeconds ?? 0) / 3600)}h`,
        ].join("\n"),
      )
      .join("\n\n") || "—";
  const rows = slice.map((b) => [{ t: `${b.enabled ? "🟢" : "⚪"} #${b.bossNumber} ${b.name}`, d: `gbt:${b.code}` }]);
  const pager: { t: string; d: string }[] = [];
  if (page > 0) pager.push({ t: "⬅️", d: `boss:roster:${page - 1}` });
  if ((page + 1) * perPage < bosses.length) pager.push({ t: "➡️", d: `boss:roster:${page + 1}` });
  return edit(
    ctx,
    [
      "🗺 <b>GLOBAL BOSS ROSTER</b>",
      `Total: <b>${bosses.length}</b> chefes · ciclo atual: ${d?.activeBossNumber ? `#${d.activeBossNumber}` : "—"}`,
      ...difficultyLines(d?.difficulty),
      "",
      body,
    ].join("\n"),
    kb([...rows, ...(pager.length ? [pager] : []), nav("m:boss")]),
  );
}

async function bossTemplateMenu(ctx: Ctx, code: string) {
  const d = (await rpc("admin_global_boss_roster", { p_admin_id: ctx.adminId })) as any;
  const b = arr<any>(d?.bosses).find((x) => x.code === code);
  if (!b) return send(ctx, "⚠️ Chefe não encontrado.", kb([[{ t: "🗺 ROSTER", d: "boss:roster:0" }], nav()]));
  return edit(
    ctx,
    [
      `👹 <b>#${b.bossNumber} ${esc(b.name)}</b>`,
      `<code>${esc(b.code)}</code> · tema ${esc(b.theme ?? "—")}`,
      `<i>${esc(b.subtitle ?? "—")}</i>`,
      "",
      `❤️ HP base: <b>${fmt(b.maxHp)}</b> → efetivo <b>${fmt(b.effective?.maxHp)}</b> (${Number(b.effective?.hpMultiplier ?? 1)}x)`,
      `🛡 DEF base: ${fmt(b.baseDefense)} → efetiva <b>${fmt(b.effective?.defense)}</b> (${Number(b.effective?.defenseMultiplier ?? 1)}x · −${((1 - Number(b.effective?.damageFactor ?? 1)) * 100).toFixed(1)}% dano)`,
      `⚔️ ATK base: ${fmt(b.baseAttack)} → efetivo <b>${fmt(b.effective?.attack)}</b> (${Number(b.effective?.atkMultiplier ?? 1)}x)`,
      `🎁 Prêmio: <b>${fmt(b.rewardFc)} FC</b>`,
      `⏱ Duração: ${Math.round(Number(b.durationSeconds ?? 0) / 3600)}h`,
      `Status: ${b.enabled ? "🟢 ATIVO no ciclo" : "⚪ DESATIVADO"}${b.current ? " · 🔥 EM COMBATE" : ""}`,
    ].join("\n"),
    kb([
      [{ t: b.enabled ? "⚪ DESATIVAR" : "🟢 ATIVAR", d: `gbtset:${b.code}:toggle` }],
      [
        { t: "❤️ HP", d: `ask:gbthp|${b.code}` },
        { t: "🎁 PRÊMIO", d: `ask:gbtrw|${b.code}` },
      ],
      [{ t: "⏱ DURAÇÃO (h)", d: `ask:gbtdur|${b.code}` }],
      [
        { t: "✏️ NOME", d: `ask:gbtname|${b.code}` },
        { t: "📖 LORE", d: `ask:gbtsub|${b.code}` },
      ],
      nav("boss:roster:0"),
    ]),
  );
}

async function bossRanking(ctx: Ctx) {
  const d = (await rpc("admin_boss_overview", { p_admin_id: ctx.adminId })) as any;
  const top = arr<any>(d?.top);
  const cycle = d?.cycle ?? null;
  const body =
    top
      .map(
        (t) =>
          `#${t.rank} <b>${esc(t.name)}</b>\n   <code>${esc(t.telegramId)}</code> · ${fmt(Math.round(Number(t.damage ?? 0)))} dano · ${Number(t.sharePercent ?? 0).toFixed(2)}%`,
      )
      .join("\n") || "Nenhum participante ainda.";
  return edit(
    ctx,
    `🏆 <b>RANKING DO BOSS GLOBAL</b>\n${cycle ? `Ciclo #${cycle.cycleNumber} · prêmio ${fmt(cycle.rewardPoolFc)} FC` : "Sem ciclo ativo"}\n\n${body}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "boss:rank" }], nav("m:boss")]),
  );
}

// ---------------------------------------------------------------- user management hub
const RARITIES = ["common", "uncommon", "rare", "epic", "legendary", "ancestral"];

async function userFcMenu(ctx: Ctx, tg: string) {
  const p = (await rpc("admin_player_detail", { p_admin_id: ctx.adminId, p_ref: tg })) as any;
  return edit(
    ctx,
    `💰 <b>SALDO</b>\n👤 ${esc(p.name)} ${p.username ? "@" + esc(p.username) : ""}\n🆔 <code>${p.telegram_id}</code>\n\nSaldo atual: <b>${fmt(p.forge_coins)} FC</b>\nTON interno: ${fmt(p.ton_balance)} TON`,
    kb([
      [
        { t: "➕ ADD FC", d: `fc:add:${tg}` },
        { t: "➖ REMOVE FC", d: `fc:remove:${tg}` },
      ],
      [
        { t: "✏️ SET BALANCE", d: `fc:set:${tg}` },
        { t: "📜 HISTÓRICO", d: `hist:${tg}` },
      ],
      [
        { t: "➕ TON", d: `ton:add:${tg}` },
        { t: "➖ TON", d: `ton:remove:${tg}` },
        { t: "✏️ SET TON", d: `ton:set:${tg}` },
      ],
      nav(`find:${tg}`),
    ]),
  );
}

async function userHeroesMenu(ctx: Ctx, tg: string, offset = 0) {
  const d = (await rpc("admin_player_heroes", {
    p_admin_id: ctx.adminId,
    p_ref: tg,
    p_rarity: null,
    p_limit: 10,
    p_offset: offset,
  })) as any;
  const heroes = arr<any>(d?.heroes);
  const lines =
    heroes
      .map(
        (h, i) =>
          `<b>${offset + i + 1}.</b> ${esc(h.name)} · ${esc(h.rarity)} NV${h.level} ⭐${h.fusion_level}\n   ATK ${fmt(h.final_atk)} · HP ${fmt(h.final_hp)}${h.in_pvp ? " · ⚔️ PvP" : ""}${h.in_boss ? " · 👹 Boss" : ""}`,
      )
      .join("\n") || "Nenhum herói.";
  const rows: { t: string; d: string }[][] = [];
  for (let i = 0; i < heroes.length; i += 5) {
    rows.push(heroes.slice(i, i + 5).map((h, j) => ({ t: `🗑 ${offset + i + j + 1}`, d: `uhd:${tg}:${h.id}` })));
  }
  const page: { t: string; d: string }[] = [];
  if (offset > 0) page.push({ t: "⬅️ ANTERIOR", d: `uh:${tg}:${Math.max(0, offset - 10)}` });
  if (offset + heroes.length < Number(d?.total ?? 0)) page.push({ t: "PRÓXIMA ➡️", d: `uh:${tg}:${offset + 10}` });
  if (page.length) rows.push(page);
  rows.push([{ t: "➕ ADD HERO", d: `uhadd:${tg}` }]);
  rows.push(nav(`find:${tg}`));
  return edit(
    ctx,
    `🦸 <b>HERÓIS DO JOGADOR</b>\nTotal: <b>${fmt(d?.total ?? 0)}</b>\n\n${lines}\n\nToque em 🗑 para remover uma instância.`,
    kb(rows),
  );
}

async function heroCatalogPicker(ctx: Ctx, tg: string, rarity?: string) {
  const d = (await rpc("admin_search_heroes", { p_admin_id: ctx.adminId, p_query: null, p_limit: 40 })) as any;
  const heroes = arr<any>(d?.heroes).filter((h) => !rarity || String(h.rarity).toLowerCase() === rarity);
  const rows: { t: string; d: string }[][] = [];
  for (let i = 0; i < heroes.slice(0, 24).length; i += 2) {
    rows.push(heroes.slice(i, i + 2).map((h) => ({ t: `${h.name}`.slice(0, 24), d: `uhc:${tg}:${h.hero_key}` })));
  }
  rows.push(RARITIES.slice(0, 3).map((r) => ({ t: r.toUpperCase().slice(0, 9), d: `uhr:${tg}:${r}` })));
  rows.push(RARITIES.slice(3).map((r) => ({ t: r.toUpperCase().slice(0, 9), d: `uhr:${tg}:${r}` })));
  rows.push([
    { t: "📋 TODOS", d: `uhadd:${tg}` },
    { t: "🔎 BUSCAR (hero_key)", d: `gh:${tg}` },
  ]);
  rows.push(nav(`uh:${tg}:0`));
  return edit(
    ctx,
    `➕ <b>ADD HERO</b>${rarity ? ` · ${esc(rarity.toUpperCase())}` : ""}\nCatálogo real (<code>hero_catalog</code>) — ${heroes.length} heróis.\nEscolha o herói para conceder.`,
    kb(rows),
  );
}

async function userItemsMenu(ctx: Ctx, tg: string) {
  const d = (await rpc("admin_player_items", { p_admin_id: ctx.adminId, p_ref: tg })) as any;
  const items = arr<any>(d?.items);
  const lines =
    items.map((i) => `• ${esc(i.label)} — <b>${fmt(i.quantity)}</b>\n   <code>${esc(i.key)}</code>`).join("\n") ||
    "Inventário vazio.";
  return edit(
    ctx,
    `🎒 <b>ITENS DO JOGADOR</b>\n\n${lines}`,
    kb([
      [
        { t: "➕ ADD ITEM", d: `uia:${tg}` },
        { t: "➖ REMOVE ITEM", d: `uir:${tg}` },
      ],
      [{ t: "🔄 ATUALIZAR", d: `ui:${tg}` }],
      nav(`find:${tg}`),
    ]),
  );
}

async function itemPicker(ctx: Ctx, tg: string, mode: "a" | "r") {
  const d = (await rpc("admin_player_items", { p_admin_id: ctx.adminId, p_ref: tg })) as any;
  const source = mode === "a" ? arr<any>(d?.catalog) : arr<any>(d?.items);
  const owned = new Map(arr<any>(d?.items).map((i) => [i.key, i.quantity]));
  const rows: { t: string; d: string }[][] = [];
  for (let i = 0; i < source.slice(0, 20).length; i += 2) {
    rows.push(
      source.slice(i, i + 2).map((it) => ({
        t: `${it.label}${mode === "r" ? ` (${it.quantity})` : owned.has(it.key) ? ` (${owned.get(it.key)})` : ""}`.slice(
          0,
          28,
        ),
        d: `uiq:${tg}:${mode}:${it.key}`.slice(0, 64),
      })),
    );
  }
  if (!rows.length) rows.push([{ t: "Nada disponível", d: `ui:${tg}` }]);
  rows.push(nav(`ui:${tg}`));
  return edit(
    ctx,
    `${mode === "a" ? "➕ <b>ADD ITEM</b>" : "➖ <b>REMOVE ITEM</b>"}\nEscolha o item (chaves internas reais do jogo).`,
    kb(rows),
  );
}

async function userPetsMenu(ctx: Ctx, tg: string) {
  const d = (await rpc("admin_player_pets", { p_admin_id: ctx.adminId, p_ref: tg })) as any;
  const pets = arr<any>(d?.pets);
  const lines =
    pets
      .map(
        (p, i) =>
          `<b>${i + 1}.</b> ${p.is_active ? "⭐ " : ""}${esc(p.name)} · ${esc(p.rarity)} NV${p.level} · tier ${p.evolution_tier} (${esc(p.evolution_stage)})`,
      )
      .join("\n") || "Nenhum pet.";
  const rows: { t: string; d: string }[][] = [];
  pets.slice(0, 6).forEach((p, i) =>
    rows.push([
      { t: `⭐ ATIVAR ${i + 1}`, d: `upa:${tg}:${p.id}` },
      { t: `🗑 REMOVER ${i + 1}`, d: `upd:${tg}:${p.id}` },
    ]),
  );
  rows.push([{ t: "➕ ADD PET", d: `gp:${tg}` }]);
  rows.push(nav(`find:${tg}`));
  return edit(ctx, `🐲 <b>PETS DO JOGADOR</b>\n\n${lines}`, kb(rows));
}

// ---------------------------------------------------------------- 🎁 GIFT CENTER (fully isolated flow)
// Every step has an explicit state persisted in its OWN row (chat_id = -chatId), so the generic
// prompt cleanup can never wipe the gift flow half way through. Delivery is always server side
// (admin_send_gift) and idempotent through a unique gift code.
const GIFT_TYPES: Record<string, { icon: string; label: string }> = {
  hero: { icon: "🦸", label: "HERÓI" },
  egg: { icon: "🥚", label: "OVO" },
  chest: { icon: "🎁", label: "BAÚ" },
  fc: { icon: "💰", label: "FC" },
  pet: { icon: "👾", label: "PET" },
  item: { icon: "🍖", label: "ITEM" },
};

const GIFT_RARITIES: [string, string][] = [
  ["comum", "Comum"],
  ["incomum", "Incomum"],
  ["raro", "Raro"],
  ["epico", "Épico"],
  ["lendario", "Lendário"],
  ["mitico", "Mítico"],
  ["ancestral", "Ancestral"],
];

type GiftItem = { key: string; label: string; sub?: string };
type GiftDraft = {
  type: string;
  tg?: string;
  playerName?: string;
  playerUser?: string;
  playerBalance?: number;
  rarity?: string | null;
  items?: GiftItem[];
  page?: number;
  pick?: GiftItem;
  qty?: number;
  fc?: number;
  code?: string;
};

const GIFT_PAGE = 8;
const giftKey = (ctx: Ctx) => -Math.abs(ctx.chatId);

async function giftDraftSet(ctx: Ctx, draft: GiftDraft, step = "gift_flow") {
  const { error } = await db.from("admin_bot_sessions").upsert(
    {
      admin_telegram_id: ctx.adminId,
      chat_id: giftKey(ctx),
      action: "giftdraft",
      step,
      context: draft as Record<string, unknown>,
      updated_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + SESSION_TTL_MS).toISOString(),
    },
    { onConflict: "admin_telegram_id,chat_id" },
  );
  if (error) console.error("gift draft write failed:", error.message);
}

async function giftDraftGet(ctx: Ctx): Promise<GiftDraft | null> {
  const { data, error } = await db
    .from("admin_bot_sessions")
    .select("context, expires_at")
    .eq("admin_telegram_id", ctx.adminId)
    .eq("chat_id", giftKey(ctx))
    .maybeSingle();
  if (error) {
    console.error("gift draft read failed:", error.message);
    return null;
  }
  if (!data) return null;
  if (new Date(data.expires_at).getTime() < Date.now()) {
    await giftDraftClear(ctx);
    return null;
  }
  return (data.context || {}) as GiftDraft;
}

async function giftDraftClear(ctx: Ctx) {
  await db.from("admin_bot_sessions").delete().eq("admin_telegram_id", ctx.adminId).eq("chat_id", giftKey(ctx));
}

const giftCode = () =>
  `AG-${Math.random().toString(36).slice(2, 6).toUpperCase()}${Date.now().toString(36).slice(-4).toUpperCase()}`;

async function giftHub(ctx: Ctx, editing = true) {
  await giftDraftClear(ctx);
  const text =
    "🎁 <b>CENTRAL DE PRESENTES</b>\n\nEnvie recompensas diretamente para jogadores.\nToda entrega é registrada com auditoria e código único.";
  const markup = kb([
    [
      { t: "🦸 HERÓI", d: "gf:t:hero" },
      { t: "🥚 OVO", d: "gf:t:egg" },
    ],
    [
      { t: "🎁 BAÚ", d: "gf:t:chest" },
      { t: "💰 FC", d: "gf:t:fc" },
    ],
    [
      { t: "👾 PET", d: "gf:t:pet" },
      { t: "🍖 ITEM", d: "gf:t:item" },
    ],
    [{ t: "📜 HISTÓRICO", d: "gf:hist" }],
    nav(),
  ]);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function giftHistory(ctx: Ctx) {
  const d = (await rpc("admin_gift_history", { p_admin_id: ctx.adminId, p_limit: 12 })) as any;
  const items = arr<any>(d?.items);
  const list =
    items
      .map((g) =>
        [
          "🎁 <b>ADMIN GIFT</b>",
          `👤 ${g.player ? "@" + esc(g.player) : "—"}`,
          `🆔 <code>${esc(String(g.telegramId ?? "—"))}</code>`,
          g.type === "fc"
            ? `💰 ${fmt(g.fc)} FC`
            : `${GIFT_TYPES[g.type]?.icon ?? "🎁"} ${esc(g.label)} ×${fmt(g.quantity)}`,
          `👮 Admin: ${esc(String(g.adminId))}`,
          `🕐 ${dt(g.createdAt)}`,
          `🔑 Gift ID: <code>${esc(g.giftCode)}</code>`,
          g.status === "delivered" ? "✅ DELIVERED" : `• ${esc(String(g.status).toUpperCase())}`,
        ].join("\n"),
      )
      .join("\n\n") || "Nenhum presente enviado ainda.";
  return edit(
    ctx,
    `📜 <b>HISTÓRICO DE PRESENTES</b> (${fmt(d?.total ?? 0)})\n\n${list.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "gf:hist" }], [{ t: "🎁 ENVIAR PRESENTE", d: "gf:home" }], nav("gf:home")]),
  );
}

/** Step 1 → type chosen, ask for the player (explicit state gift_select_user). */
async function giftStartType(ctx: Ctx, type: string) {
  if (!GIFT_TYPES[type]) return giftHub(ctx);
  await giftDraftSet(ctx, { type }, "gift_select_user");
  await edit(
    ctx,
    `${GIFT_TYPES[type].icon} <b>PRESENTE: ${GIFT_TYPES[type].label}</b>\n\nPasso 1 de 3 — escolher o jogador.`,
    kb([[{ t: "❌ CANCELAR", d: "gf:home" }]]),
  );
  return ask(ctx, `giftuser|${type}`, PROMPTS.giftuser);
}

/** Step 2 → player resolved (Telegram ID, @username, name or internal id). */
async function giftPlayerFound(ctx: Ctx, type: string, text: string) {
  const p = (await rpc("admin_player_detail", { p_admin_id: ctx.adminId, p_ref: text })) as any;
  await giftDraftSet(
    ctx,
    {
      type,
      tg: String(p.telegram_id),
      playerName: p.name,
      playerUser: p.username,
      playerBalance: Number(p.forge_coins || 0),
    },
    "gift_select_item",
  );
  return send(
    ctx,
    [
      `${GIFT_TYPES[type]?.icon ?? "🎁"} <b>PRESENTE: ${GIFT_TYPES[type]?.label ?? ""}</b>`,
      "",
      `👤 Jogador: <b>${esc(p.name)}</b>${p.username ? ` (@${esc(p.username)})` : ""}`,
      `🆔 Telegram ID: <code>${esc(String(p.telegram_id))}</code>`,
      `💰 Saldo: <b>${fmt(p.forge_coins)} FC</b>`,
    ].join("\n"),
    kb([
      [
        { t: "✅ SELECIONAR", d: "gf:sel" },
        { t: "❌ CANCELAR", d: "gf:home" },
      ],
    ]),
  );
}

/** Step 3 → after the player is confirmed, branch per gift type. */
async function giftAfterPlayer(ctx: Ctx) {
  const draft = await giftDraftGet(ctx);
  if (!draft?.tg) return giftHub(ctx);
  if (draft.type === "fc") {
    await edit(
      ctx,
      `💰 <b>PRESENTE FC</b>\n\n👤 ${esc(draft.playerName ?? "")}${draft.playerUser ? ` (@${esc(draft.playerUser)})` : ""}\n💰 Saldo atual: <b>${fmt(draft.playerBalance)} FC</b>`,
      kb([[{ t: "❌ CANCELAR", d: "gf:home" }]]),
    );
    return ask(ctx, "giftfc", PROMPTS.giftfc);
  }
  if (draft.type === "hero") return giftRarityMenu(ctx);
  return giftCatalog(ctx, null, 0);
}

async function giftRarityMenu(ctx: Ctx) {
  const rows = GIFT_RARITIES.map(([key, label]) => [{ t: label, d: `gf:r:${key}` }]);
  rows.push([{ t: "📋 TODOS", d: "gf:r:all" }]);
  rows.push([{ t: "❌ CANCELAR", d: "gf:home" }]);
  return edit(ctx, "🦸 <b>ESCOLHA O HERÓI</b>\n\nSelecione a raridade (catálogo real do servidor):", kb(rows));
}

/** Loads the REAL catalog from the database and keeps it in the draft so buttons stay short. */
async function giftCatalog(ctx: Ctx, rarity: string | null, page: number) {
  const draft = await giftDraftGet(ctx);
  if (!draft?.tg) return giftHub(ctx);
  const kind = draft.type;
  let items = draft.items;
  if (!items || draft.rarity !== (rarity ?? null) || !items.length) {
    const d = (await rpc("admin_gift_catalog", { p_admin_id: ctx.adminId, p_kind: kind, p_rarity: rarity })) as any;
    items = arr<GiftItem>(d?.items);
  }
  await giftDraftSet(ctx, { ...draft, rarity: rarity ?? null, items, page }, "gift_select_item");
  if (!items.length) {
    return edit(
      ctx,
      `⚠️ Nenhum item cadastrado para <b>${GIFT_TYPES[kind]?.label ?? kind}</b>${rarity ? ` (${esc(rarity)})` : ""}.`,
      kb([[{ t: "⬅️ VOLTAR", d: "gf:sel" }], [{ t: "🎁 CENTRAL", d: "gf:home" }]]),
    );
  }
  const pages = Math.ceil(items.length / GIFT_PAGE);
  const safePage = Math.min(Math.max(0, page), pages - 1);
  const slice = items.slice(safePage * GIFT_PAGE, safePage * GIFT_PAGE + GIFT_PAGE);
  const rows = slice.map((it, i) => [
    {
      t: `${GIFT_TYPES[kind]?.icon ?? "🎁"} ${it.label}${it.sub ? ` · ${it.sub}` : ""}`.slice(0, 60),
      d: `gf:i:${safePage * GIFT_PAGE + i}`,
    },
  ]);
  const pager: { t: string; d: string }[] = [];
  if (safePage > 0) pager.push({ t: "◀️", d: `gf:pg:${safePage - 1}` });
  if (safePage < pages - 1) pager.push({ t: "▶️", d: `gf:pg:${safePage + 1}` });
  if (pager.length) rows.push(pager);
  rows.push([{ t: "❌ CANCELAR", d: "gf:home" }]);
  return edit(
    ctx,
    `${GIFT_TYPES[kind]?.icon ?? "🎁"} <b>ESCOLHA O ${GIFT_TYPES[kind]?.label ?? "ITEM"}</b>\nJogador: ${draft.playerUser ? "@" + esc(draft.playerUser) : esc(draft.playerName ?? "")}\nPágina ${safePage + 1}/${pages}`,
    kb(rows),
  );
}

async function giftPickItem(ctx: Ctx, index: number) {
  const draft = await giftDraftGet(ctx);
  const item = arr<GiftItem>(draft?.items)[index];
  if (!draft?.tg || !item) return giftHub(ctx);
  await giftDraftSet(ctx, { ...draft, pick: item }, "gift_select_quantity");
  if (draft.type === "hero") return giftConfirm(ctx, 1);
  await edit(
    ctx,
    `${GIFT_TYPES[draft.type]?.icon ?? "🎁"} <b>${esc(item.label)}</b>\n\nQuantas unidades deseja enviar?`,
    kb([[{ t: "❌ CANCELAR", d: "gf:home" }]]),
  );
  return ask(ctx, "giftqty", PROMPTS.giftqty);
}

/** Final confirmation. The gift code is created here, so a double tap can never deliver twice. */
async function giftConfirm(ctx: Ctx, qty: number, fc = 0) {
  const draft = await giftDraftGet(ctx);
  if (!draft?.tg) return giftHub(ctx);
  const code = draft.code || giftCode();
  await giftDraftSet(ctx, { ...draft, qty, fc, code }, "gift_confirm");
  const who = `${draft.playerUser ? "@" + esc(draft.playerUser) : esc(draft.playerName ?? "")} · <code>${esc(draft.tg)}</code>`;
  const body =
    draft.type === "fc"
      ? [
          `💰 <b>PRESENTE FC</b>`,
          "",
          `👤 Jogador: ${who}`,
          `💰 Valor: <b>${fmt(fc)} FC</b>`,
          `📊 Saldo atual: ${fmt(draft.playerBalance)} FC → <b>${fmt(Number(draft.playerBalance || 0) + fc)} FC</b>`,
        ]
      : [
          "🎁 <b>ENVIAR PRESENTE</b>",
          "",
          `👤 Jogador: ${who}`,
          `Presente: ${GIFT_TYPES[draft.type]?.icon ?? "🎁"} ${esc(draft.pick?.label ?? "")}`,
          draft.pick?.sub ? `Tipo: ${esc(draft.pick.sub)}` : "",
          `Quantidade: <b>${fmt(qty)}</b>`,
          draft.type === "egg" ? "\n<i>O ovo entra no inventário — o jogador abre quando quiser.</i>" : "",
        ];
  return send(
    ctx,
    [...body.filter(Boolean), "", `🔑 Gift ID: <code>${code}</code>`].join("\n"),
    kb([
      [
        { t: "✅ ENVIAR", d: "gf:ok" },
        { t: "❌ CANCELAR", d: "gf:home" },
      ],
    ]),
  );
}

async function giftDeliver(ctx: Ctx) {
  const draft = await giftDraftGet(ctx);
  if (!draft?.tg || !draft.code) return giftHub(ctx);
  const isFc = draft.type === "fc";
  const r = (await rpc("admin_send_gift", {
    p_admin_id: ctx.adminId,
    p_ref: draft.tg,
    p_type: draft.type,
    p_item_key: isFc ? String(draft.fc ?? 0) : String(draft.pick?.key ?? ""),
    p_quantity: isFc ? 1 : Math.max(1, Number(draft.qty || 1)),
    p_gift_code: draft.code,
  })) as any;
  await giftDraftClear(ctx);
  await clearSession(ctx);
  const done = kb([
    [
      { t: "🎁 ENVIAR OUTRO", d: "gf:home" },
      { t: "🏠 MENU", d: "home" },
    ],
  ]);
  if (r?.duplicate) {
    return edit(
      ctx,
      `⚠️ <b>PRESENTE JÁ ENTREGUE</b>\n\nO código <code>${esc(draft.code)}</code> já foi processado — nada foi duplicado.`,
      done,
    );
  }
  return edit(
    ctx,
    [
      "✅ <b>PRESENTE ENVIADO</b>",
      "",
      `👤 ${draft.playerUser ? "@" + esc(draft.playerUser) : esc(draft.playerName ?? "")}`,
      `🆔 <code>${esc(draft.tg)}</code>`,
      isFc
        ? `💰 +${fmt(r?.fc ?? draft.fc)} FC`
        : `${GIFT_TYPES[draft.type]?.icon ?? "🎁"} ${esc(r?.label ?? draft.pick?.label ?? "")} ×${fmt(r?.quantity ?? draft.qty ?? 1)}`,
      `👮 Admin: ${ctx.adminId}`,
      `🔑 Gift ID: <code>${esc(draft.code)}</code>`,
      "✅ DELIVERED",
    ].join("\n"),
    done,
  );
}

async function giftCallback(ctx: Ctx, rest: string[]) {
  const [op, a] = rest;
  switch (op) {
    case "home": {
      await clearSession(ctx);
      return giftHub(ctx);
    }
    case "hist": {
      await clearSession(ctx);
      return giftHistory(ctx);
    }
    case "t":
      return giftStartType(ctx, a);
    case "sel":
      return giftAfterPlayer(ctx);
    case "r":
      return giftCatalog(ctx, a === "all" ? null : a, 0);
    case "pg": {
      const draft = await giftDraftGet(ctx);
      return giftCatalog(ctx, draft?.rarity ?? null, Number(a) || 0);
    }
    case "i":
      return giftPickItem(ctx, Number(a) || 0);
    case "ok":
      return giftDeliver(ctx);
    default:
      return giftHub(ctx);
  }
}

/** Gift prompts. Runs before any menu fallback, so a typed value is always executed. */
async function giftPrompt(ctx: Ctx, key: string, arg: string, text: string) {
  switch (key) {
    case "giftuser": {
      try {
        return await giftPlayerFound(ctx, arg || (await giftDraftGet(ctx))?.type || "fc", text);
      } catch (error) {
        const raw = error instanceof Error ? error.message : String(error);
        if (raw.includes("player_not_found"))
          throw new Error("KEEP_SESSION::⚠️ Jogador não encontrado. Envie Telegram ID, @username, nome ou ID interno.");
        throw error;
      }
    }
    case "giftfc": {
      const value = Math.round(parseAmount(text.replace(/[^\d.,-]/g, "")));
      if (!Number.isFinite(value) || value <= 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um valor de FC maior que 0 (ex.: <code>50000</code>).");
      return giftConfirm(ctx, 1, value);
    }
    case "giftqty": {
      const qty = Math.round(parseAmount(text.replace(/[^\d.,-]/g, "")));
      if (!Number.isFinite(qty) || qty < 1 || qty > 100)
        throw new Error("KEEP_SESSION::⚠️ Envie uma quantidade entre 1 e 100.");
      return giftConfirm(ctx, qty);
    }
    default:
      return giftHub(ctx, false);
  }
}

// ---------------------------------------------------------------- 🤝 partner channels
// The player only ever sees NAME + REWARD + GO. The destination URL lives in
// partner_channels.target_url and is resolved server-side by the game API.
const ptRpc = (ctx: Ctx, action: string, partnerId: string | null = null, payload: Record<string, unknown> = {}) =>
  rpc("admin_partners", { p_admin_id: ctx.adminId, p_action: action, p_partner_id: partnerId, p_payload: payload });

/**
 * Membership validation runs with the GAME bot (the same bot the players use), so the
 * capability check must be done with that token too — otherwise validation would be
 * enabled for a chat the runtime bot cannot read.
 */
async function partnerCanValidate(chatId: string): Promise<{ ok: boolean; title?: string; error?: string }> {
  const chat = await tgAs(GAME_BOT_TOKEN, "getChat", { chat_id: chatId });
  if (!chat.ok) return { ok: false, error: String(chat.error || "chat inacessível") };
  const me = await tgAs(GAME_BOT_TOKEN, "getChatMember", { chat_id: chatId, user_id: SUPER_ADMIN_ID });
  if (!me.ok) return { ok: false, error: String(me.error || "sem permissão para consultar membros") };
  return { ok: true, title: String((chat as any)?.result?.title || "") };
}

const PT_VALIDATION_QUESTION = [
  "🛡 <b>DESEJA VALIDAR SE O JOGADOR ENTROU NO CANAL/GRUPO?</b>",
  "",
  "Com validação: a recompensa só é paga depois que o servidor confirmar a entrada.",
  "Sem validação: o jogador toca GO, volta e resgata (uma vez por jogador).",
].join("\n");

async function partnersHub(ctx: Ctx, editing = true) {
  const d = (await ptRpc(ctx, "list")) as any;
  const items = (d?.partners ?? []) as any[];
  const lines = items.map(
    (x) =>
      `${x.enabled ? "🟢" : "🔴"} <b>${esc(x.name)}</b> · ${fmt(x.rewardFc)} FC ${x.validationEnabled ? "🛡" : ""}\n   visitas ${fmt(x.visits)} · resgates ${fmt(x.claims)}`,
  );
  const text = [
    "🤝 <b>PARTNER CHANNELS</b>",
    "O jogador vê apenas <b>NOME + RECOMPENSA + GO</b>. O link fica oculto no servidor e cada parceiro paga <b>uma única vez por jogador</b>.",
    "🛡 = validação de entrada ativa.",
    "",
    lines.join("\n") || "— nenhum parceiro cadastrado —",
  ].join("\n");
  const rows = items
    .slice(0, 12)
    .map((x) => [{ t: `${x.enabled ? "🟢" : "🔴"} ${String(x.name).slice(0, 22)}`, d: `pt:open:${x.id}` }]);
  const markup = kb([
    [{ t: "➕ NOVO PARCEIRO", d: "pt:ask:ptname" }],
    ...rows,
    [{ t: "🔄 ATUALIZAR", d: "m:partners" }],
    nav(),
  ]);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function partnerCard(ctx: Ctx, id: string, editing = true) {
  const d = (await ptRpc(ctx, "detail", id)) as any;
  const c = d?.partner;
  if (!c) return partnersHub(ctx, editing);
  const text = [
    `🤝 <b>${esc(c.name)}</b> ${c.enabled ? "🟢 ATIVO" : "🔴 DESATIVADO"}`,
    `🪙 Recompensa: <b>${fmt(c.rewardFc)} FC</b> (uma vez por jogador)`,
    `🔢 Ordem: ${fmt(c.sortOrder)}`,
    `🔗 Link: <b>configurado</b> (${esc(c.urlHost)}) — oculto para os jogadores`,
    `🛡 Validação de entrada: <b>${c.validationEnabled ? "ATIVA" : "DESATIVADA"}</b>`,
    `🆔 Chat ID: ${c.chatId ? `<code>${esc(c.chatId)}</code>` : "— não configurado —"}`,
    "",
    `👀 Visitas: <b>${fmt(c.visits)}</b> · ✅ Resgates: <b>${fmt(c.claims)}</b>`,
    `💸 FC distribuído: <b>${fmt(c.distributedFc)}</b>`,
    c.lastClaimAt
      ? `🕒 Último resgate: <code>${String(c.lastClaimAt).slice(0, 16).replace("T", " ")}</code>`
      : "🕒 Nenhum resgate ainda",
  ].join("\n");
  const markup = kb([
    [
      { t: "🏷 NOME", d: `pt:ask:ptrename|${id}` },
      { t: "🪙 RECOMPENSA", d: `pt:ask:ptsetreward|${id}` },
    ],
    [
      { t: "🔗 LINK", d: `pt:ask:ptsetlink|${id}` },
      { t: "🔢 ORDEM", d: `pt:ask:ptsort|${id}` },
    ],
    [
      { t: "🆔 CHAT ID", d: `pt:ask:ptsetchat|${id}` },
      { t: c.validationEnabled ? "🛡 DESATIVAR VALIDAÇÃO" : "🛡 ATIVAR VALIDAÇÃO", d: `pt:vtoggle:${id}` },
    ],
    [{ t: c.enabled ? "🔴 DESATIVAR" : "🟢 ATIVAR", d: `pt:toggle:${id}` }],
    [{ t: "🗑 REMOVER", d: `pt:confirm:${id}` }],
    nav("m:partners"),
  ]);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

async function partnersCallback(ctx: Ctx, rest: string[]) {
  const [sub, arg] = [rest[0], rest.slice(1).join(":")];
  if (sub === "ask") {
    const k = arg;
    return ask(ctx, k, PROMPTS[k.split("|")[0]] || "Envie o valor.");
  }

  // Step 4/5 of the wizard: validate membership or not.
  if (sub === "val") {
    const session = await getSession(ctx);
    const c = session?.context ?? {};
    if (!c.name || !c.url) {
      await clearSession(ctx);
      return edit(
        ctx,
        "⚠️ Cadastro expirado. Comece novamente em ➕ NOVO PARCEIRO.",
        kb([[{ t: "⬅️ PARCEIROS", d: "m:partners" }], nav()]),
      );
    }
    if (arg === "1") {
      await setSession(ctx, "ptchat", "awaiting_input", { ...c, validationEnabled: true });
      return edit(
        ctx,
        `🛡 Validação: <b>ATIVA</b>\n\n${PROMPTS.ptchat}\n\n⚠️ O Chat ID é diferente do link. O bot do jogo precisa estar no canal/grupo para conseguir validar.`,
        kb([[{ t: "❌ CANCELAR", d: "cancel" }]]),
      );
    }
    await setSession(ctx, "ptsave", "awaiting_confirm", { ...c, validationEnabled: false, chatId: null });
    return edit(
      ctx,
      partnerConfirmText({ ...c, validationEnabled: false }),
      kb([
        [
          { t: "✅ SALVAR", d: "pt:save" },
          { t: "❌ CANCELAR", d: "cancel" },
        ],
      ]),
    );
  }

  if (sub === "save") {
    const session = await getSession(ctx);
    const c = session?.context ?? {};
    const name = String(c.name || "").trim();
    const url = String(c.url || "").trim();
    const reward = Math.round(Number(c.rewardFc ?? 0)) || 0;
    const validationEnabled = c.validationEnabled === true;
    const chatId = String(c.chatId || "").trim() || null;
    if (!name || !/^https?:\/\/\S+$/i.test(url) || (validationEnabled && !chatId)) {
      await clearSession(ctx);
      return edit(
        ctx,
        "⚠️ Cadastro expirado. Comece novamente em ➕ NOVO PARCEIRO.",
        kb([[{ t: "⬅️ PARCEIROS", d: "m:partners" }], nav()]),
      );
    }
    const d = (await ptRpc(ctx, "create", null, { name, url, rewardFc: reward, validationEnabled, chatId })) as any;
    await clearSession(ctx);
    await send(
      ctx,
      `✅ <b>PARCEIRO CRIADO</b>\n${esc(d?.partner?.name || name)} · ${fmt(reward)} FC\n🛡 Validação: <b>${validationEnabled ? "ATIVA" : "DESATIVADA"}</b>\n🔗 Link salvo e oculto: no jogo aparece só o nome e o botão GO.`,
    );
    return partnersHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "open") return partnerCard(ctx, arg);
  if (sub === "toggle") {
    await ptRpc(ctx, "toggle", arg);

    return partnerCard(ctx, arg);
  }
  if (sub === "vtoggle") {
    const d = (await ptRpc(ctx, "detail", arg)) as any;
    const current = d?.partner;
    if (!current) return partnersHub(ctx);
    if (current.validationEnabled) {
      await ptRpc(ctx, "validation", arg, { validationEnabled: false });
      return partnerCard(ctx, arg);
    }
    const chatId = String(current.chatId || "").trim();
    if (!chatId)
      return edit(
        ctx,
        `🆔 Antes de ativar a validação, configure o <b>Chat ID</b> do canal/grupo.\n\n${PROMPTS.ptsetchat}`,
        kb([[{ t: "🆔 CHAT ID", d: `pt:ask:ptsetchat|${arg}` }], [{ t: "⬅️ PARCEIRO", d: `pt:open:${arg}` }]]),
      );
    const capability = await partnerCanValidate(chatId);
    if (!capability.ok) {
      return edit(
        ctx,
        `⚠️ <b>O bot não consegue validar membros desse canal/grupo.</b>\nChat: <code>${esc(chatId)}</code>\nMotivo: <code>${esc(capability.error)}</code>\n\nAdicione o bot do jogo ao canal/grupo como administrador e tente de novo. A validação <b>não</b> foi ativada.`,
        kb([
          [{ t: "🔁 TENTAR DE NOVO", d: `pt:vtoggle:${arg}` }],
          [{ t: "🆔 TROCAR CHAT ID", d: `pt:ask:ptsetchat|${arg}` }],
          [{ t: "⬅️ PARCEIRO", d: `pt:open:${arg}` }],
        ]),
      );
    }
    await ptRpc(ctx, "validation", arg, { validationEnabled: true });
    return partnerCard(ctx, arg);
  }
  if (sub === "confirm") {
    return edit(
      ctx,
      "⚠️ Remover este parceiro? Ele deixa de aparecer no jogo (os resgates já pagos são preservados).",
      kb([
        [
          { t: "✅ CONFIRMAR", d: `pt:del:${arg}` },
          { t: "❌ Cancelar", d: `pt:open:${arg}` },
        ],
      ]),
    );
  }
  if (sub === "del") {
    await ptRpc(ctx, "delete", arg);
    await send(ctx, "🗑 Parceiro removido.");
    return partnersHub({ ...ctx, messageId: undefined }, false);
  }
  return partnersHub(ctx);
}

function partnerConfirmText(c: Record<string, unknown>) {
  const validation = c.validationEnabled === true;
  return [
    "🤝 <b>CONFIRMAR PARCEIRO</b>",
    `🏷 Nome: <b>${esc(c.name)}</b>`,
    `🪙 Recompensa: <b>${fmt(c.rewardFc)} FC</b>`,
    `🔗 Link: <code>${esc(c.url)}</code>`,
    `🛡 Validação: <b>${validation ? "ATIVA" : "DESATIVADA"}</b>`,
    validation ? `🆔 Chat ID: <code>${esc(c.chatId)}</code>` : "",
    "",
    "O link fica oculto no jogo: o jogador vê só o nome e o botão GO.",
  ]
    .filter(Boolean)
    .join("\n");
}

async function partnersPrompt(ctx: Ctx, key: string, args: string[], text: string) {
  const id = args[0] || "";
  // Wizard: NAME -> REWARD -> LINK -> VALIDATION -> (CHAT ID) -> CONFIRM -> SAVE.
  // Nothing is persisted in partner_channels before the explicit ✅ SALVAR.
  if (key === "ptname") {
    const name = text.slice(0, 40);
    if (name.length < 2) throw new Error("KEEP_SESSION::⚠️ Envie um nome com pelo menos 2 caracteres.");
    // Draft lives in the session context (and in the action key, as a fallback).
    const ok = await setSession(ctx, `ptreward|${encodeURIComponent(name)}`, "awaiting_input", { name });
    if (!ok) throw new Error("KEEP_SESSION::⚠️ Não foi possível salvar o rascunho. Envie o nome novamente.");
    return send(ctx, `🏷 Nome: <b>${esc(name)}</b>\n\n${PROMPTS.ptreward}`, kb([[{ t: "❌ CANCELAR", d: "cancel" }]]));
  }
  if (key === "ptreward") {
    const reward = parseAmount(text);
    if (!Number.isFinite(reward) || reward < 0 || reward > 1_000_000)
      throw new Error("KEEP_SESSION::⚠️ Envie um valor de FC entre 0 e 1000000.");
    const session = await getSession(ctx);
    const name = String(session?.context?.name || (args[0] ? decodeURIComponent(args[0]) : "")).trim();
    if (!name) throw new Error("KEEP_SESSION::⚠️ Cadastro expirado. Comece novamente em ➕ NOVO PARCEIRO.");
    // Step 3/6: the link is mandatory — never create the partner here.
    const ok = await setSession(ctx, "pturl", "awaiting_input", { name, rewardFc: Math.round(reward) });
    if (!ok) throw new Error("KEEP_SESSION::⚠️ Não foi possível salvar o rascunho. Envie a recompensa novamente.");
    return send(
      ctx,
      `🪙 Recompensa: <b>${fmt(Math.round(reward))} FC</b>\n\n🔗 <b>Envie agora o LINK do canal/grupo parceiro.</b>\nEx.: <code>https://t.me/cashway</code>\n\n<i>O link é usado apenas pelo botão GO no jogo e nunca é exibido ao jogador.</i>`,
      kb([[{ t: "❌ CANCELAR", d: "cancel" }]]),
    );
  }
  if (key === "pturl") {
    const url = text.trim();
    if (!/^https?:\/\/[^\s.]+\.[^\s]{2,}$/i.test(url) || url.length > 300) {
      throw new Error("KEEP_SESSION::⚠️ Link inválido. Envie um link válido — ex.: <code>https://t.me/cashway</code>");
    }

    const session = await getSession(ctx);
    const name = String(session?.context?.name || (args[0] ? decodeURIComponent(args[0]) : "PARTNER"));
    const reward = Math.round(Number(session?.context?.rewardFc ?? parseAmount(args[1] || "0"))) || 0;
    // Step 4/5: ask for validation BEFORE creating anything.
    await setSession(ctx, "ptvalidation", "awaiting_choice", { name, rewardFc: reward, url });
    return send(
      ctx,
      `🔗 Link: <code>${esc(url)}</code>\n\n${PT_VALIDATION_QUESTION}`,
      kb([
        [{ t: "✅ SIM, VALIDAR", d: "pt:val:1" }],
        [{ t: "❌ NÃO VALIDAR", d: "pt:val:0" }],
        [{ t: "❌ CANCELAR", d: "cancel" }],
      ]),
    );
  }
  if (key === "ptchat") {
    const chatId = text.trim();
    if (!/^(-?\d{5,20}|@[A-Za-z0-9_]{4,40})$/.test(chatId)) {
      throw new Error(
        "KEEP_SESSION::⚠️ Chat ID inválido. Envie o ID numérico (ex.: <code>-1001234567890</code>) ou <code>@usuario_do_canal</code>. O link do canal <b>não</b> serve aqui.",
      );
    }
    const capability = await partnerCanValidate(chatId);
    if (!capability.ok) {
      throw new Error(
        `KEEP_SESSION::⚠️ <b>O bot não consegue validar membros desse canal/grupo.</b>\nChat: <code>${esc(chatId)}</code>\nMotivo: <code>${esc(capability.error)}</code>\n\nAdicione o bot do jogo como administrador e envie o Chat ID novamente.`,
      );
    }
    const session = await getSession(ctx);
    const c = session?.context ?? {};
    await setSession(ctx, "ptsave", "awaiting_confirm", { ...c, validationEnabled: true, chatId });
    return send(
      ctx,
      `${capability.title ? `📡 Canal: <b>${esc(capability.title)}</b>\n` : ""}✅ O bot consegue validar membros.\n\n${partnerConfirmText({ ...c, validationEnabled: true, chatId })}`,
      kb([
        [
          { t: "✅ SALVAR", d: "pt:save" },
          { t: "❌ CANCELAR", d: "cancel" },
        ],
      ]),
    );
  }

  if (!id) {
    await clearSession(ctx);
    return partnersHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "ptrename") {
    const name = text.slice(0, 40);
    if (name.length < 2) throw new Error("KEEP_SESSION::⚠️ Envie um nome com pelo menos 2 caracteres.");
    await ptRpc(ctx, "rename", id, { name });
  } else if (key === "ptsetreward") {
    const reward = parseAmount(text);
    if (!Number.isFinite(reward) || reward < 0 || reward > 1_000_000)
      throw new Error("KEEP_SESSION::⚠️ Envie um valor de FC entre 0 e 1000000.");
    await ptRpc(ctx, "reward", id, { rewardFc: Math.round(reward) });
  } else if (key === "ptsetlink") {
    const url = text.trim();
    if (!/^https?:\/\/\S+$/i.test(url)) throw new Error("KEEP_SESSION::⚠️ Envie um link válido começando com https://");
    await ptRpc(ctx, "link", id, { url });
  } else if (key === "ptsetchat") {
    const chatId = text.trim();
    if (!/^(-?\d{5,20}|@[A-Za-z0-9_]{4,40})$/.test(chatId)) {
      throw new Error(
        "KEEP_SESSION::⚠️ Chat ID inválido. Envie o ID numérico (ex.: <code>-1001234567890</code>) ou <code>@usuario_do_canal</code>.",
      );
    }
    const capability = await partnerCanValidate(chatId);
    await ptRpc(ctx, "chat", id, { chatId, validationEnabled: capability.ok });
    await clearSession(ctx);
    await send(
      ctx,
      capability.ok
        ? `✅ Chat ID salvo e validação <b>ATIVA</b>.`
        : `🆔 Chat ID salvo, mas ⚠️ <b>o bot não consegue validar membros desse canal/grupo</b> (<code>${esc(capability.error)}</code>).\nA validação ficou <b>DESATIVADA</b> — adicione o bot do jogo como administrador e ative de novo.`,
    );
    return partnerCard({ ...ctx, messageId: undefined }, id, false);
  } else if (key === "ptsort") {
    const order = parseAmount(text);
    if (!Number.isFinite(order) || order < 1 || order > 999)
      throw new Error("KEEP_SESSION::⚠️ Envie um número entre 1 e 999.");
    await ptRpc(ctx, "sort", id, { sortOrder: Math.round(order) });
  }
  await clearSession(ctx);
  await send(ctx, "✅ Parceiro atualizado.");
  return partnerCard({ ...ctx, messageId: undefined }, id, false);
}

// ---------------------------------------------------------------- 🔥 hot wallet
// Address + minimum withdrawal live in wallet_settings and take effect immediately
// for deposits, TonConnect and withdrawals — nothing is hardcoded in the app.
const wlRpc = (ctx: Ctx, action = "get", payload: Record<string, unknown> = {}) =>
  rpc("admin_wallet_config", { p_admin_id: ctx.adminId, p_action: action, p_payload: payload });

async function hotWalletHub(ctx: Ctx, editing = true) {
  const d = (await wlRpc(ctx)) as any;
  const address = String(d?.hotWallet || "");
  const text = [
    "🔥 <b>HOT WALLET</b>",
    address
      ? `🏦 Endereço: <code>${esc(address)}</code>`
      : "⚠️ <b>Nenhuma hot wallet configurada</b> — depósitos ficam sem destino.",
    `⬇️ Saque mínimo: <b>${fmt(d?.minWithdrawTon ?? 0)} TON</b>`,
    d?.updatedAt ? `🕒 Atualizado: <code>${String(d.updatedAt).slice(0, 16).replace("T", " ")}</code>` : "",
    "",
    `🟡 Saques pendentes: <b>${fmt(d?.pendingWithdrawals)}</b> · 📥 Depósitos 24h: <b>${fmt(d?.depositsToday)}</b>`,
    "",
    "A alteração vale imediatamente para novos depósitos e para o TonConnect do jogo (sem deploy).",
  ]
    .filter(Boolean)
    .join("\n");
  const markup = kb([
    [{ t: "✏️ TROCAR ENDEREÇO", d: "ask:wlhot" }],
    [{ t: "⬇️ SAQUE MÍNIMO", d: "ask:wlmin" }],
    [{ t: "🔄 ATUALIZAR", d: "m:hotwallet" }],
    nav("m:wallet"),
  ]);
  return editing ? edit(ctx, text, markup) : send(ctx, text, markup);
}

// ---------------------------------------------------------------- actions

// ---------------------------------------------------------------- ⚙ POOL / PASS ACTIVITY
// Points/XP and daily caps per real gameplay activity. Pool requirements
// (500 points + 5 heroes) and pass tiers/rewards are NOT touched here.
const AR_LABELS: Record<string, string> = {
  PVP_COMPLETE: "⚔ PvP",
  GLOBAL_BOSS_ATTACK: "🌎 Global Boss",
  CLAN_BOSS_ATTACK: "🏰 Clan Boss",
  PET_FEED: "🐾 Feed Pet",
  EXPEDITION_COMPLETE: "🚀 Expeditions",
};

async function arConfig(): Promise<Record<string, any>> {
  const { data } = await db.from("game_settings").select("value").eq("key", "activity_rewards").maybeSingle();
  return (data?.value ?? {}) as Record<string, any>;
}

async function arHub(ctx: Ctx, useEdit = true) {
  const cfg = await arConfig();
  let text = "⚙ <b>POOL / PASS ACTIVITY</b>\nPontos da Pool e XP do Passe por atividade real.\n";
  let poolMax = 0,
    xpMax = 0;
  const rows: any[] = [];
  for (const key of Object.keys(AR_LABELS)) {
    const c = cfg[key] ?? {};
    const pts = Number(c.poolPoints ?? 0),
      cap = Number(c.poolDailyCap ?? 0),
      xp = Number(c.passXp ?? 0);
    poolMax += pts * cap;
    xpMax += xp * cap;
    text += `\n${AR_LABELS[key]}\n<code>+${pts} pool · +${xp} xp · ${cap}/dia</code>`;
    rows.push([{ t: AR_LABELS[key], d: `ar:item:${key}` }]);
  }
  text += `\n\nMáximo diário: <b>${fmt(poolMax)} Pool Points</b> · <b>${fmt(xpMax)} base Pass XP</b>`;
  text += `\n<i>Bônus do Passe (+20% / +40%) só se aplica ao XP, nunca aos Pool Points.</i>`;
  rows.push(nav());
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function arItem(ctx: Ctx, key: string) {
  const cfg = await arConfig();
  const c = cfg[key] ?? {};
  const text =
    `${AR_LABELS[key] ?? key}\n\n` +
    `Pool Points por ação: <b>${fmt(Number(c.poolPoints ?? 0))}</b>\n` +
    `Pass XP por ação: <b>${fmt(Number(c.passXp ?? 0))}</b>\n` +
    `Limite diário pontuado: <b>${fmt(Number(c.poolDailyCap ?? 0))}</b>\n\n` +
    `A atividade continua funcionando normalmente após o limite — apenas deixa de gerar pontos/XP no dia.`;
  return edit(
    ctx,
    text,
    kb([
      [{ t: "🪙 POOL POINTS", d: `ar:ask:arpts_${key}` }],
      [{ t: "✨ PASS XP", d: `ar:ask:arxp_${key}` }],
      [{ t: "📅 LIMITE DIÁRIO", d: `ar:ask:arcap_${key}` }],
      [{ t: "⬅️ VOLTAR", d: "ar:hub" }],
    ]),
  );
}

async function arCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") {
    const [field, key] = [a.split("_")[0], a.split("_").slice(1).join("_")];
    const label =
      field === "arpts" ? "Pool Points por ação" : field === "arxp" ? "Pass XP por ação" : "limite diário pontuado";
    return ask(ctx, a, `⚙ ${AR_LABELS[key] ?? key}\nEnvie o novo valor para <b>${label}</b> (número inteiro ≥ 0).`);
  }
  if (sub === "item") return arItem(ctx, a);
  return arHub(ctx);
}

async function arPrompt(ctx: Ctx, sessionKey: string, text: string) {
  const field = sessionKey.split("_")[0];
  const key = sessionKey.split("_").slice(1).join("_");
  const n = Number(text.trim().replace(",", "."));
  if (!Number.isFinite(n) || n < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número inteiro ≥ 0.");
  const map: Record<string, string> = { arpts: "poolPoints", arxp: "passXp", arcap: "poolDailyCap" };
  await rpc("admin_set_activity_reward", {
    p_admin_id: ctx.adminId,
    p_activity: key,
    p_field: map[field],
    p_value: Math.floor(n),
  });
  await clearSession(ctx);
  await send(ctx, `✅ ${AR_LABELS[key] ?? key} atualizado.`);
  return arHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 🎁 GIVEAWAY POPUP
// Promotional popup shown ONCE per (player, campaign_id). Changing the campaign id
// releases a brand new popup for everyone; history in user_campaign_popup is kept.
async function gwHub(ctx: Ctx, useEdit = true) {
  const { data: rows } = await db
    .from("game_settings")
    .select("key,value")
    .in("key", ["giveaway_popup_enabled", "giveaway_popup_campaign_id", "giveaway_popup_group_url"]);
  const map = new Map((rows ?? []).map((r: any) => [r.key, r.value]));
  const enabled = map.get("giveaway_popup_enabled") !== false;
  const campaign = String(map.get("giveaway_popup_campaign_id") ?? "mythreon_giveaway_aug2026");
  const url = String(map.get("giveaway_popup_group_url") ?? "https://t.me/+sy4Y6cd7cuIyNmEx");
  const { count: shown } = await db
    .from("user_campaign_popup")
    .select("id", { count: "exact", head: true })
    .eq("campaign_id", campaign);
  const { count: joined } = await db
    .from("user_campaign_popup")
    .select("id", { count: "exact", head: true })
    .eq("campaign_id", campaign)
    .not("clicked_join_at", "is", null);
  const text =
    `🎁 <b>GIVEAWAY POPUP</b>\n` +
    `Estado: <b>${enabled ? "🟢 ATIVO" : "🔴 DESATIVADO"}</b>\n` +
    `Campanha: <code>${esc(campaign)}</code>\n` +
    `Grupo: <code>${esc(url)}</code>\n\n` +
    `Jogadores que viram: <b>${fmt(shown ?? 0)}</b>\n` +
    `Clicaram em ENTRAR NO GRUPO: <b>${fmt(joined ?? 0)}</b>\n\n` +
    `Ao trocar o <b>campaign_id</b> o popup reaparece 1× para todos (o histórico é mantido).`;
  const rows2 = [
    [{ t: enabled ? "⏸ DESATIVAR POPUP" : "▶️ ATIVAR POPUP", d: `gw:toggle:${enabled ? "0" : "1"}` }],
    [
      { t: "🆕 NOVA CAMPANHA", d: "gw:ask:gwcamp" },
      { t: "🔗 LINK DO GRUPO", d: "gw:ask:gwurl" },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows2)) : send(ctx, text, kb(rows2));
}

async function gwCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "toggle") {
    await rpc("admin_set_setting", {
      p_admin_id: ctx.adminId,
      p_key: "giveaway_popup_enabled",
      p_value: a === "1",
      p_reason: "painel admin",
    });
    await send(ctx, a === "1" ? "✅ Popup de giveaway ativado." : "✅ Popup de giveaway desativado.");
    return gwHub({ ...ctx, messageId: undefined }, false);
  }
  return gwHub(ctx);
}

async function gwPrompt(ctx: Ctx, key: string, text: string) {
  if (key === "gwcamp") {
    const value = text.trim().toLowerCase().replace(/\s+/g, "_");
    if (!/^[a-z0-9_\-]{4,120}$/.test(value))
      throw new Error(
        "KEEP_SESSION::⚠️ Use apenas letras, números, <code>_</code> e <code>-</code>. Ex.: <code>mythreon_giveaway_sep2026</code>",
      );
    await rpc("admin_set_setting", {
      p_admin_id: ctx.adminId,
      p_key: "giveaway_popup_campaign_id",
      p_value: value,
      p_reason: "painel admin",
    });
    await clearSession(ctx);
    await send(ctx, `🎁 Nova campanha: <code>${esc(value)}</code>\nTodos os jogadores verão o popup uma vez.`);
    return gwHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "gwurl") {
    const value = text.trim();
    if (!/^https:\/\/t\.me\/\S+$/.test(value))
      throw new Error(
        "KEEP_SESSION::⚠️ Envie um link válido do Telegram. Ex.: <code>https://t.me/+sy4Y6cd7cuIyNmEx</code>",
      );
    await rpc("admin_set_setting", {
      p_admin_id: ctx.adminId,
      p_key: "giveaway_popup_group_url",
      p_value: value,
      p_reason: "painel admin",
    });
    await clearSession(ctx);
    await send(ctx, `🎁 Link do grupo atualizado.`);
    return gwHub({ ...ctx, messageId: undefined }, false);
  }
  return gwHub(ctx);
}

// ---------------------------------------------------------------- 🗺 PET EXPEDITIONS (extra attempts)
// Every counter is per (player, MISSION, game day): the ads limit and the FC-purchase limit
// are independent and NEVER global. Values below are editable without a deploy.
const XE_RARITIES = ["common", "uncommon", "rare", "epic", "legendary"] as const;

async function xeSetting(key: string, fallback: number) {
  const { data } = await db.from("game_settings").select("value").eq("key", key).maybeSingle();
  const value = Number((data as { value?: unknown } | null)?.value ?? NaN);
  return Number.isFinite(value) ? value : fallback;
}

async function xeHub(ctx: Ctx, useEdit = true) {
  const [ads, fc, free] = await Promise.all([
    xeSetting("expedition_max_ads_per_day", 5),
    xeSetting("expedition_max_fc_purchases_per_day", 5),
    xeSetting("expedition_free_attempts_per_day", 1),
  ]);
  const defaults: Record<string, number> = {
    common: 10000,
    uncommon: 10000,
    rare: 50000,
    epic: 100000,
    legendary: 200000,
  };
  const prices: string[] = [];
  for (const rarity of XE_RARITIES) {
    const price = await xeSetting(`expedition_extra_price_fc_${rarity}`, defaults[rarity]);
    prices.push(`• <b>${rarity.toUpperCase()}</b> ${fmt(price)} FC`);
  }
  const text =
    `🗺 <b>PET EXPEDITIONS · TENTATIVAS EXTRAS</b>\n` +
    `Os limites são <b>por missão</b> (não globais) e zeram no reset diário oficial.\n\n` +
    `Tentativas gratuitas por missão/dia: <b>${fmt(free)}</b>\n` +
    `Máx. ANÚNCIOS por missão/dia: <b>${fmt(ads)}</b>\n` +
    `Máx. COMPRAS FC por missão/dia: <b>${fmt(fc)}</b>\n\n` +
    `<b>PREÇO DA TENTATIVA EXTRA (FC)</b>\n${prices.join("\n")}`;
  const rows = [
    [
      { t: "📺 MÁX. ADS/MISSÃO", d: "xe:ask:xeads" },
      { t: "🪙 MÁX. FC/MISSÃO", d: "xe:ask:xefc" },
    ],
    [
      { t: "🎟 TENTATIVAS GRATUITAS", d: "xe:ask:xefree" },
      { t: "💲 PREÇO FC", d: "xe:ask:xeprice" },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function xeCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  return xeHub(ctx);
}

async function xePrompt(ctx: Ctx, key: string, text: string) {
  const setNum = async (settingKey: string, value: number, label: string) => {
    await rpc("admin_set_setting", {
      p_admin_id: ctx.adminId,
      p_key: settingKey,
      p_value: value,
      p_reason: "painel admin",
    });
    await clearSession(ctx);
    await send(ctx, `🗺 ${label}: <b>${fmt(value)}</b>`);
    return xeHub({ ...ctx, messageId: undefined }, false);
  };
  switch (key) {
    case "xeads": {
      const value = Math.trunc(Number(text.replace(/[^\d]/g, "")));
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número inteiro. Ex.: <code>5</code>");
      return setNum("expedition_max_ads_per_day", value, "Máx. anúncios por missão/dia");
    }
    case "xefc": {
      const value = Math.trunc(Number(text.replace(/[^\d]/g, "")));
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número inteiro. Ex.: <code>5</code>");
      return setNum("expedition_max_fc_purchases_per_day", value, "Máx. compras FC por missão/dia");
    }
    case "xefree": {
      const value = Math.trunc(Number(text.replace(/[^\d]/g, "")));
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número inteiro. Ex.: <code>1</code>");
      return setNum("expedition_free_attempts_per_day", value, "Tentativas gratuitas por missão/dia");
    }
    case "xeprice": {
      const [rarityRaw, priceRaw] = text.trim().split(/\s+/);
      const rarity = String(rarityRaw ?? "").toLowerCase();
      const value = Math.trunc(Number(String(priceRaw ?? "").replace(/[^\d]/g, "")));
      if (!XE_RARITIES.includes(rarity as (typeof XE_RARITIES)[number]) || !Number.isFinite(value) || value < 0) {
        throw new Error("KEEP_SESSION::⚠️ Envie <code>raridade preço_fc</code>. Ex.: <code>epic 100000</code>");
      }
      return setNum(`expedition_extra_price_fc_${rarity}`, value, `Preço extra ${rarity.toUpperCase()}`);
    }
    default:
      return xeHub(ctx);
  }
}

// ---------------------------------------------------------------- #️⃣ MISSION: ADD #MYTHREON TO YOUR TELEGRAM NAME
// The reward is only paid by the game API after the server itself reads the player's
// current Telegram display name (Bot API getChat, fallback: signed initData).
// Here the admin controls ON/OFF, the hashtag, the reward and can audit any player.
const nmRpc = (ctx: Ctx, action: string, payload: Record<string, unknown> = {}) =>
  rpc("admin_name_mission", { p_admin_id: ctx.adminId, p_action: action, p_payload: payload });

const nmTagFound = (name: string, hashtag: string) => {
  const tag = String(hashtag || "#Mythreon")
    .replace(/^#+/, "")
    .toLowerCase();
  if (!tag) return false;
  return new RegExp(
    `(^|[^\\p{L}\\p{N}_])#${tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}([^\\p{L}\\p{N}_]|$)`,
    "iu",
  ).test(String(name || ""));
};

async function nmHub(ctx: Ctx, useEdit = true) {
  const d = (await nmRpc(ctx, "overview")) as any;
  const claims =
    arr<any>(d.claims)
      .map(
        (c) =>
          `• ${String(c.verifiedAt).slice(5, 16).replace("T", " ")} · <code>${c.telegramId}</code> ${esc(c.name)} · ${fmt(c.rewardAmount)} FC ${c.source === "bot_api" ? "🤖" : "🔐"}`,
      )
      .join("\n") || "— nenhum resgate ainda —";
  const text =
    `#️⃣ <b>MISSÃO #MYTHREON NO NOME</b>\n` +
    `Estado: <b>${d.enabled ? "🟢 ATIVA" : "🔴 DESATIVADA"}</b>\n` +
    `Hashtag exigida: <b>${esc(d.hashtag)}</b> (case-insensitive, token exato)\n` +
    `Recompensa: <b>${fmt(d.rewardFc)} FC</b> · limite <b>1 resgate por jogador</b>\n` +
    `Resgates: <b>${fmt(d.totalClaims)}</b> · pago ${fmt(d.totalPaidFc)} FC\n\n` +
    `A validação é feita no servidor com o nome REAL do Telegram (first_name + last_name). O nome do perfil do jogo nunca é aceito como prova.\n\n` +
    `<b>ÚLTIMOS RESGATES</b>\n${claims}`;
  const rows = [
    [{ t: d.enabled ? "⛔ DESATIVAR" : "✅ ATIVAR", d: `nm:toggle:${d.enabled ? "0" : "1"}` }],
    [
      { t: "💰 DEFINIR RECOMPENSA", d: "nm:ask:nmreward" },
      { t: "#️⃣ HASHTAG", d: "nm:ask:nmtag" },
    ],
    [
      { t: "📜 RESGATES", d: "nm:claims" },
      { t: "👤 VERIFICAR USUÁRIO", d: "nm:ask:nmuser" },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function nmClaims(ctx: Ctx) {
  const d = (await nmRpc(ctx, "overview")) as any;
  const lines =
    arr<any>(d.claims)
      .map(
        (c) =>
          `• <code>${c.telegramId}</code> ${esc(c.name)}\n   ${String(c.verifiedAt).slice(0, 16).replace("T", " ")} · ${fmt(c.rewardAmount)} FC · fonte ${c.source === "bot_api" ? "Bot API" : "initData"}`,
      )
      .join("\n") || "— nenhum resgate ainda —";
  return edit(
    ctx,
    `📜 <b>RESGATES DA MISSÃO #MYTHREON</b> (${fmt(d.totalClaims)})\n${lines.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "nm:claims" }], nav("nm:hub")]),
  );
}

/** Read-only audit: shows the CURRENT Telegram name and the claim status. Never pays. */
async function nmVerifyUser(ctx: Ctx, ref: string, useEdit = true) {
  const d = (await nmRpc(ctx, "lookup", { ref })) as any;
  const chat = await tgAs(GAME_BOT_TOKEN, "getChat", { chat_id: d.telegramId ?? ref.replace(/^@/, "") });
  const result = (chat as any)?.result ?? null;
  const liveName = result
    ? [result.first_name ?? "", result.last_name ?? ""].join(" ").replace(/\s+/g, " ").trim()
    : "";
  const found = liveName ? nmTagFound(liveName, d.hashtag) : null;
  const text =
    `#️⃣ <b>VERIFICAR USUÁRIO</b>\n` +
    `Telegram ID: <code>${d.telegramId ?? "—"}</code>\n` +
    `Jogador: <b>${esc(d.playerName ?? "—")}</b>${d.username ? ` (@${esc(d.username)})` : ""}\n` +
    `Nome atual no Telegram: <b>${esc(liveName || "— indisponível (bot não vê este usuário) —")}</b>\n` +
    `${esc(d.hashtag)}: <b>${found === null ? "— não foi possível consultar —" : found ? "YES ✅" : "NO ❌"}</b>\n` +
    `Missão: <b>${d.claimed ? "CLAIMED ✅" : "NOT CLAIMED"}</b>${d.claimed ? `\nNome no resgate: ${esc(d.verifiedName)}\nRecompensa: ${fmt(d.rewardAmount)} FC · ${String(d.claimedAt).slice(0, 16).replace("T", " ")}` : ""}\n\n` +
    `Consulta somente leitura — nenhuma recompensa é paga aqui.`;
  const rows = [[{ t: "👤 OUTRO USUÁRIO", d: "nm:ask:nmuser" }], nav("nm:hub")];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function nmCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  switch (sub) {
    case "ask":
      return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
    case "claims":
      return nmClaims(ctx);
    case "toggle": {
      await nmRpc(ctx, a === "1" ? "enable" : "disable");
      await send(ctx, a === "1" ? "✅ Missão #Mythreon <b>ATIVADA</b>." : "⛔ Missão #Mythreon <b>DESATIVADA</b>.");
      return nmHub({ ...ctx, messageId: undefined }, false);
    }
    default:
      return nmHub(ctx);
  }
}

async function nmPrompt(ctx: Ctx, key: string, text: string) {
  switch (key) {
    case "nmreward": {
      const value = Math.round(
        Number(
          text
            .replace(/[^\d.,-]/g, "")
            .replace(/\./g, "")
            .replace(",", "."),
        ),
      );
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie a recompensa em FC. Ex.: <code>50000</code>");
      await nmRpc(ctx, "set_reward", { rewardFc: value });
      await clearSession(ctx);
      await send(ctx, `#️⃣ Recompensa da missão definida em <b>${fmt(value)} FC</b>.`);
      return nmHub({ ...ctx, messageId: undefined }, false);
    }
    case "nmtag": {
      const tag = text.trim().replace(/\s+/g, "");
      if (!/^#?[\p{L}\p{N}_]{3,24}$/u.test(tag))
        throw new Error("KEEP_SESSION::⚠️ Envie uma hashtag válida. Ex.: <code>#Mythreon</code>");
      await nmRpc(ctx, "set_hashtag", { hashtag: tag });
      await clearSession(ctx);
      await send(ctx, `#️⃣ Hashtag exigida agora é <b>${esc(tag.startsWith("#") ? tag : "#" + tag)}</b>.`);
      return nmHub({ ...ctx, messageId: undefined }, false);
    }
    case "nmuser": {
      const ref = text.trim();
      if (!ref) throw new Error("KEEP_SESSION::⚠️ Envie o Telegram ID, @usuário ou nome do jogador.");
      await clearSession(ctx);
      return nmVerifyUser({ ...ctx, messageId: undefined }, ref, false);
    }
    default:
      return nmHub({ ...ctx, messageId: undefined }, false);
  }
}

// ---------------------------------------------------------------- ⛏ NFT MINING (master admin only)
// Passive generation driven by hero RARITY / NFT rate. The ACTIVE CURRENCY (TON or MYTH)
// is global, lives in the database and is applied without deploy: only one currency
// accrues at a time and switching settles the previous window at now().
const hmTon = (v: unknown) =>
  Number(v ?? 0)
    .toFixed(6)
    .replace(/0+$/, "")
    .replace(/\.$/, "") || "0";
const hmMyth = (v: unknown) => Number(v ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 4 });

async function hmHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_hero_mining_overview", { p_admin_id: ctx.adminId })) as any;
  const isMyth = String(d.currency ?? "ton") === "myth";
  const pool = (d.mythPool ?? {}) as any;
  const rates =
    arr<any>(d.rates)
      .map((r) => `• <b>${esc(String(r.rarity).toUpperCase())}</b> ${hmTon(r.tonPerDay)} TON/dia`)
      .join("\n") || "sem taxas";
  const claims =
    arr<any>(d.claims)
      .slice(0, 8)
      .map((c) => {
        const amount =
          String(c.currency ?? "ton") === "myth" ? `${hmMyth(c.amountMyth)} MYTH` : `${hmTon(c.amountTon)} TON`;
        return `• ${String(c.createdAt).slice(0, 16).replace("T", " ")} · ${amount} · ${esc(String(c.name ?? "—"))} <code>${c.telegramId}</code>`;
      })
      .join("\n") || "sem coletas";
  const text =
    `⛏ <b>NFT MINING</b>\n` +
    `STATUS: <b>${d.enabled ? "🟢 ACTIVE" : "🔴 PAUSED"}</b>\n` +
    `CURRENCY: <b>${isMyth ? "🪙 MYTH" : "💎 TON"}</b>\n` +
    `DAILY RATE: <b>${isMyth ? `${hmMyth(d.mythPerDay)} MYTH` : `${hmTon(arr<any>(d.rates).find((r) => r.rarity === "legendary")?.tonPerDay ?? 0)} TON`}</b>\n` +
    `Trocada em: ${d.currencyChangedAt ? String(d.currencyChangedAt).slice(0, 16).replace("T", " ") : "—"}\n` +
    `Resgate mínimo: ${isMyth ? `${hmMyth(d.minClaimMyth)} MYTH` : `${hmTon(d.minClaimTon)} TON`}\n\n` +
    `<b>TAXAS TON POR RARIDADE</b> (define a elegibilidade)\n${rates}\n\n` +
    `Heróis minerando: <b>${fmt(d.eligibleHeroes)}</b> · pausados (mercado): ${fmt(d.pausedHeroes)}\n` +
    `<b>MYTH MINING POOL</b>\nAllocated ${hmMyth(pool.allocated)} · Distributed ${hmMyth(pool.distributed)} · Available <b>${hmMyth(pool.available)}</b>\n` +
    `MYTH não coletado: ${hmMyth(d.unclaimedMyth)}\n\n` +
    `<b>TON POOL</b>\nProdução da rede: <b>${hmTon(d.networkDailyTon)} TON/dia</b>\n` +
    `Acumulado não coletado: ${hmTon(d.unclaimedTon)} TON\n` +
    `Coletado 24h: ${hmTon(d.claimedTon24h)} TON · total ${hmTon(d.claimedTon)} TON\n` +
    `<b>LIMITE ROI</b> · investido ${hmTon(d.investedTon)} TON · devolvido ${hmTon(d.returnedTon)} TON\n` +
    `Investidores: <b>${fmt(d.investorsCount)}</b> · no limite: ${fmt(d.capReachedPlayers)}\n\n` +
    `<b>ÚLTIMAS COLETAS</b>\n${claims}`;
  const rows = [
    [{ t: isMyth ? "💎 MUDAR PARA TON" : "🪙 MUDAR PARA MYTH", d: `hm:cur:${isMyth ? "ton" : "myth"}` }],
    [{ t: "⛏ SET DAILY MINING", d: "hm:ask:hmdaily" }],
    [
      { t: "🪙 MYTH POOL", d: "hm:ask:hmpool" },
      { t: "🪙 MÍNIMO MYTH", d: "hm:ask:hmminmyth" },
    ],
    [
      { t: "⚙️ ALTERAR TAXA TON", d: "hm:ask:hmrate" },
      { t: "💠 MÍNIMO TON", d: "hm:ask:hmmin" },
    ],
    [{ t: "💜 RARE HERO MYTH MINING", d: "hm:rare" }],
    [{ t: "📜 MINING HISTORY", d: "hm:hist" }],
    [{ t: d.enabled ? "⏸ PAUSAR MINERAÇÃO" : "▶️ ATIVAR MINERAÇÃO", d: `hm:toggle:${d.enabled ? "0" : "1"}` }],
    [{ t: "👤 CONSULTAR JOGADOR", d: "hm:ask:hmuser" }],
    [{ t: "💠 AJUSTAR LIMITE DO JOGADOR", d: "hm:ask:hmlimit" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

/** Mining ledger: TON and MYTH accruals/claims and every currency switch. */
async function hmHistory(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_nft_mining_history", { p_admin_id: ctx.adminId, p_limit: 15 })) as any;
  const lines =
    arr<any>(d.entries)
      .map((e) => {
        const when = String(e.createdAt).slice(0, 16).replace("T", " ");
        if (e.entryType === "NFT_MINING_CURRENCY_CHANGED") {
          const m = (e.meta ?? {}) as any;
          return `• ${when} · 🔁 <b>${String(m.previousCurrency ?? "—").toUpperCase()} ${m.oldDailyValue ?? 0}</b> → <b>${String(m.newCurrency ?? "—").toUpperCase()} ${m.newDailyValue ?? 0}</b>`;
        }
        const amount = e.currency === "myth" ? `${hmMyth(e.amount)} MYTH` : `${hmTon(e.amount)} TON`;
        return `• ${when} · ${esc(String(e.entryType))} · ${amount}${e.telegramId ? ` · <code>${e.telegramId}</code>` : ""}`;
      })
      .join("\n") || "sem registros";
  const text = `📜 <b>MINING HISTORY</b>\n\n${lines}`;
  const rows = [[{ t: "🔄 ATUALIZAR", d: "hm:hist" }], nav("hm:hub")];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function hmUserCard(ctx: Ctx, ref: string, useEdit = true) {
  const d = (await rpc("admin_hero_mining_user", { p_admin_id: ctx.adminId, p_ref: ref })) as any;
  const byRarity =
    arr<any>(d.byRarity)
      .map((r) => `• ${esc(String(r.rarity).toUpperCase())} ×${fmt(r.count)} → ${hmTon(r.tonPerDay)} TON/dia`)
      .join("\n") || "nenhum herói";
  const text =
    `⛏ <b>MINERAÇÃO DO JOGADOR</b>\n👤 ${esc(String(d.name ?? "—"))} <code>${d.telegramId}</code>\n\n` +
    `Taxa: <b>${hmTon(d.dailyRateTon)} TON/dia</b> (${fmt(d.eligibleHeroes)} heróis, ${fmt(d.pausedHeroes)} pausados)\n` +
    `Não coletado: <b>${hmTon(d.unclaimedTon)} TON</b>\n` +
    `Total minerado: ${hmTon(d.lifetimeTon)} TON\n` +
    `Investido (TON elegível): <b>${hmTon(d.investedTon)} TON</b>\n` +
    `Devolvido pela mineração: ${hmTon(d.returnedTon)} TON\n` +
    `Capacidade restante: <b>${hmTon(d.remainingTon)} TON</b>${Number(d.investedTon ?? 0) > 0 && Number(d.remainingTon ?? 0) <= 0 ? " ⛔ LIMITE ATINGIDO" : ""}\n` +
    `Saldo TON sacável: ${hmTon(d.availableTon)} TON\n` +
    `Última coleta: ${d.lastClaimAt ? String(d.lastClaimAt).slice(0, 16).replace("T", " ") : "—"}\n\n${byRarity}`;
  const rows = [
    [{ t: "💠 AJUSTAR LIMITE", d: "hm:ask:hmlimit" }],
    [{ t: "👤 OUTRO JOGADOR", d: "hm:ask:hmuser" }],
    nav("hm:hub"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

// ---------------------------------------------------------------- 💜 RARE HERO MYTH MINING
// Rare heroes mine MYTH as a PROPORTIONAL SLICE of a fixed global daily budget, with
// diminishing returns per rare count and a per-player hard cap. Nothing is minted:
// every reward is paid from the pre-allocated MYTH MINING POOL.
async function rmHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_rare_myth_mining_overview", { p_admin_id: ctx.adminId })) as any;
  const pool = (d.pool ?? {}) as any;
  const tiers = arr<any>(d.tiers)
    .map((t) => `• <b>${esc(String(t.label))}</b> raros → ${Math.round(Number(t.weight ?? 0) * 100)}% do peso`)
    .join("\n");
  const top =
    arr<any>(d.topMiners)
      .map(
        (m) =>
          `• ${esc(String(m.name ?? "—"))} <code>${m.telegramId}</code> · ${fmt(m.rareCount)} raros · ${m.units} un · <b>${hmMyth(m.emitted)} MYTH</b>`,
      )
      .join("\n") || "sem emissão hoje";
  const text =
    `💜 <b>RARE HERO MYTH MINING</b>\n` +
    `STATUS: <b>${d.enabled ? "🟢 ACTIVE" : "🔴 PAUSED"}</b>\n` +
    `GLOBAL DAILY BUDGET: <b>${hmMyth(d.dailyBudgetMyth)} MYTH</b>\n` +
    `PLAYER DAILY CAP: <b>${hmMyth(d.playerDailyCapMyth)} MYTH</b>\n` +
    `Resgate mínimo: ${hmMyth(d.minClaimMyth)} MYTH\n\n` +
    `<b>DIMINISHING RETURNS</b>\n${tiers}\n\n` +
    `<b>SNAPSHOT DE HOJE</b>\nMineradores: <b>${fmt(d.miners)}</b> · unidades efetivas globais: <b>${hmMyth(d.globalUnits)}</b>\n` +
    `Emitido hoje: <b>${hmMyth(d.emittedToday)} MYTH</b> · 7d ${hmMyth(d.emitted7d)} · 30d ${hmMyth(d.emitted30d)}\n` +
    `Não coletado: ${hmMyth(d.unclaimedMyth)} MYTH\n\n` +
    `<b>REWARD POOL</b>\nAllocated ${hmMyth(pool.allocated)} · Distributed ${hmMyth(pool.distributed)} · Available <b>${hmMyth(pool.available)}</b>\n` +
    `<i>Nenhum MYTH é criado: a emissão sai da reserva dentro do supply de 100M.</i>\n\n` +
    `<b>TOP MINERS (hoje)</b>\n${top}`;
  const rows = [
    [{ t: "🎯 DAILY BUDGET", d: "hm:ask:rmbudget" }],
    [
      { t: "🛡 PLAYER DAILY CAP", d: "hm:ask:rmcap" },
      { t: "🪙 MÍNIMO MYTH", d: "hm:ask:rmmin" },
    ],
    [{ t: "📉 ALTERAR TIER %", d: "hm:ask:rmtier" }],
    [{ t: "➕ ADD ALLOCATION À POOL", d: "hm:ask:rmpool" }],
    [{ t: d.enabled ? "⏸ PAUSAR RARE MINING" : "▶️ ATIVAR RARE MINING", d: `hm:rtoggle:${d.enabled ? "0" : "1"}` }],
    [{ t: "🔄 ATUALIZAR", d: "hm:rare" }],
    nav("hm:hub"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function rmPrompt(ctx: Ctx, key: string, text: string) {
  const num = (raw: string) => Number(String(raw).replace(/[.\s]/g, "").replace(",", ".").trim());
  switch (key) {
    case "rmbudget":
    case "rmcap":
    case "rmmin": {
      const value = num(text);
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número válido em MYTH. Ex.: <code>10000</code>");
      const field = key === "rmbudget" ? "budget" : key === "rmcap" ? "playercap" : "minclaim";
      await rpc("admin_rare_myth_mining_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
      await clearSession(ctx);
      await send(ctx, `💜 Atualizado: <b>${hmMyth(value)} MYTH</b>.`);
      return rmHub({ ...ctx, messageId: undefined }, false);
    }
    case "rmtier": {
      const [tier, raw] = text.trim().split(/\s+/);
      const value = Number(String(raw ?? "").replace(",", "."));
      const map: Record<string, string> = { "1": "tier1", "2": "tier2", "3": "tier3", "4": "tier4" };
      const field = map[String(tier ?? "").trim()];
      if (!field || !Number.isFinite(value) || value < 0 || value > 100)
        throw new Error("KEEP_SESSION::⚠️ Envie <code>tier porcentagem</code>. Ex.: <code>2 25</code>");
      await rpc("admin_rare_myth_mining_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
      await clearSession(ctx);
      await send(ctx, `📉 TIER ${tier} definido em <b>${value}%</b> do peso.`);
      return rmHub({ ...ctx, messageId: undefined }, false);
    }
    case "rmpool": {
      const value = num(text);
      if (!Number.isFinite(value) || value <= 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número válido em MYTH. Ex.: <code>1000000</code>");
      await rpc("admin_rare_myth_pool_add", { p_admin_id: ctx.adminId, p_amount: value });
      await clearSession(ctx);
      await send(ctx, `➕ Alocação adicionada: <b>${hmMyth(value)} MYTH</b> na reserva de mineração.`);
      return rmHub({ ...ctx, messageId: undefined }, false);
    }
    default:
      return rmHub({ ...ctx, messageId: undefined }, false);
  }
}

// ---------------------------------------------------------------- 💎 TON STAKING
// Internal TON locked for a period. Rates, lock terms, limits, reward pool and the
// circuit breaker all live in the database, so changes take effect with no deploy.
const tsTon = (v: unknown) => Number(v ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 4 });

async function tsHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_ton_staking_overview", { p_admin_id: ctx.adminId })) as any;
  const plans = arr<any>(d.plans)
    .map(
      (p) =>
        `• <code>${esc(String(p.code))}</code> <b>${esc(String(p.name))}</b> · ${p.lockDays}d · ${tsTon(p.effective)}%/mês ` +
        `(base ${tsTon(p.monthlyRate)} + bônus ${tsTon(p.bonusRate)}) · em stake ${tsTon(p.staked)} TON · ${p.enabled ? "🟢" : "🔴"}`,
    )
    .join("\n") || "nenhum plano";
  const top = arr<any>(d.topStakers)
    .map((o) => `• ${esc(String(o.name ?? "—"))} <code>${o.telegramId}</code> · ${tsTon(o.stakedTon)} TON · ${fmt(o.positions)} posições`)
    .join("\n") || "nenhum staker ainda";
  const text =
    `💎 <b>TON STAKING</b>\n` +
    `STATUS: <b>${d.enabled ? (d.paused ? "⏸ NOVOS STAKES PAUSADOS" : "🟢 ATIVO") : "🔴 DESATIVADO"}</b>\n` +
    `Stake: mín <b>${tsTon(d.minStakeTon)}</b> · máx <b>${tsTon(d.maxStakeTon)}</b> TON (0 = livre)\n` +
    `Auto-staking mín: <b>${tsTon(d.autoStakeMinTon)} TON</b> · mês = <b>${d.monthDays} dias</b>\n` +
    `Compound: ${d.autoCompoundAllowed ? "🟢" : "🔴"} · Saque antecipado: ${d.earlyUnstakeAllowed ? `🟢 (penalidade ${tsTon(d.earlyUnstakePenaltyPercent)}%)` : "🔴"}\n` +
    `Rende após vencer: ${d.accrueAfterMaturity ? "🟢" : "🔴"}\n\n` +
    `<b>ECONOMIA</b>\n` +
    `Em stake: <b>${tsTon(d.totalStakedTon)} TON</b> · ${fmt(d.positions)} posições · ${fmt(d.stakers)} jogadores\n` +
    `Saída mensal: <b>${tsTon(d.monthlyPayoutTon)} TON/mês</b>\n` +
    `Pendente: ${tsTon(d.outstandingTon)} TON · pago: ${tsTon(d.claimedTon)} TON\n` +
    `Reward pool: <b>${tsTon(d.rewardPoolTotal)}</b> TON · disponível <b>${tsTon(d.poolAvailable)}</b> · reserva mín ${tsTon(d.rewardPoolMinAvailable)}\n` +
    `Compromisso total (liability): <b>${tsTon(d.liability)} TON</b>\n` +
    `Circuit breaker: ${d.poolGateEnabled ? "🟢 LIGADO" : "🔴 DESLIGADO"}\n\n` +
    `<b>PLANOS</b>\n${plans}\n\n<b>TOP STAKERS</b>\n${top}`;
  const rows = [
    [{ t: "📈 TAXA DO PLANO", d: "ts:ask:tskrate" }, { t: "🎁 BÔNUS DO PLANO", d: "ts:ask:tskbonus" }],
    [{ t: "🔒 DIAS DE BLOQUEIO", d: "ts:ask:tsklock" }, { t: "🔁 ATIVAR/DESATIVAR PLANO", d: "ts:ask:tsktoggle" }],
    [{ t: "💎 STAKE MÍNIMO", d: "ts:ask:tskmin" }, { t: "💎 STAKE MÁXIMO", d: "ts:ask:tskmax" }],
    [{ t: "⛏ AUTO-STAKE MÍNIMO", d: "ts:ask:tskautomin" }, { t: "🗓 DIAS POR MÊS", d: "ts:ask:tskmonth" }],
    [{ t: "🪙 REWARD POOL", d: "ts:ask:tskpool" }, { t: "🛡 RESERVA MÍNIMA", d: "ts:ask:tskpoolmin" }],
    [{ t: "⚠️ PENALIDADE ANTECIPADA", d: "ts:ask:tskpenalty" },
     { t: d.earlyUnstakeAllowed ? "🔒 BLOQUEAR SAQUE ANTECIPADO" : "🔓 PERMITIR SAQUE ANTECIPADO", d: `ts:flag:early:${d.earlyUnstakeAllowed ? "0" : "1"}` }],
    [{ t: d.autoCompoundAllowed ? "🔴 DESLIGAR COMPOUND" : "🟢 LIGAR COMPOUND", d: `ts:flag:compound:${d.autoCompoundAllowed ? "0" : "1"}` },
     { t: d.accrueAfterMaturity ? "⏹ PARAR APÓS VENCER" : "▶️ RENDER APÓS VENCER", d: `ts:flag:aftermaturity:${d.accrueAfterMaturity ? "0" : "1"}` }],
    [{ t: d.poolGateEnabled ? "🔴 DESLIGAR CIRCUIT BREAKER" : "🟢 LIGAR CIRCUIT BREAKER", d: `ts:flag:poolgate:${d.poolGateEnabled ? "0" : "1"}` }],
    [{ t: d.paused ? "▶️ LIBERAR NOVOS STAKES" : "⏸ PAUSAR NOVOS STAKES", d: `ts:flag:paused:${d.paused ? "0" : "1"}` }],
    [{ t: d.enabled ? "🔴 DESATIVAR SISTEMA" : "🟢 ATIVAR SISTEMA", d: `ts:flag:enabled:${d.enabled ? "0" : "1"}` }],
    [{ t: "🔄 ATUALIZAR", d: "ts:hub" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function tsPrompt(ctx: Ctx, key: string, text: string) {
  const num = (raw: string) => Number(String(raw).replace(/\s/g, "").replace(",", "."));
  const pair = () => {
    const [code, ...rest] = text.trim().split(/\s+/);
    const value = rest.join(" ").trim();
    if (!code || !value) throw new Error("KEEP_SESSION::⚠️ Envie <code>plano valor</code>. Ex.: <code>d30 1.2</code>");
    return { code, value };
  };
  const planFields: Record<string, string> = { tskrate: "rate", tskbonus: "bonus", tsklock: "lock", tsktoggle: "enabled" };
  if (planFields[key]) {
    const { code, value } = pair();
    const normalized = key === "tsktoggle" ? (/^(on|1|true|sim)$/i.test(value) ? "1" : "0") : value;
    await rpc("admin_ton_staking_plan_set", { p_admin_id: ctx.adminId, p_code: code, p_field: planFields[key], p_value: normalized });
    await clearSession(ctx);
    await send(ctx, `💎 Plano <code>${esc(code)}</code> atualizado.`);
    return tsHub({ ...ctx, messageId: undefined }, false);
  }
  const fields: Record<string, string> = {
    tskmin: "min", tskmax: "max", tskautomin: "automin", tskpool: "pool",
    tskpoolmin: "poolmin", tskpenalty: "penalty", tskmonth: "monthdays",
  };
  const field = fields[key];
  if (!field) return tsHub({ ...ctx, messageId: undefined }, false);
  const value = num(text);
  if (!Number.isFinite(value) || value < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido. Ex.: <code>10</code>");
  await rpc("admin_ton_staking_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
  await clearSession(ctx);
  await send(ctx, `✅ TON STAKING atualizado: <b>${value}</b>.`);
  return tsHub({ ...ctx, messageId: undefined }, false);
}

async function tsCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "flag") {
    try {
      await rpc("admin_ton_staking_flag", { p_admin_id: ctx.adminId, p_field: a, p_value: b === "1" });
    } catch (err) {
      console.error("[admin-bot] ton_staking_flag failed", err);
      await send(ctx, "⚠️ Não foi possível alterar o TON STAKING.");
    }
    return tsHub({ ...ctx, messageId: undefined }, false);
  }
  return tsHub(ctx);
}

// ---------------------------------------------------------------- ⛏ MINAS DE TON
// Passive TON investment. Every value (price, daily yield, storage, loyalty bonus,
// limits and who can even see the building) is controlled here in real time.
const tmTon = (v: unknown) => Number(v ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 4 });

async function tmHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_ton_mines_overview", { p_admin_id: ctx.adminId })) as any;
  const mines =
    arr<any>(d.mines)
      .map(
        (m) =>
          `• <b>${esc(String(m.name))}</b> <code>${esc(String(m.key))}</code>\n` +
          `   ${tmTon(m.priceTon)} TON · ${tmTon(m.dailyTon)} TON/dia · ROI ${m.roiDays ?? "—"}d · armazena ${m.storageDays}d · limite ${m.maxPerPlayer}\n` +
          `   vendidas: <b>${fmt(m.sold)}</b> · ${m.enabled ? (m.paused ? "⏸ pausada" : "🟢 ativa") : "🔴 oculta"}`,
      )
      .join("\n") || "nenhuma mina cadastrada";
  const top =
    arr<any>(d.topOwners)
      .map(
        (o) =>
          `• ${esc(String(o.name ?? "—"))} <code>${o.telegramId}</code> · ${fmt(o.mines)} minas · investiu <b>${tmTon(o.investedTon)} TON</b> · ${tmTon(o.dailyTon)}/dia`,
      )
      .join("\n") || "nenhum investidor ainda";
  const allowed = arr<any>(d.allowedIds).map((id) => `<code>${id}</code>`).join(", ") || "—";
  const text =
    `⛏ <b>MINAS DE TON</b>\n` +
    `STATUS: <b>${d.enabled ? (d.paused ? "⏸ PAUSADO" : "🟢 ATIVO") : "🔴 DESATIVADO"}</b>\n` +
    `VISIBILIDADE: <b>${d.adminOnly ? "🔒 APENAS IDS LIBERADOS" : "🌍 TODOS OS JOGADORES"}</b>\n` +
    `IDs liberados: ${allowed}\n` +
    `Limite total por jogador: <b>${fmt(d.maxTotalPerPlayer)}</b>\n` +
    `Fidelidade: ${d.loyaltyEnabled ? `🟢 +${d.bonus30}% (30d) / +${d.bonus60}% (60d)` : "🔴 desligada"}\n\n` +
    `<b>ECONOMIA</b>\n` +
    `Minas ativas: <b>${fmt(d.activeMines)}</b> · vendas: <b>${tmTon(d.salesTon)} TON</b>\n` +
    `Saída diária: <b>${tmTon(d.dailyTon)} TON/dia</b> · projeção 30d: <b>${tmTon(d.projection30Ton)} TON</b>\n` +
    `Gerado total: ${tmTon(d.generatedTon)} TON (coletado ${tmTon(d.claimedTon)} · pendente ${tmTon(d.unclaimedTon)})\n\n` +
    `<b>CATÁLOGO</b>\n${mines}\n\n` +
    `<b>TOP INVESTIDORES</b>\n${top}`;
  const rows = [
    [
      { t: "💰 PREÇO DA MINA", d: "tm:ask:tmprice" },
      { t: "⛏ RENDIMENTO/DIA", d: "tm:ask:tmdaily" },
    ],
    [
      { t: "📦 DIAS DE ARMAZENAMENTO", d: "tm:ask:tmstore" },
      { t: "🔢 LIMITE POR JOGADOR", d: "tm:ask:tmmaxper" },
    ],
    [
      { t: "✏️ NOME", d: "tm:ask:tmname" },
      { t: "📝 DESCRIÇÃO", d: "tm:ask:tmdesc" },
    ],
    [
      { t: "🖼 IMAGEM", d: "tm:ask:tmimage" },
      { t: "🔁 ATIVAR/OCULTAR MINA", d: "tm:ask:tmtoggle" },
    ],
    [{ t: "➕ CRIAR NOVA MINA", d: "tm:ask:tmcreate" }],
    [
      { t: "🎁 BÔNUS 30 DIAS", d: "tm:ask:tmbonus30" },
      { t: "🎁 BÔNUS 60 DIAS", d: "tm:ask:tmbonus60" },
    ],
    [
      { t: "🔢 LIMITE TOTAL", d: "tm:ask:tmmaxtotal" },
      { t: d.loyaltyEnabled ? "⏸ DESLIGAR FIDELIDADE" : "▶️ LIGAR FIDELIDADE", d: `tm:flag:loyalty:${d.loyaltyEnabled ? "0" : "1"}` },
    ],
    [
      { t: "➕ LIBERAR ID", d: "tm:ask:tmallow" },
      { t: "➖ REMOVER ID", d: "tm:ask:tmdeny" },
    ],
    [{ t: d.adminOnly ? "🌍 LIBERAR PARA TODOS" : "🔒 RESTRINGIR AOS IDS", d: `tm:flag:adminonly:${d.adminOnly ? "0" : "1"}` }],
    [{ t: d.paused ? "▶️ RETOMAR MINAS" : "⏸ PAUSAR MINAS", d: `tm:flag:paused:${d.paused ? "0" : "1"}` }],
    [{ t: d.enabled ? "🔴 DESATIVAR SISTEMA" : "🟢 ATIVAR SISTEMA", d: `tm:flag:enabled:${d.enabled ? "0" : "1"}` }],
    [{ t: "🔄 ATUALIZAR", d: "tm:hub" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function tmPrompt(ctx: Ctx, key: string, text: string) {
  const num = (raw: string) => Number(String(raw).replace(/\s/g, "").replace(",", "."));
  /** Per-mine edits always arrive as `chave valor`. */
  const pair = () => {
    const [mineKey, ...rest] = text.trim().split(/\s+/);
    const value = rest.join(" ").trim();
    if (!mineKey || !value) throw new Error("KEEP_SESSION::⚠️ Envie <code>chave valor</code>. Ex.: <code>iron 5</code>");
    return { mineKey, value };
  };
  const fieldMap: Record<string, string> = {
    tmprice: "price",
    tmdaily: "daily",
    tmstore: "storage",
    tmmaxper: "maxper",
    tmname: "name",
    tmdesc: "desc",
    tmimage: "image",
    tmtoggle: "enabled",
  };

  if (fieldMap[key]) {
    const { mineKey, value } = pair();
    await rpc("admin_ton_mine_set", { p_admin_id: ctx.adminId, p_key: mineKey, p_field: fieldMap[key], p_value: value });
    await clearSession(ctx);
    await send(ctx, `⛏ Mina <code>${esc(mineKey)}</code> atualizada.`);
    return tmHub({ ...ctx, messageId: undefined }, false);
  }

  switch (key) {
    case "tmcreate": {
      const { mineKey, value } = pair();
      await rpc("admin_ton_mine_set", { p_admin_id: ctx.adminId, p_key: mineKey, p_field: "create", p_value: value });
      await clearSession(ctx);
      await send(ctx, `➕ Mina criada: <b>${esc(value)}</b> (<code>${esc(mineKey)}</code>). Defina preço e rendimento.`);
      return tmHub({ ...ctx, messageId: undefined }, false);
    }
    case "tmbonus30":
    case "tmbonus60":
    case "tmmaxtotal": {
      const value = num(text);
      if (!Number.isFinite(value) || value < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido. Ex.: <code>10</code>");
      const field = key === "tmbonus30" ? "bonus30" : key === "tmbonus60" ? "bonus60" : "maxtotal";
      await rpc("admin_ton_mines_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
      await clearSession(ctx);
      await send(ctx, `✅ Atualizado: <b>${value}</b>.`);
      return tmHub({ ...ctx, messageId: undefined }, false);
    }
    case "tmallow":
    case "tmdeny": {
      const id = Number(String(text).replace(/\D/g, ""));
      if (!Number.isFinite(id) || id <= 0) throw new Error("KEEP_SESSION::⚠️ Envie um Telegram ID numérico. Ex.: <code>8118569391</code>");
      await rpc("admin_ton_mines_allow", { p_admin_id: ctx.adminId, p_telegram_id: id, p_add: key === "tmallow" });
      await clearSession(ctx);
      await send(ctx, key === "tmallow" ? `➕ ID <code>${id}</code> liberado.` : `➖ ID <code>${id}</code> removido.`);
      return tmHub({ ...ctx, messageId: undefined }, false);
    }
    default:
      return tmHub({ ...ctx, messageId: undefined }, false);
  }
}

async function tmCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "flag") {
    try {
      await rpc("admin_ton_mines_flag", { p_admin_id: ctx.adminId, p_field: a, p_value: b === "1" });
    } catch (err) {
      console.error("[admin-bot] ton_mines_flag failed", err);
      await send(ctx, "⚠️ Não foi possível alterar as MINAS DE TON.");
    }
    return tmHub({ ...ctx, messageId: undefined }, false);
  }
  return tmHub(ctx);
}



async function hmCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  switch (sub) {
    case "ask":
      return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
    case "toggle": {
      const next = a === "1";
      try {
        await rpc("admin_hero_mining_toggle", { p_admin_id: ctx.adminId, p_enabled: next });
      } catch (err) {
        console.error("[admin-bot] hero_mining_toggle failed", err);
        await send(ctx, "⚠️ Não foi possível alterar o status da mineração.");
        return hmHub({ ...ctx, messageId: undefined }, false);
      }
      await send(
        ctx,
        next
          ? "✅ Mineração de heróis ativada.\n🟢 <b>MINERAÇÃO ATIVA</b>"
          : "✅ Mineração de heróis pausada.\n🔴 <b>MINERAÇÃO PAUSADA</b>",
      );
      return hmHub({ ...ctx, messageId: undefined }, false);
    }

    case "rare":
      return rmHub(ctx);
    case "rtoggle": {
      const next = a === "1";
      try {
        await rpc("admin_rare_myth_mining_toggle", { p_admin_id: ctx.adminId, p_enabled: next });
      } catch (err) {
        console.error("[admin-bot] rare_myth_mining_toggle failed", err);
        await send(ctx, "⚠️ Não foi possível alterar o RARE HERO MYTH MINING.");
        return rmHub({ ...ctx, messageId: undefined }, false);
      }
      await send(ctx, next ? "✅ RARE HERO MYTH MINING ativado." : "⏸ RARE HERO MYTH MINING pausado.");
      return rmHub({ ...ctx, messageId: undefined }, false);
    }
    case "hist":
      return hmHistory(ctx);
    // Currency switch: the RPC settles the previous currency at now() and only then flips,
    // so TON and MYTH never overlap and old rewards are preserved in their own currency.
    case "cur": {
      const next = a === "myth" ? "myth" : "ton";
      try {
        await rpc("admin_hero_mining_set_currency", { p_admin_id: ctx.adminId, p_currency: next, p_daily: null });
      } catch (err) {
        console.error("[admin-bot] hero_mining_set_currency failed", err);
        await send(ctx, "⚠️ Não foi possível alterar a moeda da mineração.");
        return hmHub({ ...ctx, messageId: undefined }, false);
      }
      await send(
        ctx,
        next === "myth"
          ? "✅ Mineração dos NFTs agora paga <b>🪙 MYTH</b>.\nO acúmulo em TON foi encerrado neste instante e os TON já acumulados foram preservados."
          : "✅ Mineração dos NFTs agora paga <b>💎 TON</b>.\nO acúmulo em MYTH foi encerrado neste instante e o MYTH já acumulado foi preservado.",
      );
      return hmHub({ ...ctx, messageId: undefined }, false);
    }

    default:
      return hmHub(ctx);
  }
}

async function hmPrompt(ctx: Ctx, key: string, text: string) {
  switch (key) {
    case "hmrate": {
      const [rarity, raw] = text.trim().split(/\s+/);
      const value = Number(String(raw ?? "").replace(",", "."));
      if (!rarity || !Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie <code>raridade ton_por_dia</code>. Ex.: <code>mythic 0.5</code>");
      // Common/Uncommon are permanently out of hero mining (server-side gate).
      if (["common", "uncommon"].includes(rarity.toLowerCase())) {
        throw new Error(
          "KEEP_SESSION::🚫 COMMON e UNCOMMON não mineram TON. Apenas RARE, EPIC, LEGENDARY, MYTHIC e ANCESTRAL.",
        );
      }
      await rpc("admin_hero_mining_set_rate", {
        p_admin_id: ctx.adminId,
        p_rarity: rarity.toLowerCase(),
        p_ton_per_day: value,
      });
      await clearSession(ctx);
      await send(ctx, `⛏ Taxa de <b>${esc(rarity.toUpperCase())}</b> definida em <b>${hmTon(value)} TON/dia</b>.`);
      return hmHub({ ...ctx, messageId: undefined }, false);
    }
    case "hmmin": {
      const value = Number(text.replace(",", ".").trim());
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número válido em TON. Ex.: <code>0.01</code>");
      await rpc("admin_hero_mining_set_min_claim", { p_admin_id: ctx.adminId, p_min_ton: value });
      await clearSession(ctx);
      await send(ctx, `⛏ Resgate mínimo da mineração: <b>${hmTon(value)} TON</b>.`);
      return hmHub({ ...ctx, messageId: undefined }, false);
    }
    // DAILY MINING in the ACTIVE currency: no automatic TON→MYTH conversion is ever applied.
    case "hmdaily": {
      const value = Number(text.replace(",", ".").trim());
      if (!Number.isFinite(value) || value < 0)
        throw new Error(
          "KEEP_SESSION::⚠️ Envie um número válido. Ex.: <code>500</code> (MYTH) ou <code>0.2</code> (TON)",
        );
      const overview = (await rpc("admin_hero_mining_overview", { p_admin_id: ctx.adminId })) as any;
      const currency = String(overview.currency ?? "ton");
      if (currency === "myth") {
        await rpc("admin_hero_mining_set_myth_rate", { p_admin_id: ctx.adminId, p_myth_per_day: value });
      } else {
        await rpc("admin_hero_mining_set_currency", { p_admin_id: ctx.adminId, p_currency: "ton", p_daily: value });
      }
      await clearSession(ctx);
      await send(
        ctx,
        `⛏ DAILY MINING: <b>${currency === "myth" ? `${hmMyth(value)} MYTH` : `${hmTon(value)} TON`}</b>.`,
      );
      return hmHub({ ...ctx, messageId: undefined }, false);
    }
    case "hmminmyth": {
      const value = Number(text.replace(",", ".").trim());
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número válido em MYTH. Ex.: <code>100</code>");
      await rpc("admin_hero_mining_set_min_claim_myth", { p_admin_id: ctx.adminId, p_min_myth: value });
      await clearSession(ctx);
      await send(ctx, `🪙 Resgate mínimo em MYTH: <b>${hmMyth(value)} MYTH</b>.`);
      return hmHub({ ...ctx, messageId: undefined }, false);
    }
    case "hmpool": {
      const value = Number(text.replace(/[.\s]/g, "").replace(",", ".").trim());
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número válido em MYTH. Ex.: <code>5000000</code>");
      await rpc("admin_myth_mining_pool_set", { p_admin_id: ctx.adminId, p_allocated: value });
      await clearSession(ctx);
      await send(
        ctx,
        `🪙 MYTH MINING POOL alocada: <b>${hmMyth(value)} MYTH</b>.\n<i>A mineração MYTH só distribui tokens dessa reserva — nada é criado além do supply oficial.</i>`,
      );
      return hmHub({ ...ctx, messageId: undefined }, false);
    }

    case "hmuser": {
      const ref = text.trim();
      if (!ref) throw new Error("KEEP_SESSION::⚠️ Envie o Telegram ID, @usuário ou nome do jogador.");
      await clearSession(ctx);
      return hmUserCard({ ...ctx, messageId: undefined }, ref, false);
    }
    case "hmlimit": {
      const parts = text.trim().split(/\s+/);
      const raw = parts.pop() ?? "";
      const ref = parts.join(" ").trim();
      const value = Number(String(raw).replace(",", "."));
      if (!ref || !Number.isFinite(value) || value < 0) {
        throw new Error(
          "KEEP_SESSION::⚠️ Envie <code>ID_ou_@usuario limite_ton</code>. Ex.: <code>5925045925 5</code>",
        );
      }
      await rpc("admin_hero_mining_set_limit", { p_admin_id: ctx.adminId, p_ref: ref, p_amount_ton: value });
      await clearSession(ctx);
      await send(
        ctx,
        value > 0
          ? `⛏ Limite de mineração ajustado para <b>${hmTon(value)} TON</b>.\n🟢 Mineração ativa para esse jogador.`
          : "⛏ Limite de mineração zerado.\n🔴 Mineração desativada para esse jogador.",
      );
      return hmUserCard({ ...ctx, messageId: undefined }, ref, false);
    }
    default:
      return hmHub({ ...ctx, messageId: undefined }, false);
  }
}

// ---------------------------------------------------------------- 🪙 MYTH TOKEN (decorativo)
// Supply fixo inicial de 100.000.000 MYTH, 100% na reserva do Admin Bot.
// Sem preço, sem mercado, sem saque e sem qualquer conversão com FC ou TON.
const mythFmt = (n: unknown) => Number(n ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 4 });

async function mythHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_myth_overview", { p_admin_id: ctx.adminId })) as any;
  const recent = (d.recent ?? []) as any[];
  const label: Record<string, string> = { credit: "➕", debit: "➖", supply: "🧮" };
  const text = [
    `🪙 <b>${esc(d.name)}</b> (${esc(d.symbol)})`,
    "<i>Decorativo · Coming Soon · sem preço, sem trade, sem saque</i>",
    "",
    `<b>Total Supply:</b> ${mythFmt(d.totalSupply)} ${esc(d.symbol)}`,
    `<b>Admin Reserve:</b> ${mythFmt(d.adminReserve)} ${esc(d.symbol)}`,
    `<b>Com jogadores:</b> ${mythFmt(d.playerHeld)} · 👥 ${fmt(d.holders)} holder(s)`,
    `<b>Visível no jogo:</b> ${d.visible ? "✅ SIM" : "⛔ NÃO"}`,
    "",
    `<b>ÚLTIMOS LANÇAMENTOS</b>\n${recent.map((r) => `${label[r.direction] ?? "•"} ${mythFmt(r.amount)} — ${esc(r.player ?? "—")}${r.telegram_id ? ` (<code>${r.telegram_id}</code>)` : ""}`).join("\n") || "nenhum lançamento ainda"}`,
  ].join("\n");
  const rows = [
    [
      { t: "➕ ADICIONAR A JOGADOR", d: "my:ask:mythadd" },
      { t: "➖ REMOVER DE JOGADOR", d: "my:ask:mythsub" },
    ],
    [{ t: "🔎 VER SALDO DE JOGADOR", d: "my:ask:mythsee" }],
    [
      { t: "🧮 AJUSTAR SUPPLY", d: "my:ask:mythsupply" },
      { t: "✏️ RENOMEAR TOKEN", d: "my:ask:mythname" },
    ],
    [{ t: d.visible ? "⛔ OCULTAR NO JOGO" : "✅ MOSTRAR NO JOGO", d: `my:vis:${d.visible ? 0 : 1}` }],
    [{ t: "🪙 MYTH TOKEN SALE", d: "ms:hub" }],
    [{ t: "🔒 MYTH STAKING", d: "stk:hub" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function mythCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "vis") {
    await rpc("admin_myth_set_visibility", { p_admin_id: ctx.adminId, p_visible: a === "1" });
    return mythHub(ctx);
  }
  return mythHub(ctx);
}

// ---------------------------------------------------------------- 🔒 MYTH STAKING (interno)
// Staking do ecossistema Mythreon: MYTH -> MYTH, sem smart contract e sem criar supply.
// Toda recompensa sai do REWARD POOL reservado; ligar/desligar aqui vale na hora, sem deploy.
async function stakingHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_myth_staking_overview", { p_admin_id: ctx.adminId })) as any;
  const plans = (d.plans ?? []) as any[];
  const text = [
    "🔒 <b>MYTH STAKING</b>",
    "<i>Mythreon Ecosystem Staking · interno · MYTH → MYTH</i>",
    "",
    `STATUS: <b>${d.enabled ? "✅ ACTIVE" : "⛔ OFF (Coming Soon)"}</b>`,
    `NOVOS STAKES: <b>${d.newStakesPaused ? "⏸ PAUSADOS" : "▶️ LIBERADOS"}</b> · RESGATES: <b>${d.claimsEnabled ? "✅ ON" : "⛔ OFF"}</b>`,
    `MÍNIMO: <b>${mythFmt(d.minStake)} MYTH</b> · MÁXIMO: <b>${Number(d.maxStake) > 0 ? `${mythFmt(d.maxStake)} MYTH` : "sem limite"}</b>`,
    "",
    `TOTAL STAKED: <b>${mythFmt(d.totalStaked)} MYTH</b> · STAKERS: <b>${fmt(d.stakers)}</b>`,
    `REWARD POOL: <b>${mythFmt(d.rewardPoolTotal)} MYTH</b>`,
    `DISPONÍVEL: <b>${mythFmt(d.rewardPoolAvailable)}</b> · PAGO: <b>${mythFmt(d.rewardPoolDistributed)}</b>`,
    `PENDENTE (acumulado): <b>${mythFmt(d.pendingRewards)} MYTH</b>`,
    "",
    "<b>PLANOS</b>",
    plans
      .map(
        (p) =>
          `${p.active ? "✅" : "⛔"} ${esc(p.label)} — APR ${Number(p.aprPercent) > 0 ? `${p.aprPercent}%` : "--"} · lock ${p.lockDays}d`,
      )
      .join("\n") || "nenhum plano",
  ].join("\n");
  const rows = [
    [{ t: d.enabled ? "⛔ DESLIGAR STAKING" : "✅ LIGAR STAKING", d: `stk:set:enabled:${d.enabled ? 0 : 1}` }],
    [
      {
        t: d.newStakesPaused ? "▶️ LIBERAR NOVOS STAKES" : "⏸ PAUSAR NOVOS STAKES",
        d: `stk:set:pause:${d.newStakesPaused ? 0 : 1}`,
      },
    ],
    [
      {
        t: d.claimsEnabled ? "⛔ BLOQUEAR RESGATES" : "✅ LIBERAR RESGATES",
        d: `stk:set:claims:${d.claimsEnabled ? 0 : 1}`,
      },
    ],
    [
      { t: "🪙 REWARD POOL", d: "stk:ask:stkpool" },
      { t: "📈 APR DO PLANO", d: "stk:ask:stkapr" },
    ],
    [
      { t: "🔒 STAKE MÍNIMO", d: "stk:ask:stkmin" },
      { t: "🔒 STAKE MÁXIMO", d: "stk:ask:stkmax" },
    ],
    ...plans.map((p) => [
      { t: `${p.active ? "⛔ DESATIVAR" : "✅ ATIVAR"} ${p.label}`, d: `stk:plan:${p.code}:${p.active ? 0 : 1}` },
    ]),
    [{ t: "🔄 ATUALIZAR", d: "stk:hub" }],
    nav("my:hub"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function stakingCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "set") {
    await rpc("admin_myth_staking_set", { p_admin_id: ctx.adminId, p_field: a, p_value: Number(b) });
    return stakingHub(ctx);
  }
  if (sub === "plan") {
    await rpc("admin_myth_staking_plan_set", { p_admin_id: ctx.adminId, p_code: a, p_apr: null, p_active: b === "1" });
    return stakingHub(ctx);
  }
  return stakingHub(ctx);
}

async function stakingPrompt(ctx: Ctx, key: string, text: string) {
  if (key === "stkapr") {
    const [code, raw] = text.trim().split(/\s+/);
    const apr = Number(String(raw ?? "").replace(",", "."));
    if (!code || !Number.isFinite(apr) || apr < 0)
      throw new Error("KEEP_SESSION::⚠️ Envie <code>plano APR</code>. Ex.: <code>d30 18</code>");
    await rpc("admin_myth_staking_plan_set", { p_admin_id: ctx.adminId, p_code: code, p_apr: apr, p_active: null });
    await clearSession(ctx);
    await send(ctx, `📈 APR do plano <b>${esc(code)}</b>: <b>${apr}%</b>.`);
    return stakingHub({ ...ctx, messageId: undefined }, false);
  }
  const value = Number(text.replace(",", ".").trim());
  if (!Number.isFinite(value) || value < 0)
    throw new Error("KEEP_SESSION::⚠️ Envie um número válido em MYTH. Ex.: <code>5000000</code>");
  const field = key === "stkmin" ? "min" : key === "stkmax" ? "max" : "pool";
  await rpc("admin_myth_staking_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
  await clearSession(ctx);
  await send(ctx, `🔒 MYTH STAKING atualizado: <b>${mythFmt(value)} MYTH</b>.`);
  return stakingHub({ ...ctx, messageId: undefined }, false);
}

async function mythPrompt(ctx: Ctx, key: string, text: string) {
  if (key === "mythadd" || key === "mythsub") {
    const parts = text.trim().split(/\s+/);
    const raw = parts.pop() ?? "";
    const ref = parts.join(" ").trim();
    const value = parseAmount(raw);
    if (!ref || !Number.isFinite(value) || value <= 0) {
      throw new Error(
        "KEEP_SESSION::⚠️ Envie <code>ID_ou_@usuario quantidade</code>. Ex.: <code>5925045925 1000</code>",
      );
    }
    const signed = key === "mythadd" ? value : -value;
    const r = (await rpc("admin_myth_adjust", { p_admin_id: ctx.adminId, p_ref: ref, p_amount: signed })) as any;
    await clearSession(ctx);
    await send(
      ctx,
      `🪙 ${key === "mythadd" ? "➕ Adicionado" : "➖ Removido"} <b>${mythFmt(value)} MYTH</b>\n👤 ${esc(r.name)} (<code>${r.telegramId}</code>)\n💠 Novo saldo: <b>${mythFmt(r.balance)} MYTH</b>`,
    );
    return mythHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "mythsee") {
    const ref = text.trim();
    if (!ref) throw new Error("KEEP_SESSION::⚠️ Envie o Telegram ID, @usuário ou nome.");
    const r = (await rpc("admin_myth_player", { p_admin_id: ctx.adminId, p_ref: ref })) as any;
    await clearSession(ctx);
    await send(
      ctx,
      `🪙 <b>SALDO MYTH</b>\n👤 ${esc(r.name)} (<code>${r.telegramId}</code>)\n💠 <b>${mythFmt(r.balance)} MYTH</b>`,
    );
    return mythHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "mythsupply") {
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0)
      throw new Error("KEEP_SESSION::⚠️ Envie um número válido. Ex.: <code>100000000</code>");
    await rpc("admin_myth_set_supply", { p_admin_id: ctx.adminId, p_total: value });
    await clearSession(ctx);
    await send(ctx, `🪙 Supply total definido em <b>${mythFmt(value)} MYTH</b>.`);
    return mythHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "mythname") {
    const [name, symbol] = text.split("|").map((x) => x.trim());
    if (!name)
      throw new Error("KEEP_SESSION::⚠️ Envie <code>Nome | SIMBOLO</code>. Ex.: <code>MYTH Token | MYTH</code>");
    await rpc("admin_myth_rename", { p_admin_id: ctx.adminId, p_name: name, p_symbol: symbol ?? null });
    await clearSession(ctx);
    await send(ctx, `🪙 Token renomeado para <b>${esc(name)}</b>${symbol ? ` (${esc(symbol.toUpperCase())})` : ""}.`);
    return mythHub({ ...ctx, messageId: undefined }, false);
  }
  return mythHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 🐾 FAMILIAR HUNT (progressão linear)
// Modo de caçada linear dos pets: ON/OFF, custos (FC / TON), curvas de dificuldade e loot tables
// vivem em `familiar_hunt_settings`. O bot só configura — todo loot é sorteado no servidor.
async function fhHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_familiar_hunt_overview", {})) as any;
  const diff = d.difficulty ?? {};
  const recent = (d.recent ?? []) as any[];
  const stages = (d.topStages ?? []) as any[];
  const rewards = (d.rewardsDistributed ?? []) as any[];
  const text = [
    "🐾 <b>FAMILIAR HUNT</b>",
    "<i>Progressão linear · 1 estágio por vez · loot 100% server-side</i>",
    "",
    `<b>Status:</b> ${d.enabled ? "✅ ATIVO" : "⛔ DESATIVADO"} · <b>Loot v</b>${fmt(d.lootTableVersion)}`,
    `<b>Entrada:</b> ⚔ ${fmt(d.entryFc)} FC · 💎 ${fmt(d.entryTon)} TON`,
    `<b>Dificuldade:</b> HP ${fmt(diff.hp_base ?? 0)} (x${esc(String(diff.hp_growth ?? "—"))}) · ATK ${fmt(diff.atk_base ?? 0)} (x${esc(String(diff.atk_growth ?? "—"))}) · BOSS a cada ${fmt(diff.boss_every ?? 0)} (x${esc(String(diff.boss_mult ?? "—"))})`,
    "",
    `<b>Caçadas:</b> ${fmt(d.runs)} (24h: ${fmt(d.runs24h)}) · <b>Vitórias:</b> ${fmt(d.wins)}`,
    `<b>FC gasto:</b> ${fmt(d.fcSpent)} · <b>TON pago:</b> ${fmt(d.tonPaid)} (externo ${fmt(d.tonExternal)})`,
    `<b>Pendentes:</b> pagamento ${fmt(d.pendingPayments)} · caçada ${fmt(d.paidPendingHunt)}`,
    "",
    `<b>JOGADORES POR ESTÁGIO</b>\n${stages.map((s) => `• Stage ${fmt(s.stage)} — ${fmt(s.players)} jogador(es)`).join("\n") || "sem progresso ainda"}`,
    "",
    `<b>LOOT ENTREGUE</b>\n${rewards.map((r) => `• ${esc(r.type ?? "—")} — ${fmt(r.times)}x (total ${fmt(r.total)})`).join("\n") || "nenhum loot ainda"}`,
    "",
    `<b>ÚLTIMAS CAÇADAS</b>\n${recent.map((r) => `• Stage ${fmt(r.stage)} ${r.victory ? "✅" : "❌"} — ${esc(r.username ?? "—")} (<code>${r.telegram_id}</code>) · ${fmt(r.amount)} ${esc(String(r.currency ?? "").toUpperCase())}`).join("\n") || "nenhuma caçada ainda"}`,
  ].join("\n");
  const rows = [
    [{ t: d.enabled ? "⛔ DESATIVAR MODO" : "✅ ATIVAR MODO", d: `fh:on:${d.enabled ? 0 : 1}` }],
    [
      { t: "⚔ CUSTO FC", d: "fh:ask:fhfc" },
      { t: "💎 CUSTO TON", d: "fh:ask:fhton" },
    ],
    [{ t: "📈 DIFICULDADE (JSON)", d: "fh:ask:fhdiff" }],
    [
      { t: "🎁 LOOT FC", d: "fh:ask:fhfcloot" },
      { t: "💠 LOOT TON", d: "fh:ask:fhtonloot" },
    ],
    [{ t: "🗺 STAGE POOL (JSON)", d: "fh:ask:fhpool" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function fhCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "on") await rpc("admin_familiar_hunt_set", { p_key: "enabled", p_value: a });
  return fhHub(ctx);
}

const FH_FIELDS: Record<string, string> = {
  fhfc: "entry_fc",
  fhton: "entry_ton",
  fhdiff: "difficulty",
  fhfcloot: "fc_loot",
  fhtonloot: "ton_loot",
  fhpool: "stage_pool",
};

async function fhPrompt(ctx: Ctx, key: string, text: string) {
  const field = FH_FIELDS[key];
  if (!field) return fhHub({ ...ctx, messageId: undefined }, false);
  let value = text.trim();
  if (field === "entry_fc" || field === "entry_ton") {
    const num = field === "entry_ton" ? Number(value.replace(",", ".").replace(/[^\d.]/g, "")) : parseAmount(value);
    if (!Number.isFinite(num) || num < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    value = String(num);
  } else {
    try {
      JSON.parse(value);
    } catch {
      throw new Error("KEEP_SESSION::⚠️ JSON inválido. Envie um JSON válido.");
    }
  }
  await rpc("admin_familiar_hunt_set", { p_key: field, p_value: value });
  await clearSession(ctx);
  await send(ctx, `🐾 Familiar Hunt atualizado: <b>${esc(field)}</b> = <code>${esc(value)}</code>`);
  return fhHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 👑 MYTHREON FOUNDER PACK (25 TON)

// Pacote único para contas novas. Preço, janela, conteúdo e cosméticos vivem no banco:
// tudo aqui é leitura/escrita de configuração — nenhuma recompensa é entregue pelo bot.
async function fpHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_founder_pack_overview", { p_admin_id: ctx.adminId })) as any;
  const recent = (d.recent ?? []) as any[];
  const rc = d.resourceChest ?? {};
  const text = [
    "👑 <b>MYTHREON FOUNDER PACK</b>",
    "<i>Exclusivo para contas novas · 1 compra por conta · entrega automática</i>",
    "",
    `<b>Status:</b> ${d.enabled ? "✅ ATIVO" : "⛔ DESATIVADO"} · <b>Versão:</b> v${fmt(d.packVersion)}`,
    `<b>Preço:</b> ${fmt(d.priceTon)} TON · <b>Janela:</b> ${fmt(d.eligibilityDays)} dia(s)`,
    "",
    `🎟 Passe: <b>${esc(String(d.passTier).toUpperCase())}</b>`,
    `🪙 MYTH: <b>${mythFmt(d.mythAmount)}</b> · 💎 Fragmentos: <b>${fmt(d.fragments)}</b>`,
    `⚔️ Herói: <code>${esc(d.heroKey ?? "—")}</code> · 🐲 Pet: <code>${esc(d.petSlug ?? "—")}</code>`,
    `🗝 Baú equip.: <code>${esc(d.equipmentChestCode ?? "—")}</code>`,
    `📦 Baú Premium: ${fmt(rc.fc)} FC · ${fmt(rc.fragments)} frag · ${fmt(rc.pvp_tickets)} tickets${rc.hero_chest ? ` · ${esc(rc.hero_chest)} x${fmt(rc.hero_chest_qty)}` : ""}`,
    `👑 Badge: ${d.badgeEnabled ? "✅" : "⛔"} · 🖼 Moldura: ${d.frameEnabled ? "✅" : "⛔"}`,
    "",
    `<b>Vendas:</b> ${fmt(d.purchases)} · <b>TON arrecadado:</b> ${fmt(d.tonRaised)}`,
    `<b>Intents ativos:</b> ${fmt(d.activeIntents)} · <b>expirados:</b> ${fmt(d.failedIntents)}`,
    "",
    `<b>ÚLTIMAS COMPRAS</b>\n${recent.map((r) => `• ${esc(r.player ?? "—")} (<code>${r.telegramId}</code>) — ${fmt(r.priceTon)} TON · ${esc(r.method ?? "—")} · ${esc(r.status)}`).join("\n") || "nenhuma compra ainda"}`,
  ].join("\n");
  const rows = [
    [{ t: d.enabled ? "⛔ DESATIVAR PACOTE" : "✅ ATIVAR PACOTE", d: `fp:on:${d.enabled ? 0 : 1}` }],
    [
      { t: "💎 PREÇO (TON)", d: "fp:ask:fpprice" },
      { t: "📅 JANELA (DIAS)", d: "fp:ask:fpdays" },
    ],
    [
      { t: "🪙 MYTH", d: "fp:ask:fpmyth" },
      { t: "💎 FRAGMENTOS", d: "fp:ask:fpfrag" },
    ],
    [
      { t: "⚔️ HERÓI", d: "fp:ask:fphero" },
      { t: "🐲 PET", d: "fp:ask:fppet" },
    ],
    [
      { t: "🗝 BAÚ EQUIP.", d: "fp:ask:fpchest" },
      { t: "📦 BAÚ PREMIUM", d: "fp:ask:fpresource" },
    ],
    [
      {
        t: `🎟 PASSE: ${String(d.passTier).toUpperCase()}`,
        d: `fp:pass:${d.passTier === "legendary" ? "adventurer" : "legendary"}`,
      },
    ],
    [
      { t: d.badgeEnabled ? "👑 BADGE ON" : "👑 BADGE OFF", d: `fp:badge:${d.badgeEnabled ? 0 : 1}` },
      { t: d.frameEnabled ? "🖼 MOLDURA ON" : "🖼 MOLDURA OFF", d: `fp:frame:${d.frameEnabled ? 0 : 1}` },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function fpCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "on") await rpc("admin_founder_pack_set", { p_admin_id: ctx.adminId, p_field: "enabled", p_value: a });
  if (sub === "pass") await rpc("admin_founder_pack_set", { p_admin_id: ctx.adminId, p_field: "pass", p_value: a });
  if (sub === "badge") await rpc("admin_founder_pack_set", { p_admin_id: ctx.adminId, p_field: "badge", p_value: a });
  if (sub === "frame") await rpc("admin_founder_pack_set", { p_admin_id: ctx.adminId, p_field: "frame", p_value: a });
  return fpHub(ctx);
}

const FP_FIELDS: Record<string, string> = {
  fpprice: "price",
  fpdays: "days",
  fpmyth: "myth",
  fpfrag: "fragments",
  fphero: "hero",
  fppet: "pet",
  fpchest: "chest",
  fpresource: "resource",
};

async function fpPrompt(ctx: Ctx, key: string, text: string) {
  const field = FP_FIELDS[key];
  if (!field) return fpHub({ ...ctx, messageId: undefined }, false);
  let value = text.trim();
  if (["price", "days", "myth", "fragments"].includes(field)) {
    const num = field === "price" ? Number(value.replace(",", ".").replace(/[^\d.]/g, "")) : parseAmount(value);
    if (!Number.isFinite(num) || num <= 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    value = String(num);
  }
  if (field === "resource") {
    try {
      JSON.parse(value);
    } catch {
      throw new Error('KEEP_SESSION::⚠️ JSON inválido. Envie algo como <code>{"fc":250000,"fragments":25}</code>');
    }
  }
  await rpc("admin_founder_pack_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
  await clearSession(ctx);
  await send(ctx, `👑 Founder Pack atualizado: <b>${esc(field)}</b> = <code>${esc(value)}</code>`);
  return fpHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- ⚔️ MYTHREON VETERAN VAULT (45-day cycle)
// Oferta para jogadores ANTIGOS. Preço, idade mínima, conteúdo, cronograma de rewards e o
// financiamento dos pools (TON real / MYTH da reserva oficial) vivem no banco: o bot só configura.
// Nenhuma venda é permitida sem reserva de TON/MYTH suficiente no Veteran Reward Pool.
async function vvHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_veteran_vault_overview", { p_admin_id: ctx.adminId })) as any;
  const pool = d.pool ?? {};
  const recent = (d.recent ?? []) as any[];
  const tonSchedule = Object.entries((d.rewardSchedule?.ton ?? {}) as Record<string, unknown>)
    .sort((a, b) => Number(a[0]) - Number(b[0]))
    .map(([day, value]) => `D${day}: ${fmt(value)}`)
    .join(" · ");
  const text = [
    "⚔️ <b>MYTHREON VETERAN VAULT</b>",
    "<i>Somente jogadores antigos · 1 compra por versão · ciclo de recompensas</i>",
    "",
    `<b>Status:</b> ${d.enabled ? "✅ ATIVO" : "⛔ DESATIVADO"}${d.salesPaused ? " · ⏸ VENDAS PAUSADAS" : ""}`,
    `<b>Versão:</b> <code>${esc(String(d.vaultVersion))}</code> · <b>Preço:</b> ${fmt(d.priceTon)} TON`,
    `<b>Idade mínima:</b> ${fmt(d.minAccountAgeDays)} dia(s) · <b>Ciclo:</b> ${fmt(d.cycleDays)} dias`,
    "",
    `🎫 Passe: <b>${esc(String(d.passTier).toUpperCase())}</b> · 🪙 MYTH inicial: <b>${mythFmt(d.initialMyth)}</b>`,
    `🦸 Herói: <code>${esc(d.heroKey ?? "—")}</code> · 🐉 Pet: <code>${esc(d.petSlug ?? "—")}</code>`,
    `⚔️ Baú equip.: <code>${esc(d.equipmentChestCode ?? "—")}</code> · 💎 Frag: <b>${fmt(d.fragments)}</b> · 🎁 Baús: <b>${fmt(d.resourceChestQty)}</b>`,
    `👑 Badge: ${d.badgeEnabled ? "✅" : "⛔"} · 🖼 Moldura: ${d.frameEnabled ? "✅" : "⛔"}`,
    "",
    `<b>REWARD CYCLE</b> · TON máx/vault: <b>${fmt(d.maxTonReward)}</b> · MYTH/dia: <b>${mythFmt(d.dailyMyth)}</b>`,
    `Marcos TON: ${tonSchedule || "—"}`,
    `Reserva por venda: <b>${fmt(d.tonBudgetPerVault)} TON</b> + <b>${mythFmt(d.mythBudgetPerVault)} MYTH</b>`,
    `Valor de referência alvo: <b>${fmt(d.targetReferenceTon)} TON</b>`,
    "",
    `<b>VETERAN TON POOL</b> — financiado: ${fmt(pool.tonFunded)} · reservado: ${fmt(pool.tonReserved)} · distribuído: ${fmt(pool.tonDistributed)} · disponível: <b>${fmt(pool.tonAvailable)}</b>`,
    `<b>VETERAN MYTH POOL</b> — financiado: ${mythFmt(pool.mythFunded)} · reservado: ${mythFmt(pool.mythReserved)} · distribuído: ${mythFmt(pool.mythDistributed)} · disponível: <b>${mythFmt(pool.mythAvailable)}</b>`,
    "",
    `<b>Vaults ativos:</b> ${fmt(d.activeVaults)} · <b>concluídos:</b> ${fmt(d.completedVaults)}`,
    `<b>TON arrecadado:</b> ${fmt(d.tonRaised)} · <b>TON distribuído:</b> ${fmt(d.tonDistributed)} · <b>MYTH distribuído:</b> ${mythFmt(d.mythDistributed)}`,
    `<b>Intents ativos:</b> ${fmt(d.activeIntents)} · <b>falhos/expirados:</b> ${fmt(d.failedPayments)}`,
    "",
    `<b>ÚLTIMAS COMPRAS</b>\n${recent.map((r) => `• ${esc(r.player ?? "—")} (<code>${r.telegramId}</code>) — ${fmt(r.priceTon)} TON · ${esc(r.method ?? "—")} · ${esc(r.status)} · ${fmt(r.tonEarned)} TON / ${mythFmt(r.mythEarned)} MYTH`).join("\n") || "nenhuma compra ainda"}`,
  ].join("\n");
  const rows = [
    [
      { t: d.enabled ? "⛔ DESATIVAR VAULT" : "✅ ATIVAR VAULT", d: `vv:on:${d.enabled ? 0 : 1}` },
      { t: d.salesPaused ? "▶️ RETOMAR VENDAS" : "⏸ PAUSAR VENDAS", d: `vv:pause:${d.salesPaused ? 0 : 1}` },
    ],
    [
      { t: "💎 PREÇO (TON)", d: "vv:ask:vvprice" },
      { t: "📅 IDADE MÍNIMA", d: "vv:ask:vvage" },
    ],
    [
      { t: "🔁 CICLO (DIAS)", d: "vv:ask:vvcycle" },
      { t: "🏷 VERSÃO", d: "vv:ask:vvversion" },
    ],
    [
      { t: "🪙 MYTH INICIAL", d: "vv:ask:vvmyth" },
      { t: "💎 FRAGMENTOS", d: "vv:ask:vvfrag" },
    ],
    [
      { t: "🦸 HERÓI", d: "vv:ask:vvhero" },
      { t: "🐉 PET", d: "vv:ask:vvpet" },
    ],
    [
      { t: "⚔️ BAÚ EQUIP.", d: "vv:ask:vvchest" },
      { t: "🎁 BAÚS PREMIUM", d: "vv:ask:vvchests" },
    ],
    [
      {
        t: `🎫 PASSE: ${String(d.passTier).toUpperCase()}`,
        d: `vv:pass:${d.passTier === "legendary" ? "adventurer" : "legendary"}`,
      },
    ],
    [
      { t: "💠 TON MÁX/VAULT", d: "vv:ask:vvmaxton" },
      { t: "🪙 MYTH DIÁRIO", d: "vv:ask:vvdailymyth" },
    ],
    [
      { t: "📆 CRONOGRAMA", d: "vv:ask:vvschedule" },
      { t: "🏁 REWARD FINAL", d: "vv:ask:vvfinal" },
    ],
    [{ t: "🎯 VALOR REFERÊNCIA", d: "vv:ask:vvtarget" }],
    [
      { t: "💰 FINANCIAR TON POOL", d: "vv:ask:vvfundton" },
      { t: "🪙 FINANCIAR MYTH POOL", d: "vv:ask:vvfundmyth" },
    ],
    [
      { t: d.badgeEnabled ? "👑 BADGE ON" : "👑 BADGE OFF", d: `vv:badge:${d.badgeEnabled ? 0 : 1}` },
      { t: d.frameEnabled ? "🖼 MOLDURA ON" : "🖼 MOLDURA OFF", d: `vv:frame:${d.frameEnabled ? 0 : 1}` },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function vvCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "on") await rpc("admin_veteran_vault_set", { p_admin_id: ctx.adminId, p_field: "enabled", p_value: a });
  if (sub === "pause") await rpc("admin_veteran_vault_set", { p_admin_id: ctx.adminId, p_field: "paused", p_value: a });
  if (sub === "pass") await rpc("admin_veteran_vault_set", { p_admin_id: ctx.adminId, p_field: "pass", p_value: a });
  if (sub === "badge") await rpc("admin_veteran_vault_set", { p_admin_id: ctx.adminId, p_field: "badge", p_value: a });
  if (sub === "frame") await rpc("admin_veteran_vault_set", { p_admin_id: ctx.adminId, p_field: "frame", p_value: a });
  return vvHub(ctx);
}

const VV_FIELDS: Record<string, string> = {
  vvprice: "price",
  vvage: "age",
  vvcycle: "cycle",
  vvversion: "version",
  vvmyth: "myth",
  vvhero: "hero",
  vvpet: "pet",
  vvchest: "chest",
  vvfrag: "fragments",
  vvchests: "chests",
  vvmaxton: "maxton",
  vvdailymyth: "dailymyth",
  vvschedule: "schedule",
  vvfinal: "final",
  vvtarget: "target",
};

async function vvPrompt(ctx: Ctx, key: string, text: string) {
  const raw = text.trim();
  // Pool funding is a ledger operation, not a config field: it never touches an existing reservation.
  if (key === "vvfundton" || key === "vvfundmyth") {
    const amount = Number(raw.replace(",", ".").replace(/[^\d.-]/g, ""));
    if (!Number.isFinite(amount) || amount === 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    await rpc("admin_veteran_vault_fund", {
      p_admin_id: ctx.adminId,
      p_currency: key === "vvfundton" ? "ton" : "myth",
      p_amount: amount,
    });
    await clearSession(ctx);
    await send(
      ctx,
      `⚔️ Veteran Pool atualizado: <b>${key === "vvfundton" ? "TON" : "MYTH"}</b> ${amount > 0 ? "+" : ""}<code>${esc(String(amount))}</code>`,
    );
    return vvHub({ ...ctx, messageId: undefined }, false);
  }
  const field = VV_FIELDS[key];
  if (!field) return vvHub({ ...ctx, messageId: undefined }, false);
  let value = raw;
  if (["price", "age", "cycle", "myth", "fragments", "chests", "maxton", "dailymyth", "target"].includes(field)) {
    const num = ["price", "maxton", "target"].includes(field)
      ? Number(value.replace(",", ".").replace(/[^\d.]/g, ""))
      : parseAmount(value);
    if (!Number.isFinite(num) || num < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    value = String(num);
  }
  if (field === "schedule" || field === "final") {
    try {
      JSON.parse(value);
    } catch {
      throw new Error("KEEP_SESSION::⚠️ JSON inválido.");
    }
  }
  await rpc("admin_veteran_vault_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
  await clearSession(ctx);
  await send(ctx, `⚔️ Veteran Vault atualizado: <b>${esc(field)}</b> = <code>${esc(value)}</code>`);
  return vvHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 🔥 MYTH UTILITY (pagamento alternativo)
// Liga/desliga o pagamento em MYTH, ajusta a paridade (MYTH por TON / FC por TON), o desconto e o modo de
// preço de cada funcionalidade. Todo MYTH pago é queimado — aqui só se configura, nada é creditado.
async function muHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_myth_utility_overview", { p_admin_id: ctx.adminId })) as any;
  const feats = (d.features ?? []) as any[];
  const text = [
    "🔥 <b>MYTH UTILITY</b>",
    "<i>Pagamento alternativo em MYTH · todo valor pago é queimado (supply efetivo cai)</i>",
    "",
    `Status: ${d.enabled ? "✅ ATIVO" : "⛔ DESLIGADO"} · Burn on-chain: ${d.onchainBurnEnabled ? "🔗 ON" : "📕 só interno"}`,
    `Paridade: <b>1 TON = ${mythFmt(d.mythPerTon)} MYTH = ${fmt(d.fcPerTon)} FC</b> · <b>1 MYTH ≈ ${fmt(Number(d.fcPerTon) / Math.max(1, Number(d.mythPerTon)))} FC</b>`,
    `Desconto ao pagar em MYTH: <b>${fmt(d.discountPercent)}%</b>`,
    `Queimado por utilidade: <b>${mythFmt(d.utilityBurned)}</b> · pagantes: <b>${fmt(d.payers)}</b>`,
    "",
    "<b>FUNCIONALIDADES</b>",
    ...feats.map(
      (f) =>
        `${f.enabled ? "✅" : "⛔"} <code>${esc(f.code)}</code> · ${esc(f.label ?? "")} · modo <code>${esc(f.pricingMode)}</code>${f.customMyth ? ` (${mythFmt(f.customMyth)})` : ""} · 🔥 ${mythFmt(f.burned)}`,
    ),
  ].join("\n");
  const rows: { t: string; d: string }[][] = [
    [{ t: d.enabled ? "⛔ DESLIGAR MYTH" : "✅ LIGAR MYTH", d: `mu:set:enabled:${d.enabled ? 0 : 1}` }],
    [
      { t: "🪙 MYTH POR TON", d: "mu:ask:muton" },
      { t: "💰 FC POR TON", d: "mu:ask:mufc" },
    ],
    [
      { t: "🎯 DESCONTO (%)", d: "mu:ask:mudisc" },
      {
        t: d.onchainBurnEnabled ? "📕 BURN INTERNO" : "🔗 BURN ON-CHAIN",
        d: `mu:set:onchain:${d.onchainBurnEnabled ? 0 : 1}`,
      },
    ],
  ];
  for (const f of feats) {
    rows.push([
      {
        t: `${f.enabled ? "⛔" : "✅"} ${String(f.label ?? f.code).slice(0, 18)}`,
        d: `mu:feat:${f.code}:${f.enabled ? 0 : 1}`,
      },
      { t: `🔧 ${String(f.pricingMode).slice(0, 8)}`, d: `mu:mode:${f.code}` },
    ]);
  }
  rows.push(nav());
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

const MU_MODES = ["AUTO_FC", "AUTO_TON", "CUSTOM"];

async function muCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "set") await rpc("admin_myth_utility_set", { p_admin_id: ctx.adminId, p_field: a, p_value: b });
  if (sub === "feat")
    await rpc("admin_myth_utility_set", { p_admin_id: ctx.adminId, p_field: "feature", p_value: b, p_feature: a });
  if (sub === "mode") {
    // Rotaciona o modo de preço da funcionalidade: FC → TON → valor fixo em MYTH.
    const current = (
      ((await rpc("admin_myth_utility_overview", { p_admin_id: ctx.adminId })) as any).features ?? []
    ).find((f: any) => f.code === a);
    const next = MU_MODES[(MU_MODES.indexOf(String(current?.pricingMode ?? "AUTO_FC")) + 1) % MU_MODES.length];
    await rpc("admin_myth_utility_set", { p_admin_id: ctx.adminId, p_field: "mode", p_value: next, p_feature: a });
    if (next === "CUSTOM") return ask(ctx, `mucustom|${a}`, PROMPTS.mucustom);
  }
  return muHub(ctx);
}

async function muPrompt(ctx: Ctx, key: string, text: string) {
  const [base, feature] = key.split("|");
  const raw = text
    .trim()
    .replace(",", ".")
    .replace(/[^\d.]/g, "");
  const num = Number(raw);
  if (!Number.isFinite(num) || num < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
  if (base === "muton")
    await rpc("admin_myth_utility_set", { p_admin_id: ctx.adminId, p_field: "mythperton", p_value: String(num) });
  else if (base === "mufc")
    await rpc("admin_myth_utility_set", { p_admin_id: ctx.adminId, p_field: "fcperton", p_value: String(num) });
  else if (base === "mudisc")
    await rpc("admin_myth_utility_set", { p_admin_id: ctx.adminId, p_field: "discount", p_value: String(num) });
  else if (base === "mucustom") {
    await rpc("admin_myth_utility_set", {
      p_admin_id: ctx.adminId,
      p_field: "custom",
      p_value: num > 0 ? String(num) : "",
      p_feature: feature,
    });
    if (num <= 0)
      await rpc("admin_myth_utility_set", {
        p_admin_id: ctx.adminId,
        p_field: "mode",
        p_value: "AUTO_FC",
        p_feature: feature,
      });
  }
  await clearSession(ctx);
  await send(ctx, `🔥 MYTH Utility atualizado: <b>${esc(base)}</b> = <code>${esc(String(num))}</code>`);
  return muHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 🎁 PREMIUM OFFERS (FOUNDER + VETERAN)
// Controle unificado dos dois pacotes premium: janelas de oferta, popup diário (1x/dia por oferta no
// fuso oficial), elegibilidade global e mineração em MYTH. Nada é entregue aqui — só configuração.
async function poHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_premium_offers_overview", { p_admin_id: ctx.adminId })) as any;
  const f = d.founder ?? {};
  const v = d.veteran ?? {};
  const when = (value: unknown) => (value ? esc(String(value).slice(0, 16).replace("T", " ")) : "∞");
  const text = [
    "🎁 <b>OFERTAS PREMIUM</b>",
    "<i>Founder Pack + Veteran Vault · popup 1x por dia por oferta · mineração somente em MYTH</i>",
    "",
    `<b>Fuso do reset:</b> <code>${esc(String(d.timezone))}</code> · <b>Dia atual:</b> <code>${esc(String(d.dayKey))}</code>`,
    `<b>Fundo MYTH de mineração disponível:</b> ${mythFmt(d.mythPoolAvailable)}`,
    "",
    "👑 <b>FOUNDER PACK</b>",
    `Status: ${f.enabled ? "✅ ATIVO" : "⛔ OFF"} · Popup: ${f.popupEnabled ? "🔔 ON" : "🔕 OFF"} (<code>${esc(String(f.popupFrequency))}</code>)`,
    `Preço: <b>${fmt(f.priceTon)} TON</b> · MYTH: <b>${mythFmt(f.mythAmount)}</b> · Baús: <b>${fmt(f.legendaryChests)}</b> · Frag: <b>${fmt(f.fragments)}</b>`,
    `Arma: <code>${esc(f.weaponCode ?? "—")}</code> · ⛏ herói: <b>${mythFmt(f.heroDailyMyth)}</b>/dia · pet: <b>${mythFmt(f.petDailyMyth)}</b>/dia`,
    `Janela: ${when(f.startAt)} → ${when(f.endsAt)} · Só contas novas: ${f.requireNewAccount ? "✅" : "⛔ (todos)"}`,
    `Vendas: ${fmt(f.purchases)} · popups hoje: ${fmt(f.popupsToday)}`,
    "",
    "⚔️ <b>VETERAN VAULT</b>",
    `Status: ${v.enabled ? "✅ ATIVO" : "⛔ OFF"}${v.salesPaused ? " · ⏸ PAUSADO" : ""} · Popup: ${v.popupEnabled ? "🔔 ON" : "🔕 OFF"} (<code>${esc(String(v.popupFrequency))}</code>)`,
    `Preço: <b>${fmt(v.priceTon)} TON</b> · Bônus: <b>+${fmt(v.boostPercent)}%</b> MYTH (não vale para itens Founder)`,
    `⛏ herói: <b>${mythFmt(v.heroDailyMyth)}</b> · pet: <b>${mythFmt(v.petDailyMyth)}</b> · dragão: <b>${mythFmt(v.dragonDailyMyth)}</b> /dia`,
    `Janela: ${when(v.startAt)} → ${when(v.endsAt)}`,
    `Vendas: ${fmt(v.purchases)} · popups hoje: ${fmt(v.popupsToday)}`,
  ].join("\n");
  const rows = [
    [
      { t: f.enabled ? "👑 FOUNDER OFF" : "👑 FOUNDER ON", d: `po:set:FOUNDER_PACK:enabled:${f.enabled ? 0 : 1}` },
      {
        t: f.popupEnabled ? "🔕 POPUP FOUNDER" : "🔔 POPUP FOUNDER",
        d: `po:set:FOUNDER_PACK:popup:${f.popupEnabled ? 0 : 1}`,
      },
    ],
    [
      {
        t: f.requireNewAccount ? "🌍 LIBERAR P/ TODOS" : "🆕 SÓ CONTAS NOVAS",
        d: `po:set:FOUNDER_PACK:newaccount:${f.requireNewAccount ? 0 : 1}`,
      },
    ],
    [
      { t: "💎 PREÇO FOUNDER", d: "po:ask:pofprice" },
      { t: "🪙 MYTH FOUNDER", d: "po:ask:pofmyth" },
    ],
    [
      { t: "⛏ MYTH/DIA HERÓI", d: "po:ask:pofheromyth" },
      { t: "⛏ MYTH/DIA PET", d: "po:ask:pofpetmyth" },
    ],
    [
      { t: "🗝 BAÚS FOUNDER", d: "po:ask:pofchests" },
      { t: "🗡 ARMA FOUNDER", d: "po:ask:pofweapon" },
    ],
    [
      { t: "📅 FIM FOUNDER", d: "po:ask:pofend" },
      { t: "⛏ FUNDO MYTH FOUNDER", d: "po:ask:pofpool" },
    ],
    [
      { t: v.enabled ? "⚔️ VETERAN OFF" : "⚔️ VETERAN ON", d: `po:set:VETERAN_VAULT:enabled:${v.enabled ? 0 : 1}` },
      {
        t: v.popupEnabled ? "🔕 POPUP VETERAN" : "🔔 POPUP VETERAN",
        d: `po:set:VETERAN_VAULT:popup:${v.popupEnabled ? 0 : 1}`,
      },
    ],
    [
      { t: "💎 PREÇO VETERAN", d: "po:ask:povprice" },
      { t: "🚀 BÔNUS VETERAN (%)", d: "po:ask:povboost" },
    ],
    [
      { t: "📅 FIM VETERAN", d: "po:ask:povend" },
      { t: "⛏ FUNDO MYTH VETERAN", d: "po:ask:povpool" },
    ],
    [{ t: "🕒 FUSO DO RESET", d: "po:ask:potz" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function poCallback(ctx: Ctx, rest: string[]) {
  const [sub, offer, field, value] = rest;
  if (sub === "ask") return ask(ctx, offer, PROMPTS[offer] ?? "Envie o valor.");
  if (sub === "set")
    await rpc("admin_premium_offers_set", { p_admin_id: ctx.adminId, p_offer: offer, p_field: field, p_value: value });
  return poHub(ctx);
}

const PO_FIELDS: Record<string, [string, string]> = {
  pofprice: ["FOUNDER_PACK", "price"],
  pofmyth: ["FOUNDER_PACK", "myth"],
  pofheromyth: ["FOUNDER_PACK", "heromyth"],
  pofpetmyth: ["FOUNDER_PACK", "petmyth"],
  pofchests: ["FOUNDER_PACK", "chests"],
  pofweapon: ["FOUNDER_PACK", "weapon"],
  pofend: ["FOUNDER_PACK", "end"],
  pofpool: ["FOUNDER_PACK", "pool"],
  povprice: ["VETERAN_VAULT", "price"],
  povboost: ["VETERAN_VAULT", "boost"],
  povend: ["VETERAN_VAULT", "end"],
  povpool: ["VETERAN_VAULT", "pool"],
  potz: ["TIMEZONE", "timezone"],
};

async function poPrompt(ctx: Ctx, key: string, text: string) {
  const entry = PO_FIELDS[key];
  if (!entry) return poHub({ ...ctx, messageId: undefined }, false);
  const [offer, field] = entry;
  let value = text.trim();
  if (["price", "boost"].includes(field)) {
    const num = Number(value.replace(",", ".").replace(/[^\d.]/g, ""));
    if (!Number.isFinite(num) || num <= 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    value = String(num);
  } else if (["myth", "heromyth", "petmyth", "chests", "pool"].includes(field)) {
    const num = parseAmount(value);
    if (!Number.isFinite(num) || num < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    value = String(num);
  } else if (field === "end") {
    if (/^(0|off|nunca|never|-)$/i.test(value)) value = "";
    else if (Number.isNaN(Date.parse(value)))
      throw new Error(
        "KEEP_SESSION::⚠️ Envie uma data ISO (ex.: <code>2026-12-31T23:59:00Z</code>) ou <code>0</code> para sem prazo.",
      );
  }
  await rpc("admin_premium_offers_set", { p_admin_id: ctx.adminId, p_offer: offer, p_field: field, p_value: value });
  await clearSession(ctx);
  await send(
    ctx,
    `🎁 Ofertas premium atualizadas: <b>${esc(offer)}.${esc(field)}</b> = <code>${esc(value || "∞")}</code>`,
  );
  return poHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- ⚔️ VETERAN VAULT (pacote premium 100 TON)
// Linha Veteran (herói, pet, dragão, ovo, armas), mineração SOMENTE em MYTH e bônus de +X% para quem compra.
// Preço, taxas, conteúdo e o fundo de MYTH vivem no banco: o bot apenas configura e financia.
async function vv2Hub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_veteran_v2_overview", { p_admin_id: ctx.adminId })) as any;
  const pool = d.pool ?? {};
  const tpl = d.templates ?? {};
  const recent = (d.recent ?? []) as any[];
  const text = [
    "⚔️ <b>MYTHREON VETERAN VAULT</b>",
    "<i>Pacote premium · 1 compra por conta · mineração exclusiva em MYTH</i>",
    "",
    `<b>Status:</b> ${d.enabled ? "✅ ATIVO" : "⛔ DESATIVADO"}${d.salesPaused ? " · ⏸ VENDAS PAUSADAS" : ""}`,
    `<b>Versão:</b> <code>${esc(String(d.packageVersion))}</code> · <b>Preço:</b> ${fmt(d.priceTon)} TON`,
    `<b>Popup:</b> ${d.popupEnabled ? "✅" : "⛔"} · <code>${esc(String(d.popupFrequency))}</code>`,
    "",
    `🪙 MYTH na compra: <b>${mythFmt(d.mythReward)}</b> · 🎁 Baús: <b>${fmt(d.legendaryChests)}</b> · 💎 Frag: <b>${fmt(d.fragments)}</b> · ⚔️ Armas: <b>${fmt(d.weapons)}</b>`,
    `⛏ Mineração/dia — herói: <b>${mythFmt(d.heroDailyMyth)}</b> · pet: <b>${mythFmt(d.petDailyMyth)}</b> · dragão: <b>${mythFmt(d.dragonDailyMyth)}</b>`,
    `🚀 Bônus do comprador: <b>+${fmt(d.boostPercent)}%</b> em toda mineração de MYTH`,
    "",
    `<b>TEMPLATES VETERAN</b> — heróis: ${fmt(tpl.heroes)} · pets: ${fmt(tpl.pets)} · dragões: ${fmt(tpl.dragons)} · ovos: ${fmt(tpl.eggs)} · armas: ${fmt(tpl.weapons)}`,
    `<b>FUNDO MYTH (RECOMPENSAS)</b> — financiado: ${mythFmt(pool.rewardFunded)} · distribuído: ${mythFmt(pool.rewardDistributed)} · disponível: <b>${mythFmt(pool.rewardAvailable)}</b>`,
    `<b>FUNDO MYTH (MINERAÇÃO)</b> — financiado: ${mythFmt(pool.miningFunded)} · distribuído: ${mythFmt(pool.miningDistributed)} · disponível: <b>${mythFmt(pool.miningAvailable)}</b>`,
    "",
    `<b>Vendidos:</b> ${fmt(d.sold)} · <b>intents ativos:</b> ${fmt(d.pending)} · <b>TON arrecadado:</b> ${fmt(d.tonRaised)}`,
    "",
    `<b>ÚLTIMAS COMPRAS</b>\n${recent.map((r) => `• ${esc(r.player ?? "—")} (<code>${r.telegramId}</code>) — ${fmt(r.priceTon)} TON · ${esc(r.method ?? "—")} · ${esc(r.status)}`).join("\n") || "nenhuma compra ainda"}`,
  ].join("\n");
  const rows = [
    [
      { t: d.enabled ? "⛔ DESATIVAR" : "✅ ATIVAR", d: `v2:on:${d.enabled ? 0 : 1}` },
      { t: d.salesPaused ? "▶️ RETOMAR VENDAS" : "⏸ PAUSAR VENDAS", d: `v2:pause:${d.salesPaused ? 0 : 1}` },
    ],
    [
      { t: d.popupEnabled ? "🔔 POPUP ON" : "🔔 POPUP OFF", d: `v2:popup:${d.popupEnabled ? 0 : 1}` },
      { t: "🔁 FREQUÊNCIA", d: "v2:ask:v2freq" },
    ],
    [
      { t: "💎 PREÇO (TON)", d: "v2:ask:v2price" },
      { t: "🏷 VERSÃO", d: "v2:ask:v2version" },
    ],
    [
      { t: "🪙 MYTH NA COMPRA", d: "v2:ask:v2myth" },
      { t: "🚀 BÔNUS (%)", d: "v2:ask:v2boost" },
    ],
    [
      { t: "🦸 MYTH/DIA HERÓI", d: "v2:ask:v2heromyth" },
      { t: "🐾 MYTH/DIA PET", d: "v2:ask:v2petmyth" },
    ],
    [
      { t: "🐉 MYTH/DIA DRAGÃO", d: "v2:ask:v2dragonmyth" },
      { t: "⚔️ ARMAS/COMPRA", d: "v2:ask:v2weapons" },
    ],
    [
      { t: "🎁 BAÚS LENDÁRIOS", d: "v2:ask:v2chests" },
      { t: "💎 FRAGMENTOS", d: "v2:ask:v2frag" },
    ],
    [{ t: "🎯 REFERÊNCIA MYTH/TON", d: "v2:ask:v2reference" }],
    [
      { t: "🪙 FINANCIAR RECOMPENSAS", d: "v2:ask:v2fundreward" },
      { t: "⛏ FINANCIAR MINERAÇÃO", d: "v2:ask:v2fundmining" },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function vv2Callback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "on") await rpc("admin_veteran_v2_set", { p_admin_id: ctx.adminId, p_field: "enabled", p_value: a });
  if (sub === "pause") await rpc("admin_veteran_v2_set", { p_admin_id: ctx.adminId, p_field: "paused", p_value: a });
  if (sub === "popup") await rpc("admin_veteran_v2_set", { p_admin_id: ctx.adminId, p_field: "popup", p_value: a });
  return vv2Hub(ctx);
}

const VV2_FIELDS: Record<string, string> = {
  v2price: "price",
  v2version: "version",
  v2myth: "myth",
  v2boost: "boost",
  v2heromyth: "heromyth",
  v2petmyth: "petmyth",
  v2dragonmyth: "dragonmyth",
  v2weapons: "weapons",
  v2chests: "chests",
  v2frag: "fragments",
  v2reference: "reference",
  v2freq: "frequency",
};

async function vv2Prompt(ctx: Ctx, key: string, text: string) {
  const raw = text.trim();
  if (key === "v2fundreward" || key === "v2fundmining") {
    const amount = Number(raw.replace(",", ".").replace(/[^\d.-]/g, ""));
    if (!Number.isFinite(amount) || amount === 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    await rpc("admin_veteran_v2_fund", {
      p_admin_id: ctx.adminId,
      p_pool: key === "v2fundmining" ? "mining" : "reward",
      p_amount: amount,
    });
    await clearSession(ctx);
    await send(
      ctx,
      `⚔️ Fundo Veteran atualizado: <b>${key === "v2fundmining" ? "MINERAÇÃO" : "RECOMPENSAS"}</b> ${amount > 0 ? "+" : ""}<code>${esc(String(amount))}</code> MYTH`,
    );
    return vv2Hub({ ...ctx, messageId: undefined }, false);
  }
  const field = VV2_FIELDS[key];
  if (!field) return vv2Hub({ ...ctx, messageId: undefined }, false);
  let value = raw;
  if (
    [
      "price",
      "boost",
      "myth",
      "heromyth",
      "petmyth",
      "dragonmyth",
      "weapons",
      "chests",
      "fragments",
      "reference",
    ].includes(field)
  ) {
    const num = ["price", "boost"].includes(field)
      ? Number(value.replace(",", ".").replace(/[^\d.]/g, ""))
      : parseAmount(value);
    if (!Number.isFinite(num) || num < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    value = String(num);
  }
  if (field === "frequency") value = value.toUpperCase();
  await rpc("admin_veteran_v2_set", { p_admin_id: ctx.adminId, p_field: field, p_value: value });
  await clearSession(ctx);
  await send(ctx, `⚔️ Veteran Vault atualizado: <b>${esc(field)}</b> = <code>${esc(value)}</code>`);
  return vv2Hub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 🪙 MYTH TOKEN SALE (master admin only)
// Price (1 TON = X MYTH), allocation, minimum purchase, checkout window, pause/resume and BURN.
// Every number shown here comes from `admin_myth_sale_overview` — the bot never computes supply.
async function saleHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_myth_sale_overview", { p_admin_id: ctx.adminId })) as any;
  const sales = (d.recentSales ?? []) as any[];
  const intents = (d.activeIntents ?? []) as any[];
  const burns = (d.burnHistory ?? []) as any[];
  const statusLabel: Record<string, string> = { active: "🟢 ATIVA", paused: "⏸ PAUSADA", finished: "🏁 ENCERRADA" };
  const text = [
    `🪙 <b>MYTH TOKEN SALE</b> — ${statusLabel[d.saleStatus] ?? esc(String(d.saleStatus))}`,
    "",
    `<b>Preço:</b> 1 TON = ${mythFmt(d.mythPerTon)} ${esc(d.symbol)}`,
    `<b>Alocação da venda:</b> ${mythFmt(d.saleAllocation)}`,
    `<b>Vendido:</b> ${mythFmt(d.sold)} (${Number(d.soldPercent ?? 0).toFixed(2)}%)`,
    `<b>Disponível:</b> ${mythFmt(d.available)} · <b>Reservado:</b> ${mythFmt(d.reserved)}`,
    `🔥 <b>Queimado:</b> ${mythFmt(d.burned)} (${Number(d.burnedPercent ?? 0).toFixed(2)}%)`,
    `💎 <b>TON arrecadado:</b> ${mythFmt(d.tonRaised)} TON`,
    `<b>Compra mínima:</b> ${mythFmt(d.minPurchase)} · <b>Checkout:</b> ${fmt(d.intentMinutes)} min`,
    "",
    `<b>ÚLTIMAS VENDAS</b>\n${sales.map((r) => `• ${mythFmt(r.myth_amount)} ${esc(d.symbol)} — ${mythFmt(r.amount_ton)} TON (${r.payment_method === "INTERNAL" ? "saldo interno" : "TonConnect"}) — ${esc(r.player ?? "—")}`).join("\n") || "nenhuma venda ainda"}`,
    "",
    `<b>CHECKOUTS ABERTOS</b>\n${intents.map((r) => `⏳ ${mythFmt(r.myth_amount)} — ${mythFmt(r.amount_ton)} TON (<code>${esc(r.payment_comment)}</code>)`).join("\n") || "nenhum"}`,
    "",
    `<b>QUEIMAS</b>\n${burns.map((r) => `🔥 ${mythFmt(r.amount)} — ${esc(r.reason ?? "sem motivo")}`).join("\n") || "nenhuma queima ainda"}`,
  ].join("\n");
  const rows = [
    [
      { t: "💱 PREÇO (1 TON = X)", d: "ms:ask:msprice" },
      { t: "🧮 ALOCAÇÃO", d: "ms:ask:msalloc" },
    ],
    [
      { t: "📉 COMPRA MÍNIMA", d: "ms:ask:msmin" },
      { t: "⏱ CHECKOUT (min)", d: "ms:ask:msminutes" },
    ],
    [{ t: "🔥 BURN MYTH", d: "ms:ask:msburn" }],
    [
      {
        t: d.saleStatus === "active" ? "⏸ PAUSAR VENDA" : "🟢 ATIVAR VENDA",
        d: `ms:st:${d.saleStatus === "active" ? "paused" : "active"}`,
      },
      { t: "🏁 ENCERRAR", d: "ms:st:finished" },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function saleCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "st") {
    await rpc("admin_myth_sale_status", { p_admin_id: ctx.adminId, p_status: a });
    return saleHub(ctx);
  }
  // Burning supply is irreversible, so it always goes through an explicit confirmation step.
  if (sub === "burn") {
    const amount = Number(a);
    if (!Number.isFinite(amount) || amount <= 0) return saleHub(ctx);
    await rpc("admin_myth_burn", {
      p_admin_id: ctx.adminId,
      p_amount: amount,
      p_reason: b ? decodeURIComponent(b) : null,
    });
    await send(ctx, `🔥 <b>${mythFmt(amount)} MYTH</b> queimado permanentemente.`);
    return saleHub({ ...ctx, messageId: undefined }, false);
  }
  return saleHub(ctx);
}

async function salePrompt(ctx: Ctx, key: string, text: string) {
  if (key === "msburn") {
    const parts = text.split("|");
    const amount = parseAmount(parts[0] ?? "");
    const reason = (parts[1] ?? "").trim();
    if (!Number.isFinite(amount) || amount <= 0)
      throw new Error(
        "KEEP_SESSION::⚠️ Envie <code>quantidade | motivo</code>. Ex.: <code>1000000 | queima de lançamento</code>",
      );
    await clearSession(ctx);
    return send(
      ctx,
      `🔥 <b>CONFIRMAR QUEIMA</b>\nQuantidade: <b>${mythFmt(amount)} MYTH</b>\nMotivo: ${esc(reason || "sem motivo")}\n\n<i>Ação irreversível.</i>`,
      kb([
        [{ t: "✅ CONFIRMAR QUEIMA", d: `ms:burn:${Math.floor(amount)}:${encodeURIComponent(reason).slice(0, 40)}` }],
        [{ t: "↩️ CANCELAR", d: "ms:hub" }],
      ]),
    );
  }
  const keys: Record<string, string> = {
    msprice: "price",
    msalloc: "allocation",
    msmin: "min_purchase",
    msminutes: "minutes",
  };
  const configKey = keys[key];
  if (configKey) {
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value <= 0)
      throw new Error("KEEP_SESSION::⚠️ Envie um número válido. Ex.: <code>20000</code>");
    await rpc("admin_myth_sale_set", { p_admin_id: ctx.adminId, p_key: configKey, p_value: value });
    await clearSession(ctx);
    await send(ctx, `✅ Configuração <b>${esc(configKey)}</b> atualizada para <b>${mythFmt(value)}</b>.`);
  }
  return saleHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 🧩 FRAGMENT UTILITY (master admin only)
// FRAGMENTS -> random common/uncommon hero. UNIVERSAL FRAGMENTS -> replace the copies
// required by one star-fusion step. Costs and odds live in game_settings.
async function fgHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_set_fragment_utility", { p_admin_id: ctx.adminId })) as any;
  const summon = d.summon ?? {};
  const rates = summon.rates ?? {};
  const text =
    `🧩 <b>UTILIDADE DOS FRAGMENTOS</b>\n\n` +
    `<b>FRAGMENTS → HERÓI</b>\n` +
    `• Custo por resgate: <b>${fmt(summon.fragments_per_hero ?? 5)} fragmentos</b>\n` +
    `• COMMON: <b>${Number(rates.common ?? 70)}%</b> · UNCOMMON: <b>${Number(rates.uncommon ?? 30)}%</b>\n\n` +
    `<b>UNIVERSAL FRAGMENTS → FUSE</b>\n` +
    `• Substituem as cópias de 1 etapa: <b>${fmt(d.fragmentsPerFusion ?? 25)} fragmentos</b>`;
  const rows = [
    [{ t: "🧩 FRAGMENTOS POR HERÓI", d: "fg:ask:fgper" }],
    [{ t: "🎲 CHANCES COMMON/UNCOMMON", d: "fg:ask:fgrates" }],
    [{ t: "⭐ FRAGMENTOS POR FUSÃO", d: "fg:ask:fgfusion" }],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function fgCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  return fgHub(ctx);
}

async function fgPrompt(ctx: Ctx, key: string, text: string) {
  const args: Record<string, unknown> = { p_admin_id: ctx.adminId };
  if (key === "fgper" || key === "fgfusion") {
    const value = Number(text.trim());
    if (!Number.isInteger(value) || value < 1)
      throw new Error("KEEP_SESSION::⚠️ Envie um número inteiro maior que zero. Ex.: <code>5</code>");
    args[key === "fgper" ? "p_fragments_per_hero" : "p_fragments_per_fusion"] = value;
  } else if (key === "fgrates") {
    const [c, u] = text
      .trim()
      .split(/\s+/)
      .map((v) => Number(String(v).replace(",", ".")));
    if (!Number.isFinite(c) || !Number.isFinite(u) || c < 0 || u < 0 || c + u <= 0) {
      throw new Error("KEEP_SESSION::⚠️ Envie <code>common uncommon</code>. Ex.: <code>70 30</code>");
    }
    args.p_common_chance = c;
    args.p_uncommon_chance = u;
  }
  await rpc("admin_set_fragment_utility", args);
  await clearSession(ctx);
  await send(ctx, "🧩 Configuração de fragmentos atualizada.");
  return fgHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 🛡 ANTI-FAKE / ANTI-MULTIACCOUNT
// Up to 3 distinct Telegram accounts per device. The 4th+ is access-blocked (never banned,
// nothing deleted, no TON confiscated). Every admin action is audited.
async function afHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_antifake_overview", { p_admin_id: ctx.adminId })) as any;
  const blocked = (d.blockedDevices ?? []) as any[];
  const text =
    `🛡 <b>ANTI-FAKE / MULTICONTA</b>\n\n` +
    `Status: ${d.enabled ? "🟢 ATIVO" : "🔴 DESATIVADO"}\n` +
    `Limite: <b>${fmt(d.limit)} contas por dispositivo</b>\n\n` +
    `📱 Dispositivos: <b>${fmt(d.devices)}</b>\n` +
    `🔗 Contas vinculadas: <b>${fmt(d.linkedAccounts)}</b>\n` +
    `⛔ Contas bloqueadas: <b>${fmt(d.blockedAccounts)}</b>\n` +
    `📝 Revisões pendentes: <b>${fmt(d.pendingReviews)}</b>\n` +
    `✅ Allowlist: <b>${fmt(d.allowlisted)}</b>\n\n` +
    (blocked.length
      ? `<b>ÚLTIMOS DISPOSITIVOS COM BLOQUEIO</b>\n` +
        blocked
          .slice(0, 8)
          .map(
            (x) =>
              `• <code>…${esc(x.short)}</code> · ${fmt(x.accounts)} contas (${fmt(x.blocked)} bloqueadas) · ${esc(String(x.platform || "—"))}`,
          )
          .join("\n")
      : "<i>Nenhum dispositivo bloqueado.</i>");
  const rows = [
    [
      { t: "⛔ BLOCKED DEVICES", d: "af:blocked" },
      { t: "🔎 SEARCH USER", d: "af:ask:afsearch" },
    ],
    [{ t: "📝 REVIEW REQUESTS", d: "af:reviews" }],
    [
      { t: "🔓 UNBLOCK DEVICE", d: "af:ask:afunblock" },
      { t: "✅ ALLOWLIST", d: "af:ask:afallow" },
    ],
    [
      { t: "🔢 LIMITE DE CONTAS", d: "af:ask:aflimit" },
      { t: d.enabled ? "⏸ DESATIVAR" : "▶️ ATIVAR", d: `af:toggle:${d.enabled ? "0" : "1"}` },
    ],
    nav(),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function afBlocked(ctx: Ctx) {
  const d = (await rpc("admin_antifake_overview", { p_admin_id: ctx.adminId })) as any;
  const blocked = (d.blockedDevices ?? []) as any[];
  const text =
    `⛔ <b>DISPOSITIVOS COM CONTAS BLOQUEADAS</b>\n\n` +
    (blocked.length
      ? blocked
          .map(
            (x) =>
              `• <code>…${esc(x.short)}</code>\n   ${fmt(x.accounts)} contas · ${fmt(x.blocked)} bloqueadas · ${esc(String(x.platform || "—"))}\n   Último acesso: ${String(x.lastSeen).slice(0, 16).replace("T", " ")}`,
          )
          .join("\n")
      : "<i>Nenhum dispositivo bloqueado.</i>");
  return edit(ctx, text, kb([[{ t: "🔓 DESBLOQUEAR", d: "af:ask:afunblock" }], nav("af:hub")]));
}

async function afReviews(ctx: Ctx) {
  const d = (await rpc("admin_antifake_reviews", { p_admin_id: ctx.adminId, p_limit: 10 })) as any;
  const list = (d.requests ?? []) as any[];
  const text =
    `📝 <b>PEDIDOS DE REVISÃO</b>\n\n` +
    (list.length
      ? list
          .map(
            (x) =>
              `• <code>${esc(x.telegramId)}</code>${x.username ? ` (@${esc(x.username)})` : ""}\n   Dispositivo <code>…${esc(x.short)}</code> · ${fmt(x.accountsOnDevice)} contas\n   ${String(x.createdAt).slice(0, 16).replace("T", " ")}`,
          )
          .join("\n")
      : "<i>Nenhum pedido pendente.</i>");
  const rows = list.slice(0, 5).map((x) => [{ t: `🔓 LIBERAR ${x.telegramId}`, d: `af:unblock:${x.telegramId}` }]);
  return edit(ctx, text, kb([...rows, nav("af:hub")]));
}

async function afUserCard(ctx: Ctx, ref: string, useEdit = true) {
  const d = (await rpc("admin_antifake_search", { p_admin_id: ctx.adminId, p_ref: ref })) as any;
  if (!d?.found) {
    const miss = "🔎 Jogador não encontrado.";
    return useEdit
      ? edit(ctx, miss, kb([[{ t: "🔎 BUSCAR", d: "af:ask:afsearch" }], nav("af:hub")]))
      : send(ctx, miss, kb([nav("af:hub")]));
  }
  const devices = (d.devices ?? []) as any[];
  const text =
    `🛡 <b>ANTI-FAKE · JOGADOR</b>\n\n` +
    `Telegram ID: <code>${esc(d.telegramId)}</code>\n` +
    `Usuário: ${d.username ? "@" + esc(d.username) : "—"}\n` +
    `Nome: ${esc(String(d.name || "—"))}\n` +
    `Dispositivos: <b>${fmt(d.deviceCount)}</b>\n` +
    `Status: ${d.blocked ? "⛔ BLOQUEADO" : "🟢 LIBERADO"}${d.allowlisted ? " · ✅ ALLOWLIST" : ""}${d.pendingReview ? " · 📝 REVISÃO PENDENTE" : ""}\n\n` +
    (devices.length
      ? devices
          .map(
            (x) =>
              `📱 <code>…${esc(x.short)}</code>\n   Slot ${fmt(x.slot)} · ${x.status === "blocked" ? "⛔ bloqueada" : "🟢 liberada"}${x.adminBypass ? " · 👑 admin bypass" : ""}\n   ${fmt(x.accountsOnDevice)} contas neste aparelho\n   Primeiro: ${String(x.firstSeen).slice(0, 16).replace("T", " ")} · Último: ${String(x.lastSeen).slice(0, 16).replace("T", " ")}`,
          )
          .join("\n")
      : "<i>Nenhum dispositivo registrado.</i>");
  const rows = [
    [
      { t: "🔓 DESBLOQUEAR", d: `af:unblock:${d.telegramId}` },
      { t: "✅ ALLOWLIST", d: `af:allow:${d.telegramId}` },
    ],
    [{ t: "🔎 OUTRO JOGADOR", d: "af:ask:afsearch" }],
    nav("af:hub"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function afCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  if (sub === "ask") return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
  if (sub === "blocked") return afBlocked(ctx);
  if (sub === "reviews") return afReviews(ctx);
  if (sub === "toggle") {
    await rpc("admin_antifake_set_enabled", { p_admin_id: ctx.adminId, p_enabled: a === "1" });
    await send(
      ctx,
      a === "1"
        ? "🟢 Proteção anti-fake ATIVA."
        : "🔴 Proteção anti-fake DESATIVADA. Nenhum jogador fica bloqueado enquanto estiver desligada.",
    );
    return afHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "unblock") {
    const r = (await rpc("admin_antifake_unblock", {
      p_admin_id: ctx.adminId,
      p_ref: a,
      p_reason: "liberado pelo painel admin",
    })) as any;
    await send(
      ctx,
      r?.ok
        ? `🔓 Acesso liberado (${fmt(r.unblocked)} vínculo(s)). Auditoria registrada.`
        : "ℹ️ Não havia bloqueio ativo para este alvo.",
    );
    return afUserCard({ ...ctx, messageId: undefined }, a, false);
  }
  if (sub === "allow") {
    await rpc("admin_antifake_allowlist", {
      p_admin_id: ctx.adminId,
      p_ref: a,
      p_reason: "allowlist pelo painel admin",
      p_remove: false,
    });
    await send(ctx, "✅ Adicionado à allowlist. Auditoria registrada.");
    return afUserCard({ ...ctx, messageId: undefined }, a, false);
  }
  return afHub(ctx);
}

async function afPrompt(ctx: Ctx, key: string, text: string) {
  const value = text.trim();
  if (key === "afsearch") {
    await clearSession(ctx);
    return afUserCard({ ...ctx, messageId: undefined }, value, false);
  }
  if (key === "afunblock") {
    if (!value) throw new Error("KEEP_SESSION::⚠️ Envie o Telegram ID ou o identificador do dispositivo.");
    await clearSession(ctx);
    const r = (await rpc("admin_antifake_unblock", {
      p_admin_id: ctx.adminId,
      p_ref: value,
      p_reason: "liberado pelo painel admin",
    })) as any;
    await send(
      ctx,
      r?.ok
        ? `🔓 Desbloqueado (${fmt(r.unblocked)} vínculo(s)). Auditoria registrada.`
        : "ℹ️ Nenhum bloqueio ativo encontrado.",
    );
    return afHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "afallow") {
    if (!value) throw new Error("KEEP_SESSION::⚠️ Envie o Telegram ID ou o identificador do dispositivo.");
    await clearSession(ctx);
    await rpc("admin_antifake_allowlist", {
      p_admin_id: ctx.adminId,
      p_ref: value,
      p_reason: "allowlist pelo painel admin",
      p_remove: false,
    });
    await send(ctx, "✅ Allowlist atualizada. Auditoria registrada.");
    return afHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "aflimit") {
    const n = Number(value);
    if (!Number.isInteger(n) || n < 1 || n > 10)
      throw new Error("KEEP_SESSION::⚠️ Envie um número inteiro entre 1 e 10. Ex.: <code>3</code>");
    await clearSession(ctx);
    await rpc("admin_antifake_set_enabled", { p_admin_id: ctx.adminId, p_enabled: true, p_limit: n });
    await send(ctx, `🔢 Limite definido em <b>${fmt(n)} contas por dispositivo</b>.`);
    return afHub({ ...ctx, messageId: undefined }, false);
  }
  return afHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- 📣 POOL MARKETING (transparência de gastos)
// Total do pool, lançamentos e visibilidade da aba vivem no banco: tudo muda em
// tempo real no Mini App, sem deploy.
const MP_CATEGORIES = [
  "MARKETING",
  "DEVELOPMENT",
  "INFLUENCERS",
  "DESIGN",
  "COMMUNITY",
  "MODERATION",
  "SERVER",
  "OTHER",
];

const mpTon = (n: unknown) => `${Number(n ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 4 })} TON`;

function mpExpenseLine(e: any, index?: number) {
  return `${index !== undefined ? `${index}. ` : "• "}<b>${esc(e.category)}</b> — ${esc(e.description)}\n  −${mpTon(e.amountTon)} · ${esc(String(e.spentAt))}${e.note ? ` · ${esc(e.note)}` : ""}\n  <code>${esc(String(e.id))}</code>`;
}

async function mpHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_marketing_pool_overview", { p_admin_id: ctx.adminId, p_limit: 5 })) as any;
  const text = [
    "📣 <b>POOL MARKETING</b>",
    "",
    `Total Pool: <b>${mpTon(d.totalTon)}</b>`,
    `Spent: <b>${mpTon(d.spentTon)}</b>`,
    `Remaining: <b>${mpTon(d.remainingTon)}</b>`,
    `Entries: <b>${fmt(d.entries)}</b>`,
    `Aba no Mini App: ${d.enabled ? "✅ ATIVA" : "⛔ OCULTA"}`,
    `Última atualização: ${d.updatedAt ? esc(String(d.updatedAt).slice(0, 16).replace("T", " ")) : "—"}`,
    "",
    "<b>ÚLTIMOS LANÇAMENTOS</b>",
    ((d.expenses ?? []) as any[]).map((e) => mpExpenseLine(e)).join("\n") || "nenhum lançamento registrado",
  ].join("\n");
  const rows = [
    [
      { t: "💰 SET TOTAL POOL", d: "mp:ask:mptotal" },
      { t: "➕ ADD EXPENSE", d: "mp:ask:mpadd" },
    ],
    [
      { t: "✏️ EDIT EXPENSE", d: "mp:ask:mpedit" },
      { t: "🗑 DELETE EXPENSE", d: "mp:ask:mpdel" },
    ],
    [
      { t: "📋 VIEW HISTORY", d: "mp:list:0" },
      { t: "📤 EXPORT SUMMARY", d: "mp:export" },
    ],
    [{ t: d.enabled ? "⛔ DESATIVAR ABA" : "✅ ATIVAR ABA", d: `mp:toggle:${d.enabled ? 0 : 1}` }],
    [
      { t: "♻️ RESET (GASTOS)", d: "mp:reset:expenses" },
      { t: "🧹 RESET TOTAL", d: "mp:reset:all" },
    ],
    nav("m:pool"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

const MP_PAGE = 10;

async function mpHistory(ctx: Ctx, page = 0) {
  const d = (await rpc("admin_marketing_pool_overview", { p_admin_id: ctx.adminId, p_limit: 200 })) as any;
  const all = (d.expenses ?? []) as any[];
  const pages = Math.max(1, Math.ceil(all.length / MP_PAGE));
  const p = Math.min(Math.max(0, page), pages - 1);
  const slice = all.slice(p * MP_PAGE, p * MP_PAGE + MP_PAGE);
  const text = [
    `📋 <b>HISTÓRICO — POOL MARKETING</b> (${fmt(all.length)} lançamentos · página ${p + 1}/${pages})`,
    "",
    slice.map((e, i) => mpExpenseLine(e, p * MP_PAGE + i + 1)).join("\n\n") || "nenhum lançamento registrado",
    "",
    `Spent <b>${mpTon(d.spentTon)}</b> · Remaining <b>${mpTon(d.remainingTon)}</b>`,
  ]
    .join("\n")
    .slice(0, 3800);
  const pager: { t: string; d: string }[] = [];
  if (p > 0) pager.push({ t: "⬅️ Anterior", d: `mp:list:${p - 1}` });
  if (p < pages - 1) pager.push({ t: "Próxima ➡️", d: `mp:list:${p + 1}` });
  const rows = pager.length ? [pager, nav("mp:hub")] : [nav("mp:hub")];
  return edit(ctx, text, kb(rows));
}

async function mpExport(ctx: Ctx) {
  const d = (await rpc("admin_marketing_pool_overview", { p_admin_id: ctx.adminId, p_limit: 200 })) as any;
  const byCat = new Map<string, number>();
  for (const e of (d.expenses ?? []) as any[])
    byCat.set(e.category, (byCat.get(e.category) ?? 0) + Number(e.amountTon || 0));
  const lines =
    [...byCat.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([c, v]) => `• ${esc(c)}: <b>${mpTon(v)}</b>`)
      .join("\n") || "nenhum lançamento";
  return send(
    ctx,
    [
      "📤 <b>EXPORT SUMMARY — POOL MARKETING</b>",
      "",
      `Total Pool: <b>${mpTon(d.totalTon)}</b>`,
      `Spent: <b>${mpTon(d.spentTon)}</b>`,
      `Remaining: <b>${mpTon(d.remainingTon)}</b>`,
      `Entries: <b>${fmt(d.entries)}</b>`,
      "",
      "<b>POR CATEGORIA</b>",
      lines,
    ].join("\n"),
    kb([nav("mp:hub")]),
  );
}

async function mpCallback(ctx: Ctx, rest: string[]) {
  const [sub, arg] = rest;
  if (sub === "ask") return ask(ctx, arg, PROMPTS[arg] ?? "Envie o valor.");
  await clearSession(ctx);
  if (sub === "list") return mpHistory(ctx, Number(arg) || 0);
  if (sub === "export") return mpExport(ctx);
  if (sub === "toggle") {
    await rpc("admin_marketing_pool_toggle", { p_admin_id: ctx.adminId, p_enabled: arg === "1" });
    return mpHub(ctx);
  }
  if (sub === "reset") {
    const mode = arg === "all" ? "all" : "expenses";
    return edit(
      ctx,
      `⚠️ <b>RESET POOL MARKETING</b>\n${mode === "all" ? "Apaga todos os lançamentos <b>e zera o total do pool</b>." : "Apaga todos os lançamentos e <b>mantém o total do pool</b>."}\n\nConfirmar?`,
      kb([
        [
          { t: "✅ CONFIRMAR", d: `mpgo:${mode}` },
          { t: "❌ CANCELAR", d: "mp:hub" },
        ],
      ]),
    );
  }
  if (sub === "go") {
    const r = (await rpc("admin_marketing_pool_reset", {
      p_admin_id: ctx.adminId,
      p_mode: arg === "all" ? "all" : "expenses",
    })) as any;
    await send(ctx, `♻️ Reset concluído.\nTotal <b>${mpTon(r.totalTon)}</b> · Spent <b>${mpTon(r.spentTon)}</b>`);
    return mpHub({ ...ctx, messageId: undefined }, false);
  }
  return mpHub(ctx);
}

/** Resolve um lançamento por UUID completo ou prefixo (mínimo 6 caracteres). */
async function mpResolveExpense(prefix: string): Promise<string> {
  const raw = String(prefix || "")
    .trim()
    .toLowerCase();
  if (raw.length < 6) throw new Error("KEEP_SESSION::⚠️ Envie ao menos 6 caracteres do ID do lançamento.");
  const { data, error } = await db.from("marketing_pool_expenses").select("id").ilike("id", `${raw}%`).limit(2);
  if (error) throw new Error(error.message);
  if (!data?.length) throw new Error("KEEP_SESSION::⚠️ Lançamento não encontrado.");
  if (data.length > 1) throw new Error("KEEP_SESSION::⚠️ ID ambíguo — envie mais caracteres.");
  return String(data[0].id);
}

/** Converte 16/08/2026, 2026-08-16 ou vazio (hoje) em YYYY-MM-DD. */
function mpParseDate(raw: string | undefined): string | null {
  const v = String(raw || "").trim();
  if (!v || v === "-") return null;
  const br = v.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (br) return `${br[3]}-${br[2]}-${br[1]}`;
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  throw new Error("KEEP_SESSION::⚠️ Data inválida. Use <code>16/08/2026</code> ou <code>2026-08-16</code>.");
}

async function handleCallback(ctx: Ctx, data: string) {
  const [head, ...rest] = data.split(":");

  // Navigation always leaves any pending flow in a clean state.
  if (data === "home") {
    await clearSession(ctx);
    return home(ctx, true);
  }
  if (data === "cancel") {
    await clearSession(ctx);
    return send(ctx, "❌ Ação cancelada.", MAIN_MENU);
  }
  if (head === "m") {
    await clearSession(ctx);
    return module(ctx, rest[0]);
  }
  // Hero wizard keeps its own persisted session, so it must run before the generic prompts.
  if (head === "hw") return heroWizardCallback(ctx, rest);
  // 🐲 Pet CMS keeps its own persisted session too.
  if (head === "pw") return petCms.callback(ctx, rest);
  if (head === "cl") {
    if (!["ask"].includes(rest[0])) await clearSession(ctx);
    return clansCallback(ctx, rest);
  }
  if (head === "gf") return giftCallback(ctx, rest);
  // 💎 NFT EXCLUSIVE pets (admin-only delivery, unique serials).
  // ⚔️ NFT EXCLUSIVE heroes (unique serials, admin-only delivery + power editor).
  if (head === "nfth") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return nfthCallback(ctx, rest);
  }
  // 💎 TON STAKING (planos, taxas, pool, circuit breaker, auto-staking).
  if (head === "ts") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return tsCallback(ctx, rest);
  }
  // ⛏ MINAS DE TON (preço, rendimento, armazenamento, fidelidade e visibilidade).
  if (head === "tm") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return tmCallback(ctx, rest);
  }
  // ⛏ Hero TON mining (rates, global pause, per-player audit).
  if (head === "hm") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return hmCallback(ctx, rest);
  }

  // #️⃣ Mission "ADD #MYTHREON TO YOUR TELEGRAM NAME" (ON/OFF, hashtag, reward, claims, audit).
  if (head === "nm") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return nmCallback(ctx, rest);
  }
  // 💠 Deposit methods: TON -> FC purchase and TON -> internal TON balance (toggles + minimum).
  if (head === "dp") {
    if (rest[0] === "ask") return ask(ctx, rest[1], PROMPTS[rest[1].split("|")[0]] ?? "Envie o valor.");
    await clearSession(ctx);
    if (rest[0] === "toggle") {
      await rpc("admin_deposit_settings", { p_admin_id: ctx.adminId, p_key: rest[1], p_value: Number(rest[2]) });
    }
    return depositSettingsHub(ctx);
  }
  // 📣 POOL MARKETING: total, lançamentos e visibilidade da aba (tempo real, sem deploy).
  if (head === "mp") return mpCallback(ctx, rest);
  if (head === "mpgo") {
    await clearSession(ctx);
    return mpCallback(ctx, ["go", rest[0]]);
  }
  // 🧩 Fragment utility (summon cost/odds + universal fragments per fusion step).
  if (head === "fg") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return fgCallback(ctx, rest);
  }
  // 🗺 Pet Expeditions: per-mission daily extra attempts (ads + FC) and FC prices per rarity.
  if (head === "xe") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return xeCallback(ctx, rest);
  }
  // 🎁 Promotional giveaway popup (campaign id + group link + on/off).
  if (head === "gw") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return gwCallback(ctx, rest);
  }
  // ⚙ Daily activity scoring (Community Pool points + Season Pass XP per activity).
  if (head === "ar") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return arCallback(ctx, rest);
  }
  if (head === "af") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return afCallback(ctx, rest);
  }
  if (head === "np") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return nftPoolCallback(ctx, rest);
  }
  if (head === "nstk") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return nftStockCallback(ctx, rest);
  }
  if (head === "nprc") {
    if (rest[0] === "ask") return ask(ctx, rest[1], PROMPTS[rest[1].split("|")[0]] ?? "Envie o valor.");
    await clearSession(ctx);
    if (rest[0] === "review") return nftYieldReview(ctx);
    if (rest[0] === "force") return nftYieldForceMenu(ctx);
    return nftPriceHub(ctx);
  }
  // 🛡 Hero level progression (XP curve, per-activity XP, daily caps).
  // NOTE: prefix is 'hprog' — 'hp' is already taken by the hero recruit price flow.
  if (head === "hprog") {
    if (rest[0] === "ask") return ask(ctx, rest[1], PROMPTS[rest[1].split("|")[0]] ?? "Envie o valor.");
    await clearSession(ctx);
    return heroProgressionHub(ctx);
  }
  // ⚖️ Read-only balance audit: hero rarity ranges + pet power formula.
  if (head === "gbal") {
    await clearSession(ctx);
    return gameBalanceHub(ctx);
  }
  if (head === "neq") {
    if (rest[0] === "ask") return ask(ctx, rest[1], PROMPTS[rest[1]] ?? "Envie o valor.");
    await clearSession(ctx);
    return nftEquipCallback(ctx, rest);
  }

  // ⚔️ PVP LEAGUE ARENA — main event slot (draft until the admin activates it).
  if (head === "pl") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return plCallback(ctx, rest);
  }

  // ⚔️ TACTICAL PVP (3v3) — feature flag, turn timer, ticket cost and skill balance.
  if (head === "tp") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return tpCallback(ctx, rest);
  }

  // 🏰 CLAN WAR (20v20) — feature flag, roster/phase timings, scoring and season control.
  if (head === "cw") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return cwCallback(ctx, rest);
  }

  // 🪙 MYTH TOKEN — decorativo: supply, saldos manuais, visibilidade e nome. Sem preço/trade/saque.
  // 👑 FOUNDER PACK — preço, janela de contas novas, conteúdo do pacote e cosméticos.
  // 🐾 FAMILIAR HUNT — ON/OFF, custos, dificuldade e loot tables.
  // 🎡 GLOBAL MYSTERY ROULETTE — custo do giro, meta Celestial, pesos, pools e ciclo atual (privado).
  if (head === "rl") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return rlCallback(ctx, rest);
  }

  if (head === "fh") {

    if (rest[0] !== "ask") await clearSession(ctx);
    return fhCallback(ctx, rest);
  }

  if (head === "fp") {

    if (rest[0] !== "ask") await clearSession(ctx);
    return fpCallback(ctx, rest);
  }

  // ⚔️ VETERAN VAULT — oferta para veteranos: preço, ciclo, conteúdo, cronograma e pools de reward.
  if (head === "v2") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return vv2Callback(ctx, rest);
  }
  if (head === "mu") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return muCallback(ctx, rest);
  }
  if (head === "po") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return poCallback(ctx, rest);
  }
  if (head === "vv") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return vvCallback(ctx, rest);
  }

  if (head === "my") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return mythCallback(ctx, rest);
  }

  // 🔒 MYTH STAKING — staking interno MYTH → MYTH: ON/OFF, APR por plano, limites e reward pool.
  if (head === "stk") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return stakingCallback(ctx, rest);
  }

  // 🪙 MYTH TOKEN SALE — preço, alocação, checkout, pausa e BURN (com confirmação).
  if (head === "ms") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return saleCallback(ctx, rest);
  }

  if (head === "nft") {
    if (rest[0] !== "ask") await clearSession(ctx);
    return nftCallback(ctx, rest);
  }

  // 💳 Payment recovery keeps its own session (reason + confirmation), so it must not be cleared here.
  if (head === "pr") return prCallback(ctx, rest);

  // 👹 Clan Boss module (Abyssal Warlord) — fully independent from the 👑 global boss panel.
  if (head === "cb") {
    if (!["ask", "cask"].includes(rest[0])) await clearSession(ctx);
    return cbCallback(ctx, rest);
  }

  // 🤝 Partner channels (name + reward + hidden link). Keeps its own wizard session.
  if (head === "pt") {
    if (!["ask", "save", "val"].includes(rest[0])) await clearSession(ctx);
    return partnersCallback(ctx, rest);
  }

  // 💰 Spending Event module (independent from the weekly pool and the referral event).
  if (head === "sp") {
    await clearSession(ctx);
    return spendCallback(ctx, rest);
  }

  // 🎉 Special events module (independent from the weekly community pool).
  if (head === "ev") {
    await clearSession(ctx);
    const [sub, ref] = [rest[0], rest[1] || null];
    if (sub === "list") return eventsList(ctx);
    if (sub === "rank") return eventsRanking(ctx, ref);
    if (sub === "audit") return eventsAudit(ctx);
    if (sub === "open") return eventsHub(ctx, ref);
    return eventsHub(ctx, ref);
  }
  if (head === "evconfirm") {
    await clearSession(ctx);
    const [action, ref] = [rest[0], rest[1] || ""];
    const label: Record<string, string> = {
      finish: "ENCERRAR o evento e congelar o ranking (snapshot dos vencedores)",
      distribute: "DISTRIBUIR os prêmios do evento em TON",
      cancel: "CANCELAR o evento (nenhum prêmio será pago)",
    };
    return send(
      ctx,
      `⚠️ Tem certeza que deseja <b>${label[action] ?? action}</b>?`,
      kb([
        [
          { t: "✅ CONFIRMAR", d: `evrun:${action}:${ref}` },
          { t: "❌ Cancelar", d: "m:events" },
        ],
      ]),
    );
  }
  if (head === "evrun") {
    const [action, ref] = [rest[0], rest[1] || null];
    const r = await evRpc(ctx, action, ref, {});
    const res = r.result ?? {};
    await send(ctx, `✅ Ação <b>${esc(action)}</b> concluída.\n<code>${esc(JSON.stringify(res)).slice(0, 700)}</code>`);
    return eventsHub(ctx, ref, false);
  }

  // The prompt key can carry arguments after "|" (e.g. ask:evprize|event_key); the help text uses the bare key.
  if (head === "ask") {
    const k = rest[0];
    return ask(ctx, k, PROMPTS[k] || PROMPTS[k.split("|")[0]] || "Envie o valor.");
  }

  // ---- global boss + user management (button driven, no JSON typing)
  if (head === "boss" && rest[0] === "rank") {
    await clearSession(ctx);
    return bossRanking(ctx);
  }
  if (head === "boss" && rest[0] === "roster") {
    await clearSession(ctx);
    return bossRoster(ctx, Number(rest[1] || 0) || 0);
  }
  if (head === "gbrot") {
    await clearSession(ctx);
    return bossRotationFlow(ctx, rest[0] || "ask");
  }
  if (head === "gbt") {
    await clearSession(ctx);
    return bossTemplateMenu(ctx, rest.join(":"));
  }
  if (head === "gbtset") {
    await clearSession(ctx);
    const code = rest[0];
    const field = rest[1] || "toggle";
    await rpc("admin_global_boss_template_set", {
      p_admin_id: ctx.adminId,
      p_code: code,
      p_field: field,
      p_value: null,
      p_text: null,
      p_reason: "roster toggle",
    });
    return bossTemplateMenu(ctx, code);
  }

  // Explicit flow: the prize of the ACTIVE cycle only (never the template, never a new cycle).
  if (head === "boss" && rest[0] === "curreward") {
    const d = (await rpc("admin_boss_overview", { p_admin_id: ctx.adminId })) as any;
    const cyc = d?.cycle ?? null;
    if (!cyc || cyc.status !== "active")
      return send(ctx, "⚠️ Nenhum ciclo ativo do Global Boss.", kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]));
    return ask(
      ctx,
      "bosscurreward",
      [
        "✏️ <b>CHANGE CURRENT REWARD</b>",
        `Current cycle: <b>#${cyc.cycleNumber}</b> · ${esc(cyc.name)}`,
        `Current reward: <b>${fmt(cyc.rewardPoolFc)} FC</b>`,
        "",
        "Enter new reward in FC:",
      ].join("\n"),
    );
  }
  if (head === "gbrw") {
    await clearSession(ctx);
    const amount = parseAmount(rest[0] || "");
    if (!Number.isFinite(amount) || amount < 0) return send(ctx, "⚠️ Valor inválido.", MAIN_MENU);
    const r = (await rpc("admin_set_global_boss_reward", {
      p_admin_id: ctx.adminId,
      p_scope: "cycle",
      p_value: amount,
      p_code: null,
      p_reason: "current cycle reward change (admin bot)",
    })) as any;
    return send(
      ctx,
      [
        "✅ <b>SUCCESS</b>",
        "Global Boss reward updated.",
        `Cycle: <b>#${r.cycleNumber}</b> · ${esc(r.bossName)}`,
        `Before: ${fmt(r.oldReward)} FC`,
        `New reward: <b>${fmt(r.newReward)} FC</b>`,
        "",
        `HP, dano, participantes e ranking preservados (${fmt(Math.round(Number(r.currentHp || 0)))}/${fmt(r.maxHp)} HP · ${fmt(r.participants)} jogadores).`,
      ].join("\n"),
      kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
    );
  }
  // ---- 💎 AJUSTAR TON (internal withdrawable balance only)
  if (head === "tonop") {
    const [mode, tg] = rest;
    if (mode !== "add" && mode !== "remove") {
      await clearSession(ctx);
      return send(ctx, "⚠️ Operação inválida.", kb([nav("m:wallet")]));
    }
    return ask(
      ctx,
      `tonamt|${mode}|${tg}`,
      `${mode === "add" ? "➕ <b>ADICIONAR TON</b>" : "➖ <b>REMOVER TON</b>"}\n\nDigite a quantidade de TON que deseja ${mode === "add" ? "adicionar" : "remover"}.\nEx.: <code>2.5</code>`,
    );
  }
  if (head === "tongo") {
    const session = await getSession(ctx);
    const c = (session?.context || {}) as Record<string, unknown>;
    // Double click: the session is cleared on the first press and the ledger key is unique server-side.
    if (session?.action !== "tonconfirm" || String(c.key || "") !== String(rest[0] || "")) {
      return send(
        ctx,
        "ℹ️ Este ajuste já foi processado ou expirou. Nenhuma alteração adicional foi feita.",
        kb([[{ t: "💎 AJUSTAR TON", d: "ask:tonadj" }], nav("m:wallet")]),
      );
    }
    await clearSession(ctx);
    try {
      const r = (await rpc("admin_adjust_ton_balance", {
        p_admin_id: ctx.adminId,
        p_target_telegram_id: Number(c.tg),
        p_amount: Number(c.amount),
        p_operation: String(c.mode),
        p_reason: String(c.reason || ""),
        p_idempotency_key: String(c.key),
      })) as any;
      if (r?.duplicate) {
        return send(
          ctx,
          `ℹ️ Ajuste já aplicado anteriormente.\nSaldo TON: <b>${fmtTon(r.balanceAfter)} TON</b>`,
          kb([[{ t: "💎 AJUSTAR TON", d: "ask:tonadj" }], nav("m:wallet")]),
        );
      }
      return send(
        ctx,
        [
          "✅ <b>AJUSTE TON APLICADO</b>",
          "",
          `Jogador: <b>${esc(String(r.name))}</b> · <code>${esc(String(r.telegramId))}</code>`,
          `Operação: ${r.operation === "add" ? "➕ ADICIONAR" : "➖ REMOVER"} <b>${fmtTon(r.amountTon)} TON</b>`,
          `Antes: ${fmtTon(r.balanceBefore)} TON`,
          `Novo saldo: <b>${fmtTon(r.balanceAfter)} TON</b>`,
          `Motivo: ${esc(String(c.reason || ""))}`,
          "",
          "<i>Hot Wallet e carteira externa do jogador não foram alteradas.</i>",
        ].join("\n"),
        kb([
          [
            { t: "💎 AJUSTAR TON", d: "ask:tonadj" },
            { t: "📜 ÚLTIMOS AJUSTES", d: "tonhist:1" },
          ],
          nav("m:wallet"),
        ]),
      );
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      const friendly = msg.includes("INSUFFICIENT_TON_BALANCE")
        ? "❌ Saldo insuficiente. Nenhuma alteração foi feita."
        : msg.includes("PLAYER_NOT_FOUND")
          ? "❌ Jogador não encontrado."
          : `⚠️ Falha no ajuste: ${esc(msg)}`;
      return send(ctx, friendly, kb([[{ t: "💎 AJUSTAR TON", d: "ask:tonadj" }], nav("m:wallet")]));
    }
  }
  if (head === "tonhist") {
    await clearSession(ctx);
    const items = (await rpc("admin_ton_adjust_history", { p_admin_id: ctx.adminId, p_limit: 10 })) as any[];
    const lines =
      (items || [])
        .map(
          (x: any) =>
            `${x.direction === "credit" ? "➕" : "➖"} <b>${fmtTon(x.amountTon)} TON</b> → ${esc(String(x.player))} (<code>${esc(String(x.telegramId))}</code>)\n   ${esc(String(x.reason || "—"))} · ${String(x.createdAt).slice(0, 16).replace("T", " ")}`,
        )
        .join("\n") || "—";
    return edit(
      ctx,
      `📜 <b>ÚLTIMOS AJUSTES TON</b>\n(ledger real de ajustes manuais)\n\n${lines}`,
      kb([[{ t: "💎 AJUSTAR TON", d: "ask:tonadj" }], nav("m:wallet")]),
    );
  }
  if (head === "uf") {
    await clearSession(ctx);
    return userFcMenu(ctx, rest[0]);
  }
  if (head === "balgo") {
    await clearSession(ctx);
    const [cur, mode, user, raw] = rest;
    const amount = parseAmount(raw);
    if (!Number.isFinite(amount) || amount < 0) return send(ctx, "⚠️ Valor inválido.", MAIN_MENU);
    const r = (await rpc("admin_adjust_balance", {
      p_admin_id: ctx.adminId,
      p_ref: user,
      p_currency: cur,
      p_mode: mode,
      p_amount: amount,
      p_reason: "ajuste pelo painel",
    })) as any;
    const label = String(cur).toUpperCase();
    await send(
      ctx,
      `✅ <b>SUCESSO</b>\n\nJogador: <code>${esc(user)}</code>\nAção: ${mode === "add" ? "adicionado" : mode === "remove" ? "removido" : "definido"} ${fmt(amount)} ${label}\nAnterior: ${fmt(r.old_value)} ${label}\nNovo saldo: <b>${fmt(r.new_value)} ${label}</b>`,
    );
    return userFcMenu({ ...ctx, messageId: undefined }, user);
  }

  if (head === "uh") {
    await clearSession(ctx);
    return userHeroesMenu(ctx, rest[0], Number(rest[1] || 0) || 0);
  }
  if (head === "uhadd") {
    await clearSession(ctx);
    return heroCatalogPicker(ctx, rest[0]);
  }
  if (head === "uhr") {
    await clearSession(ctx);
    return heroCatalogPicker(ctx, rest[0], rest[1]);
  }
  if (head === "uhc") {
    const [tg, heroKey] = rest;
    return edit(
      ctx,
      `➕ <b>ADD HERO</b>\nConceder <code>${esc(heroKey)}</code> ao jogador <code>${esc(tg)}</code>?`,
      kb([
        [
          { t: "✅ CONFIRMAR", d: `uhok:${tg}:${heroKey}` },
          { t: "❌ CANCELAR", d: `uh:${tg}:0` },
        ],
      ]),
    );
  }
  if (head === "uhok") {
    const [tg, heroKey] = rest;
    const r = (await rpc("admin_grant_hero", {
      p_admin_id: ctx.adminId,
      p_ref: tg,
      p_hero_key: heroKey,
      p_level: 1,
      p_reason: "concedido pelo painel",
    })) as any;
    await send(
      ctx,
      `✅ <b>SUCESSO</b>\n\nJogador: <code>${esc(tg)}</code>\nAção: herói <b>${esc(r.name)}</b> concedido\nInstância: <code>${esc(r.hero_id)}</code>`,
    );
    return userHeroesMenu({ ...ctx, messageId: undefined }, tg, 0);
  }
  if (head === "uhd") {
    const [tg, heroId] = rest;
    const d = (await rpc("admin_player_heroes", {
      p_admin_id: ctx.adminId,
      p_ref: tg,
      p_rarity: null,
      p_limit: 30,
      p_offset: 0,
    })) as any;
    const hero = arr<any>(d?.heroes).find((h) => h.id === heroId);
    if (!hero) return userHeroesMenu(ctx, tg, 0);
    const warn =
      hero.in_pvp || hero.in_boss
        ? "\n\n⚠️ Este herói está equipado" +
          (hero.in_pvp ? " no PvP" : "") +
          (hero.in_boss ? " no Boss" : "") +
          ". Ele será desequipado automaticamente."
        : "";
    return edit(
      ctx,
      `🗑 <b>REMOVER HERÓI</b>\n\nHerói: <b>${esc(hero.name)}</b>\nRaridade: ${esc(hero.rarity)}\nNível: ${hero.level} · ⭐${hero.fusion_level}${warn}\n\nO histórico (baús/fusões) é preservado.`,
      kb([
        [
          { t: "✅ REMOVER", d: `uhdok:${tg}:${heroId}` },
          { t: "❌ CANCELAR", d: `uh:${tg}:0` },
        ],
      ]),
    );
  }
  if (head === "uhdok") {
    const [tg, heroId] = rest;
    const r = (await rpc("admin_remove_player_hero", {
      p_admin_id: ctx.adminId,
      p_hero_id: heroId,
      p_reason: "removido pelo painel",
    })) as any;
    await send(
      ctx,
      `✅ <b>SUCESSO</b>\n\nJogador: <code>${esc(tg)}</code>\nAção: herói <b>${esc(r.name)}</b> removido`,
    );
    return userHeroesMenu({ ...ctx, messageId: undefined }, tg, 0);
  }
  if (head === "ui") {
    await clearSession(ctx);
    return userItemsMenu(ctx, rest[0]);
  }
  if (head === "uia") {
    await clearSession(ctx);
    return itemPicker(ctx, rest[0], "a");
  }
  if (head === "uir") {
    await clearSession(ctx);
    return itemPicker(ctx, rest[0], "r");
  }
  if (head === "uiq") {
    const [tg, mode, ...keyParts] = rest;
    const key = keyParts.join(":");
    return ask(
      ctx,
      `itemqty|${tg}|${mode}|${key}`,
      `Envie a <b>quantidade</b> para ${mode === "a" ? "adicionar" : "remover"} de <code>${esc(key)}</code>.`,
    );
  }
  if (head === "up") {
    await clearSession(ctx);
    return userPetsMenu(ctx, rest[0]);
  }
  if (head === "upa") {
    const [tg, petId] = rest;
    await rpc("admin_set_player_active_pet", {
      p_admin_id: ctx.adminId,
      p_player_pet_id: petId,
      p_reason: "painel admin",
    });
    await send(ctx, `✅ <b>SUCESSO</b>\n\nJogador: <code>${esc(tg)}</code>\nAção: pet definido como ativo`);
    return userPetsMenu({ ...ctx, messageId: undefined }, tg);
  }
  if (head === "upd") {
    const [tg, petId] = rest;
    return edit(
      ctx,
      `🗑 <b>REMOVER PET</b>\nJogador <code>${esc(tg)}</code>\nPet <code>${esc(petId)}</code>\n\nO histórico de evoluções é preservado.`,
      kb([
        [
          { t: "✅ REMOVER", d: `updok:${tg}:${petId}` },
          { t: "❌ CANCELAR", d: `up:${tg}` },
        ],
      ]),
    );
  }
  if (head === "updok") {
    const [tg, petId] = rest;
    await rpc("admin_remove_pet", {
      p_admin_id: ctx.adminId,
      p_player_pet_id: petId,
      p_reason: "removido pelo painel",
    });
    await send(ctx, `✅ <b>SUCESSO</b>\n\nJogador: <code>${esc(tg)}</code>\nAção: pet removido`);
    return userPetsMenu({ ...ctx, messageId: undefined }, tg);
  }

  if (head === "passlvtoggle") {
    await clearSession(ctx);
    const enabled = rest[0] === "on";
    await rpc("admin_set_pass_level_purchase", {
      p_admin_id: ctx.adminId,
      p_patch: { enabled },
      p_reason: "painel admin",
    });
    return module(ctx, "passlevels");
  }
  // withdrawals: every financial action is resolved by withdrawal_id, never by username.
  if (head === "pa") {
    await clearSession(ctx);
    return handlePayoutAnnouncements(ctx, rest[0] || "menu");
  }
  if (head === "pasend") {
    await clearSession(ctx);
    const r = await announcePayout(ctx.adminId, rest.join(":"));
    await send(
      ctx,
      r.status === "sent"
        ? "📢 Comprovante publicado no canal de pagamentos."
        : r.status === "skipped"
          ? `🚫 Não publicado: <code>${esc(r.detail)}</code>`
          : `⚠️ Falha: <code>${esc(r.detail)}</code>`,
    );
    return withdrawalCard(ctx, rest.join(":"), false);
  }
  if (["wd", "wdcp", "wdpay", "wdgo", "wdmk", "wdfail", "wdrj", "wdrjgo"].includes(head)) {
    await clearSession(ctx);
    return handleWithdrawal(ctx, head, rest.join(":"));
  }
  if (head === "wdlist") {
    const status = rest[0] === "paid" ? "paid" : rest[0];
    const d = await rpc("admin_list_withdrawals", { p_admin_id: ctx.adminId, p_status: status, p_limit: 12 });
    const buttons = (d.items as any[])
      .slice(0, 8)
      .map((w) => [{ t: `👁 ${w.short_id} · ${fmt(w.amount_ton)} TON`, d: `wd:${w.id}` }]);
    return edit(
      ctx,
      `💸 <b>WITHDRAWALS</b> — ${esc(String(status).toUpperCase())}\n\n${withdrawalLines(d.items)}`,
      kb([
        ...buttons,
        [
          { t: "🟡 PENDENTES", d: "wdlist:pending" },
          { t: "✅ PAGOS", d: "wdlist:paid" },
        ],
        nav("m:wallet"),
      ]),
    );
  }

  if (head === "poolgo") {
    const mode = rest[0] === "remove" ? "remove" : "add";
    const amount = parseAmount(rest[1]) * (mode === "remove" ? -1 : 1);
    if (!Number.isFinite(amount) || amount === 0) return send(ctx, "⚠️ Valor inválido.", MAIN_MENU);
    await clearSession(ctx);
    const r = await rpc("admin_adjust_pool_balance", { p_amount: amount, p_reason: "painel admin" });
    await rpc("admin_log", {
      p_admin_id: ctx.adminId,
      p_action: "pool.adjust",
      p_target_type: "pool",
      p_target_id: null,
      p_old: null,
      p_new: { amount },
      p_reason: "painel admin",
      p_context: { financial: true },
    });
    return send(
      ctx,
      `✅ Pool ajustada em <b>${amount} TON</b>.\n<code>${esc(JSON.stringify(r)).slice(0, 500)}</code>`,
      kb([[{ t: "💰 POOL", d: "m:pool" }], nav()]),
    );
  }

  if (head === "find") return playerCard(ctx, rest.join(":") || "");
  if (head === "pg") {
    const offset = Number(rest[0] || 0) || 0;
    const token = rest.slice(1).join(":");
    return playerSearch(ctx, token === "all" ? "" : token.replace(/^q:/, ""), offset);
  }
  if (head === "bpview") return passCard(ctx, rest[0]);
  if (head === "bp") return passConfirm(ctx, rest[0], rest[1]);
  if (head === "bpgo") return passApply(ctx, rest[0], rest[1]);
  if (head === "bphist") return passHistory(ctx);
  if (head === "do" && rest[0] === "snapshot") {
    const s = await rpc("admin_create_snapshot", { p_admin_id: ctx.adminId, p_label: "manual" });
    return send(ctx, `💾 Snapshot registrado: <code>${s.snapshot_id}</code>`, MAIN_MENU);
  }

  if (["fc", "ton"].includes(head))
    return ask(ctx, `bal|${head}|${rest[0]}|${rest[1]}`, `Envie o valor em ${head.toUpperCase()} (modo: ${rest[0]}).`);
  if (head === "st")
    return ask(ctx, `stat|${rest[0]}|${rest[1]}`, `Envie: <code>modo valor</code> (add/remove/set) para ${rest[0]}.`);
  if (head === "gh") return ask(ctx, `granthero|${rest[0]}`, "Envie: <code>hero_key [nível]</code>");
  if (head === "gp") return ask(ctx, `grantpet|${rest[0]}`, "Envie: <code>slug [raridade] [nível]</code>");
  if (head === "rh") return ask(ctx, "removehero", "Envie o ID do herói do jogador (uuid).");
  if (head === "rp") return ask(ctx, "removepet", "Envie o ID do pet do jogador (uuid).");
  if (head === "vip")
    return ask(ctx, `vip|${rest[0]}|${rest[1]}`, `Envie a quantidade de dias de ${rest[0].toUpperCase()} (0 remove).`);
  if (head === "ban") return ask(ctx, `ban|${rest[0]}`, "Envie o motivo do banimento (obrigatório).");
  if (head === "unban") {
    const r = await rpc("admin_set_ban", {
      p_admin_id: ctx.adminId,
      p_ref: rest[0],
      p_banned: false,
      p_reason: "desbanido pelo admin",
    });
    return send(ctx, `✅ Jogador desbanido (<code>${r.user_id}</code>).`, MAIN_MENU);
  }
  if (head === "reset")
    return send(
      ctx,
      "⚠️ Tem certeza que deseja <b>RESETAR</b> esta conta? A ação apaga heróis, pets e saldos.",
      kb([
        [
          { t: "✅ CONFIRMAR ALTERAÇÃO", d: `reset2:${rest[0]}` },
          { t: "❌ Cancelar", d: "home" },
        ],
      ]),
    );
  if (head === "reset2") return ask(ctx, `reset|${rest[0]}`, "Envie o motivo do reset (obrigatório).");
  if (head === "audit1") {
    // Deposit audit: TON in, FC credited, ledger cross-check. Read-only, never touches balances.
    const a = await rpc("audit_player_deposits", { p_telegram_id: Number(rest[0]) });
    const last = a.lastDeposit;
    const lines = [
      `🔎 <b>AUDIT DEPOSITS</b> — ${a.username ? "@" + esc(a.username) : esc(String(a.telegramId))}`,
      `FC balance: <b>${fmt(a.fcBalance)}</b>`,
      `Rate: 1 TON = <b>${fmt(a.rate)} FC</b>`,
      `Total TON deposited: <b>${fmt(a.totalTonDeposited)} TON</b>`,
      `Total FC credited from deposits: <b>${fmt(a.totalFcCreditedFromDeposits)}</b>`,
      `Ledger FC from deposits: <b>${fmt(a.ledgerFcFromDeposits)}</b> ${a.mismatch ? "⚠️ DIVERGÊNCIA" : "✅"}`,
      `Depósitos pendentes: ${fmt(a.pendingCount)}`,
      last
        ? `Último depósito: <b>${fmt(last.amountTon)} TON</b> → ${fmt(last.amountFc)} FC\nStatus: <b>${esc(String(last.status).toUpperCase())}</b>\nTX: <code>${esc(String(last.txHash || "—"))}</code>`
        : "Último depósito: —",
    ];
    return send(ctx, lines.join("\n"), MAIN_MENU);
  }
  if (head === "hist") {
    const h = await rpc("admin_player_history", { p_admin_id: ctx.adminId, p_ref: rest[0], p_limit: 15 });
    return send(
      ctx,
      `📜 <b>Histórico</b>\n${h.events.map((e: any) => `• ${String(e.at).slice(5, 16).replace("T", " ")} ${esc(e.action)} — ${esc(JSON.stringify(e.old))} → ${esc(JSON.stringify(e.new))}`).join("\n") || "—"}`,
      MAIN_MENU,
    );
  }
  if (head === "tree") {
    const t = await rpc("admin_referral_tree", { p_admin_id: ctx.adminId, p_ref: rest[0] });
    const lines = t.levels.map(
      (l: any) =>
        `${"   ".repeat(l.level - 1)}└ N${l.level} ${esc(l.user.name)} ${l.user.username ? "@" + esc(l.user.username) : ""} — ${fmt(l.user.deposited_ton)} TON`,
    );
    return send(
      ctx,
      `🌳 <b>Árvore de convites</b>\n${lines.join("\n") || "—"}\n\n💸 Comissão total: <b>${Number(t.total_commission_ton ?? 0).toFixed(3)} TON</b>\n${t.commissions.map((c: any) => `• N${c.level} ${Number(c.amount_ton ?? 0).toFixed(3)} TON de ${esc(c.from)} (${esc(String(c.source_type || "purchase"))} ${Number(c.source_amount_ton ?? 0).toFixed(3)} TON)`).join("\n")}`,
      MAIN_MENU,
    );
  }
  if (head === "hs") {
    const view = rest[0];
    if (view === "prices") return heroPricesView(ctx);
    if (view === "odds") return heroOddsView(ctx);
    if (view === "roddz") return heroRealOddsView(ctx);
    if (view === "list") return module(ctx, "herolist");
    if (view === "store") return module(ctx, "store");
    if (view === "fusion") return fusionView(ctx);
    if (view === "resetp" || view === "reseto") {
      const scope = view === "resetp" ? "prices" : "odds";
      return send(
        ctx,
        `⚠️ Restaurar o padrão de <b>${scope === "prices" ? "preços (25.000 / 125.000 / 250.000 FC)" : "chances (62 / 25 / 10 / 2,7 / 0,3)"}</b>?`,
        kb([
          [
            { t: "✅ CONFIRMAR", d: `hsr:${scope}` },
            { t: "❌ CANCELAR", d: "m:shop" },
          ],
        ]),
      );
    }
    return heroShopHub(ctx);
  }
  if (head === "hr") {
    const view = rest[0];
    if (view === "v") return rarityFlagDetail(ctx, rest[1]);
    if (view === "set") {
      const rarity = rest[1];
      const enabled = rest[2] === "1";
      try {
        await rpc("admin_set_hero_rarity_enabled", { p_admin_id: ctx.adminId, p_rarity: rarity, p_enabled: enabled });
      } catch (e) {
        const msg = String((e as Error)?.message || e);
        if (msg.includes("LAST_ACTIVE_RARITY")) {
          await send(ctx, "⚠️ É preciso manter pelo menos uma raridade ativa com heróis no pool.");
          return rarityFlagDetail(ctx, rarity);
        }
        throw e;
      }
      await send(ctx, `${RARITY_LABEL[rarity]}\nStatus: ${enabled ? "🟢 ATIVO" : "🔴 DESATIVADO"}`);
      return rarityFlagsView(ctx);
    }
    return rarityFlagsView(ctx);
  }
  if (head === "rf") {
    const view = rest[0];
    if (view === "audit") return rarityFusionAudit(ctx);
    if (view === "on" || view === "off") {
      await rpc("admin_set_rarity_fusion_enabled", { p_admin_id: ctx.adminId, p_enabled: view === "on" });
      await send(ctx, view === "on" ? "✅ Rarity Fusion ativada." : "⛔ Rarity Fusion desativada.");
      return rarityFusionView(ctx);
    }
    return rarityFusionView(ctx);
  }
  if (head === "fusr") {
    const r = await rpc("admin_set_fusion_config", {
      p_admin_id: ctx.adminId,
      p_patch: {
        max_stars: 5,
        bonus_percent: { "1": 5, "2": 5, "3": 7, "4": 8, "5": 10 },
        cost_fc: { "1": 5000, "2": 15000, "3": 35000, "4": 75000, "5": 150000 },
        duplicates: { "1": 5, "2": 5, "3": 5, "4": 5, "5": 5 },
        level_cap: { "0": 20, "1": 20, "2": 25, "3": 25, "4": 30, "5": 35 },
      },
      p_reason: "reset padrão (bot)",
    });
    return send(
      ctx,
      `✅ Fusão restaurada ao padrão (★${r.max_stars}).`,
      kb([[{ t: "🧬 DUPLICATE FUSE SETTINGS", d: "hs:fusion" }], nav("m:shop")]),
    );
  }
  if (head === "hsr") {
    const r = await rpc("admin_reset_hero_shop", { p_admin_id: ctx.adminId, p_scope: rest[0] });
    return send(
      ctx,
      `🔄 Padrão restaurado.\n1x ${fmt(r.prices["1"])} · 5x ${fmt(r.prices["5"])} · 10x ${fmt(r.prices["10"])} FC\n${RARITY_ORDER.map((k) => `${RARITY_LABEL[k]} ${pct(r.odds[k])}%`).join(" · ")}`,
      kb([[{ t: "🏪 LOJA DE HERÓIS", d: "m:shop" }], nav()]),
    );
  }
  if (head === "hp") {
    const count = Number(rest[0]);
    const cfg = await heroShopConfig(ctx);
    return ask(
      ctx,
      `hprice|${count}`,
      `Preço atual do <b>${count}x</b>: <b>${fmt(cfg.config.prices[String(count)])} FC</b>\n\nEnvie o novo preço em FC. Ex.: <code>30000</code>`,
    );
  }
  if (head === "hpok") {
    const count = Number(rest[0]);
    const before = (await heroShopConfig(ctx)).config.prices[String(count)];
    const r = await rpc("admin_set_hero_recruit_price", {
      p_admin_id: ctx.adminId,
      p_count: count,
      p_price: Number(rest[1]),
      p_reason: "painel admin (bot)",
    });
    return send(
      ctx,
      `✅ <b>${count}x</b> atualizado.\nAntes: ${fmt(before)} FC\nDepois: <b>${fmt(r.prices[String(count)])} FC</b>\n\nJá está valendo na loja do jogo.`,
      kb([[{ t: "💰 PREÇOS", d: "hs:prices" }], nav("m:shop")]),
    );
  }
  if (head === "ho") {
    const rarity = rest[0];
    const cfg = await heroShopConfig(ctx);
    return ask(
      ctx,
      `hodd|${rarity}`,
      `Chance atual de <b>${RARITY_LABEL[rarity]}</b>: <b>${pct(cfg.config.odds[rarity])}%</b>\n\nEnvie a nova porcentagem (ex.: <code>60</code> ou <code>2.5</code>). O total das 6 raridades (Ancestral fica em 0%) precisa fechar 100%.`,
    );
  }
  if (head === "hoc") {
    const rarity = rest[0];
    const cfg = await heroShopConfig(ctx);
    const rates: Record<string, number> = {};
    for (const k of RARITY_ORDER) rates[k] = Number(cfg.config.odds[k] ?? 0);
    rates.ancestral = 0;
    rates[rarity] = Number(rest[1]);
    const r = await rpc("admin_set_hero_summon_rates", {
      p_admin_id: ctx.adminId,
      p_rates: rates,
      p_reason: "painel admin (bot)",
    });
    return send(
      ctx,
      `✅ <b>${RARITY_LABEL[rarity]}</b>: ${pct(cfg.config.odds[rarity])}% → <b>${pct(r.odds[rarity])}%</b>\n\n${RARITY_ORDER.map((k) => `${RARITY_LABEL[k]} ${pct(r.odds[k])}%`).join(" · ")}`,
      kb([[{ t: "🎲 CHANCES", d: "hs:odds" }], nav("m:shop")]),
    );
  }
  if (head === "auc") {
    const [sub, arg] = String(rest[0] || "").split("|");
    if (sub === "toggle") {
      await rpc("admin_auction_set", { p_telegram_id: ctx.adminId, p_key: "enabled", p_value: arg === "on" });
      return auctionHub(ctx);
    }
    if (sub === "snipe") {
      await rpc("admin_auction_set", { p_telegram_id: ctx.adminId, p_key: "antiSnipeEnabled", p_value: arg === "on" });
      return auctionHub(ctx);
    }
    return auctionHub(ctx);
  }
  if (head === "mk") {
    const [sub, arg] = String(rest[0] || "").split("|");
    if (sub === "audit") return marketAudit(ctx);
    if (sub === "revenue") return marketRevenue(ctx);
    if (sub === "toggle") {
      const on = arg === "on";
      return edit(
        ctx,
        on
          ? "⚠️ <b>ATIVAR MARKETPLACE?</b>\n\nTodos os jogadores voltarão a acessar o mercado imediatamente."
          : "⚠️ <b>DESATIVAR MARKETPLACE?</b>\n\nJogadores comuns não poderão acessar o mercado.\nO Admin de testes continuará com acesso.",
        kb([[{ t: "✅ CONFIRMAR", d: `mk:doToggle|${on ? "on" : "off"}` }], [{ t: "❌ CANCELAR", d: "m:market" }]]),
      );
    }
    if (sub === "doToggle") {
      const on = arg === "on";
      const st = (await rpc("admin_market_set_enabled", { p_admin_id: ctx.adminId, p_enabled: on })) as any;
      return edit(
        ctx,
        on
          ? "✅ <b>Marketplace ativado para todos os jogadores.</b>"
          : `✅ <b>Marketplace desativado.</b>\n\nModo manutenção ativo para jogadores.\nAdmin bypass: <b>${fmt(st?.bypassCount ?? 1)}</b> user(s)`,
        kb([[{ t: "🛒 MARKETPLACE", d: "m:market" }], nav()]),
      );
    }
    if (sub === "list") return marketHub(ctx, arg || "active");
    // ---- 🛡 security surface (risk queue, escrow, price bands, restrictions)
    if (sub === "sec") return mkSecurityHub(ctx);
    if (sub === "review") return mkReviewQueue(ctx);
    if (sub === "ranges") return mkRanges(ctx);
    if (sub === "secaudit") return mkSecurityAudit(ctx);
    if (sub === "trade") return mkTradeCard(ctx, arg || "");
    if (sub === "appr") {
      return edit(
        ctx,
        "⚠️ <b>APROVAR NEGOCIAÇÃO?</b>\n\nO valor sai do escrow e é pago ao vendedor imediatamente.",
        kb([[{ t: "✅ CONFIRMAR", d: `mk:doAppr|${arg}` }], [{ t: "❌ CANCELAR", d: "mk:review" }]]),
      );
    }
    if (sub === "doAppr") {
      await rpc("admin_market_approve_trade", { p_admin_id: ctx.adminId, p_transaction_id: arg });
      return edit(
        ctx,
        "✅ <b>Negociação aprovada e liquidada.</b>",
        kb([[{ t: "🚨 FILA DE REVISÃO", d: "mk:review" }], nav("mk:sec")]),
      );
    }
    if (sub === "rev") {
      return edit(
        ctx,
        "⚠️ <b>REVERTER NEGOCIAÇÃO?</b>\n\nO item volta ao vendedor e os FC voltam ao comprador.",
        kb([[{ t: "✅ CONFIRMAR", d: `mk:doRev|${arg}` }], [{ t: "❌ CANCELAR", d: "mk:review" }]]),
      );
    }
    if (sub === "doRev") {
      await rpc("admin_market_reverse_trade", {
        p_admin_id: ctx.adminId,
        p_transaction_id: arg,
        p_reason: "revertida pelo admin (bot)",
      });
      return edit(
        ctx,
        "↩️ <b>Negociação revertida.</b>\n\nItem devolvido ao vendedor e FC devolvidos ao comprador.",
        kb([[{ t: "🚨 FILA DE REVISÃO", d: "mk:review" }], nav("mk:sec")]),
      );
    }
    return marketHub(ctx);
  }

  if (head === "ref") return ask(ctx, `ref|${rest[0]}`, `Envie a nova porcentagem do nível ${rest[0]} (0-100).`);

  if (head === "pool")
    return ask(ctx, `pool|${rest[0]}`, `Envie o valor em TON para ${rest[0] === "add" ? "adicionar" : "remover"}.`);
  if (head === "rank") {
    const d = await rpc("admin_pvp_overview", { p_admin_id: ctx.adminId, p_top: Number(rest[0]) });
    return send(
      ctx,
      `📈 <b>TOP ${rest[0]}</b>\n${d.ranking
        .map((r: any, i: number) => `${i + 1}. ${esc(r.name)} — ${fmt(r.trophies)}🏆`)
        .join("\n")
        .slice(0, 3500)}`,
      MAIN_MENU,
    );
  }
  if (head === "view") {
    if (rest[0] === "questrepair") {
      // Recreates/reactivates only the five default daily quests. Never duplicates, never touches player progress.
      const r = await rpc("admin_repair_daily_quests", { p_admin_id: ctx.adminId });
      return send(
        ctx,
        `🔄 <b>DAILY QUESTS REPARADAS</b>\nQuests ativas agora: <b>${fmt(r.activeDailyCount)}</b>\nO progresso dos jogadores foi preservado.`,
        kb([[{ t: "🎯 DAILY QUESTS", d: "m:quests" }], nav()]),
      );
    }
    if (rest[0] === "chests") {
      const d = await rpc("admin_chest_diagnostics", { p_admin_id: ctx.adminId });
      const chests =
        (d.chests || [])
          .map((c: any) => {
            const missing = c.missing || [];
            const status = !c.enabled
              ? "⛔ disabled"
              : missing.length
                ? `⚠️ NO ACTIVE HEROES (${missing.map(esc).join(", ")})`
                : "✅ configured";
            const rates = Object.entries(c.rates || {})
              .map(([k, v]) => `${esc(k)} ${v}%`)
              .join(" · ");
            return `📦 <b>${esc(String(c.code).toUpperCase())}</b>\n   ${status}\n   ${rates || "sem taxas"}`;
          })
          .join("\n") || "—";
      const pools = Object.entries(d.heroPools || {})
        .map(([k, v]) => `• ${esc(k)}: ${Number(v) > 0 ? fmt(Number(v)) : "⚠️ NO ACTIVE HEROES"}`)
        .join("\n");
      return send(
        ctx,
        `📦 <b>DIAGNÓSTICO DOS BAÚS</b>\n${chests}\n\n🦸 <b>HERÓIS ATIVOS POR RARIDADE</b>\n${pools}`,
        kb([[{ t: "🎁 DEFINIR BAÚ 5/5", d: "ask:questbonus" }], nav("m:quests")]),
      );
    }
    const cfg = await rpc("admin_pet_config", { p_admin_id: ctx.adminId });
    if (rest[0] === "eggs")
      return send(
        ctx,
        `🥚 <b>OVOS</b>\n${cfg.eggs.map((e: any) => `• ${esc(e.name)} <code>${e.slug ?? e.id}</code> — ${fmt(e.price_fc)} FC / ${e.price_ton ?? "—"} TON ${e.is_enabled ? "✅" : "⛔"}\n   ${esc(JSON.stringify(e.rarity_rates))}`).join("\n")}`,
        kb([
          [{ t: "💰 PREÇO DO OVO", d: "ask:eggprice" }],
          [{ t: "✏️ EDITAR OVO (JSON)", d: "ask:egg" }],
          nav("m:pets"),
        ]),
      );
    if (rest[0] === "foods")
      return send(
        ctx,
        `🍖 <b>COMIDAS</b>\n${cfg.food.map((f: any) => `• <code>${esc(f.code)}</code> ${esc(f.name)} — +${fmt(f.xp_value)} XP · ${fmt(f.price_fc ?? 0)} FC ${f.enabled ? "✅" : "⛔"}`).join("\n")}`,
        kb([
          [{ t: "💰 PREÇO DA COMIDA", d: "ask:foodprice" }],
          [{ t: "✏️ CRIAR/EDITAR COMIDA", d: "ask:food" }],
          nav("m:pets"),
        ]),
      );
    if (rest[0] === "tiers")
      return send(
        ctx,
        `🧬 <b>EVOLUÇÃO</b>\n${cfg.tiers.map((t: any) => `• Tier ${t.tier} ${esc(t.label)} — NV${t.required_level} · ${fmt(t.fc_cost)} FC · ${t.fragment_cost} frag · x${t.primary_multiplier} · novo buff ${Math.round(t.new_buff_chance * 100)}%`).join("\n")}`,
        MAIN_MENU,
      );
    if (rest[0] === "leagues") {
      const d = await rpc("admin_pvp_overview", { p_admin_id: ctx.adminId, p_top: 1 });
      return send(
        ctx,
        `🏅 <b>LIGAS</b>\n${d.leagues.map((l: any) => `• <code>${esc(l.code)}</code> ${esc(l.icon)} ${esc(l.name)} — ${l.min_trophies}–${l.max_trophies ?? "∞"} ${l.enabled ? "✅" : "⛔"}`).join("\n")}`,
        kb([[{ t: "✏️ EDITAR LIGA", d: "ask:league" }], nav("m:pvp")]),
      );
    }
    if (rest[0] === "passxp") {
      const d = await rpc("admin_pass_overview", { p_admin_id: ctx.adminId });
      const { data: rows } = await db
        .from("game_settings")
        .select("key,value")
        .in("key", ["season_pass_xp", "season_pass_xp_multipliers", "season_pass_xp_caps"]);
      const bag = Object.fromEntries((rows ?? []).map((r: any) => [r.key, r.value ?? {}])) as Record<
        string,
        Record<string, number>
      >;
      const cfg = bag["season_pass_xp"] ?? {},
        mult = bag["season_pass_xp_multipliers"] ?? {},
        caps = bag["season_pass_xp_caps"] ?? {};
      const labels: Record<string, string> = {
        daily_login: "Login diário",
        daily_quest: "Missão diária concluída",
        daily_quest_all: "Bônus 5/5 missões",
        daily_chest: "Baú diário das missões",
        pvp_battle: "Batalha PvP",
        pvp_victory: "Vitória PvP",
        boss_attack: "Participação no chefe",
        boss_damage_milestone: "Marco de dano no chefe",
        boss_reward: "Recompensa do chefe",
        boss_defeated: "Chefe derrotado",
        reward_open: "Abrir baú/ovo",
        pet_feed: "Alimentar pet",
        pet_level_up: "Pet subiu de nível",
        pet_evolution: "Evolução de pet",
        hero_fuse: "Fusão de duplicados",
        rarity_fusion: "Fusão de raridade (tentativa)",
        rarity_fusion_success: "Fusão de raridade (sucesso)",
        calendar_claim: "Resgate do calendário",
      };
      const lines = Object.keys(labels)
        .map(
          (k) =>
            `• ${labels[k]} (<code>${k}</code>): <b>${fmt(Number(cfg[k] ?? 0))} XP</b>${caps[k] != null ? ` · cap ${fmt(Number(caps[k]))}/dia` : ""}`,
        )
        .join("\n");
      const multLine = `• FREE <b>x${Number(mult.none ?? 1)}</b> · ADVENTURER <b>x${Number(mult.adventurer ?? 1.2)}</b> · LEGENDARY <b>x${Number(mult.legendary ?? 1.4)}</b>`;
      return send(
        ctx,
        `⚡ <b>XP SETTINGS</b>\nXP por nível: <b>${fmt(d.season?.xp_per_level ?? 0)}</b> · Níveis: <b>${fmt(d.season?.levels ?? 0)}</b>\n\n<b>MULTIPLICADORES</b>\n${multLine}\n\n<b>XP POR AÇÃO</b>\n${lines}\n\nTodos os jogadores ganham XP; o passe apenas acelera a progressão.`,
        kb([
          [{ t: "✏️ EDITAR XP DE AÇÃO", d: "ask:passxp" }],
          [{ t: "✖️ MULTIPLICADORES", d: "ask:passxpmult" }],
          [{ t: "🚧 LIMITES DIÁRIOS", d: "ask:passxpcap" }],
          [{ t: "🎚 XP POR NÍVEL", d: "ask:passxplevel" }],
          nav("m:pass"),
        ]),
      );
    }
    if (rest[0] === "pvptickets") {
      const d = await rpc("admin_pvp_overview", { p_admin_id: ctx.adminId, p_top: 1 });
      const packs = Object.entries(d.settings.packs || {}).sort((a, b) => Number(a[0]) - Number(b[0]));
      return send(
        ctx,
        `🎟 <b>TICKET SETTINGS</b>\nLimite diário FREE: <b>${fmt(d.settings.free_daily_limit)}</b>\nLimite diário PASSE: <b>${fmt(d.settings.pass_daily_limit)}</b>\n\n<b>PACOTES</b>\n${packs.map(([k, v]) => `• ${k} ticket(s) — ${fmt(Number(v))} FC`).join("\n") || "—"}\n\nVendidos hoje: ${fmt(d.tickets_sold_today)} tickets · ${fmt(d.fc_spent_today)} FC`,
        kb([
          [
            { t: "🔢 LIMITE FREE", d: "ask:tkfree" },
            { t: "🔢 LIMITE PASSE", d: "ask:tkpass" },
          ],
          [{ t: "💰 PREÇO DO PACOTE", d: "ask:tkpack" }],
          nav("m:pvp"),
        ]),
      );
    }
  }
  if (head === "passfix") {
    const target = rest[0] && rest[0] !== "all" ? Number(rest[0]) : null;
    const r = await rpc("admin_repair_missing_pass_rewards", { p_telegram_id: target, p_dry_run: false });
    const details = (r?.details || []) as any[];
    const lines = details
      .slice(0, 25)
      .map(
        (d) =>
          `• <code>${d.telegramId}</code> Lv.${d.level} · ${esc(String(d.slot))} → <code>${esc(String(d.item ?? "—"))}</code>`,
      );
    return send(
      ctx,
      `🛠 <b>FIX MISSING REWARDS</b>\nCorrigidas: <b>${fmt(Number(r?.fixed ?? 0))}</b>\n\n${lines.join("\n") || "Nada a corrigir."}`,
      kb([[{ t: "🔄 REVERIFICAR", d: "view:passmissing" }], nav("m:pass")]),
    );
  }
  if (head === "passxp") {
    const [mode, user] = rest;
    if (mode === "level")
      return ask(ctx, `passlevel|${user}`, "Envie o <b>nível</b> desejado do Battle Pass (ex.: <code>8</code>).");
    return ask(
      ctx,
      `passxpadj|${mode}|${user}`,
      `Envie a quantidade de <b>XP</b> para ${mode === "remove" ? "remover" : "adicionar"} (ex.: <code>500</code>).`,
    );
  }
  if (head === "maint") {
    await rpc("admin_set_setting", {
      p_admin_id: ctx.adminId,
      p_key: "maintenance_mode",
      p_value: rest[0] === "on",
      p_reason: "painel admin",
    });
    return module(ctx, "maint");
  }
  if (head === "cast") return ask(ctx, `cast|${rest[0]}`, `Envie a mensagem para o público <b>${rest[0]}</b>.`);
  if (head === "castgo") {
    const [seg, ...msg] = rest;
    const t = await rpc("admin_broadcast_targets", { p_admin_id: ctx.adminId, p_segment: seg, p_limit: 2000 });
    const text = decodeURIComponent(msg.join(":"));
    let ok = 0;
    for (const id of t.targets) {
      await tg("sendMessage", { chat_id: id, text });
      ok += 1;
    }
    await rpc("admin_log", {
      p_admin_id: ctx.adminId,
      p_action: "broadcast.send",
      p_target_type: "system",
      p_target_id: seg,
      p_old: null,
      p_new: { sent: ok },
      p_reason: null,
      p_context: {},
    });
    return send(ctx, `📣 Enviado para ${ok} jogadores.`, MAIN_MENU);
  }

  if (head === "confirm") {
    const map: Record<string, string> = {
      pvpreset: "RESETAR a temporada de PvP (todos os troféus voltam a 0)",
      pooldist: "DISTRIBUIR a pool comunitária agora",
      poolcancel: "CANCELAR o ciclo atual da pool",
      bossend: "ENCERRAR o chefe ativo",
      bosshp: "RESETAR o HP dos chefes ativos",
      questreset: "RESETAR as daily quests de hoje (progresso e resgates)",
      missdaily: "RESETAR as missões diárias",
      missweekly: "RESETAR as missões semanais",
    };
    return send(
      ctx,
      `⚠️ Tem certeza que deseja <b>${map[rest[0]]}</b>?`,
      kb([
        [
          { t: "✅ CONFIRMAR ALTERAÇÃO", d: `run:${rest[0]}` },
          { t: "❌ Cancelar", d: "home" },
        ],
      ]),
    );
  }
  if (head === "run") {
    const key = rest[0];
    if (key === "pvpreset") {
      const r = await rpc("admin_reset_pvp_season", {
        p_admin_id: ctx.adminId,
        p_reason: "reset de temporada pelo admin",
      });
      return send(ctx, `✅ Temporada resetada (${fmt(r.players_reset)} jogadores).`, MAIN_MENU);
    }
    if (key === "pooldist") {
      await rpc("admin_create_snapshot", { p_admin_id: ctx.adminId, p_label: "pre_pool_distribution" });
      const r = await rpc("distribute_community_pool", { p_force: true });
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "pool.distribute",
        p_target_type: "pool",
        p_target_id: null,
        p_old: null,
        p_new: r,
        p_reason: "distribuição manual",
        p_context: { financial: true },
      });
      return send(ctx, `✅ Pool distribuída.\n<code>${esc(JSON.stringify(r)).slice(0, 800)}</code>`, MAIN_MENU);
    }
    if (key === "poolcancel") {
      const r = await rpc("admin_cancel_pool", {});
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "pool.cancel",
        p_target_type: "pool",
        p_target_id: null,
        p_old: null,
        p_new: r,
        p_reason: null,
        p_context: {},
      });
      return send(ctx, "✅ Ciclo cancelado.", MAIN_MENU);
    }
    if (key === "bossend") {
      const r = await rpc("admin_boss_control", {
        p_admin_id: ctx.adminId,
        p_action: "end",
        p_code: null,
        p_reason: "encerrado pelo admin",
      });
      return send(ctx, `✅ Chefes encerrados (${r.affected}).`, MAIN_MENU);
    }
    if (key === "bosshp") {
      const r = await rpc("admin_boss_control", {
        p_admin_id: ctx.adminId,
        p_action: "reset_hp",
        p_code: null,
        p_reason: "reset de HP",
      });
      return send(ctx, `✅ HP resetado (${r.affected}).`, MAIN_MENU);
    }
    if (key === "questreset") {
      const r = await rpc("admin_reset_quests", { p_admin_id: ctx.adminId, p_reason: "reset manual das daily quests" });
      return send(
        ctx,
        `✅ Daily quests resetadas (${fmt(r.cleared)} registros).`,
        kb([[{ t: "🎯 DAILY QUESTS", d: "m:quests" }], nav()]),
      );
    }
    if (key.startsWith("miss")) {
      const scope = key === "missdaily" ? "daily" : "weekly";
      const r = await rpc("admin_reset_missions", {
        p_admin_id: ctx.adminId,
        p_scope: scope,
        p_reason: "reset manual",
      });
      return send(ctx, `✅ Missões ${scope} resetadas (${r.cleared}).`, MAIN_MENU);
    }
  }
  return send(ctx, "Comando não reconhecido.", MAIN_MENU);
}

// ---------------------------------------------------------------- 💰 SPENDING EVENT
// Tracking-only module: it never touches prices, payments, PvP or the wallet.
// Every number comes from the RPCs, which count confirmed spends exclusively.
const spPoints = (n: unknown) => Number(n ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 0 });

async function spendOverview(ctx: Ctx) {
  return (await rpc("admin_spending_event_overview", { p_admin_id: ctx.adminId })) as any;
}

async function spendHub(ctx: Ctx, editing = true) {
  const d = await spendOverview(ctx);
  const ev = d?.event;
  const totals = d?.totals || {};
  const body = ev
    ? [
        `💰 <b>SPENDING EVENT</b>`,
        ``,
        `🏷 <b>${esc(ev.name)}</b> · status <b>${esc(String(ev.status).toUpperCase())}</b>`,
        `🕒 ${String(ev.startsAt).slice(0, 16).replace("T", " ")} → ${String(ev.endsAt).slice(0, 16).replace("T", " ")}`,
        `🔁 1 TON = <b>${spPoints(ev.tonRateFc)}</b> pontos`,
        ``,
        `📊 Pontos totais: <b>${spPoints(totals.points)}</b>`,
        `🪙 FC gastos: <b>${spPoints(totals.fcSpent)}</b>`,
        `💎 TON gastos: <b>${Number(totals.tonSpent ?? 0)}</b>`,
        `👥 Participantes: <b>${spPoints(totals.participants)}</b>`,
      ].join("\n")
    : "💰 <b>SPENDING EVENT</b>\n\nNenhum evento criado ainda.";
  const rows = [
    [
      { t: "📊 ACTIVE EVENT", d: "sp:hub" },
      { t: "➕ CREATE EVENT", d: "sp:new" },
    ],
    [
      { t: "▶️ START EVENT", d: "sp:start" },
      { t: "⏹ END EVENT", d: "sp:end" },
    ],
    [
      { t: "📅 DURATION", d: "sp:dur" },
      { t: "🎁 REWARDS", d: "sp:rw" },
    ],
    [
      { t: "🏆 VIEW RANKING", d: "sp:rank" },
      { t: "✅ VALID SPEND TYPES", d: "sp:types" },
    ],
    [
      { t: "📣 ENTRY POPUP", d: "sp:popup" },
      { t: "⚖️ POINT RULES", d: "sp:rules" },
    ],
    [
      { t: "🔒 FINALIZE", d: "sp:fin" },
      { t: "📜 AUDIT", d: "sp:audit" },
    ],
    nav(),
  ];
  return editing ? edit(ctx, body, kb(rows)) : send(ctx, body, kb(rows));
}

// Entry popup: purely cosmetic in-game highlight. It never changes points or rewards.
async function spendPopupMenu(ctx: Ctx) {
  const r = (await rpc("admin_spending_event_popup_config", { p_admin_id: ctx.adminId })) as any;
  const cfg = r?.config || {};
  const on = cfg.enabled !== false;
  const freq = String(cfg.frequency || "daily");
  const body = [
    "📣 <b>SPENDING EVENT POPUP</b>",
    "",
    `Status: <b>${on ? "ON" : "OFF"}</b>`,
    `Frequência: <b>${freq === "event" ? "ONCE PER EVENT" : "ONCE PER DAY"}</b>`,
    "",
    "O aviso aparece na Vila quando existe evento <b>ativo</b> e pode ser fechado a qualquer momento.",
  ].join("\n");
  return edit(
    ctx,
    body,
    kb([
      [{ t: on ? "🔴 DESLIGAR" : "🟢 LIGAR", d: `sp:popset:${on ? "off" : "on"}` }],
      [{ t: `${freq === "daily" ? "✅ " : ""}ONCE PER DAY`, d: "sp:popfreq:daily" }],
      [{ t: `${freq === "event" ? "✅ " : ""}ONCE PER EVENT`, d: "sp:popfreq:event" }],
      [{ t: "⬅️ SPENDING EVENT", d: "sp:hub" }],
      nav(),
    ]),
  );
}

async function spendRanking(ctx: Ctx) {
  const d = await spendOverview(ctx);
  if (!d?.event) return spendHub(ctx);
  const r = (await rpc("admin_spending_event_ranking", {
    p_admin_id: ctx.adminId,
    p_event_id: d.event.id,
    p_limit: 20,
  })) as any;
  const list =
    (r?.ranking || [])
      .map(
        (row: any) =>
          `#${row.position} ${esc(row.username ? "@" + row.username : row.name)}\n   <b>${spPoints(row.points)}</b> pts · ${spPoints(row.fcSpent)} FC · ${Number(row.tonSpent ?? 0)} TON`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `🏆 <b>RANKING — SPENDING EVENT</b>\n\n${list.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "sp:rank" }], [{ t: "⬅️ SPENDING EVENT", d: "sp:hub" }], nav()]),
  );
}

async function spendRewards(ctx: Ctx) {
  const d = await spendOverview(ctx);
  if (!d?.event) return spendHub(ctx);
  const rows = await db
    .from("spending_event_rewards")
    .select("position_from, position_to, label, event_id")
    .or(`event_id.eq.${d.event.id},event_id.is.null`)
    .order("position_from", { ascending: true });
  const own = (rows.data || []).filter((x: any) => x.event_id === d.event.id);
  const list =
    (own.length ? own : (rows.data || []).filter((x: any) => !x.event_id))
      .map(
        (x: any) =>
          `${x.position_from === x.position_to ? "#" + x.position_from : "#" + x.position_from + "–#" + x.position_to} → ${esc(x.label)}`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `🎁 <b>RECOMPENSAS DO SPENDING EVENT</b>\n\n${list.slice(0, 3400)}`,
    kb([[{ t: "✏️ EDITAR POSIÇÃO", d: "sp:ask:spreward" }], [{ t: "⬅️ SPENDING EVENT", d: "sp:hub" }], nav()]),
  );
}

async function spendAudit(ctx: Ctx) {
  const d = await spendOverview(ctx);
  if (!d?.event) return spendHub(ctx);
  const r = (await rpc("admin_spending_event_audit", {
    p_admin_id: ctx.adminId,
    p_event_id: d.event.id,
    p_limit: 15,
  })) as any;
  const list =
    (r?.entries || [])
      .map(
        (e: any) =>
          `• ${String(e.createdAt).slice(5, 16).replace("T", " ")} ${esc(e.player || "—")}\n   <code>${esc(e.sourceType)}</code> ${Number(e.originalAmount)} ${esc(e.currency)} → <b>${spPoints(e.points)}</b> pts`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `📜 <b>AUDITORIA DE GASTOS</b>\n\n${list.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "sp:audit" }], [{ t: "⬅️ SPENDING EVENT", d: "sp:hub" }], nav()]),
  );
}

// POINT RULES — live scoring configuration (no deploy). Only rates and per-source switches.
const SPEND_SOURCES: [string, string][] = [
  ["ton_direct_deposit", "TON DIRECT DEPOSIT"],
  ["ton_to_fc", "TON → FC"],
  ["myth_sale", "MYTH SALE"],
  ["season_pass", "SEASON PASS"],
  ["packs", "PACKS (FOUNDER / VETERAN / EGGS)"],
  ["nft_shop", "NFT SHOP"],
  ["marketplace", "MARKETPLACE"],
  ["auction", "AUCTION"],
  ["fc_spend", "FC SPENDING"],
  ["other_ton", "OTHER TON SPENDING"],
];

async function spendRulesMenu(ctx: Ctx) {
  const r = (await rpc("admin_spending_event_rules", { p_admin_id: ctx.adminId })) as any;
  const rules = r?.rules || {};
  const sources = rules.sources || {};
  const body = [
    "⚖️ <b>SPENDING EVENT — POINT RULES</b>",
    "",
    `💎 1 TON = <b>${spPoints(rules.ton_points ?? 100000)}</b> pontos`,
    `🪙 1 FC gasto = <b>${spPoints(rules.fc_points ?? 1)}</b> ponto(s)`,
    "",
    `📚 Registros no ledger: <b>${spPoints(r?.entries)}</b>`,
    `👥 Jogadores pontuados: <b>${spPoints(r?.scored_players)}</b>`,
    "",
    "Fontes ativas (toque para ligar/desligar):",
    ...SPEND_SOURCES.map(([k, label]) => `${sources[k] === false ? "⛔" : "✅"} ${label}`),
  ].join("\n");
  const rows = [
    [
      { t: "💎 PONTOS POR TON", d: "sp:ask:spratet" },
      { t: "🪙 PONTOS POR FC", d: "sp:ask:spratef" },
    ],
    ...SPEND_SOURCES.map(([k, label]) => [{ t: `${sources[k] === false ? "⛔" : "✅"} ${label}`, d: `sp:src:${k}` }]),
    [{ t: "⬅️ SPENDING EVENT", d: "sp:hub" }],
    nav(),
  ];
  return edit(ctx, body, kb(rows));
}

const SPEND_TYPES_TEXT = [
  "✅ <b>CONTA COMO GASTO</b>",
  "• Recrutamento e fusão de heróis",
  "• Comida de pet e evoluções pagas",
  "• Tickets de PvP e criação de clã",
  "• Compras no marketplace (só o comprador)",
  "• Battle Pass e compra de níveis",
  "• Ovos premium (Epic, Dragon, Ancestral) e baús",
  "• Entradas pagas em eventos",
  "",
  "⛔ <b>NÃO CONTA</b>",
  "• Depósitos e saques em TON",
  "• Comissões, prêmios e recompensas",
  "• FC recebido por venda no mercado",
  "• Crédito de administrador, refund e transferências",
  "",
  "💎 Compras em TON só contam quando <b>confirmadas</b> na blockchain.",
  "🔁 A taxa TON→FC é congelada em cada lançamento, então o histórico nunca muda.",
].join("\n");

async function spendCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = [rest[0], rest[1] || ""];
  const d = await spendOverview(ctx);
  switch (sub) {
    case "hub":
      return spendHub(ctx);
    case "rank":
      return spendRanking(ctx);
    case "rw":
      return spendRewards(ctx);
    case "audit":
      return spendAudit(ctx);
    case "types":
      return edit(ctx, SPEND_TYPES_TEXT, kb([[{ t: "⬅️ SPENDING EVENT", d: "sp:hub" }], nav()]));
    case "popup":
      return spendPopupMenu(ctx);
    case "rules":
      return spendRulesMenu(ctx);
    case "src":
      await rpc("admin_spending_event_toggle_source", { p_admin_id: ctx.adminId, p_source: a });
      return spendRulesMenu(ctx);
    case "popset":
      await rpc("admin_spending_event_popup_config", { p_admin_id: ctx.adminId, p_enabled: a === "on" });
      return spendPopupMenu(ctx);
    case "popfreq":
      await rpc("admin_spending_event_popup_config", {
        p_admin_id: ctx.adminId,
        p_frequency: a === "event" ? "event" : "daily",
      });
      return spendPopupMenu(ctx);
    case "ask":
      return ask(ctx, a, PROMPTS[a] || "Envie o valor.");
    case "new":
      return ask(ctx, "spname", PROMPTS.spname);
    case "dur":
      return edit(
        ctx,
        "📅 <b>DURAÇÃO DO EVENTO</b>\nEscolha uma opção ou envie uma duração personalizada.",
        kb([
          [
            { t: "1 dia", d: "sp:durgo:1" },
            { t: "3 dias", d: "sp:durgo:3" },
            { t: "7 dias", d: "sp:durgo:7" },
          ],
          [
            { t: "14 dias", d: "sp:durgo:14" },
            { t: "30 dias", d: "sp:durgo:30" },
          ],
          [{ t: "✏️ PERSONALIZADO", d: "sp:ask:spdays" }],
          [{ t: "⬅️ SPENDING EVENT", d: "sp:hub" }],
          nav(),
        ]),
      );
    case "durgo": {
      if (!d?.event) return spendHub(ctx);
      await rpc("admin_spending_event_set_duration", {
        p_admin_id: ctx.adminId,
        p_event_id: d.event.id,
        p_days: Number(a),
      });
      await send(ctx, `✅ Duração atualizada para <b>${Number(a)} dias</b>.`);
      return spendHub({ ...ctx, messageId: undefined }, false);
    }
    case "start":
    case "end": {
      if (!d?.event) return spendHub(ctx);
      const status = sub === "start" ? "active" : "finished";
      await rpc("admin_spending_event_set_status", {
        p_admin_id: ctx.adminId,
        p_event_id: d.event.id,
        p_status: status,
      });
      await send(ctx, sub === "start" ? "▶️ Evento ativado. A contagem começa agora, do zero." : "⏹ Evento encerrado.");
      return spendHub({ ...ctx, messageId: undefined }, false);
    }
    case "fin": {
      if (!d?.event) return spendHub(ctx);
      return edit(
        ctx,
        "🔒 <b>FINALIZAR EVENTO</b>\nO ranking final será congelado e os resultados gravados para distribuição.\n\nConfirma?",
        kb([
          [
            { t: "✅ CONFIRMAR", d: "sp:fingo" },
            { t: "❌ CANCELAR", d: "sp:hub" },
          ],
        ]),
      );
    }
    case "fingo": {
      if (!d?.event) return spendHub(ctx);
      const r = (await rpc("admin_spending_event_finalize", {
        p_admin_id: ctx.adminId,
        p_event_id: d.event.id,
      })) as any;
      await send(ctx, `🔒 Ranking congelado com <b>${fmt(r?.winners ?? 0)}</b> posições.`);
      return spendHub({ ...ctx, messageId: undefined }, false);
    }
    default:
      return spendHub(ctx);
  }
}

async function spendPrompt(ctx: Ctx, key: string, text: string) {
  if (key === "spname") {
    await setSession(ctx, `spdays|${encodeURIComponent(text.slice(0, 40))}`, "awaiting_input");
    return send(
      ctx,
      `🏷 Nome: <b>${esc(text.slice(0, 40))}</b>\n\n${PROMPTS.spdays}`,
      kb([[{ t: "❌ CANCELAR", d: "cancel" }]]),
    );
  }
  if (key === "spdays") {
    const days = parseAmount(text);
    if (!Number.isFinite(days) || days < 1 || days > 90)
      throw new Error("KEEP_SESSION::⚠️ Envie um número de dias entre 1 e 90.");
    const session = await getSession(ctx);
    const raw = String(session?.action || "").split("|")[1] || "";
    const name = raw ? decodeURIComponent(raw) : "SPENDING EVENT";
    const d = (await rpc("admin_spending_event_create", {
      p_admin_id: ctx.adminId,
      p_name: name,
      p_days: Math.round(days),
    })) as any;
    await clearSession(ctx);
    await send(
      ctx,
      `✅ <b>EVENTO CRIADO</b>\n${esc(d?.event?.name || name)} · ${Math.round(days)} dias\nTodos começam com 0 pontos.`,
    );
    return spendHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "spratet" || key === "spratef") {
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0 || value > 100_000_000)
      throw new Error("KEEP_SESSION::⚠️ Envie um número válido (0 a 100.000.000).");
    await rpc("admin_spending_event_set_rate", {
      p_admin_id: ctx.adminId,
      p_currency: key === "spratet" ? "TON" : "FC",
      p_value: value,
    });
    await clearSession(ctx);
    await send(ctx, `✅ Nova regra salva: 1 ${key === "spratet" ? "TON" : "FC"} = <b>${spPoints(value)}</b> pontos.`);
    return spendRulesMenu({ ...ctx, messageId: undefined });
  }
  if (key === "spreward") {
    const [slot, ...labelParts] = text.split("|");
    const label = labelParts.join("|").trim();
    const range = String(slot || "")
      .trim()
      .replace(/#/g, "");
    const [from, to] = range.includes("-") ? range.split("-") : [range, range];
    if (!/^\d+$/.test(String(from).trim()) || !/^\d+$/.test(String(to).trim()) || label.length < 2) {
      throw new Error(
        "KEEP_SESSION::⚠️ Formato inválido. Use <code>1|Ancestral Egg</code> ou <code>11-12|Rare Chest</code>.",
      );
    }
    const d = await spendOverview(ctx);
    if (!d?.event) {
      await clearSession(ctx);
      return spendHub(ctx, false);
    }
    await rpc("admin_spending_event_set_reward", {
      p_admin_id: ctx.adminId,
      p_event_id: d.event.id,
      p_from: Number(from),
      p_to: Number(to),
      p_label: label.slice(0, 200),
    });
    await clearSession(ctx);
    await send(
      ctx,
      `✅ Recompensa salva para <b>#${Number(from)}${Number(to) !== Number(from) ? "–#" + Number(to) : ""}</b>.`,
    );
    return spendRewards({ ...ctx, messageId: undefined });
  }
  return spendHub(ctx, false);
}

// ---------------------------------------------------------------- 👹 CLAN BOSS (Abyssal Warlord)
// Exclusive per-clan boss. This module NEVER touches the 👑 global boss: it only
// calls admin_clan_boss, which writes to clan_boss_config / clan_boss_instances.
const CB_FIELDS: Record<string, { ref: string; label: string }> = {
  cbbasehp: { ref: "base_hp", label: "HP base" },
  cbclanlvl: { ref: "hp_per_clan_level_pct", label: "% HP por nível do clã" },
  cbmember: { ref: "hp_per_member_pct", label: "% HP por membro" },
  cbcycle: { ref: "hp_per_cycle_pct", label: "% HP por ciclo" },
  cbdur: { ref: "duration_hours", label: "duração (horas)" },
  cbcool: { ref: "cooldown_seconds", label: "cooldown (segundos)" },
  cbxp: { ref: "clan_xp_reward", label: "XP de clã" },
  cbmindmg: { ref: "min_damage_pct", label: "% mínimo de dano" },
  cbfixhp: { ref: "fixed_hp", label: "HP fixo global" },
  cbperday: { ref: "bosses_per_day", label: "chefes por dia (global)" },
  cbfcpool: { ref: "fc_pool", label: "pool de FC global" },
};

const cbCall = (ctx: Ctx, action = "overview", ref: string | null = null, payload: Record<string, unknown> = {}) =>
  rpc("admin_clan_boss", { p_admin_id: ctx.adminId, p_action: action, p_ref: ref, p_payload: payload }) as Promise<any>;

async function cbHub(ctx: Ctx, editing = true) {
  const d = await cbCall(ctx);
  const c = d?.config || {};
  const active = d?.active || [];
  const rw = c.rewards || {};
  const body = [
    "👹 <b>CLAN BOSS — ABYSSAL WARLORD</b>",
    "Cada clã tem o seu próprio chefe, ciclo, cooldown e ranking interno. Independente do 👑 Global Boss.",
    "",
    `🏷 Nome: <b>${esc(c.bossName)}</b> · chave <code>${esc(c.bossKey)}</code>`,
    `❤️ HP FIXO global: <b>${Number(c.fixedHp) > 0 ? fmt(Math.round(Number(c.fixedHp))) : "desligado"}</b> · HP base ${fmt(c.baseHp)}`,
    `👹 Chefes por dia: <b>${fmt(c.bossesPerDay)}</b> · 🕒 ciclo global ${fmt(c.cycleHours)}h`,
    `🎁 Pool de FC ao derrotar: <b>${fmt(Math.round(Number(rw.fcPool || 0)))}</b>`,
    `📈 +${Number(c.hpPerClanLevelPct ?? 0)}% por nível do clã · +${Number(c.hpPerMemberPct ?? 0)}% por membro · +${Number(c.hpPerCyclePct ?? 0)}% por ciclo`,
    `🕒 Ciclo: <b>${fmt(c.durationHours)}h</b> · ⏱ cooldown <b>${fmt(c.cooldownSeconds)}s</b>`,
    `⭐ XP de clã ao derrotar: <b>${fmt(c.clanXpReward)}</b> · 🎯 dano mínimo <b>${Number(c.minDamagePct ?? 0)}%</b>`,
    `🎁 Recompensas: ${esc(JSON.stringify(rw)).slice(0, 300)}`,
    "",
    `⚔️ Chefes ativos agora: <b>${fmt(active.length)}</b>`,
    active
      .slice(0, 8)
      .map(
        (a: any) =>
          `• [${esc(a.tag)}] ${esc(a.clan)} · ciclo #${a.cycle} · ${fmt(Math.round(a.currentHp))}/${fmt(Math.round(a.maxHp))} HP · ${fmt(a.participants)} membros`,
      )
      .join("\n") || "—",
  ].join("\n");
  const rows = [
    [
      { t: "❤️ HP FIXO GLOBAL", d: "cb:ask:cbfixhp" },
      { t: "🎁 FC AO DERROTAR", d: "cb:ask:cbfcpool" },
    ],
    [
      { t: "👹 CHEFES / DIA", d: "cb:ask:cbperday" },
      { t: "🏷 NOME", d: "cb:ask:cbname" },
    ],
    [
      { t: "❤️ HP BASE", d: "cb:ask:cbbasehp" },
      { t: "🏰 CONFIG POR GUILDA", d: "cb:ask:cbclan" },
    ],
    [
      { t: "📈 % NÍVEL", d: "cb:ask:cbclanlvl" },
      { t: "👥 % MEMBRO", d: "cb:ask:cbmember" },
    ],
    [
      { t: "🔁 % CICLO", d: "cb:ask:cbcycle" },
      { t: "🕒 DURAÇÃO", d: "cb:ask:cbdur" },
    ],
    [
      { t: "⏱ COOLDOWN", d: "cb:ask:cbcool" },
      { t: "⭐ XP DE CLÃ", d: "cb:ask:cbxp" },
    ],
    [
      { t: "🎯 DANO MÍNIMO", d: "cb:ask:cbmindmg" },
      { t: "🎁 RECOMPENSAS", d: "cb:ask:cbrewards" },
    ],
    [
      { t: "⚔️ CHEFES ATIVOS", d: "cb:active" },
      { t: "🏰 GERENCIAR CLÃ", d: "cb:ask:cbclan" },
    ],
    [{ t: "🎯 LIMITE DIÁRIO / JOGADORES", d: "cb:pers" }],
    [{ t: "⚖️ BALANCEAMENTO 24H", d: "cb:bal" }],
    [{ t: "📜 HISTÓRICO", d: "cb:audit" }],

    nav(),
  ];
  return editing ? edit(ctx, body, kb(rows)) : send(ctx, body, kb(rows));
}

async function cbActive(ctx: Ctx) {
  const d = await cbCall(ctx);
  const active = d?.active || [];
  const list =
    active
      .map((a: any) => {
        const pct = a.maxHp > 0 ? Math.round((a.currentHp / a.maxHp) * 100) : 0;
        return `• [${esc(a.tag)}] <b>${esc(a.clan)}</b> · ciclo #${a.cycle} (lv ${a.level})\n   ${pct}% HP · ${fmt(Math.round(a.currentHp))}/${fmt(Math.round(a.maxHp))} · ${fmt(a.participants)} membros · até ${String(a.endsAt).slice(0, 16).replace("T", " ")}`;
      })
      .join("\n") || "Nenhum chefe de clã ativo.";
  const rows = active.slice(0, 6).map((a: any) => [{ t: `🏰 ${a.tag}`, d: `cb:clan:${a.clanId}` }]);
  return edit(
    ctx,
    `⚔️ <b>CHEFES DE CLÃ ATIVOS</b>\n\n${list.slice(0, 3400)}`,
    kb([...rows, [{ t: "🔄 ATUALIZAR", d: "cb:active" }], [{ t: "⬅️ CLAN BOSS", d: "cb:hub" }], nav()]),
  );
}

async function cbAudit(ctx: Ctx) {
  const d = await cbCall(ctx);
  const list =
    (d?.audit || [])
      .map(
        (a: any) =>
          `• ${esc(a.clan)} · ciclo #${a.cycle} · <b>${a.status === "defeated" ? "derrotado" : "expirado"}</b>\n   dano ${fmt(Math.round(a.totalDamage))} · XP +${fmt(a.clanXp)} · top ${esc(a.top || "—")} · ${String(
            a.finishedAt || "",
          )
            .slice(0, 16)
            .replace("T", " ")}`,
      )
      .join("\n") || "—";
  return edit(
    ctx,
    `📜 <b>HISTÓRICO DO CLAN BOSS</b>\n\n${list.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "cb:audit" }], [{ t: "⬅️ CLAN BOSS", d: "cb:hub" }], nav()]),
  );
}

// Per-clan Clan Boss control: HP, FC reward, bosses/day and cycle reset — all live,
// no deploy needed (admin_clan_boss_clan applies to the running boss immediately).
const cbClanCall = (ctx: Ctx, clanId: string, action = "overview", payload: Record<string, unknown> = {}) =>
  rpc("admin_clan_boss_clan", {
    p_admin_id: ctx.adminId,
    p_clan_id: clanId,
    p_action: action,
    p_payload: payload,
  }) as Promise<any>;

async function cbClanCard(ctx: Ctx, clanId: string, editing = true) {
  const d = await cbClanCall(ctx, clanId);
  if (!d || d.error) return cbHub(ctx, editing);
  const clan = d.clan || {};
  const s = d.settings || {};
  const b = d.active;
  const lock = d.lock || {};
  const body = [
    `🏰 <b>[${esc(clan.tag)}] ${esc(clan.name)}</b> · nível ${fmt(clan.level)} · ${fmt(clan.members)} membros`,
    "",
    `❤️ HP do chefe: <b>${fmt(Math.round(Number(s.fixedHp || 0)))}</b>${Number(s.fixedHp) > 0 ? "" : " (usando escala automática)"}`,
    `🎁 Recompensa FC (pool): <b>${fmt(Math.round(Number(s.rewardFcPool || 0)))}</b>`,
    `👹 Chefes por dia: <b>${fmt(s.bossesPerDay)}</b> · 🕒 ciclo <b>${fmt(s.durationHours)}h</b>`,
    `📊 Iniciados nas últimas 24h: <b>${fmt(lock.startedLast24h ?? 0)}</b> · derrotados <b>${fmt(d.killedLast24h ?? 0)}</b>`,
    lock.locked
      ? `🔒 Bloqueado (${esc(lock.reason || "")}) · libera em ${Math.ceil(Number(lock.secondsRemaining || 0) / 60)} min`
      : "🔓 Liberado para iniciar novo chefe",
    s.hasOverride ? "⚙️ Este clã usa configuração <b>individual</b>." : "⚙️ Este clã usa a configuração <b>global</b>.",
    "",
    b
      ? `👹 Ciclo #${b.cycle} · ${fmt(Math.round(Number(b.currentHp)))}/${fmt(Math.round(Number(b.maxHp)))} HP\n⚔️ Dano ${fmt(Math.round(Number(b.totalDamage || 0)))} · ${fmt(b.participants)} membros · pool ${fmt(Math.round(Number(b.fcPool || 0)))} FC\n⏳ até ${String(b.endsAt).slice(0, 16).replace("T", " ")}`
      : "👹 Nenhum ciclo ativo para este clã.",
  ].join("\n");
  return (editing ? edit : send)(
    ctx,
    body,
    kb([
      [
        { t: "❤️ HP DESTE CLÃ", d: `cb:cask:cbchp:${clanId}` },
        { t: "🎁 FC DESTE CLÃ", d: `cb:cask:cbcfc:${clanId}` },
      ],
      [
        { t: "👹 CHEFES / DIA", d: `cb:cask:cbcday:${clanId}` },
        { t: "🕒 DURAÇÃO CICLO", d: `cb:cask:cbcdur:${clanId}` },
      ],
      [
        { t: "🎁 JSON RECOMPENSAS", d: `cb:cask:cbcrw:${clanId}` },
        { t: "♻️ USAR GLOBAL", d: `cb:cclear:${clanId}` },
      ],
      [{ t: "🔄 RESETAR CICLO AGORA", d: `cb:creset:${clanId}` }],
      [{ t: "▶️ INICIAR NOVO CICLO", d: `cb:start:${clanId}` }],
      [
        { t: "⏹ ENCERRAR SEM PRÊMIO", d: `cb:end:${clanId}` },
        { t: "🏆 ENCERRAR COM PRÊMIO", d: `cb:endrw:${clanId}` },
      ],
      [{ t: "🔄 ATUALIZAR", d: `cb:clan:${clanId}` }],
      [{ t: "⬅️ CLAN BOSS", d: "cb:hub" }],
      nav(),
    ]),
  );
}

const CB_CLAN_FIELDS: Record<string, { action: string; label: string; prompt: string }> = {
  cbchp: {
    action: "set_hp",
    label: "HP do chefe",
    prompt:
      "❤️ Envie o <b>HP total</b> do Clan Boss deste clã (0 = usar escala automática).\nEx.: <code>100000000</code> para 100M",
  },
  cbcfc: {
    action: "set_reward",
    label: "recompensa em FC",
    prompt: "🎁 Envie o <b>pool de FC</b> pago ao derrotar o chefe deste clã.\nEx.: <code>1000000</code>",
  },
  cbcday: {
    action: "set_per_day",
    label: "chefes por dia",
    prompt: "👹 Envie quantos <b>chefes por dia</b> este clã pode enfrentar (1 a 48).\nEx.: <code>4</code>",
  },
  cbcdur: {
    action: "set_duration",
    label: "duração do ciclo",
    prompt: "🕒 Envie a <b>duração do ciclo</b> em horas (1 a 168).\nEx.: <code>6</code>",
  },
};


// ---- ⚖️ CLAN BOSS BALANCE (dynamic 24h scaling per guild)
// Every number here is computed server-side by clan_boss_compute_scaling; the bot
// only reads the report and forwards admin settings. Global Boss is untouched.
const CB_BAL_FIELDS: Record<string, { ref: string; label: string; hours?: boolean }> = {
  cbbaltarget: { ref: "target_duration_seconds", label: "duração alvo", hours: true },
  cbbalcycle: { ref: "cycle_hours", label: "horas do ciclo" },
  cbbalhp: { ref: "hp_scaling", label: "fator de HP" },
  cbbaldef: { ref: "def_scaling", label: "fator de DEF" },
  cbbalatk: { ref: "atk_scaling", label: "fator de ATK" },
  cbbaltooeasy: { ref: "too_easy_seconds", label: "limite fácil demais" },
  cbbaltoohard: { ref: "too_hard_seconds", label: "limite difícil demais" },
};

const cbBalCall = (ctx: Ctx, action = "OVERVIEW", ref: string | null = null, payload: Record<string, unknown> = {}) =>
  rpc("admin_clan_boss_balance", {
    p_admin_id: ctx.adminId,
    p_action: action,
    p_ref: ref,
    p_payload: payload,
  }) as Promise<any>;

const cbHours = (seconds: unknown) => {
  const s = Number(seconds ?? 0);
  if (!Number.isFinite(s) || s <= 0) return "—";
  return `${Math.floor(s / 3600)}h${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}`;
};

async function cbBalHub(ctx: Ctx, editing = true) {
  const d = await cbBalCall(ctx);
  const c = d?.config || {};
  const clans = (d?.clans || []) as any[];
  const body = [
    "⚖️ <b>CLAN BOSS — ESCALA DINÂMICA 24H</b>",
    "Cada clã recebe HP/DEF/ATK calculados no nascimento do boss (snapshot) a partir do poder do roster, membros ativos e DPS real. Não afeta o 👑 Global Boss.",
    "",
    `🎯 Alvo de duração: <b>${cbHours(c.target_duration_seconds)}</b> · 🕒 ciclo <b>${fmt(c.cycle_hours)}h</b>`,
    `❤️ Fator HP <b>${Number(c.hp_scaling ?? 0)}</b> · 🛡 DEF <b>${Number(c.def_scaling ?? 0)}</b> · ⚔️ ATK <b>${Number(c.atk_scaling ?? 0)}</b>`,
    `⚡ Fácil demais: <b>${cbHours(c.too_easy_seconds)}</b> · 🐢 difícil demais: <b>${cbHours(c.too_hard_seconds)}</b>`,
    `🔁 Escala automática: <b>${c.enabled ? "ATIVA" : "DESLIGADA"}</b> · 🔒 trava de ciclo: <b>${c.cycle_lock_enabled ? "ATIVA" : "DESLIGADA"}</b>`,
    "",
    `🏰 Clãs calibrados: <b>${fmt(clans.length)}</b>`,
    clans
      .slice(0, 10)
      .map(
        (x: any) =>
          `• [${esc(x.tag)}] ${esc(x.name)} · ${esc(x.tier || "—")} · x${Number(x.hpMultiplier ?? 0).toFixed(2)} HP\n   DPS ${fmt(Math.round(Number(x.dps ?? 0)))}/s · último ciclo ${cbHours(x.lastDuration)} (${esc(x.lastQuality || "—")}) · ${fmt(x.kills24h)} abates 24h`,
      )
      .join("\n") || "—",
  ].join("\n");
  const rows = [
    [
      { t: "🎯 DURAÇÃO ALVO", d: "cb:ask:cbbaltarget" },
      { t: "🕒 CICLO (H)", d: "cb:ask:cbbalcycle" },
    ],
    [
      { t: "❤️ FATOR HP", d: "cb:ask:cbbalhp" },
      { t: "🛡 FATOR DEF", d: "cb:ask:cbbaldef" },
    ],
    [
      { t: "⚔️ FATOR ATK", d: "cb:ask:cbbalatk" },
      { t: "⚡ FÁCIL DEMAIS", d: "cb:ask:cbbaltooeasy" },
    ],
    [
      { t: "🐢 DIFÍCIL DEMAIS", d: "cb:ask:cbbaltoohard" },
      { t: c.enabled ? "🔁 DESLIGAR ESCALA" : "🔁 ATIVAR ESCALA", d: `cb:baltoggle:enabled` },
    ],
    [{ t: c.cycle_lock_enabled ? "🔓 DESLIGAR TRAVA 24H" : "🔒 ATIVAR TRAVA 24H", d: "cb:baltoggle:lock" }],
    [
      { t: "🔄 RECALCULAR TODOS", d: "cb:balrecalcall" },
      { t: "🏰 VER CLÃ", d: "cb:ask:cbbalclan" },
    ],
    [
      { t: "📊 DURAÇÕES REAIS", d: "cb:baldur" },
      { t: "⚡ FÁCEIS DEMAIS", d: "cb:baleasy" },
    ],
    [{ t: "🚨 OUTLIERS DE DANO", d: "cb:balout" }],
    [{ t: "⬅️ CLAN BOSS", d: "cb:hub" }],
    nav(),
  ];
  return editing ? edit(ctx, body, kb(rows)) : send(ctx, body, kb(rows));
}

async function cbBalClan(ctx: Ctx, clanId: string, editing = true) {
  const d = await cbBalCall(ctx, "VIEW_CLAN", clanId);
  const clan = d?.clan || {};
  const s = d?.scaling || {};
  const p = d?.profile || {};
  const cur = d?.currentBoss;
  const lock = d?.cycleLock || {};
  const hist = (d?.lastBosses || []) as any[];
  const body = [
    `⚖️ <b>[${esc(clan.tag)}] ${esc(clan.name)}</b> · nível ${fmt(clan.level)} · ${fmt(clan.members)} membros`,
    `💪 Poder do clã: <b>${fmt(clan.power)}</b> · tier <b>${esc(p.scaling_tier || s.tier || "—")}</b>`,
    `📈 DPS efetivo: <b>${fmt(Math.round(Number(s.effectiveDps ?? p.effective_dps ?? 0)))}</b>/s · capacidade 24h <b>${fmt(Math.round(Number(s.capacity24h ?? 0)))}</b>`,
    "",
    "🧬 <b>PRÓXIMO BOSS (cálculo atual)</b>",
    `❤️ HP <b>${fmt(Math.round(Number(s.effectiveHp ?? 0)))}</b> (base ${fmt(s.baseHp)} × x${Number(s.hpMultiplier ?? 0).toFixed(2)})`,
    `🛡 DEF <b>${fmt(Math.round(Number(s.effectiveDef ?? 0)))}</b> · ⚔️ ATK <b>${fmt(Math.round(Number(s.effectiveAtk ?? 0)))}</b> · 🔮 poder ${fmt(Math.round(Number(s.bossPower ?? 0)))}`,
    `⏳ Duração prevista: <b>${cbHours(s.expectedDurationSeconds)}</b> · modo ${esc(s.mode || "—")}`,
    "",
    cur
      ? `⚔️ <b>BOSS ATIVO</b> · ciclo #${cur.cycle}\n❤️ ${fmt(Math.round(cur.currentHp))}/${fmt(Math.round(cur.maxHp))} · 🛡 ${fmt(Math.round(cur.def ?? 0))} · ⚔️ ${fmt(Math.round(cur.atk ?? 0))}\n🎯 alvo ${cbHours(cur.targetDuration)} · ciclo termina ${String(
          cur.cycleEndsAt || "",
        )
          .slice(0, 16)
          .replace("T", " ")}`
      : `⏸ Nenhum boss ativo. ${lock.locked ? `Trava de ciclo: falta ${cbHours(lock.secondsRemaining)}.` : "Livre para nascer."}`,
    "",
    "📜 <b>ÚLTIMOS CICLOS</b>",
    hist
      .slice(0, 6)
      .map(
        (h: any) =>
          `• #${h.cycle} · HP ${fmt(Math.round(Number(h.effectiveHp ?? 0)))} · real ${cbHours(h.actual)} / alvo ${cbHours(h.target)} · ${esc(h.quality || "—")}`,
      )
      .join("\n") || "—",
  ].join("\n");
  const rows = [
    [{ t: "🔄 RECALCULAR ESTE CLÃ", d: `cb:balrecalc:${clanId}` }],
    [{ t: "🏰 PAINEL DO CLÃ", d: `cb:clan:${clanId}` }],
    [{ t: "⬅️ BALANCEAMENTO", d: "cb:bal" }],
    nav(),
  ];
  return editing ? edit(ctx, body.slice(0, 3800), kb(rows)) : send(ctx, body.slice(0, 3800), kb(rows));
}

async function cbBalReport(ctx: Ctx, kind: "dur" | "easy" | "out") {
  if (kind === "dur") {
    const rows = ((await cbBalCall(ctx, "DURATION_REPORT")) || []) as any[];
    const list =
      rows
        .slice(0, 20)
        .map(
          (x: any) =>
            `• ${esc(x.clan)} · #${x.cycle} · real <b>${cbHours(x.actual)}</b> / alvo ${cbHours(x.target)} · ${esc(x.quality || "—")}`,
        )
        .join("\n") || "Nenhum ciclo concluído nos últimos 14 dias.";
    return edit(
      ctx,
      `📊 <b>DURAÇÕES REAIS (14 DIAS)</b>\nQuanto tempo cada Clan Boss sobreviveu vs o alvo de 24h.\n\n${list.slice(0, 3500)}`,
      kb([[{ t: "🔄 ATUALIZAR", d: "cb:baldur" }], [{ t: "⬅️ BALANCEAMENTO", d: "cb:bal" }], nav()]),
    );
  }
  if (kind === "easy") {
    const rows = ((await cbBalCall(ctx, "TOO_EASY")) || []) as any[];
    const list =
      rows
        .slice(0, 15)
        .map(
          (x: any) =>
            `• ${esc(x.clan)} · <b>${fmt(x.kills24h)}</b> abates em 24h · DPS ${fmt(Math.round(Number(x.dps ?? 0)))}/s\n   HP recomendado: <b>${fmt(Math.round(Number(x.recommendedHp ?? 0)))}</b>`,
        )
        .join("\n") || "Nenhum clã matando bosses rápido demais. 👌";
    return edit(
      ctx,
      `⚡ <b>CLÃS COM BOSS FÁCIL DEMAIS</b>\n\n${list.slice(0, 3500)}`,
      kb([[{ t: "🔄 RECALCULAR TODOS", d: "cb:balrecalcall" }], [{ t: "⬅️ BALANCEAMENTO", d: "cb:bal" }], nav()]),
    );
  }
  const rows = ((await cbBalCall(ctx, "OUTLIERS")) || []) as any[];
  const list =
    rows
      .slice(0, 20)
      .map(
        (x: any) =>
          `• ${esc(x.clan)} · ${fmt(x.outlierAttacks)} ataques ignorados · teto ${fmt(Math.round(Number(x.cap ?? 0)))}`,
      )
      .join("\n") || "Nenhum outlier de dano detectado.";
  return edit(
    ctx,
    `🚨 <b>OUTLIERS DE DANO</b>\nAtaques anormais são excluídos do cálculo de DPS para não inflar o HP do boss.\n\n${list.slice(0, 3500)}`,
    kb([[{ t: "🔄 ATUALIZAR", d: "cb:balout" }], [{ t: "⬅️ BALANCEAMENTO", d: "cb:bal" }], nav()]),
  );
}

// ---- 🎯 PERSONAL CLAN BOSS (boss individual + limite diário de chefes DERROTADOS)
// Todas as mudanças valem na hora, sem deploy (admin_clan_boss_personal).
const cbpCall = (ctx: Ctx, action = "report", ref = "", payload: Record<string, unknown> = {}) =>
  rpc("admin_clan_boss_personal", {
    p_admin_id: ctx.adminId,
    p_action: action,
    p_ref: ref,
    p_payload: payload,
  }) as Promise<any>;

async function cbpHub(ctx: Ctx, editing = true) {
  const d = await cbpCall(ctx, "report", "", { limit: 10 });
  const c = d?.config || {};
  const players: any[] = d?.players || [];
  const body = [
    "🎯 <b>PERSONAL CLAN BOSS — LIMITE DIÁRIO</b>",
    "Cada membro tem o seu próprio chefe adaptativo. O limite conta apenas <b>chefes DERROTADOS</b> — ataques e tentativas falhas nunca consomem o limite.",
    "O contador é POR JOGADOR / POR DIA: trocar de clã, sair, ser expulso, reabrir o app ou trocar de aparelho nunca zera.",
    "",
    `👹 LIMITE DIÁRIO PADRÃO: <b>${fmt(c.daily_limit ?? 4)}</b> chefes derrotados/dia`,
    `🕒 Reset oficial do servidor: <b>${String(c.reset_hour_utc ?? 0).padStart(2, "0")}:00 UTC</b>`,
    `🎯 Ataques-alvo por chefe: <b>${fmt(c.target_attacks_per_boss ?? 12)}</b> · sistema ${c.enabled === false ? "DESLIGADO" : "ATIVO"}`,
    `🎁 POOL DE FC FIXO POR CHEFE: <b>${fmt(Math.round(Number(c.fixed_fc_pool ?? 0)))} FC</b>${Number(c.fixed_fc_pool ?? 0) > 0 ? " (vale para TODOS os chefes individuais)" : " (desligado — usa clã/template)"}`,
    `🎁 Bônus por dificuldade: <b>${c.difficulty_bonus_enabled ? "ON" : "OFF"}</b>`,
    "",
    "<b>TOP JOGADORES (HP recomendado)</b>",
    players
      .slice(0, 10)
      .map(
        (p) =>
          `• ${esc(p.name || p.username || p.userId)} · poder ${fmt(Math.round(Number(p.power || 0)))} · boss ${fmt(Math.round(Number(p.recommendedHp || 0)))} HP · hoje ${fmt(p.bossesToday || 0)}/${fmt(p.override ?? c.daily_limit ?? 4)}${p.override ? " (override)" : ""}`,
      )
      .join("\n") || "Nenhum perfil calculado ainda.",
  ].join("\n");
  const rows = [
    [{ t: "👹 LIMITE DIÁRIO PADRÃO", d: "cb:ask:cbpglobal" }],
    [{ t: "🕒 HORA DO RESET (UTC)", d: "cb:ask:cbpreset" }],
    [{ t: "🎁 POOL DE FC FIXO", d: "cb:ask:cbpfc" }],
    [{ t: "🔍 CONFIGURAR JOGADOR", d: "cb:ask:cbpsearch" }],
    ...players.slice(0, 6).map((p: any) => [
      {
        t: `👤 ${String(p.name || p.username || "jogador").slice(0, 18)} · ${p.bossesToday || 0}/${p.override ?? c.daily_limit ?? 4}`,
        d: `cb:pp:${p.userId}`,
      },
    ]),
    [{ t: "🔄 ATUALIZAR", d: "cb:pers" }],
    [{ t: "⬅️ CLAN BOSS", d: "cb:hub" }],
    nav(),
  ];
  return editing ? edit(ctx, body, kb(rows)) : send(ctx, body, kb(rows));
}

async function cbpPlayer(ctx: Ctx, ref: string, editing = true) {
  const d = await cbpCall(ctx, "view", ref);
  if (!d || d.error)
    return send(ctx, "🔍 Jogador não encontrado.", kb([[{ t: "⬅️ LIMITE DIÁRIO", d: "cb:pers" }], nav()]));
  const dl = d.daily || {};
  const body = [
    `👤 <b>${esc(d.name || d.username || "jogador")}</b>${d.username ? ` · @${esc(d.username)}` : ""}`,
    `🆔 Telegram: <code>${esc(String(d.telegramId ?? "—"))}</code> · 🏰 Clã: <b>${esc(d.clan || "sem clã")}</b>`,
    "",
    `💪 Poder oficial: <b>${fmt(Math.round(Number(d.officialPower || 0)))}</b>`,
    `👹 Poder do chefe: <b>${fmt(Math.round(Number(d.bossPower || 0)))}</b>`,
    `❤️ Chefe atual: <b>${fmt(Math.round(Number(d.currentBossHp || 0)))}/${fmt(Math.round(Number(d.currentBossMaxHp || 0)))}</b> HP · ${esc(String(d.difficulty || "—"))}`,
    `📈 HP recomendado no próximo: <b>${fmt(Math.round(Number(d.recommendedHp || 0)))}</b>`,
    `⏱ Tempo médio de kill: <b>${d.avgClearSeconds ? `${Math.floor(Number(d.avgClearSeconds) / 60)}m ${Math.round(Number(d.avgClearSeconds) % 60)}s` : "—"}</b> · dano médio/ataque ${fmt(Math.round(Number(d.avgDamage || 0)))}`,
    "",
    `🗓 CHEFES DERROTADOS HOJE: <b>${fmt(dl.defeated ?? 0)} / ${fmt(dl.limit ?? d.globalLimit ?? 4)}</b>`,
    `👹 Limite padrão global: <b>${fmt(d.globalLimit ?? 4)}</b>`,
    `🎯 Override individual: <b>${d.override == null ? "NENHUM" : fmt(d.override)}</b>`,
  ].join("\n");
  const rows = [
    [{ t: "🎯 DEFINIR LIMITE INDIVIDUAL", d: `cb:pplim:${d.userId}` }],
    [{ t: "♻️ REMOVER OVERRIDE", d: `cb:ppclr:${d.userId}` }],
    [{ t: "🔄 ZERAR CONTAGEM DE HOJE", d: `cb:pprst:${d.userId}` }],
    [{ t: "🧮 RECALCULAR CHEFE", d: `cb:pprec:${d.userId}` }],
    [{ t: "📜 HISTÓRICO DE PERFORMANCE", d: `cb:pphist:${d.userId}` }],
    [{ t: "⬅️ LIMITE DIÁRIO", d: "cb:pers" }],
    nav(),
  ];
  return editing ? edit(ctx, body, kb(rows)) : send(ctx, body, kb(rows));
}

async function cbpHistory(ctx: Ctx, uid: string) {
  const d = await cbpCall(ctx, "history", uid);
  const list =
    (d?.history || [])
      .map(
        (h: any) =>
          `• #${h.bossNumber ?? "?"} · ${fmt(Math.round(Number(h.hp || 0)))} HP · ${h.status === "defeated" ? "✅" : "❌"} ${esc(String(h.quality || ""))} · ${fmt(h.attacks || 0)} atk · ${h.clearSeconds ? `${Math.floor(Number(h.clearSeconds) / 60)}m` : "—"} · média ${fmt(Math.round(Number(h.avgDamage || 0)))}`,
      )
      .join("\n") || "Sem histórico de performance ainda.";
  return edit(
    ctx,
    `📜 <b>PERFORMANCE — ${esc(d?.username || uid)}</b>\n\n${list.slice(0, 3400)}`,
    kb([[{ t: "⬅️ JOGADOR", d: `cb:pp:${uid}` }], nav()]),
  );
}


async function cbCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = [rest[0], rest[1] || ""];
  switch (sub) {
    case "hub":
      return cbHub(ctx);
    case "active":
      return cbActive(ctx);
    case "audit":
      return cbAudit(ctx);
    case "ask":
      return ask(ctx, a, PROMPTS[a] || "Envie o valor.");
    case "cask": {
      const clanId = rest[2] || "";
      const f = CB_CLAN_FIELDS[a];
      const prompt =
        f?.prompt ??
        '🎁 Envie o JSON de recompensas deste clã.\nEx.: <code>{"fcPool":1000000,"participant":{"fc":80000}}</code>';
      return ask(ctx, `${a}|${clanId}`, prompt);
    }
    case "creset": {
      await cbClanCall(ctx, a, "reset_cycle");
      await send(
        ctx,
        "🔄 Ciclo resetado: chefe atual encerrado sem prêmio, limite diário e travas liberados e novo chefe iniciado.",
      );
      return cbClanCard({ ...ctx, messageId: undefined }, a, false);
    }
    case "cclear": {
      await cbClanCall(ctx, a, "clear");
      await send(ctx, "♻️ Configuração individual removida: este clã voltou a usar a configuração global.");
      return cbClanCard({ ...ctx, messageId: undefined }, a, false);
    }
    case "pers":
      return cbpHub(ctx);
    case "pp":
      return cbpPlayer(ctx, a);
    case "pphist":
      return cbpHistory(ctx, a);
    case "pplim":
      return ask(ctx, `cbplimit|${a}`, PROMPTS.cbplimit);
    case "ppclr": {
      await cbpCall(ctx, "clear_limit", a);
      await send(ctx, "♻️ Override removido: o jogador voltou ao limite diário global.");
      return cbpPlayer({ ...ctx, messageId: undefined }, a, false);
    }
    case "pprst": {
      await cbpCall(ctx, "reset_daily", a);
      await send(ctx, "🔄 Contagem de chefes derrotados de hoje zerada para este jogador.");
      return cbpPlayer({ ...ctx, messageId: undefined }, a, false);
    }
    case "pprec": {
      await cbpCall(ctx, "recalculate", a);
      await send(ctx, "🧮 Perfil recalculado: o próximo chefe pessoal nasce com HP/DEF/ATK adaptados.");
      return cbpPlayer({ ...ctx, messageId: undefined }, a, false);
    }
    case "clan":
      return cbClanCard(ctx, a);

    case "start": {
      await cbCall(ctx, "force_start", a);
      await send(ctx, "▶️ Novo ciclo do chefe do clã iniciado com HP recalculado.");
      return cbClanCard({ ...ctx, messageId: undefined }, a, false);
    }
    case "end":
    case "endrw": {
      await cbCall(ctx, "end_cycle", a, { reward: sub === "endrw" });
      await send(
        ctx,
        sub === "endrw"
          ? "🏆 Ciclo encerrado como derrotado: XP de clã e recompensas liberados aos membros elegíveis."
          : "⏹ Ciclo encerrado sem recompensas.",
      );
      return cbClanCard({ ...ctx, messageId: undefined }, a, false);
    }
    default:
      return cbHub(ctx);
  }
}

async function cbPrompt(ctx: Ctx, key: string, text: string, args: string[] = []) {
  const clanId = args[0] || "";
  if (key === "cbcrw" && clanId) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new Error('KEEP_SESSION::⚠️ JSON inválido. Ex.: <code>{"fcPool":1000000}</code>');
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
      throw new Error("KEEP_SESSION::⚠️ Envie um objeto JSON de recompensas.");
    await cbClanCall(ctx, clanId, "set_rewards_json", { rewards: parsed });
    await clearSession(ctx);
    await send(ctx, "✅ Recompensas deste clã atualizadas e aplicadas ao chefe ativo.");
    return cbClanCard({ ...ctx, messageId: undefined }, clanId, false);
  }
  if (CB_CLAN_FIELDS[key] && clanId) {
    const f = CB_CLAN_FIELDS[key];
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0)
      throw new Error(`KEEP_SESSION::⚠️ Envie um número válido para ${f.label}.`);
    await cbClanCall(ctx, clanId, f.action, { value });
    await clearSession(ctx);
    await send(ctx, `✅ <b>${esc(f.label)}</b> deste clã atualizado e aplicado imediatamente.`);
    return cbClanCard({ ...ctx, messageId: undefined }, clanId, false);
  }
  if (key === "cbpglobal" || key === "cbpreset") {
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
    await cbpCall(ctx, "set", key === "cbpglobal" ? "daily_limit" : "reset_hour_utc", { value });
    await clearSession(ctx);
    await send(
      ctx,
      key === "cbpglobal"
        ? `✅ Limite diário padrão atualizado para <b>${fmt(Math.round(value))}</b> chefes derrotados por jogador/dia. Jogadores sem override passam a usar esse valor imediatamente.`
        : `✅ Reset diário oficial definido para <b>${String(Math.round(value)).padStart(2, "0")}:00 UTC</b>.`,
    );
    return cbpHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "cbpfc") {
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido de FC.");
    await rpc("admin_clan_boss_personal_set_fc", { p_admin_id: ctx.adminId, p_value: value });
    await clearSession(ctx);
    await send(
      ctx,
      value > 0
        ? `✅ Pool de FC fixo dos chefes individuais definido em <b>${fmt(Math.round(value))} FC</b>. Aplicado imediatamente a todos os chefes ativos, sem deploy.`
        : "✅ Pool fixo desligado. Os chefes individuais voltam a usar o pool do clã/template.",
    );
    return cbpHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "cbpsearch") {
    await clearSession(ctx);
    return cbpPlayer({ ...ctx, messageId: undefined }, text.trim(), false);
  }
  if (key === "cbplimit") {
    const uid = args[0] || "";
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido (0 a 50).");
    await cbpCall(ctx, "set_limit", uid, { value });
    await clearSession(ctx);
    await send(ctx, `✅ Limite individual definido: <b>${fmt(Math.round(value))}</b> chefes derrotados por dia.`);
    return cbpPlayer({ ...ctx, messageId: undefined }, uid, false);
  }
  if (key === "cbclan") {
    const rows = await db
      .from("clans")
      .select("id, name, tag, level")
      .or(`name.ilike.%${text.slice(0, 40)}%,tag.ilike.%${text.slice(0, 10)}%`)
      .limit(10);
    await clearSession(ctx);
    if (!rows.data?.length)
      return send(ctx, "🔍 Nenhum clã encontrado.", kb([[{ t: "⬅️ CLAN BOSS", d: "cb:hub" }], nav()]));
    if (rows.data.length === 1) return cbClanCard({ ...ctx, messageId: undefined }, rows.data[0].id, false);
    return send(
      ctx,
      "🏰 <b>SELECIONE O CLÃ</b>",
      kb([
        ...rows.data.map((c: any) => [{ t: `[${c.tag}] ${c.name}`, d: `cb:clan:${c.id}` }]),
        [{ t: "⬅️ CLAN BOSS", d: "cb:hub" }],
        nav(),
      ]),
    );
  }
  if (key === "cbname") {
    const name = text.trim().slice(0, 40);
    if (name.length < 3) throw new Error("KEEP_SESSION::⚠️ Envie um nome com pelo menos 3 caracteres.");
    await cbCall(ctx, "set", "boss_name", { text: name });
    await clearSession(ctx);
    await send(ctx, `✅ Nome do chefe do clã atualizado para <b>${esc(name)}</b>.`);
    return cbHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "cbrewards") {
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new Error('KEEP_SESSION::⚠️ JSON inválido. Ex.: <code>{"fc_per_1m":2500}</code>');
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
      throw new Error("KEEP_SESSION::⚠️ Envie um objeto JSON de recompensas.");
    await cbCall(ctx, "set", "rewards", { rewards: parsed });
    await clearSession(ctx);
    await send(ctx, "✅ Recompensas do chefe do clã atualizadas.");
    return cbHub({ ...ctx, messageId: undefined }, false);
  }
  const field = CB_FIELDS[key];
  if (!field) return cbHub(ctx, false);
  const value = parseAmount(text);
  if (!Number.isFinite(value) || value < 0)
    throw new Error(`KEEP_SESSION::⚠️ Envie um número válido para ${field.label}.`);
  const d = await cbCall(ctx, "set", field.ref, { value });
  await clearSession(ctx);
  await send(ctx, `✅ <b>${esc(field.label)}</b> atualizado. Vale a partir do próximo ciclo de cada clã.`);
  void d;
  return cbHub({ ...ctx, messageId: undefined }, false);
}

function parseValue(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

// ---------------------------------------------------------------- 💎 NFT EXCLUSIVE pets
// Unique units: one serial can only belong to a single player. Never drawn from eggs,
// never sold in the shop — delivery and revocation happen only through this module.
const NFT_STATUS_LABEL: Record<string, string> = {
  AVAILABLE: "🟢 DISPONÍVEL",
  OWNED: "👤 ENTREGUE",
  REVOKED: "↩️ REVOGADO",
  BURNED: "🔥 QUEIMADO",
};
const nftSerial = (n: number) => `#${String(n ?? 0).padStart(3, "0")}`;

async function nftHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_nft_overview", { p_admin_id: ctx.adminId })) as any;
  const t = d.totals ?? {};
  const lines =
    (d.templates ?? [])
      .map(
        (x: any) =>
          `• <code>${esc(x.slug)}</code> ${esc(x.name)} — ${fmt(x.minted)} unid. (🟢 ${fmt(x.available)} · 👤 ${fmt(x.owned)})`,
      )
      .join("\n") || "Nenhum template NFT cadastrado.";
  const text = `💎 <b>NFT EXCLUSIVE PETS</b>\n${lines}\n\n<b>REGISTRO</b>\nUnidades ${fmt(t.units)} · 🟢 ${fmt(t.available)} · 👤 ${fmt(t.owned)} · ↩️ ${fmt(t.revoked)}\n\nEstes pets não entram em ovos, sorteios, loja, fusão ou mercado.`;
  const rows = [
    [
      { t: "➕ CRIAR UNIDADE", d: "nft:new" },
      { t: "🎁 ENTREGAR", d: "nft:ask:nftgive" },
    ],
    [
      { t: "📋 LISTAR REGISTRO", d: "nft:list:0" },
      { t: "🔎 PESQUISAR", d: "nft:ask:nftsearch" },
    ],
    [
      { t: "↩️ REVOGAR", d: "nft:revlist:0" },
      { t: "📜 HISTÓRICO", d: "nft:hist" },
    ],
    [
      { t: "💎 NFT POOL", d: "np:hub" },
      { t: "📦 NFT STOCK", d: "nstk:hub" },
    ],
    nav("m:pets"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

/**
 * NFT STOCK: rotação infinita 1/1. Nunca recoloca um NFT vendido à venda —
 * cada vaga vendida é substituída por uma unidade totalmente nova (nome, arte e
 * serial inéditos) na mesma faixa de preço/rendimento.
 */
function nftStockLines(stock: any): string {
  const tiers = (stock?.tiers ?? []) as any[];
  if (!tiers.length) return "sem faixas configuradas";
  return tiers
    .map(
      (x) =>
        `• ${fmt(x.tierTon)} TON (${x.dailyYieldTon}/dia) — 🟢 ${fmt(x.available)}/${fmt(x.slots)} · 👤 vendidos ${fmt(x.soldTotal)} · 📦 reserva ${fmt(x.poolLeft)}${Number(x.missing) > 0 ? ` · ⚠️ faltam ${fmt(x.missing)}` : ""}`,
    )
    .join("\n");
}

const NFT_RESERVE_LABEL: Record<string, string> = { hero: "⚔️ HEROES", pet: "💎 PETS", weapon: "🗡 WEAPONS" };

function nftReserveLines(stock: any): string {
  return (["hero", "pet", "weapon"] as const)
    .map((k) => {
      const s = stock?.[k] ?? {};
      return `${NFT_RESERVE_LABEL[k]}\nAvailable: ${fmt(s.available ?? 0)}\nReserve: ${fmt(s.reserve ?? 0)}\nSold: ${fmt(s.sold ?? 0)}`;
    })
    .join("\n\n");
}

async function nftStockHub(ctx: Ctx, useEdit = true) {
  const [rot, reserve] = await Promise.all([
    rpc("admin_nft_stock_overview", { p_admin_id: ctx.adminId }) as Promise<any>,
    rpc("admin_nft_reserve_overview", { p_admin_id: ctx.adminId }) as Promise<any>,
  ]);
  const text = [
    "📦 <b>NFT STOCK (ROTAÇÃO 1/1)</b>",
    "",
    nftReserveLines(reserve),
    "",
    `<b>FAIXAS — HEROES</b>\n${nftStockLines(rot.hero)}`,
    `<b>FAIXAS — PETS</b>\n${nftStockLines(rot.pet)}`,
    "",
    "REFILL publica até 2 unidades inéditas por categoria (RESERVE → AVAILABLE). NFT vendido nunca volta para AVAILABLE.",
  ].join("\n");
  const rows = [
    [
      { t: "♻️ REFILL HEROES", d: "nstk:refill:hero" },
      { t: "♻️ REFILL PETS", d: "nstk:refill:pet" },
    ],
    [
      { t: "♻️ REFILL WEAPONS", d: "nstk:refill:weapon" },
      { t: "♻️ REFILL ALL", d: "nstk:refill:all" },
    ],
    [{ t: "🔁 ROTAÇÃO POR FAIXA", d: "nstk:rot:all" }],
    nav("nft:hub"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function nftStockCallback(ctx: Ctx, rest: string[]) {
  const [sub, kind] = rest;
  // REFILL da reserva: publica unidades já preparadas (RESERVE -> AVAILABLE), sem deploy.
  if (sub === "refill") {
    const kinds = kind === "all" ? ["hero", "pet", "weapon"] : [kind];
    const parts: string[] = [];
    for (const k of kinds) {
      const r = (await rpc("admin_nft_reserve_refill", { p_admin_id: ctx.adminId, p_kind: k, p_limit: 2 })) as any;
      const published = (r?.published ?? []) as any[];
      if (!published.length) {
        parts.push(
          `<b>${NFT_RESERVE_LABEL[k]}</b>\n⚠️ Nenhum NFT ${k === "hero" ? "Hero" : k === "pet" ? "Pet" : "Weapon"} disponível na reserva.\nCrie/adicione novas unidades antes de realizar outro refill.`,
        );
        continue;
      }
      parts.push(
        `<b>${NFT_RESERVE_LABEL[k]}</b>: ${fmt(published.length)} publicada(s) · 🟢 ${fmt(r.beforeAvailable)} → ${fmt(r.afterAvailable)} · 📦 reserva ${fmt(r.reserveLeft)}\n${published.map((c) => `• ${esc(c.name)} ${nftSerial(c.serial)} · ${fmt(c.priceTon)} TON${Number(c.dailyYieldTon) > 0 ? ` · ${c.dailyYieldTon}/dia` : ""}\n  <code>${esc(c.instance)}</code>`).join("\n")}`,
      );
    }
    await send(ctx, `♻️ <b>REFILL CONCLUÍDO</b>\n\n${parts.join("\n\n")}`);
    return nftStockHub({ ...ctx, messageId: undefined }, false);
  }
  // Rotação clássica por faixa de preço (gera unidades novas do stock pool).
  if (sub === "rot") {
    const kinds = kind === "all" ? ["hero", "pet"] : [kind];
    const parts: string[] = [];
    for (const k of kinds) {
      const r = (await rpc("admin_nft_stock_refill", { p_admin_id: ctx.adminId, p_kind: k })) as any;
      const created = (r?.created ?? []) as any[];
      const short = (r?.shortages ?? []) as any[];
      parts.push(
        `<b>${NFT_RESERVE_LABEL[k]}</b>: ${fmt(created.length)} nova(s)\n${created.map((c) => `• ${esc(c.name)} ${nftSerial(c.serial)} · ${fmt(c.tierTon)} TON · ${c.dailyYieldTon}/dia\n  <code>${esc(c.instance)}</code>`).join("\n") || "• nada a repor"}${short.length ? `\n⚠️ reserva insuficiente: ${short.map((s) => `${fmt(s.tierTon)} TON (${fmt(s.missing)})`).join(", ")}` : ""}`,
      );
    }
    await send(ctx, `🔁 <b>ROTAÇÃO CONCLUÍDA</b>\n\n${parts.join("\n\n")}`);
    return nftStockHub({ ...ctx, messageId: undefined }, false);
  }
  return nftStockHub(ctx);
}

// ---------------------------------------------------------------- ⚔️ NFT EXCLUSIVE equipment (1/1)
// Supply 1/1: uma unidade vendida nunca volta para AVAILABLE.
async function nftEquipHub(ctx: Ctx, slot: string | null = null, useEdit = true) {
  const d = (await rpc("admin_nft_equipment_overview", { p_admin_id: ctx.adminId, p_slot: slot })) as any;
  const items = (d.items ?? []) as any[];
  const available = items.filter((x) => x.status === "AVAILABLE");
  const sold = items.filter((x) => x.status !== "AVAILABLE");
  const line = (x: any) =>
    `• ${esc(x.name)} ${nftSerial(x.serial)} · ${esc(String(x.slot).toUpperCase())}${x.heroClass ? `/${esc(String(x.heroClass).toUpperCase())}` : ""} · ${x.priceTon} TON\n  ⚔️ ${fmt(x.atk)} · 🛡 ${fmt(x.def)} · ❤️ ${fmt(x.hp)}${x.ownerName ? `\n  👤 ${esc(x.ownerName)} (<code>${x.ownerTelegramId}</code>)` : ""}`;
  const text = [
    `⚔️ <b>NFT EXCLUSIVE EQUIPMENT</b>${slot ? ` — ${slot.toUpperCase()}` : ""}`,
    `Unidades ${fmt(items.length)} · 🟢 estoque ${fmt(available.length)} · 👤 vendidos ${fmt(sold.length)}`,
    "",
    `<b>🟢 EM ESTOQUE</b>\n${available.slice(0, 12).map(line).join("\n") || "nenhuma unidade disponível"}`,
    "",
    `<b>👤 VENDIDOS</b>\n${sold.slice(0, 10).map(line).join("\n") || "nenhuma venda ainda"}`,
    "",
    "Supply 1/1: cada peça pertence permanentemente ao comprador e nunca retorna à loja.",
  ]
    .join("\n")
    .slice(0, 3800);
  const rows = [
    [{ t: "➕ CRIAR NFT", d: "neq:ask:neqnew" }],
    [
      { t: "⚔ WEAPONS", d: "neq:slot:weapon" },
      { t: "🛡 ARMORS", d: "neq:slot:armor" },
      { t: "💍 RINGS", d: "neq:slot:ring" },
    ],
    [{ t: "🔄 TODOS", d: "neq:hub" }],
    [{ t: "💰 PREÇOS & RENDIMENTOS", d: "nprc:hub" }],
    nav("m:heroes"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function nftEquipCallback(ctx: Ctx, rest: string[]) {
  const [sub, arg] = rest;
  if (sub === "slot") return nftEquipHub(ctx, arg);
  return nftEquipHub(ctx, null);
}

async function nftEquipPrompt(ctx: Ctx, key: string, _args: string[], text: string) {
  if (key === "neqnew") {
    const parts = text.split("|").map((p) => p.trim());
    if (parts.length < 6)
      throw new Error("KEEP_SESSION::⚠️ Formato: <code>slot|nome|classe|atk|def|hp|preco_ton|url_imagem</code>");
    const [slot, name, cls, atk, def, hp, price, image] = parts;
    const r = (await rpc("admin_nft_equipment_create", {
      p_admin_id: ctx.adminId,
      p_slot: slot,
      p_name: name,
      p_hero_class: cls && cls !== "-" ? cls : null,
      p_image: image || null,
      p_atk: Number(atk || 0),
      p_def: Number(def || 0),
      p_hp: Number(hp || 0),
      p_price_ton: Number(price || 15),
    })) as any;
    await clearSession(ctx);
    await send(
      ctx,
      `✅ <b>NFT criado</b>\n${esc(r.name)} ${nftSerial(r.serial)} · ${esc(String(r.slot).toUpperCase())}${r.heroClass ? `/${esc(String(r.heroClass).toUpperCase())}` : ""} · ${r.priceTon} TON`,
    );
    return nftEquipHub({ ...ctx, messageId: undefined }, null, false);
  }
  return nftEquipHub({ ...ctx, messageId: undefined }, null, false);
}

// ------------------------------------------------- 💰 NFT PREÇOS & RENDIMENTOS (sem deploy)
// Um único painel para: preço/rendimento dos Heróis NFT, preço/rendimento dos Pets NFT
// e preço dos Equipamentos NFT. Só afeta unidades AINDA DISPONÍVEIS (1/1 vendido nunca muda de preço).
const NPRC_TARGETS: Record<string, string> = {
  hero_price: "💰 Preço Herói NFT",
  hero_yield: "⛏ Rendimento Herói NFT (TON)",
  hero_yield_myth: "🪙 Rendimento Herói NFT (MYTH)",
  pet_price: "💰 Preço Pet NFT",
  pet_yield: "💧 Rendimento Pet NFT (TON)",
  pet_yield_myth: "🪙 Rendimento Pet NFT (MYTH)",
  equip_price: "⚔️ Preço Equipamento NFT",
};

async function nftPriceHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_nft_pricing_overview", { p_admin_id: ctx.adminId })) as any;
  const heroes = (d.heroes ?? []) as any[];
  const pets = (d.pets ?? []) as any[];
  const equips = (d.equipment ?? []) as any[];
  const py = d.petYield ?? {};
  const currency = String(d.miningCurrency ?? "ton").toUpperCase();
  const range = (a: any, b: any, unit: string) =>
    Number(a ?? 0) === Number(b ?? 0) ? `${Number(a ?? 0)} ${unit}` : `${Number(a ?? 0)}–${Number(b ?? 0)} ${unit}`;

  const text = [
    "💰 <b>NFT — PREÇOS & RENDIMENTOS</b>",
    "<i>Alterações valem imediatamente, sem publicar o app.</i>",
    `Moeda de mineração ativa: <b>${esc(currency)}</b>`,
    "",
    "<b>⚔️ HERÓIS NFT</b>",
    heroes
      .map(
        (h) =>
          `• Tier ${Number(h.tier)} TON · 🟢 ${fmt(h.available)} · 👤 ${fmt(h.sold)}\n  preço ${range(h.priceMin, h.priceMax, "TON")} · mineração ${range(h.yieldMin, h.yieldMax, "TON/dia")}\n  🪙 loja ${range(h.mythMin, h.mythMax, "MYTH/dia")}`,
      )
      .join("\n") || "nenhum herói NFT",
    "",
    "<b>🐾 PETS NFT</b>",
    pets
      .map(
        (p) =>
          `• Tier ${Number(p.tier)} TON · 🟢 ${fmt(p.available)} · 👤 ${fmt(p.sold)}\n  preço ${range(p.priceMin, p.priceMax, "TON")}\n  🪙 loja ${range(p.mythMin, p.mythMax, "MYTH/dia")}`,
      )
      .join("\n") || "nenhum pet NFT",
    `  rendimento tier 20 = ${Number(py.tier20 ?? 0)} TON/dia · tier 30 = ${Number(py.tier30 ?? 0)} TON/dia`,
    "",
    "<b>🛡 EQUIPAMENTOS NFT</b>",
    equips
      .map(
        (e) =>
          `• ${esc(String(e.slot).toUpperCase())} · 🟢 ${fmt(e.available)} · 👤 ${fmt(e.sold)} · preço ${range(e.priceMin, e.priceMax, "TON")}`,
      )
      .join("\n") || "nenhum equipamento NFT",
    "",
    "🔒 <b>YIELD CONGELADO</b>: alterações de rendimento (TON ou MYTH) valem <b>SOMENTE PARA AS UNIDADES AINDA EM LOJA</b>.",
    "NFTs já adquiridos mantêm para sempre o rendimento do momento da aquisição (venda/transferência não altera).",
  ]
    .join("\n")
    .slice(0, 3800);

  const rows: { t: string; d: string }[][] = [];
  for (const h of heroes) {
    const tier = Number(h.tier);
    rows.push([
      { t: `💰 HERÓI ${tier}T`, d: `nprc:ask:nprcset|hero_price|${tier}` },
      { t: `⛏ MINER. ${tier}T`, d: `nprc:ask:nprcset|hero_yield|${tier}` },
      { t: `🪙 MYTH ${tier}T`, d: `nprc:ask:nprcmyth|hero_yield_myth|${tier}` },
    ]);
  }
  for (const p of pets) {
    const tier = Number(p.tier);
    const row = [{ t: `💰 PET ${tier}T`, d: `nprc:ask:nprcset|pet_price|${tier}` }];
    if (tier === 20 || tier === 30) row.push({ t: `💧 REND. ${tier}T`, d: `nprc:ask:nprcset|pet_yield|${tier}` });
    row.push({ t: `🪙 MYTH ${tier}T`, d: `nprc:ask:nprcmyth|pet_yield_myth|${tier}` });
    rows.push(row);
  }
  // Atalho global: aplica o mesmo rendimento MYTH a TODO o estoque em loja (heróis ou pets).
  rows.push([
    { t: "🪙 MYTH TODOS HERÓIS", d: "nprc:ask:nprcmyth|hero_yield_myth|all" },
    { t: "🪙 MYTH TODOS PETS", d: "nprc:ask:nprcmyth|pet_yield_myth|all" },
  ]);
  rows.push([
    { t: "⚔ ARMAS", d: "nprc:ask:nprcset|equip_price|weapon" },
    { t: "🛡 ARMADURAS", d: "nprc:ask:nprcset|equip_price|armor" },
    { t: "💍 ANÉIS", d: "nprc:ask:nprcset|equip_price|ring" },
  ]);
  rows.push([{ t: "🧾 REVISÃO DE YIELD", d: "nprc:review" }]);
  rows.push([{ t: "☢️ APLICAR EM NFTS EXISTENTES", d: "nprc:force" }]);
  rows.push([{ t: "🔄 ATUALIZAR", d: "nprc:hub" }]);
  rows.push(nav("m:heroes"));

  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

// Lista de auditoria: rendimento congelado por unidade x rendimento atual do template.
async function nftYieldReview(ctx: Ctx) {
  const d = (await rpc("admin_nft_yield_review", { p_admin_id: ctx.adminId })) as any;
  const line = (x: any, unit: string) => {
    const inst = Number(x.instanceYield ?? 0);
    const tpl = Number(x.templateYield ?? 0);
    const flag = inst === tpl ? "✅" : "🔒";
    return `${flag} ${nftSerial(x.serial)} · tier ${Number(x.tierTon ?? 0)} · <b>${inst}</b> ${unit} (template ${tpl})`;
  };
  const heroes = (d.heroes ?? []) as any[];
  const pets = (d.pets ?? []) as any[];
  const div = [...heroes, ...pets].filter((x) => Number(x.instanceYield ?? 0) !== Number(x.templateYield ?? 0)).length;
  const text = [
    "🧾 <b>REVISÃO DE YIELD POR UNIDADE</b>",
    "<i>🔒 = rendimento congelado diferente do template atual (correto, é o valor prometido na aquisição).</i>",
    "",
    "<b>⚔️ HERÓIS NFT ADQUIRIDOS</b>",
    heroes.map((h) => line(h, "TON/dia")).join("\n") || "nenhum",
    "",
    "<b>🐾 PETS NFT ATIVOS</b>",
    pets.map((p) => line(p, "TON/dia")).join("\n") || "nenhum",
    "",
    `Unidades com rendimento diferente do template: <b>${fmt(div)}</b>`,
  ]
    .join("\n")
    .slice(0, 3800);
  return edit(ctx, text, kb([[{ t: "🔄 ATUALIZAR", d: "nprc:review" }], nav("nprc:hub")]));
}

async function nftYieldForceMenu(ctx: Ctx) {
  const text = [
    "☢️ <b>APLICAR EM NFTS EXISTENTES</b>",
    "",
    "Esta ação altera o rendimento de unidades <b>JÁ VENDIDAS</b> — quebra a promessa de yield congelado.",
    "Exige motivo obrigatório e fica registrada na auditoria.",
    "",
    "Escolha o alvo:",
  ].join("\n");
  return edit(
    ctx,
    text,
    kb([
      [
        { t: "⚔️ HERÓIS TIER 20", d: "nprc:ask:nprcforce|hero_yield|20" },
        { t: "⚔️ TIER 30", d: "nprc:ask:nprcforce|hero_yield|30" },
      ],
      [
        { t: "⚔️ HERÓIS TIER 50", d: "nprc:ask:nprcforce|hero_yield|50" },
        { t: "⚔️ TODOS", d: "nprc:ask:nprcforce|hero_yield|all" },
      ],
      [
        { t: "🐾 PETS TIER 20", d: "nprc:ask:nprcforce|pet_yield|20" },
        { t: "🐾 PETS TIER 30", d: "nprc:ask:nprcforce|pet_yield|30" },
      ],
      nav("nprc:hub"),
    ]),
  );
}

async function nftPricePrompt(ctx: Ctx, key: string, args: string[], text: string) {
  if (key === "nprcset" || key === "nprcmyth") {
    const [target, filter] = args;
    if (!target || !NPRC_TARGETS[target])
      throw new Error("KEEP_SESSION::⚠️ Alvo inválido. Volte ao painel e escolha novamente.");
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0)
      throw new Error("KEEP_SESSION::⚠️ Envie um número válido (ex.: <code>50</code> ou <code>1.25</code>).");
    const r = (await rpc("admin_nft_pricing_set", {
      p_admin_id: ctx.adminId,
      p_target: target,
      p_key: filter || "all",
      p_value: value,
    })) as any;
    await clearSession(ctx);
    const unit = target.endsWith("_yield_myth") ? " MYTH/dia" : "";
    const scope = target.includes("_yield")
      ? "\n🔒 Aplicado <b>SOMENTE ÀS UNIDADES EM LOJA</b> — NFTs já vendidos seguem com o rendimento congelado."
      : "";
    await send(
      ctx,
      `✅ <b>${NPRC_TARGETS[target]}</b> atualizado\nFiltro: <code>${esc(filter || "all")}</code> · novo valor: <b>${value}${unit}</b>\nUnidades afetadas: ${fmt(r?.affected ?? 0)}${scope}`,
    );
    return nftPriceHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "nprcforce") {
    const [target, filter] = args;
    if (target !== "hero_yield" && target !== "pet_yield") throw new Error("KEEP_SESSION::⚠️ Alvo inválido.");
    const parts = String(text)
      .split("|")
      .map((s) => s.trim());
    const value = parseAmount(parts[0] ?? "");
    const reason = parts[1] ?? "";
    const confirm = (parts[2] ?? "").toUpperCase();
    if (!Number.isFinite(value) || value < 0)
      throw new Error("KEEP_SESSION::⚠️ Valor inválido. Use <code>valor|motivo|CONFIRMAR</code>.");
    if (reason.length < 5) throw new Error("KEEP_SESSION::⚠️ Motivo obrigatório (mín. 5 caracteres).");
    if (confirm !== "CONFIRMAR")
      throw new Error("KEEP_SESSION::⚠️ Confirmação ausente. Termine a mensagem com <code>|CONFIRMAR</code>.");
    const r = (await rpc("admin_nft_yield_apply_existing", {
      p_admin_id: ctx.adminId,
      p_target: target,
      p_key: filter || "all",
      p_value: value,
      p_reason: reason,
    })) as any;
    await clearSession(ctx);
    await send(
      ctx,
      `☢️ <b>Rendimento alterado em NFTs existentes</b>\nAlvo: <code>${esc(target)}</code> · filtro <code>${esc(filter || "all")}</code>\nNovo valor: <b>${value}</b> TON/dia\nUnidades afetadas: <b>${fmt(r?.affected ?? 0)}</b>\nMotivo: ${esc(reason)}\n<i>Registrado na auditoria.</i>`,
    );
    return nftPriceHub({ ...ctx, messageId: undefined }, false);
  }
  return nftPriceHub({ ...ctx, messageId: undefined }, false);
}

// 🛡 HERO PROGRESSION — Lv. 1 → 20, XP curve, per-activity XP and per-hero daily cap.
// Everything is stored in game_settings.hero_progression: no deploy needed to tune it.
// ⚖️ GAME BALANCE — read-only audit of the official rarity scales.
// Hero combat stats and pet power both come from single server-side sources;
// this hub only reports them so nobody tunes balance blindly.
async function gameBalanceHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_game_balance_overview", { p_admin_id: ctx.adminId })) as any;
  const heroes = (d?.heroRarities ?? []) as any[];
  const pets = (d?.petRarities ?? []) as any[];
  const text = [
    "⚖️ <b>GAME BALANCE</b>",
    "",
    "<b>HERÓIS — ESCALA POR RARIDADE</b>",
    heroes
      .map(
        (r) =>
          `• <b>${esc(r.rarity)}</b> — boss ATK ${r.bossAtk} · boss HP ${fmt(r.bossHp)}\n   instâncias ${fmt(r.instances)} · ATK ${fmt(r.minAtk)}–${fmt(r.maxAtk)} (méd. ${fmt(r.avgAtk)}) · HP méd. ${fmt(r.avgHp)}`,
      )
      .join("\n"),
    "",
    "<b>PETS — POWER BASE POR RARIDADE</b>",
    pets.map((r) => `• <b>${esc(r.rarity)}</b> — base ${fmt(r.basePower)} · instâncias ${fmt(r.instances)}`).join("\n"),
    "",
    `<b>Fórmula do Power do pet:</b> <code>${esc(d?.petFormula ?? "")}</code>`,
    `<b>Fórmula dos stats do herói:</b> <code>${esc(d?.heroFormula ?? "")}</code>`,
    "",
    "ℹ️ Somente leitura. As escalas são centralizadas no servidor e usadas por Coleção, PvP, Boss, Clã e Expedições.",
  ]
    .join("\n")
    .slice(0, 3800);
  const rows = [[{ t: "🔄 ATUALIZAR", d: "gbal:hub" }], nav("m:heroes")];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function heroProgressionHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_hero_progression_overview", { p_admin_id: ctx.adminId })) as any;
  const acts = (d?.activities ?? {}) as Record<string, any>;
  const curve = Array.isArray(d?.curve) ? (d.curve as number[]) : [];
  const quests = (d?.questsWithHeroXp ?? []) as any[];

  const actLine = (code: string) => {
    const a = acts[code] ?? {};
    return `• <b>${esc(code)}</b> — ${fmt(a.xp)} XP/evento · até ${fmt(a.dailyEvents)} eventos/dia · cap ${fmt(a.dailyXpCap)} XP/dia`;
  };
  const text = [
    "🛡 <b>PROGRESSÃO DE HERÓIS</b>",
    `Nível máximo: <b>Lv. ${fmt(d?.maxLevel)}</b> · limite diário: <b>${fmt(d?.dailyXpCapPerHero)} XP por herói</b>`,
    "",
    "<b>XP POR ATIVIDADE</b>",
    Object.keys(acts).length ? Object.keys(acts).map(actLine).join("\n") : "nenhuma atividade configurada",
    "",
    "<b>CURVA DE XP</b> (XP para subir de nível)",
    curve.length
      ? curve
          .map((xp, i) => `Lv. ${i + 1}→${i + 2}: ${fmt(xp)}`)
          .join(" · ")
          .slice(0, 900)
      : "curva padrão",
    "",
    `<b>HOJE (${esc(d?.gameDay)})</b>`,
    `XP concedido: <b>${fmt(d?.xpToday)}</b> · heróis: ${fmt(d?.heroesToday)} · level ups: ${fmt(d?.levelUpsToday)}`,
    `Heróis no nível máximo: <b>${fmt(d?.maxedHeroes)}</b>`,
    "",
    "<b>MISSÕES QUE DÃO XP DE HERÓI</b>",
    quests.length
      ? quests
          .map((q) => `${q.enabled ? "✅" : "⛔"} <code>${esc(q.code)}</code> ${esc(q.title)}`)
          .join("\n")
          .slice(0, 900)
      : "nenhuma missão ativa",
    "",
    "ℹ️ O XP é concedido apenas pelo servidor, após a atividade ser validada e persistida.",
  ]
    .join("\n")
    .slice(0, 3800);

  const rows: { t: string; d: string }[][] = [
    [
      { t: "🎚 NÍVEL MÁXIMO", d: "hprog:ask:hpset|maxlevel|-" },
      { t: "⏱ CAP DIÁRIO/HERÓI", d: "hprog:ask:hpset|dailycap|-" },
    ],
  ];
  for (const code of Object.keys(acts)) {
    rows.push([
      { t: `⚡ XP ${code}`, d: `hp:ask:hpset|activity_xp|${code}` },
      { t: `🔢 EVENTOS ${code}`, d: `hp:ask:hpset|activity_events|${code}` },
      { t: `🚧 CAP ${code}`, d: `hp:ask:hpset|activity_cap|${code}` },
    ]);
  }
  rows.push([{ t: "📈 EDITAR CURVA DE XP", d: "hprog:ask:hpcurve|curve|-" }]);
  rows.push([{ t: "🎯 XP EM MISSÃO (ON/OFF)", d: "hprog:ask:hpquest|quest_hero_xp|-" }]);
  rows.push([{ t: "🔄 ATUALIZAR", d: "hprog:hub" }]);
  rows.push(nav("m:heroes"));

  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function heroProgressionPrompt(ctx: Ctx, key: string, args: string[], text: string) {
  const [field, target] = args;
  if (key === "hpset") {
    const value = parseAmount(text);
    if (!Number.isFinite(value) || value < 0)
      throw new Error("KEEP_SESSION::⚠️ Envie um número inteiro válido (ex.: <code>40</code>).");
    await rpc("admin_hero_progression_set", {
      p_admin_id: ctx.adminId,
      p_field: field,
      p_target: target === "-" ? null : target,
      p_value: Math.round(value),
    });
    await clearSession(ctx);
    await send(
      ctx,
      `✅ <b>${esc(field)}</b>${target && target !== "-" ? ` · <code>${esc(target)}</code>` : ""} atualizado para <b>${Math.round(value)}</b>.\nAplicado na Mythreon imediatamente (sem deploy).`,
    );
    return heroProgressionHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "hpcurve") {
    // Format: "<level>|<xp>" — level is the origin level (1..19).
    const [lvlRaw, xpRaw] = String(text)
      .split("|")
      .map((s) => s.trim());
    const level = Number(lvlRaw);
    const xp = parseAmount(xpRaw ?? "");
    if (!Number.isInteger(level) || level < 1 || level > 19)
      throw new Error("KEEP_SESSION::⚠️ Nível inválido. Use <code>nível|xp</code> com nível entre 1 e 19.");
    if (!Number.isFinite(xp) || xp < 1) throw new Error("KEEP_SESSION::⚠️ XP inválido. Ex.: <code>5|1200</code>.");
    await rpc("admin_hero_progression_set", {
      p_admin_id: ctx.adminId,
      p_field: "curve",
      p_target: String(level),
      p_value: Math.round(xp),
    });
    await clearSession(ctx);
    await send(
      ctx,
      `✅ Curva atualizada: <b>Lv. ${level} → ${level + 1}</b> agora exige <b>${fmt(Math.round(xp))} XP</b>.`,
    );
    return heroProgressionHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "hpquest") {
    // Format: "<quest_code>|on" or "<quest_code>|off".
    const [codeRaw, stateRaw] = String(text)
      .split("|")
      .map((s) => s.trim());
    const code = (codeRaw ?? "").toLowerCase();
    const on = ["on", "1", "sim", "true", "ativar"].includes((stateRaw ?? "").toLowerCase());
    if (!code)
      throw new Error("KEEP_SESSION::⚠️ Envie <code>código_da_missão|on</code> ou <code>código_da_missão|off</code>.");
    await rpc("admin_hero_progression_set", {
      p_admin_id: ctx.adminId,
      p_field: "quest_hero_xp",
      p_target: code,
      p_value: on ? 1 : 0,
    });
    await clearSession(ctx);
    await send(ctx, `✅ Missão <code>${esc(code)}</code>: XP de herói <b>${on ? "ATIVADO" : "DESATIVADO"}</b>.`);
    return heroProgressionHub({ ...ctx, messageId: undefined }, false);
  }
  return heroProgressionHub({ ...ctx, messageId: undefined }, false);
}

async function nftTemplateMenu(ctx: Ctx) {
  const d = (await rpc("admin_nft_overview", { p_admin_id: ctx.adminId })) as any;
  const rows = (d.templates ?? []).map((x: any) => [
    { t: `💎 ${x.name} (${x.available}/${x.minted})`, d: `nft:tpl:${x.slug}` },
  ]);
  rows.push([{ t: "⌨️ DIGITAR SLUG", d: "nft:ask:nftmint" }]);
  rows.push(nav("nft:hub"));
  return edit(ctx, "➕ <b>CRIAR UNIDADE NFT</b>\nEscolha o pet exclusivo que receberá novos seriais.", kb(rows));
}

async function nftTemplateCard(ctx: Ctx, slug: string) {
  const d = (await rpc("admin_nft_overview", { p_admin_id: ctx.adminId })) as any;
  const x = (d.templates ?? []).find((r: any) => r.slug === slug);
  if (!x) return send(ctx, "⚠️ Template NFT não encontrado.", kb([nav("nft:hub")]));
  return edit(
    ctx,
    `💎 <b>${esc(x.name)}</b>\nSlug <code>${esc(x.slug)}</code> · ${esc(String(x.rarity).toUpperCase())}\nUnidades: ${fmt(x.minted)} · 🟢 ${fmt(x.available)} · 👤 ${fmt(x.owned)}\n\nCada unidade recebe um serial único e um identificador de instância.`,
    kb([
      [
        { t: "➕ 1 UNIDADE", d: `nft:mint:${slug}:1` },
        { t: "➕ 5", d: `nft:mint:${slug}:5` },
        { t: "➕ 10", d: `nft:mint:${slug}:10` },
      ],
      [{ t: "📋 UNIDADES DISPONÍVEIS", d: `nft:avail:${slug}` }],
      nav("nft:new"),
    ]),
  );
}

async function nftMint(ctx: Ctx, slug: string, qty: number) {
  const r = (await rpc("admin_nft_create", { p_admin_id: ctx.adminId, p_slug: slug, p_quantity: qty })) as any;
  const created = (r.created ?? []) as any[];
  await send(
    ctx,
    `✅ <b>${fmt(created.length)}</b> unidade(s) de <b>${esc(r.pet)}</b> criada(s).\n${created.map((c) => `• ${nftSerial(c.serial)} <code>${esc(c.instance)}</code>`).join("\n")}`,
  );
  return nftTemplateCard({ ...ctx, messageId: undefined }, slug);
}

async function nftAvailable(ctx: Ctx, slug: string | null, ref?: string) {
  const units = (await rpc("admin_nft_available", { p_admin_id: ctx.adminId, p_slug: slug, p_limit: 30 })) as any[];
  if (!units.length)
    return send(
      ctx,
      "⚠️ Nenhuma unidade NFT disponível. Crie novas unidades primeiro.",
      kb([[{ t: "➕ CRIAR UNIDADE", d: "nft:new" }], nav("nft:hub")]),
    );
  const rows = units.map((u) => [
    { t: `${u.pet} ${nftSerial(u.serial)}`, d: ref ? `nft:deliver:${u.id}:${ref}` : `nft:unit:${u.id}` },
  ]);
  rows.push(nav("nft:hub"));
  const head = ref
    ? `🎁 <b>ENTREGAR NFT</b>\nJogador: <code>${esc(ref)}</code>\nEscolha a unidade única:`
    : "🟢 <b>UNIDADES DISPONÍVEIS</b>";
  return send(ctx, head, kb(rows));
}

async function nftUnitCard(ctx: Ctx, id: string, useEdit = true) {
  const rows = (await rpc("admin_nft_search", { p_admin_id: ctx.adminId, p_query: id })) as any[];
  const u = rows[0];
  if (!u) return send(ctx, "⚠️ Unidade NFT não encontrada.", kb([nav("nft:hub")]));
  const owner = u.owner ? `${esc(u.owner.name)} · <code>${u.owner.telegramId}</code>` : "—";
  const text = `💎 <b>${esc(u.pet)}</b> ${nftSerial(u.serial)}\nInstância <code>${esc(u.instance)}</code>\nStatus: <b>${NFT_STATUS_LABEL[u.status] ?? esc(u.status)}</b>\nDono: ${owner}\n<code>${esc(u.id)}</code>`;
  const buttons =
    u.status === "OWNED"
      ? [[{ t: "↩️ REVOGAR", d: `nft:rev:${u.id}` }], nav("nft:hub")]
      : [[{ t: "🎁 ENTREGAR", d: "nft:ask:nftgive" }], nav("nft:hub")];
  return useEdit ? edit(ctx, text, kb(buttons)) : send(ctx, text, kb(buttons));
}

async function nftRegistry(ctx: Ctx, offset: number, ownedOnly = false) {
  const d = (await rpc("admin_nft_registry", { p_admin_id: ctx.adminId, p_limit: 15, p_offset: offset })) as any;
  const units = ((d.units ?? []) as any[]).filter((u) => !ownedOnly || u.status === "OWNED");
  const lines =
    units
      .map(
        (u) =>
          `• ${esc(u.pet)} ${nftSerial(u.serial)} — ${NFT_STATUS_LABEL[u.status] ?? esc(u.status)}${u.owner ? ` · ${esc(u.owner.name)}` : ""}`,
      )
      .join("\n") || "sem unidades nesta página";
  const rows = units.slice(0, 10).map((u) => [
    {
      t: `${u.pet} ${nftSerial(u.serial)}${u.status === "OWNED" ? " 👤" : ""}`,
      d: ownedOnly ? `nft:rev:${u.id}` : `nft:unit:${u.id}`,
    },
  ]);
  const pager: any[] = [];
  if (offset > 0)
    pager.push({ t: "⬅️ Anterior", d: `nft:${ownedOnly ? "revlist" : "list"}:${Math.max(0, offset - 15)}` });
  if (offset + 15 < Number(d.total ?? 0))
    pager.push({ t: "Próxima ➡️", d: `nft:${ownedOnly ? "revlist" : "list"}:${offset + 15}` });
  if (pager.length) rows.push(pager);
  rows.push(nav("nft:hub"));
  return edit(
    ctx,
    `${ownedOnly ? "↩️ <b>REVOGAR NFT</b>\nEscolha a unidade entregue:" : `📋 <b>REGISTRO NFT</b> (${fmt(d.total)})`}\n${lines}`,
    kb(rows),
  );
}

async function nftCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  switch (sub) {
    case "ask":
      return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
    case "new":
      return nftTemplateMenu(ctx);
    case "tpl":
      return nftTemplateCard(ctx, a);
    case "mint":
      return nftMint(ctx, a, Number(b || 1));
    case "avail":
      return nftAvailable(ctx, a || null);
    case "unit":
      return nftUnitCard(ctx, a);
    case "list":
      return nftRegistry(ctx, Number(a || 0));
    case "revlist":
      return nftRegistry(ctx, Number(a || 0), true);
    case "rev":
      return send(
        ctx,
        "⚠️ Confirmar a <b>revogação</b>? A unidade volta ao registro como disponível e sai do inventário do jogador.",
        kb([
          [
            { t: "✅ CONFIRMAR", d: `nft:revoke:${a}` },
            { t: "❌ Cancelar", d: "nft:hub" },
          ],
        ]),
      );
    case "revoke": {
      const r = (await rpc("admin_nft_revoke", {
        p_admin_id: ctx.adminId,
        p_nft_id: a,
        p_reason: "revogado pelo painel admin",
      })) as any;
      await send(ctx, `↩️ <b>${esc(r.pet)}</b> ${nftSerial(r.serial)} revogado.\n<code>${esc(r.instance)}</code>`);
      return nftHub({ ...ctx, messageId: undefined }, false);
    }
    case "deliver": {
      const r = (await rpc("admin_nft_give", {
        p_admin_id: ctx.adminId,
        p_ref: b,
        p_nft_id: a,
        p_reason: "entrega NFT pelo painel admin",
      })) as any;
      await send(
        ctx,
        `💎 <b>${esc(r.pet)}</b> ${nftSerial(r.serial)} entregue a <b>${esc(r.playerName)}</b> (<code>${r.telegramId}</code>).\nInstância <code>${esc(r.instance)}</code>`,
      );
      return nftHub({ ...ctx, messageId: undefined }, false);
    }
    case "hist": {
      const rows = (await rpc("admin_nft_history", { p_admin_id: ctx.adminId, p_limit: 20 })) as any[];
      const lines =
        rows
          .map(
            (h) =>
              `• ${String(h.createdAt).slice(0, 16).replace("T", " ")} · <b>${esc(h.action)}</b> ${esc(h.pet)} <code>${esc(h.instance)}</code>${h.to ? ` → ${esc(h.to)}` : ""}${h.from ? ` (de ${esc(h.from)})` : ""}`,
          )
          .join("\n") || "sem histórico";
      return edit(ctx, `📜 <b>HISTÓRICO NFT</b>\n${lines}`, kb([nav("nft:hub")]));
    }
    default:
      return nftHub(ctx);
  }
}

// ---------------------------------------------------------------- 💎 NFT REWARD POOL (master admin only)
// The pool is a REAL treasury used to pay NFT EXCLUSIVE yields. It exists only here:
// the Mini App never receives pool balance, reserves, health or obligations —
// players only ever see their own NFT yield. Every RPC below asserts the master admin id.
const NP_HEALTH: Record<string, string> = {
  HEALTHY: "🟢 HEALTHY",
  STABLE: "🟡 STABLE",
  LOW: "🟠 LOW",
  CRITICAL: "🔴 CRITICAL",
};
const npTon = (v: unknown) => Number(v ?? 0).toFixed(4);

async function nftPoolHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_nft_pool_overview", { p_admin_id: ctx.adminId })) as any;
  const text =
    `💎 <b>NFT REWARD POOL</b> <i>(backend only)</i>\n\n` +
    `<b>Balance</b> ${npTon(d.balanceTon)} TON\n` +
    `<b>Reserved</b> ${npTon(d.reservedTon)} TON\n` +
    `<b>Available</b> ${npTon(d.availableTon)} TON\n` +
    `<b>Daily obligation</b> ${npTon(d.dailyObligationTon)} TON\n` +
    `<b>Claimable now</b> ${npTon(d.claimableTon)} TON\n` +
    `<b>Lifetime funded</b> ${npTon(d.lifetimeFundedTon)} TON\n` +
    `<b>Lifetime paid</b> ${npTon(d.lifetimePaidTon)} TON\n` +
    `<b>Pool health</b> ${NP_HEALTH[String(d.health)] ?? esc(String(d.health))}\n` +
    `NFTs ativos ${fmt(d.activeNfts)}/${fmt(d.totalNfts)}\n\n` +
    `<i>Invisível para jogadores. Somente o admin mestre vê estes números.</i>`;
  const rows = [
    [
      { t: "➕ APORTAR TON", d: "np:ask:npfund" },
      { t: "⚙️ AJUSTE MANUAL", d: "np:ask:npadjust" },
    ],
    [
      { t: "💠 UNIDADES (10 NFTs)", d: "np:units" },
      { t: "📜 LEDGER", d: "np:ledger" },
    ],
    [{ t: "🔧 CONFIG RENDIMENTO", d: "np:cfg" }],
    nav("nft:hub"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function nftPoolUnits(ctx: Ctx, data?: any) {
  const units = (data ?? (await rpc("admin_nft_pool_units", { p_admin_id: ctx.adminId }))) as any[];
  const lines =
    units
      .map(
        (u) =>
          `• ${nftSerial(u.serial)} ${u.status === "active" ? "🟢" : "⏸"} tier ${npTon(u.tierTon)} · dia ${npTon(u.effectiveDailyTon)} · disp ${npTon(u.availableTon)} · pago ${npTon(u.lifetimeEarnedTon)} · ${u.roiReached ? "ROI ✅" : "ROI …"} · ${esc(String(u.owner ?? "—"))}`,
      )
      .join("\n") || "Nenhuma posição NFT.";
  const rows = units.map((u) => [
    { t: `${nftSerial(u.serial)} ${u.status === "active" ? "⏸ PAUSAR" : "▶️ ATIVAR"}`, d: `np:toggle:${u.serial}` },
  ]);
  rows.push([{ t: "💠 ALTERAR TIER", d: "np:ask:nptier" }]);
  rows.push(nav("np:hub"));
  return edit(ctx, `💠 <b>POSIÇÕES NFT</b>\n${lines}`, kb(rows));
}

async function nftPoolLedger(ctx: Ctx) {
  const rows = (await rpc("admin_nft_pool_ledger", { p_admin_id: ctx.adminId, p_limit: 20 })) as any[];
  const lines =
    rows
      .map(
        (r) =>
          `• ${String(r.created_at).slice(0, 16).replace("T", " ")} · <b>${esc(r.type)}</b> ${Number(r.amount_ton) >= 0 ? "+" : ""}${npTon(r.amount_ton)} → ${npTon(r.balance_after)}${r.telegram_id ? ` · <code>${r.telegram_id}</code>` : ""}${r.note ? ` · ${esc(r.note)}` : ""}`,
      )
      .join("\n") || "sem lançamentos";
  return edit(ctx, `📜 <b>NFT_POOL_TRANSACTION</b>\n${lines}`, kb([nav("np:hub")]));
}

async function nftPoolConfig(ctx: Ctx) {
  const d = (await rpc("admin_nft_pool_overview", { p_admin_id: ctx.adminId })) as any;
  const c = d.settings ?? {};
  const text = `🔧 <b>CONFIG DE RENDIMENTO</b>\nTier 20 TON → ${npTon(c.tier20DailyTon ?? 0.5)} TON/dia\nTier 30 TON → ${npTon(c.tier30DailyTon ?? 0.8)} TON/dia\nResgate mínimo ${npTon(c.minClaimTon ?? 0.01)} TON`;
  return edit(
    ctx,
    text,
    kb([
      [
        { t: "💠 TIER 20", d: "np:ask:npcfg20" },
        { t: "💠 TIER 30", d: "np:ask:npcfg30" },
      ],
      [{ t: "💠 RESGATE MÍNIMO", d: "np:ask:npcfgmin" }],
      nav("np:hub"),
    ]),
  );
}

async function nftPoolCallback(ctx: Ctx, rest: string[]) {
  const [sub, a] = rest;
  switch (sub) {
    case "ask":
      return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
    case "units":
      return nftPoolUnits(ctx);
    case "ledger":
      return nftPoolLedger(ctx);
    case "cfg":
      return nftPoolConfig(ctx);
    case "toggle": {
      const units = (await rpc("admin_nft_pool_toggle", { p_admin_id: ctx.adminId, p_serial: Number(a) })) as any[];
      return nftPoolUnits(ctx, units);
    }
    default:
      return nftPoolHub(ctx);
  }
}

async function nftPoolPrompt(ctx: Ctx, key: string, _args: string[], text: string) {
  const num = Number(String(text).replace(",", ".").trim());
  switch (key) {
    case "npfund":
    case "npadjust": {
      if (!Number.isFinite(num) || num === 0) throw new Error("KEEP_SESSION::⚠️ Envie um valor numérico em TON.");
      if (key === "npfund" && num < 0)
        throw new Error("KEEP_SESSION::⚠️ Aportes devem ser positivos. Use AJUSTE MANUAL para debitar.");
      const d = (await rpc("admin_nft_pool_fund", {
        p_admin_id: ctx.adminId,
        p_amount_ton: num,
        p_type: key === "npfund" ? "FUND" : "ADMIN_ADJUSTMENT",
        p_note: key === "npfund" ? "aporte pelo painel admin" : "ajuste manual pelo painel admin",
      })) as any;
      await clearSession(ctx);
      await send(ctx, `💎 Pool atualizado: <b>${npTon(d.balanceTon)} TON</b> (${num >= 0 ? "+" : ""}${npTon(num)}).`);
      return nftPoolHub({ ...ctx, messageId: undefined }, false);
    }
    case "nptier": {
      const [serial, tier] = String(text)
        .trim()
        .split(/\s+/)
        .map((v) => Number(v.replace(",", ".")));
      if (!Number.isFinite(serial) || !Number.isFinite(tier) || tier <= 0)
        throw new Error("KEEP_SESSION::⚠️ Envie <code>serial tier_ton</code>. Ex.: <code>3 30</code>");
      const units = (await rpc("admin_nft_pool_set_tier", {
        p_admin_id: ctx.adminId,
        p_serial: serial,
        p_tier_ton: tier,
      })) as any[];
      await clearSession(ctx);
      await send(ctx, `💠 Tier do NFT ${nftSerial(serial)} definido em <b>${npTon(tier)} TON</b>.`);
      return nftPoolUnits({ ...ctx, messageId: undefined }, units);
    }
    case "npcfg20":
    case "npcfg30":
    case "npcfgmin": {
      if (!Number.isFinite(num) || num < 0) throw new Error("KEEP_SESSION::⚠️ Envie um número válido.");
      const map: Record<string, string> = {
        npcfg20: "tier20_daily_ton",
        npcfg30: "tier30_daily_ton",
        npcfgmin: "min_claim_ton",
      };
      await rpc("admin_nft_pool_config", { p_admin_id: ctx.adminId, p_key: map[key], p_value: num });
      await clearSession(ctx);
      await send(ctx, "✅ Configuração de rendimento atualizada.");
      return nftPoolHub({ ...ctx, messageId: undefined }, false);
    }
    default:
      return nftPoolHub({ ...ctx, messageId: undefined }, false);
  }
}

async function nftPrompt(ctx: Ctx, key: string, args: string[], text: string) {
  switch (key) {
    case "nftgive": {
      const ref = text.split(/\s+/)[0];
      if (!ref) throw new Error("KEEP_SESSION::⚠️ Envie o Telegram ID, @usuário ou nome do jogador.");
      await clearSession(ctx);
      return nftAvailable({ ...ctx, messageId: undefined }, null, ref);
    }
    case "nftmint": {
      const [slug, qty] = text.split(/\s+/);
      if (!slug) throw new Error("KEEP_SESSION::⚠️ Envie <code>slug quantidade</code>. Ex.: <code>ignarion 3</code>");
      await clearSession(ctx);
      return nftMint({ ...ctx, messageId: undefined }, slug, Number(qty || 1));
    }
    case "nftsearch": {
      const rows = (await rpc("admin_nft_search", { p_admin_id: ctx.adminId, p_query: text })) as any[];
      await clearSession(ctx);
      if (!rows.length) return send(ctx, "🔎 Nenhuma unidade NFT encontrada.", kb([nav("nft:hub")]));
      const buttons = rows
        .slice(0, 12)
        .map((u) => [
          { t: `${u.pet} ${nftSerial(u.serial)}${u.owner ? ` · ${u.owner.name}` : ""}`, d: `nft:unit:${u.id}` },
        ]);
      buttons.push(nav("nft:hub"));
      return send(ctx, `🔎 <b>${fmt(rows.length)}</b> unidade(s) encontrada(s).`, kb(buttons));
    }
    default:
      return nftHub({ ...ctx, messageId: undefined }, false);
  }
}

// ---------------------------------------------------------------- ⚔️ NFT EXCLUSIVE heroes
// Tier above ANCESTRAL. Never in recruit/chest/drop pools, never fusable/sellable.
// Every unit carries a unique serial (Eternis #001) bound to a single player.
const NFTH_FIELDS: Array<{ k: string; col: string; label: string }> = [
  { k: "atk", col: "base_atk", label: "⚔️ ATK" },
  { k: "hp", col: "base_hp", label: "❤️ HP" },
  { k: "def", col: "base_def", label: "🛡 DEF" },
  { k: "spd", col: "base_speed", label: "💨 SPEED" },
  { k: "crit", col: "crit_rate", label: "🎯 CRIT %" },
  { k: "skill", col: "skill_power", label: "✨ SKILL POWER" },
  { k: "growth", col: "growth_multiplier", label: "📈 CRESCIMENTO" },
  { k: "maxlvl", col: "max_level", label: "🔝 NÍVEL MÁX" },
];

async function nfthHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_nft_hero_overview", { p_admin_id: ctx.adminId })) as any;
  const t = d.totals ?? {};
  const lines =
    (d.templates ?? [])
      .map(
        (x: any) =>
          `• <code>${esc(x.heroKey)}</code> ${esc(x.name)} — ${fmt(x.minted)} unid. (🟢 ${fmt(x.available)} · 👤 ${fmt(x.owned)})`,
      )
      .join("\n") || "Nenhum herói NFT cadastrado.";
  const text = `⚔️ <b>NFT EXCLUSIVE HEROES</b>\n<i>Tier acima de ANCESTRAL</i>\n${lines}\n\n<b>REGISTRO</b>\nUnidades ${fmt(t.units)} · 🟢 ${fmt(t.available)} · 👤 ${fmt(t.owned)} · ↩️ ${fmt(t.revoked)}\n\nNão entram em recrutamento, baús, drops, fusão ou mercado. Evolução (nível e estrelas) permitida.`;
  const rows = [
    [
      { t: "➕ CRIAR UNIDADE", d: "nfth:new" },
      { t: "🎁 ENTREGAR", d: "nfth:ask:nfthgive" },
    ],
    [
      { t: "📋 LISTAR REGISTRO", d: "nfth:list:0" },
      { t: "🔎 PESQUISAR", d: "nfth:ask:nfthsearch" },
    ],
    [
      { t: "⚙️ EDITOR DE POWER", d: "nfth:bal" },
      { t: "📊 ESTATÍSTICAS", d: "nfth:stats" },
    ],
    [
      { t: "↩️ REVOGAR", d: "nfth:revlist:0" },
      { t: "📜 HISTÓRICO", d: "nfth:hist" },
    ],
    [
      { t: "📦 NFT STOCK", d: "nstk:hub" },
      { t: "⚔️ NFT EQUIPMENT", d: "neq:hub" },
    ],
    [{ t: "💰 PREÇOS & RENDIMENTOS", d: "nprc:hub" }],
    nav("m:heroes"),
  ];
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function nfthTemplateMenu(ctx: Ctx, mode: "mint" | "bal") {
  const d = (await rpc("admin_nft_hero_overview", { p_admin_id: ctx.adminId })) as any;
  const rows = (d.templates ?? []).map((x: any) => [
    {
      t: `⚔️ ${x.name} (${x.available}/${x.minted})`,
      d: mode === "mint" ? `nfth:tpl:${x.heroKey}` : `nfth:bt:${x.heroKey}`,
    },
  ]);
  if (mode === "mint") rows.push([{ t: "⌨️ DIGITAR HERO KEY", d: "nfth:ask:nfthmint" }]);
  rows.push(nav("nfth:hub"));
  return edit(
    ctx,
    mode === "mint"
      ? "➕ <b>CRIAR UNIDADE NFT</b>\nEscolha o herói exclusivo que receberá novos seriais."
      : "⚙️ <b>EDITOR DE POWER</b>\nEscolha o herói NFT para ajustar atributos, crescimento e nível máximo.",
    kb(rows),
  );
}

async function nfthTemplateCard(ctx: Ctx, heroKey: string) {
  const d = (await rpc("admin_nft_hero_overview", { p_admin_id: ctx.adminId })) as any;
  const x = (d.templates ?? []).find((r: any) => r.heroKey === heroKey);
  if (!x) return send(ctx, "⚠️ Herói NFT não encontrado.", kb([nav("nfth:hub")]));
  return edit(
    ctx,
    `⚔️ <b>${esc(x.name)}</b>\n<code>${esc(x.heroKey)}</code> · ${esc(String(x.class ?? "").toUpperCase())}\nATK ${fmt(x.baseAtk)} · HP ${fmt(x.baseHp)} · DEF ${fmt(x.baseDef)}\nSPD ${fmt(x.speed)} · CRIT ${x.crit}% · SKILL ${x.skillPower}\nUnidades: ${fmt(x.minted)} · 🟢 ${fmt(x.available)} · 👤 ${fmt(x.owned)}\n\nCada unidade recebe serial único e instância exclusiva.`,
    kb([
      [
        { t: "➕ 1 UNIDADE", d: `nfth:mint:${heroKey}:1` },
        { t: "➕ 5", d: `nfth:mint:${heroKey}:5` },
        { t: "➕ 10", d: `nfth:mint:${heroKey}:10` },
      ],
      [
        { t: "📋 UNIDADES DISPONÍVEIS", d: `nfth:avail:${heroKey}` },
        { t: "⚙️ POWER", d: `nfth:bt:${heroKey}` },
      ],
      nav("nfth:new"),
    ]),
  );
}

async function nfthBalanceCard(ctx: Ctx, heroKey: string, useEdit = true) {
  const d = (await rpc("admin_nft_hero_overview", { p_admin_id: ctx.adminId })) as any;
  const x = (d.templates ?? []).find((r: any) => r.heroKey === heroKey);
  if (!x) return send(ctx, "⚠️ Herói NFT não encontrado.", kb([nav("nfth:hub")]));
  const text = [
    `⚙️ <b>POWER · ${esc(x.name)}</b>`,
    `<code>${esc(x.heroKey)}</code> · ${esc(String(x.class ?? "").toUpperCase())}`,
    "",
    `⚔️ ATK <b>${fmt(x.baseAtk)}</b> · ❤️ HP <b>${fmt(x.baseHp)}</b>`,
    `🛡 DEF <b>${fmt(x.baseDef)}</b> · 💨 SPEED <b>${fmt(x.speed)}</b>`,
    `🎯 CRIT <b>${x.crit}%</b> · ✨ SKILL <b>${x.skillPower}</b>`,
    `📈 CRESCIMENTO <b>${x.growth}x</b> · 🔝 NÍVEL MÁX <b>${fmt(x.maxLevel)}</b>`,
    "",
    "Alterações valem para novas unidades e recalculam os stats das já entregues.",
  ].join("\n");
  const rows: any[] = [];
  for (let i = 0; i < NFTH_FIELDS.length; i += 2) {
    rows.push(NFTH_FIELDS.slice(i, i + 2).map((f) => ({ t: f.label, d: `nfth:set:${heroKey}:${f.k}` })));
  }
  rows.push([{ t: "📋 UNIDADES", d: `nfth:avail:${heroKey}` }]);
  rows.push(nav("nfth:bal"));
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function nfthMint(ctx: Ctx, heroKey: string, qty: number) {
  const r = (await rpc("admin_nft_hero_create", {
    p_admin_id: ctx.adminId,
    p_hero_key: heroKey,
    p_quantity: qty,
  })) as any;
  const created = (r.created ?? []) as any[];
  await send(
    ctx,
    `✅ <b>${fmt(created.length)}</b> unidade(s) de <b>${esc(r.hero)}</b> criada(s).\n${created.map((c) => `• ${nftSerial(c.serial)} <code>${esc(c.instance)}</code>`).join("\n")}`,
  );
  return nfthTemplateCard({ ...ctx, messageId: undefined }, r.heroKey ?? heroKey);
}

async function nfthAvailable(ctx: Ctx, heroKey: string | null, ref?: string) {
  const units = (await rpc("admin_nft_hero_available", {
    p_admin_id: ctx.adminId,
    p_hero_key: heroKey,
    p_limit: 30,
  })) as any[];
  if (!units.length)
    return send(
      ctx,
      "⚠️ Nenhuma unidade NFT disponível. Crie novas unidades primeiro.",
      kb([[{ t: "➕ CRIAR UNIDADE", d: "nfth:new" }], nav("nfth:hub")]),
    );
  const rows = units.map((u) => [
    { t: `${u.hero} ${nftSerial(u.serial)}`, d: ref ? `nfth:deliver:${u.id}:${ref}` : `nfth:unit:${u.id}` },
  ]);
  rows.push(nav("nfth:hub"));
  const head = ref
    ? `🎁 <b>ENTREGAR HERÓI NFT</b>\nJogador: <code>${esc(ref)}</code>\nEscolha a unidade única:`
    : "🟢 <b>UNIDADES DISPONÍVEIS</b>";
  return send(ctx, head, kb(rows));
}

async function nfthUnitCard(ctx: Ctx, id: string, useEdit = true) {
  const rows = (await rpc("admin_nft_hero_search", { p_admin_id: ctx.adminId, p_query: id })) as any[];
  const u = rows[0];
  if (!u) return send(ctx, "⚠️ Unidade NFT não encontrada.", kb([nav("nfth:hub")]));
  const owner = u.owner ? `${esc(u.owner.name)} · <code>${u.owner.telegramId}</code>` : "—";
  const text = `⚔️ <b>${esc(u.hero)}</b> ${nftSerial(u.serial)}\nInstância <code>${esc(u.instance)}</code>\nStatus: <b>${NFT_STATUS_LABEL[u.status] ?? esc(u.status)}</b>\nNível ${fmt(u.level)} · ⚔️ ${fmt(u.atk)} · ❤️ ${fmt(u.hp)} · 💪 ${fmt(u.power)}\nDono: ${owner}\n<code>${esc(u.id)}</code>`;
  const buttons =
    u.status === "OWNED"
      ? [[{ t: "↩️ REVOGAR", d: `nfth:rev:${u.id}` }], nav("nfth:hub")]
      : [[{ t: "🎁 ENTREGAR", d: "nfth:ask:nfthgive" }], nav("nfth:hub")];
  return useEdit ? edit(ctx, text, kb(buttons)) : send(ctx, text, kb(buttons));
}

async function nfthRegistry(ctx: Ctx, offset: number, ownedOnly = false) {
  const d = (await rpc("admin_nft_hero_registry", { p_admin_id: ctx.adminId, p_limit: 15, p_offset: offset })) as any;
  const units = ((d.units ?? []) as any[]).filter((u) => !ownedOnly || u.status === "OWNED");
  const lines =
    units
      .map(
        (u) =>
          `• ${esc(u.hero)} ${nftSerial(u.serial)} — ${NFT_STATUS_LABEL[u.status] ?? esc(u.status)}${u.owner ? ` · ${esc(u.owner.name)}` : ""}`,
      )
      .join("\n") || "sem unidades nesta página";
  const rows = units.slice(0, 10).map((u) => [
    {
      t: `${u.hero} ${nftSerial(u.serial)}${u.status === "OWNED" ? " 👤" : ""}`,
      d: ownedOnly ? `nfth:rev:${u.id}` : `nfth:unit:${u.id}`,
    },
  ]);
  const pager: any[] = [];
  if (offset > 0)
    pager.push({ t: "⬅️ Anterior", d: `nfth:${ownedOnly ? "revlist" : "list"}:${Math.max(0, offset - 15)}` });
  if (offset + 15 < Number(d.total ?? 0))
    pager.push({ t: "Próxima ➡️", d: `nfth:${ownedOnly ? "revlist" : "list"}:${offset + 15}` });
  if (pager.length) rows.push(pager);
  rows.push(nav("nfth:hub"));
  return edit(
    ctx,
    `${ownedOnly ? "↩️ <b>REVOGAR HERÓI NFT</b>\nEscolha a unidade entregue:" : `📋 <b>REGISTRO NFT HEROES</b> (${fmt(d.total)})`}\n${lines}`,
    kb(rows),
  );
}

async function nfthCallback(ctx: Ctx, rest: string[]) {
  const [sub, a, b] = rest;
  switch (sub) {
    case "ask":
      return ask(ctx, a, PROMPTS[a] ?? "Envie o valor.");
    case "new":
      return nfthTemplateMenu(ctx, "mint");
    case "bal":
      return nfthTemplateMenu(ctx, "bal");
    case "bt":
      return nfthBalanceCard(ctx, a);
    case "tpl":
      return nfthTemplateCard(ctx, a);
    case "mint":
      return nfthMint(ctx, a, Number(b || 1));
    case "avail":
      return nfthAvailable(ctx, a || null);
    case "unit":
      return nfthUnitCard(ctx, a);
    case "list":
      return nfthRegistry(ctx, Number(a || 0));
    case "revlist":
      return nfthRegistry(ctx, Number(a || 0), true);
    case "set": {
      const f = NFTH_FIELDS.find((x) => x.k === b);
      if (!f) return nfthBalanceCard(ctx, a);
      return ask(ctx, `nfthstat|${a}|${b}`, `⚙️ <b>${f.label}</b> — <code>${esc(a)}</code>\n${PROMPTS.nfthstat}`);
    }
    case "rev":
      return send(
        ctx,
        "⚠️ Confirmar a <b>revogação</b>? O herói sai da coleção do jogador e a unidade volta ao registro como disponível.",
        kb([
          [
            { t: "✅ CONFIRMAR", d: `nfth:revoke:${a}` },
            { t: "❌ Cancelar", d: "nfth:hub" },
          ],
        ]),
      );
    case "revoke": {
      const r = (await rpc("admin_nft_hero_revoke", {
        p_admin_id: ctx.adminId,
        p_nft_id: a,
        p_reason: "revogado pelo painel admin",
      })) as any;
      await send(ctx, `↩️ <b>${esc(r.hero)}</b> ${nftSerial(r.serial)} revogado.\n<code>${esc(r.instance)}</code>`);
      return nfthHub({ ...ctx, messageId: undefined }, false);
    }
    case "deliver": {
      const r = (await rpc("admin_nft_hero_give", {
        p_admin_id: ctx.adminId,
        p_ref: b,
        p_nft_id: a,
        p_reason: "entrega NFT pelo painel admin",
      })) as any;
      await send(
        ctx,
        `⚔️ <b>${esc(r.hero)}</b> ${nftSerial(r.serial)} entregue a <b>${esc(r.playerName)}</b> (<code>${r.telegramId}</code>).\nInstância <code>${esc(r.instance)}</code>\n⚔️ ${fmt(r.atk)} · ❤️ ${fmt(r.hp)} · 💪 ${fmt(r.power)}`,
      );
      return nfthHub({ ...ctx, messageId: undefined }, false);
    }
    case "stats": {
      const s = (await rpc("admin_nft_hero_stats", { p_admin_id: ctx.adminId })) as any;
      const lines =
        ((s.byHero ?? []) as any[])
          .map((x) => `• ${esc(x.hero)} — 👤 ${fmt(x.owned)} · média 💪 ${fmt(x.avgPower)} · topo ${fmt(x.topPower)}`)
          .join("\n") || "sem unidades entregues";
      return edit(
        ctx,
        `📊 <b>NFT HEROES · BALANCEAMENTO</b>\nPower médio ANCESTRAL: <b>${fmt(s.ancestralAvgPower)}</b>\nPower médio NFT: <b>${fmt(s.nftAvgPower)}</b>\nDonos únicos: <b>${fmt(s.nftOwners)}</b>\n\n${lines}`,
        kb([nav("nfth:hub")]),
      );
    }
    case "hist": {
      const rows = (await rpc("admin_nft_hero_history", { p_admin_id: ctx.adminId, p_limit: 20 })) as any[];
      const lines =
        rows
          .map(
            (h) =>
              `• ${String(h.createdAt).slice(0, 16).replace("T", " ")} · <b>${esc(h.action)}</b> ${esc(h.hero)} <code>${esc(h.instance)}</code>${h.to ? ` → ${esc(h.to)}` : ""}${h.from ? ` (de ${esc(h.from)})` : ""}`,
          )
          .join("\n") || "sem histórico";
      return edit(ctx, `📜 <b>HISTÓRICO NFT HEROES</b>\n${lines}`, kb([nav("nfth:hub")]));
    }
    default:
      return nfthHub(ctx);
  }
}

async function nfthPrompt(ctx: Ctx, key: string, args: string[], text: string) {
  switch (key) {
    case "nfthgive": {
      const ref = text.split(/\s+/)[0];
      if (!ref) throw new Error("KEEP_SESSION::⚠️ Envie o Telegram ID, @usuário ou nome do jogador.");
      await clearSession(ctx);
      return nfthAvailable({ ...ctx, messageId: undefined }, null, ref);
    }
    case "nfthmint": {
      const [heroKey, qty] = text.split(/\s+/);
      if (!heroKey)
        throw new Error("KEEP_SESSION::⚠️ Envie <code>hero_key quantidade</code>. Ex.: <code>kaelion 3</code>");
      await clearSession(ctx);
      return nfthMint({ ...ctx, messageId: undefined }, heroKey, Number(qty || 1));
    }
    case "nfthstat": {
      const [heroKey, fieldKey] = args;
      const f = NFTH_FIELDS.find((x) => x.k === fieldKey);
      if (!heroKey || !f) {
        await clearSession(ctx);
        return nfthHub({ ...ctx, messageId: undefined }, false);
      }
      const value = Number(text.replace(",", ".").replace(/[^\d.\-]/g, ""));
      if (!Number.isFinite(value) || value <= 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número válido maior que zero.");
      await rpc("admin_nft_hero_set_stats", {
        p_admin_id: ctx.adminId,
        p_hero_key: heroKey,
        p_patch: { [f.col]: f.k === "maxlvl" ? Math.round(value) : value },
        p_reason: "ajuste de power pelo bot admin",
      });
      await clearSession(ctx);
      await send(ctx, `✅ ${f.label} de <code>${esc(heroKey)}</code> atualizado para <b>${text.trim()}</b>.`);
      return nfthBalanceCard({ ...ctx, messageId: undefined }, heroKey, false);
    }
    case "nfthsearch": {
      const rows = (await rpc("admin_nft_hero_search", { p_admin_id: ctx.adminId, p_query: text })) as any[];
      await clearSession(ctx);
      if (!rows.length) return send(ctx, "🔎 Nenhum herói NFT encontrado.", kb([nav("nfth:hub")]));
      const buttons = rows
        .slice(0, 12)
        .map((u) => [
          { t: `${u.hero} ${nftSerial(u.serial)}${u.owner ? ` · ${u.owner.name}` : ""}`, d: `nfth:unit:${u.id}` },
        ]);
      buttons.push(nav("nfth:hub"));
      return send(ctx, `🔎 <b>${fmt(rows.length)}</b> unidade(s) encontrada(s).`, kb(buttons));
    }
    default:
      return nfthHub({ ...ctx, messageId: undefined }, false);
  }
}

/** Roster editing of a single Global Boss template (HP, reward, duration, name, lore). */
async function gbtPrompt(ctx: Ctx, key: string, code: string, text: string) {
  if (!code) throw new Error("⚠️ Chefe não identificado. Abra novamente o ROSTER.");
  const numeric = parseAmount(text);
  const call = (field: string, value: number | null, txt: string | null) =>
    rpc("admin_global_boss_template_set", {
      p_admin_id: ctx.adminId,
      p_code: code,
      p_field: field,
      p_value: value,
      p_text: txt,
      p_reason: "roster global boss",
    }) as Promise<any>;

  if (key === "gbthp") {
    if (!Number.isFinite(numeric) || numeric < 1)
      throw new Error("KEEP_SESSION::⚠️ Envie o HP total. Ex.: <code>2500000</code>");
    await call("hp", Math.round(numeric), null);
  } else if (key === "gbtrw") {
    if (!Number.isFinite(numeric) || numeric < 0)
      throw new Error("KEEP_SESSION::⚠️ Envie o prêmio em FC. Ex.: <code>600000</code>");
    await call("reward", Math.round(numeric), null);
  } else if (key === "gbtdur") {
    if (!Number.isFinite(numeric) || numeric < 1 || numeric > 168)
      throw new Error("KEEP_SESSION::⚠️ Envie a duração em horas (1 a 168). Ex.: <code>24</code>");
    await call("duration", Math.round(numeric * 3600), null);
  } else if (key === "gbtname") {
    if (!text) throw new Error("KEEP_SESSION::⚠️ Envie o novo nome do chefe.");
    await call("name", null, text.slice(0, 60));
  } else if (key === "gbtsub") {
    await call("subtitle", null, text.slice(0, 120));
  } else {
    throw new Error("⚠️ Ação inválida.");
  }
  await clearSession(ctx);
  await send(ctx, "✅ Chefe global atualizado.");
  return bossTemplateMenu({ ...ctx, messageId: undefined }, code);
}

async function handlePrompt(ctx: Ctx, cmd: string, input: string) {
  const [key, ...args] = cmd.split("|");
  const text = input.trim();

  if (key.startsWith("gift")) return giftPrompt(ctx, key, args[0] ?? "", text);
  if (key.startsWith("cl")) return clansPrompt(ctx, key, args[0] ?? "", text);
  if (key.startsWith("sp") && ["spname", "spdays", "spreward", "spratet", "spratef"].includes(key))
    return spendPrompt(ctx, key, text);
  if (key.startsWith("cb")) return cbPrompt(ctx, key, text, args);
  if (key.startsWith("pt") && key !== "ptr") return partnersPrompt(ctx, key, args, text);
  if (key === "prsearch") return prSearch(ctx, text);
  if (key.startsWith("af")) return afPrompt(ctx, key, text);
  if (key.startsWith("arpts_") || key.startsWith("arxp_") || key.startsWith("arcap_")) return arPrompt(ctx, key, text);
  if (key.startsWith("gw")) return gwPrompt(ctx, key, text);
  if (key.startsWith("xe")) return xePrompt(ctx, key, text);
  if (key.startsWith("fg")) return fgPrompt(ctx, key, text);

  if (key === "plset" || key === "plfind") return plPrompt(ctx, key, args, text);
  if (key === "tpset" || key === "tpskill") return tpPrompt(ctx, key, text);
  if (key === "cwset" || key === "cwseason") return cwPrompt(ctx, key, text);
  if (key === "depmin") {
    const value = Number(text.replace(",", ".").replace(/[^\d.]/g, ""));
    if (!Number.isFinite(value) || value <= 0 || value > 1000)
      throw new Error("KEEP_SESSION::⚠️ Envie um valor em TON entre 0 e 1000 (ex.: <code>0.1</code>).");
    await rpc("admin_deposit_settings", { p_admin_id: ctx.adminId, p_key: "min_direct_ton_deposit", p_value: value });
    await clearSession(ctx);
    await send(ctx, `✅ Depósito direto mínimo: <b>${value} TON</b>.`);
    return depositSettingsHub({ ...ctx, messageId: undefined });
  }
  if (key.startsWith("gbt")) return gbtPrompt(ctx, key, args[0] ?? "", text);
  if (key.startsWith("nm")) return nmPrompt(ctx, key, text);
  if (key.startsWith("tsk")) return tsPrompt(ctx, key, text);
  if (key.startsWith("stk")) return stakingPrompt(ctx, key, text);
  if (key.startsWith("mu")) return muPrompt(ctx, key, text);
  if (key.startsWith("po")) return poPrompt(ctx, key, text);
  if (key.startsWith("v2")) return vv2Prompt(ctx, key, text);
  if (key.startsWith("vv")) return vvPrompt(ctx, key, text);
  if (key.startsWith("rl")) return rlPrompt(ctx, key, args, text);
  if (key.startsWith("fh")) return fhPrompt(ctx, key, text);

  if (key.startsWith("fp")) return fpPrompt(ctx, key, text);

  if (key.startsWith("myth")) return mythPrompt(ctx, key, text);
  if (key.startsWith("ms")) return salePrompt(ctx, key, text);
  if (key.startsWith("hm")) return hmPrompt(ctx, key, text);
  if (key.startsWith("rm")) return rmPrompt(ctx, key, text);
  if (key.startsWith("tm")) return tmPrompt(ctx, key, text);

  if (key.startsWith("nprc")) return nftPricePrompt(ctx, key, args, text);
  if (key === "hpset" || key === "hpcurve" || key === "hpquest") return heroProgressionPrompt(ctx, key, args, text);
  if (key.startsWith("neq")) return nftEquipPrompt(ctx, key, args, text);
  if (key.startsWith("np")) return nftPoolPrompt(ctx, key, args, text);

  if (key.startsWith("nfth")) return nfthPrompt(ctx, key, args, text);
  if (key.startsWith("nft")) return nftPrompt(ctx, key, args, text);
  if (key === "wlhot") {
    const address = text.trim();
    const friendly = toFriendlyTonAddress(address);
    if (!friendly || !/^[A-Za-z0-9_-]{48}$/.test(friendly)) {
      throw new Error(
        "KEEP_SESSION::⚠️ Endereço TON inválido. Envie o endereço da carteira (formato <code>UQ...</code>/<code>EQ...</code> ou <code>0:...</code>).",
      );
    }
    await wlRpc(ctx, "set_hot_wallet", { address: friendly });
    await clearSession(ctx);
    await send(
      ctx,
      `🔥 <b>HOT WALLET ATUALIZADA</b>\n🏦 <code>${esc(friendly)}</code>\nVale imediatamente para novos depósitos.`,
    );
    return hotWalletHub({ ...ctx, messageId: undefined }, false);
  }
  if (key === "wlmin") {
    const min = parseAmount(text);
    if (!Number.isFinite(min) || min <= 0 || min > 100_000)
      throw new Error("KEEP_SESSION::⚠️ Envie um valor em TON entre 0 e 100000 (ex.: <code>1</code>).");
    await wlRpc(ctx, "set_min_withdraw", { value: min });
    await clearSession(ctx);
    await send(ctx, `⬇️ <b>SAQUE MÍNIMO</b> atualizado para <b>${fmt(min)} TON</b>.`);
    return hotWalletHub({ ...ctx, messageId: undefined }, false);
  }
  // 💎 AJUSTAR TON — internal/withdrawable balance (game_players.ton_balance) only.
  if (key === "tonadj") {
    const tg = text.replace(/\D/g, "");
    if (!tg)
      throw new Error("KEEP_SESSION::⚠️ Envie apenas o <b>Telegram ID</b> numérico. Ex.: <code>8118569391</code>");
    const r = (await rpc("admin_ton_lookup", { p_admin_id: ctx.adminId, p_telegram_id: Number(tg) })) as any;
    if (!r?.ok) throw new Error("KEEP_SESSION::❌ Jogador não encontrado.");
    await clearSession(ctx);
    return send(
      ctx,
      [
        "👤 <b>Jogador</b>",
        `Nome: <b>${esc(r.name)}</b>`,
        `Telegram ID: <code>${esc(String(r.telegramId))}</code>`,
        "",
        `💎 <b>TON atual:</b> ${fmtTon(r.balanceTon)} TON`,
        "",
        "Escolha a operação:",
      ].join("\n"),
      kb([
        [
          { t: "➕ ADICIONAR TON", d: `tonop:add:${tg}` },
          { t: "➖ REMOVER TON", d: `tonop:remove:${tg}` },
        ],
        [{ t: "❌ CANCELAR", d: "cancel" }],
      ]),
    );
  }
  if (key === "tonamt") {
    const [mode, tg] = args;
    const amount = parseAmount(text);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 1_000_000) {
      throw new Error("KEEP_SESSION::⚠️ Valor inválido. Envie um número maior que zero (ex.: <code>2.5</code>).");
    }
    const r = (await rpc("admin_ton_lookup", { p_admin_id: ctx.adminId, p_telegram_id: Number(tg) })) as any;
    if (!r?.ok) {
      await clearSession(ctx);
      return send(ctx, "❌ Jogador não encontrado.", kb([[{ t: "💳 CARTEIRA", d: "m:wallet" }], nav()]));
    }
    const current = Number(r.balanceTon);
    if (mode === "remove" && current < amount) {
      await clearSession(ctx);
      return send(
        ctx,
        [
          "❌ <b>Saldo insuficiente.</b>",
          `Saldo atual: ${fmtTon(current)} TON`,
          `Tentativa de remoção: ${fmtTon(amount)} TON`,
          "",
          "Nenhuma alteração foi feita.",
        ].join("\n"),
        kb([[{ t: "💎 AJUSTAR TON", d: "ask:tonadj" }], [{ t: "💳 CARTEIRA", d: "m:wallet" }], nav()]),
      );
    }
    return ask(
      ctx,
      `tonreason|${mode}|${tg}|${amount}`,
      `📝 <b>MOTIVO OBRIGATÓRIO</b>\nDescreva o motivo do ajuste.\nEx.: <code>Premiação PvP Top 5</code>`,
    );
  }
  if (key === "tonreason") {
    const [mode, tg, rawAmount] = args;
    if (text.length < 3) throw new Error("KEEP_SESSION::⚠️ Descreva o motivo com pelo menos 3 caracteres.");
    const amount = Number(rawAmount);
    const r = (await rpc("admin_ton_lookup", { p_admin_id: ctx.adminId, p_telegram_id: Number(tg) })) as any;
    if (!r?.ok) {
      await clearSession(ctx);
      return send(ctx, "❌ Jogador não encontrado.", kb([[{ t: "💳 CARTEIRA", d: "m:wallet" }], nav()]));
    }
    const current = Number(r.balanceTon);
    const next = mode === "add" ? current + amount : current - amount;
    if (next < 0) {
      await clearSession(ctx);
      return send(
        ctx,
        `❌ <b>Saldo insuficiente.</b>\nSaldo atual: ${fmtTon(current)} TON\nTentativa de remoção: ${fmtTon(amount)} TON`,
        kb([[{ t: "💎 AJUSTAR TON", d: "ask:tonadj" }], nav("m:wallet")]),
      );
    }
    const reason = text.slice(0, 300);
    const key2 = crypto.randomUUID();
    // The pending adjustment (with reason + idempotency key) lives in the session until CONFIRMAR.
    await setSession(ctx, "tonconfirm", "awaiting_confirm", { mode, tg, amount, reason, key: key2 });
    return send(
      ctx,
      [
        "⚠️ <b>CONFIRMAR AJUSTE TON</b>",
        "",
        `Jogador: <b>${esc(r.name)}</b>`,
        `Telegram ID: <code>${esc(String(tg))}</code>`,
        `Operação: ${mode === "add" ? "➕ ADICIONAR" : "➖ REMOVER"}`,
        `Valor: <b>${fmtTon(amount)} TON</b>`,
        `Saldo atual: ${fmtTon(current)} TON`,
        `Novo saldo: <b>${fmtTon(next)} TON</b>`,
        `Motivo: ${esc(reason)}`,
      ].join("\n"),
      kb([
        [
          { t: "✅ CONFIRMAR", d: `tongo:${key2}` },
          { t: "❌ CANCELAR", d: "cancel" },
        ],
      ]),
    );
  }
  if (key === "prreason") {
    if (text.length < 3) throw new Error("KEEP_SESSION::⚠️ Descreva o motivo com pelo menos 3 caracteres.");
    return prConfirm(ctx, args[0] ?? "", args[1] ?? "", text.slice(0, 300));
  }

  switch (key) {
    // ---- 🛡 market security prompts
    case "mktrade": {
      return mkTradeCard(ctx, text.slice(0, 40), false);
    }
    case "mkhist":
      return mkUserHistory(ctx, text.slice(0, 60));
    case "mkrestrict": {
      const [ref, rawHours] = text.split(/\s+/);
      const hours = rawHours === undefined ? 24 : Math.round(parseAmount(rawHours));
      if (!ref || !Number.isFinite(hours) || hours < 0 || hours > 8760) {
        throw new Error(
          "KEEP_SESSION::⚠️ Envie <code>ID_ou_@usuario horas</code> (ex.: <code>8118569391 24</code>). Use <code>0</code> horas para liberar.",
        );
      }
      const r = (await rpc("admin_market_restrict_user", {
        p_admin_id: ctx.adminId,
        p_query: ref,
        p_hours: hours,
      })) as any;
      if (!r?.found) throw new Error("KEEP_SESSION::⚠️ Jogador não encontrado. Envie o ID do Telegram ou @usuario.");
      return send(
        ctx,
        hours <= 0
          ? `✅ <b>${esc(r.player)}</b> liberado no mercado.`
          : `⛔️ <b>${esc(r.player)}</b> restrito por <b>${fmt(hours)}h</b> (não pode anunciar nem comprar).`,
        kb([[{ t: "🛡 MARKET SECURITY", d: "mk:sec" }], nav()]),
      );
    }
    case "mkrange": {
      const parts = text.split(/\s+/).filter(Boolean);
      const [kind, rarity] = parts;
      const min = Math.round(parseAmount(parts[2] ?? ""));
      const max = Math.round(parseAmount(parts[3] ?? ""));
      const rec = parts[4] === undefined ? null : Math.round(parseAmount(parts[4]));
      if (
        !["hero", "pet", "item"].includes(String(kind).toLowerCase()) ||
        !rarity ||
        !Number.isFinite(min) ||
        !Number.isFinite(max) ||
        max <= min
      ) {
        throw new Error(
          "KEEP_SESSION::⚠️ Formato: <code>tipo raridade min max [recomendado]</code>\nEx.: <code>hero epic 50000 400000 120000</code>\nTipos: hero, pet, item. Use <code>default</code> como raridade curinga.",
        );
      }
      const r = (await rpc("admin_market_set_price_range", {
        p_admin_id: ctx.adminId,
        p_item_type: String(kind).toLowerCase(),
        p_rarity: String(rarity).toLowerCase(),
        p_min: min,
        p_max: max,
        p_recommended: rec,
      })) as any;
      const range = r?.range || {};
      return send(
        ctx,
        `✅ <b>FAIXA ATUALIZADA</b>\n${esc(String(kind).toLowerCase())} · ${esc(String(rarity).toLowerCase())}\n${fmt(range.min ?? min)} a ${fmt(range.max ?? max)} FC · recomendado ${fmt(range.recommended ?? rec ?? 0)} FC`,
        kb([[{ t: "🏷 FAIXAS DE PREÇO", d: "mk:ranges" }], nav("mk:sec")]),
      );
    }
    case "mksettle": {
      const hours = Math.round(parseAmount(text));
      if (!Number.isFinite(hours) || hours < 0 || hours > 720)
        throw new Error("KEEP_SESSION::⚠️ Envie as horas de retenção (0 a 720). Ex.: <code>72</code>.");
      await mkSecSet(ctx, "market_settlement_hours", hours);
      return send(
        ctx,
        `✅ Retenção de pagamento agora é <b>${fmt(hours)}h</b>.`,
        kb([[{ t: "🛡 MARKET SECURITY", d: "mk:sec" }], nav()]),
      );
    }
    case "mkreq": {
      const [d1, d2, d3] = text.split(/\s+/).map((v) => Math.round(parseAmount(v)));
      if (![d1, d2, d3].every((v) => Number.isFinite(v) && v >= 0)) {
        throw new Error("KEEP_SESSION::⚠️ Formato: <code>diasConta diasAtivo heróis</code> (ex.: <code>7 3 5</code>).");
      }
      await mkSecSet(ctx, "market_sell_requirements", { accountDays: d1, activeDays: d2, heroes: d3 });
      return send(
        ctx,
        `✅ Requisitos para vender: conta <b>${fmt(d1)}d</b> · ativo <b>${fmt(d2)}d</b> · heróis <b>${fmt(d3)}</b>.`,
        kb([[{ t: "🛡 MARKET SECURITY", d: "mk:sec" }], nav()]),
      );
    }
    case "mkpair": {
      const [trades, fcPerDay] = text.split(/\s+/).map((v) => Math.round(parseAmount(v)));
      if (![trades, fcPerDay].every((v) => Number.isFinite(v) && v >= 0)) {
        throw new Error("KEEP_SESSION::⚠️ Formato: <code>tradesPorDia fcPorDia</code> (ex.: <code>3 2000000</code>).");
      }
      await mkSecSet(ctx, "market_pair_limits", { tradesPerDay: trades, fcPerDay });
      return send(
        ctx,
        `✅ Limite por par/24h: <b>${fmt(trades)}</b> trades · <b>${fmt(fcPerDay)} FC</b>.`,
        kb([[{ t: "🛡 MARKET SECURITY", d: "mk:sec" }], nav()]),
      );
    }
    case "mkvel": {
      const [p5, p1h, p24, cd] = text.split(/\s+/).map((v) => Math.round(parseAmount(v)));
      if (![p5, p1h, p24, cd].every((v) => Number.isFinite(v) && v >= 0)) {
        throw new Error(
          "KEEP_SESSION::⚠️ Formato: <code>por5min por1h por24h cooldownMin</code> (ex.: <code>5 15 40 360</code>).",
        );
      }
      await mkSecSet(ctx, "market_velocity", { per5m: p5, per1h: p1h, per24h: p24, cooldownMinutes: cd });
      return send(
        ctx,
        `✅ Velocidade: 5m <b>${fmt(p5)}</b> · 1h <b>${fmt(p1h)}</b> · 24h <b>${fmt(p24)}</b> · cooldown <b>${fmt(cd)}min</b>.`,
        kb([[{ t: "🛡 MARKET SECURITY", d: "mk:sec" }], nav()]),
      );
    }
    case "mkdyn": {
      const [minPercent, maxPercent, minSamples, days] = text.split(/\s+/).map((v) => Math.round(parseAmount(v)));
      if (
        ![minPercent, maxPercent, minSamples, days].every((v) => Number.isFinite(v) && v >= 0) ||
        maxPercent <= minPercent
      ) {
        throw new Error(
          "KEEP_SESSION::⚠️ Formato: <code>min% max% minAmostras dias</code> (ex.: <code>50 200 5 30</code>).",
        );
      }
      await mkSecSet(ctx, "market_dynamic_range", { minPercent, maxPercent, minSamples, days });
      return send(
        ctx,
        `✅ Faixa dinâmica: <b>${fmt(minPercent)}%</b>–<b>${fmt(maxPercent)}%</b> da mediana · min amostras <b>${fmt(minSamples)}</b> · janela <b>${fmt(days)}d</b>.`,
        kb([[{ t: "🛡 MARKET SECURITY", d: "mk:sec" }], nav()]),
      );
    }
    // ---- 🔨 auction prompts (internal TON only; the RPC validates every bound)
    case "aucfee": {
      const value = parseAmount(text.replace("%", ""));
      if (!Number.isFinite(value) || value < 5 || value > 10)
        throw new Error("KEEP_SESSION::⚠️ Envie uma taxa entre 5 e 10 (ex.: <code>7</code>).");
      const s = (await rpc("admin_auction_set", {
        p_telegram_id: ctx.adminId,
        p_key: "feePercent",
        p_value: value,
      })) as any;
      return send(
        ctx,
        `✅ Taxa do leilão agora é <b>${Number(s.feePercent)}%</b> em TON.`,
        kb([[{ t: "🔨 LEILÃO", d: "auc:hub" }], nav()]),
      );
    }
    case "aucmin": {
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value < 0.01)
        throw new Error("KEEP_SESSION::⚠️ Envie um valor em TON (mínimo <code>0.01</code>).");
      const s = (await rpc("admin_auction_set", {
        p_telegram_id: ctx.adminId,
        p_key: "minStartingBidTon",
        p_value: value,
      })) as any;
      return send(
        ctx,
        `✅ Lance inicial mínimo: <b>${Number(s.minStartingBidTon)} TON</b>.`,
        kb([[{ t: "🔨 LEILÃO", d: "auc:hub" }], nav()]),
      );
    }
    case "aucinc": {
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value < 0.001)
        throw new Error("KEEP_SESSION::⚠️ Envie um valor em TON (mínimo <code>0.001</code>).");
      const s = (await rpc("admin_auction_set", {
        p_telegram_id: ctx.adminId,
        p_key: "minIncrementTon",
        p_value: value,
      })) as any;
      return send(
        ctx,
        `✅ Incremento mínimo por lance: <b>${Number(s.minIncrementTon)} TON</b>.`,
        kb([[{ t: "🔨 LEILÃO", d: "auc:hub" }], nav()]),
      );
    }
    case "aucwin": {
      const value = Math.round(parseAmount(text));
      if (!Number.isFinite(value) || value < 0 || value > 60)
        throw new Error("KEEP_SESSION::⚠️ Envie os minutos da janela (0 a 60).");
      const s = (await rpc("admin_auction_set", {
        p_telegram_id: ctx.adminId,
        p_key: "antiSnipeWindowMinutes",
        p_value: value,
      })) as any;
      return send(
        ctx,
        `✅ Janela anti-snipe: <b>${Number(s.antiSnipeWindowMinutes)} min</b>.`,
        kb([[{ t: "🔨 LEILÃO", d: "auc:hub" }], nav()]),
      );
    }
    case "aucext": {
      const value = Math.round(parseAmount(text));
      if (!Number.isFinite(value) || value < 0 || value > 60)
        throw new Error("KEEP_SESSION::⚠️ Envie os minutos de extensão (0 a 60).");
      const s = (await rpc("admin_auction_set", {
        p_telegram_id: ctx.adminId,
        p_key: "antiSnipeExtensionMinutes",
        p_value: value,
      })) as any;
      return send(
        ctx,
        `✅ Extensão anti-snipe: <b>${Number(s.antiSnipeExtensionMinutes)} min</b>.`,
        kb([[{ t: "🔨 LEILÃO", d: "auc:hub" }], nav()]),
      );
    }
    case "aucdur": {
      const hours = text
        .split(/[^0-9]+/)
        .map((v) => Math.round(Number(v)))
        .filter((v) => Number.isFinite(v) && v > 0 && v <= 168);
      if (hours.length < 1 || hours.length > 6)
        throw new Error(
          "KEEP_SESSION::⚠️ Envie de 1 a 6 durações em horas, separadas por espaço (ex.: <code>6 12 24 48</code>).",
        );
      const s = (await rpc("admin_auction_set", {
        p_telegram_id: ctx.adminId,
        p_key: "durations",
        p_value: hours,
      })) as any;
      return send(
        ctx,
        `✅ Durações disponíveis: <b>${(s.durations || []).join("h · ")}h</b>.`,
        kb([[{ t: "🔨 LEILÃO", d: "auc:hub" }], nav()]),
      );
    }
    // ---- 🛒 marketplace prompts (every rule is enforced inside the RPCs)
    case "mksearch": {
      const rows = (await rpc("admin_market_search", {
        p_admin_id: ctx.adminId,
        p_query: text.slice(0, 60),
        p_limit: 15,
      })) as any[];
      return send(
        ctx,
        `🔍 <b>BUSCA NO MERCADO</b>\n${(rows || []).map(mkLine).join("\n").slice(0, 3500) || "Nenhum anúncio encontrado."}`,
        kb([[{ t: "🛒 MARKETPLACE", d: "m:market" }], nav()]),
      );
    }
    case "mkuser": {
      const d = (await rpc("admin_market_user_listings", { p_admin_id: ctx.adminId, p_ref: text, p_limit: 20 })) as any;
      const who = d.player?.username ? "@" + d.player.username : d.player?.name || d.player?.telegram_id || "—";
      return send(
        ctx,
        `👤 <b>ANÚNCIOS DE ${esc(who)}</b>\n${(d.listings || []).map(mkLine).join("\n").slice(0, 3400) || "Nenhum anúncio."}`,
        kb([[{ t: "🛒 MARKETPLACE", d: "m:market" }], nav()]),
      );
    }
    case "mkfee": {
      const value = parseAmount(text.replace("%", ""));
      if (!Number.isFinite(value) || value < 0 || value > 50)
        throw new Error("KEEP_SESSION::⚠️ Envie uma taxa entre 0 e 50 (ex.: <code>5</code>).");
      const s = (await rpc("admin_market_set_fee", { p_admin_id: ctx.adminId, p_percent: value })) as any;
      return send(
        ctx,
        `✅ Taxa do mercado agora é <b>${Number(s.feePercent)}%</b>.\nA taxa é queimada da economia FC (não vai para a pool TON).`,
        kb([[{ t: "🛒 MARKETPLACE", d: "m:market" }], nav()]),
      );
    }
    case "mklimit": {
      const value = Math.round(parseAmount(text));
      if (!Number.isFinite(value) || value < 1 || value > 200)
        throw new Error("KEEP_SESSION::⚠️ Envie um limite entre 1 e 200.");
      const s = (await rpc("admin_market_set_limit", { p_admin_id: ctx.adminId, p_max_active: value })) as any;
      return send(
        ctx,
        `✅ Limite atualizado: <b>${fmt(s.maxActiveListings)}</b> anúncios ativos por jogador.`,
        kb([[{ t: "🛒 MARKETPLACE", d: "m:market" }], nav()]),
      );
    }
    case "mkmin": {
      const [kind, raw] = text.split(/\s+/);
      const value = Math.round(parseAmount(raw ?? ""));
      if (!["hero", "pet", "item"].includes(String(kind).toLowerCase()) || !Number.isFinite(value) || value < 0) {
        throw new Error("KEEP_SESSION::⚠️ Envie: <code>hero|pet|item valor_fc</code> — ex.: <code>hero 10000</code>");
      }
      const s = (await rpc("admin_market_set_min_price", {
        p_admin_id: ctx.adminId,
        p_item_type: String(kind).toLowerCase(),
        p_value: value,
      })) as any;
      const min = s.minPrice || {};
      return send(
        ctx,
        `✅ Preço mínimo atualizado.\nHerói ${fmt(min.hero ?? 0)} FC · Pet ${fmt(min.pet ?? 0)} FC · Item ${fmt(min.item ?? 0)} FC`,
        kb([[{ t: "🛒 MARKETPLACE", d: "m:market" }], nav()]),
      );
    }
    case "mkcancel": {
      const id = text.trim();
      if (!/^[0-9a-f-]{36}$/i.test(id)) throw new Error("KEEP_SESSION::⚠️ Envie o ID completo do anúncio (UUID).");
      await rpc("admin_market_cancel_listing", {
        p_admin_id: ctx.adminId,
        p_listing_id: id,
        p_reason: "cancelado pelo admin (bot)",
      });
      return send(
        ctx,
        "✅ Anúncio cancelado. O item voltou ao inventário do vendedor e o bloqueio de mercado foi removido.",
        kb([[{ t: "🛒 MARKETPLACE", d: "m:market" }], nav()]),
      );
    }

    case "find":
      return playerSearch(ctx, text, 0);
    case "passuser":
      return passCard(ctx, text);
    case "tree":
      return handleCallback(ctx, `tree:${text}`);
    case "bal": {
      const [cur, mode, user] = args;
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value < 0)
        throw new Error(
          "KEEP_SESSION::⚠️ Valor inválido. Envie um número maior ou igual a 0 (ex.: <code>1000</code> ou <code>20,5</code>).",
        );
      const p = (await rpc("admin_player_detail", { p_admin_id: ctx.adminId, p_ref: user })) as any;
      const current = Number(cur === "ton" ? p.ton_balance : p.forge_coins);
      const next = mode === "add" ? current + value : mode === "remove" ? Math.max(0, current - value) : value;
      const label = cur.toUpperCase();
      return send(
        ctx,
        [
          `💰 <b>${mode === "add" ? "ADD" : mode === "remove" ? "REMOVE" : "SET"} ${label}</b>`,
          `👤 ${esc(p.name)} ${p.username ? "@" + esc(p.username) : ""} · <code>${p.telegram_id}</code>`,
          "",
          `Atual: <b>${fmt(current)} ${label}</b>`,
          `${mode === "set" ? "Definir" : mode === "add" ? "Adicionar" : "Remover"}: <b>${fmt(value)} ${label}</b>`,
          `Novo: <b>${fmt(next)} ${label}</b>`,
        ].join("\n"),
        kb([
          [
            { t: "✅ CONFIRMAR", d: `balgo:${cur}:${mode}:${user}:${value}` },
            { t: "❌ CANCELAR", d: `uf:${user}` },
          ],
        ]),
      );
    }

    case "itemqty": {
      const [user, mode, ...keyParts] = args;
      const key = keyParts.join("|");
      const qty = Math.round(parseAmount(text));
      if (!Number.isFinite(qty) || qty <= 0)
        throw new Error(
          "KEEP_SESSION::⚠️ Quantidade inválida. Envie um número inteiro maior que 0 (ex.: <code>10</code>).",
        );
      const delta = mode === "a" ? qty : -qty;
      try {
        const r = (await rpc("admin_adjust_player_item", {
          p_admin_id: ctx.adminId,
          p_ref: user,
          p_item_key: key,
          p_delta: delta,
          p_reason: "painel admin",
        })) as any;
        await send(
          ctx,
          `✅ <b>SUCESSO</b>\n\nJogador: <code>${esc(user)}</code>\nItem: <b>${esc(r.label)}</b>\n${mode === "a" ? "Adicionado" : "Removido"}: ${fmt(qty)}\nAntes: ${fmt(r.before)} → Agora: <b>${fmt(r.after)}</b>`,
        );
        return userItemsMenu({ ...ctx, messageId: undefined }, user);
      } catch (error) {
        const raw = error instanceof Error ? error.message : String(error);
        const max = raw.match(/insufficient_inventory:(\d+)/)?.[1];
        if (max) throw new Error(`KEEP_SESSION::⚠️ Inventário insuficiente. Máximo removível: <b>${fmt(max)}</b>.`);
        throw error;
      }
    }

    case "stat": {
      const [stat, user] = args;
      const [mode, amount] = text.split(/\s+/);
      const r = await rpc("admin_adjust_pvp_stat", {
        p_admin_id: ctx.adminId,
        p_ref: user,
        p_stat: stat,
        p_mode: mode,
        p_amount: Number(amount),
        p_reason: "ajuste pelo painel",
      });
      return send(
        ctx,
        `✅ ${stat}: ${fmt(r.old_value)} → <b>${fmt(r.new_value)}</b>`,
        kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav()]),
      );
    }
    case "granthero": {
      const parts = text.split(/\s+/);
      const user = args[0] ?? parts.shift()!;
      const r = await rpc("admin_grant_hero", {
        p_admin_id: ctx.adminId,
        p_ref: user,
        p_hero_key: parts[0],
        p_level: Number(parts[1] || 1),
        p_reason: "concedido pelo painel",
      });
      return send(
        ctx,
        `✅ Herói <b>${esc(r.name)}</b> concedido.\n<code>${r.hero_id}</code>`,
        kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav()]),
      );
    }
    case "grantpet": {
      const parts = text.split(/\s+/);
      const user = args[0] ?? parts.shift()!;
      // The pet template owns its rarity, so only slug + level are accepted here.
      let r: any;
      try {
        r = await rpc("admin_grant_pet", {
          p_admin_id: ctx.adminId,
          p_ref: user,
          p_pet_slug: parts[0],
          p_rarity: null,
          p_level: Number(parts[1] || 1),
          p_reason: "concedido pelo painel",
        });
      } catch (grantError) {
        if (String((grantError as Error)?.message ?? "").includes("USE_NFT_FLOW")) {
          return send(
            ctx,
            "⛔ Este pet é <b>NFT EXCLUSIVE</b>. Use o módulo 💎 NFT PETS para entregar (serial único preservado).",
            kb([[{ t: "💎 NFT PETS", d: "nft:hub" }], nav()]),
          );
        }
        throw grantError;
      }
      return send(
        ctx,
        `✅ Pet <b>${esc(r.pet)}</b> (${esc(String(r.rarity).toUpperCase().replace("NFT_EXCLUSIVE", "NFT EXCLUSIVE"))}) concedido.`,
        kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav()]),
      );
    }
    case "rfcommon":
    case "rfuncommon":
    case "rfrare":
    case "rfepic": {
      const source = cmd.slice(2);
      const parts = text
        .replace(/,/g, ".")
        .split(/[\s;]+/)
        .map((v) => Number(v.replace(/[^\d.]/g, "")));
      if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n)) || parts[1] < 0 || parts[1] > 100) {
        return send(
          ctx,
          "⚠️ Envie 3 números: <code>custo_myth chance fragmentos</code>. Ex.: <code>30000 40 40</code>",
          kb([[{ t: "⚗️ RARITY FUSION", d: "rf:home" }], nav()]),
        );
      }
      await rpc("admin_set_rarity_fusion_tier", {
        p_admin_id: ctx.adminId,
        p_source: source,
        p_cost: parts[0],
        p_chance: parts[1],
        p_fragments: Math.round(parts[2]),
      });
      await send(
        ctx,
        `✅ ${RF_LABEL[source]} atualizado — ${fmt(parts[0])} MYTH · ${pct(parts[1])}% · ${fmt(Math.round(parts[2]))} frag.`,
      );
      return rarityFusionView(ctx);
    }
    case "rfpool": {
      const [key, mode] = text.trim().split(/[\s;]+/);
      if (!key || !["on", "off"].includes(String(mode || "").toLowerCase())) {
        return send(
          ctx,
          "⚠️ Envie: <code>hero_key on|off</code>",
          kb([[{ t: "⚗️ RARITY FUSION", d: "rf:home" }], nav()]),
        );
      }
      const r = (await rpc("admin_set_hero_fusion_pool", {
        p_admin_id: ctx.adminId,
        p_hero_key: key,
        p_enabled: String(mode).toLowerCase() === "on",
      })) as any;
      return send(
        ctx,
        `${r.enabled ? "✅" : "🚫"} <b>${esc(r.name)}</b> (${esc(r.rarity)}) ${r.enabled ? "entra" : "não entra"} no sorteio da Rarity Fusion.`,
        kb([[{ t: "⚗️ RARITY FUSION", d: "rf:home" }], nav()]),
      );
    }
    // ---- 🎉 special events prompts
    case "evcreate": {
      const parts = text.split("|").map((v) => v.trim());
      if (parts.length < 3)
        return send(
          ctx,
          "⚠️ Envie: <code>nome | prêmio TON | dias | (opcional) YYYY-MM-DD HH:MM</code>",
          kb([nav("m:events")]),
        );
      const payload: Record<string, unknown> = {
        name: parts[0],
        prizeTon: Number(parts[1].replace(",", ".")),
        days: Number(parts[2].replace(",", ".")),
        type: "referral_ranking",
      };
      if (parts[3]) payload.startsAt = parts[3].replace(" ", "T");
      const r = await evRpc(ctx, "create", null, payload);
      await send(ctx, `✅ Evento criado: <b>${esc(r.event?.name ?? "")}</b> — ${fmt(r.event?.prizePoolTon)} TON.`);
      return eventsHub(ctx, r.event?.eventKey ?? null, false);
    }
    case "evprize": {
      const value = Number(text.replace(",", ".").replace(/[^\d.]/g, ""));
      if (!Number.isFinite(value) || value < 0)
        return send(ctx, "⚠️ Envie um valor em TON. Ex.: <code>100</code>", kb([nav("m:events")]));
      await evRpc(ctx, "set_prize", args[0] || null, { value });
      await send(ctx, `✅ Prêmio total atualizado para <b>${fmt(value)} TON</b>.`);
      return eventsHub(ctx, args[0] || null, false);
    }
    case "evdates": {
      const parts = text.split("|").map((v) => v.trim());
      const payload: Record<string, unknown> = {};
      if (parts[0]) payload.startsAt = parts[0].replace(" ", "T");
      if (parts[1] && /\d{4}-\d{2}-\d{2}/.test(parts[1])) payload.endsAt = parts[1].replace(" ", "T");
      else if (parts[1]) payload.days = Number(parts[1].replace(",", "."));
      await evRpc(ctx, "set_dates", args[0] || null, payload);
      await send(ctx, "✅ Datas atualizadas.");
      return eventsHub(ctx, args[0] || null, false);
    }
    case "evrules": {
      const parts = text.split("|").map((v) => v.trim());
      const rules: Record<string, unknown> = {};
      if (parts[0]) rules.minDailyQuests = Math.max(0, Math.round(Number(parts[0])));
      if (parts[1]) rules.topLimit = Math.max(1, Math.round(Number(parts[1])));
      if (parts[2]) rules.distributionMode = parts[2].toLowerCase() === "proportional" ? "proportional" : "fixed";
      await evRpc(ctx, "set_rules", args[0] || null, { rules });
      await send(ctx, "✅ Regras anti-fraude e de distribuição atualizadas.");
      return eventsHub(ctx, args[0] || null, false);
    }
    case "evdist": {
      const distribution = text
        .split(/[;\n]+/)
        .map((row) => row.trim())
        .filter(Boolean)
        .map((row) => {
          const [range, ton] = row.split("=").map((v) => v.trim());
          const [from, to] = range
            .replace(/#/g, "")
            .split("-")
            .map((v) => Math.round(Number(v)));
          return { from, to: Number.isFinite(to) ? to : from, ton: Number(String(ton).replace(",", ".")) };
        });
      if (!distribution.length || distribution.some((x) => !Number.isFinite(x.from) || !Number.isFinite(x.ton))) {
        return send(
          ctx,
          "⚠️ Envie faixas assim: <code>1=25; 2=15; 3=10; 4-10=3; 11-50=0.5</code>",
          kb([nav("m:events")]),
        );
      }
      await evRpc(ctx, "set_rules", args[0] || null, { rules: { distributionMode: "fixed", distribution } });
      await send(ctx, `✅ Tabela de prêmios salva (${distribution.length} faixas).`);
      return eventsHub(ctx, args[0] || null, false);
    }
    case "rfaudit":
      return rarityFusionAudit(ctx, text.trim());
    case "removehero": {
      const r = await rpc("admin_remove_player_hero", {
        p_admin_id: ctx.adminId,
        p_hero_id: text,
        p_reason: "removido pelo painel",
      });
      return send(ctx, `🗑 Herói ${esc(r.name)} removido.`, MAIN_MENU);
    }
    case "removepet": {
      const r = await rpc("admin_remove_pet", {
        p_admin_id: ctx.adminId,
        p_player_pet_id: text,
        p_reason: "removido pelo painel",
      });
      return send(ctx, `🗑 Pet removido (<code>${r.player_pet_id}</code>).`, MAIN_MENU);
    }
    case "vip": {
      const [tier, user] = args;
      const r = await rpc("admin_set_membership", {
        p_admin_id: ctx.adminId,
        p_ref: user,
        p_tier: tier,
        p_days: Number(text),
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ ${tier.toUpperCase()} até ${r.until ? String(r.until).slice(0, 10) : "removido"}.`,
        kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav()]),
      );
    }
    case "ban": {
      const r = await rpc("admin_set_ban", { p_admin_id: ctx.adminId, p_ref: args[0], p_banned: true, p_reason: text });
      return send(ctx, `🚫 Jogador banido (<code>${r.user_id}</code>).`, MAIN_MENU);
    }
    case "reset": {
      const r = await rpc("admin_reset_account", { p_admin_id: ctx.adminId, p_ref: args[0], p_reason: text });
      return send(ctx, `♻️ Conta resetada (<code>${r.user_id}</code>).`, MAIN_MENU);
    }
    case "hero": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_hero", {
        p_admin_id: ctx.adminId,
        p_hero_key: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ Herói salvo: <b>${esc(r.name)}</b> — ${esc(r.rarity)} ${r.enabled ? "✅" : "⛔"} ${r.price_fc ? fmt(r.price_fc) + " FC" : ""}`,
        MAIN_MENU,
      );
    }
    case "hprice": {
      const count = Number(args[0]);
      const price = Math.round(Number(text.replace(/[^\d]/g, "")));
      if (!Number.isFinite(price) || price < 1)
        return send(
          ctx,
          "⚠️ Envie apenas números. Ex.: <code>30000</code>",
          kb([[{ t: "💰 PREÇOS", d: "hs:prices" }], nav("m:shop")]),
        );
      const cfg = await heroShopConfig(ctx);
      return send(
        ctx,
        `✏️ <b>ALTERAR PREÇO ${count}x</b>\n\nAntes: <b>${fmt(cfg.config.prices[String(count)])} FC</b>\nDepois: <b>${fmt(price)} FC</b>`,
        kb([
          [
            { t: "✅ CONFIRMAR", d: `hpok:${count}:${price}` },
            { t: "❌ CANCELAR", d: "hs:prices" },
          ],
        ]),
      );
    }
    case "hodd": {
      const rarity = args[0];
      const value = Number(text.replace(",", ".").replace(/[^\d.]/g, ""));
      if (!Number.isFinite(value) || value < 0 || value > 100)
        return send(
          ctx,
          "⚠️ Porcentagem inválida (0 a 100).",
          kb([[{ t: "🎲 CHANCES", d: "hs:odds" }], nav("m:shop")]),
        );
      const cfg = await heroShopConfig(ctx);
      const total = RARITY_ORDER.reduce((sum, k) => sum + (k === rarity ? value : Number(cfg.config.odds[k] ?? 0)), 0);
      if (Math.abs(total - 100) > 0.001) {
        return send(
          ctx,
          `❌ Total inválido: <b>${pct(total)}%</b>\nA soma das 5 raridades precisa ser exatamente 100%.\n\nAjuste outra raridade ou use EDITAR TODAS.`,
          kb([[{ t: "✏️ EDITAR TODAS", d: "ask:hodds" }], [{ t: "🎲 CHANCES", d: "hs:odds" }], nav("m:shop")]),
        );
      }
      return send(
        ctx,
        `✏️ <b>ALTERAR CHANCE — ${RARITY_LABEL[rarity]}</b>\n\nAntes: <b>${pct(cfg.config.odds[rarity])}%</b>\nDepois: <b>${pct(value)}%</b>\nTotal: <b>${pct(total)}%</b>`,
        kb([
          [
            { t: "✅ CONFIRMAR", d: `hoc:${rarity}:${value}` },
            { t: "❌ CANCELAR", d: "hs:odds" },
          ],
        ]),
      );
    }
    case "hodds": {
      const parts = text
        .replace(/,/g, ".")
        .split(/[\s;]+/)
        .map(Number)
        .filter((n) => Number.isFinite(n));
      // Ancestral is event/admin exclusive: it is always 0 and is not asked for here.
      if (parts.length !== 6)
        return send(
          ctx,
          "⚠️ Envie 6 números: comum incomum raro épico lendário mítico.\nAncestral é exclusivo (0%).",
          kb([[{ t: "🎲 CHANCES", d: "hs:odds" }], nav("m:shop")]),
        );
      const total = parts.reduce((a, b) => a + b, 0);
      if (Math.abs(total - 100) > 0.001) {
        return send(
          ctx,
          `❌ Total inválido: <b>${pct(total)}%</b>\nA soma precisa ser exatamente 100%.`,
          kb([[{ t: "🎲 CHANCES", d: "hs:odds" }], nav("m:shop")]),
        );
      }
      const rates: Record<string, number> = { ancestral: 0 };
      RARITY_ORDER.filter((k) => k !== "ancestral").forEach((k, i) => {
        rates[k] = parts[i];
      });
      const before = (await heroShopConfig(ctx)).config.odds;
      const r = await rpc("admin_set_hero_summon_rates", {
        p_admin_id: ctx.adminId,
        p_rates: rates,
        p_reason: "painel admin (bot)",
      });
      return send(
        ctx,
        `✅ Chances salvas.\n${RARITY_ORDER.map((k) => `${RARITY_LABEL[k]}: ${pct(before[k])}% → <b>${pct(r.odds[k])}%</b>`).join("\n")}`,
        kb([[{ t: "🎲 CHANCES", d: "hs:odds" }], nav("m:shop")]),
      );
    }
    case "hoddsreal": {
      const parts = text
        .replace(/,/g, ".")
        .split(/[\s;]+/)
        .map(Number)
        .filter((n) => Number.isFinite(n));
      if (parts.length !== 6)
        return send(
          ctx,
          "⚠️ Envie 6 números: comum incomum raro épico lendário mítico.",
          kb([[{ t: "🕵️ CHANCES REAIS", d: "hs:roddz" }], nav("m:shop")]),
        );
      const total = parts.reduce((a, b) => a + b, 0);
      if (Math.abs(total - 100) > 0.001) {
        return send(
          ctx,
          `❌ Total inválido: <b>${pct(total)}%</b>\nA soma precisa ser exatamente 100%.`,
          kb([[{ t: "🕵️ CHANCES REAIS", d: "hs:roddz" }], nav("m:shop")]),
        );
      }
      const rates: Record<string, number> = { ancestral: 0 };
      RARITY_ORDER.filter((k) => k !== "ancestral").forEach((k, i) => {
        rates[k] = parts[i];
      });
      const r = await rpc("admin_set_hero_real_summon_rates", {
        p_admin_id: ctx.adminId,
        p_rates: rates,
        p_reason: "chances reais (bot)",
      });
      return send(
        ctx,
        `✅ Chances REAIS salvas (a vitrine do jogo não muda).\n${RARITY_ORDER.filter((k) => k !== "ancestral")
          .map((k) => `${RARITY_LABEL[k]}: <b>${pct(r.rates[k])}%</b> · vitrine ${pct(r.publicOdds?.[k] ?? 0)}%`)
          .join("\n")}`,
        kb([[{ t: "🕵️ CHANCES REAIS", d: "hs:roddz" }], nav("m:shop")]),
      );
    }
    case "fusion": {
      const r = await rpc("admin_set_fusion_config", {
        p_admin_id: ctx.adminId,
        p_patch: JSON.parse(text),
        p_reason: "painel admin (bot)",
      });
      return send(
        ctx,
        `✅ Fusão atualizada — máximo ★${r.max_stars}.`,
        kb([[{ t: "🧬 DUPLICATE FUSE SETTINGS", d: "hs:fusion" }], nav("m:shop")]),
      );
    }
    case "herotoggle": {
      const heroKey = text.split(/\s+/)[0];
      const { data: hero } = await db
        .from("hero_catalog")
        .select("hero_key,name,enabled")
        .eq("hero_key", heroKey)
        .maybeSingle();
      if (!hero) return send(ctx, "⚠️ Herói não encontrado.", kb([[{ t: "🦸 HERÓIS", d: "hs:list" }], nav("m:shop")]));
      const r = await rpc("admin_upsert_hero", {
        p_admin_id: ctx.adminId,
        p_hero_key: heroKey,
        p_patch: { enabled: !hero.enabled },
        p_reason: "painel admin (bot)",
      });
      return send(
        ctx,
        `${r.enabled ? "✅ Ativado" : "⛔ Desativado"}: <b>${esc(r.name)}</b>`,
        kb([[{ t: "🦸 HERÓIS", d: "hs:list" }], nav("m:shop")]),
      );
    }
    case "rates": {
      try {
        const r = await rpc("admin_set_hero_rarity_rates", {
          p_admin_id: ctx.adminId,
          p_rates: JSON.parse(text),
          p_normalize: false,
          p_reason: "painel admin",
        });
        return send(ctx, `✅ Raridades salvas:\n<code>${esc(JSON.stringify(r.rates))}</code>`, MAIN_MENU);
      } catch (e) {
        if (String(e).includes("rates_must_total_100")) {
          return send(
            ctx,
            `⚠️ O total não é 100%. Deseja normalizar automaticamente?`,
            kb([
              [
                { t: "✅ NORMALIZAR", d: `norm:${encodeURIComponent(text)}`.slice(0, 60) },
                { t: "❌ Cancelar", d: "home" },
              ],
            ]),
          );
        }
        throw e;
      }
    }
    case "pet": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_pet", {
        p_admin_id: ctx.adminId,
        p_slug: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Pet salvo: <b>${esc(r.name)}</b>`, MAIN_MENU);
    }
    case "food": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_pet_food", {
        p_admin_id: ctx.adminId,
        p_code: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Comida salva: ${esc(r.name)} — ${r.xp_value} XP`, MAIN_MENU);
    }
    case "foodprice": {
      const [code, price] = text.trim().split(/\s+/);
      const r = await rpc("admin_set_pet_food_price", {
        p_admin_id: ctx.adminId,
        p_code: code,
        p_price: Number(price),
      });
      return send(
        ctx,
        `✅ ${esc(r.name)} — novo preço <b>${fmt(r.price_fc)} FC</b> (+${fmt(r.xp_value)} XP)`,
        kb([[{ t: "🍖 COMIDAS", d: "view:foods" }], nav("m:pets")]),
      );
    }
    case "eggprice": {
      const [slug, fc, ton] = text.trim().split(/\s+/);
      const patch: Record<string, unknown> = {
        price_fc: Number(fc) > 0 ? Number(fc) : null,
        updated_at: new Date().toISOString(),
      };
      if (ton !== undefined) patch.price_ton = Number(ton) > 0 ? Number(ton) : null;
      const { data: egg, error } = await db.from("pet_eggs").update(patch).eq("slug", slug).select("*").maybeSingle();
      if (error) throw new Error(error.message);
      if (!egg) return send(ctx, "⚠️ Ovo não encontrado.", MAIN_MENU);
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "pet_egg.price",
        p_target_type: "pet_egg",
        p_target_id: slug,
        p_old: null,
        p_new: patch,
        p_reason: "painel admin",
        p_context: { financial: true },
      });
      return send(
        ctx,
        `✅ ${esc(egg.name)} — ${fmt(egg.price_fc ?? 0)} FC / ${egg.price_ton ?? "—"} TON`,
        kb([[{ t: "🥚 OVOS", d: "view:eggs" }], nav("m:pets")]),
      );
    }
    case "egg": {
      const i = text.indexOf(" ");
      const patch = JSON.parse(text.slice(i + 1));
      const { data: egg, error } = await db
        .from("pet_eggs")
        .update({ ...patch, updated_at: new Date().toISOString() })
        .eq("slug", text.slice(0, i))
        .select("*")
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (!egg) return send(ctx, "⚠️ Ovo não encontrado.", MAIN_MENU);
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "pet_egg.update",
        p_target_type: "pet_egg",
        p_target_id: egg.slug,
        p_old: null,
        p_new: patch,
        p_reason: "painel admin",
        p_context: {},
      });
      return send(
        ctx,
        `✅ Ovo salvo: <b>${esc(egg.name)}</b>`,
        kb([[{ t: "🥚 OVOS", d: "view:eggs" }], nav("m:pets")]),
      );
    }
    case "giveitem": {
      const parts = text.trim().split(/\s+/);
      const user = parts.shift()!;
      const kind = (parts.shift() || "").toLowerCase();
      const ref = parts.shift() || "";
      const quantity = Number(parts.shift() || 1);
      const player = await rpc("admin_resolve_player", { p_ref: user });
      if (!player?.telegram_id) return send(ctx, "⚠️ Jogador não encontrado.", MAIN_MENU);
      if (kind.startsWith("ovo") || kind.startsWith("egg")) {
        const { data: egg } = await db
          .from("pet_eggs")
          .select("id,name")
          .or(`slug.eq.${ref},id.eq.${ref}`)
          .maybeSingle();
        if (!egg) return send(ctx, "⚠️ Ovo não encontrado.", MAIN_MENU);
        await rpc("admin_grant_pet_item", {
          p_telegram_id: player.telegram_id,
          p_item_type: "egg",
          p_item_id: egg.id,
          p_quantity: quantity,
        });
        await rpc("admin_log", {
          p_admin_id: ctx.adminId,
          p_action: "pet_item.grant",
          p_target_type: "player",
          p_target_id: String(player.telegram_id),
          p_old: null,
          p_new: { egg: egg.name, quantity },
          p_reason: "painel admin",
          p_context: {},
        });
        return send(
          ctx,
          `🎁 <b>${quantity}x ${esc(egg.name)}</b> enviado para ${esc(String(player.telegram_id))}.`,
          kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav("m:pets")]),
        );
      }
      if (kind.startsWith("comida") || kind.startsWith("food")) {
        const r = await rpc("admin_grant_pet_food", {
          p_telegram_id: player.telegram_id,
          p_code: ref,
          p_quantity: quantity,
        });
        await rpc("admin_log", {
          p_admin_id: ctx.adminId,
          p_action: "pet_food.grant",
          p_target_type: "player",
          p_target_id: String(player.telegram_id),
          p_old: null,
          p_new: { food: ref, quantity },
          p_reason: "painel admin",
          p_context: {},
        });
        return send(
          ctx,
          `🎁 <b>${quantity}x ${esc(ref)}</b> enviado.\n<code>${esc(JSON.stringify(r?.inventory ?? {})).slice(0, 300)}</code>`,
          kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav("m:pets")]),
        );
      }
      if (kind.startsWith("frag")) {
        await rpc("admin_grant_pet_item", {
          p_telegram_id: player.telegram_id,
          p_item_type: "universal_fragment",
          p_item_id: null,
          p_quantity: quantity,
        });
        return send(
          ctx,
          `🧩 <b>${quantity}</b> fragmentos universais enviados.`,
          kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav("m:pets")]),
        );
      }
      return send(ctx, "⚠️ Tipo inválido. Use ovo, comida ou fragmento.", MAIN_MENU);
    }
    case "givefrag": {
      const [user, quantity] = text.trim().split(/\s+/);
      const player = await rpc("admin_resolve_player", { p_ref: user });
      if (!player?.telegram_id) return send(ctx, "⚠️ Jogador não encontrado.", MAIN_MENU);
      await rpc("admin_grant_pet_item", {
        p_telegram_id: player.telegram_id,
        p_item_type: "universal_fragment",
        p_item_id: null,
        p_quantity: Number(quantity || 1),
      });
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "pet_fragment.grant",
        p_target_type: "player",
        p_target_id: String(player.telegram_id),
        p_old: null,
        p_new: { quantity: Number(quantity || 1) },
        p_reason: "painel admin",
        p_context: {},
      });
      return send(
        ctx,
        `🧩 <b>${fmt(Number(quantity || 1))}</b> fragmentos universais enviados.`,
        kb([[{ t: "👤 Ver jogador", d: `find:${user}` }], nav("m:pets")]),
      );
    }
    case "league": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_league", {
        p_admin_id: ctx.adminId,
        p_code: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Liga salva: ${esc(r.name)} (${r.min_trophies}–${r.max_trophies ?? "∞"})`, MAIN_MENU);
    }
    case "channel": {
      const i = text.indexOf(" ");
      if (i < 0)
        return send(
          ctx,
          "⚠️ Envie a chave do canal e o JSON.",
          kb([[{ t: "📡 CANAIS OFICIAIS", d: "m:channels" }], nav()]),
        );
      const r = await rpc("admin_update_channel", {
        p_admin_id: ctx.adminId,
        p_channel_key: text.slice(0, i).trim(),
        p_patch: JSON.parse(text.slice(i + 1)),
      });
      return send(
        ctx,
        `✅ <b>${esc(r.title)}</b> ${r.enabled ? "✅" : "⛔"}\nchat: <code>${esc(r.chatRef || "NÃO CONFIGURADO")}</code> · ${fmt(r.rewardFc)} FC`,
        kb([[{ t: "📡 CANAIS OFICIAIS", d: "m:channels" }], nav()]),
      );
    }
    case "chclaims": {
      const d = await rpc("admin_player_channel_claims", { p_admin_id: ctx.adminId, p_player: text.trim() });
      const rows =
        (d.channels || [])
          .map(
            (c: any) =>
              `• <b>${esc(c.title)}</b> — ${c.claimed ? `✅ CLAIMED (+${fmt(c.rewardReceived || c.rewardFc)} FC)` : "⛔ NOT CLAIMED"}`,
          )
          .join("\n") || "—";
      return send(
        ctx,
        `📡 <b>CLAIMS DOS CANAIS</b>\n${esc(d.name || d.username || "")} · <code>${d.telegramId}</code>\n\n${rows}`,
        kb([[{ t: "♻️ RESET MANUAL", d: "ask:chreset" }], [{ t: "📡 CANAIS OFICIAIS", d: "m:channels" }], nav()]),
      );
    }
    case "chreset": {
      const [ref, key, confirmWord] = text.trim().split(/\s+/);
      if (!ref || !key)
        return send(
          ctx,
          "⚠️ Envie: <code>usuário channel_key CONFIRMAR</code>",
          kb([[{ t: "📡 CANAIS OFICIAIS", d: "m:channels" }], nav()]),
        );
      if (String(confirmWord || "").toUpperCase() !== "CONFIRMAR") {
        return send(
          ctx,
          `⚠️ <b>Confirmação obrigatória.</b>\nEsse reset permite que o jogador receba a recompensa de <code>${esc(key)}</code> novamente.\nReenvie: <code>${esc(ref)} ${esc(key)} CONFIRMAR</code>`,
          kb([[{ t: "♻️ TENTAR NOVAMENTE", d: "ask:chreset" }], [{ t: "📡 CANAIS OFICIAIS", d: "m:channels" }], nav()]),
        );
      }
      const d = await rpc("admin_reset_channel_claim", { p_admin_id: ctx.adminId, p_player: ref, p_channel_key: key });
      const rows =
        (d.channels || [])
          .map((c: any) => `• <b>${esc(c.title)}</b> — ${c.claimed ? "✅ CLAIMED" : "⛔ NOT CLAIMED"}`)
          .join("\n") || "—";
      return send(
        ctx,
        `♻️ Claim de <code>${esc(key)}</code> resetado (${fmt(d.removed || 0)} registro).\nAuditoria registrada.\n\n${rows}`,
        kb([[{ t: "📡 CANAIS OFICIAIS", d: "m:channels" }], nav()]),
      );
    }
    case "quest": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_quest", {
        p_admin_id: ctx.adminId,
        p_code: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ Quest salva: <b>${esc(r.title)}</b> — ${esc(r.event_key)} · meta ${r.target_amount} · ${fmt(r.reward_fc)} FC ${r.enabled ? "✅" : "⛔"}`,
        kb([[{ t: "🎯 DAILY QUESTS", d: "m:quests" }], nav()]),
      );
    }
    case "questtoggle": {
      const d = await rpc("admin_quests_overview", { p_admin_id: ctx.adminId });
      const current = (d.quests || []).find((q: any) => q.code === text);
      if (!current)
        return send(ctx, "⚠️ Quest não encontrada.", kb([[{ t: "🎯 DAILY QUESTS", d: "m:quests" }], nav()]));
      const r = await rpc("admin_upsert_quest", {
        p_admin_id: ctx.adminId,
        p_code: text,
        p_patch: { enabled: !current.enabled },
        p_reason: "toggle pelo painel",
      });
      return send(
        ctx,
        `✅ ${esc(r.title)} agora está ${r.enabled ? "ATIVA ✅" : "INATIVA ⛔"}.`,
        kb([[{ t: "🎯 DAILY QUESTS", d: "m:quests" }], nav()]),
      );
    }
    case "questbonus": {
      const [code, qty, ...name] = text.split(/\s+/);
      const r = await rpc("admin_set_quest_bonus", {
        p_admin_id: ctx.adminId,
        p_item_type: "hero_chest",
        p_item_code: code,
        p_name: name.join(" ") || code,
        p_quantity: Number(qty) || 1,
      });
      return send(
        ctx,
        `✅ Baú 5/5: <b>${esc(r.name)}</b> — <code>${esc(r.item_code)}</code> x${r.quantity}`,
        kb([[{ t: "🎯 DAILY QUESTS", d: "m:quests" }], nav()]),
      );
    }
    case "questtz": {
      const r = await rpc("admin_set_quest_timezone", { p_admin_id: ctx.adminId, p_timezone: text });
      return send(
        ctx,
        `✅ Reset diário no fuso <b>${esc(r.timezone)}</b>.`,
        kb([[{ t: "🎯 DAILY QUESTS", d: "m:quests" }], nav()]),
      );
    }
    case "mission": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_mission", {
        p_admin_id: ctx.adminId,
        p_code: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Missão salva: ${esc(r.title)}`, MAIN_MENU);
    }
    case "boss": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_boss", {
        p_admin_id: ctx.adminId,
        p_code: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Chefe salvo: ${esc(r.name)} — ${fmt(r.max_hp)} HP`, MAIN_MENU);
    }
    case "gbmulhp":
      return bossSetMultiplier(ctx, "hp", text);
    case "gbmuldef":
      return bossSetMultiplier(ctx, "def", text);
    case "gbmulatk":
      return bossSetMultiplier(ctx, "atk", text);
    case "bossspawn": {
      const r = await rpc("admin_boss_control", {
        p_admin_id: ctx.adminId,
        p_action: "activate",
        p_code: text.trim(),
        p_reason: "ativação manual",
      });
      const ends = r.endsAt ? new Date(r.endsAt).toLocaleString("pt-BR") : "—";
      return send(
        ctx,
        `✅ <b>BOSS ATIVADO</b>\n👹 ${esc(r.name ?? text)}\n❤️ HP: ${fmt(r.maxHp ?? 0)}\n⏱ Duração: ${Math.round((r.durationSeconds ?? 0) / 3600)}h\n📅 Final: ${esc(ends)}`,
        kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
      );
    }
    case "bosshpval": {
      const [code, hp] = text.trim().split(/\s+/);
      const r = await rpc("admin_boss_control", {
        p_admin_id: ctx.adminId,
        p_action: "set_hp",
        p_code: code,
        p_reason: `HP alterado para ${hp}`,
        p_value: Number(hp),
      });
      return send(
        ctx,
        `❤️ HP de <b>${esc(r.name ?? code)}</b> definido para ${fmt(Number(hp))}.`,
        kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
      );
    }
    case "bossdur": {
      const [code, hours] = text.trim().split(/\s+/);
      const seconds = Math.round(Number(hours) * 3600);
      const r = await rpc("admin_boss_control", {
        p_admin_id: ctx.adminId,
        p_action: "set_duration",
        p_code: code,
        p_reason: `duração ${hours}h`,
        p_value: seconds,
      });
      return send(
        ctx,
        `⏱ Duração de <b>${esc(r.name ?? code)}</b>: ${hours}h · fim ${esc(r.endsAt ? new Date(r.endsAt).toLocaleString("pt-BR") : "—")}`,
        kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
      );
    }
    case "bossreward": {
      const [code, reward] = text.trim().split(/\s+/);
      const amount = parseAmount(reward || "");
      if (!Number.isFinite(amount) || amount < 0)
        return send(
          ctx,
          "⚠️ Valor inválido. Ex.: <code>golem_ancestral 9000</code>",
          kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]),
        );
      const r = (await rpc("admin_set_global_boss_reward", {
        p_admin_id: ctx.adminId,
        p_scope: "default",
        p_value: amount,
        p_code: code,
        p_reason: `default reward ${amount} FC`,
      })) as any;
      return send(
        ctx,
        [
          "⚙️ <b>DEFAULT REWARD ATUALIZADO</b> (próximos ciclos)",
          `Boss: <b>${esc(r.bossName)}</b> (<code>${esc(r.bossKey)}</code>)`,
          `Antes: ${fmt(r.oldReward)} FC → Agora: <b>${fmt(r.newReward)} FC</b>`,
          r.activeCycleNumber
            ? `\n⚠️ O ciclo ativo <b>#${r.activeCycleNumber}</b> continua com <b>${fmt(r.activeCycleReward)} FC</b>. Use ✏️ CHANGE CURRENT REWARD para alterá-lo.`
            : "",
        ].join("\n"),
        kb([[{ t: "✏️ CHANGE CURRENT REWARD", d: "boss:curreward" }], [{ t: "👹 Boss", d: "m:boss" }], nav()]),
      );
    }
    case "bosscurreward": {
      const amount = parseAmount(text);
      if (!Number.isFinite(amount) || amount < 0)
        return send(
          ctx,
          "⚠️ Valor inválido. Envie apenas números, ex.: <code>100000</code>",
          kb([[{ t: "✏️ TENTAR NOVAMENTE", d: "boss:curreward" }], nav("m:boss")]),
        );
      const d = (await rpc("admin_boss_overview", { p_admin_id: ctx.adminId })) as any;
      const cyc = d?.cycle ?? null;
      if (!cyc || cyc.status !== "active")
        return send(ctx, "⚠️ Nenhum ciclo ativo do Global Boss.", kb([[{ t: "👹 Boss", d: "m:boss" }], nav()]));
      return send(
        ctx,
        [
          "⚠️ <b>Change Global Boss reward?</b>",
          `Cycle: <b>#${cyc.cycleNumber}</b> · ${esc(cyc.name)}`,
          `Before: <b>${fmt(cyc.rewardPoolFc)} FC</b>`,
          `After: <b>${fmt(amount)} FC</b>`,
          "",
          "Somente o prêmio do ciclo será alterado (HP, ranking, participantes e tempo permanecem).",
        ].join("\n"),
        kb([
          [
            { t: "✅ CONFIRM", d: `gbrw:${amount}` },
            { t: "❌ CANCEL", d: "m:boss" },
          ],
        ]),
      );
    }
    case "ads": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_upsert_ad_provider", {
        p_admin_id: ctx.adminId,
        p_code: text.slice(0, i),
        p_patch: JSON.parse(text.slice(i + 1)),
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ Provedor ${esc(r.name)} ${r.enabled ? "ativo" : "inativo"} — ${fmt(r.reward_fc)} FC`,
        MAIN_MENU,
      );
    }
    case "setting": {
      const i = text.indexOf(" ");
      const k = i < 0 ? text : text.slice(0, i);
      const v = i < 0 ? "" : text.slice(i + 1);
      const r = await rpc("admin_set_setting", {
        p_admin_id: ctx.adminId,
        p_key: k,
        p_value: parseValue(v),
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ <code>${esc(k)}</code>\n${esc(JSON.stringify(r.old_value))} → <b>${esc(JSON.stringify(r.new_value))}</b>`,
        MAIN_MENU,
      );
    }
    case "pvpset": {
      const [k, v] = text.split(/\s+/);
      const r = await rpc("admin_set_setting", {
        p_admin_id: ctx.adminId,
        p_key: k,
        p_value: parseValue(v),
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ ${esc(k)}: ${esc(JSON.stringify(r.old_value))} → <b>${esc(JSON.stringify(r.new_value))}</b>`,
        MAIN_MENU,
      );
    }
    case "tkfree": {
      const r = await rpc("admin_set_setting", {
        p_admin_id: ctx.adminId,
        p_key: "pvp_ticket_free_daily_limit",
        p_value: Number(text.replace(/[^\d]/g, "")),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Limite diário FREE: <b>${esc(JSON.stringify(r.new_value))}</b>`, MAIN_MENU);
    }
    case "tkpass": {
      const r = await rpc("admin_set_setting", {
        p_admin_id: ctx.adminId,
        p_key: "pvp_ticket_pass_daily_limit",
        p_value: Number(text.replace(/[^\d]/g, "")),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Limite diário PASSE: <b>${esc(JSON.stringify(r.new_value))}</b>`, MAIN_MENU);
    }
    case "tkpack": {
      const [q, p] = text.split(/\s+/);
      const r = await rpc("admin_set_pvp_ticket_pack", {
        p_admin_id: ctx.adminId,
        p_quantity: Number(q),
        p_price_fc: Number(String(p).replace(/[^\d.]/g, "")),
      });
      return send(ctx, `✅ Pacotes: <code>${esc(JSON.stringify(r.packs))}</code>`, MAIN_MENU);
    }

    case "maintmsg": {
      await rpc("admin_set_setting", {
        p_admin_id: ctx.adminId,
        p_key: "maintenance_message",
        p_value: text,
        p_reason: "painel admin",
      });
      return send(ctx, "✅ Mensagem atualizada.", MAIN_MENU);
    }
    case "ref": {
      const r = await rpc("admin_set_referral_percent", {
        p_admin_id: ctx.adminId,
        p_level: Number(args[0]),
        p_percent: Number(text.replace(/[^\d.]/g, "")),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Nível ${r.level}: ${r.old_value}% → <b>${r.new_value}%</b>`, MAIN_MENU);
    }
    case "unlink": {
      const i = text.indexOf(" ");
      const r = await rpc("admin_unlink_referral", {
        p_admin_id: ctx.adminId,
        p_ref: text.slice(0, i),
        p_reason: text.slice(i + 1),
      });
      return send(ctx, `✂️ ${r.removed} vínculo(s) removido(s).`, MAIN_MENU);
    }
    case "pool": {
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value <= 0)
        throw new Error(
          "KEEP_SESSION::⚠️ Valor inválido. Envie um número maior que 0 (ex.: <code>20</code> ou <code>20,5</code>).",
        );
      const mode = args[0] === "remove" ? "remove" : "add";
      await setSession(ctx, `pool|${mode}`, "awaiting_confirmation", { amount: value });
      return send(
        ctx,
        `⚠️ Confirmar <b>${mode === "remove" ? "REMOVER" : "ADICIONAR"} ${value} TON</b> na Community Pool?`,
        kb([
          [
            { t: "✅ CONFIRMAR", d: `poolgo:${mode}:${value}` },
            { t: "❌ CANCELAR", d: "cancel" },
          ],
        ]),
      );
    }

    case "mptotal": {
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número maior ou igual a 0 (ex.: <code>700</code>).");
      const r = (await rpc("admin_marketing_pool_set_total", { p_admin_id: ctx.adminId, p_total: value })) as any;
      return send(
        ctx,
        `✅ <b>TOTAL POOL</b> atualizado: <b>${mpTon(r.totalTon)}</b>\nSpent ${mpTon(r.spentTon)} · Remaining <b>${mpTon(r.remainingTon)}</b>`,
        kb([[{ t: "📣 POOL MARKETING", d: "mp:hub" }], nav()]),
      );
    }
    case "mpadd": {
      const parts = text.split("|").map((x) => x.trim());
      const [cat, desc, amountRaw, dateRaw, noteRaw] = parts;
      const category = String(cat || "").toUpperCase();
      if (!MP_CATEGORIES.includes(category))
        throw new Error(`KEEP_SESSION::⚠️ Categoria inválida. Use: ${MP_CATEGORIES.join(", ")}`);
      if (!desc) throw new Error("KEEP_SESSION::⚠️ Descrição obrigatória.");
      const amount = parseAmount(amountRaw ?? "");
      if (!Number.isFinite(amount) || amount <= 0)
        throw new Error("KEEP_SESSION::⚠️ Valor inválido (ex.: <code>120</code> ou <code>12,5</code>).");
      const r = (await rpc("admin_marketing_pool_add_expense", {
        p_admin_id: ctx.adminId,
        p_category: category,
        p_description: desc,
        p_amount: amount,
        p_spent_at: mpParseDate(dateRaw),
        p_note: noteRaw && noteRaw !== "-" ? noteRaw : null,
      })) as any;
      return send(
        ctx,
        `✅ Lançamento registrado.\n<b>${esc(category)}</b> — ${esc(desc)} · −${mpTon(amount)}\n\nSpent <b>${mpTon(r.spentTon)}</b> · Remaining <b>${mpTon(r.remainingTon)}</b> · Entries ${fmt(r.entries)}`,
        kb([[{ t: "📣 POOL MARKETING", d: "mp:hub" }], nav()]),
      );
    }
    case "mpedit": {
      const parts = text.split("|").map((x) => x.trim());
      const [idRaw, cat, desc, amountRaw, dateRaw, noteRaw] = parts;
      const id = await mpResolveExpense(idRaw ?? "");
      const category = cat && cat !== "-" ? String(cat).toUpperCase() : null;
      if (category && !MP_CATEGORIES.includes(category))
        throw new Error(`KEEP_SESSION::⚠️ Categoria inválida. Use: ${MP_CATEGORIES.join(", ")}`);
      let amount: number | null = null;
      if (amountRaw && amountRaw !== "-") {
        amount = parseAmount(amountRaw);
        if (!Number.isFinite(amount) || amount <= 0) throw new Error("KEEP_SESSION::⚠️ Valor inválido.");
      }
      const r = (await rpc("admin_marketing_pool_update_expense", {
        p_admin_id: ctx.adminId,
        p_id: id,
        p_category: category,
        p_description: desc && desc !== "-" ? desc : null,
        p_amount: amount,
        p_spent_at: mpParseDate(dateRaw),
        p_note: noteRaw && noteRaw !== "-" ? noteRaw : null,
      })) as any;
      return send(
        ctx,
        `✅ Lançamento atualizado.\nSpent <b>${mpTon(r.spentTon)}</b> · Remaining <b>${mpTon(r.remainingTon)}</b>`,
        kb([[{ t: "📋 VIEW HISTORY", d: "mp:list:0" }], [{ t: "📣 POOL MARKETING", d: "mp:hub" }], nav()]),
      );
    }
    case "mpdel": {
      const id = await mpResolveExpense(text);
      const r = (await rpc("admin_marketing_pool_delete_expense", { p_admin_id: ctx.adminId, p_id: id })) as any;
      return send(
        ctx,
        `🗑 Lançamento removido.\nSpent <b>${mpTon(r.spentTon)}</b> · Remaining <b>${mpTon(r.remainingTon)}</b> · Entries ${fmt(r.entries)}`,
        kb([[{ t: "📣 POOL MARKETING", d: "mp:hub" }], nav()]),
      );
    }
    case "poolset": {
      const [k, v] = text.split(/\s+/);
      await rpc("admin_set_setting", {
        p_admin_id: ctx.adminId,
        p_key: "pool_" + k,
        p_value: parseValue(v),
        p_reason: "painel admin",
      });
      return send(ctx, `✅ Configuração da pool <code>${esc(k)}</code> = ${esc(v)}`, MAIN_MENU);
    }
    case "poolrate": {
      // Aceita "0", "0%", "5", "5%", "10,5" e normaliza para número puro.
      const raw = String(text || "")
        .trim()
        .replace("%", "")
        .replace(",", ".")
        .replace(/\s+/g, "");
      const pct = /^\d+(\.\d+)?$/.test(raw) ? Number(raw) : NaN;
      if (!Number.isFinite(pct) || pct < 0 || pct > 100)
        return send(ctx, "⚠️ Informe um percentual entre 0 e 100 (ex: 0, 0%, 5, 15%).", MAIN_MENU);
      const r = await rpc("admin_set_pool_contribution_percent", { p_admin_id: ctx.adminId, p_percent: pct });
      const prev = r?.previous ?? null;
      const curr = r?.current ?? pct;
      const fmt = (n: unknown) => (n === null || n === undefined ? "—" : `${Number(n)}%`);
      return send(
        ctx,
        `✅ <b>Taxa da Community Pool atualizada</b>\nAnterior: <b>${fmt(prev)}</b>\nNova: <b>${fmt(curr)}</b>\n\nAplicada sobre toda receita TON confirmada.`,
        MAIN_MENU,
      );
    }

    case "passxpadj": {
      const [mode, user] = args;
      const value = parseAmount(text);
      if (!Number.isFinite(value) || value <= 0)
        throw new Error("KEEP_SESSION::⚠️ Envie um número maior que 0 (ex.: <code>500</code>).");
      const r = await rpc("admin_adjust_pass_xp", {
        p_admin_id: ctx.adminId,
        p_ref: user,
        p_delta: mode === "remove" ? -Math.round(value) : Math.round(value),
        p_reason: "ajuste manual de XP do passe",
      });
      return send(
        ctx,
        `✅ XP do passe atualizado.\nTotal: <b>${fmt(r.xp)}</b> · Nível <b>${r.level}</b>/${r.levels}`,
        kb([[{ t: "🎟 VER PASSE", d: `bpview:${user}` }], nav("m:pass")]),
      );
    }
    case "passlevel": {
      const [user] = args;
      const lvl = Math.round(parseAmount(text));
      if (!Number.isFinite(lvl) || lvl < 1)
        throw new Error("KEEP_SESSION::⚠️ Envie um nível válido (ex.: <code>8</code>).");
      const r = await rpc("admin_set_pass_level", {
        p_admin_id: ctx.adminId,
        p_ref: user,
        p_level: lvl,
        p_reason: "nível do passe definido pelo painel",
      });
      return send(
        ctx,
        `✅ Nível definido.\nNível <b>${r.level}</b>/${r.levels} · XP total ${fmt(r.xp)}`,
        kb([[{ t: "🎟 VER PASSE", d: `bpview:${user}` }], nav("m:pass")]),
      );
    }
    case "passxp": {
      const [k, v] = text.split(/\s+/);
      const value = Math.round(parseAmount(v ?? ""));
      if (!k || !Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie <code>chave valor</code> (ex.: <code>pvp_battle 50</code>).");
      const r = await rpc("admin_set_pass_xp_settings", {
        p_admin_id: ctx.adminId,
        p_patch: { [k]: value },
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ <code>${esc(k)}</code> = <b>${fmt(value)} XP</b>\n<code>${esc(JSON.stringify(r))}</code>`,
        kb([[{ t: "⚡ XP SETTINGS", d: "view:passxp" }], nav("m:pass")]),
      );
    }
    case "passxpmult": {
      const [tier, v] = text.split(/\s+/);
      const key = String(tier || "").toLowerCase() === "free" ? "none" : String(tier || "").toLowerCase();
      const value = Number(String(v ?? "").replace(",", "."));
      if (!["none", "adventurer", "legendary"].includes(key) || !Number.isFinite(value) || value < 0.1 || value > 10) {
        throw new Error(
          "KEEP_SESSION::⚠️ Envie <code>free|adventurer|legendary valor</code> (ex.: <code>legendary 1.4</code>).",
        );
      }
      const r = await rpc("admin_set_pass_xp_multipliers", {
        p_admin_id: ctx.adminId,
        p_patch: key === "none" ? { none: value, free: value } : { [key]: value },
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ Multiplicador de XP <code>${esc(key)}</code> = <b>x${value}</b>\n<code>${esc(JSON.stringify(r))}</code>`,
        kb([[{ t: "⚡ XP SETTINGS", d: "view:passxp" }], nav("m:pass")]),
      );
    }
    case "passxpcap": {
      const [k, v] = text.split(/\s+/);
      const value = Math.round(parseAmount(v ?? ""));
      if (!k || !Number.isFinite(value) || value < 0)
        throw new Error("KEEP_SESSION::⚠️ Envie <code>chave limite</code> (ex.: <code>pet_feed 100</code>).");
      const r = await rpc("admin_set_pass_xp_caps", {
        p_admin_id: ctx.adminId,
        p_patch: { [k]: value },
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ Limite diário de <code>${esc(k)}</code> = <b>${fmt(value)} XP base/dia</b>\n<code>${esc(JSON.stringify(r))}</code>`,
        kb([[{ t: "⚡ XP SETTINGS", d: "view:passxp" }], nav("m:pass")]),
      );
    }
    case "passxplevel": {
      const value = Math.round(parseAmount(text));
      if (!Number.isFinite(value) || value < 1)
        throw new Error("KEEP_SESSION::⚠️ Envie um número maior que 0 (ex.: <code>1000</code>).");
      const { data: season } = await db
        .from("season_pass_seasons")
        .select("*")
        .eq("active", true)
        .order("start_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!season) return send(ctx, "⚠️ Nenhuma temporada ativa.", MAIN_MENU);
      await rpc("admin_update_season_pass", {
        p_season_id: season.id,
        p_name: season.name,
        p_start_at: season.start_at,
        p_end_at: season.end_at,
        p_levels: season.levels,
        p_xp_per_level: value,
        p_adventurer_price: season.adventurer_price_ton,
        p_legendary_price: season.legendary_price_ton,
        p_active: season.active,
      });
      await rpc("admin_bump_settings_version", {});
      return send(
        ctx,
        `✅ XP por nível agora é <b>${fmt(value)}</b>.`,
        kb([[{ t: "⚡ XP SETTINGS", d: "view:passxp" }], nav("m:pass")]),
      );
    }
    case "passlevelprice": {
      const [n, v] = text.split(/\s+/);
      const levels = Number(n),
        value = Math.round(parseAmount(v ?? ""));
      if (![1, 3, 5].includes(levels) || !Number.isFinite(value) || value <= 0)
        throw new Error("KEEP_SESSION::⚠️ Envie <code>1|3|5 preço</code> (ex.: <code>3 135000</code>).");
      const r = await rpc("admin_set_pass_level_purchase", {
        p_admin_id: ctx.adminId,
        p_patch: { prices: { [String(levels)]: value } },
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ +${levels} nível(is) = <b>${fmt(value)} FC</b>\n<code>${esc(JSON.stringify(r))}</code>`,
        kb([[{ t: "🪜 LEVEL PURCHASE", d: "m:passlevels" }], nav("m:pass")]),
      );
    }
    case "passlevellimit": {
      const value = Math.round(parseAmount(text));
      if (!Number.isFinite(value) || value < 0 || value > 30)
        throw new Error("KEEP_SESSION::⚠️ Envie um limite entre <code>0</code> e <code>30</code>.");
      const r = await rpc("admin_set_pass_level_purchase", {
        p_admin_id: ctx.adminId,
        p_patch: { daily_limit: value },
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ Limite diário = <b>${fmt(value)} níveis</b>\n<code>${esc(JSON.stringify(r))}</code>`,
        kb([[{ t: "🪜 LEVEL PURCHASE", d: "m:passlevels" }], nav("m:pass")]),
      );
    }
    case "pass": {
      const patch = JSON.parse(text);
      const { data: season } = await db
        .from("season_pass_seasons")
        .select("*")
        .eq("active", true)
        .order("start_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!season) return send(ctx, "⚠️ Nenhuma temporada ativa.", MAIN_MENU);
      const r = await rpc("admin_update_season_pass", {
        p_season_id: season.id,
        p_name: patch.name ?? season.name,
        p_start_at: patch.start_at ?? season.start_at,
        p_end_at: patch.end_at ?? season.end_at,
        p_levels: patch.levels ?? season.levels,
        p_xp_per_level: patch.xp_per_level ?? season.xp_per_level,
        p_adventurer_price: patch.adventurer_price_ton ?? season.adventurer_price_ton,
        p_legendary_price: patch.legendary_price_ton ?? season.legendary_price_ton,
        p_active: patch.active ?? season.active,
      });
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "pass.update",
        p_target_type: "season",
        p_target_id: season.id,
        p_old: season,
        p_new: r ?? patch,
        p_reason: "painel admin",
        p_context: {},
      });
      await rpc("admin_bump_settings_version", {});
      return send(ctx, "✅ Passe atualizado.", MAIN_MENU);
    }
    case "passreward": {
      const i = text.indexOf(" ");
      const id = text.slice(0, i);
      const patch = JSON.parse(text.slice(i + 1));
      const { data: old } = await db.from("season_pass_rewards").select("*").eq("id", id).maybeSingle();
      if (!old) return send(ctx, "⚠️ Recompensa não encontrada.", MAIN_MENU);
      await rpc("admin_update_season_reward", {
        p_reward_id: id,
        p_tier: patch.tier ?? old.tier,
        p_level: patch.level ?? old.level,
        p_type: patch.reward_type ?? old.reward_type,
        p_code: patch.reward_code ?? old.reward_code,
        p_amount: patch.amount ?? old.amount,
        p_title: patch.title ?? old.title,
        p_enabled: patch.enabled ?? old.enabled,
      });
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "pass.reward.update",
        p_target_type: "season_reward",
        p_target_id: id,
        p_old: old,
        p_new: patch,
        p_reason: "painel admin",
        p_context: {},
      });
      await rpc("admin_bump_settings_version", {});
      return send(ctx, "✅ Recompensa atualizada.", MAIN_MENU);
    }
    case "depok":
    case "depno": {
      const { data: rows } = await db.from("wallet_deposits").select("id").ilike("id", `${text}%`).limit(1);
      if (!rows?.length) return send(ctx, "⚠️ Depósito não encontrado.", MAIN_MENU);
      const r = await rpc("admin_review_deposit", {
        p_admin_id: ctx.adminId,
        p_deposit_id: rows[0].id,
        p_approve: key === "depok",
        p_tx_hash: null,
        p_reason: "painel admin",
      });
      return send(
        ctx,
        `✅ Depósito ${key === "depok" ? "confirmado" : "rejeitado"}.\n<code>${esc(JSON.stringify(r)).slice(0, 500)}</code>`,
        MAIN_MENU,
      );
    }
    case "tonrate": {
      const value = Number(text.replace(/[^\d.]/g, ""));
      if (!Number.isFinite(value) || value <= 0) return send(ctx, "⚠️ Taxa inválida.", MAIN_MENU);
      const { error } = await db.from("economy_settings").upsert(
        [
          { key: "ton_to_fc_rate", value_numeric: value, updated_at: new Date().toISOString() },
          { key: "fc_per_ton", value_numeric: value, updated_at: new Date().toISOString() },
        ],
        { onConflict: "key" },
      );
      if (error) return send(ctx, `⚠️ ${esc(error.message)}`, MAIN_MENU);
      await rpc("admin_log", {
        p_admin_id: ctx.adminId,
        p_action: "wallet.ton_fc_rate",
        p_target_type: "economy",
        p_target_id: null,
        p_old: null,
        p_new: { rate: value },
        p_reason: "alterado pelo painel",
        p_context: { financial: true },
      });
      return send(
        ctx,
        `✅ Nova taxa: <b>1 TON = ${fmt(value)} FC</b>\nAplica-se somente a depósitos confirmados a partir de agora.`,
        kb([[{ t: "💳 CARTEIRA", d: "m:wallet" }], nav()]),
      );
    }
    case "wdfee": {
      const value = Number(text.replace(",", ".").replace(/[^\d.]/g, ""));
      if (!Number.isFinite(value) || value < 0 || value > 50)
        return send(ctx, "⚠️ Informe um percentual entre 0 e 50.", MAIN_MENU);
      const r = await rpc("admin_set_withdraw_fee_percent", { p_admin_id: ctx.adminId, p_percent: value });
      return send(
        ctx,
        `✅ <b>WITHDRAWAL FEE</b> atualizada para <b>${Number(r.feePercent)}%</b>.\nSaques antigos mantêm a taxa usada na época.`,
        kb([[{ t: "💳 CARTEIRA", d: "m:wallet" }], nav()]),
      );
    }
    case "auditdep": {
      const p = await rpc("admin_player_detail", { p_admin_id: ctx.adminId, p_ref: text });
      return handleCallback(ctx, `audit1:${p.telegram_id}`);
    }
    case "wdpaid":
    case "wdno": {
      // Legacy prompts now open the detail card — payment/rejection always go through it.
      const id = await resolveWithdrawalId(text.split(/\s+/)[0]);
      if (!id)
        throw new Error("KEEP_SESSION::⚠️ Saque não encontrado (ou o prefixo é ambíguo). Envie mais caracteres do ID.");
      return withdrawalCard(ctx, id, false);
    }
    case "wdhash": {
      const [id] = args;
      const hash = text.split(/\s+/)[0];
      if (!hash || hash.length < 8)
        throw new Error("KEEP_SESSION::⚠️ Hash inválido. Envie o hash completo da transação TON.");
      await rpc("admin_withdrawal_mark_paid", { p_admin_id: ctx.adminId, p_withdrawal_id: id, p_tx_hash: hash });
      // Receipt goes to the payments channel automatically; a failure never reverts the payout.
      const posted = await announcePayout(ctx.adminId, id);
      await send(
        ctx,
        `✅ Saque marcado como <b>PAID</b>.\n${posted.status === "sent" ? "📢 Comprovante publicado no canal de pagamentos." : posted.status === "skipped" ? `🚫 Comprovante não publicado (${esc(posted.detail)}).` : `⚠️ Falha ao publicar o comprovante: <code>${esc(posted.detail)}</code> — use RETRY FAILED.`}`,
      );
      return withdrawalCard(ctx, id, false);
    }
    case "pachat": {
      const chat = text.trim().split(/\s+/)[0];
      if (!/^-?\d{5,}$|^@[\w]{4,}$/.test(chat))
        throw new Error(
          "KEEP_SESSION::⚠️ Envie o chat id numérico (ex.: <code>-1004303374351</code>) ou @canalpublico.",
        );
      await rpc("admin_set_setting", { p_admin_id: ctx.adminId, p_key: "payments_channel_chat_id", p_value: chat });
      await send(ctx, `✅ Canal de pagamentos salvo: <code>${esc(chat)}</code>`);
      return payoutMenu(ctx, false);
    }

    case "findwallet": {
      const d = await rpc("admin_connected_wallets", { p_admin_id: ctx.adminId, p_query: text, p_limit: 12 });
      if (!d.items?.length)
        throw new Error(
          "KEEP_SESSION::⚠️ Nenhuma carteira encontrada. Tente Telegram ID, @usuário, nome, endereço TON ou ID interno.",
        );
      return send(
        ctx,
        connectedWalletsText(d.items),
        kb([[{ t: "🔎 PESQUISAR", d: "ask:findwallet" }], nav("m:wallet")]),
      );
    }

    case "cast": {
      const seg = args[0];
      const t = await rpc("admin_broadcast_targets", { p_admin_id: ctx.adminId, p_segment: seg, p_limit: 2000 });
      return send(
        ctx,
        `📣 <b>Prévia</b> (${t.targets.length} destinatários — ${seg})\n\n${esc(text)}`,
        kb([
          [
            { t: "✅ ENVIAR", d: `castgo:${seg}:${encodeURIComponent(text).slice(0, 40)}` },
            { t: "❌ Cancelar", d: "home" },
          ],
        ]),
      );
    }
  }
  return send(ctx, "Comando não reconhecido.", MAIN_MENU);
}

const ERRORS: Record<string, string> = {
  unauthorized: DENIED,
  player_not_found: "⚠️ Jogador não encontrado. Tente Telegram ID, @usuário, nome, carteira ou ID interno.",
  season_not_found: "⚠️ Nenhuma temporada ativa do Battle Pass.",
  invalid_tier: "⚠️ Tipo de passe inválido.",
  hero_not_found: "⚠️ Herói não encontrado.",
  pet_not_found: "⚠️ Pet não encontrado.",
  reason_required: "⚠️ O motivo é obrigatório para esta ação.",
  already_confirmed: "⚠️ Este depósito já foi confirmado.",
  already_processed: "⚠️ Este saque já foi processado.",
  withdrawal_not_found: "⚠️ Saque não encontrado.",
  withdrawal_locked: "⚠️ Este saque já está em PROCESSING. Finalize com MARK AS PAID ou libere com PAGAMENTO FALHOU.",
  wallet_missing: "⚠️ WALLET NOT FOUND — MANUAL REVIEW REQUIRED. Este saque não tem carteira TON de destino.",
  invalid_amount: "⚠️ Valor de TON inválido neste saque.",
  tx_hash_required: "⚠️ Informe o hash da transação TON para marcar como pago.",
  tx_hash_already_used: "⚠️ Este hash já foi usado em outro saque.",
  not_processing: "⚠️ Este saque não está em processamento.",

  rates_must_total_100: "❌ Total inválido. A soma das raridades precisa ser exatamente 100%.",
  ancestral_not_summonable: "⛔ Ancestral é exclusivo de eventos e presentes do admin — a chance precisa ser 0%.",
  empty_pool_for_rarity:
    "⚠️ Nenhum herói ativo com Recruit habilitado nessa raridade. Cadastre um herói antes de definir a chance.",
  recruit_pool_unavailable: "⚠️ Nenhum herói disponível no pool de recrutamento.",
  invalid_price: "⚠️ Preço inválido. Use um número entre 1 e 1.000.000.000.",
  invalid_count: "⚠️ Pacote inválido. Use 1x, 5x ou 10x.",
  immutable_setting: "⚠️ O ID do administrador mestre não pode ser alterado pelo painel.",
};

Deno.serve(async (req) => {
  if (req.method === "GET") {
    const url = new URL(req.url);
    const action = ["setup", "resync", "diag", "selftest"].find((a) => url.searchParams.has(a));
    if (!action) return new Response("ok");
    // Every maintenance/diagnostic action is gated by the server-only setup key (fail closed).
    if (!setupKeyOk(url)) return new Response("Unauthorized", { status: 401 });

    const hookUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/admin-bot`;

    if (action === "setup") {
      const res = await tg("setWebhook", {
        url: hookUrl,
        allowed_updates: ["message", "callback_query"],
        drop_pending_updates: true,
        secret_token: WEBHOOK_SECRET,
      });
      const info = await tg("getWebhookInfo", {});
      return new Response(JSON.stringify({ setWebhook: res, info }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Safe self-heal: re-points the webhook at this very function with the server-side secret.
    if (action === "resync") {
      await tg("setWebhook", {
        url: hookUrl,
        allowed_updates: ["message", "callback_query"],
        secret_token: WEBHOOK_SECRET,
      });
      const info = await tg("getWebhookInfo", {});
      const r = info?.result ?? {};
      return new Response(
        JSON.stringify({
          ok: true,
          webhookMatches: r?.url === hookUrl,
          pendingUpdates: r?.pending_update_count ?? null,
          lastError: r?.last_error_message ?? null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Read-only diagnostics: never returns the token, the admin id, or secret state.
    if (action === "diag") {
      const me = await tg("getMe", {});
      const info = await tg("getWebhookInfo", {});
      const r = info?.result ?? {};
      return new Response(
        JSON.stringify(
          {
            ok: true,
            bot: me?.result ? { id: me.result.id, username: me.result.username } : null,
            tokenConfigured: Boolean(BOT_TOKEN),
            webhook: {
              url: r?.url ?? null,
              pending_update_count: r?.pending_update_count ?? null,
              last_error_message: r?.last_error_message ?? null,
              last_error_date: r?.last_error_date ?? null,
            },
          },
          null,
          2,
        ),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Server-side self test: renders the main menu straight to the super admin chat.
    const ctx: Ctx = { chatId: SUPER_ADMIN_ID, adminId: SUPER_ADMIN_ID };
    try {
      await clearSession(ctx).catch(() => {});
      await home(ctx);
      return new Response(JSON.stringify({ ok: true, sent: "main_menu" }), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (err) {
      return new Response(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : String(err) }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
  }
  if (req.method !== "POST") return new Response("ok");
  // Fail closed: a webhook secret always exists server-side and the header must match it.
  if (!secretMatches(req.headers.get("X-Telegram-Bot-Api-Secret-Token"))) {
    return new Response("Unauthorized", { status: 401 });
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
    if (cq) await tg("answerCallbackQuery", { callback_query_id: cq.id, text: DENIED, show_alert: true });
    else await tg("sendMessage", { chat_id: chatId, text: DENIED });
    return new Response(JSON.stringify({ ok: true }));
  }

  const ctx: Ctx = { chatId, adminId: requireAdmin(fromId), messageId: cq ? msg.message_id : undefined };

  try {
    if (cq) {
      await tg("answerCallbackQuery", { callback_query_id: cq.id });
      const data = String(cq.data || "");
      if (data.startsWith("norm:")) {
        const rates = JSON.parse(decodeURIComponent(data.slice(5)));
        const r = await rpc("admin_set_hero_rarity_rates", {
          p_admin_id: ctx.adminId,
          p_rates: rates,
          p_normalize: true,
          p_reason: "normalizado pelo painel",
        });
        await send(ctx, `✅ Raridades normalizadas:\n<code>${esc(JSON.stringify(r.rates))}</code>`, MAIN_MENU);
      } else {
        await handleCallback(ctx, data);
      }
      return new Response(JSON.stringify({ ok: true }));
    }

    // Hero wizard: the persisted step decides how the next message (text OR photo) is interpreted.
    // Menu commands are never triggered while a wizard step is waiting for an answer.
    const wiz = await getSession(ctx);
    if (wiz?.action === "petcms") {
      const wizText = String(update.message?.text || "").trim();
      const wizCmd = wizText.split(/\s+/)[0].replace(/@.*/, "").toLowerCase();
      if (!["/start", "/menu", "/admin", "/cancel"].includes(wizCmd)) {
        const photos = update.message?.photo as { file_id: string }[] | undefined;
        const doc = update.message?.document as { file_id: string; mime_type?: string } | undefined;
        const draft = wiz.context as never;
        try {
          if (photos?.length) await petCms.photo(ctx, wiz.step, draft, String(photos[photos.length - 1].file_id));
          else if (doc?.mime_type?.startsWith("image/")) await petCms.photo(ctx, wiz.step, draft, String(doc.file_id));
          else if (wizText) await petCms.text(ctx, wiz.step, draft, wizText);
          else
            await send(ctx, "⚠️ Envie um texto ou uma foto para continuar.", kb([[{ t: "❌ CANCELAR", d: "cancel" }]]));
        } catch (err) {
          const raw = err instanceof Error ? err.message : String(err);
          console.error("pet cms error:", raw);
          await send(
            ctx,
            `⚠️ Falha no editor de pets: <code>${esc(raw).slice(0, 300)}</code>`,
            kb([[{ t: "🐲 PET CMS", d: "pw:hub" }], nav()]),
          );
        }
        return new Response(JSON.stringify({ ok: true }));
      }
      await clearSession(ctx);
    }
    if (wiz?.action === "herowiz") {
      const wizText = String(update.message?.text || "").trim();
      const wizCmd = wizText.split(/\s+/)[0].replace(/@.*/, "").toLowerCase();
      if (!["/start", "/menu", "/admin", "/cancel"].includes(wizCmd)) {
        const photos = update.message?.photo as { file_id: string }[] | undefined;
        const doc = update.message?.document as { file_id: string; mime_type?: string } | undefined;
        const draft = wiz.context as Record<string, unknown>;
        try {
          if (photos?.length) {
            await heroWizardPhoto(ctx, wiz.step, draft as never, String(photos[photos.length - 1].file_id));
          } else if (doc?.mime_type?.startsWith("image/")) {
            await heroWizardPhoto(ctx, wiz.step, draft as never, String(doc.file_id));
          } else if (wizText) {
            await heroWizardText(ctx, wiz.step, draft as never, wizText);
          } else {
            await send(ctx, "⚠️ Envie um texto ou uma foto para continuar.", kb([[{ t: "❌ CANCELAR", d: "cancel" }]]));
          }
        } catch (err) {
          const raw = err instanceof Error ? err.message : String(err);
          console.error("hero wizard error:", raw);
          await send(
            ctx,
            `⚠️ Falha no assistente: <code>${esc(raw).slice(0, 300)}</code>`,
            kb([[{ t: "🦸 HERO MANAGEMENT", d: "m:heroes" }], nav()]),
          );
        }
        return new Response(JSON.stringify({ ok: true }));
      }
      await clearSession(ctx);
    }

    // Forwarded message from a channel/group: only informational (channel rewards no longer use chat ids).
    const forwarded = update.message?.forward_from_chat ?? update.message?.forward_origin?.chat;
    if (forwarded?.id) {
      const id = String(forwarded.id);
      await send(
        ctx,
        `🔗 <b>CHAT DETECTADO</b>\n${esc(forwarded.title || forwarded.username || "—")} (${esc(forwarded.type)})\nchat id: <code>${esc(id)}</code>\n\nAs recompensas dos canais oficiais são one-time por Telegram ID e não usam chat id.`,
        kb([[{ t: "💳 CANAL DE PAGAMENTOS", d: "ask:pachat" }], [{ t: "📡 CANAIS OFICIAIS", d: "m:channels" }], nav()]),
      );
      return new Response(JSON.stringify({ ok: true }));
    }

    const text = String(update.message?.text || "").trim();
    const cmdWord = text.split(/\s+/)[0].replace(/@.*/, "").toLowerCase();
    const isCommand = cmdWord.startsWith("/");

    // 1) pending conversation state wins over any normal command / menu fallback.
    // Legacy quoted "#cmd" prompts still work; the persisted session is the source of truth.
    const replied = String(update.message?.reply_to_message?.text || "");
    const quoted = replied.match(/#([^\s]+)\s*$/)?.[1];
    const session = quoted ? null : await getSession(ctx);
    const pending = quoted || session?.action || null;

    const GLOBAL_CMDS = ["/start", "/admin", "/menu", "/cancel"];
    console.log(
      JSON.stringify({
        ev: "update_received",
        telegram_user_id: fromId,
        message_id: update.message?.message_id ?? null,
        command: isCommand ? cmdWord : null,
        conversation_state: pending,
        handler_selected:
          isCommand && GLOBAL_CMDS.includes(cmdWord)
            ? "global_command"
            : pending
              ? "conversation_state"
              : "command_or_menu",
      }),
    );
    if (pending && !(isCommand && GLOBAL_CMDS.includes(cmdWord))) {
      try {
        await handlePrompt(ctx, pending, text);
        // Multi-step wizards (e.g. partner NAME -> REWARD -> LINK -> ...) advance the
        // session inside handlePrompt. Only clear it when no new step was queued.
        const next = await getSession(ctx);
        if (!next || next.action === pending) await clearSession(ctx);
      } catch (error) {
        const raw = error instanceof Error ? error.message : String(error);
        if (raw.startsWith("KEEP_SESSION::")) {
          // Validation error: keep the flow alive, never bounce back to the menu.
          await send(ctx, raw.slice("KEEP_SESSION::".length), kb([[{ t: "❌ CANCELAR", d: "cancel" }]]));
          return new Response(JSON.stringify({ ok: true }));
        }
        throw error;
      }
      return new Response(JSON.stringify({ ok: true }));
    }
    if (isCommand && cmdWord === "/cancel") {
      await clearSession(ctx);
      await send(ctx, "❌ Nenhuma ação pendente.", MAIN_MENU);
      return new Response(JSON.stringify({ ok: true }));
    }

    // 2) no pending action: normal commands, then the menu fallback.
    const cmd = cmdWord;
    const arg = text.slice(cmd.length).trim();
    const direct: Record<string, string> = {
      "/heroes": "heroes",
      "/shop": "shop",
      "/loja": "shop",
      "/pets": "pets",
      "/pvp": "pvp",
      "/pool": "pool",
      "/pass": "pass",
      "/invites": "invites",
      "/boss": "boss",
      "/audit": "audit",
      "/status": "status",
      "/wallet": "wallet",
      "/missions": "missions",
      "/ads": "ads",
      "/settings": "settings",
      "/broadcast": "cast",
    };
    if (cmd === "/start" || cmd === "/admin" || cmd === "/menu") {
      await clearSession(ctx).catch((e) => console.error("session clear ignored:", String(e)));
      await home(ctx);
      console.log(JSON.stringify({ ev: "handler_success", handler: "command_admin_menu", command: cmd }));
    } else if (cmd === "/user" || cmd === "/player") {
      arg ? await playerCard(ctx, arg) : await ask(ctx, "find", PROMPTS.find);
    } else if (cmd === "/balance") {
      arg ? await playerCard(ctx, arg) : await ask(ctx, "find", PROMPTS.find);
    } else if (cmd === "/ban") {
      arg ? await handleCallback(ctx, `ban:${arg}`) : await ask(ctx, "find", PROMPTS.find);
    } else if (cmd === "/maintenance") await module({ ...ctx, messageId: undefined }, "maint");
    else if (direct[cmd]) await module({ ...ctx, messageId: undefined }, direct[cmd]);
    else await home(ctx);
  } catch (error) {
    const raw = error instanceof Error ? error.message : String(error);
    const known = Object.keys(ERRORS).find((k) => raw.includes(k));
    console.error("admin-bot error:", raw);
    await clearSession(ctx).catch(() => {});
    await send(ctx, known ? ERRORS[known] : `⚠️ Falha: <code>${esc(raw).slice(0, 400)}</code>`, MAIN_MENU);
  }
  return new Response(JSON.stringify({ ok: true }));
});

// ---------------------------------------------------------------- ⚔️ PVP LEAGUE ARENA
// Main event slot: while the event is DRAFT the Community Pool keeps rendering in the app.
// Activation is manual, sets started_at server-side and freezes the prize table.
const PL_STATUS: Record<string, string> = {
  draft: "🟡 DRAFT",
  active: "🟢 ACTIVE",
  finished: "⚫ FINISHED",
  cancelled: "🚫 CANCELLED",
};
const plDate = (v: unknown) => (v ? String(v).slice(0, 16).replace("T", " ") : "NOT STARTED");

async function plHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_pvp_league_overview", { p_admin_id: ctx.adminId })) as any;
  const ev = d?.event ?? null;
  if (!ev) return send(ctx, "⚠️ Nenhum evento PVP LEAGUE encontrado.", kb([nav()]));
  const status = String(ev.status);
  const lines = [
    "⚔️ <b>PVP LEAGUE ARENA</b>",
    `Status: <b>${PL_STATUS[status] ?? esc(status)}</b>`,
    `Nome: <b>${esc(ev.name)}</b>`,
    `Prize Pool: <b>${fmt(ev.prize_pool_ton)} TON</b> (tabela ${fmt(d.rewardTotal)} TON)`,
    `Premiados: <b>TOP ${ev.top_limit}</b> · duração <b>${ev.duration_days} dias</b> · mín. ${ev.min_matches} partida(s)`,
    `Participants: <b>${fmt(d.participants)}</b> · partidas contadas <b>${fmt(d.matches)}</b>`,
    `Start: <code>${plDate(ev.started_at)}</code>`,
    `Ends: <code>${plDate(ev.ends_at)}</code>`,
    status === "draft"
      ? "\n🕒 A Community Pool continua ativa no app até você ativar este evento."
      : status === "active"
        ? "\n🟢 O evento ocupa o slot principal da Pool no app. Premiação e datas estão congeladas."
        : `\n💸 Pago: <b>${fmt(d.paidTotal)} TON</b>`,
  ];
  const rows =
    status === "draft"
      ? [
          [{ t: "⚔️ ATIVAR / TROCAR EVENTO", d: "pl:confirm:activate" }],
          [
            { t: "⚙️ CONFIGURAR", d: "pl:ask:plset" },
            { t: "🏆 PRÊMIOS", d: "pl:prizes" },
          ],
          [{ t: "❌ CANCELAR", d: "pl:confirm:cancel" }],
          nav(),
        ]
      : status === "active"
        ? [
            [{ t: "🏆 LIVE RANKING", d: "pl:rank" }],
            [{ t: "🔎 SEARCH PLAYER", d: "pl:ask:plfind" }],
            [
              { t: "📊 STATUS", d: "pl:hub" },
              { t: "🏆 PRÊMIOS", d: "pl:prizes" },
            ],
            [{ t: "⏹ END EVENT", d: "pl:confirm:end" }],
            nav(),
          ]
        : [
            [
              { t: "🏆 RANKING FINAL", d: "pl:rank" },
              { t: "🏆 PRÊMIOS", d: "pl:prizes" },
            ],
            [{ t: "🆕 NOVO RASCUNHO", d: "pl:confirm:cancel" }],
            nav(),
          ];
  const text = lines.join("\n");
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function plPrizes(ctx: Ctx) {
  const d = (await rpc("admin_pvp_league_overview", { p_admin_id: ctx.adminId })) as any;
  const rewards = (d?.rewards ?? []) as { rank: number; ton: number }[];
  if (!rewards.length) {
    return edit(
      ctx,
      "🏆 <b>PRÊMIOS</b>\n\nA tabela é gerada no momento da ativação.\n\n" +
        `Modelo: TOP 1–3 = 40% · TOP 4–10 = 30% · TOP 11–${d?.event?.top_limit ?? 50} = 30% do total de <b>${fmt(d?.event?.prize_pool_ton ?? 40)} TON</b>.`,
      kb([[{ t: "⬅️ Voltar", d: "pl:hub" }], nav()]),
    );
  }
  const line = (r: { rank: number; ton: number }) => `#${r.rank} — <b>${fmt(r.ton)} TON</b>`;
  const head = rewards
    .filter((r) => r.rank <= 10)
    .map(line)
    .join("\n");
  const tail = rewards.filter((r) => r.rank > 10);
  const total = rewards.reduce((sum, r) => sum + Number(r.ton || 0), 0);
  return edit(
    ctx,
    `🏆 <b>PRÊMIOS — PVP LEAGUE ARENA</b>\n\n${head}\n\n` +
      (tail.length
        ? `#11–#${tail[tail.length - 1].rank}: <b>${fmt(tail.reduce((s, r) => s + Number(r.ton || 0), 0))} TON</b> (linear, ${fmt(tail[0].ton)} → ${fmt(tail[tail.length - 1].ton)} TON)\n\n`
        : "") +
      `TOTAL: <b>${fmt(total)} TON</b>`,
    kb([[{ t: "⬅️ Voltar", d: "pl:hub" }], nav()]),
  );
}

async function plRanking(ctx: Ctx, query: string | null = null) {
  const d = (await rpc("admin_pvp_league_ranking", { p_admin_id: ctx.adminId, p_limit: 20, p_query: query })) as any;
  const rows = (d?.rows ?? []) as any[];
  const body = rows.length
    ? rows
        .map(
          (r) =>
            `#${r.position} · <code>${esc(r.telegramId)}</code> ${esc(r.name)}\n   ${fmt(r.score)} pts · ${fmt(r.wins)}W/${fmt(r.matches)} · ${fmt(r.rewardTon)} TON`,
        )
        .join("\n")
    : "Nenhum jogador pontuou ainda.";
  return edit(
    ctx,
    `🏆 <b>${query ? "BUSCA" : "LIVE RANKING"} — PVP LEAGUE</b>\n\n${body}`,
    kb([
      [
        { t: "🔄 Atualizar", d: "pl:rank" },
        { t: "🔎 BUSCAR", d: "pl:ask:plfind" },
      ],
      [{ t: "⬅️ Voltar", d: "pl:hub" }],
      nav(),
    ]),
  );
}

async function plCallback(ctx: Ctx, rest: string[]) {
  const sub = rest[0] || "hub";
  if (sub === "ask") return ask(ctx, rest[1], PROMPTS[rest[1]] || "Envie o valor.");
  if (sub === "prizes") return plPrizes(ctx);
  if (sub === "rank") return plRanking(ctx);
  if (sub === "confirm") {
    const action = rest[1];
    if (action === "activate") {
      const d = (await rpc("admin_pvp_league_overview", { p_admin_id: ctx.adminId })) as any;
      const ev = d?.event ?? {};
      return send(
        ctx,
        [
          "⚠️ <b>ACTIVATE PVP LEAGUE ARENA?</b>",
          "",
          "Current: <b>Community Pool</b>",
          `New: <b>${esc(ev.name)}</b>`,
          `Prize Pool: <b>${fmt(ev.prize_pool_ton)} TON</b> · TOP ${ev.top_limit}`,
          `Duração: <b>${ev.duration_days} dias</b>`,
          "",
          "O novo evento PvP começa a contar no momento exato da ativação (ranking do zero).",
          "O histórico e pagamentos da Community Pool são preservados.",
        ].join("\n"),
        kb([
          [
            { t: "✅ CONFIRMAR", d: "pl:run:activate" },
            { t: "❌ CANCELAR", d: "pl:hub" },
          ],
        ]),
      );
    }
    if (action === "end") {
      return send(
        ctx,
        "⚠️ <b>ENCERRAR O EVENTO AGORA?</b>\n\nO ranking será congelado e os prêmios creditados no saldo TON sacável dos vencedores.",
        kb([
          [
            { t: "✅ CONFIRMAR", d: "pl:run:end" },
            { t: "❌ CANCELAR", d: "pl:hub" },
          ],
        ]),
      );
    }
    return send(
      ctx,
      "⚠️ <b>CANCELAR ESTE EVENTO?</b>\n\nNenhum prêmio é pago e um novo rascunho é criado com a mesma configuração.",
      kb([
        [
          { t: "✅ CONFIRMAR", d: "pl:run:cancel" },
          { t: "❌ CANCELAR", d: "pl:hub" },
        ],
      ]),
    );
  }
  if (sub === "run") {
    const action = rest[1];
    const fn =
      action === "activate"
        ? "admin_pvp_league_activate"
        : action === "end"
          ? "admin_pvp_league_end"
          : "admin_pvp_league_cancel";
    const r = (await rpc(fn, { p_admin_id: ctx.adminId })) as any;
    await send(
      ctx,
      `✅ <b>${esc(action.toUpperCase())}</b> concluído.\n<code>${esc(JSON.stringify(r)).slice(0, 600)}</code>`,
    );
    return plHub({ ...ctx, messageId: undefined }, false);
  }
  return plHub(ctx);
}

async function plPrompt(ctx: Ctx, key: string, _args: string[], text: string) {
  if (key === "plfind") {
    await clearSession(ctx);
    return plRanking({ ...ctx, messageId: undefined }, text.trim());
  }
  const [field, ...valueParts] = text.trim().split(/\s+/);
  const raw = valueParts.join(" ");
  const allowed = ["name", "prize_pool_ton", "duration_days", "top_limit", "min_matches", "enabled"];
  if (!allowed.includes(field) || !raw) {
    throw new Error(`KEEP_SESSION::⚠️ Formato inválido. Use: <code>chave valor</code> (${allowed.join(", ")}).`);
  }
  const patch: Record<string, unknown> = {};
  if (field === "name") patch.name = raw;
  else if (field === "enabled") patch.enabled = ["1", "on", "true", "sim", "yes"].includes(raw.toLowerCase());
  else {
    const num = parseAmount(raw);
    if (!Number.isFinite(num) || num <= 0) throw new Error("KEEP_SESSION::⚠️ Valor numérico inválido.");
    patch[field] = num;
  }
  const ev = (await rpc("admin_pvp_league_configure", { p_admin_id: ctx.adminId, p_patch: patch })) as any;
  await clearSession(ctx);
  await send(
    ctx,
    `✅ <b>${esc(field)}</b> atualizado para <code>${esc(String(patch[field]))}</code>.\nStatus: ${PL_STATUS[String(ev.status)] ?? esc(ev.status)}`,
  );
  return plHub({ ...ctx, messageId: undefined }, false);
}

// ---------------------------------------------------------------- ⚔️ TACTICAL PVP (3V3)
// Global control of the Tactical Arena: feature flag, turn timer, ticket cost, skill
// balance and ranking. While the flag is OFF only the Super Admin can play it (test mode).
async function tpHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_tactical_overview", { p_admin_id: ctx.adminId })) as any;
  const c = d?.config ?? {};
  const on = c.enabled === true;
  const lines = [
    "⚔️ <b>TACTICAL PVP (3V3)</b>",
    `Status: <b>${on ? "🟢 ATIVO PARA TODOS" : "🔴 DESATIVADO (somente admin em teste)"}</b>`,
    `Equipe: <b>${c.teamSize ?? 3} heróis</b> · Deck: <b>${c.deckSize ?? 6} habilidades</b>`,
    `Turno: <b>${c.turnTimerSeconds ?? 15}s</b> · Reconexão: <b>${c.reconnectSeconds ?? 30}s</b>`,
    `Custo: <b>${c.ticketCost ?? 1} ticket</b> · Rating K: <b>${c.ratingK ?? 32}</b>`,
    `Anti-stalemate: <b>${c.stalemateTurns ?? 5} turnos</b> · +${Math.round(Number(c.stalemateEscalation ?? 0.1) * 100)}%/turno`,
    `Torneio: <b>${c.tournamentEnabled === true ? "ON" : "OFF"}</b> · Evento: <b>${esc(String(c.eventMode ?? "CLASSIC"))}</b>`,
    "",
    `Na fila: <b>${fmt(d.queue)}</b> · Partidas ativas: <b>${fmt(d.activeMatches)}</b>`,
    `Concluídas: <b>${fmt(d.finishedMatches)}</b> · Jogadores ranqueados: <b>${fmt(d.players)}</b>`,
    `Equipes montadas: <b>${fmt(d.teams)}</b>`,
  ];
  const rows = [
    [{ t: on ? "🔴 DESATIVAR MODO" : "🟢 ATIVAR MODO", d: `tp:toggle:${on ? "0" : "1"}` }],
    [
      { t: "⚙️ CONFIGURAR", d: "tp:ask:tpset" },
      { t: "✨ HABILIDADES", d: "tp:skills" },
    ],
    [
      { t: "🏆 RANKING", d: "tp:rank" },
      { t: "📜 PARTIDAS", d: "tp:matches" },
    ],
    [{ t: "♻️ RESETAR RATINGS", d: "tp:confirm:reset" }],
    nav(),
  ];
  const text = lines.join("\n");
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function tpSkills(ctx: Ctx) {
  const d = (await rpc("admin_tactical_overview", { p_admin_id: ctx.adminId })) as any;
  const skills = (d?.skills ?? []) as any[];
  const body = skills
    .map(
      (s) =>
        `${s.enabled ? "🟢" : "🔴"} <code>${esc(s.key)}</code> · ${esc(s.class)} · ${esc(s.type)}\n   x${fmt(s.mult)} · CD ${s.cd} · dur ${s.dur} · ${esc(s.target)}`,
    )
    .join("\n");
  return edit(
    ctx,
    `✨ <b>HABILIDADES TÁTICAS</b>\n\n${body || "Nenhuma habilidade cadastrada."}`,
    kb([[{ t: "✏️ EDITAR HABILIDADE", d: "tp:ask:tpskill" }], [{ t: "⬅️ Voltar", d: "tp:hub" }], nav()]),
  );
}

async function tpRanking(ctx: Ctx) {
  const rows = (await rpc("admin_tactical_ranking", { p_admin_id: ctx.adminId, p_limit: 20 })) as any[];
  const body = (rows ?? []).length
    ? (rows as any[])
        .map(
          (r, i) =>
            `#${i + 1} · <code>${esc(r.telegramId)}</code> ${esc(r.name)}\n   ${fmt(r.rating)} · ${esc(r.league)} · ${fmt(r.wins)}W/${fmt(r.losses)}L`,
        )
        .join("\n")
    : "Nenhum jogador ranqueado ainda.";
  return edit(
    ctx,
    `🏆 <b>RANKING TÁTICO</b>\n\n${body}`,
    kb([[{ t: "🔄 Atualizar", d: "tp:rank" }], [{ t: "⬅️ Voltar", d: "tp:hub" }], nav()]),
  );
}

async function tpMatches(ctx: Ctx) {
  const rows = (await rpc("admin_tactical_matches", { p_admin_id: ctx.adminId, p_limit: 15 })) as any[];
  const body = (rows ?? []).length
    ? (rows as any[])
        .map(
          (m) =>
            `${m.status === "active" ? "🟢" : m.winner ? "🏁" : "⚫"} ${esc(m.a)} vs ${esc(m.b)}${m.practice ? " (treino)" : ""}\n   turno ${m.turn} · ${m.winner ? `vencedor ${esc(m.winner)}` : esc(String(m.status))} · ${String(m.createdAt).slice(0, 16).replace("T", " ")}`,
        )
        .join("\n")
    : "Nenhuma partida registrada.";
  return edit(
    ctx,
    `📜 <b>PARTIDAS TÁTICAS</b>\n\n${body}`,
    kb([[{ t: "🔄 Atualizar", d: "tp:matches" }], [{ t: "⬅️ Voltar", d: "tp:hub" }], nav()]),
  );
}

async function tpCallback(ctx: Ctx, rest: string[]) {
  const sub = rest[0] || "hub";
  if (sub === "ask") return ask(ctx, rest[1], PROMPTS[rest[1]] || "Envie o valor.");
  if (sub === "skills") return tpSkills(ctx);
  if (sub === "rank") return tpRanking(ctx);
  if (sub === "matches") return tpMatches(ctx);
  if (sub === "toggle") {
    await rpc("admin_tactical_set", { p_admin_id: ctx.adminId, p_key: "enabled", p_value: rest[1] === "1" });
    await send(
      ctx,
      rest[1] === "1"
        ? "🟢 <b>TACTICAL PVP ATIVADO</b> para todos os jogadores."
        : "🔴 <b>TACTICAL PVP DESATIVADO</b>. Apenas o Super Admin continua acessando (modo de teste).",
    );
    return tpHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "confirm") {
    return send(
      ctx,
      "⚠️ <b>RESETAR TODOS OS RATINGS TÁTICOS?</b>\n\nPartidas ativas serão abandonadas, a fila é limpa e todos voltam ao rating inicial. A Arena Clássica (5v5) não é afetada.",
      kb([
        [
          { t: "✅ CONFIRMAR", d: "tp:run:reset" },
          { t: "❌ CANCELAR", d: "tp:hub" },
        ],
      ]),
    );
  }
  if (sub === "run") {
    await rpc("admin_tactical_reset", { p_admin_id: ctx.adminId });
    await send(ctx, "♻️ <b>Ratings táticos resetados.</b>");
    return tpHub({ ...ctx, messageId: undefined }, false);
  }
  return tpHub(ctx);
}

async function tpPrompt(ctx: Ctx, key: string, text: string) {
  const parts = text.trim().split(/\s+/);
  if (key === "tpset") {
    const [field, raw] = [parts[0], parts.slice(1).join(" ")];
    const allowed = [
      "turnTimerSeconds",
      "ticketCost",
      "reconnectSeconds",
      "stalemateTurns",
      "stalemateEscalation",
      "ratingK",
      "deckSize",
      "tournamentEnabled",
      "eventMode",
    ];
    if (!allowed.includes(field) || !raw)
      throw new Error(`KEEP_SESSION::⚠️ Formato inválido. Use: <code>chave valor</code> (${allowed.join(", ")}).`);
    let value: unknown;
    if (field === "tournamentEnabled") value = ["1", "on", "true", "sim", "yes"].includes(raw.toLowerCase());
    else if (field === "eventMode") value = raw.toUpperCase();
    else {
      const num = Number(String(raw).replace(",", "."));
      if (!Number.isFinite(num) || num <= 0) throw new Error("KEEP_SESSION::⚠️ Valor numérico inválido.");
      value = num;
    }
    await rpc("admin_tactical_set", { p_admin_id: ctx.adminId, p_key: field, p_value: value });
    await clearSession(ctx);
    await send(ctx, `✅ <b>${esc(field)}</b> = <code>${esc(String(value))}</code>.`);
    return tpHub({ ...ctx, messageId: undefined }, false);
  }
  const [skillKey, field, raw] = parts;
  if (!skillKey || !field || raw === undefined)
    throw new Error("KEEP_SESSION::⚠️ Use: <code>skill_key campo valor</code>.");
  if (!["multiplier", "cooldown", "duration", "enabled"].includes(field))
    throw new Error("KEEP_SESSION::⚠️ Campo inválido (multiplier, cooldown, duration, enabled).");
  const num =
    field === "enabled"
      ? ["1", "on", "true", "sim", "yes"].includes(raw.toLowerCase())
        ? 1
        : 0
      : Number(String(raw).replace(",", "."));
  if (!Number.isFinite(num)) throw new Error("KEEP_SESSION::⚠️ Valor numérico inválido.");
  await rpc("admin_tactical_skill_set", {
    p_admin_id: ctx.adminId,
    p_skill_key: skillKey,
    p_field: field,
    p_value: num,
  });
  await clearSession(ctx);
  await send(ctx, `✅ <code>${esc(skillKey)}</code> · <b>${esc(field)}</b> = <code>${esc(String(num))}</code>.`);
  return tpSkills({ ...ctx, messageId: undefined });
}

// ─────────────────────────────────────────────────────────────────────────────
// 🏰 CLAN WAR (20v20) — feature flag, roster/phase timings, scoring, seasons.
// Every value is stored in game_settings and read live by clan_war_cfg().
// ─────────────────────────────────────────────────────────────────────────────
const CW_BOOL_KEYS = ["matchmaking", "tonSeasonPrize"];
const CW_NUM_KEYS = [
  "rosterSize",
  "attacksPerPlayer",
  "preparationHours",
  "battleHours",
  "seasonWeeks",
  "baseRating",
  "pointsWin",
  "pointsPerfect",
  "pointsUpsetMax",
  "pointsLoss",
  "defenderMaxDefeats",
  "conqueredPercent",
  "sectorBonusPercent",
];

async function cwHub(ctx: Ctx, useEdit = true) {
  const d = (await rpc("admin_clan_war_overview", { p_admin_id: ctx.adminId })) as any;
  const c = d?.config ?? {};
  const s = d?.season ?? null;
  const counts = d?.counts ?? {};
  const on = c.enabled === true;
  const lines = [
    "🏰 <b>CLAN WAR (20V20)</b>",
    `Status: <b>${on ? "🟢 ATIVA" : "🔴 DESATIVADA"}</b> · Matchmaking: <b>${c.matchmaking === true ? "ON" : "OFF"}</b>`,
    `Tropa: <b>${c.rosterSize ?? 20}</b> · Ataques/jogador: <b>${c.attacksPerPlayer ?? 2}</b>`,
    `Preparação: <b>${c.preparationHours ?? 12}h</b> · Batalha: <b>${c.battleHours ?? 24}h</b>`,
    `Pontos: vitória <b>${c.pointsWin ?? 100}</b> · perfeito <b>+${c.pointsPerfect ?? 20}</b> · upset máx <b>+${c.pointsUpsetMax ?? 30}</b> · derrota <b>${c.pointsLoss ?? 10}</b>`,
    `Defensor cai em <b>${c.defenderMaxDefeats ?? 2}</b> derrotas · setor conquistado paga <b>${c.conqueredPercent ?? 25}%</b> · bônus setor <b>+${c.sectorBonusPercent ?? 5}%</b>`,
    "",
    s
      ? `Temporada: <b>${esc(String(s.name))}</b> (${esc(String(s.code))})\nTermina: <b>${String(s.ends_at).slice(0, 16).replace("T", " ")}</b> · Prêmio: <b>${s.ton_prize_enabled ? `${Number(s.ton_prize_ton).toFixed(2)} TON` : "OFF"}</b>`
      : "Temporada: <b>nenhuma ativa</b>",
    "",
    `Fila: <b>${fmt(counts.searching)}</b> · Preparação: <b>${fmt(counts.preparation)}</b> · Batalha: <b>${fmt(counts.battle)}</b> · Encerradas: <b>${fmt(counts.finished)}</b>`,
  ];
  const rows = [
    [{ t: on ? "🔴 DESATIVAR GUERRA" : "🟢 ATIVAR GUERRA", d: `cw:toggle:${on ? "0" : "1"}` }],
    [
      { t: "⚙️ CONFIGURAR", d: "cw:ask:cwset" },
      { t: "🔀 MATCHMAKING", d: `cw:mm:${c.matchmaking === true ? "0" : "1"}` },
    ],
    [
      { t: "⚔️ GUERRAS", d: "cw:wars" },
      { t: "🏆 RANKING", d: "cw:rank" },
    ],
    [
      { t: "🗓 NOVA TEMPORADA", d: "cw:ask:cwseason" },
      { t: "🏁 ENCERRAR TEMPORADA", d: "cw:season_finish" },
    ],
    [{ t: "⏱ RODAR TICK AGORA", d: "cw:tick" }],
    [{ t: "♻️ RESETAR RATINGS", d: "cw:confirm:reset" }],
    nav(),
  ];
  const text = lines.join("\n");
  return useEdit ? edit(ctx, text, kb(rows)) : send(ctx, text, kb(rows));
}

async function cwWars(ctx: Ctx) {
  const d = (await rpc("admin_clan_war_overview", { p_admin_id: ctx.adminId })) as any;
  const wars = (d?.wars ?? []) as any[];
  const body = wars.length
    ? wars
        .map((w) => {
          const icon =
            w.status === "battle"
              ? "⚔️"
              : w.status === "preparation"
                ? "🛠"
                : w.status === "searching"
                  ? "🔎"
                  : w.settled
                    ? "🏁"
                    : "⚫";
          return `${icon} <b>[${esc(w.clanA)}] ${fmt(w.scoreA)} × ${fmt(w.scoreB)} [${esc(w.clanB)}]</b>\n   ${esc(String(w.status))} · <code>${esc(String(w.warId))}</code>`;
        })
        .join("\n")
    : "Nenhuma guerra registrada.";
  const rows = wars
    .filter((w) => ["searching", "preparation", "battle"].includes(String(w.status)))
    .slice(0, 4)
    .map((w) => [
      { t: `🏁 LIQUIDAR ${w.clanA}v${w.clanB}`, d: `cw:settle:${w.warId}` },
      { t: "❌ CANCELAR", d: `cw:cancel:${w.warId}` },
    ]);
  return edit(
    ctx,
    `⚔️ <b>GUERRAS DE CLÃ</b>\n\n${body}`,
    kb([...rows, [{ t: "🔄 Atualizar", d: "cw:wars" }], [{ t: "⬅️ Voltar", d: "cw:hub" }], nav()]),
  );
}

async function cwRanking(ctx: Ctx) {
  const d = (await rpc("admin_clan_war_overview", { p_admin_id: ctx.adminId })) as any;
  const rows = (d?.ranking ?? []) as any[];
  const body = rows.length
    ? rows
        .map(
          (r, i) =>
            `#${i + 1} <b>[${esc(r.tag)}] ${esc(r.name)}</b>\n   ${fmt(r.rating)} · ${esc(r.league)} · ${fmt(r.wins)}W/${fmt(r.losses)}L`,
        )
        .join("\n")
    : "Nenhum clã ranqueado.";
  return edit(
    ctx,
    `🏆 <b>RANKING CLAN WAR</b>\n\n${body}`,
    kb([[{ t: "🔄 Atualizar", d: "cw:rank" }], [{ t: "⬅️ Voltar", d: "cw:hub" }], nav()]),
  );
}

async function cwCallback(ctx: Ctx, rest: string[]) {
  const sub = rest[0] || "hub";
  if (sub === "ask") return ask(ctx, rest[1], PROMPTS[rest[1]] || "Envie o valor.");
  if (sub === "wars") return cwWars(ctx);
  if (sub === "rank") return cwRanking(ctx);
  if (sub === "toggle") {
    await rpc("admin_clan_war_set", { p_admin_id: ctx.adminId, p_key: "enabled", p_value: rest[1] === "1" });
    await send(ctx, rest[1] === "1" ? "🟢 <b>CLAN WAR ATIVADA.</b>" : "🔴 <b>CLAN WAR DESATIVADA.</b>");
    return cwHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "mm") {
    await rpc("admin_clan_war_set", { p_admin_id: ctx.adminId, p_key: "matchmaking", p_value: rest[1] === "1" });
    return cwHub(ctx);
  }
  if (sub === "tick") {
    const res = (await rpc("admin_clan_war_action", { p_admin_id: ctx.adminId, p_action: "tick" })) as any;
    await send(ctx, `⏱ <b>Tick executado.</b>\n<code>${esc(JSON.stringify(res ?? {}).slice(0, 500))}</code>`);
    return cwHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "settle" || sub === "cancel") {
    await rpc("admin_clan_war_action", { p_admin_id: ctx.adminId, p_action: sub, p_ref: rest[1] });
    await send(ctx, sub === "settle" ? "🏁 <b>Guerra liquidada.</b>" : "❌ <b>Guerra cancelada.</b>");
    return cwHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "season_finish") {
    await rpc("admin_clan_war_action", { p_admin_id: ctx.adminId, p_action: "season_finish" });
    await send(ctx, "🏁 <b>Temporada encerrada.</b>");
    return cwHub({ ...ctx, messageId: undefined }, false);
  }
  if (sub === "confirm") {
    return send(
      ctx,
      "⚠️ <b>RESETAR TODOS OS RATINGS DE CLAN WAR?</b>\n\nVitórias, derrotas e pontos acumulados voltam a zero e todos os clãs retornam ao rating inicial.",
      kb([
        [
          { t: "✅ CONFIRMAR", d: "cw:run:reset" },
          { t: "❌ CANCELAR", d: "cw:hub" },
        ],
      ]),
    );
  }
  if (sub === "run") {
    await rpc("admin_clan_war_action", { p_admin_id: ctx.adminId, p_action: "reset_ratings" });
    await send(ctx, "♻️ <b>Ratings de Clan War resetados.</b>");
    return cwHub({ ...ctx, messageId: undefined }, false);
  }
  return cwHub(ctx);
}

async function cwPrompt(ctx: Ctx, key: string, text: string) {
  if (key === "cwseason") {
    const [rawName, rawPrize] = text.split("|");
    const name = (rawName || "").trim().slice(0, 40);
    const prize = Number(
      String(rawPrize || "0")
        .replace(",", ".")
        .replace(/[^\d.]/g, ""),
    );
    if (!name) throw new Error("KEEP_SESSION::⚠️ Use: <code>nome | prêmio_ton</code>.");
    if (!Number.isFinite(prize) || prize < 0) throw new Error("KEEP_SESSION::⚠️ Prêmio em TON inválido.");
    const res = (await rpc("admin_clan_war_action", {
      p_admin_id: ctx.adminId,
      p_action: "season_start",
      p_ref: null,
      p_payload: { name, prizeTon: prize },
    })) as any;
    await clearSession(ctx);
    await send(
      ctx,
      `🗓 <b>Nova temporada aberta</b> — ${esc(name)} · ${res?.weeks ?? "?"} semanas · prêmio ${prize.toFixed(2)} TON.`,
    );
    return cwHub({ ...ctx, messageId: undefined }, false);
  }

  const parts = text.trim().split(/\s+/);
  const field = parts[0];
  const raw = parts.slice(1).join(" ");
  if (!raw || (!CW_NUM_KEYS.includes(field) && !CW_BOOL_KEYS.includes(field))) {
    throw new Error(
      `KEEP_SESSION::⚠️ Formato inválido. Use: <code>chave valor</code> (${[...CW_NUM_KEYS, ...CW_BOOL_KEYS].join(", ")}).`,
    );
  }
  let value: unknown;
  if (CW_BOOL_KEYS.includes(field)) value = ["1", "on", "true", "sim", "yes"].includes(raw.toLowerCase());
  else {
    const num = Number(String(raw).replace(",", "."));
    if (!Number.isFinite(num) || num < 0) throw new Error("KEEP_SESSION::⚠️ Valor numérico inválido.");
    value = num;
  }
  await rpc("admin_clan_war_set", { p_admin_id: ctx.adminId, p_key: field, p_value: value });
  await clearSession(ctx);
  await send(ctx, `✅ <b>${esc(field)}</b> = <code>${esc(String(value))}</code>.`);
  return cwHub({ ...ctx, messageId: undefined }, false);
}
