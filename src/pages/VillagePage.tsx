import type { GameState, LanguageStrings } from '../types';
import { Sparkles } from 'lucide-react';
import { formatCurrency } from '../utils';
import { buildings, characters } from '../gameAssets';

type VillagePageProps = {
  game: GameState;
  onUpgrade: (id: string) => void;
  lang: LanguageStrings;
};

export function VillagePage({ game, onUpgrade, lang }: VillagePageProps) {
  return (
    <section className="space-y-4">
      <div className="rounded-3xl border border-white/10 bg-forge-black/80 p-4 shadow-card">
        <div className="relative mb-4 flex min-h-24 items-center justify-between overflow-hidden">
          <div>
            <p className="text-xs uppercase tracking-[0.3em] text-slate-400">{lang.buildings}</p>
            <h3 className="mt-1 text-lg font-semibold">{lang.villageBuildings}</h3>
          </div>
          <Sparkles className="h-5 w-5 text-amber-300" />
          <img src={characters.master} alt="" loading="lazy" className="pointer-events-none absolute -bottom-14 right-5 h-40 w-28 object-contain opacity-70" />
        </div>
        <div className="space-y-3">
          {game.buildings.map((building) => (
            <div key={building.id} className="relative overflow-hidden rounded-3xl border border-white/10 bg-forge-black/80 p-4">
              <img src={buildings[building.id]} alt={building.name} loading="lazy" className={`pointer-events-none absolute -right-5 top-1 h-28 w-28 object-contain ${building.locked ? 'grayscale opacity-35' : 'opacity-80'}`} />
              <div className="relative flex items-center justify-between gap-3 pr-20">
                <div>
                  <h4 className="text-sm font-semibold">{building.name}</h4>
                  <p className="text-[12px] text-slate-400">{lang.levelLabel}: {building.level}</p>
                </div>
                <div className="rounded-full bg-white/5 px-3 py-1 text-xs text-slate-200">{building.productionPerHour} FC/h</div>
              </div>
              <div className="relative mt-3 flex flex-col gap-2 text-sm text-slate-300 sm:flex-row sm:items-center sm:justify-between">
                <span>{lang.storage}: {formatCurrency(building.storage)} FC</span>
                <span>{lang.upgradeCost}: {formatCurrency(building.upgradeCost)} FC</span>
              </div>
              <button
                onClick={() => onUpgrade(building.id)}
                className="relative mt-3 inline-flex w-full items-center justify-center rounded-3xl bg-amber-400/10 px-4 py-3 text-sm font-semibold text-amber-200 transition hover:bg-amber-400/20"
              >
                {lang.upgrade}
              </button>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
