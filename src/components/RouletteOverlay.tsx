import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { toast } from 'sonner';
import { X, Loader2, Sparkle, Wallet } from 'lucide-react';
import wheelImage from '../assets/roulette/wheel.png';
import backdropImage from '../assets/roulette/backdrop.jpg';
import mysteryHeroImage from '../assets/roulette/mystery-hero.png';
import mythPrizeImage from '../assets/roulette/myth-prize.png';
import equipmentPrizeImage from '../assets/roulette/equipment-prize.png';
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

/** Reward art is chosen ONLY from what the backend already granted — never a prediction. */
const rewardArt = (reward: RouletteSpinResult['normal']) =>
  String(reward?.class ?? '') === 'NFT_EQUIPMENT' ? equipmentPrizeImage : mythPrizeImage;

const rewardTitle = (result: RouletteSpinResult) => {
  if (result.premium) return String(result.premium.name || result.premium.label || 'PRÊMIO LENDÁRIO');
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

  const settle = useCallback((res: RouletteSpinResult) => {
    setAngle((current) => current + 1440 + Math.floor(Math.random() * 360));
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
  const blocked = data && (!data.enabled || data.paused);

  return (
    <div className="fixed inset-0 z-[130] overflow-y-auto">
      <img src={backdropImage} alt="" className="fixed inset-0 h-full w-full object-cover opacity-70" />
      <div className="fixed inset-0 bg-gradient-to-b from-background/85 via-background/70 to-background" />

      <div className="forge-safe-page relative mx-auto flex w-full max-w-md flex-col items-center gap-5 px-4 pb-10 pt-4">
        <div className="flex w-full items-center justify-between">
          <div>
            <p className="text-[10px] font-black uppercase tracking-[0.35em] text-primary">MYTHREON</p>
            <h1 className="text-lg font-black uppercase tracking-widest text-foreground">Global Mystery Roulette</h1>
          </div>
          <button type="button" onClick={onClose} aria-label="Fechar" className="rounded-full border border-border/60 bg-card/70 p-2 text-muted-foreground">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="relative flex h-72 w-72 items-center justify-center">
          <div className="absolute inset-0 rounded-full bg-primary/20 blur-3xl" />
          <img
            src={wheelImage}
            alt="Roleta mística"
            className="relative h-full w-full select-none drop-shadow-[0_0_40px_rgba(0,0,0,0.6)]"
            style={{ transform: `rotate(${angle}deg)`, transition: 'transform 2.6s cubic-bezier(0.16,1,0.3,1)' }}
          />
          <div className="pointer-events-none absolute -top-1 h-6 w-6 rotate-45 border-b-2 border-r-2 border-primary" />
          {result ? (
            <div className="absolute inset-8 flex flex-col items-center justify-center gap-2 rounded-full border border-primary/40 bg-background/85 p-4 text-center backdrop-blur">
              <img src={result.premium ? mysteryHeroImage : rewardArt(result.normal)} alt="" className="h-20 w-20 object-contain" />
              <p className="text-[10px] font-bold uppercase tracking-widest text-primary">
                {result.premium ? 'PRÊMIO LENDÁRIO' : 'RECOMPENSA'}
              </p>
              <p className="text-sm font-black uppercase text-foreground">{rewardTitle(result)}</p>
            </div>
          ) : null}
        </div>

        <div className="w-full rounded-2xl border border-border/60 bg-card/80 p-4 backdrop-blur">
          <div className="flex items-center justify-between text-xs">
            <span className="font-bold uppercase tracking-widest text-muted-foreground">Custo do giro</span>
            <span className="font-black text-foreground">💎 {cost} TON</span>
          </div>
          <div className="mt-1 flex items-center justify-between text-[11px] text-muted-foreground">
            <span>Saldo interno</span>
            <span>💎 {internalTon.toLocaleString('en-US', { maximumFractionDigits: 3 })} TON</span>
          </div>

          <button
            type="button"
            onClick={spin}
            disabled={Boolean(busy || blocked || !telegramInitData)}
            className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-primary py-3 text-sm font-black uppercase tracking-widest text-primary-foreground disabled:opacity-50"
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : usesWallet ? <Wallet className="h-4 w-4" /> : <Sparkle className="h-4 w-4" />}
            {blocked ? 'ROLETA INDISPONÍVEL' : busy ? 'GIRANDO...' : usesWallet ? `PAGAR ${cost} TON E GIRAR` : 'GIRAR AGORA'}
          </button>
          <p className="mt-2 text-center text-[10px] leading-relaxed text-muted-foreground">
            Todo giro entrega uma recompensa. Prêmios lendários surgem de forma imprevisível e são sorteados
            exclusivamente pelo servidor.
          </p>
        </div>

        <div className="w-full rounded-2xl border border-border/60 bg-card/70 p-4 backdrop-blur">
          <p className="text-[10px] font-black uppercase tracking-[0.3em] text-muted-foreground">Seus últimos giros</p>
          <div className="mt-2 space-y-1 text-[11px]">
            {history.length === 0 ? (
              <p className="text-muted-foreground">Nenhum giro ainda.</p>
            ) : (
              history.map((spinEntry) => (
                <div key={spinEntry.id} className="flex items-center justify-between gap-2">
                  <span className="truncate text-foreground">
                    {spinEntry.premium ? '👑 Prêmio lendário' : String(spinEntry.normal?.class) === 'MYTH'
                      ? `🪙 ${formatCurrency(Number(spinEntry.normal?.amount ?? 0))} MYTH`
                      : `🛡 ${spinEntry.normal?.label ?? 'Equipamento NFT'}`}
                  </span>
                  <span className="shrink-0 text-muted-foreground">
                    {spinEntry.at ? new Date(spinEntry.at).toLocaleDateString('pt-BR') : '—'}
                  </span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
