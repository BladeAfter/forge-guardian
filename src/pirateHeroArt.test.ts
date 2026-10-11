import { describe, expect, it } from 'vitest';
import { pirateHeroIdentities, pirateHeroImage } from './pirateHeroArt';
import { replaceLegacyCreatureArt } from './voyageArtReplacement';
import { arenaCrewImage } from './gameAssets';

describe('individual pirate identities', () => {
  it('never shares artwork between distinct catalog pirates', () => {
    const images = Object.values(pirateHeroIdentities).map(hero => hero.image);
    expect(images.length).toBe(213);
    expect(new Set(images).size).toBe(images.length);
  });
  it('keeps Gundrek common with a different image from Stovik and Borund', () => {
    expect(pirateHeroIdentities.mx2_gundrek.rarity).toBe('common');
    expect(pirateHeroImage('mx2_gundrek')).not.toBe(pirateHeroImage('mx2_stovik'));
    expect(pirateHeroImage('mx2_gundrek')).not.toBe(pirateHeroImage('mx_borund'));
  });
  it('preserves one identity across legacy responses, deck and battle', () => {
    for (const [key, identity] of Object.entries(pirateHeroIdentities)) {
      const hero = { heroKey: key, rarity: identity.rarity, image: `/assets/game/new-voyage/heroes/deckblade.png?hero=${key}`, attack: 131, level: 3 };
      expect(replaceLegacyCreatureArt(hero)).toEqual({ ...hero, image: identity.image });
      expect(arenaCrewImage({ image: identity.image, rarity: identity.rarity })).toBe(identity.image);
    }
  });
});