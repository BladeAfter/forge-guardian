import { useEffect, useMemo, useRef, useState } from 'react';
import { realmSecondsLeft, realmTimer, type RealmBuilding, type RealmBuildingType } from '../realm';

const SCENE = '/assets/game/realm/stronghold-scene.jpg';

/** Fixed plot for each building inside the scene (percentages of the scene box). */
const PLOT: Record<string, { x: number; y: number; size: number; depth: number; glow: string }> = {
  castle: { x: 50, y: 40, size: 34, depth: 0.35, glow: '#fbbf24' },
  forge: { x: 76, y: 60, size: 22, depth: 0.7, glow: '#fb923c' },
  training_ground: { x: 24, y: 60, size: 22, depth: 0.7, glow: '#f87171' },
  pet_sanctuary: { x: 31, y: 80, size: 21, depth: 1, glow: '#38bdf8' },
  watchtower: { x: 70, y: 82, size: 21, depth: 1, glow: '#facc15' },
};

const SHORT: Record<string, string> = {
  castle: 'CASTELO',
  forge: 'FORJA',
  training_ground: 'TREINO',
  pet_sanctuary: 'SANTUÁRIO',
  watchtower: 'VIGIA',
};

type BuildState = 'locked' | 'build' | 'built' | 'upgrading' | 'ready';

/** Visual scale of a building grows with its level (visual evolution, 3 tiers). */
const tierOf = (level: number) => (level >= 5 ? 2 : level >= 3 ? 1 : 0);

/**
 * 🏰 STRONGHOLD — interactive AAA hub.
 *
 * Pure presentation: every level/status/timer comes from `realm_state`. Buildings are
 * touch targets placed inside a single painted scene (no card grid), with pan + limited
 * pinch zoom, parallax layers, ambient particles and day/night tint.
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
  const drag = useRef<{ x: number; y: number; cx: number; cy: number; dist: number; z: number } | null>(null);
  const [paused, setPaused] = useState(false);

  // Pause ambient animation when the mini app goes to background (mobile battery).
  useEffect(() => {
    const onVis = () => setPaused(document.hidden);
    document.addEventListener('visibilitychange', onVis);
    return () => document.removeEventListener('visibilitychange', onVis);
  }, []);

  const phase = useMemo<'day' | 'sunset' | 'night'>(() => {
    const h = new Date(now).getHours();
    if (h >= 7 && h < 17) return 'day';
    if (h >= 17 && h < 20) return 'sunset';
    return 'night';
  }, [Math.floor(now / 600_000)]);

  const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v));

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
      setCam((c) => ({ ...c, z: clamp(d.z * (dist / d.dist), 0.9, 1.25) }));
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

  const tap = (id: string) => {
    const plot = PLOT[id];
    setFocus(id);
    if (plot) {
      // Small camera push toward the touched building (150–300ms transition in CSS).
      setCam({ x: clamp((50 - plot.x) * 0.9, -46, 46), y: clamp((52 - plot.y) * 0.35, -22, 22), z: 1.2 });
    }
    window.setTimeout(() => onOpen(id), 200);
  };

  const rows = buildingTypes
    .filter((bt) => PLOT[bt.id])
    .sort((a, b) => PLOT[a.id].depth - PLOT[b.id].depth);

  return (
    <section className="space-y-3">
      <div
        ref={box}
        onPointerDown={onStart}
        onPointerMove={onMove}
        onPointerUp={onEnd}
        onPointerLeave={onEnd}
        onTouchStart={onStart}
        onTouchMove={onMove}
        onTouchEnd={onEnd}
        className="stronghold-stage relative aspect-[4/5] w-full touch-pan-y select-none overflow-hidden rounded-3xl border border-white/10"
      >
        {/* BACKGROUND (parallax lento) */}
        <div
          className="absolute inset-[-6%] bg-cover bg-center"
          style={{
            backgroundImage: `url(${SCENE})`,
            transform: `translate3d(${cam.x * 0.35}px, ${cam.y * 0.35}px, 0) scale(${cam.z * 1.04})`,
            transition: 'transform 240ms ease-out',
          }}
        />
        <div className={`absolute inset-0 stronghold-tint stronghold-tint-${phase}`} />
        {!paused && <div className="stronghold-mist pointer-events-none absolute inset-0" />}

        {/* MIDGROUND — prédios clicáveis */}
        <div
          className="absolute inset-0"
          style={{ transform: `translate3d(${cam.x}px, ${cam.y}px, 0) scale(${cam.z})`, transition: 'transform 240ms ease-out' }}
        >
          {rows.map((bt) => {
            const plot = PLOT[bt.id];
            const b = buildings.find((x) => x.building_type === bt.id);
            const lvl = b?.level ?? 0;
            const left = realmSecondsLeft(b?.upgrade_finishes_at, now);
            const upgrading = Boolean(b && b.status !== 'idle' && left > 0);
            const ready = Boolean(b && b.status !== 'idle' && left <= 0);
            const state: BuildState = ready ? 'ready' : upgrading ? 'upgrading' : lvl > 0 ? 'built' : 'build';
            const tier = tierOf(lvl);
            const focused = focus === bt.id;

            return (
              <button
                key={bt.id}
                onClick={(e) => { e.stopPropagation(); tap(bt.id); }}
                aria-label={`${bt.name} nível ${lvl}`}
                className={`stronghold-slot absolute -translate-x-1/2 -translate-y-1/2 ${focused ? 'stronghold-slot-on' : ''}`}
                style={{ left: `${plot.x}%`, top: `${plot.y}%`, width: `${plot.size + tier * 3}%` }}
              >
                {/* aura da construção */}
                {state !== 'build' && !paused && (
                  <span
                    className="stronghold-aura pointer-events-none absolute left-1/2 top-[58%] -translate-x-1/2 -translate-y-1/2"
                    style={{ background: `radial-gradient(circle, ${plot.glow}55, transparent 68%)` }}
                  />
                )}

                {bt.image_url && (
                  <img
                    src={bt.image_url}
                    alt=""
                    loading="lazy"
                    className={`relative mx-auto w-full object-contain ${state === 'build' ? 'opacity-45 brightness-[.45] saturate-50' : ''} ${upgrading ? 'stronghold-works' : ''}`}
                    style={{ filter: state === 'build' ? undefined : `drop-shadow(0 6px 14px ${plot.glow}40)` }}
                  />
                )}

                {/* partículas de ambientação por prédio */}
                {!paused && state !== 'build' && bt.id === 'forge' && (
                  <>
                    <span className="stronghold-smoke" />
                    <span className="stronghold-spark" />
                  </>
                )}
                {!paused && state !== 'build' && bt.id === 'pet_sanctuary' && <span className="stronghold-motes" />}
                {!paused && state !== 'build' && bt.id === 'castle' && <span className="stronghold-flag" />}
                {!paused && state !== 'build' && bt.id === 'watchtower' && <span className="stronghold-torch" />}
                {!paused && state !== 'build' && bt.id === 'training_ground' && <span className="stronghold-npc" />}
                {upgrading && !paused && <span className="stronghold-dust" />}

                {/* label mínima: nome + nível */}
                <span className="mt-0.5 block text-center">
                  <b className={`block text-[8px] font-black uppercase tracking-[.16em] ${focused ? 'text-amber-100' : 'text-slate-200/90'}`} style={{ textShadow: '0 1px 4px #000' }}>
                    {SHORT[bt.id] ?? bt.name}
                  </b>
                  <span className="block text-[8px] font-bold text-slate-400" style={{ textShadow: '0 1px 4px #000' }}>Lv.{lvl}</span>
                </span>

                {/* estado — apenas 1 badge por prédio */}
                {state === 'build' && (
                  <span className="stronghold-badge border-amber-300/60 bg-amber-500/20 text-amber-100">CONSTRUIR</span>
                )}
                {state === 'upgrading' && (
                  <span className="stronghold-badge border-cyan-300/50 bg-cyan-500/20 tabular-nums text-cyan-100">{realmTimer(left)}</span>
                )}
                {state === 'ready' && (
                  <span className="stronghold-badge stronghold-badge-pulse border-emerald-300/60 bg-emerald-500/25 text-emerald-100">PRONTO</span>
                )}
                {state === 'built' && bt.id === 'forge' && craftingCount > 0 && (
                  <span className="stronghold-badge border-orange-300/50 bg-orange-500/20 text-orange-100">FORJANDO</span>
                )}
              </button>
            );
          })}
        </div>

        {/* FOREGROUND — névoa e vinheta */}
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-[#05070f] via-[#05070f]/70 to-transparent" />
        <div className="pointer-events-none absolute inset-0 shadow-[inset_0_0_120px_40px_rgba(0,0,0,.75)]" />

        {/* HUD mínimo da cena */}
        <div className="pointer-events-none absolute left-3 top-3 rounded-full border border-amber-300/25 bg-black/45 px-2.5 py-1 text-[9px] font-black uppercase tracking-[.18em] text-amber-100 backdrop-blur">
          Fortaleza Lv.{level}
        </div>
        <button
          onClick={() => { setCam({ x: 0, y: 0, z: 1 }); setFocus(null); }}
          className="absolute right-3 top-3 rounded-full border border-white/15 bg-black/45 px-2.5 py-1 text-[9px] font-bold text-slate-300 backdrop-blur"
        >
          Centralizar
        </button>
      </div>
      <p className="text-center text-[9px] text-slate-500">Arraste para explorar · pinça para aproximar · toque em uma construção</p>
    </section>
  );
}
