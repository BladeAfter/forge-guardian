import { useLocalizedText } from '../LanguageContext';
import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTonConnectUI } from '@tonconnect/ui-react';
import { Crown, History, Loader2, Percent, Sparkles, Swords, Trophy, Users, Wallet, X } from 'lucide-react';
import {
  fetchFamiliarHuntState, isFamiliarHuntPayment, startFamiliarHunt, verifyFamiliarHuntPayments,
  type FamiliarHuntLootTier, type FamiliarHuntPet, type FamiliarHuntResult, type FamiliarHuntReward,
} from '../services';
import { sendTonPayment } from '../tonPayment';
import { FamiliarHuntBattle } from './FamiliarHuntBattle';

const ARENA = '/assets/game/familiar-hunt/hunt-arena.jpg';

const REWARD_LABEL: Record<string, string> = {
  pet_food: 'Ração',
  universal_fragment: 'Fragmentos Universais',
  fc: 'FC',
  pvp_ticket: 'Tickets PvP',
  equipment: 'Equipamento',
  chest: 'Baú',
};

const CHEST_LABEL: Record<string, string> = {
  rare_chest: 'Baú Raro',
  epic_chest: 'Baú Épico',
  legendary_chest: 'Baú Lendário',
};

const fmt = (value: number) => Math.round(value).toLocaleString('pt-BR');
const fmtTon = (value: number) => (Number.isInteger(value) ? String(value) : value.toFixed(2));

const rewardLine = (reward: FamiliarHuntReward) => {
  if (reward.type === 'chest') return `${fmt(reward.quantity)}× ${CHEST_LABEL[reward.code] ?? 'Baú'}`;
  if (reward.type === 'equipment') return `${reward.code || 'Equipamento'} · ${String(reward.rarity ?? '').toUpperCase()}`;
  return `${fmt(reward.quantity)} ${REWARD_LABEL[reward.type] ?? reward.type}`;
};

type LootLine = { type: string; code?: string; rarity?: string; min?: number; max?: number };

/** Tolerant: an option may come as a list of lines OR as a single line object. */
const lootOptionLine = (option: LootLine | LootLine[] | null | undefined) =>
  (Array.isArray(option) ? option : option ? [option] : [])
    .map((line) => {
      const range = line.min === line.max || line.max == null ? fmt(line.min ?? 1) : `${fmt(line.min ?? 1)}–${fmt(line.max)}`;
      if (line.type === 'chest') return CHEST_LABEL[line.code ?? ''] ?? 'Baú';
      if (line.type === 'equipment') return `Equipamento ${String(line.rarity ?? '').toUpperCase()}`;
      return `${range} ${REWARD_LABEL[line.type] ?? line.type}`;
    })
    .join(' + ');


/**
 * 🐾⚔️ FAMILIAR HUNT — LINEAR progression. ONE clean screen: the CURRENT stage only.
 * Winning unlocks exactly the next stage; losing keeps the player on the same one.
 * Entry is 100.000 BERRIES (item-only loot) or 5 TON (premium loot). Internal TON is used
 * only when it covers the entry in full — otherwise TonConnect charges the FULL amount.
 * Stage, payment, fight and loot are all decided server-side.
 */
export default function FamiliarHuntSection({ initData, onWallet }: { initData: string; onWallet?: () => void }) {
  const localizeText = useLocalizedText();

  const client = useQueryClient();
  const [tonUI] = useTonConnectUI();
  const [team, setTeam] = useState<string[]>([]);
  const [picker, setPicker] = useState(false);
  const [drops, setDrops] = useState(false);
  const [history, setHistory] = useState(false);
  const [phase, setPhase] = useState<'lobby' | 'battle' | 'result'>('lobby');
  const [result, setResult] = useState<FamiliarHuntResult | null>(null);
  const [feedback, setFeedback] = useState<string | null>(null);
  const [waitingChain, setWaitingChain] = useState(false);

  const state = useQuery({ queryKey: ['familiar-hunt'], queryFn: () => fetchFamiliarHuntState(initData) });
  const data = state.data;

  const pets = data?.pets ?? [];
  const selected = useMemo(() => pets.filter((pet) => team.includes(pet.playerPetId)), [pets, team]);
  const teamPower = selected.reduce((sum, pet) => sum + pet.power, 0);

  // auto-fill the 3 strongest familiars so the screen is ready to fight
  useEffect(() => {
    if (team.length || !pets.length) return;
    setTeam(pets.slice(0, 3).map((pet) => pet.playerPetId));
  }, [pets, team.length]);

  const refreshAll = () => {
    void client.invalidateQueries({ queryKey: ['familiar-hunt'] });
    ['pet-dashboard', 'player-inventory', 'game-state', 'pvp-dashboard', 'wallet-summary'].forEach((key) =>
      void client.invalidateQueries({ queryKey: [key] }));
  };

  const settle = (payload: FamiliarHuntResult) => {
    setResult(payload);
    setPhase('battle');
    setFeedback(null);
    refreshAll();
  };

  /** Polls the backend until the external TON transfer is confirmed on-chain. */
  const awaitOnChain = async () => {
    setWaitingChain(true);
    try {
      for (let attempt = 0; attempt < 20; attempt += 1) {
        await new Promise((resolve) => window.setTimeout(resolve, 6000));
        const payload = await verifyFamiliarHuntPayments(initData).catch(() => null);
        const settled = payload?.settled?.[0];
        if (settled) { settle(settled); return; }
      }
      setFeedback('Pagamento enviado. A caçada abre automaticamente assim que a transação for confirmada.');
    } finally {
      setWaitingChain(false);
    }
  };

  const hunt = useMutation({
    mutationFn: async (currency: 'fc' | 'ton') => {
      const payload = await startFamiliarHunt(initData, team, crypto.randomUUID(), currency);
      if (!isFamiliarHuntPayment(payload)) return payload;
      // internal TON did not cover the entry: the wallet pays the FULL amount, never a mix
      await sendTonPayment(payload, (tx) => tonUI.sendTransaction(tx));
      await awaitOnChain();
      return null;
    },
    onSuccess: (payload) => { if (payload) settle(payload); },
    onError: (error: Error) => setFeedback(error.message),
  });

  const launch = (currency: 'fc' | 'ton') => {
    if (team.length !== 3) { setFeedback('Selecione 3 familiares para caçar.'); return; }
    if (currency === 'fc' && (data?.balances.fc ?? 0) < (data?.entry.fc ?? 0)) {
      setFeedback('BERRIES insuficiente para a entrada padrão.'); return;
    }
    setFeedback(null);
    hunt.mutate(currency);
  };

  if (state.isLoading) return <div className="grid h-40 place-items-center"><Loader2 className="h-6 w-6 animate-spin text-amber-300" /></div>;
  if (state.isError) return <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 p-4 text-center text-[11px] text-rose-200">{(state.error as Error).message}</p>;
  if (!data) return null;

  const stage = data.stage;
  const busy = hunt.isPending || waitingChain;

  if (phase === 'battle' && result) {
    return (
      <FamiliarHuntBattle
        result={result}
        missionName={`STAGE ${result.stage} · ${result.stageName ?? ''}`}
        onFinished={() => setPhase('result')}
        onExit={() => setPhase('result')}
      />
    );
  }

  if (phase === 'result' && result) {
    return (
      <div className="fixed inset-0 z-[140] flex flex-col justify-center gap-4 overflow-y-auto bg-[#03060d]/98 px-4 py-[max(env(safe-area-inset-top),1.25rem)] backdrop-blur-sm">
        <div className={`relative overflow-hidden rounded-[26px] border p-6 text-center ${result.victory ? 'border-amber-300/50 bg-gradient-to-b from-amber-500/15 to-black/80' : 'border-rose-400/40 bg-gradient-to-b from-rose-900/30 to-black/80'}`}>
          <p className="text-[9px] font-black uppercase tracking-[.3em] text-slate-400">{localizeText("STAGE")}{result.stage} · {result.stageName}</p>
          <h3 className={`mt-1 text-3xl font-black uppercase tracking-[.08em] ${result.victory ? 'text-amber-200' : 'text-rose-300'}`}>
            {result.victory ? localizeText("VITÓRIA") : localizeText("DERROTA")}
          </h3>
          {result.lootTier ? <p className="mt-1 text-[10px] font-black uppercase tracking-[.2em] text-amber-300/90">{localizeText("LOOT ·")}{result.lootTier}</p> : null}
          <div className="mt-5 grid grid-cols-3 gap-2">
            <Stat label="DANO" value={fmt(result.totalDamage)} />
            <Stat label="RODADAS" value={String(result.rounds)} />
            <Stat label="PODER" value={fmt(result.teamPower)} />
          </div>
          {result.rewards.length ? (
            <ul className="mt-5 space-y-1.5 text-left">
              {result.rewards.map((reward, index) => (
                <li key={`${reward.type}-${index}`} className="flex items-center gap-2 text-[11px] font-bold text-slate-200">
                  <Trophy className="h-3.5 w-3.5 shrink-0 text-amber-300" /> {rewardLine(reward)}
                </li>
              ))}
            </ul>
          ) : (
            <p className="mt-5 text-[11px] text-slate-400">
              {result.victory ? localizeText("Nenhuma recompensa nesta caçada.") : localizeText("Derrota: você permanece nesta fase. Tente novamente.")}
            </p>
          )}
          {result.victory ? (
            <p className="mt-4 text-[10px] font-black uppercase tracking-[.18em] text-emerald-300">{localizeText("STAGE")}{result.stage + 1} {localizeText("LIBERADO")}</p>
          ) : null}
        </div>
        <button
          type="button"
          onClick={() => { setPhase('lobby'); setResult(null); refreshAll(); }}
          className="w-full rounded-2xl border border-white/15 bg-white/[.04] py-3.5 text-[11px] font-black uppercase tracking-[.18em] text-slate-200 transition active:scale-95"
        >
          {localizeText("VOLTAR À CAÇADA")}</button>
      </div>
    );
  }

  return (
    <div className="space-y-3.5 pb-6">
      {/* ── header: only the current stage ───────────────── */}
      <header className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-black uppercase tracking-[.16em] text-amber-200 drop-shadow-[0_0_16px_rgba(251,191,36,.45)]">{localizeText("FAMILIAR HUNT")}</h2>
          <p className="text-[10px] font-bold tracking-wide text-slate-500">
            {localizeText("STAGE")}{stage.stage} {localizeText(" · recorde")}{data.progress.highestStageCompleted}
          </p>
        </div>
        <button
          type="button"
          onClick={() => setHistory(true)}
          className="flex items-center gap-1.5 rounded-full border border-white/12 bg-white/[.03] px-3 py-1.5 text-[9px] font-black uppercase tracking-[.14em] text-slate-300"
        >
          <History className="h-3 w-3" /> {localizeText("HISTORY")}</button>
      </header>

      {!data.enabled ? (
        <p className="rounded-2xl border border-amber-300/30 bg-amber-500/10 px-3 py-2.5 text-center text-[11px] font-bold text-amber-200">
          {localizeText(" A Familiar Hunt está temporariamente desativada.")}</p>
      ) : null}

      {feedback ? (
        <p className="rounded-2xl border border-rose-400/30 bg-rose-950/40 px-3 py-2.5 text-center text-[11px] font-bold text-rose-200">{feedback}</p>
      ) : null}

      {/* ── stage card ───────────────────────────────────── */}
      <section
        className="relative overflow-hidden rounded-[28px] border border-amber-300/20 shadow-[0_0_60px_-18px_rgba(251,191,36,.35)]"
        style={{ backgroundImage: `url(${stage.background || ARENA})`, backgroundSize: 'cover', backgroundPosition: 'center' }}
      >
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_8%,rgba(56,189,248,.14),rgba(2,6,16,.94)_70%)]" />
        <div className="relative px-4 pb-4 pt-3.5">
          <div className="flex items-center justify-center gap-2">
            <span className="rounded-full border border-amber-300/50 bg-black/60 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.18em] text-amber-200">
              {localizeText("STAGE")}{stage.stage}
            </span>
            {stage.isBoss ? (
              <span className="flex items-center gap-1 rounded-full border border-fuchsia-300/50 bg-black/60 px-2.5 py-1 text-[8px] font-black uppercase tracking-[.16em] text-fuchsia-200">
                <Crown className="h-3 w-3" /> {localizeText("BOSS")}</span>
            ) : null}
          </div>
          <p className="mt-1.5 text-center text-[13px] font-black uppercase tracking-[.1em] text-rose-100">{stage.name}</p>

          {/* enemy art */}
          <div className="mt-2 flex items-end justify-center gap-3">
            {stage.enemies.map((enemy, index) => (
              <div key={`${enemy.name}-${index}`} className="flex-1">
                {enemy.image ? (
                  <img src={enemy.image} alt={enemy.name} loading="lazy" className={`mx-auto object-contain drop-shadow-[0_0_18px_rgba(244,63,94,.45)] ${enemy.elite ? 'h-24' : 'h-16'}`} />
                ) : null}
              </div>
            ))}
          </div>

          <div className="mx-auto my-3.5 h-px w-2/3 bg-gradient-to-r from-transparent via-amber-300/40 to-transparent" />

          {/* the player's 3 familiars */}
          <div className="flex items-end justify-center gap-3">
            {[0, 1, 2].map((slot) => {
              const pet = selected[slot];
              return (
                <button key={slot} type="button" onClick={() => setPicker(true)} className="group relative flex-1">
                  {pet ? (
                    <>
                      {pet.image ? <img src={pet.image} alt={pet.name} loading="lazy" className="mx-auto h-24 object-contain drop-shadow-[0_0_22px_rgba(56,189,248,.5)]" /> : null}
                      <p className="truncate text-center text-[9px] font-black uppercase tracking-[.06em] text-sky-200">{pet.name}</p>
                    </>
                  ) : (
                    <div className="mx-auto grid h-24 place-items-center rounded-2xl border border-dashed border-sky-300/25 bg-black/40 text-sky-300/50">
                      <Users className="h-6 w-6" />
                    </div>
                  )}
                </button>
              );
            })}
          </div>

          <div className="mt-4 grid grid-cols-2 gap-2.5">
            <div className="rounded-2xl border border-sky-300/20 bg-black/60 py-2.5 text-center">
              <p className="text-[8px] font-black uppercase tracking-[.2em] text-sky-400/80">{localizeText("SUA EQUIPE")}</p>
              <p className={`text-[16px] font-black ${teamPower >= stage.recommendedPower ? 'text-emerald-300' : 'text-amber-200'}`}>{fmt(teamPower)}</p>
            </div>
            <div className="rounded-2xl border border-amber-300/20 bg-black/60 py-2.5 text-center">
              <p className="text-[8px] font-black uppercase tracking-[.2em] text-amber-400/80">{localizeText("RECOMENDADO")}</p>
              <p className="text-[16px] font-black text-slate-100">{fmt(stage.recommendedPower)}</p>
            </div>
          </div>
        </div>
      </section>

      {/* ── entry ────────────────────────────────────────── */}
      <section className="space-y-2">
        <div className="flex items-center justify-between">
          <p className="text-[9px] font-black uppercase tracking-[.24em] text-slate-400">{localizeText("ENTRADA")}</p>
          <p className="text-[9px] font-bold text-slate-500">{fmt(data.balances.fc)} {localizeText("BERRIES ·")}{fmtTon(data.balances.ton)} TON</p>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <button
            type="button"
            disabled={busy || !data.enabled}
            onClick={() => launch('fc')}
            className="rounded-2xl border border-amber-300/55 bg-amber-300/12 px-2 py-3 text-center transition active:scale-95 disabled:opacity-50"
          >
            <span className="flex items-center justify-center gap-1.5 text-[10px] font-black uppercase tracking-[.1em] text-amber-100">
              <Swords className="h-3.5 w-3.5" /> {fmt(data.entry.fc)} BERRIES
            </span>
            <span className="mt-0.5 block text-[8px] font-bold uppercase tracking-[.14em] text-amber-300/70">STANDARD · SÓ ITENS</span>
          </button>
          <button
            type="button"
            disabled={busy || !data.enabled}
            onClick={() => launch('ton')}
            className="rounded-2xl border border-sky-300/55 bg-sky-300/12 px-2 py-3 text-center transition active:scale-95 disabled:opacity-50"
          >
            <span className="flex items-center justify-center gap-1.5 text-[10px] font-black uppercase tracking-[.1em] text-sky-100">
              <Sparkles className="h-3.5 w-3.5" /> {fmtTon(data.entry.ton)} TON
            </span>
            <span className="mt-0.5 block text-[8px] font-bold uppercase tracking-[.14em] text-sky-300/70">{localizeText("PREMIUM · BERRIES + ÉPICO")}</span>
          </button>
        </div>
        {busy ? (
          <p className="flex items-center justify-center gap-2 text-[10px] font-bold text-slate-400">
            <Loader2 className="h-3.5 w-3.5 animate-spin" /> {waitingChain ? localizeText("Confirmando pagamento na blockchain...") : localizeText("Preparando a caçada...")}
          </p>
        ) : null}
        {data.balances.ton < data.entry.ton ? (
          <button
            type="button"
            onClick={() => onWallet?.()}
            className="flex w-full items-center justify-center gap-1.5 rounded-xl border border-white/10 bg-white/[.02] py-2 text-[9px] font-black uppercase tracking-[.14em] text-slate-400"
          >
            <Wallet className="h-3 w-3" /> {localizeText("DEPOSITAR TON INTERNO")}</button>
        ) : null}
      </section>

      {/* ── possible rewards (compact) ───────────────────── */}
      <section className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/50 px-3.5 py-3">
        <div>
          <p className="text-[9px] font-black uppercase tracking-[.2em] text-slate-400">{localizeText("RECOMPENSAS POSSÍVEIS")}</p>
          <p className="mt-0.5 text-[10px] font-bold text-slate-300">
            <span className="text-sky-300">{localizeText("Rare")}</span> · <span className="text-fuchsia-300">{localizeText("Epic")}</span> · <span className="text-amber-300">{localizeText("Legendary")}</span>
          </p>
        </div>
        <button
          type="button"
          onClick={() => setDrops(true)}
          className="flex items-center gap-1.5 rounded-full border border-amber-300/40 bg-amber-300/10 px-3 py-1.5 text-[9px] font-black uppercase tracking-[.12em] text-amber-200"
        >
          <Percent className="h-3 w-3" /> {localizeText("VER DROPS")}</button>
      </section>

      <button
        type="button"
        onClick={() => setPicker(true)}
        className="w-full rounded-2xl border border-sky-300/30 bg-sky-300/[.05] py-2.5 text-[10px] font-black uppercase tracking-[.16em] text-sky-200 transition active:scale-95"
      >
        {localizeText("EQUIPE")}{team.length}/3
      </button>

      {picker ? (
        <TeamPicker
          pets={pets}
          team={team}
          onToggle={(pet) => setTeam((current) => current.includes(pet.playerPetId)
            ? current.filter((id) => id !== pet.playerPetId)
            : current.length >= 3 ? current : [...current, pet.playerPetId])}
          onClose={() => setPicker(false)}
        />
      ) : null}

      {drops ? <DropRatesModal fc={data.dropRates.fc} ton={data.dropRates.ton} entryFc={data.entry.fc} entryTon={data.entry.ton} onClose={() => setDrops(false)} /> : null}

      {history ? (
        <Sheet title={localizeText("HISTÓRICO")} onClose={() => setHistory(false)}>
          {data.history.length ? (
            <ul className="space-y-1.5">
              {data.history.map((row) => (
                <li key={row.id} className="flex items-center justify-between rounded-xl border border-white/8 bg-white/[.02] px-3 py-2 text-[10px] font-bold">
                  <span className="text-slate-300">{localizeText("STAGE")}{row.stage}</span>
                  <span className="text-slate-500">{row.currency === 'fc' ? `${fmt(row.amount)} BERRIES` : `${fmtTon(row.amount)} TON`}</span>
                  <span className={row.victory ? 'text-emerald-300' : 'text-rose-300'}>{row.victory ? localizeText("VITÓRIA") : localizeText("DERROTA")}</span>
                </li>
              ))}
            </ul>
          ) : <p className="text-center text-[11px] text-slate-500">{localizeText("Nenhuma caçada ainda.")}</p>}
        </Sheet>
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

function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div className="fixed inset-0 z-[150] flex items-end bg-black/80 p-3" onClick={onClose}>
      <div className="mx-auto max-h-[80vh] w-full max-w-[460px] overflow-y-auto rounded-[24px] border border-amber-300/30 bg-[#070b13] p-3.5" onClick={(event) => event.stopPropagation()}>
        <div className="mb-3 flex items-center justify-between">
          <p className="text-[10px] font-black uppercase tracking-[.2em] text-amber-200">{title}</p>
          <button type="button" onClick={onClose} className="grid h-7 w-7 place-items-center rounded-full border border-white/15 text-slate-300"><X className="h-3.5 w-3.5" /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

/** Drop rates live behind a modal so the hunt screen stays clean. */
function DropRatesModal({ fc, ton, entryFc, entryTon, onClose }: {
  fc: FamiliarHuntLootTier[]; ton: FamiliarHuntLootTier[]; entryFc: number; entryTon: number; onClose: () => void;
}) {
  const localizeText = useLocalizedText();

  const [tab, setTab] = useState<'fc' | 'ton'>('fc');
  const tiers = tab === 'fc' ? fc : ton;
  const total = tiers.reduce((sum, tier) => sum + Number(tier.weight || 0), 0) || 1;
  return (
    <Sheet title={localizeText("TAXAS DE DROP")} onClose={onClose}>
      <div className="mb-3 grid grid-cols-2 gap-2">
        {(['fc', 'ton'] as const).map((value) => (
          <button
            key={value}
            type="button"
            onClick={() => setTab(value)}
            className={`rounded-xl border py-2 text-[9px] font-black uppercase tracking-[.12em] ${tab === value ? 'border-amber-300/60 bg-amber-300/15 text-amber-100' : 'border-white/10 bg-white/[.02] text-slate-400'}`}
          >
            {value === 'fc' ? `${fmt(entryFc)} BERRIES` : `${fmtTon(entryTon)} TON`}
          </button>
        ))}
      </div>
      {tab === 'fc' ? (
        <p className="mb-2 text-[10px] font-bold text-amber-200/80">{localizeText("Entrada em BERRIES nunca devolve BERRIES — apenas itens.")}</p>
      ) : (
        <p className="mb-2 text-[10px] font-bold text-sky-200/80">{localizeText("Loot premium: BERRIES, baús, equipamentos épicos e lendários.")}</p>
      )}
      <ul className="space-y-2">
        {tiers.map((tier) => (
          <li key={tier.label} className="rounded-xl border border-white/10 bg-white/[.02] px-3 py-2">
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-black uppercase tracking-[.14em] text-slate-200">{tier.label}</span>
              <span className="text-[10px] font-black text-amber-200">{((Number(tier.weight) / total) * 100).toFixed(1)}%</span>
            </div>
            <ul className="mt-1 space-y-0.5">
              {(tier.options ?? []).map((option, index) => (
                <li key={index} className="text-[10px] font-semibold text-slate-400">· {lootOptionLine(option)}</li>
              ))}
            </ul>
          </li>
        ))}
      </ul>
    </Sheet>
  );
}

function TeamPicker({ pets, team, onToggle, onClose }: { pets: FamiliarHuntPet[]; team: string[]; onToggle: (pet: FamiliarHuntPet) => void; onClose: () => void }) {
  const localizeText = useLocalizedText();

  return (
    <Sheet title={`EQUIPE · ${team.length}/3`} onClose={onClose}>
      <div className="grid grid-cols-3 gap-2">
        {pets.map((pet) => {
          const on = team.includes(pet.playerPetId);
          return (
            <button
              key={pet.playerPetId}
              type="button"
              onClick={() => onToggle(pet)}
              className={`rounded-2xl border p-2 text-center transition active:scale-95 ${on ? 'border-amber-300/70 bg-amber-300/10' : 'border-white/10 bg-white/[.02]'}`}
            >
              {pet.image ? <img src={pet.image} alt={pet.name} loading="lazy" className="mx-auto h-14 object-contain" /> : null}
              <p className="mt-1 truncate text-[9px] font-black uppercase text-slate-200">{pet.name}</p>
              <p className="text-[8px] text-slate-500">{localizeText("Nv")}{pet.level} · {fmt(pet.power)}</p>
            </button>
          );
        })}
      </div>
    </Sheet>
  );
}
