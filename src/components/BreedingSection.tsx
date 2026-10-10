import { useLocalizedText } from '../LanguageContext';
import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2, Search } from 'lucide-react';
import {
  claimSubNftMining,
  createBreedingRequest,
  fetchBreedingState,
  payBreedingShare,
  respondBreedingRequest,
  searchBreedingPartners,
} from '../services';
import { useT } from '../LanguageContext';
import { STAGE_LABEL, countdown, type BreedingNft, type PartnerNft, type SubNft } from '../breeding';

const fmtTon = (value: number) => `${Number(value ?? 0).toFixed(2)} TON`;

/**
 * 🧬 BREEDING — UNIQUE NFT × UNIQUE NFT ➜ SUB-NFT.
 * Nothing here decides costs or eligibility: the backend returns the next cost,
 * the breed counter (owned by the NFT instance) and the block reason for each unit.
 */
export default function BreedingSection({ initData }: { initData: string }) {
  const localizeText = useLocalizedText();

  const t = useT();
  const client = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [partners, setPartners] = useState<PartnerNft[] | null>(null);
  const [feedback, setFeedback] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);

  const state = useQuery({
    queryKey: ['breeding-state'],
    queryFn: () => fetchBreedingState(initData),
    refetchInterval: 30_000,
  });

  const refresh = () => {
    void client.invalidateQueries({ queryKey: ['breeding-state'] });
    void client.invalidateQueries({ queryKey: ['pets'] });
    void client.invalidateQueries({ queryKey: ['expeditions'] });
  };

  const search = useMutation({
    mutationFn: () => searchBreedingPartners(initData, query.trim()),
    onSuccess: (rows) => { setPartners(rows); setFeedback(rows.length ? null : { tone: 'bad', text: 'Nenhum NFT disponível encontrado.' }); },
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const request = useMutation({
    mutationFn: (partnerNftId: string) => createBreedingRequest(initData, String(selected), partnerNftId),
    onSuccess: (result) => {
      setPartners(null);
      setFeedback({ tone: 'ok', text: result.selfBreed ? 'Breeding criado. Pague as duas partes para gerar os ovos.' : 'BREEDING REQUEST enviado. Aguardando o parceiro.' });
      refresh();
    },
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const pay = useMutation({
    mutationFn: (requestId: string) => payBreedingShare(initData, requestId, crypto.randomUUID()),
    onSuccess: (result) => {
      setFeedback({ tone: 'ok', text: result.status === 'completed' ? 'Breeding concluído! Cada dono recebeu 1 Sub-NFT Egg.' : 'Sua parte foi paga. Aguardando o outro proprietário.' });
      refresh();
    },
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const respond = useMutation({
    mutationFn: (input: { requestId: string; accept: boolean }) => respondBreedingRequest(initData, input.requestId, input.accept),
    onSuccess: () => refresh(),
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const claim = useMutation({
    mutationFn: () => claimSubNftMining(initData),
    onSuccess: (result) => { setFeedback({ tone: 'ok', text: t('breeding.claimed', { amount: fmtTon(result.claimedTon) }) }); refresh(); },
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const data = state.data;
  const chosen = useMemo(() => data?.myNfts.find((nft) => nft.nftId === selected) ?? null, [data, selected]);
  const busy = request.isPending || pay.isPending || respond.isPending || claim.isPending;

  if (state.isLoading) {
    return <div className="grid h-40 place-items-center"><Loader2 className="h-6 w-6 animate-spin text-amber-300" /></div>;
  }
  if (state.isError) {
    return <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 p-4 text-center text-[11px] text-rose-200">{(state.error as Error).message}</p>;
  }
  if (!data) return null;

  return (
    <div className="space-y-3 pb-6">
      {feedback ? (
        <p className={`rounded-2xl border p-3 text-center text-[11px] font-bold ${feedback.tone === 'ok' ? 'border-emerald-400/30 bg-emerald-950/40 text-emerald-200' : 'border-rose-400/30 bg-rose-950/40 text-rose-200'}`}>
          {feedback.text}
        </p>
      ) : null}

      <section className="rounded-2xl border border-fuchsia-400/20 bg-black/60 p-3">
        <p className="text-[10px] font-black uppercase tracking-[.26em] text-fuchsia-200">{t('breeding.title')}</p>
        <p className="mt-1 text-[10px] leading-relaxed text-slate-400">
          {t('breeding.intro', { max: data.settings.maxBreeds, days: data.settings.cooldownDays, costs: data.settings.costs.map((cost) => `${cost}`).join(' / ') })}
        </p>
        <p className="mt-2 text-[10px] text-slate-300">{t('breeding.balance')} <span className="font-black text-amber-200">{fmtTon(data.tonBalance)}</span></p>
      </section>

      <section className="rounded-2xl border border-white/10 bg-black/50 p-3">
        <p className="text-[10px] font-black uppercase tracking-[.26em] text-slate-300">{t('breeding.yourUniqueNfts')}</p>
        {data.myNfts.length === 0 ? (
          <p className="mt-2 text-[11px] text-slate-500">{t('breeding.noneOwned')}</p>
        ) : (
          <div className="mt-2 grid grid-cols-2 gap-2">
            {data.myNfts.map((nft) => (
              <ParentCard key={nft.nftId} nft={nft} active={selected === nft.nftId} onSelect={() => { setSelected(nft.nftId); setPartners(null); }} />
            ))}
          </div>
        )}
      </section>

      {chosen && !chosen.blockReason ? (
        <section className="rounded-2xl border border-amber-300/20 bg-black/60 p-3">
          <p className="text-[10px] font-black uppercase tracking-[.26em] text-amber-200">{t('breeding.findPartner')}</p>
          <p className="mt-1 text-[10px] text-slate-400">{t('breeding.searchHint')}</p>
          <div className="mt-2 flex gap-2">
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={localizeText("@username / 8118569391")}
              className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/60 px-3 py-2 text-[11px] outline-none"
            />
            <button type="button" disabled={search.isPending} onClick={() => search.mutate()} className="grid h-9 w-10 place-items-center rounded-xl bg-amber-400 text-black">
              {search.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
            </button>
          </div>

          <div className="mt-3 space-y-2">
            {(data.myNfts.filter((nft) => nft.nftId !== chosen.nftId && !nft.blockReason)).map((nft) => (
              <PartnerRow
                key={nft.nftId}
                title={`${nft.name} #${nft.serial}`}
                subtitle={`${t('breeding.yourNft')} · breeding ${nft.breedCount}/${nft.maxBreeds}`}
                cost={nft.nextCost}
                image={nft.image}
                disabled={busy}
                onPick={() => request.mutate(nft.nftId)}
              />
            ))}
            {(partners ?? []).map((nft) => (
              <PartnerRow
                key={nft.nftId}
                title={`${nft.name} #${nft.serial}`}
                subtitle={`${nft.ownerName || nft.ownerUsername || nft.ownerTelegramId} · breeding ${nft.breedCount}/${data.settings.maxBreeds}`}
                cost={nft.nextCost}
                image={nft.image}
                disabled={busy}
                onPick={() => request.mutate(nft.nftId)}
              />
            ))}
          </div>
        </section>
      ) : null}

      {data.incoming.length ? (
        <section className="space-y-2">
          <p className="text-[10px] font-black uppercase tracking-[.26em] text-emerald-200">{t('breeding.requests')}</p>
          {data.incoming.map((row) => (
            <div key={row.requestId} className="rounded-2xl border border-emerald-400/20 bg-black/60 p-3">
              <p className="text-[11px] text-slate-200">
                <span className="font-black text-emerald-200">@{row.fromUsername || row.fromName || 'Player'}</span> {t('breeding.wantsToBreed')}{' '}
                {row.partnerNft?.name} #{row.partnerNft?.serial} {t('breeding.with')} {row.yourNft?.name} #{row.yourNft?.serial}
              </p>
              <p className="mt-1 text-[10px] text-slate-400">{t('breeding.yourCost')} <span className="font-black text-amber-200">{fmtTon(row.yourCost)}</span> · {t('breeding.reward')} · {t('breeding.expiresIn')} {countdown(row.expiresAt)}</p>
              {row.status === 'pending' ? (
                <div className="mt-2 grid grid-cols-2 gap-2">
                  <button type="button" disabled={busy} onClick={() => respond.mutate({ requestId: row.requestId, accept: true })} className="rounded-xl bg-emerald-500 py-2 text-[10px] font-black uppercase text-black">{t('breeding.accept')}</button>
                  <button type="button" disabled={busy} onClick={() => respond.mutate({ requestId: row.requestId, accept: false })} className="rounded-xl bg-white/10 py-2 text-[10px] font-black uppercase text-slate-300">{t('breeding.decline')}</button>
                </div>
              ) : (
                <button type="button" disabled={busy || row.paidYou} onClick={() => pay.mutate(row.requestId)} className="mt-2 w-full rounded-xl bg-amber-400 py-2 text-[10px] font-black uppercase text-black disabled:opacity-50">
                  {row.paidYou ? t('breeding.paidWaiting') : `${t('breeding.pay')} ${fmtTon(row.yourCost)}`}
                </button>
              )}
            </div>
          ))}
        </section>
      ) : null}

      {data.outgoing.length ? (
        <section className="space-y-2">
          <p className="text-[10px] font-black uppercase tracking-[.26em] text-slate-300">{t('breeding.yourRequests')}</p>
          {data.outgoing.map((row) => (
            <div key={row.requestId} className="rounded-2xl border border-white/10 bg-black/60 p-3">
              <p className="text-[11px] text-slate-200">
                {row.yourNft?.name} #{row.yourNft?.serial} + {row.partnerNft?.name} #{row.partnerNft?.serial}
                {row.selfBreed ? ` · ${t('breeding.selfBreed')}` : ` · ${row.partnerName || t('breeding.partner')}`}
              </p>
              <p className="mt-1 text-[10px] text-slate-400">
                {row.selfBreed
                  ? `${t('breeding.total')} ${fmtTon((row.yourCost || 0) + (row.partnerCost || 0))}`
                  : `${t('breeding.you')} ${fmtTon(row.yourCost)} ${row.paidYou ? `(${t('breeding.paid')})` : ''} · ${t('breeding.partnerLabel')} ${row.paidPartner ? t('breeding.paid') : t('breeding.pending')}`}
                {' '}· {t('breeding.expiresIn')} {countdown(row.expiresAt)}
              </p>
              <button type="button" disabled={busy || (row.paidYou && !row.selfBreed)} onClick={() => pay.mutate(row.requestId)} className="mt-2 w-full rounded-xl bg-amber-400 py-2 text-[10px] font-black uppercase text-black disabled:opacity-50">
                {row.selfBreed ? t('breeding.payBothParts') : row.paidYou ? t('breeding.paidWaiting') : `${t('breeding.pay')} ${fmtTon(row.yourCost)}`}
              </button>
            </div>
          ))}
        </section>
      ) : null}

      <section className="rounded-2xl border border-violet-400/20 bg-black/60 p-3">
        <div className="flex items-center justify-between gap-2">
          <p className="text-[10px] font-black uppercase tracking-[.26em] text-violet-200">{t('breeding.yourSubNfts')}</p>
          <button type="button" disabled={busy || data.unclaimedTon < data.settings.minClaimTon} onClick={() => claim.mutate()} className="rounded-xl bg-violet-500 px-3 py-1.5 text-[9px] font-black uppercase text-black disabled:opacity-40">
            {t('breeding.claimLabel').toUpperCase()} {fmtTon(data.unclaimedTon)}
          </button>
        </div>
        {data.subNfts.length === 0 ? (
          <p className="mt-2 text-[11px] text-slate-500">{t('breeding.noDescendants')}</p>
        ) : (
          <div className="mt-2 space-y-2">{data.subNfts.map((sub) => <SubNftCard key={sub.id} sub={sub} />)}</div>
        )}
      </section>
    </div>
  );
}

function ParentCard({ nft, active, onSelect }: { nft: BreedingNft; active: boolean; onSelect: () => void }) {
  const t = useT();
  const blocked = Boolean(nft.blockReason);
  const label = nft.blockReason === 'MAX_BREEDING_REACHED' ? t('breeding.maxReached')
    : nft.blockReason === 'BREEDING_COOLDOWN' ? `${t('breeding.cooldown')} ${countdown(nft.cooldownUntil)}`
    : nft.blockReason === 'NFT_IN_BREEDING' ? t('breeding.inBreeding')
    : nft.blockReason === 'NFT_LOCKED' ? t('breeding.locked') : null;
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`rounded-2xl border p-2 text-left transition ${active ? 'border-amber-300 bg-amber-400/10' : 'border-white/10 bg-black/50'}`}
    >
      {nft.image ? <img src={nft.image} alt={nft.name} loading="lazy" className="mx-auto h-16 w-16 rounded-xl object-cover" /> : null}
      <p className="mt-1 truncate text-[11px] font-black text-slate-100">{nft.name} #{nft.serial}</p>
      <p className="text-[9px] uppercase tracking-[.2em] text-slate-500">{nft.element}</p>
      <p className="mt-1 text-[10px] text-slate-300">{t('breeding.breedingCount')} <span className="font-black text-amber-200">{nft.breedCount} / {nft.maxBreeds}</span></p>
      <p className={`mt-1 text-[9px] font-black uppercase ${blocked ? 'text-rose-300' : 'text-emerald-300'}`}>
        {label ?? `${t('breeding.next')} ${fmtTon(nft.nextCost)}`}
      </p>
    </button>
  );
}

function PartnerRow({ title, subtitle, cost, image, disabled, onPick }: { title: string; subtitle: string; cost: number; image: string | null; disabled: boolean; onPick: () => void }) {
  const t = useT();
  return (
    <div className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/40 p-2">
      {image ? <img src={image} alt={title} loading="lazy" className="h-10 w-10 rounded-lg object-cover" /> : null}
      <div className="min-w-0 flex-1">
        <p className="truncate text-[11px] font-black text-slate-100">{title}</p>
        <p className="truncate text-[9px] text-slate-400">{subtitle}</p>
      </div>
      <button type="button" disabled={disabled} onClick={onPick} className="rounded-lg bg-fuchsia-500 px-2 py-1.5 text-[9px] font-black uppercase text-black disabled:opacity-40">
        {t('breeding.breed').toUpperCase()} {fmtTon(cost)}
      </button>
    </div>
  );
}

function SubNftCard({ sub }: { sub: SubNft }) {
  const t = useT();
  const progress = sub.capTon > 0 ? Math.min(100, (sub.minedTon / sub.capTon) * 100) : 0;
  return (
    <div className="rounded-2xl border border-violet-400/20 bg-black/50 p-2">
      <div className="flex items-center gap-2">
        <img src={sub.image ?? ''} alt={sub.name} loading="lazy" className="h-14 w-14 rounded-xl object-cover" />
        <div className="min-w-0 flex-1">
          <p className="text-[9px] font-black uppercase tracking-[.24em] text-violet-200">{STAGE_LABEL[sub.stage]}</p>
          <p className="truncate text-[12px] font-black text-slate-100">{sub.name} · {sub.instance}</p>
          <p className="truncate text-[9px] text-slate-400">
            {t('breeding.parents')} {sub.parents.a ? `${sub.parents.a.name} #${sub.parents.a.serial}` : '—'} × {sub.parents.b ? `${sub.parents.b.name} #${sub.parents.b.serial}` : '—'} · {t('breeding.generation')} {sub.generation}
          </p>
          {sub.traitName ? <p className="text-[9px] font-black uppercase text-emerald-300">{t('breeding.trait')} {sub.traitName}</p> : null}
        </div>
      </div>
      <p className="mt-2 text-[10px] text-slate-300">
        {sub.stage === 'ADULT'
          ? sub.miningStatus === 'COMPLETE'
            ? t('breeding.miningComplete')
            : `${sub.rateTonDay.toFixed(3)} ${t('breeding.perDay')}`
          : `${sub.stage === 'EGG' ? t('breeding.hatchesIn') : t('breeding.maturesIn')}: ${countdown(sub.maturesAt)} · 0 ${t('breeding.perDay')}`}
      </p>
      <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/10">
        <div className="h-full bg-gradient-to-r from-violet-400 to-fuchsia-300" style={{ width: `${progress}%` }} />
      </div>
      <p className="mt-1 flex justify-end text-[9px] text-slate-400">
        <span className="text-amber-200">{t('breeding.claimLabel')} {sub.unclaimedTon.toFixed(3)}</span>
      </p>

    </div>
  );
}
