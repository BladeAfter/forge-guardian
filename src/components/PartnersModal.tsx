import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { X } from 'lucide-react';
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

/**
 * Compact partner list. Only NAME + REWARD + GO are rendered: no logo, no URL,
 * no description. The destination is fetched on GO so the link stays server-side.
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
    <div className="fixed inset-0 z-[85] flex items-center justify-center bg-black/80 p-4 backdrop-blur-sm">
      <div className="w-full max-w-[360px] rounded-2xl border border-amber-300/25 bg-[#090d15] p-3 shadow-2xl">
        <header className="flex items-center justify-between gap-2">
          <p className="text-[11px] font-black uppercase tracking-[0.2em] text-amber-200">{t('partners.title')}</p>
          <button onClick={onClose} aria-label="Fechar" className="grid h-7 w-7 place-items-center rounded-full bg-white/5 text-slate-300">
            <X className="h-3.5 w-3.5" />
          </button>
        </header>

        <div className="mt-3 max-h-[60vh] space-y-1.5 overflow-y-auto">
          {isLoading ? <p className="py-6 text-center text-[10px] text-slate-400">{t('partners.loading')}</p> : null}
          {error ? (
            <div className="py-6 text-center">
              <p className="text-[10px] text-rose-300">{error instanceof Error ? error.message : ''}</p>
              <button onClick={() => void refetch()} className="mt-2 rounded-lg border border-white/15 px-3 py-1.5 text-[9px] font-black uppercase tracking-[0.16em] text-slate-200">
                {t('partners.retry')}
              </button>
            </div>
          ) : null}
          {!isLoading && !error && !partners.length ? (
            <p className="py-6 text-center text-[10px] text-slate-400">{t('partners.empty')}</p>
          ) : null}

          {partners.map((partner) => {
            const busy = (goMutation.isPending || claimMutation.isPending) && pending === partner.id;
            return (
              <div key={partner.id} className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-black/40 px-2.5 py-2">
                <p className="min-w-0 flex-1 truncate text-[11px] font-bold text-white">{partner.name}</p>
                {partner.claimed ? (
                  <span className="shrink-0 text-[9px] font-black uppercase tracking-[0.14em] text-emerald-300">✓ {t('partners.claimed')}</span>
                ) : (
                  <>
                    <span className="shrink-0 text-[10px] font-black text-amber-200">+{formatCurrency(partner.rewardFc)} FC</span>
                    <button
                      disabled={busy}
                      onClick={() => {
                        setPending(partner.id);
                        if (partner.visited) claimMutation.mutate(partner.id, { onSettled: () => setPending(null) });
                        else goMutation.mutate(partner.id);
                      }}
                      className="shrink-0 rounded-lg border border-amber-300/50 bg-gradient-to-b from-amber-400/25 to-orange-600/10 px-3 py-1 text-[9px] font-black uppercase tracking-[0.16em] text-amber-100 disabled:opacity-40"
                    >
                      {busy ? '...' : partner.visited ? t('partners.claim') : t('partners.go')}
                    </button>
                  </>
                )}
              </div>
            );
          })}
        </div>

        <p className="mt-2 text-[8px] leading-relaxed text-slate-500">{t('partners.hint')}</p>
      </div>
    </div>
  );
}
