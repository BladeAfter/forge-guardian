import { useEffect, useMemo, useRef, useState } from 'react';
import { realmSecondsLeft, realmTimer, type RealmBuilding, type RealmBuildingType } from '../realm';

const SCENE = '/assets/game/realm/stronghold-scene.jpg';

/**
 * Pseudo-isometric plots. `y` is the GROUND line (base of the building),
 * `depth` 0 = far away (small, dim, foggy) → 1 = close to the camera.
 */
const PLOT: Record<string, { x: number; y: number; size: number; depth: number; glow: string }> = {
  castle: { x: 50, y: 62, size: 32, depth: 0.62, glow: '#fbbf24' },
  forge: { x: 21, y: 80, size: 23, depth: 0.95, glow: '#fb923c' },
  training_ground: { x: 79, y: 77, size: 24, depth: 0.88, glow: '#f87171' },
  pet_sanctuary: { x: 72, y: 51, size: 18, depth: 0.36, glow: '#38bdf8' },
  watchtower: { x: 25, y: 47, size: 15, depth: 0.28, glow: '#facc15' },
};

const SHORT: Record<string, string> = {
  castle: 'Castelo',
  forge: 'Forja',
  training_ground: 'Treino',
  pet_sanctuary: 'Santuário',
  watchtower: 'Vigia',
};

type BuildState = 'gated' | 'build' | 'built' | 'upgrading' | 'ready';

/** Visual scale of a building grows with its level (visual evolution, 3 tiers). */
const tierOf = (level: number) => (level >= 5 ? 2 : level >= 3 ? 1 : 0);

/**
 * 🏰 STRONGHOLD — hub pseudo-isométrico AAA (Kingdom Base View).
 *
 * Apenas apresentação: níveis, status, timers, custos e regras (inclusive o gate
 * do Castelo) continuam vindo do backend via `realm_state`. Aqui há composição
 * assimétrica, construções apoiadas no terreno, atmosfera viva, foco de câmera
 * e placas discretas — a ação acontece no painel inferior.
 */
export default function StrongholdScene({
  buildingTypes, buildings, level, now, craftingCount, onOpen,
}: {
  buildingTypes: RealmBuildingType[];
  buildings: RealmBuilding[];
  level: number;
  now: number;
  craftingCount: number;
  onOpen: (id: string) => void;
}) {
  const box = useRef<HTMLDivElement | null>(null);
  const [cam, setCam] = useState({ x: 0, y: 0, z: 1 });
  const [focus, setFocus] = useState<string | null>(null);
  const [tip, setTip] = useState<string | null>(null);
  const drag = useRef<{ x: number; y: number; cx: number; cy: number; dist: number; z: number } | null>(null);
  const [paused, setPaused] = useState(false);

  // Pause ambient animation when the mini app goes to background (mobile battery).
  useEffect(() => {
    const onVis = () => setPaused(document.hidden);
    document.addEventListener('visibilitychange', onVis);
    return () => document.removeEventListener('visibilitychange', onVis);
  }, []);

  useEffect(() => {
    if (!tip) return;
    const id = window.setTimeout(() => setTip(null), 2600);
    return () => window.clearTimeout(id);
  }, [tip]);

  const phase = useMemo<'day' | 'sunset' | 'night'>(() => {
    const h = new Date(now).getHours();
    if (h >= 7 && h < 17) return 'day';
    if (h >= 17 && h < 20) return 'sunset';
    return 'night';
  }, [Math.floor(now / 600_000)]);

  const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v));

  const castleLevel = buildings.find((b) => b.building_type === 'castle')?.level ?? 0;
  /** Riqueza visual da base cresce com o nível da fortaleza (0–3). */
  const prosperity = level >= 8 ? 3 : level >= 5 ? 2 : level >= 3 ? 1 : 0;

  const onStart = (e: React.PointerEvent | React.TouchEvent) => {
    const t = 'touches' in e ? e.touches : null;
    if (t && t.length === 2) {
      const d = Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
      drag.current = { x: 0, y: 0, cx: cam.x, cy: cam.y, dist: d, z: cam.z };
      return;
    }
    const p = t ? t[0] : (e as React.PointerEvent);
    drag.current = { x: p.clientX, y: p.clientY, cx: cam.x, cy: cam.y, dist: 0, z: cam.z };
  };

  const onMove = (e: React.TouchEvent | React.PointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const t = 'touches' in e ? e.touches : null;
    if (t && t.length === 2 && d.dist > 0) {
      const dist = Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
      setCam((c) => ({ ...c, z: clamp(d.z * (dist / d.dist), 0.9, 1.3) }));
      return;
    }
    const p = t ? t[0] : (e as React.PointerEvent);
    if (!d.x) return;
    const limit = 46 * cam.z;
    setCam((c) => ({
      ...c,
      x: clamp(d.cx + (p.clientX - d.x) * 0.35, -limit, limit),
      y: clamp(d.cy + (p.clientY - d.y) * 0.18, -22, 22),
    }));
  };

  const onEnd = () => { drag.current = null; };

  const tap = (id: string, gated: boolean, nextLevel: number) => {
    const plot = PLOT[id];
    setFocus(id);
    if (plot) {
      // Small camera push toward the touched building (cinematic focus).
      setCam({ x: clamp((50 - plot.x) * 0.95, -46, 46), y: clamp((58 - plot.y) * 0.4, -22, 22), z: 1.2 });
    }
    if (gated) {
      setTip(`Requer Castelo Lv.${nextLevel}`);
      return;
    }
    window.setTimeout(() => onOpen(id), 240);
  };

  /** Far buildings render first so close ones overlap them correctly. */
  const rows = buildingTypes
    .filter((bt) => PLOT[bt.id])
    .sort((a, b) => PLOT[a.id].depth - PLOT[b.id].depth);

  const castlePlot = PLOT.castle;

  return (
    <section className="space-y-2">
      <div
        ref={box}
        onPointerDown={onStart}
        onPointerMove={onMove}
        onPointerUp={onEnd}
        onPointerLeave={onEnd}
        onTouchStart={onStart}
        onTouchMove={onMove}
        onTouchEnd={onEnd}
        className="stronghold-stage relative h-[66vh] min-h-[400px] w-full touch-pan-y select-none overflow-hidden rounded-3xl"
      >
        {/* ── BACKGROUND: montanhas e muralhas distantes (parallax lento) ──── */}
        <div
          className="absolute inset-[-7%] bg-cover bg-center"
          style={{
            backgroundImage: `url(${SCENE})`,
            transform: `translate3d(${cam.x * 0.32}px, ${cam.y * 0.32}px, 0) scale(${cam.z * 1.06})`,
            transition: 'transform 300ms cubic-bezier(.22,1,.36,1)',
          }}
        />
        <div className={`absolute inset-0 stronghold-tint stronghold-tint-${phase}`} />
        <div className="sh-depth-haze pointer-events-none absolute inset-x-0 top-0 h-[46%]" />
        {!paused && <div className="stronghold-mist pointer-events-none absolute inset-0" />}
        {!paused && <div className="stronghold-rays pointer-events-none absolute inset-0" />}
        {!paused && prosperity > 0 && <div className="stronghold-embers pointer-events-none absolute inset-0" />}
        {!paused && prosperity >= 2 && <div className="stronghold-fireflies pointer-events-none absolute inset-0" />}
        <div className={`stronghold-prosperity pointer-events-none absolute inset-0 stronghold-prosperity-${prosperity}`} />

        {/* ── MIDGROUND: terreno construído (pátio, caminhos, trilhas) ─────── */}
        <div
          className="absolute inset-0"
          style={{ transform: `translate3d(${cam.x}px, ${cam.y}px, 0) scale(${cam.z})`, transition: 'transform 300ms cubic-bezier(.22,1,.36,1)' }}
        >
          <div className="sh-courtyard pointer-events-none" />
          <div className="sh-plaza-ring pointer-events-none" />

          {/* caminhos de pedra ligando o castelo às demais construções */}
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="pointer-events-none absolute inset-0 h-full w-full">
            {rows.filter((bt) => bt.id !== 'castle').map((bt) => {
              const p = PLOT[bt.id];
              const b = buildings.find((x) => x.building_type === bt.id);
              const lit = (b?.level ?? 0) > 0;
              const mid = { x: (castlePlot.x + p.x) / 2 + (p.x < 50 ? -4 : 4), y: (castlePlot.y + p.y) / 2 + 3 };
              const d = `M ${castlePlot.x} ${castlePlot.y} Q ${mid.x} ${mid.y} ${p.x} ${p.y}`;
              const w = 1.4 + p.depth * 2.4;
              return (
                <g key={`path-${bt.id}`} opacity={0.35 + p.depth * 0.4}>
                  <path d={d} fill="none" stroke="rgba(0,0,0,.5)" strokeWidth={w + 1.6} strokeLinecap="round" />
                  <path d={d} fill="none" stroke="rgba(203,184,146,.26)" strokeWidth={w} strokeLinecap="round" />
                  {lit && (
                    <path
                      d={d} fill="none" stroke={`${p.glow}aa`} strokeWidth={0.5}
                      strokeLinecap="round" strokeDasharray="1.2 8" className={paused ? '' : 'sh-path-flow'}
                    />
                  )}
                </g>
              );
            })}
          </svg>

          {/* ── PRÉDIOS: apoiados no terreno, sem visual de adesivo ────────── */}
          {rows.map((bt) => {
            const plot = PLOT[bt.id];
            const b = buildings.find((x) => x.building_type === bt.id);
            const lvl = b?.level ?? 0;
            const left = realmSecondsLeft(b?.upgrade_finishes_at, now);
            const upgrading = Boolean(b && b.status !== 'idle' && left > 0);
            const ready = Boolean(b && b.status !== 'idle' && left <= 0);
            // Gate real do backend: nível seguinte não pode passar do Castelo.
            const gated = bt.id !== 'castle' && !upgrading && !ready && lvl + 1 > castleLevel;
            const state: BuildState = ready ? 'ready' : upgrading ? 'upgrading' : gated ? 'gated' : lvl > 0 ? 'built' : 'build';
            const dim = lvl === 0;
            const tier = tierOf(lvl);
            const focused = focus === bt.id;
            const near = plot.depth;

            return (
              <button
                key={bt.id}
                onClick={(e) => { e.stopPropagation(); tap(bt.id, gated && lvl === 0, lvl + 1); }}
                aria-label={`${bt.name} nível ${lvl}`}
                className={`sh-lot absolute ${focused ? 'sh-lot-on' : ''} ${focus && !focused ? 'sh-lot-off' : ''}`}
                style={{
                  left: `${plot.x}%`,
                  top: `${plot.y}%`,
                  width: `${plot.size + tier * 2.5}%`,
                  zIndex: Math.round(near * 100) + (focused ? 200 : 0),
                  ['--sh-glow' as string]: plot.glow,
                  opacity: dim ? 0.85 : 0.74 + near * 0.26,
                }}
              >
                {/* terreno: plataforma de pedra + sombra de contato + oclusão */}
                <span className="sh-ground pointer-events-none" />
                <span className="sh-shadow pointer-events-none" />
                <span className="sh-ao pointer-events-none" />

                {!dim && !paused && <span className="sh-halo pointer-events-none" />}
                {focused && <span className="sh-outline pointer-events-none" />}
                {focused && !paused && <span className="sh-select-motes pointer-events-none" />}

                <span className="stronghold-art">
                  {bt.image_url && (
                    <img
                      src={bt.image_url}
                      alt=""
                      loading="lazy"
                      className={`relative mx-auto w-full object-contain ${dim ? 'stronghold-ghost' : ''} ${upgrading ? 'stronghold-works' : ''}`}
                      style={{
                        filter: dim
                          ? undefined
                          : `drop-shadow(5px 9px 12px rgba(0,0,0,.82)) drop-shadow(0 0 16px ${plot.glow}30) brightness(${0.8 + near * 0.24}) contrast(${0.94 + near * 0.12})`,
                      }}
                    />
                  )}

                  {/* névoa atmosférica nas construções mais distantes */}
                  {near < 0.5 && <span className="sh-far-fog pointer-events-none" />}

                  {/* ambientação viva por construção */}
                  {!paused && !dim && bt.id === 'forge' && (
                    <>
                      <span className="stronghold-smoke" />
                      <span className="stronghold-spark" />
                      <span className="sh-forge-fire" />
                    </>
                  )}
                  {!paused && !dim && bt.id === 'pet_sanctuary' && <span className="stronghold-motes" />}
                  {!paused && !dim && bt.id === 'castle' && (
                    <>
                      <span className="stronghold-flag" />
                      <span className="sh-windows" />
                    </>
                  )}
                  {!paused && !dim && bt.id === 'watchtower' && <span className="stronghold-torch" />}
                  {!paused && !dim && bt.id === 'training_ground' && <span className="stronghold-npc" />}
                  {upgrading && !paused && <span className="stronghold-dust" />}
                </span>

                {/* placa discreta: nome · nível (+ estado só quando importa) */}
                <span className={`sh-tag ${focused ? 'sh-tag-on' : ''}`}>
                  <b>{SHORT[bt.id] ?? bt.name} <em>{lvl > 0 ? `Lv.${lvl}` : 'Lv.0'}</em></b>
                  {state === 'upgrading' && <i className="sh-tag-work tabular-nums">{realmTimer(left)}</i>}
                  {state === 'ready' && <i className="sh-tag-ready">Pronto</i>}
                  {state === 'build' && <i className="sh-tag-build">Construir</i>}
                  {state === 'gated' && lvl === 0 && <i className="sh-tag-lock">🔒</i>}
                  {state === 'built' && bt.id === 'forge' && craftingCount > 0 && <i className="sh-tag-craft">Forjando</i>}
                </span>
              </button>
            );
          })}

          {/* tochas do pátio, à frente das construções */}
          {!paused && (
            <>
              <span className="sh-brazier" style={{ left: '38%', top: '86%' }} />
              <span className="sh-brazier" style={{ left: '62%', top: '88%' }} />
            </>
          )}
        </div>

        {/* ── FOREGROUND: chão de pedra, névoa rasteira, vinheta e moldura ── */}
        <div className="sh-fg-stone pointer-events-none absolute inset-x-0 bottom-0 h-[22%]" />
        <div className="sh-fg-mist pointer-events-none absolute inset-x-0 bottom-0 h-[14%]" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-[#05070f] via-[#05070f]/60 to-transparent" />
        <div className="pointer-events-none absolute inset-0 shadow-[inset_0_0_140px_50px_rgba(0,0,0,.8)]" />
        <div className="stronghold-frame pointer-events-none absolute inset-0" />

        {/* HUD da cena — discreto */}
        <div className="stronghold-hud pointer-events-none absolute left-3 top-3">
          <span className="stronghold-crest">⚜</span>
          <span>Fortaleza <b className="text-amber-100">Lv.{level}</b></span>
        </div>
        <button
          onClick={() => { setCam({ x: 0, y: 0, z: 1 }); setFocus(null); }}
          className="sh-recenter absolute right-3 top-3"
          aria-label="Centralizar câmera"
        >
          ⟟
        </button>

        {tip && <span className="stronghold-tip">{tip}</span>}
      </div>
      <p className="text-center text-[9px] text-slate-500">Arraste para explorar · pinça para aproximar · toque em uma construção</p>
    </section>
  );
}
