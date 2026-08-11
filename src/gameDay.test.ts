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
