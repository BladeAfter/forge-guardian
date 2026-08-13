import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Check, Handshake, Sparkles, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { claimPartner, fetchPartners, openPartner, type PartnerChannel } from '../partners';
import { formatCurrency } from '../utils';

/** Opens the backend-provided link with Telegram's native opener when available. */
const openLink = (url: string) => {
  const webApp = (window as any)?.Telegram?.WebApp;
  if (/^https?:\/\/(t\.me|telegram\.me)\//i.test(url) && webApp?.openTelegramLink) webApp.openTelegramLink(url);
  else if (webApp?.openLink) webApp.openLink(url);
  else window.open(url, '_blank', 'noopener,noreferrer');
};

/** Deterministic accent per partner so every card feels alive but stays stable between renders. */
const ACCENTS = [
  { ring: 'from-amber-300 to-orange-500', glow: 'rgba(251,191,36,.35)' },
  { ring: 'from-sky-300 to-indigo-500', glow: 'rgba(56,189,248,.35)' },
  { ring: 'from-violet-300 to-fuchsia-500', glow: 'rgba(167,139,250,.35)' },
  { ring: 'from-emerald-300 to-teal-500', glow: 'rgba(52,211,153,.35)' },
  { ring: 'from-rose-300 to-red-500', glow: 'rgba(251,113,133,.35)' },
];
const accentFor = (id: string) => ACCENTS[Math.abs([...id].reduce((a, c) => a + c.charCodeAt(0), 0)) % ACCENTS.length];
const initialsOf = (name: string) =>
  name
    .replace(/[^\p{L}\p{N} ]/gu, ' ')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? '')
    .join('') || '★';

/**
 * Premium partner list. The Mini App still only knows NAME + REWARD + claimed state:
 * the destination is fetched on GO so the link stays server-side.
 */
export function PartnersModal({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const queryClient = useQueryClient();
  const [pending, setPending] = useState<string | null>(null);
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['partner-channels', telegramInitData],
    queryFn: () => fetchPartners(telegramInitData),
    enabled: Boolean(telegramInitData),
    staleTime: 10_000,
    refetchOnWindowFocus: true,
    retry: 1,
  });

  // Coming back from the partner channel refreshes the list so CLAIM shows up immediately.
  useEffect(() => {
    const onFocus = () => void refetch();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [refetch]);

  const claimMutation = useMutation({
    mutationFn: (partnerId: string) => claimPartner(telegramInitData, partnerId),
    onSuccess: async (result) => {
      queryClient.setQueryData(['partner-channels', telegramInitData], { partners: result.partners });
      if (result.status === 'claimed') {
        toast.success(`${t('partners.rewardTitle')} +${formatCurrency(result.creditedFc)} FC`);
      }
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['game-state'] }),
        queryClient.invalidateQueries({ queryKey: ['wallet-summary'] }),
      ]);
    },
    onError: (mutationError) => toast.error(mutationError instanceof Error ? mutationError.message : 'Erro'),
  });

  const goMutation = useMutation({
    mutationFn: (partnerId: string) => openPartner(telegramInitData, partnerId),
    onSuccess: async (visit) => {
      openLink(visit.url);
      await refetch();
    },
    onError: (mutationError) => toast.error(mutationError instanceof Error ? mutationError.message : 'Erro'),
    onSettled: () => setPending(null),
  });

  const partners: PartnerChannel[] = data?.partners ?? [];

  return (
    <div className="fixed inset-0 z-[85] flex items-center justify-center bg-black/85 p-4 backdrop-blur-md">
      <div
        className="relative w-full max-w-[380px] overflow-hidden rounded-3xl border border-amber-300/30 bg-gradient-to-b from-[#141a2c] via-[#0b1020] to-[#05070e] p-3.5 shadow-[0_25px_60px_-18px_rgba(0,0,0,.95)]"
        style={{ boxShadow: '0 0 0 1px rgba(251,191,36,.12), 0 25px 60px -18px rgba(0,0,0,.95)' }}
      >
        <div className="pointer-events-none absolute -top-24 left-1/2 h-44 w-64 -translate-x-1/2 rounded-full bg-amber-400/20 blur-3xl" />

        <header className="relative flex items-start gap-2.5">
          <div className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-amber-300/40 bg-gradient-to-b from-amber-400/30 to-orange-600/10 text-amber-200">
            <Handshake className="h-4 w-4" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-[12px] font-black uppercase tracking-[0.2em] text-amber-200">{t('partners.title')}</p>
            <p className="mt-0.5 text-[9px] leading-snug text-slate-400">{t('partners.subtitle')}</p>
          </div>
          <button
            onClick={onClose}
            aria-label="Fechar"
            className="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-white/10 bg-white/5 text-slate-300 transition active:scale-90"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </header>

        <div className="relative mt-3 max-h-[58vh] space-y-2 overflow-y-auto pr-0.5">
          {isLoading ? <p className="py-8 text-center text-[10px] text-slate-400">{t('partners.loading')}</p> : null}
          {error ? (
            <div className="py-8 text-center">
              <p className="text-[10px] text-rose-300">{error instanceof Error ? error.message : ''}</p>
              <button
                onClick={() => void refetch()}
                className="mt-2 rounded-lg border border-white/15 bg-white/5 px-3 py-1.5 text-[9px] font-black uppercase tracking-[0.16em] text-slate-200 active:scale-95"
              >
                {t('partners.retry')}
              </button>
            </div>
          ) : null}
          {!isLoading && !error && !partners.length ? (
            <p className="py-8 text-center text-[10px] text-slate-400">{t('partners.empty')}</p>
          ) : null}

          {partners.map((partner) => {
            const busy = (goMutation.isPending || claimMutation.isPending) && pending === partner.id;
            const accent = accentFor(partner.id);
            return (
              <div
                key={partner.id}
                className={`relative flex items-center gap-2.5 overflow-hidden rounded-2xl border px-2.5 py-2.5 transition ${
                  partner.claimed
                    ? 'border-emerald-400/30 bg-emerald-950/25'
                    : 'border-amber-300/20 bg-black/50 active:scale-[0.99]'
                }`}
                style={partner.claimed ? undefined : { boxShadow: `inset 0 0 22px -12px ${accent.glow}` }}
              >
                <div
                  className={`grid h-11 w-11 shrink-0 place-items-center rounded-full bg-gradient-to-br ${
                    partner.claimed ? 'from-emerald-300 to-teal-600' : accent.ring
                  } text-[13px] font-black text-black shadow-lg`}
                >
                  {partner.claimed ? <Check className="h-5 w-5" /> : initialsOf(partner.name)}
                </div>

                <div className="min-w-0 flex-1">
                  <p className="truncate text-[12px] font-black tracking-wide text-white">{partner.name}</p>
                  <p className="mt-0.5 truncate text-[8px] font-bold uppercase tracking-[0.16em] text-slate-500">
                    {t('partners.category')}
                  </p>
                  {partner.claimed ? (
                    <span className="mt-1 inline-flex items-center gap-1 rounded-full border border-emerald-400/40 bg-emerald-500/15 px-2 py-0.5 text-[8px] font-black uppercase tracking-[0.14em] text-emerald-300">
                      <Check className="h-2.5 w-2.5" />
                      {t('partners.claimed')}
                    </span>
                  ) : (
                    <span className="mt-1 inline-flex items-center gap-1 rounded-full border border-amber-300/40 bg-amber-400/15 px-2 py-0.5 text-[8px] font-black tracking-[0.1em] text-amber-200">
                      <Sparkles className="h-2.5 w-2.5" />+{formatCurrency(partner.rewardFc)} FC
                    </span>
                  )}
                </div>

                {!partner.claimed ? (
                  <button
                    disabled={busy}
                    onClick={() => {
                      setPending(partner.id);
                      if (partner.visited) claimMutation.mutate(partner.id, { onSettled: () => setPending(null) });
                      else goMutation.mutate(partner.id);
                    }}
                    className={`shrink-0 rounded-xl border px-3.5 py-2 text-[9px] font-black uppercase tracking-[0.16em] text-black shadow-md transition active:scale-95 disabled:opacity-40 ${
                      partner.visited
                        ? 'border-emerald-200/50 bg-gradient-to-b from-emerald-300 to-teal-600'
                        : 'border-amber-200/60 bg-gradient-to-b from-amber-300 to-orange-500'
                    }`}
                  >
                    {busy ? '...' : partner.visited ? t('partners.claim') : t('partners.go')}
                  </button>
                ) : null}
              </div>
            );
          })}
        </div>

        <p className="relative mt-2.5 rounded-xl border border-white/5 bg-white/[0.03] px-2.5 py-2 text-[8px] leading-relaxed text-slate-500">
          {t('partners.hint')}
        </p>
      </div>
    </div>
  );
}
