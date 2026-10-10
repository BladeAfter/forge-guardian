import { useLocalizedText } from '../LanguageContext';
import { useEffect, useMemo, useRef, useState } from 'react';
import { type RealmBuilding, type RealmBuildingType } from '../realm';
import { useT } from '../LanguageContext';

const SCENE = '/assets/game/realm/stronghold-scene.jpg';

/**
 * The fortress is ONE painted scene (like the reference art). Each building is a
 * hot spot over its painted structure — nothing is pasted on top of the art.
 * `hit` = touch area (centre of the structure), `ring` = ground ellipse used for
 * the golden selection highlight.
 */
const SPOT: Record<string, {
  hit: { x: number; y: number; w: number; h: number };
  ring: { x: number; y: number; w: number; skew: number };
  glow: string;
}> = {
  castle: { hit: { x: 48, y: 24, w: 34, h: 26 }, ring: { x: 48, y: 40, w: 30, skew: 0.34 }, glow: '#fbbf24' },
  pet_sanctuary: { hit: { x: 14, y: 32, w: 22, h: 22 }, ring: { x: 15, y: 45, w: 24, skew: 0.32 }, glow: '#a78bfa' },
  watchtower: { hit: { x: 87, y: 20, w: 18, h: 24 }, ring: { x: 87, y: 36, w: 17, skew: 0.3 }, glow: '#facc15' },
  training_ground: { hit: { x: 20, y: 78, w: 34, h: 20 }, ring: { x: 20, y: 82, w: 36, skew: 0.4 }, glow: '#f87171' },
  forge: { hit: { x: 76, y: 79, w: 32, h: 22 }, ring: { x: 76, y: 88, w: 32, skew: 0.4 }, glow: '#fb923c' },
};

const SHORT_KEY: Record<string, string> = {
  castle: 'realm.b.castle',
  forge: 'realm.b.forge',
  training_ground: 'realm.b.training_ground',
  pet_sanctuary: 'realm.b.pet_sanctuary',
  watchtower: 'realm.b.watchtower',
};

/**
 * 🏰 STRONGHOLD — a fortaleza pintada como cena única (referência AAA).
 *
 * Apenas apresentação: níveis, status, timers, custos e regras (inclusive o gate
 * do Castelo) continuam vindo do backend via `realm_state`. Nada de sprites
 * colados: o jogador toca na construção dentro da arte, ela recebe o anel
 * dourado e o painel inferior abre com a ação.
 */
export default function StrongholdScene({
  buildingTypes, buildings, level, now, onOpen,
}: {
  buildingTypes: RealmBuildingType[];
  buildings: RealmBuilding[];
  level: number;
  now: number;
  onOpen: (id: string) => void;
}) {
  const localizeText = useLocalizedText();

  const t = useT();
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
      setCam((c) => ({ ...c, z: clamp(d.z * (dist / d.dist), 1, 1.35) }));
      return;
    }
    const p = t ? t[0] : (e as React.PointerEvent);
    if (!d.x) return;
    const limit = 34 * cam.z;
    setCam((c) => ({
      ...c,
      x: clamp(d.cx + (p.clientX - d.x) * 0.3, -limit, limit),
      y: clamp(d.cy + (p.clientY - d.y) * 0.22, -30, 30),
    }));
  };

  const onEnd = () => { drag.current = null; };

  const tap = (id: string, gated: boolean, nextLevel: number) => {
    const spot = SPOT[id];
    setFocus(id);
    if (spot) {
      // Leve aproximação cinematográfica na construção tocada.
      setCam({ x: clamp((50 - spot.hit.x) * 0.5, -34, 34), y: clamp((50 - spot.hit.y) * 0.34, -30, 30), z: 1.12 });
    }
    if (gated) {
      setTip(t('realm.build.gated', { level: nextLevel }));
      return;
    }
    window.setTimeout(() => onOpen(id), 240);
  };

  const rows = buildingTypes.filter((bt) => SPOT[bt.id]);

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
        className="stronghold-stage sh-frame relative h-[68vh] min-h-[420px] w-full touch-pan-y select-none overflow-hidden"
      >
        {/* A FORTALEZA: uma única arte pintada, sem elementos colados */}
        <div
          className="absolute inset-0"
          style={{
            transform: `translate3d(${cam.x}px, ${cam.y}px, 0) scale(${cam.z})`,
            transition: 'transform 320ms cubic-bezier(.22,1,.36,1)',
          }}
        >
          <img
            src={SCENE}
            alt=""
            width={1024}
            height={1280}
            className="absolute inset-0 h-full w-full object-cover"
          />
          <div className={`absolute inset-0 stronghold-tint stronghold-tint-${phase}`} />
          {!paused && <div className="stronghold-mist pointer-events-none absolute inset-0" />}
          {!paused && prosperity > 0 && <div className="stronghold-embers pointer-events-none absolute inset-0" />}
          {!paused && prosperity >= 2 && <div className="stronghold-fireflies pointer-events-none absolute inset-0" />}
          <div className={`stronghold-prosperity pointer-events-none absolute inset-0 stronghold-prosperity-${prosperity}`} />

          {/* HOT SPOTS: cada construção pintada é tocável */}
          {rows.map((bt) => {
            const spot = SPOT[bt.id];
            const b = buildings.find((x) => x.building_type === bt.id);
            const lvl = b?.level ?? 0;
            const gated = bt.id !== 'castle' && b?.status === 'idle' && lvl + 1 > castleLevel;
            const focused = focus === bt.id;

            return (
              <button
                key={bt.id}
                onClick={(e) => { e.stopPropagation(); tap(bt.id, gated && lvl === 0, lvl + 1); }}
                aria-label={`${bt.name} Lv.${lvl}`}
                className="sh-hit absolute"
                style={{
                  left: `${spot.hit.x}%`, top: `${spot.hit.y}%`,
                  width: `${spot.hit.w}%`, height: `${spot.hit.h}%`,
                  ['--sh-glow' as string]: spot.glow,
                  zIndex: focused ? 30 : 20,
                }}
              >
                {/* anel dourado no chão, como na arte de referência */}
                <span
                  className={`sh-ring pointer-events-none ${focused ? 'sh-ring-on' : ''} ${paused ? '' : 'sh-ring-live'}`}
                  style={{
                    left: `${((spot.ring.x - spot.hit.x) / spot.hit.w) * 100 + 50}%`,
                    top: `${((spot.ring.y - spot.hit.y) / spot.hit.h) * 100 + 50}%`,
                    width: `${(spot.ring.w / spot.hit.w) * 100}%`,
                    height: `${(spot.ring.w / spot.hit.w) * 100 * spot.ring.skew}%`,
                    opacity: focused ? 1 : lvl > 0 ? 0.34 : 0.16,
                  }}
                />
                {focused && <span className="sh-focus-glow pointer-events-none" />}

                {/* placa discreta, integrada à cena */}
                <span className={`sh-name ${focused ? 'sh-name-on' : ''}`}>
                  <b>{t(SHORT_KEY[bt.id] ?? '') || bt.name} <em>{localizeText("Lv.")}{lvl}</em></b>
                </span>
              </button>
            );
          })}
        </div>

        {/* atmosfera de frente + vinheta nobre */}
        <div className="sh-fg-mist pointer-events-none absolute inset-x-0 bottom-0 h-[14%]" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-[#05070f]/95 via-[#05070f]/45 to-transparent" />
        <div className="pointer-events-none absolute inset-0 shadow-[inset_0_0_130px_46px_rgba(0,0,0,.72)]" />

        <div className="stronghold-hud pointer-events-none absolute left-3 top-3">
          <span className="stronghold-crest">⚜</span>
          <span>{t('realm.strongholdCap')} <b className="text-amber-100">{localizeText("Lv.")}{level}</b></span>
        </div>
        <button
          onClick={() => { setCam({ x: 0, y: 0, z: 1 }); setFocus(null); }}
          className="sh-recenter absolute right-3 top-3"
          aria-label="recenter"
        >
          ⟟
        </button>

        {tip && <span className="stronghold-tip">{tip}</span>}
      </div>
      <p className="text-center text-[9px] text-slate-500">{t('realm.sh.hint')}</p>
    </section>
  );
}
