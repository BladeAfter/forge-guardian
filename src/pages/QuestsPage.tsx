import { useEffect, useMemo } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { characters, chests, mainScreenArt, missionIcons } from '../gameAssets';
import { formatCurrency } from '../utils';
import { claimDailyQuest, claimDailyQuestChest } from '../services';
import type { DailyQuest, DailyQuestsDashboard } from '../quests';
import { useT, useLanguage } from '../LanguageContext';


type QuestsPageProps = {
  telegramInitData: string | null;
  dashboard?: DailyQuestsDashboard;
  loading: boolean;
  error?: string | null;
};

const QUEST_ART: Record<string, string> = {
  login: missionIcons[0],
  pet: mainScreenArt.pet,
  boss: missionIcons[3],
  pvp: mainScreenArt.pvp,
  chest: chests[1],
  hero: characters.knight,
};

const questArt = (quest: DailyQuest) => QUEST_ART[quest.icon ?? ''] ?? missionIcons[0];

export function QuestsPage({ telegramInitData, dashboard, loading, error }: QuestsPageProps) {
  const t = useT();
  const { tError } = useLanguage();
  const queryClient = useQueryClient();
  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['daily-quests'] });
    void queryClient.invalidateQueries({ queryKey: ['season-pass'] });
    void queryClient.invalidateQueries({ queryKey: ['player-inventory'] });
    void queryClient.invalidateQueries({ queryKey: ['reward-history'] });
    void queryClient.invalidateQueries({ queryKey: ['game-state'] });
  };

  const claim = useMutation({
    mutationFn: (code: string) => claimDailyQuest(telegramInitData ?? '', code),
    onSuccess: (result) => {
      queryClient.setQueryData(['daily-quests', telegramInitData], result.quests);
      invalidate();
      toast.success(t('quests.rewardValue', { amount: formatCurrency(result.rewardFc ?? 0) }));
    },
    onError: (mutationError: unknown) => toast.error(mutationError instanceof Error ? tError(mutationError) : t('quests.claimQuestError')),
  });

  const chestUnlocked = Boolean(dashboard?.bonus.unlocked) && (dashboard?.completed ?? 0) >= (dashboard?.total ?? 0) && (dashboard?.total ?? 0) > 0;
  const chestClaimed = Boolean(dashboard?.bonus.claimed);

  const claimChest = useMutation({
    // The server re-checks the 5/5 progress and the daily cycle; the client only guards the taps.
    mutationFn: () => {
      if (!chestUnlocked || chestClaimed) throw new Error(t('quests.claimChestError'));
      return claimDailyQuestChest(telegramInitData ?? '');
    },
    onSuccess: (result) => {
      queryClient.setQueryData(['daily-quests', telegramInitData], result.quests);
      invalidate();
      toast.success(t('quests.chestAddedToast'));
    },
    onError: (mutationError: unknown) => toast.error(mutationError instanceof Error ? tError(mutationError) : t('quests.claimChestApiError')),
  });


  // Temporary diagnostic: exposes the real definition/progress counts coming from the server.
  useEffect(() => {
    console.info('[DAILY QUESTS]', {
      definitionsLoaded: Boolean(dashboard),
      activeDailyCount: dashboard?.total ?? 0,
      userProgressCount: dashboard?.quests?.length ?? 0,
      completedCount: dashboard?.completed ?? 0,
      date: dashboard?.questDate ?? null,
      error: error ?? null,
    });
  }, [dashboard, error]);

  const percent = useMemo(() => {
    if (!dashboard?.total) return 0;
    return Math.min(100, Math.round((dashboard.completed / dashboard.total) * 100));
  }, [dashboard]);


  return (
    <section className="space-y-3">
      <div className="rounded-3xl border border-amber-300/25 bg-forge-black/85 p-4 shadow-card">
        <div className="flex items-end justify-between gap-3">
          <div>
            <p className="text-[10px] font-black uppercase tracking-[0.32em] text-amber-300">{t('quests.dailyLabel')}</p>
            <h1 className="text-2xl font-black uppercase tracking-wide text-white">{t('quests.title')}</h1>
          </div>
          <div className="text-right">
            {/* Never fake a total: while the server answer is in flight we show a placeholder instead of 0/0. */}
            <p className="text-lg font-black text-amber-200">{dashboard ? t('quests.progressFraction', { completed: dashboard.completed, total: dashboard.total }) : t('quests.progressPlaceholder')}</p>

            <p className="text-[9px] uppercase tracking-[0.2em] text-slate-400">{t('quests.resetsDaily')}{dashboard?.timezone ? ` · ${dashboard.timezone}` : ''}</p>
          </div>
        </div>
        <div className="mt-3 h-2.5 overflow-hidden rounded-full bg-white/10">
          <div className="h-full rounded-full bg-gradient-to-r from-amber-300 via-amber-400 to-orange-500 transition-all" style={{ width: `${percent}%` }} />
        </div>

        {/* 5/5 bonus: the chest and its odds are resolved server-side; CLAIM only unlocks at 5/5. */}
        <div className={`mt-3 flex items-center gap-3 rounded-2xl border p-3 ${chestUnlocked && !chestClaimed ? 'border-amber-300/60 bg-amber-400/10' : 'border-white/10 bg-white/[.03]'}`}>
          <img src={chests[0]} alt="Daily quest chest" className="h-11 w-11 object-contain" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-[11px] font-black uppercase tracking-[0.16em] text-amber-200">{t('quests.chestTitle')}</p>
            <p className="text-[10px] text-slate-400">
              {chestClaimed ? t('quests.chestClaimed') : chestUnlocked ? t('quests.chestUnlocked') : t('quests.chestLocked')}
            </p>
            <p className="text-[9px] uppercase tracking-[0.14em] text-slate-500">{t('quests.chestQuantity', { name: dashboard?.bonus.name ?? t('quests.chestDefaultName') })}</p>
          </div>
          <button
            type="button"
            onClick={() => claimChest.mutate()}
            disabled={!chestUnlocked || chestClaimed || claimChest.isPending}
            className="h-10 rounded-xl bg-gradient-to-b from-amber-300 to-orange-600 px-4 text-[10px] font-black text-[#241307] disabled:cursor-not-allowed disabled:bg-none disabled:bg-white/5 disabled:text-slate-500 disabled:opacity-70"
          >
            {chestClaimed ? t('quests.chestClaimedLabel') : claimChest.isPending ? t('quests.claimPending') : chestUnlocked ? t('quests.claimLabel') : t('quests.lockedLabel')}
          </button>
        </div>

      </div>

      {/* Never surface raw backend/SQL errors to players — the details stay in the console log above. */}
      {error ? <p className="rounded-2xl border border-rose-400/30 bg-rose-500/10 p-3 text-xs text-rose-200">{t('quests.errorLoad')}</p> : null}
      {loading && !dashboard ? <p className="p-3 text-xs text-slate-400">{t('quests.loading')}</p> : null}

      <div className="space-y-2">
        {(dashboard?.quests ?? []).map((quest) => (
          <div key={quest.code} className="flex items-center gap-3 rounded-3xl border border-white/10 bg-forge-black/80 p-3">
            <img src={questArt(quest)} alt="" loading="lazy" className="h-12 w-12 shrink-0 object-contain" />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[12px] font-black uppercase tracking-[0.12em] text-white">{quest.title}</p>
              <p className="truncate text-[10px] text-slate-400">{quest.description}</p>
              <div className="mt-1.5 flex items-center gap-2">
                <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10">
                  <div className="h-full rounded-full bg-emerald-400" style={{ width: `${Math.min(100, (quest.progress / Math.max(1, quest.target)) * 100)}%` }} />
                </div>
                <span className="text-[9px] font-bold text-slate-400">{Math.min(quest.progress, quest.target)}/{quest.target}</span>
              </div>
              <p className="mt-1 text-[10px] font-bold text-emerald-300">{t('quests.rewardValue', { amount: formatCurrency(quest.rewardFc) })}</p>
            </div>
            <button
              type="button"
              onClick={() => claim.mutate(quest.code)}
              disabled={!quest.completed || quest.claimed || claim.isPending}
              className={`h-10 shrink-0 rounded-xl px-3 text-[10px] font-black uppercase tracking-[0.1em] ${quest.claimed ? 'bg-white/5 text-slate-500' : quest.completed ? 'bg-gradient-to-b from-amber-300 to-orange-600 text-[#241307]' : 'bg-white/5 text-slate-500'} disabled:cursor-not-allowed`}
            >
              {quest.claimed ? t('quests.claimedLabel') : quest.completed ? t('quests.claimLabel') : t('quests.inProgress')}
            </button>
          </div>
        ))}
      </div>
    </section>
  );
}
