import ReactDOM from 'react-dom/client';
import { useEffect, useState } from 'react';
import '../styles.css';
import { LanguageProvider } from '../LanguageContext';
import { PirateActionArena } from '../components/PirateActionArena';
import { actionArenaArt } from '../gameAssets';
const kraken = actionArenaArt.kraken;
const hero = (i: number) => ({ id: 'h'+i, heroId: 'h'+i, name: 'Pirata '+i, rarity: 'Common', slot: i, level: 1, baseAtk: 100, finalAtk: 100, baseHp: 1000, maxHp: 1000, currentHp: 1000, isAlive: true, knockedOutAt: null, reviveAt: null });
function Sim() {
  const [hp, setHp] = useState(67500); const [damage, setDamage] = useState(0);
  const [heroes, setHeroes] = useState([1,2,3].map(hero)); const [last, setLast] = useState<string | null>(null);
  useEffect(() => { const t = setInterval(() => { setLast(new Date().toISOString()); setHeroes(h => h.map((x, i) => i === 0 ? { ...x, currentHp: Math.max(0, x.currentHp - 180) } : x)); (window as any).__krakenAttacks = ((window as any).__krakenAttacks || 0) + 1; }, 2500); return () => clearInterval(t); }, []);
  return <div style={{ width: 360, height: 740 }}><PirateActionArena name="Kraken das Profundezas" image={kraken} hp={hp} maxHp={67500} heroes={heroes} pet={null} hit={false} active cooldown={0} bossCountdown={null} damage={damage} rank={null} reward={0} bossLastAttackAt={last} swap={null}
    onAttack={() => { setDamage(d => d + 420); setHp(h => h - 420); }} onEquip={() => {}} onRanking={() => {}} /></div>;
}
ReactDOM.createRoot(document.getElementById('root')!).render(<LanguageProvider><Sim /></LanguageProvider>);
