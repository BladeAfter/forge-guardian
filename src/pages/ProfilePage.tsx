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
    <section className="px-1 pb-24 pt-2">
      <div className="relative overflow-hidden rounded-[1.75rem] border border-amber-300/20 bg-[linear-gradient(145deg,rgba(10,19,33,.97),rgba(3,8,16,.98))] p-4 shadow-[0_18px_45px_rgba(0,0,0,.45)]">
        <div className="pointer-events-none absolute -right-16 -top-20 h-52 w-52 rounded-full bg-amber-400/10 blur-3xl"/>
        <div className="pointer-events-none absolute -bottom-24 -left-20 h-52 w-52 rounded-full bg-sky-500/10 blur-3xl"/>

        <div className="relative flex items-center gap-3 rounded-2xl border border-white/10 bg-black/30 p-3">
          <div className="relative shrink-0">
            {profile?.photoUrl?<img src={profile.photoUrl} alt={name} className="h-16 w-16 rounded-full border-2 border-amber-400/70 object-cover shadow-[0_0_20px_rgba(251,191,36,.18)]"/>:<div className="grid h-16 w-16 place-items-center rounded-full border-2 border-amber-400/70 bg-slate-900 text-lg font-black text-amber-100">{getInitials(name)}</div>}
            <span className="absolute bottom-0 right-0 h-4 w-4 rounded-full border-2 border-[#09111e] bg-emerald-400"/>
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-[9px] font-bold uppercase tracking-[.28em] text-amber-300">{lang.profile}</p>
            <h3 className="truncate text-lg font-black text-white">{name}</h3>
            <p className="truncate text-xs text-cyan-300">{profile?.username?`@${profile.username}`:'Sem username'}</p>
            <p className="mt-0.5 truncate text-[9px] text-slate-500">Telegram ID · {profile?.telegramId??'--'}</p>
          </div>
          <div className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-emerald-300/20 bg-emerald-400/10">
            <Activity className="h-5 w-5 text-emerald-300"/>
          </div>
        </div>

        <div className="relative mt-3 grid grid-cols-2 gap-2">
          <div className="rounded-2xl border border-white/10 bg-black/35 p-3">
            <p className="text-[9px] uppercase tracking-[.2em] text-slate-400">{lang.loginStreak}</p>
            <p className="mt-1 text-xl font-black text-amber-300">{game.loginStreak} <span className="text-xs text-amber-100/70">dias</span></p>
          </div>
          <div className="rounded-2xl border border-white/10 bg-black/35 p-3">
            <p className="text-[9px] uppercase tracking-[.2em] text-slate-400">Status</p>
            <p className="mt-1 flex items-center gap-1.5 text-sm font-black text-emerald-300"><span className="h-2 w-2 rounded-full bg-emerald-400"/>Online</p>
          </div>
        </div>

        <div className="relative mt-3 rounded-2xl border border-white/10 bg-black/35 p-3">
          <div className="mb-2 flex items-center justify-between">
            <p className="text-[9px] font-bold uppercase tracking-[.22em] text-slate-400">Coleção de baús</p>
            <span className="text-[9px] font-bold text-amber-300">{chests.length} itens</span>
          </div>
          <div className="grid grid-cols-4 gap-2">
            {chests.map((chest, index) => <div key={chest} className="rounded-xl border border-amber-300/10 bg-slate-950/65 p-1.5"><img src={chest} alt={`Reward chest ${index + 1}`} loading="lazy" className="aspect-square w-full object-contain drop-shadow-[0_5px_8px_rgba(0,0,0,.5)]" /></div>)}
          </div>
        </div>
      </div>
    </section>
  );
}
