import { useMemo, useState } from 'react';
import { Castle, Crown, Flame, Loader2, Shield, ShieldCheck, Swords, Trophy } from 'lucide-react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import { useT } from '../LanguageContext';
import { useClanWarDashboard, usePlayerHeroes } from '../hooks';
import {
  attackClanWarDefender,
  clanWarErrorKey,
  joinClanWar,
  leaveClanWarQueue,
  setClanWarDefense,
  type ClanWarDashboard,
  type ClanWarSector,
} from '../clanWar';
import { ClanCrest } from './ClanHall';

type View = 'fortress' | 'defense' | 'roster' | 'feed' | 'ranking';

const countdown = (iso: string | null | undefined) => {
  if (!iso) return '--:--';
  const ms = new Date(iso).getTime() - Date.now();
  if (ms <= 0) return '00:00';
  const total = Math.floor(ms / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  return hours > 0 ? `${hours}h ${String(minutes).padStart(2, '0')}m` : `${String(minutes).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
};

/**
 * Clan War surface (20v20). Everything shown here is produced by clan_war_dashboard;
 * the panel never computes points, sector locks or eligibility on its own.
 */
export function ClanWarPanel({ telegramInitData }: { telegramInitData: string }) {
  const t = useT();
  const queryClient = useQueryClient();
  const { data, isLoading, isError, refetch } = useClanWarDashboard(telegramInitData, true);
  const [view, setView] = useState<View>('fortress');
  const [busy, setBusy] = useState(false);
  const [picked, setPicked] = useState<string[] | null>(null);

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['clan-war'] });
    await refetch();
  };

  const run = async <T,>(action: () => Promise<T>, onDone?: (result: T) => void) => {
    if (busy) return;
    setBusy(true);
    try {
      const result = await action();
      onDone?.(result);
      await refresh();
    } catch (error) {
      const raw = error instanceof Error ? error.message : '';
      const key = clanWarErrorKey(raw);
      toast.error(key ? t(key) : `${t('clanwar.error.generic')}${raw ? ` (${raw})` : ''}`);
    } finally {
      setBusy(false);
    }
  };

  if (isLoading) return <div className="grid place-items-center py-12"><Loader2 className="h-5 w-5 animate-spin text-amber-300" /></div>;
  if (isError || !data) return <p className="py-8 text-center text-[10px] text-slate-500">{t('clanwar.error.generic')}</p>;
  if (!data.config.enabled) return <Notice icon={<Castle className="h-6 w-6 text-amber-300" />} text={t('clanwar.disabled')} />;
  if (!data.inClan) return <Notice icon={<Shield className="h-6 w-6 text-amber-300" />} text={t('clanwar.needClan')} />;

  const war = data.war;

  return (
    <div className="space-y-3">
      <SeasonCard data={data} />

      {!war ? (
        <div className="rounded-2xl border border-white/10 bg-black/55 p-4 text-center">
          <p className="text-[10px] text-slate-400">{t('clanwar.noWar')}</p>
          {data.lastWar ? (
            <p className="mt-1 text-[9px] text-slate-500">
              {t('clanwar.lastWar', { result: t(`clanwar.${data.lastWar.result === 'win' ? 'win' : data.lastWar.result === 'loss' ? 'loss' : 'score'}`), you: data.lastWar.scoreYou, enemy: data.lastWar.scoreEnemy })}
            </p>
          ) : null}
          {data.canManage ? (
            <button disabled={busy} onClick={() => void run(() => joinClanWar(telegramInitData), () => toast.success(t('clanwar.enlisted')))}
              className="mt-3 w-full rounded-xl border border-amber-300/50 bg-amber-400/20 py-3 text-[10px] font-black text-amber-100 disabled:opacity-50">
              {t('clanwar.enlist')}
            </button>
          ) : null}
        </div>
      ) : null}

      {war ? (
        <>
          <ScoreBoard war={war} t={t} />
          {war.status === 'searching' ? (
            <div className="rounded-2xl border border-amber-300/25 bg-black/55 p-4 text-center">
              <p className="text-[10px] font-black text-amber-200">{t('clanwar.searching')}</p>
              {data.canManage ? (
                <button disabled={busy} onClick={() => void run(() => leaveClanWarQueue(telegramInitData), () => toast.success(t('clanwar.queueLeft')))}
                  className="mt-3 w-full rounded-xl border border-rose-400/40 py-2.5 text-[10px] font-black text-rose-300 disabled:opacity-50">
                  {t('clanwar.leaveQueue')}
                </button>
              ) : null}
            </div>
          ) : (
            <>
              <div className="grid grid-cols-5 gap-1.5">
                <NavButton active={view === 'fortress'} onClick={() => setView('fortress')} icon={<Castle className="h-4 w-4" />} label={t('clanwar.navFortress')} />
                <NavButton active={view === 'defense'} onClick={() => setView('defense')} icon={<ShieldCheck className="h-4 w-4" />} label={t('clanwar.navDefense')} />
                <NavButton active={view === 'roster'} onClick={() => setView('roster')} icon={<Swords className="h-4 w-4" />} label={t('clanwar.navRoster')} />
                <NavButton active={view === 'feed'} onClick={() => setView('feed')} icon={<Flame className="h-4 w-4" />} label={t('clanwar.navFeed')} />
                <NavButton active={view === 'ranking'} onClick={() => setView('ranking')} icon={<Trophy className="h-4 w-4" />} label={t('clanwar.navRanking')} />
              </div>

              {view === 'fortress' ? (
                <div className="space-y-2">
                  {war.status === 'preparation' ? (
                    <div className="rounded-2xl border border-amber-300/30 bg-amber-500/10 p-3 text-[9px] font-bold uppercase tracking-[.12em] text-amber-200">
                      Fase de preparação — ataques liberam quando a batalha começar{war.preparationEndsAt ? ` (${new Date(war.preparationEndsAt).toLocaleString()})` : ''}. Monte sua defesa agora.
                    </div>
                  ) : war.status === 'battle' && (war.me?.attacksLeft ?? 0) <= 0 ? (
                    <div className="rounded-2xl border border-rose-400/30 bg-rose-500/10 p-3 text-[9px] font-bold uppercase tracking-[.12em] text-rose-200">
                      Você já usou todos os seus ataques nesta guerra.
                    </div>
                  ) : null}
                  {war.sectors.map((sector) => (

                    <SectorCard
                      key={sector.code}
                      sector={sector}
                      sectors={war.sectors}
                      canAttack={war.status === 'battle' && (war.me?.attacksLeft ?? 0) > 0}
                      busy={busy}
                      onAttack={(defender) => void run(
                        () => attackClanWarDefender(telegramInitData, defender, `${war.warId}:${defender}:${Date.now()}`),
                        (result) => {
                          toast[result.win ? 'success' : 'error'](t(result.win ? 'clanwar.attackWin' : 'clanwar.attackLoss', { points: result.points }));
                          if (result.sectorConquered) toast.success(t('clanwar.sectorTaken'));
                        },
                      )}
                    />
                  ))}
                </div>
              ) : null}

              {view === 'defense' ? (
                <DefenseTab
                  telegramInitData={telegramInitData}
                  data={data}
                  picked={picked}
                  setPicked={setPicked}
                  busy={busy}
                  onSave={(heroIds) => void run(() => setClanWarDefense(telegramInitData, heroIds), () => { toast.success(t('clanwar.defenseSaved')); setPicked(null); })}
                />
              ) : null}

              {view === 'roster' ? (
                <div className="space-y-1.5">
                  <h3 className="text-[10px] font-black tracking-[.2em] text-amber-200">{t('clanwar.rosterTitle')}</h3>
                  {war.roster.map((member) => (
                    <div key={member.userId} className={`flex items-center gap-2 rounded-2xl border p-2.5 ${member.isMe ? 'border-amber-300/50 bg-amber-400/10' : 'border-white/10 bg-black/55'}`}>
                      {member.avatarUrl ? <img src={member.avatarUrl} alt="" className="h-8 w-8 rounded-full object-cover" /> : <span className="h-8 w-8 rounded-full bg-white/10" />}
                      <div className="min-w-0 flex-1">
                        <b className="block truncate text-[11px]">{member.name}</b>
                        <p className="text-[9px] text-slate-400">{t(`clanwar.sector.${member.sector}`)} · {member.wins}W/{member.losses}L {member.defenseSet ? '· 🛡' : ''}</p>
                      </div>
                      <div className="text-right">
                        <b className="block text-[11px] text-amber-300">{member.points.toLocaleString()}</b>
                        <span className="text-[8px] text-slate-500">{member.attacksLeft} ⚔</span>
                      </div>
                    </div>
                  ))}
                </div>
              ) : null}

              {view === 'feed' ? (
                <div className="space-y-1.5">
                  <h3 className="text-[10px] font-black tracking-[.2em] text-amber-200">{t('clanwar.feedTitle')}</h3>
                  {!war.feed.length ? <p className="py-6 text-center text-[10px] text-slate-500">{t('clanwar.noFeed')}</p> : null}
                  {war.feed.map((entry) => (
                    <div key={entry.id} className={`rounded-2xl border p-2.5 text-[10px] ${entry.mine ? 'border-emerald-400/25 bg-emerald-500/5' : 'border-rose-400/20 bg-rose-500/5'}`}>
                      <div className="flex items-center justify-between">
                        <b className="truncate">{entry.attacker} → {entry.defender}</b>
                        <span className={entry.result === 'win' ? 'text-emerald-300' : 'text-rose-300'}>{t(entry.result === 'win' ? 'clanwar.win' : 'clanwar.loss')}</span>
                      </div>
                      <p className="mt-0.5 text-[9px] text-slate-400">
                        {t(`clanwar.sector.${entry.sector}`)} · {t('clanwar.points', { points: entry.points })}{entry.perfect ? ` · ${t('clanwar.perfect')}` : ''}
                      </p>
                    </div>
                  ))}
                </div>
              ) : null}

              {view === 'ranking' ? <RankingList data={data} /> : null}
            </>
          )}
        </>
      ) : null}

      {war && war.status !== 'searching' ? null : <RankingList data={data} />}
    </div>
  );
}

function SeasonCard({ data }: { data: ClanWarDashboard }) {
  const t = useT();
  return (
    <section className="rounded-2xl border border-amber-300/25 bg-gradient-to-br from-amber-500/10 to-black/60 p-3">
      <div className="flex items-center gap-2">
        <Crown className="h-4 w-4 text-amber-300" />
        <b className="text-[11px] tracking-[.18em] text-amber-100">{t('clanwar.title')}</b>
        <span className="ml-auto text-[8px] uppercase tracking-[.2em] text-slate-400">{t('clanwar.subtitle')}</span>
      </div>
      {data.season ? (
        <p className="mt-1.5 text-[9px] text-slate-300">
          {t('clanwar.season')}: <b>{data.season.name}</b> · {t('clanwar.seasonEnds', { date: new Date(data.season.ends_at).toLocaleDateString() })}
          {data.season.ton_prize_enabled && Number(data.season.ton_prize_ton) > 0 ? ` · ${t('clanwar.prize', { ton: Number(data.season.ton_prize_ton).toFixed(2) })}` : ''}
        </p>
      ) : null}
    </section>
  );
}

function ScoreBoard({ war, t }: { war: NonNullable<ClanWarDashboard['war']>; t: (key: string, vars?: Record<string, string | number>) => string }) {
  const phaseKey = war.status === 'preparation' ? 'clanwar.preparation' : war.status === 'battle' ? 'clanwar.battle' : war.status === 'searching' ? 'clanwar.searching' : 'clanwar.finished';
  const deadline = war.status === 'preparation' ? war.preparationEndsAt : war.battleEndsAt;
  return (
    <section className="rounded-2xl border border-white/10 bg-black/60 p-3">
      <div className="flex items-center justify-between text-[9px] uppercase tracking-[.2em] text-amber-200">
        <span>{t(phaseKey)}</span>
        {deadline ? <span className="text-slate-400">{t('clanwar.endsIn', { time: countdown(deadline) })}</span> : null}
      </div>
      <div className="mt-2 flex items-center gap-2">
        <div className="flex min-w-0 flex-1 items-center gap-2">
          {war.yourClan ? <ClanCrest emblem={war.yourClan.emblem ?? {}} size={30} /> : null}
          <div className="min-w-0">
            <b className="block truncate text-[11px]">{war.yourClan?.name ?? '—'}</b>
            <span className="text-[8px] text-slate-400">{war.yourClan?.league ?? '—'} · {war.yourClan?.rating ?? 0}</span>
          </div>
        </div>
        <div className="shrink-0 text-center">
          <b className="text-base text-amber-300">{war.scoreYou}</b>
          <span className="mx-1 text-slate-500">×</span>
          <b className="text-base text-rose-300">{war.scoreEnemy}</b>
        </div>
        <div className="flex min-w-0 flex-1 items-center justify-end gap-2 text-right">
          <div className="min-w-0">
            <b className="block truncate text-[11px]">{war.enemyClan?.name ?? '—'}</b>
            <span className="text-[8px] text-slate-400">{war.enemyClan?.league ?? '—'} · {war.enemyClan?.rating ?? 0}</span>
          </div>
          {war.enemyClan ? <ClanCrest emblem={war.enemyClan.emblem ?? {}} size={30} /> : null}
        </div>
      </div>
      {war.me ? (
        <div className="mt-2 grid grid-cols-3 gap-1.5 text-center">
          <Mini label={t('clanwar.attacksLeft')} value={`${war.me.attacksLeft}/${war.me.attacksTotal}`} />
          <Mini label={t('clanwar.myPoints')} value={war.me.points.toLocaleString()} />
          <Mini label={t('clanwar.mySector')} value={t(`clanwar.sector.${war.me.sector}`)} />
        </div>
      ) : null}
    </section>
  );
}

function SectorCard({ sector, sectors, canAttack, busy, onAttack }: { sector: ClanWarSector; sectors: ClanWarSector[]; canAttack: boolean; busy: boolean; onAttack: (defender: string) => void }) {
  const t = useT();
  const locked = sector.requires.some((code) => !sectors.find((item) => item.code === code)?.conquered);
  return (
    <div className={`rounded-2xl border p-3 ${sector.conquered ? 'border-emerald-400/40 bg-emerald-500/5' : locked ? 'border-white/10 bg-black/40 opacity-70' : 'border-amber-300/25 bg-black/55'}`}>
      <div className="flex items-center gap-2">
        <Castle className="h-4 w-4 text-amber-300" />
        <b className="text-[11px]">{t(`clanwar.sector.${sector.code}`)}</b>
        <span className="ml-auto text-[8px] font-black uppercase tracking-[.16em]">
          {sector.conquered ? <span className="text-emerald-300">{t('clanwar.sectorConquered')}</span> : locked ? <span className="text-slate-500">{t('clanwar.sectorLocked')}</span> : null}
        </span>
      </div>
      <p className="mt-0.5 text-[9px] text-slate-400">
        {t('clanwar.sectorNeed', { count: sector.required })}{sector.bonus ? ` · ${t('clanwar.sectorBonus', { bonus: sector.bonus })}` : ''}
      </p>
      <div className="mt-2 space-y-1.5">
        {sector.defenders.map((defender) => (
          <div key={defender.userId} className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/50 p-2">
            {defender.avatarUrl ? <img src={defender.avatarUrl} alt="" className="h-7 w-7 rounded-full object-cover" /> : <span className="h-7 w-7 rounded-full bg-white/10" />}
            <div className="min-w-0 flex-1">
              <b className="block truncate text-[10px]">{defender.name}</b>
              <span className="text-[8px] text-cyan-300">{defender.power.toLocaleString()}</span>
            </div>
            {defender.beaten ? (
              <span className="rounded-lg border border-emerald-400/30 px-2 py-1 text-[8px] font-black text-emerald-300">{t('clanwar.beaten')}</span>
            ) : (
              <button disabled={!canAttack || locked || busy} onClick={() => onAttack(defender.userId)}
                className="rounded-lg border border-rose-400/40 bg-rose-500/15 px-2.5 py-1 text-[8px] font-black text-rose-200 disabled:opacity-40">
                {t('clanwar.attack')}
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

function DefenseTab({ telegramInitData, data, picked, setPicked, busy, onSave }: {
  telegramInitData: string;
  data: ClanWarDashboard;
  picked: string[] | null;
  setPicked: (value: string[]) => void;
  busy: boolean;
  onSave: (heroIds: string[]) => void;
}) {
  const t = useT();
  const { data: heroData } = usePlayerHeroes(telegramInitData, true);
  const heroes = heroData?.heroes ?? [];
  const current = useMemo(() => picked ?? data.war?.me?.defense?.heroIds ?? [], [picked, data.war]);
  const toggle = (heroId: string) => {
    if (current.includes(heroId)) setPicked(current.filter((id) => id !== heroId));
    else if (current.length < 3) setPicked([...current, heroId]);
  };

  return (
    <div className="space-y-2">
      <div className="rounded-2xl border border-white/10 bg-black/55 p-3">
        <b className="text-[10px] tracking-[.2em] text-amber-200">{t('clanwar.defenseTitle')}</b>
        <p className="mt-1 text-[9px] text-slate-400">{t('clanwar.defenseHint')}</p>
        <p className="mt-1 text-[9px] text-cyan-300">
          {data.war?.me?.defense ? `${t('clanwar.defensePower')}: ${Number(data.war.me.defense.power ?? 0).toLocaleString()}` : t('clanwar.defenseMissing')}
        </p>
      </div>
      <div className="grid grid-cols-3 gap-1.5">
        {heroes.map((hero) => {
          const active = current.includes(hero.heroId);
          return (
            <button key={hero.heroId} onClick={() => toggle(hero.heroId)}
              className={`overflow-hidden rounded-xl border text-left ${active ? 'border-amber-300/70 bg-amber-400/15' : 'border-white/10 bg-black/50'}`}>
              <img src={hero.imageUrl} alt={hero.name} className="h-16 w-full object-cover" loading="lazy" />
              <div className="p-1.5">
                <b className="block truncate text-[9px]">{hero.name}</b>
                <span className="text-[8px] text-cyan-300">{hero.power.toLocaleString()}</span>
              </div>
            </button>
          );
        })}
      </div>
      <button disabled={busy || current.length !== 3} onClick={() => onSave(current)}
        className="w-full rounded-xl border border-amber-300/50 bg-amber-400/20 py-3 text-[10px] font-black text-amber-100 disabled:opacity-50">
        {t('clanwar.defenseSave')} ({current.length}/3)
      </button>
      <div className="rounded-2xl border border-white/10 bg-black/45 p-3">
        <b className="text-[9px] tracking-[.2em] text-amber-200">{t('clanwar.attackTeam')}</b>
        <p className="mt-1 text-[9px] text-slate-400">{t('clanwar.attackTeamHint')}</p>
        <div className="mt-2 flex gap-1.5">
          {(data.war?.attackTeam ?? []).map((hero) => (
            <img key={hero.heroId} src={hero.imageUrl} alt={hero.name} className="h-10 w-10 rounded-lg border border-white/10 object-cover" />
          ))}
        </div>
      </div>
    </div>
  );
}

function RankingList({ data }: { data: ClanWarDashboard }) {
  const t = useT();
  return (
    <div className="space-y-1.5">
      <h3 className="text-[10px] font-black tracking-[.2em] text-amber-200">{t('clanwar.rankingTitle')}</h3>
      {data.ranking.map((entry, index) => (
        <div key={entry.clanId} className="flex items-center gap-2 rounded-2xl border border-white/10 bg-black/55 p-2.5">
          <b className="w-6 text-[10px] text-amber-300">#{index + 1}</b>
          <ClanCrest emblem={entry.emblem ?? {}} size={26} />
          <div className="min-w-0 flex-1">
            <b className="block truncate text-[11px]">{entry.name}</b>
            <span className="text-[8px] text-slate-400">[{entry.tag}] · {entry.league} · {entry.wins}W/{entry.losses}L</span>
          </div>
          <b className="text-[11px] text-cyan-300">{entry.rating}</b>
        </div>
      ))}
    </div>
  );
}

function NavButton({ active, onClick, icon, label }: { active: boolean; onClick: () => void; icon: React.ReactNode; label: string }) {
  return (
    <button onClick={onClick} className={`flex flex-col items-center gap-1 rounded-xl border py-2 text-[7px] font-black uppercase ${active ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-black/50 text-slate-400'}`}>
      {icon}{label}
    </button>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl border border-white/10 bg-black/50 p-1.5"><p className="text-[7px] uppercase text-slate-400">{label}</p><b className="text-[10px] text-white">{value}</b></div>;
}

function Notice({ icon, text }: { icon: React.ReactNode; text: string }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/55 p-6 text-center">
      <div className="mb-2 flex justify-center">{icon}</div>
      <p className="text-[10px] text-slate-400">{text}</p>
    </div>
  );
}
