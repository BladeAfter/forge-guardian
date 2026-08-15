import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { equipHeroItem, equipmentBonusLabel, fetchHeroEquipment, unequipHeroItem, type HeroEquipmentItem, type HeroEquipmentState } from '../heroEquipment';

const RARITY: Record<string, string> = {
  common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc',
  legendary: '#fbbf24', mythic: '#fb7185', ancestral: '#f472b6', nft_exclusive: '#fde68a',
};


const SLOTS = [
  { key: 'weapon', glyph: '⚔' },
  { key: 'armor', glyph: '🛡' },
  { key: 'ring', glyph: '💍' },
] as const;

type SlotKey = (typeof SLOTS)[number]['key'];

/**
 * Functional equipment slots. Every rule (ownership, one item per slot,
 * "already equipped elsewhere", weapon class) is enforced by the RPC — this
 * component only renders the server state it receives back.
 */
export function HeroEquipmentSlots({ telegramInitData, heroId, onState }: { telegramInitData: string; heroId: string; onState?: (state: HeroEquipmentState) => void }) {
  const t = useT();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState<SlotKey | null>(null);
  const [error, setError] = useState<string | null>(null);

  const { data, isLoading } = useQuery<HeroEquipmentState>({
    queryKey: ['hero-equipment', heroId],
    queryFn: async () => {
      const state = await fetchHeroEquipment(telegramInitData, heroId);
      onState?.(state);
      return state;
    },
    enabled: Boolean(telegramInitData && heroId),
  });

  const afterChange = (state: HeroEquipmentState) => {
    queryClient.setQueryData(['hero-equipment', heroId], state);
    onState?.(state);
    queryClient.invalidateQueries({ queryKey: ['player-heroes'] });
    queryClient.invalidateQueries({ queryKey: ['player-inventory'] });
    queryClient.invalidateQueries({ queryKey: ['hero-fusion'] });
    queryClient.invalidateQueries({ queryKey: ['market-sellable'] });
    setOpen(null);
  };

  const equip = useMutation({
    mutationFn: (instanceId: string) => equipHeroItem(telegramInitData, heroId, instanceId),
    onSuccess: afterChange,
    onError: (e: unknown) => setError(e instanceof Error ? e.message : 'Erro'),
  });
  const unequip = useMutation({
    mutationFn: (slot: SlotKey) => unequipHeroItem(telegramInitData, heroId, slot),
    onSuccess: afterChange,
    onError: (e: unknown) => setError(e instanceof Error ? e.message : 'Erro'),
  });

  const busy = equip.isPending || unequip.isPending;
  const options = (slot: SlotKey) => (data?.available ?? []).filter((item) => item.slot === slot);

  return (
    <section className="mt-3">
      <p className="mb-2 text-[10px] font-black uppercase tracking-[.24em] text-amber-300">{t('heroes.equipment')}</p>
      <div className="grid grid-cols-3 gap-2">
        {SLOTS.map((slot) => {
          const item = data?.equipped?.[slot.key] ?? null;
          const accent = RARITY[String(item?.rarity)] ?? '#fbbf24';
          return (
            <button
              key={slot.key}
              type="button"
              disabled={busy || isLoading}
              onClick={() => { setError(null); setOpen(slot.key); }}
              className={`rounded-xl border bg-black/50 p-2 text-center transition active:scale-[.98] disabled:opacity-60 ${item?.isNft ? 'nft-hero-card' : ''}`}
              style={{ borderColor: item ? accent : 'rgba(252,211,77,.28)' }}
            >
              <p className="text-[8px] font-black uppercase tracking-[.14em] text-slate-300">
                {slot.glyph} {t(`heroes.slot.${slot.key}`)}
              </p>
              <div className="mt-2 grid aspect-square w-full place-items-center overflow-hidden rounded-lg border border-white/10 bg-black/60">
                {isLoading ? <Loader2 size={14} className="animate-spin text-amber-300" />
                  : item?.image ? <img src={item.image} alt={item.name} className={`h-full w-full object-cover ${item.isNft ? 'drop-shadow-[0_0_10px_rgba(251,191,36,.55)]' : ''}`} />
                  : <span className="text-[16px] opacity-40">{slot.glyph}</span>}
              </div>
              {item ? (
                <>
                  <p className={`mt-1 truncate text-[8px] font-black uppercase ${item.isNft ? 'nft-hero-name' : 'text-white'}`}>{item.name}</p>
                  <p className="text-[7px] font-black uppercase tracking-[.1em]" style={{ color: accent }}>
                    {item.isNft ? '💎 NFT EXCLUSIVE' : `${item.rarity ? t(`rarity.${item.rarity}`) : ''} · ${t('common.levelShort')} ${item.level}`}
                  </p>
                  <p className="text-[7px] font-black text-emerald-300">{equipmentBonusLabel(item)}</p>
                </>
              ) : (
                <p className="mt-1.5 text-[8px] font-black uppercase tracking-[.12em] text-slate-400">{t('heroes.slotEmpty')}</p>
              )}
            </button>
          );
        })}

      </div>

      {data ? (
        <p className="mt-2 text-center text-[8px] font-black uppercase tracking-[.14em] text-emerald-300">
          {data.stats.equipAtk || data.stats.equipHp || data.stats.equipDef
            ? `ATK +${data.stats.equipAtk} · DEF +${data.stats.equipDef} · HP +${data.stats.equipHp}`
            : t('heroes.equipHint')}
        </p>
      ) : null}
      {error ? <p className="mt-2 rounded-lg border border-rose-400/30 bg-rose-500/10 p-2 text-[9px] font-bold text-rose-300">{error}</p> : null}

      {open ? (
        <div className="fixed inset-0 z-[120] flex items-end bg-black/80 p-3 backdrop-blur-sm" onClick={() => setOpen(null)}>
          <div className="mx-auto w-full max-w-[420px] rounded-2xl border border-amber-300/25 bg-[#090d15] p-3" onClick={(e) => e.stopPropagation()}>
            <header className="mb-2 flex items-center justify-between">
              <p className="text-[11px] font-black uppercase tracking-[.16em] text-amber-300">{t(`heroes.slot.${open}`)}</p>
              <button onClick={() => setOpen(null)} className="grid h-8 w-8 place-items-center rounded-lg border border-white/10 text-white"><X size={14} /></button>
            </header>

            {data?.equipped?.[open] ? (
              <button
                type="button"
                disabled={busy}
                onClick={() => unequip.mutate(open)}
                className="mb-2 w-full rounded-xl border border-rose-400/40 bg-rose-500/10 py-2 text-[10px] font-black uppercase tracking-[.14em] text-rose-200 disabled:opacity-60"
              >
                {t('heroes.unequip')} · {data.equipped[open]?.name}
              </button>
            ) : null}

            <div className="max-h-[45vh] space-y-2 overflow-y-auto">
              {options(open).length === 0 ? (
                <p className="rounded-xl border border-white/10 bg-black/40 p-3 text-center text-[10px] uppercase tracking-[.12em] text-slate-400">{t('heroes.noEquipment')}</p>
              ) : options(open).map((item: HeroEquipmentItem) => {
                const blocked = item.classOk === false || item.listed;
                const accent = RARITY[String(item.rarity)] ?? '#94a3b8';
                return (
                  <div key={item.instanceId} className={`flex items-center gap-2 rounded-xl border bg-black/50 p-2 ${item.isNft ? 'nft-hero-card border-amber-200/60' : 'border-white/10'}`}>
                    <div className="grid h-12 w-12 shrink-0 place-items-center overflow-hidden rounded-lg border" style={{ borderColor: accent }}>
                      {item.image ? <img src={item.image} alt={item.name} className={`h-full w-full object-cover ${item.isNft ? 'drop-shadow-[0_0_10px_rgba(251,191,36,.5)]' : ''}`} /> : <span className="text-[14px] opacity-50">⚔</span>}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className={`truncate text-[11px] font-black uppercase ${item.isNft ? 'nft-hero-name' : 'text-white'}`}>{item.name}</p>
                      <p className="text-[8px] font-black uppercase tracking-[.1em]" style={{ color: accent }}>
                        {item.isNft ? `💎 NFT EXCLUSIVE${item.serial ? ` #${String(item.serial).padStart(3, '0')}` : ''}` : (item.rarity ? t(`rarity.${item.rarity}`) : '')}{item.heroClass ? ` · ${item.heroClass.toUpperCase()}` : ''}
                      </p>
                      <p className="text-[9px] font-bold text-emerald-300">{equipmentBonusLabel(item)}</p>
                    </div>

                    {blocked ? (
                      <span className="rounded-lg border border-rose-400/40 px-2 py-1 text-[8px] font-black uppercase text-rose-300">
                        {item.listed ? t('heroes.itemListed') : t('heroes.wrongClass')}
                      </span>
                    ) : (
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => { setError(null); equip.mutate(item.instanceId); }}
                        className="rounded-lg border border-amber-200/70 bg-gradient-to-b from-amber-300 to-amber-600 px-3 py-1.5 text-[9px] font-black uppercase tracking-[.12em] text-[#2a1a04] disabled:opacity-60"
                      >
                        {busy ? '…' : t('heroes.equip')}
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      ) : null}
    </section>
  );
}
