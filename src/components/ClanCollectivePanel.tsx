import { useCallback, useEffect, useState } from 'react';
import { Coins, Flame, Gem, Hammer, Loader2, Shield, ShoppingBag, Sparkles, Swords, Trophy } from 'lucide-react';
import { toast } from 'sonner';
import { clanRequest } from '../clans';
import { formatCurrency } from '../utils';

/**
 * Collective clan layer: weekly contribution goal, milestones, shared Raid,
 * treasury, upgrades/buffs and the Clan Coin shop.
 * The Personal Clan Boss stays untouched — it only feeds contribution points here.
 */

type Milestone = { pct: number; required: number; reward: Record<string, unknown>; unlocked: boolean; claimed: boolean };
type HubState = {
  inClan: boolean;
  clan?: { name: string; tag: string; level: number; xp: number; nextLevelXp: number; members: number; activeMembers: number };
  me?: { role: string; coins: number; contributionWeek: number; contributionToday: number; contributionAllTime: number };
  weekly?: { target: number; total: number; endsAt: string; minContribution: number; milestones: Milestone[] } | null;
  raid?: { name: string; maxHp: number; currentHp: number; status: string; endsAt: string; totalDamage: number; participants: number; attacksPerDay: number; attacksUsed: number; top: { username: string; damage: number }[] } | null;
  treasury?: { fc: number; myth: number };
  upgrades?: { code: string; label: string; description: string; level: number; maxLevel: number; nextCost: number; requiredClanLevel: number }[];
  buffs?: { code: string; label: string; pct: number; costFc: number; hours: number; activePct: number; expiresAt: string | null }[];
  shop?: { code: string; label: string; cost: number; quantity: number; dailyLimit: number; boughtToday: number }[];
  contributors?: { username: string; contribution: number; raidDamage: number }[];
  bossPoints?: number[];
};

const pctOf = (a: number, b: number) => (b > 0 ? Math.min(100, Math.round((a / b) * 100)) : 0);

function Bar({ value, tone = 'amber' }: { value: number; tone?: 'amber' | 'red' | 'violet' }) {
  const tones = { amber: 'from-amber-400 to-amber-600', red: 'from-rose-500 to-red-700', violet: 'from-violet-400 to-fuchsia-600' } as const;
  return (
    <div className="h-2.5 w-full overflow-hidden rounded-full bg-black/50 ring-1 ring-white/10">
      <div className={`h-full rounded-full bg-gradient-to-r ${tones[tone]} transition-all duration-500`} style={{ width: `${value}%` }} />
    </div>
  );
}

function Section({ icon, title, right, children }: { icon: React.ReactNode; title: string; right?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-amber-500/20 bg-gradient-to-b from-slate-900/80 to-black/60 p-3 shadow-lg">
      <div className="mb-2 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-[11px] font-black uppercase tracking-widest text-amber-300">{icon}{title}</div>
        {right}
      </div>
      {children}
    </div>
  );
}

export function ClanCollectivePanel({ telegramInitData }: { telegramInitData: string }) {
  const [state, setState] = useState<HubState | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [donation, setDonation] = useState('');

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

  return (
    <div className="space-y-3">
      <Section
        icon={<Trophy className="h-3.5 w-3.5" />}
        title="Meta Semanal"
        right={<span className="text-[10px] font-bold text-slate-400">{state.clan?.activeMembers ?? 0} ativos</span>}
      >
        {weekly ? (
          <>
            <div className="mb-1 flex items-baseline justify-between text-xs">
              <span className="font-black text-amber-200">{formatCurrency(weekly.total)} / {formatCurrency(weekly.target)}</span>
              <span className="text-slate-400">sua contribuição: {formatCurrency(state.me?.contributionWeek ?? 0)}</span>
            </div>
            <Bar value={pctOf(weekly.total, weekly.target)} />
            <div className="mt-3 grid grid-cols-4 gap-2">
              {weekly.milestones.map((m) => {
                const claimable = m.unlocked && !m.claimed && (state.me?.contributionWeek ?? 0) >= weekly.minContribution;
                return (
                  <button
                    key={m.pct}
                    disabled={!claimable || busy}
                    onClick={() => void run({ action: 'milestone-claim', pct: m.pct }, `Marco ${m.pct}% resgatado!`)}
                    className={`rounded-xl border p-2 text-center text-[10px] font-black transition ${
                      m.claimed ? 'border-emerald-500/40 bg-emerald-500/10 text-emerald-300'
                        : claimable ? 'border-amber-400/60 bg-amber-400/15 text-amber-200 animate-pulse'
                        : 'border-white/10 bg-black/40 text-slate-500'}`}
                  >
                    <div className="text-sm">{m.pct}%</div>
                    <div>{m.claimed ? 'RESGATADO' : m.unlocked ? 'RESGATAR' : formatCurrency(m.required)}</div>
                  </button>
                );
              })}
            </div>
            <p className="mt-2 text-[10px] text-slate-500">
              Mínimo de {formatCurrency(weekly.minContribution)} pontos para resgatar. Boss Pessoal rende {(state.bossPoints ?? []).join(' / ')} pontos.
            </p>
          </>
        ) : <p className="text-xs text-slate-400">Ciclo semanal iniciando…</p>}
      </Section>

      <Section icon={<Flame className="h-3.5 w-3.5" />} title="Clan Raid" right={raid ? <span className="text-[10px] font-bold text-slate-400">{raid.attacksUsed}/{raid.attacksPerDay} ataques hoje</span> : null}>
        {raid ? (
          <>
            <div className="mb-1 flex items-baseline justify-between text-xs">
              <span className="font-black text-rose-200">{raid.name}</span>
              <span className="text-slate-400">{formatCurrency(raid.currentHp)} / {formatCurrency(raid.maxHp)} HP</span>
            </div>
            <Bar value={pctOf(raid.currentHp, raid.maxHp)} tone="red" />
            <button
              disabled={busy || raid.status !== 'ACTIVE' || raid.attacksUsed >= raid.attacksPerDay}
              onClick={() => void run({ action: 'raid-attack' }, 'Ataque desferido!')}
              className="mt-3 w-full rounded-xl bg-gradient-to-r from-rose-600 to-red-700 py-2.5 text-xs font-black uppercase tracking-widest text-white disabled:opacity-40"
            >
              <Swords className="mr-1 inline h-4 w-4" />{raid.status === 'ACTIVE' ? 'Atacar Raid' : 'Raid encerrada'}
            </button>
            <div className="mt-2 space-y-1">
              {raid.top.map((p, i) => (
                <div key={p.username} className="flex justify-between text-[11px] text-slate-300">
                  <span>{i + 1}. {p.username}</span><span className="font-bold text-rose-300">{formatCurrency(p.damage)}</span>
                </div>
              ))}
            </div>
          </>
        ) : <p className="text-xs text-slate-400">Nenhuma raid ativa.</p>}
      </Section>

      <Section icon={<Gem className="h-3.5 w-3.5" />} title="Tesouro do Clã" right={<span className="text-[10px] font-bold text-amber-300">{formatCurrency(state.me?.coins ?? 0)} Clan Coins</span>}>
        <div className="mb-2 grid grid-cols-2 gap-2 text-center text-[11px]">
          <div className="rounded-xl bg-black/40 p-2"><div className="font-black text-amber-300">{formatCurrency(state.treasury?.fc ?? 0)}</div><div className="text-slate-500">FC</div></div>
          <div className="rounded-xl bg-black/40 p-2"><div className="font-black text-violet-300">{formatCurrency(state.treasury?.myth ?? 0)}</div><div className="text-slate-500">MYTH</div></div>
        </div>
        <div className="flex gap-2">
          <input
            value={donation}
            onChange={(e) => setDonation(e.target.value.replace(/[^\d]/g, ''))}
            placeholder="Quantidade"
            inputMode="numeric"
            className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/50 px-3 py-2 text-xs text-white outline-none"
          />
          <button disabled={busy || !donation} onClick={() => void run({ action: 'treasury-donate', asset: 'FC', amount: Number(donation) }, 'Doação registrada!').then(() => setDonation(''))}
            className="rounded-xl bg-amber-500/20 px-3 text-[11px] font-black text-amber-200 disabled:opacity-40">DOAR FC</button>
          <button disabled={busy || !donation} onClick={() => void run({ action: 'treasury-donate', asset: 'MYTH', amount: Number(donation) }, 'Doação registrada!').then(() => setDonation(''))}
            className="rounded-xl bg-violet-500/20 px-3 text-[11px] font-black text-violet-200 disabled:opacity-40">MYTH</button>
        </div>
        <p className="mt-2 text-[10px] text-slate-500">O tesouro não pode ser sacado: financia construções e buffs coletivos.</p>
      </Section>

      <Section icon={<Hammer className="h-3.5 w-3.5" />} title="Construções">
        <div className="space-y-2">
          {(state.upgrades ?? []).map((u) => (
            <div key={u.code} className="flex items-center justify-between gap-2 rounded-xl bg-black/40 p-2">
              <div className="min-w-0">
                <div className="truncate text-[11px] font-black text-slate-100">{u.label} <span className="text-amber-300">Nv {u.level}/{u.maxLevel}</span></div>
                <div className="truncate text-[10px] text-slate-500">{u.description}</div>
              </div>
              <button disabled={busy || u.level >= u.maxLevel} onClick={() => void run({ action: 'upgrade-buy', code: u.code }, 'Construção evoluída!')}
                className="shrink-0 rounded-lg bg-amber-500/20 px-2.5 py-1.5 text-[10px] font-black text-amber-200 disabled:opacity-40">
                {u.level >= u.maxLevel ? 'MÁX' : `${formatCurrency(u.nextCost)} FC`}
              </button>
            </div>
          ))}
        </div>
      </Section>

      <Section icon={<Sparkles className="h-3.5 w-3.5" />} title="Buffs de Guilda">
        <div className="space-y-2">
          {(state.buffs ?? []).map((b) => (
            <div key={b.code} className="flex items-center justify-between gap-2 rounded-xl bg-black/40 p-2">
              <div className="min-w-0">
                <div className="truncate text-[11px] font-black text-slate-100">{b.label}</div>
                <div className="text-[10px] text-slate-500">+{b.pct}% por {b.hours}h {b.activePct > 0 ? `• ativo +${b.activePct}%` : ''}</div>
              </div>
              <button disabled={busy} onClick={() => void run({ action: 'buff-activate', code: b.code }, 'Buff ativado!')}
                className="shrink-0 rounded-lg bg-violet-500/20 px-2.5 py-1.5 text-[10px] font-black text-violet-200 disabled:opacity-40">
                {formatCurrency(b.costFc)} FC
              </button>
            </div>
          ))}
        </div>
      </Section>

      <Section icon={<ShoppingBag className="h-3.5 w-3.5" />} title="Loja do Clã">
        <div className="grid grid-cols-2 gap-2">
          {(state.shop ?? []).map((s) => (
            <button key={s.code} disabled={busy || (s.dailyLimit > 0 && s.boughtToday >= s.dailyLimit)}
              onClick={() => void run({ action: 'clan-shop-buy', code: s.code, quantity: 1, clientKey: `${s.code}-${Date.now()}` }, 'Compra realizada!')}
              className="rounded-xl border border-white/10 bg-black/40 p-2 text-left disabled:opacity-40">
              <div className="truncate text-[11px] font-black text-slate-100">{s.label}</div>
              <div className="text-[10px] text-amber-300"><Coins className="mr-1 inline h-3 w-3" />{formatCurrency(s.cost)}</div>
              {s.dailyLimit > 0 ? <div className="text-[10px] text-slate-500">hoje {s.boughtToday}/{s.dailyLimit}</div> : null}
            </button>
          ))}
        </div>
      </Section>

      <Section icon={<Shield className="h-3.5 w-3.5" />} title="Top Contribuidores">
        <div className="space-y-1">
          {(state.contributors ?? []).map((c, i) => (
            <div key={c.username} className="flex justify-between text-[11px] text-slate-300">
              <span>{i + 1}. {c.username}</span>
              <span className="font-bold text-amber-300">{formatCurrency(c.contribution)} pts</span>
            </div>
          ))}
        </div>
      </Section>
    </div>
  );
}
