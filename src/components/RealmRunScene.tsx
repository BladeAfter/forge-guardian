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

/** Base width (% of scene) per place type — depth scaling is applied on top. */
const SIZE: Record<string, number> = {
  boss: 30, elite: 25, combat: 21, shrine: 24, rest: 23,
  treasure: 18, event: 21, trap: 18, gather: 17,
};

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/**
 * Asymmetric composition: never stack destinations in a column.
 * Two alternating sets keep consecutive rooms from repeating the same picture.
 * y is the GROUND line of the place (feet / base), x its horizontal position.
 */
const SLOTS: { x: number; y: number }[][] = [
  [{ x: 19, y: 58 }, { x: 76, y: 66 }, { x: 50, y: 43 }],
  [{ x: 79, y: 60 }, { x: 23, y: 68 }, { x: 47, y: 42 }],
];

/** Where the party stands: lower-middle, slightly off-centre. */
const PARTY_AT = { x: 45, y: 88 };

const slotFor = (depthIndex: number, i: number) => SLOTS[depthIndex % 2][i % 3];

/** Farther up the scene = farther away: smaller, dimmer, more fog. */
const depthFactor = (y: number) => Math.max(0.6, Math.min(1, (y - 30) / 55));


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
  const pendingNode = pending ? nodes.find((n) => n.id === pending.nodeId) ?? null : null;

  /** Only the current fork is on screen (max 3 places) — everything else stays in the fog. */
  const destinations = useMemo(
    () => open.slice(0, 3).map((node, i) => ({ node, at: slotFor(depth, i) })),
    [open, depth],
  );

  const partyAt = PARTY_AT;
  const [travelTo, setTravelTo] = useState<{ x: number; y: number } | null>(null);
  const partyPos = travelTo ?? partyAt;

  /** Camera: gentle pan + zoom toward the picked or travelling destination. */
  const focus = travelTo
    ?? (pick ? destinations.find((d) => d.node.id === pick.id)?.at ?? partyAt : partyAt);
  const camera = `translate(${(50 - focus.x) * 0.34}%, ${(72 - focus.y) * 0.14}%) scale(${pick || travelTo ? 1.15 : 1.08})`;

  /** First-run hint only. */
  const [showHint, setShowHint] = useState(() => {
    try { return localStorage.getItem('mythreon.realm.travelHint') !== 'seen'; } catch { return true; }
  });
  useEffect(() => {
    if (!showHint) return;
    const t = window.setTimeout(() => {
      setShowHint(false);
      try { localStorage.setItem('mythreon.realm.travelHint', 'seen'); } catch { /* ignore */ }
    }, 4200);
    return () => window.clearTimeout(t);
  }, [showHint]);

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
    const to = destinations.find((d) => d.node.id === node.id)?.at ?? partyAt;
    setPick(null);
    setWalking(true);
    setTravelTo(to);
    walkTimer.current = window.setTimeout(() => {
      setWalking(false);
      setTravelTo(null);
      onEnter(node);
    }, 1300);
  };

  const hpPct = Math.max(0, Math.min(100, Number(run.hp ?? 0)));
  const riskValue = Number(run.risk ?? 0);
  const riskTone = riskValue >= 70 ? 'realm-badge-risk-x' : riskValue >= 45 ? 'realm-badge-risk-hi'
    : riskValue >= 20 ? 'realm-badge-risk-mid' : 'realm-badge-risk-low';
  const safeHere = last ? ['shrine', 'rest'].includes(last.node_type) : true;




  return (
    <div className="fixed inset-0 z-[65] overflow-hidden bg-[#04060d]">
      {/* ── WORLD (paisagem em camadas + 2-3 destinos físicos) ────────────── */}
      <div className="absolute inset-0 realm-cam" style={{ transform: camera }}>
        {/* BACKGROUND */}
        <img src={scene} alt="" aria-hidden className="absolute inset-0 h-full w-full object-cover" />
        <div className="pointer-events-none absolute inset-0 realm-scene-grade" />
        <div className="pointer-events-none absolute inset-0 realm-scene-vignette" />
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-[#04060d]/80 via-transparent to-[#04060d]/95" />
        <div
          className="pointer-events-none absolute inset-0 realm-scene-mist"
          style={{ transform: `translateX(${(focus.x - 50) * 0.06}%)` }}
        />
        <div
          className="pointer-events-none absolute inset-0 realm-scene-mist2"
          style={{ transform: `translateX(${(50 - focus.x) * 0.1}%)` }}
        />
        <div className="pointer-events-none absolute inset-0 realm-scene-light" />

        {/* objetivo distante: a silhueta do chefe da região */}
        {nodes.some((n) => n.node_type === 'boss') && !destinations.some((d) => d.node.node_type === 'boss') && (
          <img
            src={PLACE_ART.boss} alt="" aria-hidden loading="lazy"
            className="pointer-events-none absolute bottom-[52%] right-[5%] w-[24%] opacity-[.18] blur-[2px] realm-scene-boss"
          />
        )}

        {/* MIDGROUND — trilhas de terra ligando a equipe a cada destino */}
        <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="pointer-events-none absolute inset-0 h-full w-full">
          {/* caminho já percorrido, saindo por trás da equipe */}
          <path
            d={`M ${partyAt.x - 34} 102 Q ${partyAt.x - 16} ${partyAt.y + 4} ${partyAt.x} ${partyAt.y}`}
            fill="none" stroke="rgba(0,0,0,.45)" strokeWidth={5.5} strokeLinecap="round"
          />
          <path
            d={`M ${partyAt.x - 34} 102 Q ${partyAt.x - 16} ${partyAt.y + 4} ${partyAt.x} ${partyAt.y}`}
            fill="none" stroke="rgba(190,168,124,.28)" strokeWidth={2.2} strokeLinecap="round"
          />
          {destinations.map(({ node, at }) => {
            const mood = PLACE_MOOD[node.node_type]?.glow ?? 'rgba(252,211,77,.6)';
            const active = pick?.id === node.id || (walking && travelTo?.x === at.x);
            const midX = (partyAt.x + at.x) / 2 + (at.x < partyAt.x ? -5 : 5);
            const midY = (partyAt.y + at.y) / 2 + 5;
            const d = `M ${partyAt.x} ${partyAt.y} Q ${midX} ${midY} ${at.x} ${at.y}`;
            const near = depthFactor(at.y);
            return (
              <g key={`trail-${node.id}`} opacity={0.55 + near * 0.45}>
                {/* leito de terra escavado */}
                <path d={d} fill="none" stroke="rgba(0,0,0,.5)" strokeWidth={5.2 * near} strokeLinecap="round" />
                {/* terra batida / pedras */}
                <path d={d} fill="none" stroke="rgba(196,172,126,.3)" strokeWidth={2.4 * near} strokeLinecap="round" />
                <path d={d} fill="none" stroke="rgba(228,208,166,.22)" strokeWidth={0.9 * near} strokeLinecap="round" strokeDasharray="2 5" />
                {active && (
                  <>
                    <path d={d} fill="none" stroke={mood} strokeWidth={2.6 * near} strokeLinecap="round" className="realm-trail-glow" />
                    <path
                      d={d} fill="none" stroke="rgba(255,255,255,.8)" strokeWidth={0.55}
                      strokeLinecap="round" strokeDasharray="1.4 9" className="realm-trail-flow"
                    />
                  </>
                )}
              </g>
            );
          })}
        </svg>

        {/* PLAY AREA — os destinos como lugares reais, apoiados no chão */}
        {destinations.map(({ node, at }) => {
          const mood = PLACE_MOOD[node.node_type] ?? { glow: 'rgba(252,211,77,.7)', risk: '' };
          const near = depthFactor(at.y);
          const w = (SIZE[node.node_type] ?? 18) * (0.78 + near * 0.34);
          const picked = pick?.id === node.id;
          return (
            <button
              key={node.id}
              disabled={busy || walking || Boolean(pending)}
              onClick={() => setPick(node)}
              aria-label={REALM_NODE_LABEL[node.node_type] ?? node.node_type}
              style={{
                left: `${at.x}%`, top: `${at.y}%`, width: `${w}%`,
                ['--poi-glow' as string]: mood.glow,
                opacity: 0.72 + near * 0.28,
              }}
              className={`realm-place absolute -translate-x-1/2 -translate-y-full ${picked ? 'realm-place-picked' : ''}`}
            >
              <span className="realm-place-halo" aria-hidden />
              <img
                src={PLACE_ART[node.node_type] ?? PLACE_ART.event}
                alt="" aria-hidden loading="lazy"
                style={{ filter: `drop-shadow(4px 6px 10px rgba(0,0,0,.8)) drop-shadow(0 0 14px ${mood.glow}) brightness(${0.82 + near * 0.2})` }}
                className="realm-place-art"
              />
              <span className="realm-place-shadow" aria-hidden />
              <span className="realm-place-ao" aria-hidden />
              {/* névoa de distância sobre lugares mais ao fundo */}
              {near < 0.85 && <span className="realm-place-fog" aria-hidden />}
              <span className="realm-place-tag">
                <b>{REALM_NODE_TITLE[node.node_type] ?? node.node_type}</b>
                <em style={{ color: mood.glow }}>{mood.risk}</em>
              </span>
            </button>
          );
        })}

        {/* rastro do último local visitado, atrás da equipe */}
        {last && (
          <img
            src={PLACE_ART[last.node_type] ?? PLACE_ART.event} alt="" aria-hidden loading="lazy"
            className="pointer-events-none absolute bottom-[2%] left-[6%] w-[13%] opacity-30 grayscale blur-[1px]"
          />
        )}

        {/* a equipe: "eu estou aqui" */}
        <div
          className={`realm-party-anchor ${walking ? 'is-walking' : ''}`}
          style={{ left: `${partyPos.x}%`, top: `${partyPos.y}%`, width: `${13 * depthFactor(partyPos.y) + 2}%` }}
        >
          <span className="realm-party-mark" aria-hidden />
          <span className="realm-party-shadow" aria-hidden />
          <img src={PARTY_ART} alt="Sua equipe" loading="lazy" className="realm-party-art" />
        </div>

        {/* FOG OF WAR — o resto da região continua desconhecido */}
        <div className="pointer-events-none absolute inset-x-0 top-0 h-[42%] realm-fog-far" />
        <div
          className="pointer-events-none absolute inset-y-0 right-0 realm-fogwar"
          style={{ left: `${Math.min(94, 40 + ((depth + 1) / (finalDepth + 1)) * 56)}%` }}
        />
        {/* FOREGROUND — grama, pedras, folhas e névoa rasteira */}
        <div className="pointer-events-none absolute inset-0 realm-scene-dust" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-[26%] realm-scene-fg" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-[16%] realm-scene-fg-mist" />
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
        <div className="absolute inset-0 z-[20] flex items-end bg-gradient-to-t from-black/90 via-black/35 to-transparent p-3 pb-[max(12px,env(safe-area-inset-bottom))]" onClick={() => setPick(null)}>
          <div onClick={(e) => e.stopPropagation()} className="realm-dest-sheet realm-sheet-in">
            <span className="block text-[7.5px] font-black uppercase tracking-[.3em] text-slate-500">Destino</span>
            <div className="mt-0.5 flex items-center gap-2">
              <img src={PLACE_ART[pick.node_type] ?? PLACE_ART.event} alt="" aria-hidden loading="lazy" className="h-10 w-10 flex-none object-contain" style={{ filter: `drop-shadow(0 0 10px ${PLACE_MOOD[pick.node_type]?.glow})` }} />
              <b className="flex-1 text-[13px] font-black uppercase tracking-[.12em] text-amber-100">{REALM_NODE_TITLE[pick.node_type]}</b>
              <span style={{ color: PLACE_MOOD[pick.node_type]?.glow, borderColor: PLACE_MOOD[pick.node_type]?.glow }} className="realm-badge">
                {PLACE_MOOD[pick.node_type]?.risk}
              </span>
            </div>
            <p className="mt-1.5 text-[10px] leading-4 text-slate-400">{REALM_NODE_DESC[pick.node_type]}</p>

            <div className="mt-3 grid grid-cols-2 gap-2">
              <button onClick={() => setPick(null)} className="realm-dest-ghost">Voltar</button>
              <button disabled={busy} onClick={() => travel(pick)} className="realm-dest-go disabled:opacity-40">Viajar</button>
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
