import { useEffect, useMemo, useRef, useState } from 'react';
import {
  REALM_NODE_DESC,
  REALM_NODE_LABEL,
  REALM_NODE_TITLE,
  REALM_OPTION_LABEL,
  REALM_RISK_LABEL,
  type RealmExploreNode,
  type RealmExploreRun,
  type RealmMaterial,
  type RealmRegion,
} from '../realm';

/** Region scenery — layered painted backdrops (no node graph). */
const SCENE: Record<string, string> = {
  greenvale: '/assets/game/realm/scene-greenvale.jpg',
  crystal_rift: '/assets/game/realm/scene-crystal-rift.jpg',
  'crystal-rift': '/assets/game/realm/scene-crystal-rift.jpg',
  abyss: '/assets/game/realm/scene-abyss.jpg',
};

/** Every logical node type is drawn as a real place / creature in the world. */
const PLACE_ART: Record<string, string> = {
  combat: '/assets/game/realm/poi-combat.png',
  elite: '/assets/game/realm/poi-elite.png',
  boss: '/assets/game/realm/poi-boss.png',
  gather: '/assets/game/realm/poi-gather.png',
  treasure: '/assets/game/realm/poi-treasure.png',
  event: '/assets/game/realm/poi-event.png',
  trap: '/assets/game/realm/poi-trap.png',
  shrine: '/assets/game/realm/poi-shrine.png',
  rest: '/assets/game/realm/poi-rest.png',
};

const PARTY_ART = '/assets/game/realm/poi-party.png';

/** Visual danger language per place (glow colour + short risk word). */
const PLACE_MOOD: Record<string, { glow: string; risk: string }> = {
  combat: { glow: 'rgba(248,113,113,.75)', risk: 'PERIGO' },
  elite: { glow: 'rgba(251,146,60,.85)', risk: 'ALTO RISCO' },
  boss: { glow: 'rgba(250,204,21,.9)', risk: 'MORTAL' },
  gather: { glow: 'rgba(74,222,128,.7)', risk: 'SEGURO' },
  treasure: { glow: 'rgba(251,191,36,.85)', risk: 'TESOURO' },
  event: { glow: 'rgba(192,132,252,.8)', risk: 'MISTÉRIO' },
  trap: { glow: 'rgba(244,63,94,.8)', risk: 'ARRISCADO' },
  shrine: { glow: 'rgba(96,165,250,.8)', risk: 'SEGURO' },
  rest: { glow: 'rgba(52,211,153,.75)', risk: 'SEGURO' },
};

const SIZE: Record<string, number> = {
  boss: 30, elite: 24, combat: 20, shrine: 22, rest: 21,
  treasure: 17, event: 19, trap: 17, gather: 16,
};

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/** Deterministic scenery layout: the trail snakes left→right through the region art. */
function place(node: RealmExploreNode, finalDepth: number) {
  const span = Math.max(1, finalDepth + 1);
  const x = 14 + (node.depth / span) * 72;
  const wave = node.depth % 2 === 0 ? -1 : 1;
  const laneOffset = (node.lane ?? 0) === 0 ? -13 : (node.lane === 1 ? 6 : 20);
  const y = 60 + wave * 4 + laneOffset;
  return { x, y: Math.min(88, Math.max(28, y)) };
}

type Props = {
  region: RealmRegion | null;
  run: RealmExploreRun;
  nodes: RealmExploreNode[];
  materials: RealmMaterial[];
  busy: boolean;
  onEnter: (node: RealmExploreNode) => void;
  onChoose: (option: string) => void;
  onExtract: () => void;
  onAuto: () => void;
  onAbandon: () => void;
  /** Loot toast raised by the parent after a resolved node. */
  flash: string | null;
};

/**
 * 🌍 MYTHREON REALM — CINEMATIC EXPLORATION SCENE.
 *
 * The old node-graph (circles + lines) is gone: every backend node is rendered as a real
 * place inside the painted region scenery (shrine, cave, campfire, chest, creature…). The
 * party sprite walks the trail, the camera pans/zooms to the destination, unvisited areas
 * stay under fog of war and a small bottom sheet confirms the chosen place. All rules,
 * rolls, loot and progression remain 100% server-side: this layer only renders state.
 */
export default function RealmRunScene({
  region, run, nodes, materials, busy, onEnter, onChoose, onExtract, onAuto, onAbandon, flash,
}: Props) {
  const depth = run.depth ?? 0;
  const finalDepth = run.final_depth ?? 5;
  const pending = run.pending ?? null;
  const loot = run.loot ?? {};

  const [pick, setPick] = useState<RealmExploreNode | null>(null);
  const [menu, setMenu] = useState(false);
  const [lootOpen, setLootOpen] = useState(false);
  const [walking, setWalking] = useState(false);
  const [banner, setBanner] = useState<string | null>(region?.name ?? null);
  const [cameraTo, setCameraTo] = useState<number | null>(null);
  const walkTimer = useRef<number | null>(null);

  const materialById = useMemo(
    () => Object.fromEntries(materials.map((m) => [m.id, m])), [materials],
  );

  useEffect(() => {
    const t = window.setTimeout(() => setBanner(null), 1900);
    return () => window.clearTimeout(t);
  }, []);
  useEffect(() => () => { if (walkTimer.current) window.clearTimeout(walkTimer.current); }, []);

  const scene = SCENE[region?.id ?? ''] ?? region?.image_url ?? SCENE.greenvale;

  const open = nodes.filter((n) => n.depth === depth && n.status !== 'resolved' && n.status !== 'skipped');
  const resolved = nodes.filter((n) => n.status === 'resolved').sort((a, b) => a.depth - b.depth);
  const last = resolved[resolved.length - 1] ?? null;
  const partyAt = last ? place(last, finalDepth) : { x: 8, y: 66 };
  const pendingNode = pending ? nodes.find((n) => n.id === pending.nodeId) ?? null : null;

  /** Camera follows the party (or the destination while travelling). */
  const focusX = cameraTo ?? partyAt.x;
  const camera = `translateX(${(50 - focusX) * 0.45}%) scale(1.18)`;

  const lootBits = () => {
    const parts: string[] = [];
    if (Number(loot.fc)) parts.push(`${fmt(Number(loot.fc))} FC`);
    if (Number(loot.fragments)) parts.push(`${fmt(Number(loot.fragments))} frag.`);
    Object.entries(loot.materials ?? {}).forEach(([id, qty]) =>
      parts.push(`${fmt(Number(qty))} ${materialById[id]?.name ?? id}`));
    return parts;
  };
  const lootCount = lootBits().length;

  const travel = (node: RealmExploreNode) => {
    const to = place(node, finalDepth);
    setPick(null);
    setCameraTo(to.x);
    setWalking(true);
    walkTimer.current = window.setTimeout(() => {
      setWalking(false);
      setCameraTo(null);
      onEnter(node);
    }, 900);
  };

  const hpPct = Math.max(0, Math.min(100, Number(run.hp ?? 0)));
  const safeHere = last ? ['shrine', 'rest'].includes(last.node_type) : true;

  return (
    <div className="fixed inset-0 z-[65] overflow-hidden bg-[#04060d]">
      {/* ── WORLD (parallax scenery + places) ─────────────────────────────── */}
      <div className="absolute inset-0 realm-cam" style={{ transform: camera }}>
        <img src={scene} alt="" aria-hidden className="absolute inset-0 h-full w-full object-cover" />
        {/* cinematic grade: darker, cooler, deeper */}
        <div className="pointer-events-none absolute inset-0 realm-scene-grade" />
        <div className="pointer-events-none absolute inset-0 realm-scene-vignette" />
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-[#04060d]/85 via-[#04060d]/15 to-[#04060d]/95" />
        {/* parallax mist layers (slow, opposite drift) */}
        <div
          className="pointer-events-none absolute inset-0 realm-scene-mist"
          style={{ transform: `translateX(${(focusX - 50) * 0.06}%)` }}
        />
        <div
          className="pointer-events-none absolute inset-0 realm-scene-mist2"
          style={{ transform: `translateX(${(50 - focusX) * 0.1}%)` }}
        />
        <div className="pointer-events-none absolute inset-0 realm-scene-light" />

        {/* distant boss silhouette — a visual objective from the start */}
        {nodes.some((n) => n.node_type === 'boss') && (
          <img
            src={PLACE_ART.boss} alt="" aria-hidden loading="lazy"
            className="pointer-events-none absolute bottom-[46%] right-[6%] w-[26%] opacity-25 blur-[1px] realm-scene-boss"
          />
        )}

        {/* the trail itself, painted as a lit magical route */}
        <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="pointer-events-none absolute inset-0 h-full w-full">
          {nodes.map((n) => {
            const prevs = nodes.filter((p) => p.depth === n.depth - 1);
            const from = prevs.find((p) => p.status === 'resolved') ?? prevs[0];
            const a = from ? place(from, finalDepth) : { x: 8, y: 66 };
            const b = place(n, finalDepth);
            if (n.depth > depth + 1) return null;
            const walked = n.status === 'resolved';
            const next = n.depth === depth;
            const mood = PLACE_MOOD[n.node_type]?.glow ?? 'rgba(252,211,77,.5)';
            const d = `M ${a.x} ${a.y + 4} Q ${(a.x + b.x) / 2} ${Math.min(a.y, b.y) + 12} ${b.x} ${b.y + 4}`;
            return (
              <g key={`t-${n.id}`}>
                {/* soft glow base */}
                <path
                  d={d} fill="none" strokeLinecap="round"
                  stroke={walked ? 'rgba(252,211,77,.18)' : next ? mood : 'rgba(255,255,255,.05)'}
                  strokeWidth={next ? 2.6 : 1.6}
                  className="realm-trail-glow"
                />
                <path
                  d={d}
                  fill="none"
                  stroke={walked ? 'rgba(253,230,138,.6)' : next ? mood : 'rgba(255,255,255,.12)'}
                  strokeWidth={next ? 0.9 : 0.6}
                  strokeLinecap="round"
                  strokeDasharray={walked ? undefined : '3 2.5'}
                />
                {/* running energy on the active route */}
                {next && (
                  <path
                    d={d} fill="none" stroke="rgba(255,255,255,.85)" strokeWidth={0.5}
                    strokeLinecap="round" strokeDasharray="1.4 9" className="realm-trail-flow"
                  />
                )}
              </g>
            );
          })}
        </svg>

        {/* places */}
        {nodes.map((n) => {
          if (n.depth > depth + 1) return null;
          const p = place(n, finalDepth);
          const isOpen = n.depth === depth && n.status !== 'resolved' && n.status !== 'skipped';
          const done = n.status === 'resolved';
          const picked = pick?.id === n.id;
          const mood = PLACE_MOOD[n.node_type] ?? { glow: 'rgba(252,211,77,.7)', risk: '' };
          const w = SIZE[n.node_type] ?? 18;
          return (
            <button
              key={n.id}
              disabled={!isOpen || busy || walking || Boolean(pending)}
              onClick={() => setPick(n)}
              aria-label={REALM_NODE_LABEL[n.node_type] ?? n.node_type}
              style={{ left: `${p.x}%`, top: `${p.y}%`, width: `${w}%`, ['--poi-glow' as string]: mood.glow }}
              className={`realm-poi absolute -translate-x-1/2 -translate-y-full transition-all duration-500 ${
                isOpen ? 'realm-place-live realm-poi-open' : done ? 'opacity-45 grayscale' : 'opacity-25'} ${
                picked ? 'realm-poi-picked' : ''}`}
            >
              {isOpen && <span className="realm-poi-aura" aria-hidden />}
              {isOpen && <span className="realm-poi-pedestal" aria-hidden />}
              <img
                src={PLACE_ART[n.node_type] ?? PLACE_ART.event}
                alt="" aria-hidden loading="lazy"
                style={{ filter: isOpen ? `drop-shadow(0 0 18px ${mood.glow})` : 'grayscale(.5) brightness(.6)' }}
                className="relative block w-full select-none"
              />
              {isOpen && (
                <span className="realm-plaque">
                  <b>{REALM_NODE_TITLE[n.node_type] ?? n.node_type}</b>
                  <em style={{ color: mood.glow }}>{mood.risk}</em>
                </span>
              )}
            </button>
          );
        })}

        {/* the party, physically standing on the trail */}
        <img
          src={PARTY_ART} alt="Sua equipe" loading="lazy"
          style={{ left: `${partyAt.x}%`, top: `${partyAt.y + 6}%` }}
          className={`pointer-events-none absolute w-[15%] -translate-x-1/2 -translate-y-full drop-shadow-[0_6px_14px_rgba(0,0,0,.8)] transition-all duration-[900ms] ease-in-out ${walking ? 'realm-party-walk' : 'realm-party-idle'}`}
        />

        {/* fog of war over the undiscovered part of the region */}
        <div
          className="pointer-events-none absolute inset-y-0 right-0 realm-fogwar"
          style={{ left: `${Math.min(92, 22 + ((depth + 1) / (finalDepth + 1)) * 70)}%` }}
        />
        <div className="pointer-events-none absolute inset-0 realm-scene-dust" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-[22%] realm-scene-fg" />
      </div>


      {/* ── HUD ──────────────────────────────────────────────────────────── */}
      <div className="absolute inset-x-0 top-0 p-3 pt-[max(12px,env(safe-area-inset-top))]">
        <div className="realm-run-topbar">
          <b className="realm-run-region">{region?.name ?? run.region_id}</b>
          <span className="realm-pill realm-pill-depth">{Math.min(depth + 1, finalDepth + 1)}/{finalDepth + 1}</span>
          <button onClick={onAuto} disabled={busy || Boolean(pending) || walking} className="realm-pill realm-pill-auto disabled:opacity-40">Auto</button>
          <button onClick={() => setMenu(true)} aria-label="Mais opções" className="realm-pill realm-pill-menu">⋯</button>
        </div>

        <div className="mt-1.5 flex items-center gap-1.5">
          <button onClick={() => setLootOpen(true)} className="realm-stat-block min-w-0 flex-1">
            <span className="realm-stat-cap">HP</span>
            <span className="realm-hpbar realm-hpbar-pro w-16 flex-none"><span className="realm-hpfill realm-hpfill-hero" style={{ width: `${hpPct}%` }} /></span>
            <span className="text-[9px] font-black tabular-nums text-rose-100">{run.hp}</span>
            <span className="realm-badge realm-badge-loot ml-auto">Loot {lootCount}</span>
          </button>
          <span className={`realm-badge flex-none ${riskTone}`}>Risco {REALM_RISK_LABEL(run.risk)}</span>
          <button
            onClick={onExtract}
            disabled={busy || walking}
            className={`realm-extract flex-none disabled:opacity-40 ${safeHere ? 'realm-extract-hot' : ''}`}
          >
            ⤴ Extrair
          </button>
        </div>
      </div>

      {/* prompt when a fork is available */}
      {open.length > 0 && !pick && !pending && !walking && (
        <p className="realm-run-hint">Toque em um local para viajar</p>
      )}
      {open.length === 0 && !pending && (
        <div className="absolute inset-x-3 bottom-4">
          <button onClick={onExtract} disabled={busy} className="realm-extract-cta disabled:opacity-40">
            Extrair com o loot
          </button>
        </div>
      )}


      {/* ── CINEMATIC BANNERS ────────────────────────────────────────────── */}
      {banner && (
        <div className="pointer-events-none absolute inset-0 grid place-items-center">
          <div className="realm-banner text-center">
            <b className="block text-[22px] font-black uppercase tracking-[.28em] text-amber-100">{banner}</b>
            <span className="mt-1 block text-[9px] uppercase tracking-[.3em] text-slate-400">{region?.tagline ?? 'Exploração'}</span>
          </div>
        </div>
      )}
      {flash && (
        <p className="pointer-events-none absolute left-1/2 top-1/3 z-[10] -translate-x-1/2 rounded-2xl border border-amber-300/40 bg-black/85 px-4 py-2 text-center text-[11px] font-black tracking-wide text-amber-100">
          {flash}
        </p>
      )}

      {/* ── DESTINATION SHEET ────────────────────────────────────────────── */}
      {pick && (
        <div className="absolute inset-0 z-[20] flex items-end bg-gradient-to-t from-black/85 via-black/30 to-transparent p-3 pb-[max(12px,env(safe-area-inset-bottom))]" onClick={() => setPick(null)}>
          <div onClick={(e) => e.stopPropagation()} className="w-full rounded-3xl border border-amber-300/25 bg-[#080b16]/95 p-4 realm-sheet-in">
            <div className="flex items-center gap-2">
              <b className="flex-1 text-[13px] font-black uppercase tracking-[.12em] text-amber-100">{REALM_NODE_TITLE[pick.node_type]}</b>
              <span style={{ color: PLACE_MOOD[pick.node_type]?.glow }} className="text-[9px] font-black uppercase tracking-[.14em]">
                {PLACE_MOOD[pick.node_type]?.risk}
              </span>
            </div>
            <p className="mt-1 text-[10px] leading-4 text-slate-400">{REALM_NODE_DESC[pick.node_type]}</p>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <button onClick={() => setPick(null)} className="rounded-2xl border border-white/12 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-slate-300">Voltar</button>
              <button disabled={busy} onClick={() => travel(pick)} className="rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-black disabled:opacity-40">Entrar</button>
            </div>
          </div>
        </div>
      )}

      {/* ── EVENT / CHOICE SHEET (server-provided options) ────────────────── */}
      {pending && pendingNode && (
        <div className="absolute inset-0 z-[30] flex items-end bg-black/80 p-3 pb-[max(12px,env(safe-area-inset-bottom))]">
          <div className="w-full rounded-3xl border border-amber-300/30 bg-[#080b16] p-4 realm-sheet-in">
            <span className="block text-[8px] font-black uppercase tracking-[.3em] text-slate-500">Descoberta</span>
            <b className="mt-0.5 block text-[13px] font-black uppercase tracking-[.12em] text-amber-100">{REALM_NODE_TITLE[pendingNode.node_type]}</b>
            <p className="mt-1 text-[10px] leading-4 text-slate-400">{REALM_NODE_DESC[pendingNode.node_type]}</p>
            <div className="mt-3 space-y-2">
              {pending.options.map((opt) => (
                <button
                  key={opt}
                  disabled={busy}
                  onClick={() => onChoose(opt)}
                  className="w-full rounded-2xl border border-amber-300/25 bg-amber-500/[.07] py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-amber-100 disabled:opacity-40"
                >
                  {REALM_OPTION_LABEL[opt] ?? opt}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ── LOOT DETAIL ──────────────────────────────────────────────────── */}
      {lootOpen && (
        <div className="absolute inset-0 z-[30] flex items-end bg-black/80 p-3" onClick={() => setLootOpen(false)}>
          <div onClick={(e) => e.stopPropagation()} className="w-full rounded-3xl border border-emerald-300/25 bg-[#080b16] p-4 realm-sheet-in">
            <b className="block text-[11px] font-black uppercase tracking-[.2em] text-emerald-200">Loot da run</b>
            {lootCount === 0
              ? <p className="mt-2 text-[10px] text-slate-500">Nada coletado ainda.</p>
              : <ul className="mt-2 space-y-1">{lootBits().map((b) => <li key={b} className="text-[11px] text-slate-200">• {b}</li>)}</ul>}
            <p className="mt-2 text-[9px] text-slate-500">HP da equipe: {run.hp} • Risco {REALM_RISK_LABEL(run.risk)}</p>
            <button onClick={() => setLootOpen(false)} className="mt-3 w-full rounded-2xl border border-white/12 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-slate-300">Fechar</button>
          </div>
        </div>
      )}

      {/* ── ⋯ MENU ───────────────────────────────────────────────────────── */}
      {menu && (
        <div className="absolute inset-0 z-[40] flex items-end bg-black/80 p-3" onClick={() => setMenu(false)}>
          <div onClick={(e) => e.stopPropagation()} className="w-full space-y-2 rounded-3xl border border-white/12 bg-[#080b16] p-4 realm-sheet-in">
            <button onClick={() => { setMenu(false); setLootOpen(true); }} className="w-full rounded-2xl border border-white/12 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-slate-200">Ver loot e equipe</button>
            <button
              disabled={busy}
              onClick={() => { if (window.confirm('Abandonar a run? Todo o loot será perdido.')) { setMenu(false); onAbandon(); } }}
              className="w-full rounded-2xl border border-rose-400/30 py-2.5 text-[10px] font-black uppercase tracking-[.14em] text-rose-200 disabled:opacity-40"
            >
              Abandonar run
            </button>
            <button onClick={() => setMenu(false)} className="w-full py-1 text-[9px] font-bold uppercase tracking-[.18em] text-slate-500">Fechar</button>
          </div>
        </div>
      )}
    </div>
  );
}
