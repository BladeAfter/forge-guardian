import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  REALM_ROOM_LABEL,
  fetchRealmState,
  realmClaimBounty,
  realmClaimBuilding,
  realmClaimCraft,
  realmClaimExpedition,
  realmEnsureBounties,
  realmRuinChoose,
  realmRuinExtract,
  realmRuinStart,
  realmSecondsLeft,
  realmStartCraft,
  realmStartExpedition,
  realmTimer,
  realmUpgradeBuilding,
  type RealmState,
} from '../realm';

const WORLD_MAP = '/assets/game/realm/world-map.jpg';
const STRONGHOLD = '/assets/game/realm/stronghold.jpg';
const RUINS_BG = '/assets/game/realm/ruins-bg.jpg';

type Tab = 'stronghold' | 'map' | 'forge' | 'ruins' | 'bounties';

const TABS: { id: Tab; label: string }[] = [
  { id: 'stronghold', label: 'STRONGHOLD' },
  { id: 'map', label: 'MAPA' },
  { id: 'forge', label: 'FORJA' },
  { id: 'ruins', label: 'RUÍNAS' },
  { id: 'bounties', label: 'CONTRATOS' },
];

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/**
 * MYTHREON REALM — acesso antecipado (somente admins liberados no backend).
 * Toda a verdade vem de `realm_state`; esta tela apenas renderiza o estado do servidor.
 */
export function RealmPage({ telegramInitData, onBack }: { telegramInitData: string; onBack: () => void }) {
  const qc = useQueryClient();
  const [tab, setTab] = useState<Tab>('stronghold');
  const [now, setNow] = useState(() => Date.now());
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const { data, isLoading, error } = useQuery<RealmState>({
    queryKey: ['realm', telegramInitData],
    queryFn: () => fetchRealmState(telegramInitData),
    enabled: Boolean(telegramInitData),
    refetchInterval: 30_000,
  });

  const apply = (next: RealmState) => {
    qc.setQueryData(['realm', telegramInitData], next);
    const reward = next.lastReward as Record<string, unknown> | undefined;
    if (reward) setNotice(describeReward(reward));
  };

  const act = useMutation({
    mutationFn: async (run: () => Promise<RealmState>) => run(),
    onSuccess: apply,
    onError: (e: Error) => setNotice(e.message),
  });
  const busy = act.isPending;
  const call = (run: () => Promise<RealmState>) => act.mutate(run);

  useEffect(() => {
    if (!notice) return;
    const id = window.setTimeout(() => setNotice(null), 4000);
    return () => window.clearTimeout(id);
  }, [notice]);

  const balances = data?.balances ?? {};
  const materials = data?.materials ?? [];
  const materialById = useMemo(
    () => Object.fromEntries(materials.map((m) => [m.id, m])),
    [materials],
  );

  if (isLoading) {
    return (
      <div className="forge-safe-page min-h-screen bg-[#05070f] p-4">
        {[1, 2, 3].map((k) => <div key={k} className="mb-3 h-32 animate-pulse rounded-3xl bg-white/5" />)}
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="forge-safe-page min-h-screen bg-[#05070f] p-6 text-center">
        <p className="mt-16 text-sm text-rose-300">{(error as Error)?.message || 'Falha ao abrir o MYTHREON REALM.'}</p>
        <button onClick={onBack} className="mt-6 rounded-2xl border border-amber-300/40 px-5 py-3 text-xs font-black uppercase tracking-[.2em] text-amber-200">VOLTAR</button>
      </div>
    );
  }

  const profile = data.profile;
  const ruinRun = data.ruinRun;
  const openRooms = data.ruinRooms.filter((r) => r.room_index === (ruinRun?.current_room ?? -1) && r.status === 'open');

  return (
    <div className="forge-safe-page min-h-screen bg-[#05070f] pb-24">
      {/* HERO */}
      <header className="relative h-52 overflow-hidden">
        <img src={STRONGHOLD} alt="Stronghold do jogador" className="absolute inset-0 h-full w-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-t from-[#05070f] via-[#05070f]/50 to-transparent" />
        <button onClick={onBack} className="absolute left-3 top-3 rounded-2xl border border-white/15 bg-black/60 px-3 py-2 text-[10px] font-black uppercase tracking-[.2em] text-amber-100">VOLTAR</button>
        <span className="absolute right-3 top-3 rounded-full border border-amber-300/40 bg-black/60 px-3 py-1 text-[8px] font-black uppercase tracking-[.2em] text-amber-200">ACESSO ANTECIPADO</span>
        <div className="absolute bottom-3 left-4 right-4">
          <h1 className="bg-gradient-to-r from-amber-100 to-amber-400 bg-clip-text text-2xl font-black uppercase tracking-[.12em] text-transparent">MYTHREON REALM</h1>
          <p className="mt-0.5 text-[10px] font-black uppercase tracking-[.26em] text-slate-300">
            STRONGHOLD NÍVEL {profile?.stronghold_level ?? 1} · {fmt(data.fc)} FC
          </p>
        </div>
      </header>

      {/* MATERIALS STRIP */}
      <div className="flex gap-2 overflow-x-auto px-3 py-3">
        {materials.map((m) => (
          <div key={m.id} className="flex shrink-0 items-center gap-2 rounded-2xl border border-white/10 bg-black/60 px-2.5 py-1.5">
            {m.image_url && <img src={m.image_url} alt={m.name} loading="lazy" className="h-7 w-7 object-contain" />}
            <div>
              <p className="text-[7px] font-black uppercase tracking-[.16em] text-slate-400">{m.name}</p>
              <b className="text-[11px] text-amber-100">{fmt(Number(balances[m.id] ?? 0))}</b>
            </div>
          </div>
        ))}
      </div>

      {/* TABS */}
      <nav className="flex gap-1.5 overflow-x-auto px-3">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => { setTab(t.id); if (t.id === 'bounties') call(() => realmEnsureBounties(telegramInitData)); }}
            className={`shrink-0 rounded-2xl border px-3 py-2 text-[9px] font-black uppercase tracking-[.18em] ${tab === t.id ? 'border-amber-300/60 bg-amber-500/15 text-amber-100' : 'border-white/10 bg-black/50 text-slate-400'}`}
          >
            {t.label}
          </button>
        ))}
      </nav>

      {notice && (
        <p className="mx-3 mt-3 rounded-2xl border border-amber-300/35 bg-amber-500/10 px-3 py-2 text-[10px] font-bold text-amber-100">{notice}</p>
      )}

      <main className="px-3 pt-4">
        {/* ---------- STRONGHOLD ---------- */}
        {tab === 'stronghold' && (
          <section className="space-y-2.5">
            {data.buildingTypes.map((bt) => {
              const b = data.buildings.find((x) => x.building_type === bt.id);
              const level = b?.level ?? 0;
              const left = realmSecondsLeft(b?.upgrade_finishes_at, now);
              const upgrading = b?.status !== 'idle' && left > 0;
              const ready = b?.status !== 'idle' && left <= 0;
              const cost = Math.round(bt.base_fc_cost * Math.pow(1.55, level));
              return (
                <article key={bt.id} className="flex gap-3 rounded-3xl border border-white/10 bg-gradient-to-br from-[#0c1120] to-black p-3">
                  {bt.image_url && <img src={bt.image_url} alt={bt.name} loading="lazy" className="h-24 w-24 shrink-0 object-contain drop-shadow-[0_8px_18px_rgba(0,0,0,.7)]" />}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2">
                      <b className="text-[12px] font-black uppercase tracking-[.1em] text-amber-100">{bt.name}</b>
                      <span className="rounded-full border border-amber-300/30 bg-black/60 px-2 py-0.5 text-[8px] font-black text-amber-200">NV {level}/{bt.max_level}</span>
                    </div>
                    <p className="mt-1 text-[9px] leading-4 text-slate-400">{bt.description}</p>
                    <p className="mt-1 text-[9px] text-slate-500">
                      Custo: {fmt(cost)} FC · {Object.entries(bt.cost_materials).map(([id, qty]) => `${fmt(Math.ceil(Number(qty) * Math.pow(1.35, level)))} ${materialById[id]?.name ?? id}`).join(' · ')}
                    </p>
                    {upgrading ? (
                      <p className="mt-2 rounded-2xl border border-cyan-300/30 bg-cyan-500/10 px-3 py-2 text-center text-[10px] font-black tabular-nums text-cyan-100">EM OBRAS · {realmTimer(left)}</p>
                    ) : ready ? (
                      <button disabled={busy} onClick={() => call(() => realmClaimBuilding(telegramInitData, bt.id))} className="mt-2 w-full rounded-2xl bg-gradient-to-r from-emerald-400 to-teal-300 py-2.5 text-[10px] font-black uppercase tracking-[.2em] text-black">CONCLUIR</button>
                    ) : (
                      <button disabled={busy || level >= bt.max_level} onClick={() => call(() => realmUpgradeBuilding(telegramInitData, bt.id))} className="mt-2 w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-2.5 text-[10px] font-black uppercase tracking-[.2em] text-black disabled:opacity-40">
                        {level === 0 ? 'CONSTRUIR' : 'EVOLUIR'}
                      </button>
                    )}
                  </div>
                </article>
              );
            })}
          </section>
        )}

        {/* ---------- MAP / EXPEDITIONS ---------- */}
        {tab === 'map' && (
          <section className="space-y-3">
            <div className="overflow-hidden rounded-3xl border border-amber-300/25">
              <img src={WORLD_MAP} alt="Mapa do mundo de Mythreon" loading="lazy" className="w-full object-cover" />
            </div>

            {data.expeditions.length > 0 && (
              <div className="space-y-2">
                {data.expeditions.map((e) => {
                  const left = realmSecondsLeft(e.finishes_at, now);
                  const region = data.regions.find((r) => r.id === e.region_id);
                  return (
                    <div key={e.id} className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/60 px-3 py-2.5">
                      <div>
                        <b className="text-[11px] text-amber-100">{region?.name ?? e.region_id}</b>
                        <p className="text-[8px] font-black uppercase tracking-[.2em] text-slate-400">{e.expedition_type === 'deep' ? 'EXPEDIÇÃO PROFUNDA' : 'COLETA RÁPIDA'}</p>
                      </div>
                      {left > 0
                        ? <span className="text-[11px] font-black tabular-nums text-cyan-200">{realmTimer(left)}</span>
                        : <button disabled={busy} onClick={() => call(() => realmClaimExpedition(telegramInitData, e.id))} className="rounded-xl bg-gradient-to-r from-emerald-400 to-teal-300 px-3 py-2 text-[9px] font-black uppercase tracking-[.16em] text-black">COLETAR</button>}
                    </div>
                  );
                })}
              </div>
            )}

            {data.regions.map((r) => {
              const locked = (profile?.stronghold_level ?? 1) < r.unlock_stronghold_level;
              return (
                <article key={r.id} className="overflow-hidden rounded-3xl border border-white/10 bg-black/60">
                  {r.image_url && <img src={r.image_url} alt={r.name} loading="lazy" className={`h-36 w-full object-cover ${locked ? 'opacity-40 grayscale' : ''}`} />}
                  <div className="p-3">
                    <b className="text-[12px] font-black uppercase tracking-[.12em] text-amber-100">{r.name}</b>
                    <p className="mt-0.5 text-[9px] leading-4 text-slate-400">{r.tagline}</p>
                    {locked ? (
                      <p className="mt-2 text-[9px] font-black uppercase tracking-[.16em] text-rose-300">BLOQUEADA · STRONGHOLD NV {r.unlock_stronghold_level}</p>
                    ) : (
                      <div className="mt-2 grid grid-cols-2 gap-2">
                        <button disabled={busy} onClick={() => call(() => realmStartExpedition(telegramInitData, r.id, 'gather'))} className="rounded-2xl border border-amber-300/35 bg-black/50 py-2.5 text-[9px] font-black uppercase tracking-[.16em] text-amber-200">COLETA 15M</button>
                        <button disabled={busy} onClick={() => call(() => realmStartExpedition(telegramInitData, r.id, 'deep'))} className="rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-2.5 text-[9px] font-black uppercase tracking-[.16em] text-black">PROFUNDA 1H</button>
                      </div>
                    )}
                  </div>
                </article>
              );
            })}
          </section>
        )}

        {/* ---------- FORGE / CRAFTING ---------- */}
        {tab === 'forge' && (
          <section className="space-y-2.5">
            {data.crafting.map((j) => {
              const left = realmSecondsLeft(j.finishes_at, now);
              const recipe = data.recipes.find((r) => r.id === j.recipe_id);
              return (
                <div key={j.id} className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/60 px-3 py-2.5">
                  <div>
                    <b className="text-[11px] text-amber-100">{recipe?.name ?? j.recipe_id}</b>
                    <p className="text-[8px] font-black uppercase tracking-[.2em] text-slate-400">x{j.quantity}</p>
                  </div>
                  {left > 0
                    ? <span className="text-[11px] font-black tabular-nums text-cyan-200">{realmTimer(left)}</span>
                    : <button disabled={busy} onClick={() => call(() => realmClaimCraft(telegramInitData, j.id))} className="rounded-xl bg-gradient-to-r from-emerald-400 to-teal-300 px-3 py-2 text-[9px] font-black uppercase tracking-[.16em] text-black">RETIRAR</button>}
                </div>
              );
            })}

            {data.recipes.map((r) => {
              const forge = data.buildings.find((b) => b.building_type === 'forge')?.level ?? 0;
              const locked = forge < r.min_forge_level;
              const out = r.output_kind === 'material' ? materialById[r.output_ref]?.name ?? r.output_ref : r.output_ref.replace(/_/g, ' ');
              return (
                <article key={r.id} className={`rounded-3xl border p-3 ${locked ? 'border-white/10 bg-black/40 opacity-60' : 'border-amber-300/25 bg-gradient-to-br from-[#150e04] to-black'}`}>
                  <div className="flex items-center justify-between gap-2">
                    <b className="text-[11px] font-black uppercase tracking-[.1em] text-amber-100">{r.name}</b>
                    <span className="text-[8px] font-black uppercase tracking-[.16em] text-slate-400">FORJA NV {r.min_forge_level}</span>
                  </div>
                  <p className="mt-1 text-[9px] text-slate-400">
                    {Object.entries(r.inputs).map(([id, qty]) => `${fmt(Number(qty))} ${materialById[id]?.name ?? id}`).join(' + ')} + {fmt(r.fc_cost)} FC
                  </p>
                  <p className="mt-0.5 text-[9px] font-black uppercase tracking-[.14em] text-emerald-200">→ {r.output_qty}x {out} · {realmTimer(r.craft_seconds)}</p>
                  <div className="mt-2 grid grid-cols-3 gap-1.5">
                    {[1, 3, 5].map((q) => (
                      <button key={q} disabled={busy || locked} onClick={() => call(() => realmStartCraft(telegramInitData, r.id, q))} className="rounded-2xl border border-amber-300/30 bg-black/50 py-2 text-[9px] font-black uppercase tracking-[.14em] text-amber-200 disabled:opacity-40">x{q}</button>
                    ))}
                  </div>
                </article>
              );
            })}
          </section>
        )}

        {/* ---------- ANCIENT RUINS ---------- */}
        {tab === 'ruins' && (
          <section className="space-y-3">
            <div className="relative overflow-hidden rounded-3xl border border-purple-300/25">
              <img src={RUINS_BG} alt="Ruínas Ancestrais" loading="lazy" className="h-48 w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40 to-transparent" />
              <div className="absolute bottom-3 left-4 right-4">
                <b className="text-[13px] font-black uppercase tracking-[.14em] text-purple-100">RUÍNAS ANCESTRAIS</b>
                <p className="text-[9px] text-slate-300">10 salas. Escolha o caminho, sobreviva ou extraia o loot antes de cair.</p>
              </div>
            </div>

            {!ruinRun ? (
              <div className="space-y-2">
                {data.regions.filter((r) => r.ruin_enabled).map((r) => {
                  const locked = (profile?.stronghold_level ?? 1) < r.unlock_stronghold_level;
                  return (
                    <button key={r.id} disabled={busy || locked} onClick={() => call(() => realmRuinStart(telegramInitData, r.id))} className="w-full rounded-2xl border border-purple-300/30 bg-black/60 px-3 py-3 text-left disabled:opacity-40">
                      <b className="text-[11px] font-black uppercase tracking-[.12em] text-purple-100">ENTRAR · {r.name}</b>
                      <p className="text-[9px] text-slate-400">{locked ? `Stronghold nível ${r.unlock_stronghold_level}` : `Poder recomendado ${fmt(r.recommended_power)}`}</p>
                    </button>
                  );
                })}
              </div>
            ) : (
              <div className="space-y-2.5">
                <div className="grid grid-cols-3 gap-2">
                  <Stat label="Sala" value={`${ruinRun.current_room + 1}/10`} />
                  <Stat label="Vitalidade" value={`${ruinRun.hp}%`} />
                  <Stat label="Moedas" value={fmt(ruinRun.ruin_coins)} />
                </div>
                {data.lastRoom && (
                  <p className="rounded-2xl border border-white/10 bg-black/60 px-3 py-2 text-[10px] text-slate-300">{describeRoom(data.lastRoom)}</p>
                )}
                <div className="grid grid-cols-2 gap-2">
                  {openRooms.map((room) => (
                    <button key={room.id} disabled={busy} onClick={() => call(() => realmRuinChoose(telegramInitData, ruinRun.id, room.branch))} className="rounded-3xl border border-purple-300/30 bg-gradient-to-br from-[#160a24] to-black px-3 py-5 text-center">
                      <b className="text-[11px] font-black uppercase tracking-[.16em] text-purple-100">{REALM_ROOM_LABEL[room.room_type] ?? room.room_type}</b>
                      <p className="mt-1 text-[8px] font-black uppercase tracking-[.2em] text-slate-400">DIFICULDADE {room.config?.difficulty ?? 1}</p>
                    </button>
                  ))}
                </div>
                <button disabled={busy} onClick={() => call(() => realmRuinExtract(telegramInitData, ruinRun.id))} className="w-full rounded-2xl border border-amber-300/35 bg-black/60 py-3 text-[10px] font-black uppercase tracking-[.2em] text-amber-200">EXTRAIR COM O LOOT</button>
              </div>
            )}
          </section>
        )}

        {/* ---------- BOUNTIES ---------- */}
        {tab === 'bounties' && (
          <section className="space-y-2.5">
            {data.bounties.length === 0 && <p className="py-8 text-center text-[10px] text-slate-400">Nenhum contrato ativo hoje.</p>}
            {data.bounties.map((b) => {
              const done = b.progress >= b.target;
              return (
                <article key={b.id} className="rounded-3xl border border-white/10 bg-black/60 p-3">
                  <div className="flex items-center justify-between gap-2">
                    <b className="text-[11px] font-black uppercase tracking-[.1em] text-amber-100">{b.title}</b>
                    <span className="text-[9px] font-black tabular-nums text-slate-300">{Math.min(b.progress, b.target)}/{b.target}</span>
                  </div>
                  <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
                    <div className="h-full rounded-full bg-gradient-to-r from-amber-400 to-yellow-200" style={{ width: `${Math.min(100, (b.progress / b.target) * 100)}%` }} />
                  </div>
                  <p className="mt-1.5 text-[9px] text-slate-400">Recompensa: {fmt(b.reward.fc ?? 0)} FC · {b.reward.fragments ?? 0} fragmentos</p>
                  <button disabled={busy || !done || b.status !== 'active'} onClick={() => call(() => realmClaimBounty(telegramInitData, b.id))} className="mt-2 w-full rounded-2xl bg-gradient-to-r from-amber-400 to-yellow-200 py-2.5 text-[10px] font-black uppercase tracking-[.2em] text-black disabled:opacity-40">
                    {b.status === 'claimed' ? 'RESGATADO' : done ? 'RESGATAR' : 'EM ANDAMENTO'}
                  </button>
                </article>
              );
            })}
          </section>
        )}
      </main>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/60 p-2.5 text-center">
      <p className="text-[7px] font-black uppercase tracking-[.2em] text-slate-400">{label}</p>
      <b className="text-[13px] text-amber-100">{value}</b>
    </div>
  );
}

function describeReward(reward: Record<string, unknown>) {
  const parts: string[] = [];
  if (reward.fc) parts.push(`${fmt(Number(reward.fc))} FC`);
  if (reward.qty && reward.material) parts.push(`${fmt(Number(reward.qty))} ${String(reward.material).replace(/_/g, ' ')}`);
  if (reward.name) parts.push(`${reward.qty ?? ''} ${String(reward.name)}`.trim());
  if (reward.fragments) parts.push(`${fmt(Number(reward.fragments))} fragmentos`);
  Object.entries(reward).forEach(([key, value]) => {
    if (['fc', 'qty', 'material', 'name', 'kind', 'ref', 'cleared', 'fragments'].includes(key)) return;
    if (typeof value === 'number') parts.push(`${fmt(value)} ${key.replace(/_/g, ' ')}`);
  });
  return parts.length ? `Recebido: ${parts.join(' · ')}` : 'Recompensa entregue.';
}

function describeRoom(room: Record<string, unknown>) {
  const type = REALM_ROOM_LABEL[String(room.roomType)] ?? String(room.roomType);
  const dmg = Number(room.damage ?? 0);
  const coins = Number(room.coins ?? 0);
  const extra = room.material ? ` · ${fmt(Number(room.qty ?? 0))} ${String(room.material).replace(/_/g, ' ')}` : '';
  const heal = dmg < 0 ? ` · +${Math.abs(dmg)}% vitalidade` : dmg > 0 ? ` · -${dmg}% vitalidade` : '';
  return `${type}${heal} · +${fmt(coins)} moedas${extra}${room.result === 'failed' ? ' · VOCÊ CAIU' : room.result === 'cleared' ? ' · RUÍNA CONCLUÍDA' : ''}`;
}
