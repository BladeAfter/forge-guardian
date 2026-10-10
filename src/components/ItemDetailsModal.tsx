import { useLocalizedText } from '../LanguageContext';
import { X, Gem, Sparkles, Shield, Swords, Heart, Zap, Star, Pickaxe, Info, Crown } from 'lucide-react';
import { useMarketItemDetails } from '../hooks';
import { formatCurrency } from '../utils';
import { RARITY_COLORS, type HeroRarity } from '../heroCatalog';
import { petBuffShortLabel } from '../petLabels';
import { marketPriceLabel } from '../market';
import type { MarketItemDetails } from '../market';

type Props = {
  telegramInitData: string | null;
  /** Where the lot lives: player market listing or auction lot. */
  source: 'market' | 'auction';
  id: string | null;
  onClose: () => void;
  /** Optional purchase action. The buy flow itself stays in the parent panel. */
  onBuy?: (id: string) => void;
  buyLabel?: string;
  buyDisabled?: boolean;
};

const rarityColor = (rarity: string) => RARITY_COLORS[(rarity as HeroRarity)] ?? '#94a3b8';

const STAT_META: Record<string, { label: string; icon: typeof Swords; tone: string }> = {
  atk: { label: 'ATAQUE', icon: Swords, tone: 'text-rose-300' },
  hp: { label: 'VIDA', icon: Heart, tone: 'text-emerald-300' },
  def: { label: 'DEFESA', icon: Shield, tone: 'text-sky-300' },
  speed: { label: 'VELOCIDADE', icon: Zap, tone: 'text-amber-300' },
  critRate: { label: 'CRÍTICO %', icon: Star, tone: 'text-fuchsia-300' },
  skillPower: { label: 'PODER DE HABILIDADE', icon: Sparkles, tone: 'text-violet-300' },
  equipAtk: { label: 'ATK DO EQUIP.', icon: Swords, tone: 'text-rose-200' },
  equipDef: { label: 'DEF DO EQUIP.', icon: Shield, tone: 'text-sky-200' },
  equipHp: { label: 'HP DO EQUIP.', icon: Heart, tone: 'text-emerald-200' },
  petXp: { label: 'XP DE PET', icon: Sparkles, tone: 'text-amber-200' },
};

const BADGE_META: Record<string, { label: string; className: string }> = {
  nft_exclusive: { label: '💎 NFT EXCLUSIVE', className: 'border-cyan-300/50 bg-cyan-400/15 text-cyan-200' },
  veteran: { label: '🛡️ VETERAN', className: 'border-violet-300/50 bg-violet-400/15 text-violet-200' },
  founder: { label: '👑 FOUNDER', className: 'border-amber-300/50 bg-amber-400/15 text-amber-200' },
  pass_exclusive: { label: '🎟️ PASS EXCLUSIVE', className: 'border-emerald-300/50 bg-emerald-400/15 text-emerald-200' },
};

const asRecord = (value: unknown): Record<string, unknown> => (value && typeof value === 'object' ? value as Record<string, unknown> : {});
const textOf = (value: unknown) => (typeof value === 'string' && value.trim() ? value.trim() : null);
const numberOf = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? value : null);

/** Skills/passives/buffs arrive as free-form JSON from the catalog — render defensively. */
function EntryList({ title, icon: Icon, entries }: { title: string; icon: typeof Sparkles; entries: unknown[] }) {
  const rows = entries.map((raw) => {
    if (typeof raw === 'string') return { name: raw, description: null as string | null, value: null as number | null };
    const record = asRecord(raw);
    const name = textOf(record.name) ?? textOf(record.label) ?? textOf(record.title) ?? textOf(record.key) ?? textOf(record.type);
    const description = textOf(record.description) ?? textOf(record.effect) ?? textOf(record.detail) ?? textOf(record.text);
    const value = numberOf(record.value) ?? numberOf(record.percent) ?? numberOf(record.amount);
    if (!name && !description) return null;
    return { name: name ?? '—', description, value };
  }).filter(Boolean) as Array<{ name: string; description: string | null; value: number | null }>;

  if (!rows.length) return null;
  return (
    <section className="rounded-2xl border border-white/10 bg-white/[.03] p-2.5">
      <p className="mb-2 flex items-center gap-1.5 text-[9px] font-black uppercase tracking-[0.16em] text-slate-300"><Icon className="h-3.5 w-3.5 text-amber-300" />{title}</p>
      <div className="space-y-1.5">
        {rows.map((row, index) => (
          <div key={`${row.name}-${index}`} className="rounded-xl border border-white/8 bg-black/35 px-2.5 py-2">
            <div className="flex items-start justify-between gap-2">
              <p className="text-[10px] font-black uppercase tracking-[0.08em] text-slate-100">{row.name}</p>
              {row.value !== null ? <p className="shrink-0 text-[10px] font-black text-amber-300">+{formatCurrency(row.value)}</p> : null}
            </div>
            {row.description ? <p className="mt-0.5 text-[9px] leading-relaxed text-slate-400">{row.description}</p> : null}
          </div>
        ))}
      </div>
    </section>
  );
}

function BuffList({ title, buffs }: { title: string; buffs: unknown[] }) {
  const rows = buffs.map((raw) => {
    const record = asRecord(raw);
    const key = textOf(record.key) ?? textOf(record.buff) ?? textOf(record.type) ?? (typeof raw === 'string' ? raw : null);
    const value = numberOf(record.value) ?? numberOf(record.percent) ?? numberOf(record.amount);
    if (!key) return null;
    return { key, value };
  }).filter(Boolean) as Array<{ key: string; value: number | null }>;
  if (!rows.length) return null;
  return (
    <section className="rounded-2xl border border-white/10 bg-white/[.03] p-2.5">
      <p className="mb-2 flex items-center gap-1.5 text-[9px] font-black uppercase tracking-[0.16em] text-slate-300"><Sparkles className="h-3.5 w-3.5 text-fuchsia-300" />{title}</p>
      <div className="grid grid-cols-2 gap-1.5">
        {rows.map((row, index) => (
          <div key={`${row.key}-${index}`} className="rounded-xl border border-white/8 bg-black/35 px-2 py-1.5">
            <p className="truncate text-[8px] font-bold uppercase tracking-[0.1em] text-slate-400">{petBuffShortLabel(row.key) || row.key.replace(/_/g, ' ')}</p>
            {row.value !== null ? <p className="text-[11px] font-black text-emerald-300">+{Number(row.value).toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%</p> : null}
          </div>
        ))}
      </div>
    </section>
  );
}

function StatGrid({ item }: { item: MarketItemDetails }) {
  const stats = Object.entries(item.stats ?? {}).filter(([, value]) => typeof value === 'number' && Number.isFinite(value) && value !== 0);
  if (!stats.length) return null;
  return (
    <section className="grid grid-cols-2 gap-1.5">
      {stats.map(([key, value]) => {
        const meta = STAT_META[key] ?? { label: key.replace(/([A-Z])/g, ' $1').toUpperCase(), icon: Info, tone: 'text-slate-300' };
        const Icon = meta.icon;
        return (
          <div key={key} className="rounded-xl border border-white/10 bg-black/40 px-2.5 py-2">
            <p className="flex items-center gap-1 text-[8px] font-bold uppercase tracking-[0.1em] text-slate-400"><Icon className={`h-3 w-3 ${meta.tone}`} />{meta.label}</p>
            <p className="text-[13px] font-black text-slate-100">{key === 'critRate' ? `${Number(value).toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%` : formatCurrency(Number(value))}</p>
          </div>
        );
      })}
    </section>
  );
}

/**
 * Premium read-only preview of a marketplace / auction lot. Every attribute comes
 * from the backend instance — prices, ownership and the purchase flow are untouched.
 */
export function ItemDetailsModal({ telegramInitData, source, id, onClose, onBuy, buyLabel, buyDisabled }: Props) {
  const localizeText = useLocalizedText();

  const details = useMarketItemDetails(telegramInitData, source, id);
  if (!id) return null;

  const item = details.data?.item;
  const listing = details.data?.listing;
  const color = rarityColor(item?.rarity ?? 'common');
  const badges = (item?.badges ?? []).filter((badge) => BADGE_META[badge]);

  return (
    <div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/80 backdrop-blur-sm" onClick={onClose}>
      <div
        onClick={(event) => event.stopPropagation()}
        className="max-h-[92%] w-full max-w-[460px] overflow-y-auto rounded-t-[1.75rem] border-t bg-[#080d18] pb-[max(1.5rem,env(safe-area-inset-bottom))]"
        style={{ borderColor: `${color}66` }}
      >
        <div className="sticky top-0 z-10 flex items-center justify-between gap-2 border-b border-white/10 bg-[#080d18]/95 px-3 py-2.5 backdrop-blur">
          <p className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-slate-300">
            <Info className="h-3.5 w-3.5 text-amber-300" />{source === 'auction' ? localizeText("Detalhes do lote") : localizeText("Detalhes do item")}
          </p>
          <button onClick={onClose} className="grid h-8 w-8 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
        </div>

        {details.isLoading ? (
          <div className="animate-pulse space-y-3 p-3">
            <div className="h-40 w-full rounded-2xl bg-white/10" />
            <div className="h-3 w-1/2 rounded bg-white/10" />
            <div className="h-20 w-full rounded-2xl bg-white/10" />
          </div>
        ) : details.isError || !item || !listing ? (
          <div className="p-6 text-center">
            <p className="text-[11px] text-slate-400">{localizeText("Não foi possível carregar os detalhes deste item.")}</p>
            <button onClick={() => void details.refetch()} className="mt-3 rounded-lg border border-amber-300/40 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.12em] text-amber-200">{localizeText("Tentar novamente")}</button>
          </div>
        ) : (
          <div className="space-y-3 p-3">
            <div className="overflow-hidden rounded-2xl border-2" style={{ borderColor: color }}>
              {item.image ? (
                <img src={item.image} alt={item.name} loading="lazy" className="h-44 w-full object-cover" />
              ) : (
                <div className="grid h-44 w-full place-items-center bg-white/[.03]"><Gem className="h-9 w-9 text-slate-600" /></div>
              )}
              <div className="bg-gradient-to-b from-black/60 to-black/85 px-3 py-2.5">
                <p className="text-[15px] font-black leading-tight" style={{ color }}>{item.name}</p>
                <p className="mt-0.5 text-[9px] font-bold uppercase tracking-[0.14em] text-slate-400">
                  {(item.rarity ?? '').toUpperCase()}
                  {item.level ? ` · NÍVEL ${item.level}${item.maxLevel ? `/${item.maxLevel}` : ''}` : ''}
                  {item.evolutionLabel ? ` · ${item.evolutionLabel}` : ''}
                </p>
                <div className="mt-1.5 flex flex-wrap gap-1">
                  {badges.map((badge) => (
                    <span key={badge} className={`rounded-md border px-1.5 py-0.5 text-[8px] font-black tracking-[0.08em] ${BADGE_META[badge].className}`}>{BADGE_META[badge].label}</span>
                  ))}
                  {item.heroClass ? <span className="rounded-md border border-white/15 px-1.5 py-0.5 text-[8px] font-black uppercase tracking-[0.08em] text-slate-300">{item.heroClass}</span> : null}
                  {item.slot ? <span className="rounded-md border border-white/15 px-1.5 py-0.5 text-[8px] font-black uppercase tracking-[0.08em] text-slate-300">{item.slot}</span> : null}
                  {item.species ? <span className="rounded-md border border-white/15 px-1.5 py-0.5 text-[8px] font-black uppercase tracking-[0.08em] text-slate-300">{item.species}</span> : null}
                  {item.fusionLevel ? <span className="rounded-md border border-orange-300/40 bg-orange-400/10 px-1.5 py-0.5 text-[8px] font-black uppercase tracking-[0.08em] text-orange-200">{localizeText("FUSÃO +")}{item.fusionLevel}</span> : null}
                </div>
              </div>
            </div>

            {item.description ? <p className="rounded-2xl border border-white/8 bg-white/[.02] p-2.5 text-[10px] leading-relaxed text-slate-400">{item.description}</p> : null}

            {item.power ? (
              <div className="flex items-center justify-between rounded-2xl border border-amber-300/25 bg-amber-400/[.07] px-3 py-2">
                <p className="flex items-center gap-1.5 text-[9px] font-black uppercase tracking-[0.16em] text-amber-200"><Crown className="h-3.5 w-3.5" />{localizeText("Poder de combate")}</p>
                <p className="text-[14px] font-black text-amber-200">{formatCurrency(Number(item.power))}</p>
              </div>
            ) : null}

            <StatGrid item={item} />

            {item.primaryBuffKey ? (
              <div className="rounded-2xl border border-fuchsia-300/25 bg-fuchsia-400/[.07] px-3 py-2">
                <p className="text-[8px] font-black uppercase tracking-[0.16em] text-fuchsia-200">{localizeText(" Buff principal")}</p>
                <p className="text-[12px] font-black text-slate-100">
                  {petBuffShortLabel(item.primaryBuffKey) || item.primaryBuffKey.replace(/_/g, ' ')}
                  {item.primaryBuffValue !== null && item.primaryBuffValue !== undefined ? ` +${Number(item.primaryBuffValue).toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%` : ''}
                </p>
              </div>
            ) : null}

            <BuffList title={localizeText("Buffs secundários")} buffs={(item.secondaryBuffs ?? item.buffs ?? []) as unknown[]} />
            <EntryList title={localizeText("Habilidades")} icon={Swords} entries={[...(item.skills ?? []), ...(item.activeSkill ? [item.activeSkill] : [])] as unknown[]} />
            <EntryList title={localizeText("Passivas")} icon={Shield} entries={(item.passives ?? []) as unknown[]} />


            {item.nft ? (
              <section className="rounded-2xl border border-white/10 bg-white/[.03] px-3 py-2">
                <p className="text-[9px] font-black uppercase tracking-[0.16em] text-slate-300">{localizeText("Certificado NFT")}</p>
                <p className="mt-0.5 text-[10px] text-slate-400">
                  {item.nft.serial ? <>{localizeText("Série")}<span className="font-black text-slate-100">#{item.nft.serial}</span></> : null}
                  {item.nft.supply ? <> {localizeText("· Supply")}<span className="font-black text-slate-100">{item.nft.supply}</span></> : null}
                </p>
              </section>
            ) : null}

            <section className="rounded-2xl border border-white/10 bg-black/40 px-3 py-2.5">
              <div className="flex items-center justify-between">
                <p className="text-[8px] font-black uppercase tracking-[0.16em] text-slate-400">{source === 'auction' ? localizeText("Lance atual") : localizeText("Preço")}</p>
                <p className={`text-[15px] font-black ${listing.currency === 'TON' ? 'text-sky-300' : 'text-amber-300'}`}>
                  {marketPriceLabel({ currency: listing.currency, priceFc: Number(listing.priceFc ?? 0), priceTon: Number(listing.priceTon ?? 0) })}
                </p>
              </div>
              <p className="mt-1 text-[9px] text-slate-500">{localizeText("Vendedor")}<span className="text-slate-300">{listing.seller ?? '—'}</span>{Number(listing.quantity ?? 1) > 1 ? ` · x${listing.quantity}` : ''}</p>
              {source === 'auction' && listing.bidCount !== null && listing.bidCount !== undefined ? (
                <p className="mt-0.5 text-[9px] text-slate-500">{listing.bidCount} {localizeText("lance(s)")}{listing.endsAt ? ` · encerra ${new Date(listing.endsAt).toLocaleString('pt-BR')}` : ''}</p>
              ) : null}
              {listing.mine ? (
                <p className="mt-2 rounded-lg border border-white/10 py-1.5 text-center text-[9px] font-black uppercase tracking-[0.12em] text-slate-400">{localizeText("Seu anúncio")}</p>
              ) : onBuy ? (
                <button
                  disabled={buyDisabled || listing.sold}
                  onClick={() => onBuy(listing.id)}
                  className={`mt-2 w-full rounded-xl border py-2.5 text-[11px] font-black uppercase tracking-[0.14em] disabled:opacity-50 ${listing.currency === 'TON' ? 'border-sky-300/50 bg-sky-400/15 text-sky-200' : 'border-amber-300/50 bg-amber-400/15 text-amber-200'}`}
                >
                  {listing.sold ? localizeText("Indisponível") : (buyLabel ?? (source === 'auction' ? 'Dar lance' : 'Comprar'))}
                </button>
              ) : null}
            </section>
          </div>
        )}
      </div>
    </div>
  );
}
