import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { shipCustomizationLiteral } from './locales/shipCustomization';

describe('real ship upgrade materials', () => {
  const sql = readFileSync('drizzle/migrations/0132_naval_real_material_upgrade_costs.sql', 'utf8');
  it('uses level-specific costs and audited atomic debits', () => {
    expect(sql).toContain('power(growth,p_level-1)');
    expect(sql).toContain('ORDER BY material_id FOR UPDATE');
    expect(sql).toContain('public.realm_material_add(p_user,c.key,-c.value::numeric');
    expect(sql).toContain('NAVAL_MATERIALS_REQUIRED');
    expect(sql).toContain("'materialCosts'");
  });
  it('keeps upgrade functions private', () => {
    expect(sql).toContain('FROM PUBLIC,anon,authenticated');
    expect(sql).toContain('TO service_role');
  });
  it('translates material stock labels in every supported language', () => {
    for (const language of ['pt', 'en', 'es', 'ru', 'tr'] as const) {
      for (const label of ['Madeira', 'Pregos', 'Corda', 'Estoque', 'Necessário']) {
        expect(shipCustomizationLiteral(language, label)).toBeTruthy();
      }
    }
  });
});