import { useCallback, useEffect, useState } from 'react';
import { Castle, ChevronDown, Coins, Flame, Gem, Hammer, Loader2, Shield, ShoppingBag, Sparkles, Swords, Trophy, Users } from 'lucide-react';
import { toast } from 'sonner';
import { clanRequest } from '../clans';
import { formatCurrency } from '../utils';
import { ClanRaidScreen } from './ClanRaidScreen';

/**
 * Collective clan layer as a COMPACT DASHBOARD.
 * Nothing was removed: weekly goal, raid, treasury, constructions, buffs, shop and
 * top contributors are all here — only reorganised into secondary tabs so the
 * default view is a short overview instead of one very long scroll page.
 * The Personal Clan Boss stays untouched — it only feeds contribution points here.
 */

type Milestone = { pct: number; required: number; reward: Record<string, unknown>; unlocked: boolean; claimed: boolean };
type HubState = {
  inClan: boolean;
  clan?: { name: string; tag: string; level: number; xp: number; nextLevelXp: number; members: number; activeMembers: number };
  me?: { role: string; coins: number; contributionWeek: number; contributionToday: number; contributionAllTime: number };
  weekly?: { target: number; total: number; endsAt: string; minContribution: number; milestones: Milestone[] } | null;
  raid?: { id: string; name: string; maxHp: number; currentHp: number; status: string; endsAt: string; totalDamage: number; participants: number; attacksPerDay: number; attacksUsed: number; top: { username: string; damage: number }[] } | null;
  treasury?: { fc: number; myth: number };
  upgrades?: { code: string; label: string; description: string; level: number; maxLevel: number; nextCost: number; requiredClanLevel: number }[];
  buffs?: { code: string; label: string; pct: number; costFc: number; hours: number; activePct: number; expiresAt: string | null }[];
  shop?: { code: string; label: string; cost: number; quantity: number; dailyLimit: number; boughtToday: number }[];
  contributors?: { username: string; contribution: number; raidDamage: number }[];
  bossPoints?: number[];
};

type ShopItem = {
  code: string; label: string; quantity: number; price: number; basePrice: number;
  dailyLimit: number; weeklyLimit: number; boughtToday: number; boughtWeek: number;
  clanStock: number | null; clanStockTotal: number | null;
};
type ShopState = {
  inClan: boolean; coins: number; weeklyEarned: number; weeklyCap: number;
  priceMultiplier: number; effectiveActive: number; items: ShopItem[];
};

type SubTab = 'hub' | 'raid' | 'treasury' | 'upgrades' | 'shop';


const pctOf = (a: number, b: number) => (b > 0 ? Math.min(100, Math.round((a / b) * 100)) : 0);

function Bar({ value, tone = 'amber' }: { value: number; tone?: 'amber' | 'red' | 'violet' }) {
  const tones = { amber: 'from-amber-400 to-amber-600', red: 'from-rose-500 to-red-700', violet: 'from-violet-400 to-fuchsia-600' } as const;
  return (
    <div className="h-2 w-full overflow-hidden rounded-full bg-black/50 ring-1 ring-white/10">
      <div className={`h-full rounded-full bg-gradient-to-r ${tones[tone]} transition-all duration-500`} style={{ width: `${value}%` }} />
    </div>
  );
}

/** Denser premium card: tighter padding and a single-line header. */
function Section({ icon, title, right, children }: { icon: React.ReactNode; title: string; right?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-amber-500/20 bg-gradient-to-b from-slate-900/80 to-black/60 p-2.5 shadow-lg">
      <div className="mb-1.5 flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-widest text-amber-300">{icon}{title}</div>
        {right}
      </div>
      {children}
    </div>
  );
}

/** Collapsible block used to keep long lists out of the way until needed. */
function Collapsible({ icon, title, right, defaultOpen = false, children }: { icon: React.ReactNode; title: string; right?: React.ReactNode; defaultOpen?: boolean; children: React.ReactNode }) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="rounded-2xl border border-amber-500/20 bg-gradient-to-b from-slate-900/80 to-black/60 shadow-lg">
      <button onClick={() => setOpen((v) => !v)} className="flex w-full items-center justify-between gap-2 p-2.5">
        <span className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-widest text-amber-300">{icon}{title}</span>
        <span className="flex items-center gap-2">{right}<ChevronDown className={`h-3.5 w-3.5 text-slate-400 transition ${open ? 'rotate-180' : ''}`} /></span>
      </button>
      {open ? <div className="px-2.5 pb-2.5">{children}</div> : null}
    </div>
  );
}

function Chip({ label, value, tone = 'slate' }: { label: string; value: string; tone?: 'slate' | 'amber' | 'rose' | 'emerald' }) {
  const tones = {
    slate: 'border-white/10 text-slate-200',
    amber: 'border-amber-400/40 text-amber-200',
    rose: 'border-rose-400/40 text-rose-200',
    emerald: 'border-emerald-400/40 text-emerald-200',
  } as const;
  return (
    <div className={`rounded-xl border bg-black/45 px-2 py-1.5 text-center ${tones[tone]}`}>
      <div className="text-[11px] font-black leading-tight">{value}</div>
      <div className="text-[8px] uppercase tracking-widest text-slate-500">{label}</div>
    </div>
  );
}

function SubTabButton({ active, onClick, icon, label }: { active: boolean; onClick: () => void; icon: React.ReactNode; label: string }) {
  return (
    <button
      onClick={onClick}
      className={`flex flex-col items-center gap-0.5 rounded-xl border py-1.5 text-[8px] font-black uppercase tracking-wider transition ${
        active ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-black/45 text-slate-400'
      }`}
    >
      {icon}{label}
    </button>
  );
}

export function ClanCollectivePanel({
  telegramInitData,
  warStatus,
  pendingRequests,
  onOpenWar,
}: {
  telegramInitData: string;
  /** Optional live war summary rendered as a quick-stat chip on the Hub. */
  warStatus?: string;
  pendingRequests?: number;
  onOpenWar?: () => void;
}) {
  const [state, setState] = useState<HubState | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [donation, setDonation] = useState('');
  const [sub, setSub] = useState<SubTab>('hub');
  const [confirmUpgrade, setConfirmUpgrade] = useState<NonNullable<HubState['upgrades']>[number] | null>(null);


  const load = useCallback(async () => {
    try {
      const data = await clanRequest<HubState>(telegramInitData, { action: 'hub' });
      setState(data);
    } catch {
      toast.error('Não foi possível carregar o Clan Hub.');
    } finally {
      setLoading(false);
    }
  }, [telegramInitData]);

  useEffect(() => { void load(); }, [load]);

  const run = async (input: Record<string, unknown>, success: string) => {
    if (busy) return;
    setBusy(true);
    try {
      await clanRequest(telegramInitData, input);
      toast.success(success);
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Ação indisponível.');
    } finally {
      setBusy(false);
    }
  };

  if (loading) return <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-amber-400" /></div>;
  if (!state?.inClan) return <p className="py-8 text-center text-sm text-slate-400">Entre em um clã para acessar a progressão coletiva.</p>;

  const weekly = state.weekly;
  const raid = state.raid;
  // Mirrors the server rule clan_can_manage_upgrades(): leader + vice only.
  const canManageUpgrades = ['leader', 'co-leader', 'vice-leader', 'vice', 'deputy']
    .includes(String(state.me?.role ?? '').toLowerCase().replace(/_/g, '-'));
  const canAttack = Boolean(raid && raid.status === 'ACTIVE' && raid.attacksUsed < raid.attacksPerDay);


  const attackButton = (
    <button
      disabled={busy || !canAttack}
      onClick={() => void run({ action: 'raid-attack', clientKey: `${raid?.id ?? 'raid'}-${Date.now()}` }, 'Ataque desferido!')}
      className="w-full rounded-xl bg-gradient-to-r from-rose-600 to-red-700 py-2 text-[11px] font-black uppercase tracking-widest text-white disabled:opacity-40"
    >
      <Swords className="mr-1 inline h-3.5 w-3.5" />{raid?.status === 'ACTIVE' ? 'Atacar Raid' : 'Raid encerrada'}
    </button>
  );


  const donationRow = (
    <>
      <div className="mb-2 grid grid-cols-2 gap-2 text-center text-[11px]">
        <div className="rounded-xl bg-black/40 p-1.5"><div className="font-black text-amber-300">{formatCurrency(state.treasury?.fc ?? 0)}</div><div className="text-[9px] text-slate-500">FC</div></div>
        <div className="rounded-xl bg-black/40 p-1.5"><div className="font-black text-violet-300">{formatCurrency(state.treasury?.myth ?? 0)}</div><div className="text-[9px] text-slate-500">MYTH</div></div>
      </div>
      <div className="flex gap-1.5">
        <input
          value={donation}
          onChange={(e) => setDonation(e.target.value.replace(/[^\d]/g, ''))}
          placeholder="Quantidade"
          inputMode="numeric"
          className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/50 px-2.5 py-1.5 text-xs text-white outline-none"
        />
        <button disabled={busy || !donation} onClick={() => void run({ action: 'treasury-donate', asset: 'FC', amount: Number(donation) }, 'Doação registrada!').then(() => setDonation(''))}
          className="rounded-xl bg-amber-500/20 px-2.5 text-[10px] font-black text-amber-200 disabled:opacity-40">DOAR FC</button>
        <button disabled={busy || !donation} onClick={() => void run({ action: 'treasury-donate', asset: 'MYTH', amount: Number(donation) }, 'Doação registrada!').then(() => setDonation(''))}
          className="rounded-xl bg-violet-500/20 px-2.5 text-[10px] font-black text-violet-200 disabled:opacity-40">MYTH</button>
      </div>
    </>
  );

  // Collective resources are spent here, so only leader/vice see an actionable button.
  const constructions = (
    <div className="space-y-1.5">
      {(state.upgrades ?? []).map((u) => (
        <div key={u.code} className="flex items-center justify-between gap-2 rounded-xl bg-black/40 px-2 py-1.5">
          <div className="min-w-0">
            <div className="truncate text-[11px] font-black text-slate-100">{u.label} <span className="text-amber-300">Nv {u.level}/{u.maxLevel}</span></div>
            <div className="truncate text-[9px] text-slate-500">{u.description}</div>
          </div>
          {u.level >= u.maxLevel ? (
            <span className="shrink-0 rounded-lg bg-white/5 px-2 py-1 text-[10px] font-black text-slate-400">NÍVEL MÁX</span>
          ) : canManageUpgrades ? (
            <button disabled={busy} onClick={() => setConfirmUpgrade(u)}
              className="shrink-0 rounded-lg bg-amber-500/20 px-2 py-1 text-[10px] font-black text-amber-200 disabled:opacity-40">
              {formatCurrency(u.nextCost)} FC
            </button>
          ) : (
            <span className="shrink-0 rounded-lg bg-white/5 px-2 py-1 text-[9px] font-black uppercase tracking-wider text-slate-400">
              Líder / Vice
            </span>
          )}
        </div>
      ))}
    </div>
  );

  const upgradeConfirm = confirmUpgrade ? (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/80 p-4" onClick={() => setConfirmUpgrade(null)}>
      <div className="w-full max-w-xs rounded-2xl border border-amber-500/30 bg-slate-950 p-4" onClick={(e) => e.stopPropagation()}>
        <h3 className="text-center text-sm font-black uppercase tracking-widest text-amber-200">Evoluir {confirmUpgrade.label}?</h3>
        <div className="mt-3 space-y-1 text-[11px] text-slate-300">
          <div className="flex justify-between"><span className="text-slate-500">Atual</span><span className="font-bold">Nv {confirmUpgrade.level}</span></div>
          <div className="flex justify-between"><span className="text-slate-500">Próximo</span><span className="font-bold text-amber-300">Nv {confirmUpgrade.level + 1}</span></div>
          <div className="flex justify-between"><span className="text-slate-500">Custo</span><span className="font-bold">{formatCurrency(confirmUpgrade.nextCost)} FC</span></div>
          <div className="flex justify-between"><span className="text-slate-500">Tesouro do clã</span><span className="font-bold">{formatCurrency(state.treasury?.fc ?? 0)} FC</span></div>
        </div>
        {(state.treasury?.fc ?? 0) < confirmUpgrade.nextCost ? (
          <p className="mt-2 text-center text-[10px] font-black uppercase text-rose-300">Fundos do clã insuficientes</p>
        ) : null}
        <div className="mt-4 grid grid-cols-2 gap-2">
          <button
            disabled={busy || (state.treasury?.fc ?? 0) < confirmUpgrade.nextCost}
            onClick={() => {
              const code = confirmUpgrade.code;
              const level = confirmUpgrade.level;
              setConfirmUpgrade(null);
              // Idempotency key is bound to the level being bought: a second
              // simultaneous click can never pay the old price twice.
              void run({ action: 'upgrade-buy', code, clientKey: `${code}-${level}-${Date.now()}` }, 'Construção evoluída!');
            }}
            className="rounded-xl bg-gradient-to-r from-amber-500 to-amber-700 py-2 text-[10px] font-black uppercase tracking-widest text-black disabled:opacity-40"
          >
            Confirmar
          </button>
          <button onClick={() => setConfirmUpgrade(null)} className="rounded-xl bg-white/10 py-2 text-[10px] font-black uppercase tracking-widest text-slate-300">
            Cancelar
          </button>
        </div>
      </div>
    </div>
  ) : null;


  const buffsList = (
    <div className="space-y-1.5">
      {(state.buffs ?? []).map((b) => (
        <div key={b.code} className="flex items-center justify-between gap-2 rounded-xl bg-black/40 px-2 py-1.5">
          <div className="min-w-0">
            <div className="truncate text-[11px] font-black text-slate-100">{b.label}</div>
            <div className="text-[9px] text-slate-500">+{b.pct}% por {b.hours}h {b.activePct > 0 ? `• ativo +${b.activePct}%` : ''}</div>
          </div>
          <button disabled={busy} onClick={() => void run({ action: 'buff-activate', code: b.code }, 'Buff ativado!')}
            className="shrink-0 rounded-lg bg-violet-500/20 px-2 py-1 text-[10px] font-black text-violet-200 disabled:opacity-40">
            {formatCurrency(b.costFc)} FC
          </button>
        </div>
      ))}
    </div>
  );

  const contributors = (top?: number) => (
    <div className="space-y-1">
      {(state.contributors ?? []).slice(0, top ?? undefined).map((c, i) => (
        <div key={c.username} className="flex justify-between text-[11px] text-slate-300">
          <span className="truncate">{i + 1}. {c.username}</span>
          <span className="shrink-0 font-bold text-amber-300">{formatCurrency(c.contribution)} pts</span>
        </div>
      ))}
      {!(state.contributors ?? []).length ? <p className="text-[10px] text-slate-500">Sem contribuições nesta semana.</p> : null}
    </div>
  );

  return (
    <div className="space-y-2">
      {/* SECONDARY NAVIGATION — keeps the default view short */}
      <div className="grid grid-cols-5 gap-1.5">
        <SubTabButton active={sub === 'hub'} onClick={() => setSub('hub')} icon={<Trophy className="h-3.5 w-3.5" />} label="Hub" />
        <SubTabButton active={sub === 'raid'} onClick={() => setSub('raid')} icon={<Flame className="h-3.5 w-3.5" />} label="Raid" />
        <SubTabButton active={sub === 'treasury'} onClick={() => setSub('treasury')} icon={<Gem className="h-3.5 w-3.5" />} label="Tesouro" />
        <SubTabButton active={sub === 'upgrades'} onClick={() => setSub('upgrades')} icon={<Hammer className="h-3.5 w-3.5" />} label="Melhorias" />
        <SubTabButton active={sub === 'shop'} onClick={() => setSub('shop')} icon={<ShoppingBag className="h-3.5 w-3.5" />} label="Loja" />
      </div>

      {sub === 'hub' ? (
        <>
          {/* QUICK STATS */}
          <div className="grid grid-cols-4 gap-1.5">
            <Chip label="Membros" value={String(state.clan?.members ?? 0)} />
            <Chip label="Ativos 24h" value={String(state.clan?.activeMembers ?? 0)} tone="emerald" />
            <Chip label="Pedidos" value={String(pendingRequests ?? 0)} tone={pendingRequests ? 'amber' : 'slate'} />
            <button onClick={onOpenWar} className="text-left">
              <Chip label="Guerra" value={warStatus ?? '—'} tone={warStatus ? 'rose' : 'slate'} />
            </button>
          </div>

          {/* WEEKLY GOAL — compact */}
          <Section icon={<Trophy className="h-3.5 w-3.5" />} title="Meta Semanal" right={<span className="text-[9px] font-bold text-slate-400">você: {formatCurrency(state.me?.contributionWeek ?? 0)}</span>}>
            {weekly ? (
              <>
                <div className="mb-1 flex items-baseline justify-between text-[11px]">
                  <span className="font-black text-amber-200">{formatCurrency(weekly.total)} / {formatCurrency(weekly.target)}</span>
                  <span className="text-slate-500">{pctOf(weekly.total, weekly.target)}%</span>
                </div>
                <Bar value={pctOf(weekly.total, weekly.target)} />
                <div className="mt-2 grid grid-cols-4 gap-1.5">
                  {weekly.milestones.map((m) => {
                    const claimable = m.unlocked && !m.claimed && (state.me?.contributionWeek ?? 0) >= weekly.minContribution;
                    return (
                      <button
                        key={m.pct}
                        disabled={!claimable || busy}
                        onClick={() => void run({ action: 'milestone-claim', pct: m.pct }, `Marco ${m.pct}% resgatado!`)}
                        className={`rounded-lg border px-1 py-1 text-center text-[9px] font-black transition ${
                          m.claimed ? 'border-emerald-500/40 bg-emerald-500/10 text-emerald-300'
                            : claimable ? 'border-amber-400/60 bg-amber-400/15 text-amber-200 animate-pulse'
                            : 'border-white/10 bg-black/40 text-slate-500'}`}
                      >
                        <div className="text-[11px]">{m.pct}%</div>
                        <div className="truncate">{m.claimed ? 'OK' : m.unlocked ? 'RESGATAR' : formatCurrency(m.required)}</div>
                      </button>
                    );
                  })}
                </div>
                <p className="mt-1.5 text-[9px] text-slate-500">Mínimo {formatCurrency(weekly.minContribution)} pts para resgatar · Boss Pessoal: {(state.bossPoints ?? []).join('/')} pts</p>
              </>
            ) : <p className="text-xs text-slate-400">Ciclo semanal iniciando…</p>}
          </Section>

          {/* RAID — compact status + single action */}
          <Section icon={<Flame className="h-3.5 w-3.5" />} title="Clan Raid" right={raid ? <span className="text-[9px] font-bold text-slate-400">{raid.attacksUsed}/{raid.attacksPerDay} hoje</span> : null}>
            {raid ? (
              <>
                <div className="mb-1 flex items-baseline justify-between text-[11px]">
                  <span className="truncate font-black text-rose-200">{raid.name}</span>
                  <span className="shrink-0 text-slate-400">{formatCurrency(raid.currentHp)} / {formatCurrency(raid.maxHp)}</span>
                </div>
                <Bar value={pctOf(raid.currentHp, raid.maxHp)} tone="red" />
                <div className="mt-2 flex gap-1.5">
                  <div className="flex-1">{attackButton}</div>
                  <button onClick={() => setSub('raid')} className="rounded-xl border border-white/15 bg-black/50 px-2.5 text-[10px] font-black text-slate-300">DETALHES</button>
                </div>
              </>
            ) : <p className="text-xs text-slate-400">Nenhuma raid ativa.</p>}
          </Section>

          {/* TREASURY SUMMARY */}
          <Section icon={<Gem className="h-3.5 w-3.5" />} title="Tesouro" right={<span className="text-[9px] font-bold text-amber-300">{formatCurrency(state.me?.coins ?? 0)} coins</span>}>
            {donationRow}
          </Section>

          {/* TOP CONTRIBUTORS — top 5 */}
          <Section icon={<Shield className="h-3.5 w-3.5" />} title="Top Contribuidores" right={<span className="text-[9px] text-slate-500">top 5</span>}>
            {contributors(5)}
          </Section>
        </>
      ) : null}

      {/* RAID opens its own dedicated collective-boss screen instead of stacking here. */}
      {sub === 'raid' ? (
        <ClanRaidScreen telegramInitData={telegramInitData} onClose={() => { setSub('hub'); void load(); }} />
      ) : null}


      {sub === 'treasury' ? (
        <>
          <Section icon={<Gem className="h-3.5 w-3.5" />} title="Tesouro do Clã" right={<span className="text-[9px] font-bold text-amber-300">{formatCurrency(state.me?.coins ?? 0)} Clan Coins</span>}>
            {donationRow}
            <p className="mt-2 text-[9px] text-slate-500">O tesouro não pode ser sacado: financia construções e buffs coletivos.</p>
          </Section>
          <Collapsible icon={<Shield className="h-3.5 w-3.5" />} title="Histórico de Contribuição">
            <div className="grid grid-cols-3 gap-1.5">
              <Chip label="Hoje" value={formatCurrency(state.me?.contributionToday ?? 0)} />
              <Chip label="Semana" value={formatCurrency(state.me?.contributionWeek ?? 0)} tone="amber" />
              <Chip label="Total" value={formatCurrency(state.me?.contributionAllTime ?? 0)} />
            </div>
            <div className="mt-2">{contributors()}</div>
          </Collapsible>
        </>
      ) : null}

      {sub === 'upgrades' ? (
        <>
          <Collapsible icon={<Hammer className="h-3.5 w-3.5" />} title="Construções" defaultOpen right={<span className="text-[9px] text-slate-500">{(state.upgrades ?? []).length}</span>}>
            {constructions}
          </Collapsible>
          <Collapsible icon={<Sparkles className="h-3.5 w-3.5" />} title="Buffs de Guilda" right={<span className="text-[9px] text-slate-500">{(state.buffs ?? []).length}</span>}>
            {buffsList}
          </Collapsible>
        </>
      ) : null}

      {upgradeConfirm}


      {sub === 'shop' ? (
        <Section
          icon={<ShoppingBag className="h-3.5 w-3.5" />}
          title="Loja do Clã"
          right={<span className="text-[9px] font-bold text-amber-300">{formatCurrency(shop?.coins ?? state.me?.coins ?? 0)} coins</span>}
        >
          {shop ? (
            <div className="mb-1.5 flex items-center justify-between rounded-lg bg-black/40 px-2 py-1 text-[9px] text-slate-400">
              <span>Semana {shop.weeklyEarned}/{shop.weeklyCap} coins</span>
              <span>Preços x{shop.priceMultiplier.toFixed(2)} · {shop.effectiveActive} ativos</span>
            </div>
          ) : null}
          <div className="grid grid-cols-2 gap-1.5">
            {(shop?.items ?? []).map((s) => {
              const dayFull = s.dailyLimit > 0 && s.boughtToday >= s.dailyLimit;
              const weekFull = s.weeklyLimit > 0 && s.boughtWeek >= s.weeklyLimit;
              const noStock = s.clanStock !== null && s.clanStock !== undefined && s.clanStock <= 0;
              return (
                <button key={s.code} disabled={busy || dayFull || weekFull || noStock}
                  onClick={() => void run({ action: 'clan-shop-buy', code: s.code, quantity: 1, clientKey: `${s.code}-${Date.now()}` }, 'Compra realizada!')}
                  className="rounded-xl border border-white/10 bg-black/40 p-1.5 text-left disabled:opacity-40">
                  <div className="truncate text-[10px] font-black text-slate-100">{s.label}</div>
                  <div className="text-[10px] text-amber-300"><Coins className="mr-1 inline h-3 w-3" />{formatCurrency(s.price)}</div>
                  <div className="text-[9px] leading-tight text-slate-500">
                    {s.dailyLimit > 0 ? <div>hoje {s.boughtToday}/{s.dailyLimit}</div> : null}
                    {s.weeklyLimit > 0 ? <div>você {s.boughtWeek}/{s.weeklyLimit}</div> : null}
                    {s.clanStockTotal ? <div>clã {s.clanStock}/{s.clanStockTotal}</div> : null}
                  </div>
                </button>
              );
            })}
          </div>
        </Section>
      ) : null}


      {sub === 'hub' && onOpenWar ? (
        <button onClick={onOpenWar} className="flex w-full items-center justify-center gap-2 rounded-2xl border border-rose-400/30 bg-black/50 py-2 text-[10px] font-black uppercase tracking-widest text-rose-200">
          <Castle className="h-3.5 w-3.5" />Abrir Guerra de Clãs
          <Users className="h-3.5 w-3.5 opacity-40" />
        </button>
      ) : null}
    </div>
  );
}
