import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
const hooks=vi.hoisted(()=>({effects:[] as Array<()=>void|(()=>void)>,states:[] as unknown[]}));
vi.mock('react',()=>({useRef:(current:unknown)=>({current}),useState:(v:unknown)=>[v,(next:unknown)=>hooks.states.push(next)],useEffect:(fn:()=>void|(()=>void))=>hooks.effects.push(fn)}));
vi.mock('./oceanChests',()=>({oceanChestCall:vi.fn()}));
import {oceanChestCall,type OceanChestState} from './oceanChests';
import {useOceanChests} from './useOceanChests';
const state={chests:[],history:[],equipmentQuotes:[],odds:[],collectRadius:100,emission:'budget_unavailable'} as OceanChestState;
describe('ocean chest synchronization',()=>{
 beforeEach(()=>{vi.useFakeTimers();vi.clearAllMocks();hooks.effects=[];hooks.states=[];vi.stubGlobal('document',{hidden:false,addEventListener:vi.fn(),removeEventListener:vi.fn()});vi.stubGlobal('window',{addEventListener:vi.fn(),removeEventListener:vi.fn()});});
 afterEach(()=>{vi.useRealTimers();vi.unstubAllGlobals();});
 it('never polls or claims without a Telegram session',async()=>{
  const ocean=useOceanChests('');hooks.effects[0]();await ocean.action('claim','id');await vi.advanceTimersByTimeAsync(10000);expect(oceanChestCall).not.toHaveBeenCalled();
 });
 it('allows urgent claim during polling and ignores the older poll response',async()=>{
  let resolve:((s:OceanChestState)=>void)|undefined;
  vi.mocked(oceanChestCall).mockImplementationOnce(()=>new Promise(done=>resolve=done)).mockResolvedValue(state);
  const ocean=useOceanChests('fixture');const cleanup=hooks.effects[0]();
  expect(await ocean.action('claim','chest')).toBe(true);expect(ocean.current.current).toBe(state);
  resolve?.({...state,chests:[{id:'stale',x:0,y:0,rarity:'common',region:'test',expiresAt:'2099-01-01',odds:[]}]});await vi.advanceTimersByTimeAsync(1);
  expect(ocean.current.current?.chests).toEqual([]);if(typeof cleanup==='function')cleanup();
 });
 it('deduplicates simultaneous collection requests and recovers after rejection',async()=>{
  vi.mocked(oceanChestCall).mockResolvedValue(state);
  const ocean=useOceanChests('fixture');const cleanup=hooks.effects[0]();await vi.advanceTimersByTimeAsync(1);vi.mocked(oceanChestCall).mockRejectedValueOnce(new Error('OCEAN_CHEST_UNAVAILABLE'));
  const first=ocean.action('claim','id');expect(await ocean.action('claim','id')).toBe(false);expect(await first).toBe(false);expect(hooks.states).toContain('OCEAN_CHEST_UNAVAILABLE');expect(await ocean.action('claim','other')).toBe(true);if(typeof cleanup==='function')cleanup();
 });
});