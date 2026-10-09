import { describe, expect, it } from 'vitest';
import { DEFAULT_SHIP, SHIP_MODELS, SHIP_SKINS, shipMaxHp, shipStats } from './naval';
describe('naval presentation', () => {
  it('has six distinct model and skin identifiers', () => { expect(new Set(SHIP_MODELS.map(m => m.id)).size).toBe(6);expect(new Set(SHIP_SKINS.map(s => s.id)).size).toBe(6); });
  it('keeps cosmetic models independent of server stats', () => { expect(shipStats({...DEFAULT_SHIP,model:'legendary',skin:'king'})).toEqual(shipStats(DEFAULT_SHIP)); });
  it('derives hull and progression from server level', () => { expect(shipMaxHp({...DEFAULT_SHIP,level:5})).toBe(1400);expect(shipStats({...DEFAULT_SHIP,level:5}).crew).toBe(4); });
});