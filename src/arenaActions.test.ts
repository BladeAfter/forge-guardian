import { describe, expect, it } from 'vitest';
import { localizeLiteral } from './literalLocalization';
import { translate } from './i18n';
import { readFileSync } from 'node:fs';
import { globalBossArenaArt } from './globalBossThemes';

describe('Kraken arena attack presentation', () => {
  it('waits for the official identity and resolves the cycle key before its number', () => {
    expect(globalBossArenaArt(null, null, null, 'kraken.png')).toBe('');
    expect(globalBossArenaArt('ancestral_dragon', 1, null, 'kraken.png')).toBe('kraken.png');
    expect(globalBossArenaArt('infernal_behemoth', undefined, null, 'kraken.png')).toContain('infernal-behemoth.png');
    expect(globalBossArenaArt('infernal_behemoth', 1, null, 'kraken.png')).toContain('infernal-behemoth.png');
    const source = readFileSync(new URL('./components/PirateActionArena.tsx', import.meta.url), 'utf8');
    expect(source).toContain('const showBoss = !emptyTeam && Boolean(props.image)');
  });
  it('names the first boss in the supported core locales', () => {
    expect(translate('pt', 'boss.defaultName')).toBe('Kraken das Profundezas');
    expect(translate('en', 'boss.defaultName')).toBe('Kraken of the Depths');
    expect(translate('es', 'boss.defaultName')).toBe('Kraken de las Profundidades');
    expect(translate('ru', 'boss.defaultName')).toBe('Кракен глубин');
  });
  it('localizes variant controls and empty-team feedback', () => {
    expect(localizeLiteral('en', 'Ataque · Chama')).toBe('Attack · Flame');
    expect(localizeLiteral('tr', 'Dano confirmado')).toBe('Doğrulanmış hasar');
    expect(localizeLiteral('pt', 'Equipe um tripulante para atacar.')).toBe('Equipe um tripulante para atacar.');
  });
  it('shares the official callback and never applies local damage', () => {
    const source = readFileSync(new URL('./components/PirateActionArena.tsx', import.meta.url), 'utf8');
    expect(source).toContain('await onAttack()');
    expect(source).toContain('if (emptyTeam) { props.onEquip(COMBAT_SLOTS[0]); return; }');
    expect(source).toContain('onClick={() => void strike(next)}');
    expect(source).toContain('props.damage - previousDamage.current');
    expect(source).toContain('last && props.bossLastAttackAt <= last');
    expect(source).not.toContain('LockKeyhole');
  });
});