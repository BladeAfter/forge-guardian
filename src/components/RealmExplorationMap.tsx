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

const WORLD_MAP = '/assets/game/realm/world-map.jpg';

const DEPTH_TIER: Record<string, string> = {
  normal: 'Normal',
  hard: 'Difícil',
  elite: 'Elite',
  mythic: 'Mítico',
  abyssal: 'Abissal',
};

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/** Region pins over the world-map art (percent coordinates, mobile-friendly hit areas). */
const REGION_PIN: { x: number; y: number }[] = [
  { x: 26, y: 66 },
  { x: 52, y: 40 },
  { x: 78, y: 62 },
  { x: 40, y: 22 },
  { x: 66, y: 82 },
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
      setFlash(bits.length ? bits.join('  ') : 'Nada aconteceu...');
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
      <section className="space-y-4">
        <div className="relative overflow-hidden rounded-3xl border border-amber-300/10">
          <img src={WORLD_MAP} alt="Mapa do mundo de Mythreon" loading="lazy" className="h-60 w-full object-cover" />
          <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-[#05070f] via-transparent to-[#05070f]/40" />
          {regions.map((r, i) => {
            const pin = REGION_PIN[i % REGION_PIN.length];
            const locked = level < r.unlock_stronghold_level;
            const on = selected === r.id;
            return (
              <button
                key={r.id}
                onClick={() => setSelected(r.id)}
                aria-label={r.name}
                style={{ left: `${pin.x}%`, top: `${pin.y}%` }}
                className="absolute -translate-x-1/2 -translate-y-1/2"
              >
                <span className={`relative grid h-11 w-11 place-items-center rounded-full border text-[15px] transition ${
                  locked ? 'border-white/20 bg-black/70 text-slate-500'
                    : on ? 'realm-pin-on border-amber-200 bg-amber-400/25 text-amber-100'
                    : 'realm-pin border-amber-300/50 bg-black/60 text-amber-200'}`}
                >
                  {locked ? '🔒' : '⚑'}
                </span>
                <span className={`mt-0.5 block whitespace-nowrap text-[8px] font-black uppercase tracking-wide ${on ? 'text-amber-100' : 'text-slate-300'}`}>
                  {r.name}
                </span>
              </button>
            );
          })}
        </div>

        {region && (
          <div className={`space-y-2 rounded-3xl border p-3 ${regionLocked ? 'border-white/10' : 'border-amber-300/25 bg-amber-500/[.05]'}`}>
            {region.image_url && (
              <img src={region.image_url} alt={region.name} loading="lazy" className={`h-32 w-full rounded-2xl object-cover ${regionLocked ? 'opacity-40 grayscale' : ''}`} />
            )}
            <div className="flex items-start justify-between gap-2">
              <div>
                <b className="block text-[13px] font-black uppercase tracking-[.1em] text-amber-100">{region.name}</b>
                <p className="text-[10px] leading-4 text-slate-400">{region.tagline}</p>
              </div>
              {meta && (
                <span className="shrink-0 rounded-xl border border-amber-300/40 bg-black/50 px-2 py-1 text-center">
                  <b className="block text-[10px] font-black uppercase tracking-[.14em] text-amber-200">Depth {meta.depth}</b>
                  <span className="block text-[8px] font-bold uppercase tracking-[.14em] text-slate-400">
                    {DEPTH_TIER[meta.stats.tier] ?? meta.stats.tier}
                  </span>
                </span>
              )}
            </div>

            {meta && !regionLocked && (
              <div className="grid grid-cols-3 gap-1.5 text-center">
                <div className="rounded-xl border border-white/10 bg-black/30 p-1.5">
                  <span className="block text-[8px] font-bold uppercase tracking-[.12em] text-slate-500">Entrada</span>
                  <b className={`block text-[11px] font-black ${affordable ? 'text-amber-200' : 'text-rose-300'}`}>
                    {fmt(meta.stats.entryCost)} FC
                  </b>
                </div>
                <div className="rounded-xl border border-white/10 bg-black/30 p-1.5">
                  <span className="block text-[8px] font-bold uppercase tracking-[.12em] text-slate-500">Poder rec.</span>
                  <b className="block text-[11px] font-black text-cyan-200">{fmt(meta.stats.recommendedPower)}</b>
                </div>
                <div className="rounded-xl border border-white/10 bg-black/30 p-1.5">
                  <span className="block text-[8px] font-bold uppercase tracking-[.12em] text-slate-500">Melhor</span>
                  <b className="block text-[11px] font-black text-slate-200">Depth {meta.bestDepth}</b>
                </div>
              </div>
            )}

            {regionLocked ? (
              <p className="text-[10px] font-bold text-slate-500">🔒 Requer Stronghold Lv.{region.unlock_stronghold_level}</p>
            ) : (
              <>
                <button
                  disabled={busy}
                  onClick={() => setConfirm(region.id)}
                  className="w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black uppercase tracking-[.16em] text-black disabled:opacity-40"
                >
                  Explorar região
                </button>
                {!affordable && (
                  <p className="text-center text-[9px] font-bold uppercase tracking-[.12em] text-rose-300">
                    Forge Coins insuficientes — você precisa de {fmt(meta?.stats.entryCost ?? 0)} FC
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
                <div className="flex justify-between"><span className="text-slate-500">Entrada</span><b className={affordable ? 'text-amber-200' : 'text-rose-300'}>{fmt(meta.stats.entryCost)} FC</b></div>
                <div className="flex justify-between"><span className="text-slate-500">Poder recomendado</span><b className="text-cyan-200">{fmt(meta.stats.recommendedPower)}</b></div>
                <div className="flex justify-between"><span className="text-slate-500">Dificuldade</span><b className="text-slate-200">{DEPTH_TIER[meta.stats.tier] ?? meta.stats.tier}</b></div>
                <div className="flex justify-between"><span className="text-slate-500">Loot</span><b className="text-emerald-200">{meta.stats.lootMult.toFixed(2)}x</b></div>
                {meta.stats.isBossDepth && (
                  <p className="rounded-xl border border-rose-400/30 bg-rose-500/10 px-2 py-1 text-center text-[9px] font-black uppercase tracking-[.12em] text-rose-200">
                    👑 Depth de BOSS
                  </p>
                )}
                <p className="pt-1 text-[9px] uppercase tracking-[.12em] text-slate-500">Recompensas possíveis</p>
                <p className="text-[10px] text-slate-300">Materiais raros • Fragmentos • Equipamentos • Essência Ancestral</p>
              </div>
              {!affordable && (
                <p className="rounded-xl border border-rose-400/30 bg-rose-500/10 px-2 py-1.5 text-center text-[9px] font-black uppercase tracking-[.12em] text-rose-200">
                  FC insuficiente
                </p>
              )}
              <button
                disabled={busy || !affordable}
                onClick={() => { setConfirm(null); call(() => realmExploreStart(initData, region.id)); }}
                className="w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black uppercase tracking-[.16em] text-black disabled:opacity-40"
              >
                Iniciar exploração
              </button>
              <button onClick={() => setConfirm(null)} className="w-full rounded-2xl border border-white/15 py-2.5 text-[10px] font-bold uppercase tracking-[.14em] text-slate-300">
                Cancelar
              </button>
            </div>
          </div>
        )}

        {/* SECONDARY / AFK MODE — legacy timer expeditions */}
        <div className="rounded-3xl border border-white/8 p-3">
          <button onClick={() => setAfkOpen((v) => !v)} className="flex w-full items-center justify-between">
            <b className="text-[10px] font-black uppercase tracking-[.2em] text-slate-400">Expedições automáticas</b>
            <span className="text-[11px] text-slate-500">{afkOpen ? '−' : '+'}</span>
          </button>
          {afkOpen && region && !regionLocked && (
            <div className="mt-2 grid grid-cols-2 gap-2">
              <button disabled={busy} onClick={() => call(() => realmStartExpedition(initData, region.id, 'gather'))} className="rounded-2xl border border-white/15 py-2.5 text-[10px] font-bold text-slate-200 disabled:opacity-40">Coleta 15m</button>
              <button disabled={busy} onClick={() => call(() => realmStartExpedition(initData, region.id, 'deep'))} className="rounded-2xl border border-amber-300/30 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-amber-100 disabled:opacity-40">Profunda 1h</button>
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
                      <p className="text-[9px] text-slate-500">{e.expedition_type === 'deep' ? 'Expedição profunda' : 'Coleta rápida'}</p>
                    </div>
                    {left > 0
                      ? <span className="text-[11px] font-bold tabular-nums text-cyan-300">{realmTimer(left)}</span>
                      : <button disabled={busy} onClick={() => call(() => realmClaimExpedition(initData, e.id))} className="rounded-xl bg-gradient-to-r from-emerald-400 to-teal-300 px-3 py-1.5 text-[9px] font-black uppercase tracking-[.14em] text-black">Coletar</button>}
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

