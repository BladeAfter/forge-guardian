import type { GameState, LanguageStrings } from '../types';
import { Activity } from 'lucide-react';
import { chests } from '../gameAssets';
import {getDisplayName,getInitials,type TelegramPlayerProfile} from '../playerProfile';

type ProfilePageProps = {
  game: GameState;
  lang: LanguageStrings;
  profile: TelegramPlayerProfile|null;
};

export function ProfilePage({ game, lang, profile }: ProfilePageProps) {
  const name=profile?getDisplayName(profile):'Jogador';
  return (
    <section className="space-y-4">
      <div className="rounded-3xl border border-white/10 bg-forge-black/80 p-4 shadow-card">
        <div className="relative mb-4 flex min-h-40 items-start justify-between overflow-hidden">
          <div>
            <p className="text-xs uppercase tracking-[0.3em] text-slate-400">{lang.profile}</p>
            <h3 className="mt-1 text-lg font-semibold">{name}</h3>
            <p className="text-xs text-sky-300">{profile?.username?`@${profile.username}`:'Sem username'}</p>
            <p className="text-[10px] text-slate-400">ID: {profile?.telegramId??'--'}</p>
          </div>
          <Activity className="h-5 w-5 text-emerald-300" />
          {profile?.photoUrl?<img src={profile.photoUrl} alt={name} className="h-16 w-16 rounded-full border-2 border-amber-400/50 object-cover"/>:<div className="grid h-16 w-16 place-items-center rounded-full border-2 border-amber-400/50 bg-slate-900 font-black">{getInitials(name)}</div>}
        </div>
        <div className="space-y-3 text-sm text-slate-300">
          <div className="rounded-3xl bg-forge-black/70 p-4">
            <p className="text-xs uppercase tracking-[0.25em] text-slate-400">{lang.villageLevel}</p>
            <p className="mt-2 text-lg font-semibold">{game.level}</p>
          </div>
          <div className="rounded-3xl bg-forge-black/70 p-4">
            <p className="text-xs uppercase tracking-[0.25em] text-slate-400">{lang.loginStreak}</p>
            <p className="mt-2 text-lg font-semibold">{game.loginStreak}d</p>
          </div>
        </div>
        <div className="mt-4 grid grid-cols-4 gap-2 rounded-3xl bg-forge-black/70 p-3">
          {chests.map((chest, index) => <img key={chest} src={chest} alt={`Reward chest ${index + 1}`} loading="lazy" className="aspect-square w-full object-contain" />)}
        </div>
      </div>
    </section>
  );
}
