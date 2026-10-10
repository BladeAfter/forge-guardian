import { describe, expect, it } from 'vitest';
import { hasTreasureMap, treasureIsRevealed } from './islandTreasure';
import type { RealmExploreRun, RealmExploreNode } from './realm';
import { readFileSync } from 'node:fs';
import { localizeLiteral } from './literalLocalization';
const run = { id: 'run', treasure_map_found_at: null, treasure_map_used_node: null } as RealmExploreRun;
const node = { id: 'treasure', node_type: 'treasure', status: 'available' } as RealmExploreNode;
describe('adventure treasure maps', () => {
  it('requires confirmed discovery and rejects a consumed map', () => {
    expect(hasTreasureMap(null)).toBe(false);
    expect(hasTreasureMap(run)).toBe(false);
    expect(hasTreasureMap({ ...run, treasure_map_found_at: '2026-10-10' })).toBe(true);
    expect(hasTreasureMap({ ...run, treasure_map_found_at: '2026-10-10', treasure_map_used_node: node.id })).toBe(false);
  });
  it('keeps X until the official opened node is known', () => {
    expect(treasureIsRevealed(node, run)).toBe(false);
    expect(treasureIsRevealed(node, { ...run, treasure_map_used_node: node.id })).toBe(true);
    expect(treasureIsRevealed(node, run, node.id)).toBe(true);
    expect(treasureIsRevealed({ ...node, node_type: 'gather' }, run, node.id)).toBe(false);
  });
  it('guards the authoritative apply and automatic sibling path', () => {
    const sql = readFileSync('drizzle/migrations/0120_island_treasure_map_gate.sql', 'utf8');
    expect(sql).toContain('REALM_TREASURE_MAP_REQUIRED');
    expect(sql).toContain('SET treasure_map_used_node = p_node');
    expect(sql).toContain('FOR UPDATE');
    expect(sql).toContain("ELSE ''ignore'' END");
    expect(sql).toContain('FROM PUBLIC,anon,authenticated');
  });
  it('translates new treasure controls in every supported language', () => {
    for (const language of ['en', 'es', 'ru', 'tr'] as const) expect(localizeLiteral(language, 'Mapa de tesouro necessário.')).not.toBe('Mapa de tesouro necessário.');
  });
});
