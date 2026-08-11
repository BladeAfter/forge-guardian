import { useEffect, useMemo, useRef, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Lock, Plus, ShieldAlert, Sparkles, Swords, X } from 'lucide-react';
import { fuseHeroesByRarity } from '../services';
import { RARITY_COLOR, RARITY_LABEL, type RarityFusionDashboard, type RarityFusionHero, type RarityFusionResult } from '../heroFusion';

const fmt = (value: number) => new Intl.NumberFormat('pt-BR').format(Math.round(value || 0));
const SLOTS = [0, 1, 2, 3, 4];

/** Mythreon Core altar: 5 rune slots orbiting the arcane crystal. */
function AltarSlot({ hero, onPick, onClear }: { hero: RarityFusionHero | null; onPick: () => void; onClear: () => void }) {
  if (!hero) {
    return (
      <button
        onClick={onPick}
        className="grid aspect-square w-full place-items-center rounded-2xl border border-dashed border-amber-300/35 bg-[#070d18]/80 text-amber-300/70 shadow-[inset_0_0_18px_rgba(96,165,250,.16)]"
        aria-label="Selecionar herói"
      >
        <Plus size={22} />
      </button>
    );
  }
  return (
    <div className="relative aspect-square w-full overflow-hidden rounded-2xl border bg-black/70" style={{ borderColor: RARITY_COLOR[hero.rarity] }}>
      {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} loading="lazy" className="h-full w-full object-cover" /> : null}
      <span className="absolute inset-x-0 bottom-0 truncate bg-black/70 px-1 py-0.5 text-[8px] font-black uppercase">{hero.name}</span>
      <button onClick={onClear} aria-label="Remover herói" className="absolute right-1 top-1 grid h-6 w-6 place-items-center rounded-lg border border-white/20 bg-black/75 text-white">
        <X size={11} />
      </button>
    </div>
  );
}

export function HeroRarityFusion({ telegramInitData, data }: { telegramInitData: string; data: RarityFusionDashboard }) {
  const queryClient = useQueryClient();
  const [selected, setSelected] = useState<string[]>([]);
  const [picking, setPicking] = useState<number | null>(null);
  const [filter, setFilter] = useState<string>('all');
  const [confirming, setConfirming] = useState(false);
  const [phase, setPhase] = useState<'idle' | 'fusing' | 'result'>('idle');
  const [result, setResult] = useState<RarityFusionResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const busy = useRef(false);

  const config = data.config;
  const tiers = config?.tiers ?? {};
  const required = config?.required_heroes ?? 5;
  const heroes = data.heroes ?? [];
  const byId = useMemo(() => new Map(heroes.map((h) => [h.heroId, h])), [heroes]);
  const chosen = selected.map((id) => byId.get(id) ?? null).filter(Boolean) as RarityFusionHero[];
  const sourceRarity = chosen[0]?.rarity ?? null;
  const tier = sourceRarity ? tiers[sourceRarity] : null;
  const cost = tier?.cost_fc ?? 0;
  const complete = selected.length === required;
  const notEnoughFc = complete && data.balance < cost;
  const fusionEnabled = config?.enabled !== false;

  // Dropped heroes (consumed by a previous fusion) must never stay pinned to a slot.
  useEffect(() => {
    setSelected((prev) => prev.filter((id) => byId.has(id)));
  }, [byId]);

  const pool = heroes.filter((hero) => {
    if (selected.includes(hero.heroId)) return false;
    if (sourceRarity && hero.rarity !== sourceRarity) return false;
    if (!sourceRarity && filter !== 'all' && hero.rarity !== filter) return false;
    return true;
  });

  async function runFusion() {
    if (busy.current || !complete || notEnoughFc) return;
    busy.current = true;
    setConfirming(false);
    setError(null);
    setPhase('fusing');
    const key = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
    const started = Date.now();
    try {
      const payload = await fuseHeroesByRarity(telegramInitData, selected, key);
      // Keep the ritual on screen for at least 3s so the reveal never feels instant.
      const wait = Math.max(0, 3200 - (Date.now() - started));
      await new Promise((resolve) => setTimeout(resolve, wait));
      setResult(payload);
      setPhase('result');
      setSelected([]);
      queryClient.setQueryData(['rarity-fusion', telegramInitData], payload.dashboard);
      queryClient.invalidateQueries({ queryKey: ['player-heroes'] });
      queryClient.invalidateQueries({ queryKey: ['hero-fusion'] });
      queryClient.invalidateQueries({ queryKey: ['player-inventory'] });
      queryClient.invalidateQueries({ queryKey: ['reward-history'] });
      queryClient.invalidateQueries({ queryKey: ['game-state'] });
      queryClient.invalidateQueries({ queryKey: ['wallet-summary'] });
    } catch (err) {
      setPhase('idle');
      setError(err instanceof Error ? err.message : 'Não foi possível concluir a fusão.');
    } finally {
      busy.current = false;
    }
  }

  return (
    <section className="pb-4">
      <div className="rounded-2xl border border-amber-300/20 bg-[radial-gradient(circle_at_top,#12224a_0%,#060b16_70%)] p-3 text-center">
        <p className="text-[9px] uppercase tracking-[.3em] text-amber-300">MYTHREON</p>
        <h2 className="text-lg font-black">HERO FUSION</h2>
        <p className="mt-1 text-[10px] leading-snug text-slate-300">
          Combine {required} heróis da mesma raridade por uma chance de obter um herói da raridade seguinte.
        </p>
        {!fusionEnabled ? <p className="mt-2 rounded-lg border border-rose-400/40 bg-rose-500/10 px-2 py-1 text-[10px] font-black text-rose-200">FUSÃO TEMPORARIAMENTE DESATIVADA</p> : null}
      </div>

      {/* Altar */}
      <div className="relative mt-3 overflow-hidden rounded-2xl border border-white/10 bg-[#04070d] p-3">
        <div className="pointer-events-none absolute left-1/2 top-1/2 h-56 w-56 -translate-x-1/2 -translate-y-1/2 rounded-full border border-amber-300/15 bg-[radial-gradient(circle,rgba(96,165,250,.22),transparent_62%)]" />
        <div className="pointer-events-none absolute left-1/2 top-1/2 h-36 w-36 -translate-x-1/2 -translate-y-1/2 rounded-full border border-blue-300/20" />
        <div className="relative">
          <div className="mx-auto w-1/3">
            <AltarSlot hero={chosen[0] ?? null} onPick={() => setPicking(0)} onClear={() => setSelected((p) => p.filter((_, i) => i !== 0))} />
          </div>
          <div className="mt-2 flex justify-center gap-8">
            {[1, 2].map((index) => (
              <div key={index} className="w-1/3">
                <AltarSlot hero={chosen[index] ?? null} onPick={() => setPicking(index)} onClear={() => setSelected((p) => p.filter((_, i) => i !== index))} />
              </div>
            ))}
          </div>
          <div className="mt-2 flex justify-center gap-8">
            {[3, 4].map((index) => (
              <div key={index} className="w-1/3">
                <AltarSlot hero={chosen[index] ?? null} onPick={() => setPicking(index)} onClear={() => setSelected((p) => p.filter((_, i) => i !== index))} />
              </div>
            ))}
          </div>
          <div className="mt-3 grid place-items-center">
            <div className={`grid h-14 w-14 place-items-center rounded-xl border border-amber-300/50 bg-[conic-gradient(from_0deg,#1e3a8a,#0b1220,#1e3a8a)] text-amber-200 ${complete ? 'animate-pulse' : ''}`}>
              <Sparkles size={22} />
            </div>
            <p className="mt-1 text-[9px] font-black uppercase tracking-[.24em] text-amber-300">MYTHREON CORE</p>
          </div>
        </div>
      </div>

      {/* Cost panel */}
      <div className="mt-3 space-y-1.5 rounded-2xl border border-white/10 bg-black/50 p-3 text-[11px]">
        <Row label="HERÓIS NECESSÁRIOS" value={`${selected.length} / ${required}`} />
        <Row label="RARIDADE ATUAL" value={sourceRarity ? RARITY_LABEL[sourceRarity] ?? sourceRarity : '—'} color={sourceRarity ? RARITY_COLOR[sourceRarity] : undefined} />
        <Row label="RESULTADO POSSÍVEL" value={tier ? RARITY_LABEL[tier.target] ?? tier.target : '—'} color={tier ? RARITY_COLOR[tier.target] : undefined} />
        <Row label="CHANCE DE SUCESSO" value={tier ? `${tier.chance}%` : '—'} />
        <Row label="CUSTO DA FUSÃO" value={tier ? `${fmt(cost)} FC` : '—'} />
        <Row label="COMPENSAÇÃO NA FALHA" value={tier ? `${fmt(tier.fragments)} Fragmentos Universais` : '—'} />
        <Row label="SEU SALDO" value={`${fmt(data.balance)} FC`} />
      </div>

      {error ? <p className="mt-2 rounded-lg border border-rose-400/40 bg-rose-500/10 px-2 py-1.5 text-[10px] text-rose-200">{error}</p> : null}
      {notEnoughFc ? <p className="mt-2 text-center text-[10px] font-black text-rose-300">NOT ENOUGH FC</p> : null}

      <button
        disabled={!complete || notEnoughFc || !fusionEnabled || phase === 'fusing'}
        onClick={() => setConfirming(true)}
        className="mt-3 min-h-[46px] w-full rounded-xl border border-amber-300/50 bg-gradient-to-b from-amber-300/25 to-amber-500/10 text-[12px] font-black uppercase tracking-[.16em] text-amber-100 disabled:opacity-40"
      >
        {phase === 'fusing' ? 'FUNDINDO...' : complete ? `FUNDIR • ${fmt(cost)} FC` : `SELECIONE ${required} HERÓIS`}
      </button>

      {data.history?.length ? (
        <div className="mt-4 rounded-2xl border border-white/10 bg-black/40 p-3">
          <p className="text-[10px] uppercase tracking-[.2em] text-slate-400">Histórico recente</p>
          <ul className="mt-1.5 space-y-1">
            {data.history.map((entry) => (
              <li key={entry.id} className="flex items-center justify-between gap-2 text-[10px]">
                <span className="truncate text-slate-300">
                  {RARITY_LABEL[entry.sourceRarity] ?? entry.sourceRarity} → {RARITY_LABEL[entry.targetRarity] ?? entry.targetRarity}
                </span>
                <b className={entry.success ? 'text-emerald-300' : 'text-rose-300'}>
                  {entry.success ? entry.rewardHero ?? 'SUCESSO' : `+${entry.fragments} frag.`}
                </b>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {/* Hero picker */}
      {picking !== null ? (
        <div className="fixed inset-0 z-[95] flex items-end bg-black/80" onClick={() => setPicking(null)}>
          <div className="forge-safe-page max-h-[82vh] w-full overflow-y-auto rounded-t-3xl border-t border-amber-300/25 bg-[#050a12] p-3" onClick={(event) => event.stopPropagation()}>
            <div className="mb-2 flex items-center justify-between">
              <h3 className="text-sm font-black">SELECIONAR HERÓI</h3>
              <button onClick={() => setPicking(null)} aria-label="Fechar" className="grid h-9 w-9 place-items-center rounded-xl border border-white/15 bg-black/60"><X size={16} /></button>
            </div>
            {!sourceRarity ? (
              <div className="mb-2 flex flex-wrap gap-1.5">
                {['all', 'common', 'uncommon', 'rare', 'epic'].map((option) => (
                  <button
                    key={option}
                    onClick={() => setFilter(option)}
                    className={`min-h-[30px] rounded-lg border px-2 text-[9px] font-black uppercase tracking-[.1em] ${filter === option ? 'border-amber-300/60 bg-amber-300/15 text-amber-200' : 'border-white/12 bg-black/50 text-slate-300'}`}
                  >
                    {option === 'all' ? 'ALL' : RARITY_LABEL[option]}
                  </button>
                ))}
              </div>
            ) : (
              <p className="mb-2 text-[10px] text-slate-400">
                Raridade travada em <b style={{ color: RARITY_COLOR[sourceRarity] }}>{RARITY_LABEL[sourceRarity] ?? sourceRarity}</b> pelo primeiro herói selecionado.
              </p>
            )}
            {pool.length === 0 ? (
              <p className="py-10 text-center text-[11px] text-slate-400">Nenhum herói disponível para esta seleção.</p>
            ) : (
              <div className="grid grid-cols-3 gap-2">
                {pool.map((hero) => {
                  const blocked = hero.locked || hero.equipped || !tiers[hero.rarity];
                  return (
                    <button
                      key={hero.heroId}
                      disabled={blocked}
                      onClick={() => {
                        setSelected((prev) => {
                          const next = [...prev];
                          if (picking < next.length) next[picking] = hero.heroId;
                          else next.push(hero.heroId);
                          return next.slice(0, required);
                        });
                        setPicking(null);
                      }}
                      className="overflow-hidden rounded-xl border bg-black/70 text-left disabled:opacity-45"
                      style={{ borderColor: RARITY_COLOR[hero.rarity] }}
                    >
                      {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} loading="lazy" className="aspect-square w-full object-cover" /> : null}
                      <div className="p-1.5">
                        <b className="block truncate text-[9px]">{hero.name}</b>
                        <p className="text-[8px]" style={{ color: RARITY_COLOR[hero.rarity] }}>{RARITY_LABEL[hero.rarity] ?? hero.rarity} · Nv. {hero.level}</p>
                        {hero.locked ? <p className="flex items-center gap-1 text-[8px] text-amber-300"><Lock size={9} /> BLOQUEADO</p> : null}
                        {hero.equipped ? <p className="flex items-center gap-1 text-[8px] text-emerald-300"><Swords size={9} /> EM EQUIPE</p> : null}
                        {!tiers[hero.rarity] && !hero.locked && !hero.equipped ? <p className="text-[8px] text-slate-400">FUSÃO MÁXIMA</p> : null}
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      ) : null}

      {/* Confirmation */}
      {confirming && tier ? (
        <div className="fixed inset-0 z-[96] grid place-items-center bg-black/85 p-3">
          <div className="forge-safe-page w-full max-w-[420px] rounded-2xl border border-amber-300/30 bg-[#060b14] p-3">
            <h3 className="text-sm font-black">CONFIRMAR FUSÃO</h3>
            <p className="mt-1 text-[10px] text-slate-300">Você vai consumir estes {required} heróis:</p>
            <div className="mt-2 grid grid-cols-5 gap-1">
              {chosen.map((hero) => (
                <div key={hero.heroId} className="overflow-hidden rounded-lg border" style={{ borderColor: RARITY_COLOR[hero.rarity] }}>
                  {hero.imageUrl ? <img src={hero.imageUrl} alt={hero.name} className="aspect-square w-full object-cover" /> : null}
                </div>
              ))}
            </div>
            <div className="mt-2 space-y-1 text-[11px]">
              <Row label="RARIDADE ATUAL" value={RARITY_LABEL[tier ? sourceRarity ?? '' : ''] ?? sourceRarity ?? ''} />
              <Row label="RESULTADO POSSÍVEL" value={RARITY_LABEL[tier.target] ?? tier.target} color={RARITY_COLOR[tier.target]} />
              <Row label="CHANCE" value={`${tier.chance}%`} />
              <Row label="CUSTO" value={`${fmt(cost)} FC`} />
              <Row label="COMPENSAÇÃO" value={`${fmt(tier.fragments)} Fragmentos`} />
            </div>
            <p className="mt-2 flex items-center gap-1 text-[10px] font-black text-rose-300"><ShieldAlert size={12} /> ESTA AÇÃO NÃO PODE SER DESFEITA.</p>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <button onClick={() => setConfirming(false)} className="min-h-[42px] rounded-xl border border-white/15 bg-black/60 text-[11px] font-black uppercase">CANCELAR</button>
              <button onClick={runFusion} className="min-h-[42px] rounded-xl border border-amber-300/50 bg-amber-300/20 text-[11px] font-black uppercase text-amber-100">CONFIRMAR</button>
            </div>
          </div>
        </div>
      ) : null}

      {/* Ritual animation */}
      {phase === 'fusing' ? (
        <div className="fixed inset-0 z-[97] grid place-items-center bg-black/92">
          <div className="relative grid h-52 w-52 place-items-center">
            <div className="absolute inset-0 animate-spin rounded-full border-2 border-dashed border-amber-300/40" style={{ animationDuration: '3.4s' }} />
            <div className="absolute inset-6 animate-pulse rounded-full border border-blue-300/40 bg-[radial-gradient(circle,rgba(96,165,250,.35),transparent_65%)]" />
            {SLOTS.map((index) => (
              <span
                key={index}
                className="absolute h-2.5 w-2.5 rounded-full bg-amber-200 shadow-[0_0_12px_rgba(251,191,36,.9)]"
                style={{
                  transform: `rotate(${index * 72}deg) translateY(-88px)`,
                  animation: 'fade-in .6s ease-out both',
                  animationDelay: `${index * 0.18}s`,
                }}
              />
            ))}
            <Sparkles size={40} className="animate-pulse text-amber-200" />
          </div>
          <p className="mt-4 text-[11px] font-black uppercase tracking-[.28em] text-amber-200">FUNDINDO...</p>
        </div>
      ) : null}

      {/* Result */}
      {phase === 'result' && result ? (
        <div className="fixed inset-0 z-[98] grid place-items-center bg-black/92 p-4">
          <div className="animate-scale-in w-full max-w-[380px] rounded-2xl border p-4 text-center" style={{ borderColor: result.success ? RARITY_COLOR[result.targetRarity] : '#f43f5e', background: '#050a12' }}>
            {result.success && result.hero ? (
              <>
                <p className="text-[10px] uppercase tracking-[.3em] text-amber-300">FUSION SUCCESS</p>
                {result.hero.imageUrl ? (
                  <img src={result.hero.imageUrl} alt={result.hero.name} className="mx-auto mt-2 aspect-square w-40 rounded-xl border object-cover" style={{ borderColor: RARITY_COLOR[result.hero.rarity] }} />
                ) : null}
                <h3 className="mt-2 text-lg font-black">{result.hero.name}</h3>
                <p className="text-[11px] font-black" style={{ color: RARITY_COLOR[result.hero.rarity] }}>{RARITY_LABEL[result.hero.rarity] ?? result.hero.rarity}</p>
                <p className="text-[9px] uppercase tracking-[.2em] text-emerald-300">NOVO HERÓI</p>
                <div className="mt-2 grid grid-cols-3 gap-1 text-[10px]">
                  <Stat label="ATK" value={fmt(result.hero.finalAtk)} />
                  <Stat label="HP" value={fmt(result.hero.finalHp)} />
                  <Stat label="PODER" value={fmt(result.hero.power)} />
                </div>
              </>
            ) : (
              <>
                <p className="text-[10px] uppercase tracking-[.3em] text-rose-300">FUSION FAILED</p>
                <h3 className="mt-2 text-base font-black">A fusão foi instável.</h3>
                <p className="mt-2 text-[10px] uppercase tracking-[.2em] text-slate-400">COMPENSAÇÃO</p>
                <p className="text-lg font-black text-amber-200">Fragmentos Universais x{fmt(result.fragments)}</p>
              </>
            )}
            <p className="mt-2 text-[10px] text-slate-400">Saldo: {fmt(result.balance)} FC</p>
            <button onClick={() => { setPhase('idle'); setResult(null); }} className="mt-3 min-h-[44px] w-full rounded-xl border border-amber-300/50 bg-amber-300/20 text-[11px] font-black uppercase text-amber-100">
              CONTINUAR
            </button>
          </div>
        </div>
      ) : null}
    </section>
  );
}

const Row = ({ label, value, color }: { label: string; value: string; color?: string }) => (
  <div className="flex items-start justify-between gap-3">
    <span className="shrink-0 text-[9px] uppercase tracking-[.14em] text-slate-400">{label}</span>
    <b className="text-right text-[11px] font-black" style={color ? { color } : undefined}>{value}</b>
  </div>
);

const Stat = ({ label, value }: { label: string; value: string }) => (
  <div className="rounded-lg border border-white/10 bg-black/50 p-1.5">
    <p className="text-[8px] uppercase tracking-[.14em] text-slate-400">{label}</p>
    <b className="text-[11px]">{value}</b>
  </div>
);
