import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2, Shield, Swords, Trophy, Users, X, Zap } from 'lucide-react';
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
  pet_food: 'Ração de pet',
  universal_fragment: 'Fragmentos universais',
  fc: 'FC',
  pvp_ticket: 'Tickets PvP',
  equipment: 'Equipamento',
};

const fmt = (value: number) => Math.round(value).toLocaleString('pt-BR');

const rewardLine = (reward: FamiliarHuntReward) => {
  const label = REWARD_LABEL[reward.type] ?? reward.type;
  const range = reward.quantity != null ? fmt(reward.quantity)
    : reward.min === reward.max ? fmt(reward.min ?? 1) : `${fmt(reward.min ?? 1)}-${fmt(reward.max ?? 1)}`;
  const chance = reward.chance != null && reward.chance < 100 ? ` (${reward.chance}%)` : '';
  const rarity = reward.rarity ? ` ${String(reward.rarity).toUpperCase()}` : '';
  return `${range}× ${label}${rarity}${chance}`;
};

/**
 * 🐾⚔️ FAMILIAR HUNT — new pet COMBAT mode: 3 pets fight monsters on a battlefield.
 * Entirely separate from the classic AFK Expeditions (that system is untouched):
 * the server resolves the whole fight and this screen plays it back.
 */
export default function FamiliarHuntSection({ initData }: { initData: string }) {
  const client = useQueryClient();
  const [missionId, setMissionId] = useState<string | null>(null);
  const [team, setTeam] = useState<string[]>([]);
  const [picker, setPicker] = useState(false);
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

  const hunt = useMutation({
    mutationFn: () => startFamiliarHunt(initData, String(mission?.id), team, crypto.randomUUID()),
    onSuccess: (payload) => {
      setResult(payload);
      setStage('battle');
      setFeedback(null);
      void client.invalidateQueries({ queryKey: ['familiar-hunt'] });
      ['pet-dashboard', 'player-inventory', 'game-state', 'pvp-dashboard'].forEach((key) =>
        void client.invalidateQueries({ queryKey: [key] }));
    },
    onError: (error: Error) => setFeedback(error.message),
  });

  if (state.isLoading) return <div className="grid h-40 place-items-center"><Loader2 className="h-6 w-6 animate-spin text-amber-300" /></div>;
  if (state.isError) return <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 p-4 text-center text-[11px] text-rose-200">{(state.error as Error).message}</p>;
  if (!data || !mission) return null;

  if (stage === 'battle' && result) {
    return <FamiliarHuntBattle result={result} onFinished={() => setStage('result')} />;
  }

  if (stage === 'result' && result) {
    return (
      <div className="space-y-3 pb-6">
        <div className={`relative overflow-hidden rounded-[26px] border p-5 text-center ${result.victory ? 'border-amber-300/50 bg-gradient-to-b from-amber-500/15 to-black/80' : 'border-rose-400/40 bg-gradient-to-b from-rose-900/30 to-black/80'}`}>
          <div className="pointer-events-none absolute -top-20 left-1/2 h-40 w-56 -translate-x-1/2 rounded-full bg-amber-300/20 blur-3xl" />
          <p className="relative text-[10px] font-black uppercase tracking-[.3em] text-slate-300">{mission.name}</p>
          <h3 className={`relative mt-1 text-3xl font-black uppercase tracking-[.08em] ${result.victory ? 'text-amber-200 drop-shadow-[0_0_18px_rgba(251,191,36,.6)]' : 'text-rose-300'}`}>
            {result.victory ? 'VITÓRIA' : 'DERROTA'}
          </h3>
          <div className="relative mt-4 grid grid-cols-3 gap-2 text-center">
            <Stat label="DANO TOTAL" value={fmt(result.totalDamage)} />
            <Stat label="RODADAS" value={String(result.rounds)} />
            <Stat label="PODER" value={fmt(result.teamPower)} />
          </div>
          <div className="relative mt-4 rounded-2xl border border-white/10 bg-black/50 p-3 text-left">
            <p className="text-[9px] font-black uppercase tracking-[.24em] text-amber-200">RECOMPENSAS</p>
            {result.rewards.length ? (
              <ul className="mt-2 space-y-1">
                {result.rewards.map((reward, index) => (
                  <li key={`${reward.type}-${index}`} className="flex items-center gap-2 text-[11px] font-bold text-slate-200">
                    <Trophy className="h-3.5 w-3.5 text-amber-300" /> {rewardLine(reward)}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="mt-2 text-[11px] text-slate-400">Nenhuma recompensa nesta caçada.</p>
            )}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <button
            type="button"
            disabled={hunt.isPending || runsLeft <= 0}
            onClick={() => hunt.mutate()}
            className="rounded-2xl border border-amber-300/60 bg-amber-300/15 py-3 text-[11px] font-black uppercase tracking-[.16em] text-amber-100 transition active:scale-95 disabled:opacity-40"
          >
            {hunt.isPending ? 'CAÇANDO...' : 'CAÇAR NOVAMENTE'}
          </button>
          <button
            type="button"
            onClick={() => { setStage('lobby'); setResult(null); }}
            className="rounded-2xl border border-white/15 bg-white/[.04] py-3 text-[11px] font-black uppercase tracking-[.16em] text-slate-200 transition active:scale-95"
          >
            VOLTAR
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3 pb-6">
      <header className="text-center">
        <h2 className="text-xl font-black uppercase tracking-[.14em] text-amber-200 drop-shadow-[0_0_16px_rgba(251,191,36,.5)]">FAMILIAR HUNT</h2>
        <p className="mt-0.5 text-[10px] text-slate-400">Envie 3 familiares para caçar monstros em combate real.</p>
      </header>

      {feedback ? (
        <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 p-3 text-center text-[11px] font-bold text-rose-200">{feedback}</p>
      ) : null}

      {/* mission selector */}
      <div className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
        {data.missions.map((row) => {
          const on = row.id === mission.id;
          return (
            <button
              key={row.id}
              type="button"
              onClick={() => { setMissionId(row.id); setFeedback(null); }}
              className={`shrink-0 rounded-full border px-3 py-1.5 text-[9px] font-black uppercase tracking-[.12em] transition active:scale-95 ${
                on ? 'border-amber-300/70 bg-amber-300/15 text-amber-200 shadow-[0_0_14px_rgba(251,191,36,.35)]' : `${RARITY_TONE[row.rarity] ?? 'border-white/15 text-slate-300'} bg-white/[.03]`
              }`}
            >
              {row.name}
            </button>
          );
        })}
      </div>

      {/* battle preview scene */}
      <section
        className="relative overflow-hidden rounded-[26px] border border-amber-300/25 shadow-[0_0_50px_-14px_rgba(251,191,36,.35)]"
        style={{ backgroundImage: `url(${mission.background || ARENA})`, backgroundSize: 'cover', backgroundPosition: 'center' }}
      >
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_10%,rgba(56,189,248,.16),rgba(2,6,16,.92)_72%)]" />
        <div className="relative p-3">
          <div className="flex items-center justify-between">
            <span className={`rounded-full border bg-black/60 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.18em] ${RARITY_TONE[mission.rarity] ?? 'border-white/20 text-slate-200'}`}>
              {mission.rarity}
            </span>
            <span className="rounded-full border border-amber-300/40 bg-black/60 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.16em] text-amber-200">
              CAÇADAS HOJE {mission.runsToday}/{mission.maxRunsPerDay}
            </span>
          </div>

          {/* enemies */}
          <div className="mt-2 flex items-end justify-center gap-2">
            {mission.enemies?.map((enemy, index) => (
              <div key={`${enemy.name}-${index}`} className="flex-1">
                {enemy.image ? (
                  <img src={enemy.image} alt={enemy.name} loading="lazy" className={`mx-auto object-contain drop-shadow-[0_0_18px_rgba(244,63,94,.45)] ${enemy.elite ? 'h-28' : 'h-20'}`} />
                ) : null}
                <p className="truncate text-center text-[8px] font-black uppercase tracking-[.08em] text-rose-200">{enemy.name}</p>
                <p className="text-center text-[8px] text-slate-400">{fmt(enemy.hp)} HP · {fmt(enemy.atk)} ATK</p>
              </div>
            ))}
          </div>

          <div className="mx-auto my-3 h-px w-3/4 bg-gradient-to-r from-transparent via-amber-300/40 to-transparent shadow-[0_0_16px_rgba(251,191,36,.6)]" />

          {/* team slots as battle units */}
          <div className="flex items-end justify-center gap-2">
            {[0, 1, 2].map((slot) => {
              const pet = selected[slot];
              return (
                <button
                  key={slot}
                  type="button"
                  onClick={() => setPicker(true)}
                  className="group relative flex-1"
                >
                  {pet ? (
                    <>
                      {pet.image ? <img src={pet.image} alt={pet.name} loading="lazy" className="mx-auto h-24 object-contain drop-shadow-[0_0_18px_rgba(56,189,248,.5)]" /> : null}
                      <p className="truncate text-center text-[8px] font-black uppercase tracking-[.08em] text-sky-200">{pet.name}</p>
                      <p className="text-center text-[8px] text-slate-400">Nv {pet.level} · {fmt(pet.power)}</p>
                    </>
                  ) : (
                    <div className="mx-auto grid h-24 place-items-center rounded-2xl border border-dashed border-sky-300/30 bg-black/40 text-sky-300/60 transition group-hover:border-sky-300/60">
                      <Users className="h-6 w-6" />
                    </div>
                  )}
                </button>
              );
            })}
          </div>

          <div className="mt-3 grid grid-cols-2 gap-2">
            <div className="rounded-2xl border border-sky-300/25 bg-black/55 p-2 text-center">
              <p className="text-[8px] font-black uppercase tracking-[.2em] text-sky-300">PODER DA EQUIPE</p>
              <p className={`text-[15px] font-black ${teamPower >= mission.recommendedPower ? 'text-emerald-300' : 'text-amber-200'}`}>{fmt(teamPower)}</p>
            </div>
            <div className="rounded-2xl border border-amber-300/25 bg-black/55 p-2 text-center">
              <p className="text-[8px] font-black uppercase tracking-[.2em] text-amber-300">RECOMENDADO</p>
              <p className="text-[15px] font-black text-slate-100">{fmt(mission.recommendedPower)}</p>
            </div>
          </div>
        </div>
      </section>

      {mission.description ? <p className="text-center text-[10px] italic text-slate-400">{mission.description}</p> : null}

      <section className="rounded-2xl border border-white/10 bg-black/50 p-3">
        <p className="text-[9px] font-black uppercase tracking-[.24em] text-amber-200">RECOMPENSAS POSSÍVEIS</p>
        <ul className="mt-2 grid gap-1">
          {(mission.rewards ?? []).map((reward, index) => (
            <li key={`${reward.type}-${index}`} className="flex items-center gap-2 text-[11px] font-bold text-slate-200">
              <Zap className="h-3.5 w-3.5 text-amber-300" /> {rewardLine(reward)}
            </li>
          ))}
        </ul>
      </section>

      <div className="grid grid-cols-2 gap-2">
        <button
          type="button"
          onClick={() => setPicker(true)}
          className="flex items-center justify-center gap-1.5 rounded-2xl border border-sky-300/45 bg-sky-300/10 py-3 text-[11px] font-black uppercase tracking-[.14em] text-sky-200 transition active:scale-95"
        >
          <Shield className="h-4 w-4" /> SELECIONAR EQUIPE
        </button>
        <button
          type="button"
          disabled={!ready || hunt.isPending || runsLeft <= 0}
          onClick={() => hunt.mutate()}
          className="flex items-center justify-center gap-1.5 rounded-2xl border border-amber-300/60 bg-amber-300/15 py-3 text-[11px] font-black uppercase tracking-[.14em] text-amber-100 transition active:scale-95 disabled:opacity-40"
        >
          <Swords className="h-4 w-4" /> {hunt.isPending ? 'CAÇANDO...' : runsLeft <= 0 ? 'LIMITE DIÁRIO' : 'INICIAR CAÇADA'}
        </button>
      </div>

      {data.history.length ? (
        <section className="rounded-2xl border border-white/10 bg-black/40 p-3">
          <p className="text-[9px] font-black uppercase tracking-[.24em] text-slate-400">HISTÓRICO</p>
          <ul className="mt-2 space-y-1">
            {data.history.slice(0, 5).map((row) => (
              <li key={row.id} className="flex items-center justify-between text-[10px] font-bold">
                <span className="truncate text-slate-300">{row.missionName}</span>
                <span className={row.victory ? 'text-emerald-300' : 'text-rose-300'}>{row.victory ? 'VITÓRIA' : 'DERROTA'} · {fmt(row.totalDamage)}</span>
              </li>
            ))}
          </ul>
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
    <div className="rounded-xl border border-white/10 bg-black/50 p-2">
      <p className="text-[8px] font-black uppercase tracking-[.16em] text-slate-400">{label}</p>
      <p className="text-[13px] font-black text-slate-100">{value}</p>
    </div>
  );
}

function TeamPicker({ pets, team, onToggle, onClose }: { pets: FamiliarHuntPet[]; team: string[]; onToggle: (pet: FamiliarHuntPet) => void; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-[90] flex items-end bg-black/80 p-3" onClick={onClose}>
      <div className="mx-auto max-h-[80vh] w-full max-w-[460px] overflow-y-auto rounded-[24px] border border-amber-300/30 bg-[#070b13] p-3" onClick={(event) => event.stopPropagation()}>
        <div className="mb-2 flex items-center justify-between">
          <p className="text-[10px] font-black uppercase tracking-[.2em] text-amber-200">EQUIPE DE CAÇA · {team.length}/3</p>
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
                <p className="text-[8px] text-slate-400">Nv {pet.level} · {fmt(pet.power)}</p>
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
