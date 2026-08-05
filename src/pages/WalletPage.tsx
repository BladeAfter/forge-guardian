import { useMemo, useState } from 'react';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowDownToLine, ArrowUpFromLine, CheckCircle2, Clock3, Coins, Egg, Wallet } from 'lucide-react';
import { toast } from 'sonner';
import type { GameState, LanguageStrings } from '../types';
import type { LanguageCode } from '../i18n';
import { coin } from '../gameAssets';
import { FC_PER_TON, MIN_WITHDRAWAL_FC, fcToTon, tonToFc, validWithdrawal } from '../economy';
import { createDepositIntent, createEggTonOrder, requestWithdrawal } from '../services';
import { usePetDashboard, useWalletSummary } from '../hooks';

type Props = {
  game: GameState;
  lang: LanguageStrings;
  languageCode: LanguageCode;
  telegramInitData: string | null;
  connected: boolean;
  address: string | null;
  onConnect: () => Promise<void>;
  onDisconnect: () => Promise<void>;
  isConnecting: boolean;
};

export function WalletPage({ game, telegramInitData, connected, address, onConnect, onDisconnect, isConnecting }: Props) {
  const [tonConnectUI] = useTonConnectUI();
  const queryClient = useQueryClient();
  const backendEnabled = Boolean(telegramInitData);
  const { data: summary } = useWalletSummary(telegramInitData, backendEnabled);
  const { data: pets } = usePetDashboard(telegramInitData, backendEnabled);
  const balance = summary?.balanceFc ?? game.balance;
  const [depositTon, setDepositTon] = useState(1);
  const [withdrawFc, setWithdrawFc] = useState(MIN_WITHDRAWAL_FC);
  const premiumEggs = useMemo(() => pets?.eggs.filter(egg => egg.priceTon && egg.isPurchasable) ?? [], [pets?.eggs]);

  const invalidateWallet = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ['wallet-summary', telegramInitData] }),
      queryClient.invalidateQueries({ queryKey: ['wallet-deposits'] }),
      queryClient.invalidateQueries({ queryKey: ['wallet-withdrawals'] }),
      queryClient.invalidateQueries({ queryKey: ['wallet-history'] }),
      queryClient.invalidateQueries({ queryKey: ['fc-balance'] }),
      queryClient.invalidateQueries({ queryKey: ['game-state', telegramInitData] })
    ]);
  };

  const deposit = useMutation({
    mutationFn: async () => {
      if (!telegramInitData || !connected || !address) throw new Error('Conecte sua carteira TON.');
      if (!Number.isFinite(depositTon) || depositTon <= 0) throw new Error('Informe um valor de depósito válido.');
      const intent = await createDepositIntent(telegramInitData, depositTon, address, crypto.randomUUID());
      await tonConnectUI.sendTransaction({ validUntil: Math.floor(Date.now() / 1000) + 300, messages: [{ address: intent.paymentAddress, amount: intent.amountNano }] });
      return intent;
    },
    onSuccess: async () => { await invalidateWallet(); toast.success('Pagamento enviado. Aguardando confirmação on-chain.'); },
    onError: error => toast.error(error instanceof Error ? error.message : 'Não foi possível depositar.')
  });

  const withdrawal = useMutation({
    mutationFn: async () => {
      if (!telegramInitData || !connected || !address) throw new Error('Conecte sua carteira TON.');
      if (withdrawFc < MIN_WITHDRAWAL_FC) throw new Error('O saque mínimo é 100.000 FC.');
      if (withdrawFc % MIN_WITHDRAWAL_FC !== 0) throw new Error('O valor deve ser múltiplo de 100.000 FC.');
      if (!validWithdrawal(withdrawFc, balance)) throw new Error('Saldo FC insuficiente.');
      return requestWithdrawal(telegramInitData, withdrawFc, address, crypto.randomUUID());
    },
    onSuccess: async () => { await invalidateWallet(); toast.success('Saque solicitado e saldo reservado.'); },
    onError: error => toast.error(error instanceof Error ? error.message : 'Não foi possível solicitar o saque.')
  });

  const buyEgg = useMutation({
    mutationFn: async (eggId: string) => {
      if (!telegramInitData || !connected) throw new Error('Conecte sua carteira TON.');
      const order = await createEggTonOrder(telegramInitData, eggId, crypto.randomUUID());
      await tonConnectUI.sendTransaction({ validUntil: Math.floor(Date.now() / 1000) + 300, messages: [{ address: order.paymentAddress, amount: order.amountNano }] });
      return order;
    },
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['pet-egg-orders'] }),
        queryClient.invalidateQueries({ queryKey: ['pet-inventory'] }),
        queryClient.invalidateQueries({ queryKey: ['pet-dashboard', telegramInitData] }),
        queryClient.invalidateQueries({ queryKey: ['wallet-history'] }),
        queryClient.invalidateQueries({ queryKey: ['wallet-summary', telegramInitData] })
      ]);
      toast.success('Pagamento enviado. O ovo será entregue após a confirmação.');
    },
    onError: error => toast.error(error instanceof Error ? error.message : 'Não foi possível comprar o ovo.')
  });

  return (
    <section className="space-y-3 pb-5">
      <div className="rounded-2xl border border-amber-300/25 bg-[#080d16]/90 p-4 shadow-card">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-[9px] uppercase tracking-[.26em] text-amber-300">CARTEIRA TON</p>
            <div className="mt-1 flex items-center gap-2 text-sm font-bold">
              <span className={`h-2.5 w-2.5 rounded-full ${connected ? 'bg-emerald-400 shadow-[0_0_10px_#34d399]' : 'border border-slate-500'}`} />
              {connected ? 'Conectada' : 'Desconectada'}
            </div>
          </div>
          <button onClick={connected ? onDisconnect : onConnect} disabled={isConnecting} className="rounded-xl border border-amber-300/20 bg-black/40 px-3 py-2 text-[9px] font-bold text-amber-100 disabled:opacity-40">
            {isConnecting ? 'Processando...' : connected ? 'Desconectar' : 'CONECTAR CARTEIRA'}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Panel title="SALDO" icon={<Coins />}>
          <div className="flex items-center gap-2"><img src={coin} className="h-8 w-8 object-contain" alt="FC"/><strong className="text-lg text-amber-200">{Math.floor(balance).toLocaleString('pt-BR')} FC</strong></div>
          <p className="mt-1 text-[9px] text-slate-400">Equivalente a {fcToTon(balance).toLocaleString('pt-BR', { maximumFractionDigits: 4 })} TON</p>
        </Panel>
        <Panel title="CONVERSÃO" icon={<Wallet />}>
          <strong className="text-sm text-sky-300">1 TON</strong><p className="text-[10px] text-slate-300">= {FC_PER_TON.toLocaleString('pt-BR')} FC</p>
        </Panel>
      </div>

      <Panel title="DEPOSITAR TON" icon={<ArrowDownToLine />}>
        <div className="grid grid-cols-4 gap-1">{[1,3,5,10].map(value => <Quick key={value} active={depositTon===value} onClick={() => setDepositTon(value)}>{value} TON</Quick>)}</div>
        <input type="number" min="0.01" step="0.01" value={depositTon} onChange={event => setDepositTon(Number(event.target.value))} aria-label="Quantidade de TON" className="mt-2 w-full rounded-xl border border-white/10 bg-black/45 px-3 py-2 text-sm outline-none focus:border-sky-400" />
        <Result label="Você receberá" value={`${tonToFc(depositTon).toLocaleString('pt-BR')} FC`} />
        <Primary onClick={() => deposit.mutate()} disabled={!connected || deposit.isPending}>{deposit.isPending ? 'ABRINDO CARTEIRA...' : 'DEPOSITAR TON'}</Primary>
      </Panel>

      <Panel title="SACAR FC" icon={<ArrowUpFromLine />}>
        <div className="grid grid-cols-4 gap-1">{[100000,300000,500000].map(value => <Quick key={value} active={withdrawFc===value} onClick={() => setWithdrawFc(value)}>{value/1000} mil</Quick>)}<Quick active={withdrawFc===Math.floor(balance/100000)*100000} onClick={() => setWithdrawFc(Math.floor(balance/100000)*100000)}>Máximo</Quick></div>
        <input type="number" min="100000" step="100000" value={withdrawFc} onChange={event => setWithdrawFc(Number(event.target.value))} aria-label="Quantidade de FC" className="mt-2 w-full rounded-xl border border-white/10 bg-black/45 px-3 py-2 text-sm outline-none focus:border-sky-400" />
        <Result label="Você receberá" value={`${fcToTon(withdrawFc).toLocaleString('pt-BR')} TON`} />
        <Primary onClick={() => withdrawal.mutate()} disabled={!connected || withdrawal.isPending || !validWithdrawal(withdrawFc,balance)}>{withdrawal.isPending ? 'SOLICITANDO...' : 'SOLICITAR SAQUE'}</Primary>
      </Panel>

      {premiumEggs.length ? <Panel title="OVOS PREMIUM" icon={<Egg />}><div className="grid grid-cols-2 gap-2">{premiumEggs.map(egg => <div key={egg.id} className="rounded-xl border border-violet-400/20 bg-black/35 p-2 text-center"><img src={egg.image} className="mx-auto h-16 w-16 object-contain"/><p className="text-[10px] font-bold">{egg.name}</p><p className="text-xs font-black text-violet-300">{egg.priceTon} TON</p><button onClick={() => buyEgg.mutate(egg.id)} disabled={!connected || buyEgg.isPending} className="mt-2 w-full rounded-lg border border-violet-300/30 bg-violet-500/15 py-2 text-[8px] font-black text-violet-100 disabled:opacity-35">COMPRAR POR {egg.priceTon} TON</button></div>)}</div></Panel> : null}

      <Panel title="HISTÓRICO" icon={<Clock3 />}>
        <div className="max-h-60 space-y-2 overflow-y-auto">{summary?.history.length ? summary.history.map(item => <div key={`${item.type}-${item.id}`} className="flex items-center gap-2 rounded-xl bg-black/35 p-2"><Status status={item.status}/><div className="min-w-0 flex-1"><p className="truncate text-[10px] font-bold">{item.label}</p><p className="text-[8px] text-slate-500">{new Date(item.createdAt).toLocaleString('pt-BR')}</p></div><span className="text-[8px] uppercase text-slate-300">{statusLabel(item.status)}</span></div>) : <p className="py-5 text-center text-[10px] text-slate-500">Nenhuma movimentação.</p>}</div>
      </Panel>
    </section>
  );
}

function Panel({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) { return <div className="rounded-2xl border border-amber-300/15 bg-[#080d16]/82 p-3"><div className="mb-3 flex items-center gap-2 text-amber-300"><span className="h-4 w-4">{icon}</span><h3 className="text-[9px] font-black tracking-[.2em]">{title}</h3></div>{children}</div>; }
function Quick({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) { return <button type="button" onClick={onClick} className={`rounded-lg border px-1 py-2 text-[8px] font-bold ${active ? 'border-sky-300 bg-sky-500/20 text-sky-100' : 'border-white/10 bg-black/30 text-slate-300'}`}>{children}</button>; }
function Result({ label, value }: { label: string; value: string }) { return <div className="my-2 flex items-center justify-between rounded-xl bg-black/30 px-3 py-2"><span className="text-[9px] text-slate-400">{label}</span><strong className="text-xs text-emerald-300">{value}</strong></div>; }
function Primary({ children, onClick, disabled }: { children: React.ReactNode; onClick: () => void; disabled?: boolean }) { return <button type="button" onClick={onClick} disabled={disabled} className="w-full rounded-xl border border-amber-300/35 bg-amber-400/90 py-2.5 text-[10px] font-black text-black transition active:scale-[.98] disabled:grayscale disabled:opacity-35">{children}</button>; }
function Status({ status }: { status: string }) { const done=['credited','completed','delivered','paid','confirmed'].includes(status);return done?<CheckCircle2 className="h-4 w-4 text-emerald-400"/>:<Clock3 className="h-4 w-4 text-amber-300"/>; }
function statusLabel(status:string){return({pending:'Pendente',confirmed:'Confirmado',credited:'Creditado',processing:'Processando',completed:'Concluído',paid:'Pago',delivered:'Entregue',expired:'Expirado',rejected:'Rejeitado',cancelled:'Cancelado'}as Record<string,string>)[status]??status;}
