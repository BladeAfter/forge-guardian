import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Gem, Info } from 'lucide-react';
import { claimRareMythMining, fetchRareMythMining } from '../services';

const myth = (v: number) => Number(v ?? 0).toLocaleString('pt-BR', { maximumFractionDigits: 2 });

/**
 * RARE HERO MYTH MINING — the daily rate is a proportional slice of a fixed global
 * budget with diminishing returns, so it VARIES. We never advertise a guaranteed
 * "1 rare = X MYTH" rate and never show a TON equivalence.
 */
export function RareMythMiningCard({ telegramInitData }: { telegramInitData: string }) {
  const client = useQueryClient();
  const [feedback, setFeedback] = useState<string | null>(null);
  const [open, setOpen] = useState(false);

  const { data: state } = useQuery({
    queryKey: ['rare-myth-mining', telegramInitData],
    queryFn: () => fetchRareMythMining(telegramInitData),
    refetchInterval: 60000,
  });

  const claim = useMutation({
    mutationFn: () => claimRareMythMining(telegramInitData),
    onSuccess: (result) => {
      setFeedback(`Coletado: ${myth(Number(result.claimedMyth ?? 0))} MYTH`);
      client.setQueryData(['rare-myth-mining', telegramInitData], result);
      void client.invalidateQueries({ queryKey: ['myth-token'] });
      void client.invalidateQueries({ queryKey: ['wallet-summary'] });
    },
    onError: (error) => setFeedback(error instanceof Error ? error.message : 'Falha ao coletar.'),
  });

  useEffect(() => {
    if (!feedback) return;
    const timer = window.setTimeout(() => setFeedback(null), 3500);
    return () => window.clearTimeout(timer);
  }, [feedback]);

  if (!state || !state.enabled || Number(state.rareCount ?? 0) <= 0) return null;

  const canClaim = Number(state.unclaimedMyth ?? 0) >= Math.max(Number(state.minClaimMyth ?? 0), 0.000001);
  const capPct = Math.min(100, (Number(state.emittedToday ?? 0) / Math.max(Number(state.playerDailyCapMyth ?? 1), 1)) * 100);

  return (
    <section className="mt-2 overflow-hidden rounded-2xl border border-violet-300/25 bg-gradient-to-br from-slate-950 via-slate-900 to-violet-950/40 p-3">
      <div className="flex items-center justify-between gap-2">
        <p className="flex min-w-0 items-center gap-1.5 truncate text-[10px] font-black uppercase tracking-[.14em] text-violet-200">
          <Gem size={12} /> Mineração MYTH · Heróis Raros
        </p>
        <button onClick={() => setOpen((v) => !v)} className="shrink-0 rounded-full border border-violet-300/30 bg-violet-300/10 p-1 text-violet-200">
          <Info size={11} />
        </button>
      </div>

      <div className="mt-2 grid grid-cols-3 gap-1.5 text-center">
        <div className="rounded-xl bg-black/40 px-1.5 py-1.5">
          <p className="text-[8px] font-black uppercase tracking-widest text-slate-400">Raros</p>
          <p className="text-[12px] font-black text-slate-100">{state.rareCount}</p>
        </div>
        <div className="rounded-xl bg-black/40 px-1.5 py-1.5">
          <p className="text-[8px] font-black uppercase tracking-widest text-slate-400">Unidades</p>
          <p className="text-[12px] font-black text-violet-200">{myth(state.effectiveUnits)}</p>
        </div>
        <div className="rounded-xl bg-black/40 px-1.5 py-1.5">
          <p className="text-[8px] font-black uppercase tracking-widest text-slate-400">MYTH/dia (est.)</p>
          <p className="text-[12px] font-black text-amber-200">{myth(state.estimatedDailyMyth)}</p>
        </div>
      </div>

      <div className="mt-2 rounded-xl bg-black/40 px-2 py-1.5">
        <div className="flex items-center justify-between text-[9px] font-black uppercase tracking-wider">
          <span className="text-slate-400">Hoje</span>
          <span className="text-slate-300">{myth(state.emittedToday)} / {myth(state.playerDailyCapMyth)} MYTH</span>
        </div>
        <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-slate-800">
          <div className="h-full rounded-full bg-gradient-to-r from-violet-400 to-fuchsia-400" style={{ width: `${capPct}%` }} />
        </div>
      </div>

      {open ? (
        <div className="mt-2 rounded-xl border border-violet-300/20 bg-black/40 px-2 py-1.5 text-[9px] leading-relaxed text-slate-400">
          A taxa é <b className="text-slate-200">variável</b>: cada jogador recebe uma fatia do orçamento global diário de{' '}
          <b className="text-slate-200">{myth(state.globalDailyBudgetMyth)} MYTH</b> conforme suas unidades efetivas.
          <br />
          {state.tiers?.map((t) => `${t.from}${t.to ? `–${t.to}` : '+'}: ${Math.round(Number(t.weight) * 100)}%`).join(' · ')}
          <br />Reserva disponível: {myth(state.poolAvailable)} MYTH · nada é criado além do supply oficial.
        </div>
      ) : null}

      <div className="mt-2 flex items-center justify-between gap-2">
        <p className="text-[10px] font-black text-slate-200">
          {myth(state.unclaimedMyth)} <span className="text-[8px] uppercase tracking-widest text-slate-500">MYTH a coletar</span>
        </p>
        <button
          disabled={!canClaim || claim.isPending}
          onClick={() => claim.mutate()}
          className="rounded-xl bg-gradient-to-r from-violet-500 to-fuchsia-600 px-3 py-1.5 text-[10px] font-black uppercase tracking-widest text-white disabled:opacity-40"
        >
          {claim.isPending ? '...' : 'Coletar MYTH'}
        </button>
      </div>
      {feedback ? <p className="mt-1.5 text-center text-[9px] font-bold text-violet-200">{feedback}</p> : null}
    </section>
  );
}
