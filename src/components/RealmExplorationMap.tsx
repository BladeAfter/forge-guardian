import { useEffect, useMemo, useRef, useState } from 'react';
import {
  REALM_NODE_DESC,
  REALM_NODE_GLYPH,
  REALM_NODE_LABEL,
  REALM_NODE_TITLE,
  REALM_NODE_TONE,
  REALM_OPTION_LABEL,
  REALM_RISK_LABEL,
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

const WORLD_MAP = '/assets/game/realm/world-map.jpg';

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
 * 🗺️ MYTHREON REALM — INTERACTIVE MAP.
 *
 * The world map is clickable: each region is a glowing pin. Entering a region starts a
 * server-authoritative exploration run (`realm_explore_*`): a branching node path where the
 * player taps the next node, the party marker travels along the lit trail, events open a
 * choice sheet, combat plays a quick auto-battle overlay and loot is accumulated on the run
 * until EXTRACT. The legacy timer expeditions stay available as the secondary AFK mode.
 */
import RealmBattleScene from './RealmBattleScene';

export default function RealmExplorationMap({ data, initData, now, level, busy, call, run }: Props) {
  const regions = data.regions;
  const [selected, setSelected] = useState<string | null>(null);
  const [afkOpen, setAfkOpen] = useState(false);
  const [combat, setCombat] = useState<RealmExploreLog | null>(null);
  const [flash, setFlash] = useState<string | null>(null);
  const [moving, setMoving] = useState(false);
  const combatTimer = useRef<number | null>(null);

  const exploreRun = data.exploreRun;
  const nodes = data.exploreNodes ?? [];
  const region = regions.find((r) => r.id === (exploreRun?.region_id ?? selected)) ?? null;
  const regionLocked = region ? level < region.unlock_stronghold_level : true;

  const pending = exploreRun?.pending ?? null;
  const depth = exploreRun?.depth ?? 0;
  const finalDepth = exploreRun?.final_depth ?? 5;
  const loot = exploreRun?.loot ?? {};
  const materialById = useMemo(
    () => Object.fromEntries(data.materials.map((m) => [m.id, m])),
    [data.materials],
  );

  useEffect(() => () => { if (combatTimer.current) window.clearTimeout(combatTimer.current); }, []);

  const lootLine = () => {
    const parts: string[] = [];
    if (Number(loot.fc)) parts.push(`${fmt(Number(loot.fc))} FC`);
    if (Number(loot.fragments)) parts.push(`${fmt(Number(loot.fragments))} frag.`);
    Object.entries(loot.materials ?? {}).forEach(([id, qty]) =>
      parts.push(`${fmt(Number(qty))} ${materialById[id]?.name ?? id}`));
    return parts.length ? parts.join(' • ') : 'Nada ainda';
  };

  /** Plays the travel animation, then the combat overlay / loot flash for the resolved node. */
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
            <b className="block text-[13px] font-black uppercase tracking-[.1em] text-amber-100">{region.name}</b>
            <p className="text-[10px] leading-4 text-slate-400">{region.tagline}</p>
            {regionLocked ? (
              <p className="text-[10px] font-bold text-slate-500">🔒 Requer Stronghold Lv.{region.unlock_stronghold_level}</p>
            ) : (
              <button
                disabled={busy}
                onClick={() => call(() => realmExploreStart(initData, region.id))}
                className="w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black uppercase tracking-[.16em] text-black disabled:opacity-40"
              >
                Explorar região
              </button>
            )}
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

  // ── ACTIVE RUN: node path ────────────────────────────────────────────────
  const openNodes = nodes.filter((n) => n.depth === depth && n.status !== 'resolved' && n.status !== 'skipped');
  const resolved = nodes.filter((n) => n.status === 'resolved').sort((a, b) => a.depth - b.depth);
  const lastResolved = resolved[resolved.length - 1] ?? null;
  const markerX = lastResolved ? Number(lastResolved.config?.x ?? 8) : 4;
  const markerY = lastResolved ? Number(lastResolved.config?.y ?? 50) : 50;
  const pendingNode = pending ? nodes.find((n) => n.id === pending.nodeId) ?? null : null;

  return (
    <section className="space-y-3">
      {/* TOP: region, loot, risk, exit */}
      <div className="rounded-3xl border border-amber-300/20 bg-amber-500/[.05] p-3">
        <div className="flex items-center gap-2">
          <b className="flex-1 truncate text-[12px] font-black uppercase tracking-[.12em] text-amber-100">{region?.name ?? exploreRun.region_id}</b>
          <span className="rounded-full border border-rose-300/30 px-2 py-0.5 text-[9px] font-black text-rose-200">HP {exploreRun.hp}</span>
          <span className="rounded-full border border-white/15 px-2 py-0.5 text-[9px] font-black text-slate-300">RISCO {REALM_RISK_LABEL(exploreRun.risk)}</span>
        </div>
        <p className="mt-1 text-[10px] text-emerald-200">Loot: {lootLine()}</p>
        <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
          <div className="h-full rounded-full bg-gradient-to-r from-amber-300 to-yellow-200 transition-all duration-500" style={{ width: `${Math.min(100, (depth / (finalDepth + 1)) * 100)}%` }} />
        </div>
        <p className="mt-1 text-[9px] font-bold uppercase tracking-[.16em] text-slate-500">Nó {Math.min(depth + 1, finalDepth + 1)} de {finalDepth + 1}</p>
      </div>

      {/* CENTER: interactive path */}
      <div className="relative h-56 overflow-hidden rounded-3xl border border-amber-300/10 bg-[#070a14]">
        {region?.image_url && (
          <img src={region.image_url} alt="" aria-hidden className="absolute inset-0 h-full w-full object-cover opacity-25" />
        )}
        <div className="absolute inset-0 realm-fog" />
        <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="absolute inset-0 h-full w-full">
          {nodes.map((n) => {
            const prev = nodes.filter((p) => p.depth === n.depth - 1);
            const from = prev.find((p) => p.status === 'resolved') ?? prev[0];
            const x1 = from ? Number(from.config?.x ?? 8) : 4;
            const y1 = from ? Number(from.config?.y ?? 50) : 50;
            const lit = n.status === 'resolved' || n.depth <= depth;
            return (
              <line
                key={`l-${n.id}`}
                x1={x1} y1={y1} x2={Number(n.config?.x ?? 8)} y2={Number(n.config?.y ?? 50)}
                stroke={lit ? 'rgba(252,211,77,.55)' : 'rgba(255,255,255,.12)'}
                strokeWidth={lit ? 0.8 : 0.5}
                strokeDasharray={lit ? undefined : '2 2'}
              />
            );
          })}
        </svg>

        {nodes.map((n) => {
          const open = n.depth === depth && n.status !== 'resolved' && n.status !== 'skipped';
          const done = n.status === 'resolved';
          const tone = REALM_NODE_TONE[n.node_type] ?? '#fbbf24';
          return (
            <button
              key={n.id}
              disabled={!open || busy || Boolean(pending)}
              onClick={() => enter(n)}
              aria-label={REALM_NODE_LABEL[n.node_type] ?? n.node_type}
              style={{ left: `${n.config?.x ?? 8}%`, top: `${n.config?.y ?? 50}%` }}
              className="absolute -translate-x-1/2 -translate-y-1/2"
            >
              <span
                style={{ borderColor: tone, color: tone, boxShadow: open ? `0 0 14px ${tone}` : undefined }}
                className={`grid h-10 w-10 place-items-center rounded-full border-2 bg-black/75 text-[15px] transition ${
                  open ? 'realm-pin-on scale-105' : done ? 'opacity-60' : n.status === 'skipped' ? 'opacity-20' : 'opacity-40'}`}
              >
                {REALM_NODE_GLYPH[n.node_type] ?? '◆'}
              </span>
            </button>
          );
        })}

        {/* party marker */}
        <span
          style={{ left: `${markerX}%`, top: `${markerY}%` }}
          className={`pointer-events-none absolute -translate-x-1/2 -translate-y-1/2 transition-all duration-500 ${moving ? 'realm-marker-move' : ''}`}
        >
          <span className="block h-4 w-4 rounded-full bg-amber-200 shadow-[0_0_18px_6px_rgba(252,211,77,.55)]" />
        </span>
      </div>

      {/* BOTTOM: current node panel + actions */}
      <div className="rounded-3xl border border-white/10 bg-white/[.03] p-3">
        {openNodes.length > 0 ? (
          <>
            <p className="text-[9px] font-black uppercase tracking-[.2em] text-slate-500">Escolha o caminho</p>
            <div className="mt-2 space-y-1.5">
              {openNodes.map((n) => (
                <button
                  key={n.id}
                  disabled={busy || Boolean(pending)}
                  onClick={() => enter(n)}
                  className="flex w-full items-center gap-2 rounded-2xl border border-white/10 bg-black/40 p-2.5 text-left disabled:opacity-40"
                >
                  <span style={{ color: REALM_NODE_TONE[n.node_type] }} className="text-[16px]">{REALM_NODE_GLYPH[n.node_type]}</span>
                  <span className="min-w-0 flex-1">
                    <b className="block text-[11px] font-black uppercase tracking-[.1em] text-amber-100">{REALM_NODE_TITLE[n.node_type] ?? n.node_type}</b>
                    <span className="block truncate text-[9px] text-slate-400">{REALM_NODE_DESC[n.node_type]}</span>
                  </span>
                  <span className="text-[10px] font-bold text-slate-500">›</span>
                </button>
              ))}
            </div>
          </>
        ) : (
          <p className="text-[10px] text-slate-400">Trilha resolvida. Extraia o loot para garantir as recompensas.</p>
        )}

        <div className="mt-3 grid grid-cols-2 gap-2">
          <button
            disabled={busy}
            onClick={() => call(() => realmExploreExtract(initData, exploreRun.id))}
            className="rounded-2xl bg-gradient-to-r from-emerald-400 to-teal-300 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-black disabled:opacity-40"
          >
            Extrair agora
          </button>
          <button
            disabled={busy || Boolean(pending)}
            onClick={() => call(() => realmExploreAuto(initData, exploreRun.id))}
            className="rounded-2xl border border-amber-300/30 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-amber-100 disabled:opacity-40"
          >
            Auto explorar
          </button>
        </div>
        <button
          disabled={busy}
          onClick={() => call(() => realmExploreAbandon(initData, exploreRun.id))}
          className="mt-2 w-full text-[9px] font-bold uppercase tracking-[.18em] text-slate-600"
        >
          Abandonar run (perde o loot)
        </button>
      </div>

      {flash && (
        <p className="fixed left-1/2 top-24 z-[60] -translate-x-1/2 rounded-2xl border border-amber-300/40 bg-black/90 px-4 py-2 text-[11px] font-black tracking-wide text-amber-100">{flash}</p>
      )}

      {/* EVENT / CHOICE SHEET */}
      {pending && pendingNode && (
        <div className="fixed inset-0 z-[70] flex items-end bg-black/80 p-3">
          <div className="w-full rounded-3xl border border-amber-300/30 bg-[#080b16] p-4">
            <div className="flex items-center gap-2">
              <span style={{ color: REALM_NODE_TONE[pendingNode.node_type] }} className="text-[22px]">{REALM_NODE_GLYPH[pendingNode.node_type]}</span>
              <b className="text-[13px] font-black uppercase tracking-[.12em] text-amber-100">{REALM_NODE_TITLE[pendingNode.node_type]}</b>
            </div>
            <p className="mt-1 text-[10px] leading-4 text-slate-400">{REALM_NODE_DESC[pendingNode.node_type]}</p>
            <div className="mt-3 space-y-2">
              {pending.options.map((opt) => (
                <button
                  key={opt}
                  disabled={busy}
                  onClick={() => choose(opt)}
                  className="w-full rounded-2xl border border-amber-300/25 bg-amber-500/[.07] py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-amber-100 disabled:opacity-40"
                >
                  {REALM_OPTION_LABEL[opt] ?? opt}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {combat && (
        <RealmBattleScene
          log={combat}
          regionId={region?.id}
          regionName={region?.name}
          regionImage={region?.image_url}
          onClose={() => setCombat(null)}
        />
      )}
    </section>
  );
}
