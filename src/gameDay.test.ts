import{describe,expect,it}from'vitest';
import{nextResetCountdown,officialGameDayKey}from'./calendarRewards';

// 21:00 America/Sao_Paulo = 00:00 UTC (BRT, UTC-3).
const spTime=(iso:string)=>new Date(`${iso}-03:00`);

describe('official game day (21:00 America/Sao_Paulo)',()=>{
 it('TEST 1 — 20:59 still belongs to the previous game day',()=>{
  expect(officialGameDayKey(spTime('2026-08-11T20:59:00'))).toBe('2026-08-10');
 });
 it('TEST 2 — 21:00 opens the next game day',()=>{
  expect(officialGameDayKey(spTime('2026-08-11T21:00:00'))).toBe('2026-08-11');
 });
 it('TEST 3 — reopening the app between two rollovers never changes the day',()=>{
  const keys=['2026-08-11T21:05:00','2026-08-11T22:00:00','2026-08-11T23:30:00','2026-08-12T08:00:00','2026-08-12T20:59:59']
   .map(t=>officialGameDayKey(spTime(t)));
  expect(new Set(keys).size).toBe(1);
  expect(keys[0]).toBe('2026-08-11');
 });
 it('TEST 4 — launch day allows at most Day 1',()=>{
  const launch=officialGameDayKey(spTime('2026-08-10T21:00:00'));
  expect(officialGameDayKey(spTime('2026-08-10T23:59:00'))).toBe(launch);
  expect(officialGameDayKey(spTime('2026-08-11T20:59:00'))).toBe(launch);
 });
 it('device midnight does not roll the day over',()=>{
  expect(officialGameDayKey(spTime('2026-08-12T00:10:00'))).toBe('2026-08-11');
 });
 it('countdown uses the server reset timestamp only',()=>{
  const now=Date.parse('2026-08-11T18:46:00-03:00');
  expect(nextResetCountdown('2026-08-11T21:00:00-03:00',now)).toBe('02h 14m');
  expect(nextResetCountdown(undefined,now)).toBe('--h --m');
 });
});

import{calendarDayStatus,type CalendarDashboard}from'./calendarRewards';
const dash=(o:Partial<CalendarDashboard>):CalendarDashboard=>({cycle:'1',currentDay:1,claimedDays:[],canClaim:true,rewards:[],balance:0,...o});

describe('calendar day status (one claim per official day)',()=>{
 it('TEST 1 — before the claim only Day 1 is available',()=>{
  const d=dash({currentDay:1,availableDay:1,canClaim:true});
  expect(calendarDayStatus(d,1,1)).toBe('AVAILABLE');
  expect(calendarDayStatus(d,2,1)).toBe('LOCKED');
 });
 it('TEST 1b — after claiming Day 1, Day 2 stays locked',()=>{
  const d=dash({currentDay:1,availableDay:null,claimedDays:[1],canClaim:false,claimedToday:true});
  expect(calendarDayStatus(d,1,1)).toBe('CLAIMED');
  expect(calendarDayStatus(d,2,1)).toBe('LOCKED');
  expect(calendarDayStatus(d,3,1)).toBe('LOCKED');
 });
 it('TEST 5 — after the 21:00 rollover Day 2 becomes available',()=>{
  const d=dash({currentDay:2,availableDay:2,claimedDays:[1],canClaim:true,claimedToday:false});
  expect(calendarDayStatus(d,1,2)).toBe('CLAIMED');
  expect(calendarDayStatus(d,2,2)).toBe('AVAILABLE');
  expect(calendarDayStatus(d,3,2)).toBe('LOCKED');
 });
 it('never exposes two available days nor two claimed days from one claim',()=>{
  const d=dash({currentDay:1,availableDay:null,claimedDays:[1],canClaim:false,claimedToday:true});
  const all=Array.from({length:30},(_,i)=>calendarDayStatus(d,i+1,1));
  expect(all.filter(s=>s==='AVAILABLE')).toHaveLength(0);
  expect(all.filter(s=>s==='CLAIMED')).toHaveLength(1);
 });
 it('server statuses win over any local guess',()=>{
  const d=dash({currentDay:5,availableDay:5,claimedDays:[1,2,3,4],dayStatuses:{'5':'LOCKED'},canClaim:true});
  expect(calendarDayStatus(d,5,5)).toBe('LOCKED');
 });
});
