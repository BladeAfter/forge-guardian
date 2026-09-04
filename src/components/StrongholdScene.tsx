import { useEffect, useMemo, useRef, useState } from 'react';
import { realmSecondsLeft, realmTimer, type RealmBuilding, type RealmBuildingType } from '../realm';

const SCENE = '/assets/game/realm/stronghold-scene.jpg';

/** Fixed plot for each building inside the scene (percentages of the scene box). */
const PLOT: Record<string, { x: number; y: number; size: number; depth: number; glow: string }> = {
  castle: { x: 52, y: 56, size: 40, depth: 0.6, glow: '#fbbf24' },
  forge: { x: 74, y: 65, size: 26, depth: 0.75, glow: '#fb923c' },
  training_ground: { x: 28, y: 52, size: 26, depth: 0.5, glow: '#f87171' },
  pet_sanctuary: { x: 47, y: 40, size: 23, depth: 0.3, glow: '#38bdf8' },
  watchtower: { x: 76, y: 45, size: 22, depth: 0.35, glow: '#facc15' },
};


const SHORT: Record<string, string> = {
  castle: 'CASTELO',
  forge: 'FORJA',
  training_ground: 'TREINO',
  pet_sanctuary: 'SANTUÁRIO',
  watchtower: 'VIGIA',
};

type BuildState = 'gated' | 'build' | 'built' | 'upgrading' | 'ready';

/** Visual scale of a building grows with its level (visual evolution, 3 tiers). */
const tierOf = (level: number) => (level >= 5 ? 2 : level >= 3 ? 1 : 0);

/**
 * 🏰 STRONGHOLD — cena interativa AAA (Kingdom Base View).
 *
 * Apenas apresentação: níveis, status, timers e regras (inclusive o gate do Castelo)
 * continuam vindo do backend via `realm_state`. Aqui há pan, pinça, parallax,
 * atmosfera viva, foco cinematográfico e selos elegantes de nível/bloqueio.
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
      setCam({ x: clamp((50 - plot.x) * 0.95, -46, 46), y: clamp((52 - plot.y) * 0.38, -22, 22), z: 1.22 });
    }
    if (gated) {
      setTip(`Requer Castelo Lv.${nextLevel}`);
      return;
    }
    window.setTimeout(() => onOpen(id), 220);
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
        className="stronghold-stage relative aspect-[4/5] w-full touch-pan-y select-none overflow-hidden rounded-3xl"
      >
        {/* BACKGROUND (parallax lento) */}
        <div
          className="absolute inset-[-6%] bg-cover bg-center"
          style={{
            backgroundImage: `url(${SCENE})`,
            transform: `translate3d(${cam.x * 0.35}px, ${cam.y * 0.35}px, 0) scale(${cam.z * 1.05})`,
            transition: 'transform 280ms cubic-bezier(.22,1,.36,1)',
          }}
        />
        <div className={`absolute inset-0 stronghold-tint stronghold-tint-${phase}`} />
        {!paused && <div className="stronghold-mist pointer-events-none absolute inset-0" />}
        {!paused && <div className="stronghold-rays pointer-events-none absolute inset-0" />}
        {!paused && prosperity > 0 && <div className="stronghold-embers pointer-events-none absolute inset-0" />}
        {!paused && prosperity >= 2 && <div className="stronghold-fireflies pointer-events-none absolute inset-0" />}
        <div className={`stronghold-prosperity pointer-events-none absolute inset-0 stronghold-prosperity-${prosperity}`} />

        {/* halo do pátio central — dá nobreza ao pedestal do castelo */}
        <div className="stronghold-plaza pointer-events-none absolute left-1/2 top-[48%] -translate-x-1/2 -translate-y-1/2" />

        {/* MIDGROUND — prédios clicáveis */}
        <div
          className="absolute inset-0"
          style={{ transform: `translate3d(${cam.x}px, ${cam.y}px, 0) scale(${cam.z})`, transition: 'transform 280ms cubic-bezier(.22,1,.36,1)' }}
        >
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

            return (
              <button
                key={bt.id}
                onClick={(e) => { e.stopPropagation(); tap(bt.id, gated && lvl === 0, lvl + 1); }}
                aria-label={`${bt.name} nível ${lvl}`}
                className={`stronghold-slot absolute -translate-x-1/2 -translate-y-1/2 ${focused ? 'stronghold-slot-on' : ''} ${focus && !focused ? 'stronghold-slot-off' : ''}`}
                style={{ left: `${plot.x}%`, top: `${plot.y}%`, width: `${plot.size + tier * 3}%`, zIndex: Math.round(plot.depth * 10) + (focused ? 20 : 0) }}
              >
                {/* pedestal + reflexo no chão de pedra */}
                <span className="stronghold-pad pointer-events-none" style={{ background: `radial-gradient(ellipse at center, ${plot.glow}2e, transparent 70%)` }} />

                {/* aura da construção */}
                {!dim && !paused && (
                  <span
                    className="stronghold-aura pointer-events-none absolute left-1/2 top-[58%] -translate-x-1/2 -translate-y-1/2"
                    style={{ background: `radial-gradient(circle, ${plot.glow}55, transparent 68%)` }}
                  />
                )}
                {focused && <span className="stronghold-focus pointer-events-none" style={{ borderColor: `${plot.glow}80` }} />}

                {bt.image_url && (
                  <img
                    src={bt.image_url}
                    alt=""
                    loading="lazy"
                    className={`relative mx-auto w-full object-contain ${dim ? 'opacity-40 brightness-[.4] saturate-0' : ''} ${upgrading ? 'stronghold-works' : ''}`}
                    style={{ filter: dim ? undefined : `drop-shadow(0 8px 16px ${plot.glow}45) drop-shadow(0 2px 2px rgba(0,0,0,.8))` }}
                  />
                )}

                {/* partículas de ambientação por prédio */}
                {!paused && !dim && bt.id === 'forge' && (
                  <>
                    <span className="stronghold-smoke" />
                    <span className="stronghold-spark" />
                  </>
                )}
                {!paused && !dim && bt.id === 'pet_sanctuary' && <span className="stronghold-motes" />}
                {!paused && !dim && bt.id === 'castle' && <span className="stronghold-flag" />}
                {!paused && !dim && bt.id === 'watchtower' && <span className="stronghold-torch" />}
                {!paused && !dim && bt.id === 'training_ground' && <span className="stronghold-npc" />}
                {upgrading && !paused && <span className="stronghold-dust" />}

                {/* placa elegante: nome + selo de nível */}
                <span className="stronghold-plate">
                  <b className={focused ? 'text-amber-100' : 'text-slate-100/90'}>{SHORT[bt.id] ?? bt.name}</b>
                  <i className="stronghold-seal">{lvl > 0 ? `Lv.${lvl}` : '—'}</i>
                </span>

                {/* estado — apenas 1 badge por prédio */}
                {state === 'build' && (
                  <span className="stronghold-badge border-amber-300/60 bg-amber-500/20 text-amber-100">CONSTRUIR</span>
                )}
                {state === 'gated' && lvl === 0 && (
                  <span className="stronghold-badge border-slate-400/40 bg-black/60 text-slate-300">⌁ Lv.{lvl + 1}</span>
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

        {/* FOREGROUND — névoa, vinheta e moldura nobre */}
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-32 bg-gradient-to-t from-[#05070f] via-[#05070f]/70 to-transparent" />
        <div className="pointer-events-none absolute inset-0 shadow-[inset_0_0_130px_45px_rgba(0,0,0,.78)]" />
        <div className="stronghold-frame pointer-events-none absolute inset-0" />

        {/* HUD da cena */}
        <div className="stronghold-hud pointer-events-none absolute left-3 top-3">
          <span className="stronghold-crest">⚜</span>
          <span>Fortaleza <b className="text-amber-100">Lv.{level}</b></span>
        </div>
        <button
          onClick={() => { setCam({ x: 0, y: 0, z: 1 }); setFocus(null); }}
          className="stronghold-recenter absolute right-3 top-3"
          aria-label="Centralizar câmera"
        >
          ⟟ Centralizar
        </button>

        {tip && <span className="stronghold-tip">{tip}</span>}
      </div>
      <p className="text-center text-[9px] text-slate-500">Arraste para explorar · pinça para aproximar · toque em uma construção</p>
    </section>
  );
}
