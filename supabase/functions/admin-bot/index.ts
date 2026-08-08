// Forge Village :: Master Admin Bot (Telegram)
// Every operation re-validates the super admin Telegram ID server-side (bot + database).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPER_ADMIN_ID = Number(Deno.env.get('TELEGRAM_SUPER_ADMIN_ID') || '8118569391');
const BOT_TOKEN = Deno.env.get('TELEGRAM_ADMIN_BOT_TOKEN') || Deno.env.get('TELEGRAM_BOT_TOKEN') || '';
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
  if (!res.ok) console.error(`telegram ${method} failed [${res.status}]: ${await res.text()}`);
  else await res.json().catch(() => null);
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
  [{ t: '🤝 CONVITES', d: 'm:invites' }, { t: '🏪 LOJA', d: 'm:shop' }],
  [{ t: '💳 CARTEIRA / FC', d: 'm:wallet' }, { t: '🎯 MISSÕES', d: 'm:missions' }],
  [{ t: '👑 BOSS', d: 'm:boss' }, { t: '📢 ANÚNCIOS', d: 'm:ads' }],
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
/** Stateless prompt: the next reply carries the pending command inside the quoted message. */
async function ask(ctx: Ctx, cmd: string, question: string) {
  await tg('sendMessage', {
    chat_id: ctx.chatId,
    text: `${question}\n\n<code>#${cmd}</code>`,
    parse_mode: 'HTML',
    reply_markup: { force_reply: true, input_field_placeholder: 'Digite o valor' },
  });
}

// ---------------------------------------------------------------- views
async function home(ctx: Ctx, editing = false) {
  const text = '🎮 <b>FORGE VILLAGE ADMIN</b>\nControle total do jogo. Escolha um módulo:';
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
    `💼 Carteira: <code>${esc(p.wallet || '—')}</code>`,
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
    nav('m:users'),
  ]);
  if (p.avatar_url) await tg('sendPhoto', { chat_id: ctx.chatId, photo: p.avatar_url, caption: lines.join('\n'), parse_mode: 'HTML', reply_markup: markup });
  else await send(ctx, lines.join('\n'), markup);
}

async function module(ctx: Ctx, name: string) {
  switch (name) {
    case 'users':
      return edit(ctx, '👥 <b>USUÁRIOS</b>\nBusque por Telegram ID, @usuário, nome, carteira ou ID interno.',
        kb([[{ t: '🔎 PROCURAR', d: 'ask:find' }], [{ t: '🆕 ÚLTIMOS ACESSOS', d: 'find:' }], nav()]));
    case 'heroes': {
      const d = await rpc('admin_list_heroes', { p_admin_id: ctx.adminId, p_limit: 20, p_offset: 0 });
      const rates = (await rpc('admin_get_settings', { p_admin_id: ctx.adminId, p_category: 'heroes' })).settings?.[0]?.value ?? {};
      const list = d.heroes.map((h: any) => `• <code>${esc(h.hero_key)}</code> ${esc(h.name)} — ${esc(h.rarity)} ${h.enabled ? '✅' : '⛔'}${h.in_shop ? ' 🏪' : ''} ${h.price_fc ? fmt(h.price_fc) + ' FC' : ''}`).join('\n');
      return edit(ctx, `🦸 <b>HERÓIS</b> (${d.total})\n${list}\n\n🎲 Raridades: <code>${esc(JSON.stringify(rates))}</code>`,
        kb([[{ t: '✏️ CRIAR/EDITAR', d: 'ask:hero' }], [{ t: '🎲 RARIDADES', d: 'ask:rates' }], [{ t: '🦸 DAR A USUÁRIO', d: 'ask:granthero' }], nav()]));
    }
    case 'shop': {
      const d = await rpc('admin_list_heroes', { p_admin_id: ctx.adminId, p_limit: 30, p_offset: 0 });
      const shop = d.heroes.filter((h: any) => h.in_shop);
      return edit(ctx, `🏪 <b>LOJA</b>\n${shop.length ? shop.map((h: any) => `• ${esc(h.name)} — ${fmt(h.price_fc)} FC / ${h.price_ton ?? '—'} TON · ordem ${h.sort_order}${h.featured ? ' ⭐' : ''}`).join('\n') : 'Nenhum item na loja.'}\n\nUse EDITAR HERÓI com <code>in_shop</code>, <code>price_fc</code>, <code>price_ton</code>, <code>discount_percent</code>, <code>stock</code>, <code>sort_order</code>, <code>featured</code>, <code>available_until</code>.`,
        kb([[{ t: '✏️ EDITAR ITEM', d: 'ask:hero' }], nav()]));
    }
    case 'pets': {
      const list = await rpc('admin_list_pets', { p_admin_id: ctx.adminId, p_limit: 30, p_offset: 0 });
      const cfg = await rpc('admin_pet_config', { p_admin_id: ctx.adminId });
      return edit(ctx, `🐲 <b>PETS</b> (${list.total})\n${list.pets.map((p: any) => `• <code>${esc(p.slug)}</code> ${esc(p.name)} — ${esc(p.category)} ${p.is_enabled ? '✅' : '⛔'}`).join('\n')}\n\n🥚 Ovos: ${cfg.eggs.length} · 🍖 Comidas: ${cfg.food.length} · 🧬 Estágios: ${cfg.tiers.length}`,
        kb([[{ t: '✏️ CRIAR/EDITAR PET', d: 'ask:pet' }], [{ t: '🍖 COMIDAS', d: 'ask:food' }, { t: '🥚 OVOS', d: 'view:eggs' }],
            [{ t: '🧬 EVOLUÇÃO', d: 'view:tiers' }], [{ t: '🐲 DAR PET', d: 'ask:grantpet' }], nav()]));
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
        kb([[{ t: '💰 PREÇOS/DATAS', d: 'ask:pass' }], [{ t: '🎁 RECOMPENSA', d: 'ask:passreward' }], nav()]));
    }
    case 'pool': {
      const d = await rpc('admin_pool_overview', { p_admin_id: ctx.adminId });
      const p = d.pool || {};
      return edit(ctx, `💰 <b>POOL</b>\n${esc(p.week_label)} · saldo <b>${fmt(p.balance_ton)} TON</b>\nDistribuição: ${String(p.ends_at).slice(0, 16).replace('T', ' ')}\nParticipantes ${fmt(d.participants)} · Elegíveis ${fmt(d.eligible)}\nMínimo ${d.settings?.minimum_points} pts · ranking ${d.settings?.ranking_share_percent}% · sorteio ${d.settings?.lottery_share_percent}%`,
        kb([[{ t: '➕ VALOR', d: 'pool:add' }, { t: '➖ VALOR', d: 'pool:remove' }],
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
      const wd = await rpc('admin_list_transactions', { p_admin_id: ctx.adminId, p_kind: 'withdrawal', p_status: null, p_limit: 8 });
      const row = (t: any) => `• <code>${String(t.id).slice(0, 8)}</code> ${esc(t.player)} — ${fmt(t.amount_ton)} TON [${esc(t.status)}]`;
      return edit(ctx, `💳 <b>CARTEIRA</b>\n\n<b>Depósitos</b>\n${dep.items.map(row).join('\n') || '—'}\n\n<b>Saques</b>\n${wd.items.map(row).join('\n') || '—'}`,
        kb([[{ t: '✅ CONFIRMAR DEPÓSITO', d: 'ask:depok' }, { t: '❌ REJEITAR', d: 'ask:depno' }],
            [{ t: '💸 PAGAR SAQUE', d: 'ask:wdpaid' }, { t: '❌ REJEITAR SAQUE', d: 'ask:wdno' }],
            [{ t: '🪙 AJUSTAR FC', d: 'ask:find' }], nav()]));
    }
    case 'missions': {
      const d = await rpc('admin_missions_overview', { p_admin_id: ctx.adminId });
      return edit(ctx, `🎯 <b>MISSÕES</b>\n${d.missions.map((m: any) => `• <code>${esc(m.code)}</code> [${esc(m.scope)}] ${esc(m.title)} → ${fmt(m.reward_amount)} ${esc(m.reward_type)} ${m.enabled ? '✅' : '⛔'}`).join('\n') || '—'}`,
        kb([[{ t: '✏️ CRIAR/EDITAR', d: 'ask:mission' }], [{ t: '♻️ RESETAR DIÁRIAS', d: 'confirm:missdaily' }, { t: '♻️ SEMANAIS', d: 'confirm:missweekly' }], nav()]));
    }
    case 'boss': {
      const d = await rpc('admin_boss_overview', { p_admin_id: ctx.adminId });
      return edit(ctx, `👑 <b>BOSS</b>\n${d.templates.map((b: any) => `• <code>${esc(b.code)}</code> ${esc(b.name)} NV${b.level} — ${fmt(b.max_hp)} HP · ATK ${fmt(b.attack)} · 🎁 ${fmt(b.reward_amount)} ${b.active ? '🟢' : '⚪'}`).join('\n')}\nCombates ativos: ${fmt(d.active_combats)}\n\n<b>Top dano</b>\n${d.top_damage.map((t: any) => `• ${esc(t.name)} — ${fmt(t.damage)}`).join('\n') || '—'}`,
        kb([[{ t: '✏️ CRIAR/EDITAR', d: 'ask:boss' }], [{ t: '⚡ SPAWN', d: 'ask:bossspawn' }],
            [{ t: '🛑 ENCERRAR', d: 'confirm:bossend' }, { t: '❤️ RESETAR HP', d: 'confirm:bosshp' }], nav()]));
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

// ---------------------------------------------------------------- prompts
const PROMPTS: Record<string, string> = {
  find: 'Envie Telegram ID, @usuário, nome, carteira ou ID interno.',
  hero: 'Envie: <code>hero_key {json}</code>\nEx.: <code>pyro_knight {"name":"Cavaleiro Ígneo","rarity":"epico","price_fc":50000,"in_shop":true,"sort_order":1}</code>',
  rates: 'Envie as chances em JSON (total 100). Ex.: <code>{"comum":45,"incomum":25,"raro":15,"epico":8,"lendario":5,"mitico":1.5,"ancestral":0.5}</code>',
  granthero: 'Envie: <code>usuário hero_key [nível]</code>',
  pet: 'Envie: <code>slug {json}</code> — ex.: <code>pyron {"name":"Pyron","category":"fire","is_enabled":true}</code>',
  food: 'Envie: <code>code {json}</code> — ex.: <code>racao {"name":"Ração","xp_value":50,"rarity":"comum","enabled":true}</code>',
  grantpet: 'Envie: <code>usuário slug [raridade] [nível]</code>',
  pvpset: 'Envie: <code>chave valor</code>\nChaves: pvp_trophy_win, pvp_trophy_loss, pvp_ticket_cost, pvp_ticket_start, pvp_ticket_max, pvp_ticket_regen_minutes, pvp_ticket_price_fc, pvp_win_reward_fc',
  league: 'Envie: <code>code {json}</code> — ex.: <code>bronze_5 {"name":"Bronze V","min_trophies":0,"max_trophies":19}</code>',
  setting: 'Envie: <code>chave valor</code> (valor JSON ou texto simples).',
  mission: 'Envie: <code>code {json}</code> — ex.: <code>daily_pvp_wins {"title":"Vença 3 batalhas","target_amount":3,"reward_amount":4000,"enabled":true}</code>',
  boss: 'Envie: <code>code {json}</code> — ex.: <code>golem_ancestral {"name":"Golem","max_hp":50000,"attack":300,"reward_amount":9000}</code>',
  bossspawn: 'Envie o <code>code</code> do chefe para spawnar.',
  ads: 'Envie: <code>code {json}</code> — ex.: <code>adsgram {"enabled":true,"daily_limit":15,"reward_fc":800}</code>',
  pass: 'Envie JSON com os campos do passe: <code>{"adventurer_price_ton":15,"legendary_price_ton":30,"levels":30,"xp_per_level":1000}</code>',
  passreward: 'Envie: <code>reward_id {json}</code> — ex.: <code>uuid {"amount":5000,"title":"5.000 FC","enabled":true}</code>',
  poolset: 'Envie: <code>chave valor</code> — minimum_points, ranking_share_percent, lottery_share_percent, ranking_winner_limit, lottery_winner_count, season_days',
  tree: 'Envie o usuário para ver a árvore de convites.',
  unlink: 'Envie: <code>usuário motivo</code> para remover o vínculo de indicação.',
  depok: 'Envie o ID do depósito (pode ser o prefixo mostrado).',
  depno: 'Envie o ID do depósito a rejeitar.',
  wdpaid: 'Envie: <code>id [tx_hash]</code> para marcar o saque como pago.',
  wdno: 'Envie o ID do saque a rejeitar.',
  maintmsg: 'Envie a nova mensagem de manutenção.',
};

// ---------------------------------------------------------------- actions
async function handleCallback(ctx: Ctx, data: string) {
  const [head, ...rest] = data.split(':');

  if (data === 'home') return home(ctx, true);
  if (head === 'm') return module(ctx, rest[0]);
  if (head === 'ask') { const k = rest[0]; return ask(ctx, k, PROMPTS[k] || 'Envie o valor.'); }
  if (head === 'find') return playerCard(ctx, rest.join(':') || '');
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
  if (head === 'hist') {
    const h = await rpc('admin_player_history', { p_admin_id: ctx.adminId, p_ref: rest[0], p_limit: 15 });
    return send(ctx, `📜 <b>Histórico</b>\n${h.events.map((e: any) => `• ${String(e.at).slice(5, 16).replace('T', ' ')} ${esc(e.action)} — ${esc(JSON.stringify(e.old))} → ${esc(JSON.stringify(e.new))}`).join('\n') || '—'}`, MAIN_MENU);
  }
  if (head === 'tree') {
    const t = await rpc('admin_referral_tree', { p_admin_id: ctx.adminId, p_ref: rest[0] });
    const lines = t.levels.map((l: any) => `${'   '.repeat(l.level - 1)}└ N${l.level} ${esc(l.user.name)} ${l.user.username ? '@' + esc(l.user.username) : ''} — ${fmt(l.user.deposited_ton)} TON`);
    return send(ctx, `🌳 <b>Árvore de convites</b>\n${lines.join('\n') || '—'}\n\n💸 Comissão total: <b>${fmt(t.total_commission_fc)} FC</b>\n${t.commissions.map((c: any) => `• N${c.level} ${fmt(c.amount_fc)} FC de ${esc(c.from)}`).join('\n')}`, MAIN_MENU);
  }
  if (head === 'ref') return ask(ctx, `ref|${rest[0]}`, `Envie a nova porcentagem do nível ${rest[0]} (0-100).`);
  if (head === 'pool') return ask(ctx, `pool|${rest[0]}`, `Envie o valor em TON para ${rest[0] === 'add' ? 'adicionar' : 'remover'}.`);
  if (head === 'rank') {
    const d = await rpc('admin_pvp_overview', { p_admin_id: ctx.adminId, p_top: Number(rest[0]) });
    return send(ctx, `📈 <b>TOP ${rest[0]}</b>\n${d.ranking.map((r: any, i: number) => `${i + 1}. ${esc(r.name)} — ${fmt(r.trophies)}🏆`).join('\n').slice(0, 3500)}`, MAIN_MENU);
  }
  if (head === 'view') {
    const cfg = await rpc('admin_pet_config', { p_admin_id: ctx.adminId });
    if (rest[0] === 'eggs') return send(ctx, `🥚 <b>OVOS</b>\n${cfg.eggs.map((e: any) => `• ${esc(e.name)} <code>${e.id}</code> — ${fmt(e.price_fc)} FC / ${e.price_ton ?? '—'} TON ${e.is_enabled ? '✅' : '⛔'}\n   ${esc(JSON.stringify(e.rarity_rates))}`).join('\n')}`, MAIN_MENU);
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
    case 'find': return playerCard(ctx, text);
    case 'tree': return handleCallback(ctx, `tree:${text}`);
    case 'bal': {
      const [cur, mode, user] = args;
      const r = await rpc('admin_adjust_balance', { p_admin_id: ctx.adminId, p_ref: user, p_currency: cur, p_mode: mode, p_amount: Number(text.replace(/[^\d.]/g, '')), p_reason: 'ajuste pelo painel' });
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
    case 'removehero': { const r = await rpc('admin_remove_hero', { p_admin_id: ctx.adminId, p_hero_id: text, p_reason: 'removido pelo painel' }); return send(ctx, `🗑 Herói ${esc(r.name)} removido.`, MAIN_MENU); }
    case 'removepet': { const r = await rpc('admin_remove_pet', { p_admin_id: ctx.adminId, p_player_pet_id: text, p_reason: 'removido pelo painel' }); return send(ctx, `🗑 Pet removido (<code>${r.player_pet_id}</code>).`, MAIN_MENU); }
    case 'vip': { const [tier, user] = args; const r = await rpc('admin_set_membership', { p_admin_id: ctx.adminId, p_ref: user, p_tier: tier, p_days: Number(text), p_reason: 'painel admin' }); return send(ctx, `✅ ${tier.toUpperCase()} até ${r.until ? String(r.until).slice(0, 10) : 'removido'}.`, kb([[{ t: '👤 Ver jogador', d: `find:${user}` }], nav()])); }
    case 'ban': { const r = await rpc('admin_set_ban', { p_admin_id: ctx.adminId, p_ref: args[0], p_banned: true, p_reason: text }); return send(ctx, `🚫 Jogador banido (<code>${r.user_id}</code>).`, MAIN_MENU); }
    case 'reset': { const r = await rpc('admin_reset_account', { p_admin_id: ctx.adminId, p_ref: args[0], p_reason: text }); return send(ctx, `♻️ Conta resetada (<code>${r.user_id}</code>).`, MAIN_MENU); }
    case 'hero': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_hero', { p_admin_id: ctx.adminId, p_hero_key: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Herói salvo: <b>${esc(r.name)}</b> — ${esc(r.rarity)} ${r.enabled ? '✅' : '⛔'} ${r.price_fc ? fmt(r.price_fc) + ' FC' : ''}`, MAIN_MENU); }
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
    case 'league': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_league', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Liga salva: ${esc(r.name)} (${r.min_trophies}–${r.max_trophies ?? '∞'})`, MAIN_MENU); }
    case 'mission': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_mission', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Missão salva: ${esc(r.title)}`, MAIN_MENU); }
    case 'boss': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_boss', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Chefe salvo: ${esc(r.name)} — ${fmt(r.max_hp)} HP`, MAIN_MENU); }
    case 'bossspawn': { const r = await rpc('admin_boss_control', { p_admin_id: ctx.adminId, p_action: 'spawn', p_code: text, p_reason: 'spawn manual' }); return send(ctx, `⚡ Chefe <b>${esc(text)}</b> ativado (${r.affected} combates reiniciados).`, MAIN_MENU); }
    case 'ads': { const i = text.indexOf(' '); const r = await rpc('admin_upsert_ad_provider', { p_admin_id: ctx.adminId, p_code: text.slice(0, i), p_patch: JSON.parse(text.slice(i + 1)), p_reason: 'painel admin' }); return send(ctx, `✅ Provedor ${esc(r.name)} ${r.enabled ? 'ativo' : 'inativo'} — ${fmt(r.reward_fc)} FC`, MAIN_MENU); }
    case 'setting': { const i = text.indexOf(' '); const k = i < 0 ? text : text.slice(0, i); const v = i < 0 ? '' : text.slice(i + 1); const r = await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: k, p_value: parseValue(v), p_reason: 'painel admin' }); return send(ctx, `✅ <code>${esc(k)}</code>\n${esc(JSON.stringify(r.old_value))} → <b>${esc(JSON.stringify(r.new_value))}</b>`, MAIN_MENU); }
    case 'pvpset': { const [k, v] = text.split(/\s+/); const r = await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: k, p_value: parseValue(v), p_reason: 'painel admin' }); return send(ctx, `✅ ${esc(k)}: ${esc(JSON.stringify(r.old_value))} → <b>${esc(JSON.stringify(r.new_value))}</b>`, MAIN_MENU); }
    case 'maintmsg': { await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: 'maintenance_message', p_value: text, p_reason: 'painel admin' }); return send(ctx, '✅ Mensagem atualizada.', MAIN_MENU); }
    case 'ref': { const r = await rpc('admin_set_referral_percent', { p_admin_id: ctx.adminId, p_level: Number(args[0]), p_percent: Number(text.replace(/[^\d.]/g, '')), p_reason: 'painel admin' }); return send(ctx, `✅ Nível ${r.level}: ${r.old_value}% → <b>${r.new_value}%</b>`, MAIN_MENU); }
    case 'unlink': { const i = text.indexOf(' '); const r = await rpc('admin_unlink_referral', { p_admin_id: ctx.adminId, p_ref: text.slice(0, i), p_reason: text.slice(i + 1) }); return send(ctx, `✂️ ${r.removed} vínculo(s) removido(s).`, MAIN_MENU); }
    case 'pool': { const amount = Number(text.replace(/[^\d.]/g, '')) * (args[0] === 'remove' ? -1 : 1); const r = await rpc('admin_adjust_pool_balance', { p_amount: amount, p_reason: 'painel admin' }); await rpc('admin_log', { p_admin_id: ctx.adminId, p_action: 'pool.adjust', p_target_type: 'pool', p_target_id: null, p_old: null, p_new: { amount }, p_reason: 'painel admin', p_context: { financial: true } }); return send(ctx, `✅ Pool ajustada em ${amount} TON.\n<code>${esc(JSON.stringify(r)).slice(0, 500)}</code>`, MAIN_MENU); }
    case 'poolset': { const [k, v] = text.split(/\s+/); await rpc('admin_set_setting', { p_admin_id: ctx.adminId, p_key: 'pool_' + k, p_value: parseValue(v), p_reason: 'painel admin' }); return send(ctx, `✅ Configuração da pool <code>${esc(k)}</code> = ${esc(v)}`, MAIN_MENU); }
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
    case 'wdpaid': case 'wdno': {
      const [id, hash] = text.split(/\s+/);
      const { data: rows } = await db.from('wallet_withdrawals').select('id').ilike('id', `${id}%`).limit(1);
      if (!rows?.length) return send(ctx, '⚠️ Saque não encontrado.', MAIN_MENU);
      const r = await rpc('admin_review_withdrawal', { p_admin_id: ctx.adminId, p_withdrawal_id: rows[0].id, p_status: key === 'wdpaid' ? 'paid' : 'rejected', p_tx_hash: hash ?? null, p_reason: 'painel admin' });
      return send(ctx, `✅ Saque atualizado.\n<code>${esc(JSON.stringify(r)).slice(0, 500)}</code>`, MAIN_MENU);
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
  player_not_found: '⚠️ Jogador não encontrado.',
  hero_not_found: '⚠️ Herói não encontrado.',
  pet_not_found: '⚠️ Pet não encontrado.',
  reason_required: '⚠️ O motivo é obrigatório para esta ação.',
  already_confirmed: '⚠️ Este depósito já foi confirmado.',
  already_processed: '⚠️ Este saque já foi processado.',
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

    const text = String(update.message?.text || '').trim();
    const replied = String(update.message?.reply_to_message?.text || '');
    const pending = replied.match(/#([^\s]+)\s*$/)?.[1];
    if (pending) {
      await handlePrompt(ctx, pending, text);
      return new Response(JSON.stringify({ ok: true }));
    }

    const cmd = text.split(/\s+/)[0].replace(/@.*/, '').toLowerCase();
    const arg = text.slice(cmd.length).trim();
    const direct: Record<string, string> = {
      '/heroes': 'heroes', '/pets': 'pets', '/pvp': 'pvp', '/pool': 'pool', '/pass': 'pass',
      '/invites': 'invites', '/boss': 'boss', '/audit': 'audit', '/status': 'status',
      '/wallet': 'wallet', '/missions': 'missions', '/ads': 'ads', '/settings': 'settings', '/broadcast': 'cast',
    };
    if (cmd === '/start' || cmd === '/admin' || cmd === '/menu') await home(ctx);
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
    await send(ctx, known ? ERRORS[known] : `⚠️ Falha: <code>${esc(raw).slice(0, 400)}</code>`, MAIN_MENU);
  }
  return new Response(JSON.stringify({ ok: true }));
});
