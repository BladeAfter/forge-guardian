import React from 'react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import { useT } from './LanguageContext';
import type { HeroXpAward } from './pvp';

/**
 * Hero XP feedback (Lv. 1 → 20). The client never computes XP: it only renders the
 * award the backend already persisted (`hero_xp_events`) and refreshes the collection
 * so ATK/HP/Power reflect the new level immediately.
 */
export function HeroXpToasts() {
  const t = useT();
  const queryClient = useQueryClient();

  React.useEffect(() => {
    const onAward = (event: Event) => {
      const award = (event as CustomEvent<HeroXpAward | null>).detail;
      const heroes = Array.isArray(award?.heroes) ? award!.heroes : [];
      if (!heroes.length) return;

      const xpEach = Math.max(0, Number(award?.xpEach ?? heroes[0]?.xpAwarded ?? 0));
      if (xpEach > 0) toast.success(t('heroXp.gained', { xp: xpEach.toLocaleString() }), { duration: 2000 });
      for (const hero of heroes) {
        if (!hero.leveledUp) continue;
        toast.success(t('heroXp.levelUp', { name: hero.name, level: hero.level }), { duration: 3200 });
      }
      void queryClient.invalidateQueries({ queryKey: ['player-heroes'] });
    };
    window.addEventListener('mythreon:hero-xp', onAward as EventListener);
    return () => window.removeEventListener('mythreon:hero-xp', onAward as EventListener);
  }, [queryClient, t]);

  return null;
}
