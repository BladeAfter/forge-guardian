import { describe, it, expect, vi, afterEach } from 'vitest';
vi.mock('./apiClient',()=>({forgeFetch:vi.fn()}));
import {forgeFetch} from './apiClient';
import {formatOceanTon,nearestOceanChest,oceanChestCall,type OceanChest} from './oceanChests';
import {oceanChests} from './locales/oceanChests';
describe('shared ocean chest presentation and contracts',()=>{
 afterEach(()=>{vi.clearAllMocks();});
 const chest=(id:string,x:number,expiresAt=new Date(Date.now()+60000).toISOString()):OceanChest=>({id,x,y:0,region:'open-sea',rarity:'common',expiresAt,odds:[]});
 it('preserves the smallest TON prize',()=>{expect(formatOceanTon(.001,'pt-BR')).toBe('0,001');expect(formatOceanTon(.1,'en')).toBe('0.100');});
 it('selects only nearest unexpired chest within collection radius without mutating state',()=>{
  const chests=[chest('far',101),chest('near',90),chest('expired',0,'2020-01-01')];
  expect(nearestOceanChest(chests,{x:0,y:0},100)?.id).toBe('near');expect(chests[0].id).toBe('far');expect(nearestOceanChest(chests,{x:500,y:0},100)).toBeNull();
 });
 it('sends only chest identity and authenticated session, never prize or position',async()=>{
  vi.mocked(forgeFetch).mockResolvedValue(new Response(JSON.stringify({chests:[],reward:{kind:'ton',amount:.001,paymentStatus:'pending_review'}})));
  const result=await oceanChestCall('test-session','claim','chest-id');
  expect(forgeFetch).toHaveBeenCalledWith('realm',{initData:'test-session',action:'ocean-chests',oceanAction:'claim',id:'chest-id'},12000);expect(result.reward?.paymentStatus).toBe('pending_review');
 });
 it('never displays a fabricated reward on rejection',async()=>{
  vi.mocked(forgeFetch).mockResolvedValue(new Response(JSON.stringify({error:'OCEAN_CHEST_UNAVAILABLE'})));
  await expect(oceanChestCall('test','claim','id')).rejects.toThrow('OCEAN_CHEST_UNAVAILABLE');
 });
 it('covers the same nonempty player copy in all five languages',()=>{
  const base=Object.keys(oceanChests.en).sort();expect(Object.keys(oceanChests)).toHaveLength(5);
  for(const locale of Object.values(oceanChests)){expect(Object.keys(locale).sort()).toEqual(base);expect(Object.values(locale).every(v=>typeof v==='string' && v.length>0)).toBe(true);}
 });
});