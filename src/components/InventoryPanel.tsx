import { useLocalizedText } from '../LanguageContext';
import { memo, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Package, RefreshCw, X } from 'lucide-react';
import { toast } from 'sonner';
import { usePlayerInventory } from '../hooks';
import { openCalendarChest, openExclusiveChest, openKeyChest, openLegendChest, openResourceChest, petRequest, summonHeroWithFragments } from '../services';
import type { KeyChestOpenResult, LegendChestEquipment } from '../services';

import { getInventoryItemVisual } from '../inventoryVisuals';
import { ArsenalPanel } from './ArsenalPanel';
import { isHiddenVeteranItem } from '../retiredOfferPresentation';

import type { FragmentSummonResult, InventoryCategory, InventoryItem } from '../calendarRewards';
import { useT } from '../LanguageContext';
import { useItemName } from '../itemNames';

/** Discreet rarity borders — the inventory must stay readable, so no heavy glow. */
const RARITY_BORDER: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6',
};

/**
 * Premium Legend Chest: opens a random legendary equipment piece.
 * Season Pass rewards use the code `legendary_chest`, the shop uses `legend-chest`.
 * All of them must route to `open_legend_chest`, never to the calendar chest action.
 */
const isLegendChest = (item: InventoryItem) => ['legend-chest', 'legend_chest', 'legendary-chest', 'legendary_chest']
  .includes(String(item.itemId ?? '').toLowerCase());

const CATEGORIES: (InventoryCategory | 'all')[] = ['all', 'fragments', 'eggs', 'food', 'chests', 'equipment', 'keys', 'other'];

/**
 * Art comes from `getInventoryItemVisual` (shared asset map keyed by stable item
 * codes) so the inventory always shows the same official art as the other
 * screens and never renders a broken image.
 */
function ItemArt({ item, size }: { item: InventoryItem; size: 'slot' | 'modal' }) {
  const [broken, setBroken] = useState(false);
  const itemName = useItemName();
  const visual = getInventoryItemVisual(item);
  const cls = size === 'slot' ? 'h-full w-full' : 'mx-auto mb-2 h-20 w-20';

  if (visual.image && !broken) {
    return (
      <img
        src={visual.image}
        alt={itemName(item.name)}
        loading="lazy"
        decoding="async"
        onError={() => { setBroken(true); console.error('[INVENTORY ASSET]', { itemId: item.itemId, itemType: item.itemType, image: visual.image }); }}
        className={size === 'slot' ? 'h-full w-full object-contain p-1' : 'mx-auto mb-2 h-20 w-20 rounded-xl object-contain'}
      />
    );
  }
  const glyph = visual.glyph;
  if (glyph) return <span className={`grid place-items-center ${cls} ${size === 'slot' ? 'text-2xl' : 'text-4xl'}`} aria-hidden>{glyph}</span>;
  return <span className={`grid place-items-center ${cls} text-slate-400`}><Package size={size === 'slot' ? 18 : 28} /></span>;
}

const ItemSlot = memo(function ItemSlot({ item, onSelect }: { item: InventoryItem; onSelect: (item: InventoryItem) => void }) {
  const rarity = getInventoryItemVisual(item).rarity;
  const itemName = useItemName();
  const border = (rarity && RARITY_BORDER[rarity]) || 'rgba(255,255,255,.14)';
  return (
    <button
      onClick={() => onSelect(item)}
      className="relative aspect-square overflow-hidden rounded-lg border bg-black/60"
      style={{ borderColor: border }}
      aria-label={itemName(item.name)}
    >
      <ItemArt item={item} size="slot" />
      <span className="absolute inset-x-0 bottom-0 truncate bg-black/70 px-1 text-[7px] uppercase tracking-[.04em] text-slate-200">{itemName(item.name)}</span>
      <span className="absolute right-0.5 top-0.5 rounded bg-black/80 px-1 text-[8px] font-black text-amber-200">x{item.quantity}</span>
    </button>
  );
});

export function InventoryPanel({ telegramInitData, active, onViewFusion }: { telegramInitData: string; active: boolean; onViewFusion?: () => void }) {
  const localizeText = useLocalizedText();

  const t = useT();
  const itemName = useItemName();
  const queryClient = useQueryClient();
  const { data, isLoading, error, refetch, isFetching } = usePlayerInventory(telegramInitData, active);
  const [filter, setFilter] = useState<InventoryCategory | 'all'>('all');
  const [selected, setSelected] = useState<InventoryItem | null>(null);
  const [summoned, setSummoned] = useState<FragmentSummonResult | null>(null);
  const [arsenalOpen, setArsenalOpen] = useState(false);
  const [legendReward, setLegendReward] = useState<LegendChestEquipment | null>(null);
  const [keyChest, setKeyChest] = useState<KeyChestOpenResult | null>(null);



  const items = useMemo(() => (data?.items ?? []).filter(item => !isHiddenVeteranItem(item)), [data?.items]);
  const visible = useMemo(() => (filter === 'all' ? items : items.filter((i) => i.category === filter)), [items, filter]);

  const invalidate = (keys: string[]) => Promise.all(keys.map((key) => queryClient.invalidateQueries({ queryKey: [key] })));

  // Chests reuse the SAME server actions used by the calendar/pass screens.
  // Mythic (exclusive) chests have their own server action — opening them as a
  // regular hero chest is what used to fail.
  const [batch, setBatch] = useState<{ done: number; total: number } | null>(null);

  // Opens ONE chest using the exact same server actions used by the calendar/pass screens.
  const openOne = async (item: InventoryItem): Promise<string | null> => {
    // KEY CHEST: consumes the matching Tower key; every drop is rolled server-side.
    if (item.itemType === 'key_chest' || item.action === 'open-key-chest') {
      const payload = await openKeyChest(telegramInitData, String(item.instanceId));
      setKeyChest(payload);
      return null;
    }
    // Legend Chest: dedicated server action that always rolls a LEGENDARY equipment.
    if (isLegendChest(item)) {
      const payload = await openLegendChest(telegramInitData, String(item.instanceId));
      setLegendReward(payload.equipment);
      return null;
    }

    // FOUNDER PACK premium resource chest: its own server action (FC, fragments, tickets, chest).
    if (item.itemType === 'resource_chest' || item.action === 'open-resource-chest') {
      const payload = await openResourceChest(telegramInitData, String(item.instanceId));
      const parts = [payload.rewards.fc ? `${payload.rewards.fc.toLocaleString('pt-BR')} BERRIES` : '', payload.rewards.fragments ? `${payload.rewards.fragments} fragmentos` : '', payload.rewards.pvpTickets ? `${payload.rewards.pvpTickets} tickets PvP` : ''].filter(Boolean);
      return parts.length ? parts.join(' · ') : null;
    }
    if (item.itemType === 'exclusive_chest' || item.action === 'open-exclusive-chest') {
      const payload = await openExclusiveChest(telegramInitData, String(item.instanceId));
      return payload.reward?.name ?? payload.reward?.title ?? null;
    }
    const result = await openCalendarChest(telegramInitData, String(item.instanceId), 'shop');
    return result.hero?.name ?? null;
  };

  // Bulk open (1 / 5 / 10 / MAX): the server still validates and consumes one
  // chest per call, so we simply repeat the very same action sequentially.
  const openChest = useMutation({
    mutationFn: async ({ item, count }: { item: InventoryItem; count: number }) => {
      const total = Math.max(1, Math.min(count, item.quantity));
      const names: string[] = [];
      let opened = 0;
      setBatch({ done: 0, total });
      try {
        for (let index = 0; index < total; index += 1) {
          const name = await openOne(item);
          opened += 1;
          setBatch({ done: opened, total });
          if (name) names.push(name);
        }
      } catch (loopError) {
        if (opened === 0) throw loopError;
        toast.error(loopError instanceof Error ? loopError.message : t('inventory.openError'));
      } finally {
        setBatch(null);
      }
      return { opened, total, names };
    },
    onSuccess: async ({ opened, names }) => {
      setSelected(null);
      if (opened > 1) toast.success(t('inventory.bulkOpened', { count: opened }));
      if (names.length) toast.success(names.slice(0, 5).join(' · '));
      await invalidate(['player-inventory', 'player-heroes', 'player-equipment', 'arsenal', 'hero-fusion', 'rarity-fusion', 'pet-dashboard', 'pets', 'game-state']);
    },
    onError: (openError) => toast.error(openError instanceof Error ? openError.message : t('inventory.openError')),
  });



  // Eggs reuse the exact same hatch action as Pets → Eggs (petRequest 'hatch').
  const hatchEgg = useMutation({
    mutationFn: (item: InventoryItem) => petRequest(telegramInitData, { action: 'hatch', eggId: item.itemId, idempotencyKey: crypto.randomUUID() }),
    onSuccess: async (payload) => {
      setSelected(null);
      toast.success(payload.result?.name ? t('inventory.eggHatched', { name: payload.result.name }) : t('inventory.opened'));
      await invalidate(['player-inventory', 'pet-dashboard', 'pets', 'game-state']);
    },
    onError: (hatchError) => toast.error(hatchError instanceof Error ? hatchError.message : t('inventory.hatchError')),
  });

  // Fragments -> random common/uncommon hero. Cost, odds and the roll are server-side and idempotent.
  // Bulk summon (1 / 5 / 10 / MAX) reuses the SAME chest pattern: one server call per summon.
  const summon = useMutation({
    mutationFn: async (count: number = 1) => {
      const total = Math.max(1, count);
      const names: string[] = [];
      let done = 0;
      let last: Awaited<ReturnType<typeof summonHeroWithFragments>> | null = null;
      setBatch({ done: 0, total });
      try {
        for (let index = 0; index < total; index += 1) {
          last = await summonHeroWithFragments(telegramInitData);
          done += 1;
          setBatch({ done, total });
          const name = last?.hero?.name;
          if (name) names.push(name);
        }
      } catch (loopError) {
        if (done === 0) throw loopError;
        toast.error(loopError instanceof Error ? loopError.message : t('inventory.summonError'));
      } finally {
        setBatch(null);
      }
      return { last, done, names };
    },
    onSuccess: async ({ last, done, names }) => {
      setSelected(null);
      if (done > 1) {
        toast.success(t('inventory.bulkOpened', { count: done }));
        if (names.length) toast.success(names.slice(0, 5).join(' · '));
      } else if (last) setSummoned(last);
      await invalidate(['player-inventory', 'player-heroes', 'hero-fusion', 'rarity-fusion', 'game-state']);
    },
    onError: (summonError) => toast.error(summonError instanceof Error ? summonError.message : t('inventory.summonError')),
  });

  const busy = openChest.isPending || hatchEgg.isPending || summon.isPending;

  if (arsenalOpen) return <ArsenalPanel telegramInitData={telegramInitData} onBack={() => setArsenalOpen(false)} />;

  return (
    <section className="rounded-2xl border border-white/10 bg-black/45 p-3">
      <header className="mb-2 flex items-center justify-between gap-2">
        <div className="min-w-0">
          <p className="text-[10px] uppercase tracking-[.2em] text-slate-400">{t('inventory.subtitle')}</p>
          <p className="text-sm font-black text-amber-200">{t('inventory.count', { count: items.length })}</p>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          <button
            onClick={() => setArsenalOpen(true)}
            className="rounded-xl border border-amber-300/40 bg-amber-300/10 px-2.5 py-2 text-[9px] font-black uppercase tracking-[.14em] text-amber-200"
          >
            ⚔ {t('arsenal.button')}
          </button>
          <button onClick={() => void refetch()} aria-label={t('inventory.refresh')} className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-amber-300/25 bg-black/60 text-amber-200">
            <RefreshCw size={14} className={isFetching ? 'animate-spin' : ''} />
          </button>
        </div>
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

      {/*
        Portalled to <body>: the Heroes screen wraps tabs in a translated container,
        which would otherwise become the containing block for `fixed` and push the
        sheet off-screen — leaving only a black backdrop in the Telegram Mini App.
      */}
      {selected
        ? createPortal(
            <div className="fixed inset-0 z-[120] flex items-end justify-center bg-black/80 p-4 sm:items-center" onClick={() => !busy && setSelected(null)}>
              <div className="w-full max-w-[320px] rounded-2xl border border-amber-300/25 bg-[#080c14] p-4" onClick={(event) => event.stopPropagation()}>
                <div className="mb-2 flex items-start justify-between gap-2">
                  <b className="text-sm font-black uppercase tracking-[.08em] text-amber-200">{itemName(selected.name)}</b>
                  <button onClick={() => setSelected(null)} aria-label={t('inventory.close')} className="text-slate-400"><X size={16} /></button>
                </div>
                <ItemArt item={selected} size="modal" />
                <p className="text-[11px] text-slate-300">{t('inventory.quantity')}: <b className="text-white">{selected.quantity}</b></p>
                <p className="text-[10px] text-slate-400">{selected.category === 'eggs' || selected.itemType.includes('egg') ? localizeText("Baú Misterioso de mascotes") : selected.description}</p>
                {selected.rarity ? <p className="mt-1 text-[10px] font-black uppercase" style={{ color: RARITY_BORDER[selected.rarity] ?? '#94a3b8' }}>{selected.rarity}</p> : null}
                {(selected.itemType === 'key_chest' || selected.action === 'open-key-chest') && selected.instanceId ? (
                  <div className="mt-3 space-y-2">
                    {/* Key requirement: the chest only opens while the player owns the matching key. */}
                    <div className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/50 p-2">
                      {selected.keyImage ? <img src={selected.keyImage} alt={itemName(selected.keyName)} className="h-9 w-9 object-contain" /> : null}
                      <div className="min-w-0">
                        <p className="truncate text-[9px] font-black uppercase tracking-[.14em] text-slate-300">{itemName(selected.keyName) || selected.keyCode}</p>
                        <p className={`text-[10px] font-black ${(selected.keyQuantity ?? 0) > 0 ? 'text-emerald-300' : 'text-rose-300'}`}>x{selected.keyQuantity ?? 0}</p>
                      </div>
                    </div>
                    {(selected.keyQuantity ?? 0) > 0 ? (
                      <>
                        <div className="grid grid-cols-4 gap-1.5">
                          {[1, 5, 10, Math.min(selected.quantity, selected.keyQuantity ?? 0)].map((amount, index) => {
                            const maxOpens = Math.min(selected.quantity, selected.keyQuantity ?? 0);
                            const count = Math.min(amount, maxOpens);
                            const label = index === 3 ? `MAX (${maxOpens})` : `x${count}`;
                            return (
                              <button
                                key={index === 3 ? 'max' : amount}
                                disabled={busy || maxOpens < (index === 3 ? 1 : amount)}
                                onClick={() => openChest.mutate({ item: selected, count })}
                                className={`min-h-[38px] rounded-xl border text-[9px] font-black uppercase tracking-[.1em] disabled:opacity-40 ${index === 3 ? 'border-amber-300/60 bg-gradient-to-b from-amber-300/25 to-orange-500/15 text-amber-100' : 'border-amber-300/40 bg-amber-300/12 text-amber-200'}`}
                              >
                                {label}
                              </button>
                            );
                          })}
                        </div>
                        <p className="text-center text-[9px] font-black uppercase tracking-[.14em] text-slate-400">
                          {batch ? `${t('inventory.opening')} ${batch.done}/${batch.total}` : t('inventory.open')}
                        </p>
                      </>
                    ) : (
                      <p className="rounded-xl border border-rose-400/40 bg-rose-500/10 p-2 text-center text-[10px] font-black uppercase tracking-[.14em] text-rose-200">
                        {t('inventory.keyRequired')}
                      </p>
                    )}
                  </div>
                ) : (selected.action === 'open-chest' || selected.action === 'open-exclusive-chest' || selected.action === 'open-resource-chest' || selected.itemType === 'resource_chest' || selected.itemType === 'chest' || selected.itemType === 'exclusive_chest') && selected.instanceId ? (

                  <div className="mt-3 space-y-1.5">
                    {/* Bulk open: 1 / 5 / 10 / MAX — always limited by the real stack size. */}
                    <div className="grid grid-cols-4 gap-1.5">
                      {[1, 5, 10, selected.quantity].map((amount, index) => {
                        const count = Math.min(amount, selected.quantity);
                        const label = index === 3 ? `MAX (${selected.quantity})` : `x${count}`;
                        return (
                          <button
                            key={index === 3 ? 'max' : amount}
                            disabled={busy || selected.quantity < (index === 3 ? 1 : amount)}
                            onClick={() => openChest.mutate({ item: selected, count })}
                            className={`min-h-[38px] rounded-xl border text-[9px] font-black uppercase tracking-[.1em] disabled:opacity-40 ${index === 3 ? 'border-amber-300/60 bg-gradient-to-b from-amber-300/25 to-orange-500/15 text-amber-100' : 'border-amber-300/40 bg-amber-300/12 text-amber-200'}`}
                          >
                            {label}
                          </button>
                        );
                      })}
                    </div>
                    <p className="text-center text-[9px] font-black uppercase tracking-[.14em] text-slate-400">
                      {batch ? `${t('inventory.opening')} ${batch.done}/${batch.total}` : t('inventory.open')}
                    </p>
                  </div>

                ) : selected.itemType === 'egg' || selected.itemType === 'pet_egg' || selected.category === 'eggs' ? (
                  <button
                    disabled={busy}
                    onClick={() => hatchEgg.mutate(selected)}
                    className="mt-3 min-h-[38px] w-full rounded-xl border border-amber-300/40 bg-amber-300/15 text-[10px] font-black uppercase tracking-[.14em] text-amber-200 disabled:opacity-50"
                  >
                    {hatchEgg.isPending ? t('inventory.hatching') : t('inventory.hatch')}
                  </button>
                ) : selected.action === 'summon-hero' ? (
                  <>
                    <p className="mt-2 rounded-xl border border-white/10 bg-black/40 p-2 text-center text-[10px] font-black uppercase tracking-[.12em] text-amber-200">
                      {t('inventory.fragmentSummonHint', { count: selected.costPerUse ?? 5 })}
                    </p>
                    {/* Bulk summon: 1 / 5 / 10 / MAX, exactly like the chest system. */}
                    {(() => {
                      const cost = selected.costPerUse ?? 5;
                      const maxSummons = Math.floor(selected.quantity / Math.max(1, cost));
                      return (
                        <>
                          <div className="mt-3 grid grid-cols-4 gap-1.5">
                            {[1, 5, 10, maxSummons].map((amount, index) => {
                              const count = Math.min(amount, maxSummons);
                              const label = index === 3 ? `MAX (${maxSummons})` : `x${count}`;
                              return (
                                <button
                                  key={`summon-${index}`}
                                  disabled={busy || maxSummons < (index === 3 ? 1 : amount)}
                                  onClick={() => summon.mutate(count)}
                                  className="min-h-[34px] rounded-xl border border-amber-300/40 bg-amber-300/10 text-[9px] font-black uppercase tracking-[.1em] text-amber-200 disabled:opacity-40"
                                >
                                  {label}
                                </button>
                              );
                            })}
                          </div>
                          <button
                            disabled={busy || maxSummons < 1}
                            onClick={() => summon.mutate(1)}
                            className="mt-2 min-h-[38px] w-full rounded-xl border border-amber-300/40 bg-amber-300/15 text-[10px] font-black uppercase tracking-[.14em] text-amber-200 disabled:opacity-50"
                          >
                            {batch ? `${t('inventory.opening')} ${batch.done}/${batch.total}` : summon.isPending ? t('inventory.summoning') : t('inventory.use')}
                          </button>
                        </>
                      );
                    })()}
                  </>
                ) : selected.itemType === 'universal_fragment' ? (
                  <>
                    <p className="mt-2 rounded-xl border border-cyan-300/25 bg-cyan-300/5 p-2 text-center text-[10px] font-black uppercase tracking-[.12em] text-cyan-200">
                      {t('inventory.universalFragmentHint', { count: selected.costPerUse ?? 25 })}
                    </p>
                    {onViewFusion ? (
                      <button
                        onClick={() => { setSelected(null); onViewFusion(); }}
                        className="mt-3 min-h-[38px] w-full rounded-xl border border-cyan-300/40 bg-cyan-300/10 text-[10px] font-black uppercase tracking-[.14em] text-cyan-200"
                      >
                        {t('inventory.viewFusion')}
                      </button>
                    ) : null}
                  </>
                ) : selected.itemType === 'food' ? (
                  <p className="mt-3 text-[10px] text-slate-400">{t('inventory.useInFeed')}</p>
                ) : selected.itemType === 'equipment' ? (
                  <div className="mt-3 space-y-1 rounded-xl border border-white/10 bg-black/40 p-2 text-[10px] text-slate-300">
                    <p className="uppercase tracking-[.12em] text-slate-400">
                      {selected.slot} · {selected.kind}
                      {selected.heroClass ? ` · ${selected.heroClass}` : ''}
                    </p>
                    <p>ATK <b className="text-white">+{selected.bonusAttack ?? 0}</b> {localizeText("· DEF")}<b className="text-white">+{selected.bonusDefense ?? 0}</b> {localizeText("· HP")}<b className="text-white">+{selected.bonusHp ?? 0}</b></p>
                    <p className={selected.equipped ? 'font-black uppercase tracking-[.12em] text-amber-300' : 'font-black uppercase tracking-[.12em] text-emerald-300'}>
                      {selected.equipped ? `🔒 EQUIPPED${selected.equippedHeroName ? ` · ${selected.equippedHeroName}` : ''}` : selected.listed ? '🔒 LISTED' : 'AVAILABLE'}
                    </p>
                  </div>
                ) : null}
                <button
                  disabled={busy}
                  onClick={() => setSelected(null)}
                  className="mt-2 min-h-[34px] w-full rounded-xl border border-white/12 bg-black/50 text-[10px] font-black uppercase tracking-[.14em] text-slate-300 disabled:opacity-50"
                >
                  {t('inventory.cancel')}
                </button>
              </div>
            </div>,
            document.body,
          )
        : null}

      {/* KEY CHEST reveal: every reward was already granted server-side; this is presentation only. */}
      {keyChest
        ? createPortal(
            <div className="fixed inset-0 z-[130] grid place-items-center bg-black/88 p-4" onClick={() => setKeyChest(null)}>
              <div className="w-full max-w-[320px] rounded-2xl border border-amber-300/40 bg-[#080c14] p-4 text-center" onClick={(event) => event.stopPropagation()}>
                {keyChest.chest.image ? (
                  <img src={keyChest.chest.image} alt={itemName(keyChest.chest.name)} className="mx-auto mb-2 h-24 w-24 animate-[pulse_1.2s_ease-in-out_2] object-contain" />
                ) : null}
                <b className="block text-sm font-black uppercase tracking-[.1em] text-amber-200">{itemName(keyChest.chest.name)}</b>
                <p className="text-[9px] uppercase tracking-[.18em] text-slate-400">{keyChest.chest.subtitle}</p>
                <div className="mt-3 space-y-1.5">
                  {keyChest.rewards.map((reward, index) => (
                    <div
                      key={`${reward.type}-${index}`}
                      className={`flex items-center gap-2 rounded-xl border p-2 text-left ${reward.premium ? 'border-amber-300/60 bg-amber-300/10' : 'border-white/10 bg-black/50'}`}
                    >
                      {reward.image ? <img src={reward.image} alt={itemName(reward.title)} className="h-10 w-10 shrink-0 rounded-lg object-contain" /> : null}
                      <div className="min-w-0">
                        <p className="truncate text-[10px] font-black uppercase tracking-[.1em] text-white">{itemName(reward.name || reward.title)}</p>
                        {reward.rarity ? (
                          <p className="text-[9px] font-black uppercase tracking-[.14em]" style={{ color: RARITY_BORDER[reward.rarity] ?? '#94a3b8' }}>{reward.rarity}</p>
                        ) : null}
                      </div>
                    </div>
                  ))}
                </div>
                <button onClick={() => setKeyChest(null)} className="mt-3 min-h-[36px] w-full rounded-xl border border-white/12 bg-black/50 text-[10px] font-black uppercase tracking-[.14em] text-slate-300">
                  {t('inventory.close')}
                </button>
              </div>
            </div>,
            document.body,
          )
        : null}


      {/* Legend Chest reveal: the equipment already exists server-side (Arsenal). */}
      {legendReward
        ? createPortal(
            <div className="fixed inset-0 z-[130] grid place-items-center bg-black/85 p-4" onClick={() => setLegendReward(null)}>
              <div className="w-full max-w-[300px] rounded-2xl border border-amber-300/40 bg-[#080c14] p-4 text-center" onClick={(event) => event.stopPropagation()}>
                <p className="text-[9px] font-black uppercase tracking-[.24em] text-amber-300/80">{localizeText("BAÚ LENDÁRIO")}</p>
                {legendReward.imageUrl ? (
                  <img src={legendReward.imageUrl} alt={legendReward.name} className="mx-auto my-3 h-28 w-28 animate-[pulse_1.2s_ease-in-out_2] rounded-xl border border-amber-300/40 object-contain" />
                ) : null}
                <p className="text-[10px] font-black uppercase tracking-[.2em]" style={{ color: RARITY_BORDER[legendReward.rarity] ?? '#fbbf24' }}>{legendReward.rarity}</p>
                <b className="block text-sm font-black text-amber-200">{legendReward.name}</b>
                <p className="mt-1 text-[10px] uppercase tracking-[.12em] text-slate-400">{legendReward.slot}{legendReward.kind ? ` · ${legendReward.kind}` : ''}</p>
                <p className="mt-1 text-[10px] text-slate-300">{localizeText("ATK +")}{legendReward.bonusAttack ?? 0} {localizeText("· DEF +")}{legendReward.bonusDefense ?? 0} {localizeText("· HP +")}{legendReward.bonusHp ?? 0}</p>
                <p className="mt-2 text-[9px] font-black uppercase tracking-[.16em] text-emerald-300">{localizeText("⚔ ARSENAL")}</p>
                <button onClick={() => setLegendReward(null)} className="mt-3 min-h-[36px] w-full rounded-xl border border-white/12 bg-black/50 text-[10px] font-black uppercase tracking-[.14em] text-slate-300">
                  {t('inventory.close')}
                </button>
              </div>
            </div>,
            document.body,
          )
        : null}

      {/* Recruit-style reveal: the hero already exists server-side, this is presentation only. */}
      {summoned
        ? createPortal(
            <div className="fixed inset-0 z-[130] grid place-items-center bg-black/85 p-4" onClick={() => setSummoned(null)}>
              <div className="w-full max-w-[300px] rounded-2xl border border-amber-300/30 bg-[#080c14] p-4 text-center" onClick={(event) => event.stopPropagation()}>
                <p className="text-[9px] font-black uppercase tracking-[.24em] text-slate-400">{t('inventory.fragmentsUsed', { count: summoned.fragmentsSpent })}</p>
                {summoned.hero.imageUrl ? (
                  <img src={summoned.hero.imageUrl} alt={summoned.hero.name} className="mx-auto my-3 h-28 w-28 animate-[pulse_1.2s_ease-in-out_2] rounded-xl border border-amber-300/30 object-cover" />
                ) : null}
                <p className="text-[10px] font-black uppercase tracking-[.2em]" style={{ color: RARITY_BORDER[summoned.hero.rarity] ?? '#94a3b8' }}>{summoned.hero.rarity}</p>
                <b className="block text-sm font-black text-amber-200">{summoned.hero.name}</b>
                <p className="mt-1 text-[10px] text-slate-300">ATK {summoned.hero.finalAtk} {localizeText("· HP")}{summoned.hero.finalHp}</p>
                <p className="mt-2 text-[9px] font-black uppercase tracking-[.16em] text-emerald-300">{t('inventory.addedToCollection')}</p>
                <button onClick={() => setSummoned(null)} className="mt-3 min-h-[36px] w-full rounded-xl border border-white/12 bg-black/50 text-[10px] font-black uppercase tracking-[.14em] text-slate-300">
                  {t('inventory.close')}
                </button>
              </div>
            </div>,
            document.body,
          )
        : null}
    </section>
  );
}
