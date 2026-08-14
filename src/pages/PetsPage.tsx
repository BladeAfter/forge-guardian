import { useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI, useTonWallet } from '@tonconnect/ui-react';
import { formatTon } from '../economy';
import { Check, ChevronUp, Egg, Info, Minus, Plus, ShoppingCart, Sparkles, Star, X } from 'lucide-react';
import { toast } from 'sonner';
import { usePetDashboard } from '../hooks';
import { claimNftPosition, fetchMyNftRewards, petRequest } from '../services';
import { formatEggPrice, hatchedPurchase, purchasePremiumEgg, waitForEggPurchase } from '../eggPurchase';
import type { PetActionResponse, PetDashboard, PetEgg, PetEvolveResult, PetFood, PlayerPet } from '../pets';
import type { PetRarity } from '../petRules';
import { isNftExclusivePet, petBuffLabel, petBuffShortLabel, petDisplayRarity, petDisplayRarityLabel, petRarityLabel, petStageLabel, PET_FOOD_ICONS } from '../petLabels';
import { PetEggOpeningOverlay, type EggRevealResult } from '../components/PetEggOpeningOverlay';
import { PetBuff, petBuffIcon } from '../components/PetBuff';
import { NftShopSection } from '../components/NftShopSection';
import BreedingSection from '../components/BreedingSection';
import ExpeditionsSection from '../components/ExpeditionsSection';
import { useT, useLanguage } from '../LanguageContext';


type Tab = 'pets' | 'eggs' | 'food' | 'evolution' | 'catalog' | 'breeding' | 'expeditions';

const TAB_KEYS: Record<Tab, string> = { pets: 'pets.tabPets', eggs: 'pets.tabEggs', food: 'pets.tabFood', evolution: 'pets.tabEvolution', catalog: 'pets.tabCatalog', breeding: 'pets.tabBreeding', expeditions: 'pets.tabExpeditions' };
const TAB_FALLBACK: Record<Tab, string> = { pets: 'PETS', eggs: 'EGGS', food: 'FOOD', evolution: 'EVOLUTION', catalog: 'CATALOG', breeding: '🧬 BREEDING', expeditions: '🗺️ EXPEDITIONS' };
const RARITY_ORDER = ['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral', 'nft_exclusive'];
// Egg names come from the database and may carry decorative emojis that render as
// tofu boxes inside the Telegram webview: strip them and keep the plain label.
const cleanEggName = (name: string) => name.replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/gu, '').replace(/\s+/g, ' ').trim();
/** Rates always render in ascending rarity order, once per rarity. */
const rarityRank = (key: string) => { const i = RARITY_ORDER.indexOf(String(key).toLowerCase()); return i < 0 ? 99 : i; };
const sortedRates = (rates: Record<string, number>) =>
  Object.entries(rates ?? {}).filter(([, value]) => Number(value) > 0).sort((a, b) => rarityRank(a[0]) - rarityRank(b[0]));

const rarityColor: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24', mythic: '#e879f9', ancestral: '#f472b6', nft_exclusive: '#fbbf24' };

const PET_RARITY_STYLE: Record<PetRarity, { borderClass: string; glowClass: string; badgeClass: string }> = {
  common: { borderClass: 'border-slate-400/55', glowClass: 'from-slate-400/20', badgeClass: 'border-slate-300/40 bg-slate-500/15 text-slate-200' },
  uncommon: { borderClass: 'border-emerald-400/55', glowClass: 'from-emerald-400/25', badgeClass: 'border-emerald-300/45 bg-emerald-500/15 text-emerald-200' },
  rare: { borderClass: 'border-blue-400/60', glowClass: 'from-blue-500/30', badgeClass: 'border-blue-300/50 bg-blue-500/15 text-blue-200' },
  epic: { borderClass: 'border-violet-400/65', glowClass: 'from-violet-500/35', badgeClass: 'border-violet-300/50 bg-violet-500/15 text-violet-200' },
  legendary: { borderClass: 'border-amber-300/80', glowClass: 'from-amber-400/40', badgeClass: 'border-amber-200/60 bg-amber-500/20 text-amber-100' },
  mythic: { borderClass: 'border-rose-400/80', glowClass: 'from-rose-500/40', badgeClass: 'border-rose-200/60 bg-rose-600/20 text-rose-100' },
  ancestral: { borderClass: 'border-pink-300/80', glowClass: 'from-pink-400/40', badgeClass: 'border-pink-200/60 bg-pink-500/20 text-pink-100' },
  // NFT EXCLUSIVE never uses a colored rarity chip — the single premium gold/dark tag replaces it.
  nft_exclusive: { borderClass: 'border-amber-200/70', glowClass: 'from-amber-300/35', badgeClass: 'forge-nft-tag border-amber-200/80 bg-[#120c04] text-amber-200' },
};




const fmt = (value: number) => Math.round(value).toLocaleString('pt-BR');

export function PetsPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const { tError } = useLanguage();
  const queryClient = useQueryClient();
  const { data, isLoading, error } = usePetDashboard(telegramInitData, true);
  // Main section selector shown in the header: PETS | NFT EXCLUSIVE.
  const [section, setSection] = useState<Section>('pets');
  const [tab, setTab] = useState<Tab>('pets');
  const [reveal, setReveal] = useState<{ result: EggRevealResult; eggImage: string; pet?: PlayerPet } | null>(null);
  const [feedTarget, setFeedTarget] = useState<PlayerPet | null>(null);
  const [evolution, setEvolution] = useState<PetEvolveResult | null>(null);
  const [eggTarget, setEggTarget] = useState<PetEgg | null>(null);
  const [foodTarget, setFoodTarget] = useState<PetFood | null>(null);
  const [tonUI] = useTonConnectUI();
  const tonWallet = useTonWallet();
  const openingRef = useRef(false);

  // TON eggs are a purchase, never a withdrawable deposit: the backend records
  // the order and only delivers the egg after on-chain confirmation.
  const tonPurchase = useMutation({
    mutationFn: async (egg: PetEgg) => {
      if (!tonWallet) {
        await tonUI.openModal();
        throw new Error('CONNECT_TON_WALLET');
      }
      const order = await purchasePremiumEgg({ telegramInitData, eggId: egg.id, source: 'pet_shop', sendTransaction: (tx) => tonUI.sendTransaction(tx) });
      const verification = await waitForEggPurchase(telegramInitData);
      return { order, verification, egg };
    },
    onSuccess: async ({ verification, egg }) => {
      setEggTarget(null);
      const hatched = hatchedPurchase(verification);
      if (!hatched?.result) { toast(t('pets.tonPaymentSent')); return; }
      const dashboard = (hatched.dashboard ?? data) as PetDashboard | undefined;
      if (dashboard) await sync(dashboard);
      setReveal({
        result: { ...hatched.result, rarity: String(hatched.result.rarity).toLowerCase() as PetRarity },
        eggImage: egg.image,
        pet: dashboard?.playerPets.find((pet) => pet.id === hatched.result?.playerPetId)
          ?? dashboard?.playerPets.find((pet) => pet.petId === hatched.result?.petId),
      });
    },
    onError: (tonError) => toast.error(tonError instanceof Error && tonError.message === 'CONNECT_TON_WALLET' ? t('pets.connectTonWallet') : t('pets.tonPaymentFailed')),
  });

  const sync = async (fresh?: PetDashboard) => {
    if (fresh) queryClient.setQueryData(['pet-dashboard', telegramInitData], fresh);
    await Promise.all(
      ['pet-dashboard', 'player-inventory', 'boss-combat', 'pvp-dashboard', 'wallet-summary', 'game-state', 'community-pool', 'daily-quests', 'season-pass', 'market-sellable'].map((key) =>
        queryClient.invalidateQueries({ queryKey: [key] }),
      ),
    );
  };

  const mutation = useMutation({
    mutationFn: async (input: NonNullable<Parameters<typeof petRequest>[1]>) => {
      if (input.action !== 'hatch') return petRequest(telegramInitData, input) as Promise<PetActionResponse>;
      try {
        return await Promise.race([petRequest(telegramInitData, input),new Promise<never>((_,reject)=>window.setTimeout(()=>reject(new Error('HATCH_TIMEOUT')),30000))]);
      } catch (hatchError) {
        const recovered=await petRequest(telegramInitData,{action:'recover-hatch',idempotencyKey:input.idempotencyKey}) as PetActionResponse;
        if (recovered.result) return recovered;
        throw hatchError;
      }
    },
    onSuccess: async (payload, variables) => {
      const dashboard = (payload.dashboard ?? (payload as PetDashboard)) as PetDashboard;
      await sync(dashboard);
      if (payload.result) {
        const hatched = dashboard.playerPets.find((pet) => pet.id === payload.result?.playerPetId)
          ?? dashboard.playerPets.find((pet) => pet.petId === payload.result?.petId);
        const eggImage = (variables?.action === 'hatch' ? dashboard.eggs.find((egg) => egg.id === variables.eggId)?.image : null)
          || '/assets/game/pet-eggs/common-egg.webp';
        setReveal({ result: { ...payload.result, rarity: String(payload.result.rarity).toLowerCase() as PetRarity }, eggImage, pet: hatched });
        return;
      }
      if (payload.feedResult) {
        const { xpGained, levelsGained, foodName, quantity } = payload.feedResult;
        toast.success(
          levelsGained > 0
            ? t('pets.feedSuccessLevels', { quantity, foodName, xp: fmt(xpGained), levels: levelsGained })
            : t('pets.feedSuccessXp', { quantity, foodName, xp: fmt(xpGained) }),
        );
        setFeedTarget(null);
        return;
      }
      if (payload.evolveResult) {
        setEvolution(payload.evolveResult);
        return;
      }
      // Purchases only reach here AFTER the backend committed the debit + delivery.
      if (variables?.action === 'buy-food' || variables?.action === 'buy-egg') {
        const name = variables.action === 'buy-food'
          ? dashboard.foods.find((food) => food.code === variables.foodCode)?.name
          : dashboard.eggs.find((egg) => egg.id === variables.eggId)?.name;
        toast.success(name
          ? t('pets.purchaseSuccessItem', { name, quantity: variables.quantity })
          : t('pets.purchaseSuccess'));
        setFoodTarget(null);
        setEggTarget(null);
        return;
      }
      toast.success(t('pets.companionUpdated'));

    },
    onError: (mutationError) => {
      toast.error(tError(mutationError));
    },
    onSettled:()=>{openingRef.current=false},
  });

  const pending = mutation.isPending;

  if (isLoading) return <Shell onClose={onClose} section={section} onSection={setSection}><p className="py-24 text-center text-sm text-amber-200">{t('pets.loading')}</p></Shell>;
  if (error || !data) {
    return (
      <Shell onClose={onClose} section={section} onSection={setSection}>
        <p className="py-24 text-center text-sm text-rose-300">
          {error instanceof Error ? tError(error) : t('pets.loadError')}
        </p>
      </Shell>
    );
  }

  const active = data.activePet;
  const liveFeedTarget = feedTarget ? data.playerPets.find((pet) => pet.id === feedTarget.id) ?? null : null;

  if (section === 'nft') {
    return (
      <Shell onClose={onClose} section={section} onSection={setSection}>
        <NftExclusiveSection telegramInitData={telegramInitData} onGoToShop={() => setSection('shop')} />
      </Shell>
    );
  }

  if (section === 'shop') {
    return (
      <Shell onClose={onClose} section={section} onSection={setSection}>
        <NftShopSection telegramInitData={telegramInitData} />
      </Shell>
    );
  }


  return (
    <Shell onClose={onClose} section={section} onSection={setSection}>
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-400/30 bg-gradient-to-b from-sky-950/55 to-black/80 p-4 shadow-[0_0_40px_rgba(245,158,11,.12)]">
        {active ? (
          <>
            <div className="flex items-center gap-4">
              <img src={active.image} alt={active.name} className="h-32 w-32 shrink-0 object-contain drop-shadow-[0_0_22px_rgba(251,191,36,.4)]" />
              <div className="min-w-0">
                <p className="text-[9px] uppercase tracking-[.25em] text-amber-300">{t('pets.activeCompanion')}</p>
                <h2 className="truncate text-2xl font-black">{active.name}</h2>
                <p style={{ color: rarityColor[petDisplayRarity(active)] }} className="text-xs font-bold uppercase">
                  {t('pets.rarityLevel', { rarity: petDisplayRarityLabel(active), level: active.level, max: active.maxLevel })}
                </p>
                <p className="text-[10px] text-slate-400">
                  {t('pets.levelProgress', { stage: petStageLabel(active.evolutionStage), label: active.evolutionLabel, power: fmt(active.power) })}
                </p>
              </div>
            </div>

            <LevelBar pet={active} />
            <BuffGrid pet={active} />

            <div className="mt-3 grid grid-cols-2 gap-2">
              <Action text={t('pets.feed')} disabled={pending || active.isMaxLevel} onClick={() => setFeedTarget(active)} />
              <EvolveButton pet={active} balance={data.balance} universal={data.inventory.universalFragments} pending={pending} onEvolve={() => evolve(active)} />
            </div>
            <p className="mt-2 text-center text-[9px] leading-relaxed text-slate-400">
              {t('pets.feedHintPre')} <b className="text-amber-200">{t('pets.levelWord')}</b>{t('pets.feedHintMid')} <b className="text-violet-200">{t('pets.evolutionWord')}</b>{t('pets.feedHintPost')}
            </p>
          </>
        ) : (
          <div className="grid min-h-48 place-items-center text-center">
            <div>
              <Egg className="mx-auto h-14 w-14 text-slate-600" />
              <h2 className="mt-2 text-xl font-black">{t('pets.noActivePet')}</h2>
              <p className="text-xs text-slate-400">{t('pets.chooseCompanion')}</p>
            </div>
          </div>
        )}
      </section>

      {/* NFT EXCLUSIVE lives in its own main section (header selector), never here. */}

      <nav className="mt-3 flex gap-1 overflow-x-auto pb-1">
        {(Object.keys(TAB_KEYS) as Tab[]).map((key) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={`shrink-0 whitespace-nowrap rounded-xl px-2.5 py-2 text-[8px] font-black uppercase ${tab === key ? 'bg-amber-400 text-black' : 'bg-white/5 text-slate-300'}`}
          >
            {t(TAB_KEYS[key]) === TAB_KEYS[key] ? TAB_FALLBACK[key] : t(TAB_KEYS[key])}
          </button>
        ))}
      </nav>

      <main className="mt-3 pb-10">
        {tab === 'pets' && (
          <div className="grid grid-cols-2 gap-2">
            {data.playerPets.map((pet) => (
              <PetCard
                key={pet.id}
                pet={pet}
                onFeed={() => setFeedTarget(pet)}
                onActivate={pet.isActive ? undefined : () => mutation.mutate({ action: 'activate', playerPetId: pet.id })}
                pending={pending}
              />
            ))}
            {data.playerPets.length === 0 && <p className="col-span-2 py-16 text-center text-sm text-slate-400">{t('pets.noPetsYet')}</p>}
          </div>
        )}

        {tab === 'eggs' && (
          <>
            <p className="mb-2 rounded-xl border border-amber-300/20 bg-black/45 px-3 py-2 text-[9px] leading-relaxed text-slate-300">
              {t('pets.availableBalance', { balance: fmt(data.balance) })}
            </p>
            <div className="grid grid-cols-2 gap-2">
              {data.eggs.map((egg) => {
                const owned = egg.quantity > 0;
                const ton = !egg.priceFc && !!egg.priceTon;
                const locked = !egg.isPurchasable || (!egg.priceFc && !egg.priceTon);
                 const cosmic = egg.slug === 'mythic-egg';
                 const label = cleanEggName(egg.name);
                 const labelParts = label.split(' ');
                 const labelHead = labelParts.slice(0, -1).join(' ');
                 const labelTail = labelParts[labelParts.length - 1] ?? label;
                 return (
                   <div key={egg.id} className={`flex min-w-0 flex-col rounded-2xl border p-3 text-center ${cosmic ? 'egg-card-cosmic border-violet-300/40' : 'border-amber-300/20 bg-black/55'}`}>
                     <img src={egg.image} alt={label} loading="lazy" className={`mx-auto h-24 w-24 max-w-full object-contain ${cosmic ? 'egg-image-cosmic' : ''}`} />
                     <h3 className="mt-1 break-words text-xs font-black leading-tight">
                       {cosmic && labelHead ? (
                         <>
                           <span className="text-white">{labelHead} </span>
                           <span className="egg-name-mythic">{labelTail.toUpperCase()}</span>
                         </>
                       ) : cosmic ? (
                         <span className="egg-name-mythic">{labelTail.toUpperCase()}</span>
                       ) : label}
                     </h3>
                     {/* Price is rendered exactly once here; the buy button may repeat it. */}
                     <p className="text-[9px] font-bold uppercase text-amber-200">
                       {formatEggPrice(egg)}
                     </p>
                     {/* Rates ascend from the weakest rarity to the strongest (LEGENDARY then MYTHIC). */}
                     <div className="mt-1 flex flex-wrap items-center justify-center gap-x-1 gap-y-0.5">
                       {sortedRates(egg.rarityRates).map(([key, value], index) => (
                         <span key={key} className="flex items-center gap-1">
                           {index > 0 && <span className="text-[8px] text-slate-500">•</span>}
                           <span style={{ color: rarityColor[String(key).toLowerCase()] }} className="whitespace-nowrap text-[8px] font-bold">
                             {petRarityLabel(key)} {value}%
                           </span>
                         </span>
                       ))}
                     </div>
                    <p className="mt-1 text-[9px] text-slate-400">{t('pets.youOwn', { quantity: egg.quantity })}</p>
                    <div className="mt-auto">
                      {owned ? (
                        <Action
                          text={t('pets.openEgg')}
                          disabled={pending||openingRef.current}
                          onClick={() => {if(openingRef.current)return;openingRef.current=true;mutation.mutate({ action: 'hatch', eggId: egg.id, idempotencyKey: crypto.randomUUID() })}}
                        />
                      ) : locked ? (
                        <Action text={egg.availabilityLabel || t('pets.exclusiveEvent')} disabled onClick={() => undefined} />
                      ) : (
                        <Action
                          text={t('pets.buy', { price: formatEggPrice(egg) })}
                          disabled={pending || tonPurchase.isPending}
                          onClick={() => setEggTarget(egg)}
                        />
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
            {eggTarget && (
              <BuyEggModal
                egg={eggTarget}
                balance={data.balance}
                pending={pending || tonPurchase.isPending}
                onClose={() => setEggTarget(null)}
                onBuyFc={(quantity) => mutation.mutate({ action: 'buy-egg', eggId: eggTarget.id, quantity, idempotencyKey: crypto.randomUUID() })}
                onBuyTon={() => tonPurchase.mutate(eggTarget)}
              />
            )}
          </>
        )}

        {tab === 'food' && (
          <div className="space-y-3">
            <p className="rounded-xl border border-amber-300/20 bg-black/45 px-3 py-2 text-[9px] leading-relaxed text-slate-300">
              {t('pets.foodRaisesLevel', { balance: fmt(data.balance) })}
            </p>
            <div className="grid grid-cols-2 gap-2">
              {data.foods.map((food) => (
                <div key={food.code} className="flex flex-col rounded-2xl border border-amber-300/15 bg-black/55 p-3">
                  <div className="flex items-center gap-2">
                    <span className="text-2xl leading-none">{PET_FOOD_ICONS[food.icon] ?? '🍖'}</span>
                    <div className="min-w-0">
                      <p className="truncate text-[11px] font-black">{food.name}</p>
                      <p className="text-[9px] text-emerald-300">{t('pets.xpPerUnit', { xp: fmt(food.xpValue) })}</p>
                    </div>
                  </div>
                  <p className="mt-2 text-[9px] text-slate-400">{t('pets.youOwnLabel')}</p>
                  <b className="text-lg leading-none">{fmt(food.quantity)}</b>
                  <p className="mt-1 text-[9px] font-bold text-amber-200">
                    {food.priceFc ? `${fmt(food.priceFc)} FC` : t('pets.unavailable')}
                  </p>
                  <div className="mt-auto">
                    <Action
                      text={t('pets.buyLabel')}
                      disabled={pending || !food.priceFc}
                      onClick={() => setFoodTarget(food)}
                    />
                  </div>
                </div>
              ))}
            </div>
            <h3 className="pt-1 text-[10px] font-black uppercase tracking-[.2em] text-amber-300">{t('pets.fragmentsPerPet')}</h3>
            <div className="grid grid-cols-2 gap-2">
              <Stat icon={<Star />} label={t('pets.universalFragments')} value={data.inventory.universalFragments} />
              {data.fragments.map((entry) => (
                <Stat
                  key={entry.playerPetId}
                  icon={<img src={entry.image} alt={entry.petName} className="h-8 w-8 object-contain" />}
                  label={t('pets.fragmentsOf', { name: entry.petName })}
                  value={entry.quantity}
                />
              ))}
            </div>
            {foodTarget && (
              <BuyFoodModal
                food={foodTarget}
                balance={data.balance}
                pending={pending}
                onClose={() => setFoodTarget(null)}
                onBuy={(quantity) => mutation.mutate({ action: 'buy-food', foodCode: foodTarget.code, quantity, idempotencyKey: crypto.randomUUID() })}
              />
            )}
          </div>
        )}

        {tab === 'evolution' && (
          <div className="space-y-2">
            {data.playerPets.map((pet) => (
              <EvolutionRow key={pet.id} pet={pet} balance={data.balance} universal={data.inventory.universalFragments} pending={pending} onEvolve={() => evolve(pet)} onFeed={() => setFeedTarget(pet)} />
            ))}
          </div>
        )}

        {tab === 'breeding' && <BreedingSection initData={telegramInitData} />}

        {tab === 'expeditions' && <ExpeditionsSection initData={telegramInitData} />}

        {tab === 'catalog' && (
          <div className="grid grid-cols-2 gap-2">
            {data.catalog.map((pet) => {
              const buff = pet.discovered ? Object.entries(pet.basePassives)[0] : null;
              return (
                <div key={pet.id} className={`rounded-2xl border p-3 text-center ${pet.discovered ? 'border-amber-300/20 bg-black/55' : 'border-white/5 bg-black/30'}`}>
                  <img src={pet.images.baby} alt={pet.name} className={`mx-auto h-24 w-24 object-contain ${pet.discovered ? '' : 'brightness-0 opacity-70'}`} />
                  <b className="block truncate text-xs">{pet.name}</b>
                  <p className="text-[9px] text-slate-400">
                    {pet.discovered
                      ? `${pet.species} · ${t('pets.rarityLevel', { rarity: petDisplayRarityLabel({ ...pet, rarity: pet.bestRarity }), level: pet.bestLevel ?? 1, max: pet.bestLevel ?? 1 })}`
                      : `${petDisplayRarityLabel(pet)} · ${t('pets.notDiscovered')}`}
                  </p>
                  {buff && (
                    <PetBuff
                      buffKey={buff[0]}
                      label={petBuffShortLabel(buff[0])}
                      value={`+${buff[1]}%`}
                      size="sm"
                      className="mt-1 rounded-xl bg-black/40 text-left"
                    />
                  )}

                  {pet.discovered && pet.sources && pet.sources.length > 0 && (
                    <p className="mt-1 text-[8px] leading-relaxed text-slate-500">{t('pets.obtainedFrom', { sources: pet.sources.join(', ') })}</p>
                  )}
                </div>
              );
            })}

          </div>
        )}
      </main>

      {liveFeedTarget && (
        <FeedModal
          pet={liveFeedTarget}
          foods={data.foods}
          pending={pending}
          onClose={() => setFeedTarget(null)}
          onFeed={(foodCode, quantity) =>
            mutation.mutate({ action: 'feed', playerPetId: liveFeedTarget.id, foodCode, quantity, idempotencyKey: crypto.randomUUID() })
          }
        />
      )}

      {evolution && <EvolutionOverlay result={evolution} onClose={() => setEvolution(null)} />}

      {reveal && (
        <PetEggOpeningOverlay
          result={reveal.result}
          eggImage={reveal.eggImage}
          pet={reveal.pet}
          onContinue={() => setReveal(null)}
          onActivate={
            reveal.pet && !reveal.pet.isActive
              ? async () => {
                   const petId=reveal.pet?.id;if(!petId)return;await mutation.mutateAsync({ action: 'activate', playerPetId:petId });
                  setReveal(null);
                }
              : undefined
          }
        />
      )}
    </Shell>
  );

  function evolve(pet: PlayerPet) {
    mutation.mutate({ action: 'evolve', playerPetId: pet.id, idempotencyKey: crypto.randomUUID() });
  }
}

/**
 * PETS and NFT EXCLUSIVE are two MAIN sections of this screen, selected in the
 * header (never as a sub-tab next to Eggs/Food/Evolution/Catalog).
 */
type Section = 'pets' | 'nft' | 'shop';

function Shell({ children, onClose, section, onSection }: { children: React.ReactNode; onClose: () => void; section?: Section; onSection?: (value: Section) => void }) {
  const t = useT();
  return (
    <div className="fixed inset-0 z-[70] overflow-y-auto bg-[#05080e] text-white">
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top,#122542_0%,#05080e_55%)]" />
      <div className="forge-safe-page relative mx-auto min-h-full w-full max-w-[480px] p-3">
        <header className="mb-3 rounded-2xl border border-amber-300/20 bg-black/70 p-3">
          <div className="flex items-start justify-between gap-2">
            <p className="text-[9px] uppercase tracking-[.3em] text-amber-300">MYTHREON</p>
            <button type="button" onClick={onClose} aria-label={t('pets.close')} className="-mt-1 grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/5"><X className="h-5 w-5" /></button>
          </div>
          {section && onSection ? (
            <div className="mt-1 flex items-end gap-4">
              {([['pets', 'PETS'], ['nft', 'NFT EXCLUSIVE'], ['shop', 'BUY NFT']] as [Section, string][]).map(([key, label]) => {
                const on = section === key;
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => onSection(key)}
                    className={`relative shrink-0 pb-1.5 text-left text-[13px] font-black uppercase tracking-[.04em] transition ${
                      on ? 'text-amber-200 drop-shadow-[0_0_10px_rgba(251,191,36,.45)]' : 'text-slate-500'
                    }`}
                  >
                    {key === 'pets' ? null : <span className="mr-1">{key === 'nft' ? '💎' : '🛒'}</span>}
                    {label}
                    <span className={`absolute inset-x-0 bottom-0 h-[3px] rounded-full ${on ? 'bg-gradient-to-r from-amber-300 to-orange-500 shadow-[0_0_12px_rgba(251,191,36,.7)]' : 'bg-transparent'}`} />
                  </button>
                );
              })}
            </div>
          ) : (
            <h1 className="text-xl font-black">PETS</h1>
          )}
        </header>
        {children}
      </div>
    </div>
  );
}

function LevelBar({ pet }: { pet: PlayerPet }) {
  const t = useT();
  const percent = pet.isMaxLevel ? 100 : Math.min(100, (pet.xp / Math.max(1, pet.xpRequired)) * 100);
  return (
    <>
      <div className="mt-3 h-2 overflow-hidden rounded-full bg-white/10">
        <div className="h-full bg-gradient-to-r from-amber-500 to-yellow-200 transition-[width] duration-500" style={{ width: `${percent}%` }} />
      </div>
      <p className="mt-1 text-right text-[9px] text-slate-400">
        {pet.isMaxLevel ? t('pets.maxLevelReached') : `XP ${fmt(pet.xp)} / ${fmt(pet.xpRequired)}`}
      </p>
    </>
  );
}

function BuffGrid({ pet }: { pet: PlayerPet }) {
  const entries = Object.entries(pet.buffs).slice(0, 6);
  const secondary = new Set(pet.secondaryBuffs.map((buff) => buff.key));
  if (entries.length === 0) return null;
  return (
    <div className="mt-3 grid grid-cols-2 gap-1">
      {entries.map(([key, value]) => (
        <PetBuff
          key={key}
          buffKey={key}
          label={petBuffShortLabel(key)}
          value={`+${value}%`}
          size="sm"
          className="rounded-xl bg-black/45"
          valueClassName={secondary.has(key) ? 'text-violet-300' : 'text-emerald-300'}
        />
      ))}
    </div>
  );
}


function EvolveButton({ pet, balance, universal = 0, pending, onEvolve }: { pet: PlayerPet; balance: number; universal?: number; pending: boolean; onEvolve: () => void }) {
  const t = useT();
  const next = pet.nextEvolution;
  if (!next) return <Action text={t('pets.maxEvolution')} disabled onClick={() => undefined} />;
  const missingLevel = pet.level < next.requiredLevel;
  const missingFc = balance < next.fcCost;
  const missingFragments = pet.fragments + universal < next.fragmentCost;
  const ready = !missingLevel && !missingFc && !missingFragments;
  const label = missingLevel ? t('pets.evolveAtLevel', { level: next.requiredLevel }) : missingFc ? t('pets.notEnoughFc') : missingFragments ? t('pets.notEnoughFragments') : t('pets.evolve', { label: next.label });
  return (
    <button
      type="button"
      onClick={onEvolve}
      disabled={pending || !ready}
      className={`mt-2 flex w-full items-center justify-center gap-1 rounded-xl border px-2 py-2.5 text-[10px] font-black uppercase transition disabled:grayscale disabled:opacity-40 ${
        ready
          ? 'animate-pulse border-violet-200/70 bg-gradient-to-b from-violet-400 to-fuchsia-600 text-black shadow-[0_0_22px_rgba(192,132,252,.55)]'
          : 'border-white/15 bg-white/5 text-slate-300'
      }`}
    >
      <ChevronUp className="h-3 w-3" />
      {label}
    </button>
  );
}

function EvolutionRow({ pet, balance, universal = 0, pending, onEvolve, onFeed }: { pet: PlayerPet; balance: number; universal?: number; pending: boolean; onEvolve: () => void; onFeed: () => void }) {
  const t = useT();
  const next = pet.nextEvolution;
  const specificSpend = next ? Math.min(pet.fragments, next.fragmentCost) : 0;
  const universalSpend = next ? Math.max(0, next.fragmentCost - specificSpend) : 0;
  return (
    <div className={`rounded-2xl border bg-black/55 p-3 ${pet.canEvolve ? 'border-violet-300/50 shadow-[0_0_18px_rgba(168,85,247,.2)]' : 'border-white/10'}`}>
      <div className="flex items-center gap-3">
        <img src={pet.image} alt={pet.name} className="h-16 w-16 shrink-0 object-contain" />
        <div className="min-w-0 flex-1">
          <b className="block truncate text-sm">{pet.name}</b>
          {isNftExclusivePet(pet) && (
            <NftPetTag serial={pet.nft?.serial} className="mt-0.5" />
          )}
          <p className="text-[9px] text-slate-400">
            {t('pets.rarityLevel', { rarity: petStageLabel(pet.evolutionStage), level: pet.level, max: pet.maxLevel })} · {pet.evolutionLabel}
          </p>
          {next ? (
            <p className="mt-1 text-[9px] leading-relaxed text-slate-300">
              {t('pets.requirements')} <b className={pet.level >= next.requiredLevel ? 'text-emerald-300' : 'text-rose-300'}>{next.requiredLevel}</b>
              {' · '}
              <b className={balance >= next.fcCost ? 'text-emerald-300' : 'text-rose-300'}>{fmt(next.fcCost)} FC</b>
              {' · '}
              <b className={pet.fragments + universal >= next.fragmentCost ? 'text-emerald-300' : 'text-rose-300'}>{next.fragmentCost} {t('pets.fragments')}</b>
              {' · '}
              <span className="text-violet-300">{t('pets.newBuffChance', { percent: next.newBuffChance })}</span>
            </p>
          ) : (
            <p className="mt-1 text-[9px] text-amber-200">{t('pets.finalForm')}</p>
          )}
          {next && universalSpend > 0 && (
            <p className="mt-1 text-[9px] text-amber-200">
              {specificSpend} {t('pets.fragments')} + {universalSpend} {t('pets.universalFragments')} ({universal})
            </p>
          )}
          {next && (
            <p className="mt-1 text-[9px] text-slate-400">
              {petBuffLabel(pet.primaryBuffKey)}: <span className="text-slate-300">+{next.primaryFrom}%</span> → <span className="text-emerald-300">+{next.primaryTo}%</span>
            </p>
          )}
        </div>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Action text={t('pets.feed')} disabled={pending || pet.isMaxLevel} onClick={onFeed} />
        <EvolveButton pet={pet} balance={balance} universal={universal} pending={pending} onEvolve={onEvolve} />
      </div>
    </div>
  );
}

function FeedModal({ pet, foods, pending, onClose, onFeed }: { pet: PlayerPet; foods: PetFood[]; pending: boolean; onClose: () => void; onFeed: (foodCode: string, quantity: number) => void }) {
  const t = useT();
  const available = foods.filter((food) => food.quantity > 0);
  const [selected, setSelected] = useState(available[0]?.code ?? '');
  const [quantity, setQuantity] = useState(1);
  const food = available.find((item) => item.code === selected);
  const max = Math.min(100, food?.quantity ?? 1);
  const safeQuantity = Math.max(1, Math.min(quantity, max));
  const preview = useMemo(() => (food ? food.xpValue * safeQuantity : 0), [food, safeQuantity]);
  const missing = Math.max(0, pet.xpRequired - pet.xp);

  return (
    <div className="fixed inset-0 z-[95] flex items-end justify-center bg-black/80 p-3" onClick={onClose}>
      <div className="w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-4" onClick={(event) => event.stopPropagation()}>
        <header className="mb-3 flex items-center justify-between">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.25em] text-amber-300">{t('pets.feed')}</p>
            <h2 className="truncate text-lg font-black">{pet.name}</h2>
            <p className="text-[10px] text-slate-400">{t('pets.missingXp', { level: pet.level, missing: fmt(missing) })}</p>
          </div>
          <button type="button" onClick={onClose} aria-label={t('pets.close')} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
        </header>

        {available.length === 0 ? (
          <p className="py-8 text-center text-sm text-slate-300">{t('pets.noFood')}</p>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-2">
              {available.map((item) => (
                <button
                  key={item.code}
                  type="button"
                  onClick={() => { setSelected(item.code); setQuantity(1); }}
                  className={`flex items-center gap-2 rounded-xl border p-2 text-left ${item.code === selected ? 'border-amber-300 bg-amber-400/10' : 'border-white/10 bg-black/40'}`}
                >
                  <span className="text-xl leading-none">{PET_FOOD_ICONS[item.icon] ?? '🍖'}</span>
                  <span className="min-w-0">
                    <b className="block truncate text-[10px]">{item.name}</b>
                    <span className="block text-[9px] text-emerald-300">+{fmt(item.xpValue)} XP · {item.quantity}x</span>
                  </span>
                </button>
              ))}
            </div>

            <div className="mt-4">
              <label htmlFor="pet-food-quantity" className="text-[9px] uppercase tracking-[.2em] text-slate-400">{t('pets.quantity')}: {safeQuantity}</label>
              <input
                id="pet-food-quantity"
                type="range"
                min={1}
                max={max}
                value={safeQuantity}
                onChange={(event) => setQuantity(Number(event.target.value))}
                className="mt-2 w-full accent-amber-400"
              />
              <p className="mt-1 text-center text-[10px] text-emerald-300">{t('pets.estimatedGain', { xp: fmt(preview) })}</p>
            </div>

            <Action text={pending ? t('pets.feeding') : t('pets.feedWith', { quantity: safeQuantity })} disabled={pending || !food} onClick={() => food && onFeed(food.code, safeQuantity)} />
          </>
        )}
      </div>
    </div>
  );
}

function EvolutionOverlay({ result, onClose }: { result: PetEvolveResult; onClose: () => void }) {
  const t = useT();
  return (
    <div className="fixed inset-0 z-[99] grid place-items-center bg-black/85 p-4 pet-evolution-overlay">
      <div className="w-full max-w-sm rounded-3xl border border-violet-300/50 bg-[#0a0714] p-5 text-center shadow-[0_0_60px_rgba(168,85,247,.35)]">
        <Sparkles className="mx-auto h-10 w-10 animate-pulse text-violet-300" />
        <p className="mt-2 text-[9px] uppercase tracking-[.3em] text-violet-300">{t('pets.evolutionCompleted')}</p>
        <h2 className="text-2xl font-black">{result.petName}</h2>
        <p className="text-xs font-bold uppercase text-fuchsia-300">{result.label}</p>

        <div className="mt-4 rounded-2xl border border-white/10 bg-black/50 p-3">
          <p className="text-[9px] uppercase tracking-[.2em] text-slate-400">{petBuffLabel(result.primaryBuffKey)}</p>
          <p className="mt-1 text-lg font-black">
            <span className="text-slate-400">+{result.primaryBefore}%</span>
            <span className="mx-2 text-violet-300">→</span>
            <span className="text-emerald-300">+{result.primaryAfter}%</span>
          </p>
        </div>

        {result.newBuff ? (
          <div className="mt-3 rounded-2xl border border-amber-300/40 bg-amber-400/10 p-3">
            <p className="text-[9px] uppercase tracking-[.2em] text-amber-300">{t('pets.newBonusUnlocked')}</p>
            <p className="mt-1 text-sm font-black text-amber-100">
              {petBuffLabel(result.newBuff.key)} +{result.newBuff.value}%
            </p>
            <p className="text-[9px] text-slate-400">{t('pets.quality', { rarity: petRarityLabel(result.newBuff.rarity) })}</p>
          </div>
        ) : (
          <p className="mt-3 text-[10px] text-slate-400">{t('pets.noExtraBonus')}</p>
        )}

        <p className="mt-3 text-[9px] text-slate-500">
          {t('pets.cost', { fc: fmt(result.fcSpent), fragments: result.fragmentsSpent })}
        </p>
        <Action text={t('pets.continue')} onClick={onClose} />
      </div>
    </div>
  );
}

function Action({ text, onClick, disabled }: { text: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="mt-2 w-full rounded-xl border border-amber-300/30 bg-gradient-to-b from-amber-400 to-orange-600 px-2 py-2 text-[9px] font-black uppercase text-black disabled:grayscale disabled:opacity-40"
    >
      {text}
    </button>
  );
}

/**
 * NFT EXCLUSIVE main section: shows ONLY the TON-producing NFT pets owned by
 * this player. It never renders pool balance, pool health, reserved amounts,
 * daily obligation, treasury or any system revenue — that data stays in the
 * backend and is visible exclusively to the master admin through the admin bot.
 */
function NftExclusiveSection({ telegramInitData, onGoToShop }: { telegramInitData: string; onGoToShop?: () => void }) {
  const queryClient = useQueryClient();
  const { data, isLoading, error } = useQuery({
    queryKey: ['nft-rewards-mine'],
    queryFn: () => fetchMyNftRewards(telegramInitData),
    staleTime: 20_000,
  });
  const claim = useMutation({
    mutationFn: (positionId: string) => claimNftPosition(telegramInitData, positionId),
    onSuccess: (result) => {
      toast.success(`+${formatTon(result.amountTon)} TON`);
      queryClient.setQueryData(['nft-rewards-mine'], { totalSupply: result.totalSupply, items: result.items });
      queryClient.invalidateQueries({ queryKey: ['ton-wallet'] });
      queryClient.invalidateQueries({ queryKey: ['wallet-summary'] });
    },
    onError: (claimError: unknown) => toast.error(claimError instanceof Error ? claimError.message : 'Erro'),
  });

  if (isLoading) return <p className="py-24 text-center text-sm text-amber-200">...</p>;
  if (error) return <p className="py-24 text-center text-sm text-rose-300">{error instanceof Error ? error.message : 'Erro'}</p>;

  const items = data?.items ?? [];
  if (items.length === 0) {
    return (
      <section className="forge-nft-card mt-2 overflow-hidden rounded-[1.8rem] border border-amber-200/50 bg-gradient-to-b from-amber-950/35 to-black/85 p-6 text-center">
        <div className="forge-nft-sparkles pointer-events-none absolute inset-0" aria-hidden />
        <p className="text-[11px] font-black uppercase tracking-[.3em] text-amber-200">💎 NFT EXCLUSIVE</p>
        <p className="mx-auto mt-4 max-w-[260px] text-sm text-slate-300">You don&apos;t own an NFT Exclusive Pet yet.</p>
        <p className="mx-auto mt-1 max-w-[260px] text-[11px] text-slate-400">Go to BUY NFT to purchase one.</p>
        {onGoToShop ? (
          <button type="button" onClick={onGoToShop} className="relative mt-4 w-full rounded-xl bg-gradient-to-b from-amber-300 to-orange-500 px-3 py-2.5 text-[11px] font-black uppercase tracking-[.14em] text-black">
            GO TO BUY NFT
          </button>
        ) : null}
        <div className="mt-5 inline-flex flex-col rounded-2xl border border-amber-200/25 bg-black/50 px-6 py-3">
          <span className="text-[8px] uppercase tracking-[.22em] text-slate-400">Limited Collection</span>
          <span className="text-lg font-black text-amber-100">{data?.totalSupply ?? 10} NFTs Total</span>
        </div>
      </section>
    );
  }

  return (
    <div className="mt-1 space-y-3 pb-10">
      {items.map((item) => {
        const available = Number(item.availableTon ?? 0);
        const canClaim = Boolean(item.canClaim) && !claim.isPending;
        return (
          <section key={item.positionId} className="forge-nft-card relative overflow-hidden rounded-[1.6rem] border border-amber-200/60 bg-gradient-to-b from-amber-950/40 to-black/85 p-3">
            <div className="forge-nft-sparkles pointer-events-none absolute inset-0" aria-hidden />
            <div className="relative flex items-center justify-between gap-2">
              <p className="text-[9px] font-black uppercase tracking-[.26em] text-amber-200">💎 NFT EXCLUSIVE</p>
              <p className="text-[10px] font-black text-amber-100">NFT #{String(item.serial).padStart(2, '0')}/{data?.totalSupply ?? 10}</p>
            </div>
            <div className="relative mt-2 flex items-center gap-3">
              {item.image ? <img src={item.image} alt={item.name} className="h-16 w-16 shrink-0 object-contain drop-shadow-[0_0_16px_rgba(251,191,36,.45)]" /> : null}
              <div className="min-w-0">
                <h3 className="truncate text-lg font-black text-white">{item.name.toUpperCase()}</h3>
                <p className="text-[10px] font-bold uppercase tracking-[.12em] text-amber-300/90">
                  {petRarityLabel(item.rarity as PetRarity)} • LEVEL {item.level}
                </p>
              </div>
            </div>
            <div className="relative mt-3 grid grid-cols-3 gap-2 text-center">
              {[
                { label: 'Daily Yield', value: item.dailyYieldTon },
                { label: 'Available to Claim', value: available },
                { label: 'Lifetime Earned', value: item.lifetimeEarnedTon },
              ].map((stat) => (
                <div key={stat.label} className="rounded-xl border border-amber-200/20 bg-black/45 px-1 py-2">
                  <p className="text-[7px] uppercase leading-tight tracking-[.12em] text-slate-400">{stat.label}</p>
                  <p className="text-[13px] font-black text-amber-100">{formatTon(stat.value ?? 0)} <span className="text-[8px] text-amber-300/80">TON</span></p>
                </div>
              ))}
            </div>
            <button
              type="button"
              disabled={!canClaim}
              onClick={() => claim.mutate(item.positionId)}
              className={`relative mt-3 w-full rounded-xl px-3 py-2.5 text-[11px] font-black uppercase tracking-[.12em] ${canClaim ? 'bg-gradient-to-b from-amber-300 to-orange-500 text-black' : 'bg-white/5 text-slate-500'}`}
            >
              {available > 0 ? `CLAIM ${formatTon(available)} TON` : 'NOTHING TO CLAIM'}
            </button>
          </section>
        );
      })}
    </div>
  );
}

function NftPetTag({ serial, className = '' }: { serial?: string | number | null; className?: string }) {
  return (
    <span className={`forge-nft-tag inline-flex items-center gap-1 rounded-full border border-amber-200/80 bg-[#120c04] px-2 py-1 text-[7px] font-black tracking-[.16em] text-amber-200 ${className}`}>
      NFT EXCLUSIVE
      {serial ? <b className="text-amber-100">#{String(serial).padStart(3, '0')}</b> : null}
    </span>
  );
}

function PetCard({ pet, onFeed, onActivate, pending }: { pet: PlayerPet; onFeed: () => void; onActivate?: () => void; pending: boolean }) {
  const t = useT();
  const isNft = isNftExclusivePet(pet);
  const style = PET_RARITY_STYLE[petDisplayRarity(pet) as PetRarity] ?? PET_RARITY_STYLE.common;
  const serial = pet.nft?.serial;
  return (
    <div
      className={`group relative flex flex-col overflow-hidden rounded-[1.35rem] border bg-gradient-to-b from-[#102039] via-[#08111f] to-[#03070d] p-2.5 text-center shadow-[0_16px_30px_rgba(0,0,0,.45)] transition duration-200 active:scale-[.98] ${
        isNft ? 'forge-nft-card border-amber-200/60' : style.borderClass
      } ${pet.isActive ? 'ring-1 ring-emerald-300/25' : ''}`}
    >
      {isNft && <div className="forge-nft-sparkles pointer-events-none absolute inset-0 z-0" aria-hidden />}
      <div className={`pointer-events-none absolute left-1/2 top-10 h-40 w-40 -translate-x-1/2 rounded-full bg-gradient-to-b ${isNft ? 'from-amber-300/25 via-fuchsia-500/20' : style.glowClass} to-transparent blur-xl`} />
      <div className="relative z-10 flex items-start justify-between gap-1">
        {/* NFT EXCLUSIVE replaces the normal rarity badge — never both. */}
        {isNft ? (
          <NftPetTag serial={serial} />
        ) : (
          <span className={`rounded-full border px-2 py-1 text-[7px] font-black tracking-[.12em] ${style.badgeClass}`}>{petRarityLabel(pet.rarity)}</span>
        )}
        {pet.isActive && (
          <span className="flex items-center gap-1 rounded-full border border-emerald-300/45 bg-emerald-950/80 px-2 py-1 text-[7px] font-black text-emerald-200">
            <Check className="h-2.5 w-2.5" />{t('pets.active')}
          </span>
        )}
      </div>


      <div className="relative z-10 mt-1 grid h-[124px] place-items-center">
        <img src={pet.image} alt={pet.name} className="h-[118px] w-full object-contain drop-shadow-[0_10px_14px_rgba(0,0,0,.8)]" />
      </div>

      <div className="relative z-10">
        <h3 className="truncate text-base font-black uppercase tracking-wide">{pet.name}</h3>
        <p className="mt-1 text-[9px] font-bold text-slate-300">{t('pets.cardLevelPower', { level: pet.level, max: pet.maxLevel, power: fmt(pet.power) })}</p>
        <p className="text-[8px] text-slate-500">{petStageLabel(pet.evolutionStage)} · {pet.evolutionLabel}</p>
      </div>

      <div className="relative z-10 mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
        <div className="h-full bg-gradient-to-r from-amber-500 to-yellow-200" style={{ width: `${pet.isMaxLevel ? 100 : Math.min(100, (pet.xp / Math.max(1, pet.xpRequired)) * 100)}%` }} />
      </div>

      <div className="relative z-10 mt-2 rounded-xl border border-white/10 bg-black/45">
        <PetBuff
          buffKey={pet.primaryBuffKey}
          label={petBuffShortLabel(pet.primaryBuffKey)}
          value={`+${pet.primaryBuffValue}%`}
          size="sm"
          color={rarityColor[pet.rarity]}
        />
        {pet.secondaryBuffs.length > 0 && (
          <p className="px-2 pb-2 text-[8px] text-violet-300">
            {t('pets.secondaryBonus', { count: pet.secondaryBuffs.length, plural: pet.secondaryBuffs.length > 1 ? 's' : '' })}
          </p>
        )}

      </div>

      <div className="relative z-10 mt-auto grid grid-cols-2 gap-1.5 pt-3">
        <button
          type="button"
          onClick={onFeed}
          disabled={pending || pet.isMaxLevel}
          className="flex h-10 items-center justify-center gap-1 rounded-lg border border-amber-300/35 bg-black/40 px-1 text-[9px] font-black text-amber-100 disabled:opacity-40"
        >
          <Info className="h-3 w-3" />{t('pets.feedButton')}
        </button>
        {pet.isActive ? (
          <button type="button" disabled className="flex h-10 items-center justify-center gap-1 rounded-lg border border-emerald-300/30 bg-emerald-950/45 px-1 text-[9px] font-black text-emerald-300">
            <Check className="h-3 w-3" />{t('pets.equipped')}
          </button>
        ) : (
          <button
            type="button"
            onClick={onActivate}
            disabled={pending}
            className="flex h-10 items-center justify-center rounded-lg border border-amber-300/30 bg-gradient-to-b from-amber-400 to-orange-600 px-1 text-[9px] font-black text-black disabled:grayscale disabled:opacity-40"
          >
            {t('pets.activate')}
          </button>
        )}
      </div>

      {pet.canEvolve && <div className="absolute inset-x-4 bottom-0 h-0.5 animate-pulse bg-gradient-to-r from-transparent via-violet-300 to-transparent" />}
    </div>
  );
}

function Stat({ icon, label, value }: { icon: React.ReactNode; label: string; value: number }) {
  return (
    <div className="rounded-2xl border border-amber-300/15 bg-black/55 p-3">
      <div className="h-8 w-8 text-amber-300">{icon}</div>
      <p className="mt-2 text-[9px] text-slate-400">{label}</p>
      <b>{fmt(value)}</b>
    </div>
  );
}

/** Purchase confirmation: prices come from the server payload, never from the client. */
function BuyEggModal({ egg, balance, pending, onClose, onBuyFc, onBuyTon }: { egg: PetEgg; balance: number; pending: boolean; onClose: () => void; onBuyFc: (quantity: number) => void; onBuyTon: () => void }) {
  const t = useT();
  const [quantity, setQuantity] = useState(1);
  const isTon = !egg.priceFc && !!egg.priceTon;
  const unit = egg.priceFc ?? 0;
  const total = unit * quantity;
  const missing = !isTon && total > balance;
  return (
    <div className="fixed inset-0 z-[95] flex items-end justify-center bg-black/80 p-3" onClick={onClose}>
      <div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-4" onClick={(event) => event.stopPropagation()}>
        <header className="mb-3 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.25em] text-amber-300">{t('pets.buyEggTitle')}</p>
            <h2 className={`break-words text-lg font-black leading-tight ${egg.slug === 'mythic-egg' ? 'egg-name-mythic' : ''}`}>{cleanEggName(egg.name)}</h2>
          </div>
          <button type="button" onClick={onClose} aria-label={t('pets.close')} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
        </header>

        <img src={egg.image} alt={cleanEggName(egg.name)} className="mx-auto h-28 w-28 max-w-full object-contain" />

        <div className="mt-2 flex flex-wrap items-center justify-center gap-2">
          {sortedRates(egg.rarityRates).map(([key, value]) => (
            <span key={key} style={{ color: rarityColor[String(key).toLowerCase()] }} className="whitespace-nowrap text-[9px] font-bold">{petRarityLabel(key)} {value}%</span>
          ))}
        </div>

        {isTon ? (
          <div className="mt-4 rounded-2xl border border-sky-300/30 bg-sky-500/10 p-3 text-center">
            <p className="text-[9px] uppercase tracking-[.2em] text-sky-200">{t('pets.price')}</p>
            <b className="text-2xl">{formatTon(egg.priceTon)} TON</b>
            <p className="mt-1 text-[9px] leading-relaxed text-slate-400">
              {t('pets.premiumNote')}
            </p>
          </div>
        ) : (
          <>
            <QuantityPicker quantity={quantity} onChange={setQuantity} max={20} />
            <div className="mt-3 rounded-2xl border border-white/10 bg-black/50 p-3 text-[10px]">
              <Row label={t('pets.unitPrice')} value={`${fmt(unit)} FC`} />
              <Row label={t('pets.quantity')} value={`${quantity}x`} />
              <Row label={t('pets.total')} value={`${fmt(total)} FC`} strong />
              <Row label={t('pets.currentBalance')} value={`${fmt(balance)} FC`} />
              <Row label={t('pets.afterPurchase')} value={`${fmt(Math.max(0, balance - total))} FC`} danger={missing} />
            </div>
          </>
        )}

        <div className="mt-3 grid grid-cols-2 gap-2">
          <button type="button" onClick={onClose} className="rounded-xl border border-white/15 bg-white/5 py-2 text-[9px] font-black uppercase text-slate-200">{t('pets.cancel')}</button>
          <button
            type="button"
            disabled={pending || (!isTon && (missing || unit <= 0))}
            onClick={() => (isTon ? onBuyTon() : onBuyFc(quantity))}
            className="flex items-center justify-center gap-1 rounded-xl border border-amber-300/30 bg-gradient-to-b from-amber-400 to-orange-600 py-2 text-[9px] font-black uppercase text-black disabled:grayscale disabled:opacity-40"
          >
            <ShoppingCart className="h-3 w-3" />
            {isTon ? t('pets.payWithTon') : missing ? t('pets.insufficientBalance') : t('common.buy')}
          </button>
        </div>
      </div>
    </div>
  );
}

function BuyFoodModal({ food, balance, pending, onClose, onBuy }: { food: PetFood; balance: number; pending: boolean; onClose: () => void; onBuy: (quantity: number) => void }) {
  const t = useT();
  const [quantity, setQuantity] = useState(1);
  const unit = food.priceFc ?? 0;
  const total = unit * quantity;
  const missing = total > balance;
  return (
    <div className="fixed inset-0 z-[95] flex items-end justify-center bg-black/80 p-3" onClick={onClose}>
      <div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-4" onClick={(event) => event.stopPropagation()}>
        <header className="mb-3 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.25em] text-amber-300">{t('pets.buyFoodTitle')}</p>
            <h2 className="truncate text-lg font-black">{PET_FOOD_ICONS[food.icon] ?? '🍖'} {food.name}</h2>
            <p className="text-[10px] text-emerald-300">{t('pets.xpPerUnitShort', { xp: fmt(food.xpValue) })}</p>
          </div>
          <button type="button" onClick={onClose} aria-label={t('pets.close')} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
        </header>

        <QuantityPicker quantity={quantity} onChange={setQuantity} max={200} shortcuts={[1, 5, 10, 25, 50]} />

        <div className="mt-3 rounded-2xl border border-white/10 bg-black/50 p-3 text-[10px]">
          <Row label={t('pets.unitPrice')} value={`${fmt(unit)} FC`} />
          <Row label={t('pets.xpTotal')} value={`+${fmt(food.xpValue * quantity)} XP`} />
          <Row label={t('pets.total')} value={`${fmt(total)} FC`} strong />
          <Row label={t('pets.currentBalance')} value={`${fmt(balance)} FC`} />
          <Row label={t('pets.afterPurchase')} value={`${fmt(Math.max(0, balance - total))} FC`} danger={missing} />
        </div>

        <div className="mt-3 grid grid-cols-2 gap-2">
          <button type="button" onClick={onClose} className="rounded-xl border border-white/15 bg-white/5 py-2 text-[9px] font-black uppercase text-slate-200">{t('pets.cancel')}</button>
          <button
            type="button"
            disabled={pending || missing || unit <= 0}
            onClick={() => onBuy(quantity)}
            className="flex items-center justify-center gap-1 rounded-xl border border-amber-300/30 bg-gradient-to-b from-amber-400 to-orange-600 py-2 text-[9px] font-black uppercase text-black disabled:grayscale disabled:opacity-40"
          >
            <ShoppingCart className="h-3 w-3" />
            {missing ? t('pets.insufficientBalance') : t('pets.buyQuantity', { quantity })}
          </button>
        </div>
      </div>
    </div>
  );
}

function QuantityPicker({ quantity, onChange, max, shortcuts = [1, 5, 10] }: { quantity: number; onChange: (value: number) => void; max: number; shortcuts?: number[] }) {
  const t = useT();
  const clamp = (value: number) => Math.max(1, Math.min(max, value));
  return (
    <div className="mt-4">
      <p className="text-[9px] uppercase tracking-[.2em] text-slate-400">{t('pets.quantity')}</p>
      <div className="mt-2 flex items-center gap-2">
        <button type="button" aria-label={t('pets.decreaseAria')} onClick={() => onChange(clamp(quantity - 1))} className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-white/15 bg-white/5"><Minus className="h-4 w-4" /></button>
        <b className="flex-1 rounded-xl border border-amber-300/25 bg-black/50 py-2 text-center text-lg">{quantity}</b>
        <button type="button" aria-label={t('pets.increaseAria')} onClick={() => onChange(clamp(quantity + 1))} className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-white/15 bg-white/5"><Plus className="h-4 w-4" /></button>
      </div>
      <div className="mt-2 flex gap-1">
        {shortcuts.filter((value) => value <= max).map((value) => (
          <button
            key={value}
            type="button"
            onClick={() => onChange(value)}
            className={`flex-1 rounded-lg py-1.5 text-[9px] font-black ${quantity === value ? 'bg-amber-400 text-black' : 'bg-white/5 text-slate-300'}`}
          >
            {value}
          </button>
        ))}
      </div>
    </div>
  );
}

function Row({ label, value, strong, danger }: { label: string; value: string; strong?: boolean; danger?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-2 py-0.5">
      <span className="text-slate-400">{label}</span>
      <b className={danger ? 'text-rose-300' : strong ? 'text-amber-200' : 'text-slate-200'}>{value}</b>
    </div>
  );
}
