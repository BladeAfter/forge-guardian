import { useLocalizedText } from '../LanguageContext';
import { useEffect, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Plus, X } from 'lucide-react';
import { toast } from 'sonner';
import { useTowerKeyShop } from '../hooks';
import { buyTowerKey, verifyTowerKeyPurchases } from '../services';
import { sendTonPayment } from '../tonPayment';
import { TOWER_KEYS } from '../tower';

/**
 * 🔑 CHAVES RARAS — vitrine + compra com TON.
 *
 * O servidor é dono de tudo: preço por chave, limite de compras por passe (5 TON = 5 compras,
 * 20 TON = 10 compras, o passe de 20 sobrepõe o de 5), débito do saldo interno e entrega.
 * O cliente só mostra a verdade do servidor: se o saldo interno cobre o preço, a compra é
 * instantânea; caso contrário o TON Connect abre e a chave só chega após confirmação on-chain.
 */
export function RareKeyShop({ initData, keyChances }: { initData: string; keyChances?: Record<string, number> }) {
  const localizeText = useLocalizedText();

  const client = useQueryClient();
  const [tonConnectUI] = useTonConnectUI();
  const { data: shop } = useTowerKeyShop(initData || null, Boolean(initData));
  const [confirmKey, setConfirmKey] = useState<string | null>(null);
  const [flash, setFlash] = useState<string | null>(null);

  const refresh = () => Promise.all(
    ['tower-key-shop', 'tower-dashboard', 'ton-wallet', 'wallet-summary', 'player-inventory', 'game-state']
      .map(key => client.invalidateQueries({ queryKey: [key] })),
  );

  const reconcile = async () => {
    try {
      const result = await verifyTowerKeyPurchases(initData);
      if (result.confirmed.length) {
        setFlash(confirmKey);
        toast.success('Chave entregue no inventário!');
      }
      await refresh();
    } catch { /* nova tentativa na próxima montagem */ }
  };

  const ensureWallet = async (): Promise<string> => {
    const current = tonConnectUI.account?.address;
    if (current) return current;
    const linked = new Promise<string>((resolve, reject) => {
      const unsubscribe = tonConnectUI.onStatusChange(wallet => {
        if (wallet?.account?.address) { unsubscribe(); resolve(wallet.account.address); }
      });
      window.setTimeout(() => { unsubscribe(); reject(new Error('Conecte uma carteira TON para continuar.')); }, 120_000);
    });
    await tonConnectUI.openModal();
    return linked;
  };

  const buy = useMutation({
    mutationFn: async (keyCode: string) => {
      const entry = shop?.keys.find(k => k.keyCode === keyCode);
      const payWithInternal = (shop?.availableTon ?? 0) >= (entry?.priceTon ?? 0);
      const walletAddress = payWithInternal ? undefined : await ensureWallet();
      const order = await buyTowerKey(initData, keyCode, crypto.randomUUID(), walletAddress);
      if (order.status === 'payment_required') {
        await sendTonPayment(
          { paymentAddress: String(order.paymentAddress), paymentComment: String(order.paymentComment), amountNano: String(order.amountNano) },
          tx => tonConnectUI.sendTransaction(tx),
        );
      }
      return order;
    },
    onSuccess: async order => {
      await refresh();
      setConfirmKey(null);
      if (order.status === 'completed') {
        setFlash(order.keyCode);
        window.setTimeout(() => setFlash(null), 2_600);
      } else {
        toast.success('Pagamento enviado. Confirmando na blockchain…');
        window.setTimeout(() => { void reconcile(); }, 6_000);
      }
    },
    onError: error => toast.error(error instanceof Error ? error.message : 'Não foi possível comprar a chave.'),
  });

  useEffect(() => { if (shop?.pendingOrder) void reconcile(); }, [shop?.pendingOrder?.orderId]);

  const limit = shop?.purchaseLimit ?? 0;
  const used = shop?.purchasesUsed ?? 0;
  const blocked = !shop || shop.limitReached || shop.passRequired || buy.isPending;
  const selected = confirmKey ? shop?.keys.find(k => k.keyCode === confirmKey) : null;
  const selectedMeta = confirmKey ? TOWER_KEYS.find(k => k.code === confirmKey) : null;

  return (
    <>
      <div className="mt-3 flex items-center justify-between">
        <p className="text-[9px] uppercase tracking-[.28em] text-slate-500">{localizeText("Chaves raras")}</p>
        <p className={`text-[9px] font-black uppercase tracking-[.16em] ${shop?.limitReached ? 'text-rose-300' : 'text-amber-200'}`}>
          {shop?.limitReached ? localizeText("Limite atingido") : `Compras ${used} / ${limit}`}
        </p>
      </div>
      <div className="mt-1.5 grid grid-cols-3 gap-2">
        {TOWER_KEYS.map((key) => {
          const chance = Number(keyChances?.[key.code] ?? 0);
          const entry = shop?.keys.find(k => k.keyCode === key.code);
          const price = Number(entry?.priceTon ?? 0);
          const owned = Number(entry?.owned ?? 0);
          const disabled = blocked || !entry?.enabled;
          return (
            <div
              key={key.code}
              className="relative rounded-2xl border bg-black/65 p-2 text-center"
              style={{ borderColor: `${key.color}55` }}
            >
              <img src={key.image} alt={key.name} loading="lazy" width={512} height={512} className={`mx-auto h-9 w-9 object-contain ${chance > 0 ? '' : 'opacity-60'}`} />
              <p className="mt-1 truncate text-[8px] font-black uppercase tracking-[.06em]" style={{ color: key.color }}>{key.name}</p>
              <p className="text-[8px] text-slate-400">{chance > 0 ? `${chance}%` : '—'}</p>
              <p className="text-[8px] text-slate-300">{localizeText("Possui:")}<span className="font-bold text-white">{owned}</span></p>
              <div className="mt-1 flex items-center justify-between gap-1">
                <span className="text-[8px] font-bold text-slate-200">{price} TON</span>
                <button
                  type="button"
                  aria-label={`Comprar ${key.name}`}
                  disabled={disabled}
                  onClick={() => setConfirmKey(key.code)}
                  className="flex h-5 w-5 items-center justify-center rounded-full border text-black transition disabled:opacity-30"
                  style={{ backgroundColor: key.color, borderColor: key.color }}
                >
                  <Plus className="h-3 w-3" strokeWidth={3} />
                </button>
              </div>
              {flash === key.code ? (
                <p className="absolute inset-x-1 bottom-1 animate-pulse rounded-lg bg-black/85 py-1 text-[7px] font-black uppercase tracking-[.08em]" style={{ color: key.color }}>
                  {key.name} +1
                </p>
              ) : null}
            </div>
          );
        })}
      </div>
      <p className="mt-1.5 text-center text-[8px] text-slate-500">
        {shop?.passRequired ? localizeText("Compra de chaves exige o Passe de 5 TON ou 20 TON") : localizeText("Saldo interno de TON • TON Connect disponível")}
      </p>

      {selected && selectedMeta ? (
        <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/80 p-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-[280px] rounded-3xl border bg-forge-black/95 p-4 text-center shadow-card" style={{ borderColor: `${selectedMeta.color}66` }}>
            <div className="flex items-start justify-between">
              <p className="text-[9px] uppercase tracking-[.24em] text-slate-400">{localizeText("Comprar chave")}</p>
              <button type="button" aria-label={localizeText("Fechar")} onClick={() => setConfirmKey(null)} className="rounded-full bg-white/10 p-1 text-slate-200">
                <X className="h-3 w-3" />
              </button>
            </div>
            <img src={selectedMeta.image} alt={selectedMeta.name} width={512} height={512} className="mx-auto mt-2 h-16 w-16 object-contain" />
            <p className="mt-1 text-sm font-black uppercase tracking-[.06em]" style={{ color: selectedMeta.color }}>{selectedMeta.name}</p>
            <div className="mt-3 space-y-1 text-[10px] text-slate-300">
              <div className="flex justify-between"><span className="text-slate-500">{localizeText("Preço")}</span><span className="font-bold text-white">{selected.priceTon} TON</span></div>
              <div className="flex justify-between"><span className="text-slate-500">{localizeText("Saldo TON")}</span><span className="font-bold text-amber-200">{(shop?.availableTon ?? 0).toFixed(4)}</span></div>
              <div className="flex justify-between"><span className="text-slate-500">{localizeText("Compras")}</span><span className="font-bold text-white">{used} / {limit}</span></div>
              <div className="flex justify-between"><span className="text-slate-500">{localizeText("Pagamento")}</span><span className="font-bold text-slate-200">{(shop?.availableTon ?? 0) >= selected.priceTon ? localizeText("Saldo interno") : localizeText("TON Connect")}</span></div>
            </div>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button type="button" onClick={() => setConfirmKey(null)} className="rounded-2xl border border-white/15 bg-black/60 py-2 text-[10px] font-bold uppercase tracking-[.12em] text-slate-300">
                {localizeText("Cancelar")}</button>
              <button
                type="button"
                disabled={buy.isPending || blocked}
                onClick={() => buy.mutate(selected.keyCode)}
                className="rounded-2xl py-2 text-[10px] font-black uppercase tracking-[.12em] text-black disabled:opacity-40"
                style={{ backgroundColor: selectedMeta.color }}
              >
                {buy.isPending ? '...' : localizeText("Comprar")}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
