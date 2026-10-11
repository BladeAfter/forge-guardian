import { describe, expect, it } from 'vitest';
import { pirateEquipmentArt, pirateEquipmentImage } from './pirateEquipmentArt';
import { replaceLegacyCreatureArt } from './voyageArtReplacement';

describe('pirate equipment presentation', () => {
  it('maps each official equipment kind without changing its identity', () => {
    for (const [kind, image] of Object.entries(pirateEquipmentArt)) {
      expect(pirateEquipmentImage(`eq_${kind}_rare_3`)).toBe(image);
      expect(pirateEquipmentImage(`/assets/game/equipment/${kind}-legendary.png`)).toBe(image);
    }
  });
  it('preserves official ownership, rarity and equipment bonuses', () => {
    const item = { instanceId: 'owned-123', code: 'eq_sword_rare_3', rarity: 'rare', bonusAttack: 45, bonusDefense: 8, level: 3, image: '/assets/game/equipment/sword-rare.png' };
    expect(replaceLegacyCreatureArt(item)).toEqual({ ...item, image: pirateEquipmentArt.sword });
  });
  it('leaves unrelated and unknown equipment unchanged', () => {
    expect(pirateEquipmentImage('eq_unknown_rare_1')).toBeNull();
    expect(pirateEquipmentImage('/assets/game/chests/rare-chest.png')).toBeNull();
  });
  it('covers legacy named equipment through its official kind', () => {
    const item = { code: 'nft-nightshroud', kind: 'armor', slot: 'armor', rarity: 'nft_exclusive', image: '/assets/game/equipment/nft/nightshroud-garb.png', bonusDefense: 100 };
    expect(replaceLegacyCreatureArt(item)).toEqual({ ...item, image: pirateEquipmentArt.armor });
  });
});