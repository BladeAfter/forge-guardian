import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ChevronDown, Coins, Loader2, Shield, Swords, Trophy, Users, Wallet, X } from 'lucide-react';
import { fetchFamiliarHuntState, startFamiliarHunt, type FamiliarHuntMission, type FamiliarHuntPet, type FamiliarHuntResult, type FamiliarHuntReward } from '../services';
import { FamiliarHuntBattle } from './FamiliarHuntBattle';

const ARENA = '/assets/game/familiar-hunt/hunt-arena.jpg';

const RARITY_TONE: Record<string, string> = {
  common: 'border-slate-300/40 text-slate-200',
  uncommon: 'border-emerald-300/45 text-emerald-200',
  rare: 'border-sky-300/50 text-sky-200',
  epic: 'border-fuchsia-300/50 text-fuchsia-200',
  legendary: 'border-amber-300/60 text-amber-200',
};

const REWARD_LABEL: Record<string, string> = {
  pet_food: 'Ração',
  universal_fragment: 'Fragmentos',
  fc: 'FC',
  pvp_ticket: 'Ticket PvP',
  equipment: 'Equipamento',
};

const fmt = (value: number) => Math.round(value).toLocaleString('pt-BR');
const fmtTon = (value: number) => value.toFixed(2);

const rewardLine = (reward: FamiliarHuntReward) => {
  const label = REWARD_LABEL[reward.type] ?? reward.type;
  const range = reward.quantity != null ? fmt(reward.quantity)
    : reward.min === reward.max ? fmt(reward.min ?? 1) : `${fmt(reward.min ?? 1)}–${fmt(reward.max ?? 1)}`;
  const chance = reward.chance != null && reward.chance < 100 ? ` (${reward.chance}%)` : '';
  const rarity = reward.rarity ? ` ${String(reward.rarity).toUpperCase()}` : '';
  return `${range} ${label}${rarity}${chance}`;
};

/**
 * 🐾⚔️ FAMILIAR HUNT — pet COMBAT mode: 3 pets fight monsters on a battlefield.
 * Fully separate from the classic AFK Expeditions (that system is untouched).
 * Each hunt costs an ENTRY FEE, paid in FC or in the player's INTERNAL TON balance
 * (never the external wallet). The server resolves the fight and charges the fee.
 */
export default function FamiliarHuntSection({ initData, onWallet }: { initData: string; onWallet?: () => void }) {
  const client = useQueryClient();
  const [missionId, setMissionId] = useState<string | null>(null);
  const [team, setTeam] = useState<string[]>([]);
  const [picker, setPicker] = useState(false);
  const [history, setHistory] = useState(false);
  const [stage, setStage] = useState<'lobby' | 'battle' | 'result'>('lobby');
  const [result, setResult] = useState<FamiliarHuntResult | null>(null);
  const [feedback, setFeedback] = useState<string | null>(null);

  const state = useQuery({ queryKey: ['familiar-hunt'], queryFn: () => fetchFamiliarHuntState(initData) });
  const data = state.data;

  const mission: FamiliarHuntMission | null = useMemo(
    () => data?.missions.find((row) => row.id === missionId) ?? data?.missions[0] ?? null,
    [data, missionId],
  );
  const selected = useMemo(() => (data?.pets ?? []).filter((pet) => team.includes(pet.playerPetId)), [data, team]);
  const teamPower = selected.reduce((sum, pet) => sum + pet.power, 0);
  const ready = Boolean(mission) && team.length === 3;
  const runsLeft = mission ? Math.max(0, mission.maxRunsPerDay - mission.runsToday) : 0;

  const fcBalance = data?.balances?.fc ?? 0;
  const tonBalance = data?.balances?.ton ?? 0;
  const costFc = mission?.entryCostFc ?? 0;
  const costTon = mission?.entryCostTon ?? 0;
  const canPayFc = fcBalance >= costFc;
  const canPayTon = tonBalance >= costTon;

  const hunt = useMutation({
    mutationFn: (currency: 'fc' | 'ton') =>
      startFamiliarHunt(initData, String(mission?.id), team, crypto.randomUUID(), currency),
    onSuccess: (payload) => {
      setResult(payload);
      setStage('battle');
      setFeedback(null);
      void client.invalidateQueries({ queryKey: ['familiar-hunt'] });
      ['pet-dashboard', 'player-inventory', 'game-state', 'pvp-dashboard', 'wallet-summary'].forEach((key) =>
        void client.invalidateQueries({ queryKey: [key] }));
    },
    onError: (error: Error) => setFeedback(error.message),
  });

  const launch = (currency: 'fc' | 'ton') => {
    if (!ready) { setFeedback('Selecione 3 familiares para caçar.'); return; }
    if (currency === 'ton' && !canPayTon) { onWallet?.(); return; }
    if (currency === 'fc' && !canPayFc) { setFeedback('FC insuficiente para pagar a entrada.'); return; }
    hunt.mutate(currency);
  };

  if (state.isLoading) return <div className="grid h-40 place-items-center"><Loader2 className="h-6 w-6 animate-spin text-amber-300" /></div>;
  if (state.isError) return <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 p-4 text-center text-[11px] text-rose-200">{(state.error as Error).message}</p>;
  if (!data || !mission) return null;

  if (stage === 'battle' && result) {
    return <FamiliarHuntBattle result={result} onFinished={() => setStage('result')} />;
  }

  if (stage === 'result' && result) {
    return (
      <div className="space-y-4 pb-6">
        <div className={`relative overflow-hidden rounded-[26px] border p-6 text-center ${result.victory ? 'border-amber-300/50 bg-gradient-to-b from-amber-500/15 to-black/80' : 'border-rose-400/40 bg-gradient-to-b from-rose-900/30 to-black/80'}`}>
          <div className="pointer-events-none absolute -top-20 left-1/2 h-40 w-56 -translate-x-1/2 rounded-full bg-amber-300/20 blur-3xl" />
          <p className="relative text-[9px] font-black uppercase tracking-[.3em] text-slate-400">{mission.name}</p>
          <h3 className={`relative mt-1 text-3xl font-black uppercase tracking-[.08em] ${result.victory ? 'text-amber-200 drop-shadow-[0_0_18px_rgba(251,191,36,.6)]' : 'text-rose-300'}`}>
            {result.victory ? 'VITÓRIA' : 'DERROTA'}
          </h3>
          <div className="relative mt-5 grid grid-cols-3 gap-2 text-center">
            <Stat label="DANO" value={fmt(result.totalDamage)} />
            <Stat label="RODADAS" value={String(result.rounds)} />
            <Stat label="PODER" value={fmt(result.teamPower)} />
          </div>
          {result.rewards.length ? (
            <ul className="relative mt-5 space-y-1.5 text-left">
              {result.rewards.map((reward, index) => (
                <li key={`${reward.type}-${index}`} className="flex items-center gap-2 text-[11px] font-bold text-slate-200">
                  <Trophy className="h-3.5 w-3.5 shrink-0 text-amber-300" /> {rewardLine(reward)}
                </li>
              ))}
            </ul>
          ) : (
            <p className="relative mt-5 text-[11px] text-slate-400">Nenhuma recompensa nesta caçada.</p>
          )}
        </div>
        <button
          type="button"
          onClick={() => { setStage('lobby'); setResult(null); }}
          className="w-full rounded-2xl border border-white/15 bg-white/[.04] py-3.5 text-[11px] font-black uppercase tracking-[.18em] text-slate-200 transition active:scale-95"
        >
          VOLTAR À CAÇADA
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-4 pb-6">
      {/* ── header ─────────────────────────────────────────── */}
      <header className="text-center">
        <h2 className="text-xl font-black uppercase tracking-[.16em] text-amber-200 drop-shadow-[0_0_16px_rgba(251,191,36,.45)]">FAMILIAR HUNT</h2>
        <p className="mt-1 text-[10px] tracking-wide text-slate-500">3 familiares · combate real</p>
      </header>

      {/* ── mission tabs (small, horizontal) ───────────────── */}
      <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1">
        {data.missions.map((row) => {
          const on = row.id === mission.id;
          return (
            <button
              key={row.id}
              type="button"
              onClick={() => { setMissionId(row.id); setFeedback(null); }}
              className={`shrink-0 rounded-full border px-3 py-1.5 text-[9px] font-black uppercase tracking-[.1em] transition active:scale-95 ${
                on ? 'border-amber-300/70 bg-amber-300/15 text-amber-200 shadow-[0_0_14px_rgba(251,191,36,.3)]' : 'border-white/10 bg-white/[.02] text-slate-400'
              }`}
            >
              {row.name}
            </button>
          );
        })}
      </div>

      {feedback ? (
        <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 px-3 py-2.5 text-center text-[11px] font-bold text-rose-200">{feedback}</p>
      ) : null}

      {/* ── battle stage: enemies on top, pets as the focus ── */}
      <section
        className="relative overflow-hidden rounded-[28px] border border-amber-300/20 shadow-[0_0_60px_-18px_rgba(251,191,36,.35)]"
        style={{ backgroundImage: `url(${mission.background || ARENA})`, backgroundSize: 'cover', backgroundPosition: 'center' }}
      >
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_8%,rgba(56,189,248,.14),rgba(2,6,16,.94)_70%)]" />
        <div className="relative px-4 pb-4 pt-3.5">
          <div className="flex items-center justify-between">
            <span className={`rounded-full border bg-black/60 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.16em] ${RARITY_TONE[mission.rarity] ?? 'border-white/20 text-slate-200'}`}>
              {mission.rarity}
            </span>
            <span className="rounded-full border border-white/10 bg-black/60 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.14em] text-slate-300">
              {mission.runsToday}/{mission.maxRunsPerDay} HOJE
            </span>
          </div>

          {/* enemies — compact top row */}
          <div className="mt-3 flex items-end justify-center gap-3">
            {mission.enemies?.map((enemy, index) => (
              <div key={`${enemy.name}-${index}`} className="flex-1">
                {enemy.image ? (
                  <img src={enemy.image} alt={enemy.name} loading="lazy" className={`mx-auto object-contain drop-shadow-[0_0_16px_rgba(244,63,94,.4)] ${enemy.elite ? 'h-16' : 'h-12'}`} />
                ) : null}
                <p className="truncate text-center text-[8px] font-black uppercase tracking-[.06em] text-rose-200/90">{enemy.name}</p>
              </div>
            ))}
          </div>

          <div className="mx-auto my-4 h-px w-2/3 bg-gradient-to-r from-transparent via-amber-300/40 to-transparent shadow-[0_0_16px_rgba(251,191,36,.5)]" />

          {/* pets — main visual focus */}
          <div className="flex items-end justify-center gap-3">
            {[0, 1, 2].map((slot) => {
              const pet = selected[slot];
              return (
                <button key={slot} type="button" onClick={() => setPicker(true)} className="group relative flex-1">
                  {pet ? (
                    <>
                      {pet.image ? <img src={pet.image} alt={pet.name} loading="lazy" className="mx-auto h-28 object-contain drop-shadow-[0_0_22px_rgba(56,189,248,.5)]" /> : null}
                      <p className="truncate text-center text-[9px] font-black uppercase tracking-[.06em] text-sky-200">{pet.name}</p>
                      <p className="text-center text-[8px] text-slate-500">Nv {pet.level}</p>
                    </>
                  ) : (
                    <div className="mx-auto grid h-28 place-items-center rounded-2xl border border-dashed border-sky-300/25 bg-black/40 text-sky-300/50 transition group-hover:border-sky-300/60">
                      <Users className="h-6 w-6" />
                    </div>
                  )}
                </button>
              );
            })}
          </div>

          {/* two compact stat boxes */}
          <div className="mt-5 grid grid-cols-2 gap-2.5">
            <div className="rounded-2xl border border-sky-300/20 bg-black/60 py-2.5 text-center">
              <p className="text-[8px] font-black uppercase tracking-[.2em] text-sky-400/80">EQUIPE</p>
              <p className={`text-[16px] font-black ${teamPower >= mission.recommendedPower ? 'text-emerald-300' : 'text-amber-200'}`}>{fmt(teamPower)}</p>
            </div>
            <div className="rounded-2xl border border-amber-300/20 bg-black/60 py-2.5 text-center">
              <p className="text-[8px] font-black uppercase tracking-[.2em] text-amber-400/80">RECOMENDADO</p>
              <p className="text-[16px] font-black text-slate-100">{fmt(mission.recommendedPower)}</p>
            </div>
          </div>
        </div>
      </section>

      {/* ── entry cost ─────────────────────────────────────── */}
      <section className="rounded-2xl border border-amber-300/25 bg-gradient-to-r from-amber-300/[.07] to-transparent px-3.5 py-3">
        <div className="flex items-center justify-between">
          <p className="text-[9px] font-black uppercase tracking-[.24em] text-amber-200">CUSTO DE ENTRADA</p>
          <Coins className="h-3.5 w-3.5 text-amber-300/80" />
        </div>
        <div className="mt-1.5 flex items-center gap-2 text-[13px] font-black text-slate-100">
          {costFc > 0 ? <span>{fmt(costFc)} FC</span> : null}
          {costFc > 0 && costTon > 0 ? <span className="text-[9px] font-bold text-slate-500">OU</span> : null}
          {costTon > 0 ? <span className="text-sky-200">{fmtTon(costTon)} TON</span> : null}
        </div>
        <p className="mt-1 text-[9px] text-slate-500">
          Saldo: {fmt(fcBalance)} FC · {fmtTon(tonBalance)} TON interno
        </p>
      </section>

      {/* ── compact rewards ───────────────────────────────── */}
      <section className="rounded-2xl border border-white/10 bg-black/50 px-3.5 py-3">
        <p className="text-[9px] font-black uppercase tracking-[.24em] text-slate-400">RECOMPENSAS POSSÍVEIS</p>
        <ul className="mt-2 grid gap-0.5">
          {(mission.rewards ?? []).map((reward, index) => (
            <li key={`${reward.type}-${index}`} className="text-[11px] font-semibold text-slate-300">· {rewardLine(reward)}</li>
          ))}
        </ul>
      </section>

      {/* ── actions ───────────────────────────────────────── */}
      <button
        type="button"
        onClick={() => setPicker(true)}
        className="flex w-full items-center justify-center gap-2 rounded-2xl border border-sky-300/35 bg-sky-300/[.07] py-3 text-[11px] font-black uppercase tracking-[.16em] text-sky-200 transition active:scale-95"
      >
        <Shield className="h-4 w-4" /> {team.length ? `EQUIPE ${team.length}/3` : 'SELECIONAR EQUIPE'}
      </button>

      {runsLeft <= 0 ? (
        <p className="rounded-2xl border border-white/10 bg-black/50 py-3 text-center text-[11px] font-black uppercase tracking-[.16em] text-slate-500">
          LIMITE DIÁRIO ATINGIDO
        </p>
      ) : (
        <div className={`grid gap-2 ${costFc > 0 && costTon > 0 ? 'grid-cols-2' : 'grid-cols-1'}`}>
          {costFc > 0 ? (
            <button
              type="button"
              disabled={hunt.isPending}
              onClick={() => launch('fc')}
              className={`flex items-center justify-center gap-1.5 rounded-2xl border py-3.5 text-[10px] font-black uppercase tracking-[.12em] transition active:scale-95 disabled:opacity-50 ${
                canPayFc ? 'border-amber-300/60 bg-amber-300/15 text-amber-100 shadow-[0_0_20px_-8px_rgba(251,191,36,.6)]' : 'border-white/10 bg-white/[.03] text-slate-500'
              }`}
            >
              <Swords className="h-3.5 w-3.5" /> {hunt.isPending ? 'CAÇANDO...' : `CAÇAR · ${fmt(costFc)} FC`}
            </button>
          ) : null}
          {costTon > 0 ? (
            <button
              type="button"
              disabled={hunt.isPending}
              onClick={() => launch('ton')}
              className={`flex items-center justify-center gap-1.5 rounded-2xl border py-3.5 text-[10px] font-black uppercase tracking-[.12em] transition active:scale-95 disabled:opacity-50 ${
                canPayTon ? 'border-sky-300/60 bg-sky-300/15 text-sky-100 shadow-[0_0_20px_-8px_rgba(56,189,248,.6)]' : 'border-sky-300/25 bg-sky-300/[.05] text-sky-300/70'
              }`}
            >
              {canPayTon ? (
                <><Swords className="h-3.5 w-3.5" /> {hunt.isPending ? 'CAÇANDO...' : `CAÇAR · ${fmtTon(costTon)} TON`}</>
              ) : (
                <><Wallet className="h-3.5 w-3.5" /> ADICIONAR TON</>
              )}
            </button>
          ) : null}
        </div>
      )}

      {/* ── history (collapsed by default) ────────────────── */}
      {data.history.length ? (
        <section className="overflow-hidden rounded-2xl border border-white/10 bg-black/40">
          <button
            type="button"
            onClick={() => setHistory((open) => !open)}
            className="flex w-full items-center justify-between px-3.5 py-3 text-[9px] font-black uppercase tracking-[.2em] text-slate-400"
          >
            CAÇADAS RECENTES
            <ChevronDown className={`h-4 w-4 transition ${history ? 'rotate-180' : ''}`} />
          </button>
          {history ? (
            <ul className="space-y-1 px-3.5 pb-3">
              {data.history.slice(0, 5).map((row) => (
                <li key={row.id} className="flex items-center justify-between text-[10px] font-bold">
                  <span className="truncate text-slate-400">{row.missionName}</span>
                  <span className={row.victory ? 'text-emerald-300' : 'text-rose-300'}>
                    {row.victory ? 'VITÓRIA' : 'DERROTA'} · {fmt(row.totalDamage)}
                  </span>
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ) : null}

      {picker ? (
        <TeamPicker
          pets={data.pets}
          team={team}
          onToggle={(pet) => setTeam((current) => current.includes(pet.playerPetId)
            ? current.filter((id) => id !== pet.playerPetId)
            : current.length >= 3 ? current : [...current, pet.playerPetId])}
          onClose={() => setPicker(false)}
        />
      ) : null}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-black/50 py-2">
      <p className="text-[8px] font-black uppercase tracking-[.16em] text-slate-500">{label}</p>
      <p className="text-[13px] font-black text-slate-100">{value}</p>
    </div>
  );
}

function TeamPicker({ pets, team, onToggle, onClose }: { pets: FamiliarHuntPet[]; team: string[]; onToggle: (pet: FamiliarHuntPet) => void; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-[90] flex items-end bg-black/80 p-3" onClick={onClose}>
      <div className="mx-auto max-h-[80vh] w-full max-w-[460px] overflow-y-auto rounded-[24px] border border-amber-300/30 bg-[#070b13] p-3.5" onClick={(event) => event.stopPropagation()}>
        <div className="mb-3 flex items-center justify-between">
          <p className="text-[10px] font-black uppercase tracking-[.2em] text-amber-200">EQUIPE · {team.length}/3</p>
          <button type="button" onClick={onClose} className="grid h-7 w-7 place-items-center rounded-full border border-white/15 text-slate-300"><X className="h-3.5 w-3.5" /></button>
        </div>
        <div className="grid grid-cols-3 gap-2">
          {pets.map((pet) => {
            const on = team.includes(pet.playerPetId);
            return (
              <button
                key={pet.playerPetId}
                type="button"
                onClick={() => onToggle(pet)}
                className={`rounded-2xl border p-1.5 text-center transition active:scale-95 ${on ? 'border-amber-300/70 bg-amber-300/10 shadow-[0_0_14px_rgba(251,191,36,.3)]' : 'border-white/10 bg-white/[.03]'}`}
              >
                {pet.image ? <img src={pet.image} alt={pet.name} loading="lazy" className="mx-auto h-16 object-contain" /> : null}
                <p className="truncate text-[9px] font-black text-slate-100">{pet.name}</p>
                <p className="text-[8px] text-slate-500">Nv {pet.level} · {fmt(pet.power)}</p>
              </button>
            );
          })}
        </div>
        <button
          type="button"
          onClick={onClose}
          className="mt-3 w-full rounded-2xl border border-amber-300/50 bg-amber-300/15 py-2.5 text-[11px] font-black uppercase tracking-[.16em] text-amber-100"
        >
          CONFIRMAR
        </button>
      </div>
    </div>
  );
}
