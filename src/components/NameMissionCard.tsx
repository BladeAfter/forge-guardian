import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { AtSign, HelpCircle, ShieldCheck, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { fetchNameMission, verifyNameMission, type NameMissionState } from '../nameMission';
import { formatCurrency } from '../utils';

/**
 * MISSION: ADD #MYTHREON TO YOUR TELEGRAM NAME.
 * VERIFY & CLAIM is a single idempotent backend operation: the server reads the real
 * Telegram profile, validates the exact hashtag and pays once per Telegram ID. The
 * in-game profile name is never used as proof.
 */
export function NameMissionCard({ telegramInitData }: { telegramInitData: string }) {
  const t = useT();
  const queryClient = useQueryClient();
  const [howTo, setHowTo] = useState(false);

  const { data } = useQuery({
    queryKey: ['name-mission', telegramInitData],
    queryFn: () => fetchNameMission(telegramInitData),
    enabled: Boolean(telegramInitData),
    staleTime: 15_000,
    retry: 1,
  });

  const state: NameMissionState | null = data ?? null;
  const hashtag = state?.hashtag ?? '#Mythreon';

  const verify = useMutation({
    mutationFn: () => verifyNameMission(telegramInitData),
    onSuccess: (result) => {
      queryClient.setQueryData(['name-mission', telegramInitData], {
        enabled: result.enabled,
        hashtag: result.hashtag,
        rewardFc: result.rewardFc,
        claimed: result.claimed,
        claimedAt: result.claimedAt,
        verifiedName: result.verifiedName,
        rewardReceived: result.rewardReceived,
      });
      if (result.status === 'claimed') {
        toast.success(t('nameMission.success', { hashtag: result.hashtag ?? hashtag }));
        void queryClient.invalidateQueries({ queryKey: ['game-state'] });
        void queryClient.invalidateQueries({ queryKey: ['wallet-summary'] });
      } else if (result.status === 'already_claimed') {
        toast(t('nameMission.alreadyClaimed'));
      } else {
        toast.error(t('nameMission.failure', { hashtag: result.hashtag ?? hashtag }));
        // Session data can predate the rename: never validate an old cache silently.
        if (result.stale) toast(t('nameMission.stale'));
      }
    },
    onError: (error: unknown) => {
      const code = error instanceof Error ? error.message : '';
      if (code === 'NAME_MISSION_DISABLED') toast.error(t('nameMission.disabled'));
      else if (code === 'NAME_MISSION_HASHTAG_MISSING') toast.error(t('nameMission.failure', { hashtag }));
      else toast.error(t('nameMission.error'));
    },
  });

  if (!state?.enabled && !state?.claimed) return null;
  const claimed = Boolean(state?.claimed);

  return (
    <>
      <div className={`rounded-3xl border p-3.5 ${claimed ? 'border-emerald-300/30 bg-emerald-500/5' : 'border-sky-300/30 bg-forge-black/80'}`}>
        <div className="flex items-start gap-3">
          <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-2xl border ${claimed ? 'border-emerald-300/40 text-emerald-200' : 'border-sky-300/40 text-sky-200'} bg-black/50`}>
            {claimed ? <ShieldCheck className="h-5 w-5" /> : <AtSign className="h-5 w-5" />}
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[11px] font-black uppercase leading-tight tracking-[0.12em] text-white">{t('nameMission.title')}</p>
            <p className="mt-1 text-[10px] leading-snug text-slate-400">{t('nameMission.description')}</p>
            <p className="mt-1 text-[10px] font-bold text-emerald-300">{t('nameMission.reward', { amount: formatCurrency(state?.rewardFc ?? 0) })}</p>
            {claimed && state?.verifiedName ? (
              <p className="mt-1 truncate text-[9px] uppercase tracking-[0.14em] text-emerald-200/70">{t('nameMission.verifiedName', { name: state.verifiedName })}</p>
            ) : null}
          </div>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={() => setHowTo(true)}
            className="flex h-10 items-center justify-center gap-1.5 rounded-xl border border-white/15 bg-white/5 text-[10px] font-black uppercase tracking-[0.12em] text-slate-200 active:scale-95"
          >
            <HelpCircle className="h-3.5 w-3.5" /> {t('nameMission.how')}
          </button>
          <button
            type="button"
            onClick={() => verify.mutate()}
            disabled={claimed || verify.isPending}
            className={`h-10 rounded-xl text-[10px] font-black uppercase tracking-[0.12em] ${
              claimed ? 'bg-white/5 text-slate-500' : 'bg-gradient-to-b from-sky-300 to-indigo-600 text-[#08111f]'
            } disabled:cursor-not-allowed`}
          >
            {claimed ? t('nameMission.claimed') : verify.isPending ? t('nameMission.verifying') : t('nameMission.verify')}
          </button>
        </div>
      </div>

      {howTo ? (
        <div className="fixed inset-0 z-[95] flex items-center justify-center bg-black/85 p-4 backdrop-blur-sm">
          <div className="w-full max-w-[360px] rounded-3xl border border-sky-300/30 bg-gradient-to-b from-[#0d1626] to-black p-4">
            <header className="flex items-center justify-between">
              <p className="text-[11px] font-black uppercase tracking-[0.18em] text-sky-200">{t('nameMission.stepsTitle')}</p>
              <button type="button" onClick={() => setHowTo(false)} aria-label="close" className="grid h-8 w-8 place-items-center rounded-full border border-white/10 bg-white/5 text-slate-300">
                <X className="h-3.5 w-3.5" />
              </button>
            </header>
            <p className="mt-3 whitespace-pre-line text-[11px] leading-relaxed text-slate-200">{t('nameMission.steps', { hashtag })}</p>
            <p className="mt-3 rounded-xl border border-white/10 bg-white/5 p-2 text-center text-[11px] font-bold text-amber-200">{t('nameMission.example', { hashtag })}</p>
            <p className="mt-2 text-[9px] leading-snug text-slate-500">{t('nameMission.stale')}</p>
            <button
              type="button"
              onClick={() => setHowTo(false)}
              className="mt-3 h-10 w-full rounded-xl bg-gradient-to-b from-sky-300 to-indigo-600 text-[10px] font-black uppercase tracking-[0.16em] text-[#08111f]"
            >
              {t('nameMission.close')}
            </button>
          </div>
        </div>
      ) : null}
    </>
  );
}
