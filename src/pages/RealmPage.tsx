import { useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import RealmExplorationMap from '../components/RealmExplorationMap';
import RealmBountyBoard from '../components/RealmBountyBoard';
import RealmDungeonScene from '../components/RealmDungeonScene';
import RealmForgeScene from '../components/RealmForgeScene';
import StrongholdScene from '../components/StrongholdScene';

import { useT } from '../LanguageContext';
import type { Translator } from '../i18n';
import {
  REALM_ROOM_LABEL_KEY,
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

const TABS: { id: Tab; labelKey: string; art: string }[] = [
  { id: 'stronghold', labelKey: 'realm.tab.stronghold', art: '/assets/game/realm/tab-stronghold.png' },
  { id: 'map', labelKey: 'realm.tab.map', art: '/assets/game/realm/tab-map.png' },
  { id: 'forge', labelKey: 'realm.tab.forge', art: '/assets/game/realm/tab-forge.png' },
  { id: 'ruins', labelKey: 'realm.tab.ruins', art: '/assets/game/realm/tab-ruins.png' },
  { id: 'bounties', labelKey: 'realm.tab.bounties', art: '/assets/game/realm/tab-contracts.png' },
];

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/**
 * MYTHREON REALM — acesso antecipado (somente admins liberados no backend).
 * Toda a verdade vem de `realm_state`; esta tela apenas renderiza o estado do servidor.
 * UI mobile-first: hierarquia enxuta, detalhes sempre em bottom sheet.
 */
export function RealmPage({ telegramInitData, onBack }: { telegramInitData: string; onBack: () => void }) {
  const t = useT();
  const qc = useQueryClient();
  const [tab, setTab] = useState<Tab>('stronghold');
  const [now, setNow] = useState(() => Date.now());
  const [notice, setNotice] = useState<string | null>(null);
  const [resourcesOpen, setResourcesOpen] = useState(false);
  const [buildingSheet, setBuildingSheet] = useState<string | null>(null);
  

  const [dungeonOpen, setDungeonOpen] = useState(true);
  const [ruinRegion, setRuinRegion] = useState<string | null>(null);


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
    if (reward) setNotice(describeReward(reward, t));
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
        <p className="mt-16 text-sm text-rose-300">{(error as Error)?.message || t('realm.loadFail')}</p>
        <button onClick={onBack} className="mt-6 rounded-2xl border border-amber-300/40 px-5 py-3 text-xs font-black uppercase tracking-[.2em] text-amber-200">{t('realm.backCta')}</button>
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



  /* Run ativa nas Ruínas → modo dungeon fullscreen (esconde todo o chrome do Realm). */
  if (ruinRun && ruinRun.status === 'running' && dungeonOpen) {
    const region = data.regions.find((r) => r.id === ruinRun.region_id);
    return (
      <RealmDungeonScene
        run={ruinRun}
        rooms={openRooms}
        lastRoom={data.lastRoom}
        regionName={region?.name ?? t('realm.ruins.title')}
        busy={busy}
        onChoose={(branch) => runAsync(() => realmRuinChoose(telegramInitData, ruinRun.id, branch))}
        onExtract={() => runAsync(() => realmRuinExtract(telegramInitData, ruinRun.id))}
        onLeave={() => { setDungeonOpen(false); setTab('ruins'); qc.invalidateQueries({ queryKey: ['realm', telegramInitData] }); }}
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
            <button onClick={onBack} className="realm-hud-back">{t('realm.back')}</button>
            <div className="flex min-w-0 flex-1 items-center justify-center gap-1.5">
              <img src={REALM_CREST} alt="" loading="lazy" width={40} height={40} className="realm-crest" />
              <h1 className="realm-hud-title truncate">MYTHREON REALM</h1>
            </div>
            <div className={`realm-lv-badge ${levelFlash ? 'realm-lv-flash' : ''}`}>
              <span className="realm-lv-cap">{t('realm.strongholdCap')}</span>
              <b className="realm-lv-num">LV.{level}</b>
            </div>
          </div>

          {/* resource bar compacta */}
          <div className="realm-res-bar">
            {mainMaterials.map((m) => (
              <button key={m.id} onClick={() => setResourcesOpen(true)} className="realm-res-pill">
                {m.image_url
                  ? <img src={m.image_url} alt={m.name} loading="lazy" className="h-5 w-5 shrink-0 object-contain" />
                  : <span className="text-[10px] text-amber-200">◆</span>}
                <span className="min-w-0 text-left">
                  <span className="realm-res-name truncate">{m.name}</span>
                  <b className="block tabular-nums leading-3">{fmt(Number(balances[m.id] ?? 0))}</b>
                </span>
                {resDelta[m.id] ? <em className="realm-res-delta">+{fmt(resDelta[m.id])}</em> : null}
              </button>
            ))}

            <button onClick={() => setResourcesOpen(true)} aria-label={t('realm.resources')} className="realm-res-plus">+</button>
          </div>

          {/* navegação do Realm */}
          <nav className="realm-nav">
            {TABS.map((item) => (
              <button
                key={item.id}
                onClick={() => { setTab(item.id); if (item.id === 'bounties') call(() => realmEnsureBounties(telegramInitData)); }}
                className={`realm-tab ${tab === item.id ? 'realm-tab-on' : ''}`}
              >
                <img src={item.art} alt="" loading="lazy" className="realm-tab-art" />
                <span className="realm-tab-label">{t(item.labelKey)}</span>
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
          <RealmForgeScene
            forgeLevel={forgeLevel}
            forgeType={data.buildingTypes.find((bt) => bt.id === 'forge') ?? null}
            recipes={data.recipes}
            materials={materials}
            balances={balances}
            fc={data.fc}
            jobs={data.crafting}
            now={now}
            busy={busy}
            onStartCraft={(recipeId, quantity) => runAsync(() => realmStartCraft(telegramInitData, recipeId, quantity))}
            onClaim={(jobId) => runAsync(() => realmClaimCraft(telegramInitData, jobId))}
            onUpgradeForge={() => setBuildingSheet('forge')}
            onOpenResources={() => setResourcesOpen(true)}
          />
        )}


        {/* ---------- ANCIENT RUINS ---------- */}
        {tab === 'ruins' && (
          <section className="space-y-4">
            <div className="relative overflow-hidden rounded-3xl">
              <img src={RUINS_BG} alt="" loading="lazy" className="h-44 w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-[#05070f] via-transparent to-transparent" />
              <b className="absolute bottom-3 left-4 text-[13px] font-black uppercase tracking-[.14em] text-purple-100">{t('realm.ruins.title')}</b>
            </div>

            {ruinRun && ruinRun.status === 'running' && (
              <button onClick={() => setDungeonOpen(true)} className="w-full rounded-2xl bg-gradient-to-r from-purple-500 to-fuchsia-400 py-3 text-[11px] font-black uppercase tracking-[.16em] text-black">
                {t('realm.ruins.resume', { room: Math.min(ruinRun.current_room + 1, 10) })}
              </button>
            )}

            {!ruinRun ? (
              <div className="space-y-4">
                {/* estatísticas do jogador */}
                <div className="grid grid-cols-4 gap-1 rounded-3xl border border-white/10 bg-white/[.03] px-3 py-3 text-center">
                  <Stat label={t('realm.ruins.statRuns')} value={fmt(data.ruinStats?.runs ?? 0)} />
                  <Stat label={t('realm.ruins.statClears')} value={fmt(data.ruinStats?.clears ?? 0)} />
                  <Stat label={t('realm.ruins.statDeepest')} value={`${Math.min(10, data.ruinStats?.deepest ?? 0)}/10`} />
                  <Stat label={t('realm.ruins.statBest')} value={fmt(data.ruinStats?.bestLoot ?? 0)} />
                </div>

                <div>
                  <b className="text-[11px] font-black uppercase tracking-[.16em] text-purple-100">{t('realm.ruins.entryTitle')}</b>
                  <p className="mt-1 text-[10px] leading-relaxed text-slate-400">{t('realm.ruins.entryDesc')}</p>
                </div>

                {/* seleção de região */}
                <div className="flex flex-wrap gap-2">
                  {data.regions.filter((r) => r.ruin_enabled && level >= r.unlock_stronghold_level).map((r) => (
                    <button
                      key={r.id}
                      onClick={() => setRuinRegion(r.id)}
                      className={`rounded-2xl border px-3 py-2 text-[10px] font-black uppercase tracking-[.12em] ${
                        (ruinRegion ?? '') === r.id
                          ? 'border-amber-300/70 bg-amber-300/15 text-amber-100'
                          : 'border-white/10 bg-white/[.03] text-slate-300'
                      }`}
                    >
                      {r.name}
                      <span className="ml-1 text-[8px] font-semibold text-slate-500">{fmt(r.recommended_power)}</span>
                    </button>
                  ))}
                </div>

                {/* tiers de entrada */}
                <div className="space-y-2">
                  {(['fc', 'ton'] as const).map((tier) => {
                    const cost = tier === 'fc' ? Number(data.ruinEntry?.fc_cost ?? 100000) : Number(data.ruinEntry?.ton_cost ?? 0.5);
                    const mult = Number(data.ruinEntry?.ton_reward_multiplier ?? 1.6);
                    const balance = tier === 'fc' ? Number(data.fc ?? 0) : Number(data.tonBalance ?? 0);
                    const enough = balance >= cost;
                    const region = ruinRegion ?? data.regions.find((r) => r.ruin_enabled && level >= r.unlock_stronghold_level)?.id;
                    return (
                      <div
                        key={tier}
                        className={`rounded-3xl border p-4 ${
                          tier === 'ton'
                            ? 'border-amber-300/40 bg-gradient-to-br from-amber-400/12 via-transparent to-fuchsia-500/10'
                            : 'border-white/10 bg-white/[.03]'
                        }`}
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <b className={`text-[11px] font-black uppercase tracking-[.16em] ${tier === 'ton' ? 'text-amber-100' : 'text-slate-100'}`}>
                              {t(tier === 'ton' ? 'realm.ruins.tierTon' : 'realm.ruins.tierFc')}
                            </b>
                            <p className="mt-1 max-w-[190px] text-[9px] leading-relaxed text-slate-400">
                              {tier === 'ton'
                                ? t('realm.ruins.tierTonPerks', { mult: mult.toFixed(1) })
                                : t('realm.ruins.tierFcPerks')}
                            </p>
                          </div>
                          <div className="text-right">
                            <b className={`block text-[13px] font-black ${tier === 'ton' ? 'text-amber-200' : 'text-slate-100'}`}>
                              {tier === 'fc' ? `${fmt(cost)} FC` : `${cost.toFixed(2)} TON`}
                            </b>
                            <span className="text-[8px] uppercase tracking-[.12em] text-slate-500">
                              {t(tier === 'fc' ? 'realm.ruins.yourFc' : 'realm.ruins.yourTon')}:{' '}
                              {tier === 'fc' ? fmt(balance) : balance.toFixed(2)}
                            </span>
                          </div>
                        </div>
                        <button
                          disabled={busy || !enough || !region}
                          onClick={() => { if (region) { setDungeonOpen(true); call(() => realmRuinStart(telegramInitData, region, tier)); } }}
                          className={`mt-3 w-full rounded-2xl py-2.5 text-[10px] font-black uppercase tracking-[.16em] disabled:opacity-40 ${
                            tier === 'ton'
                              ? 'bg-gradient-to-r from-amber-400 to-yellow-200 text-black'
                              : 'border border-white/15 text-slate-100'
                          }`}
                        >
                          {enough ? t('realm.ruins.enter') : t('realm.ruins.notEnough')}
                        </button>
                      </div>
                    );
                  })}
                </div>

                {/* histórico */}
                <div className="rounded-3xl border border-white/10 bg-white/[.02] p-4">
                  <b className="text-[10px] font-black uppercase tracking-[.16em] text-slate-300">{t('realm.ruins.history')}</b>
                  {(data.ruinStats?.recent ?? []).length === 0 ? (
                    <p className="mt-2 text-[10px] text-slate-500">{t('realm.ruins.historyEmpty')}</p>
                  ) : (
                    <div className="mt-2 space-y-1">
                      {(data.ruinStats?.recent ?? []).map((h, i) => (
                        <div key={i} className="flex items-center justify-between border-b border-white/5 py-1.5 text-[9px]">
                          <span className="text-slate-300">
                            {data.regions.find((r) => r.id === h.region)?.name ?? h.region}
                            <em className={`ml-1 not-italic ${h.tier === 'ton' ? 'text-amber-300' : 'text-slate-500'}`}>{h.tier === 'ton' ? 'TON' : 'FC'}</em>
                          </span>
                          <span className={h.status === 'cleared' ? 'text-emerald-300' : h.status === 'failed' ? 'text-rose-300' : 'text-slate-400'}>
                            {Math.min(10, h.room)}/10 · {fmt(Number(h.fc ?? 0))} FC
                          </span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {data.regions.filter((r) => r.ruin_enabled && level < r.unlock_stronghold_level).map((r) => (
                  <p key={r.id} className="text-[10px] text-slate-500">{t('realm.ruins.locked', { name: r.name, level: r.unlock_stronghold_level })}</p>
                ))}
              </div>

            ) : (
              <div className="space-y-3">
                <div className="flex justify-between text-center">
                  <Stat label={t('realm.ruins.room')} value={`${ruinRun.current_room + 1}/10`} />
                  <Stat label={t('realm.ruins.vitality')} value={`${ruinRun.hp}%`} />
                  <Stat label={t('realm.ruins.coins')} value={fmt(ruinRun.ruin_coins)} />
                </div>
                {data.lastRoom && <p className="text-[10px] text-slate-400">{describeRoom(data.lastRoom, t)}</p>}
                <div className="grid grid-cols-2 gap-2">
                  {openRooms.map((room) => (
                    <button key={room.id} disabled={busy} onClick={() => call(() => realmRuinChoose(telegramInitData, ruinRun.id, room.branch))} className="rounded-3xl bg-white/[.05] px-3 py-5 text-center">
                      <b className="text-[11px] font-black uppercase tracking-[.14em] text-purple-100">{t(REALM_ROOM_LABEL_KEY[room.room_type] ?? '') || room.room_type}</b>
                      <p className="mt-1 text-[9px] text-slate-500">{t('realm.difficulty')} {room.config?.difficulty ?? 1}</p>
                    </button>
                  ))}
                </div>
                <button disabled={busy} onClick={() => call(() => realmRuinExtract(telegramInitData, ruinRun.id))} className="w-full rounded-2xl border border-white/15 py-3 text-[10px] font-bold text-slate-200">{t('realm.ruins.extract')}</button>
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
      <Sheet open={resourcesOpen} onClose={() => setResourcesOpen(false)} title={t('realm.resourcesTitle')}>
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
                  <p className="mt-1 text-[9px] font-bold uppercase tracking-[.14em] text-slate-500">{t('realm.build.maxInfo', { max: buildingType.max_level, time: realmTimer(buildingType.base_seconds) })}</p>
                </div>
              </div>

              {buildingType.id === 'forge' && lvl > 0 && (
                <button onClick={() => { setBuildingSheet(null); setTab('forge'); }} className="w-full rounded-2xl border border-amber-300/40 bg-amber-500/10 py-2.5 text-[11px] font-black uppercase tracking-[.16em] text-amber-100">{t('realm.build.openForge')}</button>
              )}
              {buildingType.id === 'watchtower' && (() => {
                const next = data.regions.filter((r) => level < r.unlock_stronghold_level).sort((a, b) => a.unlock_stronghold_level - b.unlock_stronghold_level)[0];
                return (
                  <p className="rounded-2xl border border-cyan-300/20 bg-cyan-500/5 px-3 py-2 text-[10px] leading-4 text-cyan-200">
                    {next ? t('realm.build.nextRegion', { name: next.name, level: next.unlock_stronghold_level }) : t('realm.build.allUnlocked')}
                  </p>
                );
              })()}

              {gated && !upgrading && !ready && (
                <p className="rounded-2xl border border-slate-400/25 bg-white/[.04] px-3 py-2 text-[10px] font-bold text-slate-300">
                  {t('realm.build.gated', { level: lvl + 1 })}
                </p>
              )}

              <div className="space-y-1.5">
                <p className="text-[9px] font-black uppercase tracking-[.2em] text-slate-500">{lvl === 0 ? t('realm.build.costBuild') : t('realm.build.costUpgrade')}</p>
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
                <p className="text-center text-[11px] font-black tabular-nums text-cyan-300">{t('realm.build.working', { time: realmTimer(left) })}</p>
              ) : ready ? (
                <button disabled={busy} onClick={() => call(() => realmClaimBuilding(telegramInitData, buildingType.id))} className="realm-action-btn realm-action-btn--done">{t('realm.build.finish')}</button>
              ) : (
                <button disabled={busy || maxed} onClick={() => call(() => realmUpgradeBuilding(telegramInitData, buildingType.id))} className="realm-action-btn">
                  {maxed ? t('realm.build.maxed') : lvl === 0 ? t('realm.build.build') : t('realm.build.upgrade')}
                </button>
              )}
            </div>
          );
        })()}
      </Sheet>


    </div>
  );
}

function Sheet({ open, onClose, title, children }: { open: boolean; onClose: () => void; title: string; children: React.ReactNode }) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end" role="dialog">
      <button aria-label="close" onClick={onClose} className="absolute inset-0 bg-black/70" />
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

function describeReward(reward: Record<string, unknown>, t: Translator) {
  const parts: string[] = [];
  if (reward.fc) parts.push(`${fmt(Number(reward.fc))} FC`);
  if (reward.qty && reward.material) parts.push(`${fmt(Number(reward.qty))} ${String(reward.material).replace(/_/g, ' ')}`);
  if (reward.name) parts.push(`${reward.qty ?? ''} ${String(reward.name)}`.trim());
  if (reward.fragments) parts.push(`${fmt(Number(reward.fragments))} ${t('realm.reward.fragments')}`);
  Object.entries(reward).forEach(([key, value]) => {
    if (['fc', 'qty', 'material', 'name', 'kind', 'ref', 'cleared', 'fragments'].includes(key)) return;
    if (typeof value === 'number') parts.push(`${fmt(value)} ${key.replace(/_/g, ' ')}`);
  });
  return parts.length ? t('realm.reward.received', { list: parts.join(' · ') }) : t('realm.reward.delivered');
}

function describeRoom(room: Record<string, unknown>, t: Translator) {
  const type = t(REALM_ROOM_LABEL_KEY[String(room.roomType)] ?? '') || String(room.roomType);
  const dmg = Number(room.damage ?? 0);
  const coins = Number(room.coins ?? 0);
  const extra = room.material ? ` · ${fmt(Number(room.qty ?? 0))} ${String(room.material).replace(/_/g, ' ')}` : '';
  const heal = dmg < 0 ? ` · +${Math.abs(dmg)}% ${t('realm.reward.vitality')}` : dmg > 0 ? ` · -${dmg}% ${t('realm.reward.vitality')}` : '';
  return `${type}${heal} · +${fmt(coins)} ${t('realm.reward.coins')}${extra}${room.result === 'failed' ? ` · ${t('realm.reward.youFell')}` : room.result === 'cleared' ? ` · ${t('realm.ruins.cleared')}` : ''}`;
}
