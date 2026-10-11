import { useCallback, useEffect, useMemo, useState } from 'react';
import { forgeFetch } from '../apiClient';
import { fleetShipArt } from '../gameAssets';
import { useLocalizedText } from '../LanguageContext';
import './ShipFleetPage.css';
import { ShipCustomizationPanel } from './ShipCustomizationPanel';
import { ShipAppearancePreview } from './ShipAppearancePreview';
import { canCustomizeShip, shipCosmetics } from '../shipCustomization';
import type { ShipCosmetics } from '../naval';

type Stat = 'atk' | 'def' | 'hp' | 'spd' | 'acc';
type ShipClass = { id: string; name: string; rarity: string; specialty: string; priceTon: number; atk: number; def: number; hp: number; spd: number; acc: number; skill: number };
type Upgrade = { category: string; name: string; stat: string; perLevel: number; maxLevel: number; woodBase: number; ironBase: number; berriesBase: number; tonCost: number; growth: number };
type Owned = { classId: string; level: number; xp: number; xpNext: number; points: number; allocated: Record<Stat, number>; upgrades: Record<string, number>; canCustomize?: boolean; cosmetics?: Partial<ShipCosmetics> };
type FleetState = { active: string; settings: { pointsPerLevel: number; respecEnabled: boolean }; classes: ShipClass[]; upgrades: Upgrade[]; owned: Owned[]; balances: { ton: number; berries: number }; materials: Record<string, number> };

const STATS: { key: Stat; label: string; per: number; desc: string }[] = [
  { key: 'atk', label: 'ATAQUE', per: 4, desc: 'Dano dos canhões' },
  { key: 'def', label: 'DEFESA', per: 2, desc: 'Reduz o dano recebido' },
  { key: 'hp', label: 'VIDA', per: 40, desc: 'Resistência máxima do casco' },
  { key: 'spd', label: 'VELOCIDADE', per: 1, desc: 'Velocidade de navegação' },
  { key: 'acc', label: 'PRECISÃO', per: 2, desc: 'Aumenta o dano acertado' },
];
const UPGRADE_KEY: Record<string, Stat | 'skill'> = { cannons: 'atk', hull: 'hp', armor: 'def', sails: 'spd', aim: 'acc', core: 'skill' };
const PER_UPGRADE: Record<string, number> = { cannons: 15, hull: 150, armor: 6, sails: 3, aim: 4, core: 5 };
const ERRORS: Record<string, string> = {
  FLEET_PURCHASE_REQUIRED: 'Personalização disponível apenas nos navios comprados.', FLEET_NOT_OWNED: 'Personalização disponível apenas nos navios comprados.',
  FLEET_TON_REQUIRED: 'Saldo de TON insuficiente.', FLEET_ALREADY_OWNED: 'Você já possui este navio.', FLEET_POINTS_REQUIRED: 'Pontos insuficientes.',
  NAVAL_XP_REQUIRED: 'XP insuficiente para evoluir.', NAVAL_MATERIALS_REQUIRED: 'Madeira ou ferro insuficientes.', FLEET_BERRIES_REQUIRED: 'BERRIES insuficientes.',
  FLEET_MAX_LEVEL: 'Nível máximo atingido.', NAVAL_IN_BATTLE: 'Indisponível durante uma batalha.',
};

/** Computes the same formula the server uses, for display only. */
export function shipStats(k: ShipClass, o?: Owned) {
  const lv = o?.level ?? 1, a = o?.allocated ?? { atk: 0, def: 0, hp: 0, spd: 0, acc: 0 }, u = o?.upgrades ?? {};
  const up = (c: string) => Number(u[c] ?? 0);
  return {
    atk: k.atk + (lv - 1) * 8 + a.atk * 4 + up('cannons') * 15,
    def: k.def + (lv - 1) * 3 + a.def * 2 + up('armor') * 6,
    hp: k.hp + (lv - 1) * 100 + a.hp * 40 + up('hull') * 150,
    spd: Math.min(200, k.spd + (lv - 1) + a.spd + up('sails') * 3),
    acc: k.acc + a.acc * 2 + up('aim') * 4,
  };
}
const power = (s: ReturnType<typeof shipStats>) => Math.round(s.atk * 3 + s.def * 4 + s.hp / 5 + s.spd * 2 + s.acc * 2);

export function ShipFleetPage({ telegramInitData, onClose, onFleetChest }: { telegramInitData: string; onClose: () => void; onFleetChest: () => void }) {
  const text = useLocalizedText();
  const [state, setState] = useState<FleetState | null>(null);
  const [tab, setTab] = useState<'fleet' | 'stats' | 'upgrade' | 'style'>('fleet');
  const [viewId, setViewId] = useState<string>('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [draft, setDraft] = useState<Record<Stat, number>>({ atk: 0, def: 0, hp: 0, spd: 0, acc: 0 });
  const [confirmBuy, setConfirmBuy] = useState<ShipClass | null>(null);
  const [flash, setFlash] = useState(0);

  const call = useCallback(async (fleetAction: string, input: Record<string, unknown> = {}, success = '') => {
    setBusy(true); setMsg('');
    try {
      const res = await forgeFetch('realm', { initData: telegramInitData, action: 'fleet', fleetAction, input });
      const body = (await res.json().catch(() => null)) as { code?: string; error?: string; data?: unknown } | null;
      if (!res.ok || !body || body.error) { const code = String(body?.code || body?.error || ''); setMsg(text(ERRORS[code] || 'Não foi possível concluir. Tente novamente.')); return false; }
      setState((body.data ?? body) as FleetState); if (success) { setMsg(text(success)); setFlash(x => x + 1); }
      return true;
    } catch { setMsg(text('Não foi possível salvar a personalização.')); return false;
    } finally { setBusy(false); }
  }, [telegramInitData, text]);

  useEffect(() => { void call('state'); }, [call]);
  useEffect(() => { if (state && !viewId) setViewId(state.active); }, [state, viewId]);

  const ship = state?.classes.find(c => c.id === viewId) ?? state?.classes[0];
  const owned = state?.owned.find(o => o.classId === ship?.id);
  const stats = useMemo(() => ship ? shipStats(ship, owned) : null, [ship, owned]);
  const used = Object.values(draft).reduce((a, b) => a + b, 0);
  const preview = ship && owned ? shipStats(ship, { ...owned, allocated: Object.fromEntries(STATS.map(s => [s.key, owned.allocated[s.key] + draft[s.key]])) as Record<Stat, number> }) : null;

  if (!state || !ship || !stats) return <div className="ship-fleet"><div className="ship-fleet__loading">{text(msg || 'Preparando o estaleiro…')}</div><button className="ship-fleet__close" onClick={onClose} aria-label={text('Fechar')}>✕</button></div>;

  const xpPct = owned ? Math.min(100, (owned.xp / Math.max(1, owned.xpNext)) * 100) : 0;
  return <div className="ship-fleet">
    <div className="ship-fleet__fog" aria-hidden />
    <header className="ship-fleet__top">
      <button className="ship-fleet__close" onClick={onClose} aria-label={text('Fechar')}>✕</button>
      <h1>{text('NAVIO')}</h1>
      <span className="ship-fleet__ton">{state.balances.ton.toFixed(2)} TON</span>
    </header>

    <section className="ship-fleet__hero" key={ship.id + flash}>
      {canCustomizeShip(owned) && Object.keys(owned?.cosmetics ?? {}).length > 0 ? <ShipAppearancePreview classId={ship.id} cosmetics={shipCosmetics(owned?.cosmetics)} /> : <img src={fleetShipArt.classes[ship.id]} alt={ship.name} className="ship-fleet__art" />}
      <div className="ship-fleet__plate">
        <span className={`ship-fleet__rarity ship-fleet__rarity--${ship.rarity.normalize('NFD').replace(/[^a-z]/gi, '').toLowerCase()}`}>{text(ship.rarity)}</span>
        <h2>{ship.name}</h2>
        <p>{text(ship.specialty)}</p>
        <div className="ship-fleet__level"><b>{text('Nível')} {owned?.level ?? 1}</b><span>{text('Poder')} {power(stats).toLocaleString()}</span></div>
        {owned && <div className="ship-fleet__xp"><i style={{ width: `${xpPct}%` }} /><small>{owned.xp} / {owned.xpNext} XP</small></div>}
      </div>
      <div className="ship-fleet__chips">
        {(['atk', 'def', 'hp', 'spd'] as Stat[]).map(k => <span key={k}><b>{k.toUpperCase()}</b>{stats[k]}</span>)}
      </div>
    </section>

    <nav className="ship-fleet__tabs">
      {([['fleet', 'FROTA'], ['stats', 'ATRIBUTOS'], ['upgrade', 'MELHORAR'], ['style', 'PERSONALIZAR']] as const).map(([k, l]) =>
        <button key={k} className={tab === k ? 'is-active' : ''} onClick={() => { setTab(k); setMsg(''); }}>{text(l)}</button>)}
    </nav>
    {msg && <div className="ship-fleet__msg" role="status">{msg}</div>}

    <section className="ship-fleet__panel">
      {tab === 'fleet' && <div className="ship-fleet__grid">
        {state.classes.map(c => {
          const o = state.owned.find(x => x.classId === c.id); const st = shipStats(c, o);
          return <button key={c.id} className={`ship-fleet__card ${c.id === ship.id ? 'is-viewing' : ''}`} onClick={() => setViewId(c.id)}>
            <img src={fleetShipArt.classes[c.id]} alt="" />
            <strong>{c.name}</strong>
            <small>{text(c.specialty)}</small>
            <em>ATK {st.atk} · DEF {st.def} · SPD {st.spd}</em>
            <span className="ship-fleet__tag">{state.active === c.id ? text('EM USO') : o ? text('POSSUÍDO') : c.priceTon > 0 ? `${c.priceTon} TON` : text('GRÁTIS')}</span>
          </button>;
        })}
        <div className="ship-fleet__actions">
          {!owned && <button disabled={busy} className="ship-fleet__primary" onClick={() => setConfirmBuy(ship)}>{text('COMPRAR')} · {ship.priceTon} TON</button>}
          {owned && state.active !== ship.id && <button disabled={busy} className="ship-fleet__primary" onClick={() => call('select', { classId: ship.id }, 'Navio selecionado!')}>{text('USAR ESTE NAVIO')}</button>}
          {owned && owned.xp >= owned.xpNext && <button disabled={busy} className="ship-fleet__primary" onClick={() => call('levelup', { classId: ship.id }, 'Navio evoluiu! +5 pontos')}>{text('EVOLUIR')}</button>}
          <button className="ship-fleet__ghost" onClick={onFleetChest}>{text('BAÚ DA FROTA')}</button>
        </div>
      </div>}

      {tab === 'stats' && (owned ? <div className="ship-fleet__stats">
        <p className="ship-fleet__points">{text('Pontos disponíveis')}: <b>{owned.points - used}</b></p>
        {STATS.map(s => <div key={s.key} className="ship-fleet__stat">
          <div><strong>{text(s.label)}</strong><small>{text(s.desc)}</small></div>
          <span>{stats[s.key]} → <b>{preview?.[s.key]}</b></span>
          <button disabled={draft[s.key] <= 0} onClick={() => setDraft(d => ({ ...d, [s.key]: d[s.key] - 1 }))} aria-label="-">−</button>
          <em>+{draft[s.key]}</em>
          <button disabled={used >= owned.points} onClick={() => setDraft(d => ({ ...d, [s.key]: d[s.key] + 1 }))} aria-label="+">+</button>
        </div>)}
        <div className="ship-fleet__actions">
          <button className="ship-fleet__ghost" disabled={!used} onClick={() => setDraft({ atk: 0, def: 0, hp: 0, spd: 0, acc: 0 })}>{text('CANCELAR')}</button>
          <button className="ship-fleet__primary" disabled={!used || busy} onClick={async () => { if (await call('allocate', { classId: ship.id, ...draft }, 'Pontos distribuídos!')) setDraft({ atk: 0, def: 0, hp: 0, spd: 0, acc: 0 }); }}>{text('CONFIRMAR DISTRIBUIÇÃO')}</button>
        </div>
        <small className="ship-fleet__note">{text('A redistribuição só é possível com item especial.')}</small>
      </div> : <p className="ship-fleet__note">{text('Compre este navio para distribuir atributos.')}</p>)}

      {tab === 'upgrade' && (owned ? <div className="ship-fleet__upgrades">
        {state.upgrades.map(u => {
          const lv = Number(owned.upgrades[u.category] ?? 0); const max = lv >= u.maxLevel; const f = Math.pow(u.growth, lv);
          const wood = Math.ceil(u.woodBase * f), iron = Math.ceil(u.ironBase * f), berries = Math.ceil(u.berriesBase * f);
          const key = UPGRADE_KEY[u.category]; const cur = key === 'skill' ? `+${lv * 5}%` : stats[key]; const next = key === 'skill' ? `+${(lv + 1) * 5}%` : stats[key] + PER_UPGRADE[u.category];
          return <div key={u.category} className="ship-fleet__upgrade">
            <div><strong>{text(u.name)}</strong><small>{text('Nível')} {lv}/{u.maxLevel}</small></div>
            <span>{cur} → <b>{max ? '—' : next}</b></span>
            {!max && <small className="ship-fleet__cost">🪵 {wood} · ⛓ {iron} · {berries.toLocaleString()} BERRIES{u.tonCost > 0 ? ` · ${u.tonCost} TON` : ''}</small>}
            <button className="ship-fleet__primary" disabled={max || busy} onClick={() => call('upgrade', { classId: ship.id, category: u.category }, 'Melhoria concluída!')}>{max ? text('MÁXIMO') : text('MELHORAR')}</button>
          </div>;
        })}
      </div> : <p className="ship-fleet__note">{text('Compre este navio para melhorá-lo.')}</p>)}

      {tab === 'style' && <ShipCustomizationPanel key={ship.id} classId={ship.id} owned={owned} busy={busy} onSave={cosmetics => call('customize', { classId: ship.id, cosmetics }, 'Personalização salva!')} />}
    </section>

    {confirmBuy && <div className="ship-fleet__modal" role="dialog" aria-modal>
      <div>
        <img src={fleetShipArt.classes[confirmBuy.id]} alt="" />
        <h3>{text('Comprar')} {confirmBuy.name}?</h3>
        <p>{confirmBuy.priceTon} TON · {text('Saldo')}: {state.balances.ton.toFixed(2)} TON</p>
        <div className="ship-fleet__actions">
          <button className="ship-fleet__ghost" onClick={() => setConfirmBuy(null)}>{text('CANCELAR')}</button>
          <button className="ship-fleet__primary" disabled={busy} onClick={async () => { const c = confirmBuy; setConfirmBuy(null); await call('buy', { classId: c.id }, 'Navio adquirido!'); }}>{text('CONFIRMAR')}</button>
        </div>
      </div>
    </div>}
  </div>;
}
