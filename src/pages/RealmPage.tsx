import { useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import RealmExplorationMap from '../components/RealmExplorationMap';
import RealmBountyBoard from '../components/RealmBountyBoard';
import RealmDungeonScene from '../components/RealmDungeonScene';
import StrongholdScene from '../components/StrongholdScene';
import {
  REALM_ROOM_LABEL,
  fetchRealmState,
  realmClaimBounty,
  realmClaimBuilding,
  realmClaimCraft,
  realmEnsureBounties,
  realmRuinChoose,
  realmRuinExtract,
  realmRuinStart,
  realmSecondsLeft,
  realmStartCraft,
  realmTimer,
  realmUpgradeBuilding,
  type RealmState,
} from '../realm';

const RUINS_BG = '/assets/game/realm/ruins-bg.jpg';
const REALM_CREST = '/assets/game/realm/realm-crest.png';



type Tab = 'stronghold' | 'map' | 'forge' | 'ruins' | 'bounties';

const TABS: { id: Tab; label: string; glyph: string }[] = [
  { id: 'stronghold', label: 'Stronghold', glyph: '🏰' },
  { id: 'map', label: 'Mapa', glyph: '🗺' },
  { id: 'forge', label: 'Forja', glyph: '⚒' },
  { id: 'ruins', label: 'Ruínas', glyph: '☠' },
  { id: 'bounties', label: 'Contratos', glyph: '📜' },
];

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/**
 * MYTHREON REALM — acesso antecipado (somente admins liberados no backend).
 * Toda a verdade vem de `realm_state`; esta tela apenas renderiza o estado do servidor.
 * UI mobile-first: hierarquia enxuta, detalhes sempre em bottom sheet.
 */
export function RealmPage({ telegramInitData, onBack }: { telegramInitData: string; onBack: () => void }) {
  const qc = useQueryClient();
  const [tab, setTab] = useState<Tab>('stronghold');
  const [now, setNow] = useState(() => Date.now());
  const [notice, setNotice] = useState<string | null>(null);
  const [resourcesOpen, setResourcesOpen] = useState(false);
  const [buildingSheet, setBuildingSheet] = useState<string | null>(null);
  const [recipeSheet, setRecipeSheet] = useState<string | null>(null);
  const [craftQty, setCraftQty] = useState(1);
  
  const [showLockedRecipes, setShowLockedRecipes] = useState(false);

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const { data, isLoading, error } = useQuery<RealmState>({
    queryKey: ['realm', telegramInitData],
    queryFn: () => fetchRealmState(telegramInitData),
    enabled: Boolean(telegramInitData),
    refetchInterval: 30_000,
  });

  const apply = (next: RealmState) => {
    qc.setQueryData(['realm', telegramInitData], next);
    const reward = next.lastReward as Record<string, unknown> | undefined;
    if (reward) setNotice(describeReward(reward));
  };

  const act = useMutation({
    mutationFn: async (run: () => Promise<RealmState>) => run(),
    onSuccess: apply,
    onError: (e: Error) => setNotice(e.message),
  });
  const busy = act.isPending;
  const call = (run: () => Promise<RealmState>) => act.mutate(run);

  /** Awaited variant: the exploration map needs the payload to play its animations. */
  const runAsync = async (fn: () => Promise<RealmState>) => {
    try {
      const next = await fn();
      apply(next);
      return next;
    } catch (e) {
      setNotice((e as Error).message);
      return null;
    }
  };


  useEffect(() => {
    if (!notice) return;
    const id = window.setTimeout(() => setNotice(null), 4000);
    return () => window.clearTimeout(id);
  }, [notice]);

  const balances = data?.balances ?? {};
  const materials = data?.materials ?? [];
  const materialById = useMemo(
    () => Object.fromEntries(materials.map((m) => [m.id, m])),
    [materials],
  );

  /* micro-animações do HUD: flash ao subir nível real e delta ao ganhar material */
  const strongholdLevel = data?.profile?.stronghold_level ?? 1;
  const [levelFlash, setLevelFlash] = useState(false);
  const prevLevel = useRef<number | null>(null);
  useEffect(() => {
    if (prevLevel.current !== null && strongholdLevel > prevLevel.current) {
      setLevelFlash(true);
      const id = window.setTimeout(() => setLevelFlash(false), 1200);
      prevLevel.current = strongholdLevel;
      return () => window.clearTimeout(id);
    }
    prevLevel.current = strongholdLevel;
  }, [strongholdLevel]);

  const [resDelta, setResDelta] = useState<Record<string, number>>({});
  const prevBalances = useRef<Record<string, number> | null>(null);
  useEffect(() => {
    const current: Record<string, number> = {};
    for (const [k, v] of Object.entries(balances)) current[k] = Number(v ?? 0);
    const before = prevBalances.current;
    prevBalances.current = current;
    if (!before) return;
    const gains: Record<string, number> = {};
    for (const [k, v] of Object.entries(current)) {
      const diff = v - (before[k] ?? 0);
      if (diff > 0) gains[k] = diff;
    }
    if (!Object.keys(gains).length) return;
    setResDelta(gains);
    const id = window.setTimeout(() => setResDelta({}), 900);
    return () => window.clearTimeout(id);
  }, [balances]);


  if (isLoading) {
    return (
      <div className="fullscreen-page forge-safe-page overflow-y-auto bg-[#05070f] p-4">
        {[1, 2, 3].map((k) => <div key={k} className="mb-3 h-32 animate-pulse rounded-3xl bg-white/5" />)}
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="fullscreen-page forge-safe-page overflow-y-auto bg-[#05070f] p-6 text-center">
        <p className="mt-16 text-sm text-rose-300">{(error as Error)?.message || 'Falha ao abrir o MYTHREON REALM.'}</p>
        <button onClick={onBack} className="mt-6 rounded-2xl border border-amber-300/40 px-5 py-3 text-xs font-black uppercase tracking-[.2em] text-amber-200">VOLTAR</button>
      </div>
    );
  }

  const profile = data.profile;
  const level = profile?.stronghold_level ?? 1;
  const ruinRun = data.ruinRun;
  const openRooms = data.ruinRooms.filter((r) => r.room_index === (ruinRun?.current_room ?? -1) && r.status === 'open');
  const mainMaterials = materials.slice(0, 3);
  const forgeLevel = data.buildings.find((b) => b.building_type === 'forge')?.level ?? 0;

  const buildingType = data.buildingTypes.find((bt) => bt.id === buildingSheet) ?? null;
  const recipe = data.recipes.find((r) => r.id === recipeSheet) ?? null;


  const openRecipes = data.recipes.filter((r) => forgeLevel >= r.min_forge_level);
  const lockedRecipes = data.recipes.filter((r) => forgeLevel < r.min_forge_level);

  /* Run ativa nas Ruínas → modo dungeon fullscreen (esconde todo o chrome do Realm). */
  if (ruinRun && ruinRun.status === 'running') {
    const region = data.regions.find((r) => r.id === ruinRun.region_id);
    return (
      <RealmDungeonScene
        run={ruinRun}
        rooms={openRooms}
        lastRoom={data.lastRoom}
        regionName={region?.name ?? 'Ruínas Ancestrais'}
        busy={busy}
        onChoose={(branch) => runAsync(() => realmRuinChoose(telegramInitData, ruinRun.id, branch))}
        onExtract={() => runAsync(() => realmRuinExtract(telegramInitData, ruinRun.id))}
        onLeave={() => { setTab('ruins'); qc.invalidateQueries({ queryKey: ['realm', telegramInitData] }); }}
      />
    );
  }


  return (
    <div className="fullscreen-page forge-safe-page overflow-y-auto bg-[#05070f] pb-28">
      {/* TOP HUD premium do Realm */}
      <header className="realm-hud sticky top-0 z-20">
        <div className="realm-hud-atmo" aria-hidden />
        <div className="relative px-3 pb-1.5 pt-2">
          <div className="flex items-center gap-2">
            <button onClick={onBack} className="realm-hud-back">‹ Voltar</button>
            <div className="flex min-w-0 flex-1 items-center justify-center gap-1.5">
              <img src={REALM_CREST} alt="" loading="lazy" width={40} height={40} className="realm-crest" />
              <h1 className="realm-hud-title truncate">MYTHREON REALM</h1>
            </div>
            <div className={`realm-lv-badge ${levelFlash ? 'realm-lv-flash' : ''}`}>
              <span className="realm-lv-cap">Stronghold</span>
              <b className="realm-lv-num">LV.{level}</b>
            </div>
          </div>

          {/* resource bar compacta */}
          <div className="realm-res-bar">
            {mainMaterials.map((m) => (
              <button key={m.id} onClick={() => setResourcesOpen(true)} className="realm-res-pill">
                {m.image_url
                  ? <img src={m.image_url} alt={m.name} loading="lazy" className="h-4 w-4 shrink-0 object-contain" />
                  : <span className="text-[10px] text-amber-200">◆</span>}
                <b className="tabular-nums">{fmt(Number(balances[m.id] ?? 0))}</b>
                {resDelta[m.id] ? <em className="realm-res-delta">+{fmt(resDelta[m.id])}</em> : null}
              </button>
            ))}
            <button onClick={() => setResourcesOpen(true)} aria-label="Recursos" className="realm-res-plus">+</button>
          </div>

          {/* navegação do Realm */}
          <nav className="realm-nav">
            {TABS.map((t) => (
              <button
                key={t.id}
                onClick={() => { setTab(t.id); if (t.id === 'bounties') call(() => realmEnsureBounties(telegramInitData)); }}
                className={`realm-tab ${tab === t.id ? 'realm-tab-on' : ''}`}
              >
                <span className="block text-[14px] leading-4">{t.glyph}</span>
                <span className="block text-[8px] font-black uppercase tracking-[.12em]">{t.label}</span>
              </button>
            ))}
          </nav>
          <div className="realm-hud-rule" aria-hidden />
        </div>
      </header>


      {notice && (
        <p className="mx-4 mt-3 rounded-2xl border border-amber-300/35 bg-amber-500/10 px-3 py-2 text-[10px] font-bold text-amber-100">{notice}</p>
      )}

      <main className="px-4 pt-4">
        {/* ---------- STRONGHOLD ---------- */}
        {tab === 'stronghold' && (
          <StrongholdScene
            buildingTypes={data.buildingTypes}
            buildings={data.buildings}
            level={level}
            now={now}
            craftingCount={data.crafting.length}
            onOpen={setBuildingSheet}
          />
        )}


        {/* ---------- MAP / INTERACTIVE EXPLORATION ---------- */}
        {tab === 'map' && (
          <RealmExplorationMap
            data={data}
            initData={telegramInitData}
            now={now}
            level={level}
            busy={busy}
            call={call}
            run={runAsync}
          />
        )}


        {/* ---------- FORGE / CRAFTING ---------- */}
        {tab === 'forge' && (
          <section className="space-y-4">
            <div className="flex items-baseline justify-between">
              <b className="text-[13px] font-black uppercase tracking-[.12em] text-amber-100">Forja Lv.{forgeLevel}</b>
              <span className="text-[10px] text-slate-500">{data.crafting.length} em produção</span>
            </div>

            {data.crafting.length > 0 && (
              <div className="space-y-1">
                {data.crafting.map((j) => {
                  const left = realmSecondsLeft(j.finishes_at, now);
                  const r = data.recipes.find((x) => x.id === j.recipe_id);
                  return (
                    <div key={j.id} className="flex items-center justify-between border-b border-white/5 py-2">
                      <div>
                        <b className="text-[11px] text-amber-100">{r?.name ?? j.recipe_id}</b>
                        <p className="text-[9px] text-slate-500">x{j.quantity}</p>
                      </div>
                      {left > 0
                        ? <span className="text-[11px] font-bold tabular-nums text-cyan-300">{realmTimer(left)}</span>
                        : <button disabled={busy} onClick={() => call(() => realmClaimCraft(telegramInitData, j.id))} className="rounded-xl bg-gradient-to-r from-emerald-400 to-teal-300 px-3 py-1.5 text-[9px] font-black uppercase tracking-[.14em] text-black">Retirar</button>}
                    </div>
                  );
                })}
              </div>
            )}

            <div>
              <p className="text-[9px] font-black uppercase tracking-[.2em] text-slate-500">Receitas</p>
              {openRecipes.map((r) => {
                const out = r.output_kind === 'material' ? materialById[r.output_ref]?.name ?? r.output_ref : r.output_ref.replace(/_/g, ' ');
                return (
                  <button key={r.id} onClick={() => { setRecipeSheet(r.id); setCraftQty(1); }} className="flex w-full items-center justify-between border-b border-white/5 py-2.5 text-left">
                    <div className="min-w-0">
                      <b className="block text-[11px] font-black text-amber-100">{r.name}</b>
                      <p className="truncate text-[9px] text-slate-500">
                        {Object.entries(r.inputs).map(([id, qty]) => `${fmt(Number(qty))} ${materialById[id]?.name ?? id}`).join(' + ')} → {r.output_qty}x {out}
                      </p>
                    </div>
                    <span className="ml-2 shrink-0 text-[10px] tabular-nums text-slate-400">{realmTimer(r.craft_seconds)}</span>
                  </button>
                );
              })}
            </div>

            {lockedRecipes.length > 0 && (
              <div>
                <button onClick={() => setShowLockedRecipes((v) => !v)} className="text-[10px] font-bold text-slate-500">
                  Receitas bloqueadas ({lockedRecipes.length}) {showLockedRecipes ? '▴' : '▾'}
                </button>
                {showLockedRecipes && lockedRecipes.map((r) => (
                  <p key={r.id} className="border-b border-white/5 py-2 text-[10px] text-slate-500">
                    {r.name} · 🔒 Forja Lv.{r.min_forge_level}
                  </p>
                ))}
              </div>
            )}
          </section>
        )}

        {/* ---------- ANCIENT RUINS ---------- */}
        {tab === 'ruins' && (
          <section className="space-y-4">
            <div className="relative overflow-hidden rounded-3xl">
              <img src={RUINS_BG} alt="Ruínas Ancestrais" loading="lazy" className="h-44 w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-[#05070f] via-transparent to-transparent" />
              <b className="absolute bottom-3 left-4 text-[13px] font-black uppercase tracking-[.14em] text-purple-100">RUÍNAS ANCESTRAIS</b>
            </div>

            {!ruinRun ? (
              <div className="space-y-1">
                {data.regions.filter((r) => r.ruin_enabled && level >= r.unlock_stronghold_level).map((r) => (
                  <div key={r.id} className="flex items-center justify-between border-b border-white/5 py-2.5">
                    <div>
                      <b className="text-[11px] font-black text-purple-100">{r.name}</b>
                      <p className="text-[9px] text-slate-500">10 salas • Poder {fmt(r.recommended_power)}</p>
                    </div>
                    <button disabled={busy} onClick={() => call(() => realmRuinStart(telegramInitData, r.id))} className="rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 px-4 py-2 text-[10px] font-black uppercase tracking-[.14em] text-black disabled:opacity-40">Entrar</button>
                  </div>
                ))}
                {data.regions.filter((r) => r.ruin_enabled && level < r.unlock_stronghold_level).map((r) => (
                  <p key={r.id} className="py-1.5 text-[10px] text-slate-500">🔒 {r.name} — Stronghold Lv.{r.unlock_stronghold_level}</p>
                ))}
              </div>
            ) : (
              <div className="space-y-3">
                <div className="flex justify-between text-center">
                  <Stat label="Sala" value={`${ruinRun.current_room + 1}/10`} />
                  <Stat label="Vitalidade" value={`${ruinRun.hp}%`} />
                  <Stat label="Moedas" value={fmt(ruinRun.ruin_coins)} />
                </div>
                {data.lastRoom && <p className="text-[10px] text-slate-400">{describeRoom(data.lastRoom)}</p>}
                <div className="grid grid-cols-2 gap-2">
                  {openRooms.map((room) => (
                    <button key={room.id} disabled={busy} onClick={() => call(() => realmRuinChoose(telegramInitData, ruinRun.id, room.branch))} className="rounded-3xl bg-white/[.05] px-3 py-5 text-center">
                      <b className="text-[11px] font-black uppercase tracking-[.14em] text-purple-100">{REALM_ROOM_LABEL[room.room_type] ?? room.room_type}</b>
                      <p className="mt-1 text-[9px] text-slate-500">Dificuldade {room.config?.difficulty ?? 1}</p>
                    </button>
                  ))}
                </div>
                <button disabled={busy} onClick={() => call(() => realmRuinExtract(telegramInitData, ruinRun.id))} className="w-full rounded-2xl border border-white/15 py-3 text-[10px] font-bold text-slate-200">Extrair com o loot</button>
              </div>
            )}
          </section>
        )}

        {/* ---------- BOUNTIES ---------- */}
        {tab === 'bounties' && (
          <RealmBountyBoard
            bounties={data.bounties}
            busy={busy}
            now={now}
            onClaim={(id) => call(() => realmClaimBounty(telegramInitData, id))}
          />
        )}

      </main>

      {/* ---------- SHEETS ---------- */}
      <Sheet open={resourcesOpen} onClose={() => setResourcesOpen(false)} title="Recursos do Realm">
        <div className="grid grid-cols-2 gap-2">
          {materials.map((m) => (
            <div key={m.id} className="flex items-center gap-2 rounded-2xl bg-white/[.04] p-2">
              {m.image_url && <img src={m.image_url} alt={m.name} loading="lazy" className="h-7 w-7 object-contain" />}
              <div className="min-w-0">
                <p className="truncate text-[9px] text-slate-400">{m.name}</p>
                <b className="text-[11px] tabular-nums text-amber-100">{fmt(Number(balances[m.id] ?? 0))}</b>
              </div>
            </div>
          ))}
        </div>
      </Sheet>

      <Sheet open={Boolean(buildingType)} onClose={() => setBuildingSheet(null)} title={buildingType ? `${buildingType.name} — Lv.${data.buildings.find((b) => b.building_type === buildingType.id)?.level ?? 0}` : ''}>
        {buildingType && (() => {
          const b = data.buildings.find((x) => x.building_type === buildingType.id);
          const lvl = b?.level ?? 0;
          const left = realmSecondsLeft(b?.upgrade_finishes_at, now);
          const upgrading = b?.status !== 'idle' && left > 0;
          const ready = b?.status !== 'idle' && left <= 0;
          const cost = Math.round(buildingType.base_fc_cost * Math.pow(1.55, lvl));
          const castleLevel = data.buildings.find((x) => x.building_type === 'castle')?.level ?? 0;
          const gated = buildingType.id !== 'castle' && lvl + 1 > castleLevel;
          const maxed = lvl >= buildingType.max_level;
          return (
            <div className="realm-sheet-card space-y-3">
              <div className="flex items-start gap-3">
                {buildingType.image_url && (
                  <img src={buildingType.image_url} alt="" loading="lazy" className="h-16 w-16 flex-none object-contain drop-shadow-[0_6px_14px_rgba(251,191,36,.35)]" />
                )}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <b className="text-[13px] font-black uppercase tracking-[.1em] text-amber-100">{buildingType.name}</b>
                    <span className="stronghold-seal">Lv.{lvl}</span>
                  </div>
                  <p className="mt-1 text-[9.5px] leading-snug text-slate-400">{buildingType.description}</p>
                  <p className="mt-1 text-[9px] font-bold uppercase tracking-[.14em] text-slate-500">Nível máximo {buildingType.max_level} · obra base {realmTimer(buildingType.base_seconds)}</p>
                </div>
              </div>

              {buildingType.id === 'forge' && lvl > 0 && (
                <button onClick={() => { setBuildingSheet(null); setTab('forge'); }} className="w-full rounded-2xl border border-amber-300/40 bg-amber-500/10 py-2.5 text-[11px] font-black uppercase tracking-[.16em] text-amber-100">Abrir Forja</button>
              )}
              {buildingType.id === 'watchtower' && (() => {
                const next = data.regions.filter((r) => level < r.unlock_stronghold_level).sort((a, b) => a.unlock_stronghold_level - b.unlock_stronghold_level)[0];
                return (
                  <p className="rounded-2xl border border-cyan-300/20 bg-cyan-500/5 px-3 py-2 text-[10px] leading-4 text-cyan-200">
                    {next ? `Próxima região: ${next.name} — requer Stronghold Lv.${next.unlock_stronghold_level}` : 'Todas as regiões já estão desbloqueadas.'}
                  </p>
                );
              })()}

              {gated && !upgrading && !ready && (
                <p className="rounded-2xl border border-slate-400/25 bg-white/[.04] px-3 py-2 text-[10px] font-bold text-slate-300">
                  Bloqueado · evolua o Castelo até o Lv.{lvl + 1} para liberar esta obra.
                </p>
              )}

              <div className="space-y-1.5">
                <p className="text-[9px] font-black uppercase tracking-[.2em] text-slate-500">{lvl === 0 ? 'Custo de construção' : 'Custo de evolução'}</p>
                <div className="flex flex-wrap gap-1.5">
                  <span className="realm-cost-chip realm-cost-chip--gold">
                    <img src="/assets/game/coins/forge-coin.png" alt="" loading="lazy" className="h-4 w-4 object-contain" />
                    <b>{fmt(cost)}</b> FC
                  </span>
                  {Object.entries(buildingType.cost_materials).map(([id, qty]) => (
                    <span key={id} className="realm-cost-chip">
                      {materialById[id]?.image_url && <img src={materialById[id]!.image_url as string} alt="" loading="lazy" className="h-4 w-4 object-contain" />}
                      <b>{fmt(Math.ceil(Number(qty) * Math.pow(1.35, lvl)))}</b> {materialById[id]?.name ?? id}
                    </span>
                  ))}
                </div>
              </div>

              {upgrading ? (
                <p className="text-center text-[11px] font-black tabular-nums text-cyan-300">Em obras · {realmTimer(left)}</p>
              ) : ready ? (
                <button disabled={busy} onClick={() => call(() => realmClaimBuilding(telegramInitData, buildingType.id))} className="realm-action-btn realm-action-btn--done">Concluir</button>
              ) : (
                <button disabled={busy || maxed} onClick={() => call(() => realmUpgradeBuilding(telegramInitData, buildingType.id))} className="realm-action-btn">
                  {maxed ? 'Nível máximo' : lvl === 0 ? 'Construir' : 'Evoluir'}
                </button>
              )}
            </div>
          );
        })()}
      </Sheet>


      <Sheet open={Boolean(recipe)} onClose={() => setRecipeSheet(null)} title={recipe?.name ?? ''}>
        {recipe && (
          <div className="space-y-3">
            <div className="space-y-1">
              <p className="text-[9px] font-black uppercase tracking-[.2em] text-slate-500">Requer</p>
              {Object.entries(recipe.inputs).map(([id, qty]) => (
                <p key={id} className="text-[11px] text-slate-300">{materialById[id]?.name ?? id} x{fmt(Number(qty) * craftQty)}</p>
              ))}
              <p className="text-[11px] text-amber-100">{fmt(recipe.fc_cost * craftQty)} FC</p>
            </div>
            <p className="text-[11px] text-emerald-200">
              Produz {recipe.output_qty * craftQty}x {recipe.output_kind === 'material' ? materialById[recipe.output_ref]?.name ?? recipe.output_ref : recipe.output_ref.replace(/_/g, ' ')} · {realmTimer(recipe.craft_seconds)}
            </p>
            <div className="flex items-center justify-center gap-4">
              <button onClick={() => setCraftQty((q) => Math.max(1, q - 1))} className="h-9 w-9 rounded-full border border-white/15 text-slate-200">−</button>
              <b className="w-8 text-center text-[15px] tabular-nums text-amber-100">{craftQty}</b>
              <button onClick={() => setCraftQty((q) => Math.min(10, q + 1))} className="h-9 w-9 rounded-full border border-white/15 text-slate-200">+</button>
            </div>
            <button disabled={busy} onClick={() => { call(() => realmStartCraft(telegramInitData, recipe.id, craftQty)); setRecipeSheet(null); }} className="w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black uppercase tracking-[.16em] text-black disabled:opacity-40">Forjar</button>
          </div>
        )}
      </Sheet>
    </div>
  );
}

function Sheet({ open, onClose, title, children }: { open: boolean; onClose: () => void; title: string; children: React.ReactNode }) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end" role="dialog">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-black/70" />
      <div className="relative w-full rounded-t-3xl border-t border-white/10 bg-[#0a0d18] p-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        <div className="mb-3 flex items-center justify-between gap-2">
          <b className="text-[12px] font-black uppercase tracking-[.12em] text-amber-100">{title}</b>
          <button onClick={onClose} className="text-[13px] text-slate-400">✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex-1">
      <p className="text-[8px] font-black uppercase tracking-[.2em] text-slate-500">{label}</p>
      <b className="text-[13px] text-amber-100">{value}</b>
    </div>
  );
}

function describeReward(reward: Record<string, unknown>) {
  const parts: string[] = [];
  if (reward.fc) parts.push(`${fmt(Number(reward.fc))} FC`);
  if (reward.qty && reward.material) parts.push(`${fmt(Number(reward.qty))} ${String(reward.material).replace(/_/g, ' ')}`);
  if (reward.name) parts.push(`${reward.qty ?? ''} ${String(reward.name)}`.trim());
  if (reward.fragments) parts.push(`${fmt(Number(reward.fragments))} fragmentos`);
  Object.entries(reward).forEach(([key, value]) => {
    if (['fc', 'qty', 'material', 'name', 'kind', 'ref', 'cleared', 'fragments'].includes(key)) return;
    if (typeof value === 'number') parts.push(`${fmt(value)} ${key.replace(/_/g, ' ')}`);
  });
  return parts.length ? `Recebido: ${parts.join(' · ')}` : 'Recompensa entregue.';
}

function describeRoom(room: Record<string, unknown>) {
  const type = REALM_ROOM_LABEL[String(room.roomType)] ?? String(room.roomType);
  const dmg = Number(room.damage ?? 0);
  const coins = Number(room.coins ?? 0);
  const extra = room.material ? ` · ${fmt(Number(room.qty ?? 0))} ${String(room.material).replace(/_/g, ' ')}` : '';
  const heal = dmg < 0 ? ` · +${Math.abs(dmg)}% vitalidade` : dmg > 0 ? ` · -${dmg}% vitalidade` : '';
  return `${type}${heal} · +${fmt(coins)} moedas${extra}${room.result === 'failed' ? ' · VOCÊ CAIU' : room.result === 'cleared' ? ' · RUÍNA CONCLUÍDA' : ''}`;
}
