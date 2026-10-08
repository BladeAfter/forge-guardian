import { useEffect, useMemo, useState } from 'react';
import {
  realmSecondsLeft,
  realmTimer,
  type RealmBuildingType,
  type RealmCraftJob,
  type RealmMaterial,
  type RealmRecipe,
  type RealmState,
} from '../realm';
import { useT } from '../LanguageContext';
import type { Translator } from '../i18n';

const SCENE_COLD = '/assets/game/realm/forge-scene-cold.jpg';
const SCENE_LIT = '/assets/game/realm/forge-scene-lit.jpg';
const SCENE_MASTER = '/assets/game/realm/forge-scene-master.jpg';
const ANVIL = '/assets/game/realm/forge-anvil.png';
const FC_COIN = '/assets/game/coins/forge-coin.png';

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

/** Nome comercial da forja por nível (apenas rótulo visual). */
const FORGE_TITLE = (lvl: number, t: Translator) =>
  t(lvl <= 0 ? 'realm.forge.name0'
    : lvl === 1 ? 'realm.forge.nameSmith'
    : lvl === 2 ? 'realm.forge.name2'
    : lvl === 3 ? 'realm.forge.name4'
    : lvl === 4 ? 'realm.forge.name5'
    : 'realm.forge.name6');

/** Espelha exatamente a regra do servidor (apenas para exibir o tempo previsto). */
const craftSeconds = (r: RealmRecipe, qty: number, forgeLevel: number) =>
  Math.max(60, Math.floor(r.craft_seconds * qty * (1 - Math.min(0.35, forgeLevel * 0.035))));

/** Slots concorrentes: 2 + floor(forge/3) — mesma fórmula do backend. */
const slotCount = (forgeLevel: number) => 2 + Math.floor(forgeLevel / 3);

type Filter = 'all' | 'material' | 'item';

const FILTERS: { id: Filter; labelKey: string }[] = [
  { id: 'all', labelKey: 'realm.forge.filterAll' },
  { id: 'material', labelKey: 'realm.forge.filterMaterial' },
  { id: 'item', labelKey: 'realm.forge.filterItem' },
];

/**
 * ⚒ FORJA — cena dark fantasy AAA.
 *
 * Apenas apresentação: receitas, custos, tempos, filas e outputs continuam vindo do
 * backend (`realm_state` / `realm_craft_start` / `realm_craft_claim`). Aqui há cena viva,
 * fila em slots, cards de receita, bloqueadas recolhidas, detalhe em bottom sheet e
 * revelação do item ao retirar.
 */
export default function RealmForgeScene({
  forgeLevel, forgeType, recipes, materials, balances, fc, jobs, now, busy,
  onStartCraft, onClaim, onUpgradeForge, onOpenResources,
}: {
  forgeLevel: number;
  forgeType: RealmBuildingType | null;
  recipes: RealmRecipe[];
  materials: RealmMaterial[];
  balances: Record<string, number>;
  fc: number;
  jobs: RealmCraftJob[];
  now: number;
  busy: boolean;
  onStartCraft: (recipeId: string, qty: number) => Promise<RealmState | null>;
  onClaim: (jobId: string) => Promise<RealmState | null>;
  onUpgradeForge: () => void;
  onOpenResources: () => void;
}) {
  const t = useT();
  const [filter, setFilter] = useState<Filter>('all');
  const [lockedOpen, setLockedOpen] = useState(false);
  const [sheet, setSheet] = useState<string | null>(null);
  const [qty, setQty] = useState(1);
  const [igniting, setIgniting] = useState(false);
  const [reveal, setReveal] = useState<{ label: string; qty: number; image: string | null } | null>(null);

  const materialById = useMemo(
    () => Object.fromEntries(materials.map((m) => [m.id, m])) as Record<string, RealmMaterial | undefined>,
    [materials],
  );

  const built = forgeLevel > 0;
  const scene = !built ? SCENE_COLD : forgeLevel >= 4 ? SCENE_MASTER : SCENE_LIT;
  const slots = slotCount(forgeLevel);
  const active = jobs.filter((j) => j.status === 'running' || j.status === 'ready');
  const readyCount = active.filter((j) => realmSecondsLeft(j.finishes_at, now) <= 0).length;

  const open = recipes.filter((r) => forgeLevel >= r.min_forge_level);
  const locked = recipes.filter((r) => forgeLevel < r.min_forge_level);
  const shown = open.filter((r) => filter === 'all' || r.category === filter);

  const recipeById = useMemo(() => Object.fromEntries(recipes.map((r) => [r.id, r])), [recipes]);
  const detail = sheet ? recipeById[sheet] ?? null : null;
  const detailLocked = detail ? forgeLevel < detail.min_forge_level : false;

  useEffect(() => { setQty(1); }, [sheet]);

  const outputLabel = (r: RealmRecipe) =>
    r.output_kind === 'material'
      ? materialById[r.output_ref]?.name ?? r.output_ref
      : r.output_ref.replace(/_/g, ' ');
  const outputImage = (r: RealmRecipe) =>
    (r.output_kind === 'material' ? materialById[r.output_ref]?.image_url : null) ?? ANVIL;

  /** Verificação apenas visual: a autoridade sobre materiais é sempre o servidor. */
  const missing = (r: RealmRecipe, times = 1) => {
    if (fc < r.fc_cost * times) return true;
    return Object.entries(r.inputs).some(([id, need]) => (balances[id] ?? 0) < Number(need) * times);
  };

  const startCraft = async (r: RealmRecipe, times: number) => {
    setSheet(null);
    setIgniting(true);
    window.setTimeout(() => setIgniting(false), 800);
    await onStartCraft(r.id, times);
  };

  const claim = async (job: RealmCraftJob) => {
    const r = recipeById[job.recipe_id];
    const next = await onClaim(job.id);
    if (next && r) setReveal({ label: outputLabel(r), qty: r.output_qty * job.quantity, image: outputImage(r) });
  };

  /* materiais relevantes: os que aparecem nas receitas liberadas */
  const relevant = useMemo(() => {
    const ids = new Set<string>();
    (open.length ? open : recipes).forEach((r) => Object.keys(r.inputs).forEach((id) => ids.add(id)));
    return materials.filter((m) => ids.has(m.id)).slice(0, 3);
  }, [open, recipes, materials]);

  const upgradeCost = forgeType ? Math.round(forgeType.base_fc_cost * Math.pow(1.55, forgeLevel)) : 0;

  return (
    <section className="space-y-3">
      {/* ---------- HERO: cena viva da forja ---------- */}
      <div className={`forge-stage ${built ? '' : 'forge-stage-cold'} ${active.length > 0 ? 'forge-stage-hot' : ''} ${readyCount > 0 ? 'forge-stage-done' : ''}`}>
        <img src={scene} alt="" loading="lazy" className="forge-stage-bg" />
        <div className="forge-stage-vignette" aria-hidden />
        {built && <div className="forge-stage-firelight" aria-hidden />}
        {built && <div className="forge-embers" aria-hidden />}
        {built && active.length > 0 && <div className="forge-sparks" aria-hidden />}
        <div className="forge-smoke" aria-hidden />
        {igniting && <div className="forge-ignite" aria-hidden />}

        {/* bigorna interativa → leva para as receitas */}
        <button
          type="button"
          onClick={() => document.getElementById('forge-recipes')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
          className="forge-anvil-hit"
          aria-label="recipes"
        >
          <img src={ANVIL} alt="" loading="lazy" className={`forge-anvil ${active.length > 0 ? 'forge-anvil-work' : ''}`} />
        </button>

        <div className="forge-stage-top">
          <span className="forge-crest">⚒</span>
          <div className="min-w-0">
            <b className="forge-title">{t('realm.forge.title')} <span className="forge-lv">Lv.{forgeLevel}</span></b>
            <p className="forge-sub">{FORGE_TITLE(forgeLevel, t)}</p>
          </div>
          <button type="button" onClick={onUpgradeForge} className="forge-upgrade">
            {built ? t('realm.forge.upgrade') : t('realm.forge.build')}
          </button>
        </div>

        <div className="forge-stage-foot">
          <span className="forge-pill">{t('realm.forge.slots')} <b>{active.length}/{slots}</b></span>
          {readyCount > 0
            ? <span className="forge-pill forge-pill-done">{t('realm.forge.ready')} <b>{readyCount}</b></span>
            : <span className="forge-pill">{t('realm.forge.producing')} <b>{active.length}</b></span>}
          {relevant.map((m) => (
            <span key={m.id} className="forge-pill">
              {m.image_url && <img src={m.image_url} alt="" loading="lazy" className="h-3.5 w-3.5 object-contain" />}
              <b>{fmt(balances[m.id] ?? 0)}</b>
            </span>
          ))}
          <button type="button" onClick={onOpenResources} className="forge-pill forge-pill-btn">{t('realm.forge.seeAll')}</button>
        </div>
      </div>

      {/* ---------- FORJA NÃO CONSTRUÍDA ---------- */}
      {!built && (
        <div className="forge-card space-y-2.5 text-center">
          <b className="block text-[12px] font-black uppercase tracking-[.16em] text-amber-100">{t('realm.forge.notBuilt')}</b>
          <p className="text-[10px] leading-snug text-slate-400">{t('realm.forge.notBuiltDesc')}</p>
          {forgeType && (
            <div className="flex flex-wrap justify-center gap-1.5">
              <span className="realm-cost-chip realm-cost-chip--gold">
                <img src={FC_COIN} alt="" loading="lazy" className="h-4 w-4 object-contain" />
                <b>{fmt(upgradeCost)}</b> FC
              </span>
              <span className="realm-cost-chip"><b>{realmTimer(forgeType.base_seconds)}</b> {t('realm.forge.buildTime')}</span>
            </div>
          )}
          <button type="button" onClick={onUpgradeForge} className="realm-action-btn">{t('realm.forge.buildCta')}</button>
          <div className="space-y-1.5 pt-1">
            <p className="forge-label">{t('realm.forge.unlocksLv1')}</p>
            <div className="grid grid-cols-3 gap-1.5">
              {locked.filter((r) => r.min_forge_level <= 1).slice(0, 3).map((r) => (
                <button key={r.id} type="button" onClick={() => setSheet(r.id)} className="forge-mini">
                  <img src={outputImage(r)} alt="" loading="lazy" />
                  <span>{r.name}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ---------- FILA DE PRODUÇÃO ---------- */}
      {built && (
        <div className="space-y-2">
          <p className="forge-label">{t('realm.forge.queue')}</p>
          <div className="grid grid-cols-2 gap-2">
            {Array.from({ length: slots }).map((_, i) => {
              const job = active[i];
              if (!job) {
                return (
                  <button
                    key={`empty-${i}`}
                    type="button"
                    onClick={() => document.getElementById('forge-recipes')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
                    className="forge-slot forge-slot-empty"
                  >
                    <span className="forge-slot-plus">＋</span>
                    <b>{t('realm.forge.emptySlot')}</b>
                    <i>{t('realm.forge.chooseRecipe')}</i>
                  </button>
                );
              }
              const r = recipeById[job.recipe_id];
              const left = realmSecondsLeft(job.finishes_at, now);
              const total = r ? craftSeconds(r, job.quantity, forgeLevel) : Math.max(left, 1);
              const pct = Math.max(4, Math.min(100, Math.round(((total - left) / total) * 100)));
              const done = left <= 0;
              return (
                <div key={job.id} className={`forge-slot ${done ? 'forge-slot-done' : 'forge-slot-work'}`}>
                  <div className="flex items-center gap-2">
                    {r && <img src={outputImage(r)} alt="" loading="lazy" className="h-8 w-8 object-contain" />}
                    <div className="min-w-0">
                      <b className="block truncate text-[10px] font-black uppercase tracking-[.08em] text-amber-100">{r?.name ?? job.recipe_id}</b>
                      <i className="text-[9px] not-italic text-slate-400">x{job.quantity}</i>
                    </div>
                  </div>
                  <div className="forge-bar"><span style={{ width: `${done ? 100 : pct}%` }} /></div>
                  {done
                    ? <button type="button" disabled={busy} onClick={() => claim(job)} className="forge-claim">{t('realm.forge.claim')}</button>
                    : <span className="forge-timer">{realmTimer(left)}</span>}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* ---------- RECEITAS DISPONÍVEIS ---------- */}
      {built && (
        <div id="forge-recipes" className="space-y-2">
          <div className="flex items-center justify-between">
            <p className="forge-label">{t('realm.forge.recipes')}</p>
            <div className="flex gap-1">
              {FILTERS.map((f) => (
                <button
                  key={f.id}
                  type="button"
                  onClick={() => setFilter(f.id)}
                  className={`forge-chip ${filter === f.id ? 'forge-chip-on' : ''}`}
                >
                  {t(f.labelKey)}
                </button>
              ))}
            </div>
          </div>

          {shown.length === 0 && <p className="text-center text-[10px] text-slate-500">{t('realm.forge.noRecipes')}</p>}

          <div className="grid grid-cols-2 gap-2">
            {shown.map((r) => {
              const lack = missing(r);
              return (
                <button
                  key={r.id}
                  type="button"
                  onClick={() => setSheet(r.id)}
                  className={`forge-recipe ${lack ? 'forge-recipe-lack' : ''}`}
                >
                  <span className="forge-recipe-art">
                    <img src={outputImage(r)} alt="" loading="lazy" />
                  </span>
                  <b className="forge-recipe-name">{r.name}</b>
                  <i className="forge-recipe-out">{r.output_qty}x {outputLabel(r)}</i>
                  <span className="forge-recipe-foot">
                    <i className="tabular-nums">{realmTimer(craftSeconds(r, 1, forgeLevel))}</i>
                    <b className={lack ? 'forge-recipe-tag-lack' : 'forge-recipe-tag'}>{lack ? t('realm.forge.lack') : t('realm.forge.craft')}</b>
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* ---------- BLOQUEADAS (recolhidas) ---------- */}
      {locked.length > 0 && (
        <div className="space-y-2">
          <button type="button" onClick={() => setLockedOpen((v) => !v)} className="forge-locked-toggle">
            {t('realm.forge.lockedRecipes', { count: locked.length })} <span>{lockedOpen ? '▴' : '▾'}</span>
          </button>
          {lockedOpen && (
            <div className="grid grid-cols-3 gap-1.5">
              {locked.map((r) => (
                <button key={r.id} type="button" onClick={() => setSheet(r.id)} className="forge-mini forge-mini-locked">
                  <img src={outputImage(r)} alt="" loading="lazy" />
                  <span>{r.name}</span>
                  <i>🔒 Lv.{r.min_forge_level}</i>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ---------- DETALHE DA RECEITA ---------- */}
      {detail && (
        <div className="forge-sheet-wrap" onClick={() => setSheet(null)}>
          <div className="forge-sheet" onClick={(e) => e.stopPropagation()}>
            <div className="forge-sheet-head">
              <img src={outputImage(detail)} alt="" loading="lazy" />
              <div className="min-w-0">
                <b>{detail.name}</b>
                <i>{t('realm.forge.produces', { qty: detail.output_qty * (detailLocked ? 1 : qty), name: outputLabel(detail) })}</i>
              </div>
            </div>

            <div className="flex flex-wrap gap-1.5">
              <span className="realm-cost-chip realm-cost-chip--gold">
                <img src={FC_COIN} alt="" loading="lazy" className="h-4 w-4 object-contain" />
                <b>{fmt(detail.fc_cost * (detailLocked ? 1 : qty))}</b> FC
              </span>
              {Object.entries(detail.inputs).map(([id, need]) => {
                const total = Number(need) * (detailLocked ? 1 : qty);
                const have = balances[id] ?? 0;
                return (
                  <span key={id} className={`realm-cost-chip ${have < total ? 'forge-chip-missing' : ''}`}>
                    {materialById[id]?.image_url && <img src={materialById[id]!.image_url as string} alt="" loading="lazy" className="h-4 w-4 object-contain" />}
                    <b>{fmt(total)}</b> {materialById[id]?.name ?? id}
                  </span>
                );
              })}
              <span className="realm-cost-chip"><b>{realmTimer(craftSeconds(detail, detailLocked ? 1 : qty, forgeLevel))}</b></span>
            </div>

            {detailLocked ? (
              <button type="button" disabled className="realm-action-btn opacity-60">{t('realm.forge.requires', { level: detail.min_forge_level })}</button>
            ) : (
              <>
                <div className="flex items-center justify-center gap-4">
                  <button type="button" onClick={() => setQty((q) => Math.max(1, q - 1))} className="forge-qty">−</button>
                  <b className="w-8 text-center text-[15px] tabular-nums text-amber-100">{qty}</b>
                  <button type="button" onClick={() => setQty((q) => Math.min(10, q + 1))} className="forge-qty">+</button>
                </div>
                <button
                  type="button"
                  disabled={busy || active.length >= slots || missing(detail, qty)}
                  onClick={() => startCraft(detail, qty)}
                  className="realm-action-btn"
                >
                  {active.length >= slots ? t('realm.forge.queueFull') : missing(detail, qty) ? t('realm.forge.noMaterials') : t('realm.forge.craft')}
                </button>
              </>
            )}
            <button type="button" onClick={() => setSheet(null)} className="forge-sheet-close">{t('realm.close')}</button>
          </div>
        </div>
      )}

      {/* ---------- REVELAÇÃO DO ITEM ---------- */}
      {reveal && (
        <div className="forge-reveal" onClick={() => setReveal(null)}>
          <div className="forge-reveal-card">
            <p className="forge-reveal-kicker">{t('realm.forge.forged')}</p>
            <div className="forge-reveal-art">
              {reveal.image && <img src={reveal.image} alt="" />}
            </div>
            <b className="forge-reveal-name">{reveal.label}</b>
            <i className="forge-reveal-qty">x{reveal.qty}</i>
            <button type="button" onClick={() => setReveal(null)} className="realm-action-btn realm-action-btn--done">{t('realm.continue')}</button>
          </div>
        </div>
      )}
    </section>
  );
}
