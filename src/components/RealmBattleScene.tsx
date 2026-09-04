import { useEffect, useMemo, useState } from 'react';
import type { RealmExploreLog } from '../realm';

const HERO_IMG = '/assets/game/realm/battle-hero.png';

/** Region id → enemy artwork (AI-generated AAA creatures, no icons). */
function foeImage(regionId?: string | null) {
  const id = (regionId ?? '').toLowerCase();
  if (id.includes('crystal') || id.includes('rift')) return '/assets/game/realm/foe-crystal-rift.png';
  if (id.includes('abyss') || id.includes('void')) return '/assets/game/realm/foe-abyss.png';
  return '/assets/game/realm/foe-greenvale.png';
}

const fmt = (n: number) => n.toLocaleString('pt-BR');

type Props = {
  log: RealmExploreLog;
  regionId?: string | null;
  regionName?: string | null;
  regionImage?: string | null;
  onClose: () => void;
};

/**
 * ⚔️ REALM BATTLE SCENE — fullscreen cinematic combat.
 *
 * Pure presentation over the server-resolved combat log: the rounds already decided by the
 * backend are replayed one at a time with real creature art, HP bars, impact flashes and a
 * final victory/defeat banner. No client-side combat math.
 */
export default function RealmBattleScene({ log, regionId, regionName, regionImage, onClose }: Props) {
  const rounds = log.rounds ?? [];
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

  return (
    <div className="realm-battle fixed inset-0 z-[80] flex flex-col">
      <img src={regionImage ?? '/assets/game/realm/world-map.jpg'} alt="" className="absolute inset-0 h-full w-full object-cover opacity-45" />
      <div className="absolute inset-0 bg-gradient-to-b from-[#04060d]/85 via-[#04060d]/55 to-[#04060d]" />

      {/* HUD */}
      <header className="relative z-10 flex items-center justify-between gap-2 px-4 pt-[calc(1rem+env(safe-area-inset-top))]">
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

      {/* ARENA */}
      <div className="relative z-10 flex flex-1 items-end justify-between px-2 pb-2">
        <img
          src={HERO_IMG}
          alt="Campeão da sua equipe"
          loading="lazy"
          className={`realm-fighter realm-fighter-hero ${impact === 'foe' ? 'is-attacking' : ''} ${impact === 'hero' ? 'is-hit' : ''}`}
        />
        <img
          src={foeImage(regionId)}
          alt="Inimigo"
          loading="lazy"
          className={`realm-fighter realm-fighter-foe ${impact === 'hero' ? 'is-attacking' : ''} ${impact === 'foe' ? 'is-hit' : ''}`}
        />

        {impact && <span className="realm-battle-slash" />}

        {step === -1 && (
          <div className="absolute inset-0 grid place-items-center">
            <p className="realm-battle-encounter text-[15px] font-black uppercase tracking-[.34em] text-rose-200">Inimigo se aproxima</p>
          </div>
        )}

        {step >= 0 && !finished && rounds[step] && (
          <div className="pointer-events-none absolute inset-x-0 top-1/3 flex justify-between px-6">
            <b key={`f${step}`} className="realm-dmg text-[22px] font-black text-emerald-300">−{fmt(Number(rounds[step].playerHit))}</b>
            <b key={`h${step}`} className="realm-dmg realm-dmg-late text-[18px] font-black text-rose-300">−{fmt(Number(rounds[step].enemyHit))}</b>
          </div>
        )}
      </div>

      {/* RESULT */}
      <footer className="relative z-10 px-4 pb-[calc(1.25rem+env(safe-area-inset-bottom))]">
        {finished ? (
          <div className="realm-battle-result rounded-3xl border border-white/10 bg-black/60 p-4 text-center backdrop-blur">
            <p className={`text-[15px] font-black uppercase tracking-[.2em] ${defeat ? 'text-rose-300' : 'text-amber-200'}`}>
              {defeat ? 'Equipe derrotada' : log.result === 'cleared' ? 'Região conquistada' : 'Vitória'}
            </p>
            <p className="mt-1 text-[11px] text-emerald-200">
              +{fmt(Number(log.fc ?? 0))} FC
              {Number(log.fragments) ? ` · +${fmt(Number(log.fragments))} frag.` : ''}
              {Number(log.damage) ? ` · −${log.damage} HP` : ''}
            </p>
            <button onClick={onClose} className="mt-3 w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-3 text-[11px] font-black uppercase tracking-[.16em] text-black">
              Continuar
            </button>
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
