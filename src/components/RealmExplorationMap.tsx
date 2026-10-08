import { useEffect, useMemo, useRef, useState } from 'react';
import {
  realmClaimExpedition,
  realmExploreAbandon,
  realmExploreAuto,
  realmExploreChoose,
  realmExploreEnter,
  realmExploreExtract,
  realmExploreStart,
  realmSecondsLeft,
  realmStartExpedition,
  realmTimer,
  type RealmExploreLog,
  type RealmExploreNode,
  type RealmState,
} from '../realm';
import RealmBattleScene from './RealmBattleScene';
import RealmRunScene from './RealmRunScene';
import { useT } from '../LanguageContext';

const WORLD_MAP = '/assets/game/realm/world-map.png';

const DEPTH_TIER_KEY: Record<string, string> = {
  normal: 'realm.tier.normal',
  hard: 'realm.tier.hard',
  elite: 'realm.tier.elite',
  mythic: 'realm.tier.mythic',
  abyssal: 'realm.tier.abyssal',
};

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/** Region label anchors over the painted world map (percent of the art). */
const REGION_SPOT: Record<string, { x: number; y: number }> = {
  greenvale: { x: 16, y: 88 },
  'crystal-rift': { x: 50, y: 47 },
  crystal_rift: { x: 50, y: 47 },
  abyss: { x: 83, y: 23 },
  'the-abyss': { x: 83, y: 23 },
};
const FALLBACK_SPOT: { x: number; y: number }[] = [
  { x: 16, y: 88 },
  { x: 50, y: 47 },
  { x: 83, y: 23 },
  { x: 32, y: 34 },
  { x: 68, y: 80 },
];


type Props = {
  data: RealmState;
  initData: string;
  now: number;
  level: number;
  busy: boolean;
  call: (run: () => Promise<RealmState>) => void;
  /** Resolves so the caller can commit state and we can react to `lastNode`. */
  run: (fn: () => Promise<RealmState>) => Promise<RealmState | null>;
};

/**
 * 🗺️ MYTHREON REALM — WORLD MAP + EXPLORATION ENTRY.
 *
 * Out of a run, the world map is clickable: each region is a glowing pin and the legacy
 * timer expeditions stay available as the secondary AFK mode. Once a server-authoritative
 * run exists (`realm_explore_*`), the whole screen is handed over to `RealmRunScene`, the
 * cinematic exploration scene (real places, party walking, fog of war, camera pan).
 */
export default function RealmExplorationMap({ data, initData, now, level, busy, call, run }: Props) {
  const t = useT();
  const regions = data.regions;
  const [selected, setSelected] = useState<string | null>(null);
  const [afkOpen, setAfkOpen] = useState(false);
  const [combat, setCombat] = useState<RealmExploreLog | null>(null);
  const [flash, setFlash] = useState<string | null>(null);
  const [moving, setMoving] = useState(false);
  const [confirm, setConfirm] = useState<string | null>(null);
  const combatTimer = useRef<number | null>(null);

  const exploreRun = data.exploreRun;
  const nodes = data.exploreNodes ?? [];
  const region = regions.find((r) => r.id === (exploreRun?.region_id ?? selected)) ?? null;
  const regionLocked = region ? level < region.unlock_stronghold_level : true;
  /** Server-computed depth progression + entry cost for the selected region. */
  const meta = (data.regionMeta ?? []).find((m) => m.regionId === region?.id) ?? null;
  const affordable = !meta || data.fc >= meta.stats.entryCost;

  const materialById = useMemo(
    () => Object.fromEntries(data.materials.map((m) => [m.id, m])),
    [data.materials],
  );

  useEffect(() => () => { if (combatTimer.current) window.clearTimeout(combatTimer.current); }, []);

  /** Plays the combat scene / loot toast for the node the server just resolved. */
  const consume = (next: RealmState | null) => {
    const log = next?.lastNode;
    if (!log || log.result === 'pending') return;
    if (log.rounds && log.rounds.length > 0) {
      setCombat(log);
    } else {
      const bits: string[] = [];
      if (Number(log.fc)) bits.push(`+${fmt(Number(log.fc))} FC`);
      if (Number(log.fragments)) bits.push(`+${fmt(Number(log.fragments))} frag.`);
      if (log.material && Number(log.materialQty)) {
        bits.push(`+${fmt(Number(log.materialQty))} ${materialById[log.material]?.name ?? log.material}`);
      }
      if (Number(log.damage) > 0) bits.push(`−${log.damage} HP`);
      if (Number(log.damage) < 0) bits.push(`+${Math.abs(Number(log.damage))} HP`);
      setFlash(bits.length ? bits.join('  ') : t('realm.map.nothing'));
      window.setTimeout(() => setFlash(null), 2600);
    }
  };

  const enter = async (node: RealmExploreNode) => {
    if (!exploreRun || busy || moving) return;
    setMoving(true);
    window.setTimeout(() => setMoving(false), 620);
    const next = await run(() => realmExploreEnter(initData, exploreRun.id, node.id));
    consume(next);
  };

  const choose = async (option: string) => {
    if (!exploreRun) return;
    const next = await run(() => realmExploreChoose(initData, exploreRun.id, option));
    consume(next);
  };


  // ── NO ACTIVE RUN: clickable world map ───────────────────────────────────
  if (!exploreRun) {
    return (
      <section className="space-y-3">
        {/* WORLD MAP — single painted world, region names written on the terrain */}
        <div className="realm-world relative overflow-hidden">
          <img src={WORLD_MAP} alt="" loading="lazy" className="block w-full" />
          {regions.map((r, i) => {
            const spot = REGION_SPOT[r.id] ?? FALLBACK_SPOT[i % FALLBACK_SPOT.length];
            const locked = level < r.unlock_stronghold_level;
            const on = selected === r.id;
            return (
              <button
                key={r.id}
                onClick={() => setSelected(r.id)}
                aria-label={r.name}
                style={{ left: `${spot.x}%`, top: `${spot.y}%` }}
                className={`realm-world-hotspot absolute -translate-x-1/2 -translate-y-1/2 ${on ? 'is-on' : ''} ${locked ? 'is-locked' : ''}`}
              >
                <span className="sr-only">{r.name}</span>
              </button>
            );
          })}
        </div>

        {/* REGION DOSSIER — ornate panel like the reference */}
        {region && (
          <div className={`realm-dossier ${regionLocked ? 'is-locked' : ''}`}>
            <div className="flex items-start gap-3">
              <div className="min-w-0 flex-1">
                <b className="block truncate text-[19px] font-black uppercase tracking-[.06em] text-amber-100" style={{ fontFamily: 'Georgia, serif' }}>
                  {region.name}
                </b>
                <p className="mt-0.5 text-[11px] leading-4 text-amber-100/60">{region.tagline}</p>
              </div>
              {region.image_url && (
                <img
                  src={region.image_url}
                  alt={region.name}
                  loading="lazy"
                  className={`h-20 w-24 shrink-0 rounded-xl border border-amber-200/20 object-cover ${regionLocked ? 'opacity-40 grayscale' : ''}`}
                />
              )}
            </div>

            {meta && !regionLocked && (
              <div className="mt-3 space-y-1.5">
                <div className="realm-dossier-row">
                  <span>{t('realm.map.powerRec')}</span>
                  <b className="text-amber-200">{fmt(meta.stats.recommendedPower)}</b>
                </div>
                <div className="realm-dossier-row">
                  <span>{t('realm.map.best')}</span>
                  <b className="text-amber-200">{meta.depth}</b>
                </div>
                <div className="realm-dossier-row">
                  <span>{t('realm.map.entry')}</span>
                  <b className={affordable ? 'text-amber-200' : 'text-rose-300'}>{fmt(meta.stats.entryCost)} FC</b>
                </div>
                <div className="realm-dossier-row">
                  <span>{t('realm.map.possibleRewards')}</span>
                  <b className="max-w-[58%] truncate text-right text-amber-200">{t('realm.map.rewardList')}</b>
                </div>
              </div>
            )}

            {regionLocked ? (
              <p className="mt-3 text-center text-[10px] font-bold uppercase tracking-[.12em] text-slate-500">
                {t('realm.map.lockedRegion', { level: region.unlock_stronghold_level })}
              </p>
            ) : (
              <>
                <button disabled={busy} onClick={() => setConfirm(region.id)} className="realm-explore-btn mt-3">
                  {t('realm.map.explore')}
                </button>
                {!affordable && (
                  <p className="mt-1 text-center text-[9px] font-bold uppercase tracking-[.12em] text-rose-300">
                    {t('realm.map.needFc', { fc: fmt(meta?.stats.entryCost ?? 0) })}
                  </p>
                )}
              </>
            )}
          </div>
        )}


        {/* ENTRY CONFIRMATION — cost, depth and possible rewards before the FC debit */}
        {confirm && region && meta && (
          <div className="fixed inset-0 z-[120] grid place-items-center bg-black/80 p-5" onClick={() => setConfirm(null)}>
            <div className="w-full max-w-xs space-y-3 rounded-3xl border border-amber-300/30 bg-[#080b14] p-4" onClick={(e) => e.stopPropagation()}>
              <b className="block text-center text-[12px] font-black uppercase tracking-[.14em] text-amber-100">
                {region.name} — Depth {meta.depth}
              </b>
              <div className="space-y-1 text-[10px] text-slate-300">
                <div className="flex justify-between"><span className="text-slate-500">{t('realm.map.entry')}</span><b className={affordable ? 'text-amber-200' : 'text-rose-300'}>{fmt(meta.stats.entryCost)} FC</b></div>
                <div className="flex justify-between"><span className="text-slate-500">{t('realm.map.recPower')}</span><b className="text-cyan-200">{fmt(meta.stats.recommendedPower)}</b></div>
                <div className="flex justify-between"><span className="text-slate-500">{t('realm.map.difficulty')}</span><b className="text-slate-200">{t(DEPTH_TIER_KEY[meta.stats.tier] ?? '') || meta.stats.tier}</b></div>
                <div className="flex justify-between"><span className="text-slate-500">{t('realm.map.loot')}</span><b className="text-emerald-200">{meta.stats.lootMult.toFixed(2)}x</b></div>
                {meta.stats.isBossDepth && (
                  <p className="rounded-xl border border-rose-400/30 bg-rose-500/10 px-2 py-1 text-center text-[9px] font-black uppercase tracking-[.12em] text-rose-200">
                    {t('realm.map.bossDepth')}
                  </p>
                )}
                <p className="pt-1 text-[9px] uppercase tracking-[.12em] text-slate-500">{t('realm.map.possibleRewards')}</p>
                <p className="text-[10px] text-slate-300">{t('realm.map.rewardList')}</p>
              </div>
              {!affordable && (
                <p className="rounded-xl border border-rose-400/30 bg-rose-500/10 px-2 py-1.5 text-center text-[9px] font-black uppercase tracking-[.12em] text-rose-200">
                  {t('realm.map.noFc')}
                </p>
              )}
              <button
                disabled={busy || !affordable}
                onClick={() => { setConfirm(null); call(() => realmExploreStart(initData, region.id)); }}
                className="w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black uppercase tracking-[.16em] text-black disabled:opacity-40"
              >
                {t('realm.map.startExplore')}
              </button>
              <button onClick={() => setConfirm(null)} className="w-full rounded-2xl border border-white/15 py-2.5 text-[10px] font-bold uppercase tracking-[.14em] text-slate-300">
                {t('realm.map.cancel')}
              </button>
            </div>
          </div>
        )}

        {/* SECONDARY / AFK MODE — legacy timer expeditions */}
        <div className="rounded-3xl border border-white/8 p-3">
          <button onClick={() => setAfkOpen((v) => !v)} className="flex w-full items-center justify-between">
            <b className="text-[10px] font-black uppercase tracking-[.2em] text-slate-400">{t('realm.map.afk')}</b>
            <span className="text-[11px] text-slate-500">{afkOpen ? '−' : '+'}</span>
          </button>
          {afkOpen && region && !regionLocked && (
            <div className="mt-2 grid grid-cols-2 gap-2">
              <button disabled={busy} onClick={() => call(() => realmStartExpedition(initData, region.id, 'gather'))} className="rounded-2xl border border-white/15 py-2.5 text-[10px] font-bold text-slate-200 disabled:opacity-40">{t('realm.map.gather15')}</button>
              <button disabled={busy} onClick={() => call(() => realmStartExpedition(initData, region.id, 'deep'))} className="rounded-2xl border border-amber-300/30 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-amber-100 disabled:opacity-40">{t('realm.map.deep1h')}</button>
            </div>
          )}
          {data.expeditions.length > 0 && (
            <div className="mt-2 space-y-1">
              {data.expeditions.map((e) => {
                const left = realmSecondsLeft(e.finishes_at, now);
                const r = regions.find((x) => x.id === e.region_id);
                return (
                  <div key={e.id} className="flex items-center justify-between border-b border-white/5 py-2">
                    <div>
                      <b className="text-[11px] text-amber-100">{r?.name ?? e.region_id}</b>
                      <p className="text-[9px] text-slate-500">{e.expedition_type === 'deep' ? t('realm.map.deepExp') : t('realm.map.quickGather')}</p>
                    </div>
                    {left > 0
                      ? <span className="text-[11px] font-bold tabular-nums text-cyan-300">{realmTimer(left)}</span>
                      : <button disabled={busy} onClick={() => call(() => realmClaimExpedition(initData, e.id))} className="rounded-xl bg-gradient-to-r from-emerald-400 to-teal-300 px-3 py-1.5 text-[9px] font-black uppercase tracking-[.14em] text-black">{t('realm.map.collect')}</button>}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </section>
    );
  }

  // ── ACTIVE RUN: fullscreen cinematic exploration scene ───────────────────
  return (
    <>
      <RealmRunScene
        region={region}
        run={exploreRun}
        nodes={nodes}
        materials={data.materials}
        busy={busy}
        flash={flash}
        onEnter={enter}
        onChoose={choose}
        onExtract={() => call(() => realmExploreExtract(initData, exploreRun.id))}
        onAuto={() => call(() => realmExploreAuto(initData, exploreRun.id))}
        onAbandon={() => call(() => realmExploreAbandon(initData, exploreRun.id))}
      />
      {combat && (
        <RealmBattleScene
          log={combat}
          regionId={region?.id}
          regionName={region?.name}
          regionImage={region?.image_url}
          onClose={() => setCombat(null)}
        />
      )}
    </>
  );
}

