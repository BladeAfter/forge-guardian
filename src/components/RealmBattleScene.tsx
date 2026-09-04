import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronsRight, Flame, Swords, Zap } from 'lucide-react';
import type { RealmExploreLog, RealmExploreNodeType } from '../realm';

const HERO_IMG = '/assets/game/realm/battle-hero.png';

type Theme = {
  key: 'greenvale' | 'crystal' | 'abyss';
  foe: string;
  ground: string;
  foreground: string;
  bossName: string;
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
      bossName: 'Guardião de Cristal',
    };
  }
  if (id.includes('abyss') || id.includes('void')) {
    return {
      key: 'abyss',
      foe: '/assets/game/realm/foe-abyss.png',
      ground: '/assets/game/realm/battle-ground-abyss.jpg',
      foreground: '/assets/game/realm/battle-fg-abyss.png',
      bossName: 'Devorador do Abismo',
    };
  }
  return {
    key: 'greenvale',
    foe: '/assets/game/realm/foe-greenvale.png',
    ground: '/assets/game/realm/battle-ground-greenvale.jpg',
    foreground: '/assets/game/realm/battle-fg-greenvale.png',
    bossName: 'Bruto da Mata',
  };
}

/** Node type → boss art / rank shown above the enemy. */
function foeOf(nodeType: RealmExploreNodeType | undefined, theme: Theme) {
  if (nodeType === 'boss') {
    return { art: '/assets/game/realm/poi-boss.png', rank: 'CHEFE', name: `${theme.bossName} Ancestral`, scale: 1.18 };
  }
  if (nodeType === 'elite') {
    return { art: '/assets/game/realm/poi-elite.png', rank: 'ELITE', name: `${theme.bossName} Élite`, scale: 1.06 };
  }
  return { art: theme.foe, rank: 'INIMIGO', name: theme.bossName, scale: 0.96 };
}

/**
 * Fixed combat slots. `x` is the horizontal center, `groundY` is the ground line the
 * sprite's feet are anchored to (percent from the top of the battlefield stage), and
 * `scale` handles the small perspective difference between near/far combatants.
 */
const PLAYER_SLOT = { x: 29, groundY: 82, scale: 1.0 };
const ENEMY_SLOT = { x: 71, groundY: 76, scale: 0.94 };

const fmt = (n: number) => Math.max(0, Math.round(n)).toLocaleString('pt-BR');
const wait = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));

type Ability = { name: string; blurb: string; icon: typeof Swords; tone: string; ring: string };

const ABILITIES: Ability[] = [
  { name: 'Golpe', blurb: 'Ataque básico', icon: Swords, tone: 'text-amber-200', ring: 'border-amber-300/50 bg-amber-400/10' },
  { name: 'Investida', blurb: 'Avanço brutal', icon: Flame, tone: 'text-rose-200', ring: 'border-rose-300/50 bg-rose-400/10' },
  { name: 'Fúria', blurb: 'Corte veloz', icon: Zap, tone: 'text-sky-200', ring: 'border-sky-300/50 bg-sky-400/10' },
];

type Props = {
  log: RealmExploreLog;
  regionId?: string | null;
  regionName?: string | null;
  regionImage?: string | null;
  onClose: () => void;
};

/**
 * ⚔️ REALM BATTLE SCENE — fullscreen boss encounter (Familiar Hunt style) with the hero.
 *
 * Presentation only: replays the rounds the backend already resolved, but as a real
 * turn-based duel — named boss with HP bar and numbers, hero with HP bar, ability buttons,
 * floating damage, auto / x2 / skip. No combat math, no rewards invented here.
 */
export default function RealmBattleScene({ log, regionId, regionName, regionImage, onClose }: Props) {
  const rounds = useMemo(() => log.rounds ?? [], [log.rounds]);
  const theme = useMemo(() => themeOf(regionId), [regionId]);
  const foe = useMemo(() => foeOf(log.nodeType, theme), [log.nodeType, theme]);
  const defeat = log.result === 'failed';

  /** Synthetic HP pools derived from the authoritative damage log. */
  const bossMax = useMemo(
    () => Math.max(1, rounds.reduce((s, r) => s + Number(r.playerHit ?? 0), 0)),
    [rounds],
  );
  const heroDealt = useMemo(
    () => Math.max(1, rounds.reduce((s, r) => s + Number(r.enemyHit ?? 0), 0)),
    [rounds],
  );
  const heroMax = defeat ? heroDealt : Math.round(heroDealt / 0.62);

  const [bossHp, setBossHp] = useState(bossMax);
  const [heroHp, setHeroHp] = useState(heroMax);
  const [turn, setTurn] = useState(0);
  const [phase, setPhase] = useState<'hero' | 'foe' | 'done'>('hero');
  const [busy, setBusy] = useState(false);
  const [auto, setAuto] = useState(false);
  const [speed, setSpeed] = useState<1 | 2>(1);
  const [impact, setImpact] = useState<'hero' | 'foe' | null>(null);
  const [banner, setBanner] = useState<string | null>('O INIMIGO SE APROXIMA');
  const [floats, setFloats] = useState<{ id: number; unit: 'hero' | 'foe'; text: string }[]>([]);
  const floatId = useRef(0);
  const finished = useRef(false);
  const step = 560 / speed;

  useEffect(() => {
    const t = window.setTimeout(() => setBanner(null), 1200);
    return () => window.clearTimeout(t);
  }, []);

  const pushFloat = useCallback((unit: 'hero' | 'foe', text: string) => {
    const id = (floatId.current += 1);
    setFloats((rows) => [...rows, { id, unit, text }]);
    window.setTimeout(() => setFloats((rows) => rows.filter((r) => r.id !== id)), 900);
  }, []);

  const finish = useCallback(() => {
    if (finished.current) return;
    finished.current = true;
    setPhase('done');
    setBossHp(defeat ? Math.max(1, Math.round(bossMax * 0.18)) : 0);
    setHeroHp(defeat ? 0 : Math.max(1, heroMax - heroDealt));
    setBanner(defeat ? 'EQUIPE DERROTADA' : 'INIMIGO DERROTADO');
    window.setTimeout(() => setBanner(null), 1400);
  }, [bossMax, defeat, heroDealt, heroMax]);

  /** Plays one authoritative round: hero strikes, then the foe answers. */
  const playTurn = useCallback(async () => {
    if (busy || phase === 'done') return;
    const round = rounds[turn];
    if (!round) { finish(); return; }
    setBusy(true);

    setImpact('foe');
    await wait(step * 0.45);
    const foeDmg = Number(round.playerHit ?? 0);
    setBossHp((hp) => Math.max(0, hp - foeDmg));
    pushFloat('foe', `-${fmt(foeDmg)}`);
    await wait(step * 0.8);
    setImpact(null);

    const heroDmg = Number(round.enemyHit ?? 0);
    if (heroDmg > 0) {
      setPhase('foe');
      setImpact('hero');
      await wait(step * 0.45);
      setHeroHp((hp) => Math.max(defeat ? 0 : 1, hp - heroDmg));
      pushFloat('hero', `-${fmt(heroDmg)}`);
      await wait(step * 0.7);
      setImpact(null);
    }

    const next = turn + 1;
    setTurn(next);
    setBusy(false);
    if (next >= rounds.length) finish();
    else setPhase('hero');
  }, [busy, defeat, finish, phase, pushFloat, rounds, step, turn]);

  useEffect(() => {
    if (!auto || busy || phase === 'done') return;
    const t = window.setTimeout(() => { void playTurn(); }, step * 0.5);
    return () => window.clearTimeout(t);
  }, [auto, busy, phase, playTurn, step]);

  const bossPct = Math.max(0, (bossHp / bossMax) * 100);
  const heroPct = Math.max(0, (heroHp / heroMax) * 100);
  const done = phase === 'done';

  const unitFloats = (unit: 'hero' | 'foe') => floats.filter((f) => f.unit === unit);

  return (
    <div className={`realm-battle bf-stage bf-stage--${theme.key} fixed inset-0 z-[80] flex flex-col`}>
      <img src={regionImage ?? '/assets/game/realm/world-map.jpg'} alt="" className="bf-bg" />
      <span className="bf-bg-haze" aria-hidden />
      <span className="bf-mid" aria-hidden />

      {/* ── BOSS HEADER ─────────────────────────────────────────────── */}
      <header className="relative z-30 px-4 pt-[calc(0.85rem+env(safe-area-inset-top))]">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 flex-1">
            <p className="text-[8px] font-black uppercase tracking-[.24em] text-rose-300/90">
              {foe.rank} · {regionName ?? 'Região'}
            </p>
            <b className="block truncate text-[13px] font-black uppercase tracking-[.12em] text-rose-100">{foe.name}</b>
            <div className="realm-hpbar mt-1"><span style={{ width: `${bossPct}%` }} className="realm-hpfill realm-hpfill-foe" /></div>
            <p className="mt-0.5 text-[8px] font-bold tracking-wider text-slate-400">{fmt(bossHp)} / {fmt(bossMax)} HP</p>
          </div>
          <div className="flex shrink-0 items-center gap-1.5">
            <button
              type="button" onClick={() => setAuto((v) => !v)}
              className={`rounded-full border px-2.5 py-1 text-[8px] font-black uppercase tracking-[.14em] transition active:scale-95 ${auto ? 'border-emerald-300/60 bg-emerald-300/15 text-emerald-200' : 'border-white/15 bg-black/50 text-slate-400'}`}
            >AUTO</button>
            <button
              type="button" onClick={() => setSpeed((v) => (v === 1 ? 2 : 1))}
              className="rounded-full border border-sky-300/40 bg-black/50 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.14em] text-sky-200 transition active:scale-95"
            >x{speed}</button>
            <button
              type="button" onClick={finish}
              className="flex items-center gap-1 rounded-full border border-amber-300/45 bg-black/50 px-2 py-1 text-[8px] font-black uppercase tracking-[.14em] text-amber-200 transition active:scale-95"
            ><ChevronsRight className="h-3 w-3" /> SKIP</button>
          </div>
        </div>
      </header>

      {/* ── BATTLEFIELD ──────────────────────────────────────────────── */}
      <div className="bf-field relative z-10 flex-1">
        <img src={theme.ground} alt="" loading="lazy" className="bf-ground" />
        <span className="bf-ground-blend" aria-hidden />
        <span className="bf-arena-light" aria-hidden />

        {/* HERO */}
        <div
          className="bf-slot"
          style={{ left: `${PLAYER_SLOT.x}%`, top: `${PLAYER_SLOT.groundY}%`, ['--slot-scale' as string]: PLAYER_SLOT.scale }}
        >
          <span className="bf-shadow" aria-hidden />
          <span className="bf-ao" aria-hidden />
          <img
            src={HERO_IMG} alt="Seu herói" loading="lazy"
            className={`bf-sprite bf-sprite--hero ${impact === 'foe' ? 'is-attacking' : ''} ${impact === 'hero' ? 'is-hit' : ''} ${done && defeat ? 'opacity-30 grayscale' : ''}`}
          />
          <span className={`bf-wrap bf-wrap--${theme.key}`} aria-hidden />
          {impact === 'foe' && <span className="bf-dust" aria-hidden />}
          {unitFloats('hero').map((f) => (
            <b key={f.id} className="realm-dmg absolute -top-6 left-1/2 -translate-x-1/2 text-[18px] font-black text-rose-300">{f.text}</b>
          ))}
        </div>

        {/* BOSS */}
        <div
          className={`bf-slot ${done && !defeat ? 'is-down' : ''}`}
          style={{ left: `${ENEMY_SLOT.x}%`, top: `${ENEMY_SLOT.groundY}%`, ['--slot-scale' as string]: ENEMY_SLOT.scale * foe.scale }}
        >
          <span className="bf-shadow bf-shadow--foe" aria-hidden />
          <span className="bf-ao" aria-hidden />
          <img
            src={foe.art} alt={foe.name} loading="lazy"
            className={`bf-sprite bf-sprite--foe ${impact === 'hero' ? 'is-attacking' : ''} ${impact === 'foe' ? 'is-hit' : ''}`}
          />
          <span className={`bf-wrap bf-wrap--${theme.key}`} aria-hidden />
          {impact === 'hero' && <span className="bf-dust" aria-hidden />}
          {unitFloats('foe').map((f) => (
            <b key={f.id} className="realm-dmg absolute -top-6 left-1/2 -translate-x-1/2 text-[20px] font-black text-emerald-300">{f.text}</b>
          ))}
        </div>

        {impact && <span className="realm-battle-slash" />}

        {banner && (
          <div className="pointer-events-none absolute inset-x-0 top-[10%] z-20 grid place-items-center px-6">
            <p className="rounded-full border border-amber-300/40 bg-black/70 px-4 py-1.5 text-center text-[10px] font-black uppercase tracking-[.22em] text-amber-100">
              {banner}
            </p>
          </div>
        )}

        <img src={theme.foreground} alt="" loading="lazy" className="bf-fg" />
        <span className="bf-fg-mist" aria-hidden />
      </div>

      {/* ── HERO BAR + ABILITIES / RESULT ────────────────────────────── */}
      <footer className="relative z-30 border-t border-white/10 bg-black/70 px-3 pb-[calc(0.85rem+env(safe-area-inset-bottom))] pt-2 backdrop-blur-sm">
        <div className="mb-2 flex items-center gap-2">
          <img src={HERO_IMG} alt="" aria-hidden className="h-8 w-8 rounded-full border border-amber-300/40 object-cover object-top" />
          <div className="min-w-0 flex-1">
            <p className="text-[8px] font-black uppercase tracking-[.2em] text-amber-200/85">Seu herói · Turno {Math.min(turn + 1, Math.max(1, rounds.length))}/{Math.max(1, rounds.length)}</p>
            <div className="realm-hpbar mt-1"><span style={{ width: `${heroPct}%` }} className="realm-hpfill realm-hpfill-hero" /></div>
          </div>
          <span className="shrink-0 text-[8px] font-bold tracking-wider text-slate-400">{fmt(heroHp)} / {fmt(heroMax)}</span>
        </div>

        {done ? (
          <div className="bf-result">
            <p className={`text-[13px] font-black uppercase tracking-[.2em] ${defeat ? 'text-rose-300' : 'text-amber-200'}`}>
              {defeat ? 'Equipe derrotada' : log.result === 'cleared' ? 'Região conquistada' : 'Vitória'}
            </p>
            <div className="mt-2 flex flex-wrap items-center justify-center gap-2">
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
              {Number(log.damage) > 0 && <span className="bf-reward bf-reward--dmg">❤ <b>−{log.damage}</b> HP</span>}
            </div>
            <button onClick={onClose} className="bf-continue">Continuar</button>
          </div>
        ) : (
          <div className="grid grid-cols-3 gap-2">
            {ABILITIES.map((ability) => {
              const Icon = ability.icon;
              return (
                <button
                  key={ability.name}
                  type="button"
                  disabled={busy || auto}
                  onClick={() => void playTurn()}
                  className={`relative overflow-hidden rounded-2xl border px-2 pb-2 pt-2.5 text-center transition active:scale-95 disabled:opacity-40 ${ability.ring}`}
                >
                  <Icon className={`mx-auto h-5 w-5 ${ability.tone}`} />
                  <span className={`mt-1 block text-[9px] font-black uppercase tracking-[.06em] ${ability.tone}`}>{ability.name}</span>
                  <span className="mt-0.5 block text-[7px] font-bold uppercase tracking-[.1em] text-white/45">{ability.blurb}</span>
                </button>
              );
            })}
          </div>
        )}
      </footer>
    </div>
  );
}
