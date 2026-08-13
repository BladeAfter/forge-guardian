import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Clock, Coins, Play, Sparkles, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { adRewardErrorKey, beginAdReward, claimAdReward, fetchAdRewards, type AdRewardsState } from '../adsRewards';
import { showAd } from '../adsgram';
import { formatTon } from '../economy';

const resetLabel = (iso: string) => {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '21:00';
  const diff = Math.max(0, date.getTime() - Date.now());
  const hours = Math.floor(diff / 3_600_000);
  const minutes = Math.floor((diff % 3_600_000) / 60_000);
  return `${hours}h ${String(minutes).padStart(2, '0')}m`;
};

/**
 * REWARDS: watch a rewarded ad, receive TON in the withdrawable balance.
 * The server is the single authority for the value, the daily limit and the reset.
 */
export function RewardsModal({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState(false);

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['ad-rewards', telegramInitData],
    queryFn: () => fetchAdRewards(telegramInitData),
    enabled: Boolean(telegramInitData),
    staleTime: 10_000,
    refetchOnWindowFocus: true,
    retry: 1,
  });

  const ads: AdRewardsState | null = data?.ads ?? null;
  const watched = ads?.adsCompleted ?? 0;
  const limit = ads?.dailyLimit ?? 10;
  const percent = limit > 0 ? Math.min(100, Math.round((watched / limit) * 100)) : 0;

  const watch = useMutation({
    mutationFn: async () => {
      const opened = await beginAdReward(telegramInitData);
      const blockId = String(opened.blockId || ads?.blockId || '');
      if (!blockId) throw new Error('AD_REWARDS_DISABLED');
      const outcome = await showAd(blockId);
      if (outcome !== 'completed') throw new Error(outcome === 'no-ads' ? 'NO_ADS' : 'AD_NOT_COMPLETED');
      return claimAdReward(telegramInitData, opened.viewId);
    },
    onSuccess: (result) => {
      if (result.granted) toast.success(t('adRewards.success', { amount: formatTon(result.rewardTon ?? ads?.rewardTon ?? 0) }));
      else toast.error(t(adRewardErrorKey(String(result.reason || ''))));
      void queryClient.invalidateQueries({ queryKey: ['ad-rewards'] });
      void queryClient.invalidateQueries({ queryKey: ['ton-wallet'] });
      void queryClient.invalidateQueries({ queryKey: ['wallet'] });
      void queryClient.invalidateQueries({ queryKey: ['game-state'] });
    },
    onError: (raw: unknown) => {
      const code = raw instanceof Error ? raw.message : '';
      if (code === 'NO_ADS') toast.error(t('adRewards.errorNoAds'));
      else if (code === 'AD_NOT_COMPLETED') toast.error(t('adRewards.errorNotWatched'));
      else toast.error(t(adRewardErrorKey(code)));
      void queryClient.invalidateQueries({ queryKey: ['ad-rewards'] });
    },
    onSettled: () => setBusy(false),
  });

  const disabled = busy || watch.isPending || !ads?.enabled || (ads?.remaining ?? 0) <= 0;

  return (
    <div className="fixed inset-0 z-[95] flex items-end justify-center bg-black/80 px-3 pb-5 pt-16 backdrop-blur-sm sm:items-center">
      <div className="relative w-full max-w-[420px] overflow-hidden rounded-[26px] border border-amber-300/40 bg-gradient-to-b from-[#1b1305] via-[#0b0a08] to-black shadow-[0_0_50px_rgba(251,191,36,.25)]">
        <div className="pointer-events-none absolute inset-0 rounded-[26px] border border-amber-200/10" />
        <header className="relative flex items-center justify-between border-b border-amber-300/20 bg-gradient-to-r from-amber-500/15 via-transparent to-amber-500/15 px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="grid h-9 w-9 place-items-center rounded-xl border border-amber-300/40 bg-black/60 text-amber-200 shadow-[0_0_18px_rgba(251,191,36,.35)]">
              <Sparkles className="h-4 w-4" />
            </span>
            <div>
              <p className="text-[13px] font-black uppercase tracking-[0.16em] text-amber-100">{t('adRewards.title')}</p>
              <p className="text-[9px] uppercase tracking-[0.2em] text-amber-300/70">{t('adRewards.subtitle')}</p>
            </div>
          </div>
          <button type="button" onClick={onClose} aria-label="close" className="grid h-8 w-8 place-items-center rounded-lg border border-white/10 bg-black/50 text-slate-300">
            <X className="h-4 w-4" />
          </button>
        </header>

        <div className="space-y-4 px-4 py-4">
          {isLoading ? (
            <div className="h-40 animate-pulse rounded-2xl bg-white/5" />
          ) : error || !ads ? (
            <div className="rounded-2xl border border-rose-400/30 bg-rose-950/30 p-5 text-center">
              <p className="text-xs text-rose-100">{t('adRewards.loadError')}</p>
              <button type="button" onClick={() => void refetch()} className="mt-3 rounded-xl border border-amber-300/40 px-4 py-2 text-[10px] font-black uppercase tracking-[0.18em] text-amber-200">
                {t('adRewards.retry')}
              </button>
            </div>
          ) : (
            <>
              <div className="relative overflow-hidden rounded-2xl border border-amber-300/35 bg-gradient-to-br from-amber-500/15 via-black/60 to-black p-4 text-center shadow-[inset_0_0_30px_rgba(251,191,36,.12)]">
                <p className="text-[9px] font-black uppercase tracking-[0.22em] text-amber-300/80">{t('adRewards.perAd')}</p>
                <p className="mt-1 flex items-center justify-center gap-2 text-3xl font-black text-amber-200 drop-shadow-[0_0_16px_rgba(251,191,36,.45)]">
                  <Coins className="h-6 w-6" />
                  {formatTon(ads.rewardTon)} TON
                </p>
                <p className="mt-1 text-[10px] text-slate-300">{t('adRewards.hint', { max: formatTon(ads.maxTon), limit: ads.dailyLimit })}</p>
              </div>

              <div className="rounded-2xl border border-white/10 bg-black/50 p-4">
                <div className="flex items-center justify-between text-[10px] font-bold uppercase tracking-[0.16em] text-slate-300">
                  <span>{t('adRewards.progress')}</span>
                  <span className="text-amber-200">{watched}/{limit}</span>
                </div>
                <div className="mt-2 h-3 overflow-hidden rounded-full border border-amber-300/20 bg-black/70">
                  <div className="h-full rounded-full bg-gradient-to-r from-amber-300 via-amber-400 to-orange-500 shadow-[0_0_12px_rgba(251,191,36,.6)] transition-all" style={{ width: `${percent}%` }} />
                </div>
                <div className="mt-3 grid grid-cols-2 gap-2">
                  <div className="rounded-xl border border-emerald-300/20 bg-emerald-500/5 p-2 text-center">
                    <p className="text-[9px] uppercase tracking-[0.16em] text-emerald-200/80">{t('adRewards.earnedToday')}</p>
                    <p className="text-sm font-black text-emerald-300">{formatTon(ads.earnedTon)} TON</p>
                  </div>
                  <div className="rounded-xl border border-sky-300/20 bg-sky-500/5 p-2 text-center">
                    <p className="flex items-center justify-center gap-1 text-[9px] uppercase tracking-[0.16em] text-sky-200/80">
                      <Clock className="h-3 w-3" /> {t('adRewards.resetIn')}
                    </p>
                    <p className="text-sm font-black text-sky-200">{resetLabel(ads.resetsAt)}</p>
                  </div>
                </div>
              </div>

              <button
                type="button"
                disabled={disabled}
                onClick={() => { setBusy(true); watch.mutate(); }}
                className={`flex w-full items-center justify-center gap-2 rounded-2xl border py-4 text-xs font-black uppercase tracking-[0.2em] transition ${
                  disabled
                    ? 'border-white/10 bg-white/5 text-slate-500'
                    : 'border-amber-200/60 bg-gradient-to-b from-amber-200 via-amber-400 to-orange-500 text-black shadow-[0_0_28px_rgba(251,191,36,.45)] active:scale-[.98]'
                }`}
              >
                <Play className="h-4 w-4" />
                {watch.isPending
                  ? t('adRewards.loading')
                  : (ads.remaining ?? 0) <= 0
                    ? t('adRewards.limitReached')
                    : t('adRewards.watch', { amount: formatTon(ads.rewardTon) })}
              </button>
              <p className="text-center text-[9px] leading-relaxed text-slate-500">{t('adRewards.footer')}</p>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
