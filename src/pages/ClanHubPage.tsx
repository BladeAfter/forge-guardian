import { useLocalizedText } from '../LanguageContext';
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
import { grandFleetArt } from '../gameAssets';
import { OceanControl } from '../components/OceanControl';

type Tab = 'hub' | 'members' | 'requests' | 'chat' | 'missions' | 'ranking' | 'boss' | 'war';

/**
 * ClanHub: the single clan surface. Both the Clan Hall building and the compact
 * top status open this component. Every rule is enforced by the backend.
 */
export function ClanHubPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const localizeText = useLocalizedText();

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
        <section className="mt-6 rounded-3xl border p-6 text-center">
          <Shield className="mx-auto h-10 w-10" />
          <p className="mt-3 text-xs">{key ? t(key) : t('clan.loadError')}</p>
          <OceanControl onClick={() => void refetch()} className="mt-4 w-full rounded-xl py-3 text-xs font-black">{t('clan.retry')}</OceanControl>
        </section>
      </Shell>
    );
  }

  if (isLoading || !data) {
    return <Shell onClose={onClose}><div className="space-y-3 pt-6">{[1, 2, 3].map((n) => <div key={n} className="h-24 animate-pulse rounded-3xl" />)}</div></Shell>;
  }


  if (!data.inClan) {
    return (
      <Shell onClose={onClose}>
        <section className="fleet-cover fleet-discover">
          <img src={grandFleetArt.deck} width={1536} height={1024} alt="" />
          <div className="fleet-cover-caption"><span>MYTHIC SEAS</span><h1>{t('clan.title')}</h1><p>{t('clan.tagline')}</p></div>
        </section>
        <div className="fleet-enlist">
          <OceanControl onClick={() => setCreating(false)}><Users size={18} />{t('clan.find')}</OceanControl>
          <OceanControl disabled={cooldownActive} onClick={() => setCreating(true)}><UserPlus size={18} />{t('clan.create')}</OceanControl>
        </div>

        {/* Server-owned cooldown after leaving a clan: joining and creating stay blocked. */}
        {cooldownActive ? <ClanCooldownCard seconds={data.antiAbuse?.cooldown.remainingSeconds ?? 0} /> : null}


        {creating ? (
          <section className="mt-3 space-y-2 rounded-3xl border p-4">
            <Field label={t('clan.name')} value={form.name} onChange={(v) => setForm({ ...form, name: v })} />
            <Field label={t('clan.tag')} value={form.tag} onChange={(v) => setForm({ ...form, tag: v.toUpperCase() })} />
            <Field label={t('clan.description')} value={form.description} onChange={(v) => setForm({ ...form, description: v })} />
            <p className="pt-1 text-[9px] uppercase">{t('clan.joinType')}</p>
            <div className="grid grid-cols-3 gap-2">
              {(['open', 'approval', 'closed'] as const).map((type) => (
                <OceanControl key={type} onClick={() => setForm({ ...form, joinType: type })} className={`rounded-xl border py-2 text-[9px] font-black ${form.joinType === type ? 'fleet-selected' : 'fleet-unselected'}`}>{t(`clan.${type}`)}</OceanControl>
              ))}
            </div>
            <Field label={t('clan.minTrophies')} value={String(form.minimumTrophies)} onChange={(v) => setForm({ ...form, minimumTrophies: Number(v.replace(/\D/g, '')) || 0 })} />
            <p className="pt-1 text-[9px] uppercase">{t('clan.emblem')}</p>
            <div className="flex flex-wrap gap-2">
              {['dragon', 'sword', 'wolf', 'crown', 'flame', 'skull'].map((symbol) => (
                <OceanControl key={symbol} onClick={() => setForm({ ...form, symbol })} className={`rounded-xl border p-1 ${form.symbol === symbol ? 'fleet-selected' : 'fleet-unselected'}`}>
                  <ClanCrest emblem={{ symbol, background: form.background }} size={34} />
                </OceanControl>
              ))}
            </div>
            <div className="flex flex-wrap gap-2">
              {['navy', 'purple', 'crimson', 'emerald'].map((background) => (
                <OceanControl key={background} onClick={() => setForm({ ...form, background })} className={`rounded-xl border p-1 ${form.background === background ? 'fleet-selected' : 'fleet-unselected'}`}>
                  <ClanCrest emblem={{ symbol: form.symbol, background }} size={26} />
                </OceanControl>
              ))}
            </div>
            <div className="flex items-center justify-between pt-2 text-[10px]">
              <span>{t('clan.cost')}</span>
              <b className="">{data.createCostFc == null ? '…' : `${formatCurrency(data.createCostFc)} BERRIES`}</b>
            </div>
            <OceanControl
              disabled={busy}
              onClick={() => void createClan()}
              className="w-full rounded-xl py-3 text-xs font-black disabled:opacity-50"
            >{t('clan.create')}</OceanControl>
          </section>
        ) : (
          <>
            <h3 className="mb-2 mt-5 text-[10px] font-black">{t('clan.recommended')}</h3>
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

  const clan = data.clan;
  if (!clan) return <Shell onClose={onClose}>{t('clan.loadError')}</Shell>;
  // The backend is the source of truth for management rights (rank >= 2); the legacy check is only a fallback.
  const canManage = data.canManageMembers ?? ['leader', 'co-leader'].includes(data.role ?? 'member');
  const requests = data.requests ?? [];

  return (
    <Shell onClose={onClose}>
      <section className="fleet-cover">
        <img src={grandFleetArt.deck} width={1536} height={1024} alt="" />
        <div className="fleet-cover-caption"><span>GRAND FLEET · [{clan.tag}]</span><h1>{clan.name}</h1><p>{clan.description || t('clan.tagline')}</p></div>
      </section>
      <section className="fleet-manifest">
        <ClanCrest emblem={clan.emblem} size={66} initials={clan.tag} />
        <div><span>{t('clan.members')}</span><b>{clan.members}/{clan.memberLimit}</b></div>
        <div><span>{t('clan.power')}</span><b>{formatCurrency(clan.power)}</b></div>
        <div><span>{t('clan.level')}</span><b>{clan.level}</b></div>
      </section>
      <div className="fleet-progress"><span>{t('clan.xp')} · {formatCurrency(clan.xp)} / {formatCurrency(clan.xpNeeded)}</span><progress max={Math.max(1,clan.xpNeeded)} value={clan.xp} /></div>
      {data.leaderBonus ? <section className="fleet-bonus"><div><span>{t('fleet.leaderBonus')}</span><b>+{data.leaderBonus.rate * 100}%</b></div><p>{t('fleet.bonusDescription')}</p><small>{t('fleet.bonusExclusions')}</small>{data.role === 'leader' ? <><strong>{t('fleet.received')}: {formatCurrency(data.leaderBonus.berries)} BERRIES</strong><dl className="fleet-material-receipts">{Object.entries(data.leaderBonus.materials).map(([material, amount]) => <div key={material}><dt>{localizeText(material.replace(/_/g, ' '))}</dt><dd>+{formatCurrency(amount)}</dd></div>)}</dl></> : null}</section> : null}



      <div className="fleet-nav">
        <TabButton active={tab === 'hub'} onClick={() => setTab('hub')} icon={<Flame className="h-4 w-4" />} label={t('fleet.deck')} />
        <TabButton active={tab === 'members'} onClick={() => setTab('members')} icon={<Users className="h-4 w-4" />} label={t('clan.members')} />
        <TabButton active={tab === 'chat'} onClick={() => void openChat()} icon={<MessageSquare className="h-4 w-4" />} label={t('clan.chat')} />
        <TabButton active={tab === 'missions'} onClick={() => setTab('missions')} icon={<Target className="h-4 w-4" />} label={t('clan.missions')} />
        <TabButton active={tab === 'ranking'} onClick={() => setTab('ranking')} icon={<Trophy className="h-4 w-4" />} label={t('clan.ranking')} />
        <TabButton active={tab === 'boss'} onClick={() => setTab('boss')} icon={<Swords className="h-4 w-4" />} label={t('clan.boss')} />
        <TabButton active={tab === 'war'} onClick={() => setTab('war')} icon={<Castle className="h-4 w-4" />} label={t('clanwar.tab')} />
        {canManage ? (
          <div className="relative">
            <TabButton active={tab === 'requests'} onClick={() => setTab('requests')} icon={<UserPlus className="h-4 w-4" />} label={t('clanx.tabRequests')} />
            {requests.length ? <span className="pointer-events-none absolute -right-1 -top-1 grid h-4 min-w-4 place-items-center rounded-full px-1 text-[8px] font-black">{requests.length}</span> : null}
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
            <OceanControl onClick={() => setConfirmLeave(true)} className="mt-2 w-full rounded-xl border py-3 text-[10px] font-black">{t('clan.leave')}</OceanControl>
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
            <h3 className="text-[10px] font-black">{t('clan.requests')}</h3>
            {!requests.length ? <p className="py-6 text-center text-[10px]">{t('clanx.noRequests')}</p> : null}
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
                <div key={message.id} className={`rounded-2xl border border-white/10 p-2 ${message.isMe ? 'fleet-message-self' : 'fleet-message'}`}>
                  <div className="flex items-center gap-2">
                    {message.avatar ? <img src={message.avatar} alt="" className="h-6 w-6 rounded-full object-cover" /> : <span className="h-6 w-6 rounded-full" />}
                    <b className="text-[10px]">{message.name}</b>
                    <span className="ml-auto text-[8px]">{new Date(message.createdAt).toLocaleTimeString().slice(0, 5)}</span>
                  </div>
                  <p className="mt-1 break-words text-[11px]">{message.body}</p>
                </div>
              ))}
            </div>
            <div className="sticky bottom-2 flex gap-2 pt-2">
              <input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder={t('clan.sendMessage')} maxLength={300} className="min-w-0 flex-1 rounded-xl border px-3 py-2 text-xs outline-none" />
              <OceanControl onClick={() => void send()} className="grid h-10 w-10 place-items-center rounded-xl"><Send className="h-4 w-4" /></OceanControl>
            </div>
          </>
        ) : null}

        {tab === 'missions' ? (
          <>
            <h3 className="text-[10px] font-black">{t('clan.weeklyMissions')}</h3>
            {(data.missions ?? []).map((mission) => (
              <div key={mission.code} className="rounded-2xl border p-3">
                <div className="flex justify-between text-[10px]"><b>{mission.title}</b><span className="">+{mission.rewardPoints}</span></div>
                <div className="mt-2 h-2 overflow-hidden rounded-full"><div className={`h-full ${mission.completed ? 'fleet-complete' : 'fleet-fill'}`} style={{ width: `${Math.min(100, (mission.progress / Math.max(1, mission.target)) * 100)}%` }} /></div>
                <p className="mt-1 text-[9px]">{mission.progress.toLocaleString()} / {mission.target.toLocaleString()}</p>
              </div>
            ))}
          </>
        ) : null}

        {tab === 'ranking' ? (data.ranking ?? []).map((entry, index) => (
          <div key={entry.id} className="flex items-center gap-2 rounded-2xl border p-3">
            <b className="w-6">#{index + 1}</b>
            <ClanCrest emblem={entry.emblem} size={28} />
            <div className="min-w-0 flex-1"><b className="block truncate text-xs">{entry.name}</b><span className="text-[9px]">{localizeText("Lv. ")}{entry.level}</span></div>
            <b className="text-[10px]">{entry.power.toLocaleString()}</b>
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
  const localizeText = useLocalizedText();

  const t = useT();
  return (
    <div className="flex items-center gap-3 rounded-2xl border p-3">
      <ClanCrest emblem={clan.emblem} size={40} />
      <div className="min-w-0 flex-1">
        <b className="block truncate text-xs">{clan.name}</b>
        <p className="text-[9px]">[{clan.tag}{localizeText("] · Lv. ")}{clan.level} · {clan.members}/{clan.memberLimit}</p>
        <p className="text-[9px]">{t('clan.power')}: {clan.power.toLocaleString()}</p>
      </div>
      <OceanControl disabled={disabled} onClick={onJoin} className="rounded-xl border px-3 py-2 text-[9px] font-black disabled:opacity-40">{clan.joinType === 'approval' ? t('clan.requested') : t('clan.join')}</OceanControl>
    </div>
  );
}

function Field({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return (
    <label className="block">
      <span className="text-[9px] uppercase">{label}</span>
      <input value={value} onChange={(event) => onChange(event.target.value)} className="mt-1 w-full rounded-xl border px-3 py-2 text-xs outline-none" />
    </label>
  );
}


function TabButton({ active, onClick, icon, label }: { active: boolean; onClick: () => void; icon: React.ReactNode; label: string }) {
  return (
    <OceanControl onClick={onClick} className={`flex flex-col items-center gap-1 rounded-xl border py-2 text-[8px] font-black uppercase ${active ? 'fleet-selected' : 'fleet-unselected'}`}>
      {icon}{label}
    </OceanControl>
  );
}

function Shell({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  const t = useT();
  return (
    <div className="fullscreen-page seas-fleet overflow-y-auto">
      <div className="forge-safe-page fleet-inner mx-auto min-h-full w-full p-3">
        <header className="mb-3 flex items-center justify-between">
          <OceanControl aria-label={t('clanx.close')} onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border"><ArrowLeft /></OceanControl>
          <div className="text-center"><p className="text-[9px]">Mythic Seas</p><b>{t('clan.title')}</b></div>
          <Shield className="" />
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
    <div className="fixed inset-0 z-[60] grid place-items-center p-4">
      <div className="w-full max-w-[360px] border p-5 text-center">
        <AlertTriangle className="mx-auto h-10 w-10" />
        <h3 className="mt-2 text-sm font-black">{t('clan.leaveConfirm.title')}</h3>
        <p className="mt-2 text-[11px] leading-relaxed">{t('clan.leaveConfirm.body')}</p>
        <div className="mt-3 rounded-2xl border p-3">
          <p className="text-[9px] uppercase">{t('clan.leaveConfirm.cooldown')}</p>
          <b className="text-lg">{hours}h</b>
        </div>
        <div className="mt-4 grid grid-cols-2 gap-2">
          <OceanControl onClick={onCancel} className="rounded-xl border py-3 text-[10px] font-black">{t('clan.leaveConfirm.cancel')}</OceanControl>
          <OceanControl disabled={busy} onClick={onConfirm} className="rounded-xl py-3 text-[10px] font-black disabled:opacity-50">{t('clan.leaveConfirm.confirm')}</OceanControl>
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
    <section className="mt-3 rounded-3xl border p-4 text-center">
      <Hourglass className="mx-auto h-8 w-8" />
      <h3 className="mt-1 text-[11px] font-black">{t('clan.cooldown.title')}</h3>
      <p className="mt-1 text-[10px]">{t('clan.cooldown.body')}</p>
      <p className="mt-2 text-[9px] uppercase">{t('clan.cooldown.in')}</p>
      <b className="text-xl">{cooldownLabel(left)}</b>
    </section>
  );
}
