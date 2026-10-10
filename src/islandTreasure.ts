import type { RealmExploreRun, RealmExploreNode } from './realm';

export const hasTreasureMap = (run?: RealmExploreRun | null) => Boolean(run?.treasure_map_found_at && !run.treasure_map_used_node);
export const treasureIsRevealed = (node: RealmExploreNode, run?: RealmExploreRun | null, openedId?: string | null) => node.node_type === 'treasure' && (run?.treasure_map_used_node === node.id || openedId === node.id);