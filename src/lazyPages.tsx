import { lazy, Suspense, type ComponentType } from 'react';

/**
 * Code-splitting for the secondary screens.
 *
 * The whole app used to ship in a single ~2.1 MB JS chunk, so the Telegram Mini App
 * had to download and parse every screen (PvP, Pets, Clan, Pool, Season Pass...)
 * before the village could render. These routes are now lazy chunks fetched on demand.
 */
const PageFallback = () => (
  <div className="forge-safe-page flex min-h-screen items-center justify-center bg-background">
    <div className="flex flex-col items-center gap-3">
      <div className="h-10 w-10 animate-spin rounded-full border-2 border-primary/30 border-t-primary" />
      <p className="text-xs uppercase tracking-[0.3em] text-muted-foreground">Carregando...</p>
    </div>
  </div>
);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function lazyPage<T extends ComponentType<any>>(factory: () => Promise<{ default: T }>): T {
  const Loaded = lazy(factory);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const Wrapped = (props: any) => (
    <Suspense fallback={<PageFallback />}>
      <Loaded {...props} />
    </Suspense>
  );
  return Wrapped as unknown as T;
}

export const ReferralPage = lazyPage(() =>
  import('./pages/ReferralPage').then((m) => ({ default: m.ReferralPage })),
);
export const PetsPage = lazyPage(() =>
  import('./pages/PetsPage').then((m) => ({ default: m.PetsPage })),
);
export const PvpPage = lazyPage(() =>
  import('./pages/PvpPage').then((m) => ({ default: m.PvpPage })),
);
export const SeasonPassPage = lazyPage(() =>
  import('./pages/SeasonPassPage').then((m) => ({ default: m.SeasonPassPage })),
);
export const HeroesPage = lazyPage(() =>
  import('./pages/HeroesPage').then((m) => ({ default: m.HeroesPage })),
);
export const ClanHubPage = lazyPage(() =>
  import('./pages/ClanHubPage').then((m) => ({ default: m.ClanHubPage })),
);
export const CommunityPoolPage = lazyPage(() =>
  import('./pages/CommunityPoolPage').then((m) => ({ default: m.CommunityPoolPage })),
);
export const DiagnosticsPage = lazyPage(() =>
  import('./pages/DiagnosticsPage').then((m) => ({ default: m.DiagnosticsPage })),
);
