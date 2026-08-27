import { useCallback, useEffect, useState } from 'react';
import { ArrowLeft, Clock, Flame, Loader2, Lock, Shield, Swords, Trophy, Users } from 'lucide-react';
import { toast } from 'sonner';
import { clanRequest } from '../clans';
import { clanErrorMessage } from '../lib/clanErrors';
import { formatCurrency } from '../utils';
import bossArt from '../assets/clan-raid-boss.jpg';

/**
 * CLAN RAID — dedicated collective boss screen.
 * Everything shown here (HP, day, phase, damage, kill status) is computed
 * server-side; the client only renders the payload of `raid-state`.
 * This is NOT the Personal Clan Boss: one boss, one shared HP pool, whole clan attacks it.
 */

type Ranking = { username: string; avatar: string | null; damage: number; attacks: number };
type Raid = {
  id: string;
  name: string;
  tier: string;
  maxHp: number;
  currentHp: number;
  status: string;
  atk: number;
  def: number;
  startedAt: string;
  endsAt: string;
  day: number;
  deadlineDays: number;
  targetDays: number;
  phase: number;
  phases: number;
  phaseFloor: number;
  phaseLocked: boolean;
  nextPhaseAt: string;
  unlockedPct: number;
  allowedDamage: number;
  damageDealt: number;
  remainingAllowed: number;

  catchupPct: number;
  totalDamage: number;
  participants: number;
  memberCount: number;
  attacksPerDay: number;
  attacksUsed: number;
  myDamage: number;
  clearedInHours: number | null;
  ranking: Ranking[];
};

function countdown(target: string) {
  const ms = new Date(target).getTime() - Date.now();
  if (ms <= 0) return '00h 00m';
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  return `${String(h).padStart(2, '0')}h ${String(m).padStart(2, '0')}m`;
}

export function ClanRaidScreen({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const [raid, setRaid] = useState<Raid | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const [, setTick] = useState(0);

  const load = useCallback(async () => {
    try {
      const data = await clanRequest<{ inClan: boolean; raid: Raid | null }>(telegramInitData, { action: 'raid-state' });
      setRaid(data.raid ?? null);
    } catch {
      toast.error('Não foi possível carregar a Clan Raid.');
    } finally {
      setLoading(false);
    }
  }, [telegramInitData]);

  useEffect(() => { void load(); }, [load]);
  // Light refresh only — no aggressive polling.
  useEffect(() => {
    const timer = window.setInterval(() => setTick((v) => v + 1), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  const attack = async () => {
    if (busy || !raid) return;
    setBusy(true);
    try {
      const result = await clanRequest<{ status: string; damage: number }>(telegramInitData, {
        action: 'raid-attack',
        clientKey: `${raid.id}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      });
      if (result.status === 'duplicate') toast('Ataque já registrado.');
      else toast.success(`Dano causado: ${formatCurrency(result.damage)}`);
      await load();
    } catch (error) {
      toast.error(clanErrorMessage(error, 'Ataque indisponível.'));
      await load();

    } finally {
      setBusy(false);
    }
  };

  const hpPct = raid && raid.maxHp > 0 ? Math.max(0, (raid.currentHp / raid.maxHp) * 100) : 0;
  const floorPct = raid && raid.maxHp > 0 ? Math.max(0, (raid.phaseFloor / raid.maxHp) * 100) : 0;
  const outOfAttacks = raid ? raid.attacksUsed >= raid.attacksPerDay : true;
  const canAttack = Boolean(raid && raid.status === 'ACTIVE' && !raid.phaseLocked && !outOfAttacks);
  const ranking = raid ? (showAll ? raid.ranking : raid.ranking.slice(0, 3)) : [];

  return (
    <div className="fullscreen-page overflow-y-auto bg-[#04060d] text-white">
      <div className="forge-safe-page mx-auto min-h-full w-full max-w-[480px] p-3">
        <header className="mb-3 flex items-center justify-between">
          <button onClick={onClose} className="grid h-10 w-10 place-items-center rounded-xl border border-amber-300/25 bg-black/50"><ArrowLeft /></button>
          <div className="text-center">
            <p className="text-[9px] tracking-[.28em] text-amber-300">MYTHREON</p>
            <b className="text-sm">CLAN RAID</b>
          </div>
          <Flame className="text-rose-400" />
        </header>

        {loading ? (
          <div className="flex justify-center py-16"><Loader2 className="h-7 w-7 animate-spin text-amber-400" /></div>
        ) : !raid ? (
          <p className="py-16 text-center text-sm text-slate-400">Nenhuma Clan Raid ativa neste ciclo.</p>
        ) : (
          <div className="space-y-2.5">
            {/* BOSS STAGE */}
            <section className="overflow-hidden rounded-[1.5rem] border border-amber-400/25 bg-gradient-to-b from-[#0d1526] to-black shadow-[0_0_40px_-12px_rgba(244,63,94,.45)]">
              <div className="relative">
                <img src={bossArt} alt={raid.name} loading="lazy" width={1024} height={1024} className="h-52 w-full object-cover" />
                <div className="absolute inset-0 bg-gradient-to-t from-black via-black/25 to-transparent" />
                <div className="absolute bottom-2 left-3 right-3">
                  <p className="text-[9px] font-black uppercase tracking-[.35em] text-amber-300">{raid.tier}</p>
                  <h2 className="text-xl font-black uppercase leading-tight text-rose-100 drop-shadow">{raid.name}</h2>
                </div>
                <div className="absolute right-2 top-2 rounded-full border border-amber-300/40 bg-black/70 px-2.5 py-1 text-[9px] font-black text-amber-200">
                  DIA {raid.day} / {raid.deadlineDays}
                </div>
              </div>

              <div className="p-3">
                {/* Shared HP with the day's health gate marked */}
                <div className="mb-1 flex items-baseline justify-between text-[11px]">
                  <span className="font-black text-rose-200">HP COMPARTILHADO</span>
                  <span className="text-slate-300">{formatCurrency(raid.currentHp)} / {formatCurrency(raid.maxHp)}</span>
                </div>
                <div className="relative h-4 w-full overflow-hidden rounded-full bg-black/60 ring-1 ring-white/10">
                  <div className="h-full rounded-full bg-gradient-to-r from-rose-500 via-red-600 to-red-800 transition-all duration-700" style={{ width: `${hpPct}%` }} />
                  {raid.phaseFloor > 0 ? (
                    <div className="absolute inset-y-0 w-[2px] bg-amber-300 shadow-[0_0_8px_2px_rgba(252,211,77,.6)]" style={{ left: `${floorPct}%` }} />
                  ) : null}
                </div>
                <div className="mt-1 flex justify-between text-[9px] text-slate-500">
                  <span>{hpPct.toFixed(1)}% restante</span>
                  <span>ALVO DE MORTE: DIA {raid.targetDays}</span>
                </div>

                <div className="mt-2.5 grid grid-cols-4 gap-1.5 text-center">
                  <Cell label="Fase" value={`${raid.phase}/${raid.phases}`} />
                  <Cell label="Ataques" value={`${raid.attacksUsed}/${raid.attacksPerDay}`} />
                  <Cell label="Participantes" value={`${raid.participants}/${raid.memberCount}`} />
                  <Cell label="Encerra" value={countdown(raid.endsAt)} />
                </div>

                {raid.catchupPct > 0 ? (
                  <p className="mt-2 rounded-xl border border-emerald-400/30 bg-emerald-500/10 px-2 py-1.5 text-center text-[10px] font-black text-emerald-200">
                    CATCH-UP ATIVO · +{raid.catchupPct}% de dano na raid
                  </p>
                ) : null}

                {raid.status === 'ACTIVE' ? (
                  raid.phaseLocked ? (
                    <div className="mt-2.5 rounded-xl border border-amber-400/40 bg-amber-400/10 p-2.5 text-center">
                      <p className="flex items-center justify-center gap-1.5 text-[11px] font-black uppercase tracking-widest text-amber-200"><Lock className="h-3.5 w-3.5" />Fase concluída</p>
                      <p className="mt-1 flex items-center justify-center gap-1 text-[10px] text-slate-300"><Clock className="h-3 w-3" />Próxima fase em {countdown(raid.nextPhaseAt)}</p>
                      <p className="mt-1 text-[9px] text-slate-500">Nenhum ataque é consumido durante o bloqueio.</p>
                    </div>
                  ) : (
                    <button
                      disabled={busy || !canAttack}
                      onClick={() => void attack()}
                      className="mt-2.5 w-full rounded-xl bg-gradient-to-r from-rose-600 to-red-700 py-3 text-xs font-black uppercase tracking-widest text-white shadow-[0_8px_24px_-8px_rgba(244,63,94,.8)] disabled:opacity-40"
                    >
                      {busy ? <Loader2 className="mx-auto h-4 w-4 animate-spin" /> : <><Swords className="mr-1.5 inline h-4 w-4" />{outOfAttacks ? 'Sem ataques hoje' : 'Atacar Raid'}</>}
                    </button>
                  )
                ) : (
                  <div className="mt-2.5 rounded-xl border border-white/15 bg-black/60 p-2.5 text-center">
                    <p className="text-[11px] font-black uppercase tracking-widest text-amber-200">
                      {raid.status === 'DEFEATED' || raid.status === 'SETTLED' ? 'Clan Raid derrotada' : 'Raid expirada'}
                    </p>
                    {raid.clearedInHours ? (
                      <p className="mt-1 text-[10px] text-slate-400">
                        Tempo: {Math.floor(raid.clearedInHours / 24)}d {Math.round(raid.clearedInHours % 24)}h
                      </p>
                    ) : null}
                  </div>
                )}
              </div>
            </section>

            {/* MY CONTRIBUTION */}
            <section className="grid grid-cols-3 gap-1.5">
              <Cell label="Meu dano" value={formatCurrency(raid.myDamage)} />
              <Cell label="Dano do clã" value={formatCurrency(raid.totalDamage)} />
              <Cell label="ATK do boss" value={formatCurrency(raid.atk)} />
            </section>

            {/* RANKING */}
            <section className="rounded-2xl border border-amber-500/20 bg-gradient-to-b from-slate-900/80 to-black/60 p-2.5">
              <div className="mb-1.5 flex items-center justify-between">
                <span className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-widest text-amber-300"><Trophy className="h-3.5 w-3.5" />Top Damage</span>
                {raid.ranking.length > 3 ? (
                  <button onClick={() => setShowAll((v) => !v)} className="text-[9px] font-black uppercase tracking-widest text-slate-400">
                    {showAll ? 'Recolher' : 'Ver todos'}
                  </button>
                ) : null}
              </div>
              <div className="space-y-1">
                {ranking.map((p, i) => (
                  <div key={p.username} className="flex items-center gap-2 rounded-xl bg-black/40 px-2 py-1.5">
                    <b className={`w-5 text-[11px] ${i === 0 ? 'text-amber-300' : 'text-slate-400'}`}>#{i + 1}</b>
                    {p.avatar ? <img src={p.avatar} alt="" loading="lazy" className="h-6 w-6 rounded-full object-cover" /> : <span className="h-6 w-6 rounded-full bg-white/10" />}
                    <span className="min-w-0 flex-1 truncate text-[11px] text-slate-200">{p.username}</span>
                    <span className="shrink-0 text-[11px] font-black text-rose-300">{formatCurrency(p.damage)}</span>
                  </div>
                ))}
                {!raid.ranking.length ? <p className="py-3 text-center text-[10px] text-slate-500">Nenhum ataque registrado ainda.</p> : null}
              </div>
              <p className="mt-2 flex items-center gap-1 text-[9px] text-slate-500">
                <Users className="h-3 w-3" />{raid.participants} participantes · <Shield className="h-3 w-3" />DEF {formatCurrency(raid.def)}
              </p>
            </section>

            <p className="pb-8 text-center text-[9px] leading-relaxed text-slate-600">
              HP calculado pela força real do clã · alvo de {raid.targetDays} dias · prazo de {raid.deadlineDays} dias ·
              {' '}{raid.phases} fases de {Math.round(100 / raid.phases)}% liberadas por dia.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function Cell({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-black/45 px-1.5 py-1.5 text-center">
      <div className="truncate text-[11px] font-black text-slate-100">{value}</div>
      <div className="text-[8px] uppercase tracking-widest text-slate-500">{label}</div>
    </div>
  );
}
