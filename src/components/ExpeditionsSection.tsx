import { useLocalizedText } from '../LanguageContext';
import { useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2, PlayCircle } from 'lucide-react';
import { beginExpeditionAd, beginExpeditionBoostAd, buyExpeditionExtra, claimExpedition, claimExpeditionAd, claimExpeditionBoostAd, fetchExpeditionState, startExpedition } from '../services';
import { showAd } from '../adsgram';
import { useT } from '../LanguageContext';
import { countdown, expeditionChance, type ActiveExpedition, type ExpeditionAttempts, type ExpeditionMission, type ExpeditionPet, type ExpeditionReward } from '../breeding';

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
  BERRIES: 'expeditions.fc',
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
  const localizeText = useLocalizedText();

  const t = useT();
  const client = useQueryClient();
  const [team, setTeam] = useState<string[]>([]);
  const [mission, setMission] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);
  // Extra-attempt modal is ALWAYS bound to one mission: its ads/BERRIES counters are per mission.
  const [extraFor, setExtraFor] = useState<string | null>(null);

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
          ? t('expeditions.successMsg', { rewards: result.rewards.map((reward) => rewardText(reward, t)).join(', ') || t('expeditions.none') })
          : t('expeditions.failMsg', { rewards: result.rewards.map((reward) => rewardText(reward, t)).join(', ') || t('expeditions.none') }),
      });
      refresh();
    },
    onError: (error: Error) => setFeedback({ tone: 'bad', text: error.message }),
  });

  const data = state.data;
  const extraMission = useMemo(() => data?.missions.find((row) => row.id === extraFor) ?? null, [data, extraFor]);
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
              {!row.ready ? <AdBoostCard initData={initData} expedition={row} onChanged={refresh} /> : null}
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
                {pet.isSubNft ? <p className="text-[8px] font-black uppercase text-violet-300">{pet.stage === 'ADULT' ? localizeText("SUB-NFT") : t('expeditions.immature')}</p> : null}
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
            onExtra={() => { setMission(row.id); setExtraFor(row.id); }}
          />
        ))}
      </section>

      <button
        type="button"
        disabled={team.length !== 3 || !selectedMission || start.isPending}
        onClick={() => {
          // A mission with no free attempt and no extra ready opens its OWN extra modal.
          if (selectedMission && !selectedMission.attempts?.canStart) { setExtraFor(selectedMission.id); return; }
          start.mutate();
        }}
        className="w-full rounded-2xl bg-gradient-to-r from-amber-400 to-orange-500 py-3 text-[11px] font-black uppercase tracking-[.2em] text-black disabled:opacity-40"
      >
        {start.isPending ? t('expeditions.sending')
          : selectedMission && !selectedMission.attempts?.canStart ? t('expeditions.extra.getExtra')
          : selectedMission ? t('expeditions.sendWithChance', { chance: expeditionChance(teamPower, selectedMission.requiredPower) })
          : t('expeditions.selectMission')}
      </button>

      {extraMission ? (
        <ExtraAttemptModal
          mission={extraMission}
          initData={initData}
          onClose={() => setExtraFor(null)}
          onChanged={refresh}
        />
      ) : null}
    </div>
  );
}

function MissionCard({ mission, active, teamPower, onSelect, onExtra }: { mission: ExpeditionMission; active: boolean; teamPower: number; onSelect: () => void; onExtra: () => void }) {
  const t = useT();
  const chance = expeditionChance(teamPower, mission.requiredPower);
  const a = mission.attempts;
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
      {active && a ? (
        <div className="mt-2 space-y-1 rounded-xl border border-white/10 bg-black/50 p-2">
          <p className="text-[9px] font-black uppercase tracking-[.18em] text-slate-300">
            {t('expeditions.extra.free')} {a.freeUsed}/{a.freeLimit} · {t('expeditions.extra.ads')} {a.adsUsed}/{a.adsLimit} · {t('expeditions.extra.fc')} {a.fcUsed}/{a.fcLimit}
          </p>
          {a.extraAvailable > 0 ? (
            <p className="text-[9px] font-black uppercase text-emerald-300">{t('expeditions.extra.available', { count: a.extraAvailable })}</p>
          ) : null}
          {a.freeRemaining <= 0 && a.extraAvailable <= 0 ? (
            <span
              role="button"
              tabIndex={0}
              onClick={(event) => { event.stopPropagation(); onExtra(); }}
              onKeyDown={(event) => { if (event.key === 'Enter') { event.stopPropagation(); onExtra(); } }}
              className="block w-full rounded-lg bg-amber-400/20 py-1 text-center text-[9px] font-black uppercase text-amber-200"
            >
              {t('expeditions.extra.getExtra')}
            </span>
          ) : null}
        </div>
      ) : null}
    </button>
  );
}

/** Per-mission extra attempts: 5 ads + 5 BERRIES purchases per game day, independent limits. */
function ExtraAttemptModal({ mission, initData, onClose, onChanged }: {
  mission: ExpeditionMission; initData: string; onClose: () => void; onChanged: () => void;
}) {
  const t = useT();
  const [attempts, setAttempts] = useState<ExpeditionAttempts>(mission.attempts);
  const [phase, setPhase] = useState<'idle' | 'ad-loading' | 'ad-watching' | 'buying'>('idle');
  const [error, setError] = useState<string | null>(null);
  const busy = useRef(false);

  const finish = (next: ExpeditionAttempts | undefined) => {
    if (next) setAttempts(next);
    onChanged();
  };

  const watchAd = async () => {
    if (busy.current || attempts.adsRemaining <= 0) return;
    busy.current = true; setError(null); setPhase('ad-loading');
    try {
      const begin = await beginExpeditionAd(initData, mission.id);
      setPhase('ad-watching');
      const outcome = await showAd(begin.blockId || '');
      if (outcome !== 'completed') {
        setError(outcome === 'no-ads' ? t('expeditions.extra.noAds') : t('expeditions.extra.notCompleted'));
        return;
      }
      const result = await claimExpeditionAd(initData, begin.viewId);
      if (result.granted) finish(result.attempts); else setError(t('expeditions.extra.notCompleted'));
    } catch (err) {
      setError(err instanceof Error ? err.message : t('expeditions.extra.notCompleted'));
    } finally { busy.current = false; setPhase('idle'); }
  };

  const buy = async () => {
    if (busy.current || attempts.fcRemaining <= 0) return;
    busy.current = true; setError(null); setPhase('buying');
    try {
      const key = `exp-extra:${mission.id}:${Date.now()}:${Math.random().toString(36).slice(2, 10)}`;
      const result = await buyExpeditionExtra(initData, mission.id, key);
      finish(result.attempts);
    } catch (err) {
      setError(err instanceof Error ? err.message : t('common.error'));
    } finally { busy.current = false; setPhase('idle'); }
  };

  const bothDone = attempts.adsRemaining <= 0 && attempts.fcRemaining <= 0;

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/80 p-4" role="dialog" aria-modal="true">
      <div className="w-full max-w-xs rounded-3xl border border-amber-300/35 bg-gradient-to-b from-slate-950 to-black p-4 shadow-2xl">
        <p className="text-center text-[10px] font-black uppercase tracking-[.24em] text-amber-200">{t('expeditions.extra.title')}</p>
        <p className="mt-1 text-center text-[13px] font-black text-slate-100">{mission.name}</p>
        <p className="text-center text-[9px] font-black uppercase tracking-[.2em] text-slate-400">{mission.rarity}</p>

        <div className="mt-3 grid grid-cols-2 gap-2">
          <div className="rounded-xl border border-sky-400/25 bg-black/60 p-2 text-center">
            <p className="text-[8px] font-black uppercase tracking-[.18em] text-sky-200">{t('expeditions.extra.ads')}</p>
            <p className="text-[14px] font-black text-slate-100">{attempts.adsUsed} / {attempts.adsLimit}</p>
          </div>
          <div className="rounded-xl border border-amber-300/25 bg-black/60 p-2 text-center">
            <p className="text-[8px] font-black uppercase tracking-[.18em] text-amber-200">{t('expeditions.extra.fc')}</p>
            <p className="text-[14px] font-black text-slate-100">{attempts.fcUsed} / {attempts.fcLimit}</p>
          </div>
        </div>

        {attempts.extraAvailable > 0 ? (
          <p className="mt-2 text-center text-[10px] font-black uppercase text-emerald-300">{t('expeditions.extra.available', { count: attempts.extraAvailable })}</p>
        ) : null}
        {error ? <p className="mt-2 text-center text-[10px] font-bold text-rose-300">{error}</p> : null}
        {bothDone ? <p className="mt-2 text-center text-[10px] font-black uppercase text-rose-300">{t('expeditions.extra.bothLimit')}</p> : null}

        <button
          type="button"
          disabled={attempts.adsRemaining <= 0 || phase !== 'idle'}
          onClick={watchAd}
          className="mt-3 w-full rounded-xl bg-gradient-to-b from-sky-400 to-blue-700 py-3 text-[10px] font-black uppercase text-white disabled:opacity-40"
        >
          {phase === 'ad-loading' ? t('expeditions.extra.loading')
            : phase === 'ad-watching' ? t('expeditions.extra.watching')
            : attempts.adsRemaining <= 0 ? t('expeditions.extra.adLimit') : t('expeditions.extra.watchAd')}
        </button>
        {attempts.adsRemaining > 0 ? <p className="mt-1 text-center text-[9px] text-slate-400">{t('expeditions.extra.adsLeft', { count: attempts.adsRemaining })}</p> : null}

        <button
          type="button"
          disabled={attempts.fcRemaining <= 0 || phase !== 'idle'}
          onClick={buy}
          className="mt-2 w-full rounded-xl bg-gradient-to-r from-amber-400 to-orange-500 py-3 text-[10px] font-black uppercase text-black disabled:opacity-40"
        >
          {phase === 'buying' ? t('expeditions.extra.buying')
            : attempts.fcRemaining <= 0 ? t('expeditions.extra.fcLimit')
            : t('expeditions.extra.payFc', { price: attempts.priceFc.toLocaleString('en-US') })}
        </button>
        {attempts.fcRemaining > 0 ? <p className="mt-1 text-center text-[9px] text-slate-400">{t('expeditions.extra.fcLeft', { count: attempts.fcRemaining })}</p> : null}

        <p className="mt-2 text-center text-[9px] text-slate-500">{t('expeditions.extra.hint')}</p>
        <button type="button" onClick={onClose} className="mt-2 w-full rounded-xl border border-white/15 py-2 text-[10px] font-black uppercase text-slate-300">
          {t('expeditions.extra.cancel')}
        </button>
      </div>
    </div>
  );
}

/**
 * AD BOOST — accelerates ONE active expedition with the rewarded-ad system that already
 * exists in the game (AdsGram). Each validated ad cuts 20% of the CURRENT remaining time,
 * up to 5 ads per expedition; the counter lives on the expedition row, so a new expedition
 * always starts at 0/5. Nothing else about the mission (team, chance, rewards) is touched.
 */
function AdBoostCard({ initData, expedition, onChanged }: { initData: string; expedition: ActiveExpedition; onChanged: () => void }) {
  const t = useT();
  const busy = useRef(false);
  const [phase, setPhase] = useState<'idle' | 'ad-loading' | 'ad-watching'>('idle');
  const [message, setMessage] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);

  const max = expedition.maxAdBoosts ?? 5;
  const used = Math.min(max, expedition.adBoostsUsed ?? 0);
  const maxed = used >= max;
  const working = phase !== 'idle';

  const watch = async () => {
    if (busy.current || maxed) return;
    busy.current = true; setMessage(null); setPhase('ad-loading');
    try {
      const begin = await beginExpeditionBoostAd(initData, expedition.id);
      setPhase('ad-watching');
      const outcome = await showAd(begin.blockId || '');
      if (outcome !== 'completed') {
        setMessage({ tone: 'bad', text: outcome === 'no-ads' ? t('expeditions.extra.noAds') : t('expeditions.boost.failed') });
        return;
      }
      const result = await claimExpeditionBoostAd(initData, begin.viewId);
      if (!result.granted) { setMessage({ tone: 'bad', text: t('expeditions.boost.failed') }); return; }
      setMessage({ tone: 'ok', text: t('expeditions.boost.success') });
      onChanged();
    } catch (err) {
      const raw = err instanceof Error ? err.message : '';
      setMessage({
        tone: 'bad',
        text: raw.includes('BOOST_LIMIT') ? t('expeditions.boost.limit', { max }) : t('expeditions.boost.failed'),
      });
    } finally { busy.current = false; setPhase('idle'); }
  };

  return (
    <div className="mt-2 rounded-2xl border border-sky-400/25 bg-gradient-to-br from-sky-950/50 to-black/60 p-2.5">
      <div className="flex items-center justify-between gap-2">
        <p className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[.2em] text-sky-200">
          <PlayCircle className="h-3.5 w-3.5" /> {t('expeditions.boost.title')}
        </p>
        <span className={`rounded-full border px-2 py-0.5 text-[8px] font-black uppercase tracking-[.14em] ${maxed ? 'border-white/15 bg-white/5 text-slate-400' : 'border-sky-300/40 bg-sky-500/10 text-sky-200'}`}>
          {t('expeditions.boost.used', { used, max })}
        </span>
      </div>
      <p className="mt-1 text-[9px] leading-snug text-slate-400">{t('expeditions.boost.desc')}</p>
      <button
        type="button"
        onClick={watch}
        disabled={maxed || working}
        className={`mt-2 w-full rounded-xl py-2 text-[10px] font-black uppercase tracking-[.14em] disabled:opacity-60 ${maxed ? 'bg-white/5 text-slate-500' : 'bg-gradient-to-b from-sky-300 to-sky-600 text-black'}`}
      >
        {phase === 'ad-loading' ? t('expeditions.boost.loading')
          : phase === 'ad-watching' ? t('expeditions.boost.processing')
          : maxed ? t('expeditions.boost.maxShort', { max })
          : `${t('expeditions.boost.watchAd')} • ${t('expeditions.boost.reduce')}`}
      </button>
      {maxed ? <p className="mt-1 text-center text-[9px] font-black uppercase tracking-[.14em] text-rose-300">{t('expeditions.boost.maxReached')}</p> : null}
      {message ? <p className={`mt-1 text-center text-[9px] font-bold ${message.tone === 'ok' ? 'text-emerald-300' : 'text-rose-300'}`}>{message.text}</p> : null}
    </div>
  );
}
