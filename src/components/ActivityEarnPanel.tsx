import { useState } from 'react';
import { Sparkles, Swords, Globe2, Castle, PawPrint, Rocket, X } from 'lucide-react';
import { useActivityProgress } from '../hooks';
import { useT, useLanguage } from '../LanguageContext';

/** Icon + accent per activity type. Order below is also the display order. */
const META: Record<string, { icon: React.ReactNode; accent: string }> = {
  PVP_COMPLETE: { icon: <Swords className="h-4 w-4" />, accent: 'text-rose-300' },
  GLOBAL_BOSS_ATTACK: { icon: <Globe2 className="h-4 w-4" />, accent: 'text-cyan-300' },
  CLAN_BOSS_ATTACK: { icon: <Castle className="h-4 w-4" />, accent: 'text-violet-300' },
  PET_FEED: { icon: <PawPrint className="h-4 w-4" />, accent: 'text-emerald-300' },
  EXPEDITION_COMPLETE: { icon: <Rocket className="h-4 w-4" />, accent: 'text-amber-300' },
};
const ORDER = ['PVP_COMPLETE', 'GLOBAL_BOSS_ATTACK', 'CLAN_BOSS_ATTACK', 'PET_FEED', 'EXPEDITION_COMPLETE'];

/**
 * Compact "HOW TO EARN" button + modal for the Community Pool.
 * Pool Points and Pass XP are granted server-side by real gameplay only; this panel
 * is purely informational and also shows today's remaining scoring room per activity.
 */
export function ActivityEarnPanel({ telegramInitData }: { telegramInitData: string }) {
  const t = useT();
  useLanguage();
  const [open, setOpen] = useState(false);
  const { data } = useActivityProgress(telegramInitData, open);
  const rows = (data?.activities ?? []).slice().sort((a, b) => ORDER.indexOf(a.activity) - ORDER.indexOf(b.activity));

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="mt-2 w-full rounded-xl border border-emerald-300/30 bg-emerald-950/20 py-3 text-xs font-black text-emerald-100"
      >
        <Sparkles className="mr-2 inline h-4 w-4" />
        {t('activity.howToEarnButton')}
      </button>

      {open ? (
        <div className="fixed inset-0 z-[100] grid place-items-center bg-black/85 p-4" onClick={() => setOpen(false)}>
          <div
            className="max-h-[85vh] w-full max-w-sm overflow-y-auto rounded-3xl border border-amber-300/35 bg-[#09111f] p-4"
            onClick={(e) => e.stopPropagation()}
          >
            <header className="flex items-start justify-between gap-2">
              <div>
                <h2 className="text-base font-black text-amber-200">{t('activity.howToEarnTitle')}</h2>
                <p className="mt-1 text-[10px] leading-4 text-slate-400">{t('activity.subtitle')}</p>
              </div>
              <button onClick={() => setOpen(false)} className="grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-white/15 bg-black/60">
                <X className="h-4 w-4" />
              </button>
            </header>

            <div className="mt-3 space-y-2">
              {rows.map((row) => {
                const meta = META[row.activity];
                const done = row.dailyCap > 0 && row.used >= row.dailyCap;
                return (
                  <div key={row.activity} className="rounded-2xl border border-white/10 bg-black/55 p-3">
                    <div className="flex items-center justify-between">
                      <b className={`flex items-center gap-2 text-[11px] ${meta?.accent ?? 'text-white'}`}>
                        {meta?.icon}
                        {t(`activity.${row.activity}`)}
                      </b>
                      <span className="text-[9px] font-black uppercase tracking-[.14em] text-slate-400">
                        {t('activity.perDay', { cap: row.dailyCap })}
                      </span>
                    </div>
                    <div className="mt-2 flex items-center gap-2 text-[10px]">
                      <span className="rounded-lg bg-amber-400/15 px-2 py-1 font-black text-amber-200">+{row.poolPoints} {t('activity.poolPoints')}</span>
                      <span className="rounded-lg bg-violet-400/15 px-2 py-1 font-black text-violet-200">+{row.passXp} {t('activity.passXp')}</span>
                    </div>
                    <div className="mt-2 flex items-center justify-between text-[9px]">
                      <span className="uppercase tracking-[.16em] text-slate-500">{t('activity.todayTitle')}</span>
                      <b className={done ? 'text-rose-300' : 'text-emerald-300'}>
                        {row.used}/{row.dailyCap}
                        {done ? ` · ${t('activity.dailyLimitReached')}` : ''}
                      </b>
                    </div>
                    <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/10">
                      <div
                        className={`h-full ${done ? 'bg-rose-400/70' : 'bg-gradient-to-r from-emerald-500 to-emerald-200'}`}
                        style={{ width: `${Math.min(100, (row.used / Math.max(1, row.dailyCap)) * 100)}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>

            <p className="mt-3 text-[9px] leading-4 text-slate-500">{t('activity.resetInfo')}</p>
            <button onClick={() => setOpen(false)} className="mt-3 w-full rounded-xl bg-amber-400 py-3 font-black text-black">
              {t('activity.gotIt')}
            </button>
          </div>
        </div>
      ) : null}
    </>
  );
}
