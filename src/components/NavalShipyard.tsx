import { useEffect, useRef, useState } from 'react';
import { X, Check, Hammer, TrendingUp } from 'lucide-react';
import { navalArt } from '../gameAssets';
import { SHIP_MODELS, SHIP_SKINS, shipStats, type NavalShip, type NavalState, type ShipCosmetics } from '../naval';
import { drawNavalShip, navalPalette } from '../navalRendering';
import { OceanControl } from './OceanControl';

export default function NavalShipyard({ ship, state, busy, onSave, onAction, onClose }: { ship: NavalShip; state: NavalState | null; busy: boolean; onSave: (input: Record<string, unknown>) => Promise<void>; onAction: (action: string) => Promise<void>; onClose: () => void }) {
  const [draft, setDraft] = useState(ship);
  const canvas = useRef<HTMLCanvasElement>(null);
  const stats = shipStats(ship);
  useEffect(() => {
    const el = canvas.current, ctx = el?.getContext('2d'); if (!el || !ctx) return;
    const image = new Image(); let alive = true;
    image.onload = () => { if (!alive) return; ctx.clearRect(0,0,360,300); drawNavalShip(ctx,image,{ ...draft,x:180,y:150,heading:Math.PI,hp:stats.hull,throttle:1 },navalPalette(el),0,230); };
    image.src = navalArt.fleet; return () => { alive = false; };
  }, [draft, stats.hull]);
  const cosmetic = (key: keyof ShipCosmetics, value: string) => setDraft(s => ({ ...s,cosmetics:{...s.cosmetics,[key]:value} }));
  return <div className="naval-sheet" role="dialog" aria-modal="true" aria-label="Estaleiro do capitão">
    <header><div><span>GRAND LINE · ESTALEIRO</span><h2>Seu navio, sua lenda</h2></div><OceanControl aria-label="Fechar estaleiro" onClick={onClose}><X size={20}/></OceanControl></header>
    <div className="naval-yard-body"><div className="naval-preview"><canvas ref={canvas} width={360} height={300} aria-label="Prévia do navio personalizado"/><b>{SHIP_MODELS.find(m => m.id === draft.model)?.name}</b><span>{SHIP_SKINS.find(s => s.id === draft.skin)?.name} · Nível {ship.level}</span></div>
    <div className="naval-customization"><h3>Modelo do casco</h3><div className="naval-options">{SHIP_MODELS.map(m => <OceanControl key={m.id} aria-pressed={draft.model === m.id} onClick={() => setDraft(s => ({...s,model:m.id}))}>{draft.model===m.id && <Check size={12}/>} {m.name}</OceanControl>)}</div>
    <h3>Casco e velas</h3><div className="naval-options">{SHIP_SKINS.map(s => <OceanControl key={s.id} className={`naval-skin naval-skin-${s.id}`} aria-pressed={draft.skin===s.id} onClick={() => setDraft(d => ({...d,skin:s.id}))}><i/>{s.name}</OceanControl>)}</div>
    <div className="naval-selects"><label>Bandeira<select aria-label="Bandeira" value={draft.cosmetics.flag} onChange={e => cosmetic('flag',e.target.value)}><option value="skull">Caveira</option><option value="sun">Sol</option><option value="moon">Lua</option></select></label>
    <label>Figura de proa<select aria-label="Figura de proa" value={draft.cosmetics.prow} onChange={e => cosmetic('prow',e.target.value)}><option value="lion">Leão</option><option value="blade">Lâmina</option><option value="none">Sem figura</option></select></label>
    <label>Decoração<select aria-label="Decoração" value={draft.cosmetics.decoration} onChange={e => cosmetic('decoration',e.target.value)}><option value="gold">Ouro</option><option value="silver">Prata</option><option value="none">Sem decoração</option></select></label>
    <label>Esteira e efeitos<select aria-label="Esteira e efeitos" value={draft.cosmetics.trail} onChange={e => cosmetic('trail',e.target.value)}><option value="foam">Espuma</option><option value="embers">Brasas</option><option value="mist">Névoa</option></select></label></div>
    <OceanControl disabled={busy || !state || Boolean(ship.battle_id)} onClick={() => void onSave({model:draft.model,skin:draft.skin,cosmetics:draft.cosmetics})}><Check size={16}/> Aplicar ao navio</OceanControl>
    {!state && <p role="status">Estaleiro compartilhado indisponível; alterações não serão salvas.</p>}
    </div></div>
    <div className="naval-stats">{[['Vida',`${ship.hp}/${stats.hull}`],['Canhões',stats.cannons],['Defesa',stats.defense],['Velocidade',`${stats.speed} m/s`],['Visão',`${stats.vision} m`],['Tripulação',stats.crew]].map(([label,value]) => <div key={label}><span>{label}</span><b>{value}</b></div>)}</div>
    <footer><span>Madeira: {state?.materials.magic_wood ?? 0} · Ferro: {state?.materials.iron_ore ?? 0}<br/>Custo: {(state?.rules.repairWood ?? 5)*ship.level} madeira + {(state?.rules.repairIron ?? 3)*ship.level} ferro</span><OceanControl disabled={busy || !state || Boolean(ship.battle_id) || ship.hp>=stats.hull} onClick={() => void onAction('repair')}><Hammer size={16}/>Reparar</OceanControl><OceanControl disabled={busy || !state || Boolean(ship.battle_id) || ship.xp<ship.level*100} onClick={() => void onAction('upgrade')}><TrendingUp size={16}/>Melhorar ({ship.xp}/{ship.level*100} XP)</OceanControl></footer>
  </div>;
}