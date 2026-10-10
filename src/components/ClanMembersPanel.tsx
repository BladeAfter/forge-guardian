import { useLocalizedText } from '../LanguageContext';
import { useMemo, useState } from 'react';
import { Crown, Shield, Swords, Trophy, Users, X } from 'lucide-react';
import { useT } from '../LanguageContext';
import { activityAge, type ClanAdminStats, type ClanJoinRequest, type ClanMember, type ClanRole } from '../clans';
import { PlayerTag } from '../premiumTitles';

/**
 * Leader tools for the MEMBERS / REQUESTS tabs.
 * Purely presentational: power, activity, counters and permissions all come from the backend.
 * Nothing here removes players automatically — the data only helps the leader decide.
 */

type Filter = 'all' | 'online' | 'today' | 'i3' | 'i7' | 'i14';
type Sort = 'powerHigh' | 'powerLow' | 'lastActive' | 'contribution' | 'joinDate';

const TONE: Record<string, string> = {
  online: 'bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,.9)]',
  fresh: 'bg-emerald-300/80',
  warm: 'bg-amber-300',
  stale: 'bg-orange-400',
  cold: 'bg-rose-500',
};
const TEXT_TONE: Record<string, string> = {
  online: 'text-emerald-300',
  fresh: 'text-emerald-200/90',
  warm: 'text-amber-200',
  stale: 'text-orange-300',
  cold: 'text-rose-300',
};

/** Colour is never the only signal: the friendly text ("7d ago") is always rendered too. */
function Activity({ lastActive, online, className = '' }: { lastActive?: string | null; online?: boolean; className?: string }) {
  const t = useT();
  const age = activityAge(lastActive);
  const tone = online ? 'online' : age.tone;
  const label = !lastActive ? t('clanx.never') : online ? t('clanx.online') : t('clanx.activeAgo', { time: age.short });
  return (
    <span className={`inline-flex items-center gap-1 text-[9px] font-bold ${TEXT_TONE[tone]} ${className}`}>
      <span className={`h-1.5 w-1.5 rounded-full ${TONE[tone]}`} />
      {label}
    </span>
  );
}

function Metric({ icon, label, value, tone = 'text-amber-200' }: { icon: React.ReactNode; label: string; value: string; tone?: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-black/45 px-2 py-1.5">
      <p className="flex items-center gap-1 text-[8px] uppercase tracking-[.14em] text-slate-400">{icon}{label}</p>
      <b className={`mt-0.5 block text-[11px] ${tone}`}>{value}</b>
    </div>
  );
}

export function ClanLeaderSummary({ stats }: { stats: ClanAdminStats }) {
  const t = useT();
  const cells: [string, string, string][] = [
    [t('clanx.statMembers'), `${stats.members} / ${stats.memberLimit}`, 'text-amber-200'],
    [t('clanx.statOnline'), String(stats.onlineNow), 'text-emerald-300'],
    [t('clanx.statActive24h'), String(stats.active24h), 'text-emerald-200'],
    [t('clanx.statInactive7d'), String(stats.inactive7d), 'text-rose-300'],
    [t('clanx.statPending'), String(stats.pendingRequests), 'text-cyan-300'],
  ];
  return (
    <section className="grid grid-cols-3 gap-2 rounded-2xl border border-amber-300/20 bg-black/50 p-2">
      {cells.map(([label, value, tone]) => (
        <div key={label} className="text-center">
          <p className="text-[7px] uppercase tracking-[.12em] text-slate-400">{label}</p>
          <b className={`text-[13px] ${tone}`}>{value}</b>
        </div>
      ))}
    </section>
  );
}

export function ClanRequestCard({ request, busy, onAccept, onReject }: {
  request: ClanJoinRequest; busy: boolean; onAccept: () => void; onReject: () => void;
}) {
  const localizeText = useLocalizedText();

  const t = useT();
  return (
    <article className="rounded-2xl border border-amber-300/25 bg-gradient-to-br from-[#131f36] via-[#0a1220] to-black p-3 shadow-[0_0_18px_rgba(0,0,0,.5)]">
      <p className="text-[8px] font-black uppercase tracking-[.2em] text-amber-300/80">{t('clanx.requestTitle')}</p>
      <div className="mt-1 flex items-center gap-2">
        {request.avatar
          ? <img src={request.avatar} alt="" className="h-9 w-9 rounded-full object-cover" />
          : <span className="grid h-9 w-9 place-items-center rounded-full bg-white/10 text-[10px]">{request.name.slice(0, 2)}</span>}
        <div className="min-w-0 flex-1">
          <b className="block truncate text-xs text-amber-100"><PlayerTag username={request.username} fallback={request.name}/></b>
          <span className="text-[9px] text-slate-400">{localizeText("Lv.")}{request.accountLevel ?? 1}</span>
        </div>
        <Activity lastActive={request.lastActive} online={request.online} />
      </div>
      <div className="mt-2 grid grid-cols-3 gap-1.5">
        <Metric icon={<Swords className="h-2.5 w-2.5" />} label={t('clanx.playerPower')} value={(request.power ?? 0).toLocaleString()} />
        <Metric icon={<Trophy className="h-2.5 w-2.5" />} label={t('clanx.league')} value={request.league ?? '—'} tone="text-cyan-200" />
        <Metric icon={<Shield className="h-2.5 w-2.5" />} label={t('clanx.heroes')} value={String(request.heroes ?? 0)} tone="text-slate-200" />
      </div>
      <div className="mt-2 flex gap-2">
        <button disabled={busy} onClick={onReject} className="flex-1 rounded-xl border border-rose-400/40 bg-rose-500/10 py-2 text-[10px] font-black text-rose-300 disabled:opacity-50">{t('clan.reject')}</button>
        <button disabled={busy} onClick={onAccept} className="flex-1 rounded-xl bg-gradient-to-b from-emerald-400 to-emerald-600 py-2 text-[10px] font-black text-black disabled:opacity-50">{t('clan.accept')}</button>
      </div>
    </article>
  );
}

export function ClanMembersList({ members, stats, canManage, myRole, busy, onAction }: {
  members: ClanMember[];
  stats?: ClanAdminStats;
  canManage: boolean;
  myRole: ClanRole;
  busy: boolean;
  onAction: (action: 'promote' | 'demote' | 'kick' | 'transfer', userId: string) => void;
}) {
  const localizeText = useLocalizedText();

  const t = useT();
  const [filter, setFilter] = useState<Filter>('all');
  const [sort, setSort] = useState<Sort>('powerHigh');
  const [detail, setDetail] = useState<ClanMember | null>(null);

  const visible = useMemo(() => {
    const days = (member: ClanMember) => {
      const age = activityAge(member.lastActive);
      return age.minutes == null ? Number.POSITIVE_INFINITY : age.minutes / 1440;
    };
    const list = members.filter((member) => {
      if (filter === 'online') return Boolean(member.online);
      if (filter === 'today') return days(member) < 1;
      if (filter === 'i3') return days(member) >= 3;
      if (filter === 'i7') return days(member) >= 7;
      if (filter === 'i14') return days(member) >= 14;
      return true;
    });
    const activityRank = (member: ClanMember) => (member.lastActive ? new Date(member.lastActive).getTime() : 0);
    return list.sort((a, b) => {
      if (sort === 'powerHigh') return (b.power ?? 0) - (a.power ?? 0);
      if (sort === 'powerLow') return (a.power ?? 0) - (b.power ?? 0);
      if (sort === 'lastActive') return activityRank(a) - activityRank(b);
      if (sort === 'contribution') return (b.contribution ?? 0) - (a.contribution ?? 0);
      return new Date(a.joinedAt ?? 0).getTime() - new Date(b.joinedAt ?? 0).getTime();
    });
  }, [members, filter, sort]);

  const filters: [Filter, string][] = [
    ['all', t('clanx.filterAll')], ['online', t('clanx.filterOnline')], ['today', t('clanx.filterToday')],
    ['i3', t('clanx.filter3d')], ['i7', t('clanx.filter7d')], ['i14', t('clanx.filter14d')],
  ];
  const sorts: [Sort, string][] = [
    ['powerHigh', t('clanx.sortPowerHigh')], ['powerLow', t('clanx.sortPowerLow')], ['lastActive', t('clanx.sortLastActive')],
    ['contribution', t('clanx.sortContribution')], ['joinDate', t('clanx.sortJoinDate')],
  ];

  return (
    <>
      {canManage && stats ? <ClanLeaderSummary stats={stats} /> : null}

      <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {filters.map(([key, label]) => (
          <button key={key} onClick={() => setFilter(key)} className={`shrink-0 rounded-full border px-2.5 py-1 text-[9px] font-black ${filter === key ? 'border-amber-300 bg-amber-400/20 text-amber-200' : 'border-white/10 bg-black/40 text-slate-400'}`}>{label}</button>
        ))}
      </div>
      <div className="flex items-center gap-2">
        <span className="text-[8px] uppercase tracking-[.16em] text-slate-500">{t('clanx.sortLabel')}</span>
        <select
          aria-label={t('clanx.sortLabel')}
          value={sort}
          onChange={(event) => setSort(event.target.value as Sort)}
          className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/60 px-2 py-1 text-[9px] font-black text-amber-200 outline-none"
        >
          {sorts.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
        </select>
      </div>

      {!visible.length ? <p className="py-6 text-center text-[10px] text-slate-500">{t('clanx.noMembers')}</p> : null}

      {visible.map((member) => (
        <button
          key={member.userId}
          type="button"
          onClick={() => setDetail(member)}
          className="w-full rounded-2xl border border-white/10 bg-black/55 p-2.5 text-left"
        >
          <div className="flex items-center gap-2">
            {member.avatar
              ? <img src={member.avatar} alt="" className="h-8 w-8 rounded-full object-cover" />
              : <span className="grid h-8 w-8 place-items-center rounded-full bg-white/10 text-[10px]">{member.name.slice(0, 2)}</span>}
            <div className="min-w-0 flex-1">
              <b className="block truncate text-xs">{member.role === 'leader' ? '👑 ' : ''}<PlayerTag username={member.username} fallback={member.name}/></b>
              <span className="text-[9px] font-black uppercase tracking-[.12em] text-amber-300">{t(`clan.role.${member.role}`)}</span>
            </div>
            <div className="text-right">
              <p className="text-[10px] font-black text-amber-200">⚔ {(member.power ?? 0).toLocaleString()}</p>
              <Activity lastActive={member.lastActive} online={member.online} />
            </div>
          </div>
        </button>
      ))}

      {detail ? (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/80 p-4" role="dialog" onClick={() => setDetail(null)}>
          <div className="w-full max-w-[340px] rounded-3xl border border-amber-300/30 bg-gradient-to-br from-[#131f36] to-black p-4" onClick={(event) => event.stopPropagation()}>
            <div className="flex items-center justify-between">
              <p className="text-[9px] font-black uppercase tracking-[.2em] text-amber-300">{t('clanx.memberDetails')}</p>
              <button onClick={() => setDetail(null)} aria-label={t('clanx.close')} className="grid h-7 w-7 place-items-center rounded-lg border border-white/10"><X className="h-3.5 w-3.5" /></button>
            </div>
            <div className="mt-2 flex items-center gap-2">
              {detail.avatar
                ? <img src={detail.avatar} alt="" className="h-11 w-11 rounded-full object-cover" />
                : <span className="grid h-11 w-11 place-items-center rounded-full bg-white/10 text-xs">{detail.name.slice(0, 2)}</span>}
              <div className="min-w-0">
                <b className="block truncate text-sm text-amber-100"><PlayerTag username={detail.username} fallback={detail.name}/></b>
                <span className="text-[9px] text-slate-400">{t(`clan.role.${detail.role}`)} {localizeText("· Lv.")}{detail.accountLevel ?? 1}</span>
              </div>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <Metric icon={<Swords className="h-2.5 w-2.5" />} label={t('clanx.playerPower')} value={(detail.power ?? 0).toLocaleString()} />
              <Metric icon={<Trophy className="h-2.5 w-2.5" />} label={t('clanx.league')} value={detail.league ?? '—'} tone="text-cyan-200" />
              <Metric icon={<Users className="h-2.5 w-2.5" />} label={t('clanx.contributionLabel')} value={(detail.contribution ?? 0).toLocaleString()} tone="text-slate-200" />
              <Metric icon={<Shield className="h-2.5 w-2.5" />} label={t('clanx.clanPointsLabel')} value={(detail.clanPoints ?? 0).toLocaleString()} tone="text-slate-200" />
            </div>
            <div className="mt-2 flex items-center justify-between rounded-xl border border-white/10 bg-black/45 px-2 py-1.5 text-[9px] text-slate-400">
              <span>{t('clanx.lastActive')}</span>
              <Activity lastActive={detail.lastActive} online={detail.online} />
            </div>
            <div className="mt-1.5 flex items-center justify-between rounded-xl border border-white/10 bg-black/45 px-2 py-1.5 text-[9px] text-slate-400">
              <span>{t('clanx.joined')}</span>
              <b className="text-slate-200">{detail.joinedAt ? t('clanx.joinedAgo', { time: activityAge(detail.joinedAt).short }) : '—'}</b>
            </div>
            {canManage && !detail.isMe ? (
              <div className="mt-3 grid grid-cols-2 gap-2">
                <button disabled={busy} onClick={() => { onAction('promote', detail.userId); setDetail(null); }} className="rounded-xl bg-white/5 py-2 text-[9px] font-black text-emerald-300 disabled:opacity-50">{t('clan.promote')}</button>
                <button disabled={busy} onClick={() => { onAction('demote', detail.userId); setDetail(null); }} className="rounded-xl bg-white/5 py-2 text-[9px] font-black text-slate-300 disabled:opacity-50">{t('clan.demote')}</button>
                <button disabled={busy} onClick={() => { onAction('kick', detail.userId); setDetail(null); }} className="rounded-xl bg-white/5 py-2 text-[9px] font-black text-rose-300 disabled:opacity-50">{t('clan.kick')}</button>
                {myRole === 'leader' ? (
                  <button disabled={busy} onClick={() => { onAction('transfer', detail.userId); setDetail(null); }} className="flex items-center justify-center gap-1 rounded-xl bg-white/5 py-2 text-[9px] font-black text-amber-300 disabled:opacity-50"><Crown className="h-3 w-3" />{t('clan.transfer')}</button>
                ) : null}
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </>
  );
}
