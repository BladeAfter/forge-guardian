import { describe, expect, it } from 'vitest';
import { localizeLiteral } from './literalLocalization';
import { translate } from './i18n';
import { readFileSync } from 'node:fs';

describe('Kraken arena attack presentation', () => {
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
    expect(source).toContain('props.bossLastAttackAt <= last');
    expect(source).not.toContain('LockKeyhole');
  });
});