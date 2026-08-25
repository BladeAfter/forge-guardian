import { createRoot } from 'react-dom/client';
import { FamiliarHuntBattle } from './components/FamiliarHuntBattle';
const pet=(name:string)=>({name,image:null,maxHp:5000,hp:5000,atk:900,power:1200});
const en=(name:string,elite=false)=>({name,image:null,maxHp:9000,hp:9000,atk:700,elite});
const result={ok:true,runId:'x',victory:true,rounds:3,teamPower:3600,totalDamage:9000,rewards:[],
  log:[{round:1,side:'pet' as const,actor:0,target:0,damage:1200,crit:false,ko:false,targetHp:1,targetMax:1}],
  team:[pet('Astrling'),pet('Cindra'),pet('Nimbry')],enemies:[en('Goblin'),en('Ogro',true),en('Wisp')],runsToday:1,maxRunsPerDay:5};
createRoot(document.getElementById('root')!).render(<FamiliarHuntBattle result={result as never} missionName="TESTE" onFinished={()=>{}} />);
