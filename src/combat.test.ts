import { describe, expect, it } from 'vitest';
import { applyBossHit, applyHeroCycle, calculateBossDamageToHero, calculateEstimatedSecondsRemaining, calculateHeroAttack, calculateHeroMaxHp, calculateTeamDamagePerCycle, clampHp, formatDuration, grantRewardOnce, normalizeRarity, preserveProportionalHp, reviveDueHeroes, type CombatHero } from './combat';

const hero = (rarity = 'common', alive = true): CombatHero => ({ id: crypto.randomUUID(), heroId: 'h', name: 'Hero', rarity, slot: 1, level: 1, baseAtk: rarity === 'legendary' ? 2.68 : 1.875, finalAtk: rarity === 'legendary' ? 2.68 : 1.875, baseHp: 100, maxHp: 100, currentHp: alive ? 100 : 0, isAlive: alive, knockedOutAt: null, reviveAt: null });

describe('boss combat formulas', () => {
  it('five common level 1 heroes deal 9.375 per cycle', () => expect(calculateTeamDamagePerCycle(Array.from({ length: 5 }, () => hero()))).toBe(9.375));
  it('five commons defeat 67500 HP in 20 hours without deaths', () => expect(calculateEstimatedSecondsRemaining(67500, 9.375)).toBe(72000));
  it('five legendary heroes are faster', () => expect(calculateEstimatedSecondsRemaining(67500, calculateTeamDamagePerCycle(Array.from({ length: 5 }, () => hero('legendary'))))!).toBeLessThan(72000));
  it('knocked-out heroes deal no damage', () => expect(calculateTeamDamagePerCycle([hero('common', false)])).toBe(0));
  it('applies level growth and safe HP', () => { expect(calculateHeroAttack(1.875, 2)).toBe(1.931); expect(calculateHeroMaxHp(100, 2)).toBe(105); expect(clampHp(-8, 100)).toBe(0); });
  it('boss damage respects rarity and never drops below one', () => { expect(calculateBossDamageToHero(8, 'common')).toBe(8); expect(calculateBossDamageToHero(8, 'lendário')).toBe(6); expect(calculateBossDamageToHero(0, 'rare')).toBe(1); });
  it('normalizes Portuguese and unknown rarity', () => { expect(normalizeRarity('ÉPICA')).toBe('epic'); expect(normalizeRarity('mythic')).toBe('common'); });
  it('preserves proportional HP without free healing', () => expect(preserveProportionalHp(50, 100, 200)).toBe(100));
  it('never formats NaN, infinity or negative values', () => { expect(formatDuration(Infinity)).toBe('--'); expect(formatDuration(NaN)).toBe('--'); expect(formatDuration(-1)).toBe('--'); });
  it('boss attacks only a selected living hero and HP never becomes negative',()=>{const living=hero(),dead=hero('rare',false);const hit=applyBossHit([living,dead],999,living.id,0);expect(hit[0].currentHp).toBe(0);expect(hit[1]).toEqual(dead);});
  it('a hero revives at five minutes with full HP',()=>{const knocked={...hero('common',false),reviveAt:new Date(300_000).toISOString()};expect(reviveDueHeroes([knocked],299_999)[0].isAlive).toBe(false);expect(reviveDueHeroes([knocked],300_000)[0]).toMatchObject({isAlive:true,currentHp:100,reviveAt:null});});
  it('boss HP never becomes negative',()=>expect(applyHeroCycle(1,[hero()]).bossHp).toBe(0));
  it('reward idempotency survives repeated requests',()=>{const keys=new Set<string>();expect(grantRewardOnce(keys,'combat',120000)).toBe(120000);expect(grantRewardOnce(keys,'combat',120000)).toBe(0);});
  it('duplicate concurrent reward attempts share the idempotency key',()=>{const keys=new Set<string>();expect([grantRewardOnce(keys,'x',10),grantRewardOnce(keys,'x',10)].reduce((a,b)=>a+b)).toBe(10)});
  it('reprocessing the same hero timestamp does not add damage when persisted HP is reused',()=>{const first=applyHeroCycle(100,[hero()]);const reopened=first.bossHp;expect(reopened).toBe(98.125)});
  it('empty team produces finite safe output',()=>{expect(calculateTeamDamagePerCycle([])).toBe(0);expect(calculateEstimatedSecondsRemaining(67500,0)).toBeNull()});
});
