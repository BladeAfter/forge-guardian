import { useState } from 'react';
import { ArrowLeft, Crown, MessageSquare, Send, Shield, Swords, Target, Trophy, Users } from 'lucide-react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import { useT } from '../LanguageContext';
import { useClanDashboard } from '../hooks';
import { clanErrorKey, clanRequest, type ClanMessage, type ClanSummary } from '../clans';
import { ClanCrest } from '../components/ClanHall';
import { formatCurrency } from '../utils';

type Tab = 'members' | 'chat' | 'missions' | 'ranking' | 'boss';

/**
 * ClanHub: the single clan surface. Both the Clan Hall building and the compact
 * top status open this component. Every rule is enforced by the backend.
 */
export function ClanHubPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const queryClient = useQueryClient();
  const { data, isLoading, refetch } = useClanDashboard(telegramInitData, true);
  const [tab, setTab] = useState<Tab>('members');
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ name: '', tag: '', description: '', joinType: 'open', minimumTrophies: 0, symbol: 'dragon', background: 'navy' });
  const [messages, setMessages] = useState<ClanMessage[] | null>(null);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['clan-dashboard'] });
    await refetch();
  };

  const run = async (input: Record<string, unknown>, successKey?: string) => {
    if (busy) return null;
    setBusy(true);
    try {
      const result = await clanRequest<Record<string, unknown>>(telegramInitData, input);
      if (successKey) toast.success(t(successKey));
      await refresh();
      return result;
    } catch (error) {
      const raw = error instanceof Error ? error.message : '';
      const key = clanErrorKey(raw);
      toast.error(key ? t(key) : t('clan.loadError'));
      return null;
    } finally {
      setBusy(false);
    }
  };

  const openChat = async () => {
    setTab('chat');
    const result = await clanRequest<{ messages: ClanMessage[] }>(telegramInitData, { action: 'chat', chatAction: 'list' }).catch(() => null);
    if (result) setMessages(result.messages);
  };

  const send = async () => {
    const body = draft.trim();
    if (!body) return;
    setDraft('');
    const result = await clanRequest<{ messages: ClanMessage[] }>(telegramInitData, { action: 'chat', chatAction: 'send', body }).catch(() => null);
    if (result) setMessages(result.messages);
  };

  if (isLoading || !data) {
    return <Shell onClose={onClose}><div className="space-y-3 pt-6">{[1, 2, 3].map((n) => <div key={n} className="h-24 animate-pulse rounded-3xl bg-white/5" />)}</div></Shell>;
  }

  if (!data.inClan) {
    return (
      <Shell onClose={onClose}>
        <section className="rounded-[2rem] border border-amber-300/30 bg-gradient-to-br from-[#101d35] via-[#0a1220] to-black p-5 text-center">
          <Shield className="mx-auto h-12 w-12 text-amber-300" />
          <p className="mt-2 text-[9px] font-bold uppercase tracking-[.35em] text-amber-300">MYTHREON</p>
          <h2 className="text-2xl font-black text-amber-100">{t('clan.title')}</h2>
          <p className="mt-1 text-xs text-slate-300">{t('clan.tagline')}</p>
          <div className="mt-4 grid gap-2">
            <button onClick={() => setCreating(false)} className="rounded-xl border border-amber-300/30 bg-black/50 py-3 text-xs font-black text-amber-200">{t('clan.find')}</button>
            <button onClick={() => setCreating(true)} className="rounded-xl bg-gradient-to-b from-amber-400 to-amber-600 py-3 text-xs font-black text-black">{t('clan.create')}</button>
          </div>
        </section>

        {creating ? (
          <section className="mt-3 space-y-2 rounded-3xl border border-white/10 bg-black/60 p-4">
            <Field label={t('clan.name')} value={form.name} onChange={(v) => setForm({ ...form, name: v })} />
            <Field label={t('clan.tag')} value={form.tag} onChange={(v) => setForm({ ...form, tag: v.toUpperCase() })} />
            <Field label={t('clan.description')} value={form.description} onChange={(v) => setForm({ ...form, description: v })} />
            <p className="pt-1 text-[9px] uppercase tracking-[.2em] text-slate-400">{t('clan.joinType')}</p>
            <div className="grid grid-cols-3 gap-2">
              {(['open', 'approval', 'closed'] as const).map((type) => (
                <button key={type} onClick={() => setForm({ ...form, joinType: type })} className={`rounded-xl border py-2 text-[9px] font-black ${form.joinType === type ? 'border-amber-300 bg-amber-400/20 text-amber-200' : 'border-white/10 text-slate-400'}`}>{t(`clan.${type}`)}</button>
              ))}
            </div>
            <Field label={t('clan.minTrophies')} value={String(form.minimumTrophies)} onChange={(v) => setForm({ ...form, minimumTrophies: Number(v.replace(/\D/g, '')) || 0 })} />
            <p className="pt-1 text-[9px] uppercase tracking-[.2em] text-slate-400">{t('clan.emblem')}</p>
            <div className="flex flex-wrap gap-2">
              {['dragon', 'sword', 'wolf', 'crown', 'flame', 'skull'].map((symbol) => (
                <button key={symbol} onClick={() => setForm({ ...form, symbol })} className={`rounded-xl border p-1 ${form.symbol === symbol ? 'border-amber-300' : 'border-white/10'}`}>
                  <ClanCrest emblem={{ symbol, background: form.background }} size={34} />
                </button>
              ))}
            </div>
            <div className="flex flex-wrap gap-2">
              {['navy', 'purple', 'crimson', 'emerald'].map((background) => (
                <button key={background} onClick={() => setForm({ ...form, background })} className={`rounded-xl border p-1 ${form.background === background ? 'border-amber-300' : 'border-white/10'}`}>
                  <ClanCrest emblem={{ symbol: form.symbol, background }} size={26} />
                </button>
              ))}
            </div>
            <div className="flex items-center justify-between pt-2 text-[10px] text-slate-300">
              <span>{t('clan.cost')}</span>
              <b className="text-amber-300">{formatCurrency(data.createCostFc ?? 100000)} FC</b>
            </div>
            <button
              disabled={busy}
              onClick={() => void run({ action: 'create', ...form, emblem: { symbol: form.symbol, background: form.background, shield: 'classic', border: 'gold' } }, 'clan.created')}
              className="w-full rounded-xl bg-gradient-to-b from-amber-400 to-amber-600 py-3 text-xs font-black text-black disabled:opacity-50"
            >{t('clan.create')}</button>
          </section>
        ) : (
          <>
            <h3 className="mb-2 mt-5 text-[10px] font-black tracking-[.2em] text-amber-200">{t('clan.recommended')}</h3>
            <div className="space-y-2 pb-10">
              {(data.recommended ?? []).map((clan) => <ClanCard key={clan.id} clan={clan} onJoin={() => void run({ action: 'join', clanId: clan.id }, 'clan.joined')} />)}
            </div>
          </>
        )}
      </Shell>
    );
  }

  const clan = data.clan!;
  const canManage = ['leader', 'co-leader'].includes(data.role ?? 'member');

  return (
    <Shell onClose={onClose}>
      <section className="rounded-[2rem] border border-amber-300/30 bg-gradient-to-br from-[#101d35] via-[#0a1220] to-black p-4 text-center">
        <div className="flex items-center justify-center"><ClanCrest emblem={clan.emblem} size={56} /></div>
        <h2 className="mt-2 text-xl font-black text-amber-100">{clan.name}</h2>
        <p className="text-[10px] font-black text-slate-400">[{clan.tag}]</p>
        <p className="mt-2 text-[10px] uppercase tracking-[.2em] text-amber-300">{t('clan.level')} {clan.level}</p>
        <p className="text-[10px] text-slate-300">{clan.members} / {clan.memberLimit} {t('clan.members')}</p>
        <div className="mt-3 text-left">
          <div className="flex justify-between text-[9px] text-slate-400"><span>{t('clan.xp')}</span><b>{clan.xp.toLocaleString()} / {clan.xpNeeded.toLocaleString()}</b></div>
          <div className="mt-1 h-2 overflow-hidden rounded-full bg-white/10"><div className="h-full bg-gradient-to-r from-amber-600 to-yellow-200" style={{ width: `${Math.min(100, (clan.xp / Math.max(1, clan.xpNeeded)) * 100)}%` }} /></div>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2 text-left">
          <Stat label={t('clan.points')} value={(data.me?.clanPoints ?? 0).toLocaleString()} />
          <Stat label={t('clan.power')} value={clan.power.toLocaleString()} />
        </div>
      </section>

      <div className="mt-3 grid grid-cols-3 gap-2">
        <TabButton active={tab === 'members'} onClick={() => setTab('members')} icon={<Users className="h-4 w-4" />} label={t('clan.members')} />
        <TabButton active={tab === 'chat'} onClick={() => void openChat()} icon={<MessageSquare className="h-4 w-4" />} label={t('clan.chat')} />
        <TabButton active={tab === 'missions'} onClick={() => setTab('missions')} icon={<Target className="h-4 w-4" />} label={t('clan.missions')} />
        <TabButton active={tab === 'ranking'} onClick={() => setTab('ranking')} icon={<Trophy className="h-4 w-4" />} label={t('clan.ranking')} />
        <TabButton active={tab === 'boss'} onClick={() => setTab('boss')} icon={<Swords className="h-4 w-4" />} label={t('clan.boss')} />
      </div>

      <div className="mt-3 space-y-2 pb-12">
        {tab === 'members' ? (
          <>
            {canManage && (data.requests ?? []).length ? (
              <>
                <h3 className="text-[10px] font-black tracking-[.2em] text-amber-200">{t('clan.requests')}</h3>
                {(data.requests ?? []).map((request) => (
                  <div key={request.id} className="flex items-center gap-2 rounded-2xl border border-white/10 bg-black/55 p-3">
                    <b className="min-w-0 flex-1 truncate text-xs">{request.name}</b>
                    <button onClick={() => void run({ action: 'manage', manageAction: 'accept', targetId: request.userId })} className="rounded-lg bg-emerald-500/20 px-2 py-1 text-[9px] font-black text-emerald-300">{t('clan.accept')}</button>
                    <button onClick={() => void run({ action: 'manage', manageAction: 'reject', targetId: request.userId })} className="rounded-lg bg-rose-500/20 px-2 py-1 text-[9px] font-black text-rose-300">{t('clan.reject')}</button>
                  </div>
                ))}
              </>
            ) : null}
            {(data.members ?? []).map((member) => (
              <div key={member.userId} className="rounded-2xl border border-white/10 bg-black/55 p-3">
                <div className="flex items-center gap-2">
                  {member.avatar ? <img src={member.avatar} alt="" className="h-8 w-8 rounded-full object-cover" /> : <span className="grid h-8 w-8 place-items-center rounded-full bg-white/10 text-[10px]">{member.name.slice(0, 2)}</span>}
                  <div className="min-w-0 flex-1">
                    <b className="block truncate text-xs">{member.role === 'leader' ? '👑 ' : ''}{member.name}</b>
                    <span className="text-[9px] text-amber-300">{t(`clan.role.${member.role}`)}</span>
                  </div>
                  <div className="text-right text-[9px] text-slate-400">
                    <p>{t('clan.power')} {member.power.toLocaleString()}</p>
                    <p>{t('clan.trophies')} {member.trophies.toLocaleString()}</p>
                    <p>{t('clan.contribution')} {member.contribution.toLocaleString()}</p>
                  </div>
                </div>
                {canManage && !member.isMe ? (
                  <div className="mt-2 flex gap-2">
                    <button onClick={() => void run({ action: 'manage', manageAction: 'promote', targetId: member.userId })} className="flex-1 rounded-lg bg-white/5 py-1 text-[9px] font-black text-emerald-300">{t('clan.promote')}</button>
                    <button onClick={() => void run({ action: 'manage', manageAction: 'demote', targetId: member.userId })} className="flex-1 rounded-lg bg-white/5 py-1 text-[9px] font-black text-slate-300">{t('clan.demote')}</button>
                    <button onClick={() => void run({ action: 'manage', manageAction: 'kick', targetId: member.userId })} className="flex-1 rounded-lg bg-white/5 py-1 text-[9px] font-black text-rose-300">{t('clan.kick')}</button>
                    {data.role === 'leader' ? <button onClick={() => void run({ action: 'manage', manageAction: 'transfer', targetId: member.userId })} className="flex-1 rounded-lg bg-white/5 py-1 text-[9px] font-black text-amber-300"><Crown className="mx-auto h-3 w-3" /></button> : null}
                  </div>
                ) : null}
              </div>
            ))}
            <button onClick={() => void run({ action: 'leave' }, 'clan.left')} className="mt-2 w-full rounded-xl border border-rose-400/30 py-3 text-[10px] font-black text-rose-300">{t('clan.leave')}</button>
          </>
        ) : null}

        {tab === 'chat' ? (
          <>
            <div className="space-y-2">
              {(messages ?? []).map((message) => (
                <div key={message.id} className={`rounded-2xl border border-white/10 p-2 ${message.isMe ? 'bg-amber-500/10' : 'bg-black/55'}`}>
                  <div className="flex items-center gap-2">
                    {message.avatar ? <img src={message.avatar} alt="" className="h-6 w-6 rounded-full object-cover" /> : <span className="h-6 w-6 rounded-full bg-white/10" />}
                    <b className="text-[10px]">{message.name}</b>
                    <span className="ml-auto text-[8px] text-slate-500">{new Date(message.createdAt).toLocaleTimeString().slice(0, 5)}</span>
                  </div>
                  <p className="mt-1 break-words text-[11px] text-slate-200">{message.body}</p>
                </div>
              ))}
            </div>
            <div className="sticky bottom-2 flex gap-2 pt-2">
              <input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder={t('clan.sendMessage')} maxLength={300} className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/70 px-3 py-2 text-xs outline-none" />
              <button onClick={() => void send()} className="grid h-10 w-10 place-items-center rounded-xl bg-amber-400 text-black"><Send className="h-4 w-4" /></button>
            </div>
          </>
        ) : null}

        {tab === 'missions' ? (
          <>
            <h3 className="text-[10px] font-black tracking-[.2em] text-amber-200">{t('clan.weeklyMissions')}</h3>
            {(data.missions ?? []).map((mission) => (
              <div key={mission.code} className="rounded-2xl border border-white/10 bg-black/55 p-3">
                <div className="flex justify-between text-[10px]"><b>{mission.title}</b><span className="text-amber-300">+{mission.rewardPoints}</span></div>
                <div className="mt-2 h-2 overflow-hidden rounded-full bg-white/10"><div className={`h-full ${mission.completed ? 'bg-emerald-400' : 'bg-gradient-to-r from-amber-600 to-yellow-200'}`} style={{ width: `${Math.min(100, (mission.progress / Math.max(1, mission.target)) * 100)}%` }} /></div>
                <p className="mt-1 text-[9px] text-slate-400">{mission.progress.toLocaleString()} / {mission.target.toLocaleString()}</p>
              </div>
            ))}
          </>
        ) : null}

        {tab === 'ranking' ? (data.ranking ?? []).map((entry, index) => (
          <div key={entry.id} className="flex items-center gap-2 rounded-2xl border border-white/10 bg-black/55 p-3">
            <b className="w-6 text-amber-300">#{index + 1}</b>
            <ClanCrest emblem={entry.emblem} size={28} />
            <div className="min-w-0 flex-1"><b className="block truncate text-xs">{entry.name}</b><span className="text-[9px] text-slate-400">Lv. {entry.level}</span></div>
            <b className="text-[10px] text-cyan-300">{entry.power.toLocaleString()}</b>
          </div>
        )) : null}

        {tab === 'boss' ? (
          data.boss ? (
            <div className="rounded-2xl border border-white/10 bg-black/55 p-4">
              <b className="text-sm">{data.boss.name}</b>
              <div className="mt-2 h-3 overflow-hidden rounded-full bg-white/10"><div className="h-full bg-gradient-to-r from-rose-600 to-amber-300" style={{ width: `${Math.max(0, (data.boss.currentHealth / Math.max(1, data.boss.maxHealth)) * 100)}%` }} /></div>
              <p className="mt-1 text-[9px] text-slate-400">{Math.round(data.boss.currentHealth).toLocaleString()} / {Math.round(data.boss.maxHealth).toLocaleString()}</p>
              <button disabled={busy} onClick={() => void run({ action: 'boss-attack' })} className="mt-3 w-full rounded-xl bg-gradient-to-b from-rose-500 to-rose-700 py-3 text-[10px] font-black text-white disabled:opacity-50">{t('clan.attack')}</button>
              <div className="mt-3 space-y-1">
                {data.boss.top.map((entry, index) => (
                  <div key={`${entry.name}-${index}`} className="flex justify-between text-[10px]"><span>#{index + 1} {entry.name}</span><b className="text-amber-300">{Math.round(entry.damage).toLocaleString()}</b></div>
                ))}
              </div>
            </div>
          ) : <p className="py-6 text-center text-[10px] text-slate-400">—</p>
        ) : null}
      </div>
    </Shell>
  );
}

function ClanCard({ clan, onJoin }: { clan: ClanSummary; onJoin: () => void }) {
  const t = useT();
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-white/10 bg-black/55 p-3">
      <ClanCrest emblem={clan.emblem} size={40} />
      <div className="min-w-0 flex-1">
        <b className="block truncate text-xs">{clan.name}</b>
        <p className="text-[9px] text-slate-400">[{clan.tag}] · Lv. {clan.level} · {clan.members}/{clan.memberLimit}</p>
        <p className="text-[9px] text-cyan-300">{t('clan.power')}: {clan.power.toLocaleString()}</p>
      </div>
      <button onClick={onJoin} className="rounded-xl border border-amber-300/40 bg-amber-400/15 px-3 py-2 text-[9px] font-black text-amber-200">{clan.joinType === 'approval' ? t('clan.requested') : t('clan.join')}</button>
    </div>
  );
}

function Field({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return (
    <label className="block">
      <span className="text-[9px] uppercase tracking-[.2em] text-slate-400">{label}</span>
      <input value={value} onChange={(event) => onChange(event.target.value)} className="mt-1 w-full rounded-xl border border-white/10 bg-black/70 px-3 py-2 text-xs outline-none" />
    </label>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl border border-white/10 bg-black/55 p-2"><p className="text-[8px] uppercase text-slate-400">{label}</p><b className="text-xs text-white">{value}</b></div>;
}

function TabButton({ active, onClick, icon, label }: { active: boolean; onClick: () => void; icon: React.ReactNode; label: string }) {
  return (
    <button onClick={onClick} className={`flex flex-col items-center gap-1 rounded-xl border py-2 text-[8px] font-black uppercase ${active ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-black/50 text-slate-400'}`}>
      {icon}{label}
    </button>
  );
}

function Shell({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  const t = useT();
  return (
    <div className="fullscreen-page overflow-y-auto text-white">
      <div className="forge-safe-page mx-auto min-h-full w-full max-w-[480px] p-3">
        <header className="mb-3 flex items-center justify-between">
          <button onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border border-amber-300/25 bg-black/50"><ArrowLeft /></button>
          <div className="text-center"><p className="text-[9px] tracking-[.28em] text-amber-300">MYTHREON</p><b>{t('clan.title')}</b></div>
          <Shield className="text-amber-300" />
        </header>
        {children}
      </div>
    </div>
  );
}
