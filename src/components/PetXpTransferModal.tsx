import { useLocalizedText } from '../LanguageContext';
import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowRight, RefreshCw, Sparkles, X } from 'lucide-react';
import { toast } from 'sonner';
import { fetchPetXpTransferPreview, resetAndTransferPetXp } from '../services';
import type { PetXpTransferTarget, PlayerPet } from '../pets';
import { useT } from '../LanguageContext';

const fmt = (value: number) => Math.round(Number(value) || 0).toLocaleString('pt-BR');

/**
 * Level/XP recycling. The server owns every rule (cost, capacity, atomic swap):
 * this sheet only renders the preview and asks for an explicit confirmation.
 */
export function PetXpTransferModal({
  pet,
  telegramInitData,
  onClose,
}: {
  pet: PlayerPet;
  telegramInitData: string;
  onClose: () => void;
}) {
  const localizeText = useLocalizedText();

  const t = useT();
  const queryClient = useQueryClient();
  const [targetId, setTargetId] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [requestKey] = useState(() => `${pet.id}:${Date.now()}`);

  const preview = useQuery({
    queryKey: ['pet-xp-transfer', pet.id],
    queryFn: () => fetchPetXpTransferPreview(telegramInitData, pet.id),
  });

  const transfer = useMutation({
    mutationFn: () => resetAndTransferPetXp(telegramInitData, pet.id, String(targetId), requestKey),
    onSuccess: (data) => {
      const result = data.xpTransferResult;
      queryClient.invalidateQueries({ queryKey: ['pet-dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['pets'] });
      if (result) toast.success(t('pets.transferDone', { xp: fmt(result.xpTransferred), name: result.targetName }));
      onClose();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const data = preview.data;
  const targets = useMemo(() => data?.targets ?? [], [data]);
  const target = targets.find((item) => item.id === targetId) ?? null;
  const notEnoughFc = !!data && data.balance < data.costFc;

  return (
    <div className="fixed inset-0 z-[97] flex items-end justify-center bg-black/85 p-3" onClick={onClose}>
      <div
        className="forge-safe-page max-h-[88vh] w-full max-w-md overflow-y-auto rounded-t-3xl border border-amber-400/30 bg-[#080b11] p-4"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="mb-3 flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.25em] text-amber-300">{t('pets.petManagement')}</p>
            <h2 className="truncate text-lg font-black uppercase">{t('pets.resetPet')}</h2>
          </div>
          <button type="button" onClick={onClose} aria-label={t('pets.close')} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/5">
            <X className="h-4 w-4" />
          </button>
        </header>

        {preview.isLoading ? (
          <p className="py-10 text-center text-xs text-slate-400">…</p>
        ) : preview.error || !data ? (
          <p className="py-10 text-center text-xs text-rose-300">{(preview.error as Error)?.message ?? '—'}</p>
        ) : (
          <>
            <div className="flex items-center gap-3 rounded-2xl border border-white/10 bg-black/50 p-3">
              <img src={pet.image} alt={pet.name} className="h-16 w-16 shrink-0 object-contain" />
              <div className="min-w-0 text-[10px]">
                <b className="block truncate text-sm uppercase">{pet.name}</b>
                <p className="text-slate-400">
                  {t('common.levelShort') === 'common.levelShort' ? localizeText("Lv.") : t('common.levelShort')} {data.level} → 1
                </p>
                <p className="text-emerald-300">{t('pets.recoverableXp')}: <b>{fmt(data.totalXp)} XP</b></p>
                <p className={notEnoughFc ? 'text-rose-300' : 'text-amber-200'}>
                  {t('pets.resetCost')}: <b>{fmt(data.costFc)} BERRIES</b>
                </p>
              </div>
            </div>

            {data.totalXp <= 0 ? (
              <p className="mt-4 rounded-xl border border-white/10 bg-black/50 p-3 text-center text-[10px] text-slate-400">{t('pets.noXpToTransfer')}</p>
            ) : targets.length === 0 ? (
              <p className="mt-4 rounded-xl border border-white/10 bg-black/50 p-3 text-center text-[10px] text-slate-400">{t('pets.noTargetPets')}</p>
            ) : confirming && target ? (
              <div className="mt-4 rounded-2xl border border-amber-300/30 bg-amber-300/5 p-3 text-[10px]">
                <p className="text-center text-[9px] font-black uppercase tracking-[.2em] text-amber-300">{t('pets.confirmResetTitle')}</p>
                <div className="mt-2 space-y-1">
                  <Line label={pet.name} value={`Lv.${data.level} → Lv.1`} />
                  <Line label={t('pets.xpTransferredLabel')} value={`${fmt(data.totalXp)} XP`} />
                  <Line label={t('pets.targetLabel')} value={target.name} />
                  <Line label={t('pets.costLabel')} value={`${fmt(data.costFc)} BERRIES`} />
                </div>
                <p className="mt-2 text-center text-[9px] text-rose-300">{t('pets.cannotUndo')}</p>
                <div className="mt-3 grid grid-cols-2 gap-2">
                  <button type="button" onClick={() => setConfirming(false)} className="rounded-xl border border-white/15 bg-white/5 py-2 text-[9px] font-black uppercase text-slate-200">
                    {t('pets.cancel')}
                  </button>
                  <button
                    type="button"
                    disabled={transfer.isPending || notEnoughFc}
                    onClick={() => transfer.mutate()}
                    className="flex items-center justify-center gap-1 rounded-xl border border-amber-300/30 bg-gradient-to-b from-amber-400 to-orange-600 py-2 text-[9px] font-black uppercase text-black disabled:grayscale disabled:opacity-40"
                  >
                    <Sparkles className="h-3 w-3" />
                    {t('pets.confirm')}
                  </button>
                </div>
              </div>
            ) : (
              <>
                <p className="mt-4 text-[9px] font-black uppercase tracking-[.2em] text-slate-400">
                  {targetId ? t('pets.transferXpTo') : t('pets.chooseTargetPet')}
                </p>
                <div className="mt-2 grid grid-cols-2 gap-2">
                  {targets.map((item) => (
                    <TargetCard
                      key={item.id}
                      target={item}
                      totalXp={data.totalXp}
                      selected={targetId === item.id}
                      onSelect={() => setTargetId(item.id)}
                    />
                  ))}
                </div>

                {target && !target.canReceive ? (
                  <div className="mt-3 rounded-xl border border-rose-400/40 bg-rose-500/10 p-3 text-center">
                    <p className="text-[9px] font-black uppercase text-rose-200">{t('pets.cannotReceiveAll')}</p>
                    <p className="mt-1 text-[9px] text-rose-300/80">{t('pets.cannotReceiveHint')}</p>
                  </div>
                ) : null}

                <button
                  type="button"
                  disabled={!target || !target.canReceive || notEnoughFc}
                  onClick={() => setConfirming(true)}
                  className="mt-3 flex w-full items-center justify-center gap-2 rounded-xl border border-amber-300/30 bg-gradient-to-b from-amber-400 to-orange-600 py-2.5 text-[10px] font-black uppercase text-black disabled:grayscale disabled:opacity-40"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  {notEnoughFc ? t('pets.insufficientBalance') : t('pets.confirmTransfer')}
                  <ArrowRight className="h-3.5 w-3.5" />
                </button>
              </>
            )}
          </>
        )}
      </div>
    </div>
  );
}

function TargetCard({ target, totalXp, selected, onSelect }: { target: PetXpTransferTarget; totalXp: number; selected: boolean; onSelect: () => void }) {
  const localizeText = useLocalizedText();

  const t = useT();
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`flex flex-col rounded-2xl border p-2 text-left ${selected ? 'border-amber-300/70 bg-amber-300/10' : 'border-white/10 bg-black/50'} ${target.canReceive ? '' : 'opacity-60'}`}
    >
      <div className="flex items-center gap-2">
        {target.image ? <img src={target.image} alt={target.name} className="h-10 w-10 shrink-0 object-contain" /> : null}
        <div className="min-w-0">
          <b className="block truncate text-[11px] uppercase">{target.name}</b>
          <p className="text-[9px] text-slate-400">{localizeText("Lv.")}{target.level}</p>
        </div>
      </div>
      <p className="mt-1 text-[9px] text-slate-400">{t('pets.currentXpLabel')}: {fmt(target.xp)}</p>
      <p className={`text-[9px] font-black ${target.canReceive ? 'text-emerald-300' : 'text-rose-300'}`}>
        {t('pets.xpToReceive')}: +{fmt(totalXp)}
      </p>
    </button>
  );
}

function Line({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <span className="truncate text-slate-400">{label}</span>
      <b className="shrink-0 text-slate-100">{value}</b>
    </div>
  );
}

export default PetXpTransferModal;
