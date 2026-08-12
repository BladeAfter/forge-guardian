import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

/**
 * Purely presentational combat FX for the Clan Boss screen.
 * These helpers NEVER compute damage, HP, cooldowns or rewards — they only
 * render events that the backend already confirmed.
 */
export type CombatEventKind = 'PLAYER_ATTACK' | 'BOSS_ATTACK' | 'CRITICAL' | 'HERO_DEFEATED' | 'HERO_REVIVED';

export type CombatEvent = {
  /** Unique id so the same backend event animates exactly once. */
  id: string;
  kind: CombatEventKind;
  /** Real damage value from the backend (already calculated). */
  damage?: number;
  critical?: boolean;
  label?: string;
};

export type CombatPhase = 'idle' | 'player' | 'boss';

/** Sound is intentionally disabled; structure kept for a future audio pass. */
export const COMBAT_SOUND_ENABLED = false;
export function playCombatSound(_kind: CombatEventKind) {
  if (!COMBAT_SOUND_ENABLED) return;
}

export function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
}

/**
 * Queue of visual events. Consumers push only when a NEW backend combat event
 * arrives (never on refetch/realtime reconnect), and each entry self-expires.
 */
export function useCombatFx() {
  const [events, setEvents] = useState<CombatEvent[]>([]);
  const [phase, setPhase] = useState<CombatPhase>('idle');
  const timers = useRef<number[]>([]);

  useEffect(() => () => { timers.current.forEach((id) => window.clearTimeout(id)); }, []);

  const track = (id: number) => { timers.current.push(id); };

  const push = useCallback((event: CombatEvent) => {
    setEvents((list) => (list.some((item) => item.id === event.id) ? list : [...list, event]));
    playCombatSound(event.kind);
    if (event.kind === 'PLAYER_ATTACK' || event.kind === 'CRITICAL') setPhase('player');
    if (event.kind === 'BOSS_ATTACK') setPhase('boss');
    track(window.setTimeout(() => setEvents((list) => list.filter((item) => item.id !== event.id)), 1500));
    track(window.setTimeout(() => setPhase('idle'), 900));
  }, []);

  return { events, phase, push };
}

/** Small floating damage / status numbers stacked over the boss art. */
export function FloatingDamage({ events }: { events: CombatEvent[] }) {
  return (
    <div className="pointer-events-none absolute inset-0 z-20 grid place-items-center">
      {events.map((event, index) => (
        <div key={event.id} className="cb-float" style={{ ['--cb-float-offset' as string]: `${index * 26}px` }}>
          {event.kind === 'HERO_DEFEATED' ? (
            <b className="cb-float-text text-rose-300">{event.label ?? 'HERO DEFEATED'}</b>
          ) : event.kind === 'HERO_REVIVED' ? (
            <b className="cb-float-text text-emerald-300 drop-shadow-[0_0_10px_rgba(52,211,153,.8)]">{event.label ?? 'REVIVED'}</b>
          ) : (
            <div className="text-center">
              {event.critical ? <p className="cb-float-crit">CRIT!</p> : null}
              <b className={event.kind === 'BOSS_ATTACK' ? 'cb-float-boss' : event.critical ? 'cb-float-crit-value' : 'cb-float-player'}>
                -{event.label ?? formatCompact(event.damage ?? 0)}
              </b>
              {event.kind === 'BOSS_ATTACK' ? <p className="cb-float-tag text-rose-200/80">TEAM DAMAGE</p> : null}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

/** Compact turn badge: who acted last, using the confirmed backend event. */
export function TurnIndicator({ phase, idleLabel }: { phase: CombatPhase; idleLabel: string }) {
  const map: Record<CombatPhase, { text: string; className: string }> = {
    idle: { text: idleLabel, className: 'border-white/10 bg-black/60 text-slate-300' },
    player: { text: '⚔ YOUR ATTACK', className: 'border-amber-300/50 bg-amber-400/15 text-amber-200 cb-turn-pop' },
    boss: { text: '☠ BOSS ATTACK', className: 'border-rose-400/50 bg-rose-500/15 text-rose-200 cb-turn-pop' },
  };
  const state = map[phase];
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-3 py-1 text-[8px] font-black tracking-[.22em] ${state.className}`}>
      {state.text}
    </span>
  );
}

/**
 * Thin "next attack" bar driven exclusively by the real cooldown values that
 * already exist in the backend state. No new timers are introduced.
 */
export function NextAttackBar({
  label,
  remainingMs,
  totalSeconds,
  readyLabel,
}: { label: string; remainingMs: number; totalSeconds: number; readyLabel: string }) {
  const total = Math.max(1, totalSeconds) * 1000;
  const remaining = Math.max(0, remainingMs);
  const filled = Math.max(0, Math.min(100, ((total - remaining) / total) * 100));
  return (
    <div className="flex items-center gap-2">
      <span className="w-14 text-[8px] font-black tracking-[.16em] text-slate-400">{label}</span>
      <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-black/70 ring-1 ring-white/10">
        <div className="h-full rounded-full bg-gradient-to-r from-amber-300 to-rose-400 transition-[width] duration-500" style={{ width: `${filled}%` }} />
      </div>
      <span className="w-14 text-right text-[8px] font-black tabular-nums text-slate-300">
        {remaining > 0 ? `${(remaining / 1000).toFixed(1)}s` : readyLabel}
      </span>
    </div>
  );
}

/**
 * Smoothly eases the HP bar width from the previous value to the new one
 * (~450ms) while the numeric readout keeps showing the real backend value.
 */
export function useEasedPercent(target: number) {
  const [value, setValue] = useState(target);
  const frame = useRef(0);
  const reduced = useMemo(prefersReducedMotion, []);

  useEffect(() => {
    if (reduced) { setValue(target); return; }
    const from = value;
    if (Math.abs(from - target) < 0.01) return;
    const start = performance.now();
    const duration = 450;
    const step = (time: number) => {
      const t = Math.min(1, (time - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      setValue(from + (target - from) * eased);
      if (t < 1) frame.current = requestAnimationFrame(step);
    };
    frame.current = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target, reduced]);

  return reduced ? target : value;
}

function formatCompact(value: number): string {
  const n = Math.max(0, Math.round(value));
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace(/\.0$/, '')}K`;
  return String(n);
}
