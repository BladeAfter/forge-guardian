import type { GameState, LanguageStrings } from '../types';
import { Trophy } from 'lucide-react';
import { characters, missionIcons } from '../gameAssets';
import { translate, type LanguageCode } from '../i18n';

type MissionsPageProps = {
  game: GameState;
  lang: LanguageStrings;
  onClaim: (id: string) => void;
  languageCode: LanguageCode;
};

export function MissionsPage({ game, lang, onClaim, languageCode }: MissionsPageProps) {
  return (
    <section className="space-y-4">
      <div className="rounded-3xl border border-white/10 bg-forge-black/80 p-4 shadow-card">
        <div className="relative mb-4 flex min-h-24 items-center justify-between overflow-hidden">
          <div>
            <p className="text-xs uppercase tracking-[0.3em] text-slate-400">{lang.missions}</p>
            <h3 className="mt-1 text-lg font-semibold">{lang.dailyQuests}</h3>
          </div>
          <Trophy className="h-5 w-5 text-blue-300" />
          <img src={characters.novice} alt="" loading="lazy" className="pointer-events-none absolute -bottom-10 right-5 h-36 w-28 object-contain opacity-75" />
        </div>
        <div className="space-y-3">
          {game.missions.map((mission, index) => (
            <div key={mission.id} className="rounded-3xl border border-white/10 bg-forge-black/70 p-4">
              <div className="flex items-center justify-between gap-2">
                <img src={missionIcons[index] ?? missionIcons[0]} alt="" loading="lazy" className="h-14 w-14 shrink-0 object-contain" />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold">{translate(languageCode, `mission.${mission.id}.title`)}</p>
                  <p className="text-[12px] text-slate-400">{translate(languageCode, `mission.${mission.id}.desc`)}</p>
                </div>
                <button
                  onClick={() => onClaim(mission.id)}
                  disabled={!mission.complete || mission.claimed}
                  className="rounded-full bg-amber-500/15 px-3 py-2 text-xs text-amber-200 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  {mission.claimed ? 'OK' : mission.complete ? `+${mission.reward} FC` : translate(languageCode, 'inProgress')}
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
