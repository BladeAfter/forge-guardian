import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';

import { useTonConnectUI } from '@tonconnect/ui-react';
import { toast } from 'sonner';
import { X, Loader2, Sparkle, Wallet } from 'lucide-react';
import wheelImage from '../assets/roulette/wheel.png';
import backdropImage from '../assets/roulette/backdrop.jpg';
import {
  PossibleRewards,
  RewardMedallion,
  RewardPreviewPopup,
  rewardCategory,
  type RewardCategory,
  type RewardCategoryId,
} from './RouletteRewardKit';
import { RouletteWheel, rotationForSlice } from './RouletteWheel';

import {
  fetchRouletteState,
  isRoulettePayment,
  spinRoulette,
  verifyRoulettePayments,
  type RouletteSpinResult,
} from '../services';
import { sendTonPayment } from '../tonPayment';
import { formatCurrency } from '../utils';

type Props = { telegramInitData: string | null; onClose: () => void };

/** Reward identity is derived ONLY from what the backend already granted — never a prediction. */
type RewardLike = {
  normal?: RouletteSpinResult['normal'] | null;
  premium?: RouletteSpinResult['premium'] | boolean | null;
};

const premiumTag = (premium: RewardLike['premium']) => {
  if (!premium || typeof premium === 'boolean') return '';
  const p = premium as { name?: string; label?: string; class?: string };
  return `${p.name ?? ''} ${p.label ?? ''} ${p.class ?? ''}`.toLowerCase();
};

const resultCategoryId = (result: RewardLike): RewardCategoryId => {
  if (result.premium) {
    return premiumTag(result.premium).includes('celestial') ? 'CELESTIAL' : 'MYSTERY';
  }
  const cls = String(result.normal?.class ?? '').toUpperCase();
  if (cls === 'MYTH') return 'MYTH';
  if (cls.includes('CHEST') || cls.includes('EGG')) return 'CHEST';
  return 'GEAR';
};

const rewardTitle = (result: RewardLike) => {
  if (result.premium) {
    const p = typeof result.premium === 'boolean' ? null : (result.premium as { name?: string; label?: string });
    return String(p?.name || p?.label || 'HERÓI MISTERIOSO');
  }
  const reward = result.normal;
  if (!reward) return 'RECOMPENSA ENTREGUE';
  if (String(reward.class) === 'MYTH') return `${formatCurrency(Number(reward.amount ?? 0))} MYTH`;
  return String(reward.label || 'EQUIPAMENTO NFT');
};



export function RouletteOverlay({ telegramInitData, onClose }: Props) {
  const queryClient = useQueryClient();
  const [tonUI] = useTonConnectUI();
  const [spinning, setSpinning] = useState(false);
  const [awaitingPayment, setAwaitingPayment] = useState(false);
  const [result, setResult] = useState<RouletteSpinResult | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [preview, setPreview] = useState<RewardCategory | null>(null);


  const [angle, setAngle] = useState(0);
  const idempotencyRef = useRef<string | null>(null);

  const state = useQuery({
    queryKey: ['roulette-state'],
    queryFn: () => fetchRouletteState(telegramInitData as string),
    enabled: Boolean(telegramInitData),
    staleTime: 15_000,
  });

  const data = state.data;
  const cost = Number(data?.spinCostTon ?? 5);
  const internalTon = Number(data?.internalTon ?? 0);
  const usesWallet = internalTon < cost;
  const busy = spinning || awaitingPayment;

  const refreshAll = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['roulette-state'] });
    queryClient.invalidateQueries({ queryKey: ['player-heroes'] });
    queryClient.invalidateQueries({ queryKey: ['player'] });
  }, [queryClient]);

  /** A paid spin that never resolved is recovered on open, so no TON is ever lost. */
  useEffect(() => {
    if (!telegramInitData) return;
    verifyRoulettePayments(telegramInitData)
      .then((res) => {
        if (res.settled.length) {
          setResult(res.settled[res.settled.length - 1]);
          refreshAll();
        }
      })
      .catch(() => undefined);
  }, [telegramInitData, refreshAll]);

  /** The animation only REPRESENTS the server-side result: the pointer lands on its slice. */
  const settle = useCallback((res: RouletteSpinResult) => {
    setAngle((current) => rotationForSlice(current, resultCategoryId(res)));
    setSpinning(true);
    window.setTimeout(() => {
      setSpinning(false);
      setResult(res);
      refreshAll();
    }, 2600);
  }, [refreshAll]);


  const spin = useCallback(async () => {
    if (!telegramInitData || busy) return;
    setResult(null);
    const key = idempotencyRef.current ?? `rl-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
    idempotencyRef.current = key;
    setSpinning(true);
    setAngle((current) => current + 720);
    try {
      const response = await spinRoulette(telegramInitData, key);
      if (isRoulettePayment(response)) {
        setSpinning(false);
        setAwaitingPayment(true);
        toast(`Confirme ${response.amountTon} TON na carteira para girar.`);
        await sendTonPayment(response, (tx) => tonUI.sendTransaction(tx as never));
        toast('Aguardando confirmação na blockchain...', { id: 'rl-pay' });
        for (let attempt = 0; attempt < 30; attempt += 1) {
          await new Promise((resolve) => window.setTimeout(resolve, 4000));
          const check = await verifyRoulettePayments(telegramInitData).catch(() => null);
          const settled = check?.settled?.[check.settled.length - 1];
          if (settled) {
            toast.dismiss('rl-pay');
            idempotencyRef.current = null;
            setAwaitingPayment(false);
            settle(settled);
            return;
          }
        }
        toast.dismiss('rl-pay');
        toast.error('Pagamento ainda não confirmado. Reabra a roleta em instantes.');
        setAwaitingPayment(false);
        return;
      }
      idempotencyRef.current = null;
      settle(response);
    } catch (error) {
      setSpinning(false);
      setAwaitingPayment(false);
      idempotencyRef.current = null;
      toast.error(error instanceof Error ? error.message : 'Não foi possível girar a roleta.');
    }
  }, [telegramInitData, busy, tonUI, settle]);

  const history = useMemo(() => (data?.mySpins ?? []).slice(0, 6), [data]);
  const blocked = Boolean(data && (!data.enabled || data.paused));

  /** Body scroll is frozen while the exclusive fullscreen mode is mounted. */
  useEffect(() => {
    const body = document.body;
    const prevOverflow = body.style.overflow;
    const prevTouch = body.style.touchAction;
    body.style.overflow = 'hidden';
    body.style.touchAction = 'none';
    return () => {
      body.style.overflow = prevOverflow;
      body.style.touchAction = prevTouch;
    };
  }, []);

  const balanceLabel = `${internalTon.toLocaleString('en-US', { maximumFractionDigits: 3 })} TON`;

  return createPortal(
    <div
      className="fixed inset-0 z-[300] flex flex-col overflow-y-auto bg-[#04060d]"
      style={{ height: '100dvh', overscrollBehavior: 'contain' }}
    >
      {/* Opaque own scenery — nothing from the hero shop can bleed through. */}
      <div className="pointer-events-none absolute inset-0">
        <img src={backdropImage} alt="" className="h-full w-full object-cover opacity-45" />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_28%,rgba(56,120,255,0.28),transparent_62%),linear-gradient(to_bottom,#04060d_0%,rgba(4,6,13,0.45)_38%,#04060d_100%)]" />
      </div>

      <div
        className="relative z-10 mx-auto flex w-full max-w-md flex-1 flex-col items-center px-4"
        style={{
          paddingTop: 'calc(env(safe-area-inset-top, 0px) + 0.9rem)',
          paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 1rem)',
        }}
      >
        {/* HEADER (own) */}
        <div className="flex w-full items-start justify-between">
          <div className="min-w-0">
            <p className="text-[9px] font-black uppercase tracking-[0.35em] text-amber-300">MYTHREON</p>
            <h1 className="truncate text-base font-black uppercase tracking-[0.14em] text-sky-100">
              Global Mystery Roulette
            </h1>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Fechar"
            className="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-amber-300/30 bg-black/50 text-amber-200"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* WHEEL — the five real reward slices live inside the wheel itself */}
        <div className="flex w-full flex-1 items-center justify-center py-2">
          <div className="relative aspect-square w-[min(86vw,340px)]">
            <div className="absolute inset-2 rounded-full bg-sky-500/20 blur-3xl" />
            <RouletteWheel angle={angle} spinning={spinning} onSelect={setPreview} />

            <div className="pointer-events-none absolute -top-1 left-1/2 h-5 w-5 -translate-x-1/2 rotate-45 border-b-2 border-r-2 border-amber-300" />


            {/* RESULT REVEAL — clear category identity + name */}
            {result
              ? (() => {
                  const category = rewardCategory(resultCategoryId(result));
                  const grand = category.id === 'CELESTIAL';
                  return (
                    <div
                      className={`absolute ${grand ? 'inset-[6%]' : 'inset-[13%]'} flex flex-col items-center justify-center gap-1.5 rounded-full border bg-[#04060d]/94 p-3 text-center animate-scale-in ${category.ring} ${category.glow}`}
                    >
                      <span
                        className={`absolute inset-0 rounded-full bg-gradient-to-br ${category.chip} opacity-50`}
                        aria-hidden
                      />
                      <p className="relative text-[9px] font-black uppercase tracking-[0.34em] text-amber-300">
                        You won
                      </p>
                      <img
                        src={category.icon}
                        alt={category.name}
                        loading="lazy"
                        className={`relative object-contain ${grand ? 'h-28 w-28' : 'h-20 w-20'} ${category.anim}`}
                      />
                      <p className={`relative text-[10px] font-black uppercase tracking-[0.2em] ${category.text}`}>
                        {category.name}
                      </p>
                      <p className="relative px-2 text-[13px] font-black uppercase leading-tight text-sky-50">
                        {rewardTitle(result)}
                      </p>
                    </div>
                  );
                })()
              : null}
          </div>
        </div>

        {/* POSSIBLE REWARDS — compact, tap for preview */}
        <PossibleRewards onSelect={setPreview} />


        {/* SPIN AREA — minimal */}
        <div className="mt-3 w-full">
          <p className="mb-1.5 text-center text-[10px] font-bold uppercase tracking-[0.18em] text-slate-400">
            Balance: <span className="text-sky-200">{balanceLabel}</span>
          </p>
          <button
            type="button"
            onClick={() => setConfirmOpen(true)}
            disabled={Boolean(busy || blocked || !telegramInitData)}
            className="flex w-full items-center justify-center gap-2 rounded-xl border border-amber-300/40 bg-gradient-to-r from-amber-400 to-amber-300 py-3 text-[13px] font-black uppercase tracking-[0.16em] text-[#1b1204] disabled:opacity-50"
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : usesWallet ? <Wallet className="h-4 w-4" /> : <Sparkle className="h-4 w-4" />}
            {blocked ? 'INDISPONÍVEL' : busy ? 'GIRANDO...' : `SPIN • ${cost} TON`}
          </button>
          {history.length ? (
            (() => {
              const last = rewardCategory(resultCategoryId(history[0]));
              return (
                <div className="mt-2 flex items-center justify-center gap-1.5">
                  <RewardMedallion category={last} size={20} onClick={() => setPreview(last)} />
                  <span className={`truncate text-[9px] font-black uppercase tracking-[0.14em] ${last.text}`}>
                    Último: {rewardTitle(history[0])}
                  </span>
                </div>
              );
            })()
          ) : null}

        </div>
      </div>

      {/* Small confirmation modal */}
      {confirmOpen ? (
        <div className="absolute inset-0 z-20 flex items-center justify-center bg-black/80 px-6">
          <div className="w-full max-w-[280px] rounded-2xl border border-amber-300/30 bg-[#080c16] p-4 text-center">
            <p className="text-[11px] font-black uppercase tracking-[0.2em] text-amber-300">Spin roulette?</p>
            <div className="mt-3 space-y-1 text-[11px]">
              <div className="flex items-center justify-between text-slate-400">
                <span className="uppercase tracking-[0.12em]">Cost</span>
                <span className="font-black text-sky-100">💎 {cost} TON</span>
              </div>
              <div className="flex items-center justify-between text-slate-400">
                <span className="uppercase tracking-[0.12em]">Balance</span>
                <span className="font-black text-sky-100">💎 {balanceLabel}</span>
              </div>
            </div>
            <div className="mt-4 flex gap-2">
              <button
                type="button"
                onClick={() => setConfirmOpen(false)}
                className="flex-1 rounded-xl border border-white/10 bg-white/5 py-2 text-[11px] font-black uppercase tracking-[0.14em] text-slate-300"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => { setConfirmOpen(false); void spin(); }}
                className="flex-1 rounded-xl bg-gradient-to-r from-amber-400 to-amber-300 py-2 text-[11px] font-black uppercase tracking-[0.14em] text-[#1b1204]"
              >
                Confirm
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {/* Elegant reward preview — no odds, no internal rules */}
      {preview ? <RewardPreviewPopup category={preview} onClose={() => setPreview(null)} /> : null}

    </div>,
    document.body,
  );
}

