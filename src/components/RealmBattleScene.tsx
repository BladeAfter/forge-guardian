import { useEffect, useMemo, useState } from 'react';
import type { RealmExploreLog } from '../realm';

const HERO_IMG = '/assets/game/realm/battle-hero.png';

type Theme = {
  key: 'greenvale' | 'crystal' | 'abyss';
  foe: string;
  ground: string;
  foreground: string;
};

/** Region id → battlefield theme (background art, ground plane, foreground vegetation, enemy). */
function themeOf(regionId?: string | null): Theme {
  const id = (regionId ?? '').toLowerCase();
  if (id.includes('crystal') || id.includes('rift')) {
    return {
      key: 'crystal',
      foe: '/assets/game/realm/foe-crystal-rift.png',
      ground: '/assets/game/realm/battle-ground-crystal-rift.jpg',
      foreground: '/assets/game/realm/battle-fg-crystal-rift.png',
    };
  }
  if (id.includes('abyss') || id.includes('void')) {
    return {
      key: 'abyss',
      foe: '/assets/game/realm/foe-abyss.png',
      ground: '/assets/game/realm/battle-ground-abyss.jpg',
      foreground: '/assets/game/realm/battle-fg-abyss.png',
    };
  }
  return {
    key: 'greenvale',
    foe: '/assets/game/realm/foe-greenvale.png',
    ground: '/assets/game/realm/battle-ground-greenvale.jpg',
    foreground: '/assets/game/realm/battle-fg-greenvale.png',
  };
}

/**
 * Fixed combat slots. `x` is the horizontal center, `groundY` is the ground line the
 * sprite's feet are anchored to (percent from the top of the battlefield stage), and
 * `scale` handles the small perspective difference between near/far combatants.
 */
const PLAYER_SLOT = { x: 30, groundY: 79, scale: 1.0 };
const ENEMY_SLOT = { x: 71, groundY: 74, scale: 0.92 };

const fmt = (n: number) => n.toLocaleString('pt-BR');

type Props = {
  log: RealmExploreLog;
  regionId?: string | null;
  regionName?: string | null;
  regionImage?: string | null;
  onClose: () => void;
};

/**
 * ⚔️ REALM BATTLE SCENE — fullscreen cinematic combat inside a layered battlefield stage.
 *
 * Presentation only: replays the rounds the backend already resolved. Combatants are grounded
 * with contact shadows + ambient occlusion, sit on a real ground plane, receive light wrap from
 * the environment and are partially overlapped by foreground vegetation. No combat math here.
 */
export default function RealmBattleScene({ log, regionId, regionName, regionImage, onClose }: Props) {
  const rounds = log.rounds ?? [];
  const theme = useMemo(() => themeOf(regionId), [regionId]);
  const totals = useMemo(() => ({
    foe: rounds.reduce((s, r) => s + Number(r.playerHit ?? 0), 0) || 1,
    hero: rounds.reduce((s, r) => s + Number(r.enemyHit ?? 0), 0) || 1,
  }), [rounds]);

  // -1 = intro card, 0..n-1 = round being played, n = result
  const [step, setStep] = useState(-1);
  const [impact, setImpact] = useState<'hero' | 'foe' | null>(null);

  useEffect(() => {
    const timers: number[] = [];
    timers.push(window.setTimeout(() => setStep(0), 1100));
    rounds.forEach((_, i) => {
      timers.push(window.setTimeout(() => { setStep(i); setImpact('foe'); }, 1100 + i * 1200));
      timers.push(window.setTimeout(() => setImpact('hero'), 1100 + i * 1200 + 520));
      timers.push(window.setTimeout(() => setImpact(null), 1100 + i * 1200 + 950));
    });
    timers.push(window.setTimeout(() => setStep(rounds.length), 1100 + rounds.length * 1200));
    return () => timers.forEach(window.clearTimeout);
  }, [rounds]);

  const played = rounds.slice(0, Math.max(0, Math.min(step + 1, rounds.length)));
  const foeDone = played.reduce((s, r) => s + Number(r.playerHit ?? 0), 0);
  const heroDone = played.reduce((s, r) => s + Number(r.enemyHit ?? 0), 0);
  const foeHp = Math.max(0, 100 - (foeDone / totals.foe) * 100);
  const heroHp = Math.max(12, 100 - (heroDone / totals.hero) * 62);
  const finished = step >= rounds.length;
  const defeat = log.result === 'failed';
  const foeDown = finished && !defeat;

  return (
    <div className={`realm-battle bf-stage bf-stage--${theme.key} fixed inset-0 z-[80] flex flex-col`}>
      {/* ── BACKGROUND (sky / mountains) ─────────────────────────────── */}
      <img src={regionImage ?? '/assets/game/realm/world-map.jpg'} alt="" className="bf-bg" />
      <span className="bf-bg-haze" aria-hidden />
      {/* ── MIDGROUND (distant depth + horizon push down) ─────────────── */}
      <span className="bf-mid" aria-hidden />

      {/* HUD (~12%) */}
      <header className="relative z-30 flex items-center justify-between gap-2 px-4 pt-[calc(1rem+env(safe-area-inset-top))]">
        <div className="min-w-0 flex-1">
          <p className="text-[8px] font-black uppercase tracking-[.24em] text-amber-200/80">Sua equipe</p>
          <div className="realm-hpbar mt-1"><span style={{ width: `${heroHp}%` }} className="realm-hpfill realm-hpfill-hero" /></div>
        </div>
        <span className="text-[10px] font-black tracking-[.24em] text-slate-400">VS</span>
        <div className="min-w-0 flex-1 text-right">
          <p className="truncate text-[8px] font-black uppercase tracking-[.24em] text-rose-200/80">{regionName ?? 'Inimigo'}</p>
          <div className="realm-hpbar mt-1"><span style={{ width: `${foeHp}%` }} className="realm-hpfill realm-hpfill-foe" /></div>
        </div>
      </header>

      {/* ── BATTLEFIELD ──────────────────────────────────────────────── */}
      <div className="bf-field relative z-10 flex-1">
        {/* ground plane */}
        <img src={theme.ground} alt="" loading="lazy" className="bf-ground" />
        <span className="bf-ground-blend" aria-hidden />
        {/* local arena light between combatants ("stage") */}
        <span className="bf-arena-light" aria-hidden />

        {/* PLAYER SLOT */}
        <div
          className="bf-slot"
          style={{ left: `${PLAYER_SLOT.x}%`, top: `${PLAYER_SLOT.groundY}%`, ['--slot-scale' as string]: PLAYER_SLOT.scale }}
        >
          <span className="bf-shadow" aria-hidden />
          <span className="bf-ao" aria-hidden />
          <img
            src={HERO_IMG}
            alt="Campeão da sua equipe"
            loading="lazy"
            className={`bf-sprite bf-sprite--hero ${impact === 'foe' ? 'is-attacking' : ''} ${impact === 'hero' ? 'is-hit' : ''}`}
          />
          <span className={`bf-wrap bf-wrap--${theme.key}`} aria-hidden />
          {impact === 'foe' && <span className="bf-dust" aria-hidden />}
        </div>

        {/* ENEMY SLOT */}
        <div
          className={`bf-slot ${foeDown ? 'is-down' : ''}`}
          style={{ left: `${ENEMY_SLOT.x}%`, top: `${ENEMY_SLOT.groundY}%`, ['--slot-scale' as string]: ENEMY_SLOT.scale }}
        >
          <span className="bf-shadow bf-shadow--foe" aria-hidden />
          <span className="bf-ao" aria-hidden />
          <img
            src={theme.foe}
            alt="Inimigo"
            loading="lazy"
            className={`bf-sprite bf-sprite--foe ${impact === 'hero' ? 'is-attacking' : ''} ${impact === 'foe' ? 'is-hit' : ''}`}
          />
          <span className={`bf-wrap bf-wrap--${theme.key}`} aria-hidden />
          {impact === 'hero' && <span className="bf-dust" aria-hidden />}
        </div>

        {impact && <span className="realm-battle-slash" />}

        {/* floating damage */}
        {step >= 0 && !finished && rounds[step] && (
          <div className="pointer-events-none absolute inset-x-0 top-[38%] z-20 flex justify-between px-8">
            <b key={`f${step}`} className="realm-dmg text-[22px] font-black text-emerald-300">−{fmt(Number(rounds[step].playerHit))}</b>
            <b key={`h${step}`} className="realm-dmg realm-dmg-late text-[18px] font-black text-rose-300">−{fmt(Number(rounds[step].enemyHit))}</b>
          </div>
        )}

        {step === -1 && (
          <div className="absolute inset-x-0 top-[18%] z-20 grid place-items-center">
            <p className="realm-battle-encounter text-[15px] font-black uppercase tracking-[.34em] text-rose-200">Inimigo se aproxima</p>
          </div>
        )}

        {/* ── FOREGROUND (grass / crystals / rocks — overlaps feet slightly) ── */}
        <img src={theme.foreground} alt="" loading="lazy" className="bf-fg" />
        <span className="bf-fg-mist" aria-hidden />
      </div>

      {/* RESULT (~20%) */}
      <footer className="relative z-30 px-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        {finished ? (
          <div className="bf-result">
            <p className={`text-[14px] font-black uppercase tracking-[.2em] ${defeat ? 'text-rose-300' : 'text-amber-200'}`}>
              {defeat ? 'Equipe derrotada' : log.result === 'cleared' ? 'Região conquistada' : 'Vitória'}
            </p>
            <div className="mt-2 flex items-center justify-center gap-2">
              <span className="bf-reward">
                <img src="/assets/game/coins/forge-coin.png" alt="" loading="lazy" className="h-3.5 w-3.5 object-contain" />
                <b>+{fmt(Number(log.fc ?? 0))}</b> FC
              </span>
              {Number(log.fragments) > 0 && (
                <span className="bf-reward">
                  <img src="/assets/game/realm/mat-rune-dust.png" alt="" loading="lazy" className="h-3.5 w-3.5 object-contain" />
                  <b>+{fmt(Number(log.fragments))}</b> frag.
                </span>
              )}
              {Number(log.damage) > 0 && (
                <span className="bf-reward bf-reward--dmg">❤ <b>−{log.damage}</b> HP</span>
              )}
            </div>
            <button onClick={onClose} className="bf-continue">Continuar</button>
          </div>
        ) : (
          <p className="text-center text-[10px] font-black uppercase tracking-[.2em] text-slate-400">
            {step < 0 ? 'Combate iniciando...' : `Round ${step + 1} de ${rounds.length}`}
          </p>
        )}
      </footer>
    </div>
  );
}
