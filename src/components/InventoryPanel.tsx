import { memo, useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Package, RefreshCw, X } from 'lucide-react';
import { toast } from 'sonner';
import { usePlayerInventory } from '../hooks';
import { openCalendarChest } from '../services';
import type { InventoryCategory, InventoryItem } from '../calendarRewards';
import { useT } from '../LanguageContext';

/** Discreet rarity borders — the inventory must stay readable, so no heavy glow. */
const RARITY_BORDER: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6',
};

const CATEGORIES: (InventoryCategory | 'all')[] = ['all', 'fragments', 'eggs', 'food', 'chests', 'equipment', 'other'];

const ItemSlot = memo(function ItemSlot({ item, onSelect }: { item: InventoryItem; onSelect: (item: InventoryItem) => void }) {
  const border = (item.rarity && RARITY_BORDER[item.rarity]) || 'rgba(255,255,255,.14)';
  return (
    <button
      onClick={() => onSelect(item)}
      className="relative aspect-square overflow-hidden rounded-lg border bg-black/60"
      style={{ borderColor: border }}
      aria-label={item.name}
    >
      {item.image ? (
        <img src={item.image} alt={item.name} loading="lazy" decoding="async" className="h-full w-full object-cover" />
      ) : (
        <span className="grid h-full w-full place-items-center text-slate-400"><Package size={18} /></span>
      )}
      <span className="absolute inset-x-0 bottom-0 truncate bg-black/70 px-1 text-[7px] uppercase tracking-[.04em] text-slate-200">{item.name}</span>
      <span className="absolute right-0.5 top-0.5 rounded bg-black/80 px-1 text-[8px] font-black text-amber-200">x{item.quantity}</span>
    </button>
  );
});

export function InventoryPanel({ telegramInitData, active }: { telegramInitData: string; active: boolean }) {
  const t = useT();
  const queryClient = useQueryClient();
  const { data, isLoading, error, refetch, isFetching } = usePlayerInventory(telegramInitData, active);
  const [filter, setFilter] = useState<InventoryCategory | 'all'>('all');
  const [selected, setSelected] = useState<InventoryItem | null>(null);

  const items = data?.items ?? [];
  const visible = useMemo(() => (filter === 'all' ? items : items.filter((i) => i.category === filter)), [items, filter]);

  // Chests reuse the SAME server action used by the calendar screen; no second opening function exists.
  const openChest = useMutation({
    mutationFn: (item: InventoryItem) => openCalendarChest(telegramInitData, String(item.instanceId), 'shop'),
    onSuccess: async (result) => {
      setSelected(null);
      toast.success(result.hero?.name ?? t('inventory.opened'));
      await Promise.all(['player-inventory', 'player-heroes', 'hero-fusion', 'rarity-fusion', 'game-state'].map((key) =>
        queryClient.invalidateQueries({ queryKey: [key] })));
    },
    onError: (openError) => toast.error(openError instanceof Error ? openError.message : t('inventory.openError')),
  });

  return (
    <section className="rounded-2xl border border-white/10 bg-black/45 p-3">
      <header className="mb-2 flex items-center justify-between gap-2">
        <div className="min-w-0">
          <p className="text-[10px] uppercase tracking-[.2em] text-slate-400">{t('inventory.subtitle')}</p>
          <p className="text-sm font-black text-amber-200">{t('inventory.count', { count: items.length })}</p>
        </div>
        <button onClick={() => void refetch()} aria-label={t('inventory.refresh')} className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-amber-300/25 bg-black/60 text-amber-200">
          <RefreshCw size={14} className={isFetching ? 'animate-spin' : ''} />
        </button>
      </header>

      <div className="-mx-1 mb-3 flex gap-1.5 overflow-x-auto px-1 pb-1">
        {CATEGORIES.map((key) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            className={`shrink-0 rounded-lg border px-2.5 py-1 text-[9px] font-black uppercase tracking-[.12em] ${filter === key ? 'border-amber-300/60 bg-amber-300/15 text-amber-200' : 'border-white/12 bg-black/50 text-slate-400'}`}
          >
            {t(`inventory.cat.${key}`)}
          </button>
        ))}
      </div>

      {isLoading && !data ? (
        <p className="py-16 text-center text-sm text-slate-300">{t('inventory.loading')}</p>
      ) : error ? (
        <p className="py-16 text-center text-sm text-slate-300">{t('inventory.loadError')}</p>
      ) : visible.length === 0 ? (
        <p className="py-16 text-center text-sm text-slate-300">{t('inventory.empty')}</p>
      ) : (
        <div className="grid grid-cols-4 gap-1.5 min-[380px]:grid-cols-5">
          {visible.map((item) => <ItemSlot key={item.key} item={item} onSelect={setSelected} />)}
        </div>
      )}

      {selected ? (
        <div className="fixed inset-0 z-[95] grid place-items-center bg-black/80 p-4" onClick={() => setSelected(null)}>
          <div className="w-full max-w-[300px] rounded-2xl border border-amber-300/25 bg-[#080c14] p-4" onClick={(event) => event.stopPropagation()}>
            <div className="mb-2 flex items-start justify-between gap-2">
              <b className="text-sm font-black uppercase tracking-[.08em] text-amber-200">{selected.name}</b>
              <button onClick={() => setSelected(null)} aria-label={t('inventory.close')} className="text-slate-400"><X size={16} /></button>
            </div>
            {selected.image ? <img src={selected.image} alt={selected.name} className="mx-auto mb-2 h-20 w-20 rounded-xl object-cover" /> : null}
            <p className="text-[11px] text-slate-300">{t('inventory.quantity')}: <b className="text-white">{selected.quantity}</b></p>
            <p className="text-[10px] text-slate-400">{selected.description}</p>
            {selected.rarity ? <p className="mt-1 text-[10px] font-black uppercase" style={{ color: RARITY_BORDER[selected.rarity] ?? '#94a3b8' }}>{selected.rarity}</p> : null}
            {selected.itemType === 'chest' && selected.instanceId ? (
              <button
                disabled={openChest.isPending}
                onClick={() => openChest.mutate(selected)}
                className="mt-3 min-h-[36px] w-full rounded-xl border border-amber-300/40 bg-amber-300/15 text-[10px] font-black uppercase tracking-[.14em] text-amber-200 disabled:opacity-50"
              >
                {openChest.isPending ? t('inventory.opening') : t('inventory.open')}
              </button>
            ) : selected.itemType === 'egg' ? (
              <p className="mt-3 text-[10px] text-slate-400">{t('inventory.useInPets')}</p>
            ) : selected.itemType === 'food' ? (
              <p className="mt-3 text-[10px] text-slate-400">{t('inventory.useInFeed')}</p>
            ) : null}
          </div>
        </div>
      ) : null}
    </section>
  );
}
