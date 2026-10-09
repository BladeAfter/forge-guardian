import { useEffect, useState } from 'react';
import { AlertTriangle, ArrowLeft, Castle, Flame, Hourglass, MessageSquare, Send, Shield, Swords, Target, Trophy, UserPlus, Users } from 'lucide-react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import { useT } from '../LanguageContext';
import { useClanDashboard } from '../hooks';
import { clanErrorKey, clanRequest, cooldownLabel, type ClanMessage, type ClanSummary } from '../clans';
import { ClanCrest } from '../components/ClanHall';
import { ClanMembersList, ClanRequestCard } from '../components/ClanMembersPanel';
import { ClanBossScreen, ClanBossTeaser } from '../components/ClanBossScreen';
import { ClanWarPanel } from '../components/ClanWarPanel';
import { ClanCollectivePanel } from '../components/ClanCollectivePanel';
import { formatCurrency } from '../utils';

type Tab = 'hub' | 'members' | 'requests' | 'chat' | 'missions' | 'ranking' | 'boss' | 'war';

/**
 * ClanHub: the single clan surface. Both the Clan Hall building and the compact
 * top status open this component. Every rule is enforced by the backend.
 */
export function ClanHubPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const t = useT();
  const queryClient = useQueryClient();
  const { data, isLoading, isError, error: loadError, refetch } = useClanDashboard(telegramInitData, true);
  const [tab, setTab] = useState<Tab>('hub');
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ name: '', tag: '', description: '', joinType: 'open', minimumTrophies: 0, symbol: 'dragon', background: 'navy' });
  const [messages, setMessages] = useState<ClanMessage[] | null>(null);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  // The clan boss lives on its own fullscreen surface (exclusive creature, HP, ranking and rewards).
  const [bossOpen, setBossOpen] = useState(false);
  // Leaving a clan is irreversible for the cycle, so it always asks for confirmation first.
  const [confirmLeave, setConfirmLeave] = useState(false);
  const cooldownActive = Boolean(data?.antiAbuse?.cooldown?.active);

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
      // Detailed diagnostics already went to the console inside clanRequest.
      toast.error(key ? t(key) : `${t('clan.actionError')}${raw ? ` (${raw})` : ''}`);
      return null;
    } finally {
      setBusy(false);
    }
  };

  /** Client-side guard rails; the backend still validates and owns the atomic creation. */
  const createClan = async () => {
    const name = form.name.trim();
    const tag = form.tag.trim().toUpperCase();
    if (name.length < 3 || name.length > 24) return toast.error(t('clan.error.invalidName'));
    if (!/^[A-Z0-9]{2,5}$/.test(tag)) return toast.error(t('clan.error.invalidTag'));
    const created = await run(
      { action: 'create', ...form, name, tag, emblem: { symbol: form.symbol, background: form.background, shield: 'classic', border: 'gold' } },
      'clan.created',
    );
    if (created) {
      setCreating(false);
      setTab('members');
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

  // Fullscreen clan boss view. Rendered before the dashboard guards so the button
  // opens instantly; the screen owns its own loading, error and retry states.
  if (bossOpen) {
    return <ClanBossScreen telegramInitData={telegramInitData} onClose={() => { setBossOpen(false); setTab('boss'); void refresh(); }} />;
  }

  if (isError && !data) {
    const raw = loadError instanceof Error ? loadError.message : '';
    const key = clanErrorKey(raw);
    return (
      <Shell onClose={onClose}>
        <section className="mt-6 rounded-3xl border border-rose-400/30 bg-black/60 p-6 text-center">
          <Shield className="mx-auto h-10 w-10 text-rose-300" />
          <p className="mt-3 text-xs text-slate-300">{key ? t(key) : t('clan.loadError')}</p>
          <button onClick={() => void refetch()} className="mt-4 w-full rounded-xl bg-gradient-to-b from-amber-400 to-amber-600 py-3 text-xs font-black text-black">{t('clan.retry')}</button>
        </section>
      </Shell>
    );
  }

  if (isLoading || !data) {
    return <Shell onClose={onClose}><div className="space-y-3 pt-6">{[1, 2, 3].map((n) => <div key={n} className="h-24 animate-pulse rounded-3xl bg-white/5" />)}</div></Shell>;
  }


  if (!data.inClan) {
    return (
      <Shell onClose={onClose}>
        <section className="rounded-[2rem] border border-amber-300/30 bg-gradient-to-br from-[#101d35] via-[#0a1220] to-black p-5 text-center">
          <Shield className="mx-auto h-12 w-12 text-amber-300" />
          <p className="mt-2 text-[9px] font-bold uppercase tracking-[.35em] text-amber-300">Mythic Seas</p>
          <h2 className="text-2xl font-black text-amber-100">{t('clan.title')}</h2>
          <p className="mt-1 text-xs text-slate-300">{t('clan.tagline')}</p>
          <div className="mt-4 grid gap-2">
            <button onClick={() => setCreating(false)} className="rounded-xl border border-amber-300/30 bg-black/50 py-3 text-xs font-black text-amber-200">{t('clan.find')}</button>
            <button disabled={cooldownActive} onClick={() => setCreating(true)} className="rounded-xl bg-gradient-to-b from-amber-400 to-amber-600 py-3 text-xs font-black text-black disabled:opacity-40">{t('clan.create')}</button>
          </div>
        </section>

        {/* Server-owned cooldown after leaving a clan: joining and creating stay blocked. */}
        {cooldownActive ? <ClanCooldownCard seconds={data.antiAbuse!.cooldown.remainingSeconds} /> : null}


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
              <b className="text-amber-300">{data.createCostFc == null ? '…' : `${formatCurrency(data.createCostFc)} BERRIES`}</b>
            </div>
            <button
              disabled={busy}
              onClick={() => void createClan()}
              className="w-full rounded-xl bg-gradient-to-b from-amber-400 to-amber-600 py-3 text-xs font-black text-black disabled:opacity-50"
            >{t('clan.create')}</button>
          </section>
        ) : (
          <>
            <h3 className="mb-2 mt-5 text-[10px] font-black tracking-[.2em] text-amber-200">{t('clan.recommended')}</h3>
            <div className="space-y-2 pb-10">
              {(data.recommended ?? []).map((clan) => (
                <ClanCard
                  key={clan.id}
                  clan={clan}
                  disabled={cooldownActive}
                  onJoin={() => void run({ action: 'join', clanId: clan.id }, 'clan.joined')}
                />
              ))}
            </div>
          </>
        )}
      </Shell>
    );
  }

  const clan = data.clan!;
  // The backend is the source of truth for management rights (rank >= 2); the legacy check is only a fallback.
  const canManage = data.canManageMembers ?? ['leader', 'co-leader'].includes(data.role ?? 'member');
  const requests = data.requests ?? [];

  return (
    <Shell onClose={onClose}>
      {/* PREMIUM GUILD PROFILE PANEL — large crest, identity block, stats block, XP bar */}
      <section className="relative overflow-hidden rounded-[1.5rem] border border-amber-300/40 bg-gradient-to-br from-[#132445] via-[#0a1220] to-black p-3 shadow-[0_16px_40px_rgba(0,0,0,.6)]">
        <span aria-hidden className="pointer-events-none absolute -left-10 -top-14 h-32 w-32 rounded-full bg-cyan-400/10 blur-2xl" />
        <span aria-hidden className="pointer-events-none absolute -right-8 bottom-0 h-28 w-28 rounded-full bg-amber-400/10 blur-2xl" />
        <span aria-hidden className="pointer-events-none absolute inset-x-3 top-0 h-px bg-gradient-to-r from-transparent via-amber-200/60 to-transparent" />

        <div className="relative flex items-start gap-3">
          <ClanCrest emblem={clan.emblem} size={72} initials={clan.tag} />
          <div className="min-w-0 flex-1">
            <h2 className="truncate text-lg font-black leading-none tracking-wide text-amber-100 drop-shadow-[0_2px_6px_rgba(0,0,0,.8)]">{clan.name}</h2>
            <p className="mt-1 inline-flex items-center gap-1.5">
              <span className="rounded-md border border-amber-300/40 bg-amber-400/10 px-1.5 py-0.5 text-[9px] font-black tracking-widest text-amber-200">[{clan.tag}]</span>
              <span className="rounded-md border border-white/10 bg-black/50 px-1.5 py-0.5 text-[9px] font-black tracking-widest text-slate-300">{t('clan.level')} {clan.level}</span>
            </p>
            <p className="mt-1 text-[9px] font-bold uppercase tracking-widest text-slate-400">
              {clan.members}/{clan.memberLimit} {t('clan.members')}
            </p>
          </div>
          <div className="shrink-0 space-y-1 text-right">
            <div className="rounded-xl border border-cyan-300/25 bg-black/50 px-2 py-1">
              <p className="text-[7px] uppercase tracking-widest text-slate-500">{t('clan.power')}</p>
              <b className="text-[11px] font-black text-cyan-300">{clan.power.toLocaleString()}</b>
            </div>
            <div className="rounded-xl border border-amber-300/25 bg-black/50 px-2 py-1">
              <p className="text-[7px] uppercase tracking-widest text-slate-500">{t('clan.points')}</p>
              <b className="text-[11px] font-black text-amber-300">{(data.me?.clanPoints ?? 0).toLocaleString()}</b>
            </div>
          </div>
        </div>

        <div className="relative mt-2.5">
          <div className="flex items-baseline justify-between text-[8px] font-bold uppercase tracking-widest text-slate-400">
            <span>{t('clan.xp')}</span>
            <span className="text-slate-300">{clan.xp.toLocaleString()} / {clan.xpNeeded.toLocaleString()}</span>
          </div>
          <div className="mt-1 h-2 overflow-hidden rounded-full bg-black/60 ring-1 ring-amber-300/20">
            <div className="h-full rounded-full bg-gradient-to-r from-amber-600 via-amber-300 to-yellow-100 shadow-[0_0_10px_rgba(251,191,36,.6)]" style={{ width: `${Math.min(100, (clan.xp / Math.max(1, clan.xpNeeded)) * 100)}%` }} />
          </div>
        </div>
      </section>



      <div className="mt-3 grid grid-cols-3 gap-2">
        <TabButton active={tab === 'hub'} onClick={() => setTab('hub')} icon={<Flame className="h-4 w-4" />} label="HUB" />
        <TabButton active={tab === 'members'} onClick={() => setTab('members')} icon={<Users className="h-4 w-4" />} label={t('clan.members')} />
        <TabButton active={tab === 'chat'} onClick={() => void openChat()} icon={<MessageSquare className="h-4 w-4" />} label={t('clan.chat')} />
        <TabButton active={tab === 'missions'} onClick={() => setTab('missions')} icon={<Target className="h-4 w-4" />} label={t('clan.missions')} />
        <TabButton active={tab === 'ranking'} onClick={() => setTab('ranking')} icon={<Trophy className="h-4 w-4" />} label={t('clan.ranking')} />
        <TabButton active={tab === 'boss'} onClick={() => setTab('boss')} icon={<Swords className="h-4 w-4" />} label={t('clan.boss')} />
        <TabButton active={tab === 'war'} onClick={() => setTab('war')} icon={<Castle className="h-4 w-4" />} label={t('clanwar.tab')} />
        {canManage ? (
          <div className="relative">
            <TabButton active={tab === 'requests'} onClick={() => setTab('requests')} icon={<UserPlus className="h-4 w-4" />} label={t('clanx.tabRequests')} />
            {requests.length ? <span className="pointer-events-none absolute -right-1 -top-1 grid h-4 min-w-4 place-items-center rounded-full bg-rose-500 px-1 text-[8px] font-black text-white">{requests.length}</span> : null}
          </div>
        ) : null}
      </div>

      <div className="mt-3 space-y-2 pb-12">
        {tab === 'members' ? (
          <>
            <ClanMembersList
              members={data.members ?? []}
              stats={data.stats}
              canManage={canManage}
              myRole={data.role ?? 'member'}
              busy={busy}
              onAction={(action, targetId) => void run({ action: 'manage', manageAction: action, targetId })}
            />
            <button onClick={() => setConfirmLeave(true)} className="mt-2 w-full rounded-xl border border-rose-400/30 py-3 text-[10px] font-black text-rose-300">{t('clan.leave')}</button>
            {confirmLeave ? (
              <LeaveClanConfirm
                hours={data.antiAbuse?.leaveCooldownHours ?? 24}
                busy={busy}
                onCancel={() => setConfirmLeave(false)}
                onConfirm={async () => {
                  setConfirmLeave(false);
                  await run({ action: 'leave' }, 'clan.left');
                }}
              />
            ) : null}
          </>
        ) : null}

        {tab === 'requests' && canManage ? (
          <>
            <h3 className="text-[10px] font-black tracking-[.2em] text-amber-200">{t('clan.requests')}</h3>
            {!requests.length ? <p className="py-6 text-center text-[10px] text-slate-500">{t('clanx.noRequests')}</p> : null}
            {requests.map((request) => (
              <ClanRequestCard
                key={request.id}
                request={request}
                busy={busy}
                onAccept={() => void run({ action: 'manage', manageAction: 'accept', targetId: request.userId })}
                onReject={() => void run({ action: 'manage', manageAction: 'reject', targetId: request.userId })}
              />
            ))}
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

        {tab === 'boss' ? <ClanBossTeaser onOpen={() => setBossOpen(true)} /> : null}

        {tab === 'war' ? <ClanWarPanel telegramInitData={telegramInitData} /> : null}

        {tab === 'hub' ? (
          <ClanCollectivePanel
            telegramInitData={telegramInitData}
            pendingRequests={canManage ? requests.length : 0}
            onOpenWar={() => setTab('war')}
          />
        ) : null}

      </div>
    </Shell>
  );
}

function ClanCard({ clan, onJoin, disabled }: { clan: ClanSummary; onJoin: () => void; disabled?: boolean }) {
  const t = useT();
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-white/10 bg-black/55 p-3">
      <ClanCrest emblem={clan.emblem} size={40} />
      <div className="min-w-0 flex-1">
        <b className="block truncate text-xs">{clan.name}</b>
        <p className="text-[9px] text-slate-400">[{clan.tag}] · Lv. {clan.level} · {clan.members}/{clan.memberLimit}</p>
        <p className="text-[9px] text-cyan-300">{t('clan.power')}: {clan.power.toLocaleString()}</p>
      </div>
      <button disabled={disabled} onClick={onJoin} className="rounded-xl border border-amber-300/40 bg-amber-400/15 px-3 py-2 text-[9px] font-black text-amber-200 disabled:opacity-40">{clan.joinType === 'approval' ? t('clan.requested') : t('clan.join')}</button>
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
          <div className="text-center"><p className="text-[9px] tracking-[.28em] text-amber-300">Mythic Seas</p><b>{t('clan.title')}</b></div>
          <Shield className="text-amber-300" />
        </header>
        {children}
      </div>
    </div>
  );
}

/** Premium confirmation before leaving: the cooldown and reward loss are stated up front. */
function LeaveClanConfirm({ hours, busy, onCancel, onConfirm }: { hours: number; busy: boolean; onCancel: () => void; onConfirm: () => void }) {
  const t = useT();
  return (
    <div className="fixed inset-0 z-[60] grid place-items-center bg-black/80 p-4">
      <div className="w-full max-w-[360px] rounded-[1.75rem] border border-rose-400/40 bg-gradient-to-br from-[#1b0d14] via-[#0b0a12] to-black p-5 text-center">
        <AlertTriangle className="mx-auto h-10 w-10 text-rose-300" />
        <h3 className="mt-2 text-sm font-black text-rose-100">{t('clan.leaveConfirm.title')}</h3>
        <p className="mt-2 text-[11px] leading-relaxed text-slate-300">{t('clan.leaveConfirm.body')}</p>
        <div className="mt-3 rounded-2xl border border-white/10 bg-black/60 p-3">
          <p className="text-[9px] uppercase tracking-[.25em] text-slate-400">{t('clan.leaveConfirm.cooldown')}</p>
          <b className="text-lg text-amber-300">{hours}h</b>
        </div>
        <div className="mt-4 grid grid-cols-2 gap-2">
          <button onClick={onCancel} className="rounded-xl border border-white/15 bg-black/60 py-3 text-[10px] font-black text-slate-200">{t('clan.leaveConfirm.cancel')}</button>
          <button disabled={busy} onClick={onConfirm} className="rounded-xl bg-gradient-to-b from-rose-400 to-rose-600 py-3 text-[10px] font-black text-black disabled:opacity-50">{t('clan.leaveConfirm.confirm')}</button>
        </div>
      </div>
    </div>
  );
}

/** Live countdown for the join cooldown; the server value is the source of truth. */
function ClanCooldownCard({ seconds }: { seconds: number }) {
  const t = useT();
  const [left, setLeft] = useState(seconds);
  useEffect(() => {
    setLeft(seconds);
    const timer = window.setInterval(() => setLeft((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [seconds]);
  return (
    <section className="mt-3 rounded-3xl border border-amber-300/30 bg-black/60 p-4 text-center">
      <Hourglass className="mx-auto h-8 w-8 text-amber-300" />
      <h3 className="mt-1 text-[11px] font-black tracking-[.2em] text-amber-200">{t('clan.cooldown.title')}</h3>
      <p className="mt-1 text-[10px] text-slate-300">{t('clan.cooldown.body')}</p>
      <p className="mt-2 text-[9px] uppercase tracking-[.2em] text-slate-400">{t('clan.cooldown.in')}</p>
      <b className="text-xl text-amber-300">{cooldownLabel(left)}</b>
    </section>
  );
}
