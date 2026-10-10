import { useLocalizedText } from '../LanguageContext';
import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { RARITY_COLORS, type HeroRarity } from '../heroCatalog';
import type { PvpHero } from '../pvp';
import { useTowerDashboard, useTowerRanking } from '../hooks';
import { enterTowerFloor, equipTowerHero, removeTowerHero } from '../services';
import { useMythUtility } from '../hooks';
import { formatMyth, mythDiscountLabel, mythPrice } from '../mythUtility';
import { TOWER_CHESTS, TOWER_KEYS, TOWER_MILESTONES, type TowerBattle, type TowerDashboard } from '../tower';
import { towerBossTheme } from '../towerBosses';
import { TowerBattleArena } from './TowerBattleArena';
import { PetCompanion } from './PetCompanion';
import { RareKeyShop } from './RareKeyShop';
import { activePetBonuses } from '../petBonuses';
import { useT } from '../LanguageContext';

type Props = {
  balance: number;
  collection?: PvpHero[];
  collectionLoading?: boolean;
  telegramInitData?: string | null;
};

const compact = (value: number) => Math.floor(Math.max(0, Number(value) || 0)).toLocaleString();
const templateOf = (h: { templateId?: string; heroKey?: string; name: string; heroId: string }) =>
  String(h.templateId || h.heroKey || h.name || h.heroId).toLowerCase();
const normalizeRarity = (value?: string): HeroRarity => {
  const key = String(value ?? '').trim().toLowerCase();
  return (['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral', 'nft_exclusive', 'celestial'] as HeroRarity[]).includes(key as HeroRarity)
    ? (key as HeroRarity)
    : 'common';
};

export function TowerOfEternityPanel({ balance, collection, collectionLoading, telegramInitData }: Props) {
  const localizeText = useLocalizedText();

  const t = useT();
  const q = useQueryClient();
  const initData = telegramInitData ?? '';
  const tower = useTowerDashboard(initData || null, Boolean(initData));
  const [isTeamOpen, setIsTeamOpen] = useState(false);
  const [slot, setSlot] = useState<number | null>(null);
  const [battle, setBattle] = useState<TowerBattle | null>(null);
  const [isRankingOpen, setIsRankingOpen] = useState(false);
  const [payWith, setPayWith] = useState<'fc' | 'ton' | 'myth'>('fc');
  const ranking = useTowerRanking(initData || null, Boolean(initData) && isRankingOpen);
  const { data: myth } = useMythUtility(initData || null);

  const data = tower.data;
  const heroes = useMemo(() => (collection ?? []).slice().sort((a, b) => (b.power ?? 0) - (a.power ?? 0)), [collection]);
  const team = data?.team ?? [];
  const usedTemplates = useMemo(() => new Set(team.map(templateOf)), [team]);
  const theme = towerBossTheme(data?.boss?.bossKey);

  const setDashboard = (next: TowerDashboard) => q.setQueryData(['tower-dashboard', initData], next);
  const refresh = () => Promise.all([
    q.invalidateQueries({ queryKey: ['tower-dashboard', initData] }),
    q.invalidateQueries({ queryKey: ['game-state', initData] }),
    q.invalidateQueries({ queryKey: ['player-inventory'] }),
    q.invalidateQueries({ queryKey: ['player-heroes'] }),
    q.invalidateQueries({ queryKey: ['hero-fusion'] }),
    q.invalidateQueries({ queryKey: ['rarity-fusion'] }),
  ]);

  const equip = useMutation({
    mutationFn: ({ targetSlot, heroId }: { targetSlot: number; heroId: string }) => equipTowerHero(initData, targetSlot, heroId),
    onSuccess: next => { setDashboard(next); setSlot(null); },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : t('tower.equipFailed')),
  });
  const unequip = useMutation({
    mutationFn: (targetSlot: number) => removeTowerHero(initData, targetSlot),
    onSuccess: next => setDashboard(next),
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : t('tower.unequipFailed')),
  });
  const enter = useMutation({
    mutationFn: (currency: 'fc' | 'ton' | 'myth') => enterTowerFloor(initData, currency),
    onSuccess: async result => { setBattle(result); setDashboard(result.dashboard); await refresh(); },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : t('tower.enterFailed')),
  });

  if (battle) return <TowerBattleArena battle={battle} onContinue={async () => { setBattle(null); await refresh(); }} />;

  if (!initData) {
    return <section className="rounded-3xl border border-amber-400/25 bg-black/55 p-6 text-center text-xs text-slate-400">{t('tower.telegramOnly')}</section>;
  }
  if (tower.isLoading && !data) {
    return <section className="rounded-3xl border border-amber-400/25 bg-black/55 p-8 text-center text-xs text-slate-400">{t('tower.opening')}</section>;
  }
  if (tower.error || !data) {
    return (
      <section className="rounded-3xl border border-amber-400/25 bg-black/55 p-8 text-center">
        <p className="text-xs text-slate-300">{tower.error instanceof Error ? tower.error.message : t('tower.loadFailed')}</p>
        <button type="button" onClick={() => void tower.refetch()} className="mt-4 rounded-xl border border-amber-300/40 px-5 py-3 text-[11px] font-black uppercase tracking-[.12em] text-amber-200">{t('tower.tryAgain')}</button>
      </section>
    );
  }

  const boss = data.boss;
  const activePet = data.petSummary?.activePet ?? null;
  const petBuffs = activePetBonuses(data.petSummary?.bonuses ?? null, Object.keys(data.petSummary?.bonuses ?? {})).slice(0, 4);
  const rewards = data.firstClear ? data.rewards : data.replayRewards;
  // The server-side BERRIES balance is authoritative; the prop is only a fallback.
  const fc = Number.isFinite(Number(data.balanceFc)) ? Number(data.balanceFc) : Number(balance) || 0;
  const canEnter = !enter.isPending;
  // Second entry option: pay with the internal TON balance (no TonConnect, no conversion).
  const entryTon = Number(data.entryCostTon ?? 0.5);
  const tonBalance = Number(data.balanceTon ?? 0);
  // Third entry option: burn MYTH (price/discount come from the backend; staked MYTH is never used).
  const entryMyth = mythPrice(myth, 'TOWER_ENTRY', { fc: data.entryCost, ton: entryTon });
  const mythBalance = Number(myth?.available ?? 0);

  const start = () => {
    if (!team.length) { toast.error(t('tower.selectTeamFirst')); setIsTeamOpen(true); return; }
    if (data.attemptsRemaining <= 0) { toast.error(t('tower.noAttemptsToday')); return; }
    if (payWith === 'ton') {
      if (tonBalance < entryTon) { toast.error(t('tower.insufficientTon')); return; }
    } else if (payWith === 'myth') {
      if (entryMyth === null) { toast.error('Pagamento com MYTH indisponível.'); return; }
      if (mythBalance < entryMyth) { toast.error('MYTH insuficiente.'); return; }
    } else if (fc < data.entryCost) { toast.error(t('tower.insufficientFc')); return; }
    enter.mutate(payWith);
  };

  return (
    <section className="space-y-3">
      <div className={`relative overflow-hidden rounded-3xl border ${theme.border} bg-[#080a11] p-4 shadow-card`}>
        <img src={theme.arena} alt="" aria-hidden className="pointer-events-none absolute inset-0 h-full w-full object-cover opacity-30" />
        <div className="pointer-events-none absolute inset-0" style={{ background: theme.stage, opacity: .78 }} />
        <div className="relative text-center">
          <p className="text-[10px] uppercase tracking-[.32em] text-amber-300/80">{t('tower.solo')} • {data.totalFloors} {t('tower.floorsSuffix')}</p>
          <h3 className="mt-1 text-xl font-black uppercase tracking-wide text-amber-200">{t('tower.title')}</h3>
          <p className="mt-2 text-[11px] font-bold text-slate-200">
            {t('tower.floorLabel')} <span className="text-amber-300">{data.floor}</span> / {data.totalFloors}
          </p>
          <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-black/70">
            <div className="h-full rounded-full bg-gradient-to-r from-amber-500 to-amber-200" style={{ width: `${(data.floor / data.totalFloors) * 100}%` }} />
          </div>
        </div>

        <div className={`relative mt-4 overflow-hidden rounded-2xl border ${theme.border} bg-black/55 p-3 text-center`}>
          <div className="pointer-events-none absolute inset-0" style={{ background: theme.aura }} />
          <p className="relative text-[9px] uppercase tracking-[.3em] text-slate-400">{t('tower.floorBoss')}</p>
          <img src={theme.art} alt={boss.name} className="relative mx-auto mt-1 h-[132px] w-auto object-contain" style={{ filter: theme.glow }} loading="lazy" />
          <p className={`relative mt-1 text-base font-bold ${theme.accent}`}>{boss.name}</p>
          <p className="relative text-[9px] uppercase tracking-[.2em] text-slate-500">{t('tower.tierRole', { tier: boss.tier, role: boss.role })}</p>
        </div>

        {activePet ? (
          <div className="relative">
            <PetCompanion pet={activePet} buffs={petBuffs} size="sm" label={t('tower.petBuffActive')} />
          </div>
        ) : null}

        <div className="relative mt-3 grid grid-cols-3 gap-2 text-[10px]">
          <div className="rounded-2xl bg-black/65 p-2.5">
            <p className="text-slate-400">{t('tower.recommendedPower')}</p>
            <p className="mt-1 font-semibold text-amber-300">{compact(boss.recommendedPower)}</p>
          </div>
          <div className="rounded-2xl bg-black/65 p-2.5">
            <p className="text-slate-400">{t('tower.entryCost')}</p>
            <p className={`mt-1 font-semibold ${payWith === 'ton' ? (tonBalance >= entryTon ? 'text-sky-300' : 'text-rose-300') : (balance >= data.entryCost ? 'text-amber-300' : 'text-rose-300')}`}>
              {payWith === 'ton' ? `${entryTon.toFixed(2)} TON` : `${compact(data.entryCost)} BERRIES`}
            </p>
          </div>
          <div className="rounded-2xl bg-black/65 p-2.5">
            <p className="text-slate-400">{data.firstClear ? t('tower.firstClear') : t('tower.replay')}</p>
            <p className="mt-1 font-semibold text-emerald-300">{t('tower.fragmentsX', { count: rewards.fragments })}</p>
          </div>
        </div>

        {/* Payment choice for the entry: current 100k BERRIES option OR internal TON balance. */}
        <div className="relative mt-3 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={() => setPayWith('fc')}
            className={`min-h-10 rounded-2xl border text-[10px] font-black uppercase tracking-wide ${payWith === 'fc' ? 'border-amber-300/70 bg-amber-400/20 text-amber-200' : 'border-white/10 bg-black/50 text-slate-400'}`}
          >
            {compact(data.entryCost)} BERRIES
          </button>
          <button
            type="button"
            onClick={() => setPayWith('ton')}
            className={`min-h-10 rounded-2xl border text-[10px] font-black uppercase tracking-wide ${payWith === 'ton' ? 'border-sky-300/70 bg-sky-400/20 text-sky-200' : 'border-white/10 bg-black/50 text-slate-400'}`}
          >
            {entryTon.toFixed(2)} TON
          </button>
        </div>
        {entryMyth !== null && (
          <button
            type="button"
            onClick={() => setPayWith('myth')}
            className={`relative mt-2 min-h-10 w-full rounded-2xl border text-[10px] font-black uppercase tracking-wide ${payWith === 'myth' ? 'border-fuchsia-300/70 bg-fuchsia-400/20 text-fuchsia-100' : 'border-white/10 bg-black/50 text-slate-400'}`}
          >
            🔥 {formatMyth(entryMyth)} MYTH {mythDiscountLabel(myth) ? `(${mythDiscountLabel(myth)})` : ''} {localizeText(" · saldo")}{formatMyth(mythBalance)}
          </button>
        )}
        {payWith === 'ton' && tonBalance < entryTon ? (
          <div className="relative mt-2 rounded-2xl border border-rose-400/40 bg-rose-500/10 p-2.5 text-center">
            <p className="text-[10px] font-bold uppercase tracking-wide text-rose-200">{t('tower.insufficientTon')}</p>
            <button
              type="button"
              onClick={() => window.dispatchEvent(new CustomEvent('mythreon:navigate', { detail: 'wallet' }))}
              className="mt-2 min-h-10 w-full rounded-xl border border-sky-300/50 bg-sky-400/15 text-[10px] font-black uppercase tracking-wide text-sky-200"
            >
              {t('tower.depositTon')}
            </button>
          </div>
        ) : null}

        <div className="relative mt-3 grid gap-2">
          <button
            type="button"
            onClick={() => setIsRankingOpen(true)}
            className="min-h-11 rounded-2xl border border-amber-300/40 bg-amber-400/10 text-xs font-bold uppercase tracking-wide text-amber-300"
          >
            🏆 {t('tower.ranking')}
          </button>
          <button
            type="button"
            onClick={() => setIsTeamOpen(true)}
            className="min-h-11 rounded-2xl border border-amber-400/40 bg-amber-400/10 text-xs font-bold uppercase tracking-wide text-amber-200"
          >
            {t('tower.selectTeamCount', { count: team.length })}{team.length ? ` · ${compact(data.teamPower)}` : ''}
          </button>
          <button
            type="button"
            onClick={start}
            disabled={!canEnter}
            className="min-h-11 rounded-2xl bg-gradient-to-r from-amber-500 to-amber-300 text-xs font-black uppercase tracking-wide text-black disabled:opacity-45"
          >
            {enter.isPending ? t('tower.loadingBattle') : `${t('tower.enterDungeon')} • ${payWith === 'ton' ? `${entryTon.toFixed(2)} TON` : payWith === 'myth' ? `${formatMyth(entryMyth ?? 0)} MYTH` : `${compact(data.entryCost)} BERRIES`}`}
          </button>
        </div>
      </div>

      <div className="rounded-3xl border border-white/10 bg-black/50 p-3">
        <p className="text-[10px] uppercase tracking-[.28em] text-amber-300/80">{t('tower.possibleRewards')}</p>
        <div className="mt-2 grid grid-cols-2 gap-2 text-[10px]">
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">{t('tower.fragments')}</p><p className="mt-1 font-semibold text-sky-300">x{rewards.fragments}</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">{t('tower.heroXp')}</p><p className="mt-1 font-semibold text-amber-300">{compact(rewards.heroXp)}</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">{t('tower.petFood')}</p><p className="mt-1 font-semibold text-emerald-300">x{rewards.petFood}</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">{t('tower.gearChest')}</p><p className="mt-1 font-semibold text-fuchsia-300">{rewards.heroChest ? `x${rewards.heroChest}` : '—'}</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">{t('tower.fcBonus')}</p><p className="mt-1 font-semibold text-amber-200">{compact(rewards.forgeCoins ?? 0)} BERRIES</p></div>
          <div className="rounded-2xl bg-black/65 p-2.5"><p className="text-slate-400">{t('tower.universalFragments')}</p><p className="mt-1 font-semibold text-cyan-300">{rewards.universalFragments ? `x${rewards.universalFragments}` : '—'}</p></div>
        </div>

        {/* Baús premium: drop aleatório na Torre + garantidos nos andares de marco. */}
        <div className="mt-3 rounded-2xl border border-amber-300/25 bg-black/60 p-2.5">
          <div className="flex items-center justify-between">
            <p className="text-[9px] font-black uppercase tracking-[.22em] text-amber-300/90">{t('tower.premiumChests')}</p>
            <p className="text-[8px] uppercase tracking-[.14em] text-slate-500">{t('tower.chestMilestoneHint')}</p>
          </div>
          <div className="mt-2 grid grid-cols-3 gap-1.5">
            {TOWER_CHESTS.map(chest => {
              const chance = Number(rewards.chestChances?.[chest.code] ?? 0);
              return (
                <div key={chest.code} className="rounded-xl border bg-black/65 p-2 text-center" style={{ borderColor: `${chest.color}55` }}>
                  <img src={chest.image} alt={chest.name} loading="lazy" className="mx-auto h-12 w-12 rounded-lg object-contain" />
                  <p className="mt-1 truncate text-[8.5px] font-black uppercase tracking-[.08em]" style={{ color: chest.color }}>{chest.name}</p>
                  <p className="text-[10px] font-black text-slate-200">{chance % 1 === 0 ? chance : chance.toFixed(1)}%</p>
                </div>
              );
            })}
          </div>
        </div>

        {/* Chaves raras: drop na Torre + compra direta com TON (saldo interno ou TON Connect). */}
        <RareKeyShop initData={initData} keyChances={rewards.keyChances} />

      </div>

      <div className="grid grid-cols-3 gap-2 text-[10px]">
        <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5"><p className="text-slate-400">{t('tower.deepestFloor')}</p><p className="mt-1 font-semibold text-amber-300">{data.highestFloor}</p></div>
        <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5"><p className="text-slate-400">{t('tower.attempts')}</p><p className="mt-1 font-semibold">{data.attemptsRemaining} / {data.attemptsLimit}</p></div>
        <div className="rounded-2xl border border-white/10 bg-black/55 p-2.5"><p className="text-slate-400">{t('tower.replayReward')}</p><p className="mt-1 font-semibold text-slate-200">50%</p></div>
      </div>

      <div className="rounded-3xl border border-white/10 bg-black/50 p-3">
        <p className="text-[10px] uppercase tracking-[.28em] text-amber-300/80">{t('tower.milestoneRewards')}</p>
        <div className="mt-2 space-y-1.5">
          {TOWER_MILESTONES.map(item => {
            const done = data.highestFloor >= item.floor;
            return (
              <div key={item.floor} className={`flex items-center justify-between rounded-xl border px-2.5 py-2 text-[10px] ${done ? 'border-emerald-400/30 bg-emerald-500/10' : 'border-white/10 bg-black/60'}`}>
                <span className="font-bold text-slate-200">{t('tower.floorNumber', { floor: item.floor })}</span>
                <span className={done ? 'text-emerald-300' : 'text-amber-200'}>{item.reward}</span>
              </div>
            );
          })}
        </div>
      </div>

      {data.history.length ? (
        <div className="rounded-3xl border border-white/10 bg-black/50 p-3">
          <p className="text-[10px] uppercase tracking-[.28em] text-amber-300/80">{t('tower.recentAttempts')}</p>
          <div className="mt-2 space-y-1.5">
            {data.history.map(run => (
              <div key={run.id} className="flex items-center justify-between rounded-xl border border-white/10 bg-black/60 px-2.5 py-2 text-[10px]">
                <span className="font-bold text-slate-200">{t('tower.floorNumber', { floor: run.floor })}</span>
                <span className="text-slate-500">{t('tower.turnsCount', { count: run.turns })}</span>
                <span className={run.result === 'win' ? 'text-emerald-300' : 'text-rose-300'}>{run.result === 'win' ? t('tower.victory') : t('tower.defeat')}</span>
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {isRankingOpen ? (
        <div className="fixed inset-0 z-[85] flex items-end justify-center bg-black/80 p-2" onClick={() => setIsRankingOpen(false)}>
          <div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-3" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold text-amber-300">{t('tower.rankingTitle')}</h3>
              <button type="button" aria-label={t('tower.close')} onClick={() => setIsRankingOpen(false)} className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-black/60 text-slate-300">✕</button>
            </div>
            <div className="mt-2 grid grid-cols-3 gap-1.5 text-[9px]">
              <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{t('tower.players')}</p><p className="mt-1 font-semibold">{compact(ranking.data?.totalPlayers ?? 0)}</p></div>
              <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{t('tower.highestFloor')}</p><p className="mt-1 font-semibold text-amber-300">{ranking.data?.highestFloor ?? 0}</p></div>
              <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{t('tower.yourRank')}</p><p className="mt-1 font-semibold">{ranking.data?.you?.rank ? `#${ranking.data.you.rank}` : '—'}</p></div>
            </div>
            <div className="mt-1.5 grid grid-cols-2 gap-1.5 text-[9px]">
              <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{t('tower.bestFloor')}</p><p className="mt-1 font-semibold text-amber-300">{ranking.data?.you?.floor ?? data.highestFloor}</p></div>
              <div className="rounded-2xl bg-black/65 p-3"><p className="text-slate-400">{t('tower.power')}</p><p className="mt-1 font-semibold">{compact(ranking.data?.you?.power ?? data.teamPower)}</p></div>
            </div>
            {ranking.isLoading && !ranking.data ? (
              <p className="py-8 text-center text-xs text-slate-400">{t('tower.loadingRanking')}</p>
            ) : !ranking.data?.top.length ? (
              <p className="py-8 text-center text-xs text-slate-400">{t('tower.noRankedPlayers')}</p>
            ) : (
              <div className="mt-3 max-h-[55vh] space-y-1.5 overflow-y-auto">
                {ranking.data.top.map(entry => (
                  <div key={entry.userId} className={`flex items-center gap-2 rounded-2xl border p-2 ${entry.isYou ? 'border-amber-300/60 bg-amber-400/10' : entry.rank <= 3 ? 'border-amber-400/30 bg-amber-500/5' : 'border-white/10 bg-black/60'}`}>
                    <span className="w-7 text-center text-[11px] font-black text-amber-300">#{entry.rank}</span>
                    {entry.photoUrl
                      ? <img src={entry.photoUrl} alt="" className="h-8 w-8 rounded-full object-cover" />
                      : <span className="grid h-8 w-8 place-items-center rounded-full bg-white/10 text-[10px]">🗼</span>}
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[11px] font-bold">{entry.name}{entry.isYou ? <span className="ml-1 text-[8px] text-amber-300">{t('tower.you')}</span> : null}</p>
                      <p className="text-[9px] text-slate-400">{t('tower.powerLabel', { power: compact(entry.power) })}{entry.updatedAt ? ` · ${new Date(entry.updatedAt).toLocaleDateString()}` : ''}</p>
                    </div>
                    <span className="text-[10px] font-bold text-amber-300">{t('tower.floorNumber', { floor: entry.floor })}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      ) : null}

      {isTeamOpen ? (
        <div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/75 p-2" onClick={() => { setIsTeamOpen(false); setSlot(null); }}>
          <div className="forge-safe-page w-full max-w-md rounded-t-3xl border border-amber-400/30 bg-[#090c12] p-3" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold">{t('tower.selectTeamCount', { count: team.length })}</h3>
              <button type="button" aria-label={t('tower.close')} onClick={() => { setIsTeamOpen(false); setSlot(null); }} className="grid h-9 w-9 place-items-center rounded-xl border border-white/10 bg-black/60 text-slate-300">✕</button>
            </div>

            <div className="mt-3 grid grid-cols-5 gap-1.5">
              {[1, 2, 3, 4, 5].map(n => {
                const hero = team.find(h => Number(h.slot) === n);
                return (
                  <button
                    key={n}
                    type="button"
                    onClick={() => setSlot(n)}
                    className={`overflow-hidden rounded-xl border bg-black/70 text-left ${slot === n ? 'border-amber-300' : 'border-white/10'}`}
                  >
                    {hero?.imageUrl ? <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover object-top" /> : <span className="grid aspect-square w-full place-items-center text-[10px] text-slate-500">+{n}</span>}
                    <p className="truncate px-1 py-0.5 text-[8px] font-bold text-slate-200">{hero?.name ?? t('tower.empty')}</p>
                  </button>
                );
              })}
            </div>
            {slot && team.some(h => Number(h.slot) === slot) ? (
              <button type="button" onClick={() => unequip.mutate(slot)} className="mt-2 w-full rounded-xl border border-rose-400/40 bg-rose-500/10 py-2 text-[11px] font-bold uppercase tracking-wide text-rose-200">{t('tower.removeFromSlot', { slot })}</button>
            ) : null}

            <p className="mt-3 text-[9px] uppercase tracking-[.24em] text-slate-500">{slot ? t('tower.chooseHeroForSlot', { slot }) : t('tower.tapSlotToChoose')}</p>

            {collectionLoading && !heroes.length ? (
              <p className="py-8 text-center text-xs text-slate-400">{t('tower.loadingHeroes')}</p>
            ) : !heroes.length ? (
              <p className="py-8 text-center text-xs text-slate-400">{t('tower.noHeroesAvailable')}</p>
            ) : (
              <div className="mt-2 grid max-h-[42vh] grid-cols-3 gap-2 overflow-y-auto">
                {heroes.map(hero => {
                  const selected = team.some(h => h.heroId === hero.heroId);
                  const duplicate = !selected && usedTemplates.has(templateOf(hero));
                  const rarity = normalizeRarity(hero.rarity);
                  return (
                    <button
                      type="button"
                      key={hero.heroId}
                      disabled={duplicate || equip.isPending}
                      onClick={() => {
                        if (!slot) { toast.error(t('tower.selectSlotFirst')); return; }
                        equip.mutate({ targetSlot: slot, heroId: hero.heroId });
                      }}
                      className={`overflow-hidden rounded-xl border bg-black text-left ${duplicate ? 'opacity-40' : ''}`}
                      style={{ borderColor: selected ? '#fbbf24' : RARITY_COLORS[rarity] }}
                    >
                      {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover object-top" loading="lazy" /> : null}
                      <div className="p-1.5">
                        <p className="truncate text-[9px] font-bold">{hero.name}</p>
                        <p className="text-[8px] text-amber-200">{compact(hero.power ?? 0)}</p>
                        {selected ? <p className="text-[8px] text-amber-300">{t('tower.inTeam')}</p> : duplicate ? <p className="text-[8px] text-rose-300">{t('tower.duplicate')}</p> : null}
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      ) : null}
    </section>
  );
}
