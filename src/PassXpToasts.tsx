import React from 'react';
import { toast } from 'sonner';
import { fetchRecentPassXp } from './services';
import { useT } from './LanguageContext';

/**
 * Small, backend-driven Battle Pass XP feedback.
 * The client NEVER computes multipliers or final XP: it only renders what the
 * ledger already recorded (source, base xp, multiplier, final xp).
 */
export function PassXpToasts({ telegramInitData }: { telegramInitData: string | null }) {
  const t = useT();
  const since = React.useRef<string>(new Date().toISOString());
  const seen = React.useRef<Set<string>>(new Set());

  React.useEffect(() => {
    if (!telegramInitData) return;
    let alive = true;
    const tick = async () => {
      try {
        const gains = await fetchRecentPassXp(telegramInitData, since.current);
        if (!alive || !Array.isArray(gains)) return;
        for (const gain of gains) {
          if (!gain?.id || seen.current.has(gain.id)) continue;
          seen.current.add(gain.id);
          if (gain.createdAt > since.current) since.current = gain.createdAt;
          const bonus = Math.round((Number(gain.multiplier || 1) - 1) * 100);
          toast.success(t('pass.xpGain', { xp: gain.xp }), {
            description: bonus > 0 ? t('pass.xpGainBonus', { percent: bonus }) : undefined,
            duration: 2200,
          });
        }
        if (seen.current.size > 200) seen.current = new Set();
      } catch {
        /* silent: XP feedback must never interrupt gameplay */
      }
    };
    const id = window.setInterval(tick, 45_000);
    return () => { alive = false; window.clearInterval(id); };
  }, [telegramInitData, t]);

  return null;
}
