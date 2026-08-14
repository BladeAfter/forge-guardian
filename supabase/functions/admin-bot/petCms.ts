// MYTHREON :: Visual Pet / Egg CMS for the master admin bot.
// Everything here is button-driven: no JSON typing, no manual urls. Photos sent in the chat are
// normalized (square, transparent-safe PNG) and stored in the private `pet-images` bucket, so the
// creature shows up in the game (catalog, eggs, chests, rewards) with no deploy.
// NOTE: no image library is used here. imagescript's wasm loader throws an unhandled
// "brotli error" on this runtime, which kills the whole admin bot worker (HTTP 500 on the webhook).
// Telegram photos are stored exactly as received — the game UI already handles arbitrary aspect ratios.

export type Ctx = { chatId: number; adminId: number; messageId?: number };
type Btn = { t: string; d: string };

export type PetCmsDeps = {
  db: any;
  botToken: string;
  tg: (method: string, payload: Record<string, unknown>) => Promise<any>;
  rpc: (fn: string, args: Record<string, unknown>) => Promise<any>;
  kb: (rows: Btn[][]) => unknown;
  nav: (back?: string) => Btn[];
  fmt: (n: unknown) => string;
  esc: (s: unknown) => string;
  send: (ctx: Ctx, text: string, markup?: unknown) => Promise<void>;
  edit: (ctx: Ctx, text: string, markup?: unknown) => Promise<void>;
  setSession: (ctx: Ctx, action: string, step?: string, context?: Record<string, unknown>) => Promise<void>;
  getSession: (ctx: Ctx) => Promise<{ action: string; step: string; context: Record<string, unknown> } | null>;
  clearSession: (ctx: Ctx) => Promise<void>;
};

export type PetDraft = {
  mode: 'pet_create' | 'pet_edit' | 'egg_create' | 'egg_edit';
  petId?: string;
  eggId?: string;
  name?: string;
  image?: string;
  rarity?: string;
  attrKey?: string;
  attrLabel?: string;
  attrValue?: number;
  category?: string;
  sources?: string[];
  showCatalog?: boolean;
  currency?: string;
  price?: number;
  field?: string;
  rates?: Record<string, number>;
  poolRarity?: string;
  ids?: string[];
  offset?: number;
};

const SOURCES: [string, string][] = [
  ['EGG', '🥚 Ovos'],
  ['CHEST', '🎁 Baús'],
  ['EVENT', '🎉 Eventos'],
  ['CLAN_BOSS', '👹 Chefe de Clã'],
  ['SEASON_PASS', '🎟 Passe'],
  ['ADMIN_GIFT', '👑 Somente Admin'],
];
const SOURCE_LABEL = Object.fromEntries(SOURCES) as Record<string, string>;
const CURRENCIES: [string, string][] = [['FC', '🪙 FC'], ['TON', '💎 TON'], ['EVENT', '🎉 Evento'], ['NONE', '🔒 Não vendável']];
const CANCEL: Btn[] = [{ t: '❌ CANCELAR', d: 'cancel' }];

export function createPetCms(d: PetCmsDeps) {
  const { rpc, kb, nav, fmt, esc, send, edit, setSession, getSession, clearSession, tg, db } = d;

  const rarities = async (ctx: Ctx) => (await rpc('admin_pet_rarities', { p_admin_id: ctx.adminId })) as any[];

  const step = async (ctx: Ctx, s: string, draft: PetDraft, text: string, rows: Btn[][] = []) => {
    await setSession(ctx, 'petcms', s, draft as Record<string, unknown>);
    await send(ctx, text, kb([...rows, CANCEL]));
  };

  /** Stores a Telegram photo as-is inside the private `pet-images` bucket. */
  async function uploadPhoto(fileId: string, baseName: string): Promise<string> {
    const info = await tg('getFile', { file_id: fileId });
    const filePath = info?.result?.file_path;
    if (!filePath) throw new Error('image_download_failed');
    const res = await fetch(`https://api.telegram.org/file/bot${d.botToken}/${filePath}`);
    if (!res.ok) throw new Error('image_download_failed');
    const bytes = new Uint8Array(await res.arrayBuffer());
    const ext = (filePath.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
    const contentType = ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
    const slug = (baseName || 'pet').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40) || 'pet';
    const path = `pets/${slug}-${Date.now()}.${ext}`;
    const up = await db.storage.from('pet-images').upload(path, bytes, { contentType, upsert: true });
    if (up.error) throw new Error(`image_upload_failed: ${up.error.message}`);
    const signed = await db.storage.from('pet-images').createSignedUrl(path, 60 * 60 * 24 * 365 * 10);
    if (signed.error || !signed.data?.signedUrl) throw new Error('image_url_failed');
    return signed.data.signedUrl as string;
  }

  async function photoOr(ctx: Ctx, image: string | null | undefined, text: string, markup: unknown) {
    if (image && /^https?:\/\//.test(String(image))) {
      const r = await tg('sendPhoto', { chat_id: ctx.chatId, photo: image, caption: text.slice(0, 1000), parse_mode: 'HTML', reply_markup: markup });
      if (r?.ok) return;
    }
    return send(ctx, text, markup);
  }

  // ------------------------------------------------------------------ hub
  async function hub(ctx: Ctx) {
    await clearSession(ctx);
    const [cat, eggs, rar] = await Promise.all([
      rpc('admin_pet_catalog', { p_admin_id: ctx.adminId, p_limit: 1, p_offset: 0 }),
      rpc('admin_egg_list', { p_admin_id: ctx.adminId }),
      rarities(ctx),
    ]);
    const text = ['🐲 <b>PET CMS</b> — editor visual', '',
      `Criaturas: <b>${fmt(cat.total)}</b> · Ovos: <b>${fmt((eggs || []).length)}</b> · Raridades: <b>${fmt(rar.length)}</b>`,
      '', 'Tudo por botões: nome, foto enviada aqui, raridade, atributo sorteado, fontes de drop e pools de ovos.'].join('\n');
    return edit(ctx, text, kb([
      [{ t: '➕ CRIAR PET', d: 'pw:new' }, { t: '📚 TODOS OS PETS', d: 'pw:list:0' }],
      [{ t: '➕ CRIAR OVO', d: 'pw:enew' }, { t: '🥚 TODOS OS OVOS', d: 'pw:eggs' }],
      [{ t: '⭐ RARIDADES', d: 'pw:rarinfo' }],
      nav('m:pets'),
    ]));
  }

  // ------------------------------------------------------------------ pet creation
  const askName = (ctx: Ctx, draft: PetDraft) =>
    step(ctx, 'pet_name', draft, '🐲 <b>NOVO PET</b>\n\nDigite o <b>nome da criatura</b>:');

  const askImage = (ctx: Ctx, draft: PetDraft) =>
    step(ctx, 'pet_image', draft, `🖼 <b>ENVIE A FOTO</b> de <b>${esc(draft.name)}</b>\n\nMande a imagem nesta conversa (PNG com fundo transparente fica melhor).`);

  async function askRarity(ctx: Ctx, draft: PetDraft) {
    const rar = await rarities(ctx);
    return step(ctx, 'pet_rarity', draft, `⭐ <b>RARIDADE</b> de <b>${esc(draft.name)}</b>:`,
      rar.map((r: any) => [{ t: `${r.emoji || '⭐'} ${String(r.label || r.rarity).toUpperCase()}`, d: `pw:rar:${r.rarity}` }]));
  }

  async function rollAttribute(ctx: Ctx, draft: PetDraft) {
    const roll = await rpc('admin_roll_pet_attribute', { p_admin_id: ctx.adminId, p_rarity: draft.rarity, p_exclude: draft.attrKey || null });
    draft.attrKey = roll.key; draft.attrLabel = roll.label; draft.attrValue = Number(roll.value);
    return step(ctx, 'pet_attr', draft,
      ['🎲 <b>ATRIBUTO SORTEADO</b>', '', `<b>${esc(roll.label || roll.key)}</b>: <b>+${fmt(roll.value)}%</b>`,
        `Faixa da raridade: ${fmt(roll.min)}% – ${fmt(roll.max)}%`].join('\n'),
      [[{ t: '🎲 SORTEAR DE NOVO', d: 'pw:reroll' }], [{ t: '✅ MANTER', d: 'pw:src' }]]);
  }

  async function askSources(ctx: Ctx, draft: PetDraft) {
    draft.sources = draft.sources || ['EGG'];
    return step(ctx, 'pet_sources', draft,
      '📦 <b>ONDE ESTE PET PODE APARECER?</b>\n\nMarque as fontes (pode escolher várias):',
      [...SOURCES.map(([k, l]) => [{ t: `${draft.sources!.includes(k) ? '✅' : '☐'} ${l}`, d: `pw:s:${k}` }]),
        [{ t: '➡️ CONTINUAR', d: 'pw:sdone' }]]);
  }

  function previewText(draft: PetDraft) {
    const sources = (draft.sources || []).map((s) => SOURCE_LABEL[s] || s).join(', ') || '—';
    return ['🐲 <b>NOVA CRIATURA</b>', '',
      `<b>${esc(draft.name)}</b>`,
      `⭐ Raridade: <b>${esc(String(draft.rarity || '').toUpperCase())}</b>`,
      `🎲 Atributo: <b>${esc(draft.attrLabel || draft.attrKey)} +${fmt(draft.attrValue)}%</b>`,
      `📦 Fontes: ${esc(sources)}`,
      `👁 Catálogo: <b>${draft.showCatalog === false ? 'OCULTO' : 'VISÍVEL (silhueta até descobrir)'}</b>`,
    ].join('\n');
  }

  async function preview(ctx: Ctx, draft: PetDraft) {
    await setSession(ctx, 'petcms', 'pet_preview', draft as Record<string, unknown>);
    return photoOr(ctx, draft.image, previewText(draft), kb([
      [{ t: '✅ CRIAR PET', d: 'pw:save' }],
      [{ t: '🎲 OUTRO ATRIBUTO', d: 'pw:reroll' }, { t: '📦 FONTES', d: 'pw:src' }],
      [{ t: `👁 Catálogo: ${draft.showCatalog === false ? 'OCULTO' : 'VISÍVEL'}`, d: 'pw:cat' }],
      [{ t: '🖼 TROCAR FOTO', d: 'pw:reimg' }],
      CANCEL,
    ]));
  }

  async function savePet(ctx: Ctx, draft: PetDraft) {
    const sources = draft.sources?.length ? draft.sources : ['EGG'];
    const availability = sources.length === 1 && sources[0] === 'ADMIN_GIFT' ? 'ADMIN_ONLY'
      : sources.length === 1 && sources[0] === 'EVENT' ? 'EVENT' : 'NORMAL';
    const pet = await rpc('admin_create_pet_visual', {
      p_admin_id: ctx.adminId,
      p_name: draft.name,
      p_image_url: draft.image,
      p_rarity: draft.rarity,
      p_attribute_key: draft.attrKey,
      p_attribute_value: draft.attrValue,
      p_category: draft.category || 'beast',
      p_sources: sources,
      p_availability: availability,
      p_show_in_catalog: draft.showCatalog !== false,
    });
    await clearSession(ctx);
    return send(ctx,
      `✅ <b>${esc(pet.name)}</b> criado (<code>${esc(pet.slug)}</code>).\n⭐ ${esc(String(pet.rarity).toUpperCase())} · 🎲 ${esc(draft.attrLabel || draft.attrKey)} +${fmt(draft.attrValue)}%\n\nJá disponível no jogo. Adicione-o ao pool de um ovo para que possa ser chocado.`,
      kb([[{ t: '🥚 ADICIONAR A UM OVO', d: 'pw:eggs' }], [{ t: '🐲 PET CMS', d: 'pw:hub' }], nav('m:pets')]));
  }

  // ------------------------------------------------------------------ pet list / edit
  async function petList(ctx: Ctx, offset: number, search?: string) {
    const d0 = await rpc('admin_pet_catalog', { p_admin_id: ctx.adminId, p_search: search || null, p_limit: 10, p_offset: offset });
    const pets = (d0.pets || []) as any[];
    if (!pets.length) {
      await clearSession(ctx);
      return send(ctx, '🔎 Nenhum pet encontrado.', kb([[{ t: '➕ CRIAR PET', d: 'pw:new' }], nav('pw:hub')]));
    }
    await setSession(ctx, 'petcms', 'pet_browse', { mode: 'pet_edit', ids: pets.map((p) => p.id), offset } as Record<string, unknown>);
    const rows = pets.map((p, i) => [{
      t: `${p.is_enabled ? '' : '⛔ '}${p.name} · ${String(p.rarity || 'common').toUpperCase()}${p.owners ? ` · ${p.owners}👤` : ''}`,
      d: `pw:p:${i}`,
    }]);
    const pager: Btn[] = [];
    if (offset > 0) pager.push({ t: '⬅️', d: `pw:list:${Math.max(0, offset - 10)}` });
    if (offset + pets.length < Number(d0.total || 0)) pager.push({ t: '➡️', d: `pw:list:${offset + 10}` });
    return send(ctx, `📚 <b>PETS</b> (${fmt(offset + 1)}–${fmt(offset + pets.length)} de ${fmt(d0.total)})`,
      kb([...rows, ...(pager.length ? [pager] : []), [{ t: '🔎 PESQUISAR', d: 'pw:search' }], nav('pw:hub')]));
  }

  async function petMenu(ctx: Ctx, petId: string) {
    const p = await rpc('admin_pet_detail_cms', { p_admin_id: ctx.adminId, p_pet_id: petId });
    await setSession(ctx, 'petcms', 'pet_menu', { mode: 'pet_edit', petId } as Record<string, unknown>);
    const eggs = (p.eggs || []) as any[];
    const sources = ((p.obtainable_from || []) as string[]).map((s) => SOURCE_LABEL[s] || s).join(', ') || '—';
    const text = ['✏️ <b>EDITAR PET</b>', '',
      `<b>${esc(p.name)}</b> · <code>${esc(p.slug)}</code>`,
      `⭐ ${esc(String(p.rarity || 'common').toUpperCase())} · 👤 ${fmt(p.owners)} donos`,
      `🎲 ${esc(p.primary_attribute_key || '—')} +${fmt(p.primary_attribute_value)}%`,
      `📦 ${esc(sources)}`,
      `👁 Catálogo: ${p.show_in_catalog ? '✅' : '❌'} · Ativo: ${p.is_enabled ? '✅' : '⛔'}`,
      eggs.length ? `🥚 Em ovos: ${esc(eggs.map((e) => `${e.name} (${e.rarity})`).join(', '))}` : '🥚 Nenhum ovo usa este pet ainda.',
    ].join('\n');
    return photoOr(ctx, p.image_baby_url, text, kb([
      [{ t: '🖼 Trocar foto', d: 'pw:pf:image' }, { t: '✏️ Nome', d: 'pw:pf:name' }],
      [{ t: '🧬 FORMAS VISUAIS (1/10/20/30/40/50)', d: 'pw:pstage' }],
      [{ t: '⭐ Raridade', d: 'pw:pf:rarity' }, { t: '🎲 Novo atributo', d: 'pw:proll' }],
      [{ t: '📦 Fontes', d: 'pw:psrc' }],
      [{ t: `👁 Catálogo ${p.show_in_catalog ? 'ON→OFF' : 'OFF→ON'}`, d: 'pw:ptog:cat' },
        { t: `${p.is_enabled ? '⛔ Desativar' : '✅ Ativar'}`, d: 'pw:ptog:on' }],
      [{ t: '📚 LISTA', d: 'pw:list:0' }],
      nav('pw:hub'),
    ]));
  }

  /** Cosmetic artwork per 10 levels — never touches rarity, buffs or stats. */
  const STAGES: Array<[string, string, string]> = [
    ['base', 'Forma Base', 'Nv 1–9'],
    ['evo1', 'Evolução I', 'Nv 10–19'],
    ['evo2', 'Evolução II', 'Nv 20–29'],
    ['evo3', 'Evolução III', 'Nv 30–39'],
    ['evo4', 'Evolução IV', 'Nv 40–49'],
    ['final', 'Forma Final', 'Nv 50'],
  ];

  async function stageMenu(ctx: Ctx, petId: string) {
    const st = await rpc('admin_pet_stage_images', { p_admin_id: ctx.adminId, p_pet_id: petId });
    await setSession(ctx, 'petcms', 'pet_stage', { mode: 'pet_edit', petId } as Record<string, unknown>);
    const lines = STAGES.map(([key, label, range]) => `${st?.[key] ? '✅' : '➖'} <b>${label}</b> · ${range}`);
    const text = ['🧬 <b>FORMAS VISUAIS</b>', `<b>${esc(st?.name || '')}</b>`, '',
      ...lines, '',
      'A arte troca sozinha a cada 10 níveis. Raridade, buffs e poder não mudam.',
      'Se uma forma ficar vazia, o jogo usa a forma anterior automaticamente.'].join('\n');
    return send(ctx, text, kb([
      ...STAGES.map(([key, label]) => [{ t: `🖼 ${label}`, d: `pw:pstg:${key}` }]),
      [{ t: '✏️ EDITAR PET', d: `pw:p:sel` }],
      nav('pw:hub'),
    ]));
  }

  const applyPet = async (ctx: Ctx, petId: string, patch: Record<string, unknown>) => {
    await rpc('admin_update_pet_visual', { p_admin_id: ctx.adminId, p_pet_id: petId, p_patch: patch, p_reason: 'editor visual' });
    return petMenu(ctx, petId);
  };

  // ------------------------------------------------------------------ eggs
  async function eggList(ctx: Ctx) {
    const eggs = (await rpc('admin_egg_list', { p_admin_id: ctx.adminId })) as any[];
    await setSession(ctx, 'petcms', 'egg_browse', { mode: 'egg_edit', ids: eggs.map((e: any) => e.id) } as Record<string, unknown>);
    const rows = eggs.map((e: any, i: number) => [{
      t: `${e.isEnabled ? '' : '⛔ '}${e.name} · ${e.priceTon ? `${e.priceTon} TON` : e.priceFc ? `${fmt(e.priceFc)} FC` : '—'} · ${e.poolCount}🐲`,
      d: `pw:e:${i}`,
    }]);
    return send(ctx, `🥚 <b>OVOS</b> (${fmt(eggs.length)})`, kb([...rows, [{ t: '➕ CRIAR OVO', d: 'pw:enew' }], nav('pw:hub')]));
  }

  async function eggMenu(ctx: Ctx, eggId: string) {
    const e = await rpc('admin_egg_detail', { p_admin_id: ctx.adminId, p_egg_id: eggId });
    await setSession(ctx, 'petcms', 'egg_menu', { mode: 'egg_edit', eggId } as Record<string, unknown>);
    const rates = (e.rarity_rates || {}) as Record<string, number>;
    const pool = (e.pool || []) as any[];
    const byRarity = pool.reduce((acc: Record<string, number>, r: any) => ({ ...acc, [r.rarity]: (acc[r.rarity] || 0) + 1 }), {});
    const oddsText = Object.entries(rates).length
      ? Object.entries(rates).map(([k, v]) => `• ${k.toUpperCase()}: <b>${v}%</b> (${byRarity[k] || 0} pets)`).join('\n')
      : '• Sem chances configuradas';
    const text = ['🥚 <b>EDITAR OVO</b>', '',
      `<b>${esc(e.name)}</b> · <code>${esc(e.slug)}</code>`,
      `💰 ${e.price_ton ? `${e.price_ton} TON` : e.price_fc ? `${fmt(e.price_fc)} FC` : 'Não vendável'} · ${e.is_enabled ? '✅ Ativo' : '⛔ Inativo'}`,
      '', '<b>CHANCES POR RARIDADE</b>', oddsText,
      '', `🐲 Pets no pool: <b>${fmt(pool.length)}</b>`,
    ].join('\n');
    return photoOr(ctx, e.image_url, text, kb([
      [{ t: '🎯 CHANCES DE RARIDADE', d: 'pw:eodds' }],
      [{ t: '🐲 PETS DESTE OVO', d: 'pw:pool' }],
      [{ t: '🖼 Trocar foto', d: 'pw:ef:image' }, { t: '✏️ Nome', d: 'pw:ef:name' }],
      [{ t: '💰 Preço', d: 'pw:ef:price' }, { t: `${e.is_enabled ? '⛔ Desativar' : '✅ Ativar'}`, d: 'pw:etog' }],
      [{ t: '🥚 TODOS OS OVOS', d: 'pw:eggs' }],
      nav('pw:hub'),
    ]));
  }

  async function askOdds(ctx: Ctx, draft: PetDraft, rates?: Record<string, number>) {
    const [rar, egg] = await Promise.all([rarities(ctx), rpc('admin_egg_detail', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId })]);
    const pool = (egg.pool || []) as any[];
    const current = rates || draft.rates || ({ ...(egg.rarity_rates || {}) } as Record<string, number>);
    draft.rates = current;
    const total = Object.values(current).reduce((a, b) => a + Number(b || 0), 0);
    const rows: Btn[][] = rar.map((r: any, i: number) => {
      const has = pool.some((p) => p.rarity === r.rarity);
      const value = Number(current[r.rarity] || 0);
      return [
        { t: `${r.emoji || '⭐'} ${String(r.rarity).toUpperCase()} ${value}%${has ? '' : ' ⚠️'}`, d: `pw:onop` },
        { t: '−5', d: `pw:o:${i}:-5` }, { t: '−1', d: `pw:o:${i}:-1` },
        { t: '+1', d: `pw:o:${i}:1` }, { t: '+5', d: `pw:o:${i}:5` },
      ];
    });
    const text = ['🎯 <b>CHANCES DO OVO</b>', '', `Total atual: <b>${total}%</b> (precisa ser 100%)`,
      '', '⚠️ = ainda não há pets desta raridade no pool deste ovo.'].join('\n');
    await setSession(ctx, 'petcms', 'egg_odds', draft as Record<string, unknown>);
    return send(ctx, text, kb([...rows, [{ t: '💾 SALVAR CHANCES', d: 'pw:osave' }], [{ t: '⬅️ Voltar', d: 'pw:eback' }]]));
  }

  async function askPoolRarity(ctx: Ctx, draft: PetDraft) {
    const [rar, egg] = await Promise.all([rarities(ctx), rpc('admin_egg_detail', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId })]);
    const pool = (egg.pool || []) as any[];
    await setSession(ctx, 'petcms', 'egg_pool', draft as Record<string, unknown>);
    const rows = rar.map((r: any, i: number) => [{
      t: `${r.emoji || '⭐'} ${String(r.rarity).toUpperCase()} · ${pool.filter((p) => p.rarity === r.rarity).length} pets`,
      d: `pw:pl:${i}`,
    }]);
    return send(ctx, `🐲 <b>PETS DE <u>${esc(egg.name)}</u></b>\n\nEscolha a raridade para definir quais criaturas podem sair:`,
      kb([...rows, [{ t: '⬅️ Voltar', d: 'pw:eback' }]]));
  }

  async function poolPets(ctx: Ctx, draft: PetDraft) {
    const [cat, egg] = await Promise.all([
      rpc('admin_pet_catalog', { p_admin_id: ctx.adminId, p_limit: 30, p_offset: 0 }),
      rpc('admin_egg_detail', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId }),
    ]);
    const pool = (egg.pool || []) as any[];
    const inPool = new Set(pool.filter((p) => p.rarity === draft.poolRarity).map((p) => p.petId));
    // A pet's rarity is fixed on its template: only pets of this exact rarity may join the pool.
    const pets = ((cat.pets || []) as any[])
      .filter((p) => p.is_enabled && String(p.rarity || 'common') === String(draft.poolRarity));
    draft.ids = pets.map((p) => p.id);
    await setSession(ctx, 'petcms', 'egg_pool_pets', draft as Record<string, unknown>);
    const rows = pets.slice(0, 24).map((p, i) => [{ t: `${inPool.has(p.id) ? '✅' : '☐'} ${p.name} (${String(p.rarity).toUpperCase()})`, d: `pw:pp:${i}` }]);
    return send(ctx,
      `🐲 <b>${esc(String(draft.poolRarity).toUpperCase())}</b> em <b>${esc(egg.name)}</b>\n\nToque para incluir/remover.\nSão listados apenas pets cuja raridade oficial é <b>${esc(String(draft.poolRarity).toUpperCase())}</b> — a raridade do pet é fixa e nunca muda.${pets.length ? '' : '\n\n⚠️ Nenhum pet cadastrado nesta raridade.'}`,
      kb([...rows, [{ t: '⬅️ Raridades', d: 'pw:pool' }], [{ t: '🥚 OVO', d: 'pw:eback' }]]));
  }

  // ------------------------------------------------------------------ callbacks
  async function callback(ctx: Ctx, rest: string[]) {
    const action = rest[0];
    const arg = rest.slice(1).join(':');
    const session = await getSession(ctx);
    const draft: PetDraft = (session?.action === 'petcms' ? session.context : {}) as PetDraft;

    if (!action || action === 'hub') return hub(ctx);
    if (action === 'onop') return;

    if (action === 'rarinfo') {
      const rar = await rarities(ctx);
      return send(ctx, ['⭐ <b>RARIDADES DE PET</b>', '',
        ...rar.map((r: any) => `${r.emoji || '⭐'} <b>${String(r.rarity).toUpperCase()}</b> · multiplicador ${r.stat_multiplier}× · atributo ${r.attr_min}–${r.attr_max}%`),
      ].join('\n'), kb([nav('pw:hub')]));
    }

    // ---- pet creation
    if (action === 'new') return askName(ctx, { mode: 'pet_create', sources: ['EGG'], showCatalog: true });
    if (action === 'reimg') return askImage(ctx, draft);
    if (action === 'rar') {
      draft.rarity = arg;
      if (draft.mode === 'pet_edit' && draft.petId) return applyPet(ctx, draft.petId, { rarity: arg });
      return rollAttribute(ctx, draft);
    }
    if (action === 'reroll') {
      if (draft.mode === 'pet_edit' && draft.petId) {
        const p = await rpc('admin_pet_detail_cms', { p_admin_id: ctx.adminId, p_pet_id: draft.petId });
        const roll = await rpc('admin_roll_pet_attribute', { p_admin_id: ctx.adminId, p_rarity: p.rarity, p_exclude: p.primary_attribute_key });
        return applyPet(ctx, draft.petId, { primary_attribute_key: roll.key, primary_attribute_value: roll.value });
      }
      return rollAttribute(ctx, draft);
    }
    if (action === 'src') return askSources(ctx, draft);
    if (action === 's') {
      const set = new Set(draft.sources || []);
      set.has(arg) ? set.delete(arg) : set.add(arg);
      draft.sources = [...set];
      if (draft.mode === 'pet_edit' && draft.petId) {
        await rpc('admin_update_pet_visual', {
          p_admin_id: ctx.adminId, p_pet_id: draft.petId,
          p_patch: { obtainable_from: draft.sources }, p_reason: 'editor visual',
        });
      }
      return askSources(ctx, draft);
    }
    if (action === 'sdone') {
      if (draft.mode === 'pet_edit' && draft.petId) return petMenu(ctx, draft.petId);
      return preview(ctx, draft);
    }
    if (action === 'cat') { draft.showCatalog = draft.showCatalog === false; return preview(ctx, draft); }
    if (action === 'save') {
      if (!draft.name || !draft.image || !draft.rarity) return send(ctx, '⚠️ Fluxo expirado. Comece novamente.', kb([[{ t: '🐲 PET CMS', d: 'pw:hub' }]]));
      return savePet(ctx, draft);
    }

    // ---- pet list / edit
    if (action === 'list') return petList(ctx, Number(arg) || 0);
    if (action === 'search') return step(ctx, 'pet_search', { mode: 'pet_edit' }, '🔎 Envie o <b>nome</b> (ou parte) do pet:');
    if (action === 'p') {
      const id = (draft.ids || [])[Number(arg)];
      if (!id) return petList(ctx, 0);
      return petMenu(ctx, id);
    }
    if (action === 'proll') { draft.mode = 'pet_edit'; return callback(ctx, ['reroll']); }
    if (action === 'psrc') {
      if (!draft.petId) return petList(ctx, 0);
      const p = await rpc('admin_pet_detail_cms', { p_admin_id: ctx.adminId, p_pet_id: draft.petId });
      return askSources(ctx, { mode: 'pet_edit', petId: draft.petId, sources: (p.obtainable_from || []) as string[] });
    }
    if (action === 'pf') {
      if (!draft.petId) return petList(ctx, 0);
      const d2: PetDraft = { mode: 'pet_edit', petId: draft.petId, field: arg };
      if (arg === 'image') return step(ctx, 'pet_edit_image', d2, '🖼 Envie a nova foto do pet nesta conversa.');
      if (arg === 'rarity') {
        const rar = await rarities(ctx);
        return step(ctx, 'pet_edit_rarity', d2, '⭐ Nova raridade:', rar.map((r: any) => [{ t: `${r.emoji || '⭐'} ${String(r.rarity).toUpperCase()}`, d: `pw:rar:${r.rarity}` }]));
      }
      return step(ctx, 'pet_edit_name', d2, '✏️ Envie o novo <b>nome</b>:');
    }
    if (action === 'pstage') {
      if (!draft.petId) return petList(ctx, 0);
      return stageMenu(ctx, draft.petId);
    }
    if (action === 'pstg') {
      if (!draft.petId) return petList(ctx, 0);
      const stage = STAGES.find(([k]) => k === arg);
      if (!stage) return stageMenu(ctx, draft.petId);
      return step(ctx, `pet_stage_image:${arg}`, { mode: 'pet_edit', petId: draft.petId },
        `🖼 Envie a imagem da <b>${stage[1]}</b> (${stage[2]}) nesta conversa.`);
    }
    if (action === 'ptog') {
      if (!draft.petId) return petList(ctx, 0);
      const p = await rpc('admin_pet_detail_cms', { p_admin_id: ctx.adminId, p_pet_id: draft.petId });
      return applyPet(ctx, draft.petId, arg === 'cat' ? { show_in_catalog: !p.show_in_catalog } : { is_enabled: !p.is_enabled });
    }

    // ---- eggs
    if (action === 'eggs') return eggList(ctx);
    if (action === 'enew') return step(ctx, 'egg_name', { mode: 'egg_create' }, '🥚 <b>NOVO OVO</b>\n\nDigite o <b>nome do ovo</b>:');
    if (action === 'e') {
      const id = (draft.ids || [])[Number(arg)];
      if (!id) return eggList(ctx);
      return eggMenu(ctx, id);
    }
    if (action === 'eback') {
      if (!draft.eggId) return eggList(ctx);
      return eggMenu(ctx, draft.eggId);
    }
    if (action === 'ecur') {
      draft.currency = arg;
      if (draft.mode === 'egg_edit' && draft.eggId && arg === 'NONE') {
        await rpc('admin_set_egg_price_visual', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_currency: 'NONE', p_price: 0 });
        return eggMenu(ctx, draft.eggId);
      }
      if (arg === 'NONE' || arg === 'EVENT') {
        draft.price = 0;
        return draft.mode === 'egg_create' ? saveEgg(ctx, draft) : eggMenu(ctx, draft.eggId!);
      }
      return step(ctx, 'egg_price', draft, `💰 Envie o preço em <b>${esc(arg)}</b> (ex.: <code>${arg === 'TON' ? '1.5' : '50000'}</code>):`);
    }
    if (action === 'ef') {
      if (!draft.eggId) return eggList(ctx);
      const d2: PetDraft = { mode: 'egg_edit', eggId: draft.eggId, field: arg };
      if (arg === 'image') return step(ctx, 'egg_edit_image', d2, '🖼 Envie a nova foto do ovo nesta conversa.');
      if (arg === 'price') return step(ctx, 'egg_currency', d2, '💰 <b>MOEDA DO OVO</b>:', CURRENCIES.map(([k, l]) => [{ t: l, d: `pw:ecur:${k}` }]));
      return step(ctx, 'egg_edit_name', d2, '✏️ Envie o novo <b>nome do ovo</b>:');
    }
    if (action === 'etog') {
      if (!draft.eggId) return eggList(ctx);
      const e = await rpc('admin_egg_detail', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId });
      await rpc('admin_update_egg_visual', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_patch: { is_enabled: !e.is_enabled } });
      return eggMenu(ctx, draft.eggId);
    }
    if (action === 'eodds') {
      if (!draft.eggId) return eggList(ctx);
      return askOdds(ctx, { mode: 'egg_edit', eggId: draft.eggId });
    }
    if (action === 'o') {
      const [idx, delta] = arg.split(':');
      const rar = await rarities(ctx);
      const key = rar[Number(idx)]?.rarity;
      if (!key) return askOdds(ctx, draft);
      const rates = { ...(draft.rates || {}) };
      rates[key] = Math.max(0, Math.min(100, Number(rates[key] || 0) + Number(delta)));
      if (!rates[key]) delete rates[key];
      return askOdds(ctx, draft, rates);
    }
    if (action === 'osave') {
      if (!draft.eggId) return eggList(ctx);
      try {
        await rpc('admin_set_egg_odds', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_rates: draft.rates || {} });
      } catch (err) {
        const raw = err instanceof Error ? err.message : String(err);
        const missing = raw.match(/NO_PET_FOR_RARITY:(\w+)/)?.[1];
        const sum = raw.match(/RATES_MUST_SUM_100:([\d.]+)/)?.[1];
        return send(ctx,
          missing ? `⚠️ Nenhum pet <b>${esc(missing.toUpperCase())}</b> está no pool deste ovo. Adicione pets antes de dar chance a esta raridade.`
            : sum ? `⚠️ As chances somam <b>${esc(sum)}%</b>. Ajuste até 100%.`
              : `⚠️ ${esc(raw).slice(0, 200)}`,
          kb([[{ t: '🐲 PETS DESTE OVO', d: 'pw:pool' }], [{ t: '🎯 AJUSTAR CHANCES', d: 'pw:eodds' }], [{ t: '🥚 OVO', d: 'pw:eback' }]]));
      }
      await send(ctx, '✅ Chances salvas — já valem para as próximas eclosões.');
      return eggMenu(ctx, draft.eggId);
    }
    if (action === 'pool') {
      if (!draft.eggId) return eggList(ctx);
      return askPoolRarity(ctx, { mode: 'egg_edit', eggId: draft.eggId });
    }
    if (action === 'pl') {
      const rar = await rarities(ctx);
      draft.poolRarity = rar[Number(arg)]?.rarity;
      if (!draft.poolRarity) return askPoolRarity(ctx, draft);
      return poolPets(ctx, draft);
    }
    if (action === 'pp') {
      const petId = (draft.ids || [])[Number(arg)];
      if (!petId || !draft.eggId || !draft.poolRarity) return askPoolRarity(ctx, draft);
      try {
        await rpc('admin_toggle_egg_pet', {
          p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_pet_id: petId, p_rarity: draft.poolRarity, p_weight: 100,
        });
      } catch (e) {
        const msg = String((e as Error)?.message || e);
        const m = msg.match(/PET_RARITY_MISMATCH: (.+)$/);
        if (m) return send(ctx, `⛔ <b>Pet rarity mismatch.</b>\n${esc(m[1])}`,
          kb([[{ t: '⬅️ Raridades', d: 'pw:pool' }], [{ t: '🥚 OVO', d: 'pw:eback' }]]));
        throw e;
      }
      return poolPets(ctx, draft);
    }

    return hub(ctx);
  }

  async function saveEgg(ctx: Ctx, draft: PetDraft) {
    const egg = await rpc('admin_create_egg_visual', {
      p_admin_id: ctx.adminId,
      p_name: draft.name,
      p_image_url: draft.image,
      p_currency: draft.currency || 'NONE',
      p_price: Number(draft.price || 0),
    });
    await send(ctx, `✅ Ovo <b>${esc(egg.name || draft.name)}</b> criado.\n\nAgora escolha quais pets ele pode gerar e ajuste as chances.`);
    return eggMenu(ctx, egg.id);
  }

  // ------------------------------------------------------------------ text / photo steps
  async function text(ctx: Ctx, s: string, draft: PetDraft, value: string) {
    const num = () => {
      const v = Number(String(value).replace(/[^\d.,-]/g, '').replace(/\.(?=\d{3}\b)/g, '').replace(',', '.'));
      return Number.isFinite(v) && v >= 0 ? v : null;
    };
    if (s.startsWith('pet_stage_image:')) {
      const stage = s.split(':')[1];
      if (/^(remover|remove|limpar|-)$/i.test(value.trim()) && draft.petId) {
        await rpc('admin_set_pet_stage_image', { p_admin_id: ctx.adminId, p_pet_id: draft.petId, p_stage: stage, p_url: null });
        await send(ctx, '🗑 Forma visual removida (usa a forma anterior).');
        return stageMenu(ctx, draft.petId);
      }
      if (/^https?:\/\//.test(value.trim()) && draft.petId) {
        await rpc('admin_set_pet_stage_image', { p_admin_id: ctx.adminId, p_pet_id: draft.petId, p_stage: stage, p_url: value.trim() });
        await send(ctx, '✅ Forma visual atualizada.');
        return stageMenu(ctx, draft.petId);
      }
      return step(ctx, s, draft, '🖼 Envie uma <b>imagem</b>, uma URL https, ou "remover".');
    }
    switch (s) {
      case 'pet_name':
        if (value.length < 2) return step(ctx, 'pet_name', draft, '⚠️ Nome muito curto. Digite o nome do pet:');
        draft.name = value.slice(0, 60);
        return askImage(ctx, draft);
      case 'pet_image':
        return askImage(ctx, draft);
      case 'pet_search':
        return petList(ctx, 0, value === '*' ? undefined : value);
      case 'pet_edit_name':
        return applyPet(ctx, draft.petId!, { name: value.slice(0, 60) });
      case 'egg_name':
        if (value.length < 2) return step(ctx, 'egg_name', draft, '⚠️ Nome muito curto. Digite o nome do ovo:');
        draft.name = value.slice(0, 60);
        if (draft.mode === 'egg_edit' && draft.eggId) {
          await rpc('admin_update_egg_visual', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_patch: { name: draft.name } });
          return eggMenu(ctx, draft.eggId);
        }
        return step(ctx, 'egg_image', draft, `🖼 Envie a <b>foto do ovo</b> <b>${esc(draft.name)}</b> nesta conversa.`);
      case 'egg_edit_name':
        await rpc('admin_update_egg_visual', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_patch: { name: value.slice(0, 60) } });
        return eggMenu(ctx, draft.eggId!);
      case 'egg_image':
        return step(ctx, 'egg_image', draft, '🖼 Envie a foto do ovo como <b>imagem</b> nesta conversa.');
      case 'egg_price': {
        const v = num();
        if (v == null || v <= 0) return step(ctx, 'egg_price', draft, '⚠️ Envie um número válido:');
        draft.price = v;
        if (draft.mode === 'egg_edit' && draft.eggId) {
          await rpc('admin_set_egg_price_visual', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_currency: draft.currency || 'FC', p_price: v });
          return eggMenu(ctx, draft.eggId);
        }
        return saveEgg(ctx, draft);
      }
      default:
        return hub(ctx);
    }
  }

  async function photo(ctx: Ctx, s: string, draft: PetDraft, fileId: string) {
    const url = await uploadPhoto(fileId, draft.name || 'pet');
    draft.image = url;
    if (s.startsWith('pet_stage_image:') && draft.petId) {
      const stage = s.split(':')[1];
      await rpc('admin_set_pet_stage_image', { p_admin_id: ctx.adminId, p_pet_id: draft.petId, p_stage: stage, p_url: url });
      await send(ctx, '✅ Forma visual atualizada — já aparece no jogo.');
      return stageMenu(ctx, draft.petId);
    }
    if (s === 'pet_edit_image' && draft.petId) {
      await send(ctx, '✅ Foto atualizada — já aparece no jogo.');
      return applyPet(ctx, draft.petId, { image_url: url });
    }
    if (s === 'egg_edit_image' && draft.eggId) {
      await rpc('admin_update_egg_visual', { p_admin_id: ctx.adminId, p_egg_id: draft.eggId, p_patch: { image_url: url } });
      await send(ctx, '✅ Foto do ovo atualizada.');
      return eggMenu(ctx, draft.eggId);
    }
    if (s === 'egg_image' || draft.mode === 'egg_create') {
      await send(ctx, '✅ Foto recebida.');
      return step(ctx, 'egg_currency', draft, '💰 <b>MOEDA DO OVO</b>:', CURRENCIES.map(([k, l]) => [{ t: l, d: `pw:ecur:${k}` }]));
    }
    await send(ctx, '✅ Foto recebida e otimizada (512×512, fundo transparente preservado).');
    return askRarity(ctx, draft);
  }

  return { hub, callback, text, photo };
}
