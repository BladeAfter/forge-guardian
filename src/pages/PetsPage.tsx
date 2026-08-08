import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Check, ChevronUp, Coins, Egg, Flame, Heart, Info, Shield, Sparkles, Star, Swords, X, Zap } from 'lucide-react';
import { toast } from 'sonner';
import { usePetDashboard } from '../hooks';
import { petRequest } from '../services';
import type { PetActionResponse, PetDashboard, PetEvolveResult, PetFood, PlayerPet } from '../pets';
import type { PetRarity } from '../petRules';
import { petBuffLabel, petRarityLabel, petStageLabel, PET_FOOD_ICONS } from '../petLabels';
import { PetEggOpeningOverlay, type EggRevealResult } from '../components/PetEggOpeningOverlay';

type Tab = 'pets' | 'eggs' | 'food' | 'evolution' | 'catalog';

const TAB_LABELS: Record<Tab, string> = { pets: 'Meus Pets', eggs: 'Ovos', food: 'Comidas', evolution: 'Evolução', catalog: 'Catálogo' };
const rarityColor: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24' };

const PET_RARITY_STYLE: Record<PetRarity, { borderClass: string; glowClass: string; badgeClass: string }> = {
  common: { borderClass: 'border-slate-400/55', glowClass: 'from-slate-400/20', badgeClass: 'border-slate-300/40 bg-slate-500/15 text-slate-200' },
  uncommon: { borderClass: 'border-emerald-400/55', glowClass: 'from-emerald-400/25', badgeClass: 'border-emerald-300/45 bg-emerald-500/15 text-emerald-200' },
  rare: { borderClass: 'border-blue-400/60', glowClass: 'from-blue-500/30', badgeClass: 'border-blue-300/50 bg-blue-500/15 text-blue-200' },
  epic: { borderClass: 'border-violet-400/65', glowClass: 'from-violet-500/35', badgeClass: 'border-violet-300/50 bg-violet-500/15 text-violet-200' },
  legendary: { borderClass: 'border-amber-300/80', glowClass: 'from-amber-400/40', badgeClass: 'border-amber-200/60 bg-amber-500/20 text-amber-100' },
};

const BUFF_ICONS: Record<string, JSX.Element> = {
  boss_damage_percent: <Flame />, team_hp_percent: <Heart />, farm_fc_percent: <Coins />,
  pvp_attack_percent: <Swords />, pvp_defense_percent: <Shield />, drop_chance_percent: <Star />,
};
const buffIcon = (key?: string | null) => (key && BUFF_ICONS[key]) || <Zap />;

const fmt = (value: number) => Math.round(value).toLocaleString('pt-BR');

export function PetsPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const queryClient = useQueryClient();
  const { data, isLoading, error } = usePetDashboard(telegramInitData, true);
  const [tab, setTab] = useState<Tab>('pets');
  const [reveal, setReveal] = useState<{ result: EggRevealResult; eggImage: string; pet?: PlayerPet } | null>(null);
  const [feedTarget, setFeedTarget] = useState<PlayerPet | null>(null);
  const [evolution, setEvolution] = useState<PetEvolveResult | null>(null);

  const sync = async (fresh?: PetDashboard) => {
    if (fresh) queryClient.setQueryData(['pet-dashboard', telegramInitData], fresh);
    await Promise.all(
      ['pet-dashboard', 'boss-combat', 'pvp-dashboard', 'wallet-summary', 'game-state'].map((key) =>
        queryClient.invalidateQueries({ queryKey: [key] }),
      ),
    );
  };

  const mutation = useMutation({
    mutationFn: (input: Parameters<typeof petRequest>[1]) => petRequest(telegramInitData, input) as Promise<PetActionResponse>,
    onSuccess: async (payload, variables) => {
      const dashboard = (payload.dashboard ?? (payload as PetDashboard)) as PetDashboard;
      await sync(dashboard);
      if (payload.result) {
        const hatched = dashboard.playerPets.find((pet) => pet.petId === payload.result?.petId || pet.name === payload.result?.name);
        const eggImage = (variables?.action === 'hatch' ? dashboard.eggs.find((egg) => egg.id === variables.eggId)?.image : null)
          || '/assets/game/pet-eggs/common-egg.webp';
        setReveal({ result: { ...payload.result, rarity: payload.result.rarity as PetRarity }, eggImage, pet: hatched });
        return;
      }
      if (payload.feedResult) {
        const { xpGained, levelsGained, foodName, quantity } = payload.feedResult;
        toast.success(
          levelsGained > 0
            ? `${quantity}x ${foodName}: +${fmt(xpGained)} XP e ${levelsGained} nível(is) ganho(s)!`
            : `${quantity}x ${foodName}: +${fmt(xpGained)} XP`,
        );
        setFeedTarget(null);
        return;
      }
      if (payload.evolveResult) {
        setEvolution(payload.evolveResult);
        return;
      }
      toast.success('Companheiro atualizado!');
    },
    onError: (mutationError) => toast.error(mutationError instanceof Error ? mutationError.message : 'Falha ao atualizar o pet.'),
  });

  const pending = mutation.isPending;

  if (isLoading) return <Shell onClose={onClose}><p className="py-24 text-center text-sm text-amber-200">Carregando companheiros...</p></Shell>;
  if (error || !data) {
    return (
      <Shell onClose={onClose}>
        <p className="py-24 text-center text-sm text-rose-300">
          {error instanceof Error ? error.message : 'Não foi possível carregar os pets.'}
        </p>
      </Shell>
    );
  }

  const active = data.activePet;
  const liveFeedTarget = feedTarget ? data.playerPets.find((pet) => pet.id === feedTarget.id) ?? null : null;

  return (
    <Shell onClose={onClose}>
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-400/30 bg-gradient-to-b from-sky-950/55 to-black/80 p-4 shadow-[0_0_40px_rgba(245,158,11,.12)]">
        {active ? (
          <>
            <div className="flex items-center gap-4">
              <img src={active.image} alt={active.name} className="h-32 w-32 shrink-0 object-contain drop-shadow-[0_0_22px_rgba(251,191,36,.4)]" />
              <div className="min-w-0">
                <p className="text-[9px] uppercase tracking-[.25em] text-amber-300">Companheiro ativo</p>
                <h2 className="truncate text-2xl font-black">{active.name}</h2>
                <p style={{ color: rarityColor[active.rarity] }} className="text-xs font-bold uppercase">
                  {petRarityLabel(active.rarity)} · Nível {active.level}/{active.maxLevel}
                </p>
                <p className="text-[10px] text-slate-400">
                  {petStageLabel(active.evolutionStage)} · {active.evolutionLabel} · Poder {fmt(active.power)}
                </p>
              </div>
            </div>

            <LevelBar pet={active} />
            <BuffGrid pet={active} />

            <div className="mt-3 grid grid-cols-2 gap-2">
              <Action text="Alimentar" disabled={pending || active.isMaxLevel} onClick={() => setFeedTarget(active)} />
              <EvolveButton pet={active} balance={data.balance} pending={pending} onEvolve={() => evolve(active)} />
            </div>
            <p className="mt-2 text-center text-[9px] leading-relaxed text-slate-400">
              Comida sobe o <b className="text-amber-200">nível</b>. Fragmentos e Forge Coins liberam a <b className="text-violet-200">evolução</b>.
            </p>
          </>
        ) : (
          <div className="grid min-h-48 place-items-center text-center">
            <div>
              <Egg className="mx-auto h-14 w-14 text-slate-600" />
              <h2 className="mt-2 text-xl font-black">Nenhum pet ativo</h2>
              <p className="text-xs text-slate-400">Escolha um companheiro em Meus Pets.</p>
            </div>
          </div>
        )}
      </section>

      <nav className="mt-3 grid grid-cols-5 gap-1">
        {(Object.keys(TAB_LABELS) as Tab[]).map((key) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={`rounded-xl px-1 py-2 text-[8px] font-black uppercase ${tab === key ? 'bg-amber-400 text-black' : 'bg-white/5 text-slate-300'}`}
          >
            {TAB_LABELS[key]}
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
            {data.playerPets.length === 0 && <p className="col-span-2 py-16 text-center text-sm text-slate-400">Você ainda não tem pets. Abra um ovo para começar.</p>}
          </div>
        )}

        {tab === 'eggs' && (
          <div className="grid grid-cols-2 gap-2">
            {data.eggs.map((egg) => (
              <div key={egg.id} className="rounded-2xl border border-amber-300/20 bg-black/55 p-3 text-center">
                <img src={egg.image} alt={egg.name} className="mx-auto h-24 w-24 object-contain" />
                <h3 className="text-xs font-black">{egg.name}</h3>
                <p className="text-[9px] text-slate-400">Você possui: {egg.quantity}</p>
                <div className="mt-2 flex flex-wrap justify-center gap-1">
                  {Object.entries(egg.rarityRates).map(([key, value]) => (
                    <span key={key} style={{ color: rarityColor[key] }} className="text-[8px] font-bold">
                      {petRarityLabel(key)} {value}%
                    </span>
                  ))}
                </div>
                <Action
                  text="Abrir ovo"
                  disabled={pending || egg.quantity < 1}
                  onClick={() => mutation.mutate({ action: 'hatch', eggId: egg.id, idempotencyKey: crypto.randomUUID() })}
                />
              </div>
            ))}
          </div>
        )}

        {tab === 'food' && (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2">
              {data.foods.map((food) => (
                <div key={food.code} className="rounded-2xl border border-amber-300/15 bg-black/55 p-3">
                  <div className="flex items-center gap-2">
                    <span className="text-2xl leading-none">{PET_FOOD_ICONS[food.icon] ?? '🍖'}</span>
                    <div className="min-w-0">
                      <p className="truncate text-[11px] font-black">{food.name}</p>
                      <p className="text-[9px] text-emerald-300">+{fmt(food.xpValue)} XP por unidade</p>
                    </div>
                  </div>
                  <p className="mt-2 text-[9px] text-slate-400">Quantidade</p>
                  <b className="text-lg">{fmt(food.quantity)}</b>
                </div>
              ))}
            </div>
            <h3 className="pt-1 text-[10px] font-black uppercase tracking-[.2em] text-amber-300">Fragmentos por pet</h3>
            <div className="grid grid-cols-2 gap-2">
              <Stat icon={<Star />} label="Fragmentos universais" value={data.inventory.universalFragments} />
              {data.fragments.map((entry) => (
                <Stat
                  key={entry.playerPetId}
                  icon={<img src={entry.image} alt={entry.petName} className="h-8 w-8 object-contain" />}
                  label={`Fragmentos de ${entry.petName}`}
                  value={entry.quantity}
                />
              ))}
            </div>
          </div>
        )}

        {tab === 'evolution' && (
          <div className="space-y-2">
            {data.playerPets.map((pet) => (
              <EvolutionRow key={pet.id} pet={pet} balance={data.balance} pending={pending} onEvolve={() => evolve(pet)} onFeed={() => setFeedTarget(pet)} />
            ))}
          </div>
        )}

        {tab === 'catalog' && (
          <div className="grid grid-cols-2 gap-2">
            {data.catalog.map((pet) => (
              <div key={pet.id} className={`rounded-2xl border p-3 text-center ${pet.discovered ? 'border-amber-300/20 bg-black/55' : 'border-white/5 bg-black/30 grayscale'}`}>
                <img src={pet.images.baby} alt={pet.name} className={`mx-auto h-24 w-24 object-contain ${pet.discovered ? '' : 'brightness-0'}`} />
                <b className="text-xs">{pet.discovered ? pet.name : 'Não descoberto'}</b>
                <p className="text-[9px] text-slate-400">
                  {pet.species} · {pet.discovered ? `${petRarityLabel(pet.bestRarity)} · Nível ${pet.bestLevel ?? 1}` : 'Disponível em ovos'}
                </p>
              </div>
            ))}
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
                  await mutation.mutateAsync({ action: 'activate', playerPetId: reveal.pet!.id });
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

function Shell({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-[70] overflow-y-auto bg-[#05080e] text-white">
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top,#122542_0%,#05080e_55%)]" />
      <div className="forge-safe-page relative mx-auto min-h-full w-full max-w-[480px] p-3">
        <header className="mb-3 flex items-center justify-between gap-2 rounded-2xl border border-amber-300/20 bg-black/70 p-3">
          <div className="min-w-0">
            <p className="text-[9px] uppercase tracking-[.3em] text-amber-300">Forge Village</p>
            <h1 className="text-xl font-black">PETS</h1>
          </div>
          <button type="button" onClick={onClose} aria-label="Fechar" className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-white/5"><X /></button>
        </header>
        {children}
      </div>
    </div>
  );
}

function LevelBar({ pet }: { pet: PlayerPet }) {
  const percent = pet.isMaxLevel ? 100 : Math.min(100, (pet.xp / Math.max(1, pet.xpRequired)) * 100);
  return (
    <>
      <div className="mt-3 h-2 overflow-hidden rounded-full bg-white/10">
        <div className="h-full bg-gradient-to-r from-amber-500 to-yellow-200 transition-[width] duration-500" style={{ width: `${percent}%` }} />
      </div>
      <p className="mt-1 text-right text-[9px] text-slate-400">
        {pet.isMaxLevel ? 'Nível máximo alcançado' : `XP ${fmt(pet.xp)} / ${fmt(pet.xpRequired)}`}
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
        <div key={key} className="rounded-xl bg-black/45 p-2">
          <p className="flex items-center gap-1 text-[8px] text-slate-400">
            <span className="h-3 w-3 text-amber-300">{buffIcon(key)}</span>
            <span className="truncate">{petBuffLabel(key)}</span>
          </p>
          <b className={`text-xs ${secondary.has(key) ? 'text-violet-300' : 'text-emerald-300'}`}>+{value}%</b>
        </div>
      ))}
    </div>
  );
}

function EvolveButton({ pet, balance, pending, onEvolve }: { pet: PlayerPet; balance: number; pending: boolean; onEvolve: () => void }) {
  const next = pet.nextEvolution;
  if (!next) return <Action text="Evolução máxima" disabled onClick={() => undefined} />;
  const missingLevel = pet.level < next.requiredLevel;
  const missingFc = balance < next.fcCost;
  const missingFragments = pet.fragments < next.fragmentCost;
  const ready = !missingLevel && !missingFc && !missingFragments;
  const label = missingLevel ? `Evoluir no nível ${next.requiredLevel}` : missingFc ? 'Forge Coins insuficientes' : missingFragments ? 'Fragmentos insuficientes' : `Evoluir · ${next.label}`;
  return (
    <button
      type="button"
      onClick={onEvolve}
      disabled={pending || !ready}
      className={`mt-2 flex w-full items-center justify-center gap-1 rounded-xl border px-2 py-2 text-[9px] font-black uppercase transition disabled:grayscale disabled:opacity-40 ${
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

function EvolutionRow({ pet, balance, pending, onEvolve, onFeed }: { pet: PlayerPet; balance: number; pending: boolean; onEvolve: () => void; onFeed: () => void }) {
  const next = pet.nextEvolution;
  return (
    <div className={`rounded-2xl border bg-black/55 p-3 ${pet.canEvolve ? 'border-violet-300/50 shadow-[0_0_18px_rgba(168,85,247,.2)]' : 'border-white/10'}`}>
      <div className="flex items-center gap-3">
        <img src={pet.image} alt={pet.name} className="h-16 w-16 shrink-0 object-contain" />
        <div className="min-w-0 flex-1">
          <b className="block truncate text-sm">{pet.name}</b>
          <p className="text-[9px] text-slate-400">
            Nível {pet.level}/{pet.maxLevel} · {petStageLabel(pet.evolutionStage)} · {pet.evolutionLabel}
          </p>
          {next ? (
            <p className="mt-1 text-[9px] leading-relaxed text-slate-300">
              Requisitos: nível <b className={pet.level >= next.requiredLevel ? 'text-emerald-300' : 'text-rose-300'}>{next.requiredLevel}</b>
              {' · '}
              <b className={balance >= next.fcCost ? 'text-emerald-300' : 'text-rose-300'}>{fmt(next.fcCost)} FC</b>
              {' · '}
              <b className={pet.fragments >= next.fragmentCost ? 'text-emerald-300' : 'text-rose-300'}>{next.fragmentCost} fragmentos</b>
              {' · '}
              <span className="text-violet-300">{next.newBuffChance}% de novo bônus</span>
            </p>
          ) : (
            <p className="mt-1 text-[9px] text-amber-200">Este companheiro alcançou a forma final.</p>
          )}
          {next && (
            <p className="mt-1 text-[9px] text-slate-400">
              {petBuffLabel(pet.primaryBuffKey)}: <span className="text-slate-300">+{next.primaryFrom}%</span> → <span className="text-emerald-300">+{next.primaryTo}%</span>
            </p>
          )}
        </div>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Action text="Alimentar" disabled={pending || pet.isMaxLevel} onClick={onFeed} />
        <EvolveButton pet={pet} balance={balance} pending={pending} onEvolve={onEvolve} />
      </div>
    </div>
  );
}

function FeedModal({ pet, foods, pending, onClose, onFeed }: { pet: PlayerPet; foods: PetFood[]; pending: boolean; onClose: () => void; onFeed: (foodCode: string, quantity: number) => void }) {
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
            <p className="text-[9px] uppercase tracking-[.25em] text-amber-300">Alimentar</p>
            <h2 className="truncate text-lg font-black">{pet.name}</h2>
            <p className="text-[10px] text-slate-400">Nível {pet.level} · faltam {fmt(missing)} XP para o próximo nível</p>
          </div>
          <button type="button" onClick={onClose} aria-label="Fechar" className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/5"><X className="h-4 w-4" /></button>
        </header>

        {available.length === 0 ? (
          <p className="py-8 text-center text-sm text-slate-300">Você não possui comidas. Consiga comidas em recompensas e eventos.</p>
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
              <label htmlFor="pet-food-quantity" className="text-[9px] uppercase tracking-[.2em] text-slate-400">Quantidade: {safeQuantity}</label>
              <input
                id="pet-food-quantity"
                type="range"
                min={1}
                max={max}
                value={safeQuantity}
                onChange={(event) => setQuantity(Number(event.target.value))}
                className="mt-2 w-full accent-amber-400"
              />
              <p className="mt-1 text-center text-[10px] text-emerald-300">Ganho estimado: +{fmt(preview)} XP</p>
            </div>

            <Action text={`Alimentar com ${safeQuantity}x`} disabled={pending || !food} onClick={() => food && onFeed(food.code, safeQuantity)} />
          </>
        )}
      </div>
    </div>
  );
}

function EvolutionOverlay({ result, onClose }: { result: PetEvolveResult; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-[99] grid place-items-center bg-black/85 p-4 pet-evolution-overlay">
      <div className="w-full max-w-sm rounded-3xl border border-violet-300/50 bg-[#0a0714] p-5 text-center shadow-[0_0_60px_rgba(168,85,247,.35)]">
        <Sparkles className="mx-auto h-10 w-10 animate-pulse text-violet-300" />
        <p className="mt-2 text-[9px] uppercase tracking-[.3em] text-violet-300">Evolução concluída</p>
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
            <p className="text-[9px] uppercase tracking-[.2em] text-amber-300">Novo bônus desbloqueado</p>
            <p className="mt-1 text-sm font-black text-amber-100">
              {petBuffLabel(result.newBuff.key)} +{result.newBuff.value}%
            </p>
            <p className="text-[9px] text-slate-400">Qualidade {petRarityLabel(result.newBuff.rarity)}</p>
          </div>
        ) : (
          <p className="mt-3 text-[10px] text-slate-400">Nenhum bônus extra desta vez. Tente na próxima evolução.</p>
        )}

        <p className="mt-3 text-[9px] text-slate-500">
          Custo: {fmt(result.fcSpent)} FC · {result.fragmentsSpent} fragmentos
        </p>
        <Action text="Continuar" onClick={onClose} />
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

function PetCard({ pet, onFeed, onActivate, pending }: { pet: PlayerPet; onFeed: () => void; onActivate?: () => void; pending: boolean }) {
  const style = PET_RARITY_STYLE[pet.rarity] ?? PET_RARITY_STYLE.common;
  return (
    <div
      className={`group relative flex flex-col overflow-hidden rounded-[1.35rem] border bg-gradient-to-b from-[#102039] via-[#08111f] to-[#03070d] p-2.5 text-center shadow-[0_16px_30px_rgba(0,0,0,.45)] transition duration-200 active:scale-[.98] ${style.borderClass} ${
        pet.isActive ? 'ring-1 ring-emerald-300/25' : ''
      }`}
    >
      <div className={`pointer-events-none absolute left-1/2 top-10 h-40 w-40 -translate-x-1/2 rounded-full bg-gradient-to-b ${style.glowClass} to-transparent blur-xl`} />
      <div className="relative z-10 flex items-start justify-between gap-1">
        <span className={`rounded-full border px-2 py-1 text-[7px] font-black tracking-[.12em] ${style.badgeClass}`}>{petRarityLabel(pet.rarity)}</span>
        {pet.isActive && (
          <span className="flex items-center gap-1 rounded-full border border-emerald-300/45 bg-emerald-950/80 px-2 py-1 text-[7px] font-black text-emerald-200">
            <Check className="h-2.5 w-2.5" />ATIVO
          </span>
        )}
      </div>

      <div className="relative z-10 mt-1 grid h-[124px] place-items-center">
        <img src={pet.image} alt={pet.name} className="h-[118px] w-full object-contain drop-shadow-[0_10px_14px_rgba(0,0,0,.8)]" />
      </div>

      <div className="relative z-10">
        <h3 className="truncate text-base font-black uppercase tracking-wide">{pet.name}</h3>
        <p className="mt-1 text-[9px] font-bold text-slate-300">Nível {pet.level}/{pet.maxLevel} · Poder {fmt(pet.power)}</p>
        <p className="text-[8px] text-slate-500">{petStageLabel(pet.evolutionStage)} · {pet.evolutionLabel}</p>
      </div>

      <div className="relative z-10 mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
        <div className="h-full bg-gradient-to-r from-amber-500 to-yellow-200" style={{ width: `${pet.isMaxLevel ? 100 : Math.min(100, (pet.xp / Math.max(1, pet.xpRequired)) * 100)}%` }} />
      </div>

      <div className="relative z-10 mt-2 rounded-xl border border-white/10 bg-black/45 px-2 py-2">
        <div className="flex items-center justify-center gap-1.5 text-[8px] font-bold uppercase tracking-wide text-slate-300">
          <span className="h-3.5 w-3.5" style={{ color: rarityColor[pet.rarity] }}>{buffIcon(pet.primaryBuffKey)}</span>
          <span className="truncate">{petBuffLabel(pet.primaryBuffKey)}</span>
        </div>
        <b className="mt-1 block text-lg leading-none" style={{ color: rarityColor[pet.rarity] }}>+{pet.primaryBuffValue}%</b>
        {pet.secondaryBuffs.length > 0 && (
          <p className="mt-1 text-[8px] text-violet-300">
            +{pet.secondaryBuffs.length} bônus secundário{pet.secondaryBuffs.length > 1 ? 's' : ''}
          </p>
        )}
      </div>

      <div className="relative z-10 mt-auto grid grid-cols-2 gap-1.5 pt-3">
        <button
          type="button"
          onClick={onFeed}
          disabled={pending || pet.isMaxLevel}
          className="flex h-9 items-center justify-center gap-1 rounded-lg border border-amber-300/35 bg-black/40 px-1 text-[8px] font-black text-amber-100 disabled:opacity-40"
        >
          <Info className="h-3 w-3" />ALIMENTAR
        </button>
        {pet.isActive ? (
          <button type="button" disabled className="flex h-9 items-center justify-center gap-1 rounded-lg border border-emerald-300/30 bg-emerald-950/45 px-1 text-[8px] font-black text-emerald-300">
            <Check className="h-3 w-3" />EQUIPADO
          </button>
        ) : (
          <button
            type="button"
            onClick={onActivate}
            disabled={pending}
            className="flex h-9 items-center justify-center rounded-lg border border-amber-300/30 bg-gradient-to-b from-amber-400 to-orange-600 px-1 text-[8px] font-black text-black disabled:grayscale disabled:opacity-40"
          >
            ATIVAR
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
