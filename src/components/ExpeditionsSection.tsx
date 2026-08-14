import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2 } from 'lucide-react';
import { claimExpedition, fetchExpeditionState, startExpedition } from '../services';
import { useT } from '../LanguageContext';
import { countdown, expeditionChance, type ExpeditionMission, type ExpeditionPet, type ExpeditionReward } from '../breeding';

const RARITY_STYLE: Record<string, string> = {
  COMMON: 'border-slate-400/30 text-slate-200',
  UNCOMMON: 'border-emerald-400/30 text-emerald-200',
  RARE: 'border-sky-400/30 text-sky-200',
  EPIC: 'border-fuchsia-400/30 text-fuchsia-200',
  LEGENDARY: 'border-amber-300/40 text-amber-200',
};

const REWARD_KEY: Record<string, string> = {
  PET_FOOD: 'expeditions.petFood',
  FRAGMENT: 'expeditions.fragments',
  MATERIAL: 'expeditions.materials',
  EQUIPMENT: 'expeditions.equipment',
  PVP_TICKET: 'expeditions.pvpTickets',
  FC: 'expeditions.fc',
};

const rewardText = (reward: ExpeditionReward, t: (key: string) => string) => {
  const key = REWARD_KEY[reward.type];
  const name = key ? t(key) : reward.type;
  const range = reward.quantity ? `${reward.quantity}` : reward.min === reward.max ? `${reward.min ?? 1}` : `${reward.min ?? 1}-${reward.max ?? 1}`;
  const chance = reward.chance && reward.chance < 100 ? ` (${reward.chance}%)` : '';
  return `${range}× ${name}${reward.rarity ? ` ${reward.rarity}` : ''}${chance}`;
};

/**
 * 🗺️ PET EXPEDITIONS (AFK MISSIONS). Team of exactly 3 pets; Sub-NFTs only when ADULT.
 * The success roll, timers and rewards are all resolved server-side on claim.
 */
export default function ExpeditionsSection({ initData }: { initData: string }) {
  const t = useT();
  const client = useQueryClient();
  const [team, setTeam] = useState<string[]>([]);
  const [mission, setMission] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);

  const state = useQuery({
    queryKey: ['expeditions'],
    queryFn: () => fetchExpeditionState(initData),
    refetchInterval: 30_000,
  });

  const refresh = () => {
    void client.invalidateQueries({ queryKey: ['expeditions'] });
    void client.invalidateQueries({ queryKey: ['pets'] });
    void client.invalidateQueries({ queryKey: ['player'] });
  };

  const start = useMutation({
    mutationFn: () => startExpedition(initData, String(mission), team),
    onSuccess: (result) => {
      setFeedback({ tone: 'ok', text: `Expedição iniciada! Poder ${result.teamPower} · ${result.successChance}% de sucesso.` });
      setTeam([]); setMission(null); refresh();
    },
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const claim = useMutation({
    mutationFn: (expeditionId: string) => claimExpedition(initData, expeditionId),
    onSuccess: (result) => {
      setFeedback({
        tone: result.success ? 'ok' : 'bad',
        text: result.success
          ? `SUCESSO! Recompensas: ${result.rewards.map(rewardText).join(', ') || 'nenhuma'}`
          : `FALHOU. Recompensa de consolação: ${result.rewards.map(rewardText).join(', ') || 'nenhuma'}`,
      });
      refresh();
    },
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const data = state.data;
  const selectedMission = useMemo(() => data?.missions.find((row) => row.id === mission) ?? null, [data, mission]);
  const teamPower = useMemo(
    () => (data?.pets ?? []).filter((pet) => team.includes(pet.playerPetId)).reduce((sum, pet) => sum + pet.power, 0),
    [data, team],
  );

  const toggle = (pet: ExpeditionPet) => {
    if (!pet.eligible || pet.busy) return;
    setTeam((current) => current.includes(pet.playerPetId)
      ? current.filter((id) => id !== pet.playerPetId)
      : current.length >= 3 ? current : [...current, pet.playerPetId]);
  };

  if (state.isLoading) {
    return <div className="grid h-40 place-items-center"><Loader2 className="h-6 w-6 animate-spin text-amber-300" /></div>;
  }
  if (state.isError) {
    return <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 p-4 text-center text-[11px] text-rose-200">{(state.error as Error).message}</p>;
  }
  if (!data) return null;

  return (
    <div className="space-y-3 pb-6">
      {feedback ? (
        <p className={`rounded-2xl border p-3 text-center text-[11px] font-bold ${feedback.tone === 'ok' ? 'border-emerald-400/30 bg-emerald-950/40 text-emerald-200' : 'border-rose-400/30 bg-rose-950/40 text-rose-200'}`}>
          {feedback.text}
        </p>
      ) : null}

      {data.active.length ? (
        <section className="space-y-2">
          <p className="text-[10px] font-black uppercase tracking-[.26em] text-emerald-200">{t('expeditions.inProgress')}</p>
          {data.active.map((row) => (
            <div key={row.id} className="rounded-2xl border border-emerald-400/20 bg-black/60 p-3">
              <p className="text-[12px] font-black text-slate-100">{row.missionName}</p>
              <p className="mt-1 text-[10px] text-slate-400">{t('expeditions.powerChance', { power: row.teamPower, chance: row.successChance })}</p>
              <p className="mt-1 text-[10px] font-black uppercase text-amber-200">{row.ready ? t('expeditions.readyToClaim') : `${t('expeditions.endsIn')} ${countdown(row.finishesAt)}`}</p>
              <button
                type="button"
                disabled={!row.ready || claim.isPending}
                onClick={() => claim.mutate(row.id)}
                className="mt-2 w-full rounded-xl bg-emerald-500 py-2 text-[10px] font-black uppercase text-black disabled:opacity-40"
              >
                {claim.isPending ? t('expeditions.claiming') : t('expeditions.claimRewards')}
              </button>
            </div>
          ))}
        </section>
      ) : null}

      <section className="rounded-2xl border border-sky-400/20 bg-black/60 p-3">
        <p className="text-[10px] font-black uppercase tracking-[.26em] text-sky-200">{t('expeditions.selectPets')}</p>
        <p className="mt-1 text-[10px] text-slate-400">{t('expeditions.petsHint')}</p>
        <p className="mt-1 text-[10px] text-slate-300">{t('expeditions.team')} <span className="font-black text-amber-200">{team.length}/3</span> · {t('expeditions.totalPower')} <span className="font-black text-amber-200">{teamPower}</span></p>
        <div className="mt-2 grid grid-cols-3 gap-2">
          {data.pets.map((pet) => {
            const active = team.includes(pet.playerPetId);
            const locked = !pet.eligible || pet.busy;
            return (
              <button
                key={pet.playerPetId}
                type="button"
                onClick={() => toggle(pet)}
                className={`rounded-xl border p-2 text-left transition ${active ? 'border-amber-300 bg-amber-400/10' : 'border-white/10 bg-black/50'} ${locked ? 'opacity-40' : ''}`}
              >
                {pet.image ? <img src={pet.image} alt={pet.name} loading="lazy" className="mx-auto h-12 w-12 rounded-lg object-cover" /> : null}
                <p className="mt-1 truncate text-[10px] font-black text-slate-100">{pet.name}</p>
                <p className="text-[9px] text-slate-400">{t('expeditions.levelShort')} {pet.level} · {pet.power}</p>
                {pet.isSubNft ? <p className="text-[8px] font-black uppercase text-violet-300">{pet.stage === 'ADULT' ? 'SUB-NFT' : t('expeditions.immature')}</p> : null}
                {pet.busy ? <p className="text-[8px] font-black uppercase text-rose-300">{t('expeditions.onExpedition')}</p> : null}
              </button>
            );
          })}
        </div>
      </section>

      <section className="space-y-2">
        <p className="text-[10px] font-black uppercase tracking-[.26em] text-slate-300">{t('expeditions.missions')}</p>
        {data.missions.map((row) => (
          <MissionCard
            key={row.id}
            mission={row}
            active={mission === row.id}
            teamPower={teamPower}
            onSelect={() => setMission(row.id)}
          />
        ))}
      </section>

      <button
        type="button"
        disabled={team.length !== 3 || !selectedMission || start.isPending}
        onClick={() => start.mutate()}
        className="w-full rounded-2xl bg-gradient-to-r from-amber-400 to-orange-500 py-3 text-[11px] font-black uppercase tracking-[.2em] text-black disabled:opacity-40"
      >
        {start.isPending ? t('expeditions.sending') : selectedMission ? t('expeditions.sendWithChance', { chance: expeditionChance(teamPower, selectedMission.requiredPower) }) : t('expeditions.selectMission')}
      </button>
    </div>
  );
}

function MissionCard({ mission, active, teamPower, onSelect }: { mission: ExpeditionMission; active: boolean; teamPower: number; onSelect: () => void }) {
  const t = useT();
  const chance = expeditionChance(teamPower, mission.requiredPower);
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`w-full rounded-2xl border bg-black/60 p-3 text-left transition ${active ? 'border-amber-300' : RARITY_STYLE[mission.rarity] ?? 'border-white/10'}`}
    >
      <div className="flex items-center justify-between gap-2">
        <p className="text-[12px] font-black text-slate-100">{mission.name}</p>
        <span className={`rounded-full border px-2 py-0.5 text-[8px] font-black uppercase ${RARITY_STYLE[mission.rarity] ?? ''}`}>{mission.rarity}</span>
      </div>
      <p className="mt-1 text-[10px] text-slate-400">
        {mission.durationHours}h · {t('expeditions.recommendedPower')} {mission.requiredPower}{mission.element ? ` · ${t('expeditions.element')} ${mission.element}` : ''}
      </p>
      <p className="mt-1 text-[10px] text-slate-300">{t('expeditions.rewards')} {mission.rewards.map((reward) => rewardText(reward, t)).join(', ')}</p>
      {teamPower > 0 ? <p className="mt-1 text-[10px] font-black uppercase text-amber-200">{t('expeditions.estimatedChance')} {chance}%</p> : null}
    </button>
  );
}
