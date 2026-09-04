import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronsRight, Flame, Swords, Zap } from 'lucide-react';
import { useT } from '../LanguageContext';
import type { Translator } from '../i18n';
import type { RealmExploreLog, RealmExploreNodeType } from '../realm';

type Theme = {
  key: 'greenvale' | 'crystal' | 'abyss';
  foe: string;
  ground: string;
  bossNameKey: string;
};

/** Region id → battlefield theme (background art, enemy). */
function themeOf(regionId?: string | null): Theme {
  const id = (regionId ?? '').toLowerCase();
  if (id.includes('crystal') || id.includes('rift')) {
    return {
      key: 'crystal',
      foe: '/assets/game/realm/foe-crystal-rift.png',
      ground: '/assets/game/realm/battle-ground-crystal-rift.jpg',
      bossNameKey: 'realm.foe.crystal',
    };
  }
  if (id.includes('abyss') || id.includes('void')) {
    return {
      key: 'abyss',
      foe: '/assets/game/realm/foe-abyss.png',
      ground: '/assets/game/realm/battle-ground-abyss.jpg',
      bossNameKey: 'realm.foe.abyss',
    };
  }
  return {
    key: 'greenvale',
    foe: '/assets/game/realm/foe-greenvale.png',
    ground: '/assets/game/realm/battle-ground-greenvale.jpg',
    bossNameKey: 'realm.foe.wild',
  };
}

/** Node type → boss art / rank shown above the enemy. */
function foeOf(nodeType: RealmExploreNodeType | undefined, theme: Theme, t: Translator) {
  const base = t(theme.bossNameKey);
  if (nodeType === 'boss') {
    return { art: '/assets/game/realm/poi-boss.png', rank: t('realm.battle.rank.boss'), name: t('realm.foe.ancestral', { name: base }) };
  }
  if (nodeType === 'elite') {
    return { art: '/assets/game/realm/poi-elite.png', rank: t('realm.battle.rank.elite'), name: t('realm.foe.eliteSuffix', { name: base }) };
  }
  return { art: theme.foe, rank: t('realm.battle.rank.foe'), name: base };
}

/** The three heroes shown in the party row (presentation only). */
const PARTY = [
  { name: 'Aldric', image: '/assets/game/realm/party-knight.png', glow: 'rgba(251,191,36,.55)' },
  { name: 'Sylvane', image: '/assets/game/realm/party-mage.png', glow: 'rgba(168,85,247,.55)' },
  { name: 'Kaelis', image: '/assets/game/realm/party-ranger.png', glow: 'rgba(52,211,153,.55)' },
];

const fmt = (n: number) => Math.max(0, Math.round(n)).toLocaleString('pt-BR');
const wait = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));

type Ability = { nameKey: string; blurbKey: string; icon: typeof Swords; tone: string; ring: string };

const ABILITIES: Ability[] = [
  { nameKey: 'realm.battle.skill.strike', blurbKey: 'realm.battle.skill.strikeDesc', icon: Swords, tone: 'text-amber-200', ring: 'border-amber-300/50 bg-amber-400/10' },
  { nameKey: 'realm.battle.skill.charge', blurbKey: 'realm.battle.skill.chargeDesc', icon: Flame, tone: 'text-rose-200', ring: 'border-rose-300/50 bg-rose-400/10' },
  { nameKey: 'realm.battle.skill.fury', blurbKey: 'realm.battle.skill.furyDesc', icon: Zap, tone: 'text-sky-200', ring: 'border-sky-300/50 bg-sky-400/10' },
];

type Props = {
  log: RealmExploreLog;
  regionId?: string | null;
  regionName?: string | null;
  regionImage?: string | null;
  onClose: () => void;
};

/**
 * ⚔️ REALM BATTLE SCENE — Familiar Hunt style: the boss on top, the 3-hero party below,
 * and the active hero's abilities in the footer. Presentation only: it replays the rounds
 * the backend already resolved (no combat math, no rewards invented here).
 */
export default function RealmBattleScene({ log, regionId, regionName, regionImage, onClose }: Props) {
  const rounds = useMemo(() => log.rounds ?? [], [log.rounds]);
  const t = useT();
  const theme = useMemo(() => themeOf(regionId), [regionId]);
  const foe = useMemo(() => foeOf(log.nodeType, theme, t), [log.nodeType, theme, t]);
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
  const partyMax = useMemo(() => {
    const total = defeat ? heroDealt : Math.round(heroDealt / 0.62);
    return PARTY.map(() => Math.max(1, Math.round(total / PARTY.length)));
  }, [defeat, heroDealt]);

  const [bossHp, setBossHp] = useState(bossMax);
  const [partyHp, setPartyHp] = useState<number[]>(() => partyMax.slice());
  const [turn, setTurn] = useState(0);
  const [slot, setSlot] = useState(0);
  const [phase, setPhase] = useState<'hero' | 'foe' | 'done'>('hero');
  const [busy, setBusy] = useState(false);
  const [auto, setAuto] = useState(false);
  const [speed, setSpeed] = useState<1 | 2>(1);
  const [hit, setHit] = useState<string | null>(null);
  const [banner, setBanner] = useState<string | null>(t('realm.battle.foeApproaches'));
  const [floats, setFloats] = useState<{ id: number; unit: string; text: string; tone: 'foe' | 'hero' }[]>([]);
  const floatId = useRef(0);
  const finished = useRef(false);
  const step = 560 / speed;

  useEffect(() => {
    const id = window.setTimeout(() => setBanner(null), 1200);
    return () => window.clearTimeout(id);
  }, []);

  const pushFloat = useCallback((unit: string, text: string, tone: 'foe' | 'hero') => {
    const id = (floatId.current += 1);
    setFloats((rows) => [...rows, { id, unit, text, tone }]);
    window.setTimeout(() => setFloats((rows) => rows.filter((r) => r.id !== id)), 900);
  }, []);

  const flash = useCallback((unit: string) => {
    setHit(unit);
    window.setTimeout(() => setHit(null), 240);
  }, []);

  const finish = useCallback(() => {
    if (finished.current) return;
    finished.current = true;
    setPhase('done');
    setBossHp(defeat ? Math.max(1, Math.round(bossMax * 0.18)) : 0);
    setPartyHp(defeat ? partyMax.map(() => 0) : partyMax.map((max) => Math.max(1, Math.round(max * 0.38))));
    setBanner(defeat ? t('realm.battle.partyDefeatedCaps') : t('realm.battle.foeDefeatedCaps'));
    window.setTimeout(() => setBanner(null), 1400);
  }, [bossMax, defeat, partyMax, t]);

  /** Plays one authoritative round: the active hero strikes, then the boss answers. */
  const playTurn = useCallback(async () => {
    if (busy || phase === 'done') return;
    const round = rounds[turn];
    if (!round) { finish(); return; }
    setBusy(true);

    const attacker = slot;
    const foeDmg = Number(round.playerHit ?? 0);
    flash('foe');
    await wait(step * 0.45);
    setBossHp((hp) => Math.max(0, hp - foeDmg));
    pushFloat('foe', `-${fmt(foeDmg)}`, 'foe');
    await wait(step * 0.8);

    const heroDmg = Number(round.enemyHit ?? 0);
    if (heroDmg > 0) {
      setPhase('foe');
      setBanner(t('realm.battle.foeTurn'));
      const target = `p${attacker}`;
      flash(target);
      await wait(step * 0.45);
      setPartyHp((rows) => {
        const next = rows.slice();
        next[attacker] = Math.max(defeat ? 0 : 1, (next[attacker] ?? 0) - heroDmg);
        return next;
      });
      pushFloat(target, `-${fmt(heroDmg)}`, 'hero');
      await wait(step * 0.7);
      setBanner(null);
    }

    const next = turn + 1;
    setTurn(next);
    setSlot((next) % PARTY.length);
    setBusy(false);
    if (next >= rounds.length) finish();
    else setPhase('hero');
  }, [busy, defeat, finish, flash, phase, pushFloat, rounds, slot, step, t, turn]);

  useEffect(() => {
    if (!auto || busy || phase === 'done') return;
    const id = window.setTimeout(() => { void playTurn(); }, step * 0.5);
    return () => window.clearTimeout(id);
  }, [auto, busy, phase, playTurn, step]);

  const bossPct = Math.max(0, (bossHp / bossMax) * 100);
  const done = phase === 'done';
  const activeHero = PARTY[slot];
  const unitFloats = (unit: string) => floats.filter((f) => f.unit === unit);

  return (
    <div className="fixed inset-0 z-[80] flex flex-col overflow-hidden bg-[#05060c]">
      <img src={regionImage ?? theme.ground} alt="" loading="lazy" className="absolute inset-0 h-full w-full object-cover opacity-45" />
      <span className="pointer-events-none absolute inset-0 bg-[radial-gradient(120%_70%_at_50%_18%,rgba(6,10,22,.15),rgba(3,4,10,.92))]" aria-hidden />

      {/* ── HEADER ─────────────────────────────────────────────── */}
      <header className="relative z-30 flex items-center justify-between gap-2 px-4 pt-[calc(0.85rem+env(safe-area-inset-top))]">
        <div className="min-w-0">
          <p className="truncate text-[9px] font-black uppercase tracking-[.22em] text-amber-200">
            {regionName ?? t('realm.battle.region')} · {foe.rank}
          </p>
          <p className="text-[8px] font-bold uppercase tracking-[.2em] text-slate-500">
            {t('realm.battle.heroTurn', { turn: Math.min(turn + 1, Math.max(1, rounds.length)), total: Math.max(1, rounds.length) })}
          </p>
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
      </header>

      {/* ── STAGE: boss on top, party below ──────────────────────── */}
      <div className="relative z-10 flex min-h-0 flex-1 flex-col justify-between gap-1 py-2">
        <section className="relative flex-none px-6">
          <div className={`relative mx-auto w-2/3 max-w-[240px] transition-all duration-200 ${done && !defeat ? 'translate-y-2 opacity-20 grayscale' : ''} ${hit === 'foe' ? 'translate-y-1.5 scale-[.97]' : ''}`}>
            {unitFloats('foe').map((f) => <FloatText key={f.id} text={f.text} tone={f.tone} />)}
            <img
              src={foe.art} alt={foe.name} loading="lazy"
              className="mx-auto h-[22vh] max-h-56 min-h-24 object-contain drop-shadow-[0_0_34px_rgba(244,63,94,.5)]"
            />
            <p className="truncate text-center text-[10px] font-black uppercase tracking-[.14em] text-rose-200">{foe.name}</p>
            <Bar value={bossHp} max={bossMax} tone="rose" />
            <p className="text-center text-[8px] font-bold tracking-wider text-slate-400">{fmt(bossHp)} / {fmt(bossMax)} · {Math.round(bossPct)}%</p>
          </div>
        </section>

        <div className="flex h-7 flex-none items-center justify-center px-6">
          {banner ? (
            <p className="animate-[scale-in_.2s_ease-out] rounded-full border border-amber-300/40 bg-black/70 px-4 py-1.5 text-center text-[9px] font-black uppercase tracking-[.2em] text-amber-100 shadow-[0_0_24px_-8px_rgba(251,191,36,.8)]">
              {banner}
            </p>
          ) : null}
        </div>

        <div className="mx-auto h-px w-2/3 flex-none bg-gradient-to-r from-transparent via-amber-300/45 to-transparent shadow-[0_0_18px_rgba(251,191,36,.6)]" />

        <section className="relative flex-none px-4">
          <div className="flex items-end justify-center gap-2.5">
            {PARTY.map((hero, index) => {
              const unit = `p${index}`;
              const hp = partyHp[index] ?? 0;
              const dead = hp <= 0;
              const active = phase === 'hero' && index === slot && !done;
              return (
                <div
                  key={unit}
                  className={`relative flex-1 rounded-2xl border px-1 pb-1.5 pt-2 transition-all duration-200 ${
                    dead ? 'border-white/5 opacity-25 grayscale'
                      : active ? '-translate-y-1 border-amber-300/60 bg-black/55 shadow-[0_0_28px_-8px_rgba(251,191,36,.9)]'
                      : 'border-white/10 bg-black/35'
                  } ${hit === unit ? 'translate-y-1 scale-[.97]' : ''}`}
                >
                  {unitFloats(unit).map((f) => <FloatText key={f.id} text={f.text} tone={f.tone} />)}
                  {active ? <span className="pointer-events-none absolute inset-x-3 bottom-10 top-3 -z-0 rounded-full bg-amber-300/20 blur-2xl" aria-hidden /> : null}
                  <img
                    src={hero.image} alt={hero.name} loading="lazy"
                    className="relative mx-auto h-[13vh] max-h-28 min-h-14 object-contain"
                    style={{ filter: `drop-shadow(0 0 18px ${hero.glow})` }}
                  />
                  <p className="relative truncate text-center text-[8px] font-black uppercase tracking-[.08em] text-slate-100">{hero.name}</p>
                  <Bar value={hp} max={partyMax[index] ?? 1} tone="emerald" />
                  {dead ? <p className="text-center text-[8px] font-black uppercase tracking-[.2em] text-rose-400">KO</p> : null}
                </div>
              );
            })}
          </div>
        </section>
      </div>

      {/* ── FOOTER: active hero abilities / result ───────────────── */}
      <footer className="relative z-30 flex-none border-t border-white/10 bg-black/70 px-3 pb-[calc(0.85rem+env(safe-area-inset-bottom))] pt-2 backdrop-blur-sm">
        {done ? (
          <div className="bf-result">
            <p className={`text-[13px] font-black uppercase tracking-[.2em] ${defeat ? 'text-rose-300' : 'text-amber-200'}`}>
              {defeat ? t('realm.battle.partyDefeated') : log.result === 'cleared' ? t('realm.battle.regionCleared') : t('realm.battle.victory')}
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
            <button onClick={onClose} className="bf-continue">{t('realm.continue')}</button>
          </div>
        ) : (
          <>
            <p className="mb-1.5 text-center text-[8px] font-black uppercase tracking-[.24em] text-slate-500">
              {t('realm.battle.abilitiesOf')} <span className="text-amber-200">{activeHero.name}</span>
            </p>
            <div className="grid grid-cols-3 gap-2">
              {ABILITIES.map((ability) => {
                const Icon = ability.icon;
                return (
                  <button
                    key={ability.nameKey}
                    type="button"
                    disabled={busy || auto}
                    onClick={() => void playTurn()}
                    className={`relative overflow-hidden rounded-2xl border px-2 pb-2 pt-2.5 text-center transition active:scale-95 disabled:opacity-40 ${ability.ring}`}
                  >
                    <Icon className={`mx-auto h-5 w-5 ${ability.tone}`} />
                    <span className={`mt-1 block text-[8.5px] font-black uppercase leading-tight tracking-[.04em] ${ability.tone}`}>{t(ability.nameKey)}</span>
                    <span className="mt-0.5 block text-[7px] font-bold uppercase tracking-[.1em] text-white/45">{t(ability.blurbKey)}</span>
                  </button>
                );
              })}
            </div>
          </>
        )}
      </footer>
    </div>
  );
}

function FloatText({ text, tone }: { text: string; tone: 'foe' | 'hero' }) {
  return (
    <span className={`pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 animate-[fade-out_.9s_ease-out_forwards] font-black drop-shadow-[0_2px_6px_rgba(0,0,0,.95)] ${tone === 'foe' ? 'text-[18px] text-amber-300' : 'text-[15px] text-rose-300'}`}>
      {text}
    </span>
  );
}

function Bar({ value, max, tone }: { value: number; max: number; tone: 'rose' | 'emerald' }) {
  const pct = Math.max(0, Math.min(100, (value / Math.max(1, max)) * 100));
  return (
    <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full border border-black/70 bg-black/70">
      <div
        className={`h-full rounded-full transition-[width] duration-300 ${tone === 'rose' ? 'bg-gradient-to-r from-rose-500 to-rose-300 shadow-[0_0_10px_rgba(244,63,94,.7)]' : 'bg-gradient-to-r from-emerald-500 to-emerald-300 shadow-[0_0_10px_rgba(52,211,153,.7)]'}`}
        style={{ width: `${pct}%` }}
      />
    </div>
  );
}
