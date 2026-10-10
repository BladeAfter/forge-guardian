import { useLocalizedText } from '../LanguageContext';
import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { History, Loader2, Search, Shield, Sparkles, Swords, Ticket, Trophy, Users, X } from 'lucide-react';
import { toast } from 'sonner';
import { useLanguage, useT } from '../LanguageContext';
import {
  cancelTacticalQueue,
  fetchTacticalDashboard,
  fetchTacticalHistory,
  fetchTacticalRanking,
  joinTacticalQueue,
  pollTacticalQueue,
  removeTacticalTeamSlot,
  saveTacticalDeck,
  saveTacticalTeamSlot,
} from '../services';
import type { TacticalDashboard, TacticalHero, TacticalSkill } from '../tactical';
import { TacticalBattleScreen } from './TacticalBattleScreen';

const RARITY: Record<string, string> = { common: '#94a3b8', uncommon: '#34d399', rare: '#60a5fa', epic: '#c084fc', legendary: '#fbbf24', mythic: '#f472b6', ancestral: '#f97316', nft_exclusive: '#22d3ee', celestial: '#fde68a', };
type View = 'team' | 'deck' | 'history' | 'ranking';

function Stat({ icon, label, value, hint }: { icon: React.ReactNode; label: string; value: React.ReactNode; hint?: string }) {
  return (
    <div className="px-2 text-center">
      <div className="mx-auto grid h-7 w-7 place-items-center text-amber-300 [&>svg]:h-4 [&>svg]:w-4">{icon}</div>
      <p className="mt-1 text-[8px] font-black uppercase tracking-[.14em] text-slate-400">{label}</p>
      <b className="block truncate text-[12px] text-amber-50">{value}</b>
      {hint ? <p className="text-[8px] text-slate-500">{hint}</p> : null}
    </div>
  );
}

function HeroPicker({
  slot,
  heroes,
  team,
  pending,
  onClose,
  onPick,
  onRemove,
}: {
  slot: number;
  heroes: TacticalHero[];
  team: TacticalHero[];
  pending: boolean;
  onClose: () => void;
  onPick: (heroId: string) => void;
  onRemove: () => void;
}) {
  const localizeText = useLocalizedText();

  const t = useT();
  const equipped = team.find((h) => Number(h.slot) === slot) ?? null;
  const templateOf = (h: TacticalHero) => String(h.templateId || h.heroKey || h.name || h.heroId).toLowerCase();
  return (
    <div className="fixed inset-0 z-[95] flex items-end justify-center bg-black/80 p-3" onClick={onClose}>
      <div className="max-h-[80dvh] w-full max-w-md overflow-y-auto rounded-t-3xl border border-amber-300/30 bg-[#080c14] p-4" onClick={(event) => event.stopPropagation()}>
        <div className="flex items-center justify-between gap-2">
          <b className="text-[12px]">{t('tactical.selectHeroSlot', { slot })}</b>
          <div className="flex items-center gap-2">
            {equipped ? (
              <button type="button" disabled={pending} onClick={onRemove} className="rounded-full border border-rose-400/45 bg-rose-500/10 px-2.5 py-1 text-[9px] font-black uppercase tracking-[.12em] text-rose-200 disabled:opacity-50">
                {t('tactical.remove')}
              </button>
            ) : null}
            <button type="button" onClick={onClose} aria-label={localizeText("close")}>
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-2">
          {heroes.map((hero) => {
            const inThisSlot = equipped?.heroId === hero.heroId;
            const otherSlot = team.find((h) => h.heroId === hero.heroId && Number(h.slot) !== slot);
            const dupe = !inThisSlot && !otherSlot && team.some((h) => Number(h.slot) !== slot && templateOf(h) === templateOf(hero));
            const hard = hero.blockReason === 'MARKET' || hero.blockReason === 'LOCKED';
            return (
              <button
                key={hero.heroId}
                type="button"
                disabled={hard || dupe || pending}
                onClick={() => (inThisSlot ? onRemove() : onPick(hero.heroId))}
                className={`relative overflow-hidden rounded-xl border bg-black/70 text-left disabled:opacity-35`}
                style={{ borderColor: inThisSlot ? '#fbbf24' : RARITY[hero.isNft ? 'nft_exclusive' : String(hero.rarity || '').toLowerCase()] || '#475569' }}
              >
                <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover object-top" />
                <p className="truncate px-1 pt-1 text-[9px] font-bold">{hero.name}</p>
                <p className="px-1 text-[8px] uppercase tracking-[.1em] text-amber-200/80">{hero.class}</p>
                <p className="px-1 pb-1 text-[8px] text-slate-400">{localizeText("Lv. ")}{hero.level} · {Number(hero.power || 0).toLocaleString()}</p>
                {otherSlot ? <span className="absolute right-1 top-1 rounded bg-black/80 px-1 text-[7px] font-black text-amber-200">S{otherSlot.slot}</span> : null}
                {dupe ? <span className="absolute inset-x-1 bottom-1 rounded bg-rose-500/80 text-center text-[7px] font-black text-black">{localizeText("DUP")}</span> : null}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/**
 * TACTICAL ARENA hub: rating/league header, 3-hero team, 6-skill deck,
 * matchmaking (real players first, admin practice vs AI) plus history and
 * ranking. All rules and validation are enforced by the backend RPCs.
 */
export function TacticalArenaPanel({ initData }: { initData: string }) {
  const localizeText = useLocalizedText();

  const t = useT();
  const { tError } = useLanguage();
  const client = useQueryClient();
  const [view, setView] = useState<View>('team');
  const [slot, setSlot] = useState<number | null>(null);
  const [draft, setDraft] = useState<string[] | null>(null);
  const [matchId, setMatchId] = useState<string | null>(null);
  const [searching, setSearching] = useState(false);

  const dashboard = useQuery<TacticalDashboard>({ queryKey: ['tactical-dashboard', initData], queryFn: () => fetchTacticalDashboard(initData) });
  const data = dashboard.data;
  const deckSize = Number(data?.config?.deckSize ?? 6);

  const history = useQuery({ queryKey: ['tactical-history', initData], queryFn: () => fetchTacticalHistory(initData, 20), enabled: view === 'history' });
  const ranking = useQuery({ queryKey: ['tactical-ranking', initData], queryFn: () => fetchTacticalRanking(initData, 50), enabled: view === 'ranking' });

  useEffect(() => {
    if (data?.activeMatchId && !matchId) setMatchId(data.activeMatchId);
    if (data?.queue?.status === 'searching') setSearching(true);
  }, [data, matchId]);

  // Queue polling: the server pairs players; as soon as it returns a match we enter it.
  const queue = useQuery({
    queryKey: ['tactical-queue', initData],
    queryFn: () => pollTacticalQueue(initData),
    enabled: searching && !matchId,
    refetchInterval: 2000,
  });
  useEffect(() => {
    if (queue.data?.status === 'matched' && queue.data.matchId) {
      setSearching(false);
      setMatchId(queue.data.matchId);
    }
    if (queue.data?.status === 'idle') setSearching(false);
  }, [queue.data]);

  const refresh = () => client.invalidateQueries({ queryKey: ['tactical-dashboard', initData] });
  const apply = (next: TacticalDashboard) => {
    client.setQueryData(['tactical-dashboard', initData], next);
    setDraft(null);
  };

  const setTeam = useMutation({
    mutationFn: (payload: { slot: number; heroId: string }) => saveTacticalTeamSlot(initData, payload.slot, payload.heroId),
    onSuccess: (next) => {
      apply(next);
      setSlot(null);
    },
    onError: (error) => toast.error(tError(error)),
  });
  const clearTeam = useMutation({
    mutationFn: (target: number) => removeTacticalTeamSlot(initData, target),
    onSuccess: (next) => {
      apply(next);
      setSlot(null);
    },
    onError: (error) => toast.error(tError(error)),
  });
  const saveDeck = useMutation({
    mutationFn: (keys: string[]) => saveTacticalDeck(initData, keys),
    onSuccess: (next) => {
      apply(next);
      toast.success(t('tactical.deckSave'));
    },
    onError: (error) => toast.error(tError(error)),
  });
  const join = useMutation({
    mutationFn: (practice: boolean) => joinTacticalQueue(initData, practice),
    onSuccess: async (result) => {
      if (result.status === 'matched' && result.matchId) setMatchId(result.matchId);
      else setSearching(true);
      await refresh();
    },
    onError: (error) => toast.error(tError(error)),
  });
  const leave = useMutation({
    mutationFn: () => cancelTacticalQueue(initData),
    onSuccess: () => setSearching(false),
    onError: (error) => toast.error(tError(error)),
  });

  const selected = useMemo(() => draft ?? (data?.deck ?? []).map((s) => s.skillKey), [draft, data?.deck]);
  const toggleSkill = (key: string) =>
    setDraft(selected.includes(key) ? selected.filter((k) => k !== key) : selected.length >= deckSize ? selected : [...selected, key]);

  if (matchId)
    return (
      <TacticalBattleScreen
        initData={initData}
        matchId={matchId}
        onExit={async () => {
          setMatchId(null);
          await refresh();
        }}
      />
    );

  if (dashboard.isLoading)
    return (
      <div className="grid min-h-[40dvh] place-items-center">
        <Loader2 className="h-5 w-5 animate-spin text-amber-300" />
      </div>
    );

  if (dashboard.error || !data)
    return (
      <div className="py-16 text-center">
        <p className="text-sm text-slate-300">{dashboard.error ? tError(dashboard.error) : t('tactical.disabled')}</p>
        <button type="button" onClick={() => void dashboard.refetch()} className="mt-4 rounded-xl border border-amber-300/40 px-5 py-3 text-xs font-black uppercase tracking-[.12em] text-amber-200">
          {t('events.retry')}
        </button>
      </div>
    );

  if (!data.available)
    return (
      <section className="mt-5 rounded-[2rem] border border-amber-400/25 bg-black/55 px-6 py-10 text-center">
        <Sparkles className="mx-auto h-8 w-8 text-amber-300" />
        <h3 className="mt-3 text-lg font-black text-amber-50">{t('tactical.title')}</h3>
        <p className="mt-2 text-[11px] text-slate-400">{t('tactical.disabled')}</p>
      </section>
    );

  const teamComplete = data.team.length === 3;
  const deckComplete = selected.length === deckSize;
  const nav = (active: boolean) =>
    `flex items-center justify-center gap-1 rounded-xl border px-2 py-2 text-[9px] font-black uppercase tracking-[.1em] ${active ? 'border-amber-300/60 bg-amber-500/15 text-amber-100' : 'border-white/10 bg-black/40 text-slate-400'}`;

  return (
    <div className="mt-4">
      <section className="overflow-hidden rounded-[2rem] border border-cyan-300/25 bg-gradient-to-b from-[#0b1a2b]/95 to-black/75 px-5 py-6">
        <div className="text-center">
          <div className="mx-auto grid h-[64px] w-[64px] place-items-center rounded-full border border-cyan-300/35 bg-cyan-500/10">
            <Swords className="h-9 w-9 text-cyan-200" strokeWidth={1.5} />
          </div>
          <h3 className="mt-3 text-[24px] font-black leading-none text-cyan-50">{t('tactical.title')}</h3>
          <p className="mt-1 text-[11px] font-bold uppercase tracking-[.2em] text-cyan-300">{t('tactical.subtitle')}</p>
          {data.testMode ? <p className="mt-2 inline-block rounded-full border border-amber-300/50 bg-amber-500/10 px-3 py-1 text-[9px] font-black uppercase tracking-[.15em] text-amber-200">{t('tactical.testMode')}</p> : null}
        </div>
        <div className="mt-5 grid grid-cols-4 divide-x divide-white/10 rounded-2xl border border-white/10 bg-black/40 py-3">
          <Stat icon={<Trophy />} label={t('tactical.rating')} value={data.rating} hint={t('tactical.best', { rating: data.bestRating })} />
          <Stat icon={<Shield />} label={t('tactical.league')} value={data.league} />
          <Stat icon={<Swords />} label={t('tactical.record')} value={`${data.wins}/${data.losses}`} />
          <Stat icon={<Ticket />} label={t('tactical.tickets')} value={data.tickets} />
        </div>
        <div className="mt-4 grid grid-cols-4 gap-2">
          <button type="button" onClick={() => setView('team')} className={nav(view === 'team')}>
            <Users className="h-3 w-3" /> {t('tactical.navTeam')}
          </button>
          <button type="button" onClick={() => setView('deck')} className={nav(view === 'deck')}>
            <Sparkles className="h-3 w-3" /> {t('tactical.navDeck')}
          </button>
          <button type="button" onClick={() => setView('history')} className={nav(view === 'history')}>
            <History className="h-3 w-3" /> {t('tactical.navHistory')}
          </button>
          <button type="button" onClick={() => setView('ranking')} className={nav(view === 'ranking')}>
            <Trophy className="h-3 w-3" /> {t('tactical.navRanking')}
          </button>
        </div>
      </section>

      {view === 'team' ? (
        <section className="mt-4 rounded-2xl border border-white/10 bg-black/50 p-3">
          <p className="text-[10px] font-black uppercase tracking-[.15em] text-slate-300">{t('tactical.teamTitle')}</p>
          <p className="mt-1 text-[9px] text-slate-500">{t('tactical.teamHint')}</p>
          <div className="mt-3 grid grid-cols-3 gap-2">
            {[1, 2, 3].map((position) => {
              const hero = data.team.find((h) => Number(h.slot) === position);
              return (
                <button
                  key={position}
                  type="button"
                  onClick={() => setSlot(position)}
                  className="relative min-h-32 overflow-hidden rounded-xl border bg-black/70"
                  style={{ borderColor: hero ? RARITY[hero.isNft ? 'nft_exclusive' : String(hero.rarity || '').toLowerCase()] || '#475569' : '#475569' }}
                >
                  {hero ? (
                    <>
                      <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover object-top" />
                      <p className="truncate px-1 pt-1 text-[9px] font-bold">{hero.name}</p>
                      <p className="px-1 text-[8px] uppercase tracking-[.1em] text-cyan-200">{hero.class}</p>
                      <p className="px-1 pb-1 text-[8px] text-slate-400">ATK {Number(hero.finalAtk).toLocaleString()}</p>
                    </>
                  ) : (
                    <span className="grid h-32 place-items-center text-xl text-slate-500">＋</span>
                  )}
                </button>
              );
            })}
          </div>
          {data.teamClasses.length ? <p className="mt-2 text-[9px] text-cyan-200/80">{t('tactical.classes', { classes: data.teamClasses.join(' · ') })}</p> : null}
        </section>
      ) : null}

      {view === 'deck' ? (
        <section className="mt-4 rounded-2xl border border-white/10 bg-black/50 p-3">
          <p className="text-[10px] font-black uppercase tracking-[.15em] text-slate-300">{t('tactical.deckTitle', { count: selected.length, size: deckSize })}</p>
          <p className="mt-1 text-[9px] text-slate-500">{teamComplete ? t('tactical.deckHint', { size: deckSize }) : t('tactical.deckLocked')}</p>
          <div className="mt-3 grid grid-cols-2 gap-2">
            {(data.skills as TacticalSkill[]).map((skill) => {
              const active = selected.includes(skill.skillKey);
              const locked = !skill.unlocked || !teamComplete;
              return (
                <button
                  key={skill.skillKey}
                  type="button"
                  disabled={locked}
                  onClick={() => toggleSkill(skill.skillKey)}
                  className={`rounded-xl border p-2 text-left disabled:opacity-35 ${active ? 'border-cyan-300 bg-cyan-500/15' : 'border-white/12 bg-black/40'}`}
                >
                  <b className="block truncate text-[10px] text-slate-100">{t(skill.nameKey)}</b>
                  <p className="text-[8px] uppercase tracking-[.1em] text-cyan-200/80">
                    {skill.class} · {skill.type}
                  </p>
                  <p className="text-[8px] text-slate-400">
                    {skill.multiplier ? `x${Number(skill.multiplier).toFixed(2)} · ` : ''}{localizeText("CD ")}{skill.cooldown}
                  </p>
                  {locked ? <p className="text-[8px] font-black text-rose-300">{t('tactical.classLocked')}</p> : null}
                </button>
              );
            })}
          </div>
          <button
            type="button"
            disabled={!deckComplete || saveDeck.isPending}
            onClick={() => saveDeck.mutate(selected)}
            className="mt-3 w-full rounded-2xl bg-gradient-to-b from-cyan-300 to-sky-500 py-3 text-xs font-black uppercase tracking-[.12em] text-black disabled:grayscale disabled:opacity-40"
          >
            {t('tactical.deckSave')}
          </button>
        </section>
      ) : null}

      {view === 'history' ? (
        <section className="mt-4 space-y-2">
          {(history.data ?? []).length ? (
            (history.data ?? []).map((entry) => (
              <div key={entry.matchId} className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/55 p-3">
                <div>
                  <b className="text-[11px]">{entry.opponent}</b>
                  <p className="text-[9px] text-slate-400">
                    {new Date(entry.createdAt).toLocaleString()} · {t('tactical.turn', { turn: entry.turns })}
                  </p>
                </div>
                <div className="text-right">
                  <b className={entry.result === 'win' ? 'text-emerald-300' : entry.result === 'loss' ? 'text-rose-300' : 'text-slate-300'}>
                    {entry.result === 'win' ? t('tactical.victory') : entry.result === 'loss' ? t('tactical.defeat') : t('tactical.draw')}
                  </b>
                  <p className="text-[9px] text-amber-200">{entry.ratingChange > 0 ? '+' : ''}{entry.ratingChange}</p>
                </div>
              </div>
            ))
          ) : (
            <p className="py-10 text-center text-[11px] text-slate-400">{t('tactical.noHistory')}</p>
          )}
        </section>
      ) : null}

      {view === 'ranking' ? (
        <section className="mt-4 space-y-2">
          {ranking.data?.you ? <p className="text-center text-[10px] font-black uppercase tracking-[.12em] text-amber-200">{t('tactical.yourPosition', { position: ranking.data.you.position })}</p> : <p className="text-center text-[10px] text-slate-500">{t('tactical.unranked')}</p>}
          {(ranking.data?.top ?? []).length ? (
            (ranking.data?.top ?? []).map((row) => (
              <div key={row.userId} className="grid grid-cols-[34px_36px_1fr_auto] items-center gap-2 rounded-2xl border border-white/10 bg-black/55 p-2">
                <b className="text-center text-cyan-200">#{row.position}</b>
                {row.avatarUrl ? <img src={row.avatarUrl} alt={row.name} className="h-9 w-9 rounded-full object-cover" /> : <div className="grid h-9 w-9 place-items-center rounded-full bg-white/10 text-[10px] font-black">{row.name.slice(0, 1)}</div>}
                <div className="min-w-0">
                  <b className="block truncate text-xs">{row.name}</b>
                  <p className="truncate text-[9px] text-slate-400">
                    {row.league} · {row.wins}W / {row.losses}L
                  </p>
                </div>
                <b className="text-xs text-amber-200">{row.rating}</b>
              </div>
            ))
          ) : (
            <p className="py-10 text-center text-[11px] text-slate-400">{t('tactical.noRanking')}</p>
          )}
        </section>
      ) : null}

      <div className="mt-4 space-y-2">
        {searching ? (
          <>
            <div className="flex items-center justify-center gap-2 rounded-2xl border border-cyan-300/35 bg-cyan-500/10 py-3 text-[11px] font-black uppercase tracking-[.12em] text-cyan-100">
              <Loader2 className="h-4 w-4 animate-spin" /> {t('tactical.searching')}
            </div>
            <p className="text-center text-[9px] text-slate-500">{t('tactical.waited', { seconds: queue.data?.waitedSeconds ?? 0 })}</p>
            <button type="button" disabled={leave.isPending} onClick={() => leave.mutate()} className="w-full rounded-2xl border border-rose-400/40 bg-rose-500/10 py-3 text-[11px] font-black uppercase tracking-[.12em] text-rose-200">
              {t('tactical.cancelSearch')}
            </button>
          </>
        ) : (
          <button
            type="button"
            disabled={join.isPending}
            onClick={() => {
              if (!teamComplete) {
                toast.error(t('tactical.needTeam'));
                setView('team');
                return;
              }
              if (!deckComplete) {
                toast.error(t('tactical.needDeck', { size: deckSize }));
                setView('deck');
                return;
              }
              if (data.tickets < Number(data.config?.ticketCost ?? 1)) {
                toast.error(t('tactical.noTickets'));
                return;
              }
              join.mutate(false);
            }}
            className="w-full rounded-2xl bg-gradient-to-b from-cyan-300 to-sky-500 py-4 text-sm font-black uppercase tracking-[.1em] text-black disabled:opacity-50"
          >
            <Search className="mr-2 inline h-4 w-4" />
            {t('tactical.findMatch')}
          </button>
        )}
        {data.isAdmin && !searching ? (
          <button type="button" disabled={join.isPending} onClick={() => join.mutate(true)} className="w-full rounded-2xl border border-amber-300/40 bg-amber-500/10 py-3 text-[10px] font-black uppercase tracking-[.12em] text-amber-200">
            {t('tactical.practice')}
          </button>
        ) : null}
      </div>

      {slot !== null ? (
        <HeroPicker
          slot={slot}
          heroes={data.ownedHeroes}
          team={data.team}
          pending={setTeam.isPending || clearTeam.isPending}
          onClose={() => setSlot(null)}
          onPick={(heroId) => setTeam.mutate({ slot, heroId })}
          onRemove={() => clearTeam.mutate(slot)}
        />
      ) : null}
    </div>
  );
}
